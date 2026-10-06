class_name Occupancy
extends RefCounted

var _width: int
var _occupied := PackedByteArray()


func _init(width: int, height: int) -> void:
	_width = width
	_occupied.resize(width * height)


func is_occupied(cell: Vector2i) -> bool:
	return _occupied[cell.y * _width + cell.x] == 1


func occupy(cells: Array[Vector2i]) -> void:
	for cell in cells:
		_occupied[cell.y * _width + cell.x] = 1
