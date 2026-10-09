class_name EnemyRenderer
extends Node

const TINT := Color(0.85, 0.3, 0.3)
const FLASH_TINT := Color.WHITE
const FLASH_MSEC := 100

var _enemies: Enemies
var _parent: RID
var _texture: Texture2D
var _items: Array[RID] = []
var _shown := 0
var _flash_ends := {}
var _flashed_items: Array[RID] = []


func setup(enemies: Enemies, parent: CanvasItem) -> void:
	_enemies = enemies
	_parent = parent.get_canvas_item()
	_texture = load(Atlas.PATH)
	_flash_ends.clear()


func flash(id: int) -> void:
	_flash_ends[id] = Time.get_ticks_msec() + FLASH_MSEC


func _process(_delta: float) -> void:
	if _enemies == null:
		return
	var count := _enemies.count
	while _items.size() < count:
		_items.append(_create_item())
	for i in range(count, _shown):
		RenderingServer.canvas_item_set_visible(_items[i], false)
	for i in range(_shown, count):
		RenderingServer.canvas_item_set_visible(_items[i], true)
	_shown = count

	var positions := _enemies.positions
	for i in count:
		var foot := GridTransform.grid_to_world(positions[i])
		RenderingServer.canvas_item_set_transform(_items[i], Transform2D(0.0, foot))
	_draw_flashes()


func _draw_flashes() -> void:
	for item in _flashed_items:
		RenderingServer.canvas_item_set_modulate(item, TINT)
	_flashed_items.clear()
	var now := Time.get_ticks_msec()
	for id: int in _flash_ends.keys():
		var index := _enemies.index_of(id)
		if index == Enemies.NONE or now >= _flash_ends[id]:
			_flash_ends.erase(id)
			continue
		RenderingServer.canvas_item_set_modulate(_items[index], FLASH_TINT)
		_flashed_items.append(_items[index])


func _create_item() -> RID:
	var item := RenderingServer.canvas_item_create()
	RenderingServer.canvas_item_set_parent(item, _parent)
	var region := Rect2(Atlas.ENEMY_REGION)
	var rect := Rect2(Vector2(-region.size.x / 2.0, -region.size.y), region.size)
	RenderingServer.canvas_item_add_texture_rect_region(item, rect, _texture.get_rid(), region)
	RenderingServer.canvas_item_set_modulate(item, TINT)
	RenderingServer.canvas_item_set_visible(item, false)
	return item


func _exit_tree() -> void:
	for item in _items:
		RenderingServer.free_rid(item)
