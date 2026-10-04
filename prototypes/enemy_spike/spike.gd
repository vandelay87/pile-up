# PROTOTYPE: throwaway spike for issue #7. Not production code.
# Answers: do ~1,000 flow-field enemies with separation, drawn as pooled
# RenderingServer canvas items under a y-sorted parent, hold 60 fps on the M5?
#
# Interactive: Godot --path . prototypes/enemy_spike/spike.tscn
#   +/-  enemies by 250    D  dense/spread spawn    S  separation on/off
#   Y    y-sort on/off      V  vsync on/off          wheel / arrows  zoom / pan
# Benchmark:   Godot --path . prototypes/enemy_spike/spike.tscn -- --bench
extends Node2D

const GRID_W := 128
const GRID_H := 96
const CELL_COUNT := GRID_W * GRID_H
const SPEED := 1.5
const SEP_RADIUS := 0.6
const SEP_RADIUS_SQ := SEP_RADIUS * SEP_RADIUS
const SEP_STRENGTH := 2.0
const PILE_COUNT := 400
const SLOW_BY_LEVEL: Array[float] = [1.0, 0.85, 0.70, 0.55, 0.40, 0.0]
const ENEMY_REGION := Rect2(0, 0, 8, 12)
const PILE_REGION := Rect2(16, 0, 16, 16)
const GROUND_ATLAS_COORDS := Vector2i(0, 2)
const SENSIBLE_TINT := Color(0.85, 0.3, 0.3)
const DIRECT_TINT := Color(1.0, 0.7, 0.2)
const WINDOW := 120

const BENCH_SCENARIOS := [
	{"name": "1000 spread", "count": 1000, "dense": false, "sep": true, "ysort": true},
	{"name": "1000 dense", "count": 1000, "dense": true, "sep": true, "ysort": true},
	{"name": "1000 dense, no y-sort", "count": 1000, "dense": true, "sep": true, "ysort": false},
	{"name": "2000 dense", "count": 2000, "dense": true, "sep": true, "ysort": true},
	{"name": "4000 dense", "count": 4000, "dense": true, "sep": true, "ysort": true},
]
const BENCH_WARMUP := 180
const BENCH_FRAMES := 600

var base_x := GRID_W * 0.5
var base_y := GRID_H * 0.5

var pile_level := PackedByteArray()
var flow_sensible := PackedVector2Array()
var flow_direct := PackedVector2Array()

var agent_count := 0
var pos_x := PackedFloat32Array()
var pos_y := PackedFloat32Array()
var route := PackedByteArray()
var drawn_route := PackedByteArray()
var bucket_head := PackedInt32Array()
var bucket_next := PackedInt32Array()
var enemy_items: Array[RID] = []

var dense := false
var separation := true
var neighbours_checked := 0
var rng := RandomNumberGenerator.new()

var atlas: ImageTexture
var ground: TileMapLayer
var sorted_layer: Node2D
var camera: Camera2D
var hud: Label
var origin := Vector2.ZERO
var axis_x := Vector2.ZERO
var axis_y := Vector2.ZERO
var viewport_rid := RID()

var samples := {}
var bench_index := -1
var bench_frame := 0
var bench_rows: Array[String] = []


func _ready() -> void:
	rng.seed = 7
	viewport_rid = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(viewport_rid, true)
	_build_atlas()
	_build_ground()
	sorted_layer = Node2D.new()
	sorted_layer.y_sort_enabled = true
	add_child(sorted_layer)
	_build_world()
	_build_camera_and_hud()
	_reset_samples()
	if "--bench" in OS.get_cmdline_user_args():
		_set_vsync(false)
		_start_bench_scenario(0)
	else:
		_set_enemy_count(1000)
		_spawn_all()


func _build_atlas() -> void:
	var img := Image.create_empty(64, 64, false, Image.FORMAT_RGBA8)
	for y in 12:
		for x in 8:
			var dx := (x - 3.5) / 4.0
			var dy := (y - 6.0) / 6.0
			if dx * dx + dy * dy <= 1.0:
				img.set_pixel(x, y, Color.WHITE)
	img.fill_rect(Rect2i(16, 0, 16, 16), Color.WHITE)
	for y in 16:
		for x in 32:
			var d := absf(x - 15.5) / 16.0 + absf(y - 7.5) / 8.0
			if d <= 0.92:
				img.set_pixel(x, 32 + y, Color(0.35, 0.42, 0.3) if d < 0.8 else Color(0.28, 0.34, 0.24))
	atlas = ImageTexture.create_from_image(img)


func _build_ground() -> void:
	var tile_set := TileSet.new()
	tile_set.tile_shape = TileSet.TILE_SHAPE_ISOMETRIC
	tile_set.tile_layout = TileSet.TILE_LAYOUT_DIAMOND_DOWN
	tile_set.tile_size = Vector2i(32, 16)
	var source := TileSetAtlasSource.new()
	source.texture = atlas
	source.texture_region_size = Vector2i(32, 16)
	source.create_tile(GROUND_ATLAS_COORDS)
	tile_set.add_source(source, 0)
	ground = TileMapLayer.new()
	ground.tile_set = tile_set
	add_child(ground)
	for y in GRID_H:
		for x in GRID_W:
			ground.set_cell(Vector2i(x, y), 0, GROUND_ATLAS_COORDS)
	var c00 := ground.map_to_local(Vector2i(0, 0))
	axis_x = ground.map_to_local(Vector2i(1, 0)) - c00
	axis_y = ground.map_to_local(Vector2i(0, 1)) - c00
	origin = c00 - axis_x * 0.5 - axis_y * 0.5


func _grid_to_world(gx: float, gy: float) -> Vector2:
	return origin + axis_x * gx + axis_y * gy


func _build_world() -> void:
	pile_level.resize(CELL_COUNT)
	var parent := sorted_layer.get_canvas_item()
	for i in PILE_COUNT:
		var x := rng.randi_range(2, GRID_W - 3)
		var y := rng.randi_range(2, GRID_H - 3)
		if absf(x - base_x) < 4 and absf(y - base_y) < 4:
			continue
		if pile_level[y * GRID_W + x] > 0:
			continue
		var level := rng.randi_range(1, 5)
		pile_level[y * GRID_W + x] = level
		_add_static_item(parent, _grid_to_world(x + 0.5, y + 0.5),
				Rect2(-10, -4.0 * level, 20, 4.0 * level), Color(0.45, 0.3, 0.2).lightened(level * 0.05))
	_add_static_item(parent, _grid_to_world(base_x, base_y), Rect2(-24, -40, 48, 40), Color(0.4, 0.55, 0.9))
	flow_sensible = _build_flow_field(3)
	flow_direct = _build_flow_field(5)
	bucket_head.resize(CELL_COUNT)


func _add_static_item(parent: RID, at: Vector2, rect: Rect2, tint: Color) -> void:
	var item := RenderingServer.canvas_item_create()
	RenderingServer.canvas_item_set_parent(item, parent)
	RenderingServer.canvas_item_set_transform(item, Transform2D(0.0, at))
	RenderingServer.canvas_item_add_texture_rect_region(item, rect, atlas.get_rid(), PILE_REGION, tint)


# BFS from the base; cells at or above block_level are impassable. Route
# quality is out of scope for this spike, only lookup and movement cost.
func _build_flow_field(block_level: int) -> PackedVector2Array:
	var dist := PackedInt32Array()
	dist.resize(CELL_COUNT)
	dist.fill(1 << 30)
	var queue := PackedInt32Array()
	var start := int(base_y) * GRID_W + int(base_x)
	dist[start] = 0
	queue.append(start)
	var head := 0
	while head < queue.size():
		var c := queue[head]
		head += 1
		var cx := c % GRID_W
		var cy := c / GRID_W
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var nx := cx + dx
				var ny := cy + dy
				if nx < 0 or ny < 0 or nx >= GRID_W or ny >= GRID_H:
					continue
				var n := ny * GRID_W + nx
				if pile_level[n] >= block_level or dist[n] <= dist[c] + 1:
					continue
				dist[n] = dist[c] + 1
				queue.append(n)
	var field := PackedVector2Array()
	field.resize(CELL_COUNT)
	for c in CELL_COUNT:
		var cx := c % GRID_W
		var cy := c / GRID_W
		var best := dist[c]
		var dir := Vector2.ZERO
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var nx := cx + dx
				var ny := cy + dy
				if nx < 0 or ny < 0 or nx >= GRID_W or ny >= GRID_H:
					continue
				if dist[ny * GRID_W + nx] < best:
					best = dist[ny * GRID_W + nx]
					dir = Vector2(dx, dy).normalized()
		field[c] = dir
	return field


func _build_camera_and_hud() -> void:
	camera = Camera2D.new()
	camera.position = _grid_to_world(base_x, base_y)
	camera.zoom = Vector2(0.55, 0.55)
	add_child(camera)
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(8, 8)
	layer.add_child(panel)
	hud = Label.new()
	hud.add_theme_font_size_override("font_size", 14)
	panel.add_child(hud)


func _set_enemy_count(count: int) -> void:
	var parent := sorted_layer.get_canvas_item()
	while enemy_items.size() < count:
		var item := RenderingServer.canvas_item_create()
		RenderingServer.canvas_item_set_parent(item, parent)
		RenderingServer.canvas_item_add_texture_rect_region(item, Rect2(-4, -12, 8, 12), atlas.get_rid(), ENEMY_REGION)
		RenderingServer.canvas_item_set_modulate(item, SENSIBLE_TINT)
		enemy_items.append(item)
	for i in enemy_items.size():
		RenderingServer.canvas_item_set_visible(enemy_items[i], i < count)
	var old := agent_count
	agent_count = count
	pos_x.resize(count)
	pos_y.resize(count)
	route.resize(count)
	drawn_route.resize(count)
	bucket_next.resize(count)
	for i in range(old, count):
		_spawn_one(i, true)


func _spawn_all() -> void:
	for i in agent_count:
		_spawn_one(i, true)


func _spawn_one(i: int, anywhere: bool) -> void:
	while true:
		var x: float
		var y: float
		if dense:
			x = rng.randf_range(0.5, 25.0 if anywhere else 2.0)
			y = rng.randf_range(base_y - 12.0, base_y + 12.0)
		elif anywhere:
			x = rng.randf_range(0.0, GRID_W - 0.01)
			y = rng.randf_range(0.0, GRID_H - 0.01)
		else:
			var t := rng.randf()
			match rng.randi_range(0, 3):
				0: x = 0.5; y = t * (GRID_H - 0.01)
				1: x = GRID_W - 0.5; y = t * (GRID_H - 0.01)
				2: x = t * (GRID_W - 0.01); y = 0.5
				_: x = t * (GRID_W - 0.01); y = GRID_H - 0.5
		if pile_level[int(y) * GRID_W + int(x)] < 5:
			pos_x[i] = x
			pos_y[i] = y
			route[i] = 0
			return


func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_build_hash()
	_step(minf(delta, 1.0 / 30.0))
	var t1 := Time.get_ticks_usec()
	_update_items()
	var t2 := Time.get_ticks_usec()

	_record("frame", delta * 1000.0)
	_record("sim", (t1 - t0) / 1000.0)
	_record("items", (t2 - t1) / 1000.0)
	_record("gpu", RenderingServer.viewport_get_measured_render_time_gpu(viewport_rid))
	_record("render_cpu", RenderingServer.viewport_get_measured_render_time_cpu(viewport_rid)
			+ RenderingServer.get_frame_setup_time_cpu())
	_record("draw_calls", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	_record("neighbours", float(neighbours_checked) / maxi(agent_count, 1))

	if "--shot" in OS.get_cmdline_user_args() and Engine.get_process_frames() == 600:
		get_viewport().get_texture().get_image().save_png("user://spike_shot.png")
		print(ProjectSettings.globalize_path("user://spike_shot.png"))
		get_tree().quit()
	if bench_index >= 0:
		_bench_tick()
	else:
		_pan(delta)
		hud.text = _hud_text()


func _exit_tree() -> void:
	for item in enemy_items:
		RenderingServer.free_rid(item)


func _build_hash() -> void:
	bucket_head.fill(-1)
	for i in agent_count:
		var c := int(pos_y[i]) * GRID_W + int(pos_x[i])
		bucket_next[i] = bucket_head[c]
		bucket_head[c] = i


func _step(dt: float) -> void:
	var checked := 0
	for i in agent_count:
		var x: float = pos_x[i]
		var y: float = pos_y[i]
		var cx := int(x)
		var cy := int(y)
		var c := cy * GRID_W + cx

		var dir: Vector2 = flow_direct[c] if route[i] == 1 else flow_sensible[c]
		var slow: float = SLOW_BY_LEVEL[pile_level[c]]

		var sep_x := 0.0
		var sep_y := 0.0
		if separation:
			for ny in range(maxi(cy - 1, 0), mini(cy + 2, GRID_H)):
				var row := ny * GRID_W
				for nx in range(maxi(cx - 1, 0), mini(cx + 2, GRID_W)):
					var j := bucket_head[row + nx]
					while j != -1:
						if j != i:
							checked += 1
							var ox: float = x - pos_x[j]
							var oy: float = y - pos_y[j]
							var d2 := ox * ox + oy * oy
							if d2 < SEP_RADIUS_SQ and d2 > 0.000001:
								var push := (SEP_RADIUS - sqrt(d2)) / sqrt(d2)
								sep_x += ox * push
								sep_y += oy * push
						j = bucket_next[j]

		var step := SPEED * slow * dt
		var new_x := clampf(x + dir.x * step + sep_x * SEP_STRENGTH * dt, 0.0, GRID_W - 0.01)
		var new_y := clampf(y + dir.y * step + sep_y * SEP_STRENGTH * dt, 0.0, GRID_H - 0.01)
		var nc := int(new_y) * GRID_W + int(new_x)
		var ahead := pile_level[nc]
		if ahead == 5:
			continue
		if ahead > 0 and route[i] == 0 and nc != c:
			if rng.randf() < 0.05:
				route[i] = 1
		elif ahead == 0 and route[i] == 1:
			route[i] = 0

		var to_base_x := new_x - base_x
		var to_base_y := new_y - base_y
		if to_base_x * to_base_x + to_base_y * to_base_y < 1.0:
			_spawn_one(i, false)
			continue
		pos_x[i] = new_x
		pos_y[i] = new_y
	neighbours_checked = checked


func _update_items() -> void:
	var ox := origin.x
	var oy := origin.y
	var ax := axis_x
	var ay := axis_y
	for i in agent_count:
		var gx: float = pos_x[i]
		var gy: float = pos_y[i]
		var at := Vector2(ox + ax.x * gx + ay.x * gy, oy + ax.y * gx + ay.y * gy)
		RenderingServer.canvas_item_set_transform(enemy_items[i], Transform2D(0.0, at))
		if drawn_route[i] != route[i]:
			drawn_route[i] = route[i]
			RenderingServer.canvas_item_set_modulate(enemy_items[i], DIRECT_TINT if route[i] == 1 else SENSIBLE_TINT)


func _record(key: String, value: float) -> void:
	if not samples.has(key):
		samples[key] = PackedFloat64Array()
	var arr: PackedFloat64Array = samples[key]
	arr.append(value)
	if bench_index < 0 and arr.size() > WINDOW:
		arr.remove_at(0)
	samples[key] = arr


func _reset_samples() -> void:
	samples = {}


func _stats(key: String) -> Vector2:
	var arr: PackedFloat64Array = samples.get(key, PackedFloat64Array())
	if arr.is_empty():
		return Vector2.ZERO
	var sorted := arr.duplicate()
	sorted.sort()
	var sum := 0.0
	for s in sorted:
		sum += s
	return Vector2(sum / sorted.size(), sorted[mini(int(sorted.size() * 0.95), sorted.size() - 1)])


func _hud_text() -> String:
	var lines: Array[String] = []
	lines.append("PROTOTYPE spike #7 | %s | %s" % [Engine.get_version_info().string, OS.get_processor_name()])
	lines.append("enemies %d | %s | separation %s | y-sort %s | vsync %s" % [
		agent_count, "dense" if dense else "spread", _on(separation), _on(sorted_layer.y_sort_enabled),
		_on(DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED)])
	lines.append("fps %d" % Engine.get_frames_per_second())
	lines.append("                mean    p95  (ms, last %d frames)" % WINDOW)
	for key in ["frame", "sim", "items", "render_cpu", "gpu"]:
		var s := _stats(key)
		lines.append("%-12s %7.2f %7.2f" % [key, s.x, s.y])
	lines.append("draw calls %d | neighbours/enemy %.1f" % [_stats("draw_calls").x, _stats("neighbours").x])
	lines.append("+/- count  D dense  S sep  Y y-sort  V vsync\nZ/X or pinch: zoom  B: zoom to base  arrows or two-finger drag: move")
	return "\n".join(lines)


func _on(b: bool) -> String:
	return "on" if b else "off"


func _set_vsync(on: bool) -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if on else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_by(1.1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_by(1.0 / 1.1)
	elif event is InputEventMagnifyGesture:
		_zoom_by(event.factor)
	elif event is InputEventPanGesture:
		camera.position += event.delta * 20.0 / camera.zoom.x
	if not (event is InputEventKey and event.pressed and not event.echo) or bench_index >= 0:
		return
	match event.keycode:
		KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
			_set_enemy_count(agent_count + 250)
		KEY_MINUS, KEY_KP_SUBTRACT:
			_set_enemy_count(maxi(agent_count - 250, 0))
		KEY_D:
			dense = not dense
			_spawn_all()
		KEY_S:
			separation = not separation
		KEY_Y:
			sorted_layer.y_sort_enabled = not sorted_layer.y_sort_enabled
		KEY_Z:
			_zoom_by(1.5)
		KEY_X:
			_zoom_by(1.0 / 1.5)
		KEY_B:
			camera.position = _grid_to_world(base_x, base_y)
			camera.zoom = Vector2(3.0, 3.0)
		KEY_V:
			_set_vsync(DisplayServer.window_get_vsync_mode() == DisplayServer.VSYNC_DISABLED)


func _zoom_by(factor: float) -> void:
	camera.zoom = (camera.zoom * factor).clamp(Vector2(0.3, 0.3), Vector2(8.0, 8.0))


func _pan(delta: float) -> void:
	var move := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	camera.position += move * 800.0 * delta / camera.zoom.x


func _start_bench_scenario(index: int) -> void:
	bench_index = index
	bench_frame = 0
	var sc: Dictionary = BENCH_SCENARIOS[index]
	dense = sc["dense"]
	separation = sc["sep"]
	sorted_layer.y_sort_enabled = sc["ysort"]
	_set_enemy_count(sc["count"])
	_spawn_all()
	_reset_samples()


func _bench_tick() -> void:
	bench_frame += 1
	if bench_frame == BENCH_WARMUP:
		_reset_samples()
	if bench_frame < BENCH_WARMUP + BENCH_FRAMES:
		return
	var sc: Dictionary = BENCH_SCENARIOS[bench_index]
	var f := _stats("frame")
	var row := "| %-22s | %5.2f / %5.2f | %5.2f / %5.2f | %5.2f / %5.2f | %5.2f / %5.2f | %5.2f / %5.2f | %4d | %4.1f |" % [
		sc["name"], f.x, f.y, _stats("sim").x, _stats("sim").y, _stats("items").x, _stats("items").y,
		_stats("render_cpu").x, _stats("render_cpu").y, _stats("gpu").x, _stats("gpu").y,
		_stats("draw_calls").x, _stats("neighbours").x]
	bench_rows.append(row)
	print(row)
	if bench_index + 1 < BENCH_SCENARIOS.size():
		_start_bench_scenario(bench_index + 1)
		return
	print("")
	print("%s | %s | debug build: %s | window %s | vsync off" % [
		Engine.get_version_info().string, OS.get_processor_name(), OS.is_debug_build(),
		DisplayServer.window_get_size()])
	print("| scenario | frame mean/p95 | sim | item updates | render CPU | GPU | draw calls | neighbours/enemy |")
	print("|---|---|---|---|---|---|---|---|")
	for r in bench_rows:
		print(r)
	get_tree().quit()
