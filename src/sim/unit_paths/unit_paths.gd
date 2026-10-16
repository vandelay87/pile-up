## Paths for soldiers, never the enemies' flow fields: one Dijkstra field per Move order and per
## rally point, grown outwards from its anchor over cells a soldier can stand on and settled
## under one shared per-tick budget, oldest field first. A field stops settling once every cell
## it needs (its soldiers' cells and slots) is settled, and takes up again when it needs more.
## Walkable regions say which cells a soldier can reach from which.
class_name UnitPaths
extends RefCounted

## The most field cells settled in one tick, across every field in flight: about 0.8 ms on the
## M5 release build, so an order across the map is ready in a handful of ticks. A cell count
## rather than a time, so runs replay exactly.
const PATH_SETTLE_CELLS := 200
const NONE := -1
const UNREACHABLE := INF
const NO_AIM := Vector2(-1.0, -1.0)
const _DIAGONAL_EXTRA := 0.41421356237309515
const _OFFSETS: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(0, -1),
	Vector2i(1, 1),
	Vector2i(-1, 1),
	Vector2i(1, -1),
	Vector2i(-1, -1),
]

static var _dxs := PackedInt32Array()
static var _dys := PackedInt32Array()
static var _steps := PackedFloat64Array()

## Each cell's walkable region, or NONE where a soldier can't stand.
var regions := PackedInt32Array()
## Cells settled by the last [method step], for tests and the profiler.
var last_settled := 0

var _settings: Settings
var _map: MapData
var _piles: Piles
var _solids: Solids
# The cost of entering each cell, per cell of step length: 1 ÷ its speed factor, or INF where
# a soldier can't stand.
var _costs := PackedFloat64Array()
# Live fields by id, oldest first.
var _fields: Dictionary[int, Field] = {}
var _next_id := 0
var _restarted: Array[int] = []


class Field:
	extends RefCounted

	var anchor: int
	## Where the field's soldiers are, as a map position: it settles towards there first, by the
	## octile distance to it, so a long order is ready sooner. NO_AIM settles evenly outwards.
	var aim := NO_AIM
	## A rally field lives while its rally point stands, with or without soldiers on it.
	var persistent := false
	## Soldiers walking on this field.
	var users := 0
	## Counts restarts, so a path can tell it came from an older settling.
	var generation := 0
	## Changed since it last settled in a way no walking soldier needs yet: a rally field
	## restarts before its next soldier joins.
	var stale := false
	var values := PackedFloat64Array()
	var parents := PackedInt32Array()
	var closed := PackedByteArray()
	var heap := CellHeap.new()
	## The cells settled, in order.
	var order := PackedInt32Array()
	## Needed cells not yet settled.
	var waiting: Dictionary[int, bool] = {}
	## The highest value among the needed cells settled since the last restart.
	var bound := 0.0

	func _init(cells: int, anchor_cell: int) -> void:
		values.resize(cells)
		parents.resize(cells)
		closed.resize(cells)
		start(anchor_cell)

	func start(anchor_cell: int) -> void:
		anchor = anchor_cell
		values.fill(UNREACHABLE)
		parents.fill(NONE)
		closed.fill(0)
		heap = CellHeap.new()
		order.clear()
		waiting.clear()
		bound = 0.0
		stale = false
		values[anchor] = 0.0
		heap.push(0.0, anchor)

	func is_ready() -> bool:
		return waiting.is_empty() or heap.is_empty()


static func _static_init() -> void:
	for offset in _OFFSETS:
		_dxs.append(offset.x)
		_dys.append(offset.y)
		_steps.append(Vector2(offset).length())


func _init(
	run_settings: Settings,
	run_map: MapData,
	run_occupancy: Occupancy,
	run_piles: Piles,
	run_structures: Structures,
) -> void:
	_settings = run_settings
	_map = run_map
	_piles = run_piles
	_solids = Solids.new(_map, run_occupancy, _piles, run_structures, false)
	_costs.resize(_map.width * _map.height)
	for index in _costs.size():
		_costs[index] = _cost_of(index)
	_relabel()


## What a soldier's speed is multiplied by on [param index]: 1 on clear ground, less on a pile
## by its slow, and less on a wall by [member Settings.soldier_wall_climb_slow].
func speed_factor(index: int) -> float:
	var level := _piles.levels[index]
	if level == Piles.WALL_LEVEL:
		return 1.0 - _settings.soldier_wall_climb_slow
	if level > 0:
		return 1.0 - _settings.pile_slow(level)
	return 1.0


## The cell nearest [param pos] by straight distance (ties to the lowest index) that a soldier
## can stand on, whose region is in [param allowed] (any region when it's empty) and whose
## [param held] count, if given, is 0; NONE when there is none.
func nearest_standable(pos: Vector2, allowed: Dictionary = {}, held := PackedInt32Array()) -> int:
	var cell := Vector2i(pos.floor())
	if _map.in_bounds(cell) and _is_open(_map.index_of(cell), allowed, held):
		return _map.index_of(cell)
	var best := NONE
	var best_distance := INF
	for index in regions.size():
		if not _is_open(index, allowed, held):
			continue
		var distance := MapData.centre_of(_map.cell_of(index)).distance_squared_to(pos)
		if distance < best_distance:
			best = index
			best_distance = distance
	return best


## Up to [param wanted] cells nearest [param anchor] by field value (ties to the lowest index)
## whose [param held] count is 0, settled at once by the field's own rule: a field from the same
## anchor settles them first, so they are a Cluster's slots.
func nearest_free(anchor: int, wanted: int, held: PackedInt32Array) -> PackedInt32Array:
	var found := PackedInt32Array()
	if wanted < 1:
		return found
	var field := Field.new(_costs.size(), anchor)
	while found.size() < wanted and not field.heap.is_empty():
		var before := field.order.size()
		_settle(field, 1, false)
		if field.order.size() > before and held[field.order[-1]] == 0:
			found.append(field.order[-1])
	return found


## Starts a field from [param anchor], settling towards [param aim] (where its soldiers are, or
## [constant NO_AIM]), and returns its id. A rally field is [param persistent]: it stays when no
## soldier walks on it.
func plan(anchor: int, aim: Vector2, persistent := false) -> int:
	var id := _next_id
	_next_id += 1
	var field := Field.new(_costs.size(), anchor)
	field.aim = aim
	field.persistent = persistent
	_fields[id] = field
	return id


## Asks a field to settle [param cells] too; a stale field restarts first. A field that hasn't
## settled anything yet (a restarted one) takes [param aim], where its soldiers are now, if given.
func need(field_id: int, cells: PackedInt32Array, aim := NO_AIM) -> void:
	var field := _fields[field_id]
	if field.stale:
		restart(field_id)
	if aim != NO_AIM and field.order.is_empty():
		field.aim = aim
	for cell in cells:
		if field.closed[cell] == 1:
			field.bound = maxf(field.bound, field.values[cell])
		else:
			field.waiting[cell] = true


## A soldier starts walking on a field.
func join(field_id: int) -> void:
	_fields[field_id].users += 1


## A soldier stops walking on a field; a field nobody walks on is dropped unless it is a rally
## field.
func leave(field_id: int) -> void:
	var field: Field = _fields.get(field_id, null)
	if field == null:
		return
	field.users -= 1
	if field.users <= 0 and not field.persistent:
		_fields.erase(field_id)


## A rally field whose rally point went: it goes once nobody walks on it.
func release(field_id: int) -> void:
	var field: Field = _fields.get(field_id, null)
	if field == null:
		return
	field.persistent = false
	if field.users <= 0:
		_fields.erase(field_id)


## Whether a field is live: not yet dropped.
func has_field(field_id: int) -> bool:
	return _fields.has(field_id)


## The live fields' ids, oldest first.
func field_ids() -> Array[int]:
	return _fields.keys()


## The cell index a field grows from.
func anchor(field_id: int) -> int:
	return _fields[field_id].anchor


## How many times a field has restarted.
func generation(field_id: int) -> int:
	return _fields[field_id].generation


## Whether a field has settled every cell it needs, or every cell it can reach.
func is_ready(field_id: int) -> bool:
	return _fields[field_id].is_ready()


## A cell's cost to walk to the anchor on a field, or [constant UNREACHABLE].
func value(field_id: int, cell: int) -> float:
	return _fields[field_id].values[cell]


## The cells from [param from_cell] to [param slot_cell] through the field's shortest-path tree,
## [param from_cell] left out: up its parent chain towards the anchor until it meets the slot's
## chain, then down that to the slot. Empty when either cell isn't settled.
func path(field_id: int, from_cell: int, slot_cell: int) -> PackedInt32Array:
	var field := _fields[field_id]
	var cells := PackedInt32Array()
	if field.closed[from_cell] == 0 or field.closed[slot_cell] == 0:
		return cells
	var down := PackedInt32Array()
	var on_slot_chain: Dictionary[int, int] = {}
	var cell := slot_cell
	while cell != NONE:
		on_slot_chain[cell] = down.size()
		down.append(cell)
		cell = field.parents[cell]
	cell = from_cell
	while not on_slot_chain.has(cell):
		cell = field.parents[cell]
		cells.append(cell)
	for k in range(on_slot_chain[cell] - 1, -1, -1):
		cells.append(down[k])
	return cells


## At [constant Simulation.Step.LAND_BODIES_AND_UPDATE_FIELDS]: takes the cells whose cost
## changed, relabels the regions when one became solid or open, and restarts each field that
## settled a changed cell at or under the highest value among its soldiers' cells and slots.
func update(cells: Array[Vector2i]) -> void:
	var changed := PackedInt32Array()
	var reshaped := false
	for cell in cells:
		var index := _map.index_of(cell)
		var cost := _cost_of(index)
		if cost == _costs[index]:
			continue
		reshaped = reshaped or cost == INF or _costs[index] == INF
		_costs[index] = cost
		changed.append(index)
	if changed.is_empty():
		return
	if reshaped:
		_relabel()
	for field_id in _fields:
		var field := _fields[field_id]
		var restart := false
		for index in changed:
			if field.closed[index] == 0:
				_reopen(field, index)
			elif field.users > 0 and field.values[index] <= field.bound:
				restart = true
			else:
				field.stale = true
		if restart:
			restart(field_id)


## Every cell's cost again, after a setting that sets them changed. Fields keep what they have
## settled until a change restarts them.
func refresh_costs() -> void:
	var changed: Array[Vector2i] = []
	for index in _costs.size():
		changed.append(_map.cell_of(index))
	update(changed)


## The fields restarted since the last call, in order, so their soldiers ask for their cells
## again.
func take_restarted() -> Array[int]:
	var taken := _restarted
	_restarted = []
	return taken


## At [constant Simulation.Step.MOVE_UNITS]: settles up to [constant PATH_SETTLE_CELLS] cells
## across the fields that need cells, oldest first.
func step() -> void:
	var budget := PATH_SETTLE_CELLS
	for field_id in _fields:
		if budget == 0:
			break
		budget -= _settle(_fields[field_id], budget)
	last_settled = PATH_SETTLE_CELLS - budget


## Settles a field again from scratch, from its anchor or, if a soldier can no longer stand
## there, the nearest cell one can.
func restart(field_id: int) -> void:
	var field := _fields[field_id]
	var anchor_cell := field.anchor
	if not _can_stand_on(anchor_cell):
		anchor_cell = nearest_standable(MapData.centre_of(_map.cell_of(anchor_cell)))
		if anchor_cell == NONE:
			anchor_cell = field.anchor
	field.start(anchor_cell)
	field.generation += 1
	if field_id not in _restarted:
		_restarted.append(field_id)


# Settles up to [param budget] cells of a field, stopping once it is ready unless not
# [param until_ready], and returns how many it settled.
func _settle(field: Field, budget: int, until_ready := true) -> int:
	var costs := _costs
	var values := field.values
	var parents := field.parents
	var closed := field.closed
	var heap := field.heap
	var waiting := field.waiting
	var dxs := _dxs
	var dys := _dys
	var steps := _steps
	var width := _map.width
	var height := _map.height
	var aimed := field.aim != NO_AIM
	var aim_x := field.aim.x - 0.5
	var aim_y := field.aim.y - 0.5
	var settled := 0
	while settled < budget and not heap.is_empty() and not (until_ready and waiting.is_empty()):
		var cell := heap.pop()
		if closed[cell] == 1 or (costs[cell] == INF and cell != field.anchor):
			continue
		closed[cell] = 1
		field.order.append(cell)
		settled += 1
		var current := values[cell]
		if waiting.erase(cell):
			field.bound = maxf(field.bound, current)
		var x := cell % width
		var y := cell / width
		var entry_cost := costs[cell]
		if entry_cost == INF:
			entry_cost = 1.0
		for k in 8:
			var nx := x + dxs[k]
			var ny := y + dys[k]
			if nx < 0 or ny < 0 or nx >= width or ny >= height:
				continue
			var neighbour := ny * width + nx
			if closed[neighbour] == 1 or costs[neighbour] == INF:
				continue
			if k >= 4 and (costs[y * width + nx] == INF or costs[ny * width + x] == INF):
				continue
			var candidate := current + steps[k] * entry_cost
			if candidate < values[neighbour]:
				values[neighbour] = candidate
				parents[neighbour] = cell
				var key := candidate
				if aimed:
					# _guess, inlined: this is the hot loop.
					var across := nx - aim_x
					if across < 0.0:
						across = -across
					var down := ny - aim_y
					if down < 0.0:
						down = -down
					if across > down:
						key += across + _DIAGONAL_EXTRA * down
					else:
						key += down + _DIAGONAL_EXTRA * across
				heap.push(key, neighbour)
	return settled


# A cell the field hasn't settled that has just opened, or got cheaper to leave from, takes
# its best value from settled neighbours again, so a settling field doesn't miss it.
func _reopen(field: Field, index: int) -> void:
	if _costs[index] == INF:
		return
	var cell := _map.cell_of(index)
	for k in 8:
		var offset := _OFFSETS[k]
		var near := cell - offset
		if not _map.in_bounds(near):
			continue
		var from := _map.index_of(near)
		if field.closed[from] == 0 or _costs[from] == INF:
			continue
		var side_a := _map.index_of(Vector2i(cell.x, near.y))
		var side_b := _map.index_of(Vector2i(near.x, cell.y))
		if k >= 4 and (_costs[side_a] == INF or _costs[side_b] == INF):
			continue
		var candidate := field.values[from] + Vector2(offset).length() * _costs[from]
		if candidate < field.values[index]:
			field.values[index] = candidate
			field.parents[index] = from
			field.heap.push(candidate + _guess(field, cell), index)


# The octile distance from [param cell] to the field's aim: never more than the cost of walking
# there, since no cell costs less than its length, so the field still settles exact values.
func _guess(field: Field, cell: Vector2i) -> float:
	if field.aim == NO_AIM:
		return 0.0
	var across := absf(cell.x - field.aim.x + 0.5)
	var down := absf(cell.y - field.aim.y + 0.5)
	return maxf(across, down) + _DIAGONAL_EXTRA * minf(across, down)


func _cost_of(index: int) -> float:
	if _solids.is_solid(_map.cell_of(index)):
		return INF
	return 1.0 / maxf(speed_factor(index), 0.01)


# Labels the connected regions of cells a soldier can stand on: 8-way, without cutting a
# corner past a cell it can't stand on.
func _relabel() -> void:
	regions.resize(_costs.size())
	regions.fill(NONE)
	var width := _map.width
	var label := 0
	var queue := PackedInt32Array()
	for start in _costs.size():
		if regions[start] != NONE or _costs[start] == INF:
			continue
		regions[start] = label
		queue.clear()
		queue.append(start)
		var head := 0
		while head < queue.size():
			var cell := queue[head]
			head += 1
			var x := cell % width
			var y := cell / width
			for k in 8:
				var offset := _OFFSETS[k]
				var nx := x + offset.x
				var ny := y + offset.y
				if nx < 0 or ny < 0 or nx >= width or ny >= _map.height:
					continue
				var neighbour := ny * width + nx
				if regions[neighbour] != NONE or _costs[neighbour] == INF:
					continue
				if k >= 4 and (_costs[y * width + nx] == INF or _costs[ny * width + x] == INF):
					continue
				regions[neighbour] = label
				queue.append(neighbour)
		label += 1


# Whether a soldier can stand on [param index]: not rock, the base or a building.
func _can_stand_on(index: int) -> bool:
	return _costs[index] != INF


func _is_open(index: int, allowed: Dictionary, held: PackedInt32Array) -> bool:
	if regions[index] == NONE or not (allowed.is_empty() or allowed.has(regions[index])):
		return false
	return held.is_empty() or held[index] == 0
