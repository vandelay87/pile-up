class_name EnemyRenderer
extends Node

const TINT := Color(0.85, 0.3, 0.3)
const BLOATER_TINT := Color(0.55, 0.85, 0.25)
const DIRECT_TINT := Color(0.95, 0.8, 0.2)
const FLASH_TINT := Color.WHITE
const FLASH_MSEC := 100
# Tumbling enemies are drawn raised above a wall's top, and tinted.
const TUMBLE_TINT := Color(1.0, 0.55, 0.15)
const TUMBLE_LIFT_LEVELS := 6.0
# A burning bloater pulses towards this, from this many times a second to the last.
const FUSE_TINT := Color(1.0, 0.95, 0.6)
const FUSE_PULSE_FROM := 2.0
const FUSE_PULSE_TO := 12.0

var _enemies: Enemies
var _settings: Settings
var _piles: Piles
var _map: MapData
var _parent: RID
var _texture: Texture2D
var _items: Array[RID] = []
var _sprites: Array[RID] = []
var _lifts := PackedFloat32Array()
# The drawn scale of each item's sprite: the bloater size for a bloater, else 1.
var _scales := PackedFloat32Array()
var _shown := 0
var _flash_ends := {}
var _flashed_items := PackedInt32Array()
var _route_tint := false
# The items tinted this frame for a tumble or a burning fuse, to restore next frame.
var _state_tinted := PackedInt32Array()


func setup(simulation: Simulation, parent: CanvasItem) -> void:
	_enemies = simulation.enemies
	_settings = simulation.settings
	_piles = simulation.piles
	_map = simulation.map
	_parent = parent.get_canvas_item()
	_texture = load(Atlas.PATH)
	_flash_ends.clear()


func flash(id: int) -> void:
	_flash_ends[id] = Time.get_ticks_msec() + FLASH_MSEC


func show_route_tint(on: bool) -> void:
	_route_tint = on
	if not on:
		for i in mini(_enemies.count, _items.size()):
			RenderingServer.canvas_item_set_modulate(_items[i], _tint(i))


func _process(_delta: float) -> void:
	if _enemies == null:
		return
	var count := _enemies.count
	while _items.size() < count:
		_create_item()
	for i in range(count, _shown):
		RenderingServer.canvas_item_set_visible(_items[i], false)
	for i in range(_shown, count):
		RenderingServer.canvas_item_set_visible(_items[i], true)
		# A reused item may still carry its last enemy's flash or tint: draw it afresh.
		_scales[i] = 0.0
	_shown = count

	var positions := _enemies.positions
	var tumbling := _enemies.tumbling
	var kinds := _enemies.kinds
	var tumble_lift := TUMBLE_LIFT_LEVELS * Atlas.PILE_SLAB_HEIGHT
	var bloater_size := _settings.bloater_size
	for i in count:
		var foot := GridTransform.grid_to_world(positions[i])
		RenderingServer.canvas_item_set_transform(_items[i], Transform2D(0.0, foot))
		var lift := _lift_at(positions[i])
		if tumbling[i] == 1:
			lift = maxf(lift, tumble_lift)
		var scale := bloater_size if kinds[i] == Enemies.Kind.BLOATER else 1.0
		if scale != _scales[i]:
			# Removal moves enemies between items, so a new kind here needs its own look.
			_scales[i] = scale
			_lifts[i] = NAN
			RenderingServer.canvas_item_set_modulate(_items[i], _tint(i))
		if lift != _lifts[i]:
			_lifts[i] = lift
			RenderingServer.canvas_item_set_transform(
				_sprites[i], Transform2D(0.0, Vector2(scale, scale), 0.0, Vector2(0, -lift))
			)
	_draw_tints(count)


func _lift_at(pos: Vector2) -> float:
	var shifted := pos - Vector2(0.5, 0.5)
	var corner := Vector2i(shifted.floor())
	var fraction := shifted - Vector2(corner)
	var levels := _piles.levels
	var height := 0.0
	for i in 4:
		var x := clampi(corner.x + (i & 1), 0, _map.width - 1)
		var y := clampi(corner.y + (i >> 1), 0, _map.height - 1)
		var level := levels[y * _map.width + x]
		if level == 0:
			continue
		var weight_x := fraction.x if i & 1 else 1.0 - fraction.x
		var weight_y := fraction.y if i >> 1 else 1.0 - fraction.y
		height += level * weight_x * weight_y
	return height * Atlas.PILE_SLAB_HEIGHT


# The enemy at [param index]'s own colour.
func _tint(index: int) -> Color:
	return BLOATER_TINT if _enemies.kinds[index] == Enemies.Kind.BLOATER else TINT


# A burning bloater's tint: its own, pulsing towards the fuse tint faster and faster as the
# fuse burns down. The pulse's phase is the integral of a rate rising linearly over the fuse.
func _fuse_tint(index: int, fuse_left: int) -> Color:
	var length := maxf(_settings.fuse_ticks, 1.0) / Simulation.TICKS_PER_SECOND
	var burnt := clampf(length - float(fuse_left) / Simulation.TICKS_PER_SECOND, 0.0, length)
	var cycles := FUSE_PULSE_FROM * burnt
	cycles += (FUSE_PULSE_TO - FUSE_PULSE_FROM) * burnt * burnt / (2.0 * length)
	var glow := 0.5 - 0.5 * cos(TAU * cycles)
	return _tint(index).lerp(FUSE_TINT, glow)


func _draw_tints(count: int) -> void:
	for i in _state_tinted:
		if i < count:
			RenderingServer.canvas_item_set_modulate(_items[i], _tint(i))
	_state_tinted.clear()
	if _route_tint:
		var routes := _enemies.routes
		for i in count:
			var direct := routes[i] == Routing.Route.DIRECT
			RenderingServer.canvas_item_set_modulate(_items[i], DIRECT_TINT if direct else _tint(i))
	else:
		for i in _flashed_items:
			if i < count:
				RenderingServer.canvas_item_set_modulate(_items[i], _tint(i))
	_flashed_items.clear()
	var tumbling := _enemies.tumbling
	var fuses := _enemies.fuses
	for i in count:
		if tumbling[i] == 1:
			RenderingServer.canvas_item_set_modulate(_items[i], TUMBLE_TINT)
			_state_tinted.append(i)
		elif fuses[i] > 0:
			RenderingServer.canvas_item_set_modulate(_items[i], _fuse_tint(i, fuses[i]))
			_state_tinted.append(i)
	var now := Time.get_ticks_msec()
	for id: int in _flash_ends.keys():
		var index := _enemies.index_of(id)
		if index == Enemies.NONE or now >= _flash_ends[id]:
			_flash_ends.erase(id)
			continue
		RenderingServer.canvas_item_set_modulate(_items[index], FLASH_TINT)
		_flashed_items.append(index)


func _create_item() -> void:
	var item := RenderingServer.canvas_item_create()
	RenderingServer.canvas_item_set_parent(item, _parent)
	RenderingServer.canvas_item_set_modulate(item, TINT)
	RenderingServer.canvas_item_set_visible(item, false)
	var sprite := RenderingServer.canvas_item_create()
	RenderingServer.canvas_item_set_parent(sprite, item)
	var region := Rect2(Atlas.ENEMY_REGION)
	var rect := Rect2(Vector2(-region.size.x / 2.0, -region.size.y), region.size)
	RenderingServer.canvas_item_add_texture_rect_region(sprite, rect, _texture.get_rid(), region)
	_items.append(item)
	_sprites.append(sprite)
	_lifts.append(0.0)
	_scales.append(1.0)


func _exit_tree() -> void:
	for sprite in _sprites:
		RenderingServer.free_rid(sprite)
	for item in _items:
		RenderingServer.free_rid(item)
