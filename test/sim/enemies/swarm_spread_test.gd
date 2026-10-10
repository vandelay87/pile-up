extends GdUnitTestSuite

const WAVE_SIZE := 160

var _settings: Settings


func before_test() -> void:
	_settings = Settings.load_file(Settings.DEFAULTS_PATH).settings
	_settings.change("enemies", "speed", 0.1)


func test_enemies_spawn_in_bursts_of_the_clump_size() -> void:
	_settings.change("waves", "wave_1_size", WAVE_SIZE)
	var sim := _start_wave(_open_field())
	var counts := PackedInt32Array([sim.enemies.count])

	while sim.enemies.count < WAVE_SIZE:
		sim.tick()
		counts.append(sim.enemies.count)

	for t in range(1, counts.size()):
		assert_int(counts[t] - counts[t - 1]).is_in([0, 16])


func test_bursts_keep_the_average_spawn_rate_over_a_wave() -> void:
	_settings.change("waves", "wave_1_size", WAVE_SIZE)
	var sim := _start_wave(_open_field())
	var ticks := 0

	while sim.enemies.count < WAVE_SIZE:
		sim.tick()
		ticks += 1

	# Bursts of 16 at 10 per second come 1.6 s (96 ticks) apart: the first lands as the
	# wave starts, so the tenth and last lands 9 gaps later, 14.4 s in.
	assert_int(ticks).is_between(9 * 96 - 2, 9 * 96 + 2)


func test_each_enemy_rolls_a_pace_within_the_speed_variety() -> void:
	var sim := _start_wave(_open_field())
	assert_int(sim.enemies.count).is_equal(16)
	var paces := {}

	for i in sim.enemies.count:
		var pace := sim.enemies.pace(i)
		assert_float(pace).is_between(0.97, 1.03)
		paces[pace] = true

	assert_int(paces.size()).is_equal(16)


func test_with_the_swarm_spread_off_a_lone_enemy_walks_straight_at_its_speed() -> void:
	_switch_swarm_spread_off()
	var sim := _start_wave(_corridor())
	var start := sim.enemies.positions[0]

	for tick in 2 * Simulation.TICKS_PER_SECOND:
		sim.tick()

	assert_vector(sim.enemies.positions[0] - start).is_equal_approx(
		Vector2(0.2, 0.0), Vector2(1e-4, 1e-4)
	)


func test_pace_changes_how_far_a_lone_enemy_walks() -> void:
	_switch_swarm_spread_off()
	_settings.change("enemies", "speed_variety", 50)
	var sim := _start_wave(_corridor())
	var start := sim.enemies.positions[0]

	for tick in 2 * Simulation.TICKS_PER_SECOND:
		sim.tick()

	var walked := sim.enemies.positions[0].x - start.x
	assert_float(absf(walked - 0.2)).is_greater(1e-3)
	assert_float(walked).is_equal_approx(0.2 * sim.enemies.pace(0), 1e-4)


func test_wander_weaves_a_lone_enemy_off_its_heading() -> void:
	_switch_swarm_spread_off()
	_settings.change("enemies", "wander", 30.0)
	var sim := _start_wave(_corridor())
	var start := sim.enemies.positions[0]

	for tick in Simulation.TICKS_PER_SECOND:
		sim.tick()

	assert_float(absf(sim.enemies.positions[0].y - start.y)).is_greater(1e-3)


func test_personal_space_holds_neighbours_wider_than_the_collision_spacing() -> void:
	assert_float(_gap_after_spawning_two(0.0)).is_less(0.62)
	assert_float(_gap_after_spawning_two(0.7)).is_greater(0.65)


func _gap_after_spawning_two(personal_space: float) -> float:
	_switch_swarm_spread_off()
	_settings.change("enemies", "personal_space_radius", personal_space)
	_settings.change("waves", "wave_1_size", 2)
	_settings.change("waves", "clump_size", 2)
	var rows: Array[String] = [".".repeat(40)]
	var edges: Array[String] = ["W"]
	var sim := _start_wave(TestMaps.from_rows(rows, Rect2i(39, 0, 1, 1), edges))

	for tick in 4 * Simulation.TICKS_PER_SECOND:
		sim.tick()

	return sim.enemies.positions[0].distance_to(sim.enemies.positions[1])


func _switch_swarm_spread_off() -> void:
	_settings.change("enemies", "heading_offset", 0.0)
	_settings.change("enemies", "speed_variety", 0)
	_settings.change("enemies", "wander", 0.0)
	_settings.change("enemies", "personal_space_radius", 0.0)
	_settings.change("waves", "wave_1_size", 1)
	_settings.change("waves", "clump_size", 1)


func _corridor() -> MapData:
	var rows: Array[String] = []
	for y in 5:
		rows.append(".".repeat(40))
	var edges: Array[String] = ["W"]
	return TestMaps.from_rows(rows, Rect2i(36, 0, 4, 5), edges)


func _start_wave(map: MapData, run_seed: int = 1) -> Simulation:
	var sim := Simulation.new(_settings.for_next_run(), map, run_seed)
	sim.queue_command(Commands.NextWave.new())
	sim.tick()
	return sim


func _open_field() -> MapData:
	var rows: Array[String] = []
	for y in 40:
		rows.append(".".repeat(40))
	var edges: Array[String] = ["N", "E", "S", "W"]
	return TestMaps.from_rows(rows, Rect2i(18, 18, 4, 4), edges)
