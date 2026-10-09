class_name PileOverlay
extends Node2D

const COLOUR := Color.WHITE
const WALL_HP_COLOUR := Color(1.0, 0.55, 0.45)
const OUTLINE := Color.BLACK
const FONT_SIZE := 12

var _piles: Piles
var _map: MapData
var _shown := false
var _walls := {}
var _wall_hp_layer := Node2D.new()


func _ready() -> void:
	add_child(_wall_hp_layer)
	_wall_hp_layer.draw.connect(_draw_wall_hp)


func setup(simulation: Simulation) -> void:
	_piles = simulation.piles
	_map = simulation.map
	_walls.clear()
	simulation.pile_changed.connect(_on_pile_changed)
	queue_redraw()


func show_labels(shown: bool) -> void:
	_shown = shown
	queue_redraw()
	_wall_hp_layer.queue_redraw()


func _process(_delta: float) -> void:
	if _shown and not _walls.is_empty():
		_wall_hp_layer.queue_redraw()


func _on_pile_changed(cells: Array[Vector2i]) -> void:
	for cell in cells:
		if _piles.level(cell) == Piles.WALL_LEVEL:
			_walls[cell] = true
		else:
			_walls.erase(cell)
	queue_redraw()


func _draw() -> void:
	if not _shown or _piles == null:
		return
	for index in _piles.levels.size():
		var level := _piles.levels[index]
		if level == 0:
			continue
		var cell := Vector2i(index % _map.width, index / _map.width)
		_draw_label(self, _label_top(cell), str(level), COLOUR)


func _draw_wall_hp() -> void:
	if not _shown or _piles == null:
		return
	var line := Vector2(0, FONT_SIZE)
	for cell: Vector2i in _walls:
		var text := "%d HP" % ceili(_piles.wall_hp(cell))
		_draw_label(_wall_hp_layer, _label_top(cell) + line, text, WALL_HP_COLOUR)


func _label_top(cell: Vector2i) -> Vector2:
	var level := _piles.level(cell)
	return GridTransform.cell_to_world(cell) - Vector2(0, Atlas.PILE_SLAB_HEIGHT * level)


static func _draw_label(canvas: CanvasItem, top: Vector2, text: String, colour: Color) -> void:
	var font := ThemeDB.fallback_font
	var size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
	var origin := top + Vector2(-size.x / 2.0, size.y / 4.0)
	canvas.draw_string_outline(
		font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, 3, OUTLINE
	)
	canvas.draw_string(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, colour)
