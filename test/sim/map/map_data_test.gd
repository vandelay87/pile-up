extends GdUnitTestSuite


func _valid() -> Dictionary:
	return {
		"version": 1,
		"width": 5,
		"height": 4,
		"rows": [".....", "..#..", ".....", "#...."],
		"base": {"origin": [2, 2], "size": [2, 1]},
		"spawn_edges": ["N", "W"],
	}


func _load(data: Dictionary) -> MapData.LoadResult:
	return MapData.from_json(JSON.stringify(data))


func _map() -> MapData:
	var result := _load(_valid())
	assert_str(result.error).is_empty()
	return result.map


func _assert_rejected(result: MapData.LoadResult, fragment: String) -> void:
	assert_object(result.map).is_null()
	assert_str(result.error).contains(fragment)


func _clear_rows(width: int, height: int) -> Array[String]:
	var rows: Array[String] = []
	for y in height:
		rows.append(".".repeat(width))
	return rows


func test_loads_size_and_rock() -> void:
	var map := _map()

	assert_int(map.width).is_equal(5)
	assert_int(map.height).is_equal(4)
	assert_bool(map.is_rock(Vector2i(2, 1))).is_true()
	assert_bool(map.is_rock(Vector2i(0, 3))).is_true()
	assert_bool(map.is_rock(Vector2i(1, 1))).is_false()


func test_derives_the_base_cells_from_origin_and_size() -> void:
	var map := _map()

	assert_array(map.base_cells()).contains_exactly_in_any_order([Vector2i(2, 2), Vector2i(3, 2)])
	assert_bool(map.is_base(Vector2i(3, 2))).is_true()
	assert_bool(map.is_base(Vector2i(4, 2))).is_false()
	assert_bool(map.is_base(Vector2i(2, 3))).is_false()


func test_derives_the_passable_cells_of_each_spawn_edge() -> void:
	var map := _map()

	assert_array(map.spawn_edges).contains_exactly(["N", "W"])
	assert_array(map.spawn_cells("N")).contains_exactly(
		[Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0)]
	)
	assert_array(map.spawn_cells("W")).contains_exactly(
		[Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2)]
	)
	assert_array(map.spawn_cells("S")).is_empty()


func test_spawn_cells_leave_out_rock_pockets_cut_off_from_the_base() -> void:
	var data := _valid()
	data["rows"] = [".#...", "##...", ".....", "....."]

	var map := _load(data).map

	assert_array(map.spawn_cells("W")).contains_exactly([Vector2i(0, 2), Vector2i(0, 3)])
	assert_array(map.spawn_cells("N")).contains_exactly(
		[Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0)]
	)


func test_rejects_an_unknown_version() -> void:
	var data := _valid()
	data["version"] = 2

	_assert_rejected(_load(data), "version: unknown version 2")


func test_rejects_a_side_over_150_cells() -> void:
	var data := _valid()
	data["width"] = 151
	data["rows"] = _clear_rows(151, 4)

	_assert_rejected(_load(data), "width: 151 is outside 1 to 150")


func test_rejects_rows_whose_lengths_do_not_match() -> void:
	var data := _valid()
	data["rows"] = [".....", "..#.", ".....", "#...."]

	_assert_rejected(_load(data), "rows[1]: 4 cells, expected 5")


func test_rejects_a_row_count_that_does_not_match_the_height() -> void:
	var data := _valid()
	data["rows"] = [".....", "..#..", "....."]

	_assert_rejected(_load(data), "rows: 3 rows, expected 4")


func test_rejects_an_unknown_character() -> void:
	var data := _valid()
	data["rows"] = [".....", "..#..", "...x.", "#...."]

	_assert_rejected(_load(data), "rows[2]: unknown character 'x' at x 3")


func test_rejects_a_base_out_of_bounds() -> void:
	var data := _valid()
	data["base"] = {"origin": [4, 2], "size": [2, 1]}

	_assert_rejected(_load(data), "base: (4, 2) size (2, 1) is outside the 5×4 map")


func test_rejects_a_base_on_rock() -> void:
	var data := _valid()
	data["base"] = {"origin": [2, 1], "size": [2, 1]}

	_assert_rejected(_load(data), "base: covers rock at (2, 1)")


func test_rejects_a_spawn_edge_with_no_passable_cell_reaching_the_base() -> void:
	var data := _valid()
	data["rows"] = [".....", "#####", ".....", "#...."]

	_assert_rejected(_load(data), "spawn_edges: N has no passable cell that reaches the base")


func test_rejects_an_unknown_spawn_edge() -> void:
	var data := _valid()
	data["spawn_edges"] = ["N", "Q"]

	_assert_rejected(_load(data), "spawn_edges: unknown edge 'Q'")


func test_rejects_a_repeated_spawn_edge() -> void:
	var data := _valid()
	data["spawn_edges"] = ["N", "N"]

	_assert_rejected(_load(data), "spawn_edges: N is listed twice")


func test_the_committed_v1_map_loads() -> void:
	var result := MapData.load_file("res://data/maps/v1.json")

	assert_str(result.error).is_empty()
	var map := result.map
	assert_int(map.width).is_equal(120)
	assert_int(map.height).is_equal(120)
	assert_that(map.base).is_equal(Rect2i(58, 58, 4, 4))
	assert_array(map.spawn_edges).contains_exactly_in_any_order(["N", "E", "S", "W"])


func test_the_default_map_path_loads_the_narrow_map() -> void:
	var settings := Settings.load_file(Settings.DEFAULTS_PATH).settings
	var result := MapData.load_file(settings.map_path)

	assert_str(result.error).is_empty()
	var map := result.map
	assert_int(map.width).is_equal(96)
	assert_int(map.height).is_equal(64)
	assert_that(map.base).is_equal(Rect2i(46, 46, 4, 4))
	assert_array(map.spawn_edges).contains_exactly_in_any_order(["N", "E", "W"])


func test_reports_a_missing_file() -> void:
	_assert_rejected(MapData.load_file("res://data/maps/missing.json"), "file not found")
