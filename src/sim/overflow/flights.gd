class_name Flights
extends RefCounted

## The way over a barrier for a tumble or a jump, shared by [Overflow] and [Jumps]: planned
## straight over the touched cell that faces the base, else down the direct field's parent chain,
## ending perched on the first building with room (claimed through [Perches]) or on the base, else
## on the first clear or pile cell that isn't crowded. And the landing at its end.
##
## A tumble crosses as many walls and full buildings as it meets, and a full base sends it to the
## free cell beside it. A jump crosses at most its reach of them, never goes past the base, and a
## full base means no jump.

## A tumble's plan: no limit on the cells it crosses.
const NO_REACH := -1
# How many cells the direct field's chain may run before it reaches the barrier it crosses.
const _MAX_LEAD_IN := 2
const _NEIGHBOURS: Array[Vector2i] = [
	Vector2i(-1, -1),
	Vector2i(0, -1),
	Vector2i(1, -1),
	Vector2i(-1, 0),
	Vector2i(1, 0),
	Vector2i(-1, 1),
	Vector2i(0, 1),
	Vector2i(1, 1),
]

var _settings: Settings
var _map: MapData
var _structures: Structures
var _enemies: Enemies
var _routing: Routing
var _perches: Perches


func _init(
	run_settings: Settings,
	run_map: MapData,
	run_structures: Structures,
	run_enemies: Enemies,
	run_routing: Routing,
	run_perches: Perches,
) -> void:
	_settings = run_settings
	_map = run_map
	_structures = run_structures
	_enemies = run_enemies
	_routing = run_routing
	_perches = run_perches


## The tumble the enemy at [param i] would take over the barrier it touches, or null.
func plan_tumble(i: int) -> Overflow.Tumble:
	var planned := _plan_straight(i, NO_REACH)
	return planned if planned != null else _plan_along_direct(i, NO_REACH)


## The jump the enemy at [param i] would take over at most [param reach] wall and building cells,
## or null when the barrier is too thick, the base is full, or there is nowhere to land.
func plan_jump(i: int, reach: int) -> Overflow.Tumble:
	var planned := _plan_straight(i, reach)
	return planned if planned != null else _plan_along_direct(i, reach)


## Perches the enemy at [param i] at the end of [param way]. False when what it claimed room on
## is gone or has been replaced, so it lands there instead.
func perch(i: int, way: Overflow.Tumble) -> bool:
	var landing := way.landing()
	if _perches.target_at(landing) != way.target:
		return false
	var entered_from := way.from if way.path.size() < 2 else way.path[-2]
	return _perches.perch(i, landing, way.drop_cell, entered_from)


# Straight over the wall or building cell the enemy touches that faces most nearly towards the
# base by the direct field, in one of 8 directions, to the first cell it can land on along that
# line: a building with room or the base perches it. A jump may start from the base it touches.
# Null when nothing it touches faces forwards, the line hits rock or the map's edge, or a jump
# would cross more than its reach.
func _plan_straight(i: int, reach: int) -> Overflow.Tumble:
	var jumping := reach != NO_REACH
	var pos := _enemies.positions[i]
	var cell := Vector2i(pos.floor())
	var heading := _routing.sample_direction(Routing.Route.DIRECT, pos)
	var touch := _settings.separation_radius + _settings.wall_reach
	var best := Vector2i.ZERO
	var best_facing := 0.0
	for offset in _NEIGHBOURS:
		var touched := cell + offset
		if not _map.in_bounds(touched):
			continue
		var index := _map.index_of(touched)
		var counts := (
			_structures.is_structure(index) if jumping else _structures.is_breakable(index)
		)
		if not counts or _distance_to_square(pos, touched) > touch:
			continue
		var facing := Vector2(offset).normalized().dot(heading)
		if facing > best_facing:
			best_facing = facing
			best = offset
	if best == Vector2i.ZERO:
		return null
	return _plan_line(i, cell + best, best, reach)


# Along the line from [param at] in steps of [param step], for [method _plan_straight].
func _plan_line(i: int, at: Vector2i, step: Vector2i, reach: int) -> Overflow.Tumble:
	var jumping := reach != NO_REACH
	var planned := Overflow.Tumble.new()
	var crossed := 0
	while _map.in_bounds(at):
		var index := _map.index_of(at)
		if _map.rock[index] == 1:
			break
		if _structures.is_base(index):
			return _end_at_base(planned, at, i, jumping)
		planned.add(at)
		if _perches.claim(at):
			return _perching(planned, i)
		if _structures.is_breakable(index):
			crossed += 1
			if jumping and crossed > reach:
				break
		elif _can_land(index):
			return planned
		at += step
	return null


# Down the direct field's chain from the enemy, over the barrier it meets within a couple of
# cells, to the first cell it can land on: a building with room or the base perches it. Null
# when the chain crosses no barrier, or a jump would cross more than its reach. A tumble that
# meets the base before any barrier isn't planned; a jump onto it is.
func _plan_along_direct(i: int, reach: int) -> Overflow.Tumble:
	var jumping := reach != NO_REACH
	var parents := _routing.parents(Routing.Route.DIRECT)
	var cell := _map.index_of(Vector2i(_enemies.positions[i].floor()))
	var planned := Overflow.Tumble.new()
	var crossed := 0
	for _step in parents.size():
		var next := parents[cell]
		if next < 0:
			break
		var at := _map.cell_of(next)
		if _structures.is_base(next):
			return _end_at_base(planned, at, i, jumping) if jumping or crossed > 0 else null
		planned.add(at)
		if _perches.claim(at):
			return _perching(planned, i)
		if _structures.is_breakable(next):
			crossed += 1
			if jumping and crossed > reach:
				break
		elif crossed > 0:
			if _can_land(next):
				return planned
		elif planned.cells.size() > _MAX_LEAD_IN:
			break
		cell = next
	return null


# Ends [param planned] perched on the base cell [param reached] if the base has room, else
# beside it for a tumble; a jump at a full base isn't planned.
func _end_at_base(
	planned: Overflow.Tumble, reached: Vector2i, i: int, jumping: bool
) -> Overflow.Tumble:
	if not _perches.claim(reached):
		return null if jumping else _end_beside_base(planned, reached)
	planned.add(reached)
	return _perching(planned, i)


# Marks [param planned], whose last cell's room the enemy at [param i] has claimed, as perching,
# and sets its drop-off cell.
func _perching(planned: Overflow.Tumble, i: int) -> Overflow.Tumble:
	planned.perching = true
	planned.target = _perches.target_at(planned.landing())
	planned.drop_cell = Vector2i(_enemies.positions[i].floor())
	for k in range(planned.cells.size() - 2, -1, -1):
		var cell := planned.cells[k]
		if not _structures.is_structure(_map.index_of(cell)):
			planned.drop_cell = cell
			break
	return planned


# Clear or a pile, and not crowded; the caller has ruled out rock and the base.
func _can_land(index: int) -> bool:
	return (
		not _structures.is_breakable(index)
		and _enemies.count_in_cell(index) < _settings.landing_crowd
	)


# Ends [param planned] on the free cell beside the base nearest [param reached], the base cell
# it got to, ties to the lower row then column. Null when the base has no free cell beside it.
# A free cell is clear or a pile, and not crowded.
func _end_beside_base(planned: Overflow.Tumble, reached: Vector2i) -> Overflow.Tumble:
	var ring := _map.base.grow(1)
	var best := Vector2i(-1, -1)
	var best_distance := INF
	for y in range(ring.position.y, ring.end.y):
		for x in range(ring.position.x, ring.end.x):
			var beside := Vector2i(x, y)
			if not _map.in_bounds(beside):
				continue
			var index := _map.index_of(beside)
			if _map.rock[index] == 1 or _structures.is_base(index) or not _can_land(index):
				continue
			var distance := Vector2(reached).distance_squared_to(Vector2(beside))
			if distance < best_distance:
				best_distance = distance
				best = beside
	if best_distance == INF:
		return null
	planned.add(best)
	return planned


static func _distance_to_square(pos: Vector2, cell: Vector2i) -> float:
	var corner := Vector2(cell)
	return pos.distance_to(pos.clamp(corner, corner + Vector2.ONE))
