class_name TickCost
extends RefCounted

const WINDOW_MSEC := 1000

var _times := PackedInt64Array()
var _costs := PackedFloat64Array()


func record(cost_msec: float, now_msec: int) -> void:
	_times.append(now_msec)
	_costs.append(cost_msec)
	_trim(now_msec)


func mean_msec(now_msec: int) -> float:
	_trim(now_msec)
	if _costs.is_empty():
		return 0.0
	var total := 0.0
	for cost in _costs:
		total += cost
	return total / _costs.size()


func max_msec(now_msec: int) -> float:
	_trim(now_msec)
	var worst := 0.0
	for cost in _costs:
		worst = maxf(worst, cost)
	return worst


func _trim(now_msec: int) -> void:
	var first := _times.bsearch(now_msec - WINDOW_MSEC + 1)
	if first > 0:
		_times = _times.slice(first)
		_costs = _costs.slice(first)
