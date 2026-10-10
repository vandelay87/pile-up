extends GdUnitTestSuite

const WALL_LINE: Array[Vector2i] = [Vector2i(4, 0), Vector2i(4, 1), Vector2i(4, 2)]

var _settings: Settings
var _piles: Piles
var _routing: Routing


func before_test() -> void:
	_settings = TestSettings.without_swarm_spread()
	_settings.change("enemies", "heading_offset", 0.0)


func test_a_wall_forming_under_an_enemy_pushes_it_out() -> void:
	var enemies := _enemies(["........", "........", "........"], Rect2i(7, 0, 1, 3))
	var id := enemies.spawn(Vector2(3.5, 1.2), _settings.enemy_hp)
	_build_walls([Vector2i(3, 1)])

	_tick(enemies)

	assert_float(_position(enemies, id).y).is_less_equal(1.0 - _settings.separation_radius + 1e-4)


func test_n_attackers_deal_n_times_2_hp_per_second() -> void:
	for attackers: int in [1, 3]:
		var enemies := _walled_corridor()
		for n in attackers:
			enemies.spawn(Vector2(3.7, 0.5 + n), _settings.enemy_hp)

		for tick in Simulation.TICKS_PER_SECOND:
			_tick(enemies)

		assert_float(_hp_lost()).is_equal_approx(2.0 * attackers, 1e-6)


func test_an_enemy_behind_an_attacker_cannot_push_it() -> void:
	var enemies := _walled_corridor()
	var attacker := enemies.spawn(Vector2(3.7, 1.5), _settings.enemy_hp)
	var behind := enemies.spawn(Vector2(3.5, 1.9), _settings.enemy_hp)

	_tick(enemies)

	assert_vector(_position(enemies, attacker)).is_equal(Vector2(3.7, 1.5))
	assert_float(_position(enemies, behind).y).is_greater(1.9)


func test_attackers_still_push_each_other() -> void:
	var enemies := _walled_corridor()
	var upper := enemies.spawn(Vector2(3.7, 1.3), _settings.enemy_hp)
	var lower := enemies.spawn(Vector2(3.7, 1.6), _settings.enemy_hp)

	_tick(enemies)

	assert_float(_position(enemies, upper).y).is_less(1.3)
	assert_float(_position(enemies, lower).y).is_greater(1.6)
	assert_float(_hp_lost()).is_greater(0.0)


func test_an_attacker_keeps_hitting_its_wall_after_its_route_changes() -> void:
	var enemies := _walled_corridor()
	enemies.spawn(Vector2(3.7, 1.5), _settings.enemy_hp)
	_tick(enemies)
	_piles.damage_wall(WALL_LINE[0], _settings.wall_hp)
	_tick(enemies)
	assert_vector(_routing.parent(Routing.Route.SENSIBLE, Vector2i(3, 1))).is_equal(Vector2i(3, 0))
	var before := _piles.wall_hp(WALL_LINE[1])

	for tick in 30:
		_tick(enemies)

	assert_float(before - _piles.wall_hp(WALL_LINE[1])).is_equal_approx(1.0, 1e-6)


func test_an_attacker_pushed_out_of_reach_stops_hitting() -> void:
	var enemies := _walled_corridor()
	var id := enemies.spawn(Vector2(3.7, 1.5), _settings.enemy_hp)
	_tick(enemies)
	_piles.damage_wall(WALL_LINE[0], _settings.wall_hp)
	_tick(enemies)
	var before := _piles.wall_hp(WALL_LINE[1])

	enemies.positions[enemies.index_of(id)] = Vector2(2.5, 1.5)
	_tick(enemies)

	assert_float(_piles.wall_hp(WALL_LINE[1])).is_equal(before)


func test_attackers_walk_on_when_their_wall_falls() -> void:
	var enemies := _walled_corridor()
	var id := enemies.spawn(Vector2(3.7, 1.5), _settings.enemy_hp)
	_piles.damage_wall(WALL_LINE[1], _settings.wall_hp - 0.01)
	_tick(enemies)
	assert_int(_piles.level(WALL_LINE[1])).is_equal(Piles.FALLEN_WALL_LEVEL)

	_tick(enemies)

	assert_float(_position(enemies, id).x).is_greater(3.7)


func test_a_stuck_enemy_pressed_against_a_wall_attacks_it_after_jam_seconds() -> void:
	_settings.change("enemies", "separation_radius", 0.6)
	var damage_by_jam := {}
	for jam_seconds: float in [0.5, 10.0]:
		_settings.change("enemies", "jam_seconds", jam_seconds)
		var enemies := _enemies(["........", "........", "....#..."], Rect2i(7, 0, 1, 3))
		var wall := Vector2i(4, 0)
		_build_walls([wall])
		enemies.spawn(Vector2(3.6, 1.5), _settings.enemy_hp)

		for tick in 2 * Simulation.TICKS_PER_SECOND:
			_tick(enemies)

		damage_by_jam[jam_seconds] = _settings.wall_hp - _piles.wall_hp(wall)

	assert_float(damage_by_jam[0.5]).is_greater(1.0)
	assert_float(damage_by_jam[10.0]).is_equal(0.0)


func _walled_corridor() -> Enemies:
	var enemies := _enemies(["........", "........", "........"], Rect2i(7, 0, 1, 3))
	_build_walls(WALL_LINE)
	return enemies


func _hp_lost() -> float:
	var lost := 0.0
	for cell in WALL_LINE:
		lost += _settings.wall_hp - _piles.wall_hp(cell)
	return lost


func _enemies(rows: Array[String], base: Rect2i) -> Enemies:
	var map := TestMaps.from_rows(rows, base)
	var occupancy := Occupancy.new(map.width, map.height)
	_piles = Piles.new(_settings, map, occupancy)
	_routing = Routing.new(_settings, map, occupancy, _piles)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	return Enemies.new(
		_settings,
		map,
		occupancy,
		_piles,
		_routing,
		Structures.new(map, _piles, RunState.new(_settings)),
		rng
	)


func _build_walls(cells: Array[Vector2i]) -> void:
	var bodies := PackedVector2Array()
	for cell in cells:
		for n in Piles.WALL_LEVEL:
			bodies.append(Vector2(cell) + Vector2(0.5, 0.5))
	_piles.queue_bodies(bodies)
	_piles.land()
	_routing.update(_piles.take_field_changes())


func _tick(enemies: Enemies) -> void:
	_routing.update(_piles.take_field_changes())
	enemies.rebuild_spatial_hash()
	enemies.move()


func _position(enemies: Enemies, id: int) -> Vector2:
	return enemies.positions[enemies.index_of(id)]
