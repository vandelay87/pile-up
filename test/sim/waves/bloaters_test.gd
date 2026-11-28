extends GdUnitTestSuite

# Bloaters: from threat 5, a stepped count of each wave's spawns, rolled per wave on its index,
# are bloaters, picked at random among its spawn slots.

const BIG := 10000

var _sim: Simulation


func before_test() -> void:
	_sim = _sim_with_seed(1)


func test_with_no_roll_the_count_steps_up_every_6_points_of_threat_from_threat_5() -> void:
	_set_chances(0, 0)

	for threat in range(1, 5):
		assert_int(_bloaters(threat)).is_equal(0)
	for threat in range(5, 11):
		assert_int(_bloaters(threat)).is_equal(1)
	for threat in range(11, 17):
		assert_int(_bloaters(threat)).is_equal(2)
	assert_int(_bloaters(17)).is_equal(3)
	assert_int(_bloaters(23)).is_equal(4)


func test_a_miss_takes_one_bloater_off_the_wave() -> void:
	_set_chances(100, 0)

	assert_int(_bloaters(4)).is_equal(0)
	assert_int(_bloaters(5)).is_equal(0)
	assert_int(_bloaters(11)).is_equal(1)


func test_an_extra_adds_one_bloater_to_the_wave() -> void:
	_set_chances(0, 100)

	assert_int(_bloaters(4)).is_equal(0)
	assert_int(_bloaters(5)).is_equal(2)
	assert_int(_bloaters(11)).is_equal(3)


func test_two_waves_at_one_threat_roll_apart_and_each_roll_follows_the_seed() -> void:
	var counts := _counts(_sim)

	var distinct := {}
	for count in counts:
		distinct[count] = true
	assert_int(distinct.size()).is_greater(1)
	assert_array(_counts(_sim)).is_equal(counts)
	assert_array(_counts(_sim_with_seed(1))).is_equal(counts)
	assert_array(_counts(_sim_with_seed(2))).is_not_equal(counts)


func test_a_wave_spawns_exactly_its_bloaters_among_its_spawns() -> void:
	_set_chances(0, 0)
	_sim.settings.change("bloaters", "threat_per_step", 1)

	var slots := _bloater_slots(_sim, 10.0)

	assert_int(_sim.run_state.kills).is_equal(149)
	assert_int(slots.size()).is_equal(6)
	assert_array(slots).is_not_equal([0, 1, 2, 3, 4, 5])


func test_bloater_slots_are_picked_with_the_seed() -> void:
	assert_array(_bloater_slots(_sim_with_seed(7), 15.0)).is_equal(
		_bloater_slots(_sim_with_seed(7), 15.0)
	)
	assert_array(_bloater_slots(_sim_with_seed(8), 15.0)).is_not_equal(
		_bloater_slots(_sim_with_seed(7), 15.0)
	)


func test_waves_below_threat_5_spawn_none() -> void:
	assert_array(_bloater_slots(_sim, 4.0)).is_empty()
	assert_int(_sim.run_state.kills).is_equal(39)


func test_a_flooded_wave_spawns_only_bloaters_at_their_flat_hp() -> void:
	_set_chances(0, 0)
	_sim.settings.change("bloaters", "first_threat", 1)
	_sim.settings.change("bloaters", "threat_per_step", 1)
	_sim.settings.change("waves", "growth", 1.0)
	TestWaves.send_at(_sim, 20.0)

	# 20 enemies, 2 of them scattered: the first burst is the other 18.
	assert_int(_sim.enemies.count).is_equal(18)
	for i in _sim.enemies.count:
		assert_int(_sim.enemies.kinds[i]).is_equal(Enemies.Kind.BLOATER)
		assert_float(_sim.enemies.hp[i]).is_equal(30.0)


func test_bloaters_take_scattered_slots_too() -> void:
	_set_chances(0, 0)
	_sim.settings.change("bloaters", "first_threat", 1)
	_sim.settings.change("bloaters", "threat_per_step", 1)
	_sim.settings.change("waves", "growth", 1.0)
	TestSettings.set_scatter_share(_sim.settings, 100)
	TestWaves.send_at(_sim, 20.0)

	for tick in 30:
		_sim.tick()

	# 20 enemies, all scattered, and 20 bloaters: every one of them is a bloater.
	assert_int(_sim.enemies.count).is_equal(20)
	for i in _sim.enemies.count:
		assert_int(_sim.enemies.kinds[i]).is_equal(Enemies.Kind.BLOATER)


func test_a_wave_announces_the_bloaters_it_spawns() -> void:
	var announced: Array[int] = []
	var spawned: Array[int] = []
	for run_seed in range(1, 9):
		var sim := _sim_with_seed(run_seed)
		sim.wave_started.connect(
			func(_edges: PackedStringArray, _size: int, specials: Dictionary) -> void:
				announced.append(specials["bloaters"])
		)
		spawned.append(_bloater_slots(sim, 7.0).size())

	assert_array(spawned).is_equal(announced)
	assert_array(announced).contains([0, 1])


# Wave 0 to 39's bloaters at threat 11.
func _counts(sim: Simulation) -> Array[int]:
	var counts: Array[int] = []
	for index in 40:
		counts.append(sim.waves.special_counts(11, BIG, index)["bloaters"])
	return counts


func _bloaters(threat: int) -> int:
	var count: int = _sim.waves.special_counts(threat, BIG, 0)["bloaters"]
	return count


func _set_chances(miss_percent: int, extra_percent: int) -> void:
	assert_str(_sim.settings.change("bloaters", "miss_chance", miss_percent)).is_empty()
	assert_str(_sim.settings.change("bloaters", "extra_chance", extra_percent)).is_empty()


func _sim_with_seed(run_seed: int) -> Simulation:
	var settings := Settings.load_file(Settings.DEFAULTS_PATH).settings
	TestWaves.without_trickle(settings)
	var rows: Array[String] = []
	for y in 8:
		rows.append("........")
	var edges: Array[String] = ["N"]
	var map := TestMaps.from_rows(rows, Rect2i(3, 3, 2, 2), edges)
	return Simulation.new(settings, map, run_seed)


# Plays a wave at [param threat] from a fresh run, killing everything as it spawns, and returns
# the ids (0 to size - 1, the spawn slots) that were bloaters, in order.
func _bloater_slots(sim: Simulation, threat: float) -> Array[int]:
	var slots: Array[int] = []
	TestWaves.send_at(sim, threat)
	var ended := TestWaves.kill_the_wave(
		sim,
		func(deaths: Deaths) -> void:
			for k in deaths.size():
				if deaths.kinds[k] == Enemies.Kind.BLOATER:
					slots.append(deaths.ids[k])
	)
	assert_bool(ended).is_true()
	slots.sort()
	return slots
