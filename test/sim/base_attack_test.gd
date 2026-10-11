extends GdUnitTestSuite

const BASE_X := 7
const ARRIVAL_TICKS := 600

var _settings: Settings


func before_test() -> void:
	_settings = TestSettings.without_swarm_spread()
	_settings.change("enemies", "heading_offset", 0.0)


func test_an_enemy_reaching_the_base_stops_at_its_edge_and_attacks_it_at_2_hp_per_second() -> void:
	var sim := _corridor_sim()
	var id := sim.enemies.spawn(Vector2(0.5, 1.5), _settings.enemy_hp)
	_run_until_attacked(sim)
	var hp_before := sim.run_state.base_hp

	for tick in Simulation.TICKS_PER_SECOND:
		sim.tick()

	assert_float(hp_before - sim.run_state.base_hp).is_equal_approx(2.0, 1e-6)
	var pos := sim.enemies.positions[sim.enemies.index_of(id)]
	assert_float(pos.x).is_less_equal(BASE_X - _settings.separation_radius + 1e-4)
	assert_float(pos.x).is_greater(BASE_X - _settings.separation_radius - _settings.wall_reach)


func test_several_attackers_add_up() -> void:
	var sim := _corridor_sim()
	for y in 3:
		sim.enemies.spawn(Vector2(5.5, 0.5 + y), _settings.enemy_hp)
	for tick in ARRIVAL_TICKS / 4:
		sim.tick()
	var hp_before := sim.run_state.base_hp

	for tick in Simulation.TICKS_PER_SECOND:
		sim.tick()

	assert_float(hp_before - sim.run_state.base_hp).is_equal_approx(6.0, 1e-6)


func test_an_enemy_beside_the_base_whose_route_leads_away_does_not_attack_it() -> void:
	# The base's north and west sides are rock, so an enemy in the pocket at its north-west
	# corner is pressed against the base but must walk round to reach it.
	_settings.change("enemies", "wall_reach", 0.3)
	_settings.change("enemies", "jam_seconds", 10.0)
	var rows: Array[String] = ["........", "........", "...#....", "..#.....", "........"]
	var sim := Simulation.new(_settings, TestMaps.from_rows(rows, Rect2i(3, 3, 1, 1)), 1)
	var id := sim.enemies.spawn(Vector2(2.7, 2.7), _settings.enemy_hp)

	for tick in 30:
		sim.tick()

	assert_float(sim.run_state.base_hp).is_equal(float(_settings.base_hp))
	var pos := sim.enemies.positions[sim.enemies.index_of(id)]
	assert_float(pos.distance_to(Vector2(3.0, 3.0))).is_greater(0.5)


func test_towers_kill_enemies_attacking_the_base() -> void:
	var sim := _corridor_sim()
	sim.queue_command(Commands.Build.new(Buildings.TOWER, Vector2i(4, 1)))
	sim.enemies.spawn(Vector2(6.5, 0.5), 30.0)
	sim.enemies.spawn(Vector2(6.5, 2.5), 30.0)
	_run_until_attacked(sim)
	assert_int(sim.buildings.built.size()).is_equal(1)
	var gold_before := sim.run_state.gold

	_run_until(sim, func() -> bool: return sim.enemies.count == 0)

	assert_int(sim.run_state.gold).is_equal(gold_before + 2 * _settings.enemy_bounty)
	assert_float(sim.run_state.base_hp).is_greater(0.0)


func test_base_hp_is_reported_when_it_changes() -> void:
	var sim := _corridor_sim()
	var reported: Array[float] = []
	sim.base_hp_changed.connect(func(hp: float) -> void: reported.append(hp))
	sim.enemies.spawn(Vector2(6.5, 1.5), _settings.enemy_hp)

	_run_until_attacked(sim)
	sim.tick()

	assert_int(reported.size()).is_greater_equal(2)
	assert_float(reported.back()).is_equal(sim.run_state.base_hp)


func test_the_run_ends_when_the_base_is_destroyed_and_only_a_restart_is_accepted() -> void:
	_settings.change("run", "base_hp", 1)
	var sim := Simulation.new(_settings.for_next_run(), _corridor_map(), 1)
	var events: Array[String] = []
	sim.game_over.connect(func() -> void: events.append("game over"))
	sim.restart_requested.connect(func() -> void: events.append("restart"))
	sim.command_rejected.connect(func(reason: String) -> void: events.append(reason))
	sim.enemies.spawn(Vector2(6.5, 1.5), _settings.enemy_hp)

	_run_until(sim, func() -> bool: return sim.run_state.is_game_over)
	var positions_at_game_over := sim.enemies.positions.slice(0, sim.enemies.count)
	for tick in 60:
		sim.tick()
	sim.queue_command(Commands.NextWave.new())
	sim.queue_command(Commands.AddGold.new(10))
	sim.queue_command(Commands.Restart.new())
	sim.tick()

	assert_float(sim.run_state.base_hp).is_equal(0.0)
	(
		assert_array(events)
		. contains_exactly(
			[
				"game over",
				"next wave: the run is over",
				"add gold: the run is over",
				"restart",
			]
		)
	)
	assert_array(Array(sim.enemies.positions.slice(0, sim.enemies.count))).is_equal(
		Array(positions_at_game_over)
	)


func _corridor_map() -> MapData:
	var rows: Array[String] = ["........", "........", "........"]
	return TestMaps.from_rows(rows, Rect2i(BASE_X, 0, 1, 3))


func _corridor_sim() -> Simulation:
	return Simulation.new(_settings, _corridor_map(), 1)


func _run_until_attacked(sim: Simulation) -> void:
	var full := sim.run_state.base_hp
	_run_until(sim, func() -> bool: return sim.run_state.base_hp < full)


func _run_until(sim: Simulation, done: Callable) -> void:
	for tick in ARRIVAL_TICKS:
		sim.tick()
		if done.call():
			return
	fail("the condition was not met within %d ticks" % ARRIVAL_TICKS)
