extends GdUnitTestSuite

const EDGES: Array[String] = ["N", "E", "S", "W"]

var _settings: Settings
var _map: MapData
var _enemies: Enemies


func before_test() -> void:
	_settings = Settings.load_file(Settings.DEFAULTS_PATH).settings
	TestWaves.without_trickle(_settings)
	_settings.change("waves", "size_roll", 0)
	var rows: Array[String] = []
	for y in 16:
		rows.append("................")
	_map = TestMaps.from_rows(rows, Rect2i(7, 7, 2, 2), EDGES)
	var systems := TestSystems.new(_settings, _map)
	_enemies = systems.enemies(systems.routing(), _rng(1))


func _waves(run_seed: int = 1) -> Waves:
	return Waves.new(_settings, _map, _enemies, _rng(run_seed), run_seed)


func _rng(run_seed: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = run_seed
	return rng


func _threat(value: float) -> Threat:
	var threat := Threat.new(_settings)
	threat.value = value
	return threat


func test_edge_picks_are_deterministic_per_seed() -> void:
	assert_array(_edge_picks(7)).is_equal(_edge_picks(7))
	assert_array(_edge_picks(8)).is_not_equal(_edge_picks(7))


func test_a_wave_spawns_exactly_its_size() -> void:
	var waves := _waves()
	var threat := _threat(1.0)
	waves.send_wave()

	for tick in 10 * Simulation.TICKS_PER_SECOND:
		waves.step(Miners.Pace.OFF, threat, false)

	assert_int(_enemies.count).is_equal(20)


func test_the_wave_ends_only_when_all_have_spawned_and_been_killed() -> void:
	var waves := _waves()
	var threat := _threat(1.0)
	waves.send_wave()
	waves.step(Miners.Pace.OFF, threat, false)
	assert_int(waves.phase).is_equal(Waves.Phase.WAVE)

	_kill_all(waves)
	assert_bool(waves.check_end()).is_false()
	assert_int(waves.phase).is_equal(Waves.Phase.WAVE)

	for tick in 10 * Simulation.TICKS_PER_SECOND:
		waves.step(Miners.Pace.OFF, threat, false)
	assert_bool(waves.check_end()).is_false()

	_kill_all(waves)
	assert_bool(waves.check_end()).is_true()
	assert_int(waves.phase).is_equal(Waves.Phase.QUIET)


func test_a_waves_enemies_push_through_once_it_is_in_its_tail() -> void:
	var waves := _waves()
	var threat := _threat(3.0)
	waves.send_wave()
	for tick in 20 * Simulation.TICKS_PER_SECOND:
		waves.step(Miners.Pace.OFF, threat, false)
	# 31 enemies at threat 3; the tail is the last 10 + 2 × 3 = 16.
	assert_int(waves.enemies_left).is_equal(31)
	assert_array(Array(waves.tail_mask())).is_equal([1, 0])

	for k in 15:
		_enemies.hp[k] = 0.0
	waves.record_kills(_enemies.remove_dead())

	assert_int(waves.enemies_left).is_equal(16)
	assert_array(Array(waves.tail_mask())).is_equal([1, 1])


# The first edge of each of 20 waves, one after another.
func _edge_picks(run_seed: int) -> Array[PackedStringArray]:
	var waves := _waves(run_seed)
	var threat := _threat(1.0)
	var picks: Array[PackedStringArray] = []
	for wave in 20:
		waves.send_wave()
		waves.step(Miners.Pace.OFF, threat, false)
		picks.append(waves.open_waves()[0].edges)
		for tick in 10 * Simulation.TICKS_PER_SECOND:
			waves.step(Miners.Pace.OFF, threat, false)
		_kill_all(waves)
		waves.check_end()
	return picks


func _kill_all(waves: Waves) -> void:
	for k in _enemies.count:
		_enemies.hp[k] = 0.0
	waves.record_kills(_enemies.remove_dead())
