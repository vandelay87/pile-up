class_name PileOverlay
extends Node2D

const COLOUR := Color.WHITE
const OUTLINE := Color.BLACK
const FONT_SIZE := 12

var _piles: Piles
var _map: MapData
var _shown := false


func setup(simulation: Simulation) -> void:
	_piles = simulation.piles
	_map = simulation.map
	simulation.pile_changed.connect(func(_cells: Array[Vector2i]) -> void: queue_redraw())
	queue_redraw()


func show_labels(shown: bool) -> void:
	_shown = shown
	queue_redraw()


func _draw() -> void:
	if not _shown or _piles == null:
		return
	var font := ThemeDB.fallback_font
	for index in _piles.levels.size():
		var level := _piles.levels[index]
		if level == 0:
			continue
		var cell := Vector2i(index % _map.width, index / _map.width)
		var top := GridTransform.cell_to_world(cell) - Vector2(0, Atlas.PILE_SLAB_HEIGHT * level)
		var text := str(level)
		var size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
		var origin := top + Vector2(-size.x / 2.0, size.y / 4.0)
		draw_string_outline(
			font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, 3, OUTLINE
		)
		draw_string(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, COLOUR)
