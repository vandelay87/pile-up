extends GdUnitTestSuite

## A grinder hurts every enemy touching it, 3 HP a second each.
##
## A 20×8 field: rock above y = 3 and below y = 6, so a 4-high corridor runs east to a 2×2 base
## at (16, 4). The base powers cells 6..27 on x. Grinders sit at x = 10..11; enemies are placed
## against their west face and walk at 0.1 cells/s, so they stay pressed against it.

const BASE := Rect2i(16, 4, 2, 2)
const NORTH := Vector2i(10, 3)
const SOUTH := Vector2i(10, 5)
const TOUGH := 1000.0

var _settings: Settings
var _sim: Simulation


func before_test() -> void:
	_settings = TestSettings.without_swarm_spread().for_next_run()
	_settings.change("enemies", "speed", 0.1)
	var rows: Array[String] = []
	for y in 8:
		rows.append(".".repeat(20) if y >= 3 and y <= 6 else "#".repeat(20))
	_sim = Simulation.new(_settings, TestMaps.from_rows(rows, BASE), 1)
	_sim.add_gold(10000 - _sim.run_state.gold)


func test_an_enemy_touching_a_grinder_loses_3_hp_a_second() -> void:
	_build(Buildings.GRINDER, NORTH)
	# 0.3 cells off the grinder's west face: within the 0.4 reach.
	var id := _sim.enemies.spawn(Vector2(9.7, 3.5), TOUGH)

	_run(Simulation.TICKS_PER_SECOND)

	assert_float(_hp(id)).is_equal_approx(TOUGH - 3.0, 1e-2)


func test_two_grinders_stack() -> void:
	_build(Buildings.GRINDER, NORTH)
	_build(Buildings.GRINDER, SOUTH)
	# On the seam between them: 0.3 cells off both.
	var id := _sim.enemies.spawn(Vector2(9.7, 5.0), TOUGH)

	_run(Simulation.TICKS_PER_SECOND)

	assert_float(_hp(id)).is_equal_approx(TOUGH - 6.0, 1e-2)


func test_the_grinder_that_takes_an_enemy_to_0_hp_is_its_killer() -> void:
	var grinder := _build(Buildings.GRINDER, NORTH)
	_sim.enemies.spawn(Vector2(9.7, 3.5), 1.0)
	var killers := PackedInt32Array()

	# 1 HP at 3 HP/s goes in 20 ticks.
	for tick in 20:
		_sim.tick()
		killers.append_array(_sim.deaths.killers)

	assert_array(Array(killers)).is_equal([grinder.id])
	assert_int(grinder.kills).is_equal(1)


func test_an_unpowered_grinder_hurts_nothing() -> void:
	var grinder := _build(Buildings.GRINDER, NORTH)
	_sim.queue_command(Commands.SetSetting.new("run", "base_power_area", 0))
	_sim.tick()
	assert_bool(_sim.buildings.is_working(grinder.id)).is_false()
	var id := _sim.enemies.spawn(Vector2(9.7, 3.5), TOUGH)

	_run(Simulation.TICKS_PER_SECOND)

	assert_float(_hp(id)).is_equal(TOUGH)
	assert_int(grinder.touching).is_equal(0)


func test_its_kills_build_its_own_combo() -> void:
	var grinder := _build(Buildings.GRINDER, NORTH)
	# Ten enemies against its west face, one a tick, each with under a tick's grinding (3/60 HP).
	for n in 10:
		_sim.enemies.spawn(Vector2(9.7, 3.5), 0.04)
		_sim.tick()

	assert_int(grinder.kills).is_equal(10)
	var combo := _sim.combos.combo(grinder.id)
	assert_int(combo.count).is_equal(10)
	assert_int(combo.tier).is_equal(2)


func test_it_joins_a_barrier_and_is_attacked_like_any_building() -> void:
	# Walls close the corridor beside it, too tough to be the way through.
	_settings.change("piles", "wall_hp", TOUGH)
	var grinder := _build(Buildings.GRINDER, NORTH)
	var cells: Array[Vector2i] = [Vector2i(10, 5), Vector2i(10, 6)]
	_walls(cells)
	_sim.enemies.spawn(Vector2(9.7, 3.5), TOUGH)

	_run(Simulation.TICKS_PER_SECOND)

	var label := _sim.overflow.barrier_label(NORTH)
	assert_int(label).is_not_equal(Overflow.NONE)
	assert_int(_sim.overflow.barrier_label(Vector2i(10, 6))).is_equal(label)
	# Its attacker deals 2 HP/s.
	assert_float(grinder.hp).is_less(100.0)


func _build(kind: StringName, origin: Vector2i) -> Buildings.Building:
	_sim.queue_command(Commands.Build.new(kind, origin))
	_sim.tick()
	var built := _sim.buildings.building(_sim.occupancy.building_at(origin))
	assert_object(built).is_not_null()
	return built


func _hp(id: int) -> float:
	return _sim.enemies.hp[_sim.enemies.index_of(id)]


# Lands a wall on each cell as bodies land on the next tick.
func _walls(cells: Array[Vector2i]) -> void:
	var bodies := PackedVector2Array()
	for cell in cells:
		for n in Piles.WALL_LEVEL:
			bodies.append(Vector2(cell) + Vector2(0.5, 0.5))
	_sim.piles.queue_bodies(Deaths.bodies_at(bodies))
	_sim.tick()


func _run(ticks: int) -> void:
	for tick in ticks:
		_sim.tick()
