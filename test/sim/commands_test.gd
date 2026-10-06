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
