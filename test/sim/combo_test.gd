extends GdUnitTestSuite

# Wave 5 has 57 enemies; with bursts of 50 there are 50 on the field after its first tick.
const WAVE := 5
const WINDOW_TICKS := 120

var _settings: Settings
var _sim: Simulation
var _tiers: Array[int]
var _payouts: Array[Vector2i]


func before_test() -> void:
	_settings = Settings.load_file(Settings.DEFAULTS_PATH).settings
	_settings.change("waves", "clump_size", 50)
	var rows: Array[String] = []
	for y in 8:
		rows.append("........")
	var edges: Array[String] = ["N"]
	_sim = Simulation.new(_settings, TestMaps.from_rows(rows, Rect2i(3, 3, 2, 2), edges), 1)
	_tiers = []
	_payouts = []
	_sim.combo_changed.connect(func(tier: int) -> void: _tiers.append(tier))
	_sim.payout.connect(
		func(amount: int, tier: int) -> void: _payouts.append(Vector2i(amount, tier))
	)
	_sim.queue_command(Commands.JumpToWave.new(WAVE))
	_sim.tick()


func test_the_combo_starts_at_x1() -> void:
	assert_int(_sim.combo_tier).is_equal(1)


func test_a_burst_crossing_10_kills_pays_x2_from_the_crossing_kill_on() -> void:
	_kill(12)

	# 9 kills at x1, then the 10th, 11th and 12th at x2.
	assert_int(_sim.run_state.gold).is_equal(200 + 9 + 3 * 2)
	assert_int(_sim.combo_tier).is_equal(2)
	assert_array(_tiers).contains_exactly([2])
	assert_array(_payouts).contains_exactly([Vector2i(15, 2)])


func test_the_tier_reaches_x3_at_20_kills_and_caps_there() -> void:
	_kill(15)
	_kill(25)

	# 15 kills: 9 at x1, 6 at x2. Then 4 more at x2 and the rest at x3, however many.
	assert_int(_sim.combo_tier).is_equal(3)
	assert_int(_sim.run_state.gold).is_equal(200 + 9 + 6 * 2 + 4 * 2 + 21 * 3)
	assert_array(_tiers).contains_exactly([2, 3])
	assert_array(_payouts).contains_exactly([Vector2i(21, 2), Vector2i(71, 3)])


func test_the_tier_falls_as_old_kills_leave_the_2_second_window() -> void:
	# A kill counts for WINDOW_TICKS ticks, its own tick included.
	_kill(12)
	_wait(59)
	_kill(10)
	assert_int(_sim.combo_tier).is_equal(3)

	_wait(WINDOW_TICKS - 61)
	assert_int(_sim.combo_tier).is_equal(3)
	_wait(1)
	assert_int(_sim.combo_tier).is_equal(2)
	_wait(59)
	assert_int(_sim.combo_tier).is_equal(2)
	_wait(1)
	assert_int(_sim.combo_tier).is_equal(1)
	assert_array(_tiers).contains_exactly([2, 3, 2, 1])


func test_a_kill_after_the_fall_pays_the_lower_tier() -> void:
	_kill(20)
	_wait(WINDOW_TICKS)
	var gold := _sim.run_state.gold

	_kill(1)

	assert_int(_sim.run_state.gold - gold).is_equal(1)
	assert_int(_sim.combo_tier).is_equal(1)


func test_the_combo_cap_holds_the_tier_below_x3() -> void:
	_sim.queue_command(Commands.SetSetting.new("run", "combo_cap", 2))
	_kill(25)

	# 9 kills at x1, then the rest at x2: the cap stops the climb to x3 at 20 kills.
	assert_int(_sim.combo_tier).is_equal(2)
	assert_int(_sim.run_state.gold).is_equal(200 + 9 + 16 * 2)
	assert_array(_tiers).contains_exactly([2])


func test_damage_to_the_base_does_not_lower_the_tier() -> void:
	_sim.queue_command(Commands.SetSetting.new("run", "combo_window", 10.0))
	_kill(10)

	for tick in 8 * Simulation.TICKS_PER_SECOND:
		if _sim.run_state.base_hp < _settings.base_hp:
			break
		_sim.tick()

	assert_float(_sim.run_state.base_hp).is_less(_settings.base_hp)
	assert_int(_sim.combo_tier).is_equal(2)
	assert_array(_tiers).contains_exactly([2])


func _wait(ticks: int) -> void:
	for tick in ticks:
		_sim.tick()


func _kill(n: int) -> void:
	for k in n:
		_sim.enemies.hp[k] = 0.0
	_sim.tick()
