extends GdUnitTestSuite

# Move and Stop orders, at the Simulation seam. Each test draws its own map: '.' clear ground,
# '#' rock, 'W' a wall (5 bodies landed before the test starts) and 'p' a level-2 pile. The base
# is 2×2 in the bottom-left corner, out of the way.

var _sim: Simulation
var _rejections: Array[String]


func test_a_soldier_sent_across_open_ground_reaches_the_target_and_stands_there() -> void:
	_sim = _sim_from(
		["............", "............", "............", "............", "............"]
	)
	var id := _sim.soldiers.add(Vector2i(1, 1))

	_move([id], Vector2(9.5, 1.5), Formations.CLUSTER)
	_run_until_standing(2000)

	assert_object(_spot_of(id)).is_equal(Vector2i(9, 1))
	assert_vector(_position_of(id)).is_equal_approx(Vector2(9.5, 1.5), Vector2(1e-4, 1e-4))


func test_a_soldier_sent_behind_a_corner_walks_round_it_to_its_slot() -> void:
	_sim = _sim_from(
		[
			"............",
			".#######....",
			".......#....",
			".......#....",
			"............",
			"............"
		]
	)
	var id := _sim.soldiers.add(Vector2i(9, 2))

	_move([id], Vector2(5.5, 2.5), Formations.CLUSTER)
	var cells := _cells_walked(id, 2000)

	assert_object(_spot_of(id)).is_equal(Vector2i(5, 2))
	for cell in cells:
		(
			assert_bool(_sim.map.is_rock(cell))
			. override_failure_message("walked on rock at %s" % cell)
			. is_false()
		)


func test_a_soldier_climbs_over_a_wall_rather_than_walking_a_long_way_round() -> void:
	_sim = _sim_from(
		[
			"....W.......",
			"....W.......",
			"....W.......",
			"....W.......",
			"....W.......",
			"............",
			"............"
		]
	)
	var id := _sim.soldiers.add(Vector2i(2, 0))

	_move([id], Vector2(7.5, 0.5), Formations.CLUSTER)
	var cells := _cells_walked(id, 2000)

	assert_object(_spot_of(id)).is_equal(Vector2i(7, 0))
	(
		assert_bool(cells.any(func(cell: Vector2i) -> bool: return cell.x == 4 and cell.y < 3))
		. is_true()
	)


func test_buildings_and_rock_are_never_crossed() -> void:
	_sim = _sim_from(
		[
			"............",
			"............",
			"##.######.##",
			"............",
			"............",
			"............"
		]
	)
	_sim.queue_command(Commands.Build.new(Buildings.PYLON, Vector2i(2, 2)))
	var id := _sim.soldiers.add(Vector2i(2, 0))

	_move([id], Vector2(2.5, 4.5), Formations.CLUSTER)
	var cells := _cells_walked(id, 2000)

	assert_object(_spot_of(id)).is_equal(Vector2i(2, 4))
	assert_array(cells).not_contains([Vector2i(2, 2)])
	assert_array(cells).contains([Vector2i(9, 2)])


func test_a_target_on_rock_becomes_the_nearest_cell_a_soldier_can_stand_on() -> void:
	_sim = _sim_from(
		[
			"............",
			"............",
			"....###.....",
			"............",
			"............",
			"............"
		]
	)
	var id := _sim.soldiers.add(Vector2i(9, 4))

	_move([id], Vector2(5.5, 2.4), Formations.CLUSTER)
	_run_until_standing(2000)

	assert_object(_spot_of(id)).is_equal(Vector2i(5, 1))


func test_a_target_on_a_building_becomes_the_nearest_cell_a_soldier_can_stand_on() -> void:
	_sim = _sim_from(
		[
			"............",
			"............",
			"............",
			"............",
			"............",
			"............"
		]
	)
	_sim.queue_command(Commands.Build.new(Buildings.PYLON, Vector2i(5, 2)))
	var id := _sim.soldiers.add(Vector2i(9, 4))

	_move([id], Vector2(5.5, 2.6), Formations.CLUSTER)
	_run_until_standing(2000)

	assert_object(_spot_of(id)).is_equal(Vector2i(5, 3))


func test_a_soldier_in_an_enclosed_region_stops_where_the_anchor_is_out_of_its_reach() -> void:
	_sim = _sim_from(
		[
			"#####.......",
			"#...#.......",
			"#####.......",
			"............",
			"............",
			"............"
		]
	)
	var shut_in := _sim.soldiers.add(Vector2i(2, 1))
	var outside := _sim.soldiers.add(Vector2i(6, 4))

	_move([shut_in, outside], Vector2(9.5, 1.5), Formations.CLUSTER)
	_sim.tick()

	assert_int(_sim.soldiers.orders[0]).is_equal(Soldiers.NONE)
	assert_object(_spot_of(shut_in)).is_equal(Vector2i(2, 1))
	_run_until_standing(2000)
	assert_object(_spot_of(outside)).is_equal(Vector2i(9, 1))


func test_a_cluster_fills_the_cells_nearest_the_anchor() -> void:
	_sim = _sim_from(
		[
			"............",
			"............",
			"............",
			"............",
			"............",
			"............",
			"............"
		]
	)
	var ids := _add_row(Vector2i(3, 5), 5)

	_move(ids, Vector2(8.5, 2.5), Formations.CLUSTER)
	_run_until_standing(2000)

	assert_array(_spots()).contains_exactly_in_any_order(
		[Vector2i(8, 2), Vector2i(8, 1), Vector2i(7, 2), Vector2i(9, 2), Vector2i(8, 3)]
	)


func test_a_cluster_skips_cells_standing_soldiers_hold() -> void:
	_sim = _sim_from(
		[
			"............",
			"............",
			"............",
			"............",
			"............",
			"............",
			"............"
		]
	)
	var ids := _add_row(Vector2i(3, 5), 2)
	_sim.soldiers.add(Vector2i(8, 2))

	_move(ids, Vector2(8.5, 2.5), Formations.CLUSTER)
	_run_until_standing(2000)

	assert_array(_spots().slice(0, 2)).contains_exactly_in_any_order(
		[Vector2i(8, 1), Vector2i(7, 2)]
	)


func test_a_line_runs_across_the_direction_of_travel_alternating_from_the_centre() -> void:
	_sim = _sim_from(
		[
			"............",
			"............",
			"............",
			"............",
			"............",
			"............",
			"............"
		]
	)
	var ids := _add_row(Vector2i(4, 5), 5)

	_move(ids, Vector2(6.5, 1.5), Formations.LINE)
	_run_until_standing(2000)

	assert_array(_spots()).contains_exactly_in_any_order(
		[Vector2i(4, 1), Vector2i(5, 1), Vector2i(6, 1), Vector2i(7, 1), Vector2i(8, 1)]
	)


func test_a_line_forms_a_second_rank_behind_once_both_sides_end() -> void:
	_sim = _sim_from(
		[
			"............",
			"....#...#...",
			"............",
			"............",
			"............",
			"............",
			"............"
		]
	)
	var ids := _add_row(Vector2i(4, 5), 5)

	_move(ids, Vector2(6.5, 1.5), Formations.LINE)
	_run_until_standing(2000)

	assert_array(_spots()).contains_exactly_in_any_order(
		[Vector2i(5, 1), Vector2i(6, 1), Vector2i(7, 1), Vector2i(5, 2), Vector2i(6, 2)]
	)


func test_soldiers_take_slots_nearest_them_nearest_the_anchor_first() -> void:
	_sim = _sim_from(
		[
			"............",
			"............",
			"............",
			"............",
			"............",
			"............",
			"............"
		]
	)
	var far := _sim.soldiers.add(Vector2i(6, 4))
	var near := _sim.soldiers.add(Vector2i(7, 1))

	# The slots are the anchor (6, 1) and (6, 0); the near soldier picks first and takes the
	# anchor, nearest it, though the far one is nearer it still.
	_move([far, near], Vector2(6.5, 1.5), Formations.CLUSTER)
	_run_until_standing(2000)

	assert_object(_spot_of(near)).is_equal(Vector2i(6, 1))
	assert_object(_spot_of(far)).is_equal(Vector2i(6, 0))


func test_a_building_placed_on_a_path_replans_it_and_soldiers_keep_walking_meanwhile() -> void:
	_sim = _sim_from(
		[
			"....................",
			"....................",
			"....................",
			"....................",
			"...................."
		]
	)
	var id := _sim.soldiers.add(Vector2i(2, 1))
	_move([id], Vector2(17.5, 1.5), Formations.CLUSTER)
	for tick in 10:
		_sim.tick()
	var before := _position_of(id)
	assert_bool(_path_cells(id).has(Vector2i(10, 1))).is_true()

	_sim.queue_command(Commands.Build.new(Buildings.PYLON, Vector2i(10, 1)))
	_sim.tick()

	assert_array(_rejections).is_empty()
	assert_float(_position_of(id).x).is_greater(before.x)
	var cells := _cells_walked(id, 2000)
	assert_object(_spot_of(id)).is_equal(Vector2i(17, 1))
	assert_array(cells).not_contains([Vector2i(10, 1)])


func test_a_long_order_settles_over_several_ticks_within_the_budget() -> void:
	var rows: Array[String] = []
	for y in 60:
		rows.append(".".repeat(80))
	_sim = _sim_from(rows)
	var id := _sim.soldiers.add(Vector2i(79, 0))

	_move([id], Vector2(2.5, 57.5), Formations.CLUSTER)
	var ticks_waiting := 0
	while ticks_waiting < 100:
		_sim.tick()
		ticks_waiting += 1
		assert_int(_sim.unit_paths.last_settled).is_less_equal(UnitPaths.PATH_SETTLE_CELLS)
		if not _path_cells(id).is_empty():
			break
		# Its field isn't ready, so it stands.
		assert_vector(_position_of(id)).is_equal(Vector2(79.5, 0.5))

	assert_int(ticks_waiting).is_greater(1)
	_run_until_standing(3000)
	assert_object(_spot_of(id)).is_equal(Vector2i(2, 57))


func test_stop_makes_the_current_position_the_spot() -> void:
	_sim = _sim_from(
		["............", "............", "............", "............", "............"]
	)
	var id := _sim.soldiers.add(Vector2i(1, 1))
	_move([id], Vector2(10.5, 1.5), Formations.CLUSTER)
	for tick in 60:
		_sim.tick()
	var cell := Vector2i(_position_of(id).floor())

	_sim.queue_command(Commands.Stop.new(PackedInt32Array([id])))
	_sim.tick()

	assert_int(_sim.soldiers.orders[0]).is_equal(Soldiers.NONE)
	assert_object(_spot_of(id)).is_equal(cell)
	for tick in 60:
		_sim.tick()
	assert_object(Vector2i(_position_of(id).floor())).is_equal(cell)


func test_a_soldier_pushed_more_than_a_cell_off_its_spot_paths_back_to_it() -> void:
	_sim = _sim_from(
		["............", ".#######....", ".......#....", "............", "............"]
	)
	var id := _sim.soldiers.add(Vector2i(4, 0))
	_sim.soldiers.positions[0] = Vector2(4.5, 2.5)

	var cells := _cells_walked(id, 2000)

	assert_object(_spot_of(id)).is_equal(Vector2i(4, 0))
	assert_vector(_position_of(id)).is_equal(Vector2(4.5, 0.5))
	assert_array(cells).contains([Vector2i(0, 1)])


func test_a_building_placed_on_soldiers_pushes_them_to_the_nearest_free_cell() -> void:
	_sim = _sim_from(
		[
			"............",
			"............",
			"............",
			"............",
			"............",
			"............"
		]
	)
	var id := _sim.soldiers.add(Vector2i(5, 2))

	_sim.queue_command(Commands.Build.new(Buildings.PYLON, Vector2i(5, 2)))
	_sim.tick()

	# The ring around (5, 2): the cell nearest the base's centre (1, 5) is (4, 3).
	assert_object(_spot_of(id)).is_equal(Vector2i(4, 3))
	assert_vector(_position_of(id)).is_equal(Vector2(4.5, 3.5))


func test_unknown_formations_are_rejected() -> void:
	_sim = _sim_from(["............", "............", "............", "............"])
	var id := _sim.soldiers.add(Vector2i(5, 1))

	_move([id], Vector2(9.5, 1.5), &"wedge")
	_sim.tick()

	assert_array(_rejections).contains_exactly(["move: the formation must be cluster or line"])
	assert_int(_sim.soldiers.orders[0]).is_equal(Soldiers.NONE)


func test_two_runs_with_the_same_orders_end_in_the_same_state() -> void:
	var ends: Array[PackedVector2Array] = []
	for run in 2:
		_sim = _sim_from(
			[
				"............",
				".#######....",
				".......#....",
				"..W....#....",
				"..pp........",
				"............"
			]
		)
		var ids := _add_row(Vector2i(8, 0), 4)
		_move(ids, Vector2(4.5, 2.5), Formations.LINE)
		for tick in 30:
			_sim.tick()
		_move(ids.slice(0, 2), Vector2(10.5, 5.5), Formations.CLUSTER)
		for tick in 200:
			_sim.tick()
		ends.append(_sim.soldiers.positions.slice(0, _sim.soldiers.count))

	assert_array(Array(ends[1])).is_equal(Array(ends[0]))


func _move(ids: Array, target: Vector2, formation: StringName) -> void:
	_sim.queue_command(Commands.Move.new(PackedInt32Array(ids), target, formation))


# Ticks until no soldier is under an order, failing after [param limit] ticks.
func _run_until_standing(limit: int) -> int:
	for tick in limit:
		_sim.tick()
		var walking := false
		for i in _sim.soldiers.count:
			walking = walking or _sim.soldiers.orders[i] != Soldiers.NONE
		if not walking:
			return tick + 1
	fail("soldiers still walking after %d ticks" % limit)
	return limit


# Ticks until the soldier [param id] stands, returning every cell it stood on along the way.
func _cells_walked(id: int, limit: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for tick in limit:
		_sim.tick()
		var cell := Vector2i(_position_of(id).floor())
		if cells.is_empty() or cells[-1] != cell:
			cells.append(cell)
		if _sim.soldiers.orders[_sim.soldiers.index_of(id)] == Soldiers.NONE:
			return cells
	fail("soldier still walking after %d ticks" % limit)
	return cells


func _path_cells(id: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for index in _sim.soldiers.path_left(_sim.soldiers.index_of(id)):
		cells.append(_sim.map.cell_of(index))
	return cells


func _add_row(first: Vector2i, wanted: int) -> Array:
	var ids := []
	for n in wanted:
		ids.append(_sim.soldiers.add(first + Vector2i(n, 0)))
	return ids


func _spots() -> Array[Vector2i]:
	var spots: Array[Vector2i] = []
	for i in _sim.soldiers.count:
		spots.append(_sim.soldiers.spot(i))
	return spots


func _spot_of(id: int) -> Vector2i:
	return _sim.soldiers.spot(_sim.soldiers.index_of(id))


func _position_of(id: int) -> Vector2:
	return _sim.soldiers.positions[_sim.soldiers.index_of(id)]


# Rows with the base's 2×2 in the bottom-left corner. 'W' cells get a wall and 'p' cells a
# level-2 pile before the test starts.
func _sim_from(rows: Array[String]) -> Simulation:
	var clear_rows: Array[String] = []
	var bodies := PackedVector2Array()
	for y in rows.size():
		clear_rows.append(rows[y].replace("W", ".").replace("p", "."))
		for x in rows[y].length():
			var level: int = {"W": Piles.WALL_LEVEL, "p": 2}.get(rows[y][x], 0)
			for n in level:
				bodies.append(Vector2(x + 0.5, y + 0.5))
	var map := TestMaps.from_rows(clear_rows, Rect2i(0, rows.size() - 2, 2, 2))
	var sim := Simulation.new(Settings.load_file(Settings.DEFAULTS_PATH).settings, map)
	_rejections = []
	sim.command_rejected.connect(func(reason: String) -> void: _rejections.append(reason))
	if not bodies.is_empty():
		sim.piles.queue_bodies(Deaths.bodies_at(bodies))
		sim.tick()
	return sim
