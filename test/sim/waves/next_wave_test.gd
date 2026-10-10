extends GdUnitTestSuite

const EDGES: Array[String] = ["N", "S"]
const WAVE_TICKS := 2000

var _sim: Simulation
var _events: Array[String]


func before_test() -> void:
	var settings := Settings.load_file(Settings.DEFAULTS_PATH).settings
	var rows: Array[String] = []
	for y in 8:
		rows.append("........")
	_sim = Simulation.new(settings, TestMaps.from_rows(rows, Rect2i(3, 3, 2, 2), EDGES), 1)
	_events = []
	_sim.command_rejected.connect(func(reason: String) -> void: _events.append(reason))
	_sim.phase_changed.connect(
		func(phase: Waves.Phase) -> void: _events.append("phase %s" % Waves.Phase.find_key(phase))
	)
	_sim.wave_started.connect(
		func(edges: PackedStringArray) -> void: _events.append("wave %s" % ",".join(edges))
	)


func test_a_run_starts_in_the_build_phase_at_wave_0() -> void:
	assert_int(_sim.waves.phase).is_equal(Waves.Phase.BUILD)
	assert_int(_sim.run_state.wave).is_equal(0)


func test_next_wave_starts_the_next_wave_and_announces_its_edges() -> void:
	_sim.queue_command(Commands.NextWave.new())

	_sim.tick()

	assert_int(_sim.run_state.wave).is_equal(1)
	assert_int(_sim.waves.phase).is_equal(Waves.Phase.WAVE)
	assert_int(_sim.enemies.count).is_equal(16)
	assert_array(_events).contains_exactly(["phase WAVE", "wave %s" % ",".join(_sim.waves.edges)])


func test_next_wave_is_rejected_during_a_wave() -> void:
	_sim.queue_command(Commands.NextWave.new())
	_sim.tick()
	_events.clear()

	_sim.queue_command(Commands.NextWave.new())
	_sim.tick()

	assert_int(_sim.run_state.wave).is_equal(1)
	assert_array(_events).contains_exactly(["next wave: a wave is already running"])


func test_the_phase_returns_to_build_when_the_wave_ends() -> void:
	_sim.queue_command(Commands.NextWave.new())
	_sim.tick()
	_events.clear()

	_run_until_build_phase()

	assert_int(_sim.enemies.count).is_equal(0)
	assert_array(_events).contains_exactly(["phase BUILD"])
	for tick in Simulation.DECAY_REBUILD_TICKS + 1:
		_sim.tick()
	_sim.queue_command(Commands.NextWave.new())
	_sim.tick()
	assert_int(_sim.run_state.wave).is_equal(2)


func test_jump_to_wave_starts_that_wave_from_the_build_phase() -> void:
	_sim.queue_command(Commands.JumpToWave.new(12))
	_sim.tick()

	assert_int(_sim.run_state.wave).is_equal(12)
	assert_float(_sim.enemies.hp[0]).is_equal_approx(_sim.waves.enemy_hp(12), 1e-4)

	_events.clear()
	_sim.queue_command(Commands.JumpToWave.new(3))
	_sim.tick()

	assert_int(_sim.run_state.wave).is_equal(12)
	assert_array(_events).contains_exactly(["jump to wave: a wave is already running"])


func test_jump_to_wave_below_1_is_rejected() -> void:
	_sim.queue_command(Commands.JumpToWave.new(0))

	_sim.tick()

	assert_int(_sim.waves.phase).is_equal(Waves.Phase.BUILD)
	assert_array(_events).contains_exactly(["jump to wave: the wave must be at least 1"])


func test_add_gold_adds_to_the_run_gold() -> void:
	_sim.queue_command(Commands.AddGold.new(100))

	_sim.tick()

	assert_int(_sim.run_state.gold).is_equal(300)


func _run_until_build_phase() -> void:
	for tick in WAVE_TICKS:
		_sim.tick()
		if _sim.waves.phase == Waves.Phase.BUILD:
			return
		_clear_enemies()
	fail("the wave did not end within %d ticks" % WAVE_TICKS)


# Enemies no longer leave by reaching the base, so the wave is ended by taking them off the
# field outside the tick, leaving no bodies.
func _clear_enemies() -> void:
	for k in _sim.enemies.count:
		_sim.enemies.hp[k] = 0.0
	_sim.enemies.remove_dead()
