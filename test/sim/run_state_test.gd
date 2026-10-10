extends GdUnitTestSuite

var _settings: Settings
var _run: RunState


func before_test() -> void:
	_settings = Settings.load_file(Settings.DEFAULTS_PATH).settings
	_run = RunState.new(_settings)


func test_a_run_starts_with_200_base_hp_and_200_gold_at_wave_0() -> void:
	assert_float(_run.base_hp).is_equal(200.0)
	assert_int(_run.gold).is_equal(200)
	assert_int(_run.wave).is_equal(0)
	assert_bool(_run.is_game_over).is_false()


func test_a_kill_adds_the_bounty() -> void:
	_settings.change("enemies", "bounty", 3)

	_run.record_kills(2)

	assert_int(_run.gold).is_equal(206)


func test_damage_lowers_base_hp() -> void:
	_run.damage_base(0.5)

	assert_float(_run.base_hp).is_equal(199.5)
	assert_bool(_run.is_game_over).is_false()


func test_the_run_is_over_at_0_base_hp_and_base_hp_never_goes_below_0() -> void:
	_run.damage_base(250.0)

	assert_float(_run.base_hp).is_equal(0.0)
	assert_bool(_run.is_game_over).is_true()


func test_can_afford_compares_the_cost_with_gold() -> void:
	assert_bool(_run.can_afford(200)).is_true()
	assert_bool(_run.can_afford(201)).is_false()

	_run.add_gold(1)

	assert_bool(_run.can_afford(201)).is_true()


func test_a_kill_in_a_tick_adds_the_bounty_and_reports_the_gold() -> void:
	var sim := _sim(_settings)
	var reported: Array[int] = []
	sim.gold_changed.connect(func(gold: int) -> void: reported.append(gold))
	sim.queue_command(Commands.NextWave.new())
	sim.tick()

	sim.enemies.damage(sim.enemies.ids[0], 100.0)
	sim.tick()

	assert_int(sim.run_state.gold).is_equal(201)
	assert_array(reported).contains_exactly([201])


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


func test_restart_is_accepted_while_paused() -> void:
	var sim := _sim(_settings)
	var restarts: Array[bool] = []
	sim.restart_requested.connect(func() -> void: restarts.append(true))
	sim.queue_command(Commands.SetPaused.new(true))
	sim.run_frame()

	sim.queue_command(Commands.Restart.new())
	sim.run_frame()

	assert_array(restarts).contains_exactly([true])


func _sim(settings: Settings) -> Simulation:
	var rows: Array[String] = []
	for y in 8:
		rows.append("........")
	var edges: Array[String] = ["N"]
	return Simulation.new(settings, TestMaps.from_rows(rows, Rect2i(3, 3, 2, 2), edges), 1)
