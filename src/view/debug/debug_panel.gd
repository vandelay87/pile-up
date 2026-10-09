class_name DebugPanel
extends CanvasLayer

const WIDTH := 400.0
const CHANGED_COLOUR := Color(1.0, 0.75, 0.3)
const RESTART_COLOUR := Color(0.6, 0.6, 0.65)
const ERROR_COLOUR := Color(1.0, 0.45, 0.4)

var _simulation: Simulation
var _file_settings: Settings
var _rows: Array[Row] = []
var _status := Label.new()
var _overlays := VBoxContainer.new()
var _box := VBoxContainer.new()


class Row:
	extends RefCounted

	signal edited

	var group: String
	var key: String
	var name_label := Label.new()
	var editor := HBoxContainer.new()
	var _type: int
	var _range: Range
	var _line_edit: LineEdit

	func _init(row_group: String, row_key: String, entry: Dictionary, initial: Variant) -> void:
		group = row_group
		key = row_key
		_type = entry["type"]
		name_label.text = key.capitalize()
		name_label.tooltip_text = entry["unit"]
		name_label.mouse_filter = Control.MOUSE_FILTER_PASS
		if _type == TYPE_STRING:
			_line_edit = LineEdit.new()
			_line_edit.text = initial
			_line_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_line_edit.text_submitted.connect(func(_text: String) -> void: edited.emit())
			editor.add_child(_line_edit)
		else:
			var slider := HSlider.new()
			slider.min_value = entry["min"]
			slider.max_value = entry["max"]
			slider.step = entry["step"]
			slider.value = initial
			slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			var field := SpinBox.new()
			slider.share(field)
			slider.value_changed.connect(func(_number: float) -> void: edited.emit())
			_range = slider
			editor.add_child(slider)
			editor.add_child(field)

	func value() -> Variant:
		if _line_edit != null:
			return _line_edit.text
		return type_convert(_range.value, _type)

	func reset_to(file_value: Variant) -> void:
		if _line_edit != null:
			_line_edit.text = file_value
			edited.emit()
		else:
			_range.value = file_value

	func highlight(file_value: Variant) -> void:
		var changed: bool
		if _range != null:
			var file_number: float = file_value
			changed = not is_equal_approx(_range.value, file_number)
		else:
			changed = _line_edit.text != file_value
		if changed:
			name_label.add_theme_color_override("font_color", CHANGED_COLOUR)
		else:
			name_label.remove_theme_color_override("font_color")


func setup(simulation: Simulation) -> void:
	_simulation = simulation
	_file_settings = Settings.load_file(Settings.DEFAULTS_PATH).settings
	_simulation.command_rejected.connect(_show_status.bind(ERROR_COLOUR))
	_add_time_controls()
	_add_cheats()
	_box.add_child(_section("Overlays", _overlays))
	_add_settings()
	_add_save()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_box.add_child(_status)


func add_overlay(label: String, toggled: Callable) -> void:
	var check := CheckBox.new()
	check.text = label
	check.toggled.connect(toggled)
	_overlays.add_child(check)


func _ready() -> void:
	visible = false
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	panel.custom_minimum_size.x = WIDTH
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_box)
	panel.add_child(scroll)
	add_child(panel)


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key.pressed and not key.echo and key.keycode == KEY_F1:
		visible = not visible


func _add_time_controls() -> void:
	var row := HBoxContainer.new()
	var pause := Button.new()
	pause.text = "Pause"
	pause.toggle_mode = true
	pause.toggled.connect(func(pressed: bool) -> void: _send(Commands.SetPaused.new(pressed)))
	row.add_child(pause)
	var step := Button.new()
	step.text = "Step"
	step.pressed.connect(func() -> void: _send(Commands.StepOneTick.new()))
	row.add_child(step)
	var speeds := ButtonGroup.new()
	for speed in Simulation.SPEEDS:
		var button := Button.new()
		button.text = "×%d" % speed
		button.toggle_mode = true
		button.button_group = speeds
		button.button_pressed = speed == _simulation.speed
		button.pressed.connect(func() -> void: _send(Commands.SetSpeed.new(speed)))
		row.add_child(button)
	_box.add_child(row)


func _add_cheats() -> void:
	var gold := _number_field(0, 10000, 10, 100)
	var add_gold := Button.new()
	add_gold.text = "Add gold"
	add_gold.pressed.connect(func() -> void: _send(Commands.AddGold.new(roundi(gold.value))))
	var wave := _number_field(1, 99, 1, 1)
	var jump := Button.new()
	jump.text = "Jump to wave"
	jump.pressed.connect(func() -> void: _send(Commands.JumpToWave.new(roundi(wave.value))))
	var row := HBoxContainer.new()
	for control: Control in [gold, add_gold, wave, jump]:
		row.add_child(control)
	_box.add_child(row)


func _add_settings() -> void:
	var current := _simulation.settings.for_next_run()
	for group: String in Settings.SCHEMA:
		var group_box := VBoxContainer.new()
		var entries: Dictionary = Settings.SCHEMA[group]
		for key: String in entries:
			var entry: Dictionary = entries[key]
			group_box.add_child(_setting_row(group, key, entry, current.value(group, key)))
		_box.add_child(_section(group.capitalize(), group_box))


func _setting_row(group: String, key: String, entry: Dictionary, value: Variant) -> Control:
	var row := Row.new(group, key, entry, value)
	row.edited.connect(_change.bind(row))

	var header := HBoxContainer.new()
	header.add_child(row.name_label)
	if entry["apply"] == Settings.Apply.RESTART:
		var restart := Label.new()
		restart.text = "applies on restart"
		restart.add_theme_color_override("font_color", RESTART_COLOUR)
		header.add_child(restart)

	var reset := Button.new()
	reset.text = "Reset"
	reset.pressed.connect(func() -> void: row.reset_to(_file_value(row)))
	row.editor.add_child(reset)

	_rows.append(row)
	row.highlight(_file_value(row))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.add_child(header)
	box.add_child(row.editor)
	return box


func _add_save() -> void:
	var save := Button.new()
	save.text = "Save to defaults.json"
	if OS.has_feature("editor"):
		save.pressed.connect(_save)
	else:
		save.disabled = true
		save.tooltip_text = "Only available when running from the project folder"
	_box.add_child(save)


func _change(row: Row) -> void:
	_send(Commands.SetSetting.new(row.group, row.key, row.value()))
	row.highlight(_file_value(row))


func _file_value(row: Row) -> Variant:
	return _file_settings.value(row.group, row.key)


func _save() -> void:
	var file := FileAccess.open(Settings.DEFAULTS_PATH, FileAccess.WRITE)
	if file == null:
		_show_status("Save failed: %s" % error_string(FileAccess.get_open_error()), ERROR_COLOUR)
		return
	file.store_string(_simulation.settings.for_next_run().to_json())
	file.close()
	_file_settings = Settings.load_file(Settings.DEFAULTS_PATH).settings
	for row in _rows:
		row.highlight(_file_value(row))
	_show_status("Saved %s" % Settings.DEFAULTS_PATH, Color.WHITE)


func _send(command: Commands.Command) -> void:
	_simulation.queue_command(command)


func _show_status(message: String, colour: Color) -> void:
	_status.text = message
	_status.add_theme_color_override("font_color", colour)


func _section(title: String, content: Control) -> FoldableContainer:
	var section := FoldableContainer.new()
	section.title = title
	section.add_child(content)
	return section


func _number_field(min_value: float, max_value: float, step: float, value: float) -> SpinBox:
	var field := SpinBox.new()
	field.min_value = min_value
	field.max_value = max_value
	field.step = step
	field.value = value
	return field
