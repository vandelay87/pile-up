extends GdUnitTestSuite

# A corridor sealed by a tower at (5, 0) over rock at (5, 2) and (6, 2): the only way to the
# base at the east end is through the tower.
const SEALED: Array[String] = ["............", "............", ".....##....."]
const BASE := Rect2i(11, 0, 1, 3)
const TOWER_ORIGIN := Vector2i(5, 0)
const ARRIVAL_TICKS := 1200
# Enemies tough enough to outlast the tower's own fire.
const TOUGH := 1e6

var _settings: Settings
var _events: Array[String]


func before_test() -> void:
	_settings = TestSettings.without_swarm_spread()
	_settings.change("enemies", "heading_offset", 0.0)
	_events = []


func test_a_tower_sealing_the_base_off_is_accepted_and_attackers_chew_it_at_2_hp_per_second(
) -> void:
	var sim := _sealed_sim()
	var tower := _build_tower(sim, TOWER_ORIGIN)
	assert_float(tower.hp).is_equal(60.0)
	sim.enemies.spawn(Vector2(1.5, 1.5), TOUGH)
	_run_until(sim, func() -> bool: return tower.hp < 60.0)
	var hp_before := tower.hp

	for tick in Simulation.TICKS_PER_SECOND:
		sim.tick()

	assert_float(hp_before - tower.hp).is_equal_approx(2.0, 1e-6)


func test_a_tower_at_0_hp_is_destroyed_its_cells_clear_and_attackers_walk_on_through_them() -> void:
	_settings.change("towers", "hp", 4.0)
	var sim := _sealed_sim()
	var tower := _build_tower(sim, TOWER_ORIGIN)
	var id := sim.enemies.spawn(Vector2(1.5, 1.5), TOUGH)

	_run_until(sim, func() -> bool: return _events.has("destroyed 0"))

	assert_float(tower.hp).is_equal(0.0)
	assert_object(sim.buildings.building(tower.id)).is_null()
	assert_array(sim.buildings.built).is_empty()
	for cell in tower.footprint:
		assert_bool(sim.occupancy.is_occupied(cell)).is_false()
		assert_int(sim.structures.structure_at(cell)).is_equal(Structures.Kind.NONE)
	assert_bool(FieldChecks.matches_full_rebuild(sim)).is_false()

	_events.clear()
	sim.tick()

	assert_bool(FieldChecks.matches_full_rebuild(sim)).is_true()
	assert_array(_events).contains(["fields changed"])
	_run_until(sim, func() -> bool: return _position(sim, id).x > TOWER_ORIGIN.x + 2)
	assert_int(sim.enemies.structure_targets[sim.enemies.index_of(id)]).is_equal(Enemies.NONE)


func test_a_destroyed_tower_leaves_its_cells_buildable() -> void:
	_settings.change("towers", "hp", 4.0)
	var sim := _sealed_sim()
	_build_tower(sim, TOWER_ORIGIN)
	sim.enemies.spawn(Vector2(1.5, 1.5), TOUGH)
	_run_until(sim, func() -> bool: return _events.has("destroyed 0"))
	_events.clear()

	sim.queue_command(Commands.Build.new(Buildings.TOWER, TOWER_ORIGIN))
	sim.tick()

	assert_array(_events).contains(["placed 1"])


func test_a_base_sealed_by_a_tower_and_a_wall_is_breached_through_the_cheaper_wall() -> void:
	var open: Array[String] = ["............", "............", "............"]
	var sim := Simulation.new(_settings, TestMaps.from_rows(open, BASE), 1)
	sim.building_placed.connect(func(id: int) -> void: _events.append("placed %d" % id))
	var tower := _build_tower(sim, TOWER_ORIGIN)
	var wall := Vector2i(TOWER_ORIGIN.x, 2)
	var bodies := PackedVector2Array()
	for n in Piles.WALL_LEVEL:
		bodies.append(Vector2(wall) + Vector2(0.5, 0.5))
	sim.piles.queue_bodies(bodies)
	sim.tick()
	var id := sim.enemies.spawn(Vector2(1.5, 1.5), TOUGH)

	_run_until(sim, func() -> bool: return _position(sim, id).x > TOWER_ORIGIN.x + 2)

	assert_int(sim.piles.level(wall)).is_equal(Piles.FALLEN_WALL_LEVEL)
	assert_float(tower.hp).is_equal(60.0)


func test_a_tower_hp_bucket_change_updates_the_fields_at_step_1_of_the_next_tick() -> void:
	var sim := _sealed_sim()
	var tower := _build_tower(sim, TOWER_ORIGIN)
	sim.step_observer = func(step: int) -> void:
		if step == Simulation.Step.MOVE_ENEMIES:
			sim.structures.damage(TOWER_ORIGIN, _settings.wall_hp_bucket)

	sim.tick()
	sim.step_observer = Callable()

	assert_float(tower.hp).is_equal(60.0 - _settings.wall_hp_bucket)
	assert_bool(FieldChecks.matches_full_rebuild(sim)).is_false()
	assert_array(_events).not_contains(["fields changed"])

	sim.tick()

	assert_bool(FieldChecks.matches_full_rebuild(sim)).is_true()
	assert_array(_events).contains_exactly(["fields changed"])


func test_damage_within_a_tower_hp_bucket_leaves_the_fields_alone() -> void:
	var sim := _sealed_sim()
	var tower := _build_tower(sim, TOWER_ORIGIN)
	var before := sim.routing.value(Routing.Route.SENSIBLE, Vector2i(0, 1))

	sim.structures.damage(TOWER_ORIGIN, _settings.wall_hp_bucket - 1.0)
	sim.tick()

	assert_float(tower.hp).is_less(60.0)
	assert_array(_events).is_empty()
	assert_float(sim.routing.value(Routing.Route.SENSIBLE, Vector2i(0, 1))).is_equal(before)


func _sealed_sim() -> Simulation:
	var sim := Simulation.new(_settings, TestMaps.from_rows(SEALED, BASE), 1)
	sim.command_rejected.connect(func(reason: String) -> void: _events.append(reason))
	sim.building_placed.connect(func(id: int) -> void: _events.append("placed %d" % id))
	sim.building_destroyed.connect(func(id: int) -> void: _events.append("destroyed %d" % id))
	sim.fields_changed.connect(func() -> void: _events.append("fields changed"))
	return sim


func _build_tower(sim: Simulation, origin: Vector2i) -> Buildings.Building:
	sim.queue_command(Commands.Build.new(Buildings.TOWER, origin))
	sim.tick()
	assert_array(_events).contains(["placed 0"])
	_events.clear()
	return sim.buildings.built[sim.buildings.built.size() - 1]


func _run_until(sim: Simulation, done: Callable) -> void:
	for tick in ARRIVAL_TICKS:
		sim.tick()
		if done.call():
			return
	fail("the condition was not met within %d ticks" % ARRIVAL_TICKS)


func _position(sim: Simulation, id: int) -> Vector2:
	return sim.enemies.positions[sim.enemies.index_of(id)]
