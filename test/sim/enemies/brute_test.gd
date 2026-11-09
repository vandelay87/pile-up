extends GdUnitTestSuite

## The brute: a big, slow enemy locked to the direct route, breaking structures five times as
## fast, shouldering through the crowd by mass, never tumbling.

const WALL_LINE: Array[Vector2i] = [Vector2i(4, 0), Vector2i(4, 1), Vector2i(4, 2)]
# A wall line across the field with a gap at the bottom: the sensible route goes round by the
# gap, the direct one straight through the wall.
const GAPPED: Array[String] = [
	"..........",
	"..........",
	"..........",
	"..........",
	"..........",
	"..........",
	"..........",
]

var _settings: Settings
var _piles: Piles
var _routing: Routing


func before_test() -> void:
	_settings = TestSettings.without_swarm_spread()
	_settings.change("enemies", "heading_offset", 0.0)


func test_the_brute_settings_load_with_their_starting_values() -> void:
	assert_float(_settings.enemy_hp_of(Enemies.Kind.BRUTE)).is_equal(40.0)
	assert_float(_settings.enemy_speed_per_tick_of(Enemies.Kind.BRUTE)).is_equal_approx(
		1.4 / Simulation.TICKS_PER_SECOND, 1e-9
	)
	assert_int(_settings.enemy_bounty_of(Enemies.Kind.BRUTE)).is_equal(4)
	assert_float(_settings.enemy_mass_of(Enemies.Kind.BRUTE)).is_equal(3.0)
	assert_float(_settings.enemy_mass_of(Enemies.Kind.NORMAL)).is_equal(1.0)
	assert_float(_settings.enemy_mass_of(Enemies.Kind.BLOATER)).is_equal(1.0)
	assert_float(_settings.structure_damage_per_tick_of(Enemies.Kind.BRUTE)).is_equal_approx(
		10.0 / Simulation.TICKS_PER_SECOND, 1e-9
	)
	assert_float(_settings.enemy_size_of(Enemies.Kind.BRUTE)).is_equal(1.8)


func test_a_brute_spawns_on_the_direct_route_and_a_normal_enemy_on_the_sensible() -> void:
	var enemies := _enemies(GAPPED, Rect2i(8, 3, 2, 2))
	var brute := enemies.spawn(Vector2(1.5, 3.5), 40.0, Enemies.Kind.BRUTE)
	var normal := enemies.spawn(Vector2(1.5, 1.5), 10.0)

	assert_int(_route(enemies, brute)).is_equal(Routing.Route.DIRECT)
	assert_int(_route(enemies, normal)).is_equal(Routing.Route.SENSIBLE)


func test_a_brute_never_leaves_the_direct_route_past_obstacles_and_in_the_wave_tail() -> void:
	_settings.change("enemies", "pile_roll_chance", 100)
	_settings.change("enemies", "wall_roll_chance", 100)
	var enemies := _enemies(GAPPED, Rect2i(8, 3, 2, 2))
	_build_walls(_column(5, 0, 5))
	var brute := enemies.spawn(Vector2(1.5, 3.5), 40.0, Enemies.Kind.BRUTE)
	# A normal enemy rolled onto the direct route goes back to the sensible one past its wall.
	var normal := enemies.spawn(Vector2(1.5, 2.5), 1000.0)

	var normal_went_back := false
	for tick in 20 * Simulation.TICKS_PER_SECOND:
		_routing.update(_piles.take_field_changes())
		_routing.step()
		enemies.rebuild_spatial_hash()
		enemies.move(tick % 2 == 0)
		assert_int(_route(enemies, brute)).is_equal(Routing.Route.DIRECT)
		var normal_at := enemies.index_of(normal)
		if normal_at != Enemies.NONE and enemies.positions[normal_at].x > 6.0:
			normal_went_back = normal_went_back or _route(enemies, normal) == Routing.Route.SENSIBLE

	# It broke through the wall rather than going round by the gap.
	assert_float(enemies.positions[enemies.index_of(brute)].x).is_greater(6.0)
	assert_bool(normal_went_back).is_true()


func test_a_brute_coming_down_from_a_lifted_state_is_back_on_the_direct_route() -> void:
	var enemies := _enemies(GAPPED, Rect2i(8, 3, 2, 2))
	var brute := enemies.spawn(Vector2(1.5, 3.5), 40.0, Enemies.Kind.BRUTE)
	var index := enemies.index_of(brute)

	enemies.set_state(index, Enemies.State.TUMBLING)
	enemies.set_state(index, Enemies.State.WALKING)

	assert_int(_route(enemies, brute)).is_equal(Routing.Route.DIRECT)


func test_a_brute_deals_10_hp_a_second_and_breaks_a_wall_in_1_5_seconds() -> void:
	var enemies := _enemies(["........", "........", "........"], Rect2i(7, 0, 1, 3))
	_build_walls(WALL_LINE)
	enemies.spawn(Vector2(3.7, 1.5), 1000.0, Enemies.Kind.BRUTE)

	for tick in Simulation.TICKS_PER_SECOND:
		_tick(enemies)
	assert_float(_hp_lost()).is_equal_approx(10.0, 1e-6)

	for tick in Simulation.TICKS_PER_SECOND / 2 - 1:
		_tick(enemies)
	assert_int(_piles.level(WALL_LINE[1])).is_equal(Piles.WALL_LEVEL)
	# 1.5 s, give or take the tick that float sums of 10/60 HP land on.
	for tick in 2:
		_tick(enemies)
	assert_int(_piles.level(WALL_LINE[1])).is_equal(Piles.FALLEN_WALL_LEVEL)


func test_two_enemies_of_equal_mass_separate_exactly_as_two_normal_enemies() -> void:
	# Brutes at a normal enemy's speed, so only the masses differ.
	_settings.change("brutes", "speed", _settings.enemy_speed)
	var normals := _enemies(GAPPED, Rect2i(8, 3, 2, 2))
	var brutes := _enemies(GAPPED, Rect2i(8, 3, 2, 2))
	for pos: Vector2 in [Vector2(2.5, 3.4), Vector2(2.6, 3.6), Vector2(2.45, 3.55)]:
		normals.spawn(pos, 10.0)
		brutes.spawn(pos, 40.0, Enemies.Kind.BRUTE)
	for enemies: Enemies in [normals, brutes]:
		for tick in 10:
			enemies.rebuild_spatial_hash()
			enemies.move()

	for i in normals.count:
		assert_vector(brutes.positions[i]).is_equal(normals.positions[i])


func test_a_brute_is_pushed_a_third_as_far_as_a_normal_enemy_beside_it() -> void:
	_settings.change("brutes", "speed", _settings.enemy_speed)
	var enemies := _enemies(GAPPED, Rect2i(8, 3, 2, 2))
	var brute := enemies.spawn(Vector2(2.5, 3.4), 40.0, Enemies.Kind.BRUTE)
	var normal := enemies.spawn(Vector2(2.5, 3.6), 10.0)

	enemies.rebuild_spatial_hash()
	enemies.move()

	var brute_pushed := 3.4 - enemies.positions[enemies.index_of(brute)].y
	var normal_pushed := enemies.positions[enemies.index_of(normal)].y - 3.6
	assert_float(brute_pushed).is_greater(0.0)
	# Half its equal-mass push against one and a half times as much.
	assert_float(normal_pushed).is_equal_approx(3.0 * brute_pushed, 1e-5)


func _route(enemies: Enemies, id: int) -> int:
	return enemies.routes[enemies.index_of(id)]


func _hp_lost() -> float:
	var lost := 0.0
	for cell in WALL_LINE:
		lost += _settings.wall_hp - _piles.wall_hp(cell)
	return lost


func _enemies(rows: Array[String], base: Rect2i) -> Enemies:
	var systems := TestSystems.new(_settings, TestMaps.from_rows(rows, base))
	_piles = systems.piles
	_routing = systems.routing()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	return systems.enemies(_routing, rng)


func _column(x: int, top: int, bottom: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in range(top, bottom + 1):
		cells.append(Vector2i(x, y))
	return cells


func _build_walls(cells: Array[Vector2i]) -> void:
	var bodies := PackedVector2Array()
	for cell in cells:
		for n in Piles.WALL_LEVEL:
			bodies.append(Vector2(cell) + Vector2(0.5, 0.5))
	_piles.queue_bodies(Deaths.bodies_at(bodies))
	_piles.land()
	_routing.update(_piles.take_field_changes())
	_routing.step()
	while _routing.is_settling():
		_routing.step()


func _tick(enemies: Enemies) -> void:
	_routing.update(_piles.take_field_changes())
	_routing.step()
	enemies.rebuild_spatial_hash()
	enemies.move()
