# Draws the placeholder atlas and writes it to Atlas.PATH.
# Run with: godot --headless --script res://tools/make_atlas.gd
extends SceneTree

const GRASS := Color(0.37, 0.5, 0.3)
const ROCK := Color(0.24, 0.22, 0.24)
const BASE := Color(0.3, 0.47, 0.8)
const PILE := Color(0.66, 0.53, 0.42)
const WHITE := Color(1, 1, 1)
const BASE_HEIGHT := 48
const TOWER_HEIGHT := 56
const PYLON_HEIGHT := 64
const PYLON_HEAD_HEIGHT := 8
const UNPOWERED := Color(0.8, 0.2, 0.15)
const YARD := Color(0.95, 0.85, 0.55)
const YARD_HEIGHT := 14
const PAD := Color(0.45, 0.42, 0.38)
const DRONE := Color(0.95, 0.95, 0.95)
const ROTOR := Color(0.25, 0.25, 0.28)
const REPAIR := Color(0.35, 0.95, 0.45)


func _init() -> void:
	var image := Image.create_empty(
		Atlas.SIZE_IN_UNITS.x * Atlas.UNIT.x,
		Atlas.SIZE_IN_UNITS.y * Atlas.UNIT.y,
		false,
		Image.FORMAT_RGBA8
	)
	_draw_tile(image, Atlas.CLEAR, GRASS, 0.18)
	_draw_tile(image, Atlas.ROCK, ROCK, 0.06)
	for level in range(1, 6):
		_draw_pile(image, level)
	_draw_box_tile(image, Atlas.region(Atlas.BASE, Atlas.BASE_SIZE), BASE_HEIGHT, BASE)
	_draw_box_tile(image, Atlas.region(Atlas.TOWER, Atlas.TOWER_SIZE), TOWER_HEIGHT, WHITE)
	_draw_pylon(image)
	_draw_repair_yard(image)
	_draw_drone(image)
	_draw_repair_effect(image)
	_draw_unpowered_icon(image)
	_draw_enemy(image)
	_draw_tracer(image)
	var error := image.save_png(Atlas.PATH)
	if error != OK:
		push_error("could not write %s: %s" % [Atlas.PATH, error_string(error)])
	quit(error)


func _draw_tile(image: Image, coords: Vector2i, color: Color, outline_darkening: float) -> void:
	var area := Atlas.region(coords, Vector2i.ONE)
	var centre := Vector2(area.get_center())
	var half := Vector2(area.size) / 2.0
	_fill_diamond(image, centre, half, color)
	_outline_diamond(image, centre, half, color.darkened(outline_darkening))


func _draw_pile(image: Image, level: int) -> void:
	var area := Atlas.region(Atlas.pile(level), Atlas.PILE_SIZE)
	var foot := Vector2(area.get_center().x, area.end.y - Atlas.UNIT.y / 2.0)
	var color := PILE.darkened(0.12 * (level - 1))
	for slab in level:
		var half := Vector2(Atlas.UNIT) / 2.0 * (0.8 - 0.08 * slab)
		var centre := foot - Vector2(0, Atlas.PILE_SLAB_HEIGHT * slab)
		_draw_box(image, centre, half, Atlas.PILE_SLAB_HEIGHT - 1, color)


func _draw_box_tile(image: Image, area: Rect2i, height: int, color: Color) -> void:
	var footprint := Vector2(area.size.x, area.size.x / 2.0)
	var foot := Vector2(area.get_center().x, area.end.y - footprint.y / 2.0)
	_draw_box(image, foot, footprint / 2.0, height, color)


# A slim mast with a wider head, standing on one cell.
func _draw_pylon(image: Image) -> void:
	var area := Atlas.region(Atlas.PYLON, Atlas.PYLON_SIZE)
	var foot := Vector2(area.get_center().x, area.end.y - Atlas.UNIT.y / 2.0)
	_draw_box(image, foot, Vector2(8, 4), PYLON_HEIGHT, WHITE)
	var head := foot - Vector2(0, PYLON_HEIGHT - PYLON_HEAD_HEIGHT)
	_draw_box(image, head, Vector2(16, 8), PYLON_HEAD_HEIGHT, WHITE)


# A low platform with a dark landing pad on top.
func _draw_repair_yard(image: Image) -> void:
	var area := Atlas.region(Atlas.REPAIR_YARD, Atlas.REPAIR_YARD_SIZE)
	_draw_box_tile(image, area, YARD_HEIGHT, YARD)
	var footprint := Vector2(area.size.x, area.size.x / 2.0)
	var top := Vector2(area.get_center().x, area.end.y - footprint.y / 2.0 - YARD_HEIGHT)
	_fill_diamond(image, top, footprint / 2.0 * 0.5, PAD)
	_outline_diamond(image, top, footprint / 2.0 * 0.5, YARD)


# A small body between two rotors, seen from the side.
func _draw_drone(image: Image) -> void:
	var area := Atlas.DRONE_REGION
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var local := Vector2i(x, y) - area.position
			var rotor := local.y < 2 and (local.x < 7 or local.x >= area.size.x - 7)
			var arm := local.y == 3 and local.x >= 3 and local.x < area.size.x - 3
			var body := local.y >= 4 and local.x >= 6 and local.x < area.size.x - 6 and local.y < 10
			if rotor or arm:
				image.set_pixel(x, y, ROTOR)
			elif body:
				image.set_pixel(x, y, DRONE.darkened(0.2) if local.y >= 8 else DRONE)


# A green cross, drawn over a building while a drone repairs it.
func _draw_repair_effect(image: Image) -> void:
	var area := Atlas.REPAIR_EFFECT_REGION
	var centre := Vector2(area.get_center())
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var offset := (Vector2(x, y) + Vector2(0.5, 0.5) - centre).abs()
			if minf(offset.x, offset.y) < 2.5 and maxf(offset.x, offset.y) < 7.5:
				image.set_pixel(x, y, REPAIR)
			elif minf(offset.x, offset.y) < 3.5 and maxf(offset.x, offset.y) < 8.0:
				image.set_pixel(x, y, REPAIR.darkened(0.5))


# A red disc crossed by a white slash.
func _draw_unpowered_icon(image: Image) -> void:
	var area := Atlas.UNPOWERED_REGION
	var centre := Vector2(area.get_center())
	var radius := area.size.x / 2.0
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var offset := Vector2(x, y) + Vector2(0.5, 0.5) - centre
			if offset.length() > radius:
				continue
			var on_slash := absf(offset.x - offset.y) < 2.0 and offset.length() < radius - 2.0
			image.set_pixel(x, y, WHITE if on_slash else UNPOWERED)


func _draw_enemy(image: Image) -> void:
	var area := Atlas.ENEMY_REGION
	var centre := Vector2(area.get_center())
	var radius := Vector2(area.size) / 2.0
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var offset := (Vector2(x, y) + Vector2(0.5, 0.5) - centre) / radius
			if offset.length_squared() <= 1.0:
				var shade := WHITE.darkened(0.2) if offset.y > 0.35 else WHITE
				image.set_pixel(x, y, shade)


func _draw_tracer(image: Image) -> void:
	var area := Atlas.TRACER_REGION
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var alpha := float(x - area.position.x + 1) / area.size.x
			image.set_pixel(x, y, Color(WHITE, alpha))


func _draw_box(image: Image, foot: Vector2, half: Vector2, height: int, color: Color) -> void:
	for x in range(floori(foot.x - half.x), ceili(foot.x + half.x)):
		var across := 1.0 - absf(x + 0.5 - foot.x) / half.x
		if across <= 0.0:
			continue
		var bottom := foot.y + half.y * across
		var top := foot.y - half.y * across
		var side := color.darkened(0.25) if x + 0.5 < foot.x else color.darkened(0.4)
		for y in range(roundi(top - height), roundi(bottom)):
			var on_side := y + 0.5 > bottom - height
			image.set_pixel(x, y, side if on_side else color)


func _fill_diamond(image: Image, centre: Vector2, half: Vector2, color: Color) -> void:
	for y in range(floori(centre.y - half.y), ceili(centre.y + half.y)):
		for x in range(floori(centre.x - half.x), ceili(centre.x + half.x)):
			if _diamond_distance(Vector2(x, y), centre, half) <= 1.0:
				image.set_pixel(x, y, color)


func _outline_diamond(image: Image, centre: Vector2, half: Vector2, color: Color) -> void:
	var edge := 1.5 / half.y
	for y in range(floori(centre.y - half.y), ceili(centre.y + half.y)):
		for x in range(floori(centre.x - half.x), ceili(centre.x + half.x)):
			var distance := _diamond_distance(Vector2(x, y), centre, half)
			if distance <= 1.0 and distance > 1.0 - edge:
				image.set_pixel(x, y, color)


func _diamond_distance(pixel: Vector2, centre: Vector2, half: Vector2) -> float:
	var offset := (pixel + Vector2(0.5, 0.5) - centre).abs()
	return offset.x / half.x + offset.y / half.y
