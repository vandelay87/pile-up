class_name Deaths
extends RefCounted

## The enemies the removal step took this tick, in removal order: each one's id, where it died,
## where its body lands, its kind, its killer (the last building to damage it, or Enemies.NONE),
## whether a blast killed it and whether it was a bloater whose fuse ran out.

var ids := PackedInt32Array()
var positions := PackedVector2Array()
## Where each body lands: where it died, unless Overflow sends it back the way it came.
var bodies := PackedVector2Array()
var kinds := PackedByteArray()
var killers := PackedInt32Array()
var blasts := PackedByteArray()
var popped := PackedByteArray()


## Normal enemies with no killer, dead at the given positions: bodies to queue on piles.
static func bodies_at(dead_at: PackedVector2Array) -> Deaths:
	var deaths := Deaths.new()
	for pos in dead_at:
		deaths.add(Enemies.NONE, pos, Enemies.Kind.NORMAL, Enemies.NONE)
	return deaths


func add(
	id: int, pos: Vector2, kind: Enemies.Kind, killer: int, by_blast := false, fuse_ran_out := false
) -> void:
	ids.append(id)
	positions.append(pos)
	bodies.append(pos)
	kinds.append(kind)
	killers.append(killer)
	blasts.append(1 if by_blast else 0)
	popped.append(1 if fuse_ran_out else 0)


func size() -> int:
	return positions.size()


## Whether death [param k] leaves a body: a bloater never does, nor does a blast kill.
func leaves_body(k: int) -> bool:
	return kinds[k] != Enemies.Kind.BLOATER and blasts[k] == 0


## Whether death [param k] pays its kind's bounty: all but a bloater that blew itself up.
func pays_bounty(k: int) -> bool:
	return popped[k] == 0
