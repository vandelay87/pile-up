class_name Tracers
extends Node2D

const TINT := Color(1.0, 0.85, 0.45)
const MUZZLE_HEIGHT := 52.0
const HIT_HEIGHT := 12.0

var _simulation: Simulation
var _enemy_renderer: EnemyRenderer
var _texture: Texture2D
var _free: Array[RID] = []
var _flights: Array[Flight] = []


class Flight:
	extends RefCounted

	var item: RID
	var target_id: int
	var from: Vector2
	var to: Vector2
	var started_msec: int
	var duration_msec: float


func setup(simulation: Simulation, enemy_renderer: EnemyRenderer) -> void:
	_simulation = simulation
	_enemy_renderer = enemy_renderer
	_texture = load(Atlas.PATH)
	for flight in _flights:
		_release(flight.item)
	_flights.clear()
	_simulation.shots_fired.connect(_launch)


func _launch(shots: Array[Buildings.Shot]) -> void:
	var now := Time.get_ticks_msec()
	var speed := _simulation.settings.tracer_speed
	for shot in shots:
		var muzzle := _simulation.buildings.building(shot.tower_id).centre
		var flight := Flight.new()
		flight.item = _take()
		flight.target_id = shot.target_id
		flight.from = GridTransform.grid_to_world(muzzle) + Vector2.UP * MUZZLE_HEIGHT
		flight.to = GridTransform.grid_to_world(shot.position) + Vector2.UP * HIT_HEIGHT
		flight.started_msec = now
		flight.duration_msec = muzzle.distance_to(shot.position) / speed * 1000.0
		var heading := (flight.to - flight.from).angle()
		RenderingServer.canvas_item_set_transform(flight.item, Transform2D(heading, flight.from))
		_flights.append(flight)


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	var flying: Array[Flight] = []
	for flight in _flights:
		var progress := (now - flight.started_msec) / maxf(flight.duration_msec, 1.0)
		if progress >= 1.0:
			_enemy_renderer.flash(flight.target_id)
			_release(flight.item)
			continue
		var heading := (flight.to - flight.from).angle()
		var head := flight.from.lerp(flight.to, progress)
		RenderingServer.canvas_item_set_transform(flight.item, Transform2D(heading, head))
		flying.append(flight)
	_flights = flying


func _take() -> RID:
	var item: RID
	if _free.is_empty():
		item = RenderingServer.canvas_item_create()
		RenderingServer.canvas_item_set_parent(item, get_canvas_item())
		var region := Rect2(Atlas.TRACER_REGION)
		var rect := Rect2(Vector2(-region.size.x, -region.size.y / 2.0), region.size)
		RenderingServer.canvas_item_add_texture_rect_region(item, rect, _texture.get_rid(), region)
		RenderingServer.canvas_item_set_modulate(item, TINT)
	else:
		item = _free.pop_back()
	RenderingServer.canvas_item_set_visible(item, true)
	return item


func _release(item: RID) -> void:
	RenderingServer.canvas_item_set_visible(item, false)
	_free.append(item)


func _exit_tree() -> void:
	for flight in _flights:
		_free.append(flight.item)
	for item in _free:
		RenderingServer.free_rid(item)
