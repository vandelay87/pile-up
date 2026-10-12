# Throwaway profiling marks for the 1,000-enemy tick research. Never merged.
class_name Prof
extends RefCounted

static var usec := {}


static func add(section: StringName, started: int) -> void:
	usec[section] = usec.get(section, 0) + Time.get_ticks_usec() - started


static func take() -> Dictionary:
	var taken := usec
	usec = {}
	return taken
