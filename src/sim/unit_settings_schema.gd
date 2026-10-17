class_name UnitSettingsSchema
extends RefCounted

## The soldiers and barracks groups of [constant SettingsSchema.SCHEMA], kept apart so the
## schema file stays within gdlint's line limit.

const SOLDIERS := {
	"hp":
	{
		"type": TYPE_FLOAT,
		"min": 1.0,
		"max": 1000.0,
		"step": 1.0,
		"unit": "HP",
		"apply": Settings.Apply.LIVE,
	},
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
		"min": 0.5,
		"max": 30.0,
		"step": 0.5,
		"unit": "cells",
		"apply": Settings.Apply.LIVE,
	},
	"range_per_level":
	{
		"type": TYPE_FLOAT,
		"min": 0.0,
		"max": 5.0,
		"step": 0.1,
		"unit": "cells a level up",
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
	"wall_climb_slow":
	{
		"type": TYPE_INT,
		"min": 0,
		"max": 95,
		"step": 5,
		"unit": "% slower on a wall",
		"apply": Settings.Apply.LIVE,
	},
	"mass":
	{
		"type": TYPE_FLOAT,
		"min": 1.0,
		"max": 50.0,
		"step": 0.5,
		"unit": "an enemy's mass (1)",
		"apply": Settings.Apply.LIVE,
	},
	"contact_push":
	{
		"type": TYPE_FLOAT,
		"min": 0.05,
		"max": 1.0,
		"step": 0.05,
		"unit": "overlap/tick with enemies",
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
	"training_time":
	{
		"type": TYPE_FLOAT,
		"min": 0.5,
		"max": 60.0,
		"step": 0.5,
		"unit": "s each during a wave",
		"apply": Settings.Apply.LIVE,
	},
}

const BARRACKS := {
	"hp":
	{
		"type": TYPE_FLOAT,
		"min": 1.0,
		"max": 1000.0,
		"step": 1.0,
		"unit": "HP",
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
	"power_area":
	{
		"type": TYPE_INT,
		"min": 0,
		"max": 50,
		"step": 1,
		"unit": "cells from the footprint",
		"apply": Settings.Apply.LIVE,
	},
	"capacity":
	{
		"type": TYPE_INT,
		"min": 1,
		"max": 100,
		"step": 1,
		"unit": "soldiers a barracks",
		"apply": Settings.Apply.RESTART,
	},
	"limit":
	{
		"type": TYPE_INT,
		"min": 1,
		"max": 20,
		"step": 1,
		"unit": "barracks at once",
		"apply": Settings.Apply.RESTART,
	},
}
