extends GdUnitTestSuite

## Perching: a tumble over a barrier stops on top of the first building it crosses with room, or
## on the base, and the enemy attacks what it stands on until it falls.
##
## A 20×17 open field with a 2×3 base at (18, 7), as in the tumble tests. Walls have 1000 HP so
## the crowd never breaks through, and the base has 10000. Enemies spawned west of a wall line
## walk east into it and are held there; a high fill takes the crush to a surge within a second or
## two. Some tests perch enemies straight through [Perches] instead of waiting on a crush.

const BASE := Rect2i(18, 7, 2, 3)
const TOUGH_WALL := 1000.0
const HEIGHT := 17
const YARD := Vector2i(10, 7)

var _settings: Settings
var _sim: Simulation
# Every enemy id seen tumbling so far.
var _seen := {}
var _drops: Array[Perches.Drop] = []


func before_test() -> void:
	var settings := TestSettings.without_swarm_spread()
	settings.change("run", "base_hp", 10000)
	settings.change("run", "starting_gold", 5000)
	_settings = settings.for_next_run()
	_settings.change("piles", "wall_hp", TOUGH_WALL)
	_settings.change("overflow", "leak", 5.0)
	var rows: Array[String] = []
	for y in HEIGHT:
		rows.append(".".repeat(20))
	_sim = Simulation.new(_settings, TestMaps.from_rows(rows, BASE), 1)
	_sim.perched_bodies.connect(
		func(drops: Array[Perches.Drop]) -> void: _drops.append_array(drops)
	)
	_seen = {}
	_drops = []


func test_a_tumble_over_a_wall_then_a_building_perches_on_the_building() -> void:
	var yard := _yard_behind_a_wall_line()
	var footprint := Rect2i(yard.origin, Vector2i(2, 2))
	var id := _first_tumbler_onto(footprint)
	var tumble := _sim.overflow.tumble(id)

	assert_int(_sim.piles.level(tumble.cells[0])).is_equal(Piles.WALL_LEVEL)
	assert_bool(tumble.perching).is_true()
	assert_int(_sim.perches.claimed(yard.id)).is_greater_equal(1)
	while _sim.overflow.is_tumbling(id):
		_sim.tick()

	var index := _sim.enemies.index_of(id)
	assert_int(_sim.enemies.states[index]).is_equal(Enemies.State.PERCHED)
	assert_bool(Rect2(footprint).has_point(_sim.enemies.positions[index])).is_true()
	assert_int(_sim.perches.perched_on(id)).is_equal(yard.id)
	assert_int(_sim.perches.count(yard.id)).is_greater_equal(1)
	assert_int(_sim.perches.room(yard.id)).is_equal(8)
	# It stays put up there.
	var at := _sim.enemies.positions[index]
	_run(Simulation.TICKS_PER_SECOND)
	assert_vector(_sim.enemies.positions[_sim.enemies.index_of(id)]).is_equal(at)


func test_a_full_building_is_crossed() -> void:
	# A pylon in the middle of a 3-thick block holds one enemy at a perch room of 1. Attackers
	# reach only the block's west column.
	_settings.change("overflow", "fill_per_stalled", 10.0)
	_settings.change("overflow", "perch_room", 1)
	var pylon := Vector2i(10, 8)
	var built := _build(Buildings.PYLON, pylon)
	var middle := _column(10, 0, HEIGHT - 1)
	middle.erase(pylon)
	_walls(_column(9, 0, HEIGHT - 1) + middle + _column(11, 0, HEIGHT - 1))
	_crowd(80, Rect2(1, 1, 7, HEIGHT - 2))
	var crossed := 0

	for tick in 8 * Simulation.TICKS_PER_SECOND:
		_sim.tick()
		assert_int(_sim.perches.claimed(built.id)).is_less_equal(1)
		assert_int(_sim.perches.count(built.id)).is_less_equal(1)
		for id in _take_new_tumblers():
			var tumble := _sim.overflow.tumble(id)
			if pylon in tumble.cells and tumble.landing() != pylon:
				assert_int(_sim.perches.claimed(built.id)).is_equal(1)
				assert_bool(tumble.perching).is_false()
				assert_int(tumble.landing().x).is_greater(pylon.x)
				crossed += 1

	assert_int(_sim.perches.count(built.id)).is_equal(1)
	assert_int(crossed).is_greater(0)


func test_a_tumble_reaching_the_base_perches_while_it_has_room_then_stops_beside_it() -> void:
	# The wall line stands against the base's west side; at 1 a cell the base holds 6.
	_settings.change("overflow", "fill_per_stalled", 10.0)
	_settings.change("overflow", "base_perch_room", 1)
	_walls(_column(17, 0, HEIGHT - 1))
	_crowd(80, Rect2(8, 1, 8, HEIGHT - 2))
	var room := _sim.perches.room(Perches.BASE)
	var perching := 0
	var beside := 0

	for tick in 15 * Simulation.TICKS_PER_SECOND:
		_sim.tick()
		# Several tumbles are in flight at a surge; none overfills the base.
		assert_int(_sim.perches.claimed(Perches.BASE)).is_less_equal(room)
		assert_int(_sim.perches.on_base_count()).is_less_equal(room)
		for id in _take_new_tumblers():
			var tumble := _sim.overflow.tumble(id)
			if BASE.has_point(tumble.landing()):
				assert_bool(tumble.perching).is_true()
				perching += 1
			elif BASE.has_point(tumble.cells[0] + Vector2i.RIGHT):
				# It reached the base, full by then, and stops beside it.
				assert_bool(BASE.grow(1).has_point(tumble.landing())).is_true()
				assert_bool(tumble.perching).is_false()
				assert_int(_sim.perches.claimed(Perches.BASE)).is_equal(room)
				beside += 1

	assert_int(room).is_equal(6)
	assert_int(perching).is_equal(room)
	assert_int(_sim.perches.on_base_count()).is_equal(room)
	assert_int(beside).is_greater(0)


func test_a_claim_is_given_back_when_the_tumbler_dies_in_the_air() -> void:
	var yard := _yard_behind_a_wall_line()
	var id := _first_tumbler_onto(Rect2i(yard.origin, Vector2i(2, 2)))
	var claimed := _sim.perches.claimed(yard.id)
	# Nothing else takes the yard's room from here.
	_sim.queue_command(Commands.SetSetting.new("overflow", "enabled", 0))

	_sim.enemies.kill(id)
	_run(2)

	assert_int(_sim.perches.claimed(yard.id)).is_less(claimed)
	assert_int(_sim.perches.claimed(yard.id)).is_equal(
		_in_flight_onto(yard.id) + _sim.perches.count(yard.id)
	)


func test_a_perched_enemy_damages_its_building_at_2_hp_a_second_while_unpowered() -> void:
	var yard := _build(Buildings.REPAIR_YARD, YARD)
	_perch(YARD, Vector2i(9, 7))
	_perch(YARD + Vector2i.ONE, Vector2i(12, 8))
	_sim.queue_command(Commands.SetSetting.new("run", "base_power_area", 0))
	_sim.tick()
	assert_bool(yard.powered).is_false()
	var hp := yard.hp

	_run(Simulation.TICKS_PER_SECOND)

	assert_float(hp - yard.hp).is_equal_approx(2.0 * 2.0, 1e-3)


func test_a_destroyed_building_puts_its_perched_enemies_back_to_walking_on_its_footprint() -> void:
	var pylon := Vector2i(10, 8)
	var built := _build(Buildings.PYLON, pylon)
	var ids: Array[int] = [_perch(pylon, Vector2i(9, 8)), _perch(pylon, Vector2i(9, 8))]

	var ticks := 0
	while _sim.buildings.building(built.id) != null:
		_sim.tick()
		ticks += 1
	# 20 HP at 2 enemies × 2 HP/s.
	assert_int(ticks).is_between(299, 301)

	for id in ids:
		var index := _sim.enemies.index_of(id)
		assert_int(_sim.enemies.states[index]).is_equal(Enemies.State.WALKING)
		assert_int(_sim.enemies.routes[index]).is_equal(Routing.Route.SENSIBLE)
		(
			assert_bool(Rect2(Vector2(pylon), Vector2.ONE).has_point(_sim.enemies.positions[index]))
			. is_true()
		)
		assert_bool(_sim.perches.is_perched(id)).is_false()
	assert_int(_sim.perches.count(built.id)).is_equal(0)
	var at := _sim.enemies.positions[_sim.enemies.index_of(ids[0])]
	_run(Simulation.TICKS_PER_SECOND)
	assert_vector(_sim.enemies.positions[_sim.enemies.index_of(ids[0])]).is_not_equal(at)


func test_a_perched_bloater_lights_its_fuse_and_its_blast_releases_the_rest() -> void:
	_settings.change("bloaters", "blast_radius", 1.0)
	var tower := _build(Buildings.TOWER, YARD)
	_sim.buildings.damage(tower.id, tower.hp - 10.0)
	_sim.queue_command(Commands.SetSetting.new("run", "base_power_area", 0))
	var bloater := _perch_from(YARD, MapData.centre_of(YARD), Vector2i(9, 7), Enemies.Kind.BLOATER)
	var other := _perch_from(
		YARD + Vector2i.ONE, MapData.centre_of(YARD + Vector2i.ONE), Vector2i(9, 8)
	)

	assert_int(_sim.enemies.fuse(bloater)).is_greater(0)
	var hp := tower.hp
	_sim.tick()
	# The bloater holds without damage; the other enemy deals its 2 HP/s.
	assert_float(hp - tower.hp).is_equal_approx(2.0 / Simulation.TICKS_PER_SECOND, 1e-4)
	while _sim.enemies.index_of(bloater) != Enemies.NONE:
		_sim.tick()

	assert_object(_sim.buildings.building(tower.id)).is_null()
	var index := _sim.enemies.index_of(other)
	assert_int(index).is_not_equal(Enemies.NONE)
	assert_int(_sim.enemies.states[index]).is_equal(Enemies.State.WALKING)
	assert_bool(_sim.perches.is_perched(other)).is_false()


func test_a_perched_enemys_body_drops_off_the_side_it_came_from() -> void:
	var yard := _yard_behind_a_wall_line()
	var id := _first_tumbler_onto(Rect2i(yard.origin, Vector2i(2, 2)))
	var tumble := _sim.overflow.tumble(id)
	var from := Vector2i(tumble.from.floor())
	# Walking back from the yard, the wall is skipped: it drops where the tumble started.
	assert_vector(tumble.drop_cell).is_equal(from)
	while _sim.overflow.is_tumbling(id):
		_sim.tick()
	assert_vector(_sim.perches.drop_cell(id)).is_equal(from)
	_sim.queue_command(Commands.SetSetting.new("overflow", "enabled", 0))
	_run(2)
	var level := _sim.piles.level(from)
	var roof := _sim.enemies.positions[_sim.enemies.index_of(id)]

	_sim.enemies.kill(id)
	_run(2)

	assert_int(_sim.piles.level(from)).is_equal(level + 1)
	assert_int(_drops.size()).is_equal(1)
	assert_int(_drops[0].id).is_equal(id)
	assert_vector(_drops[0].died_at).is_equal(roof)
	assert_vector(_drops[0].cell).is_equal(from)
	for cell in Buildings.cells_of(Buildings.REPAIR_YARD, yard.origin):
		assert_int(_sim.piles.level(cell)).is_equal(0)


func test_the_drop_off_cell_is_the_first_on_the_way_back_that_is_no_structure() -> void:
	# A wall, a clear cell, a second wall and the yard: the body drops on the clear cell between.
	var yard := _build(Buildings.REPAIR_YARD, Vector2i(11, 7))
	_settings.change("overflow", "landing_crowd", 1)
	_walls(_column(8, 0, HEIGHT - 1) + _column(10, 0, HEIGHT - 1))
	# One enemy on every cell of the gap, so no tumble lands in it.
	for y in HEIGHT:
		_sim.enemies.spawn(Vector2(9.5, y + 0.5), 1000.0)
	_settings.change("overflow", "fill_per_stalled", 10.0)
	_crowd(80, Rect2(1, 1, 6, HEIGHT - 2))
	var id := _first_tumbler_onto(Rect2i(yard.origin, Vector2i(2, 2)))

	var tumble := _sim.overflow.tumble(id)
	assert_int(tumble.drop_cell.x).is_equal(9)


func test_a_grinder_hurts_the_enemies_perched_on_it_and_not_those_on_its_neighbour() -> void:
	var grinder := _build(Buildings.GRINDER, YARD)
	var yard := _build(Buildings.REPAIR_YARD, YARD + Vector2i(2, 0))
	var on_grinder := _perch(YARD + Vector2i(1, 0), Vector2i(9, 7))
	# Its spot is a fraction of a cell from the grinder's edge.
	var on_yard := _perch(YARD + Vector2i(2, 0), Vector2i(11, 7))

	_run(Simulation.TICKS_PER_SECOND)

	var hp := _settings.enemy_hp
	assert_float(_sim.enemies.hp[_sim.enemies.index_of(on_grinder)]).is_equal_approx(hp - 3.0, 1e-3)
	assert_float(_sim.enemies.hp[_sim.enemies.index_of(on_yard)]).is_equal(hp)
	assert_int(yard.id).is_not_equal(grinder.id)


func test_a_grinder_that_kills_a_perched_enemy_gets_the_kill() -> void:
	var grinder := _build(Buildings.GRINDER, YARD)
	_perch(YARD, Vector2i(9, 7))

	_run(4 * Simulation.TICKS_PER_SECOND)

	assert_int(grinder.kills).is_equal(1)


func test_a_perched_enemy_takes_no_soldier_target_is_never_pushed_and_is_shot() -> void:
	_build(Buildings.REPAIR_YARD, YARD)
	var id := _perch(YARD, Vector2i(9, 7))
	var index := _sim.enemies.index_of(id)
	_sim.enemies.hp[index] = 1000.0
	var at := _sim.enemies.positions[index]
	var soldier := _sim.soldiers.add(Vector2i(9, 7))
	_sim.soldiers.positions[_sim.soldiers.index_of(soldier)] = at + Vector2(-0.4, 0.0)

	_run(2 * Simulation.TICKS_PER_SECOND)

	index = _sim.enemies.index_of(id)
	assert_vector(_sim.enemies.positions[index]).is_equal(at)
	assert_int(_sim.enemies.soldier_targets[index]).is_equal(Enemies.NONE)
	assert_int(_sim.enemies.last_hitters[index]).is_equal(soldier)
	assert_float(_sim.enemies.hp[index]).is_less(1000.0)


func test_perched_enemies_count_towards_no_crush() -> void:
	_settings.change("overflow", "fill_per_stalled", 10.0)
	_build(Buildings.REPAIR_YARD, YARD)
	_walls(_column(9, 0, HEIGHT - 1))
	for n in 8:
		var id := _perch(YARD + Vector2i(n % 2, n / 4), Vector2i(8, 7))
		_sim.enemies.progress[_sim.enemies.index_of(id)] = 0.0

	_run(2 * Simulation.TICKS_PER_SECOND)

	assert_array(_sim.overflow.crushes()).is_empty()


func test_closest_to_base_ranks_a_perched_enemy_ahead_of_the_crowd_it_crossed() -> void:
	_build(Buildings.REPAIR_YARD, YARD)
	var tower := _build(Buildings.TOWER, Vector2i(12, 11))
	_sim.queue_command(Commands.SetTargeting.new(tower.id, Enemies.CLOSEST_TO_BASE))
	_walls(_column(9, 0, HEIGHT - 1))
	var crowd := _crowd(6, Rect2(7, 6, 2, 4))
	for id in crowd:
		_sim.enemies.hp[_sim.enemies.index_of(id)] = 1000.0
	var perched := _perch(YARD, Vector2i(8, 7))
	_sim.enemies.hp[_sim.enemies.index_of(perched)] = 1000.0

	_run(2)

	assert_int(tower.target_id).is_equal(perched)
	var index := _sim.enemies.index_of(perched)
	assert_float(_sim.enemies.hp[index]).is_equal(1000.0 - _settings.tower_damage)


# A repair yard at YARD, in the second column behind a wall line at x 9, with a crowd west of it.
func _yard_behind_a_wall_line() -> Buildings.Building:
	_settings.change("overflow", "fill_per_stalled", 10.0)
	var yard := _build(Buildings.REPAIR_YARD, YARD)
	_walls(_column(9, 0, HEIGHT - 1))
	_crowd(80, Rect2(1, 1, 7, HEIGHT - 2))
	return yard


# Ticks until a tumble that ends in [param footprint] starts, returning its enemy's id.
func _first_tumbler_onto(footprint: Rect2i) -> int:
	for tick in 15 * Simulation.TICKS_PER_SECOND:
		_sim.tick()
		for id in _take_new_tumblers():
			if footprint.has_point(_sim.overflow.tumble(id).landing()):
				return id
	fail("no tumble ended on %s" % footprint)
	return Enemies.NONE


# The tumbles in flight that will perch on the building with id [param building_id].
func _in_flight_onto(building_id: int) -> int:
	var found := 0
	for i in _sim.enemies.count:
		var tumble := _sim.overflow.tumble(_sim.enemies.ids[i])
		if tumble != null and tumble.perching:
			if _sim.occupancy.building_at(tumble.landing()) == building_id:
				found += 1
	return found


# Spawns an enemy and perches it on [param cell] straight away, as if its path entered the cell
# from the centre of [param drop], where its body drops off, returning its id.
func _perch(cell: Vector2i, drop: Vector2i, kind := Enemies.Kind.NORMAL) -> int:
	return _perch_from(cell, MapData.centre_of(drop), drop, kind)


# As [method _perch], entering the cell from [param entered_from].
func _perch_from(
	cell: Vector2i, entered_from: Vector2, drop: Vector2i, kind := Enemies.Kind.NORMAL
) -> int:
	var id := _sim.enemies.spawn(entered_from, _settings.enemy_hp, kind)
	assert_bool(_sim.perches.claim(cell)).is_true()
	_sim.perches.perch(_sim.enemies.index_of(id), cell, drop, entered_from)
	return id


func _build(kind: StringName, origin: Vector2i) -> Buildings.Building:
	_sim.queue_command(Commands.Build.new(kind, origin))
	_sim.tick()
	var built := _sim.buildings.building(_sim.occupancy.building_at(origin))
	assert_object(built).is_not_null()
	return built


# The ids that started tumbling since the last call.
func _take_new_tumblers() -> Array[int]:
	var started: Array[int] = []
	for i in _sim.enemies.count:
		var id := _sim.enemies.ids[i]
		if _sim.overflow.is_tumbling(id) and not _seen.has(id):
			_seen[id] = true
			started.append(id)
	return started


func _column(x: int, top: int, bottom: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in range(top, bottom + 1):
		cells.append(Vector2i(x, y))
	return cells


# Lands a wall on each cell as bodies land on the next tick.
func _walls(cells: Array[Vector2i]) -> void:
	var bodies := PackedVector2Array()
	for cell in cells:
		for n in Piles.WALL_LEVEL:
			bodies.append(Vector2(cell) + Vector2(0.5, 0.5))
	_sim.piles.queue_bodies(Deaths.bodies_at(bodies))
	_sim.tick()
	while _sim.routing.is_settling():
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
