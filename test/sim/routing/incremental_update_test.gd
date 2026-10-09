extends GdUnitTestSuite

const ROWS: Array[String] = [
	"........................",
	"........................",
	"....#...................",
	"....#.........###.......",
	"....#...................",
	"........................",
	"..........#.............",
	"..........#.............",
	"........................",
	"...................#....",
	"........................",
	"........................",
	"........................",
	"......##................",
	"........................",
	"........................",
	"..............#.........",
	"..............#.........",
	"........................",
	"........................",
	"...#....................",
	"........................",
	"........................",
	"........................",
]
const BASE := Rect2i(11, 11, 2, 2)
const STEPS := 300

var _settings: Settings
var _map: MapData
var _occupancy: Occupancy
var _piles: Piles
var _routing: Routing
var _rng: RandomNumberGenerator


func before_test() -> void:
	_settings = Settings.load_file(Settings.DEFAULTS_PATH).settings
	_map = TestMaps.from_rows(ROWS, BASE)
	_occupancy = Occupancy.new(_map.width, _map.height)
	_piles = Piles.new(_map, _occupancy)
	_routing = Routing.new(_settings, _map, _occupancy, _piles)
	_rng = RandomNumberGenerator.new()
	_rng.seed = 29


func test_both_fields_equal_a_full_rebuild_after_each_random_rise_and_fall() -> void:
	var mismatches: Array[String] = []
	for n in STEPS:
		var cells := _random_change()
		_routing.update(cells)
		if not _matches_full_rebuild():
			mismatches.append("step %d at %s" % [n, cells])

	assert_array(mismatches).is_empty()


func test_a_tower_built_beside_the_base_equals_a_full_rebuild() -> void:
	_raise_piles_around(BASE.grow(2))
	var cells := Towers.footprint(BASE.position + Vector2i(-2, 0))
	_occupancy.occupy(cells)

	_routing.update(cells)

	assert_bool(_matches_full_rebuild()).is_true()


func test_a_pile_rising_and_falling_at_a_tower_corner_equals_a_full_rebuild() -> void:
	var tower := Towers.footprint(Vector2i(6, 6))
	_occupancy.occupy(tower)
	_routing.update(tower)
	var beside := Vector2i(8, 8)

	for level in range(1, Piles.MAX_LANDING_LEVEL + 1):
		_set_level(beside, level)
		_routing.update([beside] as Array[Vector2i])
		assert_bool(_matches_full_rebuild()).is_true()
	for level in range(Piles.MAX_LANDING_LEVEL - 1, -1, -1):
		_set_level(beside, level)
		_routing.update([beside] as Array[Vector2i])
		assert_bool(_matches_full_rebuild()).is_true()


func test_a_tower_cutting_a_diagonal_parent_edge_equals_a_full_rebuild() -> void:
	var map := TestMaps.from_rows(["....", "....", "...."], Rect2i(0, 0, 1, 1))
	var occupancy := Occupancy.new(map.width, map.height)
	var piles := Piles.new(map, occupancy)
	var routing := Routing.new(_settings, map, occupancy, piles)
	var corner: Array[Vector2i] = [Vector2i(1, 0)]
	assert_vector(routing.parent(Routing.Route.SENSIBLE, Vector2i(1, 1))).is_equal(Vector2i.ZERO)

	occupancy.occupy(corner)
	routing.update(corner)

	var rebuilt := Routing.new(_settings, map, occupancy, piles)
	assert_vector(routing.parent(Routing.Route.SENSIBLE, Vector2i(1, 1))).is_equal(Vector2i(0, 1))
	assert_bool(FieldChecks.routings_match(routing, rebuilt, map)).is_true()


func test_changes_batched_in_one_update_equal_applying_them_one_by_one() -> void:
	var one_by_one := Routing.new(_settings, _map, _occupancy, _piles)
	for batch_round in 20:
		var batch: Array[Vector2i] = []
		for n in 8:
			var cells := _random_change()
			batch.append_array(cells)
			one_by_one.update(cells)

		_routing.update(batch)

		assert_bool(FieldChecks.routings_match(_routing, one_by_one, _map)).is_true()
	assert_bool(_matches_full_rebuild()).is_true()


func test_an_update_after_a_worker_rebuild_swaps_in_equals_a_full_rebuild() -> void:
	_raise_piles_around(BASE.grow(4))
	for y in _map.height:
		for x in _map.width:
			_set_level(Vector2i(x, y), maxi(_piles.level(Vector2i(x, y)) - 1, 0))
	_routing.start_rebuild()
	_routing.finish_rebuild()
	var cell := BASE.position + Vector2i(-1, -1)
	_set_level(cell, Piles.MAX_LANDING_LEVEL)

	_routing.update([cell] as Array[Vector2i])

	assert_bool(_matches_full_rebuild()).is_true()


func test_an_unchanged_cell_in_the_batch_changes_nothing() -> void:
	_raise_piles_around(Rect2i(3, 3, 4, 4))
	var before := Routing.new(_settings, _map, _occupancy, _piles)

	_routing.update([Vector2i(4, 4), Vector2i(4, 4), Vector2i(0, 0)] as Array[Vector2i])

	assert_bool(FieldChecks.routings_match(_routing, before, _map)).is_true()


func _random_change() -> Array[Vector2i]:
	while true:
		var cell := _random_cell()
		if _map.is_rock(cell) or _map.is_base(cell) or _occupancy.is_occupied(cell):
			continue
		if _rng.randf() < 0.03:
			var footprint := Towers.footprint(cell)
			if _can_build(footprint):
				_occupancy.occupy(footprint)
				return footprint
			continue
		var level := _piles.level(cell)
		var rise := level == 0 or (level < Piles.MAX_LANDING_LEVEL and _rng.randf() < 0.6)
		_set_level(cell, level + 1 if rise else level - 1)
		return [cell] as Array[Vector2i]
	return [] as Array[Vector2i]


func _random_cell() -> Vector2i:
	var near: Rect2i
	match _rng.randi_range(0, 2):
		0:
			near = BASE.grow(1)
		1:
			near = _random_tower_ring()
		_:
			return Vector2i(
				_rng.randi_range(0, _map.width - 1), _rng.randi_range(0, _map.height - 1)
			)
	var clipped := near.intersection(Rect2i(0, 0, _map.width, _map.height))
	return (
		clipped.position
		+ Vector2i(_rng.randi_range(0, clipped.size.x - 1), _rng.randi_range(0, clipped.size.y - 1))
	)


func _random_tower_ring() -> Rect2i:
	var towers: Array[Vector2i] = []
	for y in _map.height:
		for x in _map.width:
			if _occupancy.is_occupied(Vector2i(x, y)):
				towers.append(Vector2i(x, y))
	if towers.is_empty():
		return BASE.grow(3)
	return Rect2i(towers[_rng.randi_range(0, towers.size() - 1)], Vector2i.ONE).grow(1)


func _can_build(footprint: Array[Vector2i]) -> bool:
	for cell in footprint:
		if not _map.in_bounds(cell) or _map.is_rock(cell) or _map.is_base(cell):
			return false
		if _occupancy.is_occupied(cell):
			return false
	return true


func _raise_piles_around(area: Rect2i) -> void:
	var cells: Array[Vector2i] = []
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var cell := Vector2i(x, y)
			if not _map.is_rock(cell) and not _map.is_base(cell):
				_set_level(cell, 1 + (x + y) % Piles.MAX_LANDING_LEVEL)
				cells.append(cell)
	_routing.update(cells)


func _set_level(cell: Vector2i, level: int) -> void:
	_piles.levels[cell.y * _map.width + cell.x] = level


func _matches_full_rebuild() -> bool:
	var rebuilt := Routing.new(_settings, _map, _occupancy, _piles)
	return FieldChecks.routings_match(_routing, rebuilt, _map)
