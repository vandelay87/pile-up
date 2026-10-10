extends GdUnitTestSuite

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


func test_a_drone_flies_out_repairs_to_full_at_its_rate_and_flies_home() -> void:
	var yard := _build(Buildings.REPAIR_YARD, YARD)
	var tower := _build(Buildings.TOWER, TOWER)
	_start_wave()
	var drone := _sim.repair_yards.drone(yard.id)
	assert_int(drone.state).is_equal(RepairYards.State.HOME)
	assert_vector(drone.position).is_equal(Vector2(19, 13))

	_sim.buildings.damage(tower.id, 10.0)
	_run(30)
	assert_int(drone.state).is_equal(RepairYards.State.OUTBOUND)
	assert_int(drone.target_id).is_equal(tower.id)
	assert_vector(drone.position).is_equal_approx(Vector2(19, 17), Vector2(0.001, 0.001))
	_run(30)
	assert_int(drone.state).is_equal(RepairYards.State.REPAIRING)
	assert_vector(drone.position).is_equal(Vector2(19, 21))
	assert_float(tower.hp).is_equal(50.0)

	_run(60)
	assert_float(tower.hp).is_equal_approx(55.0, 0.001)
	_run(60)
	assert_float(tower.hp).is_equal(60.0)
	assert_int(drone.state).is_equal(RepairYards.State.RETURNING)
	assert_float(drone.repaired).is_equal_approx(10.0, 0.001)

	_run(60)
	assert_int(drone.state).is_equal(RepairYards.State.HOME)
	assert_vector(drone.position).is_equal(Vector2(19, 13))
	assert_array(_events).is_empty()


func test_it_never_repairs_its_own_yard_walls_or_the_base() -> void:
	var yard := _build(Buildings.REPAIR_YARD, YARD)
	var wall := Vector2i(19, 18)
	var bodies := PackedVector2Array()
	for n in Piles.WALL_LEVEL:
		bodies.append(Vector2(wall) + Vector2(0.5, 0.5))
	_sim.piles.queue_bodies(bodies)
	_start_wave()
	assert_int(_sim.piles.level(wall)).is_equal(Piles.WALL_LEVEL)

	_sim.buildings.damage(yard.id, 10.0)
	_sim.structures.damage(wall, 5.0)
	_sim.run_state.damage_base(10.0)
	_run(120)

	var drone := _sim.repair_yards.drone(yard.id)
	assert_int(drone.state).is_equal(RepairYards.State.HOME)
	assert_float(yard.hp).is_equal(50.0)
	assert_float(_sim.piles.wall_hp(wall)).is_equal(10.0)
	assert_float(_sim.run_state.base_hp).is_equal(190.0)
	assert_float(drone.repaired).is_equal(0.0)


func test_it_does_not_repair_outside_a_wave() -> void:
	var yard := _build(Buildings.REPAIR_YARD, YARD)
	var tower := _build(Buildings.TOWER, TOWER)

	_sim.buildings.damage(tower.id, 10.0)
	_run(120)

	assert_int(_sim.repair_yards.drone(yard.id).state).is_equal(RepairYards.State.HOME)
	assert_float(tower.hp).is_equal(50.0)


func test_two_yards_drones_spread_over_two_damaged_towers() -> void:
	var first := _build(Buildings.REPAIR_YARD, YARD)
	var second := _build(Buildings.REPAIR_YARD, Vector2i(22, 12))
	# Both towers are as near one yard as the other; the first is the nearer of the two.
	var near := _build(Buildings.TOWER, Vector2i(20, 18))
	var far := _build(Buildings.TOWER, Vector2i(20, 5))
	_start_wave()

	_sim.buildings.damage(near.id, 10.0)
	_sim.buildings.damage(far.id, 10.0)
	_sim.tick()

	assert_int(_sim.repair_yards.drone(first.id).target_id).is_equal(near.id)
	assert_int(_sim.repair_yards.drone(second.id).target_id).is_equal(far.id)


func test_two_yards_drones_double_up_on_one_damaged_tower_and_add_their_rates() -> void:
	var first := _build(Buildings.REPAIR_YARD, YARD)
	var second := _build(Buildings.REPAIR_YARD, Vector2i(22, 12))
	var near := _build(Buildings.TOWER, Vector2i(20, 18))
	_build(Buildings.TOWER, Vector2i(20, 5))
	_start_wave()

	_sim.buildings.damage(near.id, 20.0)
	# Both are about 6.32 cells away: they arrive on tick 48 and repair from tick 49.
	_run(48)
	var drones := [_sim.repair_yards.drone(first.id), _sim.repair_yards.drone(second.id)]
	for drone: RepairYards.Drone in drones:
		assert_int(drone.state).is_equal(RepairYards.State.REPAIRING)
		assert_int(drone.target_id).is_equal(near.id)
	_run(60)
	assert_float(near.hp).is_equal_approx(50.0, 0.001)
	_run(60)
	assert_float(near.hp).is_equal(60.0)
	for drone: RepairYards.Drone in drones:
		assert_int(drone.state).is_equal(RepairYards.State.RETURNING)
		assert_float(drone.repaired).is_equal_approx(10.0, 0.001)


func test_a_damaged_assignment_wins_over_a_nearer_building_after_the_current_trip() -> void:
	var yard := _build(Buildings.REPAIR_YARD, YARD)
	var near := _build(Buildings.TOWER, TOWER)
	# 10 cells from the yard's centre, in the corner of its repair area.
	var assigned := _build(Buildings.TOWER, Vector2i(24, 4))
	_sim.queue_command(Commands.Assign.new(yard.id, assigned.id))
	_start_wave()
	var drone := _sim.repair_yards.drone(yard.id)
	assert_int(drone.assignment).is_equal(assigned.id)

	# The assignment is at full HP, so the drone goes to the nearer tower.
	_sim.buildings.damage(near.id, 5.0)
	_run(30)
	assert_int(drone.target_id).is_equal(near.id)

	# Damaged mid-trip, the assignment waits for the drone to come home.
	_sim.buildings.damage(assigned.id, 5.0)
	_run(30 + 60)
	assert_int(drone.state).is_equal(RepairYards.State.RETURNING)
	assert_float(near.hp).is_equal(60.0)
	assert_float(assigned.hp).is_equal(55.0)
	_sim.buildings.damage(near.id, 5.0)
	_run(60)
	assert_int(drone.state).is_equal(RepairYards.State.HOME)

	_sim.tick()
	assert_int(drone.state).is_equal(RepairYards.State.OUTBOUND)
	assert_int(drone.target_id).is_equal(assigned.id)


func test_clearing_the_assignment_returns_the_drone_to_auto() -> void:
	var yard := _build(Buildings.REPAIR_YARD, YARD)
	var near := _build(Buildings.TOWER, TOWER)
	var assigned := _build(Buildings.TOWER, Vector2i(24, 4))
	_sim.queue_command(Commands.Assign.new(yard.id, assigned.id))
	_sim.queue_command(Commands.ClearAssignment.new(yard.id))
	_start_wave()

	_sim.buildings.damage(near.id, 5.0)
	_sim.buildings.damage(assigned.id, 5.0)
	_sim.tick()

	var drone := _sim.repair_yards.drone(yard.id)
	assert_int(drone.assignment).is_equal(RepairYards.NONE)
	assert_int(drone.target_id).is_equal(near.id)
	assert_array(_events).is_empty()


func test_an_assignment_ends_when_its_building_is_destroyed() -> void:
	var yard := _build(Buildings.REPAIR_YARD, YARD)
	var assigned := _build(Buildings.TOWER, TOWER)
	_sim.queue_command(Commands.Assign.new(yard.id, assigned.id))
	_start_wave()

	_sim.buildings.damage(assigned.id, 1000.0)
	_sim.tick()

	assert_int(_sim.repair_yards.drone(yard.id).assignment).is_equal(RepairYards.NONE)


func test_a_destroyed_target_makes_it_pick_again_from_where_it_is() -> void:
	var yard := _build(Buildings.REPAIR_YARD, YARD)
	var near := _build(Buildings.TOWER, TOWER)
	var far := _build(Buildings.TOWER, Vector2i(24, 4))
	_start_wave()
	_sim.buildings.damage(near.id, 10.0)
	_sim.buildings.damage(far.id, 10.0)
	_run(30)
	var drone := _sim.repair_yards.drone(yard.id)
	assert_int(drone.target_id).is_equal(near.id)

	_sim.buildings.damage(near.id, 1000.0)
	var from := drone.position
	_sim.tick()

	assert_int(drone.state).is_equal(RepairYards.State.OUTBOUND)
	assert_int(drone.target_id).is_equal(far.id)
	var heading := (Vector2(25, 5) - from).normalized()
	assert_vector(drone.position).is_equal_approx(
		from + heading * 8.0 / 60.0, Vector2(0.001, 0.001)
	)


func test_a_destroyed_target_with_nothing_else_to_repair_sends_it_home() -> void:
	var yard := _build(Buildings.REPAIR_YARD, YARD)
	var tower := _build(Buildings.TOWER, TOWER)
	_start_wave()
	_sim.buildings.damage(tower.id, 10.0)
	_run(30)

	_sim.buildings.damage(tower.id, 1000.0)
	_sim.tick()

	var drone := _sim.repair_yards.drone(yard.id)
	assert_int(drone.state).is_equal(RepairYards.State.RETURNING)
	assert_int(drone.target_id).is_equal(RepairYards.NONE)
	_run(30)
	assert_int(drone.state).is_equal(RepairYards.State.HOME)


func test_losing_power_sends_it_home_and_it_stops() -> void:
	# A pylon at the base grid's edge powers a yard beyond it.
	_build(Buildings.PYLON, Vector2i(25, 13))
	var yard := _build(Buildings.REPAIR_YARD, Vector2i(30, 13))
	var tower := _build(Buildings.TOWER, Vector2i(30, 20))
	assert_bool(yard.powered).is_true()
	_start_wave()
	_sim.buildings.damage(tower.id, 10.0)
	_run(30)
	var drone := _sim.repair_yards.drone(yard.id)
	assert_int(drone.state).is_equal(RepairYards.State.OUTBOUND)

	_sim.structures.damage(Vector2i(25, 13), 1000.0)
	_sim.tick()
	assert_bool(yard.powered).is_false()
	assert_int(drone.state).is_equal(RepairYards.State.RETURNING)
	_run(120)

	assert_int(drone.state).is_equal(RepairYards.State.HOME)
	assert_vector(drone.position).is_equal(Vector2(31, 14))
	assert_float(tower.hp).is_equal(50.0)


func test_the_wave_ending_sends_it_home_and_it_stops() -> void:
	var yard := _build(Buildings.REPAIR_YARD, YARD)
	var tower := _build(Buildings.TOWER, TOWER)
	_start_wave()
	_sim.buildings.damage(tower.id, 30.0)
	_run(90)
	var drone := _sim.repair_yards.drone(yard.id)
	assert_int(drone.state).is_equal(RepairYards.State.REPAIRING)

	_sim.enemies.hp[0] = 0.0
	_sim.tick()
	assert_int(_sim.waves.phase).is_equal(Waves.Phase.BUILD)
	var hp := tower.hp
	_sim.tick()
	assert_int(drone.state).is_equal(RepairYards.State.RETURNING)
	_run(120)

	assert_int(drone.state).is_equal(RepairYards.State.HOME)
	assert_float(tower.hp).is_equal(hp)


func test_a_destroyed_yards_drone_is_gone() -> void:
	var yard := _build(Buildings.REPAIR_YARD, YARD)
	_start_wave()

	_sim.buildings.damage(yard.id, 1000.0)
	_sim.tick()

	assert_object(_sim.repair_yards.drone(yard.id)).is_null()
	assert_array(_sim.repair_yards.drones).is_empty()


func test_assign_is_rejected_outside_the_area_for_the_yard_itself_and_for_non_yards() -> void:
	var yard := _build(Buildings.REPAIR_YARD, YARD)
	var tower := _build(Buildings.TOWER, TOWER)
	# Its nearest cell is 9 cells below the yard's footprint.
	var outside := _build(Buildings.TOWER, Vector2i(18, 22))

	_sim.queue_command(Commands.Assign.new(yard.id, outside.id))
	_sim.queue_command(Commands.Assign.new(yard.id, yard.id))
	_sim.queue_command(Commands.Assign.new(tower.id, yard.id))
	_sim.queue_command(Commands.ClearAssignment.new(tower.id))
	_sim.tick()

	(
		assert_array(_events)
		. contains_exactly(
			[
				"assign: outside the repair area",
				"assign: a yard cannot repair itself",
				"assign: not a repair yard",
				"clear assignment: not a repair yard",
			]
		)
	)
	assert_int(_sim.repair_yards.drone(yard.id).assignment).is_equal(RepairYards.NONE)


func test_hp_repaired_adds_up_over_trips() -> void:
	var yard := _build(Buildings.REPAIR_YARD, YARD)
	var tower := _build(Buildings.TOWER, TOWER)
	_start_wave()

	_sim.buildings.damage(tower.id, 10.0)
	_run(60 + 120 + 60)
	_sim.buildings.damage(tower.id, 15.0)
	_run(60 + 180 + 60)

	var drone := _sim.repair_yards.drone(yard.id)
	assert_int(drone.state).is_equal(RepairYards.State.HOME)
	assert_float(tower.hp).is_equal(60.0)
	assert_float(drone.repaired).is_equal_approx(25.0, 0.001)


func _build(kind: StringName, origin: Vector2i) -> Buildings.Building:
	_sim.queue_command(Commands.Build.new(kind, origin))
	_sim.tick()
	return _sim.buildings.building(_sim.occupancy.building_at(origin))


func _start_wave() -> void:
	_sim.queue_command(Commands.NextWave.new())
	_sim.tick()


func _run(ticks: int) -> void:
	for tick in ticks:
		_sim.tick()
