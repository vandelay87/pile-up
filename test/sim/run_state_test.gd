extends GdUnitTestSuite

var _settings: Settings
var _run: RunState


func before_test() -> void:
	_settings = Settings.load_file(Settings.DEFAULTS_PATH).settings
	_run = RunState.new(_settings)


func test_a_run_starts_with_the_starting_lives_and_gold_at_wave_0() -> void:
	assert_int(_run.lives).is_equal(20)
	assert_int(_run.gold).is_equal(150)
	assert_int(_run.wave).is_equal(0)
	assert_bool(_run.is_game_over).is_false()


func test_a_kill_adds_the_bounty() -> void:
	_settings.change("enemies", "bounty", 3)

	_run.record_removals(2, 0)

	assert_int(_run.gold).is_equal(156)


func test_a_leak_costs_1_life() -> void:
	_run.record_removals(0, 1)

	assert_int(_run.lives).is_equal(19)
	assert_bool(_run.is_game_over).is_false()


func test_the_run_is_over_at_0_lives_and_lives_never_go_below_0() -> void:
	_run.record_removals(0, 25)

	assert_int(_run.lives).is_equal(0)
	assert_bool(_run.is_game_over).is_true()


func test_can_afford_compares_the_cost_with_gold() -> void:
	assert_bool(_run.can_afford(150)).is_true()
	assert_bool(_run.can_afford(151)).is_false()

	_run.add_gold(1)

	assert_bool(_run.can_afford(151)).is_true()


func test_a_kill_in_a_tick_adds_the_bounty_and_reports_the_gold() -> void:
	var sim := _sim(_settings)
	var reported: Array[int] = []
	sim.gold_changed.connect(func(gold: int) -> void: reported.append(gold))
	sim.queue_command(Commands.NextWave.new())
	sim.tick()

	sim.enemies.damage(sim.enemies.ids[0], 100.0)
	sim.tick()

	assert_int(sim.run_state.gold).is_equal(151)
	assert_array(reported).contains_exactly([151])


func test_a_leak_in_a_tick_costs_a_life_and_reports_the_lives() -> void:
	var sim := _sim(_settings)
	var reported: Array[int] = []
	sim.lives_changed.connect(func(lives: int) -> void: reported.append(lives))
	sim.queue_command(Commands.NextWave.new())

	_run_until(sim, func() -> bool: return sim.run_state.lives < 20)

	assert_int(sim.run_state.lives).is_equal(19)
	assert_array(reported).contains_exactly([19])


func test_game_over_fires_once_at_0_lives_and_then_only_restart_is_accepted() -> void:
	_settings.change("run", "starting_lives", 1)
	var sim := _sim(_settings.for_next_run())
	var events: Array[String] = []
	sim.game_over.connect(func() -> void: events.append("game over"))
	sim.restart_requested.connect(func() -> void: events.append("restart"))
	sim.command_rejected.connect(func(reason: String) -> void: events.append(reason))
	sim.queue_command(Commands.NextWave.new())

	_run_until(sim, func() -> bool: return sim.run_state.is_game_over)
	var enemies_at_game_over := sim.enemies.positions.slice(0, sim.enemies.count)
	for tick in 60:
		sim.tick()
	sim.queue_command(Commands.NextWave.new())
	sim.queue_command(Commands.AddGold.new(10))
	sim.queue_command(Commands.Restart.new())
	sim.tick()

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
		Array(enemies_at_game_over)
	)


func test_the_next_run_is_a_fresh_simulation_with_pending_restart_settings() -> void:
	var sim := _sim(_settings)
	sim.queue_command(Commands.NextWave.new())
	sim.queue_command(Commands.SetSetting.new("run", "starting_gold", 500))
	for tick in 30:
		sim.tick()

	var next := sim.next_run(2)

	assert_object(next).is_not_same(sim)
	assert_object(next.map).is_same(sim.map)
	assert_int(next.run_state.gold).is_equal(500)
	assert_int(next.run_state.wave).is_equal(0)
	assert_int(next.waves.phase).is_equal(Waves.Phase.BUILD)
	assert_int(next.enemies.count).is_equal(0)


func _sim(settings: Settings) -> Simulation:
	var rows: Array[String] = []
	for y in 8:
		rows.append("........")
	var edges: Array[String] = ["N"]
	return Simulation.new(settings, TestMaps.from_rows(rows, Rect2i(3, 3, 2, 2), edges), 1)


func _run_until(sim: Simulation, done: Callable) -> void:
	for tick in 2000:
		sim.tick()
		if done.call():
			return
	fail("the condition was not met within 2000 ticks")
