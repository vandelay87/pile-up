extends GdUnitTestSuite

const TOUGH := 1000.0

var _settings: Settings
var _sim: Simulation


func before_test() -> void:
	_settings = Settings.load_file(Settings.DEFAULTS_PATH).settings
	_settings.change("enemies", "speed", 0.1)
	_settings.change("enemies", "heading_offset", 0.0)
	# Shots of 3 damage every 30 ticks, and up to three towers from the starting gold.
	_settings.change("towers", "fire_rate", 2.0)
	_settings.change("towers", "damage", 3.0)
	_settings.change("towers", "cost", 50)
	_settings.change("run", "base_power_area", 20)
	var rows: Array[String] = []
	for y in 20:
		rows.append("....................")
	var edges: Array[String] = ["N"]
	_sim = Simulation.new(_settings, TestMaps.from_rows(rows, Rect2i(18, 18, 2, 2), edges), 1)


func test_a_new_tower_has_no_kills() -> void:
	_build(Vector2i(2, 2))
	_sim.tick()

	assert_int(_sim.buildings.built[0].kills).is_equal(0)


func test_a_tower_counts_one_kill_per_enemy_it_kills() -> void:
	# Each 3-HP enemy dies to one shot; the tower shoots at ticks 0, 30 and 60.
	_sim.enemies.spawn(Vector2(5.5, 5.5), 3.0)
	_sim.enemies.spawn(Vector2(6.5, 6.5), 3.0)
	_build(Vector2i(2, 2))

	_sim.tick()
	assert_int(_sim.buildings.built[0].kills).is_equal(1)

	for tick in 60:
		_sim.tick()
	assert_int(_sim.buildings.built[0].kills).is_equal(2)


func test_only_the_tower_that_lands_the_killing_shot_counts_the_kill() -> void:
	# Both towers hit the 6-HP enemy on tick 0: the first leaves it at 3, the second kills it.
	var enemy := _sim.enemies.spawn(Vector2(6.5, 6.5), 6.0)
	var other := _sim.enemies.spawn(Vector2(4.5, 4.5), TOUGH)
	_build(Vector2i(2, 2))
	_build(Vector2i(4, 2))
	_build(Vector2i(2, 8))

	_sim.tick()

	assert_int(_sim.enemies.index_of(enemy)).is_equal(Enemies.NONE)
	assert_int(_sim.enemies.index_of(other)).is_not_equal(Enemies.NONE)
	var kills: Array[int] = []
	for tower in _sim.buildings.built:
		kills.append(tower.kills)
	assert_array(kills).contains_exactly([0, 1, 0])


func _build(origin: Vector2i) -> void:
	_sim.queue_command(Commands.Build.new(Buildings.TOWER, origin))
