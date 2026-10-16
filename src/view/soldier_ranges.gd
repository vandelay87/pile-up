class_name SoldierRanges
extends Node2D

## The selected soldiers' ranges as one merged shape, in the colour of a tower's range circle:
## each soldier's range circle at its own elevation, following it as it moves and climbs. The
## circles are drawn solid into a screen-sized mask, and the mask is drawn over the world with a
## fill-and-edge shader, so the union costs one pass whatever the count.

const SHADER := preload("res://src/view/soldier_ranges.gdshader")

var _simulation: Simulation
var _selection: SoldierSelection
var _mask := SubViewport.new()
var _painter := Node2D.new()


func _ready() -> void:
	_mask.transparent_bg = true
	_mask.disable_3d = true
	_mask.gui_disable_input = true
	_mask.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_mask.add_child(_painter)
	add_child(_mask)
	_painter.draw.connect(_paint)
	var shading := ShaderMaterial.new()
	shading.shader = SHADER
	shading.set_shader_parameter("colour", Selection.RANGE)
	material = shading


func setup(simulation: Simulation, selection: SoldierSelection) -> void:
	_simulation = simulation
	_selection = selection


func _process(_delta: float) -> void:
	var shown := _simulation != null and _selection.has_selection()
	_mask.render_target_update_mode = (
		SubViewport.UPDATE_ALWAYS if shown else SubViewport.UPDATE_DISABLED
	)
	if shown:
		var viewport := get_viewport()
		_mask.size = Vector2i(viewport.get_visible_rect().size)
		_mask.canvas_transform = viewport.canvas_transform
		_painter.queue_redraw()
	queue_redraw()


# Into the mask: each selected soldier's range circle, solid, on the ground under it.
func _paint() -> void:
	var soldiers := _simulation.soldiers
	for id in _selection.selected():
		var index := soldiers.index_of(id)
		if index == Soldiers.NONE:
			continue
		var circle := GridTransform.circle(soldiers.positions[index], soldiers.range_of(index))
		# The outline closes on its first point; a polygon needs it once.
		_painter.draw_colored_polygon(circle.slice(0, -1), Color.WHITE)


# The mask laid back over the screen it was drawn from, through the shader.
func _draw() -> void:
	if _simulation == null or not _selection.has_selection():
		return
	draw_set_transform_matrix(get_viewport().canvas_transform.affine_inverse())
	draw_texture(_mask.get_texture(), Vector2.ZERO)
