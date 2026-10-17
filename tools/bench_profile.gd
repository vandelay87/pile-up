# Runs the real Main scene with vsync off and times each tick step with StepProfile, then prints
# the per-step table, times each frame with FrameTimer and prints its split, and checks the case
# against its performance target (v4 spec, section 5).
# Cases, chosen by a user arg:
#   --case=dense-1000  1,000 dense enemies from BenchCrowd: tick p99 ≤ 12 ms, frame p99 ≤ 16.7 ms
#   --case=dense-1390  the wave-20 crowd, dense: frame mean ≤ 16.7 ms
#   --case=wave-20     a real wave 20 against BenchCrowd's towers and endless base, jumped to once
#                      warm-up ends: no tick over 16.7 ms, for up to 7,200 ticks or until the wave
#                      ends
# With --army, BenchCrowd's army stands in and around the crowd's ring and a group of its soldiers
# is sent across the ring through the crowd every BenchCrowd.ORDER_INTERVAL ticks, alternating
# Cluster and Line, so the unit steps' cost shows.
# Run in the release export: in a copy of the project, set run/main_scene to this scene, drop
# tools/* from the macOS preset's exclude_filter, export with --export-release, then run one tick
# a frame with:
# pile-up.app/Contents/MacOS/pile-up --fixed-fps 60 -- --case=dense-1000
extends Node

const MAIN_SCENE := preload("res://src/view/main.tscn")
const CROWD_SEED := 1
const WARMUP_FRAMES := 240
const DENSE_TICKS := 1800
const WAVE := 20
const WAVE_TICKS := 7200
const FRAME_BUDGET_MSEC := 1000.0 / 60.0
const DENSE_TICK_P99_MSEC := 12.0
const CASES: Array[String] = ["dense-1000", "dense-1390", "wave-20"]

var _main: Main
var _sim: Simulation
var _crowd: BenchCrowd
var _case := "dense-1000"
var _dense_count := 0
var _profile := StepProfile.new()
var _frame := 0
var _measuring := false
var _ticked := false
var _ticks := 0
var _frames := FrameTimer.new()
var _enemies := PackedInt32Array()
var _army := false


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--case="):
			_case = arg.trim_prefix("--case=")
		elif arg == "--army":
			_army = true
	if _case not in CASES:
		push_error("bench_profile: expected --case= one of %s, got %s" % [CASES, _case])
		get_tree().quit(1)
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_main = MAIN_SCENE.instantiate() as Main
	add_child(_main)
	_sim = _main.simulation
	if _sim == null:
		get_tree().quit(1)
		return
	_crowd = BenchCrowd.new(_sim, CROWD_SEED)
	if _case != "wave-20":
		_dense_count = int(_case.trim_prefix("dense-"))
	if _army:
		_crowd.field_army()
	_sim.step_observer = _on_step


func _on_step(step: Simulation.Step) -> void:
	if not _measuring:
		return
	if step == Simulation.Step.DRAIN_COMMANDS and _ticked:
		push_error("bench_profile: two ticks in one frame; run with --fixed-fps 60 at speed 1")
		get_tree().quit(1)
		return
	_ticked = true
	_profile.mark(step, Time.get_ticks_usec())


# Main ticks in _physics_process, so this frame's tick has already run.
func _process(_delta: float) -> void:
	if _crowd == null:
		return
	if not _ticked:
		_frames.restart()
	else:
		_ticked = false
		var tick_msec := _sim.tick_cost.last_msec()
		_frames.lap(tick_msec)
		_profile.finish_tick(tick_msec)
		_ticks += 1
		_enemies.append(_sim.enemies.count)
		if _done():
			_print_report()
			get_tree().quit()
			return
	if _dense_count > 0:
		_crowd.top_up(_dense_count)
	if _army and _measuring:
		_crowd.top_up_army()
		_crowd.send_army(_ticks)
	_frame += 1
	if _frame == WARMUP_FRAMES:
		_measuring = true
		if _dense_count == 0:
			_sim.jump_to_wave(WAVE)


func _done() -> bool:
	if _dense_count > 0:
		return _ticks >= DENSE_TICKS
	return _ticks >= WAVE_TICKS or _sim.waves.phase != Waves.Phase.WAVE


func _print_report() -> void:
	var table := _profile.table()
	var frames := _frames.profile.table()
	print("")
	print(
		(
			(
				"Godot %s | %s | debug build: %s | window %s | vsync off | %d physics ticks/s"
				+ " | neighbour cap %d | case %s%s | %d ticks after %d warm-up frames"
			)
			% [
				Engine.get_version_info().string,
				OS.get_processor_name(),
				OS.is_debug_build(),
				DisplayServer.window_get_size(),
				Engine.physics_ticks_per_second,
				_sim.settings.neighbour_cap,
				_case,
				" with the army" if _army else "",
				_ticks,
				WARMUP_FRAMES,
			]
		)
	)
	print(
		(
			"Enemies on the field: mean %.0f, max %d. Frame mean %.2f / p99 %.2f ms."
			% [
				_mean_count(_enemies),
				_max_count(_enemies),
				frames.frame.mean_msec,
				frames.frame.p99_msec,
			]
		)
	)
	print("")
	print("| Step | Mean | p99 | Max | Share | Mean in worst 1% of ticks |")
	print("|---|---|---|---|---|---|")
	print(_row("**Tick**", table.tick))
	var names := PackedStringArray(Simulation.Step.keys())
	for step in names.size():
		print(_row(names[step].capitalize(), table.steps[step]))
	print("")
	print("The last step runs to the tick's end, so it includes emitting the tick's signals.")
	print("")
	print("| Frame part | Mean | p99 | Max | Share | Mean in worst 1% of frames |")
	print("|---|---|---|---|---|---|")
	print(_row("**Frame**", frames.frame))
	print(_row("Tick", frames.tick))
	print(_row("Process", frames.process))
	print(_row("Render", frames.render))
	print(_row("Render: frame setup", frames.frame_setup))
	print(_row("Other", frames.other))
	print("")
	print(
		(
			"Process runs from this bench's _process to frame_pre_draw, the RenderingServer sync"
			+ " included. Render runs to frame_post_draw, presenting included. Other is the rest."
		)
	)
	print("")
	print(_verdict(table, frames))


func _row(label: String, stats: SampleStats) -> String:
	var values := [
		label,
		stats.mean_msec,
		stats.p99_msec,
		stats.max_msec,
		stats.share * 100.0,
		stats.worst_mean_msec,
	]
	return "| %s | %.2f ms | %.2f ms | %.2f ms | %.1f%% | %.2f ms |" % values


func _verdict(table: StepProfile.Table, frames: FrameProfile.Table) -> String:
	match _case:
		"dense-1000":
			var frame_p99 := frames.frame.p99_msec
			var passed := (
				frame_p99 <= FRAME_BUDGET_MSEC and table.tick.p99_msec <= DENSE_TICK_P99_MSEC
			)
			return (
				"Target: frame p99 %.2f ms against %.2f ms, tick p99 %.2f ms against %.2f ms (%s)."
				% [
					frame_p99,
					FRAME_BUDGET_MSEC,
					table.tick.p99_msec,
					DENSE_TICK_P99_MSEC,
					_pass_text(passed),
				]
			)
		"dense-1390":
			var frame_mean := frames.frame.mean_msec
			return (
				"Target: frame mean %.2f ms against %.2f ms (%s)."
				% [frame_mean, FRAME_BUDGET_MSEC, _pass_text(frame_mean <= FRAME_BUDGET_MSEC)]
			)
		_:
			return (
				"Target: worst tick %.2f ms against %.2f ms (%s)."
				% [
					table.tick.max_msec,
					FRAME_BUDGET_MSEC,
					_pass_text(table.tick.max_msec <= FRAME_BUDGET_MSEC),
				]
			)


func _pass_text(passed: bool) -> String:
	return "pass" if passed else "FAIL"


func _mean_count(counts: PackedInt32Array) -> float:
	var total := 0
	for count in counts:
		total += count
	return float(total) / counts.size()


func _max_count(counts: PackedInt32Array) -> int:
	var most := 0
	for count in counts:
		most = maxi(most, count)
	return most
