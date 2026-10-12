class_name BlastRings
extends Node2D

## A short ring of the blast radius where each bloater blows up, swelling and fading.

const TINT := Color(1.0, 0.75, 0.3)
const DURATION_MSEC := 350.0
const START_SHARE := 0.4

var _simulation: Simulation
var _texture: Texture2D
var _free: Array[RID] = []
var _rings: Array[Ring] = []


class Ring:
	extends RefCounted

	var item: RID
	var at: Vector2
	var started_msec: int


func setup(simulation: Simulation) -> void:
	_simulation = simulation
	_texture = load(Atlas.PATH)
	for ring in _rings:
		_release(ring.item)
	_rings.clear()
	_simulation.blasts.connect(_go_off)


func _go_off(went_off: Array[Blasts.Blast]) -> void:
	var now := Time.get_ticks_msec()
	for blast in went_off:
		var ring := Ring.new()
		ring.item = _take()
		ring.at = GridTransform.grid_to_world(blast.position)
		ring.started_msec = now
		_rings.append(ring)
	_draw_rings(now)


func _process(_delta: float) -> void:
	if not _rings.is_empty():
		_draw_rings(Time.get_ticks_msec())


func _draw_rings(now: int) -> void:
	var full := _simulation.settings.blast_radius * Atlas.BLAST_RING_SCALE
	var showing: Array[Ring] = []
	for ring in _rings:
		var progress := (now - ring.started_msec) / DURATION_MSEC
		if progress >= 1.0:
			_release(ring.item)
			continue
		var scale := full * lerpf(START_SHARE, 1.0, sqrt(progress))
		RenderingServer.canvas_item_set_transform(
			ring.item, Transform2D(0.0, Vector2(scale, scale), 0.0, ring.at)
		)
		RenderingServer.canvas_item_set_modulate(ring.item, Color(TINT, 1.0 - progress))
		showing.append(ring)
	_rings = showing


func _take() -> RID:
	var item: RID
	if _free.is_empty():
		item = RenderingServer.canvas_item_create()
		RenderingServer.canvas_item_set_parent(item, get_canvas_item())
		var region := Rect2(Atlas.BLAST_RING_REGION)
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
	for ring in _rings:
		_free.append(ring.item)
	for item in _free:
		RenderingServer.free_rid(item)
