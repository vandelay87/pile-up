class_name PrototypeBottomHud
extends CanvasLayer
## PROTOTYPE, throwaway (Bottom HUD ticket #96). Three bottom-HUD layouts on the real
## game, cycled with the Left and Right arrow keys or the pill at the top. Start on one
## with `-- --hud=B`. Everything is read from the simulation each frame; nothing here is
## tested or meant to merge. The old top bar and the floating details panel are hidden
## while this layer runs. The combo gauge sits at the top right in every variant.
## Combo prototype (#104): locked to the chosen layout A; Left and Right now cycle the combo
## looks in PrototypeComboView, K fakes kills, G adds gold, and the details show the combo.

signal build_requested(kind: StringName)

const VARIANTS: Array[String] = ["A", "B", "C"]
const NAMES := {
	"A": "StarCraft console",
	"B": "Diablo orbs and belt",
	"C": "Corner clusters, no bar",
}
const GOLD := Color(1.0, 0.85, 0.2)
const HP_RED := Color(0.85, 0.2, 0.2)
const WAVE_BLUE := Color(0.3, 0.55, 0.95)
const PANEL_BG := Color(0.08, 0.09, 0.11, 0.92)
const PANEL_EDGE := Color(0.45, 0.4, 0.3)
const BUILDS := [
	[&"tower", "Tower", "T"],
	[&"pylon", "Pylon", "P"],
	[&"repair_yard", "Repair yard", "R"],
]

var _simulation: Simulation
var _selection: Selection
var _variant := "A"
var _ui: UiRoot
var _root: Control
var _pill_label := Label.new()
var _combo := Label.new()
# Filled by whichever variant is built; read each frame.
var _readouts: Dictionary[StringName, Label] = {}
var _details: Label
var _details_box: Control
var _yard_controls: Control
var _assign: Button
var _next_wave: Button
var _cost_labels: Dictionary[StringName, Button] = {}
var _orbs: Array[Orb] = []
var _wave_peak := 1
var _combo_card: ComboCard
var _combo_text: Label


## PROTOTYPE (#104): the selected tower's combo, drawn large in the current look.
class ComboCard:
	extends Control

	var fx: PrototypeComboView.Fx

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.12, 0.13, 0.16))
		if fx == null:
			return
		if PrototypeComboView.variant == "D":
			PrototypeComboView.draw_combo(self, Vector2(size.x / 2.0, size.y - 30), fx, 1.6, 62, 0.45)
		else:
			PrototypeComboView.draw_combo(self, size / 2.0 + Vector2(0, 30), fx, 2.2, 30)


## A circle filled from the bottom by `fraction`, with text in the middle.
class Orb:
	extends Control

	var fraction := 1.0
	var colour := Color.RED
	var text := ""
	var caption := ""

	func _draw() -> void:
		var r := minf(size.x, size.y) / 2.0
		var c := size / 2.0
		draw_circle(c, r + 3.0, Color(0.55, 0.48, 0.35))
		draw_circle(c, r, Color(0.05, 0.05, 0.06))
		var f := clampf(fraction, 0.0, 1.0)
		if f > 0.0:
			# Arc of the circle below the fill line, closed along the chord.
			var t := 1.0 - 2.0 * f
			var start := asin(clampf(t, -1.0, 1.0))
			var points := PackedVector2Array()
			var steps := 48
			for i in steps + 1:
				var a := lerpf(start, PI - start, float(i) / steps)
				points.append(c + Vector2(cos(a), sin(a)) * r)
			draw_colored_polygon(points, colour)
		draw_arc(c, r * 0.8, PI * 1.15, PI * 1.6, 16, Color(1, 1, 1, 0.18), 3.0)
		var font := get_theme_default_font()
		var big := 22
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, big).x
		draw_string_outline(font, c + Vector2(-w / 2.0, 6), text, HORIZONTAL_ALIGNMENT_LEFT, -1, big, 4, Color.BLACK)
		draw_string(font, c + Vector2(-w / 2.0, 6), text, HORIZONTAL_ALIGNMENT_LEFT, -1, big)
		var small := 12
		var cw := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, small).x
		draw_string_outline(font, c + Vector2(-cw / 2.0, 24), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, small, 3, Color.BLACK)
		draw_string(font, c + Vector2(-cw / 2.0, 24), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, small)


func setup(simulation: Simulation, selection: Selection) -> void:
	_simulation = simulation
	_selection = selection
	_wave_peak = 1


func _ready() -> void:
	layer = 5
	_ui = UiRoot.add_to(self)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hud="):
			var picked := arg.trim_prefix("--hud=").to_upper()
			if picked in VARIANTS:
				pass  # Combo prototype: the HUD stays on the chosen layout A.
	_build_combo()
	_build_pill()
	_build_variant()


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	if key.keycode == KEY_RIGHT:
		_cycle(1)
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_LEFT:
		_cycle(-1)
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_K and PrototypeComboView.instance != null:
		PrototypeComboView.instance.fake_kills = not PrototypeComboView.instance.fake_kills
		_update_pill()
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_G and _simulation != null:
		_simulation.run_state.add_gold(1000)
		get_viewport().set_input_as_handled()


func _cycle(step: int) -> void:
	PrototypeComboView.cycle(step)
	_update_pill()


func _update_pill() -> void:
	var fake := PrototypeComboView.instance != null and PrototypeComboView.instance.fake_kills
	_pill_label.text = (
		"PROTOTYPE combo   %s   (Left / Right)   K fake kills: %s   G +1000 gold"
		% [PrototypeComboView.label(), "on" if fake else "off"]
	)


# --- Shared pieces ---------------------------------------------------------------


func _build_pill() -> void:
	var pill := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.95, 0.2, 0.6)
	style.set_corner_radius_all(14)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	style.shadow_size = 4
	pill.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	var back := Button.new()
	back.text = "<"
	back.flat = true
	back.focus_mode = Control.FOCUS_NONE
	back.pressed.connect(_cycle.bind(-1))
	var forward := Button.new()
	forward.text = ">"
	forward.flat = true
	forward.focus_mode = Control.FOCUS_NONE
	forward.pressed.connect(_cycle.bind(1))
	_pill_label.add_theme_font_size_override("font_size", 13)
	row.add_child(back)
	row.add_child(_pill_label)
	row.add_child(forward)
	pill.add_child(row)
	pill.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE)
	pill.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pill.position.y += 6
	_ui.add_child(pill)


func _build_combo() -> void:
	_combo.add_theme_constant_override("outline_size", 6)
	_combo.add_theme_color_override("font_outline_color", Color.BLACK)
	_combo.add_theme_color_override("font_color", GOLD)
	_combo.add_theme_font_size_override("font_size", 28)
	_combo.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_combo.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE)
	_combo.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_combo.position += Vector2(-16, 10)
	_ui.add_child(_combo)


func _panel_style(radius := 4) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG
	style.border_color = PANEL_EDGE
	style.set_border_width_all(2)
	style.set_corner_radius_all(radius)
	style.set_content_margin_all(8)
	return style


func _panel(radius := 4) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style(radius))
	return panel


func _readout(key: StringName, size := 16, colour := Color.WHITE) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	label.add_theme_constant_override("outline_size", 4)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	_readouts[key] = label
	return label


func _build_button(entry: Array, square: bool) -> Button:
	var button := Button.new()
	var kind: StringName = entry[0]
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(build_requested.emit.bind(kind))
	if square:
		button.custom_minimum_size = Vector2(72, 56)
	_cost_labels[kind] = button
	return button


func _next_wave_button() -> Button:
	_next_wave = Button.new()
	_next_wave.text = "Next wave"
	_next_wave.focus_mode = Control.FOCUS_NONE
	_next_wave.pressed.connect(
		func() -> void: _simulation.queue_command(Commands.NextWave.new())
	)
	return _next_wave


func _details_label() -> Label:
	_details = Label.new()
	_details.add_theme_font_size_override("font_size", 14)
	return _details


func _yard_buttons() -> HBoxContainer:
	var row := HBoxContainer.new()
	_assign = Button.new()
	_assign.text = "Assign"
	_assign.toggle_mode = true
	_assign.focus_mode = Control.FOCUS_NONE
	_assign.toggled.connect(func(on: bool) -> void: _selection.set_assigning(on))
	var clear := Button.new()
	clear.text = "Clear"
	clear.focus_mode = Control.FOCUS_NONE
	clear.pressed.connect(func() -> void: _selection.clear_assignment())
	row.add_child(_assign)
	row.add_child(clear)
	_yard_controls = row
	return row


func _build_variant() -> void:
	if _root != null:
		_root.queue_free()
	_readouts.clear()
	_cost_labels.clear()
	_orbs.clear()
	_details = null
	_details_box = null
	_yard_controls = null
	_assign = null
	_next_wave = null
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_root)
	_ui.move_child(_root, 0)
	match _variant:
		"A":
			_variant_a()
		"B":
			_variant_b()
		"C":
			_variant_c()
	_update_pill()


# --- A: StarCraft console --------------------------------------------------------
# One full-width bar. Status on the left, the selection's details in the middle (always
# there, empty when nothing is selected), a command card of square buttons on the right.


func _variant_a() -> void:
	var bar := _panel(0)
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bar.custom_minimum_size.y = 150
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bar.offset_top = -150
	_root.add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	bar.add_child(row)

	var status := _panel()
	status.custom_minimum_size.x = 230
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	for pair: Array in [
		["Gold", _readout(&"gold", 20, GOLD)],
		["Base", _readout(&"base", 20, Color(1, 0.5, 0.45))],
		["Wave", _readout(&"wave", 16)],
		["Enemies left", _readout(&"left", 16)],
		["Kills", _readout(&"kills", 16)],
	]:
		var name_label := Label.new()
		name_label.text = pair[0]
		name_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.72))
		grid.add_child(name_label)
		var value: Label = pair[1]
		grid.add_child(value)
	status.add_child(grid)
	row.add_child(status)

	var details := _panel()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var details_row := HBoxContainer.new()
	var portrait := ColorRect.new()
	portrait.color = Color(0.2, 0.22, 0.26)
	portrait.custom_minimum_size = Vector2(96, 96)
	portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	details_row.add_child(portrait)
	var text_col := VBoxContainer.new()
	text_col.add_child(_details_label())
	text_col.add_child(_yard_buttons())
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details_row.add_child(text_col)
	_combo_text = Label.new()
	_combo_text.add_theme_font_size_override("font_size", 14)
	_combo_text.add_theme_color_override("font_color", Color(1, 0.88, 0.5))
	_combo_text.custom_minimum_size.x = 170
	details_row.add_child(_combo_text)
	_combo_card = ComboCard.new()
	_combo_card.custom_minimum_size = Vector2(150, 120)
	_combo_card.clip_contents = true
	details_row.add_child(_combo_card)
	details.add_child(details_row)
	row.add_child(details)

	var card := _panel()
	var commands := GridContainer.new()
	commands.columns = 3
	for entry: Array in BUILDS:
		commands.add_child(_build_button(entry, true))
	commands.add_child(Control.new())
	commands.add_child(Control.new())
	var next := _next_wave_button()
	next.custom_minimum_size = Vector2(72, 56)
	next.text = "Next\nwave"
	commands.add_child(next)
	card.add_child(commands)
	row.add_child(card)


# --- B: Diablo orbs and belt -----------------------------------------------------
# A centred belt between two orbs: base HP on the left, the wave draining on the right.
# Gold and the build slots live in the belt. Details pop up above the belt only while
# something is selected.


func _variant_b() -> void:
	var dock := VBoxContainer.new()
	dock.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE)
	dock.grow_horizontal = Control.GROW_DIRECTION_BOTH
	dock.grow_vertical = Control.GROW_DIRECTION_BEGIN
	dock.alignment = BoxContainer.ALIGNMENT_END
	dock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dock)

	var popup := _panel(8)
	popup.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var popup_col := VBoxContainer.new()
	popup_col.add_child(_details_label())
	popup_col.add_child(_yard_buttons())
	popup.add_child(popup_col)
	_details_box = popup
	dock.add_child(popup)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", -14)
	dock.add_child(row)

	var hp_orb := Orb.new()
	hp_orb.colour = HP_RED
	hp_orb.caption = "Base"
	hp_orb.custom_minimum_size = Vector2(124, 124)
	_orbs.append(hp_orb)
	row.add_child(hp_orb)

	var belt := _panel(6)
	belt.size_flags_vertical = Control.SIZE_SHRINK_END
	var belt_col := VBoxContainer.new()
	var strip := HBoxContainer.new()
	strip.alignment = BoxContainer.ALIGNMENT_CENTER
	strip.add_theme_constant_override("separation", 22)
	strip.add_child(_readout(&"gold", 20, GOLD))
	strip.add_child(_readout(&"kills", 14))
	belt_col.add_child(strip)
	var slots := HBoxContainer.new()
	slots.add_theme_constant_override("separation", 6)
	for entry: Array in BUILDS:
		slots.add_child(_build_button(entry, true))
	var next := _next_wave_button()
	next.custom_minimum_size = Vector2(90, 56)
	slots.add_child(next)
	belt_col.add_child(slots)
	belt.add_child(belt_col)
	row.add_child(belt)

	var wave_orb := Orb.new()
	wave_orb.colour = WAVE_BLUE
	wave_orb.custom_minimum_size = Vector2(124, 124)
	_orbs.append(wave_orb)
	row.add_child(wave_orb)

	var spacer := Control.new()
	spacer.custom_minimum_size.y = 4
	dock.add_child(spacer)


# --- C: corner clusters, no bar --------------------------------------------------
# No continuous bar, so the map shows between clusters. Status bottom-left with a base
# HP bar, a hotbar bottom-centre, details bottom-right (only while something is selected).


func _variant_c() -> void:
	var status := _panel(6)
	status.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE)
	status.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var col := VBoxContainer.new()
	col.add_child(_readout(&"gold", 22, GOLD))
	var hp := ProgressBar.new()
	hp.name = "HpBar"
	hp.show_percentage = false
	hp.custom_minimum_size = Vector2(170, 12)
	var fill := StyleBoxFlat.new()
	fill.bg_color = HP_RED
	hp.add_theme_stylebox_override("fill", fill)
	col.add_child(_readout(&"base", 15, Color(1, 0.5, 0.45)))
	col.add_child(hp)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 14)
	line.add_child(_readout(&"wave", 14))
	line.add_child(_readout(&"left", 14))
	col.add_child(line)
	col.add_child(_readout(&"kills", 14))
	status.add_child(col)
	_root.add_child(status)
	status.position += Vector2(10, -10)

	var hotbar := HBoxContainer.new()
	hotbar.add_theme_constant_override("separation", 6)
	for entry: Array in BUILDS:
		var slot := _build_button(entry, true)
		slot.custom_minimum_size = Vector2(84, 64)
		hotbar.add_child(slot)
	var next := _next_wave_button()
	next.custom_minimum_size = Vector2(110, 64)
	next.add_theme_font_size_override("font_size", 18)
	hotbar.add_child(next)
	var hotbar_panel := _panel(6)
	hotbar_panel.add_child(hotbar)
	hotbar_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE)
	hotbar_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hotbar_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_root.add_child(hotbar_panel)
	hotbar_panel.position.y -= 10

	var card := _panel(6)
	var card_col := VBoxContainer.new()
	card_col.add_child(_details_label())
	card_col.add_child(_yard_buttons())
	card.add_child(card_col)
	card.custom_minimum_size.x = 200
	card.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE)
	card.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_details_box = card
	_root.add_child(card)
	card.position += Vector2(-10, -10)


# --- Each frame ------------------------------------------------------------------


func _process(_delta: float) -> void:
	if _simulation == null:
		return
	var run := _simulation.run_state
	var settings := _simulation.settings
	var hp := ceili(run.base_hp)
	var hp_max := settings.base_hp
	var left := _simulation.enemies_left
	if _simulation.waves.phase == Waves.Phase.WAVE:
		_wave_peak = maxi(_wave_peak, left)
	else:
		_wave_peak = maxi(left, 1)
	var texts := {
		&"gold": "%d gold" % run.gold,
		&"base": "%d / %d HP" % [hp, hp_max],
		&"wave": "Wave %d" % run.wave,
		&"left": "%d left" % left,
		&"kills": "%d kills" % run.kills,
	}
	if _variant == "A":
		texts[&"gold"] = "%d" % run.gold
		texts[&"base"] = "%d / %d" % [hp, hp_max]
		texts[&"wave"] = "%d" % run.wave
		texts[&"left"] = "%d" % left
		texts[&"kills"] = "%d" % run.kills
	for key: StringName in _readouts:
		_readouts[key].text = texts[key]
	var bar := _root.find_child("HpBar", true, false) as ProgressBar
	if bar != null:
		bar.max_value = hp_max
		bar.value = run.base_hp
	if _orbs.size() == 2:
		_orbs[0].fraction = run.base_hp / hp_max
		_orbs[0].text = "%d" % hp
		_orbs[1].fraction = float(left) / _wave_peak
		_orbs[1].text = "%d" % left
		_orbs[1].caption = "Wave %d" % run.wave
		for orb in _orbs:
			orb.queue_redraw()

	var costs := {
		&"tower": settings.tower_cost,
		&"pylon": settings.pylon_cost,
		&"repair_yard": settings.repair_yard_cost,
	}
	for entry: Array in BUILDS:
		var kind: StringName = entry[0]
		var button := _cost_labels[kind]
		var cost: int = costs[kind]
		var hotkey: String = entry[2]
		var label: String = entry[1]
		if _variant == "A":
			button.text = "%s\n%d [%s]" % [label.split(" ")[0], cost, hotkey]
		else:
			button.text = "[%s] %s\n%d gold" % [hotkey, label, cost]
		button.modulate = Color.WHITE if run.gold >= cost else Color(1, 0.6, 0.6)
	_next_wave.disabled = (
		_simulation.waves.phase == Waves.Phase.WAVE
		or _simulation.is_decay_rebuild_in_flight()
		or run.is_game_over
	)

	var details := _selection.details_text()
	if details.is_empty():
		_details.text = "Nothing selected.\nClick a building or the base." if _variant == "A" else ""
	else:
		_details.text = details
	if _details_box != null:
		_details_box.visible = not details.is_empty()
	_yard_controls.visible = _selection.is_yard_selected()
	_assign.set_pressed_no_signal(_selection.is_assigning())

	_combo.visible = false  # No top-right combo in v3 (#97).
	_update_pill()
	_show_combo_details()


func _show_combo_details() -> void:
	var building := _simulation.buildings.building(_selection._building_id)
	var tower := building != null and building.kind == Buildings.TOWER and not _selection._base
	_combo_card.visible = tower
	_combo_text.visible = tower
	if not tower:
		return
	var view := PrototypeComboView.instance
	_combo_card.fx = view.fx_of(building.id) if view != null else null
	_combo_card.queue_redraw()
	var tier := PrototypeCombo.tier(building.combo_count)
	var lines: Array[String] = []
	if tier < 2:
		lines.append("Combo x1, %d in the chain" % building.combo_count)
	else:
		lines.append("Combo x%d, %d kills" % [tier, building.combo_count])
	var next := PrototypeCombo.next_of(tier)
	if next >= 0:
		lines.append("Next x%d at %d kills" % [tier + 1, next])
	else:
		lines.append("At the cap")
	if building.combo_ticks > 0:
		lines.append("Chain %.1f s" % (building.combo_ticks / float(Simulation.TICKS_PER_SECOND)))
	var best := building.combo_best
	lines.append("Best x%d, %d kills" % [PrototypeCombo.tier(best), best])
	_combo_text.text = "\n".join(lines)
