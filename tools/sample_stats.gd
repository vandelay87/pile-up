# Summarises one column of timings (a tick step, or a part of the frame) for the bench reports.
class_name SampleStats
extends RefCounted

## The worst samples, as a share of all samples, that each column reports its mean inside.
const WORST_SHARE := 0.01

var mean_msec := 0.0
var p99_msec := 0.0
var max_msec := 0.0
## The column's mean as a share of the whole's mean (the tick's, or the frame's).
var share := 0.0
## The column's mean inside the whole's worst samples, picked by [method worst].
var worst_mean_msec := 0.0


## The indices of the worst [constant WORST_SHARE] of [param samples], at least one.
static func worst(samples: PackedFloat64Array) -> PackedInt32Array:
	var by_cost := range(samples.size())
	by_cost.sort_custom(func(a: int, b: int) -> bool: return samples[a] > samples[b])
	return PackedInt32Array(by_cost.slice(0, maxi(1, ceili(samples.size() * WORST_SHARE))))


static func of(
	samples: PackedFloat64Array, worst_indices: PackedInt32Array, whole_mean: float
) -> SampleStats:
	var sorted := samples.duplicate()
	sorted.sort()
	var stats := SampleStats.new()
	stats.mean_msec = mean(samples)
	stats.p99_msec = sorted[ceili(sorted.size() * 0.99) - 1]
	stats.max_msec = sorted[-1]
	stats.share = stats.mean_msec / whole_mean
	var worst_total := 0.0
	for i in worst_indices:
		worst_total += samples[i]
	stats.worst_mean_msec = worst_total / worst_indices.size()
	return stats


static func mean(samples: PackedFloat64Array) -> float:
	var total := 0.0
	for sample in samples:
		total += sample
	return total / samples.size()
