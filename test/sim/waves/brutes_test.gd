extends GdUnitTestSuite

# Brutes in the waves: from threat 12, a stepped count rolled per wave on its own seed, taking
# spawn slots after the bloaters; and the debug SpawnEnemies action sends brutes at once.

const BIG := 10000

var _sim: Simulation


func before_test() -> void:
	_sim = _sim_with_seed(1)


func test_with_no_roll_the_count_steps_up_every_6_points_of_threat_from_threat_12() -> void:
	_set_chances(0, 0)

	for threat in range(1, 12):
		assert_int(_brutes(_sim, threat)).is_equal(0)
	for threat in range(12, 18):
		assert_int(_brutes(_sim, threat)).is_equal(1)
	assert_int(_brutes(_sim, 18)).is_equal(2)
	assert_int(_brutes(_sim, 24)).is_equal(3)


func test_a_miss_takes_one_off_and_an_extra_adds_one() -> void:
	_set_chances(100, 0)
	assert_int(_brutes(_sim, 11)).is_equal(0)
	assert_int(_brutes(_sim, 12)).is_equal(0)
	assert_int(_brutes(_sim, 18)).is_equal(1)

	_set_chances(0, 100)
	assert_int(_brutes(_sim, 11)).is_equal(0)
	assert_int(_brutes(_sim, 12)).is_equal(2)


func test_the_brute_roll_follows_the_seed_apart_from_the_bloater_roll() -> void:
	var brutes := _brute_counts(_sim)
	var bloaters: Array[int] = []
	for index in 60:
		var count: int = _sim.waves.special_counts(11, BIG, index)["bloaters"]
		bloaters.append(count)

	assert_array(brutes).is_not_equal(bloaters)
	assert_array(_brute_counts(_sim)).is_equal(brutes)
	assert_array(_brute_counts(_sim_with_seed(1))).is_equal(brutes)
	assert_array(_brute_counts(_sim_with_seed(2))).is_not_equal(brutes)


func test_special_counts_list_each_kind_and_give_brutes_fewer_when_the_wave_is_full() -> void:
	_set_chances(0, 0)
	assert_dict(_sim.waves.special_counts(18, 888, 0)).is_equal(
		{"bloaters": 3, "jumpers": 44, "brutes": 2}
	)
	assert_dict(_sim.waves.special_counts(4, 39, 0)).is_equal(
		{"bloaters": 0, "jumpers": 0, "brutes": 0}
	)

	_sim.settings.change("bloaters", "threat_per_step", 1)
	# 20 enemies with 26 bloaters wanted: no room is left for brutes.
	assert_dict(_sim.waves.special_counts(30, 20, 0)).is_equal(
		{"bloaters": 20, "jumpers": 0, "brutes": 0}
	)


func test_a_wave_spawns_exactly_its_special_counts_with_brutes_on_the_direct_route() -> void:
	_set_chances(0, 0)
	_sim.settings.change("brutes", "threat_per_step", 1)
	var specials := {}
	_sim.wave_started.connect(
		func(_edges: PackedStringArray, _size: int, counts: Dictionary) -> void:
			specials.merge(counts)
	)
	var spawned := {}
	for kind: Enemies.Kind in Enemies.Kind.values():
		spawned[kind] = 0
	var seen := {}
	TestWaves.send_at(_sim, 14.0)
	assert_int(specials["brutes"]).is_equal(3)
	for tick in 6000:
		for i in _sim.enemies.count:
			var id := _sim.enemies.ids[i]
			if seen.has(id):
				continue
			seen[id] = true
			spawned[_sim.enemies.kinds[i]] += 1
			if _sim.enemies.kinds[i] == Enemies.Kind.BRUTE:
				assert_int(_sim.enemies.routes[i]).is_equal(Routing.Route.DIRECT)
				assert_float(_sim.enemies.hp[i]).is_equal(40.0)
		if _sim.waves.phase == Waves.Phase.QUIET:
			break
		_sim.queue_command(Commands.KillEnemies.new(maxi(1, _sim.enemies.count)))
		_sim.tick()

	assert_int(_sim.waves.phase).is_equal(Waves.Phase.QUIET)
	assert_int(spawned[Enemies.Kind.BRUTE]).is_equal(specials["brutes"])
	assert_int(spawned[Enemies.Kind.BLOATER]).is_equal(specials["bloaters"])
	assert_int(seen.size()).is_equal(364)


func test_spawn_enemies_sends_brutes_as_one_burst_on_a_spawn_edge() -> void:
	_sim.queue_command(Commands.SpawnEnemies.new(Enemies.Kind.BRUTE, 4))

	_sim.tick()

	assert_int(_sim.enemies.count).is_equal(4)
	for i in _sim.enemies.count:
		assert_int(_sim.enemies.kinds[i]).is_equal(Enemies.Kind.BRUTE)
		assert_int(_sim.enemies.routes[i]).is_equal(Routing.Route.DIRECT)
		assert_float(_sim.enemies.hp[i]).is_equal(40.0)
		# The north edge: the top row, give or take the jitter and a tick's walk.
		assert_float(_sim.enemies.positions[i].y).is_less(1.0)


func test_spawn_enemies_rejects_a_count_below_1() -> void:
	var rejections: Array[String] = []
	_sim.command_rejected.connect(func(reason: String) -> void: rejections.append(reason))

	_sim.queue_command(Commands.SpawnEnemies.new(Enemies.Kind.BRUTE, 0))
	_sim.tick()

	assert_int(_sim.enemies.count).is_equal(0)
	assert_array(rejections).has_size(1)


# Wave 0 to 59's brutes at threat 11, with the bloaters' numbers so only the rolls differ.
func _brute_counts(sim: Simulation) -> Array[int]:
	for key: String in ["first_threat", "threat_per_step", "miss_chance", "extra_chance"]:
		sim.settings.change("brutes", key, sim.settings.value("bloaters", key))
	var counts: Array[int] = []
	for index in 60:
		var count: int = sim.waves.special_counts(11, BIG, index)["brutes"]
		counts.append(count)
	return counts


func _brutes(sim: Simulation, threat: int) -> int:
	var count: int = sim.waves.special_counts(threat, BIG, 0)["brutes"]
	return count


func _set_chances(miss_percent: int, extra_percent: int) -> void:
	for kind: String in ["bloaters", "brutes"]:
		assert_str(_sim.settings.change(kind, "miss_chance", miss_percent)).is_empty()
		assert_str(_sim.settings.change(kind, "extra_chance", extra_percent)).is_empty()


func _sim_with_seed(run_seed: int) -> Simulation:
	var settings := Settings.load_file(Settings.DEFAULTS_PATH).settings
	TestWaves.without_trickle(settings)
	var rows: Array[String] = []
	for y in 8:
		rows.append("........")
	var edges: Array[String] = ["N"]
	var map := TestMaps.from_rows(rows, Rect2i(3, 3, 2, 2), edges)
	return Simulation.new(settings, map, run_seed)
