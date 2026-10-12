extends GdUnitTestSuite

# The bloater: slow and tough, it pays 2 and never adds to a pile.

const TICKS := 60

var _sim: Simulation


func before_test() -> void:
	var settings := TestSettings.without_swarm_spread()
	settings.change("enemies", "heading_offset", 0.0)
	# One shot of 50 damage at once, enough to kill either kind.
	settings.change("towers", "damage", 50.0)
	settings.change("towers", "cost", 50)
	settings.change("run", "base_power_area", 30)
	var rows: Array[String] = []
	for y in 30:
		rows.append("..............................")
	var edges: Array[String] = ["N"]
	_sim = Simulation.new(settings, TestMaps.from_rows(rows, Rect2i(14, 27, 2, 2), edges), 1)


func test_a_bloater_walks_at_its_own_speed() -> void:
	_sim.enemies.spawn(Vector2(5.5, 2.5), 30.0, Enemies.Kind.BLOATER)
	_sim.enemies.spawn(Vector2(24.5, 2.5), 10.0)
	var starts := _sim.enemies.positions.duplicate()

	for tick in TICKS:
		_sim.tick()

	# A second's walk: 1.6 cells for the bloater, 2 for a normal enemy.
	var bloater_walk := _sim.enemies.positions[0].distance_to(starts[0])
	var normal_walk := _sim.enemies.positions[1].distance_to(starts[1])
	assert_float(bloater_walk).is_equal_approx(1.6, 0.05)
	assert_float(normal_walk).is_equal_approx(2.0, 0.05)


func test_killing_a_bloater_pays_2_and_leaves_no_body() -> void:
	_sim.enemies.spawn(Vector2(6.5, 6.5), 30.0, Enemies.Kind.BLOATER)
	_sim.queue_command(Commands.Build.new(Buildings.TOWER, Vector2i(2, 2)))
	_sim.tick()
	var gold := _sim.run_state.gold

	assert_int(_sim.deaths.size()).is_equal(1)
	assert_int(_sim.deaths.kinds[0]).is_equal(Enemies.Kind.BLOATER)
	assert_int(_sim.run_state.payout).is_equal(2)
	_sim.tick()
	assert_int(_sim.piles.level(Vector2i(6, 6))).is_equal(0)
	assert_int(_sim.run_state.gold).is_equal(gold)


func test_a_normal_enemy_killed_the_same_way_pays_1_and_leaves_a_body() -> void:
	_sim.enemies.spawn(Vector2(6.5, 6.5), 10.0)
	_sim.queue_command(Commands.Build.new(Buildings.TOWER, Vector2i(2, 2)))
	_sim.tick()

	assert_int(_sim.run_state.payout).is_equal(1)
	_sim.tick()
	assert_int(_sim.piles.level(Vector2i(6, 6))).is_equal(1)
