class_name PowerGrid
extends RefCounted

## Which buildings are powered and which cells are on the power grid. The base is always
## powered; a building is powered when any of its cells lies in the power area of the base or of
## another powered building. A power area is the square reaching its size in cells from the
## footprint's edge (Chebyshev distance), ignoring terrain.

## 1 for each cell on the grid (row-major).
var cells := PackedByteArray()

var _settings: Settings
var _map: MapData
var _powered: Dictionary[int, bool] = {}
var _changed := false


func _init(run_settings: Settings, run_map: MapData) -> void:
	_settings = run_settings
	_map = run_map
	cells.resize(_map.width * _map.height)
	_paint(base_area())


func is_on_grid(cell: Vector2i) -> bool:
	return _map.in_bounds(cell) and cells[cell.y * _map.width + cell.x] == 1


func is_powered(id: int) -> bool:
	return _powered.has(id)


## The base's power area, clipped to the map.
func base_area() -> Rect2i:
	return _area(_map.base, _settings.base_power_area)


## A building's power area, clipped to the map.
func area_of(kind: StringName, origin: Vector2i) -> Rect2i:
	var footprint := Rect2i(origin, Buildings.footprint_size(kind))
	return _area(footprint, power_area(kind))


func power_area(kind: StringName) -> int:
	match kind:
		Buildings.TOWER:
			return _settings.tower_power_area
		Buildings.PYLON:
			return _settings.pylon_power_area
	return 0


## Walks outwards from the base through overlapping power areas, setting each building's
## [member Buildings.Building.powered] flag. Marks the grid changed when any flag or cell changes.
func recompute(buildings: Buildings) -> void:
	var before := cells
	cells = PackedByteArray()
	cells.resize(_map.width * _map.height)
	_paint(base_area())
	var powered: Dictionary[int, bool] = {}
	var waiting := buildings.built.duplicate()
	var progress := true
	while progress:
		progress = false
		var still_waiting: Array[Buildings.Building] = []
		for building: Buildings.Building in waiting:
			if _touches_grid(building):
				powered[building.id] = true
				_paint(area_of(building.kind, building.origin))
				progress = true
			else:
				still_waiting.append(building)
		waiting = still_waiting
	for building in buildings.built:
		building.powered = powered.has(building.id)
	if cells != before or powered != _powered:
		_changed = true
	_powered = powered


## True once after the grid or any powered flag changed.
func take_changed() -> bool:
	var changed := _changed
	_changed = false
	return changed


func _touches_grid(building: Buildings.Building) -> bool:
	for cell in building.footprint:
		if cells[cell.y * _map.width + cell.x] == 1:
			return true
	return false


func _area(footprint: Rect2i, reach: int) -> Rect2i:
	return footprint.grow(reach).intersection(Rect2i(0, 0, _map.width, _map.height))


func _paint(area: Rect2i) -> void:
	for y in range(area.position.y, area.end.y):
		var row := y * _map.width
		for x in range(area.position.x, area.end.x):
			cells[row + x] = 1
