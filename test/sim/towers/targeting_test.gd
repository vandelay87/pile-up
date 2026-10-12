extends GdUnitTestSuite

## Each tower's targeting: bloaters first by default, or the enemy closest to the base.
##
## A 20×20 open field with a 2×2 base at (18, 18). The tower at (2, 2) reaches 8 cells from
## (3, 3); the enemies stand still at 0.1 cells/s.

const TOUGH := 1000.0
const TOWER := Vector2i(2, 2)

var _sim: Simulation
var _targets: Array[int]
var _events: Array[String]


func before_test() -> void:
	var settings := Settings.load_file(Settings.DEFAULTS_PATH).settings
	settings.change("enemies", "speed", 0.1)
	settings.change("enemies", "heading_offset", 0.0)
	settings.change("run", "base_power_area", 20)
	var rows: Array[String] = []
	for y in 20:
		rows.append(".".repeat(20))
	var edges: Array[String] = ["N"]
	_sim = Simulation.new(settings, TestMaps.from_rows(rows, Rect2i(18, 18, 2, 2), edges), 1)
	_targets = []
	_events = []
	_sim.shots_fired.connect(
		func(shots: Array[Buildings.Shot]) -> void:
			for shot in shots:
				_targets.append(shot.target_id)
	)
	_sim.command_rejected.connect(func(reason: String) -> void: _events.append(reason))


func test_a_new_tower_shoots_a_bloater_before_a_normal_enemy_nearer_the_base() -> void:
	var bloater := _sim.enemies.spawn(Vector2(4.5, 4.5), TOUGH, Enemies.Kind.BLOATER)
	_sim.enemies.spawn(Vector2(8.5, 8.5), TOUGH)
	_sim.queue_command(Commands.Build.new(Buildings.TOWER, TOWER))

	_sim.tick()

	assert_array(_targets).contains_exactly([bloater])


func test_closest_to_base_shoots_the_enemy_nearest_the_base() -> void:
	_sim.enemies.spawn(Vector2(4.5, 4.5), TOUGH, Enemies.Kind.BLOATER)
	var nearer := _sim.enemies.spawn(Vector2(8.5, 8.5), TOUGH)
	_sim.queue_command(Commands.Build.new(Buildings.TOWER, TOWER))
	_sim.queue_command(Commands.SetTargeting.new(0, Enemies.CLOSEST_TO_BASE))

	_sim.tick()

	assert_array(_targets).contains_exactly([nearer])
	assert_array(_events).is_empty()


func test_of_two_bloaters_the_one_nearer_the_base_is_shot() -> void:
	_sim.enemies.spawn(Vector2(4.5, 4.5), TOUGH, Enemies.Kind.BLOATER)
	var nearer := _sim.enemies.spawn(Vector2(7.5, 7.5), TOUGH, Enemies.Kind.BLOATER)
	_sim.enemies.spawn(Vector2(8.5, 8.5), TOUGH)
	_sim.queue_command(Commands.Build.new(Buildings.TOWER, TOWER))

	_sim.tick()

	assert_array(_targets).contains_exactly([nearer])


func test_a_tumbling_bloater_counts() -> void:
	var bloater := _sim.enemies.spawn(Vector2(4.5, 4.5), TOUGH, Enemies.Kind.BLOATER)
	_sim.enemies.spawn(Vector2(8.5, 8.5), TOUGH)
	_sim.enemies.start_tumble(_sim.enemies.index_of(bloater))
	_sim.queue_command(Commands.Build.new(Buildings.TOWER, TOWER))

	_sim.tick()

	assert_array(_targets).contains_exactly([bloater])


func test_set_targeting_rejects_an_unknown_mode_and_a_non_tower() -> void:
	_sim.queue_command(Commands.Build.new(Buildings.TOWER, TOWER))
	_sim.queue_command(Commands.Build.new(Buildings.PYLON, Vector2i(10, 2)))
	_sim.tick()

	_sim.queue_command(Commands.SetTargeting.new(0, &"weakest"))
	_sim.queue_command(Commands.SetTargeting.new(1, Enemies.CLOSEST_TO_BASE))
	_sim.queue_command(Commands.SetTargeting.new(99, Enemies.CLOSEST_TO_BASE))
	_sim.tick()

	(
		assert_array(_events)
		. contains_exactly(
			[
				"targeting: the mode must be bloaters_first or closest_to_base",
				"targeting: not a tower",
				"targeting: not a tower",
			]
		)
	)
	assert_str(_sim.buildings.building(0).targeting).is_equal(Enemies.BLOATERS_FIRST)
