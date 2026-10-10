class_name PowerOverlay
extends Node2D

## Debug overlay: the power grid's cells tinted, and the base's and each building's power area
## outlined (dimmed when the building is unpowered).

const GRID_TINT := Color(0.45, 0.75, 1.0, 0.18)
const AREA := Color(0.5, 0.85, 1.0, 0.8)
const UNPOWERED_AREA := Color(0.6, 0.6, 0.6, 0.4)

var _simulation: Simulation
var _shown := false


func setup(simulation: Simulation) -> void:
	_simulation = simulation
	_simulation.power_changed.connect(queue_redraw)
	queue_redraw()


func show_grid(shown: bool) -> void:
	_shown = shown
	queue_redraw()


func _draw() -> void:
	if not _shown or _simulation == null:
		return
	var grid := _simulation.power_grid
	PowerGridDrawing.tint_grid(self, grid, _simulation.map, GRID_TINT)
	PowerGridDrawing.outline(self, grid.base_area(), AREA)
	for building in _simulation.buildings.built:
		var colour := AREA if building.powered else UNPOWERED_AREA
		PowerGridDrawing.outline(self, grid.area_of(building.kind, building.origin), colour)
