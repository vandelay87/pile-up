extends GdUnitTestSuite

## A 16×12 open field with a 2×2 base at (2, 8) and a rock at (12, 3). The barracks at (6, 6)
## trains in the build phase, so a Train puts its soldier beside it at once: on (5, 8), the ring
## cell nearest the base's centre.

var _sim: Simulation
var _rejections: Array[String]
var _barracks: Buildings.Building


func before_test() -> void:
	var rows: Array[String] = []
	for y in 12:
		rows.append("............#..." if y == 3 else "................")
	_sim = (
		Simulation
		. new(
			Settings.load_file(Settings.DEFAULTS_PATH).settings,
			TestMaps.from_rows(rows, Rect2i(2, 8, 2, 2)),
		)
	)
	_sim.add_gold(10000 - _sim.run_state.gold)
	_rejections = []
	_sim.command_rejected.connect(func(reason: String) -> void: _rejections.append(reason))
	_sim.queue_command(Commands.Build.new(Buildings.BARRACKS, Vector2i(6, 6)))
	_sim.tick()
	_barracks = _sim.buildings.building(_sim.occupancy.building_at(Vector2i(6, 6)))


func test_a_new_soldier_walks_to_its_barracks_rally_point() -> void:
	_sim.queue_command(Commands.SetRallyPoint.new(_barracks.id, Vector2i(11, 2)))
	_sim.queue_command(Commands.Train.new(_barracks.id, 1))
	_sim.tick()

	_run_until_standing()

	assert_object(_sim.soldiers.spot(0)).is_equal(Vector2i(11, 2))
	assert_object(_sim.barracks.rally_point(_barracks.id)).is_equal(Vector2i(11, 2))


func test_new_soldiers_gather_round_the_rally_point_on_the_free_cells_nearest_it() -> void:
	_sim.queue_command(Commands.SetRallyPoint.new(_barracks.id, Vector2i(11, 2)))
	_sim.queue_command(Commands.Train.new(_barracks.id, 1))
	_sim.queue_command(Commands.Train.new(_barracks.id, 1))
	_sim.queue_command(Commands.Train.new(_barracks.id, 1))
	_sim.tick()

	_run_until_standing()

	var spots: Array[Vector2i] = []
	for i in _sim.soldiers.count:
		spots.append(_sim.soldiers.spot(i))
	assert_array(spots).contains_exactly_in_any_order(
		[Vector2i(11, 2), Vector2i(11, 1), Vector2i(10, 2)]
	)


func test_a_rally_point_on_rock_moves_to_the_nearest_cell_a_soldier_can_stand_on() -> void:
	_sim.queue_command(Commands.SetRallyPoint.new(_barracks.id, Vector2i(12, 3)))
	_sim.tick()

	assert_object(_sim.barracks.rally_point(_barracks.id)).is_equal(Vector2i(12, 2))


func test_without_a_rally_point_a_new_soldier_stands_where_it_appears() -> void:
	_sim.queue_command(Commands.SetRallyPoint.new(_barracks.id, Vector2i(11, 2)))
	_sim.queue_command(Commands.ClearRallyPoint.new(_barracks.id))
	_sim.queue_command(Commands.Train.new(_barracks.id, 1))
	_sim.tick()
	_sim.tick()

	assert_int(_sim.soldiers.orders[0]).is_equal(Soldiers.NONE)
	assert_object(_sim.soldiers.spot(0)).is_equal(Vector2i(5, 8))
	assert_object(_sim.barracks.rally_point(_barracks.id)).is_equal(Barracks.NO_RALLY)


func test_a_rally_point_on_something_not_a_barracks_is_rejected() -> void:
	_sim.queue_command(Commands.SetRallyPoint.new(999, Vector2i(11, 2)))
	_sim.queue_command(Commands.ClearRallyPoint.new(999))
	_sim.tick()

	assert_array(_rejections).contains_exactly(
		["rally point: not a barracks", "clear rally point: not a barracks"]
	)


func test_setting_a_rally_point_reports_the_barracks_changed() -> void:
	var changed: Array[int] = []
	_sim.training_changed.connect(func(id: int) -> void: changed.append(id))

	_sim.queue_command(Commands.SetRallyPoint.new(_barracks.id, Vector2i(11, 2)))
	_sim.tick()

	assert_array(changed).contains_exactly([_barracks.id])


func _run_until_standing() -> void:
	for tick in 2000:
		_sim.tick()
		var walking := false
		for i in _sim.soldiers.count:
			walking = walking or _sim.soldiers.orders[i] != Soldiers.NONE
		if not walking:
			return
	fail("soldiers still walking")
