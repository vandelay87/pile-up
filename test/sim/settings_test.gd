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
		"base_hp":
		{
			"type": TYPE_INT,
			"min": 1,
			"max": 100,
			"step": 1,
			"unit": "HP",
			"apply": Settings.Apply.RESTART,
		},
		"map_path": {"type": TYPE_STRING, "unit": "path", "apply": Settings.Apply.RESTART},
	},
}

# group, key, min, max, step
const _SWARM_RANGES := [
	["enemies", "speed_variety", 0, 50, 1],
	["enemies", "wander", 0.0, 90.0, 1.0],
	["enemies", "wander_period", 0.5, 20.0, 0.5],
	["enemies", "personal_space_radius", 0.0, 3.0, 0.05],
	["enemies", "personal_space_push", 0.0, 1.0, 0.01],
	["waves", "clump_size", 1, 50, 1],
]


func _valid() -> Dictionary:
	return {
		"towers": {"fire_rate": 2},
		"run": {"base_hp": 20, "map_path": "res://data/maps/v1.json"},
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
	assert_int(settings.value("run", "base_hp")).is_equal(20)
	assert_str(settings.value("run", "map_path")).is_equal("res://data/maps/v1.json")


func test_the_committed_defaults_file_loads() -> void:
	var result := Settings.load_file(Settings.DEFAULTS_PATH)

	assert_str(result.error).is_empty()
	assert_object(result.settings).is_not_null()


func test_reads_the_committed_defaults_as_typed_values() -> void:
	var settings := Settings.load_file(Settings.DEFAULTS_PATH).settings

	assert_int(settings.base_hp).is_equal(200)
	assert_int(settings.starting_gold).is_equal(200)
	assert_str(settings.map_path).is_equal("res://data/maps/v2-narrow.json")
	assert_float(settings.enemy_speed).is_equal_approx(2.0, 1e-6)
	assert_float(settings.wall_damage).is_equal_approx(2.0, 1e-6)
	assert_float(settings.wall_hp).is_equal_approx(15.0, 1e-6)
	assert_float(settings.tower_damage).is_equal_approx(5.0, 1e-6)
	assert_int(settings.tower_cooldown_ticks).is_equal(17)
	assert_int(settings.tower_cost).is_equal(80)
	assert_float(settings.tower_hp).is_equal_approx(60.0, 1e-6)
	assert_float(settings.pile_slow(1)).is_equal_approx(0.15, 1e-6)
	assert_float(settings.pile_slow(4)).is_equal_approx(0.6, 1e-6)
	assert_float(settings.direct_wall_weight).is_equal_approx(0.1, 1e-6)
	assert_float(settings.enemy_hp).is_equal_approx(10.0, 1e-6)
	assert_int(settings.enemy_bounty).is_equal(1)
	assert_float(settings.separation_radius).is_equal_approx(0.3, 1e-6)
	assert_float(settings.separation_push).is_equal_approx(0.5, 1e-6)
	assert_int(settings.neighbour_cap).is_equal(0)
	assert_int(settings.wave_1_size).is_equal(20)
	assert_float(settings.wave_growth).is_equal_approx(1.3, 1e-6)
	assert_float(settings.hp_growth).is_equal_approx(1.05, 1e-6)
	assert_float(settings.spawn_rate).is_equal_approx(10.0, 1e-6)
	assert_float(settings.second_edge_chance).is_equal_approx(0.5, 1e-6)


func test_converts_the_enemy_and_swarm_spread_settings_to_sim_units() -> void:
	var settings := Settings.load_file(Settings.DEFAULTS_PATH).settings

	assert_float(settings.enemy_speed_per_tick).is_equal_approx(2.0 / 60.0, 1e-6)
	assert_float(settings.heading_offset_radians).is_equal_approx(deg_to_rad(10.0), 1e-6)
	assert_float(settings.speed_variety).is_equal_approx(0.03, 1e-6)
	assert_float(settings.wander_radians).is_equal_approx(deg_to_rad(30.0), 1e-6)
	assert_float(settings.wander_period_ticks).is_equal_approx(240.0, 1e-6)
	assert_float(settings.personal_space_radius).is_equal_approx(0.7, 1e-6)
	assert_float(settings.personal_space_push).is_equal_approx(0.06, 1e-6)
	assert_int(settings.clump_size).is_equal(16)


func test_the_swarm_spread_settings_accept_their_range_on_the_step() -> void:
	for row: Array in _SWARM_RANGES:
		var settings := Settings.load_file(Settings.DEFAULTS_PATH).settings
		var group: String = row[0]
		var key: String = row[1]
		for accepted: float in [row[2], row[3], row[2] + row[4]]:
			assert_str(settings.change(group, key, accepted)).is_empty()
		assert_str(settings.change(group, key, row[2] - row[4])).contains("is outside")
		assert_str(settings.change(group, key, row[3] + row[4])).contains("is outside")
		var off_step: float = row[2] + row[4] * 0.5
		assert_str(settings.change(group, key, off_step)).is_not_empty()


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
	run.erase("base_hp")

	_assert_rejected(_load(data), "run.base_hp: missing")


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
	data["run"]["base_hp"] = "20"

	_assert_rejected(_load(data), "run.base_hp: expected int")


func test_rejects_a_fractional_int() -> void:
	var data := _valid()
	data["run"]["base_hp"] = 20.5

	_assert_rejected(_load(data), "run.base_hp: expected int")


func test_rejects_an_out_of_range_value() -> void:
	var data := _valid()
	data["run"]["base_hp"] = 0

	_assert_rejected(_load(data), "run.base_hp: 0 is outside 1 to 100")


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
	data["run"]["base_hp"] = 0
	data["towers"]["fire_rate"] = "fast"

	var result := _load(data)

	assert_str(result.error).contains("run.base_hp").contains("towers.fire_rate")


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
