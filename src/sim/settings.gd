class_name Settings
extends RefCounted

enum Apply { LIVE, RESTART }

const DEFAULTS_PATH := "res://data/settings/defaults.json"
const TICKS_PER_SECOND := 60

const SCHEMA := {
	"run":
	{
		"starting_lives":
		{
			"type": TYPE_INT,
			"min": 1,
			"max": 100,
			"step": 1,
			"unit": "lives",
			"apply": Apply.RESTART,
		},
		"starting_gold":
		{
			"type": TYPE_INT,
			"min": 0,
			"max": 10000,
			"step": 10,
			"unit": "gold",
			"apply": Apply.RESTART,
		},
		"map_path": {"type": TYPE_STRING, "unit": "path", "apply": Apply.RESTART},
	},
}

var starting_lives: int:
	get:
		return value("run", "starting_lives")
var starting_gold: int:
	get:
		return value("run", "starting_gold")
var map_path: String:
	get:
		return value("run", "map_path")

var _schema: Dictionary
var _values: Dictionary
var _pending: Dictionary


class LoadResult:
	extends RefCounted

	var settings: Settings
	var error: String

	func _init(loaded: Settings, message: String) -> void:
		settings = loaded
		error = message


func _init(schema: Dictionary, values: Dictionary) -> void:
	_schema = schema
	_values = values


static func load_file(path: String) -> LoadResult:
	if not FileAccess.file_exists(path):
		return LoadResult.new(null, "%s: file not found" % path)
	var result := from_json(FileAccess.get_file_as_string(path))
	if not result.error.is_empty():
		result.error = "%s:\n%s" % [path, result.error]
	return result


static func from_json(text: String, schema: Dictionary = SCHEMA) -> LoadResult:
	var json := JSON.new()
	if json.parse(text) != OK:
		return LoadResult.new(
			null, "invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()]
		)
	if json.data is not Dictionary:
		return LoadResult.new(null, "expected a JSON object of setting groups")

	var data: Dictionary = json.data
	var errors := PackedStringArray()
	var values := {}
	for group: String in data:
		if not schema.has(group):
			errors.append("%s: unknown group" % group)
	for group: String in schema:
		var entries: Dictionary = schema[group]
		if data.get(group) is not Dictionary:
			errors.append("%s: missing" % group)
			continue
		var group_data: Dictionary = data[group]
		for key: String in group_data:
			if not entries.has(key):
				errors.append("%s.%s: unknown setting" % [group, key])
		values[group] = {}
		for key: String in entries:
			if not group_data.has(key):
				errors.append("%s.%s: missing" % [group, key])
				continue
			var entry: Dictionary = entries[key]
			var error := _check(entry, group_data[key])
			if not error.is_empty():
				errors.append("%s.%s: %s" % [group, key, error])
				continue
			values[group][key] = _coerce(entry, group_data[key])

	if not errors.is_empty():
		return LoadResult.new(null, "\n".join(errors))
	return LoadResult.new(Settings.new(schema, values), "")


static func ticks_from_seconds(seconds: float) -> int:
	return roundi(seconds * TICKS_PER_SECOND)


static func interval_ticks(per_second: float) -> int:
	return maxi(1, roundi(TICKS_PER_SECOND / per_second))


func value(group: String, key: String) -> Variant:
	return _values[group][key]


func change(group: String, key: String, new_value: Variant) -> String:
	var entries: Dictionary = _schema.get(group, {})
	if not entries.has(key):
		return "%s.%s: unknown setting" % [group, key]
	var entry: Dictionary = entries[key]
	var error := _check(entry, new_value)
	if not error.is_empty():
		return "%s.%s: %s" % [group, key, error]

	var target := _values if entry["apply"] == Apply.LIVE else _pending
	if not target.has(group):
		target[group] = {}
	target[group][key] = _coerce(entry, new_value)
	return ""


func for_next_run() -> Settings:
	var values := _values.duplicate(true)
	for group: String in _pending:
		var group_values: Dictionary = values[group]
		var pending_values: Dictionary = _pending[group]
		group_values.merge(pending_values, true)
	return Settings.new(_schema, values)


static func _check(entry: Dictionary, raw: Variant) -> String:
	var type: int = entry["type"]
	match type:
		TYPE_INT:
			var is_whole_float := false
			if raw is float:
				var number: float = raw
				is_whole_float = number == roundf(number)
			if raw is not int and not is_whole_float:
				return "expected int, got %s" % _describe(raw)
		TYPE_FLOAT:
			if raw is not int and raw is not float:
				return "expected float, got %s" % _describe(raw)
		TYPE_STRING:
			if raw is not String:
				return "expected string, got %s" % _describe(raw)
			return ""
	var coerced: Variant = _coerce(entry, raw)
	if coerced < entry["min"] or coerced > entry["max"]:
		return "%s is outside %s to %s" % [coerced, entry["min"], entry["max"]]
	return ""


static func _coerce(entry: Dictionary, raw: Variant) -> Variant:
	var type: int = entry["type"]
	return type_convert(raw, type)


static func _describe(raw: Variant) -> String:
	return "%s %s" % [type_string(typeof(raw)), JSON.stringify(raw)]
