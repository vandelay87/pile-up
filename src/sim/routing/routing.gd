class_name Routing
extends RefCounted

enum Route { SENSIBLE, DIRECT }

const UNREACHABLE := INF
const NO_PARENT := Vector2i(-1, -1)
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
const _NO_OFFSET := 8
const _REGION := 1
const _INVALID := 2

static var _dxs := PackedInt32Array()
static var _dys := PackedInt32Array()
static var _steps := PackedFloat64Array()
static var _directions := PackedVector2Array()

var last_rebuild_msec: float
var last_update_msec: float

var _settings: Settings
var _map: MapData
var _occupancy: Occupancy
var _piles: Piles
var _fields: Array[Field] = []
var _factors: Array[PackedFloat64Array] = []
var _builds: Array[_FieldBuild] = []
var _build_tasks := PackedInt64Array()
var _builds_stale := false
var _blend_cells := PackedInt32Array([0, 0, 0, 0])
var _blend_weights := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
var _marks := PackedByteArray()


class Field:
	extends RefCounted

	var values := PackedFloat64Array()
	var parents := PackedInt32Array()
	var parent_offsets := PackedByteArray()
	var directions := PackedVector2Array()


class _FieldBuild:
	extends RefCounted

	var field: Field
	var factors: PackedFloat64Array

	var _map: MapData

	func _init(map: MapData, terrain_factors: PackedFloat64Array) -> void:
		_map = map
		factors = terrain_factors

	func run() -> void:
		field = Routing._build_field(_map, factors)


func _init(
	run_settings: Settings, run_map: MapData, run_occupancy: Occupancy, run_piles: Piles
) -> void:
	_settings = run_settings
	_map = run_map
	_occupancy = run_occupancy
	_piles = run_piles
	_marks.resize(_map.width * _map.height)
	_rebuild_now()


static func _static_init() -> void:
	for offset in _OFFSETS:
		_dxs.append(offset.x)
		_dys.append(offset.y)
		_steps.append(Vector2(offset).length())
		_directions.append(Vector2(offset).normalized())
	_directions.append(Vector2.ZERO)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for task in _build_tasks:
			WorkerThreadPool.wait_for_task_completion(task)


func rebuild() -> bool:
	if is_rebuilding():
		_builds_stale = true
		return false
	_rebuild_now()
	return true


func _rebuild_now() -> void:
	var started := Time.get_ticks_usec()
	_factors = [_terrain_factors(Route.SENSIBLE), _terrain_factors(Route.DIRECT)]
	_fields = [
		_build_field(_map, _factors[Route.SENSIBLE]),
		_build_field(_map, _factors[Route.DIRECT]),
	]
	last_rebuild_msec = (Time.get_ticks_usec() - started) / 1000.0


func update(cells: Array[Vector2i]) -> bool:
	if is_rebuilding():
		_builds_stale = true
		return false
	var started := Time.get_ticks_usec()
	var changed := false
	for route: Route in Route.values():
		changed = _repair(route, cells) or changed
	last_update_msec = (Time.get_ticks_usec() - started) / 1000.0
	return changed


func start_rebuild() -> void:
	if is_rebuilding():
		_builds_stale = true
		return
	_start_builds()


func is_rebuilding() -> bool:
	return not _builds.is_empty()


func finish_rebuild() -> bool:
	if not is_rebuilding():
		return false
	_wait_for_builds()
	if _builds_stale:
		_start_builds()
		return false
	_fields = [_builds[Route.SENSIBLE].field, _builds[Route.DIRECT].field]
	_factors = [_builds[Route.SENSIBLE].factors, _builds[Route.DIRECT].factors]
	_builds.clear()
	return true


func would_block(cells: Array[Vector2i], enemy_positions: PackedVector2Array) -> bool:
	var current := _terrain_factors(Route.SENSIBLE)
	var factors := current.duplicate()
	for cell in cells:
		factors[_index(cell)] = INF
	var reached := _reachable(factors)
	var must_reach: Array[Vector2i] = []
	for edge in _map.spawn_edges:
		must_reach.append_array(_map.spawn_cells(edge))
	for pos in enemy_positions:
		var cell := Vector2i(pos.floor())
		if _map.in_bounds(cell) and value(Route.SENSIBLE, cell) != UNREACHABLE:
			must_reach.append(cell)
	for cell in must_reach:
		var index := _index(cell)
		if current[index] != INF and reached[index] == 0:
			return true
	return false


func value(route: Route, cell: Vector2i) -> float:
	return _fields[route].values[_index(cell)]


func parent(route: Route, cell: Vector2i) -> Vector2i:
	var parent_index := _fields[route].parents[_index(cell)]
	if parent_index < 0:
		return NO_PARENT
	return Vector2i(parent_index % _map.width, parent_index / _map.width)


func direction(route: Route, cell: Vector2i) -> Vector2:
	return _fields[route].directions[_index(cell)]


func sample_direction(route: Route, pos: Vector2) -> Vector2:
	var field := _fields[route]
	_blend(field, pos)
	var blended := Vector2.ZERO
	for i in 4:
		if _blend_weights[i] > 0.0:
			blended += field.directions[_blend_cells[i]] * _blend_weights[i]
	return blended.normalized()


func sample_value(route: Route, pos: Vector2) -> float:
	var field := _fields[route]
	_blend(field, pos)
	var total := 0.0
	var total_weight := 0.0
	for i in 4:
		if _blend_weights[i] > 0.0:
			total += field.values[_blend_cells[i]] * _blend_weights[i]
			total_weight += _blend_weights[i]
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


func _start_builds() -> void:
	_builds_stale = false
	_builds.clear()
	for route: Route in Route.values():
		var build := _FieldBuild.new(_map, _terrain_factors(route))
		_builds.append(build)
		_build_tasks.append(WorkerThreadPool.add_task(build.run))


func _wait_for_builds() -> void:
	for task in _build_tasks:
		WorkerThreadPool.wait_for_task_completion(task)
	_build_tasks.clear()


func _repair(route: Route, cells: Array[Vector2i]) -> bool:
	var field := _fields[route]
	var factors := _factors[route]
	var region := _apply_factors(route, factors, cells)
	if region.is_empty():
		return false
	var invalid := _invalidate(field, factors, region)
	var changed := invalid.duplicate()
	var heap := _Heap.new(64)
	for seeds: PackedInt32Array in [region, invalid]:
		for cell in seeds:
			if _reseed(field, factors, cell, heap):
				changed.append(cell)
	_settle(_map.width, _map.height, factors, field, heap, changed)
	for cell in changed:
		field.directions[cell] = _directions[field.parent_offsets[cell]]
	for cell in region:
		_marks[cell] = 0
	for cell in invalid:
		_marks[cell] = 0
	return true


func _apply_factors(
	route: Route, factors: PackedFloat64Array, cells: Array[Vector2i]
) -> PackedInt32Array:
	var level_factors := _level_factors(route)
	var width := _map.width
	var height := _map.height
	var region := PackedInt32Array()
	for cell in cells:
		var index := _index(cell)
		var factor := _cell_factor(level_factors, index)
		if factor == factors[index]:
			continue
		factors[index] = factor
		for y in range(maxi(cell.y - 1, 0), mini(cell.y + 2, height)):
			for x in range(maxi(cell.x - 1, 0), mini(cell.x + 2, width)):
				var near := y * width + x
				if _marks[near] & _REGION == 0:
					_marks[near] |= _REGION
					region.append(near)
	return region


func _invalidate(
	field: Field, factors: PackedFloat64Array, region: PackedInt32Array
) -> PackedInt32Array:
	var values := field.values
	var parents := field.parents
	var invalid := PackedInt32Array()
	for cell in region:
		if values[cell] == UNREACHABLE:
			continue
		var k := field.parent_offsets[cell]
		if (
			factors[cell] == INF
			or (k != _NO_OFFSET and _cost_via(factors, values, cell, k) > values[cell])
		):
			_marks[cell] |= _INVALID
			invalid.append(cell)
	var width := _map.width
	var height := _map.height
	var dxs := _dxs
	var dys := _dys
	var next := 0
	while next < invalid.size():
		var cell := invalid[next]
		next += 1
		var x := cell % width
		var y := cell / width
		for k in 8:
			var nx := x - dxs[k]
			var ny := y - dys[k]
			if nx < 0 or ny < 0 or nx >= width or ny >= height:
				continue
			var child := ny * width + nx
			if parents[child] == cell and _marks[child] & _INVALID == 0:
				_marks[child] |= _INVALID
				invalid.append(child)
	for cell in invalid:
		values[cell] = UNREACHABLE
		_set_parent(field, cell, _NO_OFFSET, width)
	return invalid


func _reseed(field: Field, factors: PackedFloat64Array, cell: int, heap: _Heap) -> bool:
	var values := field.values
	if factors[cell] == INF or values[cell] == 0.0:
		return false
	var width := _map.width
	var height := _map.height
	var x := cell % width
	var y := cell / width
	var dxs := _dxs
	var dys := _dys
	var steps := _steps
	var best := UNREACHABLE
	var best_k := _NO_OFFSET
	for k in 8:
		var dx := dxs[k]
		var px := x + dx
		var py := y + dys[k]
		if px < 0 or py < 0 or px >= width or py >= height:
			continue
		var parent_index := py * width + px
		var entry_cost := factors[parent_index]
		if entry_cost == INF or values[parent_index] == UNREACHABLE:
			continue
		if k >= 4 and (factors[cell + dx] == INF or factors[parent_index - dx] == INF):
			continue
		var cost := values[parent_index] + steps[k] * entry_cost
		if cost < best:
			best = cost
			best_k = k
	if best > values[cell] or (best == values[cell] and field.parent_offsets[cell] == best_k):
		return false
	if best < values[cell]:
		values[cell] = best
		heap.push(best, cell)
	_set_parent(field, cell, best_k, width)
	return true


func _cost_via(factors: PackedFloat64Array, values: PackedFloat64Array, cell: int, k: int) -> float:
	var width := _map.width
	var dx := _dxs[k]
	var px := cell % width + dx
	var py := cell / width + _dys[k]
	if px < 0 or py < 0 or px >= width or py >= _map.height:
		return UNREACHABLE
	var parent_index := py * width + px
	var entry_cost := factors[parent_index]
	if entry_cost == INF or factors[cell] == INF or values[parent_index] == UNREACHABLE:
		return UNREACHABLE
	if k >= 4 and (factors[cell + dx] == INF or factors[parent_index - dx] == INF):
		return UNREACHABLE
	return values[parent_index] + _steps[k] * entry_cost


func _level_factors(route: Route) -> PackedFloat64Array:
	var level_factors := PackedFloat64Array([1.0])
	for level in range(1, Piles.WALL_LEVEL):
		level_factors.append(pile_factor(route, level))
	return level_factors


func _cell_factor(level_factors: PackedFloat64Array, index: int) -> float:
	if _map.rock[index] == 1 or _occupancy.occupied[index] == 1:
		return INF
	return level_factors[_piles.levels[index]]


static func _build_field(map: MapData, factors: PackedFloat64Array) -> Field:
	var width := map.width
	var count := width * map.height
	var field := Field.new()
	field.values.resize(count)
	field.values.fill(UNREACHABLE)
	field.parents.resize(count)
	field.parents.fill(-1)
	field.parent_offsets.resize(count)
	field.parent_offsets.fill(_NO_OFFSET)
	field.directions.resize(count)

	var heap := _Heap.new(count)
	for cell in map.base_cells():
		var base_index := cell.y * width + cell.x
		field.values[base_index] = 0.0
		heap.push(0.0, base_index)
	_settle(width, map.height, factors, field, heap, PackedInt32Array())

	for cell in count:
		field.directions[cell] = _directions[field.parent_offsets[cell]]
	return field


static func _settle(
	width: int,
	height: int,
	factors: PackedFloat64Array,
	field: Field,
	heap: _Heap,
	changed: PackedInt32Array
) -> void:
	var values := field.values
	var parents := field.parents
	var parent_offsets := field.parent_offsets
	var dxs := _dxs
	var dys := _dys
	var steps := _steps
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
			var neighbour := ny * width + nx
			if factors[neighbour] == INF:
				continue
			if k >= 4 and (factors[neighbour + dx] == INF or factors[cell - dx] == INF):
				continue
			var candidate := current + steps[k] * entry_cost
			if candidate < values[neighbour]:
				values[neighbour] = candidate
				heap.push(candidate, neighbour)
			elif candidate > values[neighbour] or k >= parent_offsets[neighbour]:
				continue
			parents[neighbour] = cell
			parent_offsets[neighbour] = k
			changed.append(neighbour)


static func _set_parent(field: Field, cell: int, k: int, width: int) -> void:
	field.parent_offsets[cell] = k
	field.parents[cell] = -1 if k == _NO_OFFSET else cell + _dys[k] * width + _dxs[k]


func _reachable(factors: PackedFloat64Array) -> PackedByteArray:
	var width := _map.width
	var height := _map.height
	var reached := PackedByteArray()
	reached.resize(width * height)
	var frontier := PackedInt32Array()
	for cell in _map.base_cells():
		reached[_index(cell)] = 1
		frontier.append(_index(cell))
	var next := 0
	while next < frontier.size():
		var cell := frontier[next]
		next += 1
		var x := cell % width
		var y := cell / width
		for k in 8:
			var offset := _OFFSETS[k]
			var nx := x + offset.x
			var ny := y + offset.y
			if nx < 0 or ny < 0 or nx >= width or ny >= height:
				continue
			var neighbour := ny * width + nx
			if reached[neighbour] == 1 or factors[neighbour] == INF:
				continue
			if k >= 4 and (factors[y * width + nx] == INF or factors[ny * width + x] == INF):
				continue
			reached[neighbour] = 1
			frontier.append(neighbour)
	return reached


func _terrain_factors(route: Route) -> PackedFloat64Array:
	var level_factors := _level_factors(route)
	var rock := _map.rock
	var occupied := _occupancy.occupied
	var levels := _piles.levels
	var factors := PackedFloat64Array()
	factors.resize(levels.size())
	for index in levels.size():
		var impassable := rock[index] == 1 or occupied[index] == 1
		factors[index] = INF if impassable else level_factors[levels[index]]
	return factors


func _blend(field: Field, pos: Vector2) -> void:
	var shifted := pos - Vector2(0.5, 0.5)
	var corner := Vector2i(shifted.floor())
	var fraction := shifted - Vector2(corner)
	var width := _map.width
	var height := _map.height
	for i in 4:
		var x := corner.x + (i & 1)
		var y := corner.y + (i >> 1)
		var weight := 0.0
		if x >= 0 and y >= 0 and x < width and y < height:
			var cell := y * width + x
			if field.values[cell] != UNREACHABLE:
				var weight_x := fraction.x if i & 1 else 1.0 - fraction.x
				var weight_y := fraction.y if i >> 1 else 1.0 - fraction.y
				weight = weight_x * weight_y
				_blend_cells[i] = cell
		_blend_weights[i] = weight


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
