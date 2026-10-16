class_name Barracks
extends RefCounted

## Every barracks' training queue, in build order. A Train pays for each soldier as it is queued.
## In the build phase a queue trains at once; during a wave each barracks trains its queue's head
## while it is working. A new soldier appears on the free cell beside its barracks nearest the
## base, by the new-soldier rule.

const QUEUE_LENGTH := 5
## How many soldiers a shift-click Train asks for.
const BATCH := 5
const NOT_A_BARRACKS := "not a barracks"
const BAD_COUNT := "the count must be 1 or 5"
const QUEUE_FULL := "the queue is full"
const CAPACITY_FULL := "capacity is full"
const NOT_ENOUGH_GOLD := "not enough gold"
const NO_SUCH_SLOT := "no such slot"

var _settings: Settings
var _buildings: Buildings
var _run_state: RunState
var _soldiers: Soldiers
var _trainers: Array[Trainer] = []
var _by_id: Dictionary[int, Trainer] = {}
# The barracks whose queue or head changed since the last take_changed(), in order of change.
var _changed: Array[int] = []


class Trainer:
	extends RefCounted

	var barracks_id: int
	var area: Rect2i
	## The gold paid for each queued soldier, head first.
	var paid := PackedInt32Array()
	## Ticks the head has trained so far.
	var progress := 0

	func _init(barracks: Buildings.Building) -> void:
		barracks_id = barracks.id
		area = Rect2i(barracks.origin, Buildings.footprint_size(barracks.kind))


func _init(
	run_settings: Settings, run_buildings: Buildings, run_state: RunState, run_soldiers: Soldiers
) -> void:
	_settings = run_settings
	_buildings = run_buildings
	_run_state = run_state
	_soldiers = run_soldiers


## Creates a new barracks' empty queue.
func add(barracks: Buildings.Building) -> void:
	var trainer := Trainer.new(barracks)
	_trainers.append(trainer)
	_by_id[barracks.id] = trainer


## The gold paid for each soldier in a barracks' queue, head first; empty for no such barracks.
func queue_of(barracks_id: int) -> PackedInt32Array:
	var trainer: Trainer = _by_id.get(barracks_id, null)
	return PackedInt32Array() if trainer == null else trainer.paid


## [member Settings.barracks_capacity] for each standing barracks, unpowered ones included.
func capacity() -> int:
	return _settings.barracks_capacity * count()


## Living soldiers plus every queued one.
func used() -> int:
	var queued := 0
	for trainer in _trainers:
		queued += trainer.paid.size()
	return _soldiers.count + queued


## Ticks until a barracks' head is trained at wave pace, or 0 with an empty queue.
func ticks_left(barracks_id: int) -> int:
	var trainer: Trainer = _by_id.get(barracks_id, null)
	if trainer == null or trainer.paid.is_empty():
		return 0
	return maxi(0, _settings.training_ticks - trainer.progress)


## How many barracks stand.
func count() -> int:
	return _trainers.size()


## Why a Train of [param count] at a barracks would queue none, or "" when it would queue some.
func train_error(barracks_id: int, count := 1) -> String:
	var trainer: Trainer = _by_id.get(barracks_id, null)
	if trainer == null:
		return NOT_A_BARRACKS
	if count != 1 and count != BATCH:
		return BAD_COUNT
	if trainer.paid.size() >= QUEUE_LENGTH:
		return QUEUE_FULL
	if used() >= capacity():
		return CAPACITY_FULL
	if not _run_state.can_afford(_settings.soldier_cost):
		return NOT_ENOUGH_GOLD
	return ""


## Queues [param count] soldiers (1 or [constant BATCH]) at a barracks, as many as its queue,
## capacity and gold allow, paying for each; returns why none could be queued, or "". With
## [param instant] (the build phase) the queue trains at once.
func train(barracks_id: int, count: int, instant: bool) -> String:
	var error := train_error(barracks_id, count)
	if not error.is_empty():
		return error
	var trainer := _by_id[barracks_id]
	var cost := _settings.soldier_cost
	var fits := mini(mini(count, QUEUE_LENGTH - trainer.paid.size()), capacity() - used())
	if cost > 0:
		fits = mini(fits, _run_state.gold / cost)
	for n in fits:
		_run_state.spend(cost)
		trainer.paid.append(cost)
	_mark_changed(trainer)
	if instant:
		_finish(trainer)
	return ""


## Takes [param slot] out of a barracks' queue and refunds what it cost; returns why not, or "".
func cancel(barracks_id: int, slot: int) -> String:
	var trainer: Trainer = _by_id.get(barracks_id, null)
	if trainer == null:
		return NOT_A_BARRACKS
	if slot < 0 or slot >= trainer.paid.size():
		return NO_SUCH_SLOT
	_run_state.add_gold(trainer.paid[slot])
	trainer.paid.remove_at(slot)
	if slot == 0:
		trainer.progress = 0
	_mark_changed(trainer)
	return ""


## At [constant Simulation.Step.SPAWN_ENEMIES] during a wave, each barracks with a queue trains
## its head one tick while it is working, in build order (unpowered or under repair, its
## timer holds); a head trained for [member Settings.training_ticks] appears beside it.
func step(in_wave: bool) -> void:
	if not in_wave:
		return
	for trainer in _trainers:
		if trainer.paid.is_empty() or not _buildings.is_working(trainer.barracks_id):
			continue
		trainer.progress += 1
		if trainer.progress >= _settings.training_ticks and _release_head(trainer):
			trainer.progress = 0


## At [constant Simulation.Step.REMOVE_DEAD], a destroyed barracks' queue is refunded and its
## place in capacity goes. Its soldiers stay. Any other id is ignored.
func remove(barracks_id: int) -> void:
	var trainer: Trainer = _by_id.get(barracks_id, null)
	if trainer == null:
		return
	for paid in trainer.paid:
		_run_state.add_gold(paid)
	_trainers.erase(trainer)
	_by_id.erase(barracks_id)
	_mark_changed(trainer)


## At wave end, every barracks' queue trains at once, in build order.
func finish_queues() -> void:
	for trainer in _trainers:
		_finish(trainer)


## The barracks whose queue or head changed since the last call, each once, in order of change.
func take_changed() -> Array[int]:
	var taken := _changed
	_changed = []
	return taken


# Trains every soldier in a queue at once, head first, as long as a free cell is found.
func _finish(trainer: Trainer) -> void:
	while not trainer.paid.is_empty() and _release_head(trainer):
		pass
	trainer.progress = 0


# Puts the head on the free cell beside its barracks the new-soldier rule picks and takes it off
# the queue; false, leaving it queued, when no free cell can be reached.
func _release_head(trainer: Trainer) -> bool:
	if _soldiers.add_beside(trainer.area, 1) == 0:
		return false
	trainer.paid.remove_at(0)
	_mark_changed(trainer)
	return true


func _mark_changed(trainer: Trainer) -> void:
	if trainer.barracks_id not in _changed:
		_changed.append(trainer.barracks_id)
