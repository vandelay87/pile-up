class_name Hud
extends CanvasLayer

signal build_requested(kind: StringName)

const MARGIN := 8.0
const TOAST_HOLD_SECONDS := 1.5
const TOAST_FADE_SECONDS := 0.5
const COMBO_PULSE_SECONDS := 0.25
const COMBO_FADE_SECONDS := 0.6
const GOLD_FLASH_SECONDS := 0.35
const GOLD_FLASH_COLOUR := Color(1.0, 0.85, 0.2)

var _simulation: Simulation
var _gold := Label.new()
var _base_hp := Label.new()
var _wave := Label.new()
var _enemies_left := Label.new()
var _kills := Label.new()
var _combo := Label.new()
var _combo_tween: Tween
var _gold_tween: Tween
var _shown_tier := 1
var _next_wave := Button.new()
var _tower := Button.new()
var _pylon := Button.new()
var _repair_yard := Button.new()
var _toast := Label.new()
var _toast_tween: Tween
var _game_over := PanelContainer.new()
var _reached := Label.new()
var _run_kills := Label.new()


func setup(simulation: Simulation) -> void:
	_simulation = simulation
	_simulation.gold_changed.connect(_show_gold)
	_simulation.base_hp_changed.connect(_show_base_hp)
	_simulation.phase_changed.connect(_show_phase)
	_simulation.game_over.connect(_show_game_over)
	_simulation.command_rejected.connect(_show_toast)
	_simulation.enemies_left_changed.connect(_show_enemies_left)
	_simulation.kills_changed.connect(_show_kills)
	_simulation.combo_changed.connect(_show_combo)
	_simulation.payout.connect(_flash_gold)
	var run_state := _simulation.run_state
	_show_gold(run_state.gold)
	_show_base_hp(run_state.base_hp)
	_show_enemies_left(_simulation.enemies_left)
	_show_kills(run_state.kills)
	_shown_tier = 1
	_combo.modulate.a = 0.0
	_show_phase(_simulation.waves.phase)
	_game_over.visible = false


func _ready() -> void:
	var ui := UiRoot.add_to(self)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 24)
	for label: Label in [_gold, _base_hp, _wave, _enemies_left, _kills]:
		label.add_theme_constant_override("outline_size", 4)
		label.add_theme_color_override("font_outline_color", Color.BLACK)
		bar.add_child(label)
	_next_wave.text = "Next wave"
	_next_wave.pressed.connect(func() -> void: _send(Commands.NextWave.new()))
	bar.add_child(_next_wave)
	_tower.pressed.connect(build_requested.emit.bind(Buildings.TOWER))
	_pylon.pressed.connect(build_requested.emit.bind(Buildings.PYLON))
	_repair_yard.pressed.connect(build_requested.emit.bind(Buildings.REPAIR_YARD))
	for button: Button in [_tower, _pylon, _repair_yard]:
		button.focus_mode = Control.FOCUS_NONE
		bar.add_child(button)
	bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE)
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bar.position.y += MARGIN
	ui.add_child(bar)

	_combo.add_theme_constant_override("outline_size", 6)
	_combo.add_theme_color_override("font_outline_color", Color.BLACK)
	_combo.add_theme_color_override("font_color", GOLD_FLASH_COLOUR)
	_combo.add_theme_font_size_override("font_size", 28)
	_combo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_combo.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE)
	_combo.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_combo.position.y += MARGIN * 6
	_combo.modulate.a = 0.0
	ui.add_child(_combo)

	var box := VBoxContainer.new()
	var title := Label.new()
	title.text = "Game over"
	title.add_theme_font_size_override("font_size", 32)
	var restart := Button.new()
	restart.text = "Restart"
	restart.pressed.connect(func() -> void: _send(Commands.Restart.new()))
	for control: Control in [title, _reached, _run_kills, restart]:
		box.add_child(control)
	for label: Label in [title, _reached, _run_kills]:
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
	ui.add_child(_game_over)

	_toast.add_theme_constant_override("outline_size", 4)
	_toast.add_theme_color_override("font_outline_color", Color.BLACK)
	_toast.add_theme_color_override("font_color", Color(1.0, 0.55, 0.45))
	_toast.add_theme_font_size_override("font_size", 20)
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_toast.position.y -= MARGIN * 6
	_toast.modulate.a = 0.0
	ui.add_child(_toast)


func _show_gold(gold: int) -> void:
	_gold.text = "Gold %d" % gold
	_tower.text = "Tower (%d gold) [T]" % _simulation.settings.tower_cost
	_pylon.text = "Pylon (%d gold) [P]" % _simulation.settings.pylon_cost
	_repair_yard.text = "Repair yard (%d gold) [R]" % _simulation.settings.repair_yard_cost


func _show_enemies_left(left: int) -> void:
	_enemies_left.text = "Enemies left %d" % left


func _show_kills(kills: int) -> void:
	_kills.text = "Kills %d" % kills


# Hidden at x1; pulses and grows on each tier-up, fades as the tier falls.
func _show_combo(tier: int) -> void:
	var rising := tier > _shown_tier
	_shown_tier = tier
	if _combo_tween != null:
		_combo_tween.kill()
	_combo_tween = create_tween()
	if tier <= 1:
		_combo_tween.tween_property(_combo, "modulate:a", 0.0, COMBO_FADE_SECONDS)
		return
	_combo.text = "Combo x%d" % tier
	_combo.pivot_offset = _combo.get_combined_minimum_size() / 2.0
	var grown := 1.0 + 0.25 * (tier - 1)
	if rising:
		_combo.modulate.a = 1.0
		_combo.scale = Vector2.ONE * grown * 1.4
		(
			_combo_tween
			. tween_property(_combo, "scale", Vector2.ONE * grown, COMBO_PULSE_SECONDS)
			. set_trans(Tween.TRANS_BACK)
			. set_ease(Tween.EASE_OUT)
		)
	else:
		_combo_tween.set_parallel()
		_combo_tween.tween_property(_combo, "modulate:a", 0.6, COMBO_FADE_SECONDS)
		_combo_tween.tween_property(_combo, "scale", Vector2.ONE * grown, COMBO_FADE_SECONDS)


func _flash_gold(_amount: int, _tier: int) -> void:
	if _gold_tween != null:
		_gold_tween.kill()
	_gold.modulate = GOLD_FLASH_COLOUR * 1.3
	_gold_tween = create_tween()
	_gold_tween.tween_property(_gold, "modulate", Color.WHITE, GOLD_FLASH_SECONDS)


func _show_base_hp(hp: float) -> void:
	_base_hp.text = "Base %d HP" % ceili(hp)


func _process(_delta: float) -> void:
	if _simulation == null:
		return
	_next_wave.disabled = (
		_simulation.waves.phase == Waves.Phase.WAVE
		or _simulation.is_decay_rebuild_in_flight()
		or _simulation.run_state.is_game_over
	)


func _show_phase(_phase: Waves.Phase) -> void:
	_wave.text = "Wave %d" % _simulation.run_state.wave


func _show_game_over() -> void:
	_reached.text = "Reached wave %d" % _simulation.run_state.wave
	_run_kills.text = "Kills %d" % _simulation.run_state.kills
	_game_over.visible = true


func _show_toast(reason: String) -> void:
	_toast.text = reason[0].to_upper() + reason.substr(1)
	if _toast_tween != null:
		_toast_tween.kill()
	_toast.modulate.a = 1.0
	_toast_tween = create_tween()
	_toast_tween.tween_interval(TOAST_HOLD_SECONDS)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, TOAST_FADE_SECONDS)


func _send(command: Commands.Command) -> void:
	_simulation.queue_command(command)
