extends GdUnitTestSuite

# Denser spawning: a wave comes out as bursts, each on one stretch of a spawn edge, with a share
# of scattered enemies spread singly between them, at a spawn rate that grows with threat. A wave
# at threat n with the roll off and a size factor of 1 is v5's wave n.

const S := Waves.SCATTERED

var _settings: Settings
var _map: MapData
var _enemies: Enemies


func before_test() -> void:
	_settings = Settings.load_file(Settings.DEFAULTS_PATH).settings
	TestWaves.without_trickle(_settings)
	_settings.change("waves", "size_roll", 0)
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


# Sends a wave at [param threat] at Off, its size factor ×1, and steps once: it starts and its
# first entry spawns. Returns the threat to step it on with.
func _start(waves: Waves, threat: float) -> Threat:
	var at := Threat.new(_settings)
	at.value = threat
	waves.send_wave()
	waves.step(Miners.Pace.OFF, at, false)
	return at


func _rng(run_seed: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = run_seed
	return rng


func test_the_scatter_share_falls_from_90_to_10_percent_by_threat_12_then_holds() -> void:
	var waves := _waves()

	assert_float(waves.scatter_share(1)).is_equal_approx(0.9, 1e-6)
	# 80 points over the 11 points of threat from 1 to 12: threat 6 is 5 of them down, and the
	# share runs on between whole points.
	assert_float(waves.scatter_share(6)).is_equal_approx(0.9 - 0.8 * 5.0 / 11.0, 1e-6)
	assert_float(waves.scatter_share(12)).is_equal_approx(0.1, 1e-6)
	assert_float(waves.scatter_share(30)).is_equal_approx(0.1, 1e-6)
	assert_float(waves.scatter_share(6.5)).is_equal_approx(0.9 - 0.8 * 5.5 / 11.0, 1e-6)


func test_threat_1s_plan_is_one_burst_of_2_then_18_scattered_enemies() -> void:
	var plan := _waves().spawn_plan(1.0, 20)

	assert_int(plan[0]).is_equal(2)
	assert_int(plan.size()).is_equal(19)
	assert_int(plan.count(S)).is_equal(18)


func test_threat_10s_plan_has_bursts_of_25_and_37_scattered_spread_evenly_between_them() -> void:
	# 149 enemies: 37 scattered (24.5%, two thirds of the way down from 90% to 10%), and 112 in
	# bursts of round(16 × 1.05^9) = 25, the fifth one short.
	var plan := _waves().spawn_plan(10.0, 149)

	assert_array(_bursts(plan)).is_equal([25, 25, 25, 25, 12])
	assert_array(_scattered_after_each_burst(plan)).is_equal([8, 7, 8, 7, 7])


func test_threat_20s_plan_has_31_bursts_of_40_a_short_one_and_139_scattered() -> void:
	# 1,388 enemies: 139 scattered, and 1,249 in bursts of round(16 × 1.05^19) = 40.
	var plan := _waves().spawn_plan(20.0, 1388)
	var bursts := _bursts(plan)

	assert_int(plan.count(S)).is_equal(139)
	assert_int(bursts.size()).is_equal(32)
	assert_int(bursts.count(40)).is_equal(31)
	assert_int(bursts[31]).is_equal(9)
	assert_int(plan[0]).is_equal(40)
	assert_int(plan[plan.size() - 1]).is_equal(S)


func test_a_bursts_enemies_all_land_within_its_stretch_of_the_edge() -> void:
	_use_map(64, ["N"])
	TestSettings.set_scatter_share(_settings, 10)
	for run_seed in range(1, 41):
		_clear_enemies()
		_start(_waves(run_seed), 1.0)

		assert_int(_enemies.count).is_equal(16)
		# A stretch 6 cells wide: the centre cell and 3 either side, plus ±0.25 jitter.
		assert_float(_spread_along_x()).is_less_equal(6.5)


func test_the_stretch_widens_with_the_square_root_of_the_burst() -> void:
	_use_map(64, ["N"])
	TestSettings.set_scatter_share(_settings, 10)
	_settings.change("waves", "growth", 2.0)
	_settings.change("waves", "burst_growth", 2.0)
	var widest := 0.0
	for run_seed in range(1, 41):
		_clear_enemies()
		_start(_waves(run_seed), 3.0)

		# Threat 3's wave is 80 enemies, 72 of them in bursts of 16 × 2² = 64, which take a
		# stretch 6 × √4 = 12 cells wide.
		assert_int(_enemies.count).is_equal(64)
		widest = maxf(widest, _spread_along_x())
	assert_float(widest).is_greater(6.5)
	assert_float(widest).is_less_equal(12.5)


func test_scattered_enemies_land_alone_between_the_bursts() -> void:
	TestSettings.set_scatter_share(_settings, 10)
	var waves := _waves()
	var threat := _start(waves, 1.0)
	var landings: Array[int] = [_enemies.count]
	var edges := waves.open_waves()[0].edges

	for tick in 10 * Simulation.TICKS_PER_SECOND:
		var before := _enemies.count
		waves.step(Miners.Pace.OFF, threat, false)
		if _enemies.count > before:
			landings.append(_enemies.count - before)

	assert_array(landings).is_equal([16, 1, 2, 1])
	var spawn_cells: Array[Vector2i] = []
	for edge in edges:
		spawn_cells.append_array(_map.spawn_cells(edge))
	for k in _enemies.count:
		assert_array(spawn_cells).contains([Vector2i(_enemies.positions[k].floor())])


func test_the_average_rate_over_a_wave_is_the_grown_spawn_rate() -> void:
	var waves := _waves()
	var threat := _start(waves, 10.0)
	var ticks := 1

	while _enemies.count < 149:
		waves.step(Miners.Pace.OFF, threat, false)
		ticks += 1

	# 10 × 1.1^9 ≈ 23.58 enemies/s at threat 10. The first burst of 25 lands as the wave starts,
	# and the other 124 enemies take 124 ÷ 23.58 ≈ 5.26 s, or about 316 ticks.
	assert_int(ticks).is_between(314, 318)


func test_a_wave_spawns_exactly_its_size_whatever_the_burst_and_scatter() -> void:
	for share: int in [0, 10, 50, 100]:
		_clear_enemies()
		TestSettings.set_scatter_share(_settings, share)
		var waves := _waves()
		var threat := _start(waves, 10.0)

		for tick in 60 * Simulation.TICKS_PER_SECOND:
			waves.step(Miners.Pace.OFF, threat, false)

		assert_int(_enemies.count).is_equal(149)


func _bursts(plan: PackedInt32Array) -> Array:
	return Array(plan).filter(func(entry: int) -> bool: return entry != S)


func _scattered_after_each_burst(plan: PackedInt32Array) -> Array[int]:
	var runs: Array[int] = []
	for entry in plan:
		if entry != S:
			runs.append(0)
		else:
			runs[runs.size() - 1] += 1
	return runs


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
