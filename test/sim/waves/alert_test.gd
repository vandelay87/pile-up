extends GdUnitTestSuite

# The alert fills in the quiet at the pace's speed (60 s at High, ×0.6 at Low, ×0.8 at Medium),
# not at Off, and at ×0.8 whatever the pace once every deposit is dry. At 75% the next wave's
# edges are picked; full, a wave starts and the alert empties, staying empty until that wave's
# last enemy dies.

const EDGES: Array[String] = ["N", "E", "S", "W"]
const TEN_SECONDS := 600
const WAVE_TICKS := 4000

var _sim: Simulation
var _settings: Settings
var _events: Array[String]


func before_test() -> void:
	_settings = Settings.load_file(Settings.DEFAULTS_PATH).settings
	_sim = _make_sim(Vector2i(MapData.DEFAULT_BASE_GOLD, MapData.DEFAULT_BASE_AETHER))


func test_the_alert_does_not_fill_at_off() -> void:
	_run(TEN_SECONDS)

	assert_float(_sim.waves.alert).is_equal(0.0)
	assert_int(_sim.waves.phase).is_equal(Waves.Phase.QUIET)


func test_the_alert_fills_at_each_paces_speed() -> void:
	var fills := {Miners.Pace.LOW: 0.1, Miners.Pace.MEDIUM: 0.4 / 3.0, Miners.Pace.HIGH: 1.0 / 6.0}
	for pace: Miners.Pace in fills:
		before_test()
		_sim.queue_command(Commands.SetPace.new(pace))
		_run(TEN_SECONDS)

		var fill: float = fills[pace]
		assert_float(_sim.waves.alert).is_equal_approx(fill, 1e-9)


func test_dry_the_alert_fills_at_the_dry_speed_whatever_the_pace() -> void:
	# 4 minerals at 3.2 a second run dry in 75 ticks.
	_sim = _make_sim(Vector2i(3, 1))
	_sim.queue_command(Commands.SetPace.new(Miners.Pace.HIGH))
	_run(75)
	assert_bool(_sim.miners.all_dry()).is_true()
	var before := _sim.waves.alert

	_run(TEN_SECONDS)

	assert_float(_sim.waves.alert - before).is_equal_approx(0.8 / 6.0, 1e-9)


func test_at_75_percent_the_next_waves_edges_are_picked_and_announced() -> void:
	_fill_in_one_second()
	_run(44)
	assert_array(_sim.waves.next_edges).is_empty()

	_run(1)

	assert_float(_sim.waves.alert).is_equal_approx(0.75, 1e-9)
	assert_int(_sim.waves.next_edges.size()).is_equal(1)
	assert_array(EDGES).contains([_sim.waves.next_edges[0]])
	assert_array(_events).contains_exactly(["coming %s" % _sim.waves.next_edges[0]])


func test_edges_number_1_2_3_and_4_by_whole_threat() -> void:
	var by_threat := {1.0: 1, 5.9: 1, 6.0: 2, 9.9: 2, 10.0: 3, 14.9: 3, 15.0: 4, 40.0: 4}
	for threat: float in by_threat:
		before_test()
		_sim.queue_command(Commands.JumpToThreat.new(threat))
		_fill_in_one_second()
		_run(45)

		var edges := _sim.waves.next_edges
		var expected: int = by_threat[threat]
		assert_int(edges.size()).override_failure_message("threat %s" % threat).is_equal(expected)
		var distinct := {}
		for edge in edges:
			distinct[edge] = true
		assert_int(distinct.size()).is_equal(edges.size())


func test_picked_edges_stay_picked_when_the_pace_drops_to_off() -> void:
	_fill_in_one_second()
	_run(50)
	var picked := _sim.waves.next_edges
	var alert := _sim.waves.alert

	_sim.queue_command(Commands.SetPace.new(Miners.Pace.OFF))
	_run(TEN_SECONDS)

	assert_float(_sim.waves.alert).is_equal(alert)
	assert_array(_sim.waves.next_edges).is_equal(picked)
	_sim.queue_command(Commands.SendWave.new())
	_sim.tick()
	assert_str(_events.back()).starts_with("wave %s " % ",".join(picked))


func test_a_full_alert_starts_a_wave_and_empties() -> void:
	_fill_in_one_second()
	_run(59)
	assert_int(_sim.waves.phase).is_equal(Waves.Phase.QUIET)
	var picked := ",".join(_sim.waves.next_edges)
	_events.clear()

	_run(1)

	assert_int(_sim.waves.phase).is_equal(Waves.Phase.WAVE)
	assert_float(_sim.waves.alert).is_equal(0.0)
	assert_array(_sim.waves.next_edges).is_empty()
	assert_array(_events).has_size(2)
	assert_str(_events[0]).is_equal("phase WAVE")
	assert_str(_events[1]).starts_with("wave %s " % picked)


func test_the_alert_stays_empty_and_no_wave_starts_until_the_last_wave_enemy_dies() -> void:
	_fill_in_one_second()
	_run(60)
	_run(TEN_SECONDS)
	assert_float(_sim.waves.alert).is_equal(0.0)
	_events.clear()
	_sim.queue_command(Commands.SendWave.new())
	_sim.tick()
	assert_array(_events).contains(["send wave: a wave is already running"])

	_run_until_quiet()

	assert_array(_events).contains(["phase QUIET", "wave ended"])
	_run(30)
	assert_float(_sim.waves.alert).is_equal_approx(0.5, 1e-9)


func test_send_wave_starts_a_wave_this_tick_picking_its_edges() -> void:
	_sim.queue_command(Commands.SendWave.new())

	_sim.tick()

	assert_int(_sim.waves.phase).is_equal(Waves.Phase.WAVE)
	assert_float(_sim.waves.alert).is_equal(0.0)
	assert_int(_sim.enemies.count).is_greater(0)
	# Its edges are picked as it starts: no warning comes first.
	assert_int(_events.size()).is_equal(2)
	assert_str(_events[1]).starts_with("wave ")


func _make_sim(base_deposit: Vector2i) -> Simulation:
	var rows: Array[String] = []
	for y in 16:
		rows.append("................")
	var map := TestMaps.from_rows(rows, Rect2i(7, 7, 2, 2), EDGES, [], base_deposit)
	var sim := Simulation.new(_settings, map, 1)
	_events = []
	sim.command_rejected.connect(func(reason: String) -> void: _events.append(reason))
	sim.phase_changed.connect(
		func(phase: Waves.Phase) -> void: _events.append("phase %s" % Waves.Phase.find_key(phase))
	)
	sim.wave_coming.connect(
		func(edges: PackedStringArray) -> void: _events.append("coming %s" % ",".join(edges))
	)
	sim.wave_started.connect(
		func(edges: PackedStringArray, size: int, _specials: Dictionary) -> void:
			_events.append("wave %s %d" % [",".join(edges), size])
	)
	sim.wave_ended.connect(func() -> void: _events.append("wave ended"))
	return sim


# At High with a 1 s fill, the alert fills in 60 ticks: 75% at tick 45.
func _fill_in_one_second() -> void:
	_settings.change("alert", "fill_seconds", 1.0)
	_sim.queue_command(Commands.SetPace.new(Miners.Pace.HIGH))


func _run(ticks: int) -> void:
	for tick in ticks:
		_sim.tick()


func _run_until_quiet() -> void:
	for tick in WAVE_TICKS:
		_sim.queue_command(Commands.KillEnemies.new(maxi(1, _sim.enemies.count)))
		_sim.tick()
		if _sim.waves.phase == Waves.Phase.QUIET:
			return
	fail("the wave did not end within %d ticks" % WAVE_TICKS)
