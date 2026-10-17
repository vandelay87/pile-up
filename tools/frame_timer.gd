# Times frames into a FrameProfile for a bench whose root node calls lap() or restart() at the top
# of its _process. As the scene's root it processes before Main and every view node, so a frame
# runs from one call to the next and holds, in the order Godot runs them:
# - the rest of the previous frame's process: the process callbacks after the root's, the message
#   queue flush and the RenderingServer sync, up to frame_pre_draw (Process);
# - the previous frame's draw, from frame_pre_draw to frame_post_draw, presenting included, which
#   bracket the draw with the default single-threaded renderer (Render);
# - this frame's physics, the tick in it (Tick);
# - the rest, end-of-frame work and physics outside the tick (Other).
# Performance.TIME_PROCESS is no use here: Godot sets it once a second to that second's worst
# process + sync + draw. Neither is the viewport's measured render time, read back frames late.
class_name FrameTimer
extends RefCounted

var profile := FrameProfile.new()
var _lap_usec := 0
var _pre_draw_usec := 0
var _post_draw_usec := 0
var _frame_setup_msec := 0.0
var _drew := false


func _init() -> void:
	RenderingServer.frame_pre_draw.connect(_on_pre_draw)
	RenderingServer.frame_post_draw.connect(_on_post_draw)


## Ends a frame that ticked for [param tick_msec] and adds it to [member profile]. A frame whose
## draw Godot skipped puts everything but its tick in Other.
func lap(tick_msec: float) -> void:
	var now := Time.get_ticks_usec()
	var process_msec := 0.0
	var render_msec := 0.0
	var frame_setup_msec := 0.0
	if _drew:
		process_msec = (_pre_draw_usec - _lap_usec) / 1000.0
		render_msec = (_post_draw_usec - _pre_draw_usec) / 1000.0
		frame_setup_msec = _frame_setup_msec
	var frame_msec := (now - _lap_usec) / 1000.0
	profile.add_frame(frame_msec, tick_msec, process_msec, render_msec, frame_setup_msec)
	_start(now)


## Starts a frame without adding the one that ends.
func restart() -> void:
	_start(Time.get_ticks_usec())


func _start(usec: int) -> void:
	_lap_usec = usec
	_drew = false


func _on_pre_draw() -> void:
	_pre_draw_usec = Time.get_ticks_usec()


func _on_post_draw() -> void:
	_post_draw_usec = Time.get_ticks_usec()
	_frame_setup_msec = RenderingServer.get_frame_setup_time_cpu()
	_drew = true
