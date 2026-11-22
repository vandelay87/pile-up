extends GdUnitTestSuite

## Map format version 2: the base's deposit and the rig deposits.


func _load(data: Dictionary) -> MapData.LoadResult:
	return MapData.from_json(JSON.stringify(data))


func _assert_rejected(result: MapData.LoadResult, fragment: String) -> void:
	assert_object(result.map).is_null()
	assert_str(result.error).contains(fragment)


# A 12×8 version 2 map: rock at (5, 1), a no-build margin along the top row, the base at
# (5, 4) 2×2 and one deposit at (1, 2).
func _valid_v2() -> Dictionary:
	return {
		"version": 2,
		"width": 12,
		"height": 8,
		"rows":
		[
			"::::::::::::",
			".....#......",
			"............",
			"............",
			"............",
			"............",
			"............",
			"............",
		],
		"base": {"origin": [5, 4], "size": [2, 2]},
		"spawn_edges": ["N"],
		"base_deposit": {"gold": 500, "aether": 50},
		"deposits": [{"name": "near", "origin": [1, 2], "gold": 720, "aether": 30}],
	}


func _with_deposit(origin: Array, name := "extra") -> Dictionary:
	var data := _valid_v2()
	var deposits: Array = data["deposits"]
	deposits.append({"name": name, "origin": origin, "gold": 100, "aether": 10})
	return data


func test_version_2_parses_the_base_deposit_and_the_deposits() -> void:
	var result := _load(_valid_v2())

	assert_str(result.error).is_empty()
	var map := result.map
	assert_int(map.base_deposit.gold).is_equal(500)
	assert_int(map.base_deposit.aether).is_equal(50)
	assert_that(map.base_deposit.area).is_equal(map.base)
	assert_int(map.deposits.size()).is_equal(1)
	var near := map.deposits[0]
	assert_str(near.name).is_equal("near")
	assert_that(near.area).is_equal(Rect2i(1, 2, 3, 3))
	assert_int(near.gold).is_equal(720)
	assert_int(near.aether).is_equal(30)


func test_deposit_at_names_a_deposits_cells_and_nothing_else() -> void:
	var map := _load(_with_deposit([8, 4], "far")).map

	for y in map.height:
		for x in map.width:
			var cell := Vector2i(x, y)
			var found := map.deposit_at(cell)
			if Rect2i(1, 2, 3, 3).has_point(cell):
				assert_str(found.name).is_equal("near")
			elif Rect2i(8, 4, 3, 3).has_point(cell):
				assert_str(found.name).is_equal("far")
			else:
				assert_object(found).is_null()


func test_version_1_maps_load_with_the_default_base_deposit_and_no_rig_deposits() -> void:
	var data := _valid_v2()
	data["version"] = 1
	data.erase("base_deposit")
	data.erase("deposits")
	var map := _load(data).map

	assert_int(map.base_deposit.gold).is_equal(MapData.DEFAULT_BASE_GOLD)
	assert_int(map.base_deposit.aether).is_equal(MapData.DEFAULT_BASE_AETHER)
	assert_int(MapData.DEFAULT_BASE_GOLD).is_equal(4200)
	assert_int(MapData.DEFAULT_BASE_AETHER).is_equal(1400)
	assert_array(map.deposits).is_empty()
	assert_object(map.deposit_at(Vector2i(0, 0))).is_null()


func test_rejects_a_deposit_overlapping_the_base() -> void:
	_assert_rejected(_load(_with_deposit([4, 4])), "deposits[1] (extra): overlaps the base")


func test_rejects_a_deposit_overlapping_another_deposit() -> void:
	_assert_rejected(_load(_with_deposit([0, 4])), "deposits[1] (extra): overlaps deposit 'near'")


func test_rejects_a_deposit_on_rock() -> void:
	_assert_rejected(_load(_with_deposit([5, 1])), "deposits[1] (extra): covers rock at (5, 1)")


func test_rejects_a_deposit_in_the_no_build_margin() -> void:
	_assert_rejected(
		_load(_with_deposit([7, 0])), "deposits[1] (extra): in the no-build margin at (7, 0)"
	)


func test_rejects_a_deposit_over_the_maps_edge() -> void:
	_assert_rejected(
		_load(_with_deposit([10, 5])),
		"deposits[1] (extra): (10, 5) size (3, 3) is outside the 12×8 map"
	)


func test_rejects_a_repeated_deposit_name() -> void:
	_assert_rejected(_load(_with_deposit([8, 4], "near")), "deposits[1]: near is named twice")


func test_rejects_a_malformed_deposit() -> void:
	var data := _valid_v2()
	data["deposits"] = [{"name": "", "origin": [8, 4], "gold": -1, "aether": "lots"}]

	var result := _load(data)

	_assert_rejected(result, "deposits[0].name: expected a name")
	assert_str(result.error).contains("deposits[0].gold: expected a whole number of 0 or more")
	assert_str(result.error).contains("deposits[0].aether: expected a whole number")


func test_rejects_a_version_2_map_without_its_deposits() -> void:
	var data := _valid_v2()
	data.erase("base_deposit")
	data.erase("deposits")

	var result := _load(data)

	_assert_rejected(result, "base_deposit: expected an object with gold and aether")
	assert_str(result.error).contains("deposits: expected an array of deposits")


func test_test_maps_from_rows_gains_deposits() -> void:
	var map := TestMaps.from_rows(
		[".......", ".......", ".......", "......."],
		Rect2i(0, 0, 2, 2),
		[],
		[{"name": "near", "origin": Vector2i(3, 1), "gold": 10, "aether": 2}]
	)

	assert_str(map.deposit_at(Vector2i(5, 3)).name).is_equal("near")
	assert_int(map.base_deposit.gold).is_equal(MapData.DEFAULT_BASE_GOLD)
