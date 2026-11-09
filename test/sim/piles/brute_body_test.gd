extends GdUnitTestSuite

## A brute's body: 2 levels on the cell it lands on, stopping at a wall, and none from a blast.


func test_a_brutes_body_adds_two_levels() -> void:
	var piles := _piles(_open_rows())
	_set_level(piles, Vector2i(3, 3), 1)

	_land_brutes(piles, [Vector2(2.5, 2.5), Vector2(3.5, 3.5)])

	assert_int(piles.level(Vector2i(2, 2))).is_equal(2)
	assert_int(piles.level(Vector2i(3, 3))).is_equal(3)


func test_a_brutes_body_on_a_level_3_or_4_pile_makes_a_wall_and_goes_no_higher() -> void:
	for level: int in [3, 4]:
		var piles := _piles(_open_rows())
		_set_level(piles, Vector2i(2, 2), level)

		_land_brutes(piles, [Vector2(2.5, 2.5)])

		assert_int(piles.level(Vector2i(2, 2))).is_equal(Piles.WALL_LEVEL)
		assert_float(piles.wall_hp(Vector2i(2, 2))).is_equal(_settings().wall_hp)
		# The second level is lost, not passed on.
		for cell: Vector2i in [Vector2i(1, 2), Vector2i(3, 2), Vector2i(2, 1), Vector2i(2, 3)]:
			assert_int(piles.level(cell)).is_equal(0)


func test_a_brutes_body_on_a_wall_lands_both_levels_on_the_nearest_valid_cell() -> void:
	var piles := _piles(_open_rows())
	_set_level(piles, Vector2i(2, 2), Piles.WALL_LEVEL)

	_land_brutes(piles, [Vector2(2.9, 2.5)])

	assert_int(piles.level(Vector2i(3, 2))).is_equal(2)


func test_a_brute_killed_by_a_blast_leaves_no_body() -> void:
	var piles := _piles(_open_rows())
	var deaths := Deaths.new()
	deaths.add(0, Vector2(2.5, 2.5), Enemies.Kind.BRUTE, Enemies.NONE, true)

	piles.queue_bodies(deaths)
	piles.land()

	assert_int(piles.level(Vector2i(2, 2))).is_equal(0)


func _land_brutes(piles: Piles, positions: Array[Vector2]) -> void:
	var deaths := Deaths.new()
	for pos in positions:
		deaths.add(0, pos, Enemies.Kind.BRUTE, Enemies.NONE)
	piles.queue_bodies(deaths)
	piles.land()
	piles.clear_changes()


func _set_level(piles: Piles, cell: Vector2i, level: int) -> void:
	piles.levels[cell.y * 8 + cell.x] = level


func _open_rows() -> Array[String]:
	var rows: Array[String] = []
	for y in 8:
		rows.append("........")
	return rows


func _piles(rows: Array[String]) -> Piles:
	var map := TestMaps.from_rows(rows, Rect2i(6, 6, 2, 2))
	return Piles.new(_settings(), map, Occupancy.new(map.width, map.height))


func _settings() -> Settings:
	return Settings.load_file(Settings.DEFAULTS_PATH).settings
