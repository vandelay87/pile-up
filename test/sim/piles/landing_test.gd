extends GdUnitTestSuite


func test_a_body_with_no_pile_nearby_starts_a_level_1_pile_on_its_cell() -> void:
	var piles := _piles(_open_rows())
	_set_level(piles, Vector2i(4, 4), 3)

	_land(piles, [Vector2(2.5, 2.5)])

	assert_int(piles.level(Vector2i(2, 2))).is_equal(1)
	assert_int(piles.level(Vector2i(4, 4))).is_equal(3)


func test_a_body_lands_on_its_death_cell_even_beside_a_taller_pile() -> void:
	var piles := _piles(_open_rows())
	_set_level(piles, Vector2i(3, 3), 4)
	_set_level(piles, Vector2i(1, 2), 2)

	_land(piles, [Vector2(2.9, 2.9)])

	assert_int(piles.level(Vector2i(2, 2))).is_equal(1)
	assert_int(piles.level(Vector2i(3, 3))).is_equal(4)
	assert_int(piles.level(Vector2i(1, 2))).is_equal(2)


func test_bodies_land_in_death_list_order() -> void:
	var east_first := _piles(_open_rows())
	var west_first := _piles(_open_rows())
	_set_level(east_first, Vector2i(2, 2), Piles.WALL_LEVEL - 1)
	_set_level(west_first, Vector2i(2, 2), Piles.WALL_LEVEL - 1)

	_land(east_first, [Vector2(2.9, 2.5), Vector2(2.1, 2.5)])
	_land(west_first, [Vector2(2.1, 2.5), Vector2(2.9, 2.5)])

	assert_int(east_first.level(Vector2i(1, 2))).is_equal(1)
	assert_int(east_first.level(Vector2i(3, 2))).is_equal(0)
	assert_int(west_first.level(Vector2i(3, 2))).is_equal(1)
	assert_int(west_first.level(Vector2i(1, 2))).is_equal(0)


func test_a_body_on_rock_moves_to_the_nearest_valid_cell() -> void:
	var rows := _open_rows()
	rows[1] = "..#....."
	rows[2] = ".###...."
	var piles := _piles(rows)

	_land(piles, [Vector2(2.5, 2.5)])

	assert_int(piles.level(Vector2i(2, 3))).is_equal(1)
	assert_int(piles.level(Vector2i(2, 2))).is_equal(0)


func test_a_spill_measures_from_the_exact_death_position_not_the_cell() -> void:
	var rows := _open_rows()
	rows[2] = "..#....."
	var piles := _piles(rows)

	_land(piles, [Vector2(2.6, 2.95)])

	assert_int(piles.level(Vector2i(2, 3))).is_equal(1)
	assert_int(piles.level(Vector2i(2, 1))).is_equal(0)


func test_a_spill_tie_goes_to_the_lowest_y_then_x() -> void:
	var by_y := _piles(_rows_with_rock_at([Vector2i(2, 2)]))
	var by_x := _piles(_rows_with_rock_at([Vector2i(2, 2), Vector2i(2, 1)]))

	_land(by_y, [Vector2(2.5, 2.5)])
	_land(by_x, [Vector2(2.5, 2.5)])

	assert_int(by_y.level(Vector2i(2, 1))).is_equal(1)
	assert_int(by_x.level(Vector2i(1, 2))).is_equal(1)


func test_a_spill_tie_across_rings_still_goes_to_the_lowest_y_then_x() -> void:
	var rows: Array[String] = ["###.#", "#####", ".####", "####."]
	var map := TestMaps.from_rows(rows, Rect2i(4, 3, 1, 1))
	var piles := Piles.new(_settings(), map, Occupancy.new(map.width, map.height))

	_land(piles, [Vector2(1.75, 1.125)])

	assert_int(piles.levels[0 * 5 + 3]).is_equal(1)
	assert_int(piles.levels[2 * 5 + 0]).is_equal(0)


func test_a_death_on_a_wall_spills_to_the_enemys_side() -> void:
	var from_west := _piles(_open_rows())
	var from_east := _piles(_open_rows())
	for piles: Piles in [from_west, from_east]:
		_land(piles, _bodies(Vector2(3.5, 2.5), Piles.WALL_LEVEL))

	_land(from_west, [Vector2(3.1, 2.5)])
	_land(from_east, [Vector2(3.9, 2.5)])

	assert_int(from_west.level(Vector2i(2, 2))).is_equal(1)
	assert_int(from_west.level(Vector2i(4, 2))).is_equal(0)
	assert_int(from_east.level(Vector2i(4, 2))).is_equal(1)
	assert_int(from_east.level(Vector2i(2, 2))).is_equal(0)


func test_a_death_at_a_tower_spills_in_front_of_it() -> void:
	var piles := _piles(_open_rows(), Towers.footprint(Vector2i(2, 2)))

	_land(piles, [Vector2(2.5, 3.9), Vector2(3.9, 2.5)])

	assert_int(piles.level(Vector2i(2, 4))).is_equal(1)
	assert_int(piles.level(Vector2i(4, 2))).is_equal(1)


func test_a_death_at_the_base_spills_in_front_of_it() -> void:
	var piles := _piles(_open_rows())

	_land(piles, [Vector2(6.5, 6.1), Vector2(6.1, 7.5)])

	assert_int(piles.level(Vector2i(6, 5))).is_equal(1)
	assert_int(piles.level(Vector2i(5, 7))).is_equal(1)
	assert_int(piles.level(Vector2i(6, 6))).is_equal(0)


func test_a_body_is_never_dropped_however_far_the_nearest_valid_cell_is() -> void:
	var rows: Array[String] = []
	for y in 40:
		rows.append("#".repeat(40))
	rows[0] = "." + "#".repeat(39)
	rows[39] = "#".repeat(39) + "."
	var map := TestMaps.from_rows(rows, Rect2i(0, 0, 1, 1))
	var piles := Piles.new(_settings(), map, Occupancy.new(map.width, map.height))

	_land(piles, [Vector2(1.5, 1.5)])

	assert_int(piles.levels[39 * 40 + 39]).is_equal(1)


func test_the_fifth_body_makes_a_15_hp_wall() -> void:
	var piles := _piles(_open_rows())

	_land(piles, [Vector2(2.5, 2.5), Vector2(2.5, 2.5), Vector2(2.5, 2.5), Vector2(2.5, 2.5)])
	assert_float(piles.wall_hp(Vector2i(2, 2))).is_equal(0.0)
	_land(piles, [Vector2(2.5, 2.5)])

	assert_int(piles.level(Vector2i(2, 2))).is_equal(Piles.WALL_LEVEL)
	assert_float(piles.wall_hp(Vector2i(2, 2))).is_equal(15.0)


func test_a_body_dying_beside_a_wall_starts_a_pile_on_its_own_cell() -> void:
	var piles := _piles(_open_rows())
	_land(piles, _bodies(Vector2(3.5, 2.5), Piles.WALL_LEVEL))

	_land(piles, [Vector2(2.5, 2.5)])

	assert_int(piles.level(Vector2i(2, 2))).is_equal(1)
	assert_int(piles.level(Vector2i(3, 2))).is_equal(Piles.WALL_LEVEL)


func test_a_body_dying_on_a_wall_spills_to_the_nearest_non_wall_cell() -> void:
	var piles := _piles(_open_rows())
	_land(piles, _bodies(Vector2(2.5, 2.5), Piles.WALL_LEVEL))
	_land(piles, _bodies(Vector2(2.5, 1.5), Piles.WALL_LEVEL))

	_land(piles, [Vector2(2.5, 2.5)])

	assert_int(piles.level(Vector2i(1, 2))).is_equal(1)
	assert_int(piles.level(Vector2i(2, 2))).is_equal(Piles.WALL_LEVEL)


func test_a_body_beyond_a_new_wall_in_the_same_tick_spills() -> void:
	var piles := _piles(_open_rows())
	_land(piles, _bodies(Vector2(2.5, 2.5), Piles.WALL_LEVEL - 1))

	_land(piles, _bodies(Vector2(2.5, 2.5), 2))

	assert_int(piles.level(Vector2i(2, 2))).is_equal(Piles.WALL_LEVEL)
	assert_int(piles.level(Vector2i(2, 1))).is_equal(1)


func test_landing_lists_each_changed_cell_once() -> void:
	var piles := _piles(_open_rows())
	piles.queue_bodies(
		PackedVector2Array([Vector2(2.5, 2.5), Vector2(2.5, 2.5), Vector2(5.5, 1.5)])
	)

	piles.land()

	assert_array(piles.changed).contains_exactly([Vector2i(2, 2), Vector2i(5, 1)])


func test_landing_with_nothing_queued_changes_nothing() -> void:
	var piles := _piles(_open_rows())
	_set_level(piles, Vector2i(2, 2), 1)

	piles.land()

	assert_array(piles.changed).is_empty()
	assert_int(piles.level(Vector2i(2, 2))).is_equal(1)


func _land(piles: Piles, positions: Array[Vector2]) -> void:
	piles.queue_bodies(PackedVector2Array(positions))
	piles.land()
	piles.clear_changes()


func _bodies(pos: Vector2, count: int) -> Array[Vector2]:
	var bodies: Array[Vector2] = []
	for n in count:
		bodies.append(pos)
	return bodies


func _set_level(piles: Piles, cell: Vector2i, level: int) -> void:
	piles.levels[cell.y * 8 + cell.x] = level


func _rows_with_rock_at(cells: Array[Vector2i]) -> Array[String]:
	var rows := _open_rows()
	for cell in cells:
		var row := rows[cell.y]
		rows[cell.y] = row.substr(0, cell.x) + "#" + row.substr(cell.x + 1)
	return rows


func _open_rows() -> Array[String]:
	var rows: Array[String] = []
	for y in 8:
		rows.append("........")
	return rows


func _piles(rows: Array[String], towers: Array[Vector2i] = []) -> Piles:
	var map := TestMaps.from_rows(rows, Rect2i(6, 6, 2, 2))
	var occupancy := Occupancy.new(map.width, map.height)
	occupancy.occupy(towers)
	return Piles.new(_settings(), map, occupancy)


func _settings() -> Settings:
	return Settings.load_file(Settings.DEFAULTS_PATH).settings
