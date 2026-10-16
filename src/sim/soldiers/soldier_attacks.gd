class_name SoldierAttacks
extends RefCounted

## Enemies attacking soldiers, at [constant Simulation.Step.MOVE_UNITS] once soldiers have moved.
## An enemy pressed against a soldier (centres within two body radii plus the wall reach) and
## jammed there, by the structure rule (no progress along its route for
## [member Settings.jam_ticks]), takes that soldier as its soldier target, unless it is tumbling or
## attacking a structure already, or the soldier stands on a wall. A bloater lights its fuse there
## instead of attacking. Each attack deals the structure damage a tick, and ends when the soldier
## dies, leaves reach or climbs onto a wall. Enemies never leave their route for a soldier.

var _settings: Settings
var _routing: Routing
var _enemies: Enemies
var _soldiers: Soldiers
# The ids of the enemies given a soldier target, some since cleared or dead.
var _attackers := PackedInt32Array()
# The jam counter of each enemy pressed against a soldier on the last pass, by enemy id.
var _jams: Dictionary[int, Jam] = {}
var _passes := 0


## An enemy's jam against soldiers: its best field value while pressed, the passes without
## progress since, and the pass it was last pressed on.
class Jam:
	extends RefCounted

	var best_value := INF
	var stuck := 0
	var pressed_at := 0


func _init(
	run_settings: Settings, run_routing: Routing, run_enemies: Enemies, run_soldiers: Soldiers
) -> void:
	_settings = run_settings
	_routing = run_routing
	_enemies = run_enemies
	_soldiers = run_soldiers


## At [constant Simulation.Step.MOVE_UNITS], after [method Soldiers.step]: attacks that no longer
## hold end, enemies newly jammed against soldiers start theirs, then every attack lands.
func step() -> void:
	_passes += 1
	var reach := 2.0 * _settings.separation_radius + _settings.wall_reach
	_end_lapsed(reach)
	_press(reach)
	var damage := _settings.structure_damage_per_tick
	for e in _attacking():
		if _enemies.kinds[e] != Enemies.Kind.BLOATER:
			_soldiers.damage(_enemies.soldier_targets[e], damage)


## At [constant Simulation.Step.REMOVE_DEAD], every enemy attacking one of the soldiers that
## died, [param dead], stops.
func end_on(dead: PackedInt32Array) -> void:
	for e in _attacking():
		if _enemies.soldier_targets[e] in dead:
			_enemies.soldier_targets[e] = Enemies.NONE


func _end_lapsed(reach: float) -> void:
	for e in _attacking():
		var i := _soldiers.index_of(_enemies.soldier_targets[e])
		if (
			i == Soldiers.NONE
			or not _can_be_attacked(i)
			or _enemies.positions[e].distance_to(_soldiers.positions[i]) > reach
		):
			_enemies.soldier_targets[e] = Enemies.NONE


# Every enemy pressed against a soldier that can be attacked counts towards its jam, once a pass
# however many soldiers it is pressed against; a jam not pressed on this pass is dropped.
func _press(reach: float) -> void:
	var jam_ticks := _settings.jam_ticks
	for i in _soldiers.count:
		if not _can_be_attacked(i):
			continue
		for e in _enemies.living_within(_soldiers.positions[i], reach):
			if (
				_enemies.tumbling[e] == 1
				or _enemies.structure_targets[e] != Enemies.NONE
				or _enemies.soldier_targets[e] != Enemies.NONE
			):
				continue
			var id := _enemies.ids[e]
			var jam: Jam = _jams.get(id)
			if jam != null and jam.pressed_at == _passes:
				continue
			var route := _enemies.routes[e] as Routing.Route
			var field_value := _routing.sample_value(route, _enemies.positions[e])
			if jam == null or jam.pressed_at != _passes - 1:
				jam = Jam.new()
				_jams[id] = jam
			if field_value < jam.best_value - Enemies.PROGRESS:
				jam.best_value = field_value
				jam.stuck = 0
			else:
				jam.stuck += 1
			jam.pressed_at = _passes
			if jam.stuck >= jam_ticks:
				_start(e, _soldiers.ids[i])
	for id: int in _jams.keys():
		if _jams[id].pressed_at != _passes:
			_jams.erase(id)


func _start(e: int, soldier_id: int) -> void:
	_enemies.soldier_targets[e] = soldier_id
	_attackers.append(_enemies.ids[e])
	_jams.erase(_enemies.ids[e])
	if _enemies.kinds[e] == Enemies.Kind.BLOATER and _enemies.fuses[e] == 0:
		_enemies.fuses[e] = _settings.fuse_ticks


# The indices of the living enemies with a soldier target, in the order they took it.
func _attacking() -> PackedInt32Array:
	var kept := PackedInt32Array()
	var indices := PackedInt32Array()
	for id in _attackers:
		var e := _enemies.index_of(id)
		if (
			e != Enemies.NONE
			and _enemies.is_alive(e)
			and _enemies.soldier_targets[e] != Enemies.NONE
		):
			kept.append(id)
			indices.append(e)
	_attackers = kept
	return indices


# Living and off a wall: an enemy jammed against a wall is held up by the wall.
func _can_be_attacked(i: int) -> bool:
	return _soldiers.hp[i] > 0.0 and _soldiers.elevation(i) != Piles.WALL_LEVEL
