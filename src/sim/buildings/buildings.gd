class_name Buildings
extends RefCounted

const TOWER := &"tower"
const PYLON := &"pylon"
const FOOTPRINTS := {TOWER: Vector2i(2, 2), PYLON: Vector2i(1, 1)}
const UNKNOWN_KIND := "unknown kind"
const OFF_MAP := "off the map"
const OFF_GRID := "off the power grid"
const OCCUPIED := "occupied"
const NOT_ENOUGH_GOLD := "not enough gold"

var built: Array[Building] = []
## How many building cells are in each cell's 3x3 neighbourhood (row-major).
var nearby := PackedByteArray()

var _settings: Settings
var _map: MapData
var _occupancy: Occupancy
var _piles: Piles
var _run_state: RunState
var _power_grid: PowerGrid
var _by_id: Dictionary[int, Building] = {}
var _next_id := 0
var _field_changes: Array[Vector2i] = []
var _destroyed: Array[int] = []


class Building:
	extends RefCounted

	var id: int
	var kind: StringName
	var origin: Vector2i
	var footprint: Array[Vector2i]
	var centre: Vector2
	var hp := 0.0
	var powered := false
	var cooldown := 0
	var target_id := Enemies.NONE

	func _init(building_id: int, building_kind: StringName, building_origin: Vector2i) -> void:
		id = building_id
		kind = building_kind
		origin = building_origin
		footprint = Buildings.cells_of(kind, origin)
		centre = Buildings.centre_of(kind, origin)


class Shot:
	extends RefCounted

	var tower_id: int
	var target_id: int
	var position: Vector2

	func _init(shooter: int, target: int, hit: Vector2) -> void:
		tower_id = shooter
		target_id = target
		position = hit


func _init(
	run_settings: Settings,
	run_map: MapData,
	run_occupancy: Occupancy,
	run_piles: Piles,
	run_state: RunState,
	power_grid: PowerGrid,
) -> void:
	_settings = run_settings
	_map = run_map
	_occupancy = run_occupancy
	_piles = run_piles
	_run_state = run_state
	_power_grid = power_grid
	nearby.resize(_map.width * _map.height)


static func is_kind(kind: StringName) -> bool:
	return FOOTPRINTS.has(kind)


static func footprint_size(kind: StringName) -> Vector2i:
	return FOOTPRINTS[kind]


static func centre_of(kind: StringName, origin: Vector2i) -> Vector2:
	return Vector2(origin) + Vector2(footprint_size(kind)) / 2.0


static func origin_at(kind: StringName, centre: Vector2) -> Vector2i:
	return Vector2i((centre - Vector2(footprint_size(kind)) / 2.0).round())


static func cells_of(kind: StringName, origin: Vector2i) -> Array[Vector2i]:
	var size := footprint_size(kind)
	var cells: Array[Vector2i] = []
	for y in size.y:
		for x in size.x:
			cells.append(origin + Vector2i(x, y))
	return cells


func building(id: int) -> Building:
	return _by_id.get(id, null)


func can_place(kind: StringName, origin: Vector2i) -> bool:
	return _placement_error(kind, origin).is_empty()


## Places a building at the end of [member built], or returns the reason it was rejected.
func build(kind: StringName, origin: Vector2i) -> String:
	var error := _placement_error(kind, origin)
	if not error.is_empty():
		return error
	var cost := cost_of(kind)
	if not _run_state.can_afford(cost):
		return NOT_ENOUGH_GOLD
	_run_state.spend(cost)
	var placed := Building.new(_next_id, kind, origin)
	_next_id += 1
	placed.hp = max_hp(kind)
	_occupancy.occupy(placed.footprint, placed.id)
	_count_nearby(placed.footprint, 1)
	built.append(placed)
	_by_id[placed.id] = placed
	_power_grid.recompute(self)
	return ""


func max_hp(kind: StringName) -> float:
	match kind:
		TOWER:
			return _settings.tower_hp
		PYLON:
			return _settings.pylon_hp
	return 0.0


## Lowers a building's HP at once. A bucket change queues its cells for a field update; at 0
## HP the building is destroyed: it leaves [member built], its cells are cleared and queued.
func damage(id: int, amount: float) -> void:
	var target := building(id)
	if target == null:
		return
	var bucket := _bucket(target.hp)
	target.hp -= amount
	if target.hp <= 0.0:
		target.hp = 0.0
		_destroy(target)
	elif _bucket(target.hp) != bucket:
		_field_changes.append_array(target.footprint)


## A building's HP rounded up to the routing bucket, as the fields cost it.
func bucketed_hp(id: int) -> float:
	var target := building(id)
	if target == null:
		return 0.0
	return _bucket(target.hp) * _settings.wall_hp_bucket


func take_field_changes() -> Array[Vector2i]:
	var taken := _field_changes
	_field_changes = []
	return taken


func take_destroyed() -> Array[int]:
	var taken := _destroyed
	_destroyed = []
	return taken


func fire(enemies: Enemies) -> Array[Shot]:
	var shots: Array[Shot] = []
	for tower in built:
		if tower.kind != TOWER or not tower.powered:
			continue
		if tower.cooldown > 0:
			tower.cooldown -= 1
			if tower.cooldown > 0:
				continue
		var target := enemies.nearest_to_base_in_range(tower.centre, _settings.tower_range)
		if target == Enemies.NONE:
			continue
		enemies.damage(target, _settings.tower_damage)
		tower.target_id = target
		tower.cooldown = _settings.tower_cooldown_ticks
		shots.append(Shot.new(tower.id, target, enemies.positions[enemies.index_of(target)]))
	return shots


func _destroy(target: Building) -> void:
	built.erase(target)
	_by_id.erase(target.id)
	_occupancy.vacate(target.footprint)
	_count_nearby(target.footprint, -1)
	_field_changes.append_array(target.footprint)
	_destroyed.append(target.id)
	_power_grid.recompute(self)


func _count_nearby(cells: Array[Vector2i], change: int) -> void:
	for cell in cells:
		for y in range(maxi(cell.y - 1, 0), mini(cell.y + 2, _map.height)):
			for x in range(maxi(cell.x - 1, 0), mini(cell.x + 2, _map.width)):
				nearby[y * _map.width + x] += change


func _bucket(hp: float) -> int:
	return ceili(hp / _settings.wall_hp_bucket)


func cost_of(kind: StringName) -> int:
	match kind:
		TOWER:
			return _settings.tower_cost
		PYLON:
			return _settings.pylon_cost
	return 0


func _placement_error(kind: StringName, origin: Vector2i) -> String:
	if not is_kind(kind):
		return UNKNOWN_KIND
	for cell in cells_of(kind, origin):
		if not _map.in_bounds(cell):
			return OFF_MAP
		if not _power_grid.is_on_grid(cell):
			return OFF_GRID
		if _map.is_rock(cell) or _map.is_base(cell) or _occupancy.is_occupied(cell):
			return OCCUPIED
		if _piles.level(cell) > 0:
			return OCCUPIED
	return ""
