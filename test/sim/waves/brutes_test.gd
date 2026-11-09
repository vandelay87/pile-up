extends GdUnitTestSuite

# Brutes in the waves: from the first brute wave, a stepped count rolled per wave on its own seed,
# taking spawn slots after the bloaters; the build phase lists each special type; and the debug
# SpawnEnemies action sends brutes at once.

const WAVE_TICKS := 6000

var _sim: Simulation


func before_test() -> void:
	_sim = _sim_with_seed(1)


func test_with_no_roll_the_count_steps_up_every_6_waves_from_wave_12() -> void:
	_set_chances(0, 0)

	for wave in range(1, 12):
		assert_int(_sim.waves.brute_count(wave)).is_equal(0)
	for wave in range(12, 18):
		assert_int(_sim.waves.brute_count(wave)).is_equal(1)
	assert_int(_sim.waves.brute_count(18)).is_equal(2)
	assert_int(_sim.waves.brute_count(24)).is_equal(3)


func test_a_miss_takes_one_off_and_an_extra_adds_one() -> void:
	_set_chances(100, 0)
	assert_int(_sim.waves.brute_count(11)).is_equal(0)
	assert_int(_sim.waves.brute_count(12)).is_equal(0)
	assert_int(_sim.waves.brute_count(18)).is_equal(1)

	_set_chances(0, 100)
	assert_int(_sim.waves.brute_count(11)).is_equal(0)
	assert_int(_sim.waves.brute_count(12)).is_equal(2)


func test_the_brute_roll_follows_the_seed_apart_from_the_bloater_roll() -> void:
	var brutes := _brute_counts(_sim)
	var bloaters: Array[int] = []
	for wave in range(5, 60):
		bloaters.append(_sim.waves.bloater_count(wave))

	assert_array(brutes).is_not_equal(bloaters)
	assert_array(_brute_counts(_sim)).is_equal(brutes)
	assert_array(_brute_counts(_sim_with_seed(1))).is_equal(brutes)
	assert_array(_brute_counts(_sim_with_seed(2))).is_not_equal(brutes)


func test_special_counts_list_each_kind_and_give_brutes_fewer_when_the_wave_is_full() -> void:
	_set_chances(0, 0)
	assert_dict(_sim.waves.special_counts(18)).is_equal({"bloaters": 3, "jumpers": 44, "brutes": 2})
	assert_dict(_sim.waves.special_counts(4)).is_equal({"bloaters": 0, "jumpers": 0, "brutes": 0})

	_sim.settings.change("waves", "growth", 1.0)
	_sim.settings.change("bloaters", "waves_per_step", 1)
	# Wave 30 is 20 enemies with 26 bloaters wanted: no room is left for brutes.
	assert_dict(_sim.waves.special_counts(30)).is_equal({"bloaters": 20, "jumpers": 0, "brutes": 0})


func test_a_wave_spawns_exactly_its_special_counts_with_brutes_on_the_direct_route() -> void:
	_set_chances(0, 0)
	_sim.settings.change("brutes", "waves_per_step", 1)
	var wave := 14
	var counts := _sim.waves.special_counts(wave)
	assert_int(counts["brutes"]).is_equal(3)
	var spawned := {}
	for kind: Enemies.Kind in Enemies.Kind.values():
		spawned[kind] = 0
	_sim.queue_command(Commands.JumpToWave.new(wave))
	var seen := {}
	for tick in WAVE_TICKS:
		_sim.tick()
		for i in _sim.enemies.count:
			var id := _sim.enemies.ids[i]
			if seen.has(id):
				continue
			seen[id] = true
			spawned[_sim.enemies.kinds[i]] += 1
			if _sim.enemies.kinds[i] == Enemies.Kind.BRUTE:
				assert_int(_sim.enemies.routes[i]).is_equal(Routing.Route.DIRECT)
				assert_float(_sim.enemies.hp[i]).is_equal_approx(40.0 * pow(1.05, wave - 1), 1e-3)
		if _sim.waves.phase == Waves.Phase.BUILD:
			break
		_sim.queue_command(Commands.KillEnemies.new(_sim.enemies.count))

	assert_int(_sim.waves.phase).is_equal(Waves.Phase.BUILD)
	assert_int(spawned[Enemies.Kind.BRUTE]).is_equal(counts["brutes"])
	assert_int(spawned[Enemies.Kind.BLOATER]).is_equal(counts["bloaters"])
	assert_int(seen.size()).is_equal(_sim.waves.size(wave))


func test_enemies_left_reports_the_next_waves_specials_in_the_build_phase_only() -> void:
	_set_chances(0, 0)
	var reports: Array = []
	_sim.enemies_left_changed.connect(
		func(left: int, specials: Dictionary) -> void: reports.append([left, specials])
	)
	_sim.queue_command(Commands.JumpToWave.new(17))
	_sim.tick()

	assert_dict(reports[-1][1]).is_empty()
	for tick in WAVE_TICKS:
		if _sim.waves.phase == Waves.Phase.BUILD:
			break
		_sim.queue_command(Commands.KillEnemies.new(_sim.enemies.count))
		_sim.tick()

	assert_int(reports[-1][0]).is_equal(_sim.waves.size(18))
	assert_dict(reports[-1][1]).is_equal({"bloaters": 3, "jumpers": 44, "brutes": 2})
	assert_dict(_sim.next_wave_specials).is_equal(reports[-1][1])


func test_spawn_enemies_sends_brutes_as_one_burst_on_a_spawn_edge_at_this_waves_hp() -> void:
	_sim.queue_command(Commands.SpawnEnemies.new(Enemies.Kind.BRUTE, 4))

	_sim.tick()

	assert_int(_sim.enemies.count).is_equal(4)
	for i in _sim.enemies.count:
		assert_int(_sim.enemies.kinds[i]).is_equal(Enemies.Kind.BRUTE)
		assert_int(_sim.enemies.routes[i]).is_equal(Routing.Route.DIRECT)
		assert_float(_sim.enemies.hp[i]).is_equal(40.0)
		# The north edge: the top row, give or take the jitter and a tick's walk.
		assert_float(_sim.enemies.positions[i].y).is_less(1.0)


func test_enemies_sent_during_a_wave_count_towards_nothing_in_it() -> void:
	_sim.queue_command(Commands.JumpToWave.new(3))
	_sim.tick()
	var left := _sim.enemies_left

	_sim.queue_command(Commands.SpawnEnemies.new(Enemies.Kind.BRUTE, 2))
	_sim.tick()
	var sent: Array[int] = []
	for i in _sim.enemies.count:
		if _sim.enemies.kinds[i] == Enemies.Kind.BRUTE:
			sent.append(_sim.enemies.ids[i])
			assert_float(_sim.enemies.hp[i]).is_equal_approx(40.0 * pow(1.05, 2), 1e-3)
	assert_int(sent.size()).is_equal(2)
	var gold := _sim.run_state.gold
	for id in sent:
		_sim.enemies.kill(id)
	_sim.tick()

	assert_int(_sim.enemies_left).is_equal(left)
	assert_int(_sim.run_state.gold - gold).is_equal(8)


func test_spawn_enemies_rejects_a_count_below_1() -> void:
	var rejections: Array[String] = []
	_sim.command_rejected.connect(func(reason: String) -> void: rejections.append(reason))

	_sim.queue_command(Commands.SpawnEnemies.new(Enemies.Kind.BRUTE, 0))
	_sim.tick()

	assert_int(_sim.enemies.count).is_equal(0)
	assert_array(rejections).has_size(1)


# Brute counts from wave 5 to 59, with the bloaters' numbers so only the rolls differ.
func _brute_counts(sim: Simulation) -> Array[int]:
	for key: String in ["first_wave", "waves_per_step", "miss_chance", "extra_chance"]:
		sim.settings.change("brutes", key, sim.settings.value("bloaters", key))
	var counts: Array[int] = []
	for wave in range(5, 60):
		counts.append(sim.waves.brute_count(wave))
	return counts


func _set_chances(miss_percent: int, extra_percent: int) -> void:
	for kind: String in ["bloaters", "brutes"]:
		assert_str(_sim.settings.change(kind, "miss_chance", miss_percent)).is_empty()
		assert_str(_sim.settings.change(kind, "extra_chance", extra_percent)).is_empty()


func _sim_with_seed(run_seed: int) -> Simulation:
	var rows: Array[String] = []
	for y in 8:
		rows.append("........")
	var edges: Array[String] = ["N"]
	var map := TestMaps.from_rows(rows, Rect2i(3, 3, 2, 2), edges)
	return Simulation.new(Settings.load_file(Settings.DEFAULTS_PATH).settings, map, run_seed)
