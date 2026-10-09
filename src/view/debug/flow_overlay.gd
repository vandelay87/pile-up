class_name FlowOverlay
extends Node2D

const ROUTE_COLOURS: Array[Color] = [Color(0.35, 0.85, 1.0), Color(1.0, 0.6, 0.2)]
const HEAT_NEAR := Color(1.0, 0.25, 0.2, 0.45)
const HEAT_FAR := Color(0.2, 0.3, 1.0, 0.45)
const ARROW_LENGTH := 0.35
const ARROW_HEAD := 0.12

var _routing: Routing
var _map: MapData
var _arrows: Array[bool] = [false, false]
var _heatmaps: Array[bool] = [false, false]


func setup(routing: Routing, map: MapData) -> void:
	_routing = routing
	_map = map
	queue_redraw()


func show_arrows(route: Routing.Route, shown: bool) -> void:
	_arrows[route] = shown
	queue_redraw()


func show_heatmap(route: Routing.Route, shown: bool) -> void:
	_heatmaps[route] = shown
	queue_redraw()


func _draw() -> void:
	if _routing == null:
		return
	for route: Routing.Route in Routing.Route.values():
		if _heatmaps[route]:
			_draw_heatmap(route)
	for route: Routing.Route in Routing.Route.values():
		if _arrows[route]:
			_draw_arrows(route)


func _draw_heatmap(route: Routing.Route) -> void:
	var furthest := 0.0
	for y in _map.height:
		for x in _map.width:
			var value := _routing.value(route, Vector2i(x, y))
			if value != Routing.UNREACHABLE:
				furthest = maxf(furthest, value)
	if furthest == 0.0:
		return
	var points := PackedVector2Array()
	var colours := PackedColorArray()
	var indices := PackedInt32Array()
	for y in _map.height:
		for x in _map.width:
			var cell := Vector2i(x, y)
			var value := _routing.value(route, cell)
			if value == Routing.UNREACHABLE:
				continue
			var first := points.size()
			var corner := Vector2(cell)
			var colour := HEAT_NEAR.lerp(HEAT_FAR, value / furthest)
			for offset: Vector2 in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]:
				points.append(GridTransform.grid_to_world(corner + offset))
				colours.append(colour)
			indices.append_array([first, first + 1, first + 2, first, first + 2, first + 3])
	RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), indices, points, colours)


func _draw_arrows(route: Routing.Route) -> void:
	var segments := PackedVector2Array()
	for y in _map.height:
		for x in _map.width:
			var cell := Vector2i(x, y)
			var direction := _routing.direction(route, cell)
			if direction == Vector2.ZERO:
				continue
			var centre := Vector2(cell) + Vector2(0.5, 0.5)
			var back := centre + direction * (ARROW_LENGTH - ARROW_HEAD)
			var side := direction.orthogonal() * ARROW_HEAD
			var tail := GridTransform.grid_to_world(centre - direction * ARROW_LENGTH)
			var tip := GridTransform.grid_to_world(centre + direction * ARROW_LENGTH)
			var left := GridTransform.grid_to_world(back + side)
			var right := GridTransform.grid_to_world(back - side)
			segments.append_array([tail, tip, tip, left, tip, right])
	draw_multiline(segments, ROUTE_COLOURS[route])
