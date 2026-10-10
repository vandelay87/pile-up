# One interface over everything enemies attack: walls (in Piles), buildings (in Buildings) and
# the base (in RunState). It owns no state; it looks a cell up and routes damage to the system
# that owns it.
class_name Structures
extends RefCounted

enum Kind { NONE, WALL, BUILDING, BASE }

var _map: MapData
var _occupancy: Occupancy
var _piles: Piles
var _buildings: Buildings
var _run_state: RunState
var _base_cells := PackedByteArray()
var _near_base := PackedByteArray()


func _init(
	run_map: MapData,
	run_occupancy: Occupancy,
	run_piles: Piles,
	run_buildings: Buildings,
	run_state: RunState,
) -> void:
	_map = run_map
	_occupancy = run_occupancy
	_piles = run_piles
	_buildings = run_buildings
	_run_state = run_state
	_base_cells.resize(_map.width * _map.height)
	_near_base.resize(_map.width * _map.height)
	for cell in _map.base_cells():
		_base_cells[_index(cell)] = 1
		for y in range(maxi(cell.y - 1, 0), mini(cell.y + 2, _map.height)):
			for x in range(maxi(cell.x - 1, 0), mini(cell.x + 2, _map.width)):
				_near_base[y * _map.width + x] = 1


func structure_at(cell: Vector2i) -> Kind:
	var index := _index(cell)
	if _base_cells[index] == 1:
		return Kind.BASE
	if _occupancy.building_ids[index] != Occupancy.EMPTY:
		return Kind.BUILDING
	if _piles.levels[index] == Piles.WALL_LEVEL:
		return Kind.WALL
	return Kind.NONE


func damage(cell: Vector2i, amount: float) -> void:
	match structure_at(cell):
		Kind.BASE:
			_run_state.damage_base(amount)
		Kind.BUILDING:
			_buildings.damage(_occupancy.building_at(cell), amount)
		Kind.WALL:
			_piles.damage_wall(cell, amount)


func hp(cell: Vector2i) -> float:
	match structure_at(cell):
		Kind.BASE:
			return _run_state.base_hp
		Kind.BUILDING:
			var building := _buildings.building(_occupancy.building_at(cell))
			return building.hp if building != null else 0.0
		Kind.WALL:
			return _piles.wall_hp(cell)
	return 0.0


# HP rounded up to the routing bucket for walls and buildings; the base's HP never changes
# the fields.
func bucketed_hp(cell: Vector2i) -> float:
	match structure_at(cell):
		Kind.BASE:
			return _run_state.base_hp
		Kind.BUILDING:
			return _buildings.bucketed_hp(_occupancy.building_at(cell))
		Kind.WALL:
			return _piles.bucketed_wall_hp(cell)
	return 0.0


# Lookups by cell index for the enemy movement loop.
func is_structure(index: int) -> bool:
	return (
		_base_cells[index] == 1
		or _occupancy.building_ids[index] != Occupancy.EMPTY
		or _piles.levels[index] == Piles.WALL_LEVEL
	)


func is_base(index: int) -> bool:
	return _base_cells[index] == 1


# True for a wall or a building cell: the obstacles the fields cost by break time.
func is_breakable(index: int) -> bool:
	return (
		_occupancy.building_ids[index] != Occupancy.EMPTY
		or _piles.levels[index] == Piles.WALL_LEVEL
	)


# True when a structure is in this cell or one of its 8 neighbours.
func is_nearby(index: int) -> bool:
	return _near_base[index] == 1 or _piles.walls_nearby[index] > 0 or _buildings.nearby[index] > 0


func _index(cell: Vector2i) -> int:
	return cell.y * _map.width + cell.x
