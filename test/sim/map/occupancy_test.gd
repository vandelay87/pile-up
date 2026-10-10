extends GdUnitTestSuite


func test_cells_start_unoccupied() -> void:
	var occupancy := Occupancy.new(4, 3)

	assert_bool(occupancy.is_occupied(Vector2i(0, 0))).is_false()
	assert_bool(occupancy.is_occupied(Vector2i(3, 2))).is_false()


func test_occupied_cells_stay_occupied_by_their_building() -> void:
	var occupancy := Occupancy.new(4, 3)

	occupancy.occupy([Vector2i(1, 1), Vector2i(2, 1)], 3)
	occupancy.occupy([Vector2i(0, 0)], 0)

	assert_bool(occupancy.is_occupied(Vector2i(1, 1))).is_true()
	assert_bool(occupancy.is_occupied(Vector2i(2, 1))).is_true()
	assert_bool(occupancy.is_occupied(Vector2i(0, 0))).is_true()
	assert_bool(occupancy.is_occupied(Vector2i(1, 2))).is_false()
	assert_int(occupancy.building_at(Vector2i(1, 1))).is_equal(3)
	assert_int(occupancy.building_at(Vector2i(2, 1))).is_equal(3)
	assert_int(occupancy.building_at(Vector2i(0, 0))).is_equal(0)
	assert_int(occupancy.building_at(Vector2i(1, 2))).is_equal(Occupancy.EMPTY)
