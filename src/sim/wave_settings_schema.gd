class_name WaveSettingsSchema
extends RefCounted

## The groups of [constant SettingsSchema.SCHEMA] for the waves, the alert, the trickle and
## threat, kept apart so the schema file stays within gdlint's line limit.

const WAVES := {
	"wave_1_size":
	{
		"type": TYPE_INT,
		"min": 1,
		"max": 500,
		"step": 1,
		"unit": "enemies at threat 1, Medium",
		"apply": Settings.Apply.RESTART,
	},
	"growth":
	{
		"type": TYPE_FLOAT,
		"min": 1.0,
		"max": 2.0,
		"step": 0.01,
		"unit": "× enemies per point of threat",
		"apply": Settings.Apply.LIVE,
	},
	"hp_growth":
	{
		"type": TYPE_FLOAT,
		"min": 1.0,
		"max": 2.0,
		"step": 0.01,
		"unit": "× HP per point of threat",
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
	"spawn_rate_growth":
	{
		"type": TYPE_FLOAT,
		"min": 1.0,
		"max": 2.0,
		"step": 0.01,
		"unit": "× spawn rate per point of threat",
		"apply": Settings.Apply.LIVE,
	},
	"burst_size":
	{
		"type": TYPE_INT,
		"min": 1,
		"max": 50,
		"step": 1,
		"unit": "enemies per burst at threat 1",
		"apply": Settings.Apply.LIVE,
	},
	"burst_growth":
	{
		"type": TYPE_FLOAT,
		"min": 1.0,
		"max": 2.0,
		"step": 0.01,
		"unit": "× burst size per point of threat",
		"apply": Settings.Apply.LIVE,
	},
	"burst_width":
	{
		"type": TYPE_FLOAT,
		"min": 1.0,
		"max": 40.0,
		"step": 0.5,
		"unit": "cells along the edge for a threat-1 burst",
		"apply": Settings.Apply.LIVE,
	},
	"scatter_share_start":
	{
		"type": TYPE_INT,
		"min": 0,
		"max": 100,
		"step": 5,
		"unit": "percent spawned singly at threat 1",
		"apply": Settings.Apply.LIVE,
	},
	"scatter_share_end":
	{
		"type": TYPE_INT,
		"min": 0,
		"max": 100,
		"step": 5,
		"unit": "percent spawned singly from the end threat on",
		"apply": Settings.Apply.LIVE,
	},
	"scatter_share_end_threat":
	{
		"type": TYPE_INT,
		"min": 1,
		"max": 50,
		"step": 1,
		"unit": "threat the scatter share reaches its end",
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
	"wave_tail_per_threat":
	{
		"type": TYPE_INT,
		"min": 0,
		"max": 50,
		"step": 1,
		"unit": "more wave-tail enemies per point of threat",
		"apply": Settings.Apply.LIVE,
	},
	"size_low":
	{
		"type": TYPE_FLOAT,
		"min": 0.0,
		"max": 3.0,
		"step": 0.05,
		"unit": "× wave size at Low",
		"apply": Settings.Apply.LIVE,
	},
	"size_medium":
	{
		"type": TYPE_FLOAT,
		"min": 0.0,
		"max": 3.0,
		"step": 0.05,
		"unit": "× wave size at Medium",
		"apply": Settings.Apply.LIVE,
	},
	"size_high":
	{
		"type": TYPE_FLOAT,
		"min": 0.0,
		"max": 3.0,
		"step": 0.05,
		"unit": "× wave size at High",
		"apply": Settings.Apply.LIVE,
	},
	"dry_size":
	{
		"type": TYPE_FLOAT,
		"min": 0.0,
		"max": 3.0,
		"step": 0.05,
		"unit": "× wave size while every deposit is dry, or at Off",
		"apply": Settings.Apply.LIVE,
	},
	"size_roll":
	{
		"type": TYPE_INT,
		"min": 0,
		"max": 100,
		"step": 5,
		"unit": "± percent each wave's size is rolled by",
		"apply": Settings.Apply.LIVE,
	},
	"two_edges_threat":
	{
		"type": TYPE_INT,
		"min": 1,
		"max": 100,
		"step": 1,
		"unit": "threat from which waves come from 2 edges",
		"apply": Settings.Apply.LIVE,
	},
	"three_edges_threat":
	{
		"type": TYPE_INT,
		"min": 1,
		"max": 100,
		"step": 1,
		"unit": "threat from which waves come from 3 edges",
		"apply": Settings.Apply.LIVE,
	},
	"four_edges_threat":
	{
		"type": TYPE_INT,
		"min": 1,
		"max": 100,
		"step": 1,
		"unit": "threat from which waves come from 4 edges",
		"apply": Settings.Apply.LIVE,
	},
}

const ALERT := {
	"fill_seconds":
	{
		"type": TYPE_FLOAT,
		"min": 1.0,
		"max": 600.0,
		"step": 1.0,
		"unit": "s to fill at High",
		"apply": Settings.Apply.LIVE,
	},
	"fill_low":
	{
		"type": TYPE_FLOAT,
		"min": 0.0,
		"max": 3.0,
		"step": 0.05,
		"unit": "× fill speed at Low",
		"apply": Settings.Apply.LIVE,
	},
	"fill_medium":
	{
		"type": TYPE_FLOAT,
		"min": 0.0,
		"max": 3.0,
		"step": 0.05,
		"unit": "× fill speed at Medium",
		"apply": Settings.Apply.LIVE,
	},
	"fill_high":
	{
		"type": TYPE_FLOAT,
		"min": 0.0,
		"max": 3.0,
		"step": 0.05,
		"unit": "× fill speed at High",
		"apply": Settings.Apply.LIVE,
	},
	"dry_fill":
	{
		"type": TYPE_FLOAT,
		"min": 0.0,
		"max": 3.0,
		"step": 0.05,
		"unit": "× fill speed while every deposit is dry",
		"apply": Settings.Apply.LIVE,
	},
	"warn_at":
	{
		"type": TYPE_INT,
		"min": 1,
		"max": 100,
		"step": 5,
		"unit": "percent full when the next wave's edges are picked",
		"apply": Settings.Apply.LIVE,
	},
}

const TRICKLE := {
	"interval":
	{
		"type": TYPE_FLOAT,
		"min": 0.0,
		"max": 60.0,
		"step": 0.1,
		"unit": "s between trickle enemies at threat 1, 0 for none",
		"apply": Settings.Apply.LIVE,
	},
	"growth":
	{
		"type": TYPE_FLOAT,
		"min": 1.0,
		"max": 2.0,
		"step": 0.01,
		"unit": "× trickle rate per point of threat",
		"apply": Settings.Apply.LIVE,
	},
}

const THREAT := {
	"start":
	{
		"type": TYPE_FLOAT,
		"min": 1.0,
		"max": 50.0,
		"step": 0.5,
		"unit": "threat at the start of a run",
		"apply": Settings.Apply.RESTART,
	},
	"seconds_per_point":
	{
		"type": TYPE_FLOAT,
		"min": 10.0,
		"max": 10000.0,
		"step": 10.0,
		"unit": "s of time per point of threat",
		"apply": Settings.Apply.LIVE,
	},
	"minerals_per_point":
	{
		"type": TYPE_FLOAT,
		"min": 10.0,
		"max": 10000.0,
		"step": 10.0,
		"unit": "minerals mined per point of threat",
		"apply": Settings.Apply.LIVE,
	},
}
