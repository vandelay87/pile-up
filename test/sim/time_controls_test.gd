extends GdUnitTestSuite

var _sim: Simulation


func before_test() -> void:
	_sim = Simulation.new(Settings.from_json("{}", {}).settings, TestMaps.open_field())


func test_pause_stops_ticks_advancing() -> void:
	_sim.queue_command(Commands.SetPaused.new(true))
	_sim.run_frame()
	var paused_at := _sim.tick_count

	for frame in 5:
		_sim.run_frame()

	assert_int(_sim.tick_count).is_equal(paused_at)


func test_step_advances_exactly_one_tick_while_paused() -> void:
	_sim.queue_command(Commands.SetPaused.new(true))
	_sim.run_frame()
	var paused_at := _sim.tick_count

	_sim.queue_command(Commands.StepOneTick.new())
	_sim.run_frame()
	_sim.run_frame()

	assert_int(_sim.tick_count).is_equal(paused_at + 1)


func test_speed_n_runs_n_ticks_per_frame() -> void:
	for speed: int in [1, 2, 4]:
		_sim.queue_command(Commands.SetSpeed.new(speed))
		_sim.run_frame()
		var before := _sim.tick_count

		_sim.run_frame()

		assert_int(_sim.tick_count - before).is_equal(speed)


func test_a_seed_and_recorded_commands_replay_to_an_identical_state() -> void:
	var frames := {
		0: [Commands.SpawnBurst.new(40)],
		5: [Commands.SetSetting.new("enemies", "speed", 3.0), Commands.SetSpeed.new(4)],
		10: [Commands.SetPaused.new(true)],
		12:
		[Commands.SetSetting.new("enemies", "separation_push", 0.2), Commands.StepOneTick.new()],
		13: [Commands.StepOneTick.new(), Commands.StepOneTick.new()],
		15: [Commands.SetPaused.new(false), Commands.SetSpeed.new(2)],
		20: [Commands.SetSetting.new("routing", "sensible_wall_weight", 2.0)],
	}
	var live := _crowd_sim()
	var recorded: Array[Array] = []
	for frame in 40:
		for command: Commands.Command in frames.get(frame, []):
			recorded.append([live.tick_count, command])
			live.queue_command(command)
		live.run_frame()

	var replay := _crowd_sim()
	for tick in live.tick_count:
		for entry in recorded:
			if entry[0] == tick:
				var command: Commands.Command = entry[1]
				replay.queue_command(command)
		replay.tick()

	assert_int(live.tick_count).is_equal(76)
	assert_int(replay.enemies.count).is_equal(live.enemies.count)
	assert_array(Array(replay.enemies.ids)).is_equal(Array(live.enemies.ids))
	assert_array(Array(replay.enemies.positions)).is_equal(Array(live.enemies.positions))
	assert_float(replay.settings.enemy_speed).is_equal(3.0)
	assert_float(replay.settings.separation_push).is_equal(0.2)
	assert_float(replay.settings.sensible_wall_weight).is_equal(2.0)
	assert_bool(replay.paused).is_equal(live.paused)
	assert_int(replay.speed).is_equal(2)
	for route: Routing.Route in Routing.Route.values():
		assert_array(_field_values(replay, route)).is_equal(_field_values(live, route))


func _field_values(sim: Simulation, route: Routing.Route) -> Array[float]:
	var values: Array[float] = []
	for y in sim.map.height:
		for x in sim.map.width:
			values.append(sim.routing.value(route, Vector2i(x, y)))
	return values


func _crowd_sim() -> Simulation:
	var settings := Settings.load_file(Settings.DEFAULTS_PATH).settings
	var rows: Array[String] = []
	for y in 16:
		rows.append("................")
	var edges: Array[String] = ["N", "E", "S", "W"]
	return Simulation.new(settings, TestMaps.from_rows(rows, Rect2i(7, 7, 2, 2), edges), 7)


func test_a_step_taken_while_running_does_not_advance_a_later_pause() -> void:
	_sim.queue_command(Commands.StepOneTick.new())
	_sim.queue_command(Commands.SetPaused.new(true))
	_sim.run_frame()
	var paused_at := _sim.tick_count

	_sim.run_frame()

	assert_int(_sim.tick_count).is_equal(paused_at)
