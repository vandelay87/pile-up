class_name UiRoot
extends Control
## Full-screen root for one UI CanvasLayer's controls. It scales its layer with the
## window and keeps itself sized to the window in unscaled UI units, so children
## anchor to the window's edges at any scale. The world's zoom is untouched.
##
## Usage: in a CanvasLayer, `var ui := UiRoot.add_to(self)`, then add controls to `ui`.

## The window size the UI is laid out for: at this size the scale is 1.
const REFERENCE_SIZE := Vector2(1152.0, 648.0)
## Below this the UI would be too small to read; a smaller window clips instead.
const MIN_SCALE := 0.5


static func add_to(layer: CanvasLayer) -> UiRoot:
	var root := UiRoot.new()
	root.name = "UiRoot"
	layer.add_child(root)
	return root


## The scale that fits a UI laid out for REFERENCE_SIZE into a window of this size.
static func scale_for(window_size: Vector2) -> float:
	var fit := minf(window_size.x / REFERENCE_SIZE.x, window_size.y / REFERENCE_SIZE.y)
	return maxf(fit, MIN_SCALE)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_viewport().size_changed.connect(_fit)
	_fit()


func _fit() -> void:
	var layer := get_parent() as CanvasLayer
	var window_size := get_viewport().get_visible_rect().size
	var ui_scale := scale_for(window_size)
	layer.scale = Vector2(ui_scale, ui_scale)
	position = Vector2.ZERO
	size = window_size / ui_scale
