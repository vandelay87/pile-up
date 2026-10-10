extends GdUnitTestSuite

var _settings: Settings
var _sim: Simulation
var _events: Array[String]
var _placed: Array[int]


func before_test() -> void:
	_settings = Settings.load_file(Settings.DEFAULTS_PATH).settings
	var rows: Array[String] = []
	for y in 10:
		rows.append("..........")
	var edges: Array[String] = ["N"]
	_sim = Simulation.new(_settings, TestMaps.from_rows(rows, Rect2i(4, 4, 2, 2), edges), 1)
	_events = []
	_placed = []
	_sim.building_placed.connect(func(id: int) -> void: _placed.append(id))
	_sim.gold_changed.connect(func(gold: int) -> void: _events.append("gold %d" % gold))
	_sim.command_rejected.connect(func(reason: String) -> void: _events.append(reason))


func test_building_a_tower_places_it_charges_its_cost_and_reports_its_new_id() -> void:
	_sim.queue_command(Commands.Build.new(Buildings.TOWER, Vector2i(0, 5)))
	_sim.tick()

	assert_array(_events).contains_exactly(["gold 100"])
	assert_int(_placed.size()).is_equal(1)
	var tower := _sim.buildings.building(_placed[0])
	assert_str(tower.kind).is_equal(Buildings.TOWER)
	assert_that(tower.origin).is_equal(Vector2i(0, 5))
	assert_array(tower.footprint).contains_exactly_in_any_order(
		[Vector2i(0, 5), Vector2i(1, 5), Vector2i(0, 6), Vector2i(1, 6)]
	)
	for cell in tower.footprint:
		assert_int(_sim.occupancy.building_at(cell)).is_equal(tower.id)
	assert_int(_sim.occupancy.building_at(Vector2i(2, 5))).is_equal(Occupancy.EMPTY)


func test_ids_are_stable_never_reused_and_buildings_stay_in_build_order() -> void:
	for origin: Vector2i in [Vector2i(0, 0), Vector2i(0, 7), Vector2i(0, 7), Vector2i(7, 7)]:
		_sim.queue_command(Commands.Build.new(Buildings.TOWER, origin))
	_sim.tick()

	assert_int(_placed.size()).is_equal(2)
	assert_int(_placed[0]).is_not_equal(_placed[1])
	assert_array(_origins()).contains_exactly([Vector2i(0, 7), Vector2i(7, 7)])
	assert_array(_ids()).is_equal(_placed)
	var first := _sim.buildings.building(_placed[0])

	_sim.queue_command(Commands.Build.new(Buildings.TOWER, Vector2i(7, 2)))
	_sim.tick()

	assert_int(_placed.size()).is_equal(3)
	assert_array(_placed.slice(0, 2)).not_contains([_placed[2]])
	assert_object(_sim.buildings.building(_placed[0])).is_same(first)
	assert_array(_ids()).is_equal(_placed)


func test_an_unknown_kind_is_rejected_with_a_reason() -> void:
	_sim.queue_command(Commands.Build.new(&"castle", Vector2i(0, 5)))
	_sim.tick()

	assert_array(_events).contains_exactly(["build castle: unknown kind"])
	assert_array(_placed).is_empty()
	assert_int(_sim.run_state.gold).is_equal(150)
	assert_bool(_sim.occupancy.is_occupied(Vector2i(0, 5))).is_false()


func _origins() -> Array[Vector2i]:
	var origins: Array[Vector2i] = []
	for building in _sim.buildings.built:
		origins.append(building.origin)
	return origins


func _ids() -> Array[int]:
	var ids: Array[int] = []
	for building in _sim.buildings.built:
		ids.append(building.id)
	return ids
