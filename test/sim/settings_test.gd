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


func _valid() -> Dictionary:
	return {
		"towers": {"fire_rate": 2},
		"run": {"starting_lives": 20, "map_path": "data/maps/v1.json"},
	}


func _load(data: Dictionary) -> Settings.LoadResult:
	return Settings.from_json(JSON.stringify(data), SCHEMA)


func _settings() -> Settings:
	var result := _load(_valid())
	assert_str(result.error).is_empty()
	return result.settings


func test_loads_a_valid_file() -> void:
	var settings := _settings()

	assert_float(settings.value("towers", "fire_rate")).is_equal(2.0)
	assert_int(settings.value("run", "starting_lives")).is_equal(20)
	assert_str(settings.value("run", "map_path")).is_equal("data/maps/v1.json")


func test_the_committed_defaults_file_loads() -> void:
	var result := Settings.load_file(Settings.DEFAULTS_PATH)

	assert_str(result.error).is_empty()
	assert_object(result.settings).is_not_null()


func test_reads_the_committed_defaults_as_typed_values() -> void:
	var settings := Settings.load_file(Settings.DEFAULTS_PATH).settings

	assert_int(settings.starting_lives).is_equal(20)
	assert_int(settings.starting_gold).is_equal(150)
	assert_str(settings.map_path).is_equal("data/maps/v1.json")


func test_rejects_malformed_json() -> void:
	_assert_rejected(Settings.from_json("{", SCHEMA), "JSON")


func test_rejects_an_unknown_group() -> void:
	var data := _valid()
	data["walls"] = {}

	_assert_rejected(_load(data), "walls: unknown group")


func test_rejects_an_unknown_key() -> void:
	var data := _valid()
	data["run"]["starting_mana"] = 5

	_assert_rejected(_load(data), "run.starting_mana: unknown setting")


func test_rejects_a_missing_key() -> void:
	var data := _valid()
	var run: Dictionary = data["run"]
	run.erase("starting_lives")

	_assert_rejected(_load(data), "run.starting_lives: missing")


func test_rejects_a_missing_group() -> void:
	var data := _valid()
	data.erase("towers")

	_assert_rejected(_load(data), "towers: missing")


func test_rejects_a_wrong_type() -> void:
	var data := _valid()
	data["run"]["starting_lives"] = "20"

	_assert_rejected(_load(data), "run.starting_lives: expected int")


func test_rejects_a_fractional_int() -> void:
	var data := _valid()
	data["run"]["starting_lives"] = 20.5

	_assert_rejected(_load(data), "run.starting_lives: expected int")


func test_rejects_an_out_of_range_value() -> void:
	var data := _valid()
	data["run"]["starting_lives"] = 0

	_assert_rejected(_load(data), "run.starting_lives: 0 is outside 1 to 100")


func test_reports_every_error_at_once() -> void:
	var data := _valid()
	data["run"]["starting_lives"] = 0
	data["towers"]["fire_rate"] = "fast"

	var result := _load(data)

	assert_str(result.error).contains("run.starting_lives").contains("towers.fire_rate")


func test_converts_seconds_to_ticks() -> void:
	assert_int(Settings.ticks_from_seconds(0.5)).is_equal(30)


func test_converts_a_rate_to_interval_ticks() -> void:
	assert_int(Settings.interval_ticks(2.0)).is_equal(30)
	assert_int(Settings.interval_ticks(7.0)).is_equal(9)


func test_interval_ticks_is_at_least_one_tick() -> void:
	assert_int(Settings.interval_ticks(1000.0)).is_equal(1)


func test_a_live_change_applies_on_the_tick_its_command_is_drained() -> void:
	var settings := _settings()
	var sim := Simulation.new(settings)
	var seen: Array[float] = []
	sim.step_observer = func(step: int) -> void:
		if step == Simulation.Step.LAND_BODIES_AND_UPDATE_FIELDS:
			seen.append(settings.value("towers", "fire_rate"))

	sim.queue_command(Commands.SetSetting.new("towers", "fire_rate", 4.0))
	assert_float(settings.value("towers", "fire_rate")).is_equal(2.0)
	sim.tick()

	assert_array(seen).contains_exactly([4.0])


func test_a_restart_change_leaves_the_running_value_unchanged() -> void:
	var sim := Simulation.new(_settings())

	sim.queue_command(Commands.SetSetting.new("run", "starting_lives", 5))
	sim.tick()

	assert_int(sim.settings.value("run", "starting_lives")).is_equal(20)
	assert_int(sim.settings.for_next_run().value("run", "starting_lives")).is_equal(5)


func test_an_invalid_change_is_rejected_and_leaves_the_value_unchanged() -> void:
	var sim := Simulation.new(_settings())
	var rejections: Array[String] = []
	sim.command_rejected.connect(func(reason: String) -> void: rejections.append(reason))

	sim.queue_command(Commands.SetSetting.new("towers", "fire_rate", 50.0))
	sim.tick()

	assert_array(rejections).has_size(1)
	assert_str(rejections[0]).contains("towers.fire_rate")
	assert_float(sim.settings.value("towers", "fire_rate")).is_equal(2.0)


func test_a_change_to_an_unknown_setting_is_rejected() -> void:
	var sim := Simulation.new(_settings())
	var rejections: Array[String] = []
	sim.command_rejected.connect(func(reason: String) -> void: rejections.append(reason))

	sim.queue_command(Commands.SetSetting.new("run", "starting_mana", 5))
	sim.tick()

	assert_array(rejections).contains_exactly(["run.starting_mana: unknown setting"])


func _assert_rejected(result: Settings.LoadResult, expected: String) -> void:
	assert_object(result.settings).is_null()
	assert_str(result.error).contains(expected)
