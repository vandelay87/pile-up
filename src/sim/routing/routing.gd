class_name Routing
extends RefCounted

enum Route { SENSIBLE, DIRECT }

const UNREACHABLE := INF
const NO_PARENT := Vector2i(-1, -1)
const _BLEND_CORNERS: Array[Vector2i] = [
	Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)
]
const _OFFSETS: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(0, -1),
	Vector2i(1, 1),
	Vector2i(-1, 1),
	Vector2i(1, -1),
	Vector2i(-1, -1),
]

var last_rebuild_msec: float

var _settings: Settings
var _map: MapData
var _occupancy: Occupancy
var _fields: Array[Field] = []


class Field:
	extends RefCounted

	var values := PackedFloat64Array()
	var parents := PackedInt32Array()
	var directions := PackedVector2Array()


func _init(run_settings: Settings, run_map: MapData, run_occupancy: Occupancy) -> void:
	_settings = run_settings
	_map = run_map
	_occupancy = run_occupancy
	rebuild()


func rebuild() -> void:
	var started := Time.get_ticks_usec()
	var factors := _terrain_factors()
	_fields = [_build_field(factors), _build_field(factors)]
	last_rebuild_msec = (Time.get_ticks_usec() - started) / 1000.0


func value(route: Route, cell: Vector2i) -> float:
	return _fields[route].values[_index(cell)]


func parent(route: Route, cell: Vector2i) -> Vector2i:
	var parent_index := _fields[route].parents[_index(cell)]
	if parent_index < 0:
		return NO_PARENT
	return Vector2i(parent_index % _map.width, parent_index / _map.width)


func sample_direction(route: Route, pos: Vector2) -> Vector2:
	var field := _fields[route]
	var blended := Vector2.ZERO
	var corner := Vector2i((pos - Vector2(0.5, 0.5)).floor())
	var fraction := pos - Vector2(0.5, 0.5) - Vector2(corner)
	for offset: Vector2i in _BLEND_CORNERS:
		var cell := corner + offset
		if _reachable(field, cell):
			blended += field.directions[_index(cell)] * _blend_weight(fraction, offset)
	return blended.normalized()


func sample_value(route: Route, pos: Vector2) -> float:
	var field := _fields[route]
	var total := 0.0
	var total_weight := 0.0
	var corner := Vector2i((pos - Vector2(0.5, 0.5)).floor())
	var fraction := pos - Vector2(0.5, 0.5) - Vector2(corner)
	for offset: Vector2i in _BLEND_CORNERS:
		var cell := corner + offset
		if _reachable(field, cell):
			var weight := _blend_weight(fraction, offset)
			total += field.values[_index(cell)] * weight
			total_weight += weight
	return total / total_weight if total_weight > 0.0 else UNREACHABLE


func pile_factor(route: Route, level: int) -> float:
	var weight := (
		_settings.sensible_pile_weight if route == Route.SENSIBLE else _settings.direct_pile_weight
	)
	return 1.0 + weight * (1.0 / (1.0 - _settings.pile_slow(level)) - 1.0)


func wall_factor(route: Route, hp: float) -> float:
	var weight := (
		_settings.sensible_wall_weight if route == Route.SENSIBLE else _settings.direct_wall_weight
	)
	var break_time_in_cells := hp / _settings.wall_damage * _settings.enemy_speed
	return 1.0 + weight * break_time_in_cells


func _build_field(factors: PackedFloat64Array) -> Field:
	var width := _map.width
	var height := _map.height
	var count := width * height
	var offsets := PackedInt32Array()
	var dxs := PackedInt32Array()
	var dys := PackedInt32Array()
	var steps := PackedFloat64Array()
	for offset in _OFFSETS:
		offsets.append(offset.y * width + offset.x)
		dxs.append(offset.x)
		dys.append(offset.y)
		steps.append(Vector2(offset).length())

	var values := PackedFloat64Array()
	values.resize(count)
	values.fill(UNREACHABLE)
	var parents := PackedInt32Array()
	parents.resize(count)
	parents.fill(-1)

	var heap := _Heap.new(count)
	for cell in _map.base_cells():
		values[_index(cell)] = 0.0
		heap.push(0.0, _index(cell))

	while not heap.is_empty():
		var current := heap.peek_value()
		var cell := heap.pop()
		if current > values[cell]:
			continue
		var x := cell % width
		var y := cell / width
		var entry_cost := factors[cell]
		for k in 8:
			var dx := dxs[k]
			var nx := x - dx
			var ny := y - dys[k]
			if nx < 0 or ny < 0 or nx >= width or ny >= height:
				continue
			var neighbour := cell - offsets[k]
			if factors[neighbour] == INF:
				continue
			if k >= 4 and (factors[neighbour + dx] == INF or factors[cell - dx] == INF):
				continue
			var candidate := current + steps[k] * entry_cost
			if candidate < values[neighbour]:
				values[neighbour] = candidate
				parents[neighbour] = cell
				heap.push(candidate, neighbour)

	var directions := PackedVector2Array()
	directions.resize(count)
	for cell in count:
		var parent_index := parents[cell]
		if parent_index >= 0:
			var to_parent := Vector2(
				parent_index % width - cell % width, parent_index / width - cell / width
			)
			directions[cell] = to_parent.normalized()

	var field := Field.new()
	field.values = values
	field.parents = parents
	field.directions = directions
	return field


func _terrain_factors() -> PackedFloat64Array:
	var factors := PackedFloat64Array()
	factors.resize(_map.width * _map.height)
	for y in _map.height:
		for x in _map.width:
			var cell := Vector2i(x, y)
			var blocked := _map.is_rock(cell) or _occupancy.is_occupied(cell)
			factors[_index(cell)] = INF if blocked else 1.0
	return factors


func _reachable(field: Field, cell: Vector2i) -> bool:
	return _map.in_bounds(cell) and field.values[_index(cell)] != UNREACHABLE


static func _blend_weight(fraction: Vector2, offset: Vector2i) -> float:
	var weight_x := fraction.x if offset.x == 1 else 1.0 - fraction.x
	var weight_y := fraction.y if offset.y == 1 else 1.0 - fraction.y
	return weight_x * weight_y


func _index(cell: Vector2i) -> int:
	return cell.y * _map.width + cell.x


class _Heap:
	extends RefCounted

	var _values := PackedFloat64Array()
	var _items := PackedInt32Array()
	var _size := 0

	func _init(capacity: int) -> void:
		_values.resize(capacity)
		_items.resize(capacity)

	func is_empty() -> bool:
		return _size == 0

	func peek_value() -> float:
		return _values[0]

	func push(value: float, item: int) -> void:
		if _size == _values.size():
			_values.resize(_size * 2)
			_items.resize(_size * 2)
		var i := _size
		_size += 1
		while i > 0:
			var up := (i - 1) >> 1
			if _values[up] <= value:
				break
			_values[i] = _values[up]
			_items[i] = _items[up]
			i = up
		_values[i] = value
		_items[i] = item

	func pop() -> int:
		var top := _items[0]
		_size -= 1
		var last_value := _values[_size]
		var last_item := _items[_size]
		var i := 0
		while true:
			var child := 2 * i + 1
			if child >= _size:
				break
			if child + 1 < _size and _values[child + 1] < _values[child]:
				child += 1
			if _values[child] >= last_value:
				break
			_values[i] = _values[child]
			_items[i] = _items[child]
			i = child
		_values[i] = last_value
		_items[i] = last_item
		return top
