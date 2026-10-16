extends "res://test/sim/soldiers/order_suite.gd"

# Enemies fight back: an enemy jammed against a soldier attacks it at step 5, bloaters light
# their fuses on soldiers and blasts hurt them, and soldiers die, leave bodies and recover after
# a wave.

const TOUGH := 1000.0
# A corridor one cell wide from the east edge to the base in the west.
const LANE: Array[String] = [
	"##############",
	"..............",
	"..############",
	"..############",
]
# A corridor two cells wide, the same way.
const OPEN: Array[String] = [
	"..............",
	"..............",
	"..............",
	"..............",
	"..............",
]
const CORRIDOR: Array[String] = [
	"##############",
	"..............",
	"..............",
	"..############",
	"..############",
]


func test_an_enemy_jammed_against_a_soldier_attacks_it_at_2_hp_a_second() -> void:
	_sim = _sim_from(LANE)
	var id := _sim.soldiers.add(Vector2i(7, 1))
	var enemy := _sim.enemies.spawn(Vector2(9.5, 1.5), TOUGH)
	_run_until_attacking(enemy, 120)
	var before := _hp_of(id)

	for tick in 60:
		_sim.tick()

	assert_int(_soldier_target(enemy)).is_equal(id)
	assert_float(before - _hp_of(id)).is_equal_approx(2.0, 1e-3)


func test_an_enemy_passing_a_soldier_never_attacks_it() -> void:
	_sim = _sim_from(CORRIDOR)
	var id := _sim.soldiers.add(Vector2i(7, 1))
	var enemy := _sim.enemies.spawn(Vector2(12.5, 2.15), TOUGH)

	for tick in 240:
		_sim.tick()
		assert_int(_soldier_target(enemy)).is_equal(Enemies.NONE)

	assert_float(_sim.enemies.positions[_sim.enemies.index_of(enemy)].x).is_less(6.5)
	assert_float(_hp_of(id)).is_equal(_sim.settings.soldier_hp)


func test_an_enemy_attacking_a_soldier_holds_its_ground() -> void:
	_sim = _sim_from(LANE)
	_sim.soldiers.add(Vector2i(7, 1))
	var enemy := _sim.enemies.spawn(Vector2(9.5, 1.5), TOUGH)
	_run_until_attacking(enemy, 120)
	var held_at := _sim.enemies.positions[_sim.enemies.index_of(enemy)]

	for tick in 60:
		_sim.tick()

	var now := _sim.enemies.positions[_sim.enemies.index_of(enemy)]
	assert_float(now.distance_to(held_at)).is_less(0.05)


func test_a_soldier_on_a_wall_is_never_attacked_by_ground_enemies() -> void:
	var rows: Array[String] = LANE.duplicate()
	rows[1] = ".......W......"
	_sim = _sim_from(rows)
	var id := _sim.soldiers.add(Vector2i(7, 1))
	var enemies := []
	for n in 3:
		enemies.append(_sim.enemies.spawn(Vector2(9.0 + 0.7 * n, 1.5), TOUGH))

	for tick in 300:
		_sim.tick()
		for enemy: int in enemies:
			assert_int(_soldier_target(enemy)).is_equal(Enemies.NONE)

	assert_float(_hp_of(id)).is_equal(_sim.settings.soldier_hp)


func test_an_attack_ends_when_a_wall_rises_under_its_soldier() -> void:
	_sim = _sim_from(LANE)
	var id := _sim.soldiers.add(Vector2i(7, 1))
	var enemy := _sim.enemies.spawn(Vector2(9.5, 1.5), TOUGH)
	_run_until_attacking(enemy, 120)
	var bodies := PackedVector2Array()
	for n in Piles.WALL_LEVEL:
		bodies.append(Vector2(7.5, 1.5))
	_sim.piles.queue_bodies(Deaths.bodies_at(bodies))

	_sim.tick()
	var hp := _hp_of(id)
	for tick in 60:
		_sim.tick()

	assert_int(_sim.soldiers.elevation(_sim.soldiers.index_of(id))).is_equal(Piles.WALL_LEVEL)
	assert_int(_soldier_target(enemy)).is_equal(Enemies.NONE)
	assert_float(_hp_of(id)).is_equal(hp)


func test_an_attack_ends_when_its_soldier_walks_out_of_reach() -> void:
	_sim = _sim_from(LANE)
	var id := _sim.soldiers.add(Vector2i(7, 1))
	var enemy := _sim.enemies.spawn(Vector2(9.5, 1.5), TOUGH)
	_run_until_attacking(enemy, 120)

	_move([id], Vector2(3.5, 1.5), Formations.CLUSTER)
	_run_until_standing(240)

	assert_int(_soldier_target(enemy)).is_equal(Enemies.NONE)


func test_enemies_held_up_by_soldiers_fill_no_gauge() -> void:
	var rows: Array[String] = LANE.duplicate()
	rows[1] = "....W........."
	_sim = _sim_from(rows)
	_sim.settings.change("overflow", "leak", 0.0)
	_sim.soldiers.add(Vector2i(6, 1))
	var enemy := _sim.enemies.spawn(Vector2(9.5, 1.5), TOUGH)
	_run_until_attacking(enemy, 240)
	var at := Vector2i(_sim.enemies.positions[_sim.enemies.index_of(enemy)].floor())
	assert_int(_sim.overflow.band_label(at)).is_not_equal(Overflow.NONE)
	var gauges := _gauges()

	for tick in 300:
		_sim.tick()

	assert_int(_soldier_target(enemy)).is_not_equal(Enemies.NONE)
	assert_array(_gauges()).is_equal(gauges)


func test_a_bloater_lights_its_fuse_on_a_soldier_and_its_self_pop_pays_only_its_kills() -> void:
	_sim = _sim_from(LANE)
	var id := _sim.soldiers.add(Vector2i(7, 1))
	var bloater := _sim.enemies.spawn(Vector2(9.5, 1.5), TOUGH, Enemies.Kind.BLOATER)
	_sim.enemies.spawn(Vector2(10.5, 1.5), TOUGH)
	_sim.enemies.spawn(Vector2(11.3, 1.5), TOUGH)
	_run_until_attacking(bloater, 240)
	assert_int(_sim.enemies.fuse(bloater)).is_greater(0)
	var gold := _sim.run_state.gold
	var hp := _hp_of(id)

	for tick in _sim.settings.fuse_ticks:
		_sim.tick()

	assert_int(_sim.enemies.count).is_equal(0)
	assert_int(_sim.run_state.kills).is_equal(3)
	# The bloater pays no bounty; its two blast kills pay 1 each at x1.
	assert_int(_sim.run_state.gold - gold).is_equal(2)
	assert_object(_sim.combos.combo(id)).is_null()
	# A bloater holds with its fuse lit and deals no damage of its own.
	assert_float(_hp_of(id)).is_equal_approx(hp - _sim.settings.blast_damage, 1e-4)


func test_a_soldier_survives_one_blast_with_15_hp() -> void:
	_sim = _sim_from(OPEN)
	var id := _sim.soldiers.add(Vector2i(6, 1))
	_pop_bloaters_at([Vector2(6.5, 2.5)])

	_sim.tick()

	assert_float(_hp_of(id)).is_equal_approx(15.0, 1e-4)


func test_two_blasts_kill_a_soldier_and_leave_no_body() -> void:
	_sim = _sim_from(OPEN)
	var id := _sim.soldiers.add(Vector2i(6, 1))
	_pop_bloaters_at([Vector2(6.5, 2.5), Vector2(5.5, 2.5)])
	var died: Array[SoldierDeaths] = []
	_sim.soldiers_died.connect(func(deaths: SoldierDeaths) -> void: died.append(deaths))

	_sim.tick()
	_sim.tick()

	assert_int(_sim.soldiers.index_of(id)).is_equal(Soldiers.NONE)
	assert_int(died.size()).is_equal(1)
	assert_array(Array(died[0].ids)).is_equal([id])
	assert_int(died[0].blasts[0]).is_equal(1)
	assert_int(_sim.piles.level(Vector2i(6, 1))).is_equal(0)


func test_a_dead_soldier_frees_its_capacity_and_leaves_one_body_where_it_fell() -> void:
	_sim = _sim_from(OPEN)
	var id := _sim.soldiers.add(Vector2i(6, 1))
	_sim.soldiers.add(Vector2i(9, 1))
	var used := _sim.barracks.used()
	var died: Array[SoldierDeaths] = []
	_sim.soldiers_died.connect(func(deaths: SoldierDeaths) -> void: died.append(deaths))

	_sim.soldiers.damage(id, _sim.settings.soldier_hp)
	_sim.tick()
	_sim.tick()

	assert_int(_sim.soldiers.index_of(id)).is_equal(Soldiers.NONE)
	assert_int(_sim.soldiers.count).is_equal(1)
	assert_int(_sim.barracks.used()).is_equal(used - 1)
	assert_int(_sim.run_state.kills).is_equal(0)
	assert_vector(died[0].positions[0]).is_equal(Vector2(6.5, 1.5))
	assert_int(died[0].blasts[0]).is_equal(0)
	assert_int(_sim.piles.level(Vector2i(6, 1))).is_equal(1)


func test_an_enemy_attacking_a_soldier_that_dies_stops_at_once() -> void:
	_sim = _sim_from(LANE)
	var id := _sim.soldiers.add(Vector2i(7, 1))
	var enemy := _sim.enemies.spawn(Vector2(9.5, 1.5), TOUGH)
	_run_until_attacking(enemy, 240)

	_sim.soldiers.damage(id, _sim.settings.soldier_hp)
	_sim.tick()

	assert_int(_soldier_target(enemy)).is_equal(Enemies.NONE)


func test_a_kill_on_the_tick_its_soldier_dies_pays_x1() -> void:
	_sim = _sim_from(OPEN)
	_sim.settings.change("enemies", "speed", 0.1)
	var id := _sim.soldiers.add(Vector2i(6, 1))
	for n in 12:
		_sim.enemies.spawn(Vector2(4.0 + 0.8 * (n % 6), 3.0 + 0.8 * (n / 6)), 2.0)
	var i := _sim.soldiers.index_of(id)
	while (
		_sim.soldiers.kills[i] < _sim.settings.combo_tier_2_kills or _sim.soldiers.cooldowns[i] > 1
	):
		_sim.tick()
	assert_int(_sim.combos.combo(id).tier).is_equal(2)
	var gold := _sim.run_state.gold
	var kills := _sim.run_state.kills

	_sim.soldiers.damage(id, _sim.settings.soldier_hp)
	_sim.tick()

	assert_int(_sim.run_state.kills).is_equal(kills + 1)
	assert_int(_sim.run_state.gold - gold).is_equal(1)
	assert_object(_sim.combos.combo(id)).is_null()


func test_soldiers_recover_to_full_hp_at_wave_end_and_not_before() -> void:
	var rows: Array[String] = OPEN.duplicate()
	var map := TestMaps.from_rows(rows, Rect2i(0, 3, 2, 2), ["E"])
	_sim = Simulation.new(Settings.load_file(Settings.DEFAULTS_PATH).settings, map)
	var id := _sim.soldiers.add(Vector2i(6, 1))
	_sim.queue_command(Commands.NextWave.new())
	_sim.tick()
	_sim.soldiers.damage(id, 20.0)

	var ticks := 0
	while _sim.waves.phase == Waves.Phase.WAVE:
		assert_float(_hp_of(id)).is_equal_approx(25.0, 1e-4)
		_sim.queue_command(Commands.KillEnemies.new(100))
		_sim.tick()
		ticks += 1
		assert_int(ticks).is_less(1200)

	assert_float(_hp_of(id)).is_equal(_sim.settings.soldier_hp)


func _pop_bloaters_at(at: Array[Vector2]) -> void:
	for pos in at:
		_sim.enemies.kill(_sim.enemies.spawn(pos, TOUGH, Enemies.Kind.BLOATER))


func _run_until_attacking(enemy: int, limit: int) -> void:
	for tick in limit:
		_sim.tick()
		if _soldier_target(enemy) != Enemies.NONE:
			return
	fail("enemy %d not attacking a soldier after %d ticks" % [enemy, limit])


func _gauges() -> Array[float]:
	var gauges: Array[float] = []
	for crush in _sim.overflow.crushes():
		gauges.append(crush.gauge)
	return gauges


func _soldier_target(enemy: int) -> int:
	return _sim.enemies.soldier_targets[_sim.enemies.index_of(enemy)]


func _hp_of(id: int) -> float:
	return _sim.soldiers.hp[_sim.soldiers.index_of(id)]
