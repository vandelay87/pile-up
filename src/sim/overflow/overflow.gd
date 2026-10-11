# PROTOTYPE (overflow, #94): throwaway code to judge how pressure and overflow feel. Not the
# real implementation: it skips tests, is tuned from the debug panel and recomputes crushes on
# a timer rather than on change.
#
# A crush is one connected run (8-way) of walls and buildings. Enemies within the band of it
# that make little progress fill its gauge; the gauge leaks. Above the start reading it is
# active and climbers go over at its tier's rate, each following the direct field across the
# obstacle to the first free, uncrowded cell.
class_name Overflow
extends RefCounted

enum Tier { NONE, TRICKLE, STREAM, SURGE }

const NONE := -1
const RELABEL_TICKS := 30
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

## Label -> Crush, for every crush with any pressure.
var crushes := {}
## Enemy id -> Climb, for every enemy climbing now.
var climbs := {}
var total_climbers := 0

var _settings: Settings
var _map: MapData
var _piles: Piles
var _routing: Routing
var _structures: Structures
var _enemies: Enemies
var _labels := PackedInt32Array()
var _near_labels := PackedInt32Array()
var _near_steps := PackedByteArray()
var _ticks := 0
var _next_label := 0


class Crush:
	extends RefCounted

	var label: int
	var pressure := 0.0
	var active := false
	var tier := Tier.NONE
	var credit := 0.0
	var stalled := 0
	var contact := 0.0
	var centre := Vector2.ZERO
	var climbed := 0
	var front_free: Array[int] = []
	var front_attacking: Array[int] = []
	var _centre_sum := Vector2.ZERO

	func _init(crush_label: int) -> void:
		label = crush_label


class Climb:
	extends RefCounted

	var path := PackedVector2Array()
	var cells := PackedInt32Array()
	var at := 0


func _init(
	run_settings: Settings,
	run_map: MapData,
	run_piles: Piles,
	run_routing: Routing,
	run_structures: Structures,
	run_enemies: Enemies,
) -> void:
	_settings = run_settings
	_map = run_map
	_piles = run_piles
	_routing = run_routing
	_structures = run_structures
	_enemies = run_enemies
	var size := _map.width * _map.height
	_labels.resize(size)
	_labels.fill(NONE)
	_near_labels.resize(size)
	_near_labels.fill(NONE)
	_near_steps.resize(size)


func num(key: String) -> float:
	var raw: float = _settings.value("overflow", key)
	return raw


func is_on(key: String) -> bool:
	var raw: int = _settings.value("overflow", key)
	return raw == 1


func is_enabled() -> bool:
	return is_on("enabled")


func step() -> void:
	if _ticks % RELABEL_TICKS == 0:
		_relabel()
	_ticks += 1
	_move_climbers()
	if not is_enabled():
		crushes.clear()
		return
	_gather()
	var dt := 1.0 / Simulation.TICKS_PER_SECOND
	for label: int in crushes.keys():
		var crush: Crush = crushes[label]
		_fill(crush, dt)
		_overflow(crush, dt)
		if crush.pressure <= 0.0 and not crush.active:
			crushes.erase(label)


func climbing_count() -> int:
	return climbs.size()


func _fill(crush: Crush, dt: float) -> void:
	var fill: float
	if is_on("fill_by_contact"):
		fill = crush.contact * num("fill_per_contact")
	else:
		fill = crush.stalled * num("fill_per_stalled")
	var gauge_max := num("gauge_max")
	crush.pressure = clampf(crush.pressure + (fill - num("leak")) * dt, 0.0, gauge_max)
	if not crush.active and crush.pressure >= num("crush_start"):
		crush.active = true
	elif crush.active and crush.pressure <= num("crush_end"):
		crush.active = false
	crush.tier = _tier_of(crush)


func _tier_of(crush: Crush) -> Tier:
	if not crush.active:
		return Tier.NONE
	if crush.pressure >= num("surge_at"):
		return Tier.SURGE
	if crush.pressure >= num("stream_at"):
		return Tier.STREAM
	if crush.pressure >= num("trickle_at"):
		return Tier.TRICKLE
	return Tier.NONE


func _overflow(crush: Crush, dt: float) -> void:
	var rate := 0.0
	match crush.tier:
		Tier.TRICKLE:
			rate = num("trickle_rate")
		Tier.STREAM:
			rate = num("stream_rate")
		Tier.SURGE:
			rate = num("surge_rate")
	if rate <= 0.0:
		crush.credit = 0.0
		return
	crush.credit += rate * dt
	while crush.credit >= 1.0:
		if not _launch_one(crush):
			crush.credit = minf(crush.credit, 1.0)
			return
		crush.credit -= 1.0
		crush.climbed += 1
		total_climbers += 1
		if is_on("relieves"):
			crush.pressure = maxf(crush.pressure - num("relief"), 0.0)


# Front-rank non-attackers first, then attackers only once every front enemy attacks. Among
# them the one furthest along the direct field goes first.
func _launch_one(crush: Crush) -> bool:
	var pool := crush.front_free
	if pool.is_empty():
		pool = crush.front_attacking
	while not pool.is_empty():
		var best := 0
		var best_value := INF
		for k in pool.size():
			var value := _routing.sample_value(Routing.Route.DIRECT, _enemies.positions[pool[k]])
			if value < best_value:
				best_value = value
				best = k
		var i := pool[best]
		pool.remove_at(best)
		var climb := _plan(i)
		if climb != null:
			_enemies.climbing[i] = 1
			_enemies.structure_targets[i] = Enemies.NONE
			climbs[_enemies.ids[i]] = climb
			return true
	return false


# The direct field's chain from the enemy, over the obstacle, to the first free cell with
# fewer enemies than the landing crowd. Null when the chain doesn't cross an obstacle at once,
# exceeds the climb cap, or dead-ends.
func _plan(i: int) -> Climb:
	var parents := _routing.parents(Routing.Route.DIRECT)
	var cell := _cell_index(_enemies.positions[i])
	var cap := int(num("climb_cap"))
	var crowd := int(num("landing_crowd"))
	var climb := Climb.new()
	var crossed := 0
	var lead_in := 0
	for _step in _map.width * _map.height:
		var next := parents[cell]
		if next < 0:
			return null
		if _structures.is_base(next):
			var beside := _beside_base(cell, next)
			if beside == NONE:
				return null
			_append(climb, beside)
			return climb
		if _structures.is_breakable(next):
			crossed += 1
			if cap > 0 and crossed > cap:
				return null
			_append(climb, next)
		elif crossed == 0:
			lead_in += 1
			if lead_in > _MAX_LEAD_IN:
				return null
			_append(climb, next)
		else:
			_append(climb, next)
			if _enemies.count_in_cell(next) < crowd:
				return climb
		cell = next
	return null


func _append(climb: Climb, cell: int) -> void:
	climb.cells.append(cell)
	climb.path.append(Vector2(_map.cell_of(cell)) + Vector2(0.5, 0.5))


# A free cell touching the base, nearest the cell the climb reached it from.
func _beside_base(from_cell: int, base_cell: int) -> int:
	var base := _map.cell_of(base_cell)
	var from := Vector2(_map.cell_of(from_cell))
	var best := NONE
	var best_distance := INF
	for offset in _NEIGHBOURS:
		var cell := base + offset
		if not _map.in_bounds(cell):
			continue
		var index := _map.index_of(cell)
		if _is_blocked(index):
			continue
		var distance := from.distance_squared_to(Vector2(cell))
		if distance < best_distance:
			best_distance = distance
			best = index
	return best


func _move_climbers() -> void:
	var speed := _settings.enemy_speed_per_tick * num("climb_speed") / 100.0
	var knock := is_on("knock_wall")
	for id: int in climbs.keys():
		var i := _enemies.index_of(id)
		if i == Enemies.NONE or not _enemies.is_alive(i):
			climbs.erase(id)
			continue
		var climb: Climb = climbs[id]
		var pos := _enemies.positions[i]
		var budget := speed * _enemies.pace(i)
		while budget > 0.0 and climb.at < climb.path.size():
			var target := climb.path[climb.at]
			var gap := pos.distance_to(target)
			if gap > budget:
				pos += (target - pos) / gap * budget
				budget = 0.0
			else:
				pos = target
				budget -= gap
				var cell := climb.cells[climb.at]
				if knock and _piles.levels[cell] == Piles.WALL_LEVEL:
					_piles.knock_wall(_map.cell_of(cell))
				climb.at += 1
		_enemies.positions[i] = pos
		if climb.at >= climb.path.size():
			climbs.erase(id)
			_enemies.land_climber(i)


# Stalled enemies near each crush: count them, sum their shoves, find their middle and the
# front rank (touching the obstacle).
func _gather() -> void:
	for crush: Crush in crushes.values():
		crush.stalled = 0
		crush.contact = 0.0
		crush._centre_sum = Vector2.ZERO
		crush.front_free.clear()
		crush.front_attacking.clear()
	var stall := num("stall_progress") / 100.0
	for i in _enemies.count:
		if not _enemies.is_alive(i) or _enemies.climbing[i] == 1:
			continue
		var cell := _cell_index(_enemies.positions[i])
		var label := _near_labels[cell]
		if label == NONE:
			continue
		var crush: Crush = crushes.get(label)
		if crush == null:
			crush = Crush.new(label)
			crushes[label] = crush
		crush.contact += _enemies.contact[i]
		if _enemies.progress[i] >= stall:
			continue
		crush.stalled += 1
		crush._centre_sum += _enemies.positions[i]
		if _near_steps[cell] <= 1:
			if _enemies.structure_targets[i] == Enemies.NONE:
				crush.front_free.append(i)
			else:
				crush.front_attacking.append(i)
	for crush: Crush in crushes.values():
		if crush.stalled > 0:
			crush.centre = crush._centre_sum / crush.stalled


# Labels each connected run of walls and buildings, keeping a crush's gauge when its run
# survives a relabel, then marks the cells within the band of each run.
func _relabel() -> void:
	var size := _labels.size()
	var old_labels := _labels.duplicate()
	_labels.fill(NONE)
	var kept := {}
	var stack := PackedInt32Array()
	for index in size:
		if _labels[index] != NONE or not _structures.is_breakable(index):
			continue
		var label := _inherit(old_labels, index, kept)
		_labels[index] = label
		stack.append(index)
		while not stack.is_empty():
			var cell := stack[stack.size() - 1]
			stack.remove_at(stack.size() - 1)
			var at := _map.cell_of(cell)
			for offset in _NEIGHBOURS:
				var other := at + offset
				if not _map.in_bounds(other):
					continue
				var other_index := _map.index_of(other)
				if _labels[other_index] == NONE and _structures.is_breakable(other_index):
					_labels[other_index] = label
					stack.append(other_index)
	for label: int in crushes.keys():
		if not kept.has(label):
			crushes.erase(label)
	_mark_band()


func _inherit(old_labels: PackedInt32Array, index: int, kept: Dictionary) -> int:
	var old := old_labels[index]
	if old != NONE and not kept.has(old):
		kept[old] = true
		return old
	_next_label += 1
	kept[_next_label] = true
	return _next_label


func _mark_band() -> void:
	var band := floori(num("band"))
	_near_labels.fill(NONE)
	_near_steps.fill(255)
	var frontier := PackedInt32Array()
	for index in _labels.size():
		if _labels[index] != NONE:
			_near_labels[index] = _labels[index]
			_near_steps[index] = 0
			frontier.append(index)
	for steps in range(1, band + 1):
		var next := PackedInt32Array()
		for cell in frontier:
			var at := _map.cell_of(cell)
			for offset in _NEIGHBOURS:
				var other := at + offset
				if not _map.in_bounds(other):
					continue
				var other_index := _map.index_of(other)
				if _near_steps[other_index] != 255 or _is_blocked(other_index):
					continue
				_near_steps[other_index] = steps
				_near_labels[other_index] = _near_labels[cell]
				next.append(other_index)
		frontier = next
	var mask := PackedByteArray()
	mask.resize(_labels.size())
	for index in mask.size():
		mask[index] = 1 if _near_labels[index] != NONE and _labels[index] == NONE else 0
	_enemies.progress_mask = mask


func _is_blocked(index: int) -> bool:
	return _map.rock[index] == 1 or _structures.is_structure(index)


func _cell_index(pos: Vector2) -> int:
	return int(pos.y) * _map.width + int(pos.x)
