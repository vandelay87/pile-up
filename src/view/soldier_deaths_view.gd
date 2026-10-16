class_name SoldierDeathsView
extends Node2D

## A brief burst on the ground where each soldier falls, in the soldiers' colour, swelling and
## fading. No alert.

const DURATION_MSEC := 450.0
const START_SCALE := 0.5
const END_SCALE := 1.4

var _simulation: Simulation
var _texture: Texture2D
var _free: Array[RID] = []
var _bursts: Array[Burst] = []


class Burst:
	extends RefCounted

	var item: RID
	var at: Vector2
	var started_msec: int


func setup(simulation: Simulation) -> void:
	_simulation = simulation
	_texture = load(Atlas.PATH)
	for burst in _bursts:
		_release(burst.item)
	_bursts.clear()
	_simulation.soldiers_died.connect(_fall)


func _fall(deaths: SoldierDeaths) -> void:
	var now := Time.get_ticks_msec()
	for pos in deaths.positions:
		var burst := Burst.new()
		burst.item = _take()
		burst.at = GridTransform.grid_to_world(pos)
		burst.started_msec = now
		_bursts.append(burst)
	_draw_bursts(now)


func _process(_delta: float) -> void:
	if not _bursts.is_empty():
		_draw_bursts(Time.get_ticks_msec())


func _draw_bursts(now: int) -> void:
	var showing: Array[Burst] = []
	for burst in _bursts:
		var progress := (now - burst.started_msec) / DURATION_MSEC
		if progress >= 1.0:
			_release(burst.item)
			continue
		var scale := lerpf(START_SCALE, END_SCALE, sqrt(progress))
		RenderingServer.canvas_item_set_transform(
			burst.item, Transform2D(0.0, Vector2(scale, scale), 0.0, burst.at)
		)
		RenderingServer.canvas_item_set_modulate(
			burst.item, Color(SoldierRenderer.TINT, 1.0 - progress)
		)
		showing.append(burst)
	_bursts = showing


func _take() -> RID:
	var item: RID
	if _free.is_empty():
		item = RenderingServer.canvas_item_create()
		RenderingServer.canvas_item_set_parent(item, get_canvas_item())
		var region := Rect2(Atlas.DEATH_EFFECT_REGION)
		var rect := Rect2(-region.size / 2.0, region.size)
		RenderingServer.canvas_item_add_texture_rect_region(item, rect, _texture.get_rid(), region)
	else:
		item = _free.pop_back()
	RenderingServer.canvas_item_set_visible(item, true)
	return item


func _release(item: RID) -> void:
	RenderingServer.canvas_item_set_visible(item, false)
	_free.append(item)


func _exit_tree() -> void:
	for burst in _bursts:
		_free.append(burst.item)
	for item in _free:
		RenderingServer.free_rid(item)
