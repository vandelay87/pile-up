extends GdUnitTestSuite

# Jumpers in the waves: from threat 8, a share of the wave rounded, capped when the cap is on,
# taking spawn slots after the bloaters and before the brutes; and the debug SpawnEnemies action
# sends jumpers at once.

var _sim: Simulation


func before_test() -> void:
	var settings := Settings.load_file(Settings.DEFAULTS_PATH).settings
	TestWaves.without_trickle(settings)
	var rows: Array[String] = []
	for y in 8:
		rows.append("........")
	var edges: Array[String] = ["N"]
	var map := TestMaps.from_rows(rows, Rect2i(3, 3, 2, 2), edges)
	_sim = Simulation.new(settings, map, 1)
	for kind: String in ["bloaters", "brutes"]:
		_sim.settings.change(kind, "miss_chance", 0)
		_sim.settings.change(kind, "extra_chance", 0)


func test_none_below_threat_8_then_5_percent_of_the_wave_rounded() -> void:
	for threat in range(1, 8):
		assert_int(_jumpers(threat, 95)).is_equal(0)
	assert_int(_jumpers(8, 95)).is_equal(5)
	assert_int(_jumpers(15, 455)).is_equal(23)
	assert_int(_jumpers(20, 1388)).is_equal(69)


func test_the_cap_limits_the_count_when_it_is_above_0() -> void:
	_sim.settings.change("jumpers", "cap", 10)
	assert_int(_jumpers(8, 95)).is_equal(5)
	assert_int(_jumpers(20, 1388)).is_equal(10)

	_sim.settings.change("jumpers", "cap", 0)
	assert_int(_jumpers(20, 1388)).is_equal(69)


func test_the_share_and_first_threat_are_live() -> void:
	_sim.settings.change("jumpers", "share", 10)
	_sim.settings.change("jumpers", "first_threat", 2)

	assert_int(_jumpers(2, 25)).is_equal(3)
	assert_int(_jumpers(1, 25)).is_equal(0)


func test_special_counts_put_jumpers_after_bloaters_and_before_brutes() -> void:
	assert_dict(_sim.waves.special_counts(15, 455, 0)).is_equal(
		{"bloaters": 2, "jumpers": 23, "brutes": 1}
	)

	_sim.settings.change("jumpers", "share", 100)
	_sim.settings.change("jumpers", "first_threat", 1)
	# 20 enemies with 2 bloaters: the jumpers take the other 18 and no brute fits.
	assert_dict(_sim.waves.special_counts(12, 20, 0)).is_equal(
		{"bloaters": 2, "jumpers": 18, "brutes": 0}
	)


func test_a_wave_spawns_exactly_its_special_counts_with_jumpers_on_the_direct_route() -> void:
	var specials := {}
	_sim.wave_started.connect(
		func(_edges: PackedStringArray, _size: int, counts: Dictionary) -> void:
			specials.merge(counts)
	)
	var spawned := {}
	for kind: Enemies.Kind in Enemies.Kind.values():
		spawned[kind] = 0
	var seen := {}
	TestWaves.send_at(_sim, 9.0)
	assert_int(specials["jumpers"]).is_equal(6)
	for tick in 6000:
		for i in _sim.enemies.count:
			var id := _sim.enemies.ids[i]
			if seen.has(id):
				continue
			seen[id] = true
			spawned[_sim.enemies.kinds[i]] += 1
			if _sim.enemies.kinds[i] == Enemies.Kind.JUMPER:
				assert_int(_sim.enemies.routes[i]).is_equal(Routing.Route.DIRECT)
				assert_float(_sim.enemies.hp[i]).is_equal(10.0)
		if _sim.waves.phase == Waves.Phase.QUIET:
			break
		_sim.queue_command(Commands.KillEnemies.new(maxi(1, _sim.enemies.count)))
		_sim.tick()

	assert_int(_sim.waves.phase).is_equal(Waves.Phase.QUIET)
	assert_int(spawned[Enemies.Kind.JUMPER]).is_equal(specials["jumpers"])
	assert_int(spawned[Enemies.Kind.BLOATER]).is_equal(specials["bloaters"])
	assert_int(spawned[Enemies.Kind.BRUTE]).is_equal(specials["brutes"])
	assert_int(seen.size()).is_equal(119)


func test_spawn_enemies_sends_jumpers() -> void:
	_sim.queue_command(Commands.SpawnEnemies.new(Enemies.Kind.JUMPER, 3))

	_sim.tick()

	assert_int(_sim.enemies.count).is_equal(3)
	for i in _sim.enemies.count:
		assert_int(_sim.enemies.kinds[i]).is_equal(Enemies.Kind.JUMPER)
		assert_int(_sim.enemies.routes[i]).is_equal(Routing.Route.DIRECT)
		assert_float(_sim.enemies.hp[i]).is_equal(10.0)


func _jumpers(threat: int, size: int) -> int:
	var count: int = _sim.waves.special_counts(threat, size, 0)["jumpers"]
	return count
