extends GdUnitTestSuite

# Bloaters: from the first bloater wave, a share of each wave's spawns are bloaters, picked at
# random among its clump bursts.

const WAVE_TICKS := 4000

var _sim: Simulation


func before_test() -> void:
	_sim = _sim_with_seed(1)


func test_bloater_count_is_0_before_wave_5_then_grows_with_its_share() -> void:
	for wave in range(1, 5):
		assert_int(_sim.waves.bloater_count(wave)).is_equal(0)
	assert_int(_sim.waves.bloater_count(5)).is_equal(1)
	assert_int(_sim.waves.bloater_count(10)).is_equal(5)
	assert_int(_sim.waves.bloater_count(15)).is_equal(23)
	assert_int(_sim.waves.bloater_count(20)).is_equal(69)


func test_a_wave_spawns_exactly_its_bloaters_among_its_spawns() -> void:
	var slots := _bloater_slots(_sim, 10)

	assert_int(_sim.run_state.kills).is_equal(149)
	assert_int(slots.size()).is_equal(5)
	assert_array(slots).is_not_equal([0, 1, 2, 3, 4])


func test_bloater_slots_are_picked_with_the_seed() -> void:
	assert_array(_bloater_slots(_sim_with_seed(7), 15)).is_equal(
		_bloater_slots(_sim_with_seed(7), 15)
	)
	assert_array(_bloater_slots(_sim_with_seed(8), 15)).is_not_equal(
		_bloater_slots(_sim_with_seed(7), 15)
	)


func test_waves_before_the_first_bloater_wave_spawn_none() -> void:
	assert_array(_bloater_slots(_sim, 4)).is_empty()
	assert_int(_sim.run_state.kills).is_equal(39)


func test_a_flooded_wave_spawns_only_bloaters_with_their_wave_hp() -> void:
	_sim.settings.change("bloaters", "share", 100.0)
	_sim.settings.change("bloaters", "share_cap", 100.0)
	_sim.queue_command(Commands.JumpToWave.new(20))
	_sim.tick()

	assert_int(_sim.enemies.count).is_equal(16)
	for i in _sim.enemies.count:
		assert_int(_sim.enemies.kinds[i]).is_equal(Enemies.Kind.BLOATER)
		assert_float(_sim.enemies.hp[i]).is_equal_approx(30.0 * pow(1.05, 19), 1e-3)


func test_the_build_phase_counts_the_next_waves_bloaters() -> void:
	_sim.queue_command(Commands.JumpToWave.new(9))
	_sim.tick()
	_kill_the_wave(_sim)

	assert_int(_sim.waves.phase).is_equal(Waves.Phase.BUILD)
	assert_int(_sim.enemies_left).is_equal(149)
	assert_int(_sim.next_wave_bloaters).is_equal(5)


func _sim_with_seed(run_seed: int) -> Simulation:
	var rows: Array[String] = []
	for y in 8:
		rows.append("........")
	var edges: Array[String] = ["N"]
	var map := TestMaps.from_rows(rows, Rect2i(3, 3, 2, 2), edges)
	return Simulation.new(Settings.load_file(Settings.DEFAULTS_PATH).settings, map, run_seed)


# Plays wave [param wave] from a fresh run, killing everything as it spawns, and returns the
# spawn slots (0 to size - 1) that were bloaters, in order.
func _bloater_slots(sim: Simulation, wave: int) -> Array[int]:
	var slots: Array[int] = []
	sim.queue_command(Commands.JumpToWave.new(wave))
	sim.tick()
	_kill_the_wave(
		sim,
		func(deaths: Deaths) -> void:
			for k in deaths.size():
				if deaths.kinds[k] == Enemies.Kind.BLOATER:
					slots.append(deaths.ids[k])
	)
	slots.sort()
	return slots


# Kills everything on the field each tick until the wave ends, handing each tick's deaths to
# [param on_deaths].
func _kill_the_wave(sim: Simulation, on_deaths := Callable()) -> void:
	for tick in WAVE_TICKS:
		if sim.waves.phase == Waves.Phase.BUILD:
			return
		sim.queue_command(Commands.KillEnemies.new(sim.enemies.count))
		sim.tick()
		if on_deaths.is_valid():
			on_deaths.call(sim.deaths)
	fail("the wave did not end within %d ticks" % WAVE_TICKS)
