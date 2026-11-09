class_name PerchedFallsView
extends Node2D

## The short fall of a perched enemy's body, from its roof to its drop-off cell, where
## perched_bodies reports one: an enemy sprite dropping under gravity, then gone. The body is
## already on its pile in the sim. Pooled, as the soldier death effect is.

const DURATION_MSEC := 280.0

var _simulation: Simulation
var _texture: Texture2D
var _free: Array[RID] = []
var _falls: Array[Fall] = []


class Fall:
	extends RefCounted

	var item: RID
	var from: Vector2
	var to: Vector2
	var started_msec: int


func setup(simulation: Simulation) -> void:
	_simulation = simulation
	_texture = load(Atlas.PATH)
	for fall in _falls:
		_release(fall.item)
	_falls.clear()
	_simulation.perched_bodies.connect(_drop)


func _drop(drops: Array[Perches.Drop]) -> void:
	var now := Time.get_ticks_msec()
	for drop in drops:
		var fall := Fall.new()
		fall.item = _take()
		var roof := Heights.of_cell(_simulation, Vector2i(drop.died_at.floor()))
		fall.from = GridTransform.grid_to_world(drop.died_at) + Vector2.UP * roof
		var ground := _simulation.piles.level(drop.cell) * Atlas.PILE_SLAB_HEIGHT
		fall.to = GridTransform.grid_to_world(MapData.centre_of(drop.cell)) + Vector2.UP * ground
		fall.started_msec = now
		_falls.append(fall)
	_draw_falls(now)


func _process(_delta: float) -> void:
	if not _falls.is_empty():
		_draw_falls(Time.get_ticks_msec())


func _draw_falls(now: int) -> void:
	var showing: Array[Fall] = []
	for fall in _falls:
		var progress := (now - fall.started_msec) / DURATION_MSEC
		if progress >= 1.0:
			_release(fall.item)
			continue
		# Across at an even pace, down gathering speed.
		var at := Vector2(
			lerpf(fall.from.x, fall.to.x, progress),
			lerpf(fall.from.y, fall.to.y, progress * progress)
		)
		RenderingServer.canvas_item_set_transform(fall.item, Transform2D(0.0, at))
		showing.append(fall)
	_falls = showing


func _take() -> RID:
	var item: RID
	if _free.is_empty():
		item = RenderingServer.canvas_item_create()
		RenderingServer.canvas_item_set_parent(item, get_canvas_item())
		RenderingServer.canvas_item_set_modulate(item, EnemyRenderer.TINT)
		var region := Rect2(Atlas.ENEMY_REGION)
		var rect := Rect2(Vector2(-region.size.x / 2.0, -region.size.y), region.size)
		RenderingServer.canvas_item_add_texture_rect_region(item, rect, _texture.get_rid(), region)
	else:
		item = _free.pop_back()
	RenderingServer.canvas_item_set_visible(item, true)
	return item


func _release(item: RID) -> void:
	RenderingServer.canvas_item_set_visible(item, false)
	_free.append(item)


func _exit_tree() -> void:
	for fall in _falls:
		_free.append(fall.item)
	for item in _free:
		RenderingServer.free_rid(item)
