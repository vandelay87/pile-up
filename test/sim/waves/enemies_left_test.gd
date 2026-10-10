extends GdUnitTestSuite

const WAVE_TICKS := 2000

var _sim: Simulation
var _enemies_left: Array[int]
var _kills: Array[int]


func before_test() -> void:
	var settings := Settings.load_file(Settings.DEFAULTS_PATH).settings
	var rows: Array[String] = []
	for y in 8:
		rows.append("........")
	var edges: Array[String] = ["N"]
	_sim = Simulation.new(settings, TestMaps.from_rows(rows, Rect2i(3, 3, 2, 2), edges), 1)
	_enemies_left = []
	_kills = []
	_sim.enemies_left_changed.connect(func(left: int) -> void: _enemies_left.append(left))
	_sim.kills_changed.connect(func(kills: int) -> void: _kills.append(kills))


func test_enemies_left_shows_the_first_wave_size_before_the_run_starts() -> void:
	assert_int(_sim.enemies_left).is_equal(20)


func test_enemies_left_starts_at_the_wave_size_with_unspawned_enemies_included() -> void:
	_sim.queue_command(Commands.JumpToWave.new(3))

	_sim.tick()

	assert_int(_sim.enemies.count).is_equal(16)
	assert_int(_sim.enemies_left).is_equal(34)


func test_enemies_left_falls_by_one_per_kill_and_is_reported() -> void:
	_sim.queue_command(Commands.NextWave.new())
	_sim.tick()
	_enemies_left.clear()

	_kill(1)
	_kill(2)

	assert_int(_sim.enemies_left).is_equal(17)
	assert_array(_enemies_left).contains_exactly([19, 17])
	assert_int(_sim.run_state.kills).is_equal(3)
	assert_array(_kills).contains_exactly([1, 3])


func test_enemies_left_reaches_0_as_the_wave_ends_then_shows_the_next_wave_size() -> void:
	_sim.queue_command(Commands.NextWave.new())
	_sim.tick()

	_kill_the_wave()

	assert_int(_sim.waves.phase).is_equal(Waves.Phase.BUILD)
	assert_array(_enemies_left.slice(-2)).contains_exactly([0, 26])
	assert_int(_sim.enemies_left).is_equal(26)


func test_kills_count_across_waves() -> void:
	_sim.queue_command(Commands.NextWave.new())
	_sim.tick()
	_kill_the_wave()
	for tick in Simulation.DECAY_REBUILD_TICKS + 1:
		_sim.tick()

	_sim.queue_command(Commands.NextWave.new())
	_sim.tick()
	_kill(5)

	assert_int(_sim.run_state.wave).is_equal(2)
	assert_int(_sim.run_state.kills).is_equal(25)
	assert_int(_sim.enemies_left).is_equal(21)


# Kills the first n enemies on the field in the next tick, as towers would.
func _kill(n: int) -> void:
	_sim.queue_command(Commands.KillEnemies.new(n))
	_sim.tick()


func _kill_the_wave() -> void:
	for tick in WAVE_TICKS:
		if _sim.waves.phase == Waves.Phase.BUILD:
			return
		_kill(_sim.enemies.count)
	fail("the wave did not end within %d ticks" % WAVE_TICKS)
