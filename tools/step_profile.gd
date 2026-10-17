# Times each tick step from Simulation.step_observer's calls: a step lasts from its mark until
# the next step's, and the last step until the tick ends.
class_name StepProfile
extends RefCounted


class Table:
	var tick := SampleStats.new()
	## Indexed by Simulation.Step.
	var steps: Array[SampleStats] = []


var _tick_msec := PackedFloat64Array()
# Each finished tick's step times, indexed by Simulation.Step.
var _step_msec: Array[PackedFloat64Array] = []
var _mark_steps := PackedInt32Array()
var _mark_usec := PackedInt64Array()


## Step [param step] started at [param usec].
func mark(step: Simulation.Step, usec: int) -> void:
	_mark_steps.append(step)
	_mark_usec.append(usec)


## Closes the marked tick, which took [param tick_msec] in all from its first mark.
func finish_tick(tick_msec: float) -> void:
	var last_mark := _mark_steps.size() - 1
	var row := PackedFloat64Array()
	row.resize(Simulation.Step.size())
	for m in last_mark:
		row[_mark_steps[m]] = (_mark_usec[m + 1] - _mark_usec[m]) / 1000.0
	row[_mark_steps[last_mark]] = tick_msec - (_mark_usec[last_mark] - _mark_usec[0]) / 1000.0
	_step_msec.append(row)
	_tick_msec.append(tick_msec)
	_mark_steps.clear()
	_mark_usec.clear()


func table() -> Table:
	var worst := SampleStats.worst(_tick_msec)
	var tick_mean := SampleStats.mean(_tick_msec)
	var result := Table.new()
	result.tick = SampleStats.of(_tick_msec, worst, tick_mean)
	for step in Simulation.Step.size():
		var column := PackedFloat64Array()
		for row in _step_msec:
			column.append(row[step])
		result.steps.append(SampleStats.of(column, worst, tick_mean))
	return result
