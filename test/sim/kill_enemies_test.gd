extends GdUnitTestSuite

# The debug "kill enemies" command: the first n enemies on the field die on the tick it is
# drained, and are removed at step 7 like any kill. They die before moving, so they stand
# still and attack nothing that tick.

var _sim: Simulation
var _events: Array[String]


func before_test() -> void:
	var settings := TestSettings.without_swarm_spread()
	settings.change("waves", "clump_size", 20)
	var rows: Array[String] = []
	for y in 12:
		rows.append("............")
	var edges: Array[String] = ["N"]
	_sim = Simulation.new(settings, TestMaps.from_rows(rows, Rect2i(5, 9, 2, 2), edges), 1)
	_events = []
	_sim.command_rejected.connect(func(reason: String) -> void: _events.append(reason))
	_sim.queue_command(Commands.NextWave.new())
	_sim.tick()


func test_kill_enemies_kills_the_first_n_on_the_field_that_tick() -> void:
	var survivors := Array(_sim.enemies.ids.slice(5, _sim.enemies.count))

	_sim.queue_command(Commands.KillEnemies.new(5))
	_sim.tick()

	assert_int(_sim.enemies.count).is_equal(15)
	(
		assert_array(Array(_sim.enemies.ids.slice(0, _sim.enemies.count)))
		. contains_exactly_in_any_order(survivors)
	)


func test_killed_enemies_count_as_kills_pay_and_leave_bodies() -> void:
	var gold := _sim.run_state.gold

	_sim.queue_command(Commands.KillEnemies.new(3))
	_sim.tick()
	_sim.tick()

	assert_int(_sim.run_state.kills).is_equal(3)
	assert_int(_sim.enemies_left).is_equal(17)
	assert_int(_sim.run_state.gold - gold).is_equal(3 * _sim.settings.enemy_bounty)
	var bodies := 0
	for level in _sim.piles.levels:
		bodies += level
	assert_int(bodies).is_equal(3)


func test_a_killed_enemy_attacks_nothing_on_the_tick_it_dies() -> void:
	var start_hp := _sim.run_state.base_hp
	for tick in 2000:
		if _sim.run_state.base_hp < start_hp:
			break
		_sim.tick()
	assert_float(_sim.run_state.base_hp).is_less(start_hp)
	var hp := _sim.run_state.base_hp

	_sim.queue_command(Commands.KillEnemies.new(1000))
	_sim.tick()

	assert_float(_sim.run_state.base_hp).is_equal(hp)


func test_kill_enemies_beyond_the_field_kills_them_all() -> void:
	_sim.queue_command(Commands.KillEnemies.new(1000))
	_sim.tick()

	assert_int(_sim.enemies.count).is_equal(0)
	assert_int(_sim.run_state.kills).is_equal(20)


func test_kill_enemies_below_1_is_rejected() -> void:
	_sim.queue_command(Commands.KillEnemies.new(0))
	_sim.tick()

	assert_int(_sim.enemies.count).is_equal(20)
	assert_array(_events).contains_exactly(["kill enemies: the count must be at least 1"])
