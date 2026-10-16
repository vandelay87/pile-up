extends GdUnitTestSuite

const SIZE := 40
const BASE := Rect2i(18, 18, 4, 4)
const ROCK := Rect2i(30, 10, 2, 20)
const CROWD := 200
const TICKS_TO_KILL := 600

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


func test_top_up_replaces_enemies_that_died() -> void:
	var sim := Simulation.new(_settings, _map(), 1)
	var crowd := BenchCrowd.new(sim, 1)
	crowd.top_up(CROWD)
	for t in TICKS_TO_KILL:
		sim.tick()
	assert_int(sim.enemies.count).is_less(CROWD)

	crowd.top_up(CROWD)

	assert_int(sim.enemies.count).is_equal(CROWD)


func test_the_same_seed_reaches_the_same_state() -> void:
	assert_int(BenchCrowd.digest(_run(7, 60))).is_equal(BenchCrowd.digest(_run(7, 60)))


func test_a_different_seed_reaches_a_different_state() -> void:
	assert_int(BenchCrowd.digest(_run(7, 60))).is_not_equal(BenchCrowd.digest(_run(8, 60)))


func test_soldiers_on_the_field_change_the_state() -> void:
	var with_soldiers := _run(7, 0)
	with_soldiers.queue_command(Commands.AddSoldiers.new(5))
	with_soldiers.tick()
	var without := _run(7, 0)
	without.tick()

	assert_int(BenchCrowd.digest(with_soldiers)).is_not_equal(BenchCrowd.digest(without))


func test_the_army_stands_in_and_around_the_ring_some_of_it_on_walls() -> void:
	var sim := Simulation.new(_settings, _map(), 1)
	var crowd := BenchCrowd.new(sim, 1)

	crowd.field_army()

	var soldiers := sim.soldiers
	assert_int(soldiers.count).is_equal(BenchCrowd.ARMY)
	var centre := Vector2(BASE.get_center())
	var on_walls := 0
	var spots := {}
	# Each soldier stands at its cell's centre, up to a cell from the point that picked the cell.
	var inner := BenchCrowd.ARMY_INNER_RADIUS - 1.0
	var outer := BenchCrowd.ARMY_OUTER_RADIUS + 1.0
	for i in soldiers.count:
		assert_float(soldiers.positions[i].distance_to(centre)).is_between(inner, outer)
		if soldiers.elevation(i) == Piles.WALL_LEVEL:
			on_walls += 1
		spots[soldiers.spot(i)] = true
	assert_int(on_walls).is_greater(0)
	assert_int(on_walls).is_less(BenchCrowd.ARMY)
	assert_int(spots.size()).is_equal(BenchCrowd.ARMY)


func test_every_order_interval_ten_soldiers_are_sent_across_the_ring() -> void:
	var sim := Simulation.new(_settings, _map(), 1)
	var crowd := BenchCrowd.new(sim, 1)
	crowd.field_army()
	var walking := []
	for t in 2 * BenchCrowd.ORDER_INTERVAL:
		crowd.send_army(t)
		sim.tick()
		if t % BenchCrowd.ORDER_INTERVAL == 0:
			walking.append(_walking(sim))

	assert_array(walking).is_equal([BenchCrowd.ORDER_GROUP, 2 * BenchCrowd.ORDER_GROUP])


func test_the_same_seed_with_the_army_reaches_the_same_state() -> void:
	assert_int(BenchCrowd.digest(_run_with_army(7, 300))).is_equal(
		BenchCrowd.digest(_run_with_army(7, 300))
	)


func _run_with_army(crowd_seed: int, ticks: int) -> Simulation:
	var sim := Simulation.new(_settings, _map(), 1)
	var crowd := BenchCrowd.new(sim, crowd_seed)
	crowd.field_army()
	for t in ticks:
		crowd.top_up(CROWD)
		crowd.send_army(t)
		sim.tick()
	return sim


func _walking(sim: Simulation) -> int:
	var walking := 0
	for i in sim.soldiers.count:
		if sim.soldiers.orders[i] != Soldiers.NONE:
			walking += 1
	return walking
