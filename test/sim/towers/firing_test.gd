extends GdUnitTestSuite

const TOUGH := 1000.0

var _settings: Settings
var _sim: Simulation
var _shots: Array[Buildings.Shot]
var _shot_ticks: Array[int]


func before_test() -> void:
	_settings = Settings.load_file(Settings.DEFAULTS_PATH).settings
	_settings.change("enemies", "speed", 0.1)
	_settings.change("enemies", "heading_offset", 0.0)
	# The worked examples below fire 2 shots/s (every 30 ticks) of 3 damage, and build
	# up to three towers from the starting gold.
	_settings.change("towers", "fire_rate", 2.0)
	_settings.change("towers", "damage", 3.0)
	_settings.change("towers", "cost", 50)
	var rows: Array[String] = []
	for y in 20:
		rows.append("....................")
	var edges: Array[String] = ["N"]
	_sim = Simulation.new(_settings, TestMaps.from_rows(rows, Rect2i(18, 18, 2, 2), edges), 1)
	_shots = []
	_shot_ticks = []
	_sim.shots_fired.connect(
		func(shots: Array[Buildings.Shot]) -> void:
			_shots.append_array(shots)
			for shot in shots:
				_shot_ticks.append(_sim.tick_count - 1)
	)


func test_a_new_tower_fires_on_the_tick_it_is_built_then_every_30_ticks() -> void:
	var enemy := _sim.enemies.spawn(Vector2(5.5, 5.5), TOUGH)
	_build(Vector2i(2, 2))

	for tick in 70:
		_sim.tick()

	assert_array(_shot_ticks).contains_exactly([0, 30, 60])
	assert_float(_hp(enemy)).is_equal_approx(TOUGH - 9.0, 1e-4)


func test_an_idle_tower_fires_on_the_first_tick_an_enemy_is_in_range() -> void:
	_build(Vector2i(2, 2))
	for tick in 45:
		_sim.tick()

	_sim.enemies.spawn(Vector2(5.5, 5.5), TOUGH)
	_sim.tick()

	assert_array(_shot_ticks).contains_exactly([45])


func test_range_is_measured_from_the_centre_of_the_footprint() -> void:
	var inside := _sim.enemies.spawn(Vector2(3.0, 10.9), TOUGH)
	_sim.enemies.spawn(Vector2(11.1, 3.0), TOUGH)
	_build(Vector2i(2, 2))

	_sim.tick()

	assert_array(_targets()).contains_exactly([inside])


func test_the_target_is_the_enemy_in_range_closest_to_the_base() -> void:
	_sim.enemies.spawn(Vector2(4.5, 4.5), TOUGH)
	var nearer_the_base := _sim.enemies.spawn(Vector2(8.5, 8.5), TOUGH)
	_sim.enemies.spawn(Vector2(15.5, 15.5), TOUGH)
	_build(Vector2i(2, 2))

	_sim.tick()

	assert_array(_targets()).contains_exactly([nearer_the_base])
	assert_int(_sim.buildings.built[0].target_id).is_equal(nearer_the_base)


func test_a_later_tower_skips_an_enemy_killed_earlier_in_the_same_tick() -> void:
	_settings.change("towers", "damage", 10.0)
	var weak := _sim.enemies.spawn(Vector2(8.5, 8.5), 10.0)
	var behind := _sim.enemies.spawn(Vector2(6.5, 6.5), TOUGH)
	_build(Vector2i(2, 2))
	_build(Vector2i(4, 2))

	_sim.tick()

	assert_array(_targets()).contains_exactly([weak, behind])
	assert_int(_sim.enemies.index_of(weak)).is_equal(Enemies.NONE)


func test_towers_fire_in_build_order_and_the_shot_list_matches_the_shots() -> void:
	var enemy := _sim.enemies.spawn(Vector2(6.5, 6.5), TOUGH)
	_build(Vector2i(8, 2))
	_build(Vector2i(2, 2))
	_build(Vector2i(2, 8))
	var shot_lists: Array[int] = []
	_sim.shots_fired.connect(
		func(shots_in_tick: Array[Buildings.Shot]) -> void: shot_lists.append(shots_in_tick.size())
	)

	_sim.tick()

	assert_array(shot_lists).contains_exactly([3])
	var tower_ids: Array[int] = []
	for shot in _shots:
		tower_ids.append(shot.tower_id)
		assert_int(shot.target_id).is_equal(enemy)
		assert_vector(shot.position).is_equal(_sim.enemies.positions[_sim.enemies.index_of(enemy)])
	assert_array(tower_ids).contains_exactly([0, 1, 2])
	(
		assert_array(
			_sim.buildings.built.map(
				func(tower: Buildings.Building) -> Vector2i: return tower.origin
			)
		)
		. contains_exactly([Vector2i(8, 2), Vector2i(2, 2), Vector2i(2, 8)])
	)
	assert_float(_hp(enemy)).is_equal_approx(TOUGH - 9.0, 1e-4)


func test_no_shot_list_is_reported_when_no_tower_fires() -> void:
	var reports: Array[bool] = []
	_sim.shots_fired.connect(
		func(_shots_in_tick: Array[Buildings.Shot]) -> void: reports.append(true)
	)
	_build(Vector2i(2, 2))

	_sim.tick()

	assert_array(reports).is_empty()


func _targets() -> Array[int]:
	var targets: Array[int] = []
	for shot in _shots:
		targets.append(shot.target_id)
	return targets


func _build(origin: Vector2i) -> void:
	_sim.queue_command(Commands.Build.new(Buildings.TOWER, origin))


func _hp(id: int) -> float:
	return _sim.enemies.hp[_sim.enemies.index_of(id)]
