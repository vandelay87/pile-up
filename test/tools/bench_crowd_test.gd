extends GdUnitTestSuite

const SIZE := 40
const BASE := Rect2i(18, 18, 4, 4)
const ROCK := Rect2i(30, 10, 2, 20)
const CROWD := 200
const TICKS_TO_LEAK := 600

var _settings: Settings


func before_test() -> void:
	_settings = Settings.load_file(Settings.DEFAULTS_PATH).settings


func _map() -> MapData:
	var rows: Array[String] = []
	for y in SIZE:
		var row := ""
		for x in SIZE:
			row += MapData.ROCK if ROCK.has_point(Vector2i(x, y)) else MapData.CLEAR
		rows.append(row)
	return TestMaps.from_rows(rows, BASE)


func _run(crowd_seed: int, ticks: int) -> Simulation:
	var sim := Simulation.new(_settings, _map(), 1)
	var crowd := BenchCrowd.new(sim, crowd_seed)
	for t in ticks:
		crowd.top_up(CROWD)
		sim.tick()
	return sim


func test_top_up_fills_the_crowd_to_the_target() -> void:
	var sim := Simulation.new(_settings, _map(), 1)
	var crowd := BenchCrowd.new(sim, 1)

	crowd.top_up(150)

	assert_int(sim.enemies.count).is_equal(150)


func test_top_up_spawns_on_clear_cells_in_a_ring_around_the_base() -> void:
	var sim := Simulation.new(_settings, _map(), 1)
	var crowd := BenchCrowd.new(sim, 1)

	crowd.top_up(500)

	var centre := Vector2(BASE.get_center())
	for i in sim.enemies.count:
		var pos := sim.enemies.positions[i]
		var cell := Vector2i(pos.floor())
		assert_bool(sim.map.is_rock(cell) or sim.map.is_base(cell)).is_false()
		var distance := pos.distance_to(centre)
		assert_float(distance).is_between(BenchCrowd.INNER_RADIUS, BenchCrowd.OUTER_RADIUS)


func test_top_up_replaces_enemies_that_leaked() -> void:
	var sim := Simulation.new(_settings, _map(), 1)
	var crowd := BenchCrowd.new(sim, 1)
	crowd.top_up(CROWD)
	for t in TICKS_TO_LEAK:
		sim.tick()
	assert_int(sim.enemies.count).is_less(CROWD)

	crowd.top_up(CROWD)

	assert_int(sim.enemies.count).is_equal(CROWD)


func test_the_same_seed_reaches_the_same_state() -> void:
	assert_int(BenchCrowd.digest(_run(7, 60))).is_equal(BenchCrowd.digest(_run(7, 60)))


func test_a_different_seed_reaches_a_different_state() -> void:
	assert_int(BenchCrowd.digest(_run(7, 60))).is_not_equal(BenchCrowd.digest(_run(8, 60)))
