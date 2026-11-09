class_name Perches
extends RefCounted

## Enemies perched on top of buildings and the base, where a tumble landed them. Each building
## holds [member Settings.perch_room] enemies per footprint cell and the base
## [member Settings.base_perch_room] per cell. Room is claimed when a tumble is planned, so those
## in flight never overfill it, and given back if the enemy dies in the air. A perched enemy
## stands on a spot of the cell its path entered, attacks what it stands on whatever its state,
## gets down only when its building is destroyed, and drops its body off at its drop-off cell, on
## the side it came from.

## What an enemy perched on the base is perched on, in place of a building id.
const BASE := -2
const NONE := -1
## The spots on a footprint cell, as offsets into it, in the order they fill: the first
## perch room of them are used.
const SPOTS: Array[Vector2] = [
	Vector2(0.3, 0.3),
	Vector2(0.7, 0.7),
	Vector2(0.7, 0.3),
	Vector2(0.3, 0.7),
]

var _settings: Settings
var _map: MapData
var _occupancy: Occupancy
var _structures: Structures
var _buildings: Buildings
var _enemies: Enemies
# The ids perched on each building id or BASE, in the order they perched.
var _perched: Dictionary[int, PackedInt32Array] = {}
# The room claimed on each building id or BASE: those perched and those on their way.
var _claims: Dictionary[int, int] = {}
# Per perched enemy id: what it is on, the cell it stands on, its drop-off cell and its spot
# (the cell index × the spot count + the spot).
var _on: Dictionary[int, int] = {}
var _cells: Dictionary[int, Vector2i] = {}
var _drop_cells: Dictionary[int, Vector2i] = {}
var _spots: Dictionary[int, int] = {}
var _taken_spots: Dictionary[int, bool] = {}
var _base_cell_count := 0


## A perched enemy's body dropping off its building or the base: who, where it died up there
## and the cell it lands on.
class Drop:
	extends RefCounted

	var id: int
	var died_at: Vector2
	var cell: Vector2i

	func _init(drop_id: int, drop_died_at: Vector2, drop_cell: Vector2i) -> void:
		id = drop_id
		died_at = drop_died_at
		cell = drop_cell


func _init(
	run_settings: Settings,
	run_map: MapData,
	run_occupancy: Occupancy,
	run_structures: Structures,
	run_buildings: Buildings,
	run_enemies: Enemies,
) -> void:
	_settings = run_settings
	_map = run_map
	_occupancy = run_occupancy
	_structures = run_structures
	_buildings = run_buildings
	_enemies = run_enemies
	_base_cell_count = _map.base_cells().size()


## The building id on [param cell], [constant BASE] for a base cell, or [constant NONE].
func target_at(cell: Vector2i) -> int:
	var index := _map.index_of(cell)
	if _structures.is_base(index):
		return BASE
	var building_id := _occupancy.building_ids[index]
	return building_id if building_id != Occupancy.EMPTY else NONE


## Claims room for one enemy on what stands on [param cell]. False when it is full, or nothing
## there holds enemies.
func claim(cell: Vector2i) -> bool:
	var target := target_at(cell)
	if target == NONE or claimed(target) >= room(target):
		return false
	_claims[target] = claimed(target) + 1
	return true


## Gives back a claim on [param target], a building id or [constant BASE], for an enemy that
## never perched.
func release_claim(target: int) -> void:
	if _claims.has(target):
		_claims[target] = maxi(_claims[target] - 1, 0)


## Perches the enemy at [param index], whose claim is on what stands on [param cell], on the
## free spot nearest where its path entered that cell from [param entered_from]. Its body
## will drop off at [param drop_cell]. A bloater's fuse is lit. False, changing nothing, when
## nothing stands on the cell any more.
func perch(index: int, cell: Vector2i, drop_cell: Vector2i, entered_from: Vector2) -> bool:
	var target := target_at(cell)
	if target == NONE:
		return false
	var id := _enemies.ids[index]
	var spot := _free_spot(target, cell, entered_from)
	if spot != NONE:
		_taken_spots[spot] = true
		_enemies.positions[index] = (
			Vector2(_map.cell_of(spot / SPOTS.size())) + SPOTS[spot % SPOTS.size()]
		)
	else:
		_enemies.positions[index] = MapData.centre_of(cell)
	_enemies.set_state(index, Enemies.State.PERCHED)
	if not _perched.has(target):
		_perched[target] = PackedInt32Array()
	_perched[target].append(id)
	_on[id] = target
	_cells[id] = cell
	_drop_cells[id] = drop_cell
	_spots[id] = spot
	return true


## At [constant Simulation.Step.MOVE_ENEMIES], after the overflow: the buildings in
## [param destroyed], those destroyed this tick, let their perched enemies down, then every perched
## enemy but a bloater deals the structure damage to what it stands on, powered, under repair or
## not. Any building that destroys lets its perched enemies down too.
func step(destroyed: Array[int]) -> void:
	release_destroyed(destroyed)
	var damage := _settings.structure_damage_per_tick
	for target: int in _perched:
		for id in _perched[target]:
			var index := _enemies.index_of(id)
			if index == Enemies.NONE or not _enemies.is_alive(index):
				continue
			if _enemies.kinds[index] == Enemies.Kind.BLOATER:
				continue
			_structures.damage(_cells[id], damage)
	release_destroyed(destroyed)


## The living enemies perched on each building in [param building_ids] walk again from where they
## stand. Those already dead keep their drop-off cells for [method drop_cells].
func release_destroyed(building_ids: Array[int]) -> void:
	for building_id in building_ids:
		# Claims of tumbles and jumps still on their way go too.
		_claims.erase(building_id)
		if not _perched.has(building_id):
			continue
		for id in _perched[building_id]:
			var index := _enemies.index_of(id)
			if index == Enemies.NONE or not _enemies.is_alive(index):
				continue
			_forget(id)
			_enemies.set_state(index, Enemies.State.WALKING)
		_perched.erase(building_id)


## At [constant Simulation.Step.REMOVE_DEAD], each perched enemy in [param deaths] gets down for
## good: one that leaves a body drops it off at its drop-off cell. Returns those drops.
func drop_cells(deaths: Deaths) -> Array[Drop]:
	var drops: Array[Drop] = []
	for k in deaths.size():
		var id := deaths.ids[k]
		if not _on.has(id):
			continue
		var target := _on[id]
		var drop_cell := _drop_cells[id]
		if _perched.has(target):
			var listed := _perched[target]
			listed.remove_at(listed.find(id))
			release_claim(target)
		_forget(id)
		if deaths.leaves_body(k):
			deaths.bodies[k] = MapData.centre_of(drop_cell)
			drops.append(Drop.new(id, deaths.positions[k], drop_cell))
	return drops


## How many enemies are perched on [param target], a building id or [constant BASE].
func count(target: int) -> int:
	return _perched[target].size() if _perched.has(target) else 0


## How many enemies [param target], a building id or [constant BASE], holds.
func room(target: int) -> int:
	if target == BASE:
		return _settings.base_perch_room * _base_cell_count
	var building := _buildings.building(target)
	if building == null:
		return 0
	return _settings.perch_room * building.footprint.size()


## The room claimed on [param target]: its perched enemies and those on their way to it.
func claimed(target: int) -> int:
	return _claims.get(target, 0)


func on_base_count() -> int:
	return count(BASE)


func is_perched(id: int) -> bool:
	return _on.has(id)


## The building id the enemy with id [param id] is perched on, [constant BASE], or
## [constant NONE].
func perched_on(id: int) -> int:
	return _on.get(id, NONE)


## Where the body of the perched enemy with id [param id] would drop off.
func drop_cell(id: int) -> Vector2i:
	return _drop_cells.get(id, Vector2i(-1, -1))


## The indices of the living enemies perched on [param target].
func enemies_on(target: int) -> PackedInt32Array:
	var found := PackedInt32Array()
	if not _perched.has(target):
		return found
	for id in _perched[target]:
		var index := _enemies.index_of(id)
		if index != Enemies.NONE and _enemies.is_alive(index):
			found.append(index)
	return found


func _forget(id: int) -> void:
	if _spots.get(id, NONE) != NONE:
		_taken_spots.erase(_spots[id])
	_on.erase(id)
	_cells.erase(id)
	_drop_cells.erase(id)
	_spots.erase(id)


# The free spot on [param target]'s cells nearest [param entered_from] clamped onto
# [param cell], where the path entered it, ties to the earlier cell then spot: among each cell's
# perch room of spots, else among them all, else NONE.
func _free_spot(target: int, cell: Vector2i, entered_from: Vector2) -> int:
	var entry := entered_from.clamp(Vector2(cell), Vector2(cell + Vector2i.ONE))
	var cells: Array[Vector2i] = []
	var per_cell := _settings.perch_room
	if target == BASE:
		cells = _map.base_cells()
		per_cell = _settings.base_perch_room
	else:
		cells = _buildings.building(target).footprint
	var spot := _nearest_free(cells, entry, mini(per_cell, SPOTS.size()))
	return spot if spot != NONE else _nearest_free(cells, entry, SPOTS.size())


func _nearest_free(cells: Array[Vector2i], entry: Vector2, spots: int) -> int:
	var best := NONE
	var best_distance := INF
	for cell in cells:
		var base_code := _map.index_of(cell) * SPOTS.size()
		for k in spots:
			if _taken_spots.has(base_code + k):
				continue
			var distance := entry.distance_squared_to(Vector2(cell) + SPOTS[k])
			if distance < best_distance:
				best_distance = distance
				best = base_code + k
	return best
