extends GdUnitTestSuite

## The v6 map's shape: four spawn edges reaching the base, each deposit in a wide basin with one
## mouth, and pylon chains of the planned lengths.

const PATH := "res://data/maps/v6.json"
# Each deposit's basin mouth: a straight line of cells from rock to rock across its one opening
# onto its route. A basin is a wide half-circle bay, so the line is long.
const MOUTHS := {
	"near": Rect2i(37, 54, 17, 1),
	"far_north": Rect2i(90, 6, 1, 20),
	"far_east": Rect2i(106, 67, 17, 1),
}
const MOUTH_MIN_CELLS := 10
const BASIN_MAX_CELLS := 150
# The fewest pylons that put each deposit on the grid, as [least, most].
const PYLONS := {"near": [1, 2], "far_north": [4, 5], "far_east": [4, 5]}

var _map: MapData


func before() -> void:
	var result := MapData.load_file(PATH)
	assert_str(result.error).is_empty()
	_map = result.map


func test_the_v6_map_loads_with_four_spawn_edges_and_its_deposits() -> void:
	assert_int(_map.width).is_equal(136)
	assert_int(_map.height).is_equal(96)
	assert_that(_map.base).is_equal(Rect2i(66, 46, 4, 4))
	assert_array(_map.spawn_edges).contains_exactly_in_any_order(["N", "E", "S", "W"])
	assert_int(_map.base_deposit.gold).is_equal(4200)
	assert_int(_map.base_deposit.aether).is_equal(1400)
	var contents := {}
	for deposit in _map.deposits:
		contents[deposit.name] = [deposit.gold, deposit.aether]
	assert_dict(contents).is_equal(
		{"near": [720, 30], "far_north": [1440, 360], "far_east": [2000, 100]}
	)


func test_every_spawn_edge_reaches_the_base_through_its_no_build_margin() -> void:
	for edge in MapData.EDGES:
		var cells := _map.spawn_cells(edge)
		assert_array(cells).is_not_empty()
		for cell in cells:
			assert_bool(_map.is_no_build(cell)).is_true()
	assert_bool(_map.is_no_build(_map.base.position)).is_false()


func test_each_deposit_sits_in_a_wide_basin_with_one_mouth() -> void:
	for deposit in _map.deposits:
		var mouth: Rect2i = MOUTHS[deposit.name]
		var walled := _map.is_rock(mouth.position) and _map.is_rock(mouth.end - Vector2i.ONE)
		(
			assert_bool(walled)
			. override_failure_message("%s's mouth doesn't run from rock to rock" % deposit.name)
			. is_true()
		)
		var blocked := {}
		for y in range(mouth.position.y, mouth.end.y):
			for x in range(mouth.position.x, mouth.end.x):
				if not _map.is_rock(Vector2i(x, y)):
					blocked[Vector2i(x, y)] = true
		assert_int(blocked.size()).is_greater_equal(MOUTH_MIN_CELLS)
		var basin := _flood(deposit.area.position, blocked)
		(
			assert_bool(_reaches_base(basin))
			. override_failure_message("%s's basin has another opening" % deposit.name)
			. is_false()
		)
		assert_int(basin.size()).is_less(BASIN_MAX_CELLS)
		assert_bool(_reaches_base(_flood(deposit.area.position, {}))).is_true()


func test_the_fewest_pylons_to_power_each_deposit() -> void:
	var settings := Settings.load_file(Settings.DEFAULTS_PATH).settings
	var chains := _pylon_chains(settings)
	for deposit in _map.deposits:
		var fewest := _fewest_pylons(chains, deposit.area, settings)
		var bounds: Array = PYLONS[deposit.name]
		var least: int = bounds[0]
		var most: int = bounds[1]
		(
			assert_int(fewest)
			. override_failure_message(
				"%s takes %d pylons, expected %d to %d" % [deposit.name, fewest, least, most]
			)
			. is_between(least, most)
		)


# Clear cells 4-connected to [param start], not crossing [param blocked].
func _flood(start: Vector2i, blocked: Dictionary) -> Dictionary:
	var reached := {start: true}
	var frontier: Array[Vector2i] = [start]
	while not frontier.is_empty():
		var cell: Vector2i = frontier.pop_back()
		for offset: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next := cell + offset
			if (
				_map.in_bounds(next)
				and not _map.is_rock(next)
				and not reached.has(next)
				and not blocked.has(next)
			):
				reached[next] = true
				frontier.append(next)
	return reached


func _reaches_base(cells: Dictionary) -> bool:
	return _map.base_cells().any(func(cell: Vector2i) -> bool: return cells.has(cell))


# A cell a pylon can stand on: clear, buildable, and on neither the base nor a deposit.
func _can_hold_pylon(cell: Vector2i) -> bool:
	return (
		_map.in_bounds(cell)
		and not _map.is_rock(cell)
		and not _map.is_no_build(cell)
		and not _map.is_base(cell)
		and _map.deposit_at(cell) == null
	)


# Breadth-first over pylon cells: a cell's value is the fewest pylons in a chain from the base
# ending with one on it. A pylon can stand in the base's power area, or in an earlier pylon's.
func _pylon_chains(settings: Settings) -> Dictionary:
	var base_area := _map.base.grow(settings.base_power_area)
	var reach: int = Buildings.kind_setting(settings, Buildings.PYLON, "power_area")
	var chains := {}
	var frontier: Array[Vector2i] = []
	for y in range(base_area.position.y, base_area.end.y):
		for x in range(base_area.position.x, base_area.end.x):
			var cell := Vector2i(x, y)
			if _can_hold_pylon(cell):
				chains[cell] = 1
				frontier.append(cell)
	var next := 0
	while next < frontier.size():
		var from := frontier[next]
		next += 1
		for y in range(from.y - reach, from.y + reach + 1):
			for x in range(from.x - reach, from.x + reach + 1):
				var cell := Vector2i(x, y)
				if not chains.has(cell) and _can_hold_pylon(cell):
					chains[cell] = chains[from] + 1
					frontier.append(cell)
	return chains


# The fewest pylons whose last one's power area covers the whole deposit (a rig is built only on
# the grid), or 0 when the base's area covers it.
func _fewest_pylons(chains: Dictionary, deposit: Rect2i, settings: Settings) -> int:
	if _map.base.grow(settings.base_power_area).encloses(deposit):
		return 0
	var reach: int = Buildings.kind_setting(settings, Buildings.PYLON, "power_area")
	var fewest := 1 << 30
	for cell: Vector2i in chains:
		var length: int = chains[cell]
		if Rect2i(cell, Vector2i.ONE).grow(reach).encloses(deposit):
			fewest = mini(fewest, length)
	return fewest


func test_the_default_map_path_is_the_v6_map() -> void:
	var settings := Settings.load_file(Settings.DEFAULTS_PATH).settings

	assert_str(settings.map_path).is_equal(PATH)
