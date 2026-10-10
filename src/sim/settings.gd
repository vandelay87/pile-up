class_name Settings
extends RefCounted

enum Apply { LIVE, RESTART }

const DEFAULTS_PATH := "res://data/settings/defaults.json"

const SCHEMA := {
	"enemies":
	{
		"hp":
		{
			"type": TYPE_FLOAT,
			"min": 0.5,
			"max": 1000.0,
			"step": 0.5,
			"unit": "HP",
			"apply": Apply.LIVE,
		},
		"bounty":
		{
			"type": TYPE_INT,
			"min": 0,
			"max": 100,
			"step": 1,
			"unit": "gold",
			"apply": Apply.LIVE,
		},
		"separation_radius":
		{
			"type": TYPE_FLOAT,
			"min": 0.05,
			"max": 1.0,
			"step": 0.05,
			"unit": "cells",
			"apply": Apply.LIVE,
		},
		"separation_push":
		{
			"type": TYPE_FLOAT,
			"min": 0.0,
			"max": 1.0,
			"step": 0.05,
			"unit": "overlap/tick",
			"apply": Apply.LIVE,
		},
		"neighbour_cap":
		{
			"type": TYPE_INT,
			"min": 0,
			"max": 64,
			"step": 1,
			"unit": "neighbours (0 = off)",
			"apply": Apply.LIVE,
		},
		"heading_offset":
		{
			"type": TYPE_FLOAT,
			"min": 0.0,
			"max": 45.0,
			"step": 1.0,
			"unit": "degrees",
			"apply": Apply.LIVE,
		},
		"speed":
		{
			"type": TYPE_FLOAT,
			"min": 0.1,
			"max": 10.0,
			"step": 0.1,
			"unit": "cells/s",
			"apply": Apply.LIVE,
		},
		"wall_damage":
		{
			"type": TYPE_FLOAT,
			"min": 0.1,
			"max": 100.0,
			"step": 0.1,
			"unit": "HP/s",
			"apply": Apply.LIVE,
		},
		"wall_reach":
		{
			"type": TYPE_FLOAT,
			"min": 0.0,
			"max": 1.0,
			"step": 0.05,
			"unit": "cells",
			"apply": Apply.LIVE,
		},
		"jam_seconds":
		{
			"type": TYPE_FLOAT,
			"min": 0.05,
			"max": 10.0,
			"step": 0.05,
			"unit": "s",
			"apply": Apply.LIVE,
		},
		"pile_roll_chance":
		{
			"type": TYPE_INT,
			"min": 0,
			"max": 100,
			"step": 1,
			"unit": "percent",
			"apply": Apply.LIVE,
		},
		"wall_roll_chance":
		{
			"type": TYPE_INT,
			"min": 0,
			"max": 100,
			"step": 1,
			"unit": "percent",
			"apply": Apply.LIVE,
		},
		"speed_variety":
		{
			"type": TYPE_INT,
			"min": 0,
			"max": 50,
			"step": 1,
			"unit": "± percent pace, rolled at spawn",
			"apply": Apply.LIVE,
		},
		"wander":
		{
			"type": TYPE_FLOAT,
			"min": 0.0,
			"max": 90.0,
			"step": 1.0,
			"unit": "± degrees of weave",
			"apply": Apply.LIVE,
		},
		"wander_period":
		{
			"type": TYPE_FLOAT,
			"min": 0.5,
			"max": 20.0,
			"step": 0.5,
			"unit": "s per weave",
			"apply": Apply.LIVE,
		},
		"personal_space_radius":
		{
			"type": TYPE_FLOAT,
			"min": 0.0,
			"max": 3.0,
			"step": 0.05,
			"unit": "cells, 0 = off",
			"apply": Apply.LIVE,
		},
		"personal_space_push":
		{
			"type": TYPE_FLOAT,
			"min": 0.0,
			"max": 1.0,
			"step": 0.01,
			"unit": "push per neighbour per tick",
			"apply": Apply.LIVE,
		},
		"turn_back_angle":
		{
			"type": TYPE_FLOAT,
			"min": 0.0,
			"max": 180.0,
			"step": 5.0,
			"unit": "degrees of turn that push through in the wave tail",
			"apply": Apply.LIVE,
		},
	},
	"piles":
	{
		"slow_level_1":
		{
			"type": TYPE_INT,
			"min": 0,
			"max": 95,
			"step": 5,
			"unit": "percent",
			"apply": Apply.LIVE,
		},
		"slow_level_2":
		{
			"type": TYPE_INT,
			"min": 0,
			"max": 95,
			"step": 5,
			"unit": "percent",
			"apply": Apply.LIVE,
		},
		"slow_level_3":
		{
			"type": TYPE_INT,
			"min": 0,
			"max": 95,
			"step": 5,
			"unit": "percent",
			"apply": Apply.LIVE,
		},
		"slow_level_4":
		{
			"type": TYPE_INT,
			"min": 0,
			"max": 95,
			"step": 5,
			"unit": "percent",
			"apply": Apply.LIVE,
		},
		"wall_hp":
		{
			"type": TYPE_FLOAT,
			"min": 1.0,
			"max": 1000.0,
			"step": 1.0,
			"unit": "HP",
			"apply": Apply.LIVE,
		},
		"decay_chance":
		{
			"type": TYPE_INT,
			"min": 0,
			"max": 100,
			"step": 5,
			"unit": "percent",
			"apply": Apply.LIVE,
		},
		"wall_decay_chance":
		{
			"type": TYPE_INT,
			"min": 0,
			"max": 100,
			"step": 5,
			"unit": "percent",
			"apply": Apply.LIVE,
		},
	},
	"routing":
	{
		"sensible_pile_weight":
		{
			"type": TYPE_FLOAT,
			"min": 0.0,
			"max": 5.0,
			"step": 0.05,
			"unit": "weight",
			"apply": Apply.LIVE,
		},
		"sensible_wall_weight":
		{
			"type": TYPE_FLOAT,
			"min": 0.0,
			"max": 5.0,
			"step": 0.05,
			"unit": "weight",
			"apply": Apply.LIVE,
		},
		"direct_pile_weight":
		{
			"type": TYPE_FLOAT,
			"min": 0.0,
			"max": 5.0,
			"step": 0.05,
			"unit": "weight",
			"apply": Apply.LIVE,
		},
		"direct_wall_weight":
		{
			"type": TYPE_FLOAT,
			"min": 0.0,
			"max": 5.0,
			"step": 0.05,
			"unit": "weight",
			"apply": Apply.LIVE,
		},
		"wall_hp_bucket":
		{
			"type": TYPE_FLOAT,
			"min": 1.0,
			"max": 100.0,
			"step": 1.0,
			"unit": "HP",
			"apply": Apply.LIVE,
		},
	},
	"waves":
	{
		"wave_1_size":
		{
			"type": TYPE_INT,
			"min": 1,
			"max": 500,
			"step": 1,
			"unit": "enemies",
			"apply": Apply.RESTART,
		},
		"growth":
		{
			"type": TYPE_FLOAT,
			"min": 1.0,
			"max": 2.0,
			"step": 0.01,
			"unit": "× enemies per wave",
			"apply": Apply.LIVE,
		},
		"hp_growth":
		{
			"type": TYPE_FLOAT,
			"min": 1.0,
			"max": 2.0,
			"step": 0.01,
			"unit": "× HP per wave",
			"apply": Apply.LIVE,
		},
		"spawn_rate":
		{
			"type": TYPE_FLOAT,
			"min": 0.5,
			"max": 120.0,
			"step": 0.5,
			"unit": "enemies/s",
			"apply": Apply.LIVE,
		},
		"second_edge_chance":
		{
			"type": TYPE_INT,
			"min": 0,
			"max": 100,
			"step": 5,
			"unit": "percent",
			"apply": Apply.LIVE,
		},
		"clump_size":
		{
			"type": TYPE_INT,
			"min": 1,
			"max": 50,
			"step": 1,
			"unit": "enemies per spawn burst",
			"apply": Apply.LIVE,
		},
		"wave_tail":
		{
			"type": TYPE_INT,
			"min": 0,
			"max": 500,
			"step": 1,
			"unit": "enemies left when the wave tail starts",
			"apply": Apply.LIVE,
		},
		"wave_tail_per_wave":
		{
			"type": TYPE_INT,
			"min": 0,
			"max": 50,
			"step": 1,
			"unit": "more wave-tail enemies per wave",
			"apply": Apply.LIVE,
		},
	},
	"combo":
	{
		"window":
		{
			"type": TYPE_FLOAT,
			"min": 0.5,
			"max": 10.0,
			"step": 0.5,
			"unit": "s of kills counted",
			"apply": Apply.LIVE,
		},
		"tier_2_kills":
		{
			"type": TYPE_INT,
			"min": 1,
			"max": 500,
			"step": 1,
			"unit": "kills in the window for x2",
			"apply": Apply.LIVE,
		},
		"tier_3_kills":
		{
			"type": TYPE_INT,
			"min": 1,
			"max": 500,
			"step": 1,
			"unit": "kills in the window for x3",
			"apply": Apply.LIVE,
		},
	},
	"towers":
	{
		"damage":
		{
			"type": TYPE_FLOAT,
			"min": 0.5,
			"max": 100.0,
			"step": 0.5,
			"unit": "HP",
			"apply": Apply.LIVE,
		},
		"fire_rate":
		{
			"type": TYPE_FLOAT,
			"min": 0.1,
			"max": 20.0,
			"step": 0.1,
			"unit": "shots/s",
			"apply": Apply.LIVE,
		},
		"range":
		{
			"type": TYPE_FLOAT,
			"min": 1.0,
			"max": 30.0,
			"step": 0.5,
			"unit": "cells",
			"apply": Apply.LIVE,
		},
		"cost":
		{
			"type": TYPE_INT,
			"min": 0,
			"max": 1000,
			"step": 5,
			"unit": "gold",
			"apply": Apply.LIVE,
		},
		"hp":
		{
			"type": TYPE_FLOAT,
			"min": 1.0,
			"max": 1000.0,
			"step": 1.0,
			"unit": "HP",
			"apply": Apply.LIVE,
		},
		"power_area":
		{
			"type": TYPE_INT,
			"min": 0,
			"max": 50,
			"step": 1,
			"unit": "cells from the footprint",
			"apply": Apply.LIVE,
		},
	},
	"pylons":
	{
		"cost":
		{
			"type": TYPE_INT,
			"min": 0,
			"max": 1000,
			"step": 5,
			"unit": "gold",
			"apply": Apply.LIVE,
		},
		"hp":
		{
			"type": TYPE_FLOAT,
			"min": 1.0,
			"max": 1000.0,
			"step": 1.0,
			"unit": "HP",
			"apply": Apply.LIVE,
		},
		"power_area":
		{
			"type": TYPE_INT,
			"min": 0,
			"max": 50,
			"step": 1,
			"unit": "cells from the footprint",
			"apply": Apply.LIVE,
		},
	},
	"repair_yards":
	{
		"cost":
		{
			"type": TYPE_INT,
			"min": 0,
			"max": 1000,
			"step": 5,
			"unit": "gold",
			"apply": Apply.LIVE,
		},
		"hp":
		{
			"type": TYPE_FLOAT,
			"min": 1.0,
			"max": 1000.0,
			"step": 1.0,
			"unit": "HP",
			"apply": Apply.LIVE,
		},
		"power_area":
		{
			"type": TYPE_INT,
			"min": 0,
			"max": 50,
			"step": 1,
			"unit": "cells from the footprint",
			"apply": Apply.LIVE,
		},
		"repair_area":
		{
			"type": TYPE_INT,
			"min": 0,
			"max": 50,
			"step": 1,
			"unit": "cells from the footprint",
			"apply": Apply.LIVE,
		},
		"drone_speed":
		{
			"type": TYPE_FLOAT,
			"min": 0.5,
			"max": 60.0,
			"step": 0.5,
			"unit": "cells/s",
			"apply": Apply.LIVE,
		},
		"repair_rate":
		{
			"type": TYPE_FLOAT,
			"min": 0.5,
			"max": 100.0,
			"step": 0.5,
			"unit": "HP/s",
			"apply": Apply.LIVE,
		},
	},
	"run":
	{
		"base_hp":
		{
			"type": TYPE_INT,
			"min": 1,
			"max": 10000,
			"step": 10,
			"unit": "HP",
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
		"base_power_area":
		{
			"type": TYPE_INT,
			"min": 0,
			"max": 50,
			"step": 1,
			"unit": "cells from the base",
			"apply": Apply.LIVE,
		},
		"map_path": {"type": TYPE_STRING, "unit": "path", "apply": Apply.RESTART},
	},
	"view":
	{
		"tracer_speed":
		{
			"type": TYPE_FLOAT,
			"min": 5.0,
			"max": 200.0,
			"step": 5.0,
			"unit": "cells/s",
			"apply": Apply.LIVE,
		},
	},
}

var enemy_hp: float:
	get:
		return value("enemies", "hp")
var enemy_bounty: int:
	get:
		return value("enemies", "bounty")
var separation_radius: float:
	get:
		return value("enemies", "separation_radius")
var separation_push: float:
	get:
		return value("enemies", "separation_push")
var neighbour_cap: int:
	get:
		return value("enemies", "neighbour_cap")
var heading_offset_radians: float:
	get:
		var degrees: float = value("enemies", "heading_offset")
		return deg_to_rad(degrees)
var enemy_speed: float:
	get:
		return value("enemies", "speed")
var enemy_speed_per_tick: float:
	get:
		return enemy_speed / Simulation.TICKS_PER_SECOND
var wall_damage: float:
	get:
		return value("enemies", "wall_damage")
var wall_damage_per_tick: float:
	get:
		return wall_damage / Simulation.TICKS_PER_SECOND
var wall_reach: float:
	get:
		return value("enemies", "wall_reach")
var jam_ticks: int:
	get:
		var seconds: float = value("enemies", "jam_seconds")
		return ticks_from_seconds(seconds)
var pile_roll_chance: float:
	get:
		var percent: int = value("enemies", "pile_roll_chance")
		return percent / 100.0
var wall_roll_chance: float:
	get:
		var percent: int = value("enemies", "wall_roll_chance")
		return percent / 100.0
var speed_variety: float:
	get:
		var percent: int = value("enemies", "speed_variety")
		return percent / 100.0
var wander_radians: float:
	get:
		var degrees: float = value("enemies", "wander")
		return deg_to_rad(degrees)
var wander_period_ticks: float:
	get:
		var seconds: float = value("enemies", "wander_period")
		return seconds * Simulation.TICKS_PER_SECOND
var personal_space_radius: float:
	get:
		return value("enemies", "personal_space_radius")
var personal_space_push: float:
	get:
		return value("enemies", "personal_space_push")
var turn_back_radians: float:
	get:
		var degrees: float = value("enemies", "turn_back_angle")
		return deg_to_rad(degrees)
var clump_size: int:
	get:
		return value("waves", "clump_size")
var wave_tail: int:
	get:
		return value("waves", "wave_tail")
var wave_tail_per_wave: int:
	get:
		return value("waves", "wave_tail_per_wave")
var wall_hp: float:
	get:
		return value("piles", "wall_hp")
var pile_decay_chance: float:
	get:
		var percent: int = value("piles", "decay_chance")
		return percent / 100.0
var wall_decay_chance: float:
	get:
		var percent: int = value("piles", "wall_decay_chance")
		return percent / 100.0
var wall_hp_bucket: float:
	get:
		return value("routing", "wall_hp_bucket")
var sensible_pile_weight: float:
	get:
		return value("routing", "sensible_pile_weight")
var sensible_wall_weight: float:
	get:
		return value("routing", "sensible_wall_weight")
var direct_pile_weight: float:
	get:
		return value("routing", "direct_pile_weight")
var direct_wall_weight: float:
	get:
		return value("routing", "direct_wall_weight")
var wave_1_size: int:
	get:
		return value("waves", "wave_1_size")
var wave_growth: float:
	get:
		return value("waves", "growth")
var hp_growth: float:
	get:
		return value("waves", "hp_growth")
var spawn_rate: float:
	get:
		return value("waves", "spawn_rate")
var second_edge_chance: float:
	get:
		var percent: int = value("waves", "second_edge_chance")
		return percent / 100.0
var combo_window_ticks: int:
	get:
		var seconds: float = value("combo", "window")
		return ticks_from_seconds(seconds)
var combo_tier_2_kills: int:
	get:
		return value("combo", "tier_2_kills")
var combo_tier_3_kills: int:
	get:
		return value("combo", "tier_3_kills")
var tower_damage: float:
	get:
		return value("towers", "damage")
var tower_cooldown_ticks: int:
	get:
		var per_second: float = value("towers", "fire_rate")
		return interval_ticks(per_second)
var tower_range: float:
	get:
		return value("towers", "range")
var tower_cost: int:
	get:
		return value("towers", "cost")
var tower_hp: float:
	get:
		return value("towers", "hp")
var tower_power_area: int:
	get:
		return value("towers", "power_area")
var pylon_cost: int:
	get:
		return value("pylons", "cost")
var pylon_hp: float:
	get:
		return value("pylons", "hp")
var pylon_power_area: int:
	get:
		return value("pylons", "power_area")
var repair_yard_cost: int:
	get:
		return value("repair_yards", "cost")
var repair_yard_hp: float:
	get:
		return value("repair_yards", "hp")
var repair_yard_power_area: int:
	get:
		return value("repair_yards", "power_area")
var repair_area: int:
	get:
		return value("repair_yards", "repair_area")
## Cells a drone flies per tick.
var drone_step: float:
	get:
		var per_second: float = value("repair_yards", "drone_speed")
		return per_second / Simulation.TICKS_PER_SECOND
## HP a drone repairs per tick.
var repair_per_tick: float:
	get:
		var per_second: float = value("repair_yards", "repair_rate")
		return per_second / Simulation.TICKS_PER_SECOND
var base_power_area: int:
	get:
		return value("run", "base_power_area")
var tracer_speed: float:
	get:
		return value("view", "tracer_speed")
var base_hp: int:
	get:
		return value("run", "base_hp")
var starting_gold: int:
	get:
		return value("run", "starting_gold")
var map_path: String:
	get:
		return value("run", "map_path")

var _schema: Dictionary
var _values: Dictionary
var _restart_values: Dictionary


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
		if not data.has(group):
			errors.append("%s: missing" % group)
			continue
		if data[group] is not Dictionary:
			errors.append("%s: expected an object of settings" % group)
			continue
		var group_data: Dictionary = data[group]
		values[group] = {}
		for key: String in group_data:
			var error := _validation_error(schema, group, key, group_data[key])
			if error.is_empty():
				var entry: Dictionary = entries[key]
				values[group][key] = _coerce(entry, group_data[key])
			else:
				errors.append(error)
		for key: String in entries:
			if not group_data.has(key):
				errors.append("%s.%s: missing" % [group, key])

	if not errors.is_empty():
		return LoadResult.new(null, "\n".join(errors))
	return LoadResult.new(Settings.new(schema, values), "")


static func ticks_from_seconds(seconds: float) -> int:
	return roundi(seconds * Simulation.TICKS_PER_SECOND)


static func interval_ticks(per_second: float) -> int:
	return maxi(1, roundi(Simulation.TICKS_PER_SECOND / per_second))


func pile_slow(level: int) -> float:
	var percent: int = value("piles", "slow_level_%d" % level)
	return percent / 100.0


func value(group: String, key: String) -> Variant:
	return _values[group][key]


func change(group: String, key: String, new_value: Variant) -> String:
	var error := _validation_error(_schema, group, key, new_value)
	if not error.is_empty():
		return error

	var entry: Dictionary = _schema[group][key]
	var target := _values if entry["apply"] == Apply.LIVE else _restart_values
	if not target.has(group):
		target[group] = {}
	target[group][key] = _coerce(entry, new_value)
	return ""


func to_json() -> String:
	var data := {}
	for group: String in _schema:
		var group_data := {}
		for key: String in _schema[group]:
			var raw: Variant = _values[group][key]
			if raw is float:
				var number: float = raw
				if number == roundf(number):
					raw = roundi(number)
			group_data[key] = raw
		data[group] = group_data
	return JSON.stringify(data, "\t", false) + "\n"


func for_next_run() -> Settings:
	var values := _values.duplicate(true)
	for group: String in _restart_values:
		var group_values: Dictionary = values[group]
		var pending_values: Dictionary = _restart_values[group]
		group_values.merge(pending_values, true)
	return Settings.new(_schema, values)


static func _validation_error(
	schema: Dictionary, group: String, key: String, raw: Variant
) -> String:
	var entries: Dictionary = schema.get(group, {})
	if not entries.has(key):
		return "%s.%s: unknown setting" % [group, key]
	var entry: Dictionary = entries[key]
	var error := _type_or_range_error(entry, raw)
	if error.is_empty():
		return ""
	return "%s.%s: %s" % [group, key, error]


static func _type_or_range_error(entry: Dictionary, raw: Variant) -> String:
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
	var steps: float = (coerced - entry["min"]) / entry["step"]
	if not is_equal_approx(steps, roundf(steps)):
		return "%s is not a multiple of %s from %s" % [coerced, entry["step"], entry["min"]]
	return ""


static func _coerce(entry: Dictionary, raw: Variant) -> Variant:
	var type: int = entry["type"]
	return type_convert(raw, type)


static func _describe(raw: Variant) -> String:
	return "%s %s" % [type_string(typeof(raw)), JSON.stringify(raw)]
