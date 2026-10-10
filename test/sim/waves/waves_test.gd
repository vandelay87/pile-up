extends GdUnitTestSuite

const EDGES: Array[String] = ["N", "E", "S", "W"]
const PICKS := 200

var _settings: Settings
var _map: MapData
var _enemies: Enemies


func before_test() -> void:
	_settings = Settings.load_file(Settings.DEFAULTS_PATH).settings
	var rows: Array[String] = []
	for y in 16:
		rows.append("................")
	_map = TestMaps.from_rows(rows, Rect2i(7, 7, 2, 2), EDGES)
	var occupancy := Occupancy.new(_map.width, _map.height)
	var piles := Piles.new(_settings, _map, occupancy)
	var routing := Routing.new(_settings, _map, occupancy, piles)
	_enemies = Enemies.new(_settings, _map, occupancy, piles, routing, _rng(1))


func _waves(run_seed: int = 1) -> Waves:
	return Waves.new(_settings, _map, _enemies, _rng(run_seed))


func _rng(run_seed: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = run_seed
	return rng


func test_wave_size_and_hp_follow_the_growth_formulas() -> void:
	var waves := _waves()

	assert_int(waves.size(1)).is_equal(20)
	assert_int(waves.size(2)).is_equal(26)
	assert_int(waves.size(20)).is_equal(2924)
	assert_float(waves.enemy_hp(1)).is_equal_approx(10.0, 1e-6)
	assert_float(waves.enemy_hp(20)).is_equal_approx(10.0 * pow(1.05, 19), 1e-4)


func test_each_wave_picks_1_or_2_distinct_spawn_edges_of_the_map() -> void:
	var waves := _waves()
	var counts := {}

	for wave in PICKS:
		waves.start(1)
		var edges := waves.edges
		counts[edges.size()] = counts.get(edges.size(), 0) + 1
		assert_int(edges.size()).is_between(1, 2)
		for edge in edges:
			assert_array(EDGES).contains([edge])
		if edges.size() == 2:
			assert_str(edges[0]).is_not_equal(edges[1])

	assert_array(counts.keys()).contains_exactly_in_any_order([1, 2])


func test_edge_picks_are_deterministic_per_seed() -> void:
	assert_array(_edge_picks(7)).is_equal(_edge_picks(7))
	assert_array(_edge_picks(8)).is_not_equal(_edge_picks(7))


func test_second_edge_chance_sets_how_often_a_wave_uses_2_edges() -> void:
	for chance: int in [0, 100]:
		_settings.change("waves", "second_edge_chance", chance)
		var waves := _waves()
		for wave in 20:
			waves.start(1)
			assert_int(waves.edges.size()).is_equal(1 if chance == 0 else 2)


func test_a_clump_size_of_1_spawns_a_trickle_at_the_spawn_rate_over_the_edges() -> void:
	_settings.change("waves", "clump_size", 1)
	_settings.change("waves", "second_edge_chance", 100)
	var waves := _waves()
	waves.start(1)

	for tick in Simulation.TICKS_PER_SECOND:
		waves.spawn()

	assert_int(_enemies.count).is_equal(10)
	for k in _enemies.count:
		var edge := waves.edges[k % 2]
		var cell := Vector2i(_enemies.positions[k].floor())
		assert_array(_map.spawn_cells(edge)).contains([cell])


func test_enemies_spawn_with_the_wave_hp() -> void:
	var waves := _waves()
	waves.start(20)

	waves.spawn()

	assert_float(_enemies.hp[0]).is_equal_approx(waves.enemy_hp(20), 1e-4)


func test_a_wave_spawns_exactly_its_size() -> void:
	var waves := _waves()
	waves.start(1)

	for tick in 10 * Simulation.TICKS_PER_SECOND:
		waves.spawn()

	assert_int(_enemies.count).is_equal(20)


func test_the_wave_ends_only_when_all_have_spawned_and_none_remain() -> void:
	var waves := _waves()
	waves.start(1)
	assert_int(waves.phase).is_equal(Waves.Phase.WAVE)

	waves.spawn()
	_remove_all_enemies()
	assert_bool(waves.check_end()).is_false()
	assert_int(waves.phase).is_equal(Waves.Phase.WAVE)

	for tick in 10 * Simulation.TICKS_PER_SECOND:
		waves.spawn()
	assert_bool(waves.check_end()).is_false()

	_remove_all_enemies()
	assert_bool(waves.check_end()).is_true()
	assert_int(waves.phase).is_equal(Waves.Phase.BUILD)


func _edge_picks(run_seed: int) -> Array[PackedStringArray]:
	var waves := _waves(run_seed)
	var picks: Array[PackedStringArray] = []
	for wave in 20:
		waves.start(1)
		picks.append(waves.edges)
	return picks


func _remove_all_enemies() -> void:
	for k in _enemies.count:
		_enemies.hp[k] = 0.0
	_enemies.remove_dead_and_leaked()
