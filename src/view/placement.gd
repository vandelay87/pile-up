class_name Placement
extends Node2D

const VALID := Color(0.3, 0.9, 0.4)
const INVALID := Color(0.95, 0.3, 0.25)
const FILL_ALPHA := 0.35
const RANGE_ALPHA := 0.5
const GRID_TINT := Color(0.45, 0.75, 1.0, 0.12)
const REPAIR_AREA_TINT := Color(0.35, 0.95, 0.45, 0.12)
const KEYS := {KEY_T: Buildings.TOWER, KEY_P: Buildings.PYLON, KEY_R: Buildings.REPAIR_YARD}

var active := false
var kind := Buildings.TOWER

var _simulation: Simulation
var _origin := Vector2i.ZERO


func setup(simulation: Simulation) -> void:
	_simulation = simulation
	leave()


func enter(building_kind: StringName = Buildings.TOWER) -> void:
	kind = building_kind
	active = true
	queue_redraw()


func leave() -> void:
	active = false
	queue_redraw()


func _process(_delta: float) -> void:
	if not active:
		return
	_origin = _origin_under(get_global_mouse_position())
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key := event as InputEventKey
		if not key.pressed or key.echo:
			return
		if KEYS.has(key.keycode):
			var building_kind: StringName = KEYS[key.keycode]
			enter(building_kind)
		elif key.keycode == KEY_ESCAPE and active:
			leave()
		else:
			return
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and active:
		var button := event as InputEventMouseButton
		if not button.pressed:
			return
		if button.button_index == MOUSE_BUTTON_LEFT:
			var origin := _origin_under(get_global_mouse_position())
			_simulation.queue_command(Commands.Build.new(kind, origin))
		elif button.button_index == MOUSE_BUTTON_RIGHT:
			leave()
		else:
			return
		get_viewport().set_input_as_handled()


func _draw() -> void:
	if not active or _simulation == null:
		return
	PowerGridDrawing.tint_grid(self, _simulation.power_grid, _simulation.map, GRID_TINT)
	if kind == Buildings.REPAIR_YARD:
		var repair_area := RepairYards.repair_area_of(_origin, _simulation.settings.repair_area)
		PowerGridDrawing.tint_area(self, repair_area, _simulation.map, REPAIR_AREA_TINT)
	var colour := VALID if _is_valid() else INVALID
	var corner := Vector2(_origin)
	var size := Vector2(Buildings.footprint_size(kind))
	var footprint := PackedVector2Array(
		[corner, corner + Vector2(size.x, 0), corner + size, corner + Vector2(0, size.y)]
	)
	var outline := GridTransform.XF * footprint
	draw_colored_polygon(outline, Color(colour, FILL_ALPHA))
	outline.append(outline[0])
	draw_polyline(outline, colour, 2.0)

	if kind == Buildings.TOWER:
		var circle := GridTransform.circle(
			Buildings.centre_of(kind, _origin), _simulation.settings.tower_range
		)
		draw_polyline(circle, Color(colour, RANGE_ALPHA), 1.5)
	else:
		var area := _simulation.power_grid.area_of(kind, _origin)
		PowerGridDrawing.outline(self, area, Color(colour, RANGE_ALPHA))


func _is_valid() -> bool:
	var affordable := _simulation.run_state.can_afford(_simulation.buildings.cost_of(kind))
	return affordable and _simulation.buildings.can_place(kind, _origin)


func _origin_under(point: Vector2) -> Vector2i:
	return Buildings.origin_at(kind, GridTransform.world_to_grid(point))
