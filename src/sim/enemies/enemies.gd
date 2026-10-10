class_name Enemies
extends RefCounted

const NONE := -1
const _COLLISION_PASSES := 2
const _HASH_MARGIN := 2
const _PROGRESS := 0.02
const _ROLL_STEPS := 40
const _FACES: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]

var count := 0
var ids := PackedInt32Array()
var positions := PackedVector2Array()
var hp := PackedFloat32Array()
var heading_offsets := PackedFloat32Array()
var structure_targets := PackedInt32Array()
var routes := PackedByteArray()
var last_rolled_cells := PackedInt32Array()
var pace_rolls := PackedFloat32Array()
var wander_phases := PackedFloat32Array()

var _settings: Settings
var _map: MapData
var _occupancy: Occupancy
var _piles: Piles
var _routing: Routing
var _structures: Structures
var _rng: RandomNumberGenerator
var _swarm_rng: RandomNumberGenerator
var _next_id := 0
var _index_by_id := {}
var _bucket_starts := PackedInt32Array()
var _bucket_enemies := PackedInt32Array()
var _moved := PackedVector2Array()
var _best_values := PackedFloat64Array()
var _stuck_ticks := PackedInt32Array()
var _ticks := 0


func _init(
	run_settings: Settings,
	run_map: MapData,
	run_occupancy: Occupancy,
	run_piles: Piles,
	run_routing: Routing,
	run_structures: Structures,
	rng: RandomNumberGenerator,
	swarm_rng: RandomNumberGenerator = null,
) -> void:
	_settings = run_settings
	_map = run_map
	_occupancy = run_occupancy
	_piles = run_piles
	_routing = run_routing
	_structures = run_structures
	_rng = rng
	# The swarm spread rolls draw from their own stream so the heading offsets and route
	# rolls stay as they were without it.
	_swarm_rng = swarm_rng
	if _swarm_rng == null:
		_swarm_rng = RandomNumberGenerator.new()
		_swarm_rng.seed = hash([rng.seed, "swarm"])
	_bucket_starts.resize(_map.width * _map.height + 1)


func spawn(pos: Vector2, start_hp: float) -> int:
	if count == ids.size():
		_grow()
	var id := _next_id
	_next_id += 1
	ids[count] = id
	positions[count] = pos
	hp[count] = start_hp
	heading_offsets[count] = _rng.randf_range(-1.0, 1.0) * _settings.heading_offset_radians
	structure_targets[count] = NONE
	routes[count] = Routing.Route.SENSIBLE
	last_rolled_cells[count] = NONE
	pace_rolls[count] = _swarm_rng.randf_range(-1.0, 1.0)
	wander_phases[count] = _swarm_rng.randf_range(0.0, TAU)
	_best_values[count] = INF
	_stuck_ticks[count] = 0
	_index_by_id[id] = count
	count += 1
	return id


# The enemy's speed multiplier: its roll at spawn scaled by the current speed variety.
func pace(index: int) -> float:
	return 1.0 + pace_rolls[index] * _settings.speed_variety


func index_of(id: int) -> int:
	return _index_by_id.get(id, NONE)


func damage(id: int, amount: float) -> void:
	var index := index_of(id)
	if index != NONE:
		hp[index] -= amount


func nearest_to_base_in_range(pos: Vector2, reach: float) -> int:
	var low := Vector2i((pos - Vector2(reach, reach)).floor()) - Vector2i.ONE * _HASH_MARGIN
	var high := Vector2i((pos + Vector2(reach, reach)).floor()) + Vector2i.ONE * _HASH_MARGIN
	var reach_squared := reach * reach
	var best_id := NONE
	var best_value := INF
	for y in range(maxi(low.y, 0), mini(high.y + 1, _map.height)):
		var row := y * _map.width
		for x in range(maxi(low.x, 0), mini(high.x + 1, _map.width)):
			for slot in range(_bucket_starts[row + x], _bucket_starts[row + x + 1]):
				var i := _bucket_enemies[slot]
				if hp[i] <= 0.0:
					continue
				if positions[i].distance_squared_to(pos) > reach_squared:
					continue
				var field_value := _routing.sample_value(Routing.Route.SENSIBLE, positions[i])
				var ties_lower := field_value == best_value and ids[i] < best_id
				if best_id == NONE or field_value < best_value or ties_lower:
					best_value = field_value
					best_id = ids[i]
	return best_id


func rebuild_spatial_hash() -> void:
	_bucket_starts.fill(0)
	_bucket_enemies.resize(count)
	for i in count:
		_bucket_starts[_cell_index(positions[i]) + 1] += 1
	for cell in range(1, _bucket_starts.size()):
		_bucket_starts[cell] += _bucket_starts[cell - 1]
	var next_slot := _bucket_starts.duplicate()
	for i in count:
		var cell := _cell_index(positions[i])
		_bucket_enemies[next_slot[cell]] = i
		next_slot[cell] += 1


func move() -> void:
	if count == 0:
		return
	var step := _settings.enemy_speed_per_tick
	var steps := PackedFloat64Array([step])
	for level in range(1, Piles.WALL_LEVEL):
		steps.append(step * (1.0 - _settings.pile_slow(level)))
	steps.append(step)
	var levels := _piles.levels
	var radius := _settings.separation_radius
	var push := _settings.separation_push
	var cap := _settings.neighbour_cap
	var reach := radius + _settings.wall_reach
	var jam_ticks := _settings.jam_ticks
	var sensible_parents := _routing.parents(Routing.Route.SENSIBLE)
	var direct_parents := _routing.parents(Routing.Route.DIRECT)
	var variety := _settings.speed_variety
	var wander := _settings.wander_radians
	var wander_angle := TAU * _ticks / _settings.wander_period_ticks
	var space_radius := _settings.personal_space_radius
	var space_push := _settings.personal_space_push
	var spreads := space_radius > 2.0 * radius and space_push > 0.0
	_ticks += 1
	for i in count:
		structure_targets[i] = _structure_target(i, reach, jam_ticks)
	_moved.resize(count)
	for i in count:
		var pos := positions[i]
		var separation := _separation(i, radius, push, cap).limit_length(radius)
		if structure_targets[i] != NONE:
			_moved[i] = pos + separation
			continue
		if spreads:
			separation += _personal_space(i, space_radius, space_push).limit_length(step)
		var turn := heading_offsets[i]
		if wander > 0.0:
			turn += wander * sin(wander_phases[i] + wander_angle)
		var heading := _routing.sample_direction(routes[i], pos).rotated(turn)
		var pace_step := steps[levels[_cell_index(pos)]] * (1.0 + pace_rolls[i] * variety)
		_moved[i] = pos + heading * pace_step + separation
	for i in count:
		var pos := _moved[i]
		for _pass in _COLLISION_PASSES:
			var resolved := _resolve_collision(pos, radius)
			if resolved == pos:
				break
			pos = resolved
		positions[i] = pos
		if routes[i] == Routing.Route.SENSIBLE:
			_roll_route(i, _cell_index(pos), sensible_parents, direct_parents)
		elif _is_past_obstacle(i, pos):
			routes[i] = Routing.Route.SENSIBLE
	var damage_per_tick := _settings.wall_damage_per_tick
	for i in count:
		if structure_targets[i] != NONE:
			_structures.damage(_cell_of(structure_targets[i]), damage_per_tick)


func _roll_route(
	i: int, cell: int, sensible_parents: PackedInt32Array, direct_parents: PackedInt32Array
) -> void:
	var next := direct_parents[cell]
	if next < 0 or next == sensible_parents[cell]:
		return
	var obstacle := _first_pile_on_chain(next, direct_parents)
	if obstacle == NONE or obstacle == last_rolled_cells[i]:
		return
	last_rolled_cells[i] = obstacle
	var is_wall := _is_wall(obstacle)
	var chance := _settings.wall_roll_chance if is_wall else _settings.pile_roll_chance
	if chance > 0.0 and _rng.randf() <= chance:
		routes[i] = Routing.Route.DIRECT


func _is_past_obstacle(i: int, pos: Vector2) -> bool:
	var obstacle_value := _routing.value(Routing.Route.DIRECT, _cell_of(last_rolled_cells[i]))
	return _routing.sample_value(Routing.Route.DIRECT, pos) < obstacle_value


func _first_pile_on_chain(cell: int, chain_parents: PackedInt32Array) -> int:
	var levels := _piles.levels
	for _step in _ROLL_STEPS:
		if levels[cell] > 0:
			return cell
		cell = chain_parents[cell]
		if cell < 0:
			return NONE
	return NONE


# The structure cell the enemy attacks this tick, or NONE: the one it is already finishing
# if still in reach, else the nearest pressed structure once it is in the way (the route
# crosses it within 2 steps) or the enemy is jammed against it.
func _structure_target(i: int, reach: float, jam_ticks: int) -> int:
	var pos := positions[i]
	var target := structure_targets[i]
	if (
		target != NONE
		and _structures.is_structure(target)
		and _distance_to_cell(pos, target) <= reach
	):
		return target
	var nearest := NONE
	if _structures.is_nearby(_cell_index(pos)):
		nearest = _nearest_pressed_structure(pos, reach)
	if nearest == NONE:
		_best_values[i] = INF
		_stuck_ticks[i] = 0
		return NONE
	var route := routes[i] as Routing.Route
	var field_value := _routing.sample_value(route, pos)
	if field_value < _best_values[i] - _PROGRESS:
		_best_values[i] = field_value
		_stuck_ticks[i] = 0
	else:
		_stuck_ticks[i] += 1
	if _stuck_ticks[i] >= jam_ticks or _route_crosses_structure(route, pos):
		_stuck_ticks[i] = 0
		return nearest
	return NONE


func _route_crosses_structure(route: Routing.Route, pos: Vector2) -> bool:
	var next := _routing.parent(route, Vector2i(pos.floor()))
	if next == Routing.NO_PARENT:
		return false
	if _structures.is_structure(_index(next)):
		return true
	var after := _routing.parent(route, next)
	return after != Routing.NO_PARENT and _structures.is_structure(_index(after))


func _nearest_pressed_structure(pos: Vector2, reach: float) -> int:
	var cell := Vector2i(pos.floor())
	var best := NONE
	var best_distance := reach
	for y in range(maxi(cell.y - 1, 0), mini(cell.y + 2, _map.height)):
		for x in range(maxi(cell.x - 1, 0), mini(cell.x + 2, _map.width)):
			var index := y * _map.width + x
			if not _structures.is_structure(index):
				continue
			var distance := _distance_to_cell(pos, index)
			if distance <= best_distance:
				best_distance = distance
				best = index
	return best


func _is_wall(index: int) -> bool:
	return _piles.levels[index] == Piles.WALL_LEVEL


func _distance_to_cell(pos: Vector2, index: int) -> float:
	var corner := Vector2(_cell_of(index))
	return pos.distance_to(pos.clamp(corner, corner + Vector2.ONE))


func _separation(i: int, radius: float, push: float, cap: int) -> Vector2:
	var spacing := 2.0 * radius
	var spacing_squared := spacing * spacing
	var width := _map.width
	var pos := positions[i]
	var cell := Vector2i(pos.floor())
	var holding := structure_targets[i] != NONE
	var checked := 0
	var total := Vector2.ZERO
	for y in range(maxi(cell.y - 1, 0), mini(cell.y + 2, _map.height)):
		for x in range(maxi(cell.x - 1, 0), mini(cell.x + 2, width)):
			var bucket := y * width + x
			for slot in range(_bucket_starts[bucket], _bucket_starts[bucket + 1]):
				var j := _bucket_enemies[slot]
				if j == i:
					continue
				if cap > 0 and checked == cap:
					return total
				checked += 1
				var away := pos - positions[j]
				if away.length_squared() >= spacing_squared:
					continue
				var share := 1.0
				if structure_targets[j] != NONE and not holding:
					share = 2.0
				elif holding and structure_targets[j] == NONE:
					continue
				var distance := away.length()
				var direction := away / distance if distance > 1e-6 else _tie_break(i, j)
				total += direction * (spacing - distance) * push * share
	return total


# A soft push that keeps neighbours a personal-space radius apart, wider than the
# collision spacing, so a column fans out across a corridor rather than single-filing.
func _personal_space(i: int, space_radius: float, space_push: float) -> Vector2:
	var reach := ceili(space_radius)
	var radius_squared := space_radius * space_radius
	var width := _map.width
	var pos := positions[i]
	var cell := Vector2i(pos.floor())
	var total := Vector2.ZERO
	for y in range(maxi(cell.y - reach, 0), mini(cell.y + reach + 1, _map.height)):
		for x in range(maxi(cell.x - reach, 0), mini(cell.x + reach + 1, width)):
			var bucket := y * width + x
			for slot in range(_bucket_starts[bucket], _bucket_starts[bucket + 1]):
				var j := _bucket_enemies[slot]
				if j == i or structure_targets[j] != NONE:
					continue
				var away := pos - positions[j]
				if away.length_squared() >= radius_squared:
					continue
				var distance := away.length()
				var direction := away / distance if distance > 1e-6 else _tie_break(i, j)
				total += direction * (1.0 - distance / space_radius) * space_push
	return total


func _resolve_collision(pos: Vector2, radius: float) -> Vector2:
	var margin := Vector2(radius, radius)
	pos = pos.clamp(margin, Vector2(_map.width, _map.height) - margin)
	var low := Vector2i((pos - margin).floor())
	var high := Vector2i((pos + margin).floor())
	for y in range(low.y, high.y + 1):
		for x in range(low.x, high.x + 1):
			var blocked := Vector2i(x, y)
			if not _is_impassable(blocked):
				continue
			var closest := pos.clamp(Vector2(blocked), Vector2(blocked + Vector2i.ONE))
			var away := pos - closest
			var distance := away.length()
			if distance >= radius:
				continue
			if distance > 1e-6:
				pos = closest + away / distance * radius
			else:
				pos = _leave_through_nearest_open_face(pos, blocked, radius)
	return pos


func _leave_through_nearest_open_face(pos: Vector2, cell: Vector2i, radius: float) -> Vector2:
	var inside := pos - Vector2(cell)
	var face_distances: Array[float] = [inside.x, 1.0 - inside.x, inside.y, 1.0 - inside.y]
	var best_face := Vector2i.ZERO
	var best_distance := INF
	for k in _FACES.size():
		if not _is_impassable(cell + _FACES[k]) and face_distances[k] < best_distance:
			best_distance = face_distances[k]
			best_face = _FACES[k]
	if best_face == Vector2i.ZERO:
		return pos
	return pos + Vector2(best_face) * (best_distance + radius)


func _is_impassable(cell: Vector2i) -> bool:
	if not _map.in_bounds(cell):
		return true
	var index := _index(cell)
	return (
		_map.rock[index] == 1
		or _structures.is_base(index)
		or _occupancy.building_ids[index] != Occupancy.EMPTY
		or _piles.levels[index] == Piles.WALL_LEVEL
	)


func _tie_break(i: int, j: int) -> Vector2:
	return Vector2.RIGHT if ids[i] > ids[j] else Vector2.LEFT


# Removes the dead and returns where they died.
func remove_dead() -> PackedVector2Array:
	var deaths := PackedVector2Array()
	var i := 0
	while i < count:
		if hp[i] <= 0.0:
			deaths.append(positions[i])
			_swap_remove(i)
		else:
			i += 1
	return deaths


func _cell_index(pos: Vector2) -> int:
	return int(pos.y) * _map.width + int(pos.x)


func _index(cell: Vector2i) -> int:
	return cell.y * _map.width + cell.x


func _cell_of(index: int) -> Vector2i:
	return Vector2i(index % _map.width, index / _map.width)


func _swap_remove(index: int) -> void:
	_index_by_id.erase(ids[index])
	count -= 1
	if index == count:
		return
	ids[index] = ids[count]
	positions[index] = positions[count]
	hp[index] = hp[count]
	heading_offsets[index] = heading_offsets[count]
	structure_targets[index] = structure_targets[count]
	routes[index] = routes[count]
	last_rolled_cells[index] = last_rolled_cells[count]
	pace_rolls[index] = pace_rolls[count]
	wander_phases[index] = wander_phases[count]
	_best_values[index] = _best_values[count]
	_stuck_ticks[index] = _stuck_ticks[count]
	_index_by_id[ids[index]] = index


func _grow() -> void:
	var capacity := maxi(64, ids.size() * 2)
	ids.resize(capacity)
	positions.resize(capacity)
	hp.resize(capacity)
	heading_offsets.resize(capacity)
	structure_targets.resize(capacity)
	routes.resize(capacity)
	last_rolled_cells.resize(capacity)
	pace_rolls.resize(capacity)
	wander_phases.resize(capacity)
	_best_values.resize(capacity)
	_stuck_ticks.resize(capacity)
