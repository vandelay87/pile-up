extends GdUnitTestSuite

var _settings: Settings
var _events: Array[String]


func before_test() -> void:
	_settings = Settings.load_file(Settings.DEFAULTS_PATH).settings
	_events = []


func test_a_placement_charges_the_cost_and_occupies_all_four_cells() -> void:
	var sim := _sim(_open_rows())

	sim.queue_command(Commands.Build.new(Buildings.TOWER, Vector2i(0, 5)))
	sim.tick()

	assert_int(sim.run_state.gold).is_equal(120)
	for cell: Vector2i in [Vector2i(0, 5), Vector2i(1, 5), Vector2i(0, 6), Vector2i(1, 6)]:
		assert_bool(sim.occupancy.is_occupied(cell)).is_true()
	for cell: Vector2i in [Vector2i(2, 5), Vector2i(0, 7), Vector2i(0, 4)]:
		assert_bool(sim.occupancy.is_occupied(cell)).is_false()
	assert_array(_events).contains_exactly(["gold 120", "placed (0, 5)"])


func test_a_placement_overlapping_rock_base_or_a_tower_is_rejected_as_occupied() -> void:
	var rows := _open_rows()
	rows[1] = ".#........"
	var sim := _sim(rows)
	sim.queue_command(Commands.Build.new(Buildings.TOWER, Vector2i(7, 1)))
	sim.tick()
	_events.clear()

	for origin: Vector2i in [Vector2i(0, 0), Vector2i(3, 3), Vector2i(6, 1), Vector2i(8, 0)]:
		sim.queue_command(Commands.Build.new(Buildings.TOWER, origin))
	sim.tick()

	var occupied := "build tower: occupied"
	assert_array(_events).contains_exactly([occupied, occupied, occupied, occupied])
	assert_int(sim.run_state.gold).is_equal(120)
	assert_bool(sim.occupancy.is_occupied(Vector2i(0, 0))).is_false()


func test_a_placement_overlapping_a_pile_is_rejected_as_occupied() -> void:
	var sim := _sim(_open_rows())
	sim.piles.queue_bodies(PackedVector2Array([Vector2(1.5, 6.5)]))
	sim.tick()

	sim.queue_command(Commands.Build.new(Buildings.TOWER, Vector2i(0, 5)))
	sim.tick()

	assert_array(_events).contains_exactly(["build tower: occupied"])
	assert_bool(sim.occupancy.is_occupied(Vector2i(0, 5))).is_false()


func test_a_placement_off_the_map_is_rejected() -> void:
	var sim := _sim(_open_rows())

	sim.queue_command(Commands.Build.new(Buildings.TOWER, Vector2i(9, 3)))
	sim.queue_command(Commands.Build.new(Buildings.TOWER, Vector2i(-1, 3)))
	sim.tick()

	assert_array(_events).contains_exactly(["build tower: off the map", "build tower: off the map"])
	assert_int(sim.run_state.gold).is_equal(200)


func test_a_placement_without_enough_gold_is_rejected() -> void:
	_settings.change("towers", "cost", 90)
	var sim := _sim(_open_rows())

	for origin: Vector2i in [Vector2i(0, 2), Vector2i(0, 4), Vector2i(0, 6)]:
		sim.queue_command(Commands.Build.new(Buildings.TOWER, origin))
	sim.tick()

	assert_array(_events).contains_exactly(
		["gold 20", "placed (0, 2)", "placed (0, 4)", "build tower: not enough gold"]
	)
	assert_bool(sim.occupancy.is_occupied(Vector2i(0, 6))).is_false()


func test_a_placement_that_cuts_a_spawn_edge_off_from_the_base_is_rejected() -> void:
	var rows := _open_rows()
	rows[2] = "..########"
	var sim := _sim(rows)

	sim.queue_command(Commands.Build.new(Buildings.TOWER, Vector2i(0, 1)))
	sim.tick()

	assert_array(_events).contains_exactly(["build tower: blocked"])
	assert_int(sim.run_state.gold).is_equal(200)
	assert_bool(sim.occupancy.is_occupied(Vector2i(0, 1))).is_false()


func test_a_placement_that_cuts_a_live_enemy_off_from_the_base_is_rejected() -> void:
	var rows := _open_rows()
	rows[7] = "##..######"
	var sim := _sim(rows)
	sim.enemies.spawn(Vector2(5.5, 8.5), _settings.enemy_hp)

	sim.queue_command(Commands.Build.new(Buildings.TOWER, Vector2i(2, 6)))
	sim.tick()

	assert_array(_events).contains_exactly(["build tower: blocked"])


func test_the_same_placement_is_accepted_with_no_enemy_behind_it() -> void:
	var rows := _open_rows()
	rows[7] = "##..######"
	var sim := _sim(rows)

	sim.queue_command(Commands.Build.new(Buildings.TOWER, Vector2i(2, 6)))
	sim.tick()

	assert_array(_events).contains_exactly(["gold 120", "placed (2, 6)"])


func test_a_placement_covering_a_spawn_cell_is_rejected() -> void:
	var sim := _sim(_open_rows())

	sim.queue_command(Commands.Build.new(Buildings.TOWER, Vector2i(0, 0)))
	sim.tick()

	assert_array(_events).contains_exactly(["build tower: blocked"])


func test_a_placement_on_top_of_a_live_enemy_is_rejected() -> void:
	var sim := _sim(_open_rows())
	sim.enemies.spawn(Vector2(1.5, 6.5), _settings.enemy_hp)

	sim.queue_command(Commands.Build.new(Buildings.TOWER, Vector2i(0, 6)))
	sim.tick()

	assert_array(_events).contains_exactly(["build tower: blocked"])


func test_a_route_left_only_through_a_cut_corner_counts_as_blocked() -> void:
	var rows := _open_rows()
	rows[2] = "#.########"
	var sim := _sim(rows)

	sim.queue_command(Commands.Build.new(Buildings.TOWER, Vector2i(0, 3)))
	sim.tick()

	assert_array(_events).contains_exactly(["build tower: blocked"])


func test_both_fields_route_around_a_new_tower_on_the_tick_it_is_built() -> void:
	var sim := _sim(_open_rows())
	var routing := sim.routing
	var seen: Array[float] = []
	sim.step_observer = func(step: int) -> void:
		if step == Simulation.Step.SPAWN_ENEMIES:
			seen.append(routing.value(Routing.Route.DIRECT, Vector2i(1, 6)))
	sim.fields_changed.connect(func() -> void: _events.append("fields changed"))

	sim.queue_command(Commands.Build.new(Buildings.TOWER, Vector2i(0, 5)))
	sim.tick()

	assert_array(seen).contains_exactly([Routing.UNREACHABLE])
	for route: Routing.Route in Routing.Route.values():
		assert_float(sim.routing.value(route, Vector2i(0, 6))).is_equal(Routing.UNREACHABLE)
	assert_array(_events).contains(["fields changed"])


func _open_rows() -> Array[String]:
	var rows: Array[String] = []
	for y in 10:
		rows.append("..........")
	return rows


func _sim(rows: Array[String], base := Rect2i(4, 4, 2, 2)) -> Simulation:
	var edges: Array[String] = ["N"]
	var sim := Simulation.new(_settings, TestMaps.from_rows(rows, base, edges), 1)
	sim.building_placed.connect(
		func(id: int) -> void: _events.append("placed %s" % sim.buildings.building(id).origin)
	)
	sim.gold_changed.connect(func(gold: int) -> void: _events.append("gold %d" % gold))
	sim.command_rejected.connect(func(reason: String) -> void: _events.append(reason))
	return sim
