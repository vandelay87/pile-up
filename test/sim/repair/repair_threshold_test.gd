extends GdUnitTestSuite

## Each yard's repair threshold decides how damaged a building must be before its drone goes.
##
## A 48×48 open field with a 4×4 base at (12, 12): the base's grid is cells 2..25 on both axes.
## A wave of one slow enemy from the east edge keeps the wave running without reaching anything.
## The yard at (18, 12) has its centre at (19, 13); its repair area is cells 10..27 on x and 4..21
## on y. Drones fly 8 cells/s (8/60 a tick) and repair 5 HP/s (1/12 a tick).

const BASE := Rect2i(12, 12, 4, 4)
const SIZE := 48
const YARD := Vector2i(18, 12)
# 8 cells below the yard's centre: 60 ticks of flight.
const TOWER := Vector2i(18, 20)

var _settings: Settings
var _sim: Simulation
var _events: Array[String]


func before_test() -> void:
	var settings := Settings.load_file(Settings.DEFAULTS_PATH).settings
	settings.change("waves", "wave_1_size", 1)
	_settings = settings.for_next_run()
	_settings.change("enemies", "speed", 0.1)
	var rows: Array[String] = []
	for y in SIZE:
		rows.append(".".repeat(SIZE))
	var edges: Array[String] = ["E"]
	_sim = Simulation.new(_settings, TestMaps.from_rows(rows, BASE, edges), 1)
	_sim.add_gold(10000 - _sim.run_state.gold)
	_events = []
	_sim.command_rejected.connect(func(reason: String) -> void: _events.append(reason))


func test_a_building_at_60_percent_is_picked_at_a_75_percent_threshold_not_50() -> void:
	var yard := _build(Buildings.REPAIR_YARD, YARD, RepairYards.DEFAULT_THRESHOLD)
	var tower := _build(Buildings.TOWER, TOWER)
	_start_wave()
	var drone := _sim.repair_yards.drone(yard.id)
	assert_int(drone.threshold).is_equal(50)

	_sim.buildings.damage(tower.id, 24.0)
	_run(10)
	assert_int(drone.state).is_equal(RepairYards.State.HOME)

	_sim.queue_command(Commands.SetRepairThreshold.new(yard.id, 75))
	_sim.tick()
	assert_int(drone.target_id).is_equal(tower.id)
	# Once started, it repairs to full: 60 ticks out, then 24 HP at 1/12 HP a tick.
	_run(60 + 288)
	assert_float(tower.hp).is_equal(60.0)
	assert_int(drone.state).is_equal(RepairYards.State.RETURNING)
	assert_array(_events).is_empty()


func test_an_assignment_above_the_threshold_is_skipped_for_auto() -> void:
	var yard := _build(Buildings.REPAIR_YARD, YARD, RepairYards.DEFAULT_THRESHOLD)
	var near := _build(Buildings.TOWER, TOWER)
	var assigned := _build(Buildings.TOWER, Vector2i(24, 4))
	_sim.queue_command(Commands.Assign.new(yard.id, assigned.id))
	_start_wave()

	# The assignment is at 2/3 HP, above the 50% threshold; the nearer tower is at 1/3.
	_sim.buildings.damage(assigned.id, 20.0)
	_sim.buildings.damage(near.id, 40.0)
	_sim.tick()

	var drone := _sim.repair_yards.drone(yard.id)
	assert_int(drone.assignment).is_equal(assigned.id)
	assert_int(drone.target_id).is_equal(near.id)


func test_set_repair_threshold_rejects_other_percents_and_non_yards() -> void:
	var yard := _build(Buildings.REPAIR_YARD, YARD, RepairYards.DEFAULT_THRESHOLD)
	var tower := _build(Buildings.TOWER, TOWER)

	_sim.queue_command(Commands.SetRepairThreshold.new(yard.id, 60))
	_sim.queue_command(Commands.SetRepairThreshold.new(yard.id, 0))
	_sim.queue_command(Commands.SetRepairThreshold.new(tower.id, 75))
	_sim.tick()

	(
		assert_array(_events)
		. contains_exactly(
			[
				"repair threshold: the threshold must be 25, 50, 75 or 100%",
				"repair threshold: the threshold must be 25, 50, 75 or 100%",
				"repair threshold: not a repair yard",
			]
		)
	)
	assert_int(_sim.repair_yards.drone(yard.id).threshold).is_equal(50)


# Yards repair any damage unless a test sets their threshold, so small hits start trips.
func _build(kind: StringName, origin: Vector2i, threshold := 100) -> Buildings.Building:
	_sim.queue_command(Commands.Build.new(kind, origin))
	_sim.tick()
	var built := _sim.buildings.building(_sim.occupancy.building_at(origin))
	if kind == Buildings.REPAIR_YARD:
		_sim.queue_command(Commands.SetRepairThreshold.new(built.id, threshold))
		_sim.tick()
	return built


func _start_wave() -> void:
	_sim.queue_command(Commands.NextWave.new())
	_sim.tick()


func _run(ticks: int) -> void:
	for tick in ticks:
		_sim.tick()
