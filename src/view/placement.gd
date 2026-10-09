class_name Placement
extends Node2D

const VALID := Color(0.3, 0.9, 0.4)
const INVALID := Color(0.95, 0.3, 0.25)
const FILL_ALPHA := 0.35
const RANGE_ALPHA := 0.5

var active := false

var _simulation: Simulation
var _origin := Vector2i.ZERO
var _sent_origin := Vector2i.ZERO
var _blocked := false


func setup(simulation: Simulation) -> void:
	_simulation = simulation
	_simulation.command_rejected.connect(_on_rejected)
	_blocked = false
	leave()


func enter() -> void:
	active = true
	queue_redraw()


func leave() -> void:
	active = false
	queue_redraw()


func _process(_delta: float) -> void:
	if not active:
		return
	var origin := _origin_under(get_global_mouse_position())
	if origin != _origin:
		_origin = origin
		_blocked = false
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key := event as InputEventKey
		if not key.pressed or key.echo:
			return
		if key.keycode == KEY_T:
			enter()
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
			_sent_origin = _origin_under(get_global_mouse_position())
			_simulation.queue_command(Commands.BuildTower.new(_sent_origin))
		elif button.button_index == MOUSE_BUTTON_RIGHT:
			leave()
		else:
			return
		get_viewport().set_input_as_handled()


func _draw() -> void:
	if not active or _simulation == null:
		return
	var colour := VALID if _is_valid() else INVALID
	var corner := Vector2(_origin)
	var size := Vector2(Towers.FOOTPRINT)
	var footprint := PackedVector2Array(
		[corner, corner + Vector2(size.x, 0), corner + size, corner + Vector2(0, size.y)]
	)
	var outline := GridTransform.XF * footprint
	draw_colored_polygon(outline, Color(colour, FILL_ALPHA))
	outline.append(outline[0])
	draw_polyline(outline, colour, 2.0)

	var circle := GridTransform.circle(Towers.centre_of(_origin), _simulation.settings.tower_range)
	draw_polyline(circle, Color(colour, RANGE_ALPHA), 1.5)


func _is_valid() -> bool:
	if _blocked:
		return false
	var affordable := _simulation.run_state.can_afford(_simulation.settings.tower_cost)
	return affordable and _simulation.towers.can_place(_origin)


func _on_rejected(reason: String) -> void:
	if reason == "%s: %s" % [Commands.BuildTower.LABEL, Towers.BLOCKED]:
		_blocked = _sent_origin == _origin


func _origin_under(point: Vector2) -> Vector2i:
	return Towers.origin_at(GridTransform.world_to_grid(point))
