class_name SoldierDeaths
extends RefCounted

## The soldiers the removal step took this tick, in removal order: each one's id, where it fell
## and whether a blast killed it.

var ids := PackedInt32Array()
var positions := PackedVector2Array()
var blasts := PackedByteArray()


func add(id: int, pos: Vector2, by_blast: bool) -> void:
	ids.append(id)
	positions.append(pos)
	blasts.append(1 if by_blast else 0)


func size() -> int:
	return ids.size()


func is_empty() -> bool:
	return ids.is_empty()


## A body for each soldier that leaves one, where it fell: all but a blast kill, so the crater
## stays clear.
func bodies() -> Deaths:
	var fell := PackedVector2Array()
	for k in size():
		if blasts[k] == 0:
			fell.append(positions[k])
	return Deaths.bodies_at(fell)
