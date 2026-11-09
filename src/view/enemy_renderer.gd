class_name EnemyRenderer
extends Node

const TINT := Color(0.85, 0.3, 0.3)
const BLOATER_TINT := Color(0.55, 0.85, 0.25)
# Steel grey-blue.
const BRUTE_TINT := Color(0.42, 0.52, 0.66)
const JUMPER_TINT := Color(0.62, 0.32, 0.85)
# A crouching jumper squashes down on the spot: wider and lower.
const CROUCH_SQUASH := Vector2(1.2, 0.7)
# An item's kind before it has drawn one.
const _NO_KIND := 255
const DIRECT_TINT := Color(0.95, 0.8, 0.2)
const FLASH_TINT := Color.WHITE
const FLASH_MSEC := 100
# A tumble is drawn as a low fall, rising just over the top of the tallest thing it crosses,
# by this much, then dropping beyond; tinted while it lasts.
const TUMBLE_TINT := Color(1.0, 0.55, 0.15)
const TUMBLE_CLEARANCE := 4.0
# A burning bloater pulses towards this, from this many times a second to the last.
const FUSE_TINT := Color(1.0, 0.95, 0.6)
const FUSE_PULSE_FROM := 2.0
const FUSE_PULSE_TO := 12.0

var _simulation: Simulation
var _enemies: Enemies
var _settings: Settings
var _piles: Piles
var _map: MapData
var _parent: RID
var _texture: Texture2D
var _items: Array[RID] = []
var _sprites: Array[RID] = []
# Each item's sprite offset from the item: up by its lift, and back from where it sorts to its
# feet for a perched enemy.
var _offsets := PackedVector2Array()
# The drawn scale of each item's sprite (its kind's size, squashed while crouching), and the kind
# it last drew.
var _shapes := PackedVector2Array()
var _kinds := PackedByteArray()
var _shown := 0
var _flash_ends := {}
var _flashed_items := PackedInt32Array()
var _route_tint := false
# The items tinted this frame for a tumble or a burning fuse, to restore next frame.
var _state_tinted := PackedInt32Array()


func setup(simulation: Simulation, parent: CanvasItem) -> void:
	_simulation = simulation
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
		_shapes[i] = Vector2.ZERO
		_kinds[i] = _NO_KIND
	_shown = count

	var positions := _enemies.positions
	var states := _enemies.states
	var kinds := _enemies.kinds
	var sizes := PackedFloat32Array()
	for kind: Enemies.Kind in Enemies.Kind.values():
		sizes.append(_settings.enemy_size_of(kind))
	for i in count:
		var foot := GridTransform.grid_to_world(positions[i])
		var sorted_at := foot
		var lift: float
		match states[i]:
			Enemies.State.TUMBLING:
				lift = _tumble_lift(i)
			Enemies.State.JUMPING:
				lift = _jump_lift(i)
			Enemies.State.PERCHED:
				# Sorted at the front corner of what it stands on, so its roof never hides it.
				var target := _simulation.perches.perched_on(_enemies.ids[i])
				lift = Heights.of_target(_simulation, target)
				sorted_at = _front_of(target, foot)
			_:
				lift = _lift_at(positions[i])
		RenderingServer.canvas_item_set_transform(_items[i], Transform2D(0.0, sorted_at))
		var offset := foot - sorted_at + Vector2(0, -lift)
		var shape := Vector2.ONE * sizes[kinds[i]]
		if states[i] == Enemies.State.CROUCHING:
			shape *= CROUCH_SQUASH
		if shape != _shapes[i] or kinds[i] != _kinds[i]:
			# Removal moves enemies between items, so a new kind here needs its own look.
			_shapes[i] = shape
			_offsets[i] = Vector2(NAN, NAN)
			if kinds[i] != _kinds[i]:
				_kinds[i] = kinds[i]
				RenderingServer.canvas_item_set_modulate(_items[i], _tint(i))
		if offset != _offsets[i]:
			_offsets[i] = offset
			RenderingServer.canvas_item_set_transform(
				_sprites[i], Transform2D(0.0, shape, 0.0, offset)
			)
	_draw_tints(count)


# The world point of the front corner of [param target], a building id or the base, or
# [param foot] when it is gone.
func _front_of(target: int, foot: Vector2) -> Vector2:
	var area := _simulation.map.base
	if target != Perches.BASE:
		var built := _simulation.buildings.building(target)
		if built == null:
			return foot
		area = Rect2i(built.origin, Buildings.footprint_size(built.kind))
	return GridTransform.grid_to_world(Vector2(area.end))


# The low fall: from the ground where the tumble started up to just over the tallest thing it
# crosses, peaking over that cell, then down to where it lands, a roof when it perches.
func _tumble_lift(i: int) -> float:
	var pos := _enemies.positions[i]
	var tumble := _simulation.overflow.tumble(_enemies.ids[i])
	if tumble == null:
		return _lift_at(pos)
	var path := tumble.path
	var last := path.size() - 1
	var end := _lift_at(path[last])
	if tumble.perching:
		end = Heights.of_target(_simulation, tumble.target)
	var top := end
	var top_at := last
	for k in last:
		var height := Heights.of_cell(_simulation, tumble.cells[k]) + TUMBLE_CLEARANCE
		if height > top:
			top = height
			top_at = k
	# How far along the way it is, and where its peak is, as distances from where it started.
	var total := 0.0
	var to_top := 0.0
	var travelled := 0.0
	var previous := tumble.from
	for k in path.size():
		var length := previous.distance_to(path[k])
		if k < tumble.next:
			travelled += length
		elif k == tumble.next:
			travelled += length - pos.distance_to(path[k])
		total += length
		if k == top_at:
			to_top = total
		previous = path[k]
	var start := _lift_at(tumble.from)
	if travelled <= to_top:
		var rise := travelled / to_top if to_top > 0.0 else 1.0
		return lerpf(start, top, sin(rise * PI / 2.0))
	var fall := (travelled - to_top) / maxf(total - to_top, 1e-6)
	return lerpf(top, end, 1.0 - cos(clampf(fall, 0.0, 1.0) * PI / 2.0))


# The jump's arc: from the ground where it crouched up to jump_clearance above the tallest wall,
# building, base or pile on its way, peaking halfway through its air time, then down to where it
# lands, a roof when it perches.
func _jump_lift(i: int) -> float:
	var pos := _enemies.positions[i]
	var jump := _simulation.jumps.jump(_enemies.ids[i])
	if jump == null or jump.is_crouching():
		return _lift_at(pos)
	var way := jump.way
	var start := _lift_at(way.from)
	var end := _lift_at(MapData.centre_of(way.landing()))
	if way.perching:
		end = Heights.of_target(_simulation, way.target)
	var tallest := maxf(start, end)
	for cell in way.cells:
		tallest = maxf(tallest, Heights.of_cell(_simulation, cell))
	var top := tallest + _settings.jump_clearance
	var through := clampf(float(jump.flown) / jump.air_ticks, 0.0, 1.0)
	if through <= 0.5:
		return lerpf(start, top, sin(through * PI))
	return lerpf(top, end, 1.0 - cos((through - 0.5) * PI))


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
	match _enemies.kinds[index]:
		Enemies.Kind.BLOATER:
			return BLOATER_TINT
		Enemies.Kind.BRUTE:
			return BRUTE_TINT
		Enemies.Kind.JUMPER:
			return JUMPER_TINT
	return TINT


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
	var states := _enemies.states
	var fuses := _enemies.fuses
	for i in count:
		if states[i] == Enemies.State.TUMBLING:
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
	_offsets.append(Vector2.ZERO)
	_shapes.append(Vector2.ONE)
	_kinds.append(_NO_KIND)


func _exit_tree() -> void:
	for sprite in _sprites:
		RenderingServer.free_rid(sprite)
	for item in _items:
		RenderingServer.free_rid(item)
