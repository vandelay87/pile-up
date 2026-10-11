class_name TestSettings
extends RefCounted


# The committed defaults with pace, wander and personal space off, for tests of the
# movement rules underneath the swarm spread.
static func without_swarm_spread() -> Settings:
	var settings := Settings.load_file(Settings.DEFAULTS_PATH).settings
	settings.change("enemies", "speed_variety", 0)
	settings.change("enemies", "wander", 0.0)
	settings.change("enemies", "personal_space_radius", 0.0)
	return settings
