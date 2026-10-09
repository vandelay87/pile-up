# Runs the real Main scene with vsync off and a dense crowd near the base, raising the enemy
# count until the p99 frame time no longer holds 60 fps, then prints the Performance table.
# Run in the foreground, or in movie mode so macOS does not throttle a background window:
# godot --path . tools/bench_frame.tscn --write-movie <scratch>/bench.avi --fixed-fps 60
extends Node

const MAIN_SCENE := preload("res://src/view/main.tscn")
const CROWD_SEED := 1
const FIRST_COUNT := 1000
const COUNT_STEP := 250
const MAX_COUNT := 10000
const WARMUP_FRAMES := 240
const MEASURED_FRAMES := 600
const FRAME_BUDGET_MSEC := 1000.0 / 60.0

var _main: Main
var _crowd: BenchCrowd
var _viewport: RID
var _count := 0
var _frame := 0
var _tick_msec := PackedFloat64Array()
var _frame_msec := PackedFloat64Array()
var _rows: Array[String] = []
var _largest_holding := 0
var _first_p99 := 0.0


func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_viewport = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_viewport, true)
	_main = MAIN_SCENE.instantiate() as Main
	add_child(_main)
	if _main.simulation == null:
		get_tree().quit(1)
		return
	_crowd = BenchCrowd.new(_main.simulation, CROWD_SEED)
	_start(FIRST_COUNT)


func _process(_delta: float) -> void:
	if _crowd == null:
		return
	_crowd.top_up(_count)
	_frame += 1
	if _frame <= WARMUP_FRAMES:
		return
	var tick := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var process := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var render := (
		RenderingServer.viewport_get_measured_render_time_cpu(_viewport)
		+ RenderingServer.get_frame_setup_time_cpu()
	)
	_tick_msec.append(tick)
	_frame_msec.append(tick + process + render)
	if _frame < WARMUP_FRAMES + MEASURED_FRAMES:
		return
	_finish_count()


func _start(count: int) -> void:
	_count = count
	_frame = 0
	_tick_msec.clear()
	_frame_msec.clear()


func _finish_count() -> void:
	var frame_p99 := _p99(_frame_msec)
	var holds := frame_p99 < FRAME_BUDGET_MSEC
	if _count == FIRST_COUNT:
		_first_p99 = frame_p99
	if holds:
		_largest_holding = _count
	_rows.append(_row(frame_p99, holds))
	if holds and _count + COUNT_STEP <= MAX_COUNT:
		_start(_count + COUNT_STEP)
		return
	_print_table()
	get_tree().quit()


func _row(frame_p99: float, holds: bool) -> String:
	var cells := [
		_with_commas(_count),
		_mean(_tick_msec),
		_p99(_tick_msec),
		_mean(_frame_msec),
		frame_p99,
		"yes" if holds else "no",
	]
	return "| %s | %.2f / %.2f ms | %.2f / %.2f ms | %s |" % cells


func _print_table() -> void:
	print("")
	print(
		(
			"Godot %s | %s | debug build: %s | window %s | vsync off | %d frames after %d warm-up"
			% [
				Engine.get_version_info().string,
				OS.get_processor_name(),
				OS.is_debug_build(),
				DisplayServer.window_get_size(),
				MEASURED_FRAMES,
				WARMUP_FRAMES,
			]
		)
	)
	print("")
	print("| Enemies | Tick mean / p99 | Frame CPU mean / p99 | Holds 60 fps |")
	print("|---|---|---|---|")
	for row in _rows:
		print(row)
	print("")
	print(
		(
			"%s dense enemies: p99 frame %.2f ms against %.2f ms (%s)."
			% [
				_with_commas(FIRST_COUNT),
				_first_p99,
				FRAME_BUDGET_MSEC,
				"pass" if _first_p99 < FRAME_BUDGET_MSEC else "FAIL",
			]
		)
	)
	print(
		(
			"Largest count that holds 60 fps, in steps of %d: %s."
			% [COUNT_STEP, _with_commas(_largest_holding)]
		)
	)


func _mean(samples: PackedFloat64Array) -> float:
	var total := 0.0
	for sample in samples:
		total += sample
	return total / samples.size()


func _p99(samples: PackedFloat64Array) -> float:
	var sorted := samples.duplicate()
	sorted.sort()
	return sorted[ceili(sorted.size() * 0.99) - 1]


func _with_commas(number: int) -> String:
	var digits := str(number)
	var grouped := ""
	while digits.length() > 3:
		grouped = "," + digits.right(3) + grouped
		digits = digits.left(-3)
	return digits + grouped
