class_name UnitPathsOverlay
extends Node2D

## Off at launch: each live path field's anchor and its soldiers' slots, and each walking
## soldier's remaining path, so pathing can be read in QA.

const ANCHOR := Color(1.0, 0.85, 0.3, 0.9)
const SLOT := Color(0.4, 1.0, 0.5, 0.8)
const PATH := Color(0.4, 0.8, 1.0, 0.7)
const MARK_RADIUS := 5.0

var _simulation: Simulation
var _shown := false


func setup(simulation: Simulation) -> void:
	_simulation = simulation
	queue_redraw()


func show_paths(shown: bool) -> void:
	_shown = shown
	queue_redraw()


func _process(_delta: float) -> void:
	if _shown:
		queue_redraw()


func _draw() -> void:
	if not _shown or _simulation == null:
		return
	var map := _simulation.map
	var paths := _simulation.unit_paths
	for field in paths.field_ids():
		_mark(map.cell_of(paths.anchor(field)), ANCHOR, true)
	var soldiers := _simulation.soldiers
	for i in soldiers.count:
		if soldiers.orders[i] == Soldiers.NONE:
			continue
		if soldiers.slots[i] != Soldiers.NONE:
			_mark(map.cell_of(soldiers.slots[i]), SLOT, false)
		var line := PackedVector2Array([GridTransform.grid_to_world(soldiers.positions[i])])
		for cell in soldiers.path_left(i):
			line.append(GridTransform.grid_to_world(MapData.centre_of(map.cell_of(cell))))
		if line.size() > 1:
			draw_polyline(line, PATH, 1.5)


func _mark(cell: Vector2i, colour: Color, filled: bool) -> void:
	var centre := GridTransform.grid_to_world(MapData.centre_of(cell))
	draw_set_transform(centre, 0.0, Vector2(1.0, 0.5))
	if filled:
		draw_circle(Vector2.ZERO, MARK_RADIUS, colour)
	else:
		draw_arc(Vector2.ZERO, MARK_RADIUS, 0.0, TAU, 16, colour, 1.5)
	draw_set_transform(Vector2.ZERO)
