class_name Combos
extends RefCounted

## Each killer's own combo on a timer: a building's or a soldier's, by the id they share. A kill
## credited to a killer adds 1 to its count, sets its tier and restarts its timer; a combo whose
## timer runs out breaks back to x1. A destroyed building's combo is removed with it, and a kill
## credited to it afterwards counts for nothing. The kill pulses, tier-ups and breaks wait in
## take_events() for the view.

enum EventKind { KILL, TIER_UP, BREAK }

var _settings: Settings
var _by_building: Dictionary[int, Combo] = {}
var _removed: Dictionary[int, bool] = {}
var _events: Array[Event] = []


## One building's combo: its count and tier, the tick its timer runs out, and its best tier
## this run.
class Combo:
	extends RefCounted

	var count := 0
	var tier := 1
	var ends_at := 0
	var best := 1


## A kill pulse, a tier-up (to [member tier]) or a break (from [member tier] and [member count]).
class Event:
	extends RefCounted

	var kind: EventKind
	var building_id: int
	var tier: int
	var count: int

	func _init(event_kind: EventKind, id: int, event_tier: int, event_count: int) -> void:
		kind = event_kind
		building_id = id
		tier = event_tier
		count = event_count


func _init(run_settings: Settings) -> void:
	_settings = run_settings


## The building's combo, read-only, or null if it has never killed (or was destroyed).
func combo(building_id: int) -> Combo:
	return _by_building.get(building_id, null)


## Counts a kill credited to the building at this tick and returns the tier it pays at: x1 for
## no building, or one destroyed.
func record(building_id: int, tick: int) -> int:
	if building_id == Enemies.NONE or _removed.has(building_id):
		return 1
	var held: Combo = _by_building.get(building_id, null)
	if held == null:
		held = Combo.new()
		_by_building[building_id] = held
	held.count += 1
	held.ends_at = tick + _settings.combo_timer_ticks
	_events.append(Event.new(EventKind.KILL, building_id, held.tier, held.count))
	var tier := tier_of(held.count)
	if tier > held.tier:
		_events.append(Event.new(EventKind.TIER_UP, building_id, tier, held.count))
	held.tier = tier
	held.best = maxi(held.best, tier)
	return tier


## Breaks every combo whose timer has run out by this tick.
func expire(tick: int) -> void:
	for id: int in _by_building:
		var held := _by_building[id]
		if held.count > 0 and tick >= held.ends_at:
			_events.append(Event.new(EventKind.BREAK, id, held.tier, held.count))
			held.count = 0
			held.tier = 1


func remove(building_id: int) -> void:
	_by_building.erase(building_id)
	_removed[building_id] = true


func take_events() -> Array[Event]:
	var taken := _events
	_events = []
	return taken


## The tier a count of kills reaches, capped.
func tier_of(count: int) -> int:
	var tier := 1
	if count >= _settings.combo_tier_3_kills:
		tier = 3
	elif count >= _settings.combo_tier_2_kills:
		tier = 2
	return mini(tier, _settings.combo_cap)


## The kills the next tier needs, or -1 at the cap.
func next_threshold(tier: int) -> int:
	if tier >= _settings.combo_cap:
		return -1
	return _settings.combo_tier_2_kills if tier <= 1 else _settings.combo_tier_3_kills


## How far a count is from its tier's start towards the next tier, 0 to 1; 1 at the cap.
func progress(count: int) -> float:
	var tier := tier_of(count)
	var next := next_threshold(tier)
	if next < 0:
		return 1.0
	var start := 0 if tier <= 1 else _settings.combo_tier_2_kills
	return clampf(float(count - start) / float(next - start), 0.0, 1.0)


## Ticks left on the building's timer at this tick; 0 with no combo running.
func ticks_left(building_id: int, tick: int) -> int:
	var held := combo(building_id)
	if held == null or held.count == 0:
		return 0
	return maxi(0, held.ends_at - tick)


## The share of the building's timer left at this tick, 0 to 1.
func timer_left(building_id: int, tick: int) -> float:
	return clampf(float(ticks_left(building_id, tick)) / _settings.combo_timer_ticks, 0.0, 1.0)
