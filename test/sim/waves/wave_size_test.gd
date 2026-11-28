extends GdUnitTestSuite

# A wave's size is fixed as it starts: round(20 × 1.25^(threat − 1) × the pace's factor × roll),
# at least 1 and uncapped, where the factor is ×0.7 at Low, ×1 at Medium, ×1.4 at High and ×1
# dry, and the roll is uniform within ±15%, seeded by the run and the wave's index. HP is flat.

const EDGES: Array[String] = ["N", "S"]

var _settings: Settings
var _sizes: Array[int]


func before_test() -> void:
	_settings = Settings.load_file(Settings.DEFAULTS_PATH).settings
	TestWaves.without_trickle(_settings)


func test_with_the_roll_off_the_size_follows_threat_and_has_no_cap() -> void:
	var waves := _sim().waves
	_settings.change("waves", "size_roll", 0)

	assert_int(waves.size_for(1.0, 1.0, 0)).is_equal(20)
	assert_int(waves.size_for(2.0, 1.0, 0)).is_equal(25)
	# Continuous: 20 × 1.25^1.5 = 27.95.
	assert_int(waves.size_for(2.5, 1.0, 0)).is_equal(28)
	assert_int(waves.size_for(10.0, 1.0, 0)).is_equal(149)
	assert_int(waves.size_for(20.0, 1.0, 0)).is_equal(1388)
	assert_int(waves.size_for(30.0, 1.0, 0)).is_equal(12925)
	assert_int(waves.size_for(1.0, 0.01, 0)).is_equal(1)


func test_each_pace_sizes_the_wave_it_starts() -> void:
	var sizes := {
		Miners.Pace.OFF: 20, Miners.Pace.LOW: 14, Miners.Pace.MEDIUM: 20, Miners.Pace.HIGH: 28
	}
	for pace: Miners.Pace in sizes:
		var sim := _sim()
		sim.settings.change("waves", "size_roll", 0)
		sim.queue_command(Commands.SetPace.new(pace))
		sim.queue_command(Commands.SendWave.new())
		sim.tick()

		var expected: int = sizes[pace]
		(
			assert_int(_sizes.back())
			. override_failure_message(str(Miners.Pace.find_key(pace)))
			. is_equal(expected)
		)


func test_dry_the_wave_takes_the_dry_size_whatever_the_pace() -> void:
	# 4 minerals at 3.2 a second run dry in 75 ticks.
	var sim := _sim(Vector2i(3, 1))
	sim.settings.change("waves", "size_roll", 0)
	sim.settings.change("waves", "dry_size", 1.5)
	sim.queue_command(Commands.SetPace.new(Miners.Pace.HIGH))
	for tick in 75:
		sim.tick()
	assert_bool(sim.miners.all_dry()).is_true()

	sim.queue_command(Commands.SendWave.new())
	sim.tick()

	assert_int(_sizes.back()).is_equal(30)


func test_the_roll_stays_within_15_percent_and_varies_by_wave() -> void:
	var waves := _sim().waves
	var seen := {}

	for index in 200:
		var size := waves.size_for(1.0, 1.0, index)
		assert_int(size).is_between(17, 23)
		seen[size] = true

	assert_int(seen.size()).is_greater(4)


func test_a_waves_size_replays_by_run_seed_and_index() -> void:
	var sizes := _sizes_for(_sim(Vector2i(4200, 1400), 7))

	assert_array(_sizes_for(_sim(Vector2i(4200, 1400), 7))).is_equal(sizes)
	assert_array(_sizes_for(_sim(Vector2i(4200, 1400), 8))).is_not_equal(sizes)


func test_hp_is_flat_whatever_the_threat() -> void:
	var sim := _sim()
	TestWaves.send_at(sim, 15.0)

	assert_int(sim.enemies.count).is_greater(0)
	for i in sim.enemies.count:
		if sim.enemies.kinds[i] in [Enemies.Kind.NORMAL, Enemies.Kind.JUMPER]:
			assert_float(sim.enemies.hp[i]).is_equal(10.0)
	assert_float(sim.waves.enemy_hp(15.0, Enemies.Kind.BLOATER)).is_equal(30.0)
	assert_float(sim.waves.enemy_hp(15.0, Enemies.Kind.BRUTE)).is_equal(40.0)


func test_a_waves_size_doesnt_change_when_the_pace_does() -> void:
	var sim := _sim()
	sim.settings.change("waves", "size_roll", 0)
	sim.queue_command(Commands.SetPace.new(Miners.Pace.HIGH))
	sim.queue_command(Commands.SendWave.new())
	sim.tick()

	sim.queue_command(Commands.SetPace.new(Miners.Pace.LOW))
	sim.tick()

	assert_int(sim.waves.open_size).is_equal(28)


# Waves 0 to 19's sizes at threat 10, Medium.
func _sizes_for(sim: Simulation) -> Array[int]:
	var sizes: Array[int] = []
	for index in 20:
		sizes.append(sim.waves.size_for(10.0, 1.0, index))
	return sizes


func _sim(base_deposit := Vector2i(4200, 1400), run_seed := 1) -> Simulation:
	var rows: Array[String] = []
	for y in 8:
		rows.append("........")
	var map := TestMaps.from_rows(rows, Rect2i(3, 3, 2, 2), EDGES, [], base_deposit)
	var sim := Simulation.new(_settings, map, run_seed)
	_sizes = []
	sim.wave_started.connect(
		func(_edges: PackedStringArray, size: int, _specials: Dictionary) -> void:
			_sizes.append(size)
	)
	return sim
