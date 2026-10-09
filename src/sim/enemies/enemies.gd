class_name Enemies
extends RefCounted

const NONE := -1
const _COLLISION_PASSES := 2
const _HASH_MARGIN := 2
const _FACES: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]

var count := 0
var ids := PackedInt32Array()
var positions := PackedVector2Array()
var hp := PackedFloat32Array()
var leaked := PackedByteArray()
var heading_offsets := PackedFloat32Array()

var _settings: Settings
var _map: MapData
var _occupancy: Occupancy
var _routing: Routing
var _rng: RandomNumberGenerator
var _next_id := 0
var _index_by_id := {}
var _bucket_starts := PackedInt32Array()
var _bucket_enemies := PackedInt32Array()
var _moved := PackedVector2Array()


class Removal:
	extends RefCounted

	var deaths := PackedVector2Array()
	var leaks := 0


func _init(
	run_settings: Settings,
	run_map: MapData,
	run_occupancy: Occupancy,
	run_routing: Routing,
	rng: RandomNumberGenerator,
) -> void:
	_settings = run_settings
	_map = run_map
	_occupancy = run_occupancy
	_routing = run_routing
	_rng = rng
	_bucket_starts.resize(_map.width * _map.height + 1)


func spawn(pos: Vector2) -> int:
	if count == ids.size():
		_grow()
	var id := _next_id
	_next_id += 1
	ids[count] = id
	positions[count] = pos
	hp[count] = _settings.enemy_hp
	leaked[count] = 0
	heading_offsets[count] = _rng.randf_range(-1.0, 1.0) * _settings.heading_offset_radians
	_index_by_id[id] = count
	count += 1
	return id


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
				if hp[i] <= 0.0 or leaked[i] == 1:
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
	var radius := _settings.separation_radius
	var push := _settings.separation_push
	var cap := _settings.neighbour_cap
	_moved.resize(count)
	for i in count:
		var pos := positions[i]
		var heading := _routing.sample_direction(Routing.Route.SENSIBLE, pos).rotated(
			heading_offsets[i]
		)
		var separation := _separation(i, radius, push, cap).limit_length(radius)
		_moved[i] = pos + heading * step + separation
	for i in count:
		var pos := _moved[i]
		for _pass in _COLLISION_PASSES:
			var resolved := _resolve_collision(pos, radius)
			if resolved == pos:
				break
			pos = resolved
		positions[i] = pos
		if _map.is_base(Vector2i(pos.floor())):
			leaked[i] = 1


func _separation(i: int, radius: float, push: float, cap: int) -> Vector2:
	var spacing := 2.0 * radius
	var spacing_squared := spacing * spacing
	var width := _map.width
	var pos := positions[i]
	var cell := Vector2i(pos.floor())
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
				var distance := away.length()
				var direction := away / distance if distance > 1e-6 else _tie_break(i, j)
				total += direction * (spacing - distance) * push
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
	return not _map.in_bounds(cell) or _map.is_rock(cell) or _occupancy.is_occupied(cell)


func _tie_break(i: int, j: int) -> Vector2:
	return Vector2.RIGHT if ids[i] > ids[j] else Vector2.LEFT


func remove_dead_and_leaked() -> Removal:
	var removal := Removal.new()
	var i := 0
	while i < count:
		if leaked[i] == 1:
			removal.leaks += 1
		elif hp[i] <= 0.0:
			removal.deaths.append(positions[i])
		else:
			i += 1
			continue
		_swap_remove(i)
	return removal


func _cell_index(pos: Vector2) -> int:
	return int(pos.y) * _map.width + int(pos.x)


func _swap_remove(index: int) -> void:
	_index_by_id.erase(ids[index])
	count -= 1
	if index == count:
		return
	ids[index] = ids[count]
	positions[index] = positions[count]
	hp[index] = hp[count]
	leaked[index] = leaked[count]
	heading_offsets[index] = heading_offsets[count]
	_index_by_id[ids[index]] = index


func _grow() -> void:
	var capacity := maxi(64, ids.size() * 2)
	ids.resize(capacity)
	positions.resize(capacity)
	hp.resize(capacity)
	leaked.resize(capacity)
	heading_offsets.resize(capacity)
