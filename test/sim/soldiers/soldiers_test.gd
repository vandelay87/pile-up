extends GdUnitTestSuite

# An 8×8 open field with a 2×2 base at (3, 3), centred on (4, 4). The base's ring is the 12
# cells around it: the 8 beside its sides are nearest its centre, then the 4 corners.

var _sim: Simulation


func before_test() -> void:
	_sim = _field_sim([])


func test_added_soldiers_stand_on_the_ring_cells_nearest_the_base_lowest_index_first() -> void:
	_sim.queue_command(Commands.AddSoldiers.new(3))
	_sim.tick()

	assert_array(_spots()).contains_exactly([Vector2i(3, 2), Vector2i(4, 2), Vector2i(2, 3)])
	assert_array(Array(_positions())).contains_exactly(
		[Vector2(3.5, 2.5), Vector2(4.5, 2.5), Vector2(2.5, 3.5)]
	)


func test_soldiers_never_stand_on_rock_the_base_or_a_building() -> void:
	_sim = _field_sim([Vector2i(3, 2)])
	_sim.queue_command(Commands.Build.new(Buildings.PYLON, Vector2i(4, 2)))
	_sim.queue_command(Commands.AddSoldiers.new(1))
	_sim.tick()

	assert_array(_spots()).contains_exactly([Vector2i(2, 3)])


func test_once_the_ring_is_full_soldiers_spread_outwards_never_sharing_a_spot() -> void:
	_sim.queue_command(Commands.AddSoldiers.new(12))
	_sim.queue_command(Commands.AddSoldiers.new(2))
	_sim.tick()

	var spots := _spots()
	assert_int(spots.size()).is_equal(14)
	for spot: Vector2i in spots.slice(0, 12):
		assert_bool(Rect2i(2, 2, 4, 4).has_point(spot)).is_true()
	assert_array(spots.slice(12)).contains_exactly([Vector2i(3, 1), Vector2i(4, 1)])
	var unique := {}
	for spot: Vector2i in spots:
		unique[spot] = true
	assert_int(unique.size()).is_equal(14)


func test_added_soldiers_are_reported_at_the_end_of_the_tick() -> void:
	var reported: Array[PackedInt32Array] = []
	_sim.soldiers_added.connect(func(ids: PackedInt32Array) -> void: reported.append(ids))
	_sim.queue_command(Commands.AddSoldiers.new(2))
	_sim.tick()
	_sim.tick()

	assert_int(reported.size()).is_equal(1)
	assert_array(Array(reported[0])).is_equal(Array(_sim.soldiers.ids.slice(0, 2)))


func test_adding_fewer_than_one_soldier_is_rejected() -> void:
	var rejections: Array[String] = []
	_sim.command_rejected.connect(func(reason: String) -> void: rejections.append(reason))
	_sim.queue_command(Commands.AddSoldiers.new(0))
	_sim.tick()

	assert_array(rejections).contains_exactly(["add soldiers: the count must be at least 1"])
	assert_int(_sim.soldiers.count).is_equal(0)


func test_killer_ids_from_buildings_and_soldiers_never_collide() -> void:
	_sim.queue_command(Commands.Build.new(Buildings.PYLON, Vector2i(0, 0)))
	_sim.queue_command(Commands.AddSoldiers.new(2))
	_sim.queue_command(Commands.Build.new(Buildings.PYLON, Vector2i(7, 7)))
	_sim.tick()

	var killers := {}
	for building in _sim.buildings.built:
		killers[building.id] = true
	for id in _sim.soldiers.ids.slice(0, _sim.soldiers.count):
		killers[id] = true
	assert_int(killers.size()).is_equal(4)


func test_a_soldier_displaced_a_little_walks_back_to_its_spot_at_its_speed() -> void:
	_add_one_and_tick()
	_sim.soldiers.positions[0] = Vector2(4.0, 2.5)

	_sim.tick()
	assert_float(_sim.soldiers.positions[0].x).is_equal_approx(4.0 - 2.5 / 60.0, 1e-5)

	for tick in 30:
		_sim.tick()
	assert_float(_sim.soldiers.positions[0].distance_to(Vector2(3.5, 2.5))).is_less_equal(0.1)


func test_a_soldier_nudged_within_a_tenth_of_a_cell_stays_put() -> void:
	_add_one_and_tick()
	_sim.soldiers.positions[0] = Vector2(3.55, 2.5)

	_sim.tick()

	assert_vector(_sim.soldiers.positions[0]).is_equal(Vector2(3.55, 2.5))


func test_a_soldier_pushed_into_rock_is_put_back_out_at_its_body_radius() -> void:
	_sim = _field_sim([Vector2i(3, 1)])
	_add_one_and_tick()
	_sim.soldiers.positions[0] = Vector2(3.5, 1.9)

	_sim.tick()

	assert_float(_sim.soldiers.positions[0].y).is_equal_approx(2.3, 1e-4)


func test_a_soldier_pushed_against_the_base_is_held_off_it_at_its_body_radius() -> void:
	_add_one_and_tick()
	_sim.soldiers.positions[0] = Vector2(3.5, 2.9)

	_sim.tick()

	assert_float(_sim.soldiers.positions[0].y).is_equal_approx(2.7, 1e-4)


func test_walls_are_not_solid_to_soldiers() -> void:
	_add_one_and_tick()
	_land_bodies(Vector2i(3, 1), Piles.WALL_LEVEL)
	_sim.soldiers.positions[0] = Vector2(3.5, 1.9)

	_sim.tick()

	assert_float(_sim.soldiers.positions[0].y).is_equal_approx(1.9 + 2.5 / 60.0, 1e-4)


func test_a_pile_landing_under_a_soldier_raises_its_elevation() -> void:
	_add_one_and_tick()
	assert_int(_sim.soldiers.elevation(0)).is_equal(0)

	_land_bodies(Vector2i(3, 2), 2)

	assert_int(_sim.soldiers.elevation(0)).is_equal(2)


func test_a_soldier_on_a_wall_stands_at_elevation_5() -> void:
	_add_one_and_tick()

	_land_bodies(Vector2i(3, 2), Piles.WALL_LEVEL)

	assert_int(_sim.soldiers.elevation(0)).is_equal(5)


# Lands [param level] bodies on [param cell] at step 1 of the next tick.
func _land_bodies(cell: Vector2i, level: int) -> void:
	var bodies := PackedVector2Array()
	for n in level:
		bodies.append(Vector2(cell) + Vector2(0.5, 0.5))
	_sim.piles.queue_bodies(Deaths.bodies_at(bodies))
	_sim.tick()
	assert_int(_sim.piles.level(cell)).is_equal(level)


func _add_one_and_tick() -> void:
	_sim.queue_command(Commands.AddSoldiers.new(1))
	_sim.tick()
	assert_array(_spots()).contains_exactly([Vector2i(3, 2)])


func _field_sim(rock: Array[Vector2i]) -> Simulation:
	var rows: Array[String] = []
	for y in 8:
		var row := ""
		for x in 8:
			row += "#" if Vector2i(x, y) in rock else "."
		rows.append(row)
	var map := TestMaps.from_rows(rows, Rect2i(3, 3, 2, 2))
	return Simulation.new(Settings.load_file(Settings.DEFAULTS_PATH).settings, map)


func _spots() -> Array[Vector2i]:
	var spots: Array[Vector2i] = []
	for i in _sim.soldiers.count:
		spots.append(_sim.soldiers.spot(i))
	return spots


func _positions() -> PackedVector2Array:
	return _sim.soldiers.positions.slice(0, _sim.soldiers.count)
