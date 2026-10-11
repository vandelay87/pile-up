class_name StatsReadout
extends CanvasLayer

const MARGIN := 8.0

var _simulation: Simulation
var _label := Label.new()


func setup(simulation: Simulation) -> void:
	_simulation = simulation


func _ready() -> void:
	var ui := UiRoot.add_to(self)
	visible = false
	_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE)
	_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_label.position.x -= MARGIN
	_label.position.y += MARGIN
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label.add_theme_constant_override("outline_size", 4)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	ui.add_child(_label)


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key.pressed and not key.echo and key.keycode == KEY_F2:
		visible = not visible


func _process(_delta: float) -> void:
	if not visible or _simulation == null:
		return
	var now := Time.get_ticks_msec()
	_label.text = (
		"%d fps\n%d enemies\ntick %.2f ms mean, %.2f ms max\ndecay rebuild in flight: %s"
		% [
			Engine.get_frames_per_second(),
			_simulation.enemies.count,
			_simulation.tick_cost.mean_msec(now),
			_simulation.tick_cost.max_msec(now),
			"yes" if _simulation.is_decay_rebuild_in_flight() else "no",
		]
	)
