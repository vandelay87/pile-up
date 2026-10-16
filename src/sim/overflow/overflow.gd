class_name Overflow
extends RefCounted

## Crushes. Every barrier, a connected stretch (8-way) of wall and building cells, has a label,
## and the clear and pile cells within the band of it belong to it. Enemies stalled in a
## barrier's band fill its gauge, which leaks; above the start reading the crush is active, with
## a tier. While it has a tier it sends its front rank tumbling over the barrier at the tier's
## rate, each tumble taking some pressure off.

enum Tier { NONE, TRICKLE, STREAM, SURGE }

const NONE := -1
const _UNREACHED := 255
# How many cells the direct field's chain may run before it reaches the barrier it crosses.
const _MAX_LEAD_IN := 2
const _NEIGHBOURS: Array[Vector2i] = [
	Vector2i(-1, -1),
	Vector2i(0, -1),
	Vector2i(1, -1),
	Vector2i(-1, 0),
	Vector2i(1, 0),
	Vector2i(-1, 1),
	Vector2i(0, 1),
	Vector2i(1, 1),
]

## 1 on each cell in a band, 0 elsewhere: where Enemies tracks progress.
var band_mask := PackedByteArray()

var _settings: Settings
var _map: MapData
var _structures: Structures
var _buildings: Buildings
var _enemies: Enemies
var _routing: Routing
var _rng: RandomNumberGenerator
# Barrier label per cell, or NONE.
var _labels := PackedInt32Array()
# The label of the barrier whose band each cell is in, or NONE, and its steps from that barrier.
var _band_labels := PackedInt32Array()
var _band_steps := PackedByteArray()
var _next_label := 0
var _crushes: Dictionary[int, Crush] = {}
# Every tumble in flight, by enemy id.
var _tumbles: Dictionary[int, Tumble] = {}
# Where each enemy that landed within the fall-back window started its tumble, and the ticks
# left in its window, by enemy id.
var _landed_from: Dictionary[int, Vector2] = {}
var _landed_ticks: Dictionary[int, int] = {}
# The wall cells tumbles crossed this tick, each with its tumble's landing cell, in the order
# they were crossed.
var _knock_offs: Array[KnockOff] = []


## One barrier's gauge, and the stalled enemies filling it this tick.
class Crush:
	extends RefCounted

	var label: int
	var gauge := 0.0
	var active := false
	var tier := Tier.NONE
	var stalled := 0
	## The mean position of its stalled enemies; kept from the last tick that had any.
	var centre := Vector2.ZERO
	## Tumbles banked towards the next launch.
	var credit := 0.0
	## The enemies (by index) in its front rank this tick that aren't attacking (a burning
	## bloater among them), and those that are, gathered before any launch.
	var front_free := PackedInt32Array()
	var front_attacking := PackedInt32Array()
	var _centre_sum := Vector2.ZERO

	func _init(crush_label: int) -> void:
		label = crush_label

	func clear_stalled() -> void:
		stalled = 0
		_centre_sum = Vector2.ZERO
		front_free.clear()
		front_attacking.clear()

	func add_stalled(pos: Vector2) -> void:
		stalled += 1
		_centre_sum += pos
		centre = _centre_sum / stalled


## A wall cell a tumble crossed, and the cell that tumble lands on.
class KnockOff:
	extends RefCounted

	var wall: Vector2i
	var landing: Vector2i

	func _init(wall_cell: Vector2i, landing_cell: Vector2i) -> void:
		wall = wall_cell
		landing = landing_cell


## One enemy's way over a barrier: the cells it crosses, ending on the one it lands on, and the
## next one it is heading for.
class Tumble:
	extends RefCounted

	## The centre of each cell on the way.
	var path := PackedVector2Array()
	## The cells on the way, in order.
	var cells: Array[Vector2i] = []
	## The index in [member path] of the point it is heading for.
	var next := 0
	## The cell it was last in.
	var last_cell := Vector2i.ZERO
	## Where the enemy was when it started.
	var from := Vector2.ZERO

	func add(cell: Vector2i) -> void:
		cells.append(cell)
		path.append(MapData.centre_of(cell))

	## The cell it lands on.
	func landing() -> Vector2i:
		return cells[-1]


func _init(
	run_settings: Settings,
	run_map: MapData,
	run_structures: Structures,
	run_buildings: Buildings,
	run_enemies: Enemies,
	run_routing: Routing,
	rng: RandomNumberGenerator,
) -> void:
	_settings = run_settings
	_map = run_map
	_structures = run_structures
	_buildings = run_buildings
	_enemies = run_enemies
	_routing = run_routing
	_rng = rng
	var size := _map.width * _map.height
	_labels.resize(size)
	_labels.fill(NONE)
	_band_labels.resize(size)
	_band_labels.fill(NONE)
	_band_steps.resize(size)
	band_mask.resize(size)


## Relabels the barriers when a changed cell became, or stopped being, a wall or building. Other
## changes, such as a wall's HP bucket, leave the barriers as they are.
func update(cells: Array[Vector2i]) -> void:
	for cell in cells:
		var index := _map.index_of(cell)
		if (_labels[index] != NONE) != _structures.is_breakable(index):
			relabel()
			return


## Labels every barrier afresh. Each new barrier keeps the label, and so the gauge, of the old
## barrier it overlaps most, ties to the lower old label; an old barrier passes its gauge to one
## new barrier.
func relabel() -> void:
	var old_labels := _labels
	_labels = PackedInt32Array()
	_labels.resize(old_labels.size())
	_labels.fill(NONE)
	var barriers: Array[PackedInt32Array] = []
	var stack := PackedInt32Array()
	for index in _labels.size():
		if _labels[index] != NONE or not _structures.is_breakable(index):
			continue
		var barrier := PackedInt32Array()
		_labels[index] = barriers.size()
		stack.append(index)
		while not stack.is_empty():
			var cell := stack[stack.size() - 1]
			stack.remove_at(stack.size() - 1)
			barrier.append(cell)
			var at := _map.cell_of(cell)
			for offset in _NEIGHBOURS:
				var other := at + offset
				if not _map.in_bounds(other):
					continue
				var other_index := _map.index_of(other)
				if _labels[other_index] == NONE and _structures.is_breakable(other_index):
					_labels[other_index] = barriers.size()
					stack.append(other_index)
		barriers.append(barrier)
	var barrier_labels := _inherit(barriers, old_labels)
	for k in barriers.size():
		for cell in barriers[k]:
			_labels[cell] = barrier_labels[k]
	var kept := {}
	for label in barrier_labels:
		kept[label] = true
	for label: int in _crushes.keys():
		if not kept.has(label):
			_crushes.erase(label)
	_mark_band()


## The crushes with any gauge, in label order.
func crushes() -> Array[Crush]:
	var listed: Array[Crush] = []
	var labels := _crushes.keys()
	labels.sort()
	for label: int in labels:
		listed.append(_crushes[label])
	return listed


## The label of the barrier on [param cell], or NONE.
func barrier_label(cell: Vector2i) -> int:
	return _labels[_map.index_of(cell)]


## The label of the barrier whose band holds [param cell], or NONE.
func band_label(cell: Vector2i) -> int:
	return _band_labels[_map.index_of(cell)]


## True while the enemy with id [param id] is tumbling.
func is_tumbling(id: int) -> bool:
	return _tumbles.has(id)


## The tumble the enemy with id [param id] is on, or null.
func tumble(id: int) -> Tumble:
	return _tumbles.get(id)


## Fills and leaks each gauge from the enemies stalled in its band this tick, launches each
## crush's tumbles, then moves every tumbling enemy, recording each wall cell one crosses.
## Switched off, only tumbles in flight go on.
func step() -> void:
	_knock_offs.clear()
	_count_down_landings()
	if not _settings.overflow_enabled:
		_crushes.clear()
		_move_tumblers()
		return
	_gather()
	var dt := 1.0 / Simulation.TICKS_PER_SECOND
	var fill := _settings.fill_per_stalled
	var leak := _settings.overflow_leak
	var gauge_max := _settings.gauge_max
	for label: int in _crushes.keys():
		var crush: Crush = _crushes[label]
		crush.gauge = clampf(crush.gauge + (crush.stalled * fill - leak) * dt, 0.0, gauge_max)
		if not crush.active and crush.gauge > _settings.crush_start:
			crush.active = true
		elif crush.active and crush.gauge < _settings.crush_end:
			crush.active = false
		crush.tier = _tier_of(crush)
		_launch(crush, dt)
		# Relief may have taken the gauge below its tier.
		crush.tier = _tier_of(crush)
		if crush.gauge <= 0.0 and not crush.active:
			_crushes.erase(label)
	_move_tumblers()


## The wall cells tumbles crossed this tick, each with its landing cell, for the knock-off at
## [constant Simulation.Step.MOVE_UNITS].
func take_knock_offs() -> Array[KnockOff]:
	var taken := _knock_offs
	_knock_offs = []
	return taken


## At [constant Simulation.Step.REMOVE_DEAD], the body of each enemy in [param deaths] that
## died mid-tumble, or within the fall-back window of landing, lands where its tumble started
## instead, back the way it came, so the overflow's dead don't build its barrier out ahead of
## it.
func fall_back(deaths: Deaths) -> void:
	if not _settings.bodies_fall_back:
		return
	for k in deaths.size():
		var id := deaths.ids[k]
		if _tumbles.has(id):
			deaths.bodies[k] = _tumbles[id].from
		elif _landed_from.has(id):
			deaths.bodies[k] = _landed_from[id]


func _count_down_landings() -> void:
	for id: int in _landed_ticks.keys():
		var left := _landed_ticks[id] - 1
		if left <= 0:
			_landed_ticks.erase(id)
			_landed_from.erase(id)
		else:
			_landed_ticks[id] = left


func _tier_of(crush: Crush) -> Tier:
	if not crush.active:
		return Tier.NONE
	if crush.gauge >= _settings.surge_at:
		return Tier.SURGE
	if crush.gauge >= _settings.stream_at:
		return Tier.STREAM
	if crush.gauge >= _settings.trickle_at:
		return Tier.TRICKLE
	return Tier.NONE


func _rate_of(tier: Tier) -> float:
	match tier:
		Tier.TRICKLE:
			return _settings.trickle_rate
		Tier.STREAM:
			return _settings.stream_rate
		Tier.SURGE:
			return _settings.surge_rate
	return 0.0


# Banks the crush's tier rate, launching a tumble for each whole credit: front-rank enemies
# that aren't attacking, picked at random, or its attackers when every front enemy attacks.
# One whose tumble can't be planned is skipped. Credit waiting on a front rank that can't go
# is held at one launch.
func _launch(crush: Crush, dt: float) -> void:
	var rate := _rate_of(crush.tier)
	if rate <= 0.0:
		crush.credit = 0.0
		return
	crush.credit += rate * dt
	var pool := crush.front_free if not crush.front_free.is_empty() else crush.front_attacking
	pool = pool.duplicate()
	while crush.credit >= 1.0:
		var launched := false
		while not launched and not pool.is_empty():
			var k := _rng.randi_range(0, pool.size() - 1)
			launched = _start_tumble(pool[k])
			pool.remove_at(k)
		if not launched:
			crush.credit = 1.0
			return
		crush.credit -= 1.0
		crush.gauge = maxf(crush.gauge - _settings.tumble_relief, 0.0)


# Starts the enemy at [param i] tumbling, unless its tumble can't be planned.
func _start_tumble(i: int) -> bool:
	var planned := _plan_straight(i)
	if planned == null:
		planned = _plan_along_direct(i)
	if planned == null:
		return false
	planned.last_cell = Vector2i(_enemies.positions[i].floor())
	planned.from = _enemies.positions[i]
	_enemies.start_tumble(i)
	_tumbles[_enemies.ids[i]] = planned
	return true


# Straight over the wall or building cell the enemy touches that faces most nearly towards the
# base by the direct field, in one of 8 directions, to the first cell it can land on along that
# line. Null when nothing it touches faces forwards, or the line hits rock or the map's edge.
func _plan_straight(i: int) -> Tumble:
	var pos := _enemies.positions[i]
	var cell := Vector2i(pos.floor())
	var heading := _routing.sample_direction(Routing.Route.DIRECT, pos)
	var reach := _settings.separation_radius + _settings.wall_reach
	var best := Vector2i.ZERO
	var best_facing := 0.0
	for offset in _NEIGHBOURS:
		var touched := cell + offset
		if not _map.in_bounds(touched) or not _structures.is_breakable(_map.index_of(touched)):
			continue
		if _distance_to_square(pos, touched) > reach:
			continue
		var facing := Vector2(offset).normalized().dot(heading)
		if facing > best_facing:
			best_facing = facing
			best = offset
	if best == Vector2i.ZERO:
		return null
	var planned := Tumble.new()
	var at := cell + best
	while _map.in_bounds(at):
		var index := _map.index_of(at)
		if _map.rock[index] == 1:
			return null
		if _structures.is_base(index):
			return _end_beside_base(planned, at)
		planned.add(at)
		if _can_land(index):
			return planned
		at += best
	return null


# Down the direct field's chain from the enemy, over the barrier it meets within a couple of
# cells, to the first cell it can land on. Null when the chain crosses no barrier.
func _plan_along_direct(i: int) -> Tumble:
	var parents := _routing.parents(Routing.Route.DIRECT)
	var cell := _map.index_of(Vector2i(_enemies.positions[i].floor()))
	var planned := Tumble.new()
	var crossed := false
	for _step in parents.size():
		var next := parents[cell]
		if next < 0:
			return null
		var at := _map.cell_of(next)
		if _structures.is_base(next):
			return _end_beside_base(planned, at) if crossed else null
		planned.add(at)
		if _structures.is_breakable(next):
			crossed = true
		elif crossed:
			if _can_land(next):
				return planned
		elif planned.cells.size() > _MAX_LEAD_IN:
			return null
		cell = next
	return null


# Clear or a pile, and not crowded; the caller has ruled out rock and the base.
func _can_land(index: int) -> bool:
	return (
		not _structures.is_breakable(index)
		and _enemies.count_in_cell(index) < _settings.landing_crowd
	)


# Ends [param planned] on the free cell beside the base nearest [param reached], the base cell
# it got to, ties to the lower row then column. Null when the base has no free cell beside it.
# A free cell is clear or a pile, and not crowded.
func _end_beside_base(planned: Tumble, reached: Vector2i) -> Tumble:
	var ring := _map.base.grow(1)
	var best := Vector2i(-1, -1)
	var best_distance := INF
	for y in range(ring.position.y, ring.end.y):
		for x in range(ring.position.x, ring.end.x):
			var beside := Vector2i(x, y)
			if not _map.in_bounds(beside):
				continue
			var index := _map.index_of(beside)
			if _map.rock[index] == 1 or _structures.is_base(index) or not _can_land(index):
				continue
			var distance := Vector2(reached).distance_squared_to(Vector2(beside))
			if distance < best_distance:
				best_distance = distance
				best = beside
	if best_distance == INF:
		return null
	planned.add(best)
	return planned


# Moves each tumbling enemy along its path at the tumble speed, ignoring slow, collision and
# structures. Each wall cell it enters is recorded for the knock-off, and each cell it enters is
# ground by a working grinder there. One that reaches its path's end lands. The dead stay where
# they fell until removal.
func _move_tumblers() -> void:
	var speed := _settings.tumble_speed
	for id: int in _tumbles.keys():
		var i := _enemies.index_of(id)
		if i == Enemies.NONE:
			_tumbles.erase(id)
			continue
		if not _enemies.is_alive(i):
			continue
		var tumbling: Tumble = _tumbles[id]
		var kind := _enemies.kinds[i] as Enemies.Kind
		var budget := _settings.enemy_speed_per_tick_of(kind) * _enemies.pace(i) * speed
		var pos := _enemies.positions[i]
		while budget > 0.0 and tumbling.next < tumbling.path.size():
			var target := tumbling.path[tumbling.next]
			var gap := pos.distance_to(target)
			if gap > budget:
				pos += (target - pos) / gap * budget
				budget = 0.0
			else:
				pos = target
				budget -= gap
				tumbling.next += 1
			var cell := Vector2i(pos.floor())
			if cell != tumbling.last_cell:
				tumbling.last_cell = cell
				if _structures.structure_at(cell) == Structures.Kind.WALL:
					_knock_offs.append(KnockOff.new(cell, tumbling.landing()))
				_buildings.grind_tumble(_enemies, i, cell)
				if not _enemies.is_alive(i):
					break
		_enemies.positions[i] = pos
		if not _enemies.is_alive(i):
			continue
		if tumbling.next == tumbling.path.size():
			_tumbles.erase(id)
			_enemies.land(i)
			_landed_from[id] = tumbling.from
			_landed_ticks[id] = _settings.fall_back_window_ticks


# Counts each band's stalled enemies, and sorts those within an attacker's reach of the band's
# barrier into its front rank. Tumbling enemies count towards nothing, nor do those held up
# attacking a soldier.
func _gather() -> void:
	for crush: Crush in _crushes.values():
		crush.clear_stalled()
	var stall := _settings.stall_progress
	var reach := _settings.separation_radius + _settings.wall_reach
	var positions := _enemies.positions
	var progress := _enemies.progress
	var tumbling := _enemies.tumbling
	var targets := _enemies.structure_targets
	var soldier_targets := _enemies.soldier_targets
	var fuses := _enemies.fuses
	for i in _enemies.count:
		if not _enemies.is_alive(i) or progress[i] >= stall or tumbling[i] == 1:
			continue
		if soldier_targets[i] != Enemies.NONE:
			continue
		var pos := positions[i]
		var label := _band_labels[int(pos.y) * _map.width + int(pos.x)]
		if label == NONE:
			continue
		var crush: Crush = _crushes.get(label)
		if crush == null:
			crush = Crush.new(label)
			_crushes[label] = crush
		crush.add_stalled(pos)
		if not _touches_barrier(pos, label, reach):
			continue
		# A bloater holding with its fuse lit isn't attacking.
		if targets[i] == Enemies.NONE or fuses[i] > 0:
			crush.front_free.append(i)
		else:
			crush.front_attacking.append(i)


func _touches_barrier(pos: Vector2, label: int, reach: float) -> bool:
	var cell := Vector2i(pos.floor())
	for y in range(maxi(cell.y - 1, 0), mini(cell.y + 2, _map.height)):
		for x in range(maxi(cell.x - 1, 0), mini(cell.x + 2, _map.width)):
			if _labels[y * _map.width + x] != label:
				continue
			if _distance_to_square(pos, Vector2i(x, y)) <= reach:
				return true
	return false


static func _distance_to_square(pos: Vector2, cell: Vector2i) -> float:
	var corner := Vector2(cell)
	return pos.distance_to(pos.clamp(corner, corner + Vector2.ONE))


# Each new barrier (by index into [param barriers]) gets the old label it overlaps most. Pairs are
# settled from the largest overlap down, ties to the lower old label then the earlier barrier, so
# each old label goes to one barrier; a barrier left without one gets a fresh label.
func _inherit(barriers: Array[PackedInt32Array], old_labels: PackedInt32Array) -> PackedInt32Array:
	var pairs: Array[Vector3i] = []
	for k in barriers.size():
		var overlaps: Dictionary[int, int] = {}
		for cell in barriers[k]:
			var old := old_labels[cell]
			if old != NONE:
				overlaps[old] = overlaps.get(old, 0) + 1
		for old: int in overlaps:
			pairs.append(Vector3i(overlaps[old], old, k))
	pairs.sort_custom(
		func(a: Vector3i, b: Vector3i) -> bool:
			if a.x != b.x:
				return a.x > b.x
			if a.y != b.y:
				return a.y < b.y
			return a.z < b.z
	)
	var barrier_labels := PackedInt32Array()
	barrier_labels.resize(barriers.size())
	barrier_labels.fill(NONE)
	var taken := {}
	for pair in pairs:
		if barrier_labels[pair.z] == NONE and not taken.has(pair.y):
			barrier_labels[pair.z] = pair.y
			taken[pair.y] = true
	for k in barriers.size():
		if barrier_labels[k] == NONE:
			barrier_labels[k] = _next_label
			_next_label += 1
		_next_label = maxi(_next_label, barrier_labels[k] + 1)
	return barrier_labels


# Spreads out from every barrier a step at a time (8-way, through cells that aren't rock or
# structure) up to the band. A cell reached from two barriers at once goes to the lower label.
func _mark_band() -> void:
	var band := _settings.overflow_band
	_band_labels.fill(NONE)
	_band_steps.fill(_UNREACHED)
	var frontier := PackedInt32Array()
	for index in _labels.size():
		if _labels[index] != NONE:
			_band_steps[index] = 0
			frontier.append(index)
	for steps in range(1, band + 1):
		var next := PackedInt32Array()
		for cell in frontier:
			var label := _labels[cell] if steps == 1 else _band_labels[cell]
			var at := _map.cell_of(cell)
			for offset in _NEIGHBOURS:
				var other := at + offset
				if not _map.in_bounds(other):
					continue
				var other_index := _map.index_of(other)
				var reached := _band_steps[other_index]
				if reached == _UNREACHED:
					if _map.rock[other_index] == 1 or _structures.is_structure(other_index):
						continue
					_band_steps[other_index] = steps
					_band_labels[other_index] = label
					next.append(other_index)
				elif reached == steps and label < _band_labels[other_index]:
					_band_labels[other_index] = label
		frontier = next
	for index in band_mask.size():
		band_mask[index] = 1 if _band_labels[index] != NONE else 0
