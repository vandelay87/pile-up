class_name Occupancy
extends RefCounted

const EMPTY := -1

## The building id on each cell (row-major), or [constant EMPTY].
var building_ids: PackedInt32Array:
	get:
		return _building_ids

var _width: int
var _building_ids := PackedInt32Array()


func _init(width: int, height: int) -> void:
	_width = width
	_building_ids.resize(width * height)
	_building_ids.fill(EMPTY)


func is_occupied(cell: Vector2i) -> bool:
	return building_at(cell) != EMPTY


func building_at(cell: Vector2i) -> int:
	return _building_ids[cell.y * _width + cell.x]


func occupy(cells: Array[Vector2i], building_id: int) -> void:
	for cell in cells:
		_building_ids[cell.y * _width + cell.x] = building_id
