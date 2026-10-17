# Runs the real Main scene with vsync off and a dense crowd near the base, with BenchCrowd's army
# among it, raising the enemy count until the p99 frame time, timed by FrameTimer, no longer holds
# 60 fps, then prints the Performance table.
# Run in the release export the way tools/bench_profile.gd says, with this scene as the main scene.
# Not with --write-movie: writing each frame out lands in the frame's time.
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
var _count := 0
var _frame := 0
var _frames := FrameTimer.new()
var _rows: Array[String] = []
var _largest_holding := 0
var _first_p99 := 0.0


func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_main = MAIN_SCENE.instantiate() as Main
	add_child(_main)
	if _main.simulation == null:
		get_tree().quit(1)
		return
	_crowd = BenchCrowd.new(_main.simulation, CROWD_SEED)
	_crowd.field_army()
	_start(FIRST_COUNT)


func _process(_delta: float) -> void:
	if _crowd == null:
		return
	if _frame < WARMUP_FRAMES:
		_frames.restart()
	else:
		_frames.lap(_main.simulation.tick_cost.last_msec())
		if _frame == WARMUP_FRAMES + MEASURED_FRAMES - 1:
			_finish_count()
			return
	_crowd.top_up(_count)
	_crowd.top_up_army()
	_crowd.send_army(_frame)
	_frame += 1


func _start(count: int) -> void:
	_count = count
	_frame = 0
	_frames.profile = FrameProfile.new()


func _finish_count() -> void:
	var table := _frames.profile.table()
	var frame_p99 := table.frame.p99_msec
	var holds := frame_p99 < FRAME_BUDGET_MSEC
	if _count == FIRST_COUNT:
		_first_p99 = frame_p99
	if holds:
		_largest_holding = _count
	_rows.append(_row(table, holds))
	if holds and _count + COUNT_STEP <= MAX_COUNT:
		_start(_count + COUNT_STEP)
		return
	_print_table()
	get_tree().quit()


func _row(table: FrameProfile.Table, holds: bool) -> String:
	var values := [
		_with_commas(_count),
		table.tick.mean_msec,
		table.tick.p99_msec,
		table.frame.mean_msec,
		table.frame.p99_msec,
		"yes" if holds else "no",
	]
	return "| %s | %.2f / %.2f ms | %.2f / %.2f ms | %s |" % values


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
	print("| Enemies | Tick mean / p99 | Frame mean / p99 | Holds 60 fps |")
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
			% [COUNT_STEP, _largest_holding_text()]
		)
	)


func _largest_holding_text() -> String:
	if _largest_holding == 0:
		return "under %s" % _with_commas(FIRST_COUNT)
	return _with_commas(_largest_holding)


func _with_commas(number: int) -> String:
	var digits := str(number)
	var grouped := ""
	while digits.length() > 3:
		grouped = "," + digits.right(3) + grouped
		digits = digits.left(-3)
	return digits + grouped
