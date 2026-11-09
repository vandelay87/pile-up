extends GdUnitTestSuite

# Jumpers in the waves: from the first jumper wave, a share of the wave rounded, capped when the
# cap is on, taking spawn slots after the bloaters and before the brutes; and the debug
# SpawnEnemies action sends jumpers at once.

const WAVE_TICKS := 6000

var _sim: Simulation


func before_test() -> void:
	var rows: Array[String] = []
	for y in 8:
		rows.append("........")
	var edges: Array[String] = ["N"]
	var map := TestMaps.from_rows(rows, Rect2i(3, 3, 2, 2), edges)
	_sim = Simulation.new(Settings.load_file(Settings.DEFAULTS_PATH).settings, map, 1)
	for kind: String in ["bloaters", "brutes"]:
		_sim.settings.change(kind, "miss_chance", 0)
		_sim.settings.change(kind, "extra_chance", 0)


func test_none_before_wave_8_then_5_percent_of_the_wave_rounded() -> void:
	for wave in range(1, 8):
		assert_int(_sim.waves.jumper_count(wave)).is_equal(0)
	# Waves 8, 15 and 20 are 95, 455 and 1,388 enemies.
	assert_int(_sim.waves.jumper_count(8)).is_equal(5)
	assert_int(_sim.waves.jumper_count(15)).is_equal(23)
	assert_int(_sim.waves.jumper_count(20)).is_equal(69)


func test_the_cap_limits_the_count_when_it_is_above_0() -> void:
	_sim.settings.change("jumpers", "cap", 10)
	assert_int(_sim.waves.jumper_count(8)).is_equal(5)
	assert_int(_sim.waves.jumper_count(20)).is_equal(10)

	_sim.settings.change("jumpers", "cap", 0)
	assert_int(_sim.waves.jumper_count(20)).is_equal(69)


func test_the_share_and_first_wave_are_live() -> void:
	_sim.settings.change("jumpers", "share", 10)
	_sim.settings.change("jumpers", "first_wave", 2)

	# Wave 2 is 25 enemies.
	assert_int(_sim.waves.jumper_count(2)).is_equal(3)
	assert_int(_sim.waves.jumper_count(1)).is_equal(0)


func test_special_counts_put_jumpers_after_bloaters_and_before_brutes() -> void:
	assert_dict(_sim.waves.special_counts(15)).is_equal({"bloaters": 2, "jumpers": 23, "brutes": 1})

	_sim.settings.change("waves", "growth", 1.0)
	_sim.settings.change("jumpers", "share", 100)
	_sim.settings.change("jumpers", "first_wave", 1)
	# Wave 12 is 20 enemies with 2 bloaters: the jumpers take the other 18 and no brute fits.
	assert_dict(_sim.waves.special_counts(12)).is_equal({"bloaters": 2, "jumpers": 18, "brutes": 0})


func test_a_wave_spawns_exactly_its_special_counts_with_jumpers_on_the_direct_route() -> void:
	var wave := 9
	var counts := _sim.waves.special_counts(wave)
	assert_int(counts["jumpers"]).is_equal(6)
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
			if _sim.enemies.kinds[i] == Enemies.Kind.JUMPER:
				assert_int(_sim.enemies.routes[i]).is_equal(Routing.Route.DIRECT)
				assert_float(_sim.enemies.hp[i]).is_equal_approx(10.0 * pow(1.05, wave - 1), 1e-3)
		if _sim.waves.phase == Waves.Phase.BUILD:
			break
		_sim.queue_command(Commands.KillEnemies.new(_sim.enemies.count))

	assert_int(_sim.waves.phase).is_equal(Waves.Phase.BUILD)
	assert_int(spawned[Enemies.Kind.JUMPER]).is_equal(counts["jumpers"])
	assert_int(spawned[Enemies.Kind.BLOATER]).is_equal(counts["bloaters"])
	assert_int(spawned[Enemies.Kind.BRUTE]).is_equal(counts["brutes"])
	assert_int(seen.size()).is_equal(_sim.waves.size(wave))


func test_spawn_enemies_sends_jumpers() -> void:
	_sim.queue_command(Commands.SpawnEnemies.new(Enemies.Kind.JUMPER, 3))

	_sim.tick()

	assert_int(_sim.enemies.count).is_equal(3)
	for i in _sim.enemies.count:
		assert_int(_sim.enemies.kinds[i]).is_equal(Enemies.Kind.JUMPER)
		assert_int(_sim.enemies.routes[i]).is_equal(Routing.Route.DIRECT)
		assert_float(_sim.enemies.hp[i]).is_equal(10.0)
