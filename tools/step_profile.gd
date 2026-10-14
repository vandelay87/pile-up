# Times each tick step from Simulation.step_observer's calls: a step lasts from its mark until
# the next step's, and the last step until the tick ends.
class_name StepProfile
extends RefCounted

## The worst ticks, as a share of all ticks, that each step reports its mean inside.
const WORST_TICKS := 0.01


class Stats:
	var mean_msec := 0.0
	var p99_msec := 0.0
	var max_msec := 0.0
	## Of the tick's mean.
	var share := 0.0
	var worst_ticks_mean_msec := 0.0


class Table:
	var tick := Stats.new()
	## Indexed by Simulation.Step.
	var steps: Array[Stats] = []


var _tick_msec := PackedFloat64Array()
## Each finished tick's step times, indexed by Simulation.Step.
var _step_msec: Array[PackedFloat64Array] = []
var _mark_steps := PackedInt32Array()
var _mark_usec := PackedInt64Array()


## Step [param step] started at [param usec].
func mark(step: int, usec: int) -> void:
	_mark_steps.append(step)
	_mark_usec.append(usec)


## Closes the marked tick, which took [param tick_msec] in all from its first mark.
func finish_tick(tick_msec: float) -> void:
	var last := _mark_steps.size() - 1
	var row := PackedFloat64Array()
	row.resize(Simulation.Step.size())
	for k in last:
		row[_mark_steps[k]] = (_mark_usec[k + 1] - _mark_usec[k]) / 1000.0
	row[_mark_steps[last]] = tick_msec - (_mark_usec[last] - _mark_usec[0]) / 1000.0
	_step_msec.append(row)
	_tick_msec.append(tick_msec)
	_mark_steps.clear()
	_mark_usec.clear()


func table() -> Table:
	var worst := _worst_ticks()
	var tick_mean := _mean(_tick_msec)
	var result := Table.new()
	result.tick = _stats(_tick_msec, worst, tick_mean)
	for step in Simulation.Step.size():
		var column := PackedFloat64Array()
		for row in _step_msec:
			column.append(row[step])
		result.steps.append(_stats(column, worst, tick_mean))
	return result


func _worst_ticks() -> PackedInt32Array:
	var order := PackedInt32Array(range(_tick_msec.size()))
	var by_cost := Array(order)
	by_cost.sort_custom(func(a: int, b: int) -> bool: return _tick_msec[a] > _tick_msec[b])
	return PackedInt32Array(by_cost.slice(0, maxi(1, ceili(_tick_msec.size() * WORST_TICKS))))


func _stats(samples: PackedFloat64Array, worst: PackedInt32Array, tick_mean: float) -> Stats:
	var sorted := samples.duplicate()
	sorted.sort()
	var stats := Stats.new()
	stats.mean_msec = _mean(samples)
	stats.p99_msec = sorted[ceili(sorted.size() * 0.99) - 1]
	stats.max_msec = sorted[-1]
	stats.share = stats.mean_msec / tick_mean
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
