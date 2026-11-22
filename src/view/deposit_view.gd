class_name DepositView
extends Node2D

## Each rig deposit's 3×3 cells tinted in its mix's colours: gold, with a share of cells in a cold
## blue-violet for its Aether. The base's deposit isn't drawn: the base stands on it.

const GOLD := Color(0.95, 0.72, 0.18, 0.6)
const AETHER := Color(0.5, 0.42, 1.0, 0.7)
# Aether is scarcer than gold, so its share of cells is doubled to read at a glance: a deposit
# with any Aether shows at least one cell of it.
const AETHER_WEIGHT := 2.0
# The order cells turn Aether-coloured: the centre, then the corners, then the edges.
const AETHER_ORDER: Array[Vector2i] = [
	Vector2i(1, 1),
	Vector2i(0, 0),
	Vector2i(2, 2),
	Vector2i(2, 0),
	Vector2i(0, 2),
	Vector2i(1, 0),
	Vector2i(1, 2),
	Vector2i(0, 1),
	Vector2i(2, 1),
]

var _map: MapData


func setup(map: MapData) -> void:
	_map = map
	queue_redraw()


## How many of a deposit's 9 cells are drawn in Aether's colour.
static func aether_cells(gold: int, aether: int) -> int:
	if aether <= 0:
		return 0
	var share := float(aether) / (gold + aether)
	return clampi(roundi(AETHER_ORDER.size() * share * AETHER_WEIGHT), 1, AETHER_ORDER.size())


func _draw() -> void:
	if _map == null:
		return
	for deposit in _map.deposits:
		var aether_offsets := AETHER_ORDER.slice(0, aether_cells(deposit.gold, deposit.aether))
		for y in deposit.area.size.y:
			for x in deposit.area.size.x:
				var colour := AETHER if Vector2i(x, y) in aether_offsets else GOLD
				var cell := Rect2i(deposit.area.position + Vector2i(x, y), Vector2i.ONE)
				PowerGridDrawing.tint_area(self, cell, _map, colour)
