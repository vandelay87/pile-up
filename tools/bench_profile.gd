# Throwaway: profiles the tick by system for the 1,000-enemy research (#157). Never merged.
# Scenarios, chosen by a user arg: dense-1000, dense-1390 (a dense ring kept topped up, as in
# bench_frame), wave-20 (jump to wave 20 with the bench's ring of towers and an endless base).
extends Node
@warning_ignore_start("untyped_declaration", "unsafe_property_access", "unsafe_method_access", "unsafe_cast", "unsafe_call_argument", "inference_on_variant")

const MAIN_SCENE := preload("res://src/view/main.tscn")
const WARMUP_FRAMES := 240
const MEASURED_TICKS := 1800
const WAVE_MAX_TICKS := 7200

var _main: Main
var _sim: Simulation
var _crowd: BenchCrowd
var _scenario := "dense-1000"
var _count := 1000
var _warm := 0
var _ticks: Array[Dictionary] = []
var _frames: Array[Dictionary] = []
var _viewport: RID
var _done := false


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--scenario="):
			_scenario = arg.trim_prefix("--scenario=")
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_viewport = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_viewport, true)
	_main = MAIN_SCENE.instantiate() as Main
	add_child(_main)
	_sim = _main.simulation
	_crowd = BenchCrowd.new(_sim, 1)
	if _scenario.begins_with("dense-"):
		_count = int(_scenario.trim_prefix("dense-"))
	else:
		_count = 0
		_sim.jump_to_wave(20)
	_sim.step_observer = _on_step
	Prof.take()


func _on_step(step: Simulation.Step) -> void:
	if step != Simulation.Step.DRAIN_COMMANDS or _done:
		return
	var sections := Prof.take()
	if _warm < WARMUP_FRAMES:
		return
	sections[&"tick"] = int(_sim.tick_cost.last_msec() * 1000.0)
	sections[&"enemies"] = _sim.enemies.count
	_ticks.append(sections)
	if _ticks.size() % 300 == 0:
		print("ticks %d, enemies %d, tick %.2f ms" % [_ticks.size(), _sim.enemies.count, _sim.tick_cost.last_msec()])
	var limit := MEASURED_TICKS if _count > 0 else WAVE_MAX_TICKS
	if _ticks.size() >= limit or (_count == 0 and _sim.waves.phase != Waves.Phase.WAVE):
		_done = true
		_report()
		get_tree().quit()


func _process(_delta: float) -> void:
	if _done:
		return
	if _count > 0:
		_crowd.top_up(_count)
	if _warm < WARMUP_FRAMES:
		_warm += 1
		return
	# Shadow passes run on even frames; the monitors read then report the odd frame before.
	_warm += 1
	if _warm % 2 == 1:
		return
	var frame := {
		&"view process (frame without shadow passes)":
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		&"render":
		(
			RenderingServer.viewport_get_measured_render_time_cpu(_viewport)
			+ RenderingServer.get_frame_setup_time_cpu()
		),
	}
	frame.merge(_shadow_passes())
	_frames.append(frame)


# Times the pure per-enemy helpers of the move loops on the current field, outside the tick.
func _shadow_passes() -> Dictionary:
	var e := _sim.enemies
	var s := _sim.settings
	var radius := s.separation_radius
	var out := {}
	var t := Time.get_ticks_usec()
	for i in e.count:
		if e.tumbling[i] == 0:
			e._separation(i, radius, s.separation_push, s.neighbour_cap)
	out[&"separation"] = (Time.get_ticks_usec() - t) / 1000.0
	t = Time.get_ticks_usec()
	for i in e.count:
		if e.tumbling[i] == 0 and e.structure_targets[i] == Enemies.NONE:
			e._personal_space(i, s.personal_space_radius, s.personal_space_push)
	out[&"personal space"] = (Time.get_ticks_usec() - t) / 1000.0
	t = Time.get_ticks_usec()
	for i in e.count:
		if e.tumbling[i] == 0 and e.structure_targets[i] == Enemies.NONE:
			_sim.routing.sample_direction(e.routes[i], e.positions[i])
	out[&"sample direction"] = (Time.get_ticks_usec() - t) / 1000.0
	t = Time.get_ticks_usec()
	for i in e.count:
		if e.tumbling[i] == 0:
			e._resolve_collision(e.positions[i], radius)
	out[&"resolve collision (1 pass)"] = (Time.get_ticks_usec() - t) / 1000.0
	return out


func _report() -> void:
	var keys := {}
	for sections in _ticks:
		for key in sections:
			keys[key] = true
	var names: Array = keys.keys().filter(
		func(k): return k not in [&"tick", &"enemies", &"cells changed", &"field cells repaired"]
	)
	names.sort_custom(func(a, b): return _order(a) < _order(b))
	var ticks := _column(&"tick")
	var worst := _worst_indices(ticks, 0.01)
	print("")
	print(
		(
			"Godot %s | %s | debug build: %s | scenario %s | %d ticks after %d warm-up frames"
			% [
				Engine.get_version_info().string,
				OS.get_processor_name(),
				OS.is_debug_build(),
				_scenario,
				_ticks.size(),
				WARMUP_FRAMES,
			]
		)
	)
	var enemies := _column(&"enemies")
	print(
		(
			"Enemies on field: mean %.0f, max %.0f. Tick mean %.2f / p99 %.2f / max %.2f ms."
			% [_mean(enemies) * 1000.0, _max(enemies) * 1000.0, _mean(ticks), _p99(ticks), _max(ticks)]
		)
	)
	print(
		(
			"Ticks with field changes: %d of %d; changed cells per such tick mean %.1f; field cells repaired per such tick mean %.0f."
			% _change_stats()
		)
	)
	print("")
	print("| Section | Mean ms | p99 ms | Max ms | Share of tick mean | Mean in worst 1% ticks |")
	print("|---|---|---|---|---|---|")
	print(
		(
			"| **tick** | %.3f | %.3f | %.3f | 100%% | %.3f |"
			% [_mean(ticks), _p99(ticks), _max(ticks), _mean_at(ticks, worst)]
		)
	)
	for name in names:
		var column := _column(name)
		print(
			(
				"| %s | %.3f | %.3f | %.3f | %.1f%% | %.3f |"
				% [
					name,
					_mean(column),
					_p99(column),
					_max(column),
					100.0 * _mean(column) / _mean(ticks),
					_mean_at(column, worst),
				]
			)
		)
	print("")
	print("Per-enemy helpers, timed outside the tick once per frame (%d frames):" % _frames.size())
	print("| Helper or frame part | Mean ms | p99 ms |")
	print("|---|---|---|")
	for name in _frames[0].keys():
		var column := PackedFloat64Array()
		for frame in _frames:
			column.append(frame[name])
		print("| %s | %.3f | %.3f |" % [name, _mean(column), _p99(column)])


func _order(name: StringName) -> String:
	var parts := String(name).get_slice(" ", 0).split(".")
	var key := ""
	for part in parts:
		key += part.lpad(3, "0") + "."
	return key


func _column(name: StringName) -> PackedFloat64Array:
	var column := PackedFloat64Array()
	for sections in _ticks:
		column.append(sections.get(name, 0) / 1000.0)
	return column


func _change_stats() -> Array:
	var changed := 0
	var cells := 0
	var repaired := 0
	for sections in _ticks:
		if sections.has(&"cells changed"):
			changed += 1
			cells += sections[&"cells changed"]
			repaired += sections.get(&"field cells repaired", 0)
	return [changed, _ticks.size(), cells / maxf(changed, 1), repaired / maxf(changed, 1)]


func _worst_indices(column: PackedFloat64Array, share: float) -> PackedInt32Array:
	var order := range(column.size())
	order.sort_custom(func(a, b): return column[a] > column[b])
	return PackedInt32Array(order.slice(0, maxi(1, ceili(column.size() * share))))


func _mean_at(column: PackedFloat64Array, indices: PackedInt32Array) -> float:
	var total := 0.0
	for i in indices:
		total += column[i]
	return total / indices.size()


func _mean(samples: PackedFloat64Array) -> float:
	var total := 0.0
	for sample in samples:
		total += sample
	return total / maxi(samples.size(), 1)


func _max(samples: PackedFloat64Array) -> float:
	var worst := 0.0
	for sample in samples:
		worst = maxf(worst, sample)
	return worst


func _p99(samples: PackedFloat64Array) -> float:
	var sorted := samples.duplicate()
	sorted.sort()
	return sorted[ceili(sorted.size() * 0.99) - 1]
