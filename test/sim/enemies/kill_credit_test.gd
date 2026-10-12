extends GdUnitTestSuite

# Kill credit: every death knows which building killed it. The removal step's death list
# holds each dead enemy's position, kind, killer and blast flag, in removal order.

const TOUGH := 1000.0

var _sim: Simulation


func before_test() -> void:
	var settings := Settings.load_file(Settings.DEFAULTS_PATH).settings
	settings.change("enemies", "speed", 0.1)
	settings.change("enemies", "heading_offset", 0.0)
	# Shots of 3 damage every 30 ticks.
	settings.change("towers", "fire_rate", 2.0)
	settings.change("towers", "damage", 3.0)
	settings.change("towers", "cost", 50)
	settings.change("run", "base_power_area", 20)
	var rows: Array[String] = []
	for y in 20:
		rows.append("....................")
	var edges: Array[String] = ["N"]
	_sim = Simulation.new(settings, TestMaps.from_rows(rows, Rect2i(18, 18, 2, 2), edges), 1)


func test_a_towers_kill_has_that_tower_as_killer() -> void:
	_sim.enemies.spawn(Vector2(6.5, 6.5), 3.0)
	_sim.queue_command(Commands.Build.new(Buildings.TOWER, Vector2i(2, 2)))

	_sim.tick()

	assert_int(_sim.deaths.size()).is_equal(1)
	assert_int(_sim.deaths.killers[0]).is_equal(_sim.buildings.built[0].id)
	assert_int(_sim.deaths.kinds[0]).is_equal(Enemies.Kind.NORMAL)
	assert_int(_sim.deaths.blasts[0]).is_equal(0)


func test_a_debug_kill_has_no_killer_even_after_a_tower_hit() -> void:
	_sim.enemies.spawn(Vector2(6.5, 6.5), TOUGH)
	_sim.queue_command(Commands.Build.new(Buildings.TOWER, Vector2i(2, 2)))
	_sim.tick()
	assert_int(_sim.deaths.size()).is_equal(0)

	_sim.queue_command(Commands.KillEnemies.new(1))
	_sim.tick()

	assert_int(_sim.deaths.size()).is_equal(1)
	assert_int(_sim.deaths.killers[0]).is_equal(Enemies.NONE)


func test_deaths_keep_removal_order_with_each_killer_beside_its_position() -> void:
	# The debug kill takes the first enemy; the tower kills the one nearest the base. Removal
	# swaps the last enemy into the first's slot, so the tower's kill is removed second.
	_sim.enemies.spawn(Vector2(5.5, 5.5), TOUGH)
	_sim.enemies.spawn(Vector2(4.5, 4.5), TOUGH)
	_sim.enemies.spawn(Vector2(6.5, 6.5), 3.0)
	_sim.queue_command(Commands.KillEnemies.new(1))
	_sim.queue_command(Commands.Build.new(Buildings.TOWER, Vector2i(2, 2)))

	_sim.tick()

	var tower := _sim.buildings.built[0].id
	assert_int(_sim.deaths.size()).is_equal(2)
	assert_vector(_sim.deaths.positions[0]).is_equal_approx(Vector2(5.5, 5.5), Vector2(0.1, 0.1))
	assert_vector(_sim.deaths.positions[1]).is_equal_approx(Vector2(6.5, 6.5), Vector2(0.1, 0.1))
	assert_array(Array(_sim.deaths.killers)).contains_exactly([Enemies.NONE, tower])
