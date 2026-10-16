## The player's soldiers, in packed arrays swap-removed with an id map as Enemies keeps its
## enemies (ADR 0001), but apart from them: soldiers never count towards a wave.
class_name Soldiers
extends RefCounted

const NONE := -1
## A new soldier's targeting: the index of [constant Enemies.BLOATERS_FIRST] in
## [constant Enemies.TARGETINGS].
const DEFAULT_TARGETING := 0
## How far a standing soldier can be pushed off its spot before it walks all the way back, and
## how far it walks back on its own; further than that it will plan a path back (#190).
const SPOT_SLACK := 0.1
const WALK_BACK_REACH := 1.0
const _NO_CELL := Vector2i(-1, -1)
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
var _piles: Piles
var _solids: Solids
var _ids: Ids
var _index_by_id := {}
# The soldier id holding each cell as its spot, or NONE.
var _spot_holders := PackedInt32Array()
var _added := PackedInt32Array()
# 1 for a standing soldier walking back to its spot, until it gets there.
var _walking_back := PackedByteArray()


func _init(
	run_settings: Settings,
	run_map: MapData,
	run_occupancy: Occupancy,
	run_piles: Piles,
	run_structures: Structures,
	run_ids: Ids,
) -> void:
	_settings = run_settings
	_map = run_map
	_piles = run_piles
	_solids = Solids.new(_map, run_occupancy, _piles, run_structures, false)
	_ids = run_ids
	_spot_holders.resize(_map.width * _map.height)
	_spot_holders.fill(NONE)


## Adds up to [param wanted] soldiers beside [param area], one by one on the free cell the
## new-soldier rule picks, and returns how many found a cell.
func add_beside(area: Rect2i, wanted: int) -> int:
	for n in wanted:
		var cell := _free_cell_beside(area)
		if cell == _NO_CELL:
			return n
		add(cell)
	return wanted


## A new soldier standing on [param cell], which becomes its spot.
func add(cell: Vector2i) -> int:
	if count == ids.size():
		_grow()
	var id := _ids.next()
	var spot := _map.index_of(cell)
	ids[count] = id
	positions[count] = MapData.centre_of(cell)
	hp[count] = _settings.soldier_hp
	spots[count] = spot
	orders[count] = NONE
	path_cursors[count] = 0
	targetings[count] = DEFAULT_TARGETING
	cooldowns[count] = 0
	targets[count] = Enemies.NONE
	kills[count] = 0
	blast_killed[count] = 0
	_walking_back[count] = 0
	_spot_holders[spot] = id
	_index_by_id[id] = count
	_added.append(id)
	count += 1
	return id


func index_of(id: int) -> int:
	return _index_by_id.get(id, NONE)


func spot(index: int) -> Vector2i:
	return _map.cell_of(spots[index])


## The targeting of the soldier at [param index]: one of [constant Enemies.TARGETINGS].
func targeting(index: int) -> StringName:
	return Enemies.TARGETINGS[targetings[index]]


## Sets [param mode] on each soldier in [param soldier_ids]; ids of soldiers no longer living
## are skipped, since one can die between the order and the drain. Returns an error, or "".
func set_targeting(soldier_ids: PackedInt32Array, mode: StringName) -> String:
	var mode_index := Enemies.TARGETINGS.find(mode)
	if mode_index == NONE:
		return Buildings.BAD_TARGETING
	for id in soldier_ids:
		var index := index_of(id)
		if index != NONE:
			targetings[index] = mode_index
	return ""


## The level of the cell under the soldier at [param index]: 0 on the ground, 1–4 on a pile,
## 5 on a wall. Nothing is stored; it follows the cell.
func elevation(index: int) -> int:
	return _piles.levels[_map.index_of(Vector2i(positions[index]))]


## At [constant Simulation.Step.MOVE_UNITS], each standing soldier pushed off its spot walks
## back towards it, then every soldier is held off what is solid to it.
func step() -> void:
	var step_length := _settings.soldier_speed / Simulation.TICKS_PER_SECOND
	var radius := _settings.separation_radius
	for i in count:
		if orders[i] == NONE:
			var home := MapData.centre_of(_map.cell_of(spots[i]))
			var off := positions[i].distance_to(home)
			if off > WALK_BACK_REACH:
				_walking_back[i] = 0
			elif off > SPOT_SLACK:
				_walking_back[i] = 1
			if _walking_back[i] == 1:
				positions[i] = positions[i].move_toward(home, step_length)
				if positions[i] == home:
					_walking_back[i] = 0
		positions[i] = _solids.resolve(positions[i], radius)


## Not rock, the base or a building, and on the map. Walls and piles are open ground.
func can_stand_on(cell: Vector2i) -> bool:
	return not _solids.is_solid(cell)


## The soldiers added since the last call, in id order.
func take_added() -> PackedInt32Array:
	var added := _added
	_added = PackedInt32Array()
	return added


# The new-soldier rule: the free cell in the ring around [param area] whose centre is nearest
# the base's centre (ties to the lowest cell index), else the same in each ring further out,
# reached breadth-first through cells a soldier can stand on. _NO_CELL when no free cell can be
# reached.
func _free_cell_beside(area: Rect2i) -> Vector2i:
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
		var best := _NO_CELL
		var best_distance := INF
		for cell in ring:
			if _spot_holders[_map.index_of(cell)] != NONE:
				continue
			var distance := MapData.centre_of(cell).distance_squared_to(base_centre)
			if distance < best_distance or (distance == best_distance and _lower_index(cell, best)):
				best = cell
				best_distance = distance
		if best != _NO_CELL:
			return best
		ring = _next_ring(ring, seen)
	return _NO_CELL


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


# Whether [param cell] wins a tie with [param other]: it has the lower cell index, or there is
# no other yet.
func _lower_index(cell: Vector2i, other: Vector2i) -> bool:
	return other == _NO_CELL or _map.index_of(cell) < _map.index_of(other)


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
	_walking_back.resize(capacity)
