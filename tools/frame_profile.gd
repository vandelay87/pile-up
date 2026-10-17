# Splits each frame's wall-clock time into its tick, its process callbacks, its draw (frame setup
# is the first part of the draw) and the rest, so a frame's spikes show where they come from.
class_name FrameProfile
extends RefCounted


class Table:
	var frame := StepProfile.Stats.new()
	var tick := StepProfile.Stats.new()
	var process := StepProfile.Stats.new()
	var render := StepProfile.Stats.new()
	## Part of render.
	var frame_setup := StepProfile.Stats.new()
	var other := StepProfile.Stats.new()


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
	var worst := _worst_frames()
	var frame_mean := _mean(_frame_msec)
	var result := Table.new()
	result.frame = _stats(_frame_msec, worst, frame_mean)
	result.tick = _stats(_tick_msec, worst, frame_mean)
	result.process = _stats(_process_msec, worst, frame_mean)
	result.render = _stats(_render_msec, worst, frame_mean)
	result.frame_setup = _stats(_frame_setup_msec, worst, frame_mean)
	result.other = _stats(other_msec, worst, frame_mean)
	return result


func _worst_frames() -> PackedInt32Array:
	var by_cost := range(_frame_msec.size())
	by_cost.sort_custom(func(a: int, b: int) -> bool: return _frame_msec[a] > _frame_msec[b])
	var count := maxi(1, ceili(_frame_msec.size() * StepProfile.WORST_TICK_SHARE))
	return PackedInt32Array(by_cost.slice(0, count))


func _stats(
	samples: PackedFloat64Array, worst: PackedInt32Array, frame_mean: float
) -> StepProfile.Stats:
	var sorted := samples.duplicate()
	sorted.sort()
	var stats := StepProfile.Stats.new()
	stats.mean_msec = _mean(samples)
	stats.p99_msec = sorted[ceili(sorted.size() * 0.99) - 1]
	stats.max_msec = sorted[-1]
	stats.share = stats.mean_msec / frame_mean
	var worst_total := 0.0
	for i in worst:
		worst_total += samples[i]
	stats.worst_ticks_mean_msec = worst_total / worst.size()
	return stats


func _mean(samples: PackedFloat64Array) -> float:
	var total := 0.0
	for sample in samples:
		total += sample
	return total / samples.size()
