class_name SettingsSchema
extends RefCounted

## Every setting, by group: its type, range, step, unit and whether a change applies live or
## at the next restart. Settings validates against it and the debug panel is built from it.

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
			"apply": Settings.Apply.LIVE,
		},
		"bounty":
		{
			"type": TYPE_INT,
			"min": 0,
			"max": 100,
			"step": 1,
			"unit": "gold",
			"apply": Settings.Apply.LIVE,
		},
		"separation_radius":
		{
			"type": TYPE_FLOAT,
			"min": 0.05,
			"max": 1.0,
			"step": 0.05,
			"unit": "cells",
			"apply": Settings.Apply.LIVE,
		},
		"separation_push":
		{
			"type": TYPE_FLOAT,
			"min": 0.0,
			"max": 1.0,
			"step": 0.05,
			"unit": "overlap/tick",
			"apply": Settings.Apply.LIVE,
		},
		"neighbour_cap":
		{
			"type": TYPE_INT,
			"min": 0,
			"max": 64,
			"step": 1,
			"unit": "neighbours (0 = off)",
			"apply": Settings.Apply.LIVE,
		},
		"heading_offset":
		{
			"type": TYPE_FLOAT,
			"min": 0.0,
			"max": 45.0,
			"step": 1.0,
			"unit": "degrees",
			"apply": Settings.Apply.LIVE,
		},
		"speed":
		{
			"type": TYPE_FLOAT,
			"min": 0.1,
			"max": 10.0,
			"step": 0.1,
			"unit": "cells/s",
			"apply": Settings.Apply.LIVE,
		},
		"structure_damage":
		{
			"type": TYPE_FLOAT,
			"min": 0.1,
			"max": 100.0,
			"step": 0.1,
			"unit": "HP/s",
			"apply": Settings.Apply.LIVE,
		},
		"wall_reach":
		{
			"type": TYPE_FLOAT,
			"min": 0.0,
			"max": 1.0,
			"step": 0.05,
			"unit": "cells",
			"apply": Settings.Apply.LIVE,
		},
		"jam_seconds":
		{
			"type": TYPE_FLOAT,
			"min": 0.05,
			"max": 10.0,
			"step": 0.05,
			"unit": "s",
			"apply": Settings.Apply.LIVE,
		},
		"pile_roll_chance":
		{
			"type": TYPE_INT,
			"min": 0,
			"max": 100,
			"step": 1,
			"unit": "percent",
			"apply": Settings.Apply.LIVE,
		},
		"wall_roll_chance":
		{
			"type": TYPE_INT,
			"min": 0,
			"max": 100,
			"step": 1,
			"unit": "percent",
			"apply": Settings.Apply.LIVE,
		},
		"speed_variety":
		{
			"type": TYPE_INT,
			"min": 0,
			"max": 50,
			"step": 1,
			"unit": "± percent pace, rolled at spawn",
			"apply": Settings.Apply.LIVE,
		},
		"wander":
		{
			"type": TYPE_FLOAT,
			"min": 0.0,
			"max": 90.0,
			"step": 1.0,
			"unit": "± degrees of weave",
			"apply": Settings.Apply.LIVE,
		},
		"wander_period":
		{
			"type": TYPE_FLOAT,
			"min": 0.5,
			"max": 20.0,
			"step": 0.5,
			"unit": "s per weave",
			"apply": Settings.Apply.LIVE,
		},
		"personal_space_radius":
		{
			"type": TYPE_FLOAT,
			"min": 0.0,
			"max": 3.0,
			"step": 0.05,
			"unit": "cells, 0 = off",
			"apply": Settings.Apply.LIVE,
		},
		"personal_space_push":
		{
			"type": TYPE_FLOAT,
			"min": 0.0,
			"max": 1.0,
			"step": 0.01,
			"unit": "push per neighbour per tick",
			"apply": Settings.Apply.LIVE,
		},
		"turn_back_angle":
		{
			"type": TYPE_FLOAT,
			"min": 0.0,
			"max": 180.0,
			"step": 5.0,
			"unit": "degrees of turn that push through in the wave tail",
			"apply": Settings.Apply.LIVE,
		},
	},
	"bloaters":
	{
		"hp":
		{
			"type": TYPE_FLOAT,
			"min": 0.5,
			"max": 1000.0,
			"step": 0.5,
			"unit": "HP",
			"apply": Settings.Apply.LIVE,
		},
		"speed":
		{
			"type": TYPE_FLOAT,
			"min": 0.1,
			"max": 10.0,
			"step": 0.1,
			"unit": "cells/s",
			"apply": Settings.Apply.LIVE,
		},
		"bounty":
		{
			"type": TYPE_INT,
			"min": 0,
			"max": 100,
			"step": 1,
			"unit": "gold",
			"apply": Settings.Apply.LIVE,
		},
		"first_wave":
		{
			"type": TYPE_INT,
			"min": 1,
			"max": 100,
			"step": 1,
			"unit": "wave",
			"apply": Settings.Apply.LIVE,
		},
		"share":
		{
			"type": TYPE_FLOAT,
			"min": 0.0,
			"max": 100.0,
			"step": 0.1,
			"unit": "percent of the first bloater wave",
			"apply": Settings.Apply.LIVE,
		},
		"share_per_wave":
		{
			"type": TYPE_FLOAT,
			"min": 0.0,
			"max": 10.0,
			"step": 0.1,
			"unit": "percent added each wave",
			"apply": Settings.Apply.LIVE,
		},
		"share_cap":
		{
			"type": TYPE_FLOAT,
			"min": 0.0,
			"max": 100.0,
			"step": 0.1,
			"unit": "percent",
			"apply": Settings.Apply.LIVE,
		},
		"size":
		{
			"type": TYPE_FLOAT,
			"min": 0.5,
			"max": 3.0,
			"step": 0.1,
			"unit": "× drawn size",
			"apply": Settings.Apply.LIVE,
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
			"apply": Settings.Apply.LIVE,
		},
		"slow_level_2":
		{
			"type": TYPE_INT,
			"min": 0,
			"max": 95,
			"step": 5,
			"unit": "percent",
			"apply": Settings.Apply.LIVE,
		},
		"slow_level_3":
		{
			"type": TYPE_INT,
			"min": 0,
			"max": 95,
			"step": 5,
			"unit": "percent",
			"apply": Settings.Apply.LIVE,
		},
		"slow_level_4":
		{
			"type": TYPE_INT,
			"min": 0,
			"max": 95,
			"step": 5,
			"unit": "percent",
			"apply": Settings.Apply.LIVE,
		},
		"wall_hp":
		{
			"type": TYPE_FLOAT,
			"min": 1.0,
			"max": 1000.0,
			"step": 1.0,
			"unit": "HP",
			"apply": Settings.Apply.LIVE,
		},
		"decay_chance":
		{
			"type": TYPE_INT,
			"min": 0,
			"max": 100,
			"step": 5,
			"unit": "percent",
			"apply": Settings.Apply.LIVE,
		},
		"wall_decay_chance":
		{
			"type": TYPE_INT,
			"min": 0,
			"max": 100,
			"step": 5,
			"unit": "percent",
			"apply": Settings.Apply.LIVE,
		},
	},
	"overflow":
	{
		"enabled":
		{
			"type": TYPE_INT,
			"min": 0,
			"max": 1,
			"step": 1,
			"unit": "on/off",
			"toggle": true,
			"apply": Settings.Apply.LIVE,
		},
		"band":
		{
			"type": TYPE_INT,
			"min": 1,
			"max": 8,
			"step": 1,
			"unit": "steps from a run of walls and buildings",
			"apply": Settings.Apply.LIVE,
		},
		"stall_progress":
		{
			"type": TYPE_INT,
			"min": 0,
			"max": 100,
			"step": 1,
			"unit": "percent of walking progress below which an enemy in a band is stalled",
			"apply": Settings.Apply.LIVE,
		},
		"fill_per_stalled":
		{
			"type": TYPE_FLOAT,
			"min": 0.0,
			"max": 10.0,
			"step": 0.1,
			"unit": "gauge per stalled enemy per s",
			"apply": Settings.Apply.LIVE,
		},
		"leak":
		{
			"type": TYPE_FLOAT,
			"min": 0.0,
			"max": 100.0,
			"step": 0.5,
			"unit": "gauge per s",
			"apply": Settings.Apply.LIVE,
		},
		"crush_start":
		{
			"type": TYPE_FLOAT,
			"min": 0.0,
			"max": 500.0,
			"step": 1.0,
			"unit": "gauge above which a crush is active",
			"apply": Settings.Apply.LIVE,
		},
		"crush_end":
		{
			"type": TYPE_FLOAT,
			"min": 0.0,
			"max": 500.0,
			"step": 1.0,
			"unit": "gauge below which an active crush ends",
			"apply": Settings.Apply.LIVE,
		},
		"trickle_at":
		{
			"type": TYPE_FLOAT,
			"min": 0.0,
			"max": 500.0,
			"step": 1.0,
			"unit": "gauge",
			"apply": Settings.Apply.LIVE,
		},
		"stream_at":
		{
			"type": TYPE_FLOAT,
			"min": 0.0,
			"max": 500.0,
			"step": 1.0,
			"unit": "gauge",
			"apply": Settings.Apply.LIVE,
		},
		"surge_at":
		{
			"type": TYPE_FLOAT,
			"min": 0.0,
			"max": 500.0,
			"step": 1.0,
			"unit": "gauge",
			"apply": Settings.Apply.LIVE,
		},
		"gauge_max":
		{
			"type": TYPE_FLOAT,
			"min": 1.0,
			"max": 500.0,
			"step": 1.0,
			"unit": "gauge",
			"apply": Settings.Apply.LIVE,
		},
		"trickle_rate":
		{
			"type": TYPE_FLOAT,
			"min": 0.0,
			"max": 100.0,
			"step": 0.5,
			"unit": "enemies tumbling per s",
			"apply": Settings.Apply.LIVE,
		},
		"stream_rate":
		{
			"type": TYPE_FLOAT,
			"min": 0.0,
			"max": 100.0,
			"step": 0.5,
			"unit": "enemies tumbling per s",
			"apply": Settings.Apply.LIVE,
		},
		"surge_rate":
		{
			"type": TYPE_FLOAT,
			"min": 0.0,
			"max": 100.0,
			"step": 0.5,
			"unit": "enemies tumbling per s",
			"apply": Settings.Apply.LIVE,
		},
		"relief":
		{
			"type": TYPE_FLOAT,
			"min": 0.0,
			"max": 100.0,
			"step": 0.5,
			"unit": "gauge per tumble",
			"apply": Settings.Apply.LIVE,
		},
		"tumble_speed":
		{
			"type": TYPE_INT,
			"min": 10,
			"max": 500,
			"step": 10,
			"unit": "percent of walking speed",
			"apply": Settings.Apply.LIVE,
		},
		"landing_crowd":
		{
			"type": TYPE_INT,
			"min": 1,
			"max": 50,
			"step": 1,
			"unit": "enemies in a cell that stop a tumble landing on it",
			"apply": Settings.Apply.LIVE,
		},
		"bodies_fall_back":
		{
			"type": TYPE_INT,
			"min": 0,
			"max": 1,
			"step": 1,
			"unit": "on/off",
			"toggle": true,
			"apply": Settings.Apply.LIVE,
		},
		"fall_back_window":
		{
			"type": TYPE_FLOAT,
			"min": 0.0,
			"max": 10.0,
			"step": 0.5,
			"unit": "s after landing that a body still falls back",
			"apply": Settings.Apply.LIVE,
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
			"apply": Settings.Apply.LIVE,
		},
		"sensible_wall_weight":
		{
			"type": TYPE_FLOAT,
			"min": 0.0,
			"max": 5.0,
			"step": 0.05,
			"unit": "weight",
			"apply": Settings.Apply.LIVE,
		},
		"direct_pile_weight":
		{
			"type": TYPE_FLOAT,
			"min": 0.0,
			"max": 5.0,
			"step": 0.05,
			"unit": "weight",
			"apply": Settings.Apply.LIVE,
		},
		"direct_wall_weight":
		{
			"type": TYPE_FLOAT,
			"min": 0.0,
			"max": 5.0,
			"step": 0.05,
			"unit": "weight",
			"apply": Settings.Apply.LIVE,
		},
		"wall_hp_bucket":
		{
			"type": TYPE_FLOAT,
			"min": 1.0,
			"max": 100.0,
			"step": 1.0,
			"unit": "HP",
			"apply": Settings.Apply.LIVE,
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
			"apply": Settings.Apply.RESTART,
		},
		"growth":
		{
			"type": TYPE_FLOAT,
			"min": 1.0,
			"max": 2.0,
			"step": 0.01,
			"unit": "× enemies per wave",
			"apply": Settings.Apply.LIVE,
		},
		"hp_growth":
		{
			"type": TYPE_FLOAT,
			"min": 1.0,
			"max": 2.0,
			"step": 0.01,
			"unit": "× HP per wave",
			"apply": Settings.Apply.LIVE,
		},
		"spawn_rate":
		{
			"type": TYPE_FLOAT,
			"min": 0.5,
			"max": 120.0,
			"step": 0.5,
			"unit": "enemies/s",
			"apply": Settings.Apply.LIVE,
		},
		"second_edge_chance":
		{
			"type": TYPE_INT,
			"min": 0,
			"max": 100,
			"step": 5,
			"unit": "percent",
			"apply": Settings.Apply.LIVE,
		},
		"clump_size":
		{
			"type": TYPE_INT,
			"min": 1,
			"max": 50,
			"step": 1,
			"unit": "enemies per spawn burst",
			"apply": Settings.Apply.LIVE,
		},
		"wave_tail":
		{
			"type": TYPE_INT,
			"min": 0,
			"max": 500,
			"step": 1,
			"unit": "enemies left when the wave tail starts",
			"apply": Settings.Apply.LIVE,
		},
		"wave_tail_per_wave":
		{
			"type": TYPE_INT,
			"min": 0,
			"max": 50,
			"step": 1,
			"unit": "more wave-tail enemies per wave",
			"apply": Settings.Apply.LIVE,
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
			"apply": Settings.Apply.LIVE,
		},
		"fire_rate":
		{
			"type": TYPE_FLOAT,
			"min": 0.1,
			"max": 20.0,
			"step": 0.1,
			"unit": "shots/s",
			"apply": Settings.Apply.LIVE,
		},
		"range":
		{
			"type": TYPE_FLOAT,
			"min": 1.0,
			"max": 30.0,
			"step": 0.5,
			"unit": "cells",
			"apply": Settings.Apply.LIVE,
		},
		"cost":
		{
			"type": TYPE_INT,
			"min": 0,
			"max": 1000,
			"step": 5,
			"unit": "gold",
			"apply": Settings.Apply.LIVE,
		},
		"hp":
		{
			"type": TYPE_FLOAT,
			"min": 1.0,
			"max": 1000.0,
			"step": 1.0,
			"unit": "HP",
			"apply": Settings.Apply.LIVE,
		},
		"power_area":
		{
			"type": TYPE_INT,
			"min": 0,
			"max": 50,
			"step": 1,
			"unit": "cells from the footprint",
			"apply": Settings.Apply.LIVE,
		},
	},
	"grinders":
	{
		"cost":
		{
			"type": TYPE_INT,
			"min": 0,
			"max": 1000,
			"step": 5,
			"unit": "gold",
			"apply": Settings.Apply.LIVE,
		},
		"hp":
		{
			"type": TYPE_FLOAT,
			"min": 1.0,
			"max": 1000.0,
			"step": 1.0,
			"unit": "HP",
			"apply": Settings.Apply.LIVE,
		},
		"power_area":
		{
			"type": TYPE_INT,
			"min": 0,
			"max": 50,
			"step": 1,
			"unit": "cells from the footprint",
			"apply": Settings.Apply.LIVE,
		},
		"damage":
		{
			"type": TYPE_FLOAT,
			"min": 0.0,
			"max": 100.0,
			"step": 0.5,
			"unit": "HP/s to each enemy touching it",
			"apply": Settings.Apply.LIVE,
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
			"apply": Settings.Apply.LIVE,
		},
		"hp":
		{
			"type": TYPE_FLOAT,
			"min": 1.0,
			"max": 1000.0,
			"step": 1.0,
			"unit": "HP",
			"apply": Settings.Apply.LIVE,
		},
		"power_area":
		{
			"type": TYPE_INT,
			"min": 0,
			"max": 50,
			"step": 1,
			"unit": "cells from the footprint",
			"apply": Settings.Apply.LIVE,
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
			"apply": Settings.Apply.LIVE,
		},
		"hp":
		{
			"type": TYPE_FLOAT,
			"min": 1.0,
			"max": 1000.0,
			"step": 1.0,
			"unit": "HP",
			"apply": Settings.Apply.LIVE,
		},
		"power_area":
		{
			"type": TYPE_INT,
			"min": 0,
			"max": 50,
			"step": 1,
			"unit": "cells from the footprint",
			"apply": Settings.Apply.LIVE,
		},
		"repair_area":
		{
			"type": TYPE_INT,
			"min": 0,
			"max": 50,
			"step": 1,
			"unit": "cells from the footprint",
			"apply": Settings.Apply.LIVE,
		},
		"drone_speed":
		{
			"type": TYPE_FLOAT,
			"min": 0.5,
			"max": 60.0,
			"step": 0.5,
			"unit": "cells/s",
			"apply": Settings.Apply.LIVE,
		},
		"repair_rate":
		{
			"type": TYPE_FLOAT,
			"min": 0.5,
			"max": 100.0,
			"step": 0.5,
			"unit": "HP/s",
			"apply": Settings.Apply.LIVE,
		},
	},
	"combo":
	{
		"timer":
		{
			"type": TYPE_FLOAT,
			"min": 0.5,
			"max": 10.0,
			"step": 0.5,
			"unit": "s from a kill until the combo breaks",
			"apply": Settings.Apply.LIVE,
		},
		"tier_2_kills":
		{
			"type": TYPE_INT,
			"min": 1,
			"max": 500,
			"step": 1,
			"unit": "kills in a combo for x2",
			"apply": Settings.Apply.LIVE,
		},
		"tier_3_kills":
		{
			"type": TYPE_INT,
			"min": 1,
			"max": 500,
			"step": 1,
			"unit": "kills in a combo for x3",
			"apply": Settings.Apply.LIVE,
		},
		"cap":
		{
			"type": TYPE_INT,
			"min": 1,
			"max": 3,
			"step": 1,
			"unit": "highest combo tier",
			"apply": Settings.Apply.LIVE,
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
			"apply": Settings.Apply.RESTART,
		},
		"starting_gold":
		{
			"type": TYPE_INT,
			"min": 0,
			"max": 10000,
			"step": 10,
			"unit": "gold",
			"apply": Settings.Apply.RESTART,
		},
		"base_power_area":
		{
			"type": TYPE_INT,
			"min": 0,
			"max": 50,
			"step": 1,
			"unit": "cells from the base",
			"apply": Settings.Apply.LIVE,
		},
		"map_path": {"type": TYPE_STRING, "unit": "path", "apply": Settings.Apply.RESTART},
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
			"apply": Settings.Apply.LIVE,
		},
	},
}
