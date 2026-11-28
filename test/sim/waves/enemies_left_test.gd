extends GdUnitTestSuite

# Each wave enemy knows its wave. Enemies left is the open wave's enemies not yet killed,
# unspawned ones included, reported with the wave's size only during a wave. A wave ends when all
# its enemies have spawned and died; the trickle's and debug spawns count towards neither.

const WAVE_TICKS := 2000

var _sim: Simulation
var _reports: Array


func before_test() -> void:
	var settings := Settings.load_file(Settings.DEFAULTS_PATH).settings
	TestSettings.set_scatter_share(settings, 10)
	TestWaves.without_trickle(settings)
	var rows: Array[String] = []
	for y in 8:
		rows.append("........")
	var edges: Array[String] = ["N"]
	_sim = Simulation.new(settings, TestMaps.from_rows(rows, Rect2i(3, 3, 2, 2), edges), 1)
	_reports = []
	_sim.enemies_left_changed.connect(
		func(left: int, size: int) -> void: _reports.append([left, size])
	)


func test_nothing_is_reported_in_the_quiet() -> void:
	for tick in 60:
		_sim.tick()

	assert_int(_sim.waves.enemies_left).is_equal(0)
	assert_array(_reports).is_empty()


func test_enemies_left_starts_at_the_wave_size_with_unspawned_enemies_included() -> void:
	TestWaves.send_at(_sim, 3.0)

	# Threat 3's first burst: round(16 × 1.05²) = 18.
	assert_int(_sim.enemies.count).is_equal(18)
	assert_int(_sim.waves.enemies_left).is_equal(31)
	assert_array(_reports).contains_exactly([[31, 31]])


func test_each_wave_enemy_carries_its_waves_index() -> void:
	TestWaves.send_at(_sim, 1.0)
	TestWaves.kill_the_wave(_sim)
	for tick in Simulation.DECAY_REBUILD_TICKS + 1:
		_sim.tick()

	TestWaves.send_at(_sim, 1.0)

	assert_int(_sim.enemies.count).is_greater(0)
	for i in _sim.enemies.count:
		assert_int(_sim.enemies.waves[i]).is_equal(1)


func test_enemies_left_falls_by_one_per_kill_and_is_reported() -> void:
	TestWaves.send_at(_sim, 1.0)
	_reports.clear()

	_kill(1)
	_kill(2)

	assert_int(_sim.waves.enemies_left).is_equal(17)
	assert_array(_reports).contains_exactly([[19, 20], [17, 20]])
	assert_int(_sim.run_state.kills).is_equal(3)


func test_debug_spawns_count_towards_no_wave() -> void:
	TestWaves.send_at(_sim, 1.0)
	_sim.queue_command(Commands.SpawnEnemies.new(Enemies.Kind.BRUTE, 3))
	_sim.tick()
	var sent: Array[int] = []
	for i in _sim.enemies.count:
		if _sim.enemies.kinds[i] == Enemies.Kind.BRUTE:
			assert_int(_sim.enemies.waves[i]).is_equal(Waves.NO_WAVE)
			sent.append(_sim.enemies.ids[i])
	assert_int(sent.size()).is_equal(3)
	var left := _sim.waves.enemies_left

	for id in sent:
		_sim.enemies.kill(id)
	_sim.tick()

	assert_int(_sim.waves.enemies_left).is_equal(left)
	assert_int(_sim.run_state.kills).is_equal(3)


func test_the_wave_ends_with_its_last_enemy_whatever_else_is_alive() -> void:
	TestWaves.send_at(_sim, 1.0)
	_sim.queue_command(Commands.SpawnEnemies.new(Enemies.Kind.NORMAL, 5))
	_sim.tick()
	var ended := []
	_sim.wave_ended.connect(func() -> void: ended.append(_sim.tick_count))

	for tick in WAVE_TICKS:
		if _sim.waves.phase == Waves.Phase.QUIET:
			break
		for i in _sim.enemies.count:
			if _sim.enemies.waves[i] != Waves.NO_WAVE:
				_sim.enemies.kill(_sim.enemies.ids[i])
		_sim.tick()

	assert_int(_sim.waves.phase).is_equal(Waves.Phase.QUIET)
	assert_int(ended.size()).is_equal(1)
	assert_int(_sim.enemies.count).is_equal(5)


func test_kills_count_across_waves() -> void:
	TestWaves.send_at(_sim, 1.0)
	TestWaves.kill_the_wave(_sim)
	for tick in Simulation.DECAY_REBUILD_TICKS + 1:
		_sim.tick()

	TestWaves.send_at(_sim, 2.0)
	_kill(5)

	assert_int(_sim.waves.started).is_equal(2)
	assert_int(_sim.run_state.kills).is_equal(25)
	assert_int(_sim.waves.enemies_left).is_equal(20)


# Kills the first n enemies on the field in the next tick, as towers would.
func _kill(n: int) -> void:
	_sim.queue_command(Commands.KillEnemies.new(n))
	_sim.tick()
