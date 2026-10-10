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
	return levels[_index(cell)]


func wall_hp(cell: Vector2i) -> float:
	return wall_hps[_index(cell)]


func queue_bodies(positions: PackedVector2Array) -> void:
	_queued.append_array(positions)


func land() -> void:
	for pos in _queued:
		var cell := _landing_cell(Vector2i(pos.floor()))
		if not is_valid_landing(cell):
			continue
		var index := _index(cell)
		levels[index] += 1
		if levels[index] == WALL_LEVEL:
			wall_hps[index] = _settings.wall_hp
			_count_wall(cell, 1)
		_mark_changed(cell)
		_field_changes.append(cell)
	_queued.clear()


func damage_wall(cell: Vector2i, amount: float) -> void:
	var index := _index(cell)
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
		if _rng.randf() >= (wall_chance if is_wall else pile_chance):
			continue
		var cell := Vector2i(index % _map.width, index / _map.width)
		if is_wall:
			_count_wall(cell, -1)
			wall_hps[index] = 0.0
		levels[index] -= 1
		_mark_changed(cell)


func clear_changes() -> void:
	for cell in changed:
		_changed_mask[_index(cell)] = 0
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
		levels[_index(cell)] < WALL_LEVEL
		and not _map.is_rock(cell)
		and not _map.is_base(cell)
		and not _occupancy.is_occupied(cell)
	)


func _landing_cell(death_cell: Vector2i) -> Vector2i:
	var chosen := death_cell
	var tallest := level(death_cell) if level(death_cell) < WALL_LEVEL else 0
	for y in range(death_cell.y - 1, death_cell.y + 2):
		for x in range(death_cell.x - 1, death_cell.x + 2):
			var cell := Vector2i(x, y)
			if not _map.in_bounds(cell):
				continue
			var cell_level := level(cell)
			if cell_level > tallest and cell_level < WALL_LEVEL:
				tallest = cell_level
				chosen = cell
	if is_valid_landing(chosen):
		return chosen
	return _nearest_valid(death_cell)


func _nearest_valid(from: Vector2i) -> Vector2i:
	var best := from
	var best_distance := INF
	var ring := 1
	while ring <= maxi(_map.width, _map.height) and ring <= best_distance:
		for y in range(from.y - ring, from.y + ring + 1):
			for x in range(from.x - ring, from.x + ring + 1):
				var cell := Vector2i(x, y)
				if maxi(absi(x - from.x), absi(y - from.y)) != ring:
					continue
				if not _map.in_bounds(cell) or not is_valid_landing(cell):
					continue
				var distance := _octile(cell - from)
				if distance < best_distance:
					best_distance = distance
					best = cell
		ring += 1
	return best


func _count_wall(cell: Vector2i, change: int) -> void:
	for y in range(maxi(cell.y - 1, 0), mini(cell.y + 2, _map.height)):
		for x in range(maxi(cell.x - 1, 0), mini(cell.x + 2, _map.width)):
			walls_nearby[y * _map.width + x] += change


func _mark_changed(cell: Vector2i) -> void:
	var index := _index(cell)
	if _changed_mask[index] == 0:
		_changed_mask[index] = 1
		changed.append(cell)


func _bucket(hp: float) -> int:
	return ceili(hp / _settings.wall_hp_bucket)


func _index(cell: Vector2i) -> int:
	return cell.y * _map.width + cell.x


static func _octile(offset: Vector2i) -> float:
	var straight := absi(absi(offset.x) - absi(offset.y))
	var diagonal := mini(absi(offset.x), absi(offset.y))
	return straight + diagonal * sqrt(2.0)
