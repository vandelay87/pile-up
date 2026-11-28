class_name Hud
extends CanvasLayer
## The StarCraft-style console: one full-width bar across the bottom, built in UiRoot units.
## Status on the left, the selection's details in the middle (always there), and a command
## card of square buttons on the right, with the alert strip along the bar's top edge. Toasts sit
## just above the bar; game over is centred.
## With soldiers selected the card swaps to their commands and the details to theirs. Space
## toggles pause; no HUD button takes keyboard focus, so Space always reaches it.

signal build_requested(kind: StringName)

const BAR_HEIGHT := 150.0
const MARGIN := 8.0
const TOAST_HOLD_SECONDS := 1.5
const TOAST_FADE_SECONDS := 0.5
const GOLD_COLOUR := Color(1.0, 0.85, 0.2)
## Aether's cold blue-violet, as the deposits draw it, brightened to read as text.
const AETHER_COLOUR := Color(0.62, 0.56, 1.0)
const PACE_TOOLTIP := "Mining pace: more gold, and more enemies"
const BASE_COLOUR := Color(1.0, 0.5, 0.45)
const NAME_COLOUR := Color(0.7, 0.7, 0.72)
const PANEL_BG := Color(0.08, 0.09, 0.11, 0.92)
const PANEL_EDGE := Color(0.45, 0.4, 0.3)
const PORTRAIT_COLOUR := Color(0.2, 0.22, 0.26)
const UNAFFORDABLE_COLOUR := Color(1.0, 0.6, 0.6)
const TILE_SIZE := Vector2(14, 14)
const FULL_HP_COLOUR := Color(0.35, 0.85, 0.4)
const NO_HP_COLOUR := Color(0.9, 0.25, 0.2)
const COMMAND_SIZE := Vector2(72, 56)
const COMMAND_COLUMNS := 3
## The pace switch's buttons, in order, with each pace's name and the colour it lights in.
const PACES := {
	Miners.Pace.OFF: {"name": "Off", "colour": Color(0.75, 0.75, 0.8)},
	Miners.Pace.LOW: {"name": "Low", "colour": Color(0.5, 0.9, 0.5)},
	Miners.Pace.MEDIUM: {"name": "Med", "colour": Color(1.0, 0.8, 0.35)},
	Miners.Pace.HIGH: {"name": "High", "colour": Color(1.0, 0.45, 0.4)},
}
const PACE_SIZE := Vector2(52, 30)
## The command card's build buttons in grid order.
const COMMANDS: Array[StringName] = [
	Buildings.TOWER, Buildings.GRINDER, Buildings.PYLON, Buildings.REPAIR_YARD, Buildings.BARRACKS
]
const COMMAND_LABELS := {
	Buildings.TOWER: ["Tower", "T"],
	Buildings.GRINDER: ["Grinder", "G"],
	Buildings.PYLON: ["Pylon", "P"],
	Buildings.REPAIR_YARD: ["Repair", "R"],
	Buildings.BARRACKS: ["Barracks", "B"],
}
## A barracks queue slot: queued (click to cancel) or empty.
const QUEUED_SLOT := "■"
const EMPTY_SLOT := "□"
## The targeting modes' names: a tower's toggle, in button order, and the soldier card's.
const TARGETING_NAMES := {
	Enemies.BLOATERS_FIRST: "Bloaters first",
	Enemies.CLOSEST_TO_BASE: "Closest to base",
}

var _simulation: Simulation
var _bar: PanelContainer
var _selection: Selection
var _soldiers: SoldierSelection
var _gold := Label.new()
var _base_hp := Label.new()
var _threat := Label.new()
var _enemies_left := Label.new()
# The row under Threat: Enemies left during a wave, the alert in the quiet.
var _enemies_left_name := Label.new()
var _alert_strip := AlertStrip.new()
var _kills := Label.new()
var _mining := Label.new()
var _aether := Label.new()
var _capacity := Label.new()
var _capacity_name := Label.new()
var _details_title := Label.new()
var _details_lines := VFlowContainer.new()
var _yard_controls := HBoxContainer.new()
var _assign := Button.new()
var _threshold_buttons: Dictionary[int, Button] = {}
var _tower_controls := HBoxContainer.new()
var _targeting_buttons: Dictionary[StringName, Button] = {}
var _barracks_controls := HBoxContainer.new()
var _train := Button.new()
var _slot_buttons: Array[Button] = []
var _pace_buttons: Dictionary[Miners.Pace, Button] = {}
var _stop := Button.new()
var _clear_rally := Button.new()
var _soldier_targeting := Button.new()
var _formation := Button.new()
# The soldier card's buttons and the blanks that fill the build buttons' slots.
var _soldier_commands: Array[Control] = []
var _soldier_tiles := HFlowContainer.new()
var _paused := Label.new()
var _build_buttons: Dictionary[StringName, Button] = {}
var _toast := Label.new()
var _toast_tween: Tween
var _game_over := PanelContainer.new()
var _reached := Label.new()
var _run_kills := Label.new()


func setup(simulation: Simulation, selection: Selection, soldiers: SoldierSelection) -> void:
	_simulation = simulation
	_selection = selection
	_soldiers = soldiers
	_simulation.gold_changed.connect(_show_gold)
	_simulation.base_hp_changed.connect(_show_base_hp)
	_simulation.wave_coming.connect(_show_wave_coming)
	_simulation.wave_started.connect(_show_wave_started)
	_simulation.wave_ended.connect(_show_toast.bind("wave beaten"))
	_simulation.game_over.connect(_show_game_over)
	_simulation.command_rejected.connect(_show_toast)
	_simulation.kills_changed.connect(_show_kills)
	_simulation.pace_changed.connect(_show_pace)
	_simulation.miner_changed.connect(_show_miner_changed)
	_simulation.building_placed.connect(_show_build_buttons.unbind(1))
	_simulation.building_destroyed.connect(_show_build_buttons.unbind(1))
	var run_state := _simulation.run_state
	_show_gold(run_state.gold)
	_show_base_hp(run_state.base_hp)
	_show_kills(run_state.kills)
	_show_pace(_simulation.miners.pace, _simulation.miners.all_dry())
	_game_over.visible = false
	_capacity.visible = false
	_capacity_name.visible = false
	_show_build_buttons()


func _ready() -> void:
	var ui := UiRoot.add_to(self)
	_bar = _panel(0)
	_bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_bar.offset_top = -BAR_HEIGHT
	ui.add_child(_bar)
	# Outside the bar's container, so it isn't laid out with its panels; it follows the bar's top.
	_alert_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(_alert_strip)
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
	restart.focus_mode = Control.FOCUS_NONE
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

	_paused.text = "Paused"
	_paused.add_theme_font_size_override("font_size", 24)
	_paused.add_theme_constant_override("outline_size", 6)
	_paused.add_theme_color_override("font_outline_color", Color.BLACK)
	_paused.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE)
	_paused.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_paused.offset_top = MARGIN
	_paused.visible = false
	ui.add_child(_paused)


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if _simulation == null or not key.pressed or key.echo or key.keycode != KEY_SPACE:
		return
	_send(Commands.SetPaused.new(not _simulation.paused))
	get_viewport().set_input_as_handled()


# Gold, Base HP, Threat, Enemies left (or Alert), Kills, Mining and Aether as a two-column table.
func _status_panel() -> PanelContainer:
	var status := _panel()
	# Wide enough for six-digit values, so the details don't shift as Gold grows.
	status.custom_minimum_size.x = 230
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 0)
	var rows := [
		["Gold", _gold, 18, GOLD_COLOUR],
		["Base HP", _base_hp, 18, BASE_COLOUR],
		["Threat", _threat, 15, Color.WHITE],
		["Alert", _enemies_left, 15, Color.WHITE],
		["Kills", _kills, 15, Color.WHITE],
		["Mining", _mining, 15, GOLD_COLOUR],
		["Aether", _aether, 15, AETHER_COLOUR],
		["Capacity", _capacity, 15, Color.WHITE],
	]
	for entry: Array in rows:
		var name_label := Label.new()
		if entry[1] == _capacity:
			name_label = _capacity_name
		elif entry[1] == _enemies_left:
			name_label = _enemies_left_name
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


# A portrait placeholder, then the selection's title and stats wrapping into columns.
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
	var targeting := ButtonGroup.new()
	for mode: StringName in TARGETING_NAMES:
		var button := Button.new()
		button.text = TARGETING_NAMES[mode]
		button.toggle_mode = true
		button.button_group = targeting
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(func() -> void: _selection.set_tower_targeting(mode))
		_targeting_buttons[mode] = button
		_tower_controls.add_child(button)
	text_column.add_child(_tower_controls)
	_train.text = "Train soldier"
	_train.focus_mode = Control.FOCUS_NONE
	_train.pressed.connect(
		func() -> void: _selection.train(Barracks.BATCH if Input.is_key_pressed(KEY_SHIFT) else 1)
	)
	_barracks_controls.add_child(_train)
	_clear_rally.text = "Clear rally point"
	_clear_rally.focus_mode = Control.FOCUS_NONE
	_clear_rally.tooltip_text = "New soldiers stand beside the barracks"
	_clear_rally.pressed.connect(func() -> void: _selection.clear_rally())
	_barracks_controls.add_child(_clear_rally)
	var queue_label := Label.new()
	queue_label.text = "  Queue"
	queue_label.add_theme_font_size_override("font_size", 14)
	queue_label.add_theme_color_override("font_color", NAME_COLOUR)
	_barracks_controls.add_child(queue_label)
	for slot in Barracks.QUEUE_LENGTH:
		var button := Button.new()
		button.focus_mode = Control.FOCUS_NONE
		button.tooltip_text = "Cancel and refund"
		button.pressed.connect(func() -> void: _selection.cancel_training(slot))
		_slot_buttons.append(button)
		_barracks_controls.add_child(button)
	text_column.add_child(_barracks_controls)
	_soldier_tiles.add_theme_constant_override("h_separation", 3)
	_soldier_tiles.add_theme_constant_override("v_separation", 3)
	text_column.add_child(_soldier_tiles)
	details_row.add_child(text_column)
	details.add_child(details_row)
	return details


# Square build buttons with cost and hotkey, and the pace switch in a row beneath. With soldiers
# selected, the build buttons give way to Stop, targeting and Formation on the top row.
func _command_card() -> PanelContainer:
	var card := _panel()
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	var commands := GridContainer.new()
	commands.columns = COMMAND_COLUMNS
	_stop.text = "Stop\n[S]"
	_stop.pressed.connect(func() -> void: _soldiers.stop())
	_stop.tooltip_text = "Stops the selected soldiers where they stand"
	_soldier_targeting.pressed.connect(func() -> void: _soldiers.flip_targeting())
	_soldier_targeting.tooltip_text = "Which enemy each soldier fires at first"
	_formation.pressed.connect(func() -> void: _soldiers.flip_formation())
	_formation.tooltip_text = "The shape soldiers take when ordered to move"
	_soldier_commands.append_array([_stop, _soldier_targeting, _formation])
	for button: Button in _soldier_commands:
		button.focus_mode = Control.FOCUS_NONE
	for blank in 2:
		_soldier_commands.append(Control.new())
	for control in _soldier_commands:
		control.custom_minimum_size = COMMAND_SIZE
		control.visible = false
		commands.add_child(control)
	for kind: StringName in COMMANDS:
		var button := Button.new()
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = COMMAND_SIZE
		button.pressed.connect(build_requested.emit.bind(kind))
		_build_buttons[kind] = button
		commands.add_child(button)
	column.add_child(commands)
	column.add_child(_pace_switch())
	card.add_child(column)
	return card


# Off / Low / Med / High as one switch: the pace's button lit in its colour.
func _pace_switch() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var group := ButtonGroup.new()
	for pace: Miners.Pace in PACES:
		var button := Button.new()
		button.text = PACES[pace]["name"]
		button.toggle_mode = true
		button.button_group = group
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = PACE_SIZE
		button.pressed.connect(func() -> void: _send(Commands.SetPace.new(pace)))
		_pace_buttons[pace] = button
		row.add_child(button)
	return row


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
	_show_build_buttons()


# Each build button's cost and hotkey, tinted when unaffordable; the barracks' also shows its
# count against the limit, like "3/5", and greys out at the limit.
func _show_build_buttons() -> void:
	var gold := _simulation.run_state.gold
	for kind: StringName in _build_buttons:
		var cost := _simulation.buildings.cost_of(kind)
		var label: Array = COMMAND_LABELS[kind]
		var button := _build_buttons[kind]
		button.text = "%s\n%d [%s]" % [label[0], cost, label[1]]
		button.modulate = Color.WHITE if gold >= cost else UNAFFORDABLE_COLOUR
	var barracks := _simulation.barracks.count()
	var limit := _simulation.settings.barracks_limit
	var button := _build_buttons[Buildings.BARRACKS]
	button.text += " %d/%d" % [barracks, limit]
	button.disabled = barracks >= limit
	button.tooltip_text = _sentence(Buildings.BARRACKS_LIMIT) if button.disabled else ""


# Threat to one decimal; then during a wave Enemies left against the wave's size, like
# "143 / 214", and in the quiet the alert's fill, like "62% · wave coming".
func _show_waves() -> void:
	var waves := _simulation.waves
	_threat.text = "%.1f" % _simulation.threat.value
	_alert_strip.position = _bar.position
	_alert_strip.size = Vector2(_bar.size.x, AlertStrip.HEIGHT)
	_alert_strip.warn_at = _simulation.settings.alert_warn_at
	_alert_strip.in_wave = waves.phase == Waves.Phase.WAVE
	if _alert_strip.in_wave:
		# Full as the wave starts, draining to empty as its last enemy dies.
		_alert_strip.fill = float(waves.enemies_left) / maxi(1, waves.open_size)
		_enemies_left_name.text = "Enemies left"
		_enemies_left.text = "%d / %d" % [waves.enemies_left, waves.open_size]
		return
	_alert_strip.fill = waves.alert
	_enemies_left_name.text = "Alert"
	_enemies_left.text = "%d%%" % floori(waves.alert * 100.0)
	if not waves.next_edges.is_empty():
		_enemies_left.text += " · wave coming"
	elif waves.fill_factor(_simulation.miners.pace, _simulation.miners.all_dry()) == 0.0:
		_enemies_left.text += " · not filling"


func _show_wave_coming(edges: PackedStringArray) -> void:
	_show_toast("wave coming from %s" % ", ".join(edges))


# The wave's size, each special type it brings and its edges, like
# "214 enemies · 3 bloaters · 6 jumpers · from N, E".
func _show_wave_started(edges: PackedStringArray, size: int, specials: Dictionary) -> void:
	var text := "%d enemies" % size
	for kind: String in ["bloaters", "jumpers", "brutes"]:
		var count: int = specials.get(kind, 0)
		if count > 0:
			text += " · %d %s" % [count, kind if count > 1 else kind.trim_suffix("s")]
	_show_toast("%s · from %s" % [text, ", ".join(edges)])


func _show_kills(kills: int) -> void:
	_kills.text = str(kills)


# The pace's button pressed and lit in its colour; the whole switch greyed once locked.
func _show_pace(pace: Miners.Pace, locked: bool) -> void:
	for each: Miners.Pace in _pace_buttons:
		var button := _pace_buttons[each]
		var lit := each == pace
		button.set_pressed_no_signal(lit)
		button.disabled = locked
		button.modulate = PACES[each]["colour"] if lit and not locked else Color.WHITE
		button.tooltip_text = "Every deposit is dry" if locked else PACE_TOOLTIP


func _show_miner_changed(id: int) -> void:
	if id == Miners.BASE and _simulation.miners.is_dry(id):
		_show_toast("base dry")


func _show_base_hp(hp: float) -> void:
	_base_hp.text = "%d / %d" % [ceili(hp), ceili(_simulation.settings.base_hp)]


func _process(_delta: float) -> void:
	if _simulation == null:
		return
	_show_waves()
	_show_capacity()
	_show_mining()
	_show_command_card()
	_show_details()
	_paused.visible = _simulation.paused


# The soldier card while soldiers are selected, else the build menu.
func _show_command_card() -> void:
	var soldiers := _soldiers.has_selection()
	for control in _soldier_commands:
		control.visible = soldiers
	for button: Button in _build_buttons.values():
		button.visible = not soldiers
	if not soldiers:
		return
	# Two lines, like the build buttons: "Bloaters" over "first [A]".
	var targeting := _soldiers.targeting_name()
	var cut := targeting.find(" ")
	if cut == -1:
		_soldier_targeting.text = "%s\n[A]" % targeting
	else:
		_soldier_targeting.text = "%s\n%s [A]" % [targeting.left(cut), targeting.substr(cut + 1)]
	_formation.text = "%s\n[F]" % SoldierSelection.FORMATION_NAMES[_soldiers.formation]


# The gold a second at the current pace, and the Aether mined, rounded down.
func _show_mining() -> void:
	_mining.text = "%.1f/s" % _simulation.miners.gold_rate()
	_aether.text = str(floori(_simulation.run_state.aether_mined))


# Capacity shows from the first barracks on.
func _show_capacity() -> void:
	if not _capacity.visible and _simulation.barracks.count() == 0:
		return
	_capacity.visible = true
	_capacity_name.visible = true
	_capacity.text = "%d/%d" % [_simulation.barracks.used(), _simulation.barracks.capacity()]


func _show_details() -> void:
	var lines := _soldiers.details() if _soldiers.has_selection() else _selection.details()
	if lines.is_empty():
		lines = ["Nothing selected", "Click a soldier, a building or the base."]
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
	_yard_controls.visible = _selection.is_yard_selected()
	_assign.set_pressed_no_signal(_selection.is_assigning())
	var threshold := _selection.yard_threshold()
	for percent in _threshold_buttons:
		_threshold_buttons[percent].set_pressed_no_signal(percent == threshold)
	_tower_controls.visible = _selection.is_tower_selected()
	var mode := _selection.tower_targeting()
	for each: StringName in _targeting_buttons:
		_targeting_buttons[each].set_pressed_no_signal(each == mode)
	_show_barracks_controls()
	_show_soldier_tiles()


# Several soldiers' tiles, one per soldier in selection order, coloured by HP. A click selects
# that soldier alone; shift-click takes it out.
func _show_soldier_tiles() -> void:
	var ids := _soldiers.selected()
	var count := ids.size() if ids.size() > 1 else 0
	_soldier_tiles.visible = count > 0
	while _soldier_tiles.get_child_count() < count:
		_soldier_tiles.add_child(_soldier_tile(_soldier_tiles.get_child_count()))
	for slot in _soldier_tiles.get_child_count():
		var tile := _soldier_tiles.get_child(slot) as Button
		tile.visible = slot < count
		if tile.visible:
			var style := tile.get_theme_stylebox("normal") as StyleBoxFlat
			style.bg_color = NO_HP_COLOUR.lerp(FULL_HP_COLOUR, _soldiers.hp_fraction(slot))


func _soldier_tile(slot: int) -> Button:
	var tile := Button.new()
	tile.focus_mode = Control.FOCUS_NONE
	tile.custom_minimum_size = TILE_SIZE
	var style := StyleBoxFlat.new()
	for state: String in ["normal", "hover", "pressed"]:
		tile.add_theme_stylebox_override(state, style)
	tile.pressed.connect(
		func() -> void: _soldiers.pick(_soldiers.selected()[slot], Input.is_key_pressed(KEY_SHIFT))
	)
	return tile


# Train soldier, greyed with the reason on hover, and one button per queue slot.
func _show_barracks_controls() -> void:
	_barracks_controls.visible = _selection.is_barracks_selected()
	if not _barracks_controls.visible:
		return
	var id := _selection.selected_building().id
	var error := _simulation.barracks.train_error(id)
	_train.disabled = not error.is_empty()
	_train.tooltip_text = (
		_sentence(error) if _train.disabled else "Shift-click queues %d" % Barracks.BATCH
	)
	_clear_rally.disabled = _simulation.barracks.rally_point(id) == Barracks.NO_RALLY
	var queued := _simulation.barracks.queue_of(id).size()
	for slot in _slot_buttons.size():
		_slot_buttons[slot].text = QUEUED_SLOT if slot < queued else EMPTY_SLOT
		_slot_buttons[slot].disabled = slot >= queued


func _show_game_over() -> void:
	_reached.text = "Reached threat %.1f" % _simulation.threat.value
	_run_kills.text = "Kills %d" % _simulation.run_state.kills
	_game_over.visible = true


func _show_toast(reason: String) -> void:
	_toast.text = _sentence(reason)
	# The bar can grow a little past BAR_HEIGHT with its content, so sit above its real top.
	_toast.position.y = _bar.position.y - _toast.get_combined_minimum_size().y - MARGIN
	if _toast_tween != null:
		_toast_tween.kill()
	_toast.modulate.a = 1.0
	_toast_tween = create_tween()
	_toast_tween.tween_interval(TOAST_HOLD_SECONDS)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, TOAST_FADE_SECONDS)


# A reason as a sentence: its first letter upper-cased.
func _sentence(reason: String) -> String:
	return reason[0].to_upper() + reason.substr(1)


func _send(command: Commands.Command) -> void:
	_simulation.queue_command(command)
