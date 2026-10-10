class_name PowerGridDrawing
extends RefCounted

## Drawing helpers for the power grid, shared by placement and the debug overlay.


## Tints every cell on the grid, one polygon per run of grid cells in a row.
static func tint_grid(canvas: CanvasItem, grid: PowerGrid, map: MapData, colour: Color) -> void:
	for y in map.height:
		var row := y * map.width
		var start := -1
		for x in map.width + 1:
			var on_grid := x < map.width and grid.cells[row + x] == 1
			if on_grid and start < 0:
				start = x
			elif not on_grid and start >= 0:
				canvas.draw_colored_polygon(_corners(Rect2(start, y, x - start, 1)), colour)
				start = -1


static func outline(canvas: CanvasItem, area: Rect2i, colour: Color, width := 1.5) -> void:
	var corners := _corners(Rect2(area))
	corners.append(corners[0])
	canvas.draw_polyline(corners, colour, width)


static func _corners(area: Rect2) -> PackedVector2Array:
	var corners := PackedVector2Array(
		[
			area.position,
			Vector2(area.end.x, area.position.y),
			area.end,
			Vector2(area.position.x, area.end.y)
		]
	)
	return GridTransform.XF * corners
