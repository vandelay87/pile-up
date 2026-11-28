extends GdUnitTestSuite

# The threat, alert and trickle settings, in sim units.


func test_converts_the_threat_alert_and_trickle_settings_to_sim_units() -> void:
	var settings := Settings.load_file(Settings.DEFAULTS_PATH).settings

	assert_float(settings.threat_start).is_equal(1.0)
	assert_float(settings.threat_per_tick).is_equal_approx(1.0 / 60000.0, 1e-12)
	assert_float(settings.minerals_per_threat).is_equal(360.0)
	assert_float(settings.alert_fill_per_tick).is_equal_approx(1.0 / 3600.0, 1e-12)
	assert_float(settings.alert_warn_at).is_equal_approx(0.75, 1e-9)
	assert_float(settings.trickle_spawn_rate).is_equal_approx(0.4, 1e-9)
	assert_float(settings.trickle_spawn_growth).is_equal_approx(1.05, 1e-9)
	settings.change("trickle", "interval", 0.0)
	assert_float(settings.trickle_spawn_rate).is_equal(0.0)
