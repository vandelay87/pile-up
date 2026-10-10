extends GdUnitTestSuite

var _settings: Settings
var _piles: Piles


func before_test() -> void:
	_settings = TestSettings.without_swarm_spread()


func _enemies(rows: Array[String], base: Rect2i, towers: Array[Vector2i] = []) -> Enemies:
	var map := TestMaps.from_rows(rows, base)
	var occupancy := Occupancy.new(map.width, map.height)
	occupancy.occupy(towers, 0)
	_piles = Piles.new(_settings, map, occupancy)
	var routing := Routing.new(_settings, map, occupancy, _piles)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	return Enemies.new(
		_settings,
		map,
		occupancy,
		_piles,
		routing,
		Structures.new(map, _piles, RunState.new(_settings)),
		rng
	)


func _open_field() -> Enemies:
	return _enemies(["........", "........", "........", "........"], Rect2i(7, 0, 1, 1))


func test_ids_stay_valid_across_swap_removes() -> void:
	var enemies := _open_field()
	var first := enemies.spawn(Vector2(0.5, 0.5), _settings.enemy_hp)
	var second := enemies.spawn(Vector2(1.5, 1.5), _settings.enemy_hp)
	var third := enemies.spawn(Vector2(2.5, 2.5), _settings.enemy_hp)

	enemies.damage(first, 100.0)
	enemies.remove_dead()

	assert_int(enemies.count).is_equal(2)
	assert_int(enemies.index_of(first)).is_equal(Enemies.NONE)
	assert_vector(enemies.positions[enemies.index_of(second)]).is_equal(Vector2(1.5, 1.5))
	assert_vector(enemies.positions[enemies.index_of(third)]).is_equal(Vector2(2.5, 2.5))

	enemies.damage(third, 100.0)
	enemies.remove_dead()

	assert_int(enemies.index_of(third)).is_equal(Enemies.NONE)
	assert_vector(enemies.positions[enemies.index_of(second)]).is_equal(Vector2(1.5, 1.5))


func test_removal_returns_the_positions_of_the_dead() -> void:
	var enemies := _open_field()
	var dead := enemies.spawn(Vector2(0.5, 0.5), _settings.enemy_hp)
	enemies.spawn(Vector2(1.5, 1.5), _settings.enemy_hp)

	enemies.damage(dead, 10.0)
	var deaths := enemies.remove_dead()

	assert_array(Array(deaths)).contains_exactly([Vector2(0.5, 0.5)])


func test_an_enemy_on_an_open_grid_reaches_the_base_and_stays_outside_it() -> void:
	var enemies := _open_field()
	var id := enemies.spawn(Vector2(0.5, 3.5), _settings.enemy_hp)

	for tick in 600:
		_tick(enemies)

	var pos := _position(enemies, id)
	assert_bool(Rect2(7, 0, 1, 1).has_point(pos)).is_false()
	var distance := pos.distance_to(pos.clamp(Vector2(7, 0), Vector2(8, 1)))
	assert_float(distance).is_less_equal(_settings.separation_radius + _settings.wall_reach)


func test_two_overlapping_enemies_separate() -> void:
	_settings.change("enemies", "heading_offset", 0.0)
	var enemies := _flowing_north()
	var left := enemies.spawn(Vector2(3.95, 3.5), _settings.enemy_hp)
	var right := enemies.spawn(Vector2(4.05, 3.5), _settings.enemy_hp)

	_tick(enemies)

	var gap := _position(enemies, right).x - _position(enemies, left).x
	assert_float(gap).is_greater_equal(2.0 * _settings.separation_radius - 1e-4)


func test_a_neighbour_cap_limits_the_neighbours_checked() -> void:
	_settings.change("enemies", "heading_offset", 0.0)
	for cap: int in [0, 1]:
		_settings.change("enemies", "neighbour_cap", cap)
		var enemies := _flowing_north()
		var middle := enemies.spawn(Vector2(4.0, 3.5), _settings.enemy_hp)
		enemies.spawn(Vector2(3.8, 3.5), _settings.enemy_hp)
		enemies.spawn(Vector2(4.2, 3.5), _settings.enemy_hp)

		_tick(enemies)

		var drift := absf(_position(enemies, middle).x - 4.0)
		if cap == 0:
			assert_float(drift).is_less(1e-4)
		else:
			assert_float(drift).is_greater(0.05)


func test_an_enemy_inside_rock_is_pushed_out_through_the_nearest_side() -> void:
	var enemies := _enemies(["........", "...#....", "........", "........"], Rect2i(7, 3, 1, 1))
	var id := enemies.spawn(Vector2(3.2, 1.5), _settings.enemy_hp)

	_tick(enemies)

	var pos := _position(enemies, id)
	assert_float(pos.x).is_less_equal(3.0 - _settings.separation_radius + 0.05)
	assert_float(pos.y).is_between(1.0, 2.0)


func test_an_enemy_inside_a_tower_cell_is_pushed_out_through_the_nearest_side() -> void:
	var towers: Array[Vector2i] = [Vector2i(4, 1)]
	var enemies := _enemies(
		["........", "........", "........", "........"], Rect2i(7, 3, 1, 1), towers
	)
	var id := enemies.spawn(Vector2(4.5, 1.85), _settings.enemy_hp)

	_tick(enemies)

	assert_float(_position(enemies, id).y).is_greater_equal(
		2.0 + _settings.separation_radius - 0.05
	)


func test_a_blocked_nearest_side_is_skipped_for_the_next_nearest_open_side() -> void:
	var enemies := _enemies(["........", "..##....", "........", "........"], Rect2i(7, 3, 1, 1))
	var id := enemies.spawn(Vector2(3.1, 1.3), _settings.enemy_hp)

	_tick(enemies)

	var pos := _position(enemies, id)
	assert_float(pos.y).is_less_equal(1.0 - _settings.separation_radius + 0.05)
	assert_float(pos.x).is_between(3.0, 4.0)


func test_nearest_to_base_in_range_picks_the_lowest_field_value_in_range() -> void:
	var enemies := _open_field()
	enemies.spawn(Vector2(1.5, 1.5), _settings.enemy_hp)
	var nearer := enemies.spawn(Vector2(5.5, 1.5), _settings.enemy_hp)
	enemies.spawn(Vector2(6.5, 3.5), _settings.enemy_hp)
	enemies.rebuild_spatial_hash()

	assert_int(enemies.nearest_to_base_in_range(Vector2(3.5, 1.5), 3.0)).is_equal(nearer)


func test_nearest_to_base_in_range_breaks_ties_by_lowest_id() -> void:
	var enemies := _flowing_north()
	var removed := enemies.spawn(Vector2(0.5, 3.5), _settings.enemy_hp)
	var lower := enemies.spawn(Vector2(2.5, 2.5), _settings.enemy_hp)
	enemies.spawn(Vector2(5.5, 2.5), _settings.enemy_hp)
	enemies.damage(removed, 100.0)
	enemies.remove_dead()
	enemies.rebuild_spatial_hash()

	assert_int(enemies.nearest_to_base_in_range(Vector2(4.0, 2.5), 3.0)).is_equal(lower)


func test_nearest_to_base_in_range_skips_enemies_at_zero_hp() -> void:
	var enemies := _open_field()
	var farther := enemies.spawn(Vector2(1.5, 1.5), _settings.enemy_hp)
	var nearer := enemies.spawn(Vector2(5.5, 1.5), _settings.enemy_hp)
	enemies.damage(nearer, _settings.enemy_hp)
	enemies.rebuild_spatial_hash()

	assert_int(enemies.nearest_to_base_in_range(Vector2(3.5, 1.5), 3.0)).is_equal(farther)


func test_nearest_to_base_in_range_finds_an_enemy_whose_field_value_is_unreachable() -> void:
	var rows: Array[String] = ["........", ".###....", ".###....", ".###...."]
	var enemies := _enemies(rows, Rect2i(7, 0, 1, 1))
	var inside_rock := enemies.spawn(Vector2(2.5, 2.5), _settings.enemy_hp)
	enemies.rebuild_spatial_hash()

	assert_int(enemies.nearest_to_base_in_range(Vector2(4.5, 2.5), 3.0)).is_equal(inside_rock)


func test_nearest_to_base_in_range_is_none_when_nothing_is_in_range() -> void:
	var enemies := _open_field()
	enemies.spawn(Vector2(0.5, 3.5), _settings.enemy_hp)
	enemies.rebuild_spatial_hash()

	assert_int(enemies.nearest_to_base_in_range(Vector2(6.5, 0.5), 2.0)).is_equal(Enemies.NONE)


func _flowing_north() -> Enemies:
	return _enemies(["........", "........", "........", "........"], Rect2i(0, 0, 8, 1))


func _position(enemies: Enemies, id: int) -> Vector2:
	return enemies.positions[enemies.index_of(id)]


func _tick(enemies: Enemies) -> void:
	enemies.rebuild_spatial_hash()
	enemies.move()
	enemies.remove_dead()


func test_an_enemy_on_a_level_2_pile_moves_at_70_percent_speed() -> void:
	_settings.change("enemies", "heading_offset", 0.0)
	var enemies := _open_field()
	_piles.levels[1 * 8 + 2] = 2
	var on_clear := enemies.spawn(Vector2(2.5, 2.5), _settings.enemy_hp)
	var on_pile := enemies.spawn(Vector2(2.5, 1.5), _settings.enemy_hp)
	var clear_start := enemies.positions[0]
	var pile_start := enemies.positions[1]

	enemies.rebuild_spatial_hash()
	enemies.move()

	var step := _settings.enemy_speed_per_tick
	var clear_moved := enemies.positions[enemies.index_of(on_clear)].distance_to(clear_start)
	var pile_moved := enemies.positions[enemies.index_of(on_pile)].distance_to(pile_start)
	assert_float(clear_moved).is_equal_approx(step, 1e-5)
	assert_float(pile_moved).is_equal_approx(step * 0.7, 1e-5)
