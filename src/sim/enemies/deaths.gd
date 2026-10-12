class_name Deaths
extends RefCounted

## The enemies the removal step took this tick, in removal order: each one's id, where it died,
## where its body lands, its kind, its killer (the last building to damage it, or Enemies.NONE)
## and whether a blast killed it.

var ids := PackedInt32Array()
var positions := PackedVector2Array()
## Where each body lands: where it died, unless Overflow sends it back the way it came.
var bodies := PackedVector2Array()
var kinds := PackedByteArray()
var killers := PackedInt32Array()
var blasts := PackedByteArray()


## Normal enemies with no killer, dead at the given positions: bodies to queue on piles.
static func bodies_at(dead_at: PackedVector2Array) -> Deaths:
	var deaths := Deaths.new()
	for pos in dead_at:
		deaths.add(Enemies.NONE, pos, Enemies.Kind.NORMAL, Enemies.NONE)
	return deaths


func add(id: int, pos: Vector2, kind: Enemies.Kind, killer: int, by_blast := false) -> void:
	ids.append(id)
	positions.append(pos)
	bodies.append(pos)
	kinds.append(kind)
	killers.append(killer)
	blasts.append(1 if by_blast else 0)


func size() -> int:
	return positions.size()
