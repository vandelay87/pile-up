extends GdUnitTestSuite

const SCHEMA := {
	"towers":
	{
		"fire_rate":
		{
			"type": TYPE_FLOAT,
			"min": 0.1,
			"max": 20.0,
			"step": 0.1,
			"unit": "shots/s",
			"apply": Settings.Apply.LIVE,
		},
	},
	"run":
	{
		"starting_lives":
		{
			"type": TYPE_INT,
			"min": 1,
			"max": 100,
			"step": 1,
			"unit": "lives",
			"apply": Settings.Apply.RESTART,
		},
		"map_path": {"type": TYPE_STRING, "unit": "path", "apply": Settings.Apply.RESTART},
	},
}


func _settings() -> Settings:
	var data := {
		"towers": {"fire_rate": 2},
		"run": {"starting_lives": 20, "map_path": "res://data/maps/v1.json"},
	}
	var result := Settings.from_json(JSON.stringify(data), SCHEMA)
	assert_str(result.error).is_empty()
	return result.settings


func test_a_live_change_applies_on_the_tick_its_command_is_drained() -> void:
	var settings := _settings()
	var sim := Simulation.new(settings, TestMaps.open_field())
	var seen: Array[float] = []
	sim.step_observer = func(step: int) -> void:
		if step == Simulation.Step.LAND_BODIES_AND_UPDATE_FIELDS:
			seen.append(settings.value("towers", "fire_rate"))

	sim.queue_command(Commands.SetSetting.new("towers", "fire_rate", 4.0))
	assert_float(settings.value("towers", "fire_rate")).is_equal(2.0)
	sim.tick()

	assert_array(seen).contains_exactly([4.0])


func test_a_restart_change_leaves_the_running_value_unchanged() -> void:
	var sim := Simulation.new(_settings(), TestMaps.open_field())

	sim.queue_command(Commands.SetSetting.new("run", "starting_lives", 5))
	sim.tick()

	assert_int(sim.settings.value("run", "starting_lives")).is_equal(20)
	assert_int(sim.settings.for_next_run().value("run", "starting_lives")).is_equal(5)


func test_an_invalid_change_is_rejected_and_leaves_the_value_unchanged() -> void:
	var sim := Simulation.new(_settings(), TestMaps.open_field())
	var rejections: Array[String] = []
	sim.command_rejected.connect(func(reason: String) -> void: rejections.append(reason))

	sim.queue_command(Commands.SetSetting.new("towers", "fire_rate", 50.0))
	sim.tick()

	assert_array(rejections).has_size(1)
	assert_str(rejections[0]).contains("towers.fire_rate")
	assert_float(sim.settings.value("towers", "fire_rate")).is_equal(2.0)


func test_a_change_to_an_unknown_setting_is_rejected() -> void:
	var sim := Simulation.new(_settings(), TestMaps.open_field())
	var rejections: Array[String] = []
	sim.command_rejected.connect(func(reason: String) -> void: rejections.append(reason))

	sim.queue_command(Commands.SetSetting.new("run", "starting_mana", 5))
	sim.tick()

	assert_array(rejections).contains_exactly(["run.starting_mana: unknown setting"])


func test_a_route_weight_change_reports_fields_changed_at_the_end_of_the_tick() -> void:
	var sim := Simulation.new(_defaults(), TestMaps.open_field())
	var trace: Array[String] = []
	sim.step_observer = func(step: int) -> void: trace.append("step %d" % step)
	sim.fields_changed.connect(func() -> void: trace.append("fields changed"))

	sim.queue_command(Commands.SetSetting.new("routing", "direct_wall_weight", 0.5))
	sim.tick()

	assert_array(trace).has_size(9)
	assert_str(trace[8]).is_equal("fields changed")
	assert_float(sim.routing.wall_factor(Routing.Route.DIRECT, 30.0)).is_equal_approx(23.5, 1e-6)


func test_fields_changed_is_not_reported_for_other_or_rejected_changes() -> void:
	var sim := Simulation.new(_defaults(), TestMaps.open_field())
	var reports: Array[bool] = []
	sim.fields_changed.connect(func() -> void: reports.append(true))

	sim.queue_command(Commands.SetSetting.new("enemies", "speed", 2.0))
	sim.queue_command(Commands.SetSetting.new("routing", "direct_wall_weight", 50.0))
	sim.tick()
	sim.tick()

	assert_array(reports).is_empty()


func _defaults() -> Settings:
	return Settings.load_file(Settings.DEFAULTS_PATH).settings
