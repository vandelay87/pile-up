extends GdUnitTestSuite

# Denser spawning: a wave comes out as bursts, each on one stretch of a spawn edge, with a share
# of scattered enemies spread singly between them, at a spawn rate that grows each wave.

const S := Waves.SCATTERED

var _settings: Settings
var _map: MapData
var _enemies: Enemies


func before_test() -> void:
	_settings = Settings.load_file(Settings.DEFAULTS_PATH).settings
	_use_map(16, ["N", "E", "S", "W"])


func _use_map(width: int, edges: Array[String]) -> void:
	var rows: Array[String] = []
	for y in 16:
		rows.append(".".repeat(width))
	_map = TestMaps.from_rows(rows, Rect2i(width / 2 - 1, 7, 2, 2), edges)
	var systems := TestSystems.new(_settings, _map)
	_enemies = systems.enemies(systems.routing(), _rng(1))


func _waves(run_seed: int = 1) -> Waves:
	return Waves.new(_settings, _map, _enemies, _rng(run_seed), run_seed)


func _rng(run_seed: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = run_seed
	return rng


func test_wave_1s_plan_is_a_burst_of_16_and_one_of_2_each_followed_by_a_scattered_enemy() -> void:
	assert_array(_waves().spawn_plan(1)).is_equal([16, S, 2, S])


func test_wave_10s_plan_has_bursts_of_25_and_15_scattered_spread_evenly_between_them() -> void:
	# 149 enemies: 15 scattered (10%), and 134 in bursts of round(16 × 1.05^9) = 25.
	(
		assert_array(_waves().spawn_plan(10))
		. is_equal(
			[
				25,
				S,
				S,
				S,
				25,
				S,
				S,
				25,
				S,
				S,
				S,
				25,
				S,
				S,
				25,
				S,
				S,
				S,
				9,
				S,
				S,
			]
		)
	)


func test_wave_20s_plan_has_31_bursts_of_40_a_short_one_and_139_scattered() -> void:
	# 1,388 enemies: 139 scattered, and 1,249 in bursts of round(16 × 1.05^19) = 40.
	var plan := _waves().spawn_plan(20)
	var bursts := Array(plan).filter(func(entry: int) -> bool: return entry != S)

	assert_int(plan.count(S)).is_equal(139)
	assert_int(bursts.size()).is_equal(32)
	assert_int(bursts.count(40)).is_equal(31)
	assert_int(bursts[31]).is_equal(9)
	assert_int(plan[0]).is_equal(40)
	assert_int(plan[plan.size() - 1]).is_equal(S)


func test_a_bursts_enemies_all_land_within_its_stretch_of_the_edge() -> void:
	_use_map(64, ["N"])
	for run_seed in range(1, 41):
		_clear_enemies()
		var waves := _waves(run_seed)
		waves.start(1)

		waves.spawn()

		assert_int(_enemies.count).is_equal(16)
		# A stretch 6 cells wide: the centre cell and 3 either side, plus ±0.25 jitter.
		assert_float(_spread_along_x()).is_less_equal(6.5)


func test_the_stretch_widens_with_the_square_root_of_the_burst() -> void:
	_use_map(64, ["N"])
	_settings.change("waves", "growth", 2.0)
	_settings.change("waves", "burst_growth", 2.0)
	var widest := 0.0
	for run_seed in range(1, 41):
		_clear_enemies()
		var waves := _waves(run_seed)
		waves.start(3)

		waves.spawn()

		# Wave 3 is 80 enemies, 72 of them in bursts of 16 × 2² = 64, which take a
		# stretch 6 × √4 = 12 cells wide.
		assert_int(_enemies.count).is_equal(64)
		widest = maxf(widest, _spread_along_x())
	assert_float(widest).is_greater(6.5)
	assert_float(widest).is_less_equal(12.5)


func test_scattered_enemies_land_alone_between_the_bursts() -> void:
	var waves := _waves()
	waves.start(1)
	var landings: Array[int] = []

	for tick in 10 * Simulation.TICKS_PER_SECOND:
		var before := _enemies.count
		waves.spawn()
		if _enemies.count > before:
			landings.append(_enemies.count - before)

	assert_array(landings).is_equal([16, 1, 2, 1])
	var spawn_cells: Array[Vector2i] = []
	for edge in waves.edges:
		spawn_cells.append_array(_map.spawn_cells(edge))
	for k in _enemies.count:
		assert_array(spawn_cells).contains([Vector2i(_enemies.positions[k].floor())])


func test_the_average_rate_over_a_wave_is_the_grown_spawn_rate() -> void:
	var waves := _waves()
	waves.start(10)
	var ticks := 0

	while _enemies.count < 149:
		waves.spawn()
		ticks += 1

	# 10 × 1.1^9 ≈ 23.58 enemies/s. The first burst of 25 lands as the wave starts, and the
	# other 124 enemies take 124 ÷ 23.58 ≈ 5.26 s, or about 316 ticks.
	assert_int(ticks).is_between(314, 318)


func test_a_wave_spawns_exactly_its_size_whatever_the_burst_and_scatter() -> void:
	for share: int in [0, 10, 50, 100]:
		_clear_enemies()
		_settings.change("waves", "scatter_share", share)
		var waves := _waves()
		waves.start(10)

		for tick in 60 * Simulation.TICKS_PER_SECOND:
			waves.spawn()

		assert_int(_enemies.count).is_equal(149)


func _spread_along_x() -> float:
	var low := INF
	var high := -INF
	for k in _enemies.count:
		low = minf(low, _enemies.positions[k].x)
		high = maxf(high, _enemies.positions[k].x)
	return high - low


func _clear_enemies() -> void:
	for k in _enemies.count:
		_enemies.hp[k] = 0.0
	_enemies.remove_dead()
