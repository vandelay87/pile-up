## The player's soldiers, in packed arrays swap-removed with an id map as Enemies keeps its
## enemies (ADR 0001), but apart from them: soldiers never count towards a wave.
class_name Soldiers
extends RefCounted

const NONE := -1
## A soldier's HP and speed until the soldiers settings group arrives with barracks (#188).
const HP := 45.0
const SPEED := 2.5
const NO_CELL := Vector2i(-1, -1)
## How far a standing soldier can be pushed off its spot before it walks back, and how far it
## walks back on its own; further than that it will plan a path back (#190).
const SPOT_SLACK := 0.1
const WALK_BACK_REACH := 1.0
const _FACES: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
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

var count := 0
var ids := PackedInt32Array()
var positions := PackedVector2Array()
var hp := PackedFloat32Array()
## The cell index each soldier holds when standing.
var spots := PackedInt32Array()
## The order each soldier is walking, or NONE when standing.
var orders := PackedInt32Array()
var path_cursors := PackedInt32Array()
## Each soldier's targeting: an index into [constant Enemies.TARGETINGS].
var targetings := PackedByteArray()
var cooldowns := PackedInt32Array()
var targets := PackedInt32Array()
## Enemies each soldier has killed this run.
var kills := PackedInt32Array()
## 1 for a soldier a blast took to 0 HP.
var blast_killed := PackedByteArray()

var _settings: Settings
var _map: MapData
var _occupancy: Occupancy
var _piles: Piles
var _ids: Ids
var _index_by_id := {}
# The soldier id holding each cell as its spot, or NONE.
var _spot_holders := PackedInt32Array()
var _added := PackedInt32Array()


func _init(
	run_settings: Settings,
	run_map: MapData,
	run_occupancy: Occupancy,
	run_piles: Piles,
	run_ids: Ids,
) -> void:
	_settings = run_settings
	_map = run_map
	_occupancy = run_occupancy
	_piles = run_piles
	_ids = run_ids
	_spot_holders.resize(_map.width * _map.height)
	_spot_holders.fill(NONE)


## A new soldier standing on [param cell], which becomes its spot.
func add(cell: Vector2i) -> int:
	if count == ids.size():
		_grow()
	var id := _ids.next()
	var spot := _map.index_of(cell)
	ids[count] = id
	positions[count] = Vector2(cell) + Vector2(0.5, 0.5)
	hp[count] = HP
	spots[count] = spot
	orders[count] = NONE
	path_cursors[count] = 0
	targetings[count] = Enemies.TARGETINGS.find(Enemies.BLOATERS_FIRST)
	cooldowns[count] = 0
	targets[count] = Enemies.NONE
	kills[count] = 0
	blast_killed[count] = 0
	_spot_holders[spot] = id
	_index_by_id[id] = count
	_added.append(id)
	count += 1
	return id


func index_of(id: int) -> int:
	return _index_by_id.get(id, NONE)


func spot(index: int) -> Vector2i:
	return _map.cell_of(spots[index])


## The level of the cell under the soldier at [param index]: 0 on the ground, 1–4 on a pile,
## 5 on a wall. Nothing is stored; it follows the cell.
func elevation(index: int) -> int:
	var pos := positions[index]
	return _piles.levels[int(pos.y) * _map.width + int(pos.x)]


## Step 5: each standing soldier pushed off its spot walks back towards it, then every soldier
## is held off what is solid to it.
func step() -> void:
	var step_length := SPEED / Simulation.TICKS_PER_SECOND
	var radius := _settings.separation_radius
	for i in count:
		if orders[i] == NONE:
			var home := Vector2(_map.cell_of(spots[i])) + Vector2(0.5, 0.5)
			var off := positions[i].distance_to(home)
			if off > SPOT_SLACK and off <= WALK_BACK_REACH:
				positions[i] = positions[i].move_toward(home, step_length)
		positions[i] = _resolve_collision(positions[i], radius)


## Where a new soldier appears beside [param area]: the free cell in the ring around it whose
## centre is nearest the base's centre (ties to the lowest cell index), else the same in each
## ring further out, reached breadth-first through cells a soldier can stand on. NO_CELL when
## no free cell can be reached.
func free_cell_beside(area: Rect2i) -> Vector2i:
	var base_centre := Vector2(_map.base.position) + Vector2(_map.base.size) / 2.0
	var seen := PackedByteArray()
	seen.resize(_map.width * _map.height)
	var ring: Array[Vector2i] = []
	for y in range(area.position.y - 1, area.end.y + 1):
		for x in range(area.position.x - 1, area.end.x + 1):
			var cell := Vector2i(x, y)
			if area.has_point(cell) or not can_stand_on(cell):
				continue
			seen[_map.index_of(cell)] = 1
			ring.append(cell)
	while not ring.is_empty():
		var best := NO_CELL
		var best_distance := INF
		for cell in ring:
			if _spot_holders[_map.index_of(cell)] != NONE:
				continue
			var distance := (Vector2(cell) + Vector2(0.5, 0.5)).distance_squared_to(base_centre)
			if distance < best_distance or (distance == best_distance and _before(cell, best)):
				best = cell
				best_distance = distance
		if best != NO_CELL:
			return best
		ring = _next_ring(ring, seen)
	return NO_CELL


## Not rock, the base or a building, and on the map.
func can_stand_on(cell: Vector2i) -> bool:
	return (
		_map.in_bounds(cell)
		and not _map.is_rock(cell)
		and not _map.is_base(cell)
		and not _occupancy.is_occupied(cell)
	)


## The soldiers added since the last call, in id order.
func take_added() -> PackedInt32Array:
	var added := _added
	_added = PackedInt32Array()
	return added


# [param pos] moved out of every solid cell's square to [param radius] from it, by the enemies'
# rule: buildings, rock, the base and the map's edge are solid; walls and piles are not.
func _resolve_collision(pos: Vector2, radius: float) -> Vector2:
	var margin := Vector2(radius, radius)
	pos = pos.clamp(margin, Vector2(_map.width, _map.height) - margin)
	var low := Vector2i((pos - margin).floor())
	var high := Vector2i((pos + margin).floor())
	for y in range(low.y, high.y + 1):
		for x in range(low.x, high.x + 1):
			var solid := Vector2i(x, y)
			if can_stand_on(solid):
				continue
			var closest := pos.clamp(Vector2(solid), Vector2(solid + Vector2i.ONE))
			var away := pos - closest
			var distance := away.length()
			if distance >= radius:
				continue
			if distance > 1e-6:
				pos = closest + away / distance * radius
			else:
				pos = _leave_through_nearest_open_face(pos, solid, radius)
	return pos


func _leave_through_nearest_open_face(pos: Vector2, cell: Vector2i, radius: float) -> Vector2:
	var inside := pos - Vector2(cell)
	var face_distances: Array[float] = [inside.x, 1.0 - inside.x, inside.y, 1.0 - inside.y]
	var best_face := Vector2i.ZERO
	var best_distance := INF
	for k in _FACES.size():
		if can_stand_on(cell + _FACES[k]) and face_distances[k] < best_distance:
			best_distance = face_distances[k]
			best_face = _FACES[k]
	if best_face == Vector2i.ZERO:
		return pos
	return pos + Vector2(best_face) * (best_distance + radius)


# The cells a soldier can step to from [param ring] that haven't been seen: 8-way, without
# cutting a corner past a cell it can't stand on.
func _next_ring(ring: Array[Vector2i], seen: PackedByteArray) -> Array[Vector2i]:
	var next: Array[Vector2i] = []
	for cell in ring:
		for step in _NEIGHBOURS:
			var neighbour := cell + step
			if not can_stand_on(neighbour) or seen[_map.index_of(neighbour)] == 1:
				continue
			var diagonal := step.x != 0 and step.y != 0
			if (
				diagonal
				and not (
					can_stand_on(cell + Vector2i(step.x, 0))
					and can_stand_on(cell + Vector2i(0, step.y))
				)
			):
				continue
			seen[_map.index_of(neighbour)] = 1
			next.append(neighbour)
	return next


func _before(cell: Vector2i, other: Vector2i) -> bool:
	return other == NO_CELL or _map.index_of(cell) < _map.index_of(other)


func _grow() -> void:
	var capacity := maxi(16, ids.size() * 2)
	ids.resize(capacity)
	positions.resize(capacity)
	hp.resize(capacity)
	spots.resize(capacity)
	orders.resize(capacity)
	path_cursors.resize(capacity)
	targetings.resize(capacity)
	cooldowns.resize(capacity)
	targets.resize(capacity)
	kills.resize(capacity)
	blast_killed.resize(capacity)
