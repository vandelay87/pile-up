extends GdUnitTestSuite

## A building a drone is repairing stops working until the drone lifts off, except a pylon.
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


func test_a_tower_under_repair_holds_fire_until_the_drone_lifts_off() -> void:
	var yard := _build(Buildings.REPAIR_YARD, YARD)
	var tower := _build(Buildings.TOWER, TOWER)
	var shots: Array[Buildings.Shot] = []
	_sim.shots_fired.connect(func(fired: Array[Buildings.Shot]) -> void: shots.append_array(fired))
	_start_wave()
	_sim.buildings.damage(tower.id, 10.0)
	_run(60)
	var drone := _sim.repair_yards.drone(yard.id)
	assert_int(drone.state).is_equal(RepairYards.State.REPAIRING)
	assert_bool(_sim.repair_yards.is_under_repair(tower.id)).is_true()
	assert_bool(_sim.buildings.is_working(tower.id)).is_false()

	# 5.5 cells below the tower's centre: in range, and too slow to reach it.
	_sim.enemies.spawn(Vector2(19.5, 26.5), 1000.0)
	while drone.state == RepairYards.State.REPAIRING:
		_sim.tick()
	assert_float(tower.hp).is_equal(60.0)
	assert_array(shots).is_empty()

	_sim.tick()
	assert_int(shots.size()).is_equal(1)
	assert_int(shots[0].shooter_id).is_equal(tower.id)


func test_a_grinder_under_repair_hurts_nothing_until_the_drone_lifts_off() -> void:
	var yard := _build(Buildings.REPAIR_YARD, YARD)
	var grinder := _build(Buildings.GRINDER, TOWER)
	_start_wave()
	_sim.buildings.damage(grinder.id, 10.0)
	_run(60)
	var drone := _sim.repair_yards.drone(yard.id)
	assert_int(drone.state).is_equal(RepairYards.State.REPAIRING)

	# 0.3 cells off the grinder's west face.
	var id := _sim.enemies.spawn(Vector2(17.7, 20.5), 1000.0)
	var index := _sim.enemies.index_of(id)
	while drone.state == RepairYards.State.REPAIRING:
		_sim.tick()
	assert_float(_sim.enemies.hp[index]).is_equal(1000.0)

	_sim.tick()
	assert_float(_sim.enemies.hp[index]).is_less(1000.0)


func test_a_pylon_under_repair_keeps_powering() -> void:
	# The pylon at the base grid's edge is the yard's only power.
	var pylon := _build(Buildings.PYLON, Vector2i(25, 13))
	var yard := _build(Buildings.REPAIR_YARD, Vector2i(30, 13))
	_start_wave()
	_sim.buildings.damage(pylon.id, 10.0)
	_run(90)
	var drone := _sim.repair_yards.drone(yard.id)
	assert_int(drone.state).is_equal(RepairYards.State.REPAIRING)
	assert_bool(_sim.repair_yards.is_under_repair(pylon.id)).is_true()

	assert_bool(_sim.buildings.is_working(pylon.id)).is_true()
	assert_bool(yard.powered).is_true()
	assert_bool(_sim.buildings.is_working(yard.id)).is_true()
	_run(120)
	assert_float(pylon.hp).is_equal(20.0)


func test_a_yard_under_repair_sends_its_drone_home() -> void:
	var yard := _build(Buildings.REPAIR_YARD, YARD)
	var other := _build(Buildings.REPAIR_YARD, Vector2i(22, 12))
	var tower := _build(Buildings.TOWER, TOWER)
	_sim.queue_command(Commands.Assign.new(other.id, yard.id))
	_start_wave()
	_sim.buildings.damage(tower.id, 30.0)
	_sim.buildings.damage(yard.id, 10.0)
	var drone := _sim.repair_yards.drone(yard.id)
	var other_drone := _sim.repair_yards.drone(other.id)
	_sim.tick()
	assert_int(drone.target_id).is_equal(tower.id)
	assert_int(other_drone.target_id).is_equal(yard.id)

	# The other drone is 4 cells away: it arrives on its 30th tick, and the yard stops working on
	# the next.
	_run(29)
	assert_int(other_drone.state).is_equal(RepairYards.State.REPAIRING)
	assert_int(drone.state).is_equal(RepairYards.State.OUTBOUND)
	assert_bool(_sim.buildings.is_working(yard.id)).is_false()
	_sim.tick()
	assert_int(drone.state).is_equal(RepairYards.State.RETURNING)
	assert_int(drone.target_id).is_equal(RepairYards.NONE)


func test_a_yard_stops_the_tick_after_its_repair_starts_whatever_the_build_order() -> void:
	# The repairing yard is built first, so its drone steps before the repaired yard's.
	var other := _build(Buildings.REPAIR_YARD, Vector2i(22, 12))
	var yard := _build(Buildings.REPAIR_YARD, YARD)
	var tower := _build(Buildings.TOWER, TOWER)
	_sim.queue_command(Commands.Assign.new(other.id, yard.id))
	_start_wave()
	_sim.buildings.damage(tower.id, 30.0)
	_sim.buildings.damage(yard.id, 10.0)
	var drone := _sim.repair_yards.drone(yard.id)
	var other_drone := _sim.repair_yards.drone(other.id)

	_run(30)
	assert_int(other_drone.state).is_equal(RepairYards.State.REPAIRING)
	assert_int(drone.state).is_equal(RepairYards.State.OUTBOUND)
	_sim.tick()
	assert_int(drone.state).is_equal(RepairYards.State.RETURNING)


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
