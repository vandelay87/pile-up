class_name Hud
extends CanvasLayer

const MARGIN := 8.0

var _simulation: Simulation
var _gold := Label.new()
var _lives := Label.new()
var _wave := Label.new()
var _next_wave := Button.new()
var _game_over := PanelContainer.new()
var _reached := Label.new()


func setup(simulation: Simulation) -> void:
	_simulation = simulation
	_simulation.gold_changed.connect(_show_gold)
	_simulation.lives_changed.connect(_show_lives)
	_simulation.phase_changed.connect(_show_phase)
	_simulation.game_over.connect(_show_game_over)
	var run_state := _simulation.run_state
	_show_gold(run_state.gold)
	_show_lives(run_state.lives)
	_show_phase(_simulation.waves.phase)
	_game_over.visible = false


func _ready() -> void:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 24)
	for label: Label in [_gold, _lives, _wave]:
		label.add_theme_constant_override("outline_size", 4)
		label.add_theme_color_override("font_outline_color", Color.BLACK)
		bar.add_child(label)
	_next_wave.text = "Next wave"
	_next_wave.pressed.connect(func() -> void: _send(Commands.NextWave.new()))
	bar.add_child(_next_wave)
	bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE)
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bar.position.y += MARGIN
	add_child(bar)

	var box := VBoxContainer.new()
	var title := Label.new()
	title.text = "Game over"
	title.add_theme_font_size_override("font_size", 32)
	var restart := Button.new()
	restart.text = "Restart"
	restart.pressed.connect(func() -> void: _send(Commands.Restart.new()))
	for control: Control in [title, _reached, restart]:
		box.add_child(control)
	for label: Label in [title, _reached]:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 24)
	margin.add_child(box)
	_game_over.add_child(margin)
	_game_over.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	_game_over.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_game_over.grow_vertical = Control.GROW_DIRECTION_BOTH
	_game_over.visible = false
	add_child(_game_over)


func _show_gold(gold: int) -> void:
	_gold.text = "Gold %d" % gold


func _show_lives(lives: int) -> void:
	_lives.text = "Lives %d" % lives


func _show_phase(phase: Waves.Phase) -> void:
	_wave.text = "Wave %d" % _simulation.run_state.wave
	_next_wave.disabled = phase == Waves.Phase.WAVE


func _show_game_over() -> void:
	_next_wave.disabled = true
	_reached.text = "Reached wave %d" % _simulation.run_state.wave
	_game_over.visible = true


func _send(command: Commands.Command) -> void:
	_simulation.queue_command(command)
