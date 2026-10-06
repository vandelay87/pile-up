class_name MapCamera
extends Camera2D

const SCREENS_ACROSS := 1.75
const MAX_ZOOM := 2.0
const WHEEL_ZOOM_STEP := 1.1
const PAN_GESTURE_SPEED := 16.0

var _bounds: Rect2
var _min_zoom := 1.0
var _dragging := false


func frame(map: MapData) -> void:
	var corners := PackedVector2Array()
	var size := Vector2(map.width, map.height)
	for corner: Vector2 in [Vector2.ZERO, Vector2(size.x, 0), Vector2(0, size.y), size]:
		corners.append(GridTransform.grid_to_world(corner))
	_bounds = Rect2(corners[0], Vector2.ZERO)
	for corner in corners:
		_bounds = _bounds.expand(corner)

	var view := get_viewport_rect().size
	_min_zoom = minf(view.x / _bounds.size.x, view.y / _bounds.size.y)
	_set_zoom_level(SCREENS_ACROSS * view.x / _bounds.size.x)
	position = GridTransform.grid_to_world(Vector2(map.base.get_center()))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		match button.button_index:
			MOUSE_BUTTON_WHEEL_UP when button.pressed:
				_zoom_at(button.position, WHEEL_ZOOM_STEP)
			MOUSE_BUTTON_WHEEL_DOWN when button.pressed:
				_zoom_at(button.position, 1.0 / WHEEL_ZOOM_STEP)
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE:
				_dragging = button.pressed
	elif event is InputEventMouseMotion and _dragging:
		var motion := event as InputEventMouseMotion
		_move_to(position - motion.relative / zoom)
	elif event is InputEventPanGesture:
		var pan := event as InputEventPanGesture
		_move_to(position + pan.delta * PAN_GESTURE_SPEED / zoom)
	elif event is InputEventMagnifyGesture:
		var magnify := event as InputEventMagnifyGesture
		_zoom_at(magnify.position, magnify.factor)


func _zoom_at(screen_point: Vector2, factor: float) -> void:
	var from_centre := screen_point - get_viewport_rect().size / 2.0
	var under_cursor := position + from_centre / zoom
	_set_zoom_level(zoom.x * factor)
	_move_to(under_cursor - from_centre / zoom)


func _set_zoom_level(level: float) -> void:
	zoom = Vector2.ONE * clampf(level, _min_zoom, MAX_ZOOM)


func _move_to(target: Vector2) -> void:
	position = target.clamp(_bounds.position, _bounds.end)
