class_name Piles
extends RefCounted

const WALL_LEVEL := 5
const MAX_LEVEL := WALL_LEVEL - 1

var levels := PackedByteArray()
var changed: Array[Vector2i] = []

var _map: MapData
var _occupancy: Occupancy
var _queued := PackedVector2Array()
var _changed_mask := PackedByteArray()


func _init(run_map: MapData, run_occupancy: Occupancy) -> void:
	_map = run_map
	_occupancy = run_occupancy
	levels.resize(_map.width * _map.height)
	_changed_mask.resize(_map.width * _map.height)


func level(cell: Vector2i) -> int:
	return levels[_index(cell)]


func queue_bodies(positions: PackedVector2Array) -> void:
	_queued.append_array(positions)


func land() -> void:
	for pos in _queued:
		var cell := _landing_cell(Vector2i(pos.floor()))
		var index := _index(cell)
		if levels[index] < MAX_LEVEL:
			levels[index] += 1
			_mark_changed(cell)
	_queued.clear()


func decay() -> void:
	for index in levels.size():
		if levels[index] > 0:
			levels[index] -= 1
			_mark_changed(Vector2i(index % _map.width, index / _map.width))


func clear_changes() -> void:
	for cell in changed:
		_changed_mask[_index(cell)] = 0
	changed.clear()


func take_changes() -> Array[Vector2i]:
	var taken := changed.duplicate()
	clear_changes()
	return taken


func is_valid_landing(cell: Vector2i) -> bool:
	return (
		levels[_index(cell)] < WALL_LEVEL
		and not _map.is_rock(cell)
		and not _map.is_base(cell)
		and not _occupancy.is_occupied(cell)
	)


func _landing_cell(death_cell: Vector2i) -> Vector2i:
	var chosen := death_cell
	var tallest := level(death_cell) if level(death_cell) < WALL_LEVEL else 0
	for y in range(death_cell.y - 1, death_cell.y + 2):
		for x in range(death_cell.x - 1, death_cell.x + 2):
			var cell := Vector2i(x, y)
			if not _map.in_bounds(cell):
				continue
			var cell_level := level(cell)
			if cell_level > tallest and cell_level < WALL_LEVEL:
				tallest = cell_level
				chosen = cell
	if is_valid_landing(chosen):
		return chosen
	return _nearest_valid(death_cell)


func _nearest_valid(from: Vector2i) -> Vector2i:
	var best := from
	var best_distance := INF
	var ring := 1
	while ring <= maxi(_map.width, _map.height) and ring <= best_distance:
		for y in range(from.y - ring, from.y + ring + 1):
			for x in range(from.x - ring, from.x + ring + 1):
				var cell := Vector2i(x, y)
				if maxi(absi(x - from.x), absi(y - from.y)) != ring:
					continue
				if not _map.in_bounds(cell) or not is_valid_landing(cell):
					continue
				var distance := _octile(cell - from)
				if distance < best_distance:
					best_distance = distance
					best = cell
		ring += 1
	return best


func _mark_changed(cell: Vector2i) -> void:
	var index := _index(cell)
	if _changed_mask[index] == 0:
		_changed_mask[index] = 1
		changed.append(cell)


func _index(cell: Vector2i) -> int:
	return cell.y * _map.width + cell.x


static func _octile(offset: Vector2i) -> float:
	var straight := absi(absi(offset.x) - absi(offset.y))
	var diagonal := mini(absi(offset.x), absi(offset.y))
	return straight + diagonal * sqrt(2.0)
