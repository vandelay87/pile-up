class_name Hud
extends CanvasLayer
## The StarCraft-style console: one full-width bar across the bottom, built in UiRoot units.
## Status on the left, the selection's details in the middle (always there), and a command
## card of square buttons on the right. Toasts sit just above the bar; game over is centred.

signal build_requested(kind: StringName)

const BAR_HEIGHT := 150.0
const MARGIN := 8.0
const TOAST_HOLD_SECONDS := 1.5
const TOAST_FADE_SECONDS := 0.5
const GOLD_FLASH_SECONDS := 0.35
const GOLD_FLASH_COLOUR := Color(1.0, 0.85, 0.2)
## Gold is already drawn gold, so a payout flashes it brighter.
const GOLD_FLASH_BRIGHTNESS := Color(1.8, 1.8, 1.8)
const BASE_COLOUR := Color(1.0, 0.5, 0.45)
const NAME_COLOUR := Color(0.7, 0.7, 0.72)
const PANEL_BG := Color(0.08, 0.09, 0.11, 0.92)
const PANEL_EDGE := Color(0.45, 0.4, 0.3)
const PORTRAIT_COLOUR := Color(0.2, 0.22, 0.26)
const UNAFFORDABLE_COLOUR := Color(1.0, 0.6, 0.6)
const COMBO_RING_SIZE := 96.0
const COMMAND_SIZE := Vector2(72, 56)
const COMMAND_COLUMNS := 3
## The command card's slots in grid order: a building kind, or an empty slot.
const COMMANDS: Array[StringName] = [
	Buildings.TOWER, Buildings.GRINDER, Buildings.PYLON, Buildings.REPAIR_YARD, &""
]
const COMMAND_LABELS := {
	Buildings.TOWER: ["Tower", "T"],
	Buildings.GRINDER: ["Grinder", "G"],
	Buildings.PYLON: ["Pylon", "P"],
	Buildings.REPAIR_YARD: ["Repair", "R"],
}

var _simulation: Simulation
var _bar: PanelContainer
var _selection: Selection
var _gold := Label.new()
var _base_hp := Label.new()
var _wave := Label.new()
var _enemies_left := Label.new()
var _kills := Label.new()
var _gold_tween: Tween
var _combo_view: ComboView
var _combo_ring := ComboRing.new()
var _details_title := Label.new()
var _details_lines := VFlowContainer.new()
var _yard_controls := HBoxContainer.new()
var _assign := Button.new()
var _threshold_buttons: Dictionary[int, Button] = {}
var _next_wave := Button.new()
var _build_buttons: Dictionary[StringName, Button] = {}
var _toast := Label.new()
var _toast_tween: Tween
var _game_over := PanelContainer.new()
var _reached := Label.new()
var _run_kills := Label.new()


## The selected building's combo ring, drawn large in the details.
class ComboRing:
	extends Control

	var ring: ComboView.Ring

	func _draw() -> void:
		if ring != null:
			ComboView.draw_ring(self, size / 2.0, ring, size.y / 36.0, true)


func setup(simulation: Simulation, selection: Selection, combo_view: ComboView) -> void:
	_simulation = simulation
	_selection = selection
	_combo_view = combo_view
	_simulation.gold_changed.connect(_show_gold)
	_simulation.base_hp_changed.connect(_show_base_hp)
	_simulation.phase_changed.connect(_show_phase)
	_simulation.game_over.connect(_show_game_over)
	_simulation.command_rejected.connect(_show_toast)
	_simulation.enemies_left_changed.connect(_show_enemies_left)
	_simulation.kills_changed.connect(_show_kills)
	_simulation.payout.connect(_flash_gold)
	var run_state := _simulation.run_state
	_show_gold(run_state.gold)
	_show_base_hp(run_state.base_hp)
	_show_enemies_left(_simulation.enemies_left)
	_show_kills(run_state.kills)
	_show_phase(_simulation.waves.phase)
	_game_over.visible = false


func _ready() -> void:
	var ui := UiRoot.add_to(self)
	_bar = _panel(0)
	_bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_bar.offset_top = -BAR_HEIGHT
	ui.add_child(_bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.add_child(_status_panel())
	row.add_child(_details_panel())
	row.add_child(_command_card())
	_bar.add_child(row)

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
	_toast.modulate.a = 0.0
	ui.add_child(_toast)


# Gold, Base HP, Wave, Enemies left and Kills as a two-column table.
func _status_panel() -> PanelContainer:
	var status := _panel()
	# Wide enough for six-digit values, so the details don't shift as Gold grows.
	status.custom_minimum_size.x = 230
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 0)
	var rows := [
		["Gold", _gold, 18, GOLD_FLASH_COLOUR],
		["Base HP", _base_hp, 18, BASE_COLOUR],
		["Wave", _wave, 15, Color.WHITE],
		["Enemies left", _enemies_left, 15, Color.WHITE],
		["Kills", _kills, 15, Color.WHITE],
	]
	for entry: Array in rows:
		var name_label := Label.new()
		name_label.text = entry[0]
		name_label.add_theme_font_size_override("font_size", 15)
		name_label.add_theme_color_override("font_color", NAME_COLOUR)
		grid.add_child(name_label)
		var value: Label = entry[1]
		var font_size: int = entry[2]
		var colour: Color = entry[3]
		value.add_theme_font_size_override("font_size", font_size)
		value.add_theme_color_override("font_color", colour)
		value.add_theme_constant_override("outline_size", 4)
		value.add_theme_color_override("font_outline_color", Color.BLACK)
		grid.add_child(value)
	status.add_child(grid)
	return status


# A portrait placeholder, the selection's title and stats wrapping into columns, then its combo
# ring when it can hold one.
func _details_panel() -> PanelContainer:
	var details := _panel()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var details_row := HBoxContainer.new()
	details_row.add_theme_constant_override("separation", 12)
	var portrait := ColorRect.new()
	portrait.color = PORTRAIT_COLOUR
	portrait.custom_minimum_size = Vector2(96, 96)
	portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	details_row.add_child(portrait)
	var text_column := VBoxContainer.new()
	text_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_column.add_theme_constant_override("separation", 2)
	_details_title.add_theme_font_size_override("font_size", 17)
	text_column.add_child(_details_title)
	_details_lines.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_details_lines.add_theme_constant_override("h_separation", 24)
	_details_lines.add_theme_constant_override("v_separation", 0)
	text_column.add_child(_details_lines)
	_assign.text = "Assign"
	_assign.toggle_mode = true
	_assign.toggled.connect(func(on: bool) -> void: _selection.set_assigning(on))
	var clear := Button.new()
	clear.text = "Clear"
	clear.pressed.connect(func() -> void: _selection.clear_assignment())
	for button: Button in [_assign, clear]:
		button.focus_mode = Control.FOCUS_NONE
		_yard_controls.add_child(button)
	var threshold_label := Label.new()
	threshold_label.text = "  Threshold"
	threshold_label.add_theme_font_size_override("font_size", 14)
	threshold_label.add_theme_color_override("font_color", NAME_COLOUR)
	_yard_controls.add_child(threshold_label)
	var thresholds := ButtonGroup.new()
	for percent in RepairYards.THRESHOLDS:
		var button := Button.new()
		button.text = "%d%%" % percent
		button.toggle_mode = true
		button.button_group = thresholds
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(func() -> void: _selection.set_yard_threshold(percent))
		_threshold_buttons[percent] = button
		_yard_controls.add_child(button)
	text_column.add_child(_yard_controls)
	details_row.add_child(text_column)
	_combo_ring.custom_minimum_size = Vector2.ONE * COMBO_RING_SIZE
	_combo_ring.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	details_row.add_child(_combo_ring)
	details.add_child(details_row)
	return details


# Square build buttons with cost and hotkey, then Next wave; empty slots are kept.
func _command_card() -> PanelContainer:
	var card := _panel()
	var commands := GridContainer.new()
	commands.columns = COMMAND_COLUMNS
	for kind: StringName in COMMANDS:
		if kind.is_empty():
			commands.add_child(Control.new())
			continue
		var button := Button.new()
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = COMMAND_SIZE
		button.pressed.connect(build_requested.emit.bind(kind))
		_build_buttons[kind] = button
		commands.add_child(button)
	_next_wave.text = "Next\nwave"
	_next_wave.focus_mode = Control.FOCUS_NONE
	_next_wave.custom_minimum_size = COMMAND_SIZE
	_next_wave.pressed.connect(func() -> void: _send(Commands.NextWave.new()))
	commands.add_child(_next_wave)
	card.add_child(commands)
	return card


func _panel(radius := 4) -> PanelContainer:
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG
	style.border_color = PANEL_EDGE
	style.set_border_width_all(2)
	style.set_corner_radius_all(radius)
	style.set_content_margin_all(6)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _show_gold(gold: int) -> void:
	_gold.text = str(gold)
	for kind: StringName in _build_buttons:
		var cost := _simulation.buildings.cost_of(kind)
		var label: Array = COMMAND_LABELS[kind]
		var button := _build_buttons[kind]
		button.text = "%s\n%d [%s]" % [label[0], cost, label[1]]
		button.modulate = Color.WHITE if gold >= cost else UNAFFORDABLE_COLOUR


func _show_enemies_left(left: int) -> void:
	_enemies_left.text = str(left)


func _show_kills(kills: int) -> void:
	_kills.text = str(kills)


func _flash_gold(_amount: int, _tier: int) -> void:
	if _gold_tween != null:
		_gold_tween.kill()
	_gold.modulate = GOLD_FLASH_BRIGHTNESS
	_gold_tween = create_tween()
	_gold_tween.tween_property(_gold, "modulate", Color.WHITE, GOLD_FLASH_SECONDS)


func _show_base_hp(hp: float) -> void:
	_base_hp.text = "%d / %d" % [ceili(hp), ceili(_simulation.settings.base_hp)]


func _process(_delta: float) -> void:
	if _simulation == null:
		return
	_next_wave.disabled = (
		_simulation.waves.phase == Waves.Phase.WAVE
		or _simulation.is_decay_rebuild_in_flight()
		or _simulation.run_state.is_game_over
	)
	_show_details()


func _show_details() -> void:
	var lines := _selection.details()
	if lines.is_empty():
		lines = ["Nothing selected", "Click a building or the base."]
	_details_title.text = lines[0]
	var stats := lines.slice(1)
	for i in stats.size():
		if i == _details_lines.get_child_count():
			var line := Label.new()
			line.add_theme_font_size_override("font_size", 14)
			_details_lines.add_child(line)
		var label := _details_lines.get_child(i) as Label
		label.text = stats[i]
		label.visible = true
	for i in range(stats.size(), _details_lines.get_child_count()):
		(_details_lines.get_child(i) as Label).visible = false
	_show_combo_ring()
	_yard_controls.visible = _selection.is_yard_selected()
	_assign.set_pressed_no_signal(_selection.is_assigning())
	var threshold := _selection.yard_threshold()
	for percent in _threshold_buttons:
		_threshold_buttons[percent].set_pressed_no_signal(percent == threshold)


# A tower's or grinder's ring, in pale gold at x1 rather than hidden, so its progress towards
# x2 shows.
func _show_combo_ring() -> void:
	var building := _selection.selected_building()
	_combo_ring.visible = (
		building != null and building.kind in [Buildings.TOWER, Buildings.GRINDER]
	)
	if not _combo_ring.visible:
		return
	_combo_ring.ring = _combo_view.ring_of(building.id)
	if _combo_ring.ring == null:
		_combo_ring.ring = ComboView.Ring.new()
	_combo_ring.queue_redraw()


func _show_phase(_phase: Waves.Phase) -> void:
	_wave.text = str(_simulation.run_state.wave)


func _show_game_over() -> void:
	_reached.text = "Reached wave %d" % _simulation.run_state.wave
	_run_kills.text = "Kills %d" % _simulation.run_state.kills
	_game_over.visible = true


func _show_toast(reason: String) -> void:
	_toast.text = reason[0].to_upper() + reason.substr(1)
	# The bar can grow a little past BAR_HEIGHT with its content, so sit above its real top.
	_toast.position.y = _bar.position.y - _toast.get_combined_minimum_size().y - MARGIN
	if _toast_tween != null:
		_toast_tween.kill()
	_toast.modulate.a = 1.0
	_toast_tween = create_tween()
	_toast_tween.tween_interval(TOAST_HOLD_SECONDS)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, TOAST_FADE_SECONDS)


func _send(command: Commands.Command) -> void:
	_simulation.queue_command(command)
