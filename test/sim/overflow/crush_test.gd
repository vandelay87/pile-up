extends GdUnitTestSuite

## Crushes: a crowd stalled against a run of walls and buildings fills that run's gauge.
##
## A 20×17 open field with a 2×3 base at (18, 7). Walls have 1000 HP so the crowd never breaks
## through, and the base has 10000. Enemies spawned west of a wall line walk east into it and
## are held there.

const BASE := Rect2i(18, 7, 2, 3)
const TOUGH_WALL := 1000.0
const HEIGHT := 17

var _settings: Settings
var _sim: Simulation


func before_test() -> void:
	var settings := TestSettings.without_swarm_spread()
	settings.change("run", "base_hp", 10000)
	_settings = settings.for_next_run()
	_settings.change("piles", "wall_hp", TOUGH_WALL)
	var rows: Array[String] = []
	for y in HEIGHT:
		rows.append(".".repeat(20))
	_sim = Simulation.new(_settings, TestMaps.from_rows(rows, BASE), 1)


func test_enemies_held_against_a_wall_fill_its_gauge_by_half_a_point_each_less_the_leak() -> void:
	_walls(_column(10, 0, HEIGHT - 1))
	_crowd(20, Rect2(3, 5, 5, 7))
	_run(8 * Simulation.TICKS_PER_SECOND)

	var crush := _only_crush()
	assert_int(crush.stalled).is_equal(20)
	assert_bool(crush.active).is_true()
	# Each tick adds (0.5 × stalled − 5) / 60; the crowd jostles, so count each tick's stalled.
	var expected := crush.gauge
	for tick in Simulation.TICKS_PER_SECOND:
		_sim.tick()
		expected += (0.5 * crush.stalled - 5.0) / Simulation.TICKS_PER_SECOND
		assert_int(crush.stalled).is_greater_equal(15)

	assert_float(crush.gauge).is_equal_approx(expected, 1e-3)
	assert_float(crush.gauge).is_greater(_settings.crush_start)


func test_a_clump_walking_past_a_wall_fills_no_gauge() -> void:
	_walls(_row(2, 3, 11))
	_crowd(16, Rect2(0.5, 3, 3, 4))

	for tick in 6 * Simulation.TICKS_PER_SECOND:
		_sim.tick()
		assert_array(_sim.overflow.crushes()).is_empty()
	# It went by inside the band.
	assert_int(_sim.overflow.band_label(Vector2i(7, 4))).is_not_equal(Overflow.NONE)


func test_a_gauge_leaks_5_a_second_once_its_crowd_is_gone_then_the_crush_is_dropped() -> void:
	_hold_a_crowd()
	var crush := _only_crush()
	var gauge := crush.gauge
	_sim.kill_enemies(_sim.enemies.count)

	_run(Simulation.TICKS_PER_SECOND)
	assert_float(crush.gauge).is_equal_approx(gauge - 5.0, 1e-3)

	_run(ceili(gauge / 5.0) * Simulation.TICKS_PER_SECOND)
	assert_array(_sim.overflow.crushes()).is_empty()


func test_a_crush_starts_above_10_and_ends_below_4() -> void:
	_walls(_column(10, 0, HEIGHT - 1))
	_crowd(20, Rect2(3, 5, 5, 7))
	var rising := _watch_until(func(crush: Overflow.Crush) -> bool: return crush.active)
	_sim.kill_enemies(_sim.enemies.count)
	var falling := _watch_until(func(crush: Overflow.Crush) -> bool: return not crush.active)

	# Rising, it stays inactive up to 10, through readings between 4 and 10.
	assert_float(rising[-2].x).is_between(4.0, 10.0)
	assert_float(rising[-1].x).is_greater(10.0)
	for reading: Vector2 in rising.slice(0, -1):
		assert_float(reading.y).is_equal(0.0)
	# Falling, it stays active down to 4, through readings between 4 and 10.
	assert_float(falling[-2].x).is_between(4.0, 10.0)
	assert_float(falling[-1].x).is_less(4.0)
	for reading: Vector2 in falling.slice(0, -1):
		assert_float(reading.y).is_equal(1.0)


func test_an_active_crush_is_a_trickle_from_20_a_stream_from_50_and_a_surge_from_90() -> void:
	_settings.change("overflow", "fill_per_stalled", 2.0)
	_walls(_column(10, 0, HEIGHT - 1))
	_crowd(20, Rect2(3, 5, 5, 7))
	var seen := {}
	for tick in 12 * Simulation.TICKS_PER_SECOND:
		_sim.tick()
		for crush in _sim.overflow.crushes():
			if not crush.active:
				assert_int(crush.tier).is_equal(Overflow.Tier.NONE)
				continue
			seen[crush.tier] = true
			if crush.gauge < 20.0:
				assert_int(crush.tier).is_equal(Overflow.Tier.NONE)
			elif crush.gauge < 50.0:
				assert_int(crush.tier).is_equal(Overflow.Tier.TRICKLE)
			elif crush.gauge < 90.0:
				assert_int(crush.tier).is_equal(Overflow.Tier.STREAM)
			else:
				assert_int(crush.tier).is_equal(Overflow.Tier.SURGE)
	assert_dict(seen).has_size(4)
	# Capped at 120.
	assert_float(_only_crush().gauge).is_equal(120.0)


func test_a_crowd_at_each_end_of_one_long_wall_shares_one_gauge() -> void:
	_walls(_column(10, 0, HEIGHT - 1))
	var north := _crowd(10, Rect2(5, 0.5, 3, 3))
	var south := _crowd(10, Rect2(5, HEIGHT - 3.5, 3, 3))
	_run(8 * Simulation.TICKS_PER_SECOND)

	assert_float(_sim.enemies.positions[_sim.enemies.index_of(north[0])].y).is_less(5.0)
	assert_float(_sim.enemies.positions[_sim.enemies.index_of(south[0])].y).is_greater(11.0)
	assert_int(_only_crush().stalled).is_greater_equal(18)


func test_piles_below_a_wall_and_the_base_never_make_a_crush() -> void:
	# Levels 1 to 4 in columns 14 to 17, right up to the base, where the crowd stalls.
	for level in range(1, Piles.WALL_LEVEL):
		_piles(_column(13 + level, 0, HEIGHT - 1), level)
	_crowd(20, Rect2(1, 5, 4, 7))

	for tick in 15 * Simulation.TICKS_PER_SECOND:
		_sim.tick()
		assert_array(_sim.overflow.crushes()).is_empty()
	# The crowd reached the base and is attacking it.
	assert_float(_sim.run_state.base_hp).is_less(10000.0)
	assert_int(_sim.overflow.run_label(Vector2i(17, 8))).is_equal(Overflow.NONE)


func test_a_gauge_survives_a_wall_forming_beside_its_run() -> void:
	_hold_a_crowd()
	var crush := _only_crush()
	var gauge := crush.gauge

	_walls([Vector2i(11, 0)])

	assert_object(_only_crush()).is_same(crush)
	assert_int(_sim.overflow.run_label(Vector2i(11, 0))).is_equal(crush.label)
	assert_float(crush.gauge).is_greater(gauge)


func test_switching_overflow_off_empties_every_gauge() -> void:
	_hold_a_crowd()

	_sim.queue_command(Commands.SetSetting.new("overflow", "enabled", 0))
	_run(Simulation.TICKS_PER_SECOND)

	assert_array(_sim.overflow.crushes()).is_empty()


func _hold_a_crowd() -> void:
	_walls(_column(10, 0, HEIGHT - 1))
	_crowd(20, Rect2(3, 5, 5, 7))
	_run(8 * Simulation.TICKS_PER_SECOND)
	assert_bool(_only_crush().active).is_true()


# Ticks until the only crush meets [param done], returning each tick's (gauge, active).
func _watch_until(done: Callable) -> Array[Vector2]:
	var readings: Array[Vector2] = []
	for tick in 30 * Simulation.TICKS_PER_SECOND:
		_sim.tick()
		var crushes := _sim.overflow.crushes()
		if crushes.is_empty():
			continue
		readings.append(Vector2(crushes[0].gauge, 1.0 if crushes[0].active else 0.0))
		if done.call(crushes[0]):
			return readings
	fail("the crush never changed")
	return readings


func _only_crush() -> Overflow.Crush:
	var crushes := _sim.overflow.crushes()
	assert_int(crushes.size()).is_equal(1)
	return crushes[0]


func _column(x: int, top: int, bottom: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in range(top, bottom + 1):
		cells.append(Vector2i(x, y))
	return cells


func _row(y: int, left: int, right: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for x in range(left, right + 1):
		cells.append(Vector2i(x, y))
	return cells


# Lands a pile of [param level] on each cell at step 1 of the next tick.
func _piles(cells: Array[Vector2i], level: int) -> void:
	var bodies := PackedVector2Array()
	for cell in cells:
		for n in level:
			bodies.append(Vector2(cell) + Vector2(0.5, 0.5))
	_sim.piles.queue_bodies(Deaths.bodies_at(bodies))
	_sim.tick()


# Lands a wall on each cell at step 1 of the next tick.
func _walls(cells: Array[Vector2i]) -> void:
	_piles(cells, Piles.WALL_LEVEL)


# Spawns enemies spread in a grid across the area.
func _crowd(count: int, area: Rect2) -> Array[int]:
	var ids: Array[int] = []
	var columns := ceili(sqrt(count))
	for n in count:
		var at := Vector2(n % columns + 0.5, n / columns + 0.5) / columns
		ids.append(_sim.enemies.spawn(area.position + at * area.size, _settings.enemy_hp))
	return ids


func _run(ticks: int) -> void:
	for tick in ticks:
		_sim.tick()
