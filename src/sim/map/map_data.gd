class_name MapData
extends RefCounted

const VERSION := 1
const MAX_SIZE := 150
const CLEAR := "."
const ROCK := "#"
const EDGES: Array[String] = ["N", "E", "S", "W"]

var width: int:
	get:
		return _width
var height: int:
	get:
		return _height
var base: Rect2i:
	get:
		return _base
var spawn_edges: PackedStringArray:
	get:
		return _spawn_edges
var rock: PackedByteArray:
	get:
		return _rock

var _width: int
var _height: int
var _rock: PackedByteArray
var _base: Rect2i
var _spawn_edges: PackedStringArray
var _spawn_cells := {}


class LoadResult:
	extends RefCounted

	var map: MapData
	var error: String

	func _init(loaded: MapData, message: String) -> void:
		map = loaded
		error = message


func _init(
	map_width: int,
	map_height: int,
	rock: PackedByteArray,
	base_rect: Rect2i,
	edges: PackedStringArray,
) -> void:
	_width = map_width
	_height = map_height
	_rock = rock
	_base = base_rect
	_spawn_edges = edges
	var reaches_base := _cells_reaching_base()
	for edge in edges:
		var cells: Array[Vector2i] = []
		for cell in _edge_cells(edge):
			if reaches_base[_index(cell)] == 1:
				cells.append(cell)
		_spawn_cells[edge] = cells


static func load_file(path: String) -> LoadResult:
	if not FileAccess.file_exists(path):
		return LoadResult.new(null, "%s: file not found" % path)
	var result := from_json(FileAccess.get_file_as_string(path))
	if not result.error.is_empty():
		result.error = "%s:\n%s" % [path, result.error]
	return result


static func from_json(text: String) -> LoadResult:
	var json := JSON.new()
	if json.parse(text) != OK:
		return LoadResult.new(
			null, "invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()]
		)
	if json.data is not Dictionary:
		return LoadResult.new(null, "expected a JSON object")

	var data: Dictionary = json.data
	var errors := PackedStringArray()
	var version := _read_int(data, "version", errors)
	if errors.is_empty() and version != VERSION:
		errors.append("version: unknown version %d (expected %d)" % [version, VERSION])
		return _failure(errors)
	var map_width := _read_side(data, "width", errors)
	var map_height := _read_side(data, "height", errors)
	var rows := _read_strings(data, "rows", errors)
	var base_rect := _read_base(data, errors)
	var edges := _read_edges(data, errors)
	if not errors.is_empty():
		return _failure(errors)

	var rock := _parse_rock(rows, map_width, map_height, errors)
	if not errors.is_empty():
		return _failure(errors)

	_check_base(base_rect, rock, map_width, map_height, errors)
	if not errors.is_empty():
		return _failure(errors)

	var map := MapData.new(map_width, map_height, rock, base_rect, edges)
	for edge in edges:
		if map.spawn_cells(edge).is_empty():
			errors.append("spawn_edges: %s has no passable cell that reaches the base" % edge)
	if not errors.is_empty():
		return _failure(errors)
	return LoadResult.new(map, "")


func is_rock(cell: Vector2i) -> bool:
	return _rock[_index(cell)] == 1


func is_base(cell: Vector2i) -> bool:
	return _base.has_point(cell)


func base_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in range(_base.position.y, _base.end.y):
		for x in range(_base.position.x, _base.end.x):
			cells.append(Vector2i(x, y))
	return cells


func spawn_cells(edge: String) -> Array[Vector2i]:
	var cells: Array[Vector2i] = _spawn_cells.get(edge, [] as Array[Vector2i])
	return cells.duplicate()


func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < _width and cell.y < _height


func _index(cell: Vector2i) -> int:
	return cell.y * _width + cell.x


func _edge_cells(edge: String) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	match edge:
		"N":
			for x in _width:
				cells.append(Vector2i(x, 0))
		"S":
			for x in _width:
				cells.append(Vector2i(x, _height - 1))
		"W":
			for y in _height:
				cells.append(Vector2i(0, y))
		"E":
			for y in _height:
				cells.append(Vector2i(_width - 1, y))
	return cells


func _cells_reaching_base() -> PackedByteArray:
	var reached := PackedByteArray()
	reached.resize(_width * _height)
	var frontier := base_cells()
	for cell in frontier:
		reached[_index(cell)] = 1
	var next := 0
	while next < frontier.size():
		var cell := frontier[next]
		next += 1
		for offset: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var neighbour := cell + offset
			if in_bounds(neighbour) and not is_rock(neighbour) and reached[_index(neighbour)] == 0:
				reached[_index(neighbour)] = 1
				frontier.append(neighbour)
	return reached


static func _failure(errors: PackedStringArray) -> LoadResult:
	return LoadResult.new(null, "\n".join(errors))


static func _parse_rock(
	rows: PackedStringArray, map_width: int, map_height: int, errors: PackedStringArray
) -> PackedByteArray:
	var rock := PackedByteArray()
	if rows.size() != map_height:
		errors.append("rows: %d rows, expected %d" % [rows.size(), map_height])
		return rock
	rock.resize(map_width * map_height)
	for y in map_height:
		var row := rows[y]
		if row.length() != map_width:
			errors.append("rows[%d]: %d cells, expected %d" % [y, row.length(), map_width])
			continue
		for x in map_width:
			match row[x]:
				ROCK:
					rock[y * map_width + x] = 1
				CLEAR:
					pass
				_:
					errors.append("rows[%d]: unknown character '%s' at x %d" % [y, row[x], x])
	return rock


static func _check_base(
	base_rect: Rect2i,
	rock: PackedByteArray,
	map_width: int,
	map_height: int,
	errors: PackedStringArray,
) -> void:
	if not base_rect.has_area() or not Rect2i(0, 0, map_width, map_height).encloses(base_rect):
		errors.append(
			(
				"base: %s size %s is outside the %d×%d map"
				% [base_rect.position, base_rect.size, map_width, map_height]
			)
		)
		return
	for y in range(base_rect.position.y, base_rect.end.y):
		for x in range(base_rect.position.x, base_rect.end.x):
			if rock[y * map_width + x] == 1:
				errors.append("base: covers rock at %s" % Vector2i(x, y))


static func _read_base(data: Dictionary, errors: PackedStringArray) -> Rect2i:
	if data.get("base") is not Dictionary:
		errors.append("base: expected an object with origin and size")
		return Rect2i()
	var base_data: Dictionary = data["base"]
	var origin := _read_cell(base_data, "origin", "base.origin", errors)
	var size := _read_cell(base_data, "size", "base.size", errors)
	return Rect2i(origin, size)


static func _read_edges(data: Dictionary, errors: PackedStringArray) -> PackedStringArray:
	var edges := _read_strings(data, "spawn_edges", errors)
	var seen := PackedStringArray()
	for edge in edges:
		if edge not in EDGES:
			errors.append(
				"spawn_edges: unknown edge '%s' (expected one of %s)" % [edge, ", ".join(EDGES)]
			)
		elif edge in seen:
			errors.append("spawn_edges: %s is listed twice" % edge)
		seen.append(edge)
	return edges


static func _read_cell(
	data: Dictionary, key: String, label: String, errors: PackedStringArray
) -> Vector2i:
	var raw: Variant = data.get(key)
	if raw is Array:
		var pair: Array = raw
		if pair.size() == 2 and _is_whole(pair[0]) and _is_whole(pair[1]):
			var x: int = type_convert(pair[0], TYPE_INT)
			var y: int = type_convert(pair[1], TYPE_INT)
			return Vector2i(x, y)
	errors.append("%s: expected [x, y] whole numbers, got %s" % [label, JSON.stringify(raw)])
	return Vector2i()


static func _read_side(data: Dictionary, key: String, errors: PackedStringArray) -> int:
	var count := errors.size()
	var side := _read_int(data, key, errors)
	if errors.size() == count and (side < 1 or side > MAX_SIZE):
		errors.append("%s: %d is outside 1 to %d" % [key, side, MAX_SIZE])
	return side


static func _read_int(data: Dictionary, key: String, errors: PackedStringArray) -> int:
	var raw: Variant = data.get(key)
	if not _is_whole(raw):
		errors.append("%s: expected a whole number, got %s" % [key, JSON.stringify(raw)])
		return 0
	return type_convert(raw, TYPE_INT)


static func _read_strings(
	data: Dictionary, key: String, errors: PackedStringArray
) -> PackedStringArray:
	var raw: Variant = data.get(key)
	if raw is Array:
		var items: Array = raw
		if items.all(func(item: Variant) -> bool: return item is String):
			return PackedStringArray(items)
	errors.append("%s: expected an array of strings" % key)
	return PackedStringArray()


static func _is_whole(raw: Variant) -> bool:
	if raw is int:
		return true
	if raw is float:
		var number: float = raw
		return number == roundf(number)
	return false
