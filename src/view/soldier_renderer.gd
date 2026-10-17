## Draws each soldier as one figure from the atlas, in pooled canvas items in the y-sorted world,
## lifted by the pile level of the cell it stands on. A soldier flashes white when a blast hits it,
## and pulses towards a warning colour while enemies are attacking it.
class_name SoldierRenderer
extends Node

const TINT := Color(0.3, 0.75, 0.95)
const FLASH_TINT := Color.WHITE
const FLASH_MSEC := 150
const ATTACKED_TINT := Color(1.0, 0.35, 0.25)
## Pulses a second while attacked.
const ATTACKED_PULSE_HZ := 2.0

var _enemies: Enemies
var _soldiers: Soldiers
var _parent: RID
var _texture: Texture2D
var _items: Array[RID] = []
var _sprites: Array[RID] = []
var _lifts := PackedFloat32Array()
var _shown := 0
# When each soldier hit by a blast stops flashing, by id.
var _flash_ends: Dictionary[int, int] = {}
var _attacked := PackedByteArray()


## How far the soldier at [param index] is drawn above its feet: its pile's height.
static func lift(soldiers: Soldiers, index: int) -> float:
	return float(soldiers.elevation(index) * Atlas.PILE_SLAB_HEIGHT)


func setup(simulation: Simulation, parent: CanvasItem) -> void:
	_enemies = simulation.enemies
	_soldiers = simulation.soldiers
	_parent = parent.get_canvas_item()
	_texture = load(Atlas.PATH)
	_flash_ends.clear()
	simulation.blasts.connect(_flash_hit)


func _flash_hit(went_off: Array[Blasts.Blast]) -> void:
	var ends := Time.get_ticks_msec() + FLASH_MSEC
	for blast in went_off:
		for id in blast.soldiers_hit:
			_flash_ends[id] = ends


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
		var lifted := lift(_soldiers, i)
		if lifted != _lifts[i]:
			_lifts[i] = lifted
			RenderingServer.canvas_item_set_transform(
				_sprites[i], Transform2D(0.0, Vector2(0, -lifted))
			)
	_tint(count)


# Items follow soldiers by index, which a death swaps, so every tint is set afresh each frame.
func _tint(count: int) -> void:
	_attacked.resize(count)
	_attacked.fill(0)
	var targets := _enemies.soldier_targets
	for e in _enemies.count:
		if targets[e] != Enemies.NONE:
			var i := _soldiers.index_of(targets[e])
			if i != Soldiers.NONE:
				_attacked[i] = 1
	var now := Time.get_ticks_msec()
	var pulse := 0.5 - 0.5 * cos(TAU * ATTACKED_PULSE_HZ * now / 1000.0)
	for id: int in _flash_ends.keys():
		if now >= _flash_ends[id] or _soldiers.index_of(id) == Soldiers.NONE:
			_flash_ends.erase(id)
	for i in count:
		var tint := TINT
		if _flash_ends.has(_soldiers.ids[i]):
			tint = FLASH_TINT
		elif _attacked[i] == 1:
			tint = TINT.lerp(ATTACKED_TINT, pulse)
		RenderingServer.canvas_item_set_modulate(_items[i], tint)


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
