class_name Overflow
extends RefCounted

## Crushes. Every barrier, a connected stretch (8-way) of wall and building cells, has a label,
## and the clear and pile cells within the band of it belong to it. Enemies stalled in a
## barrier's band fill its gauge, which leaks; above the start reading the crush is active, with
## a tier.

enum Tier { NONE, TRICKLE, STREAM, SURGE }

const NONE := -1
const _UNREACHED := 255
const _NEIGHBOURS: Array[Vector2i] = [
	Vector2i(-1, -1),
	Vector2i(0, -1),
	Vector2i(1, -1),
	Vector2i(-1, 0),
	Vector2i(1, 0),
	Vector2i(-1, 1),
	Vector2i(0, 1),
	Vector2i(1, 1),
]

## 1 on each cell in a band, 0 elsewhere: where Enemies tracks progress.
var band_mask := PackedByteArray()

var _settings: Settings
var _map: MapData
var _structures: Structures
var _enemies: Enemies
# Barrier label per cell, or NONE.
var _labels := PackedInt32Array()
# The label of the barrier whose band each cell is in, or NONE, and its steps from that barrier.
var _band_labels := PackedInt32Array()
var _band_steps := PackedByteArray()
var _next_label := 0
var _crushes: Dictionary[int, Crush] = {}


## One barrier's gauge, and the stalled enemies filling it this tick.
class Crush:
	extends RefCounted

	var label: int
	var gauge := 0.0
	var active := false
	var tier := Tier.NONE
	var stalled := 0
	## The mean position of its stalled enemies; kept from the last tick that had any.
	var centre := Vector2.ZERO
	var _centre_sum := Vector2.ZERO

	func _init(crush_label: int) -> void:
		label = crush_label

	func clear_stalled() -> void:
		stalled = 0
		_centre_sum = Vector2.ZERO

	func add_stalled(pos: Vector2) -> void:
		stalled += 1
		_centre_sum += pos
		centre = _centre_sum / stalled


func _init(
	run_settings: Settings, run_map: MapData, run_structures: Structures, run_enemies: Enemies
) -> void:
	_settings = run_settings
	_map = run_map
	_structures = run_structures
	_enemies = run_enemies
	var size := _map.width * _map.height
	_labels.resize(size)
	_labels.fill(NONE)
	_band_labels.resize(size)
	_band_labels.fill(NONE)
	_band_steps.resize(size)
	band_mask.resize(size)


## Relabels the barriers when a changed cell became, or stopped being, a wall or building. Other
## changes, such as a wall's HP bucket, leave the barriers as they are.
func update(cells: Array[Vector2i]) -> void:
	for cell in cells:
		var index := _map.index_of(cell)
		if (_labels[index] != NONE) != _structures.is_breakable(index):
			relabel()
			return


## Labels every barrier afresh. Each new barrier keeps the label, and so the gauge, of the old
## barrier it overlaps most, ties to the lower old label; an old barrier passes its gauge to one
## new barrier.
func relabel() -> void:
	var old_labels := _labels
	_labels = PackedInt32Array()
	_labels.resize(old_labels.size())
	_labels.fill(NONE)
	var barriers: Array[PackedInt32Array] = []
	var stack := PackedInt32Array()
	for index in _labels.size():
		if _labels[index] != NONE or not _structures.is_breakable(index):
			continue
		var barrier := PackedInt32Array()
		_labels[index] = barriers.size()
		stack.append(index)
		while not stack.is_empty():
			var cell := stack[stack.size() - 1]
			stack.remove_at(stack.size() - 1)
			barrier.append(cell)
			var at := _map.cell_of(cell)
			for offset in _NEIGHBOURS:
				var other := at + offset
				if not _map.in_bounds(other):
					continue
				var other_index := _map.index_of(other)
				if _labels[other_index] == NONE and _structures.is_breakable(other_index):
					_labels[other_index] = barriers.size()
					stack.append(other_index)
		barriers.append(barrier)
	var barrier_labels := _inherit(barriers, old_labels)
	for k in barriers.size():
		for cell in barriers[k]:
			_labels[cell] = barrier_labels[k]
	var kept := {}
	for label in barrier_labels:
		kept[label] = true
	for label: int in _crushes.keys():
		if not kept.has(label):
			_crushes.erase(label)
	_mark_band()


## The crushes with any gauge, in label order.
func crushes() -> Array[Crush]:
	var listed: Array[Crush] = []
	var labels := _crushes.keys()
	labels.sort()
	for label: int in labels:
		listed.append(_crushes[label])
	return listed


## The label of the barrier on [param cell], or NONE.
func barrier_label(cell: Vector2i) -> int:
	return _labels[_map.index_of(cell)]


## The label of the barrier whose band holds [param cell], or NONE.
func band_label(cell: Vector2i) -> int:
	return _band_labels[_map.index_of(cell)]


## Fills and leaks each gauge from the enemies stalled in its band this tick.
func step() -> void:
	if not _settings.overflow_enabled:
		_crushes.clear()
		return
	_gather()
	var dt := 1.0 / Simulation.TICKS_PER_SECOND
	var fill := _settings.fill_per_stalled
	var leak := _settings.overflow_leak
	var gauge_max := _settings.gauge_max
	for label: int in _crushes.keys():
		var crush: Crush = _crushes[label]
		crush.gauge = clampf(crush.gauge + (crush.stalled * fill - leak) * dt, 0.0, gauge_max)
		if not crush.active and crush.gauge > _settings.crush_start:
			crush.active = true
		elif crush.active and crush.gauge < _settings.crush_end:
			crush.active = false
		crush.tier = _tier_of(crush)
		if crush.gauge <= 0.0 and not crush.active:
			_crushes.erase(label)


func _tier_of(crush: Crush) -> Tier:
	if not crush.active:
		return Tier.NONE
	if crush.gauge >= _settings.surge_at:
		return Tier.SURGE
	if crush.gauge >= _settings.stream_at:
		return Tier.STREAM
	if crush.gauge >= _settings.trickle_at:
		return Tier.TRICKLE
	return Tier.NONE


func _gather() -> void:
	for crush: Crush in _crushes.values():
		crush.clear_stalled()
	var stall := _settings.stall_progress
	var positions := _enemies.positions
	var progress := _enemies.progress
	for i in _enemies.count:
		if not _enemies.is_alive(i) or progress[i] >= stall:
			continue
		var pos := positions[i]
		var label := _band_labels[int(pos.y) * _map.width + int(pos.x)]
		if label == NONE:
			continue
		var crush: Crush = _crushes.get(label)
		if crush == null:
			crush = Crush.new(label)
			_crushes[label] = crush
		crush.add_stalled(pos)


# Each new barrier (by index into [param barriers]) gets the old label it overlaps most. Pairs are
# settled from the largest overlap down, ties to the lower old label then the earlier barrier, so
# each old label goes to one barrier; a barrier left without one gets a fresh label.
func _inherit(barriers: Array[PackedInt32Array], old_labels: PackedInt32Array) -> PackedInt32Array:
	var pairs: Array[Vector3i] = []
	for k in barriers.size():
		var overlaps: Dictionary[int, int] = {}
		for cell in barriers[k]:
			var old := old_labels[cell]
			if old != NONE:
				overlaps[old] = overlaps.get(old, 0) + 1
		for old: int in overlaps:
			pairs.append(Vector3i(overlaps[old], old, k))
	pairs.sort_custom(
		func(a: Vector3i, b: Vector3i) -> bool:
			if a.x != b.x:
				return a.x > b.x
			if a.y != b.y:
				return a.y < b.y
			return a.z < b.z
	)
	var barrier_labels := PackedInt32Array()
	barrier_labels.resize(barriers.size())
	barrier_labels.fill(NONE)
	var taken := {}
	for pair in pairs:
		if barrier_labels[pair.z] == NONE and not taken.has(pair.y):
			barrier_labels[pair.z] = pair.y
			taken[pair.y] = true
	for k in barriers.size():
		if barrier_labels[k] == NONE:
			barrier_labels[k] = _next_label
			_next_label += 1
		_next_label = maxi(_next_label, barrier_labels[k] + 1)
	return barrier_labels


# Spreads out from every barrier a step at a time (8-way, through cells that aren't rock or
# structure) up to the band. A cell reached from two barriers at once goes to the lower label.
func _mark_band() -> void:
	var band := _settings.overflow_band
	_band_labels.fill(NONE)
	_band_steps.fill(_UNREACHED)
	var frontier := PackedInt32Array()
	for index in _labels.size():
		if _labels[index] != NONE:
			_band_steps[index] = 0
			frontier.append(index)
	for steps in range(1, band + 1):
		var next := PackedInt32Array()
		for cell in frontier:
			var label := _labels[cell] if steps == 1 else _band_labels[cell]
			var at := _map.cell_of(cell)
			for offset in _NEIGHBOURS:
				var other := at + offset
				if not _map.in_bounds(other):
					continue
				var other_index := _map.index_of(other)
				var reached := _band_steps[other_index]
				if reached == _UNREACHED:
					if _map.rock[other_index] == 1 or _structures.is_structure(other_index):
						continue
					_band_steps[other_index] = steps
					_band_labels[other_index] = label
					next.append(other_index)
				elif reached == steps and label < _band_labels[other_index]:
					_band_labels[other_index] = label
		frontier = next
	for index in band_mask.size():
		band_mask[index] = 1 if _band_labels[index] != NONE else 0
