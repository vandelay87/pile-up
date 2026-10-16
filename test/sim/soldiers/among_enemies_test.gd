extends "res://test/sim/soldiers/order_suite.gd"

# Soldiers among enemies: the contact pass by mass at step 5, from the soldier side.

const OPEN: Array[String] = [
	"..............",
	"..............",
	"..............",
	"..............",
	"..............",
]
# A corridor two cells wide from the east edge to the base in the west.
const CORRIDOR: Array[String] = [
	"##############",
	"..............",
	"..............",
	"..############",
	"..############",
]


func test_an_enemy_overlapping_a_soldier_is_pushed_five_times_as_far_as_the_soldier() -> void:
	var alone := _sim_from(OPEN)
	alone.enemies.spawn(Vector2(7.8, 1.5), 10.0)
	alone.tick()
	_sim = _sim_from(OPEN)
	var id := _sim.soldiers.add(Vector2i(7, 1))
	_sim.enemies.spawn(Vector2(7.8, 1.5), 10.0)

	_sim.tick()

	var enemy_pushed := _sim.enemies.positions[0].distance_to(alone.enemies.positions[0])
	var soldier_pushed := _position_of(id).distance_to(Vector2(7.5, 1.5))
	assert_float(soldier_pushed).is_greater(0.0)
	assert_float(enemy_pushed).is_equal_approx(5.0 * soldier_pushed, 1e-4)


func test_a_soldier_and_an_enemy_push_apart_softly_as_enemies_do() -> void:
	_sim = _sim_from(OPEN)
	var id := _sim.soldiers.add(Vector2i(7, 1))
	_sim.enemies.spawn(Vector2(7.8, 1.5), 10.0)

	_sim.tick()

	var apart := _position_of(id).distance_to(_sim.enemies.positions[0])
	assert_float(apart).is_less(2.0 * _sim.settings.separation_radius - 0.01)


func test_a_tumbling_enemy_neither_pushes_nor_is_pushed_by_a_soldier() -> void:
	_sim = _sim_from(OPEN)
	var id := _sim.soldiers.add(Vector2i(7, 1))
	_sim.enemies.spawn(Vector2(7.8, 1.5), 10.0)
	_sim.enemies.start_tumble(0)

	_sim.tick()

	assert_vector(_position_of(id)).is_equal(Vector2(7.5, 1.5))
	assert_vector(_sim.enemies.positions[0]).is_equal(Vector2(7.8, 1.5))


func test_a_standing_soldier_pushed_by_a_thin_stream_returns_to_its_spot() -> void:
	_sim = _sim_from(
		[
			"##############",
			"..............",
			"..............",
			"..............",
			"..############",
			"..############",
		]
	)
	var id := _sim.soldiers.add(Vector2i(7, 2))
	var furthest := 0.0
	for tick in 480:
		if tick % 40 == 0 and tick < 320:
			_sim.enemies.spawn(Vector2(13.5, 2.5), 10.0)
		_sim.tick()
		furthest = maxf(furthest, _position_of(id).distance_to(Vector2(7.5, 2.5)))
	for tick in 240:
		_sim.tick()

	assert_float(furthest).is_greater(Soldiers.SPOT_SLACK)
	assert_object(_spot_of(id)).is_equal(Vector2i(7, 2))
	var off := _position_of(id).distance_to(Vector2(7.5, 2.5))
	assert_float(off).is_less_equal(Soldiers.SPOT_SLACK)


func test_a_surge_pushes_a_soldier_line_back() -> void:
	_sim = _sim_from(CORRIDOR)
	var ids := [_sim.soldiers.add(Vector2i(7, 1)), _sim.soldiers.add(Vector2i(7, 2))]
	_spawn_crowd(Rect2(8.4, 1.2, 5.4, 1.6), 140)
	var furthest := 0.0
	for tick in 240:
		_sim.tick()
		for id: int in ids:
			furthest = maxf(furthest, 7.5 - _position_of(id).x)

	assert_float(furthest).is_greater(Soldiers.WALK_BACK_REACH)


func test_a_walking_soldier_makes_less_progress_through_a_crowd_than_across_open_ground() -> void:
	_sim = _sim_from(CORRIDOR)
	var open_id := _sim.soldiers.add(Vector2i(2, 1))
	_move([open_id], Vector2(13.5, 1.5), Formations.CLUSTER)
	for tick in 120:
		_sim.tick()
	var open_progress := _position_of(open_id).x - 2.5
	_sim = _sim_from(CORRIDOR)
	var crowd_id := _sim.soldiers.add(Vector2i(2, 1))
	_spawn_crowd(Rect2(4.2, 1.2, 9.6, 1.6), 50)
	_move([crowd_id], Vector2(13.5, 1.5), Formations.CLUSTER)
	for tick in 120:
		_sim.tick()

	assert_float(_position_of(crowd_id).x - 2.5).is_less(open_progress - 1.0)


func test_enemies_are_never_pushed_into_a_wall() -> void:
	_sim = _sim_from(
		[
			"##############",
			".....W........",
			".....W........",
			"..############",
			"..############",
		]
	)
	_spawn_crowd(Rect2(6.3, 1.2, 0.4, 1.6), 4)
	for tick in 60:
		_sim.tick()
	var id := _sim.soldiers.add(Vector2i(10, 1))
	_move([id], Vector2(2.5, 1.5), Formations.CLUSTER)

	for tick in 180:
		_sim.tick()
		_assert_enemies_clear_of([Vector2i(5, 1), Vector2i(5, 2)])


func test_enemies_are_never_pushed_into_a_building() -> void:
	_sim = _sim_from(CORRIDOR)
	_sim.add_gold(2 * _sim.settings.pylon_cost)
	_sim.queue_command(Commands.Build.new(Buildings.PYLON, Vector2i(5, 1)))
	_sim.queue_command(Commands.Build.new(Buildings.PYLON, Vector2i(5, 2)))
	_spawn_crowd(Rect2(6.3, 1.2, 0.4, 1.6), 4)
	for tick in 60:
		_sim.tick()
	var id := _sim.soldiers.add(Vector2i(10, 1))
	_move([id], Vector2(6.5, 1.5), Formations.CLUSTER)

	for tick in 180:
		_sim.tick()
		_assert_enemies_clear_of([Vector2i(5, 1), Vector2i(5, 2)])


func test_soldiers_never_enter_the_flow_fields_or_a_barrier() -> void:
	var without := _sim_from(CORRIDOR)
	_sim = without
	_spawn_crowd(Rect2(8.4, 1.2, 5.4, 1.6), 40)
	_sim = _sim_from(CORRIDOR)
	_sim.soldiers.add(Vector2i(7, 1))
	_sim.soldiers.add(Vector2i(7, 2))
	_spawn_crowd(Rect2(8.4, 1.2, 5.4, 1.6), 40)
	for sim: Simulation in [without, _sim]:
		sim.add_gold(sim.settings.pylon_cost)
		sim.queue_command(Commands.Build.new(Buildings.PYLON, Vector2i(10, 1)))
		for tick in 60:
			sim.tick()
	assert_bool(_sim.soldiers.positions[0] == Vector2(7.5, 1.5)).is_false()

	for y in _sim.map.height:
		for x in _sim.map.width:
			var cell := Vector2i(x, y)
			for route: Routing.Route in Routing.Route.values():
				assert_float(_sim.routing.value(route, cell)).is_equal(
					without.routing.value(route, cell)
				)
			assert_int(_sim.overflow.barrier_label(cell)).is_equal(
				without.overflow.barrier_label(cell)
			)


func _spawn_crowd(area: Rect2, wanted: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	for n in wanted:
		var pos := area.position + Vector2(rng.randf(), rng.randf()) * area.size
		_sim.enemies.spawn(pos, 10.0)


func _assert_enemies_clear_of(cells: Array[Vector2i]) -> void:
	var radius := _sim.settings.separation_radius
	for i in _sim.enemies.count:
		if _sim.enemies.tumbling[i] == 1:
			continue
		var pos := _sim.enemies.positions[i]
		for cell in cells:
			var wall := _sim.piles.level(cell) == Piles.WALL_LEVEL
			if not wall and _sim.occupancy.building_at(cell) == Occupancy.EMPTY:
				continue
			var closest := pos.clamp(Vector2(cell), Vector2(cell + Vector2i.ONE))
			(
				assert_float(pos.distance_to(closest))
				. override_failure_message("enemy at %s inside %s" % [pos, cell])
				. is_greater_equal(radius - 1e-4)
			)
