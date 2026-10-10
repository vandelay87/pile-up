extends GdUnitTestSuite

const CORRIDOR: Array[String] = [".........", ".........", "........."]
const CORRIDOR_BASE := Rect2i(8, 0, 1, 3)
const PILE := Vector2i(4, 1)
const BESIDE_OBSTACLE := Vector2(3.5, 1.5)
const WALL := Vector2i(4, 1)
const WALL_BASE := Rect2i(8, 0, 1, 9)
const SAMPLE_ENEMIES := 4000
const RATE_TOLERANCE := 0.01

var _settings: Settings
var _piles: Piles
var _routing: Routing


func before_test() -> void:
	_settings = TestSettings.without_swarm_spread()
	_settings.change("enemies", "heading_offset", 0.0)


func test_at_full_chance_an_enemy_beside_a_pile_switches_to_the_direct_route() -> void:
	_settings.change("enemies", "pile_roll_chance", 100)
	var enemies := _enemies(CORRIDOR, CORRIDOR_BASE)
	_add_bodies(PILE, 4)
	_assert_next_cells_differ(Vector2i(BESIDE_OBSTACLE.floor()))
	var id := enemies.spawn(BESIDE_OBSTACLE, _settings.enemy_hp)
	assert_int(_route(enemies, id)).is_equal(Routing.Route.SENSIBLE)

	_tick(enemies)

	assert_int(_route(enemies, id)).is_equal(Routing.Route.DIRECT)


func test_an_enemy_rolls_once_for_an_obstacle_and_never_again_for_it() -> void:
	_settings.change("enemies", "pile_roll_chance", 0)
	var enemies := _enemies(CORRIDOR, CORRIDOR_BASE)
	_add_bodies(PILE, 4)
	var id := enemies.spawn(BESIDE_OBSTACLE, _settings.enemy_hp)
	_tick(enemies)
	assert_int(_route(enemies, id)).is_equal(Routing.Route.SENSIBLE)

	_settings.change("enemies", "pile_roll_chance", 100)
	_tick(enemies)

	assert_vector(Vector2i(_position(enemies, id).floor())).is_equal(
		Vector2i(BESIDE_OBSTACLE.floor())
	)
	assert_int(_route(enemies, id)).is_equal(Routing.Route.SENSIBLE)


func test_an_enemy_never_rolls_when_both_routes_step_into_the_same_cell() -> void:
	_settings.change("enemies", "pile_roll_chance", 100)
	var enemies := _enemies(CORRIDOR, CORRIDOR_BASE)
	_add_bodies(PILE, 1)
	var cell := Vector2i(BESIDE_OBSTACLE.floor())
	assert_vector(_routing.parent(Routing.Route.DIRECT, cell)).is_equal(
		_routing.parent(Routing.Route.SENSIBLE, cell)
	)
	var id := enemies.spawn(BESIDE_OBSTACLE, _settings.enemy_hp)

	_tick(enemies)

	assert_int(_route(enemies, id)).is_equal(Routing.Route.SENSIBLE)


func test_an_enemy_rolls_for_a_pile_up_to_40_steps_down_the_direct_route() -> void:
	_settings.change("enemies", "pile_roll_chance", 100)
	for steps: int in [40, 41]:
		var lane := ".".repeat(50)
		var spine := "..." + "#".repeat(45) + ".."
		var enemies := _enemies([lane, spine, lane], Rect2i(49, 0, 1, 3))
		var start := Vector2(2.5, 1.5)
		var first := _routing.parent(Routing.Route.DIRECT, Vector2i(start.floor()))
		assert_vector(first).is_equal(Vector2i(2, 2))
		_add_bodies(first + Vector2i(steps - 1, 0), 4)
		_assert_next_cells_differ(Vector2i(start.floor()))
		var id := enemies.spawn(start, _settings.enemy_hp)

		_tick(enemies)

		var expected := Routing.Route.DIRECT if steps == 40 else Routing.Route.SENSIBLE
		assert_int(_route(enemies, id)).is_equal(expected)


func test_a_direct_route_enemy_pushes_through_the_pile_then_returns_to_sensible() -> void:
	_settings.change("enemies", "pile_roll_chance", 100)
	var enemies := _enemies(CORRIDOR, CORRIDOR_BASE)
	_add_bodies(PILE, 4)
	var id := enemies.spawn(BESIDE_OBSTACLE, _settings.enemy_hp)

	var cells := _walk_until_past(enemies, id, PILE.x + 1.5)

	assert_bool(PILE in cells).is_true()
	for cell in cells:
		assert_int(cell.y).is_equal(PILE.y)
	assert_int(_route(enemies, id)).is_equal(Routing.Route.SENSIBLE)


func test_a_direct_route_enemy_stays_direct_until_past_the_obstacle() -> void:
	_settings.change("enemies", "pile_roll_chance", 100)
	var enemies := _enemies(CORRIDOR, CORRIDOR_BASE)
	_add_bodies(PILE, 4)
	var id := enemies.spawn(BESIDE_OBSTACLE, _settings.enemy_hp)
	_tick(enemies)

	while _position(enemies, id).x < PILE.x + 0.5:
		assert_int(_route(enemies, id)).is_equal(Routing.Route.DIRECT)
		_tick(enemies)


func test_a_direct_route_enemy_attacks_the_wall_it_rolled_for_without_jamming() -> void:
	_settings.change("enemies", "wall_roll_chance", 100)
	_settings.change("enemies", "jam_seconds", 10.0)
	var enemies := _walled_field()
	var id := enemies.spawn(BESIDE_OBSTACLE, _settings.enemy_hp)
	_tick(enemies)
	assert_int(_route(enemies, id)).is_equal(Routing.Route.DIRECT)

	for tick in Simulation.TICKS_PER_SECOND:
		_tick(enemies)

	assert_float(_piles.wall_hp(WALL)).is_less(_settings.wall_hp)


func test_a_direct_route_enemy_returns_to_sensible_after_its_wall_breaks() -> void:
	_settings.change("enemies", "wall_roll_chance", 100)
	var enemies := _walled_field()
	var id := enemies.spawn(BESIDE_OBSTACLE, _settings.enemy_hp)
	_tick(enemies)
	assert_int(_route(enemies, id)).is_equal(Routing.Route.DIRECT)

	_piles.damage_wall(WALL, _settings.wall_hp)
	_walk_until_past(enemies, id, WALL.x + 1.5)

	assert_float(_position(enemies, id).x).is_greater(WALL.x + 1.5)
	assert_int(_route(enemies, id)).is_equal(Routing.Route.SENSIBLE)


func test_a_direct_route_enemy_returns_to_sensible_after_its_pile_decays() -> void:
	_settings.change("enemies", "pile_roll_chance", 100)
	var enemies := _enemies(CORRIDOR, CORRIDOR_BASE)
	_add_bodies(PILE, 4)
	var id := enemies.spawn(BESIDE_OBSTACLE, _settings.enemy_hp)
	_tick(enemies)
	assert_int(_route(enemies, id)).is_equal(Routing.Route.DIRECT)

	for level in 4:
		_piles.decay()
	_routing.rebuild()
	_walk_until_past(enemies, id, PILE.x + 1.5)

	assert_int(_piles.level(PILE)).is_equal(0)
	assert_float(_position(enemies, id).x).is_greater(PILE.x + 1.5)
	assert_int(_route(enemies, id)).is_equal(Routing.Route.SENSIBLE)


func test_a_direct_route_enemy_stuck_behind_attackers_stays_direct() -> void:
	_settings.change("enemies", "wall_roll_chance", 100)
	var enemies := _walled_field()
	enemies.spawn(Vector2(3.7, 1.5), _settings.enemy_hp)
	var behind := enemies.spawn(Vector2(3.1, 1.5), _settings.enemy_hp)

	for tick in 2 * Simulation.TICKS_PER_SECOND:
		_tick(enemies)
		assert_int(_route(enemies, behind)).is_equal(Routing.Route.DIRECT)

	assert_int(_piles.level(WALL)).is_equal(Piles.WALL_LEVEL)
	assert_float(_position(enemies, behind).x).is_less(WALL.x)


func test_at_the_default_pile_chance_about_5_percent_of_enemies_switch() -> void:
	var enemies := _crowd_beside(_enemies(CORRIDOR, CORRIDOR_BASE))
	_add_bodies(PILE, 4)

	_tick(enemies)

	assert_float(_direct_share(enemies)).is_equal_approx(0.05, RATE_TOLERANCE)


func test_at_the_default_wall_chance_about_3_percent_of_enemies_switch() -> void:
	var enemies := _crowd_beside(_walled_field())

	_tick(enemies)

	assert_float(_direct_share(enemies)).is_equal_approx(0.03, RATE_TOLERANCE)


func test_rolls_are_identical_for_the_same_seed() -> void:
	var runs: Array[PackedByteArray] = []
	for run in 2:
		var enemies := _crowd_beside(_enemies(CORRIDOR, CORRIDOR_BASE, 7))
		_add_bodies(PILE, 4)
		_tick(enemies)
		runs.append(enemies.routes.slice(0, enemies.count))
	var other_seed := _crowd_beside(_enemies(CORRIDOR, CORRIDOR_BASE, 8))
	_add_bodies(PILE, 4)
	_tick(other_seed)

	assert_array(runs[1]).is_equal(runs[0])
	assert_array(other_seed.routes.slice(0, other_seed.count)).is_not_equal(runs[0])


func _crowd_beside(enemies: Enemies) -> Enemies:
	_settings.change("enemies", "separation_push", 0.0)
	_settings.change("enemies", "neighbour_cap", 1)
	for n in SAMPLE_ENEMIES:
		enemies.spawn(BESIDE_OBSTACLE, _settings.enemy_hp)
	return enemies


func _direct_share(enemies: Enemies) -> float:
	var direct := 0
	for i in enemies.count:
		if enemies.routes[i] == Routing.Route.DIRECT:
			direct += 1
	return float(direct) / enemies.count


func _walled_field() -> Enemies:
	var enemies := _enemies(_rows(9, 9), WALL_BASE)
	for y in WALL_BASE.size.y - 1:
		_add_bodies(Vector2i(WALL.x, y), Piles.WALL_LEVEL)
	_assert_next_cells_differ(Vector2i(BESIDE_OBSTACLE.floor()))
	return enemies


func _rows(width: int, height: int) -> Array[String]:
	var rows: Array[String] = []
	for y in height:
		rows.append(".".repeat(width))
	return rows


func _walk_until_past(enemies: Enemies, id: int, x: float) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for tick in 10 * Simulation.TICKS_PER_SECOND:
		_tick(enemies)
		var pos := _position(enemies, id)
		cells.append(Vector2i(pos.floor()))
		if pos.x > x:
			break
	return cells


func _route(enemies: Enemies, id: int) -> int:
	return enemies.routes[enemies.index_of(id)]


func _position(enemies: Enemies, id: int) -> Vector2:
	return enemies.positions[enemies.index_of(id)]


func _assert_next_cells_differ(cell: Vector2i) -> void:
	assert_vector(_routing.parent(Routing.Route.DIRECT, cell)).is_not_equal(
		_routing.parent(Routing.Route.SENSIBLE, cell)
	)


func _enemies(rows: Array[String], base: Rect2i, rng_seed: int = 1) -> Enemies:
	var map := TestMaps.from_rows(rows, base)
	var occupancy := Occupancy.new(map.width, map.height)
	_piles = Piles.new(_settings, map, occupancy)
	_routing = Routing.new(_settings, map, occupancy, _piles)
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	return Enemies.new(_settings, map, occupancy, _piles, _routing, rng)


func _add_bodies(cell: Vector2i, bodies: int) -> void:
	var positions := PackedVector2Array()
	for n in bodies:
		positions.append(Vector2(cell) + Vector2(0.5, 0.5))
	_piles.queue_bodies(positions)
	_piles.land()
	_routing.update(_piles.take_field_changes())


func _tick(enemies: Enemies) -> void:
	_routing.update(_piles.take_field_changes())
	enemies.rebuild_spatial_hash()
	enemies.move()
