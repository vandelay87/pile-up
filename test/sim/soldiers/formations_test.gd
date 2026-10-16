extends "res://test/sim/soldiers/order_suite.gd"

# Cluster and Line slots, and which soldier takes which.


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


func test_a_slot_built_over_moves_to_a_free_cell_no_other_soldier_takes() -> void:
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
	var ids := _add_row(Vector2i(2, 0), 5)
	_move(ids, Vector2(8.5, 2.5), Formations.CLUSTER)
	_sim.tick()
	var slot_cells: Array[Vector2i] = []
	for i in _sim.soldiers.count:
		slot_cells.append(_sim.map.cell_of(_sim.soldiers.slots[i]))
	assert_array(slot_cells).contains([Vector2i(8, 1)])

	_sim.queue_command(Commands.Build.new(Buildings.PYLON, Vector2i(8, 1)))
	_run_until_standing(2000)

	var spots := _spots()
	assert_array(spots).not_contains([Vector2i(8, 1)])
	var unique := {}
	for spot in spots:
		unique[spot] = true
	assert_int(unique.size()).is_equal(5)


func test_soldiers_sent_onto_a_pile_get_past_those_already_standing_there() -> void:
	_sim = _sim_from(
		[
			"................",
			"................",
			"........33333...",
			"........33333...",
			"........33333...",
			"........33333...",
			"........33333...",
			"................",
			"................",
			"................",
			"................",
			"................",
		]
	)
	var ids := _add_row(Vector2i(2, 8), 3)

	_move(ids, Vector2(10.5, 4.5), Formations.CLUSTER)

	# Unhindered, the last soldier stands in about 300 ticks; held back by the soldiers on its
	# path, it took over 700.
	assert_int(_run_until_standing(2000)).is_less(400)
