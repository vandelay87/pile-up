extends GdUnitTestSuite

## The jumper: a quick enemy locked to the direct route that jumps a thin line of walls or
## buildings at once, landing beyond it or perched on a building or the base, then waits out a
## cooldown.
##
## A 20×9 open field with a 2×3 base at (18, 3). Walls have 1000 HP, so nothing breaks through, and
## the base has 10000. A jumper spawned west of a wall line walks east into it.

const BASE := Rect2i(18, 3, 2, 3)
const WIDTH := 20
const HEIGHT := 9
const TOUGH_WALL := 1000.0

var _settings: Settings
var _sim: Simulation


func before_test() -> void:
	var settings := TestSettings.without_swarm_spread()
	settings.change("run", "base_hp", 10000)
	settings.change("run", "starting_gold", 5000)
	_settings = settings.for_next_run()
	_settings.change("enemies", "heading_offset", 0.0)
	_settings.change("piles", "wall_hp", TOUGH_WALL)
	var rows: Array[String] = []
	for y in HEIGHT:
		rows.append(".".repeat(WIDTH))
	_sim = Simulation.new(_settings, TestMaps.from_rows(rows, BASE), 1)


func test_the_jumper_settings_load_with_their_starting_values() -> void:
	assert_float(_settings.enemy_hp_of(Enemies.Kind.JUMPER)).is_equal(10.0)
	assert_int(_settings.enemy_bounty_of(Enemies.Kind.JUMPER)).is_equal(1)
	assert_float(_settings.enemy_mass_of(Enemies.Kind.JUMPER)).is_equal(1.0)
	assert_float(_settings.enemy_size_of(Enemies.Kind.JUMPER)).is_equal(1.0)
	assert_float(_settings.enemy_speed_per_tick_of(Enemies.Kind.JUMPER)).is_equal_approx(
		2.4 / Simulation.TICKS_PER_SECOND, 1e-9
	)
	assert_int(_settings.jumper_reach).is_equal(3)
	assert_int(_settings.jumper_cooldown_ticks).is_equal(240)
	assert_int(_settings.jumper_crouch_ticks).is_equal(15)
	assert_int(_settings.jumper_air_ticks).is_equal(48)
	assert_float(_settings.jump_clearance).is_equal(24.0)


func test_a_jumper_spawns_on_the_direct_route_and_stays_on_it() -> void:
	var id := _sim.enemies.spawn(Vector2(1.5, 4.5), 10.0, Enemies.Kind.JUMPER)

	assert_int(_sim.enemies.routes[_sim.enemies.index_of(id)]).is_equal(Routing.Route.DIRECT)
	assert_bool(Enemies.is_locked_to_direct(Enemies.Kind.JUMPER)).is_true()


func test_a_jumper_meeting_a_1_cell_wall_crouches_flies_for_48_ticks_and_lands_beyond() -> void:
	_walls(_column(9, 0, HEIGHT - 1))
	var id := _jumper(Vector2(7.5, 4.5))
	var crouch_ticks := 0
	var last_crouch := -1
	var landed_at := -1
	for tick in 4 * Simulation.TICKS_PER_SECOND:
		_sim.tick()
		var index := _sim.enemies.index_of(id)
		var state := _sim.enemies.states[index]
		if state == Enemies.State.CROUCHING:
			crouch_ticks += 1
			last_crouch = tick
			# It deals no damage while it crouches.
			assert_int(_sim.enemies.structure_targets[index]).is_equal(Enemies.NONE)
		elif state == Enemies.State.WALKING and last_crouch >= 0:
			landed_at = tick
			break

	assert_int(crouch_ticks).is_equal(15)
	assert_int(landed_at - last_crouch).is_equal(48)
	var index := _sim.enemies.index_of(id)
	assert_float(_sim.enemies.positions[index].x).is_greater(10.0)
	assert_int(_sim.enemies.routes[index]).is_equal(Routing.Route.DIRECT)
	assert_int(_sim.jumps.cooldown(id)).is_equal(_settings.jumper_cooldown_ticks)
	# It never attacked: the wall is untouched.
	for cell in _column(9, 0, HEIGHT - 1):
		assert_float(_sim.structures.hp(cell)).is_equal(TOUGH_WALL)


func test_a_barrier_4_cells_thick_stops_it_and_it_attacks() -> void:
	var block: Array[Vector2i] = []
	for x in range(9, 13):
		block.append_array(_column(x, 0, HEIGHT - 1))
	_walls(block)
	var id := _jumper(Vector2(7.5, 4.5))

	_run(3 * Simulation.TICKS_PER_SECOND)

	var index := _sim.enemies.index_of(id)
	assert_int(_sim.enemies.states[index]).is_equal(Enemies.State.WALKING)
	assert_int(_sim.enemies.structure_targets[index]).is_not_equal(Enemies.NONE)
	(
		assert_float(_sim.structures.hp(_sim.map.cell_of(_sim.enemies.structure_targets[index])))
		. is_less(TOUGH_WALL)
	)


func test_a_barrier_3_cells_thick_is_jumped() -> void:
	var block: Array[Vector2i] = []
	for x in range(9, 12):
		block.append_array(_column(x, 0, HEIGHT - 1))
	_walls(block)
	var id := _jumper(Vector2(7.5, 4.5))

	_run_until_landed(id)

	assert_float(_sim.enemies.positions[_sim.enemies.index_of(id)].x).is_greater(12.0)


func test_a_second_wall_within_reach_of_its_landing_catches_it_on_cooldown() -> void:
	_walls(_column(9, 0, HEIGHT - 1) + _column(12, 0, HEIGHT - 1))
	var id := _jumper(Vector2(7.5, 4.5))
	_run_until_landed(id)

	_run(2 * Simulation.TICKS_PER_SECOND)

	var index := _sim.enemies.index_of(id)
	assert_float(_sim.enemies.positions[index].x).is_between(10.0, 12.0)
	assert_int(_sim.enemies.states[index]).is_equal(Enemies.State.WALKING)
	assert_int(_sim.jumps.cooldown(id)).is_greater(0)
	assert_float(_sim.structures.hp(Vector2i(12, 4))).is_less(TOUGH_WALL)


func test_once_its_cooldown_runs_out_it_jumps_the_second_wall() -> void:
	_walls(_column(9, 0, HEIGHT - 1) + _column(12, 0, HEIGHT - 1))
	var id := _jumper(Vector2(7.5, 4.5))
	_run_until_landed(id)

	_run_until_landed(id)

	assert_float(_sim.enemies.positions[_sim.enemies.index_of(id)].x).is_greater(13.0)


func test_a_jump_over_a_soldiers_wall_cell_knocks_the_soldier_off_to_the_landing_side() -> void:
	_walls(_column(9, 0, HEIGHT - 1))
	var soldier := _sim.soldiers.add(Vector2i(9, 4))
	var id := _jumper(Vector2(7.5, 4.5))
	_sim.enemies.hp[_sim.enemies.index_of(id)] = 1000.0
	while _sim.enemies.positions[_sim.enemies.index_of(id)].x < 9.0:
		_sim.tick()

	# It walks back to its spot on the wall after.
	var index := _sim.soldiers.index_of(soldier)
	assert_vector(Vector2i(_sim.soldiers.positions[index].floor())).is_equal(Vector2i(10, 4))
	assert_int(_sim.soldiers.elevation(index)).is_equal(0)


func test_a_jump_over_a_grinder_takes_its_damage_for_each_cell_it_enters() -> void:
	_settings.change("overflow", "perch_room", 0)
	_build(Buildings.GRINDER, Vector2i(9, 4))
	_walls(_column(9, 0, 3) + _column(9, 6, HEIGHT - 1))
	var id := _jumper(Vector2(7.5, 4.5))
	_sim.enemies.hp[_sim.enemies.index_of(id)] = 1000.0
	var hp_at_lift_off := 0.0
	while true:
		_sim.tick()
		var index := _sim.enemies.index_of(id)
		if _sim.enemies.states[index] == Enemies.State.CROUCHING:
			hp_at_lift_off = _sim.enemies.hp[index]
		elif _sim.enemies.states[index] == Enemies.State.WALKING and hp_at_lift_off > 0.0:
			break

	var index := _sim.enemies.index_of(id)
	assert_float(_sim.enemies.positions[index].x).is_greater(11.0)
	assert_float(hp_at_lift_off - _sim.enemies.hp[index]).is_equal_approx(
		2.0 * _settings.grinder_damage, 1e-3
	)


func test_a_crouch_and_a_jump_neither_fill_a_gauge_nor_take_anything_off_it() -> void:
	# Without a leak, one normal enemy held at the wall fills its crush slowly, never reaching a
	# tier in the time this takes. A long crouch gives the jumper time to count as stalled if it
	# could.
	_settings.change("overflow", "leak", 0.0)
	_settings.change("jumpers", "crouch", 1.5)
	_walls(_column(9, 0, HEIGHT - 1))
	_sim.enemies.spawn(Vector2(7.5, 1.5), 1000.0)
	while _sim.overflow.crushes().is_empty():
		_sim.tick()
	var id := _jumper(Vector2(7.5, 6.5))
	var per_tick := _settings.fill_per_stalled / Simulation.TICKS_PER_SECOND
	var checked := 0

	while _sim.jumps.jump(id) != null or checked == 0:
		var before := _sim.overflow.crushes()[0].gauge
		_sim.tick()
		if _sim.jumps.jump(id) == null:
			continue
		var crush := _sim.overflow.crushes()[0]
		assert_int(crush.stalled).is_equal(1)
		assert_float(crush.gauge - before).is_equal_approx(per_tick, 1e-4)
		assert_int(crush.tier).is_equal(Overflow.Tier.NONE)
		checked += 1

	assert_int(checked).is_greater_equal(90 + 48 - 1)


func test_a_jumper_on_cooldown_in_a_crush_tumbles_without_a_new_cooldown() -> void:
	# The jumpers jump a single wall line at x 3 into a crowd held at a block too thick to jump,
	# and wait out a long cooldown there; a high fill takes the crush to a surge.
	_settings.change("jumpers", "cooldown", 30.0)
	_settings.change("overflow", "fill_per_stalled", 10.0)
	_settings.change("overflow", "leak", 5.0)
	var block := _column(3, 0, HEIGHT - 1)
	for x in range(10, 14):
		block.append_array(_column(x, 0, HEIGHT - 1))
	_walls(block)
	for n in 40:
		_sim.enemies.spawn(Vector2(5.0 + (n % 5), 0.5 + n / 5), 1000.0)
	var jumpers: Array[int] = []
	for y in HEIGHT:
		jumpers.append(_jumper(Vector2(1.5, y + 0.5)))
	# The cooldown each jumper had as it started tumbling, by id.
	var tumbled := {}
	var landed := 0
	var states := {}

	for tick in 20 * Simulation.TICKS_PER_SECOND:
		_sim.tick()
		for id in jumpers:
			var index := _sim.enemies.index_of(id)
			if index == Enemies.NONE:
				continue
			var state := _sim.enemies.states[index]
			if state == Enemies.State.TUMBLING and not tumbled.has(id):
				assert_int(states.get(id, Enemies.State.WALKING)).is_not_equal(
					Enemies.State.CROUCHING
				)
				assert_int(_sim.jumps.cooldown(id)).is_greater(0)
				tumbled[id] = _sim.jumps.cooldown(id) + tick
			elif tumbled.has(id) and state != Enemies.State.TUMBLING and tumbled[id] > 0:
				# Its cooldown ran on through the tumble rather than starting again.
				assert_int(_sim.jumps.cooldown(id)).is_equal(tumbled[id] - tick)
				tumbled[id] = 0
				landed += 1
			states[id] = state

	assert_int(landed).is_greater(0)


func _jumper(at: Vector2) -> int:
	return _sim.enemies.spawn(at, _settings.enemy_hp, Enemies.Kind.JUMPER)


func _column(x: int, top: int, bottom: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in range(top, bottom + 1):
		cells.append(Vector2i(x, y))
	return cells


# Lands a wall on each cell, then ticks until the fields have settled round them.
func _walls(cells: Array[Vector2i]) -> void:
	var bodies := PackedVector2Array()
	for cell in cells:
		for n in Piles.WALL_LEVEL:
			bodies.append(MapData.centre_of(cell))
	_sim.piles.queue_bodies(Deaths.bodies_at(bodies))
	_sim.tick()
	while _sim.routing.is_settling():
		_sim.tick()


# Ticks until the jumper with id [param id] next comes down from a jump, walking or perched.
func _run_until_landed(id: int) -> void:
	for tick in 20 * Simulation.TICKS_PER_SECOND:
		var was_jumping := _sim.enemies.states[_sim.enemies.index_of(id)] == Enemies.State.JUMPING
		_sim.tick()
		if was_jumping and _sim.jumps.jump(id) == null:
			return
	fail("the jumper never landed")


# A wall line at x 9 and, behind it, repair yards filling columns 10 and 11 but for walls in
# the corners left over, so every way east meets a yard.
func _yards_behind_a_wall() -> Array[Buildings.Building]:
	var yards: Array[Buildings.Building] = []
	for y: int in [1, 3, 5]:
		yards.append(_build(Buildings.REPAIR_YARD, Vector2i(10, y)))
	var walls := _column(9, 0, HEIGHT - 1)
	for cell: Vector2i in [Vector2i(10, 0), Vector2i(11, 0), Vector2i(10, 7), Vector2i(11, 7)]:
		walls.append(cell)
	walls.append_array([Vector2i(10, 8), Vector2i(11, 8)])
	_walls(walls)
	return yards


func _build(kind: StringName, origin: Vector2i) -> Buildings.Building:
	_sim.queue_command(Commands.Build.new(kind, origin))
	_sim.tick()
	var built := _sim.buildings.building(_sim.occupancy.building_at(origin))
	assert_object(built).is_not_null()
	return built


func _run(ticks: int) -> void:
	for tick in ticks:
		_sim.tick()
