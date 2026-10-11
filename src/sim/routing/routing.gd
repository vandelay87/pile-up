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
const _RESHAPED := 4

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
var _structures: Structures
var _fields: Array[Field] = []
var _factors: Array[PackedFloat64Array] = []
var _solid := PackedByteArray()
var _builds: Array[_FieldBuild] = []
var _build_tasks := PackedInt64Array()
var _builds_stale := false
var _blend_cells := PackedInt32Array([0, 0, 0, 0])
var _blend_weights := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
var _marks := PackedByteArray()
var _sensible_before: Field = null


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
	var solid: PackedByteArray

	var _map: MapData

	func _init(
		map: MapData, terrain_factors: PackedFloat64Array, solid_cells: PackedByteArray
	) -> void:
		_map = map
		factors = terrain_factors
		solid = solid_cells

	func run() -> void:
		field = Routing._build_field(_map, factors, solid)


func _init(
	run_settings: Settings,
	run_map: MapData,
	run_occupancy: Occupancy,
	run_piles: Piles,
	run_structures: Structures,
) -> void:
	_settings = run_settings
	_map = run_map
	_occupancy = run_occupancy
	_piles = run_piles
	_structures = run_structures
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
	_keep_sensible_before(false)
	_rebuild_now()
	return true


func _rebuild_now() -> void:
	var started := Time.get_ticks_usec()
	_factors = [_terrain_factors(Route.SENSIBLE), _terrain_factors(Route.DIRECT)]
	_solid = _solid_cells()
	_fields = [
		_build_field(_map, _factors[Route.SENSIBLE], _solid),
		_build_field(_map, _factors[Route.DIRECT], _solid),
	]
	last_rebuild_msec = (Time.get_ticks_usec() - started) / 1000.0


func update(cells: Array[Vector2i]) -> bool:
	if is_rebuilding():
		_builds_stale = true
		return false
	var started := Time.get_ticks_usec()
	var reshaped := _apply_solid(cells)
	var changed := false
	for route: Route in Route.values():
		changed = _repair(route, cells) or changed
	for cell in reshaped:
		_marks[cell] &= ~_RESHAPED
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
	_keep_sensible_before(false)
	_fields = [_builds[Route.SENSIBLE].field, _builds[Route.DIRECT].field]
	_factors = [_builds[Route.SENSIBLE].factors, _builds[Route.DIRECT].factors]
	_solid = _builds[Route.SENSIBLE].solid
	_builds.clear()
	return true


# The sensible field as it was before its first change since the last call, or null if it
# has not changed since.
func take_sensible_before() -> Field:
	var before := _sensible_before
	_sensible_before = null
	return before


# Keeps the sensible field about to change; a field repaired in place is copied first.
func _keep_sensible_before(copy: bool) -> void:
	if _sensible_before != null:
		return
	var field := _fields[Route.SENSIBLE]
	if copy:
		var kept := Field.new()
		kept.values = field.values.duplicate()
		kept.directions = field.directions.duplicate()
		field = kept
	_sensible_before = field


func value(route: Route, cell: Vector2i) -> float:
	return _fields[route].values[_map.index_of(cell)]


func parent(route: Route, cell: Vector2i) -> Vector2i:
	var parent_index := _fields[route].parents[_map.index_of(cell)]
	if parent_index < 0:
		return NO_PARENT
	return _map.cell_of(parent_index)


func parents(route: Route) -> PackedInt32Array:
	return _fields[route].parents


func direction(route: Route, cell: Vector2i) -> Vector2:
	return _fields[route].directions[_map.index_of(cell)]


func sample_direction(route: Route, pos: Vector2) -> Vector2:
	return sample_field_direction(_fields[route], pos)


func sample_field_direction(field: Field, pos: Vector2) -> Vector2:
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
	var break_time_in_cells := hp / _settings.structure_damage * _settings.enemy_speed
	return 1.0 + weight * break_time_in_cells


func _start_builds() -> void:
	_builds_stale = false
	_builds.clear()
	var solid := _solid_cells()
	for route: Route in Route.values():
		var build := _FieldBuild.new(_map, _terrain_factors(route), solid)
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
	if route == Route.SENSIBLE:
		_keep_sensible_before(true)
	var invalid := _invalidate(field, factors, region)
	var changed := invalid.duplicate()
	var heap := _Heap.new(64)
	for seeds: PackedInt32Array in [region, invalid]:
		for cell in seeds:
			if _reseed(field, factors, cell, heap):
				changed.append(cell)
	_settle(_map.width, _map.height, factors, _solid, field, heap, changed)
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
		var index := _map.index_of(cell)
		var factor := _cell_factor(route, level_factors, index)
		if factor == factors[index] and _marks[index] & _RESHAPED == 0:
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
	var solid := _solid
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
		if k >= 4 and (solid[cell + dx] == 1 or solid[parent_index - dx] == 1):
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
	if k >= 4 and (_solid[cell + dx] == 1 or _solid[parent_index - dx] == 1):
		return UNREACHABLE
	return values[parent_index] + _steps[k] * entry_cost


func _level_factors(route: Route) -> PackedFloat64Array:
	var level_factors := PackedFloat64Array([1.0])
	for level in range(1, Piles.WALL_LEVEL):
		level_factors.append(pile_factor(route, level))
	return level_factors


func _cell_factor(route: Route, level_factors: PackedFloat64Array, index: int) -> float:
	if _map.rock[index] == 1:
		return INF
	var level := _piles.levels[index]
	if level == Piles.WALL_LEVEL or _occupancy.building_ids[index] != Occupancy.EMPTY:
		return _structure_cell_factor(route, index)
	return level_factors[level]


# A wall or building costs its break time, from its bucketed HP.
func _structure_cell_factor(route: Route, index: int) -> float:
	var cell := Vector2i(index % _map.width, index / _map.width)
	return wall_factor(route, _structures.bucketed_hp(cell))


func _is_solid(index: int) -> bool:
	return (
		_map.rock[index] == 1
		or _occupancy.building_ids[index] != Occupancy.EMPTY
		or _piles.levels[index] == Piles.WALL_LEVEL
	)


func _solid_cells() -> PackedByteArray:
	var solid := PackedByteArray()
	solid.resize(_map.width * _map.height)
	for index in solid.size():
		solid[index] = 1 if _is_solid(index) else 0
	return solid


func _apply_solid(cells: Array[Vector2i]) -> PackedInt32Array:
	var reshaped := PackedInt32Array()
	for cell in cells:
		var index := _map.index_of(cell)
		var solid := 1 if _is_solid(index) else 0
		if solid != _solid[index]:
			_solid[index] = solid
			_marks[index] |= _RESHAPED
			reshaped.append(index)
	return reshaped


static func _build_field(
	map: MapData, factors: PackedFloat64Array, solid: PackedByteArray
) -> Field:
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
		var base_index := map.index_of(cell)
		field.values[base_index] = 0.0
		heap.push(0.0, base_index)
	_settle(width, map.height, factors, solid, field, heap, PackedInt32Array())

	for cell in count:
		field.directions[cell] = _directions[field.parent_offsets[cell]]
	return field


static func _settle(
	width: int,
	height: int,
	factors: PackedFloat64Array,
	solid: PackedByteArray,
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
			if k >= 4 and (solid[neighbour + dx] == 1 or solid[cell - dx] == 1):
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


func _terrain_factors(route: Route) -> PackedFloat64Array:
	var level_factors := _level_factors(route)
	var rock := _map.rock
	var building_ids := _occupancy.building_ids
	var levels := _piles.levels
	var factors := PackedFloat64Array()
	factors.resize(levels.size())
	for index in levels.size():
		if rock[index] == 1:
			factors[index] = INF
		elif levels[index] == Piles.WALL_LEVEL or building_ids[index] != Occupancy.EMPTY:
			factors[index] = _structure_cell_factor(route, index)
		else:
			factors[index] = level_factors[levels[index]]
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
