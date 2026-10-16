extends "res://test/sim/soldiers/order_suite.gd"

# Move and Stop orders: where soldiers go, how they path there, and replanning.


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


func test_a_building_placed_on_a_path_replans_it_and_soldiers_keep_walking_meanwhile() -> void:
	# A rock wall down x = 30 with a gap at the bottom: the new field fills much of the map before
	# it finds the way round, more than one tick's budget, so it settles over several.
	var rows: Array[String] = []
	for y in 40:
		rows.append(".".repeat(30) + ("#" if y < 34 else ".") + ".".repeat(29))
	_sim = _sim_from(rows)
	_sim.change_setting("run", "base_power_area", 50)
	var id := _sim.soldiers.add(Vector2i(20, 2))
	_move([id], Vector2(45.5, 2.5), Formations.CLUSTER)
	for tick in 30:
		_sim.tick()
	var on_path := _path_cells(id)[3]
	var generation := _sim.unit_paths.generation(_sim.soldiers.orders[0])

	_sim.queue_command(Commands.Build.new(Buildings.PYLON, on_path))
	var waited := 0
	var before := _position_of(id)
	_sim.tick()
	while not _sim.unit_paths.is_ready(_sim.soldiers.orders[0]):
		assert_bool(_path_cells(id).has(on_path)).is_true()
		assert_vector(_position_of(id)).is_not_equal(before)
		before = _position_of(id)
		_sim.tick()
		waited += 1

	assert_array(_rejections).is_empty()
	assert_int(_sim.unit_paths.generation(_sim.soldiers.orders[0])).is_greater(generation)
	assert_int(waited).is_greater(0)
	var cells := _cells_walked(id, 5000)
	assert_object(_spot_of(id)).is_equal(Vector2i(45, 2))
	assert_array(cells).not_contains([on_path])


func test_a_long_order_settles_over_several_ticks_within_the_budget() -> void:
	# A rock wall down x = 40 with a gap at the bottom: the way round is long and the field fills
	# most of the map to find it.
	var rows: Array[String] = []
	for y in 60:
		rows.append(".".repeat(40) + ("#" if y < 56 else ".") + ".".repeat(39))
	_sim = _sim_from(rows)
	var id := _sim.soldiers.add(Vector2i(79, 0))

	_move([id], Vector2(2.5, 2.5), Formations.CLUSTER)
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
	_run_until_standing(6000)
	assert_object(_spot_of(id)).is_equal(Vector2i(2, 2))


func test_a_soldier_pushed_where_it_cannot_reach_its_spot_stands_where_it_is() -> void:
	_sim = _sim_from(
		["#####.......", "#...#.......", "#####.......", "............", "............"]
	)
	var id := _sim.soldiers.add(Vector2i(8, 1))
	_sim.soldiers.positions[0] = Vector2(2.5, 1.5)

	for tick in 5:
		_sim.tick()

	assert_int(_sim.soldiers.orders[0]).is_equal(Soldiers.NONE)
	assert_object(_spot_of(id)).is_equal(Vector2i(2, 1))
	assert_int(_sim.unit_paths.field_ids().size()).is_equal(0)


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
	var ends: Array[Array] = []
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
		ends.append(_state())

	assert_array(ends[1]).is_equal(ends[0])
