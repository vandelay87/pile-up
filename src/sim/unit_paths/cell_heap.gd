## A binary min-heap of cells by value, ties to the lowest cell index, so fields settle in the
## same order on every run.
class_name CellHeap
extends RefCounted

var _values := PackedFloat64Array()
var _items := PackedInt32Array()
var _size := 0


func is_empty() -> bool:
	return _size == 0


func push(value: float, item: int) -> void:
	if _size == _values.size():
		_values.resize(maxi(16, _size * 2))
		_items.resize(maxi(16, _size * 2))
	var i := _size
	_size += 1
	while i > 0:
		var up := (i - 1) >> 1
		if not _before(value, item, _values[up], _items[up]):
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
		if (
			child + 1 < _size
			and _before(_values[child + 1], _items[child + 1], _values[child], _items[child])
		):
			child += 1
		if not _before(_values[child], _items[child], last_value, last_item):
			break
		_values[i] = _values[child]
		_items[i] = _items[child]
		i = child
	_values[i] = last_value
	_items[i] = last_item
	return top


static func _before(value: float, item: int, other_value: float, other_item: int) -> bool:
	return value < other_value or (value == other_value and item < other_item)
