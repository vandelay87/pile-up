extends GdUnitTestSuite

# The blast: a bloater lights a 1 s fuse at a structure in its way and blows up when it dies,
# killing enemies, hurting buildings and the base, and erasing piles and walls within 2 cells.
#
# A 20×10 open field with the base at its east edge. Walls are tough, so nothing but a blast
# takes them down.

const FUSE_TICKS := 60
const TOUGH := 1000.0
const WALL_X := 10
const BASE := Rect2i(18, 4, 2, 2)

var _settings: Settings
var _sim: Simulation


func before_test() -> void:
	_settings = TestSettings.without_swarm_spread()
	_settings.change("enemies", "heading_offset", 0.0)
	_settings.change("piles", "wall_hp", TOUGH)
	_settings.change("towers", "cost", 50)
	_settings.change("run", "base_power_area", 30)
	var rows: Array[String] = []
	for y in 10:
		rows.append(".".repeat(20))
	var edges: Array[String] = ["W"]
	_sim = Simulation.new(_settings, TestMaps.from_rows(rows, BASE, edges), 1)


func test_a_bloater_against_a_wall_lights_its_fuse_and_pops_60_ticks_later() -> void:
	_wall_column()
	var bloater := _sim.enemies.spawn(Vector2(8.5, 4.5), TOUGH, Enemies.Kind.BLOATER)
	assert_int(_tick_until(func() -> bool: return _sim.enemies.fuse(bloater) > 0)).is_not_negative()

	for tick in FUSE_TICKS - 1:
		_sim.tick()
		assert_int(_sim.enemies.index_of(bloater)).is_not_equal(Enemies.NONE)
	# Holding at the wall, it dealt the wall no damage.
	assert_float(_sim.piles.wall_hp(Vector2i(WALL_X, 4))).is_equal(TOUGH)

	_sim.tick()

	assert_int(_sim.enemies.index_of(bloater)).is_equal(Enemies.NONE)
	assert_int(_sim.deaths.ids[0]).is_equal(bloater)
	assert_int(_sim.deaths.killers[0]).is_equal(Enemies.NONE)


func test_a_shot_during_the_fuse_pops_it_at_once_credited_to_the_tower() -> void:
	_settings.change("towers", "damage", 50.0)
	_wall_column()
	var bloater := _sim.enemies.spawn(Vector2(8.5, 4.5), 30.0, Enemies.Kind.BLOATER)
	_tick_until(func() -> bool: return _sim.enemies.fuse(bloater) > 0)
	_sim.queue_command(Commands.Build.new(Buildings.TOWER, Vector2i(4, 1)))

	_sim.tick()

	assert_int(_sim.enemies.index_of(bloater)).is_equal(Enemies.NONE)
	assert_int(_sim.deaths.killers[0]).is_equal(_sim.buildings.built[0].id)


func test_the_blast_kills_enemies_inside_2_cells_and_none_outside() -> void:
	var tower := _idle_tower()
	var bloater := _sim.enemies.spawn(Vector2(5.5, 5.0), TOUGH, Enemies.Kind.BLOATER)
	var inside := _sim.enemies.spawn(Vector2(5.5, 3.1), TOUGH)
	var outside := _sim.enemies.spawn(Vector2(5.5, 7.2), TOUGH)

	_pop(bloater, tower)

	assert_array(Array(_sim.deaths.ids)).contains_exactly([bloater, inside])
	assert_int(_sim.deaths.killers[1]).is_equal(tower)
	assert_int(_sim.deaths.blasts[0]).is_equal(0)
	assert_int(_sim.deaths.blasts[1]).is_equal(1)
	assert_int(_sim.enemies.index_of(outside)).is_not_equal(Enemies.NONE)


func test_a_chain_reaches_a_second_bloater() -> void:
	var tower := _idle_tower()
	var first := _sim.enemies.spawn(Vector2(4.5, 1.5), TOUGH, Enemies.Kind.BLOATER)
	var second := _sim.enemies.spawn(Vector2(4.5, 3.0), TOUGH, Enemies.Kind.BLOATER)
	# Out of the first's reach, inside the second's.
	var beyond := _sim.enemies.spawn(Vector2(4.5, 4.8), TOUGH)

	_pop(first, tower)

	assert_array(Array(_sim.deaths.ids)).contains_exactly([first, second, beyond])
	assert_array(Array(_sim.deaths.killers)).contains_exactly([tower, tower, tower])


func test_no_bodies_land_from_the_blast() -> void:
	var tower := _idle_tower()
	var bloater := _sim.enemies.spawn(Vector2(5.5, 5.5), TOUGH, Enemies.Kind.BLOATER)
	_sim.enemies.spawn(Vector2(5.5, 4.5), TOUGH)
	_sim.enemies.spawn(Vector2(6.5, 5.5), TOUGH)

	_pop(bloater, tower)
	_sim.tick()

	assert_int(_sim.deaths.size()).is_equal(0)
	for y in 10:
		for x in 20:
			assert_int(_sim.piles.level(Vector2i(x, y))).is_equal(0)


func test_the_killers_combo_gains_every_blast_kill() -> void:
	var tower := _idle_tower()
	var bloater := _sim.enemies.spawn(Vector2(5.5, 5.5), TOUGH, Enemies.Kind.BLOATER)
	for n in 3:
		_sim.enemies.spawn(Vector2(4.5 + n, 4.5), TOUGH)
	var gold := _sim.run_state.gold

	_pop(bloater, tower)

	assert_int(_sim.combos.combo(tower).count).is_equal(4)
	assert_int(_sim.run_state.kills).is_equal(4)
	# The bloater's 2 and three kills of 1, all at x1.
	assert_int(_sim.run_state.gold - gold).is_equal(5)


func test_a_self_pop_pays_x1_for_its_blast_kills_and_no_bloater_bounty() -> void:
	_wall_column()
	var bloater := _sim.enemies.spawn(Vector2(8.5, 4.5), TOUGH, Enemies.Kind.BLOATER)
	_tick_until(func() -> bool: return _sim.enemies.fuse(bloater) > 0)
	for n in FUSE_TICKS - 1:
		_sim.tick()
	_sim.enemies.spawn(Vector2(8.5, 3.5), TOUGH)
	_sim.enemies.spawn(Vector2(8.5, 5.5), TOUGH)
	var gold := _sim.run_state.gold

	_sim.tick()

	assert_int(_sim.deaths.size()).is_equal(3)
	assert_int(_sim.run_state.kills).is_equal(3)
	assert_int(_sim.run_state.gold - gold).is_equal(2)


func test_a_tower_in_range_takes_30_once_and_so_does_the_base() -> void:
	var tower := _idle_tower()
	var hp := _sim.buildings.building(tower).hp
	var base_hp := _sim.run_state.base_hp
	# Both of the tower's west cells are in reach of the first; two base cells of the second.
	var by_tower := _sim.enemies.spawn(Vector2(2.2, 9.0), TOUGH, Enemies.Kind.BLOATER)
	_sim.enemies.spawn(Vector2(17.2, 5.0), TOUGH, Enemies.Kind.BLOATER)
	var far_tower := _sim.buildings.building(tower)

	_pop(by_tower, tower)

	assert_float(far_tower.hp).is_equal_approx(hp - 30.0, 1e-6)
	assert_float(_sim.run_state.base_hp).is_equal_approx(base_hp, 1e-6)

	_pop(_sim.enemies.ids[0], tower)

	assert_float(far_tower.hp).is_equal_approx(hp - 30.0, 1e-6)
	assert_float(_sim.run_state.base_hp).is_equal_approx(base_hp - 30.0, 1e-6)


func test_a_wall_in_range_is_erased_and_the_fields_update() -> void:
	_wall_column()
	var tower := _idle_tower()
	_sim.piles.queue_bodies(Deaths.bodies_at([Vector2(7.5, 4.5), Vector2(7.5, 4.5)]))
	_sim.tick()
	var changed: Array[Vector2i] = []
	_sim.pile_changed.connect(func(cells: Array[Vector2i]) -> void: changed.append_array(cells))
	var bloater := _sim.enemies.spawn(Vector2(8.5, 4.5), TOUGH, Enemies.Kind.BLOATER)

	_pop(bloater, tower)

	assert_int(_sim.piles.level(Vector2i(WALL_X, 4))).is_equal(0)
	assert_int(_sim.piles.level(Vector2i(7, 4))).is_equal(0)
	# Just out of reach.
	assert_int(_sim.piles.level(Vector2i(WALL_X, 3))).is_equal(Piles.WALL_LEVEL)
	assert_array(changed).contains_exactly_in_any_order([Vector2i(WALL_X, 4), Vector2i(7, 4)])

	_sim.tick()

	assert_bool(FieldChecks.matches_full_rebuild(_sim)).is_true()


func test_a_bloater_picked_to_tumble_has_its_fuse_out() -> void:
	# A long fuse, so the bloaters held at the wall are still burning when the crush peaks.
	_settings.change("bloaters", "fuse", 10.0)
	_settings.change("overflow", "fill_per_stalled", 10.0)
	_wall_column()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var bloaters := {}
	for n in 60:
		var kind := Enemies.Kind.BLOATER if n % 2 == 0 else Enemies.Kind.NORMAL
		var pos := Vector2(rng.randf_range(1.0, 9.0), rng.randf_range(0.5, 9.5))
		var id := _sim.enemies.spawn(pos, TOUGH, kind)
		if kind == Enemies.Kind.BLOATER:
			bloaters[id] = true
	var lit := {}
	var tumbled := 0

	for tick in 8 * Simulation.TICKS_PER_SECOND:
		_sim.tick()
		for id: int in bloaters:
			if _sim.overflow.is_tumbling(id):
				if lit.get(id, false):
					tumbled += 1
				assert_int(_sim.enemies.fuse(id)).is_equal(0)
			lit[id] = _sim.enemies.fuse(id) > 0

	assert_int(tumbled).is_greater(0)


func test_a_debug_killed_bloater_still_pays_its_bounty() -> void:
	_sim.enemies.spawn(Vector2(5.5, 5.5), TOUGH, Enemies.Kind.BLOATER)
	var gold := _sim.run_state.gold

	_sim.queue_command(Commands.KillEnemies.new(1))
	_sim.tick()

	assert_int(_sim.run_state.gold - gold).is_equal(2)


func test_a_tower_destroyed_by_the_blast_leaves_at_once_and_loses_its_combo() -> void:
	_settings.change("towers", "hp", 30.0)
	var tower := _idle_tower()
	var destroyed: Array[int] = []
	_sim.building_destroyed.connect(func(id: int) -> void: destroyed.append(id))
	var bloater := _sim.enemies.spawn(Vector2(2.2, 9.0), TOUGH, Enemies.Kind.BLOATER)
	var gold := _sim.run_state.gold

	_pop(bloater, tower)

	assert_object(_sim.buildings.building(tower)).is_null()
	assert_array(destroyed).contains_exactly([tower])
	assert_object(_sim.combos.combo(tower)).is_null()
	assert_int(_sim.occupancy.building_at(Vector2i(0, 8))).is_equal(Occupancy.EMPTY)
	# Its killer destroyed this tick, the bloater pays x1.
	assert_int(_sim.run_state.gold - gold).is_equal(2)


# A column of walls across the field at WALL_X, landed.
func _wall_column() -> void:
	var bodies := PackedVector2Array()
	for y in 10:
		for n in Piles.WALL_LEVEL:
			bodies.append(Vector2(WALL_X + 0.5, y + 0.5))
	_sim.piles.queue_bodies(Deaths.bodies_at(bodies))
	_sim.tick()


# Ticks until [param done] holds, returning the ticks taken, or -1 after 10 s.
func _tick_until(done: Callable) -> int:
	for tick in 10 * Simulation.TICKS_PER_SECOND:
		_sim.tick()
		if done.call():
			return tick
	return -1


# A powered tower, built at the field's corner, that deals no damage: a killer to credit.
func _idle_tower() -> int:
	_settings.change("towers", "damage", 0.0)
	_sim.queue_command(Commands.Build.new(Buildings.TOWER, Vector2i(0, 8)))
	_sim.tick()
	return _sim.buildings.built[-1].id


# Kills the enemy with id [param id] at the start of the next tick, credited to [param by], as
# if a building had shot it, and runs that tick.
func _pop(id: int, by: int) -> void:
	_sim.step_observer = func(step: int) -> void:
		if step == Simulation.Step.DRAIN_COMMANDS:
			_sim.enemies.damage(id, TOUGH * 10.0, by)
	_sim.tick()
	_sim.step_observer = Callable()
