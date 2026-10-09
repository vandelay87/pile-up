class_name Towers
extends RefCounted

const FOOTPRINT := Vector2i(2, 2)
const OFF_MAP := "off the map"
const OCCUPIED := "occupied"
const NOT_ENOUGH_GOLD := "not enough gold"
const BLOCKED := "blocked"

var built: Array[Tower] = []

var _settings: Settings
var _map: MapData
var _occupancy: Occupancy
var _routing: Routing
var _enemies: Enemies
var _run_state: RunState


class Tower:
	extends RefCounted

	var id: int
	var cell: Vector2i
	var centre: Vector2
	var cooldown := 0
	var target_id := Enemies.NONE

	func _init(tower_id: int, origin: Vector2i) -> void:
		id = tower_id
		cell = origin
		centre = Towers.centre_of(origin)


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
	run_routing: Routing,
	run_enemies: Enemies,
	run_state: RunState,
) -> void:
	_settings = run_settings
	_map = run_map
	_occupancy = run_occupancy
	_routing = run_routing
	_enemies = run_enemies
	_run_state = run_state


static func centre_of(origin: Vector2i) -> Vector2:
	return Vector2(origin) + Vector2(FOOTPRINT) / 2.0


static func origin_at(centre: Vector2) -> Vector2i:
	return Vector2i((centre - Vector2(FOOTPRINT) / 2.0).round())


static func footprint(origin: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in FOOTPRINT.y:
		for x in FOOTPRINT.x:
			cells.append(origin + Vector2i(x, y))
	return cells


func can_place(origin: Vector2i) -> bool:
	return _placement_error(origin).is_empty()


func build(origin: Vector2i) -> String:
	var error := _placement_error(origin)
	if not error.is_empty():
		return error
	var cost := _settings.tower_cost
	if not _run_state.can_afford(cost):
		return NOT_ENOUGH_GOLD
	var cells := footprint(origin)
	if _routing.would_block(cells, _enemies.positions.slice(0, _enemies.count)):
		return BLOCKED
	_run_state.spend(cost)
	_occupancy.occupy(cells)
	built.append(Tower.new(built.size(), origin))
	return ""


func fire() -> Array[Shot]:
	var shots: Array[Shot] = []
	for tower in built:
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


func _placement_error(origin: Vector2i) -> String:
	for cell in footprint(origin):
		if not _map.in_bounds(cell):
			return OFF_MAP
		if _map.is_rock(cell) or _map.is_base(cell) or _occupancy.is_occupied(cell):
			return OCCUPIED
	return ""
