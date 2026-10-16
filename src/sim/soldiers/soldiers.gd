## The player's soldiers, in packed arrays swap-removed with an id map as Enemies keeps its
## enemies (ADR 0001), but apart from them: soldiers never count towards a wave.
class_name Soldiers
extends RefCounted

const NONE := -1
## A new soldier's targeting: the index of [constant Enemies.BLOATERS_FIRST] in
## [constant Enemies.TARGETINGS].
const DEFAULT_TARGETING := 0
## How far a standing soldier can be pushed off its spot before it walks all the way back, and
## how far it walks back on its own; further than that it plans a path back.
const SPOT_SLACK := 0.1
const WALK_BACK_REACH := 1.0
const _NO_CELL := Vector2i(-1, -1)
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

var count := 0
var ids := PackedInt32Array()
var positions := PackedVector2Array()
var hp := PackedFloat32Array()
## The cell index each soldier holds when standing.
var spots := PackedInt32Array()
## The field each soldier is walking on, or NONE when standing.
var orders := PackedInt32Array()
## The cell index each walking soldier is walking to, or NONE until its order assigns one.
var slots := PackedInt32Array()
## How far along its path each walking soldier is.
var path_cursors := PackedInt32Array()
## Each soldier's targeting: an index into [constant Enemies.TARGETINGS].
var targetings := PackedByteArray()
var cooldowns := PackedInt32Array()
var targets := PackedInt32Array()
## Enemies each soldier has killed this run.
var kills := PackedInt32Array()
## 1 for a soldier a blast took to 0 HP.
var blast_killed := PackedByteArray()

var _settings: Settings
var _map: MapData
var _piles: Piles
var _solids: Solids
var _paths: UnitPaths
var _ids: Ids
var _index_by_id := {}
# How many soldiers hold each cell as their spot: standing soldiers, and those walking back.
var _spot_counts := PackedInt32Array()
var _added := PackedInt32Array()
# 1 for a standing soldier walking back to its spot, until it gets there.
var _walking_back := PackedByteArray()
# 1 for a soldier that holds its spot: standing, or on a path back to it.
var _holding := PackedByteArray()
# 1 for a soldier on a path back to its own spot.
var _returning := PackedByteArray()
var _walks: Array[PackedInt32Array] = []
# The field generation each soldier's path came from, or NONE before it has one.
var _path_generations := PackedInt32Array()
# Each Move order's slots that no soldier has taken yet, by field, until the field is ready.
var _unassigned: Dictionary[int, PackedInt32Array] = {}
var _pushes := PackedVector2Array()


func _init(
	run_settings: Settings,
	run_map: MapData,
	run_occupancy: Occupancy,
	run_piles: Piles,
	run_structures: Structures,
	run_ids: Ids,
	run_paths: UnitPaths,
) -> void:
	_settings = run_settings
	_map = run_map
	_piles = run_piles
	_solids = Solids.new(_map, run_occupancy, _piles, run_structures, false)
	_ids = run_ids
	_paths = run_paths
	_spot_counts.resize(_map.width * _map.height)


## Adds up to [param wanted] soldiers beside [param area], one by one on the free cell the
## new-soldier rule picks, and returns how many found a cell.
func add_beside(area: Rect2i, wanted: int) -> int:
	for n in wanted:
		var cell := _free_cell_beside(area)
		if cell == _NO_CELL:
			return n
		add(cell)
	return wanted


## A new soldier standing on [param cell], which becomes its spot.
func add(cell: Vector2i) -> int:
	if count == ids.size():
		_grow()
	var id := _ids.next()
	ids[count] = id
	positions[count] = MapData.centre_of(cell)
	hp[count] = _settings.soldier_hp
	orders[count] = NONE
	slots[count] = NONE
	path_cursors[count] = 0
	targetings[count] = DEFAULT_TARGETING
	cooldowns[count] = 0
	targets[count] = Enemies.NONE
	kills[count] = 0
	blast_killed[count] = 0
	_walking_back[count] = 0
	_holding[count] = 0
	_returning[count] = 0
	_walks[count] = PackedInt32Array()
	_path_generations[count] = NONE
	_hold(count, _map.index_of(cell))
	_index_by_id[id] = count
	_added.append(id)
	count += 1
	return id


func index_of(id: int) -> int:
	return _index_by_id.get(id, NONE)


func spot(index: int) -> Vector2i:
	return _map.cell_of(spots[index])


## The cells the soldier at [param index] still has to walk through, the next first; empty when
## it isn't walking or its path isn't planned yet.
func path_left(index: int) -> PackedInt32Array:
	return _walks[index].slice(path_cursors[index])


## The targeting of the soldier at [param index]: one of [constant Enemies.TARGETINGS].
func targeting(index: int) -> StringName:
	return Enemies.TARGETINGS[targetings[index]]


## Sets [param mode] on each soldier in [param soldier_ids]; ids of soldiers no longer living
## are skipped, since one can die between the order and the drain. Returns an error, or "".
func set_targeting(soldier_ids: PackedInt32Array, mode: StringName) -> String:
	var mode_index := Enemies.TARGETINGS.find(mode)
	if mode_index == NONE:
		return Buildings.BAD_TARGETING
	for id in soldier_ids:
		var index := index_of(id)
		if index != NONE:
			targetings[index] = mode_index
	return ""


## The level of the cell under the soldier at [param index]: 0 on the ground, 1–4 on a pile,
## 5 on a wall. Nothing is stored; it follows the cell.
func elevation(index: int) -> int:
	return _piles.levels[_map.index_of(Vector2i(positions[index]))]


## Gives every living soldier in [param soldier_ids] one shared Move order to [param target]
## in [param formation]: an anchor, the formation's slots, a field and, once the field is ready,
## each soldier's slot. A soldier that can't reach the anchor stops. Returns an error, or "".
func move(soldier_ids: PackedInt32Array, target: Vector2, formation: StringName) -> String:
	if formation not in Formations.ALL:
		return Formations.BAD_FORMATION
	var indices := _living(soldier_ids)
	if indices.is_empty():
		return ""
	var reached := {}
	var mean := Vector2.ZERO
	for i in indices:
		mean += positions[i]
		var region := _paths.regions[_cell_index(i)]
		if region != NONE:
			reached[region] = true
	mean /= indices.size()
	var anchor := NONE if reached.is_empty() else _paths.nearest_standable(target, reached)
	var going := PackedInt32Array()
	for i in indices:
		_end_order(i)
		if anchor == NONE or _paths.regions[_cell_index(i)] != _paths.regions[anchor]:
			_stand_here(i)
		else:
			_unhold(i)
			going.append(i)
	if going.is_empty():
		return ""
	var formation_slots := (
		_paths.nearest_free(anchor, going.size(), _spot_counts)
		if formation == Formations.CLUSTER
		else Formations.line(_paths, _map, anchor, mean, target, going.size(), _spot_counts)
	)
	var field := _paths.plan(anchor)
	var needed := formation_slots.duplicate()
	for i in going:
		_set_order(i, field, NONE)
		needed.append(_cell_index(i))
	_unassigned[field] = formation_slots
	_paths.need(field, needed)
	return ""


## Ends the orders of every living soldier in [param soldier_ids]: each stands where it is, and
## that becomes its spot.
func stop(soldier_ids: PackedInt32Array) -> void:
	for i in _living(soldier_ids):
		_end_order(i)
		_unhold(i)
		_stand_here(i)


## Sends the soldier [param id] on a one-soldier Cluster order on a rally field: to the free cell
## nearest the rally point that no other soldier walking there has taken.
func send_to_rally(id: int, field: int) -> void:
	var i := index_of(id)
	var held := _spot_counts.duplicate()
	for j in count:
		if orders[j] == field and slots[j] != NONE:
			held[slots[j]] += 1
	_unhold(i)
	var slot := _paths.nearest_free(_paths.anchor(field), 1, held)
	if slot.is_empty():
		_stand_here(i)
		return
	_set_order(i, field, slot[0])
	_paths.need(field, PackedInt32Array([_cell_index(i), slot[0]]))


## At [constant Simulation.Step.DRAIN_COMMANDS], as a building is placed: every soldier standing
## in [param area], or holding a spot there, moves to the nearest free cell by the new-soldier
## rule. A standing soldier's spot moves with it; a walking one keeps its order and plans again.
func push_out_of(area: Rect2i) -> void:
	for i in count:
		var inside := area.has_point(Vector2i(positions[i].floor()))
		var spot_inside := _holding[i] == 1 and area.has_point(spot(i))
		if not inside and not spot_inside:
			continue
		var walking := orders[i] != NONE and _returning[i] == 0
		if _returning[i] == 1:
			_end_order(i)
		_unhold(i)
		var cell := _free_cell_beside(area)
		if cell == _NO_CELL:
			continue
		if inside:
			positions[i] = MapData.centre_of(cell)
		if walking:
			_path_generations[i] = NONE
			_paths.restart(orders[i])
		else:
			_hold(i, _map.index_of(cell))


## At [constant Simulation.Step.MOVE_UNITS], before [method UnitPaths.step]: each field restarted
## since the last tick asks again for its soldiers' cells and slots.
func need_restarted() -> void:
	for field in _paths.take_restarted():
		var needed := PackedInt32Array()
		for i in count:
			if orders[i] == field:
				needed.append(_cell_index(i))
				if slots[i] != NONE:
					needed.append(slots[i])
		var unassigned: PackedInt32Array = _unassigned.get(field, PackedInt32Array())
		needed.append_array(unassigned)
		_paths.need(field, needed)


## At [constant Simulation.Step.MOVE_UNITS], after [method UnitPaths.step]: gives the soldiers of
## ready fields their slots and paths, walks soldiers along their paths or back to their spots,
## spaces them out, then holds every soldier off what is solid to it.
func step() -> void:
	_assign_slots()
	_plan_paths()
	_walk()
	_space_out()
	var radius := _settings.separation_radius
	for i in count:
		positions[i] = _solids.resolve(positions[i], radius)


## Not rock, the base or a building, and on the map. Walls and piles are open ground.
func can_stand_on(cell: Vector2i) -> bool:
	return not _solids.is_solid(cell)


## The soldiers added since the last call, in id order.
func take_added() -> PackedInt32Array:
	var added := _added
	_added = PackedInt32Array()
	return added


func _assign_slots() -> void:
	for field: int in _unassigned.keys():
		if not _paths.has_field(field):
			_unassigned.erase(field)
			continue
		if not _paths.is_ready(field):
			continue
		var free: PackedInt32Array = _unassigned[field]
		_unassigned.erase(field)
		var waiting: Array[int] = []
		for i in count:
			if orders[i] == field and slots[i] == NONE:
				waiting.append(i)
		waiting.sort_custom(func(a: int, b: int) -> bool: return _closer_to_anchor(field, a, b))
		for i in waiting:
			var best := NONE
			var best_distance := INF
			for k in free.size():
				var distance := positions[i].distance_squared_to(_centre(free[k]))
				if distance < best_distance or (distance == best_distance and free[k] < free[best]):
					best = k
					best_distance = distance
			if best == NONE:
				_end_order(i)
				_stand_here(i)
				continue
			slots[i] = free[best]
			free.remove_at(best)


# Nearest the anchor first by field value, ties to the lowest id.
func _closer_to_anchor(field: int, a: int, b: int) -> bool:
	var value_a := _paths.value(field, _cell_index(a))
	var value_b := _paths.value(field, _cell_index(b))
	return value_a < value_b or (value_a == value_b and ids[a] < ids[b])


# Each walking soldier with a slot whose field is ready and newer than its path takes its path.
# A slot it can no longer stand on moves to the nearest cell it can; a soldier its field can't
# take to its slot stops.
func _plan_paths() -> void:
	for i in count:
		var field := orders[i]
		if field == NONE or slots[i] == NONE or not _paths.is_ready(field):
			continue
		if _path_generations[i] == _paths.generation(field):
			continue
		if not can_stand_on(_map.cell_of(slots[i])):
			slots[i] = _free_slot_near(i)
			if slots[i] != NONE:
				_paths.need(field, PackedInt32Array([slots[i]]))
				continue
		var from := _cell_index(i)
		var walk := PackedInt32Array()
		if slots[i] != NONE:
			walk = _paths.path(field, from, slots[i])
		if slots[i] == NONE or (walk.is_empty() and from != slots[i]):
			_end_order(i)
			_unhold(i)
			_stand_here(i)
			continue
		_walks[i] = walk
		path_cursors[i] = 0
		_path_generations[i] = _paths.generation(field)


# The nearest cell to the soldier's slot, by straight distance, that it can stand on and reach
# from its field's anchor, that no standing soldier holds and no other soldier is walking to.
func _free_slot_near(i: int) -> int:
	var field := orders[i]
	var held := _spot_counts.duplicate()
	for j in count:
		if j != i and slots[j] != NONE:
			held[slots[j]] += 1
	var region := {_paths.regions[_paths.anchor(field)]: true}
	return _paths.nearest_standable(_centre(slots[i]), region, held)


# Walking soldiers step along their paths at their speed times the slow of the cell under them;
# a soldier on its slot stands there. A standing soldier pushed off its spot walks back, or plans
# a path back when it is more than a cell away.
func _walk() -> void:
	var step_length := _settings.soldier_speed / Simulation.TICKS_PER_SECOND
	for i in count:
		if orders[i] == NONE:
			_stand(i, step_length)
			continue
		if _path_generations[i] == NONE:
			continue
		var left := step_length * _paths.speed_factor(_cell_index(i))
		var walk := _walks[i]
		while left > 0.0:
			var goal := _centre(
				walk[path_cursors[i]] if path_cursors[i] < walk.size() else slots[i]
			)
			var distance := positions[i].distance_to(goal)
			if distance > left:
				positions[i] = positions[i].move_toward(goal, left)
				break
			positions[i] = goal
			left -= distance
			if path_cursors[i] < walk.size():
				path_cursors[i] += 1
			else:
				_arrive(i)
				break


func _stand(i: int, step_length: float) -> void:
	var home := _centre(spots[i])
	var off := positions[i].distance_to(home)
	if off > WALK_BACK_REACH:
		_walking_back[i] = 0
		if _paths.regions[_cell_index(i)] == _paths.regions[spots[i]]:
			_return(i)
		else:
			# Its spot is out of reach: where it is becomes its spot.
			_unhold(i)
			_stand_here(i)
		return
	if off > SPOT_SLACK:
		_walking_back[i] = 1
	if _walking_back[i] == 1:
		positions[i] = positions[i].move_toward(home, step_length)
		if positions[i] == home:
			_walking_back[i] = 0


# A standing soldier more than a cell off its spot plans a path back as for a Move, holding it.
func _return(i: int) -> void:
	var field := _paths.plan(spots[i])
	_set_order(i, field, spots[i])
	_returning[i] = 1
	_paths.need(field, PackedInt32Array([_cell_index(i), spots[i]]))


func _arrive(i: int) -> void:
	var slot := slots[i]
	var returning := _returning[i] == 1
	_end_order(i)
	if not returning:
		_hold(i, slot)


# Pairs of soldiers closer than the personal-space radius push apart softly, every pair at once
# and each soldier's pushes averaged. A walking soldier takes the whole push of a pair with a
# standing one, and two standing soldiers don't push each other. A push is held to half a
# walking step, so a soldier always gets past those standing in its way.
func _space_out() -> void:
	var radius := _settings.personal_space_radius
	var push := _settings.personal_space_push
	if radius <= 0.0 or push <= 0.0:
		return
	var most := 0.5 * _settings.soldier_speed / Simulation.TICKS_PER_SECOND
	_pushes.resize(count)
	_pushes.fill(Vector2.ZERO)
	var pushed := PackedInt32Array()
	pushed.resize(count)
	for i in count:
		var i_walking := orders[i] != NONE
		for j in range(i + 1, count):
			var j_walking := orders[j] != NONE
			if not i_walking and not j_walking:
				continue
			var away := positions[i] - positions[j]
			var distance := away.length()
			if distance >= radius:
				continue
			var direction := away / distance if distance > 1e-6 else Vector2.LEFT
			var shove := direction * (1.0 - distance / radius) * push
			if i_walking:
				_pushes[i] += shove
				pushed[i] += 1
			if j_walking:
				_pushes[j] -= shove
				pushed[j] += 1
	for i in count:
		if pushed[i] > 0:
			positions[i] += (_pushes[i] / pushed[i]).limit_length(most)


func _set_order(i: int, field: int, slot: int) -> void:
	orders[i] = field
	slots[i] = slot
	path_cursors[i] = 0
	_walks[i] = PackedInt32Array()
	_path_generations[i] = NONE
	_walking_back[i] = 0
	_paths.join(field)


# Ends a soldier's order, if it has one, leaving its field. Its spot is left as it was.
func _end_order(i: int) -> void:
	if orders[i] == NONE:
		return
	var field := orders[i]
	orders[i] = NONE
	slots[i] = NONE
	path_cursors[i] = 0
	_walks[i] = PackedInt32Array()
	_path_generations[i] = NONE
	_returning[i] = 0
	_paths.leave(field)


# The soldier holds the cell under it as its spot, or the nearest free cell if it can't stand
# there.
func _stand_here(i: int) -> void:
	var cell := Vector2i(positions[i].floor())
	if not can_stand_on(cell):
		cell = _free_cell_beside(Rect2i(cell, Vector2i.ONE))
		if cell == _NO_CELL:
			return
		positions[i] = MapData.centre_of(cell)
	_hold(i, _map.index_of(cell))


func _hold(i: int, cell: int) -> void:
	spots[i] = cell
	_holding[i] = 1
	_spot_counts[cell] += 1


func _unhold(i: int) -> void:
	if _holding[i] == 1:
		_holding[i] = 0
		_spot_counts[spots[i]] -= 1


# The indices of the living soldiers among [param soldier_ids], each once, in the order given.
func _living(soldier_ids: PackedInt32Array) -> PackedInt32Array:
	var indices := PackedInt32Array()
	for id in soldier_ids:
		var i := index_of(id)
		if i != NONE and i not in indices:
			indices.append(i)
	return indices


func _cell_index(i: int) -> int:
	var cell := Vector2i(positions[i].floor()).clamp(
		Vector2i.ZERO, Vector2i(_map.width - 1, _map.height - 1)
	)
	return _map.index_of(cell)


func _centre(cell: int) -> Vector2:
	return MapData.centre_of(_map.cell_of(cell))


# The new-soldier rule: the free cell in the ring around [param area] whose centre is nearest
# the base's centre (ties to the lowest cell index), else the same in each ring further out,
# reached breadth-first through cells a soldier can stand on. _NO_CELL when no free cell can be
# reached.
func _free_cell_beside(area: Rect2i) -> Vector2i:
	var base_centre := Vector2(_map.base.position) + Vector2(_map.base.size) / 2.0
	var seen := PackedByteArray()
	seen.resize(_map.width * _map.height)
	var ring: Array[Vector2i] = []
	for y in range(area.position.y - 1, area.end.y + 1):
		for x in range(area.position.x - 1, area.end.x + 1):
			var cell := Vector2i(x, y)
			if area.has_point(cell) or not can_stand_on(cell):
				continue
			seen[_map.index_of(cell)] = 1
			ring.append(cell)
	while not ring.is_empty():
		var best := _NO_CELL
		var best_distance := INF
		for cell in ring:
			if _spot_counts[_map.index_of(cell)] > 0:
				continue
			var distance := MapData.centre_of(cell).distance_squared_to(base_centre)
			if distance < best_distance or (distance == best_distance and _lower_index(cell, best)):
				best = cell
				best_distance = distance
		if best != _NO_CELL:
			return best
		ring = _next_ring(ring, seen)
	return _NO_CELL


# The cells a soldier can step to from [param ring] that haven't been seen: 8-way, without
# cutting a corner past a cell it can't stand on.
func _next_ring(ring: Array[Vector2i], seen: PackedByteArray) -> Array[Vector2i]:
	var next: Array[Vector2i] = []
	for cell in ring:
		for step in _NEIGHBOURS:
			var neighbour := cell + step
			if not can_stand_on(neighbour) or seen[_map.index_of(neighbour)] == 1:
				continue
			var diagonal := step.x != 0 and step.y != 0
			if (
				diagonal
				and not (
					can_stand_on(cell + Vector2i(step.x, 0))
					and can_stand_on(cell + Vector2i(0, step.y))
				)
			):
				continue
			seen[_map.index_of(neighbour)] = 1
			next.append(neighbour)
	return next


# Whether [param cell] wins a tie with [param other]: it has the lower cell index, or there is
# no other yet.
func _lower_index(cell: Vector2i, other: Vector2i) -> bool:
	return other == _NO_CELL or _map.index_of(cell) < _map.index_of(other)


func _grow() -> void:
	var capacity := maxi(16, ids.size() * 2)
	ids.resize(capacity)
	positions.resize(capacity)
	hp.resize(capacity)
	spots.resize(capacity)
	orders.resize(capacity)
	path_cursors.resize(capacity)
	targetings.resize(capacity)
	cooldowns.resize(capacity)
	targets.resize(capacity)
	kills.resize(capacity)
	blast_killed.resize(capacity)
	_walking_back.resize(capacity)
	slots.resize(capacity)
	_holding.resize(capacity)
	_returning.resize(capacity)
	_walks.resize(capacity)
	_path_generations.resize(capacity)
