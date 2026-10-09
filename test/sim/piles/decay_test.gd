extends GdUnitTestSuite


func test_decay_lowers_every_pile_by_one_and_removes_level_1() -> void:
	var piles := _piles()
	_set_level(piles, Vector2i(0, 0), 1)
	_set_level(piles, Vector2i(2, 1), 2)
	_set_level(piles, Vector2i(3, 3), 4)

	piles.decay()

	assert_int(piles.level(Vector2i(0, 0))).is_equal(0)
	assert_int(piles.level(Vector2i(2, 1))).is_equal(1)
	assert_int(piles.level(Vector2i(3, 3))).is_equal(3)
	assert_array(piles.changed).contains_exactly_in_any_order(
		[Vector2i(0, 0), Vector2i(2, 1), Vector2i(3, 3)]
	)


func test_decay_with_no_piles_changes_nothing() -> void:
	var piles := _piles()

	piles.decay()

	assert_array(piles.changed).is_empty()


func test_taking_the_changes_empties_the_list() -> void:
	var piles := _piles()
	_set_level(piles, Vector2i(1, 1), 2)
	piles.decay()

	var taken := piles.take_changes()
	piles.decay()

	assert_array(taken).contains_exactly([Vector2i(1, 1)])
	assert_array(piles.changed).contains_exactly([Vector2i(1, 1)])


func _set_level(piles: Piles, cell: Vector2i, level: int) -> void:
	piles.levels[cell.y * 4 + cell.x] = level


func _piles() -> Piles:
	var map := TestMaps.open_field()
	return Piles.new(map, Occupancy.new(map.width, map.height))
