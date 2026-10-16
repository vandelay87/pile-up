extends "res://test/sim/soldiers/order_suite.gd"

# Soldiers fire at step 7 with their own numbers (2 damage at 2 shots/s,
# range 4 plus 0.5 a level up), and earn bounty and a combo of their own.

const TOUGH := 1000.0
const OPEN: Array[String] = [
	"..............",
	"..............",
	"..............",
	"..............",
	"..............",
]


func test_a_soldier_hits_an_enemy_in_range_and_not_one_out_of_it() -> void:
	_sim = _still_sim(OPEN)
	_sim.soldiers.add(Vector2i(6, 1))
	var out_of_range := _sim.enemies.spawn(Vector2(10.6, 1.5), TOUGH)
	for tick in 60:
		_sim.tick()
	var in_range := _sim.enemies.spawn(Vector2(6.5, 4.4), TOUGH)

	_sim.tick()

	assert_float(_hp(out_of_range)).is_equal(TOUGH)
	assert_float(_hp(in_range)).is_equal_approx(TOUGH - 2.0, 1e-4)


func test_a_soldier_reaches_4_cells_on_the_ground() -> void:
	assert_bool(_hits_at_once(OPEN, Vector2i(2, 1), Vector2(6.4, 1.5))).is_true()
	assert_bool(_hits_at_once(OPEN, Vector2i(2, 1), Vector2(6.6, 1.5))).is_false()


func test_a_soldier_reaches_5_cells_on_a_level_2_pile() -> void:
	var rows: Array[String] = OPEN.duplicate()
	rows[1] = "..p..........."
	assert_bool(_hits_at_once(rows, Vector2i(2, 1), Vector2(7.4, 1.5))).is_true()
	assert_bool(_hits_at_once(rows, Vector2i(2, 1), Vector2(7.6, 1.5))).is_false()


func test_a_soldier_reaches_6_and_a_half_cells_on_a_wall() -> void:
	var rows: Array[String] = OPEN.duplicate()
	rows[1] = "..W..........."
	assert_bool(_hits_at_once(rows, Vector2i(2, 1), Vector2(8.9, 1.5))).is_true()
	assert_bool(_hits_at_once(rows, Vector2i(2, 1), Vector2(9.1, 1.5))).is_false()


func test_a_soldier_keeps_its_target_while_it_lives_and_is_in_range() -> void:
	_sim = _still_sim(OPEN)
	var id := _sim.soldiers.add(Vector2i(6, 1))
	var first := _sim.enemies.spawn(Vector2(9.5, 1.5), TOUGH)
	_sim.tick()
	_sim.enemies.spawn(Vector2(6.5, 3.5), TOUGH)

	for tick in 60:
		_sim.tick()

	assert_int(_target_of(id)).is_equal(first)
	assert_float(_hp(first)).is_equal_approx(TOUGH - 6.0, 1e-4)


func test_stepping_down_drops_a_target_left_out_of_range_and_picks_again() -> void:
	var rows: Array[String] = OPEN.duplicate()
	rows[1] = "..W..........."
	_sim = _still_sim(rows)
	var id := _sim.soldiers.add(Vector2i(2, 1))
	var far := _sim.enemies.spawn(Vector2(8.0, 1.5), TOUGH)
	_sim.tick()
	assert_int(_target_of(id)).is_equal(far)
	var near := _sim.enemies.spawn(Vector2(5.5, 2.5), TOUGH)

	_sim.piles.erase(Vector2i(2, 1))
	_sim.tick()

	assert_int(_sim.soldiers.elevation(_sim.soldiers.index_of(id))).is_equal(0)
	assert_int(_target_of(id)).is_equal(near)


func test_bloaters_first_prefers_a_bloater_over_an_enemy_nearer_the_base() -> void:
	_sim = _still_sim(OPEN)
	var id := _sim.soldiers.add(Vector2i(6, 1))
	_sim.enemies.spawn(Vector2(4.5, 2.5), TOUGH)
	var bloater := _sim.enemies.spawn(Vector2(9.5, 1.5), TOUGH, Enemies.Kind.BLOATER)

	_sim.tick()

	assert_int(_target_of(id)).is_equal(bloater)


func test_closest_to_base_ignores_the_bloater() -> void:
	_sim = _still_sim(OPEN)
	var id := _sim.soldiers.add(Vector2i(6, 1))
	var nearer := _sim.enemies.spawn(Vector2(4.5, 2.5), TOUGH)
	_sim.enemies.spawn(Vector2(9.5, 1.5), TOUGH, Enemies.Kind.BLOATER)
	_sim.queue_command(
		Commands.SetSoldierTargeting.new(PackedInt32Array([id]), Enemies.CLOSEST_TO_BASE)
	)

	_sim.tick()

	assert_int(_target_of(id)).is_equal(nearer)


func test_a_firing_soldier_walks_at_half_speed() -> void:
	var idle := _walked_from_30_to_60_ticks(false)
	var firing := _walked_from_30_to_60_ticks(true)

	assert_float(idle).is_equal_approx(30.0 * 2.5 / 60.0, 1e-3)
	assert_float(firing).is_equal_approx(idle / 2.0, 1e-3)


func test_a_soldier_whose_target_died_has_no_target_as_firing_ends() -> void:
	_sim = _still_sim(OPEN)
	var id := _sim.soldiers.add(Vector2i(6, 1))
	_sim.enemies.spawn(Vector2(8.5, 1.5), 2.0)

	_sim.tick()

	assert_int(_sim.run_state.kills).is_equal(1)
	assert_int(_target_of(id)).is_equal(Enemies.NONE)


func test_a_firing_soldier_walks_back_to_its_spot_at_its_normal_speed() -> void:
	_sim = _still_sim(OPEN)
	var id := _sim.soldiers.add(Vector2i(6, 1))
	_sim.enemies.spawn(Vector2(9.5, 1.5), TOUGH)
	_sim.tick()
	_sim.soldiers.positions[_sim.soldiers.index_of(id)] = Vector2(6.5, 2.0)

	_sim.tick()

	assert_float(_position_of(id).y).is_equal_approx(2.0 - 2.5 / 60.0, 1e-4)


func test_a_soldiers_kills_pay_bounty_times_its_tier_and_build_its_combo() -> void:
	_sim = _still_sim(OPEN)
	var id := _sim.soldiers.add(Vector2i(6, 1))
	_spawn_weak_row(12)
	var gold := _sim.run_state.gold

	# A kill every 30 ticks, the first on tick 0.
	for tick in 331:
		_sim.tick()

	# Kills 1–9 pay 1 each at ×1; the 10th reaches ×2, so it and the next two pay 2 each.
	assert_int(_sim.run_state.gold - gold).is_equal(15)
	assert_int(_sim.soldiers.kills[_sim.soldiers.index_of(id)]).is_equal(12)
	assert_int(_sim.combos.combo(id).count).is_equal(12)
	assert_int(_sim.combos.combo(id).tier).is_equal(2)


func test_moving_never_breaks_a_soldiers_combo() -> void:
	_sim = _still_sim(OPEN)
	var id := _sim.soldiers.add(Vector2i(6, 1))
	_spawn_weak_row(12)
	var breaks := []
	_sim.combo_events.connect(
		func(events: Array[Combos.Event]) -> void:
			for event in events:
				if event.kind == Combos.EventKind.BREAK:
					breaks.append(event)
	)
	for tick in 100:
		_sim.tick()

	_move([id], Vector2(8.5, 1.5), Formations.CLUSTER)
	for tick in 231:
		_sim.tick()

	assert_vector(_position_of(id)).is_not_equal(Vector2(6.5, 1.5))
	assert_array(breaks).is_empty()
	assert_int(_sim.combos.combo(id).count).is_equal(12)


func test_a_bloater_a_soldier_kills_credits_it_with_its_blasts_kills() -> void:
	_sim = _still_sim(OPEN)
	var id := _sim.soldiers.add(Vector2i(3, 1))
	_sim.enemies.spawn(Vector2(7.5, 1.5), 2.0, Enemies.Kind.BLOATER)
	for pos: Vector2 in [Vector2(8.5, 1.5), Vector2(7.5, 2.5), Vector2(8.5, 2.5)]:
		_sim.enemies.spawn(pos, TOUGH)
	var gold := _sim.run_state.gold

	_sim.tick()

	assert_int(_sim.enemies.count).is_equal(0)
	assert_int(_sim.soldiers.kills[_sim.soldiers.index_of(id)]).is_equal(4)
	assert_int(_sim.combos.combo(id).count).is_equal(4)
	# A bloater's bounty is 2 and a normal enemy's 1, all at ×1.
	assert_int(_sim.run_state.gold - gold).is_equal(5)


# Twelve enemies a shot kills, in range of a soldier at (6, 1), in two rows of six.
func _spawn_weak_row(wanted: int) -> void:
	for n in wanted:
		_sim.enemies.spawn(Vector2(4.0 + 0.8 * (n % 6), 3.0 + 0.8 * (n / 6)), 2.0)


# How far a soldier walking east along row 1 goes from tick 30 to tick 60, with or without a
# tough enemy in range all the way.
func _walked_from_30_to_60_ticks(with_enemy: bool) -> float:
	_sim = _still_sim(OPEN)
	var id := _sim.soldiers.add(Vector2i(4, 1))
	if with_enemy:
		_sim.enemies.spawn(Vector2(8.5, 3.5), TOUGH)
	_move([id], Vector2(12.5, 1.5), Formations.CLUSTER)
	for tick in 30:
		_sim.tick()
	var from := _position_of(id)
	for tick in 30:
		_sim.tick()
	return _position_of(id).distance_to(from)


# Whether a soldier standing on [param cell] hits an enemy at [param enemy_at] on the first tick.
func _hits_at_once(rows: Array[String], cell: Vector2i, enemy_at: Vector2) -> bool:
	_sim = _still_sim(rows)
	_sim.soldiers.add(cell)
	var enemy := _sim.enemies.spawn(enemy_at, TOUGH)
	_sim.tick()
	return _hp(enemy) < TOUGH


func _target_of(id: int) -> int:
	return _sim.soldiers.targets[_sim.soldiers.index_of(id)]


# Enemies barely move, so ranges in the tests hold for a few seconds.
func _still_sim(rows: Array[String]) -> Simulation:
	var sim := _sim_from(rows)
	sim.settings.change("enemies", "speed", 0.1)
	sim.settings.change("enemies", "heading_offset", 0.0)
	return sim


func _hp(enemy_id: int) -> float:
	return _sim.enemies.hp[_sim.enemies.index_of(enemy_id)]
