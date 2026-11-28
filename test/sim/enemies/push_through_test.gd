extends GdUnitTestSuite

# A ring: a top and a bottom lane joined at the west end, the base at the east end. An enemy
# in the top lane near the west end heads east; a pile landing ahead of it makes the long
# way round the cheaper sensible route, turning it back west.
const RING: Array[String] = [
	"..............",
	".###########..",
	".###########..",
	".###########..",
	"..............",
]
const RING_BASE := Rect2i(13, 2, 1, 1)
const RING_START := Vector2(3.5, 0.5)
const RING_PILE := Vector2i(6, 0)
# An open field: a pile just ahead of the enemy bends its sensible heading round the pile,
# well under the turn-back angle.
const FIELD: Array[String] = [
	"............",
	"............",
	"............",
	"............",
	"............",
]
const FIELD_BASE := Rect2i(11, 2, 1, 1)
const FIELD_START := Vector2(2.5, 2.5)
const FIELD_PILE := Vector2i(4, 2)
const PILE_BODIES := 4
const WALK_TICKS := 1200

var _settings: Settings


func before_test() -> void:
	_settings = TestSettings.without_swarm_spread()
	_settings.change("enemies", "heading_offset", 0.0)
	_settings.change("enemies", "pile_roll_chance", 0)
	_settings.change("piles", "slow_level_4", 75)
	_settings.change("routing", "sensible_pile_weight", 5.0)
	_settings.change("waves", "burst_size", 50)
	TestSettings.set_scatter_share(_settings, 10)
	_settings.change("waves", "size_roll", 0)
	TestWaves.without_trickle(_settings)


func test_outside_the_wave_tail_an_enemy_turned_back_takes_the_long_way() -> void:
	var sim := _sim_in_wave(RING, RING_BASE, 13)
	assert_bool(_in_tail(sim)).is_false()
	var id := _spawn_heading_east(sim, RING_START)

	_land_pile(sim, RING_PILE)
	for tick in 60:
		sim.tick()
		assert_int(_route(sim, id)).is_equal(Routing.Route.SENSIBLE)

	assert_float(_position(sim, id).x).is_less(RING_START.x - 1.0)


func test_in_the_wave_tail_an_enemy_turned_back_pushes_through_on_the_direct_route() -> void:
	var sim := _sim_in_wave(RING, RING_BASE, 12)
	assert_bool(_in_tail(sim)).is_true()
	var id := _spawn_heading_east(sim, RING_START)

	_land_pile(sim, RING_PILE)
	sim.tick()

	assert_int(_route(sim, id)).is_equal(Routing.Route.DIRECT)
	assert_float(_position(sim, id).x).is_greater(RING_START.x)


func test_a_pushed_through_enemy_crosses_the_obstacle_then_returns_to_sensible() -> void:
	var sim := _sim_in_wave(RING, RING_BASE, 12)
	var id := _spawn_heading_east(sim, RING_START)
	_land_pile(sim, RING_PILE)

	var cells: Array[Vector2i] = []
	for tick in WALK_TICKS:
		sim.tick()
		var pos := _position(sim, id)
		cells.append(Vector2i(pos.floor()))
		if pos.x > RING_PILE.x + 1.5:
			break
		if pos.x < RING_PILE.x + 0.5:
			assert_int(_route(sim, id)).is_equal(Routing.Route.DIRECT)

	assert_bool(RING_PILE in cells).is_true()
	for cell in cells:
		assert_int(cell.y).is_equal(RING_PILE.y)
	assert_float(_position(sim, id).x).is_greater(RING_PILE.x + 1.5)
	assert_int(_route(sim, id)).is_equal(Routing.Route.SENSIBLE)


func test_in_the_wave_tail_a_turn_under_the_angle_keeps_the_sensible_route() -> void:
	var sim := _sim_in_wave(FIELD, FIELD_BASE, 12)
	var id := _spawn_heading_east(sim, FIELD_START)

	_land_pile(sim, FIELD_PILE)
	for tick in 60:
		sim.tick()
		assert_int(_route(sim, id)).is_equal(Routing.Route.SENSIBLE)

	assert_float(absf(_position(sim, id).y - FIELD_START.y)).is_greater(0.25)


func test_a_wider_turn_back_angle_keeps_a_turned_back_enemy_on_the_long_way() -> void:
	_settings.change("enemies", "turn_back_angle", 180.0)
	var sim := _sim_in_wave(RING, RING_BASE, 12)
	var id := _spawn_heading_east(sim, RING_START)

	_land_pile(sim, RING_PILE)
	for tick in 60:
		sim.tick()
		assert_int(_route(sim, id)).is_equal(Routing.Route.SENSIBLE)


func test_the_wave_tail_starts_at_10_plus_2_per_point_of_threat_enemies_left() -> void:
	for threat: int in [1, 3]:
		var expected_tail: int = {1: 12, 3: 16}[threat]
		var sim := _ring_sim()
		TestWaves.send_at(sim, threat + 0.5)
		_kill(sim, sim.waves.enemies_left - expected_tail - 1)
		assert_int(sim.waves.enemies_left).is_equal(expected_tail + 1)
		assert_bool(_in_tail(sim)).is_false()

		_kill(sim, 1)

		assert_int(sim.waves.enemies_left).is_equal(expected_tail)
		assert_bool(_in_tail(sim)).is_true()


func test_the_wave_tail_follows_its_settings() -> void:
	_settings.change("waves", "wave_tail", 4)
	_settings.change("waves", "wave_tail_per_threat", 3)
	var sim := _ring_sim()
	sim.queue_command(Commands.SendWave.new())
	sim.tick()

	_kill(sim, sim.waves.enemies_left - 7)

	assert_bool(_in_tail(sim)).is_true()
	assert_bool(_in_tail(_sim_in_wave(RING, RING_BASE, 8))).is_false()


func test_in_the_quiet_a_trickle_enemy_turned_back_pushes_through_as_in_the_wave_tail() -> void:
	var sim := _ring_sim()
	assert_int(sim.waves.phase).is_equal(Waves.Phase.QUIET)
	var id := _spawn_heading_east(sim, RING_START)

	_land_pile(sim, RING_PILE)
	sim.tick()

	assert_int(_route(sim, id)).is_equal(Routing.Route.DIRECT)


func _ring_sim() -> Simulation:
	var edges: Array[String] = ["W"]
	return Simulation.new(_settings, TestMaps.from_rows(RING, RING_BASE, edges), 1)


# A wave with the given Enemies left and an empty field: one enemy spawns and is killed, and
# the slowest spawn rate keeps the next one off the field for 120 ticks.
func _sim_in_wave(rows: Array[String], base: Rect2i, enemies_left: int) -> Simulation:
	_settings.change("waves", "wave_1_size", enemies_left + 1)
	_settings.change("waves", "burst_size", 1)
	_settings.change("waves", "spawn_rate", 0.5)
	var edges: Array[String] = ["W"]
	var sim := Simulation.new(_settings.for_next_run(), TestMaps.from_rows(rows, base, edges), 1)
	sim.queue_command(Commands.SendWave.new())
	sim.tick()
	assert_int(sim.enemies.count).is_equal(1)
	_kill(sim, 1)
	assert_int(sim.enemies.count).is_equal(0)
	assert_int(sim.waves.enemies_left).is_equal(enemies_left)
	return sim


func _in_tail(sim: Simulation) -> bool:
	return sim.waves.open_waves()[0].is_in_tail()


# An enemy of the open wave, or of no wave in the quiet, walking east from [param start].
func _spawn_heading_east(sim: Simulation, start: Vector2) -> int:
	var open := sim.waves.open_waves()
	var wave := open[0].index if not open.is_empty() else Waves.NO_WAVE
	var id := sim.enemies.spawn(start, _settings.enemy_hp, Enemies.Kind.NORMAL, wave)
	sim.tick()
	assert_float(_position(sim, id).x).is_greater(start.x)
	return id


func _land_pile(sim: Simulation, cell: Vector2i) -> void:
	var bodies := PackedVector2Array()
	for n in PILE_BODIES:
		bodies.append(Vector2(cell) + Vector2(0.5, 0.5))
	sim.piles.queue_bodies(Deaths.bodies_at(bodies))


func _kill(sim: Simulation, count: int) -> void:
	sim.queue_command(Commands.KillEnemies.new(count))
	sim.tick()


func _route(sim: Simulation, id: int) -> int:
	return sim.enemies.routes[sim.enemies.index_of(id)]


func _position(sim: Simulation, id: int) -> Vector2:
	return sim.enemies.positions[sim.enemies.index_of(id)]
