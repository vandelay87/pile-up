## What a body can't move into, and how a body is held off it. Buildings, rock, the base and the
## map's edge are solid to every body; walls are solid to enemies, which break them, but not to
## soldiers, which climb them. Piles are never solid.
class_name Solids
extends RefCounted

const _FACES: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]

var _map: MapData
var _occupancy: Occupancy
var _piles: Piles
var _structures: Structures
var _walls_solid: bool


func _init(
	run_map: MapData,
	run_occupancy: Occupancy,
	run_piles: Piles,
	run_structures: Structures,
	walls_solid: bool,
) -> void:
	_map = run_map
	_occupancy = run_occupancy
	_piles = run_piles
	_structures = run_structures
	_walls_solid = walls_solid


func is_solid(cell: Vector2i) -> bool:
	if not _map.in_bounds(cell):
		return true
	var index := _map.index_of(cell)
	return (
		_map.rock[index] == 1
		or _structures.is_base(index)
		or _occupancy.building_ids[index] != Occupancy.EMPTY
		or (_walls_solid and _piles.levels[index] == Piles.WALL_LEVEL)
	)


## [param pos] moved out of every solid cell's square to [param radius] from it, and inside the
## map's edge.
func resolve(pos: Vector2, radius: float) -> Vector2:
	var margin := Vector2(radius, radius)
	pos = pos.clamp(margin, Vector2(_map.width, _map.height) - margin)
	var low := Vector2i((pos - margin).floor())
	var high := Vector2i((pos + margin).floor())
	for y in range(low.y, high.y + 1):
		for x in range(low.x, high.x + 1):
			var blocked := Vector2i(x, y)
			if not is_solid(blocked):
				continue
			var closest := pos.clamp(Vector2(blocked), Vector2(blocked + Vector2i.ONE))
			var away := pos - closest
			var distance := away.length()
			if distance >= radius:
				continue
			if distance > 1e-6:
				pos = closest + away / distance * radius
			else:
				pos = _leave_through_nearest_open_face(pos, blocked, radius)
	return pos


func _leave_through_nearest_open_face(pos: Vector2, cell: Vector2i, radius: float) -> Vector2:
	var inside := pos - Vector2(cell)
	var face_distances: Array[float] = [inside.x, 1.0 - inside.x, inside.y, 1.0 - inside.y]
	var best_face := Vector2i.ZERO
	var best_distance := INF
	for k in _FACES.size():
		if not is_solid(cell + _FACES[k]) and face_distances[k] < best_distance:
			best_distance = face_distances[k]
			best_face = _FACES[k]
	if best_face == Vector2i.ZERO:
		return pos
	return pos + Vector2(best_face) * (best_distance + radius)
