class_name RangeOverlay
extends Node2D

const COLOUR := Color(1.0, 0.9, 0.4, 0.6)

var _simulation: Simulation
var _shown := false


func setup(simulation: Simulation) -> void:
	_simulation = simulation
	queue_redraw()


func show_ranges(shown: bool) -> void:
	_shown = shown
	queue_redraw()


func _process(_delta: float) -> void:
	if _shown:
		queue_redraw()


func _draw() -> void:
	if not _shown or _simulation == null:
		return
	var reach := _simulation.settings.tower_range
	for tower in _simulation.towers.built:
		draw_polyline(GridTransform.circle(tower.centre, reach), COLOUR, 1.5)
