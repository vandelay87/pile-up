## Where the soldiers of one Move order stand when they arrive. A Cluster takes the free cells
## nearest the anchor in the order's field; a Line runs across the direction of travel.
class_name Formations
extends RefCounted

const CLUSTER := &"cluster"
const LINE := &"line"
const ALL: Array[StringName] = [CLUSTER, LINE]
const BAD_FORMATION := "the formation must be cluster or line"


## [param wanted] Line slots centred on [param anchor], across the line from [param from] (the
## selection's mean position) to [param target]. Slots step out 1 cell at a time, alternating
## sides from the centre, skipping cells this line took or [param held] counts; a side ends at
## the first cell a soldier can't stand on or reach from the anchor, or at the map's edge. Once
## both sides end, the next rank forms one cell behind, the same way.
static func line(
	paths: UnitPaths,
	map: MapData,
	anchor: int,
	from: Vector2,
	target: Vector2,
	wanted: int,
	held: PackedInt32Array,
) -> PackedInt32Array:
	var travel := target - from
	travel = Vector2.DOWN if travel.length() < 1e-6 else travel.normalized()
	var across := travel.orthogonal()
	var centre := MapData.centre_of(map.cell_of(anchor))
	var region := paths.regions[anchor]
	var slots := PackedInt32Array()
	var taken: Dictionary[int, bool] = {}
	for rank in maxi(map.width, map.height):
		var rank_centre := centre - travel * rank
		var ended: Array[bool] = [false, false]
		var reach := 0
		while slots.size() < wanted and not (ended[0] and ended[1]):
			for side: int in [0] if reach == 0 else [0, 1]:
				if ended[side] or slots.size() == wanted:
					continue
				var direction := 1.0 if side == 0 else -1.0
				var cell := Vector2i((rank_centre + across * direction * reach).floor())
				if not map.in_bounds(cell):
					ended[side] = true
					continue
				var index := map.index_of(cell)
				if paths.regions[index] != region:
					ended[side] = reach > 0 or ended[side]
					continue
				if taken.has(index) or held[index] > 0:
					continue
				taken[index] = true
				slots.append(index)
			reach += 1
		if slots.size() == wanted:
			break
	return slots
