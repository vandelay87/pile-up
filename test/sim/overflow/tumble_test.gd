extends GdUnitTestSuite

## Tumbling: an active crush sends its front rank over the barrier at its tier's rate.
##
## A 20×17 open field with a 2×3 base at (18, 7). Walls have 1000 HP so the crowd never breaks
## through, and the base has 10000. Enemies spawned west of a wall line walk east into it and
## are held there; a high fill takes the crush to a surge within a second or two.

const BASE := Rect2i(18, 7, 2, 3)
const TOUGH_WALL := 1000.0
const HEIGHT := 17
const LANDING_CROWD := 6

var _settings: Settings
var _sim: Simulation
# Every enemy id seen tumbling so far.
var _seen := {}


func before_test() -> void:
	var settings := TestSettings.without_swarm_spread()
	settings.change("run", "base_hp", 10000)
	_settings = settings.for_next_run()
	_settings.change("piles", "wall_hp", TOUGH_WALL)
	_settings.change("overflow", "leak", 5.0)
	var rows: Array[String] = []
	for y in HEIGHT:
		rows.append(".".repeat(20))
	_sim = Simulation.new(_settings, TestMaps.from_rows(rows, BASE), 1)
	_seen = {}


func test_a_surge_launches_15_a_second_and_each_takes_2_off_the_gauge() -> void:
	_settings.change("overflow", "fill_per_stalled", 10.0)
	_walls(_column(10, 0, HEIGHT - 1))
	_crowd(80, Rect2(1, 1, 8, HEIGHT - 2))
	_run_until_surge()
	var crush := _only_crush()

	var launched := 0
	for tick in Simulation.TICKS_PER_SECOND:
		var before := crush.gauge
		_sim.tick()
		var now := _take_new_tumblers().size()
		launched += now
		var filled := before + (10.0 * crush.stalled - 5.0) / Simulation.TICKS_PER_SECOND
		assert_float(crush.gauge).is_equal_approx(minf(filled, 120.0) - 2.0 * now, 1e-3)
		assert_int(crush.tier).is_equal(Overflow.Tier.SURGE)

	assert_int(launched).is_equal(15)


func test_an_attacker_isnt_picked_while_a_non_attacker_is_in_the_front_rank() -> void:
	# A wall row hangs off the wall line. The crowd jammed in the corner below it presses on
	# the row without attacking it, since no route crosses the row and nobody jams for long
	# enough; the front at the wall line attacks.
	_settings.change("enemies", "jam_seconds", 10.0)
	_settings.change("overflow", "fill_per_stalled", 10.0)
	_walls(_column(10, 0, HEIGHT - 1) + _row(12, 2, 9))
	_crowd(60, Rect2(1, 13, 9, 4))
	var mixed := 0
	var all_attacking := 0

	for tick in 15 * Simulation.TICKS_PER_SECOND:
		_sim.tick()
		var started := _take_new_tumblers()
		if started.is_empty():
			continue
		var crush := _only_crush()
		var free := _ids_of(crush.front_free)
		var attacking := _ids_of(crush.front_attacking)
		for id in started:
			if free.is_empty():
				assert_bool(attacking.has(id)).is_true()
			else:
				assert_bool(free.has(id)).is_true()
		if not free.is_empty() and not attacking.is_empty():
			mixed += 1
		elif free.is_empty():
			all_attacking += 1

	assert_int(mixed).is_greater_equal(3)
	assert_int(all_attacking).is_greater_equal(3)


func test_a_tumble_crosses_a_3_thick_block_to_the_first_free_cell_at_180_percent() -> void:
	_settings.change("overflow", "fill_per_stalled", 10.0)
	_walls(_column(9, 0, HEIGHT - 1) + _column(10, 0, HEIGHT - 1) + _column(11, 0, HEIGHT - 1))
	_crowd(60, Rect2(1, 1, 7, HEIGHT - 2))
	var id := _first_tumbler()
	var index := _sim.enemies.index_of(id)
	var tumble := _sim.overflow.tumble(id)

	assert_int(tumble.landing().x).is_equal(12)
	for cell: Vector2i in tumble.cells.slice(0, -1):
		assert_int(_sim.piles.level(cell)).is_equal(Piles.WALL_LEVEL)
	# 2 cells/s at 180%, along the way from where it was this tick.
	var at := _sim.enemies.positions[index]
	var left := 0.0
	for point in tumble.path.slice(tumble.next):
		left += at.distance_to(point)
		at = point
	var ticks := 0
	while _sim.overflow.is_tumbling(id):
		_sim.tick()
		ticks += 1
	assert_int(ticks).is_equal(ceili(left / (2.0 * 1.8 / Simulation.TICKS_PER_SECOND)))

	index = _sim.enemies.index_of(id)
	assert_object(_sim.enemies.positions[index]).is_equal(tumble.path[-1])
	assert_int(_sim.enemies.tumbling[index]).is_equal(0)
	assert_int(_sim.enemies.routes[index]).is_equal(Routing.Route.SENSIBLE)
	# It walks on from where it landed.
	_run(Simulation.TICKS_PER_SECOND)
	assert_float(_sim.enemies.positions[index].x).is_greater(tumble.path[-1].x)


func test_a_tumble_skips_a_cell_holding_6_enemies() -> void:
	_settings.change("overflow", "fill_per_stalled", 10.0)
	_walls(_column(10, 0, HEIGHT - 1))
	_crowd(80, Rect2(1, 1, 8, HEIGHT - 2))
	_run_until_surge()
	var crush := _only_crush()
	# The next tick launches one.
	while crush.credit < 0.75 - 1e-6:
		_sim.tick()
	_take_new_tumblers()
	# Six enemies on every cell just past the wall line.
	for y in HEIGHT:
		for n in LANDING_CROWD:
			_sim.enemies.spawn(Vector2(11.5, y + 0.5), _settings.enemy_hp)

	_sim.tick()

	var started := _take_new_tumblers()
	assert_int(started.size()).is_equal(1)
	var tumble := _sim.overflow.tumble(started[0])
	assert_int(tumble.cells[1].x).is_equal(11)
	assert_int(_sim.piles.level(tumble.cells[1])).is_equal(0)
	assert_int(tumble.landing().x).is_equal(12)


func test_a_tumble_reaching_the_base_ends_beside_it_and_the_enemy_attacks() -> void:
	# The wall line stands against the base's west side.
	_settings.change("overflow", "fill_per_stalled", 10.0)
	_walls(_column(17, 0, HEIGHT - 1))
	_crowd(80, Rect2(8, 1, 8, HEIGHT - 2))
	var base_cells := {}
	for cell in _sim.map.base_cells():
		base_cells[_sim.map.index_of(cell)] = true

	var id := Enemies.NONE
	var tumble: Overflow.Tumble = null
	for tick in 10 * Simulation.TICKS_PER_SECOND:
		_sim.tick()
		for started in _take_new_tumblers():
			var reaching := _sim.overflow.tumble(started)
			if BASE.has_point(reaching.cells[0] + Vector2i.RIGHT):
				id = started
				tumble = reaching
		if tumble != null:
			break
	assert_object(tumble).is_not_null()

	# Beside the base, nearest the base cell the line reached: above or below it.
	var landing := tumble.landing()
	assert_bool(BASE.has_point(landing)).is_false()
	assert_bool(BASE.grow(1).has_point(landing)).is_true()
	assert_int(landing.x).is_equal(18)
	while _sim.overflow.is_tumbling(id):
		_sim.tick()
	var hp := _sim.run_state.base_hp
	_run(Simulation.TICKS_PER_SECOND)
	var index := _sim.enemies.index_of(id)
	assert_bool(base_cells.has(_sim.enemies.structure_targets[index])).is_true()
	assert_float(_sim.run_state.base_hp).is_less(hp)


func test_a_tumbler_killed_mid_way_leaves_its_body_on_the_nearer_side() -> void:
	_settings.change("overflow", "fill_per_stalled", 10.0)
	_walls(_column(9, 0, HEIGHT - 1) + _column(10, 0, HEIGHT - 1) + _column(11, 0, HEIGHT - 1))
	_crowd(60, Rect2(1, 1, 7, HEIGHT - 2))
	var near := _kill_a_tumbler_between(9.0, 10.4)
	var far := _kill_a_tumbler_between(10.6, 12.0)
	_run(2)

	assert_int(_sim.piles.level(Vector2i(8, int(near.y)))).is_greater_equal(1)
	assert_int(_sim.piles.level(Vector2i(12, int(far.y)))).is_greater_equal(1)
	for x in range(9, 12):
		assert_int(_sim.piles.level(Vector2i(x, int(near.y)))).is_equal(Piles.WALL_LEVEL)
		assert_int(_sim.piles.level(Vector2i(x, int(far.y)))).is_equal(Piles.WALL_LEVEL)


func test_towers_shoot_tumblers() -> void:
	_settings.change("overflow", "fill_per_stalled", 10.0)
	_sim.queue_command(Commands.Build.new(Buildings.TOWER, Vector2i(13, 3)))
	_walls(_column(9, 0, HEIGHT - 1) + _column(10, 0, HEIGHT - 1) + _column(11, 0, HEIGHT - 1))
	_crowd(60, Rect2(1, 1, 7, HEIGHT - 2))
	var shot_tumbling := 0

	for tick in 5 * Simulation.TICKS_PER_SECOND:
		_sim.tick()
		for i in _sim.enemies.count:
			var hit := _sim.enemies.last_hitters[i] != Enemies.NONE
			if hit and _sim.overflow.is_tumbling(_sim.enemies.ids[i]):
				shot_tumbling += 1

	assert_int(shot_tumbling).is_greater(0)


func test_nothing_crossed_loses_hp_or_a_level() -> void:
	# A pylon sits in the middle of a 3-thick block. Attackers reach only its west column.
	_settings.change("overflow", "fill_per_stalled", 10.0)
	var pylon := Vector2i(10, 8)
	_sim.queue_command(Commands.Build.new(Buildings.PYLON, pylon))
	var middle := _column(10, 0, HEIGHT - 1)
	middle.erase(pylon)
	var far := _column(11, 0, HEIGHT - 1)
	_walls(_column(9, 0, HEIGHT - 1) + middle + far)
	_crowd(80, Rect2(1, 1, 7, HEIGHT - 2))
	var over_the_pylon := 0

	for tick in 8 * Simulation.TICKS_PER_SECOND:
		_sim.tick()
		for id in _take_new_tumblers():
			if pylon in _sim.overflow.tumble(id).cells:
				over_the_pylon += 1

	assert_int(_seen.size()).is_greater(50)
	assert_int(over_the_pylon).is_greater(0)
	for cell in middle + far:
		assert_int(_sim.piles.level(cell)).is_equal(Piles.WALL_LEVEL)
		assert_float(_sim.piles.wall_hp(cell)).is_equal(TOUGH_WALL)
	var built := _sim.buildings.building(_sim.occupancy.building_at(pylon))
	assert_float(built.hp).is_equal(_sim.buildings.max_hp(Buildings.PYLON))


func test_switching_overflow_off_stops_launches_and_lets_tumbles_land() -> void:
	_settings.change("overflow", "fill_per_stalled", 10.0)
	_walls(_column(9, 0, HEIGHT - 1) + _column(10, 0, HEIGHT - 1) + _column(11, 0, HEIGHT - 1))
	_crowd(60, Rect2(1, 1, 7, HEIGHT - 2))
	_run_until_surge()
	_run(10)
	var in_flight := _take_new_tumblers()
	for i in _sim.enemies.count:
		if _sim.overflow.is_tumbling(_sim.enemies.ids[i]):
			in_flight.append(_sim.enemies.ids[i])
	assert_array(in_flight).is_not_empty()

	_sim.queue_command(Commands.SetSetting.new("overflow", "enabled", 0))
	_run(3 * Simulation.TICKS_PER_SECOND)

	assert_array(_take_new_tumblers()).is_empty()
	for id in in_flight:
		assert_bool(_sim.overflow.is_tumbling(id)).is_false()
		assert_float(_sim.enemies.positions[_sim.enemies.index_of(id)].x).is_greater(12.0)


# Ticks until a tumbler's position is between [param left] and [param right], then kills it,
# returning where it died.
func _kill_a_tumbler_between(left: float, right: float) -> Vector2:
	for tick in 10 * Simulation.TICKS_PER_SECOND:
		_sim.tick()
		for i in _sim.enemies.count:
			var pos := _sim.enemies.positions[i]
			if _sim.overflow.is_tumbling(_sim.enemies.ids[i]) and pos.x > left and pos.x < right:
				_sim.enemies.kill(_sim.enemies.ids[i])
				return pos
	fail("no tumbler passed between %s and %s" % [left, right])
	return Vector2.ZERO


# Ticks until an enemy starts tumbling, returning its id.
func _first_tumbler() -> int:
	for tick in 10 * Simulation.TICKS_PER_SECOND:
		_sim.tick()
		var started := _take_new_tumblers()
		if not started.is_empty():
			return started[0]
	fail("nothing tumbled")
	return Enemies.NONE


func _run_until_surge() -> void:
	for tick in 10 * Simulation.TICKS_PER_SECOND:
		_sim.tick()
		var crushes := _sim.overflow.crushes()
		if not crushes.is_empty() and crushes[0].tier == Overflow.Tier.SURGE:
			_take_new_tumblers()
			return
	fail("the crush never reached a surge")


func _ids_of(indices: PackedInt32Array) -> Dictionary:
	var ids := {}
	for i in indices:
		ids[_sim.enemies.ids[i]] = true
	return ids


# The ids that started tumbling since the last call.
func _take_new_tumblers() -> Array[int]:
	var started: Array[int] = []
	for i in _sim.enemies.count:
		var id := _sim.enemies.ids[i]
		if _sim.overflow.is_tumbling(id) and not _seen.has(id):
			_seen[id] = true
			started.append(id)
	return started


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


# Lands a wall on each cell at step 1 of the next tick.
func _walls(cells: Array[Vector2i]) -> void:
	var bodies := PackedVector2Array()
	for cell in cells:
		for n in Piles.WALL_LEVEL:
			bodies.append(Vector2(cell) + Vector2(0.5, 0.5))
	_sim.piles.queue_bodies(Deaths.bodies_at(bodies))
	_sim.tick()


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
