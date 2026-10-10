# Pile level labels, and the structure HP overlay: remaining HP on walls, buildings and the
# base, read each frame.
class_name PileOverlay
extends Node2D

const COLOUR := Color.WHITE
const HP_COLOUR := Color(1.0, 0.55, 0.45)
const OUTLINE := Color.BLACK
const FONT_SIZE := 12
const BUILDING_LABEL_HEIGHT := 48.0
const BASE_LABEL_HEIGHT := 32.0

var _simulation: Simulation
var _piles: Piles
var _map: MapData
var _shown := false
var _hp_shown := false
var _walls := {}
var _hp_layer := Node2D.new()


func _ready() -> void:
	add_child(_hp_layer)
	_hp_layer.draw.connect(_draw_structure_hp)


func setup(simulation: Simulation) -> void:
	_simulation = simulation
	_piles = simulation.piles
	_map = simulation.map
	_walls.clear()
	simulation.pile_changed.connect(_on_pile_changed)
	queue_redraw()
	_hp_layer.queue_redraw()


func show_labels(shown: bool) -> void:
	_shown = shown
	queue_redraw()
	_hp_layer.queue_redraw()


func show_structure_hp(shown: bool) -> void:
	_hp_shown = shown
	_hp_layer.queue_redraw()


func _process(_delta: float) -> void:
	if _hp_shown:
		_hp_layer.queue_redraw()


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


func _draw_structure_hp() -> void:
	if not _hp_shown or _simulation == null:
		return
	# Below the pile level label when both are shown.
	var line := Vector2(0, FONT_SIZE) if _shown else Vector2.ZERO
	for cell: Vector2i in _walls:
		_draw_hp(_label_top(cell) + line, _piles.wall_hp(cell))
	for building in _simulation.buildings.built:
		var top := GridTransform.grid_to_world(building.centre) + Vector2.UP * BUILDING_LABEL_HEIGHT
		_draw_hp(top, building.hp)
	var base := Rect2(_map.base)
	var base_top := GridTransform.grid_to_world(base.get_center()) + Vector2.UP * BASE_LABEL_HEIGHT
	_draw_hp(base_top, _simulation.run_state.base_hp)


func _draw_hp(top: Vector2, hp: float) -> void:
	_draw_label(_hp_layer, top, "%d HP" % ceili(hp), HP_COLOUR)


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
