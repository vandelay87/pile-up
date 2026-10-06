extends GdUnitTestSuite

const TICKS := 120


func test_the_same_seed_gives_identical_positions_after_n_ticks() -> void:
	var first := _run(7)
	var second := _run(7)

	assert_int(first.size()).is_equal(40)
	assert_array(Array(second)).is_equal(Array(first))


func test_a_different_seed_gives_different_positions() -> void:
	assert_array(Array(_run(8))).is_not_equal(Array(_run(7)))


func _run(run_seed: int) -> PackedVector2Array:
	var settings := Settings.load_file(Settings.DEFAULTS_PATH).settings
	var rows: Array[String] = []
	for y in 16:
		rows.append("................")
	var edges: Array[String] = ["N", "E", "S", "W"]
	var map := TestMaps.from_rows(rows, Rect2i(7, 7, 2, 2), edges)
	var sim := Simulation.new(settings, map, run_seed)
	sim.queue_command(Commands.SpawnBurst.new(40))
	for tick in TICKS:
		sim.tick()
	return sim.enemies.positions.slice(0, sim.enemies.count)
