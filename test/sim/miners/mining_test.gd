extends GdUnitTestSuite

# The base mines its deposit at the pace the player sets: Off, Low, Medium or High. Each tick's
# minerals split by the deposit's mix, gold is paid in whole steps and Aether is banked, until the
# deposit runs dry.

const PACES: Array[Miners.Pace] = [Miners.Pace.LOW, Miners.Pace.MEDIUM, Miners.Pace.HIGH]
# Minerals a second at each pace, by the defaults: 3.2 at High, ×0.3 at Low and ×0.5 at Medium.
const RATES := [0.96, 1.6, 3.2]

var _sim: Simulation
var _rejections: Array[String]


func before_test() -> void:
	_sim = _make_sim(Vector2i(MapData.DEFAULT_BASE_GOLD, MapData.DEFAULT_BASE_AETHER))


func test_at_off_nothing_is_mined() -> void:
	_run(600)

	assert_int(_sim.miners.pace).is_equal(Miners.Pace.OFF)
	assert_int(_sim.run_state.gold).is_equal(300)
	assert_float(_sim.run_state.gold_mined).is_equal(0.0)
	assert_float(_sim.run_state.aether_mined).is_equal(0.0)
	assert_float(_sim.miners.remaining(Miners.BASE).gold).is_equal(4200.0)
	assert_float(_sim.miners.gold_rate()).is_equal(0.0)


func test_each_pace_mines_its_rate_split_75_25_into_gold_and_aether() -> void:
	for i in PACES.size():
		before_test()
		_set_pace(PACES[i])
		_run(60)

		var rate: float = RATES[i]
		assert_float(_sim.run_state.gold_mined).is_equal_approx(rate * 0.75, 1e-6)
		assert_float(_sim.run_state.aether_mined).is_equal_approx(rate * 0.25, 1e-6)
		assert_float(_sim.miners.gold_rate()).is_equal_approx(rate * 0.75, 1e-6)
		assert_float(_sim.miners.remaining(Miners.BASE).gold).is_equal_approx(
			4200.0 - rate * 0.75, 1e-6
		)
		assert_float(_sim.miners.remaining(Miners.BASE).aether).is_equal_approx(
			1400.0 - rate * 0.25, 1e-6
		)


func test_gold_arrives_in_whole_steps_that_add_up_exactly_over_a_run() -> void:
	_sim = _make_sim(Vector2i(30, 10))
	var reported: Array[int] = []
	_sim.gold_changed.connect(func(gold: int) -> void: reported.append(gold))
	_set_pace(Miners.Pace.HIGH)
	# 40 minerals at 3.2 a second take 12.5 s; run well past it.
	_run(900)

	var expected: Array[int] = []
	for gold in range(301, 331):
		expected.append(gold)
	assert_array(reported).contains_exactly(expected)
	assert_int(_sim.run_state.gold).is_equal(330)
	assert_float(_sim.run_state.aether_mined).is_equal_approx(10.0, 1e-6)


func test_the_deposit_runs_dry_with_both_minerals_ending_on_the_same_tick() -> void:
	_sim = _make_sim(Vector2i(30, 10))
	var dry_ticks: Array[int] = []
	_sim.miner_changed.connect(func(id: int) -> void: dry_ticks.append(_sim.tick_count))
	_set_pace(Miners.Pace.HIGH)
	var gold_ended := -1
	var aether_ended := -1
	for tick in 900:
		_sim.tick()
		var left := _sim.miners.remaining(Miners.BASE)
		if gold_ended < 0 and left.gold == 0.0:
			gold_ended = tick
		if aether_ended < 0 and left.aether == 0.0:
			aether_ended = tick
	var mined := _sim.run_state.gold_mined + _sim.run_state.aether_mined

	# 40 minerals at 3.2/60 a tick: the 750th tick takes the last of them.
	assert_int(gold_ended).is_equal(749)
	assert_int(aether_ended).is_equal(gold_ended)
	assert_array(dry_ticks).contains_exactly([750])
	assert_bool(_sim.miners.is_dry(Miners.BASE)).is_true()
	assert_float(_sim.miners.gold_rate()).is_equal(0.0)
	_run(60)
	assert_float(_sim.run_state.gold_mined + _sim.run_state.aether_mined).is_equal(mined)


func test_set_pace_is_rejected_once_dry_and_the_pace_reports_locked() -> void:
	_sim = _make_sim(Vector2i(3, 1))
	var reports: Array = []
	_sim.pace_changed.connect(
		func(pace: Miners.Pace, locked: bool) -> void: reports.append([pace, locked])
	)
	_set_pace(Miners.Pace.HIGH)
	_run(120)

	_set_pace(Miners.Pace.LOW)
	_sim.tick()

	assert_array(_rejections).contains_exactly(["pace: every deposit is dry"])
	assert_int(_sim.miners.pace).is_equal(Miners.Pace.HIGH)
	assert_array(reports).contains_exactly([[Miners.Pace.HIGH, false], [Miners.Pace.HIGH, true]])


func test_the_full_base_deposit_pays_every_gold_at_any_pace_mix() -> void:
	# The whole 4,200 gold and 1,400 Aether, mined through pace changes, pays exactly.
	var map := _sim.map
	var settings := _sim.settings
	var miners := Miners.new(settings, map)
	var run := RunState.new(settings)
	var paces: Array[Miners.Pace] = [Miners.Pace.LOW, Miners.Pace.HIGH, Miners.Pace.MEDIUM]
	var tick := 0
	while not miners.is_dry(Miners.BASE):
		miners.set_pace(paces[(tick / 7919) % paces.size()])
		run.credit(miners.step())
		tick += 1

	assert_int(run.gold).is_equal(300 + 4200)
	assert_float(run.gold_mined).is_equal_approx(4200.0, 1e-6)
	assert_float(run.aether_mined).is_equal_approx(1400.0, 1e-6)


func test_the_pace_changes_mining_from_the_tick_it_is_set_mid_wave_included() -> void:
	_sim.queue_command(Commands.SendWave.new())
	_set_pace(Miners.Pace.HIGH)
	_run(30)
	assert_int(_sim.waves.phase).is_equal(Waves.Phase.WAVE)
	var before := _sim.run_state.gold_mined + _sim.run_state.aether_mined

	_set_pace(Miners.Pace.LOW)
	_sim.tick()

	var mined := _sim.run_state.gold_mined + _sim.run_state.aether_mined - before
	assert_float(mined).is_equal_approx(0.96 / 60.0, 1e-9)


func test_damage_to_the_base_does_not_change_the_rate() -> void:
	_set_pace(Miners.Pace.HIGH)
	_sim.run_state.damage_base(150.0)
	_run(60)

	assert_float(_sim.run_state.gold_mined).is_equal_approx(2.4, 1e-6)
	assert_float(_sim.miners.gold_rate()).is_equal_approx(2.4, 1e-6)


func test_kills_pay_nothing_and_kills_still_counts_them() -> void:
	_sim.queue_command(Commands.SendWave.new())
	_sim.tick()
	assert_int(_sim.enemies.count).is_greater_equal(2)

	_sim.queue_command(Commands.KillEnemies.new(2))
	_sim.tick()

	assert_int(_sim.run_state.kills).is_equal(2)
	assert_int(_sim.run_state.gold).is_equal(300)


func _make_sim(base_deposit: Vector2i) -> Simulation:
	var rows: Array[String] = []
	for y in 8:
		rows.append("........")
	var edges: Array[String] = ["N"]
	var map := TestMaps.from_rows(rows, Rect2i(3, 3, 2, 2), edges, [], base_deposit)
	var sim := Simulation.new(Settings.load_file(Settings.DEFAULTS_PATH).settings, map, 1)
	_rejections = []
	sim.command_rejected.connect(func(reason: String) -> void: _rejections.append(reason))
	return sim


func _set_pace(pace: Miners.Pace) -> void:
	_sim.queue_command(Commands.SetPace.new(pace))


func _run(ticks: int) -> void:
	for tick in ticks:
		_sim.tick()
