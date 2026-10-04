# Headless micro-benchmark for the per-frame enemy update (issue #6).
# Run: Godot --headless --script docs/research/gdscript-enemy-loop/enemy_loop_bench.gd
extends SceneTree

const GRID_W := 128
const GRID_H := 96
const CELL_COUNT := GRID_W * GRID_H
const DT := 1.0 / 60.0
const SPEED := 1.5
const SEP_RADIUS := 0.6
const SEP_RADIUS_SQ := SEP_RADIUS * SEP_RADIUS
const SEP_STRENGTH := 2.0
const PILE_COUNT := 400
const WARMUP_FRAMES := 120
const MEASURED_FRAMES := 600
const SLOW_BY_LEVEL: Array[float] = [1.0, 0.85, 0.70, 0.55, 0.40, 0.0]

var base_x := GRID_W * 0.5
var base_y := GRID_H * 0.5

var pile_level := PackedByteArray()
var flow_sensible := PackedVector2Array()
var flow_direct := PackedVector2Array()

var agent_count := 0
var pos_x := PackedFloat32Array()
var pos_y := PackedFloat32Array()
var route := PackedByteArray()
var bucket_head := PackedInt32Array()
var bucket_next := PackedInt32Array()
var instance_buffer := PackedFloat32Array()
var multimesh := RID()

var neighbours_checked := 0
var rng := RandomNumberGenerator.new()


func _init() -> void:
	rng.seed = 6
	_build_world()
	print("Godot %s | %s | debug build: %s" % [
		Engine.get_version_info().string, OS.get_processor_name(), OS.is_debug_build()])
	print("grid %dx%d, %d piles, %d warmup + %d measured frames" % [
		GRID_W, GRID_H, PILE_COUNT, WARMUP_FRAMES, MEASURED_FRAMES])
	print("")
	for scenario in ["spread", "dense"]:
		for count in [1000, 2000]:
			_run(count, scenario, true)
	_run(1000, "dense", false)
	RenderingServer.free_rid(multimesh)
	quit()


func _run(count: int, scenario: String, typed: bool) -> void:
	_spawn(count, scenario)
	var hash_ms := PackedFloat64Array()
	var move_ms := PackedFloat64Array()
	var render_ms := PackedFloat64Array()
	var total_ms := PackedFloat64Array()
	var neighbour_total := 0
	for frame in WARMUP_FRAMES + MEASURED_FRAMES:
		neighbours_checked = 0
		var t0 := Time.get_ticks_usec()
		_build_hash()
		var t1 := Time.get_ticks_usec()
		if typed:
			_step_typed()
		else:
			_step_untyped()
		var t2 := Time.get_ticks_usec()
		_fill_render_buffer()
		var t3 := Time.get_ticks_usec()
		if frame >= WARMUP_FRAMES:
			hash_ms.append((t1 - t0) / 1000.0)
			move_ms.append((t2 - t1) / 1000.0)
			render_ms.append((t3 - t2) / 1000.0)
			total_ms.append((t3 - t0) / 1000.0)
			neighbour_total += neighbours_checked
	print("%d agents, %s, %s: avg %.1f neighbours checked/agent" % [
		count, scenario, "typed" if typed else "untyped",
		float(neighbour_total) / (MEASURED_FRAMES * count)])
	_report("  hash build ", hash_ms)
	_report("  move+sep   ", move_ms)
	_report("  render buf ", render_ms)
	_report("  TOTAL      ", total_ms)
	print("")


func _report(label: String, samples: PackedFloat64Array) -> void:
	var sorted := samples.duplicate()
	sorted.sort()
	var sum := 0.0
	for s in sorted:
		sum += s
	print("%s mean %6.3f  p50 %6.3f  p95 %6.3f  max %6.3f ms" % [
		label, sum / sorted.size(), sorted[sorted.size() / 2],
		sorted[int(sorted.size() * 0.95)], sorted[sorted.size() - 1]])


func _build_world() -> void:
	pile_level.resize(CELL_COUNT)
	for i in PILE_COUNT:
		var x := rng.randi_range(2, GRID_W - 3)
		var y := rng.randi_range(2, GRID_H - 3)
		if absf(x - base_x) < 4 and absf(y - base_y) < 4:
			continue
		pile_level[y * GRID_W + x] = rng.randi_range(1, 5)
	flow_sensible = _build_flow_field(3)
	flow_direct = _build_flow_field(5)
	bucket_head.resize(CELL_COUNT)
	multimesh = RenderingServer.multimesh_create()


# BFS from the base; cells at or above block_level are impassable. Only the
# lookup cost matters for the benchmark, not route quality.
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


func _spawn(count: int, scenario: String) -> void:
	agent_count = count
	pos_x.resize(count)
	pos_y.resize(count)
	route.resize(count)
	route.fill(0)
	bucket_next.resize(count)
	instance_buffer.resize(count * 8)
	RenderingServer.multimesh_allocate_data(multimesh, count, RenderingServer.MULTIMESH_TRANSFORM_2D)
	for i in count:
		while true:
			var x: float
			var y: float
			if scenario == "dense":
				x = rng.randf_range(1.0, 25.0)
				y = rng.randf_range(base_y - 12.0, base_y + 12.0)
			else:
				x = rng.randf_range(0.0, GRID_W - 0.01)
				y = rng.randf_range(0.0, GRID_H - 0.01)
			if pile_level[int(y) * GRID_W + int(x)] < 5:
				pos_x[i] = x
				pos_y[i] = y
				break


# Linked-list spatial hash keyed by grid cell: one O(n) pass, no prefix sum.
func _build_hash() -> void:
	bucket_head.fill(-1)
	for i in agent_count:
		var c := int(pos_y[i]) * GRID_W + int(pos_x[i])
		bucket_next[i] = bucket_head[c]
		bucket_head[c] = i


func _step_typed() -> void:
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

		var step := SPEED * slow * DT
		var new_x := clampf(x + dir.x * step + sep_x * SEP_STRENGTH * DT, 0.0, GRID_W - 0.01)
		var new_y := clampf(y + dir.y * step + sep_y * SEP_STRENGTH * DT, 0.0, GRID_H - 0.01)
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
			new_x = 0.5
			new_y = rng.randf_range(0.0, GRID_H - 0.01)
			route[i] = 0
		pos_x[i] = new_x
		pos_y[i] = new_y
	neighbours_checked = checked


# Same logic as _step_typed with static types removed, to show what typing buys.
func _step_untyped() -> void:
	var checked = 0
	for i in agent_count:
		var x = pos_x[i]
		var y = pos_y[i]
		var cx = int(x)
		var cy = int(y)
		var c = cy * GRID_W + cx

		var dir = flow_direct[c] if route[i] == 1 else flow_sensible[c]
		var slow = SLOW_BY_LEVEL[pile_level[c]]

		var sep_x = 0.0
		var sep_y = 0.0
		for ny in range(max(cy - 1, 0), min(cy + 2, GRID_H)):
			var row = ny * GRID_W
			for nx in range(max(cx - 1, 0), min(cx + 2, GRID_W)):
				var j = bucket_head[row + nx]
				while j != -1:
					if j != i:
						checked += 1
						var ox = x - pos_x[j]
						var oy = y - pos_y[j]
						var d2 = ox * ox + oy * oy
						if d2 < SEP_RADIUS_SQ and d2 > 0.000001:
							var push = (SEP_RADIUS - sqrt(d2)) / sqrt(d2)
							sep_x += ox * push
							sep_y += oy * push
					j = bucket_next[j]

		var step = SPEED * slow * DT
		var new_x = clamp(x + dir.x * step + sep_x * SEP_STRENGTH * DT, 0.0, GRID_W - 0.01)
		var new_y = clamp(y + dir.y * step + sep_y * SEP_STRENGTH * DT, 0.0, GRID_H - 0.01)
		var nc = int(new_y) * GRID_W + int(new_x)
		var ahead = pile_level[nc]
		if ahead == 5:
			continue
		if ahead > 0 and route[i] == 0 and nc != c:
			if rng.randf() < 0.05:
				route[i] = 1
		elif ahead == 0 and route[i] == 1:
			route[i] = 0

		var to_base_x = new_x - base_x
		var to_base_y = new_y - base_y
		if to_base_x * to_base_x + to_base_y * to_base_y < 1.0:
			new_x = 0.5
			new_y = rng.randf_range(0.0, GRID_H - 0.01)
			route[i] = 0
		pos_x[i] = new_x
		pos_y[i] = new_y
	neighbours_checked = checked


# 2D MultiMesh layout per instance: x.x, y.x, pad, origin.x, x.y, y.y, pad, origin.y.
func _fill_render_buffer() -> void:
	var buf := instance_buffer
	for i in agent_count:
		var x: float = pos_x[i]
		var y: float = pos_y[i]
		var o := i * 8
		buf[o] = 1.0
		buf[o + 1] = 0.0
		buf[o + 3] = (x - y) * 16.0
		buf[o + 4] = 0.0
		buf[o + 5] = 1.0
		buf[o + 7] = (x + y) * 8.0
	RenderingServer.multimesh_set_buffer(multimesh, buf)
