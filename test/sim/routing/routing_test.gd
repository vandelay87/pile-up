extends GdUnitTestSuite

const SENSIBLE := Routing.Route.SENSIBLE
const DIRECT := Routing.Route.DIRECT
const DIAGONAL := sqrt(2.0)


func _routing(
	rows: Array[String], base: Rect2i, towers: Array[Vector2i] = [], piles: Dictionary = {}
) -> Routing:
	var map := TestMaps.from_rows(rows, base)
	var occupancy := Occupancy.new(map.width, map.height)
	occupancy.occupy(towers, 0)
	var run_piles := Piles.new(_settings(), map, occupancy)
	for cell: Vector2i in piles:
		var index := cell.y * map.width + cell.x
		run_piles.levels[index] = piles[cell]
		run_piles.wall_hps[index] = _settings().wall_hp if piles[cell] == Piles.WALL_LEVEL else 0.0
	return Routing.new(_settings(), map, occupancy, run_piles)


func _settings() -> Settings:
	return Settings.load_file(Settings.DEFAULTS_PATH).settings


func test_open_field_values_are_octile_distances_to_the_base() -> void:
	var routing := _routing([".....", ".....", "....."], Rect2i(0, 0, 1, 1))

	for route: Routing.Route in [SENSIBLE, DIRECT]:
		assert_float(routing.value(route, Vector2i(1, 0))).is_equal_approx(1.0, 1e-6)
		assert_float(routing.value(route, Vector2i(1, 1))).is_equal_approx(DIAGONAL, 1e-6)
		assert_float(routing.value(route, Vector2i(4, 0))).is_equal_approx(4.0, 1e-6)
		assert_float(routing.value(route, Vector2i(4, 2))).is_equal_approx(
			2.0 + 2.0 * DIAGONAL, 1e-6
		)


func test_no_diagonal_step_cuts_a_rock_corner() -> void:
	var routing := _routing([".#..", "....", "...."], Rect2i(0, 0, 1, 1))

	for route: Routing.Route in [SENSIBLE, DIRECT]:
		assert_float(routing.value(route, Vector2i(1, 1))).is_equal_approx(2.0, 1e-6)
		assert_float(routing.value(route, Vector2i(2, 0))).is_equal_approx(4.0, 1e-6)


func test_base_cells_are_zero_and_rock_and_tower_cells_are_unreachable() -> void:
	var routing := _routing(["#....", ".....", "....."], Rect2i(2, 1, 2, 1), [Vector2i(0, 2)])

	for route: Routing.Route in [SENSIBLE, DIRECT]:
		assert_float(routing.value(route, Vector2i(2, 1))).is_equal(0.0)
		assert_float(routing.value(route, Vector2i(3, 1))).is_equal(0.0)
		assert_float(routing.value(route, Vector2i(0, 0))).is_equal(Routing.UNREACHABLE)
		assert_float(routing.value(route, Vector2i(0, 2))).is_equal(Routing.UNREACHABLE)
		assert_vector(routing.parent(route, Vector2i(2, 1))).is_equal(Routing.NO_PARENT)
		assert_vector(routing.parent(route, Vector2i(0, 0))).is_equal(Routing.NO_PARENT)


func test_every_reachable_cell_has_a_parent_on_its_shortest_path() -> void:
	var rows: Array[String] = [
		"..........",
		"..##......",
		"...#..#...",
		"......#...",
		"..#.......",
		"......##..",
	]
	var towers: Array[Vector2i] = [Vector2i(8, 1), Vector2i(9, 1), Vector2i(8, 2), Vector2i(9, 2)]
	var routing := _routing(rows, Rect2i(4, 3, 2, 1), towers)

	for route: Routing.Route in [SENSIBLE, DIRECT]:
		for y in rows.size():
			for x in rows[0].length():
				var cell := Vector2i(x, y)
				var cell_value := routing.value(route, cell)
				if cell_value == Routing.UNREACHABLE or cell_value == 0.0:
					continue
				var parent := routing.parent(route, cell)
				var best := INF
				for neighbour in _walkable_neighbours(routing, route, cell):
					best = minf(best, routing.value(route, neighbour) + cell.distance_to(neighbour))
				assert_bool(parent in _walkable_neighbours(routing, route, cell)).is_true()
				(
					assert_float(routing.value(route, parent) + cell.distance_to(parent))
					. is_equal_approx(best, 1e-6)
				)
				assert_float(cell_value).is_equal_approx(best, 1e-6)


func _walkable_neighbours(
	routing: Routing, route: Routing.Route, cell: Vector2i
) -> Array[Vector2i]:
	var neighbours: Array[Vector2i] = []
	for dy: int in [-1, 0, 1]:
		for dx: int in [-1, 0, 1]:
			var neighbour := cell + Vector2i(dx, dy)
			if neighbour == cell or not _reachable(routing, route, neighbour):
				continue
			var cuts_corner: bool = (
				dx != 0
				and dy != 0
				and (
					not _reachable(routing, route, cell + Vector2i(dx, 0))
					or not _reachable(routing, route, cell + Vector2i(0, dy))
				)
			)
			if not cuts_corner:
				neighbours.append(neighbour)
	return neighbours


func _reachable(routing: Routing, route: Routing.Route, cell: Vector2i) -> bool:
	if cell.x < 0 or cell.y < 0 or cell.x >= 10 or cell.y >= 6:
		return false
	return routing.value(route, cell) != Routing.UNREACHABLE


func test_pile_factor_follows_the_slow_at_pile_weight_1() -> void:
	var routing := _routing(["..."], Rect2i(0, 0, 1, 1))

	assert_float(routing.pile_factor(SENSIBLE, 1)).is_equal_approx(1.18, 0.005)
	assert_float(routing.pile_factor(SENSIBLE, 4)).is_equal_approx(2.5, 1e-6)
	assert_float(routing.pile_factor(DIRECT, 4)).is_equal_approx(1.0, 1e-6)


func test_wall_factor_is_its_break_time_in_cells_at_wall_weight_1() -> void:
	var routing := _routing(["..."], Rect2i(0, 0, 1, 1))

	# At 2 cells/s against 2 HP/s, a wall takes 1 cell of walking per HP to break.
	assert_float(routing.wall_factor(SENSIBLE, 30.0)).is_equal_approx(31.0, 1e-6)
	assert_float(routing.wall_factor(SENSIBLE, 10.0)).is_equal_approx(11.0, 1e-6)
	assert_float(routing.wall_factor(DIRECT, 30.0)).is_equal_approx(4.0, 1e-6)


func test_cost_factors_follow_route_weight_settings() -> void:
	var settings := _settings()
	settings.change("routing", "sensible_pile_weight", 2.0)
	settings.change("routing", "direct_wall_weight", 0.5)
	var map := TestMaps.from_rows(["..."], Rect2i(0, 0, 1, 1))
	var occupancy := Occupancy.new(map.width, map.height)
	var routing := Routing.new(settings, map, occupancy, Piles.new(settings, map, occupancy))

	assert_float(routing.pile_factor(SENSIBLE, 4)).is_equal_approx(4.0, 1e-6)
	assert_float(routing.wall_factor(DIRECT, 30.0)).is_equal_approx(16.0, 1e-6)


func test_a_wall_costs_its_wall_factor_at_its_bucketed_hp_to_enter() -> void:
	var expected := {30.0: Vector2(33.0, 6.0), 25.0: Vector2(33.0, 6.0), 20.0: Vector2(23.0, 5.0)}
	for hp: float in expected:
		var map := TestMaps.from_rows(["....."], Rect2i(0, 0, 1, 1))
		var occupancy := Occupancy.new(map.width, map.height)
		var piles := Piles.new(_settings(), map, occupancy)
		piles.levels[2] = Piles.WALL_LEVEL
		piles.wall_hps[2] = hp
		var routing := Routing.new(_settings(), map, occupancy, piles)

		var values: Vector2 = expected[hp]
		assert_float(routing.value(SENSIBLE, Vector2i(3, 0))).is_equal_approx(values.x, 1e-6)
		assert_float(routing.value(DIRECT, Vector2i(3, 0))).is_equal_approx(values.y, 1e-6)


func test_no_diagonal_step_cuts_a_wall_corner() -> void:
	var wall := {Vector2i(1, 0): Piles.WALL_LEVEL}
	var routing := _routing(["....", "....", "...."], Rect2i(0, 0, 1, 1), [], wall)

	for route: Routing.Route in [SENSIBLE, DIRECT]:
		assert_float(routing.value(route, Vector2i(1, 1))).is_equal_approx(2.0, 1e-6)
		assert_float(routing.value(route, Vector2i(2, 0))).is_equal_approx(4.0, 1e-6)


func test_direction_at_a_cell_centre_points_to_its_parent() -> void:
	var routing := _routing([".....", ".....", "....."], Rect2i(0, 0, 1, 1))

	assert_vector(routing.sample_direction(SENSIBLE, Vector2(2.5, 0.5))).is_equal_approx(
		Vector2(-1, 0), Vector2.ONE * 1e-6
	)
	assert_vector(routing.sample_direction(DIRECT, Vector2(2.5, 2.5))).is_equal_approx(
		Vector2(-1, -1).normalized(), Vector2.ONE * 1e-6
	)


func test_direction_between_cell_centres_is_a_blend() -> void:
	var routing := _routing(["...", "...", "..."], Rect2i(0, 0, 1, 1))

	var halfway := Vector2(-cos(PI / 8.0), -sin(PI / 8.0))
	assert_vector(routing.sample_direction(SENSIBLE, Vector2(1.5, 1.0))).is_equal_approx(
		halfway, Vector2.ONE * 1e-6
	)


func test_direction_sampling_skips_impassable_cells() -> void:
	var routing := _routing(["...", ".#."], Rect2i(0, 0, 1, 1))

	assert_vector(routing.sample_direction(SENSIBLE, Vector2(1.5, 1.0))).is_equal_approx(
		Vector2(-1, 0), Vector2.ONE * 1e-6
	)


func test_value_sampling_blends_the_field_and_skips_impassable_cells() -> void:
	var routing := _routing(["...", ".#."], Rect2i(0, 0, 1, 1))

	assert_float(routing.sample_value(SENSIBLE, Vector2(2.5, 0.5))).is_equal_approx(2.0, 1e-6)
	assert_float(routing.sample_value(SENSIBLE, Vector2(2.0, 0.5))).is_equal_approx(1.5, 1e-6)
	assert_float(routing.sample_value(SENSIBLE, Vector2(1.5, 1.0))).is_equal_approx(1.0, 1e-6)


func test_a_pile_costs_its_pile_factor_to_enter_on_each_route() -> void:
	var routing := _routing(["....."], Rect2i(0, 0, 1, 1), [], {Vector2i(2, 0): 2})

	var sensible := 2.0 + routing.pile_factor(SENSIBLE, 2)
	assert_float(routing.value(SENSIBLE, Vector2i(3, 0))).is_equal_approx(sensible, 1e-6)
	assert_float(routing.value(DIRECT, Vector2i(3, 0))).is_equal_approx(3.0, 1e-6)
	assert_float(routing.value(SENSIBLE, Vector2i(2, 0))).is_equal_approx(2.0, 1e-6)


func test_a_change_during_a_rebuild_is_in_the_fields_it_swaps_in() -> void:
	var map := TestMaps.from_rows(["......", "......", "......"], Rect2i(0, 0, 1, 1))
	var occupancy := Occupancy.new(map.width, map.height)
	var piles := Piles.new(_settings(), map, occupancy)
	var routing := Routing.new(_settings(), map, occupancy, piles)
	routing.start_rebuild()

	var tower: Array[Vector2i] = [Vector2i(2, 0), Vector2i(2, 1)]
	occupancy.occupy(tower, 0)
	var updated_now := routing.update(tower)
	var swapped_stale := routing.finish_rebuild()
	var swapped_restart := routing.finish_rebuild()

	assert_bool(updated_now).is_false()
	assert_bool(swapped_stale).is_false()
	assert_bool(swapped_restart).is_true()
	assert_bool(routing.is_rebuilding()).is_false()
	var rebuilt := Routing.new(_settings(), map, occupancy, piles)
	assert_bool(FieldChecks.routings_match(routing, rebuilt, map)).is_true()
