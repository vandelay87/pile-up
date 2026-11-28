class_name Threat
extends RefCounted

## The run's threat: it starts at [code]threat.start[/code] and rises with time and with every
## mineral mined, and never falls. Rules that v5 read from the wave number read it: continuous
## ones its value as a wave starts, stepped ones its whole points.

## A value this far under a whole number from float error has reached it.
const WHOLE_TOLERANCE := 1e-9

var value: float

var _settings: Settings


func _init(run_settings: Settings) -> void:
	_settings = run_settings
	value = _settings.threat_start


## Its whole points, for the stepped rules.
func whole() -> int:
	return floori(value + WHOLE_TOLERANCE)


## Step 2: a tick's time.
func step() -> void:
	value += _settings.threat_per_tick


## Step 2: every mineral mined this tick, of every kind.
func add_minerals(amount: float) -> void:
	value += amount / _settings.minerals_per_threat


## Debug: sets the threat to [param to]; an error if that would lower it.
func jump_to(to: float) -> String:
	if to < value:
		return "the threat never falls"
	value = to
	return ""
