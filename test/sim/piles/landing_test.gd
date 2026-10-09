extends GdUnitTestSuite


func test_a_body_with_no_pile_nearby_starts_a_level_1_pile_on_its_cell() -> void:
	var piles := _piles(_open_rows())
	_set_level(piles, Vector2i(4, 4), 3)

	_land(piles, [Vector2(2.5, 2.5)])

	assert_int(piles.level(Vector2i(2, 2))).is_equal(1)
	assert_int(piles.level(Vector2i(4, 4))).is_equal(3)


func test_a_body_joins_the_tallest_pile_within_1_cell() -> void:
	var piles := _piles(_open_rows())
	_set_level(piles, Vector2i(2, 2), 1)
	_set_level(piles, Vector2i(3, 3), 2)

	_land(piles, [Vector2(2.5, 2.5)])

	assert_int(piles.level(Vector2i(2, 2))).is_equal(1)
	assert_int(piles.level(Vector2i(3, 3))).is_equal(3)


func test_a_tie_for_tallest_goes_to_the_death_cell() -> void:
	var piles := _piles(_open_rows())
	_set_level(piles, Vector2i(1, 1), 1)
	_set_level(piles, Vector2i(2, 2), 1)

	_land(piles, [Vector2(2.5, 2.5)])

	assert_int(piles.level(Vector2i(2, 2))).is_equal(2)
	assert_int(piles.level(Vector2i(1, 1))).is_equal(1)


func test_a_tie_away_from_the_death_cell_goes_to_the_lowest_y_then_x() -> void:
	var by_y := _piles(_open_rows())
	_set_level(by_y, Vector2i(1, 3), 1)
	_set_level(by_y, Vector2i(3, 1), 1)
	var by_x := _piles(_open_rows())
	_set_level(by_x, Vector2i(3, 2), 1)
	_set_level(by_x, Vector2i(1, 2), 1)

	_land(by_y, [Vector2(2.5, 2.5)])
	_land(by_x, [Vector2(2.5, 2.5)])

	assert_int(by_y.level(Vector2i(3, 1))).is_equal(2)
	assert_int(by_y.level(Vector2i(1, 3))).is_equal(1)
	assert_int(by_x.level(Vector2i(1, 2))).is_equal(2)
	assert_int(by_x.level(Vector2i(3, 2))).is_equal(1)


func test_bodies_land_in_death_list_order() -> void:
	var piles := _piles(_open_rows())

	_land(piles, [Vector2(2.5, 2.5), Vector2(3.5, 2.5)])

	assert_int(piles.level(Vector2i(2, 2))).is_equal(2)
	assert_int(piles.level(Vector2i(3, 2))).is_equal(0)


func test_a_body_on_rock_moves_to_the_nearest_valid_cell_by_octile_distance() -> void:
	var rows := _open_rows()
	rows[1] = "..#....."
	rows[2] = ".###...."
	var piles := _piles(rows)

	_land(piles, [Vector2(2.5, 2.5)])

	assert_int(piles.level(Vector2i(2, 3))).is_equal(1)
	assert_int(piles.level(Vector2i(2, 2))).is_equal(0)


func test_a_body_moving_off_rock_breaks_ties_by_the_lowest_y_then_x() -> void:
	var rows := _open_rows()
	rows[2] = "..#....."
	var piles := _piles(rows)

	_land(piles, [Vector2(2.5, 2.5)])

	assert_int(piles.level(Vector2i(2, 1))).is_equal(1)


func test_a_body_on_a_tower_cell_moves_to_the_nearest_valid_cell() -> void:
	var piles := _piles(_open_rows(), Towers.footprint(Vector2i(2, 2)))

	_land(piles, [Vector2(2.5, 2.5)])

	assert_int(piles.level(Vector2i(2, 1))).is_equal(1)


func test_a_body_on_a_base_cell_moves_to_the_nearest_valid_cell() -> void:
	var piles := _piles(_open_rows())

	_land(piles, [Vector2(6.5, 6.5)])

	assert_int(piles.level(Vector2i(6, 5))).is_equal(1)
	assert_int(piles.level(Vector2i(6, 6))).is_equal(0)


func test_a_pile_stops_at_level_4_until_walls_exist() -> void:
	var piles := _piles(_open_rows())

	_land(piles, [Vector2(2.5, 2.5), Vector2(2.5, 2.5), Vector2(2.5, 2.5), Vector2(2.5, 2.5)])
	_land(piles, [Vector2(2.5, 2.5)])

	assert_int(piles.level(Vector2i(2, 2))).is_equal(4)


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


func _set_level(piles: Piles, cell: Vector2i, level: int) -> void:
	piles.levels[cell.y * 8 + cell.x] = level


func _open_rows() -> Array[String]:
	var rows: Array[String] = []
	for y in 8:
		rows.append("........")
	return rows


func _piles(rows: Array[String], towers: Array[Vector2i] = []) -> Piles:
	var map := TestMaps.from_rows(rows, Rect2i(6, 6, 2, 2))
	var occupancy := Occupancy.new(map.width, map.height)
	occupancy.occupy(towers)
	return Piles.new(map, occupancy)
