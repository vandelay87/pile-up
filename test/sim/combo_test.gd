extends GdUnitTestSuite

# Per-building combos: each building's kills build its own combo on a chain timer, and each
# kill pays its bounty times its killer's tier after counting that kill.

const TIMER_TICKS := 120
const TOUGH := 1000.0
# Out of both towers' range, so they never fire on these enemies themselves.
const FAR := Vector2(16.5, 2.5)

var _settings: Settings
var _sim: Simulation
var _a: int
var _b: int
var _payouts: Array[Vector2i]
var _events: Array[Combos.Event]


func before_test() -> void:
	_settings = Settings.load_file(Settings.DEFAULTS_PATH).settings
	_settings.change("enemies", "speed", 0.1)
	_settings.change("run", "base_power_area", 20)
	var rows: Array[String] = []
	for y in 20:
		rows.append("....................")
	var edges: Array[String] = ["N"]
	_sim = Simulation.new(_settings, TestMaps.from_rows(rows, Rect2i(18, 18, 2, 2), edges), 1)
	_sim.add_gold(1000)
	_sim.queue_command(Commands.Build.new(Buildings.TOWER, Vector2i(0, 0)))
	_sim.queue_command(Commands.Build.new(Buildings.TOWER, Vector2i(0, 4)))
	_sim.tick()
	_a = _sim.buildings.built[0].id
	_b = _sim.buildings.built[1].id
	_payouts = []
	_events = []
	_sim.payout.connect(
		func(amount: int, tier: int) -> void: _payouts.append(Vector2i(amount, tier))
	)
	_sim.combo_events.connect(
		func(events: Array[Combos.Event]) -> void: _events.append_array(events)
	)


func test_a_building_starts_with_no_combo() -> void:
	assert_object(_sim.combos.combo(_a)).is_null()


func test_a_towers_10th_kill_within_the_timer_pays_x2() -> void:
	var gold := _sim.run_state.gold
	_kill(_a, 9)
	assert_int(_sim.run_state.gold - gold).is_equal(9)
	assert_array(_payouts).is_empty()

	_kill(_a, 1)

	assert_int(_sim.run_state.gold - gold).is_equal(9 + 2)
	assert_int(_sim.combos.combo(_a).count).is_equal(10)
	assert_int(_sim.combos.combo(_a).tier).is_equal(2)
	assert_array(_payouts).contains_exactly([Vector2i(2, 2)])


func test_another_towers_kills_do_not_count_towards_it() -> void:
	_kill(_a, 9)
	_kill(_b, 5)
	var gold := _sim.run_state.gold

	_kill(_b, 1)

	assert_int(_sim.run_state.gold - gold).is_equal(1)
	assert_int(_sim.combos.combo(_a).count).is_equal(9)
	assert_int(_sim.combos.combo(_b).count).is_equal(6)
	assert_int(_sim.combos.combo(_b).tier).is_equal(1)


func test_one_tick_pays_each_kill_at_its_own_killers_tier() -> void:
	_kill(_a, 10)
	var gold := _sim.run_state.gold
	_payouts.clear()

	_kill_both(2, 3)

	assert_int(_sim.run_state.gold - gold).is_equal(2 * 2 + 3)
	assert_array(_payouts).contains_exactly([Vector2i(7, 2)])


func test_a_kill_within_the_timer_keeps_the_combo_and_a_2_second_gap_breaks_it() -> void:
	_kill(_a, 10)
	_wait(TIMER_TICKS - 2)
	var gold := _sim.run_state.gold
	# The 11th kill comes 119 ticks after the 10th, inside the timer.
	_kill(_a, 1)
	assert_int(_sim.run_state.gold - gold).is_equal(2)
	assert_int(_sim.combos.combo(_a).tier).is_equal(2)

	_wait(TIMER_TICKS - 1)
	gold = _sim.run_state.gold
	# The next comes 120 ticks later: the timer ran out first, so it starts a new combo at x1.
	_kill(_a, 1)

	assert_int(_sim.run_state.gold - gold).is_equal(1)
	assert_int(_sim.combos.combo(_a).count).is_equal(1)
	assert_int(_sim.combos.combo(_a).tier).is_equal(1)


func test_the_timer_running_out_breaks_the_combo_without_a_kill() -> void:
	_kill(_a, 12)
	_wait(TIMER_TICKS - 1)
	assert_int(_sim.combos.combo(_a).count).is_equal(12)

	_wait(1)

	assert_int(_sim.combos.combo(_a).count).is_equal(0)
	assert_int(_sim.combos.combo(_a).tier).is_equal(1)


func test_the_25th_kill_pays_x3_and_the_cap_holds() -> void:
	var gold := _sim.run_state.gold
	_kill(_a, 24)
	assert_int(_sim.run_state.gold - gold).is_equal(9 + 15 * 2)

	_kill(_a, 1)
	assert_int(_sim.run_state.gold - gold).is_equal(9 + 15 * 2 + 3)
	assert_int(_sim.combos.combo(_a).tier).is_equal(3)

	_kill(_a, 30)
	assert_int(_sim.run_state.gold - gold).is_equal(9 + 15 * 2 + 31 * 3)
	assert_int(_sim.combos.combo(_a).tier).is_equal(3)


func test_a_lower_cap_holds_the_tier_at_x2() -> void:
	_sim.queue_command(Commands.SetSetting.new("combo", "cap", 2))
	var gold := _sim.run_state.gold

	_kill(_a, 30)

	assert_int(_sim.run_state.gold - gold).is_equal(9 + 21 * 2)
	assert_int(_sim.combos.combo(_a).tier).is_equal(2)


func test_a_destroyed_towers_combo_is_removed_and_its_rebuild_starts_at_x1() -> void:
	_kill(_a, 12)
	_sim.buildings.damage(_a, TOUGH)
	_sim.tick()
	assert_object(_sim.combos.combo(_a)).is_null()

	_sim.queue_command(Commands.Build.new(Buildings.TOWER, Vector2i(0, 0)))
	_sim.tick()
	var rebuilt := _sim.occupancy.building_at(Vector2i(0, 0))
	var gold := _sim.run_state.gold
	_kill(rebuilt, 1)

	assert_int(rebuilt).is_not_equal(_a)
	assert_int(_sim.run_state.gold - gold).is_equal(1)
	assert_int(_sim.combos.combo(rebuilt).count).is_equal(1)


func test_a_kill_whose_killer_was_destroyed_this_tick_pays_x1_and_feeds_no_combo() -> void:
	_kill(_a, 12)
	var gold := _sim.run_state.gold
	var id := _sim.enemies.spawn(FAR, TOUGH)
	_sim.enemies.damage(id, TOUGH, _a)
	_sim.buildings.damage(_a, TOUGH)

	_sim.tick()

	assert_int(_sim.run_state.gold - gold).is_equal(1)
	assert_object(_sim.combos.combo(_a)).is_null()


func test_a_kill_with_no_killer_pays_x1() -> void:
	_kill(_a, 12)
	var gold := _sim.run_state.gold
	_sim.enemies.spawn(FAR, TOUGH)
	_sim.queue_command(Commands.KillEnemies.new(1))

	_sim.tick()

	assert_int(_sim.run_state.gold - gold).is_equal(1)
	assert_int(_sim.combos.combo(_a).count).is_equal(12)


func test_damage_to_the_base_or_the_tower_does_not_break_a_combo() -> void:
	_sim.queue_command(Commands.SetSetting.new("combo", "timer", 10.0))
	_kill(_a, 10)
	_sim.buildings.damage(_a, 1.0)
	_sim.enemies.spawn(Vector2(17.5, 17.5), TOUGH)

	for tick in 4 * Simulation.TICKS_PER_SECOND:
		if _sim.run_state.base_hp < _settings.base_hp:
			break
		_sim.tick()

	assert_float(_sim.run_state.base_hp).is_less(_settings.base_hp)
	assert_int(_sim.combos.combo(_a).tier).is_equal(2)
	assert_int(_sim.combos.combo(_a).count).is_equal(10)


func test_the_best_combo_this_run_is_kept_after_a_break() -> void:
	_kill(_a, 12)
	_wait(TIMER_TICKS)
	_kill(_a, 3)

	assert_int(_sim.combos.combo(_a).count).is_equal(3)
	assert_int(_sim.combos.combo(_a).tier).is_equal(1)
	assert_int(_sim.combos.combo(_a).best).is_equal(2)


func test_combo_events_report_each_kill_pulse_tier_up_and_break() -> void:
	_kill(_a, 9)
	_events.clear()
	_kill(_a, 1)
	assert_array(_kinds_of(_events)).contains_exactly(
		[Combos.EventKind.KILL, Combos.EventKind.TIER_UP]
	)
	assert_int(_events[1].building_id).is_equal(_a)
	assert_int(_events[1].tier).is_equal(2)

	_events.clear()
	_wait(TIMER_TICKS)

	assert_array(_kinds_of(_events)).contains_exactly([Combos.EventKind.BREAK])
	assert_int(_events[0].building_id).is_equal(_a)
	assert_int(_events[0].tier).is_equal(2)
	assert_int(_events[0].count).is_equal(10)


func _kinds_of(events: Array[Combos.Event]) -> Array:
	return events.map(func(event: Combos.Event) -> Combos.EventKind: return event.kind)


func _wait(ticks: int) -> void:
	for tick in ticks:
		_sim.tick()


# Kills n enemies credited to a tower, removed at the next tick's REMOVE_DEAD.
func _kill(tower: int, n: int) -> void:
	_credit(tower, n)
	_sim.tick()


func _kill_both(n_a: int, n_b: int) -> void:
	_credit(_a, n_a)
	_credit(_b, n_b)
	_sim.tick()


func _credit(tower: int, n: int) -> void:
	for i in n:
		var id := _sim.enemies.spawn(FAR, TOUGH)
		_sim.enemies.damage(id, TOUGH, tower)
