## Draws each soldier as one figure from the atlas, in pooled canvas items in the y-sorted world,
## lifted by the pile level of the cell it stands on.
class_name SoldierRenderer
extends Node

const TINT := Color(0.3, 0.75, 0.95)

var _soldiers: Soldiers
var _parent: RID
var _texture: Texture2D
var _items: Array[RID] = []
var _sprites: Array[RID] = []
var _lifts := PackedFloat32Array()
var _shown := 0


func setup(simulation: Simulation, parent: CanvasItem) -> void:
	_soldiers = simulation.soldiers
	_parent = parent.get_canvas_item()
	_texture = load(Atlas.PATH)


func _process(_delta: float) -> void:
	if _soldiers == null:
		return
	var count := _soldiers.count
	while _items.size() < count:
		_create_item()
	for i in range(count, _shown):
		RenderingServer.canvas_item_set_visible(_items[i], false)
	for i in range(_shown, count):
		RenderingServer.canvas_item_set_visible(_items[i], true)
	_shown = count

	var positions := _soldiers.positions
	for i in count:
		var foot := GridTransform.grid_to_world(positions[i])
		RenderingServer.canvas_item_set_transform(_items[i], Transform2D(0.0, foot))
		var lift := float(_soldiers.elevation(i) * Atlas.PILE_SLAB_HEIGHT)
		if lift != _lifts[i]:
			_lifts[i] = lift
			RenderingServer.canvas_item_set_transform(
				_sprites[i], Transform2D(0.0, Vector2(0, -lift))
			)


func _create_item() -> void:
	var item := RenderingServer.canvas_item_create()
	RenderingServer.canvas_item_set_parent(item, _parent)
	RenderingServer.canvas_item_set_modulate(item, TINT)
	RenderingServer.canvas_item_set_visible(item, false)
	var sprite := RenderingServer.canvas_item_create()
	RenderingServer.canvas_item_set_parent(sprite, item)
	var region := Rect2(Atlas.SOLDIER_REGION)
	var rect := Rect2(Vector2(-region.size.x / 2.0, -region.size.y), region.size)
	RenderingServer.canvas_item_add_texture_rect_region(sprite, rect, _texture.get_rid(), region)
	_items.append(item)
	_sprites.append(sprite)
	_lifts.append(0.0)


func _exit_tree() -> void:
	for sprite in _sprites:
		RenderingServer.free_rid(sprite)
	for item in _items:
		RenderingServer.free_rid(item)
