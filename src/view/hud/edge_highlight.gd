class_name EdgeHighlight
extends Node2D

const COLOUR := Color(1.0, 0.55, 0.15, 0.7)
const BAND_CELLS := 2.0
const HOLD_SECONDS := 2.0
const FADE_SECONDS := 1.0

var _map: MapData
var _edges := PackedStringArray()
var _tween: Tween


func setup(map: MapData) -> void:
	_map = map


func announce(edges: PackedStringArray) -> void:
	_edges = edges
	queue_redraw()
	if _tween != null:
		_tween.kill()
	modulate.a = 1.0
	_tween = create_tween()
	_tween.tween_interval(HOLD_SECONDS)
	_tween.tween_property(self, "modulate:a", 0.0, FADE_SECONDS)


func clear() -> void:
	if _tween != null:
		_tween.kill()
	_edges = PackedStringArray()
	queue_redraw()


func _draw() -> void:
	if _map == null:
		return
	var size := Vector2(_map.width, _map.height)
	var bands := {
		"N": Rect2(0.0, 0.0, size.x, BAND_CELLS),
		"E": Rect2(size.x - BAND_CELLS, 0.0, BAND_CELLS, size.y),
		"S": Rect2(0.0, size.y - BAND_CELLS, size.x, BAND_CELLS),
		"W": Rect2(0.0, 0.0, BAND_CELLS, size.y),
	}
	for edge in _edges:
		var band: Rect2 = bands[edge]
		var corners := PackedVector2Array(
			[
				band.position,
				Vector2(band.end.x, band.position.y),
				band.end,
				Vector2(band.position.x, band.end.y)
			]
		)
		draw_colored_polygon(GridTransform.XF * corners, COLOUR)
