extends GdUnitTestSuite

## A 24×24 open field with a 4×4 base at (10, 10), centred on (12, 12); the base powers cells
## 0..23. The barracks at (15, 10) powers x 12..19, y 7..14.

const BASE := Rect2i(10, 10, 4, 4)
const SIZE := 24
const BARRACKS := Vector2i(15, 10)

var _sim: Simulation
var _rejections: Array[String]


func before_test() -> void:
	var settings := Settings.load_file(Settings.DEFAULTS_PATH).settings
	settings.change("waves", "wave_1_size", 1)
	settings = settings.for_next_run()
	settings.change("enemies", "speed", 0.1)
	var rows: Array[String] = []
	for y in SIZE:
		rows.append(".".repeat(SIZE))
	var edges: Array[String] = ["E"]
	_sim = Simulation.new(settings, TestMaps.from_rows(rows, BASE, edges), 1)
	_sim.add_gold(10000 - _sim.run_state.gold)
	_rejections = []
	_sim.command_rejected.connect(func(reason: String) -> void: _rejections.append(reason))


func test_reads_the_soldier_and_barracks_starting_numbers() -> void:
	var settings := Settings.load_file(Settings.DEFAULTS_PATH).settings

	assert_float(settings.soldier_hp).is_equal_approx(45.0, 1e-6)
	assert_float(settings.soldier_speed).is_equal_approx(2.5, 1e-6)
	assert_int(settings.soldier_cost).is_equal(30)
	assert_int(settings.training_ticks).is_equal(300)
	assert_float(settings.value("soldiers", "damage")).is_equal_approx(2.0, 1e-6)
	assert_float(settings.value("soldiers", "fire_rate")).is_equal_approx(2.0, 1e-6)
	assert_float(settings.value("soldiers", "range")).is_equal_approx(4.0, 1e-6)
	assert_float(settings.value("soldiers", "range_per_level")).is_equal_approx(0.5, 1e-6)
	assert_int(settings.value("soldiers", "wall_climb_slow")).is_equal(75)
	assert_float(settings.value("soldiers", "mass")).is_equal_approx(5.0, 1e-6)
	assert_float(settings.value("barracks", "hp")).is_equal_approx(100.0, 1e-6)
	assert_int(settings.value("barracks", "cost")).is_equal(200)
	assert_int(settings.value("barracks", "power_area")).is_equal(3)
	assert_int(settings.barracks_capacity).is_equal(10)
	assert_int(settings.barracks_limit).is_equal(5)


func test_barracks_capacity_and_limit_wait_for_a_restart() -> void:
	var settings := Settings.load_file(Settings.DEFAULTS_PATH).settings
	settings.change("barracks", "capacity", 20)
	settings.change("barracks", "limit", 2)

	assert_int(settings.barracks_capacity).is_equal(10)
	assert_int(settings.barracks_limit).is_equal(5)
	assert_int(settings.for_next_run().barracks_capacity).is_equal(20)
	assert_int(settings.for_next_run().barracks_limit).is_equal(2)


func test_a_barracks_is_a_two_by_two_building_with_its_hp_cost_and_power_area() -> void:
	var barracks := _build(BARRACKS)

	assert_object(barracks).is_not_null()
	assert_array(barracks.footprint).contains_exactly(
		[Vector2i(15, 10), Vector2i(16, 10), Vector2i(15, 11), Vector2i(16, 11)]
	)
	assert_float(barracks.hp).is_equal(100.0)
	assert_int(_sim.run_state.gold).is_equal(9800)
	assert_bool(barracks.powered).is_true()
	assert_object(_sim.power_grid.area_of(Buildings.BARRACKS, BARRACKS)).is_equal(
		Rect2i(12, 7, 8, 8)
	)


func test_the_barracks_power_area_setting_recomputes_power() -> void:
	_build(BARRACKS)
	var pylon := _build_kind(Buildings.PYLON, Vector2i(20, 10))
	# The base now powers x 8..15 and the barracks x 12..19, one cell short of the pylon.
	_sim.queue_command(Commands.SetSetting.new("run", "base_power_area", 2))
	_sim.tick()
	assert_bool(pylon.powered).is_false()

	_sim.queue_command(Commands.SetSetting.new("barracks", "power_area", 4))
	_sim.tick()
	assert_bool(pylon.powered).is_true()


func test_the_limit_refuses_a_sixth_barracks_and_frees_a_place_when_one_is_destroyed() -> void:
	var first := _build(Vector2i(2, 2))
	for x: int in [5, 8, 15, 18]:
		_build(Vector2i(x, 2))
	_build(Vector2i(2, 18))

	assert_array(_rejections).contains_exactly(["build barracks: barracks limit reached"])
	assert_object(_building_at(Vector2i(2, 18))).is_null()

	_sim.buildings.damage(first.id, 1000.0)
	_sim.tick()
	_build(Vector2i(2, 18))
	assert_object(_building_at(Vector2i(2, 18))).is_not_null()


func test_the_limit_is_checked_after_placement_and_before_gold() -> void:
	for x: int in [2, 5, 8, 15, 18]:
		_build(Vector2i(x, 2))
	_sim.add_gold(-_sim.run_state.gold)
	_build(Vector2i(10, 10))
	_build(Vector2i(2, 18))

	assert_array(_rejections).contains_exactly(
		["build barracks: occupied", "build barracks: barracks limit reached"]
	)


func test_unpowered_barracks_count_towards_capacity() -> void:
	_build(BARRACKS)
	_sim.queue_command(Commands.SetSetting.new("run", "base_power_area", 0))
	_sim.tick()

	assert_int(_sim.barracks.capacity()).is_equal(10)


func _build(origin: Vector2i) -> Buildings.Building:
	return _build_kind(Buildings.BARRACKS, origin)


func _build_kind(kind: StringName, origin: Vector2i) -> Buildings.Building:
	_sim.queue_command(Commands.Build.new(kind, origin))
	_sim.tick()
	return _building_at(origin)


func _building_at(cell: Vector2i) -> Buildings.Building:
	return _sim.buildings.building(_sim.occupancy.building_at(cell))
