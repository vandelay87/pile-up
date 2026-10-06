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
		"run": {"starting_lives": 20, "map_path": "res://data/maps/v1.json"},
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
	assert_str(settings.value("run", "map_path")).is_equal("res://data/maps/v1.json")


func test_the_committed_defaults_file_loads() -> void:
	var result := Settings.load_file(Settings.DEFAULTS_PATH)

	assert_str(result.error).is_empty()
	assert_object(result.settings).is_not_null()


func test_reads_the_committed_defaults_as_typed_values() -> void:
	var settings := Settings.load_file(Settings.DEFAULTS_PATH).settings

	assert_int(settings.starting_lives).is_equal(20)
	assert_int(settings.starting_gold).is_equal(150)
	assert_str(settings.map_path).is_equal("res://data/maps/v1.json")
	assert_float(settings.enemy_speed).is_equal_approx(1.5, 1e-6)
	assert_float(settings.pile_slow(1)).is_equal_approx(0.15, 1e-6)
	assert_float(settings.pile_slow(4)).is_equal_approx(0.6, 1e-6)
	assert_float(settings.direct_wall_weight).is_equal_approx(0.1, 1e-6)


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


func test_rejects_a_group_that_is_not_an_object() -> void:
	var data := _valid()
	data["run"] = 5

	_assert_rejected(_load(data), "run: expected an object of settings")


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


func test_rejects_a_value_off_the_step() -> void:
	var data := _valid()
	data["towers"]["fire_rate"] = 2.05

	_assert_rejected(_load(data), "towers.fire_rate: 2.05 is not a multiple of 0.1 from 0.1")


func test_accepts_a_float_on_the_step_despite_rounding() -> void:
	var data := _valid()
	data["towers"]["fire_rate"] = 0.3

	assert_str(_load(data).error).is_empty()


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


func _assert_rejected(result: Settings.LoadResult, expected: String) -> void:
	assert_object(result.settings).is_null()
	assert_str(result.error).contains(expected)
