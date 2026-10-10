# One interface over everything enemies attack: walls (in Piles) and the base (in RunState).
# It owns no state; it looks a cell up and routes damage to the system that owns it.
class_name Structures
extends RefCounted

enum Kind { NONE, WALL, BASE }

var _map: MapData
var _piles: Piles
var _run_state: RunState
var _base_cells := PackedByteArray()
var _near_base := PackedByteArray()


func _init(run_map: MapData, run_piles: Piles, run_state: RunState) -> void:
	_map = run_map
	_piles = run_piles
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
	if _piles.levels[index] == Piles.WALL_LEVEL:
		return Kind.WALL
	return Kind.NONE


func damage(cell: Vector2i, amount: float) -> void:
	match structure_at(cell):
		Kind.BASE:
			_run_state.damage_base(amount)
		Kind.WALL:
			_piles.damage_wall(cell, amount)


func hp(cell: Vector2i) -> float:
	match structure_at(cell):
		Kind.BASE:
			return _run_state.base_hp
		Kind.WALL:
			return _piles.wall_hp(cell)
	return 0.0


# A wall's HP rounded up to the routing bucket; the base's HP never changes the fields.
func bucketed_hp(cell: Vector2i) -> float:
	match structure_at(cell):
		Kind.BASE:
			return _run_state.base_hp
		Kind.WALL:
			return _piles.bucketed_wall_hp(cell)
	return 0.0


# Lookups by cell index for the enemy movement loop.
func is_structure(index: int) -> bool:
	return _base_cells[index] == 1 or _piles.levels[index] == Piles.WALL_LEVEL


func is_base(index: int) -> bool:
	return _base_cells[index] == 1


# True when a structure is in this cell or one of its 8 neighbours.
func is_nearby(index: int) -> bool:
	return _near_base[index] == 1 or _piles.walls_nearby[index] > 0


func _index(cell: Vector2i) -> int:
	return cell.y * _map.width + cell.x
