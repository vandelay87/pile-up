class_name MapData
extends RefCounted

## Version 2 adds the base's deposit and the rig deposits; version 1 maps still load.
const VERSION := 2
## A version 1 map's base deposit: v6's contents, so older maps play under v6's rules.
const DEFAULT_BASE_GOLD := 4200
const DEFAULT_BASE_AETHER := 1400
const DEPOSIT_SIZE := Vector2i(3, 3)
const MAX_SIZE := 150
const CLEAR := "."
const ROCK := "#"
## Clear ground that enemies walk on but nothing can be built on.
const NO_BUILD := ":"
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
var no_build: PackedByteArray:
	get:
		return _no_build
## The deposit under the base, its area the base's.
var base_deposit: Deposit:
	get:
		return _base_deposit
## The deposits a rig can mine, in map order.
var deposits: Array[Deposit]:
	get:
		return _deposits

var _width: int
var _height: int
var _rock: PackedByteArray
var _no_build: PackedByteArray
var _base: Rect2i
var _spawn_edges: PackedStringArray
var _spawn_cells := {}
var _base_deposit: Deposit
var _deposits: Array[Deposit] = []
# Each cell's index into _deposits, or -1.
var _deposit_index := PackedInt32Array()


## A fixed 3×3 area of minerals, or the base's area for the base's own deposit.
class Deposit:
	extends RefCounted

	var name: String
	var area: Rect2i
	var gold: int
	var aether: int

	func _init(
		deposit_name: String, deposit_area: Rect2i, gold_held: int, aether_held: int
	) -> void:
		name = deposit_name
		area = deposit_area
		gold = gold_held
		aether = aether_held


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
	no_build_cells: PackedByteArray,
	base_contents: Vector2i,
	rig_deposits: Array[Deposit],
) -> void:
	_width = map_width
	_height = map_height
	_rock = rock
	_no_build = no_build_cells
	_base = base_rect
	_spawn_edges = edges
	_base_deposit = Deposit.new("base", base_rect, base_contents.x, base_contents.y)
	_deposits = rig_deposits
	_deposit_index.resize(map_width * map_height)
	_deposit_index.fill(-1)
	for i in rig_deposits.size():
		var area := rig_deposits[i].area
		for y in range(area.position.y, area.end.y):
			for x in range(area.position.x, area.end.x):
				_deposit_index[index_of(Vector2i(x, y))] = i
	var reaches_base := _cells_reaching_base()
	for edge in edges:
		var cells: Array[Vector2i] = []
		for cell in _edge_cells(edge):
			if reaches_base[index_of(cell)] == 1:
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
	if errors.is_empty() and (version < 1 or version > VERSION):
		errors.append("version: unknown version %d (expected 1 to %d)" % [version, VERSION])
		return _failure(errors)
	var map_width := _read_side(data, "width", errors)
	var map_height := _read_side(data, "height", errors)
	var rows := _read_strings(data, "rows", errors)
	var base_rect := _read_base(data, errors)
	var edges := _read_edges(data, errors)
	var base_contents := Vector2i(DEFAULT_BASE_GOLD, DEFAULT_BASE_AETHER)
	var rig_deposits: Array[Deposit] = []
	if version >= 2:
		base_contents = _read_base_deposit(data, errors)
		rig_deposits = _read_deposits(data, errors)
	if not errors.is_empty():
		return _failure(errors)

	var no_build_cells := PackedByteArray()
	var rock := _parse_cells(rows, map_width, map_height, no_build_cells, errors)
	if not errors.is_empty():
		return _failure(errors)

	_check_base(base_rect, rock, map_width, map_height, errors)
	if not errors.is_empty():
		return _failure(errors)
	_check_deposits(rig_deposits, base_rect, rock, no_build_cells, map_width, map_height, errors)
	if not errors.is_empty():
		return _failure(errors)

	var map := MapData.new(
		map_width, map_height, rock, base_rect, edges, no_build_cells, base_contents, rig_deposits
	)
	for edge in edges:
		if map.spawn_cells(edge).is_empty():
			errors.append("spawn_edges: %s has no passable cell that reaches the base" % edge)
	if not errors.is_empty():
		return _failure(errors)
	return LoadResult.new(map, "")


func is_rock(cell: Vector2i) -> bool:
	return _rock[index_of(cell)] == 1


func is_no_build(cell: Vector2i) -> bool:
	return _no_build[index_of(cell)] == 1


func is_base(cell: Vector2i) -> bool:
	return _base.has_point(cell)


## The rig deposit [param cell] belongs to, or null (the base's deposit included).
func deposit_at(cell: Vector2i) -> Deposit:
	if not in_bounds(cell):
		return null
	var i := _deposit_index[index_of(cell)]
	return null if i < 0 else _deposits[i]


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


## A cell's index in the map's row-major arrays.
func index_of(cell: Vector2i) -> int:
	return cell.y * _width + cell.x


func cell_of(index: int) -> Vector2i:
	return Vector2i(index % _width, index / _width)


## The position at the centre of [param cell].
static func centre_of(cell: Vector2i) -> Vector2:
	return Vector2(cell) + Vector2(0.5, 0.5)


## The cell and its 8 neighbours, clipped to the map.
func neighbourhood(cell: Vector2i) -> Rect2i:
	return Rect2i(cell - Vector2i.ONE, Vector2i(3, 3)).intersection(Rect2i(0, 0, _width, _height))


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
		reached[index_of(cell)] = 1
	var next := 0
	while next < frontier.size():
		var cell := frontier[next]
		next += 1
		for offset: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var neighbour := cell + offset
			if (
				in_bounds(neighbour)
				and not is_rock(neighbour)
				and reached[index_of(neighbour)] == 0
			):
				reached[index_of(neighbour)] = 1
				frontier.append(neighbour)
	return reached


static func _failure(errors: PackedStringArray) -> LoadResult:
	return LoadResult.new(null, "\n".join(errors))


## Returns the rock mask and fills `no_build_cells` with the no-build mask.
static func _parse_cells(
	rows: PackedStringArray,
	map_width: int,
	map_height: int,
	no_build_cells: PackedByteArray,
	errors: PackedStringArray,
) -> PackedByteArray:
	var rock := PackedByteArray()
	if rows.size() != map_height:
		errors.append("rows: %d rows, expected %d" % [rows.size(), map_height])
		return rock
	rock.resize(map_width * map_height)
	no_build_cells.resize(map_width * map_height)
	for y in map_height:
		var row := rows[y]
		if row.length() != map_width:
			errors.append("rows[%d]: %d cells, expected %d" % [y, row.length(), map_width])
			continue
		for x in map_width:
			match row[x]:
				ROCK:
					rock[y * map_width + x] = 1
				NO_BUILD:
					no_build_cells[y * map_width + x] = 1
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


static func _check_deposits(
	rig_deposits: Array[Deposit],
	base_rect: Rect2i,
	rock: PackedByteArray,
	no_build_cells: PackedByteArray,
	map_width: int,
	map_height: int,
	errors: PackedStringArray,
) -> void:
	for i in rig_deposits.size():
		var deposit := rig_deposits[i]
		var area := deposit.area
		var label := "deposits[%d] (%s)" % [i, deposit.name]
		if not Rect2i(0, 0, map_width, map_height).encloses(area):
			errors.append(
				(
					"%s: %s size %s is outside the %d×%d map"
					% [label, area.position, area.size, map_width, map_height]
				)
			)
			continue
		if area.intersects(base_rect):
			errors.append("%s: overlaps the base" % label)
		for j in i:
			if area.intersects(rig_deposits[j].area):
				errors.append("%s: overlaps deposit '%s'" % [label, rig_deposits[j].name])
		for y in range(area.position.y, area.end.y):
			for x in range(area.position.x, area.end.x):
				if rock[y * map_width + x] == 1:
					errors.append("%s: covers rock at %s" % [label, Vector2i(x, y)])
				elif no_build_cells[y * map_width + x] == 1:
					errors.append("%s: in the no-build margin at %s" % [label, Vector2i(x, y)])


## The base deposit's gold (x) and Aether (y).
static func _read_base_deposit(data: Dictionary, errors: PackedStringArray) -> Vector2i:
	if data.get("base_deposit") is not Dictionary:
		errors.append("base_deposit: expected an object with gold and aether")
		return Vector2i()
	var contents: Dictionary = data["base_deposit"]
	return Vector2i(
		_read_amount(contents, "gold", "base_deposit.gold", errors),
		_read_amount(contents, "aether", "base_deposit.aether", errors),
	)


static func _read_deposits(data: Dictionary, errors: PackedStringArray) -> Array[Deposit]:
	var loaded: Array[Deposit] = []
	var raw: Variant = data.get("deposits")
	var items: Array = raw if raw is Array else []
	if raw is not Array or not items.all(func(item: Variant) -> bool: return item is Dictionary):
		errors.append("deposits: expected an array of deposits")
		return loaded
	var names := PackedStringArray()
	for i in items.size():
		var item: Dictionary = items[i]
		var label := "deposits[%d]" % i
		var raw_name: Variant = item.get("name")
		var deposit_name: String = raw_name if raw_name is String else ""
		if deposit_name.is_empty():
			errors.append("%s.name: expected a name" % label)
		elif deposit_name in names:
			errors.append("%s: %s is named twice" % [label, deposit_name])
		names.append(deposit_name)
		var origin := _read_cell(item, "origin", label + ".origin", errors)
		var gold := _read_amount(item, "gold", label + ".gold", errors)
		var aether := _read_amount(item, "aether", label + ".aether", errors)
		loaded.append(Deposit.new(deposit_name, Rect2i(origin, DEPOSIT_SIZE), gold, aether))
	return loaded


static func _read_amount(
	data: Dictionary, key: String, label: String, errors: PackedStringArray
) -> int:
	var raw: Variant = data.get(key)
	if not _is_whole(raw) or type_convert(raw, TYPE_INT) < 0:
		errors.append(
			"%s: expected a whole number of 0 or more, got %s" % [label, JSON.stringify(raw)]
		)
		return 0
	return type_convert(raw, TYPE_INT)


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
