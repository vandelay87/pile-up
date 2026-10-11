extends GdUnitTestSuite

## A 48×48 open field with a 4×4 base at (12, 12): the base's grid is cells 2..25 on both axes.

const BASE := Rect2i(12, 12, 4, 4)
const SIZE := 48

var _settings: Settings
var _sim: Simulation
var _events: Array[String]


func before_test() -> void:
	_settings = Settings.load_file(Settings.DEFAULTS_PATH).settings
	var rows: Array[String] = []
	for y in SIZE:
		rows.append(".".repeat(SIZE))
	var edges: Array[String] = ["E"]
	_sim = Simulation.new(_settings, TestMaps.from_rows(rows, BASE, edges), 1)
	_sim.add_gold(1000 - _sim.run_state.gold)
	_events = []
	_sim.command_rejected.connect(func(reason: String) -> void: _events.append(reason))
	_sim.power_changed.connect(func() -> void: _events.append("power changed"))


func test_the_bases_grid_is_24_by_24_at_the_start() -> void:
	var on_grid := 0
	for y in SIZE:
		for x in SIZE:
			if _sim.power_grid.is_on_grid(Vector2i(x, y)):
				on_grid += 1

	assert_int(on_grid).is_equal(24 * 24)
	for cell: Vector2i in [Vector2i(2, 2), Vector2i(25, 2), Vector2i(2, 25), Vector2i(25, 25)]:
		assert_bool(_sim.power_grid.is_on_grid(cell)).is_true()
	for cell: Vector2i in [Vector2i(1, 2), Vector2i(26, 25), Vector2i(2, 26), Vector2i(25, 1)]:
		assert_bool(_sim.power_grid.is_on_grid(cell)).is_false()


func test_a_building_off_the_grid_is_rejected() -> void:
	_sim.queue_command(Commands.Build.new(Buildings.TOWER, Vector2i(30, 14)))
	_sim.queue_command(Commands.Build.new(Buildings.TOWER, Vector2i(25, 14)))
	_sim.queue_command(Commands.Build.new(Buildings.PYLON, Vector2i(26, 2)))
	_sim.tick()

	var off_grid := "build tower: off the power grid"
	assert_array(_events).contains_exactly([off_grid, off_grid, "build pylon: off the power grid"])
	assert_int(_sim.run_state.gold).is_equal(1000)
	assert_array(_sim.buildings.built).is_empty()


func test_a_pylon_at_the_grids_edge_extends_it() -> void:
	_sim.queue_command(Commands.Build.new(Buildings.PYLON, Vector2i(25, 13)))
	_sim.tick()

	assert_array(_events).contains_exactly(["power changed"])
	assert_int(_sim.run_state.gold).is_equal(1000 - 20)
	var pylon := _sim.buildings.built[0]
	assert_float(pylon.hp).is_equal(20.0)
	assert_bool(pylon.powered).is_true()
	assert_bool(_sim.power_grid.is_on_grid(Vector2i(35, 23))).is_true()
	assert_bool(_sim.power_grid.is_on_grid(Vector2i(36, 13))).is_false()
	assert_bool(_sim.power_grid.is_on_grid(Vector2i(35, 24))).is_false()

	_sim.queue_command(Commands.Build.new(Buildings.TOWER, Vector2i(30, 14)))
	_sim.tick()

	assert_array(_events).contains_exactly(["power changed", "power changed"])
	assert_bool(_sim.buildings.built[1].powered).is_true()


func test_destroying_a_pylon_unpowers_the_branch_beyond_it_which_stops_firing_but_stays() -> void:
	var branch := _build_branch()
	var tower := _sim.buildings.building(branch[2])
	var enemy := _sim.enemies.spawn(Vector2(44.5, 20.5), 1e6)
	_sim.tick()
	assert_float(_hp(enemy)).is_less(1e6)
	var cooldown := tower.cooldown
	_events.clear()

	_sim.structures.damage(Vector2i(25, 13), 1000.0)
	var hp_before := _hp(enemy)
	for tick in 60:
		_sim.tick()

	assert_array(_events).contains_exactly(["power changed"])
	assert_bool(_sim.power_grid.is_powered(branch[1])).is_false()
	assert_bool(_sim.power_grid.is_powered(branch[2])).is_false()
	assert_bool(tower.powered).is_false()
	assert_float(_hp(enemy)).is_equal(hp_before)
	assert_int(tower.cooldown).is_equal(cooldown)
	assert_float(tower.hp).is_equal(60.0)
	# Still a structure, so routing costs it and enemies attack it.
	assert_int(_sim.structures.structure_at(Vector2i(44, 13))).is_equal(Structures.Kind.BUILDING)
	assert_float(_sim.structures.bucketed_hp(Vector2i(44, 13))).is_equal(60.0)
	assert_bool(_sim.occupancy.is_occupied(Vector2i(44, 13))).is_true()
	assert_bool(_sim.power_grid.is_on_grid(Vector2i(25, 13))).is_true()
	assert_bool(_sim.power_grid.is_on_grid(Vector2i(26, 13))).is_false()


func test_building_a_new_link_repowers_the_branch_on_the_same_tick() -> void:
	var branch := _build_branch()
	_sim.structures.damage(Vector2i(25, 13), 1000.0)
	_sim.tick()
	var enemy := _sim.enemies.spawn(Vector2(44.5, 20.5), 1e6)
	_events.clear()

	_sim.queue_command(Commands.Build.new(Buildings.PYLON, Vector2i(25, 15)))
	_sim.tick()

	assert_array(_events).contains_exactly(["power changed"])
	assert_bool(_sim.power_grid.is_powered(branch[1])).is_true()
	assert_bool(_sim.power_grid.is_powered(branch[2])).is_true()
	assert_float(_hp(enemy)).is_less(1e6)


func test_an_unpowered_building_powers_nothing() -> void:
	_build_branch()
	_sim.structures.damage(Vector2i(25, 13), 1000.0)
	_sim.tick()
	_events.clear()

	# (47, 14) lies in the unpowered tower's power area only.
	_sim.queue_command(Commands.Build.new(Buildings.PYLON, Vector2i(47, 14)))
	_sim.tick()

	assert_bool(_sim.power_grid.is_on_grid(Vector2i(47, 14))).is_false()
	assert_array(_events).contains_exactly(["build pylon: off the power grid"])


func test_changing_a_power_area_setting_recomputes_the_grid() -> void:
	_sim.queue_command(Commands.SetSetting.new("run", "base_power_area", 11))
	_sim.tick()

	assert_bool(_sim.power_grid.is_on_grid(Vector2i(26, 26))).is_true()
	assert_array(_events).contains_exactly(["power changed"])


func test_changing_a_building_kinds_power_area_recomputes_the_grid() -> void:
	_sim.queue_command(Commands.Build.new(Buildings.PYLON, Vector2i(25, 13)))
	_sim.tick()
	assert_bool(_sim.power_grid.is_on_grid(Vector2i(37, 13))).is_false()
	_events.clear()

	_sim.queue_command(Commands.SetSetting.new("pylons", "power_area", 12))
	_sim.tick()

	assert_bool(_sim.power_grid.is_on_grid(Vector2i(37, 13))).is_true()
	assert_array(_events).contains_exactly(["power changed"])


# A pylon at the base grid's edge, a pylon at that one's edge, and a tower beyond it, all
# powered. Returns their ids in build order.
func _build_branch() -> Array[int]:
	_settings.change("enemies", "speed", 0.1)
	_sim.queue_command(Commands.Build.new(Buildings.PYLON, Vector2i(25, 13)))
	_sim.queue_command(Commands.Build.new(Buildings.PYLON, Vector2i(35, 13)))
	_sim.queue_command(Commands.Build.new(Buildings.TOWER, Vector2i(44, 13)))
	_sim.tick()
	assert_array(_events).contains_exactly(["power changed"])
	var ids: Array[int] = []
	for building in _sim.buildings.built:
		assert_bool(building.powered).is_true()
		ids.append(building.id)
	return ids


func _hp(id: int) -> float:
	return _sim.enemies.hp[_sim.enemies.index_of(id)]
