class_name EnemyKindsSchema
extends RefCounted

## The groups of [constant SettingsSchema.SCHEMA] for the enemy kinds beyond the normal enemy,
## kept apart so the schema file stays within gdlint's line limit.

const BLOATERS := {
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
	"waves_per_step":
	{
		"type": TYPE_INT,
		"min": 1,
		"max": 50,
		"step": 1,
		"unit": "waves per extra bloater",
		"apply": Settings.Apply.LIVE,
	},
	"miss_chance":
	{
		"type": TYPE_INT,
		"min": 0,
		"max": 100,
		"step": 5,
		"unit": "percent chance a wave has one fewer",
		"apply": Settings.Apply.LIVE,
	},
	"extra_chance":
	{
		"type": TYPE_INT,
		"min": 0,
		"max": 100,
		"step": 5,
		"unit": "percent chance a wave has one more",
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
	"fuse":
	{
		"type": TYPE_FLOAT,
		"min": 0.1,
		"max": 10.0,
		"step": 0.1,
		"unit": "s",
		"apply": Settings.Apply.LIVE,
	},
	"blast_radius":
	{
		"type": TYPE_FLOAT,
		"min": 0.5,
		"max": 6.0,
		"step": 0.5,
		"unit": "cells",
		"apply": Settings.Apply.LIVE,
	},
	"blast_damage":
	{
		"type": TYPE_FLOAT,
		"min": 0.0,
		"max": 1000.0,
		"step": 5.0,
		"unit": "HP to each building and the base",
		"apply": Settings.Apply.LIVE,
	},
}

const JUMPERS := {
	"speed":
	{
		"type": TYPE_FLOAT,
		"min": 0.1,
		"max": 10.0,
		"step": 0.1,
		"unit": "cells/s",
		"apply": Settings.Apply.LIVE,
	},
	"reach":
	{
		"type": TYPE_INT,
		"min": 1,
		"max": 10,
		"step": 1,
		"unit": "wall and building cells",
		"apply": Settings.Apply.LIVE,
	},
	"cooldown":
	{
		"type": TYPE_FLOAT,
		"min": 0.0,
		"max": 30.0,
		"step": 0.5,
		"unit": "s",
		"apply": Settings.Apply.LIVE,
	},
	"crouch":
	{
		"type": TYPE_FLOAT,
		"min": 0.0,
		"max": 2.0,
		"step": 0.05,
		"unit": "s",
		"apply": Settings.Apply.LIVE,
	},
	"air_time":
	{
		"type": TYPE_FLOAT,
		"min": 0.1,
		"max": 3.0,
		"step": 0.05,
		"unit": "s",
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
		"type": TYPE_INT,
		"min": 0,
		"max": 100,
		"step": 1,
		"unit": "percent of the wave",
		"apply": Settings.Apply.LIVE,
	},
	"cap":
	{
		"type": TYPE_INT,
		"min": 0,
		"max": 1000,
		"step": 1,
		"unit": "jumpers a wave (0 is off)",
		"apply": Settings.Apply.LIVE,
	},
}

const BRUTES := {
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
	"mass":
	{
		"type": TYPE_FLOAT,
		"min": 0.5,
		"max": 20.0,
		"step": 0.5,
		"unit": "× a normal enemy's mass",
		"apply": Settings.Apply.LIVE,
	},
	"structure_damage_factor":
	{
		"type": TYPE_FLOAT,
		"min": 0.5,
		"max": 20.0,
		"step": 0.5,
		"unit": "× structure damage",
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
	"first_wave":
	{
		"type": TYPE_INT,
		"min": 1,
		"max": 100,
		"step": 1,
		"unit": "wave",
		"apply": Settings.Apply.LIVE,
	},
	"waves_per_step":
	{
		"type": TYPE_INT,
		"min": 1,
		"max": 50,
		"step": 1,
		"unit": "waves per extra brute",
		"apply": Settings.Apply.LIVE,
	},
	"miss_chance":
	{
		"type": TYPE_INT,
		"min": 0,
		"max": 100,
		"step": 5,
		"unit": "percent chance a wave has one fewer",
		"apply": Settings.Apply.LIVE,
	},
	"extra_chance":
	{
		"type": TYPE_INT,
		"min": 0,
		"max": 100,
		"step": 5,
		"unit": "percent chance a wave has one more",
		"apply": Settings.Apply.LIVE,
	},
}
