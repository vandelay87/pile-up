## The one counter that buildings and soldiers draw their ids from, so a killer id names one
## building or one soldier and never both.
class_name Ids
extends RefCounted

var _next := 0


func next() -> int:
	var id := _next
	_next += 1
	return id
