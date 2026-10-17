# Splits each frame's wall-clock time into its tick, its process callbacks, its draw (frame setup
# is the first part of the draw) and the rest, so a frame's spikes show where they come from.
class_name FrameProfile
extends RefCounted


class Table:
	var frame := SampleStats.new()
	var tick := SampleStats.new()
	var process := SampleStats.new()
	var render := SampleStats.new()
	## Part of render.
	var frame_setup := SampleStats.new()
	var other := SampleStats.new()


var _frame_msec := PackedFloat64Array()
var _tick_msec := PackedFloat64Array()
var _process_msec := PackedFloat64Array()
var _render_msec := PackedFloat64Array()
var _frame_setup_msec := PackedFloat64Array()


## A frame took [param frame_msec] in all, [param tick_msec] of it ticking, [param process_msec]
## in process callbacks and [param render_msec] drawing, [param frame_setup_msec] of that
## setting the frame up.
func add_frame(
	frame_msec: float,
	tick_msec: float,
	process_msec: float,
	render_msec: float,
	frame_setup_msec: float,
) -> void:
	_frame_msec.append(frame_msec)
	_tick_msec.append(tick_msec)
	_process_msec.append(process_msec)
	_render_msec.append(render_msec)
	_frame_setup_msec.append(frame_setup_msec)


func table() -> Table:
	var other_msec := PackedFloat64Array()
	for i in _frame_msec.size():
		other_msec.append(_frame_msec[i] - _tick_msec[i] - _process_msec[i] - _render_msec[i])
	var worst := SampleStats.worst(_frame_msec)
	var frame_mean := SampleStats.mean(_frame_msec)
	var result := Table.new()
	result.frame = SampleStats.of(_frame_msec, worst, frame_mean)
	result.tick = SampleStats.of(_tick_msec, worst, frame_mean)
	result.process = SampleStats.of(_process_msec, worst, frame_mean)
	result.render = SampleStats.of(_render_msec, worst, frame_mean)
	result.frame_setup = SampleStats.of(_frame_setup_msec, worst, frame_mean)
	result.other = SampleStats.of(other_msec, worst, frame_mean)
	return result
