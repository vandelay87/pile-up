class_name Buildings
extends RefCounted

const TOWER := &"tower"
const FOOTPRINTS := {TOWER: Vector2i(2, 2)}
const UNKNOWN_KIND := "unknown kind"
const OFF_MAP := "off the map"
const OCCUPIED := "occupied"
const NOT_ENOUGH_GOLD := "not enough gold"
const BLOCKED := "blocked"

var built: Array[Building] = []

var _settings: Settings
var _map: MapData
var _occupancy: Occupancy
var _piles: Piles
var _routing: Routing
var _enemies: Enemies
var _run_state: RunState
var _by_id: Dictionary[int, Building] = {}
var _next_id := 0


class Building:
	extends RefCounted

	var id: int
	var kind: StringName
	var origin: Vector2i
	var footprint: Array[Vector2i]
	var centre: Vector2
	## HP slot: buildings cannot be attacked yet, so nothing reads or writes it.
	var hp := 0.0
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
	run_routing: Routing,
	run_enemies: Enemies,
	run_state: RunState,
) -> void:
	_settings = run_settings
	_map = run_map
	_occupancy = run_occupancy
	_piles = run_piles
	_routing = run_routing
	_enemies = run_enemies
	_run_state = run_state


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
	var cost := _cost(kind)
	if not _run_state.can_afford(cost):
		return NOT_ENOUGH_GOLD
	var cells := cells_of(kind, origin)
	if _routing.would_block(cells, _enemies.positions.slice(0, _enemies.count)):
		return BLOCKED
	_run_state.spend(cost)
	var placed := Building.new(_next_id, kind, origin)
	_next_id += 1
	_occupancy.occupy(cells, placed.id)
	built.append(placed)
	_by_id[placed.id] = placed
	return ""


func fire() -> Array[Shot]:
	var shots: Array[Shot] = []
	for tower in built:
		if tower.kind != TOWER:
			continue
		if tower.cooldown > 0:
			tower.cooldown -= 1
			if tower.cooldown > 0:
				continue
		var target := _enemies.nearest_to_base_in_range(tower.centre, _settings.tower_range)
		if target == Enemies.NONE:
			continue
		_enemies.damage(target, _settings.tower_damage)
		tower.target_id = target
		tower.cooldown = _settings.tower_cooldown_ticks
		shots.append(Shot.new(tower.id, target, _enemies.positions[_enemies.index_of(target)]))
	return shots


func _cost(kind: StringName) -> int:
	match kind:
		TOWER:
			return _settings.tower_cost
	return 0


func _placement_error(kind: StringName, origin: Vector2i) -> String:
	if not is_kind(kind):
		return UNKNOWN_KIND
	for cell in cells_of(kind, origin):
		if not _map.in_bounds(cell):
			return OFF_MAP
		if _map.is_rock(cell) or _map.is_base(cell) or _occupancy.is_occupied(cell):
			return OCCUPIED
		if _piles.level(cell) > 0:
			return OCCUPIED
	return ""
