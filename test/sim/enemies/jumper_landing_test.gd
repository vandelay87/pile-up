extends GdUnitTestSuite

## Where a jump ends: perched on a building with room or on the base, or on the ground beyond;
## claims on the room it would take; and where a jumper's body lands when it dies on the way.
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


func test_it_perches_on_a_building_with_room_behind_a_wall() -> void:
	var yards := _yards_behind_a_wall()
	var id := _jumper(Vector2(7.5, 4.5))

	_run_until_landed(id)

	var index := _sim.enemies.index_of(id)
	assert_int(_sim.enemies.states[index]).is_equal(Enemies.State.PERCHED)
	var yard := _sim.buildings.building(_sim.perches.perched_on(id))
	assert_bool(yard in yards).is_true()
	var footprint := Rect2(Vector2(yard.origin), Vector2(2, 2))
	assert_bool(footprint.has_point(_sim.enemies.positions[index])).is_true()
	assert_int(_sim.jumps.cooldown(id)).is_equal(_settings.jumper_cooldown_ticks)
	# Its body would drop off on the side it came from.
	assert_int(_sim.perches.drop_cell(id).x).is_less(9)


func test_a_full_building_is_crossed_and_counts_towards_the_reach() -> void:
	_settings.change("overflow", "perch_room", 0)
	_yards_behind_a_wall()
	var id := _jumper(Vector2(7.5, 4.5))

	_run_until_landed(id)

	var index := _sim.enemies.index_of(id)
	assert_int(_sim.enemies.states[index]).is_equal(Enemies.State.WALKING)
	assert_float(_sim.enemies.positions[index].x).is_greater(12.0)


func test_it_perches_on_the_base_when_it_has_room() -> void:
	var id := _jumper(Vector2(15.5, 4.5))

	_run_until_landed(id)

	assert_int(_sim.perches.perched_on(id)).is_equal(Perches.BASE)
	assert_bool(Rect2(BASE).has_point(_sim.enemies.positions[_sim.enemies.index_of(id)])).is_true()


func test_it_attacks_a_full_base_from_the_ground() -> void:
	_settings.change("overflow", "base_perch_room", 0)
	var id := _jumper(Vector2(15.5, 4.5))
	var hp := _sim.run_state.base_hp

	_run(3 * Simulation.TICKS_PER_SECOND)

	var index := _sim.enemies.index_of(id)
	assert_int(_sim.enemies.states[index]).is_equal(Enemies.State.WALKING)
	assert_object(_sim.jumps.jump(id)).is_null()
	assert_float(_sim.run_state.base_hp).is_less(hp)


func test_a_jumper_killed_in_the_air_falls_back_to_where_it_crouched() -> void:
	_walls(_column(9, 0, HEIGHT - 1))
	var id := _jumper(Vector2(7.5, 4.5))
	var crouched := Vector2i(-1, -1)
	while _sim.enemies.states[_sim.enemies.index_of(id)] != Enemies.State.JUMPING:
		_sim.tick()
		crouched = Vector2i(_sim.enemies.positions[_sim.enemies.index_of(id)].floor())
	_run(30)
	assert_float(_sim.enemies.positions[_sim.enemies.index_of(id)].x).is_greater(9.0)

	_sim.enemies.kill(id)
	_run(2)

	assert_int(_sim.piles.level(crouched)).is_equal(1)


func test_a_jumper_killed_within_a_second_of_landing_falls_back_to_where_it_crouched() -> void:
	_walls(_column(9, 0, HEIGHT - 1))
	var id := _jumper(Vector2(7.5, 4.5))
	var crouched := Vector2i(-1, -1)
	while _sim.enemies.states[_sim.enemies.index_of(id)] != Enemies.State.JUMPING:
		_sim.tick()
		crouched = Vector2i(_sim.enemies.positions[_sim.enemies.index_of(id)].floor())
	_run_until_landed(id)
	_run(30)

	_sim.enemies.kill(id)
	_run(2)

	assert_int(_sim.piles.level(crouched)).is_equal(1)


func test_a_jumper_killed_later_lands_where_it_died() -> void:
	_walls(_column(9, 0, HEIGHT - 1))
	var id := _jumper(Vector2(7.5, 4.5))
	_run_until_landed(id)
	_run(2 * Simulation.TICKS_PER_SECOND)
	var died_at := Vector2i(_sim.enemies.positions[_sim.enemies.index_of(id)].floor())

	_sim.enemies.kill(id)
	_run(2)

	assert_int(_sim.piles.level(died_at)).is_equal(1)


func test_a_claim_is_given_back_when_the_jumper_dies_in_the_air() -> void:
	_yards_behind_a_wall()
	var id := _jumper(Vector2(7.5, 4.5))
	while _sim.jumps.jump(id) == null:
		_sim.tick()
	var yard := _sim.buildings.building(_sim.jumps.jump(id).way.target)
	assert_int(_sim.perches.claimed(yard.id)).is_equal(1)

	_sim.enemies.kill(id)
	_run(2)

	assert_int(_sim.perches.claimed(yard.id)).is_equal(0)


func test_a_building_destroyed_on_its_way_frees_the_claim_and_it_lands_on_the_ground() -> void:
	_yards_behind_a_wall()
	var id := _jumper(Vector2(7.5, 4.5))
	while _sim.jumps.jump(id) == null:
		_sim.tick()
	var yard := _sim.buildings.building(_sim.jumps.jump(id).way.target)

	_sim.buildings.damage(yard.id, yard.hp + 1.0)
	_run_until_landed(id)

	var index := _sim.enemies.index_of(id)
	assert_int(_sim.enemies.states[index]).is_equal(Enemies.State.WALKING)
	assert_bool(_sim.perches.is_perched(id)).is_false()
	assert_int(_sim.perches.claimed(yard.id)).is_equal(0)


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
