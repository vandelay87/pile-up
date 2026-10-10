class_name Piles
extends RefCounted

const WALL_LEVEL := 5
const FALLEN_WALL_LEVEL := 3

var levels := PackedByteArray()
var wall_hps := PackedFloat64Array()
var walls_nearby := PackedByteArray()
var changed: Array[Vector2i] = []

var _settings: Settings
var _map: MapData
var _occupancy: Occupancy
var _rng: RandomNumberGenerator
var _queued := PackedVector2Array()
var _field_changes: Array[Vector2i] = []
var _changed_mask := PackedByteArray()


func _init(
	run_settings: Settings,
	run_map: MapData,
	run_occupancy: Occupancy,
	rng: RandomNumberGenerator = null
) -> void:
	_settings = run_settings
	_map = run_map
	_occupancy = run_occupancy
	_rng = rng
	if _rng == null:
		_rng = RandomNumberGenerator.new()
		_rng.seed = hash([0, "piles"])
	levels.resize(_map.width * _map.height)
	wall_hps.resize(_map.width * _map.height)
	walls_nearby.resize(_map.width * _map.height)
	_changed_mask.resize(_map.width * _map.height)


func level(cell: Vector2i) -> int:
	return levels[_map.index_of(cell)]


func wall_hp(cell: Vector2i) -> float:
	return wall_hps[_map.index_of(cell)]


func queue_bodies(positions: PackedVector2Array) -> void:
	_queued.append_array(positions)


func land() -> void:
	for pos in _queued:
		var cell := _landing_cell(pos)
		if not _map.in_bounds(cell) or not is_valid_landing(cell):
			continue
		var index := _map.index_of(cell)
		levels[index] += 1
		if levels[index] == WALL_LEVEL:
			wall_hps[index] = _settings.wall_hp
			_count_wall(cell, 1)
		_mark_changed(cell)
		_field_changes.append(cell)
	_queued.clear()


func damage_wall(cell: Vector2i, amount: float) -> void:
	var index := _map.index_of(cell)
	if levels[index] != WALL_LEVEL:
		return
	var bucket := _bucket(wall_hps[index])
	wall_hps[index] -= amount
	if wall_hps[index] <= 0.0:
		wall_hps[index] = 0.0
		levels[index] = FALLEN_WALL_LEVEL
		_count_wall(cell, -1)
	elif _bucket(wall_hps[index]) == bucket:
		return
	_mark_changed(cell)
	_field_changes.append(cell)


func bucketed_wall_hp(cell: Vector2i) -> float:
	return _bucket(wall_hp(cell)) * _settings.wall_hp_bucket


# Every pile rolls once, in (y, x) order, to lose one level: levels 1-4 at the pile chance,
# walls at the wall chance. A wall that loses drops to level 4 and discards its HP; one that
# survives keeps its damage.
func decay() -> void:
	var pile_chance := _settings.pile_decay_chance
	var wall_chance := _settings.wall_decay_chance
	for index in levels.size():
		if levels[index] == 0:
			continue
		var is_wall := levels[index] == WALL_LEVEL
		if not _rolls_under(wall_chance if is_wall else pile_chance):
			continue
		var cell := _map.cell_of(index)
		if is_wall:
			_count_wall(cell, -1)
			wall_hps[index] = 0.0
		levels[index] -= 1
		_mark_changed(cell)


# One roll against a 0..1 chance. randf() can return exactly 1.0, so a chance of 1 always hits;
# a chance of 0 never does. The roll is always drawn, so the stream does not depend on chances.
func _rolls_under(chance: float) -> bool:
	var roll := _rng.randf()
	return chance >= 1.0 or roll < chance


func clear_changes() -> void:
	for cell in changed:
		_changed_mask[_map.index_of(cell)] = 0
	changed.clear()


func take_changes() -> Array[Vector2i]:
	var taken := changed.duplicate()
	clear_changes()
	return taken


func take_field_changes() -> Array[Vector2i]:
	var taken := _field_changes
	_field_changes = []
	return taken


func is_valid_landing(cell: Vector2i) -> bool:
	return (
		levels[_map.index_of(cell)] < WALL_LEVEL
		and not _map.is_rock(cell)
		and not _map.is_base(cell)
		and not _occupancy.is_occupied(cell)
	)


func _landing_cell(death_pos: Vector2) -> Vector2i:
	var death_cell := Vector2i(death_pos.floor())
	if _map.in_bounds(death_cell) and is_valid_landing(death_cell):
		return death_cell
	return _nearest_valid(death_pos, death_cell)


# Searches rings of cells outwards from the death cell. Every cell in ring r is
# at least r - 0.5 from a position inside the death cell, so the search stops
# once that bound passes the best distance found. Returns a cell outside the
# map when no cell is valid.
func _nearest_valid(death_pos: Vector2, death_cell: Vector2i) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_squared := INF
	var last_ring := maxi(_map.width, _map.height)
	var ring := 1
	while ring <= last_ring and (ring - 0.5) * (ring - 0.5) <= best_squared:
		for y in range(maxi(death_cell.y - ring, 0), mini(death_cell.y + ring + 1, _map.height)):
			var on_edge_row := absi(y - death_cell.y) == ring
			var step := 1 if on_edge_row else 2 * ring
			for x in range(death_cell.x - ring, death_cell.x + ring + 1, step):
				var cell := Vector2i(x, y)
				if not _map.in_bounds(cell) or not is_valid_landing(cell):
					continue
				var dx: float = death_pos.x - (x + 0.5)
				var dy: float = death_pos.y - (y + 0.5)
				var squared := dx * dx + dy * dy
				if squared < best_squared or (squared == best_squared and _before(cell, best)):
					best_squared = squared
					best = cell
		ring += 1
	return best


func _count_wall(cell: Vector2i, change: int) -> void:
	var area := _map.neighbourhood(cell)
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			walls_nearby[_map.index_of(Vector2i(x, y))] += change


func _mark_changed(cell: Vector2i) -> void:
	var index := _map.index_of(cell)
	if _changed_mask[index] == 0:
		_changed_mask[index] = 1
		changed.append(cell)


func _bucket(hp: float) -> int:
	return ceili(hp / _settings.wall_hp_bucket)


static func _before(cell: Vector2i, other: Vector2i) -> bool:
	return cell.y < other.y or (cell.y == other.y and cell.x < other.x)
