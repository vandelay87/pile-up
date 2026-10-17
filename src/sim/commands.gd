class_name Commands
extends RefCounted


class Command:
	extends RefCounted

	func apply(_sim: Simulation) -> void:
		pass


class TimeControl:
	extends Commands.Command


class Play:
	extends Commands.Command

	func label() -> String:
		return ""


class NextWave:
	extends Commands.Play

	const LABEL := "next wave"

	func label() -> String:
		return LABEL

	func apply(sim: Simulation) -> void:
		sim.next_wave()


class Build:
	extends Commands.Play

	var _kind: StringName
	var _origin: Vector2i

	func _init(kind: StringName, origin: Vector2i) -> void:
		_kind = kind
		_origin = origin

	static func label_for(kind: StringName) -> String:
		return "build %s" % String(kind).replace("_", " ")

	func label() -> String:
		return label_for(_kind)

	func apply(sim: Simulation) -> void:
		sim.build(_kind, _origin)


class Assign:
	extends Commands.Play

	const LABEL := "assign"

	var _yard_id: int
	var _building_id: int

	func _init(yard_id: int, building_id: int) -> void:
		_yard_id = yard_id
		_building_id = building_id

	func label() -> String:
		return LABEL

	func apply(sim: Simulation) -> void:
		sim.assign(_yard_id, _building_id)


class ClearAssignment:
	extends Commands.Play

	const LABEL := "clear assignment"

	var _yard_id: int

	func _init(yard_id: int) -> void:
		_yard_id = yard_id

	func label() -> String:
		return LABEL

	func apply(sim: Simulation) -> void:
		sim.clear_assignment(_yard_id)


class SetRepairThreshold:
	extends Commands.Play

	const LABEL := "repair threshold"

	var _yard_id: int
	var _percent: int

	func _init(yard_id: int, percent: int) -> void:
		_yard_id = yard_id
		_percent = percent

	func label() -> String:
		return LABEL

	func apply(sim: Simulation) -> void:
		sim.set_repair_threshold(_yard_id, _percent)


class SetTargeting:
	extends Commands.Play

	const LABEL := "targeting"

	var _tower_id: int
	var _mode: StringName

	func _init(tower_id: int, mode: StringName) -> void:
		_tower_id = tower_id
		_mode = mode

	func label() -> String:
		return LABEL

	# Straight to Buildings: Simulation is at gdlint's limit of public methods.
	func apply(sim: Simulation) -> void:
		var error := sim.buildings.set_targeting(_tower_id, _mode)
		if not error.is_empty():
			sim.reject_command("%s: %s" % [LABEL, error])


class SetSoldierTargeting:
	extends Commands.Play

	const LABEL := "soldier targeting"

	var _soldier_ids: PackedInt32Array
	var _mode: StringName

	func _init(soldier_ids: PackedInt32Array, mode: StringName) -> void:
		_soldier_ids = soldier_ids
		_mode = mode

	func label() -> String:
		return LABEL

	# Straight to Soldiers: Simulation is at gdlint's limit of public methods.
	func apply(sim: Simulation) -> void:
		var error := sim.soldiers.set_targeting(_soldier_ids, _mode)
		if not error.is_empty():
			sim.reject_command("%s: %s" % [LABEL, error])


class Train:
	extends Commands.Play

	const LABEL := "train"

	var _barracks_id: int
	var _count: int

	func _init(barracks_id: int, count: int) -> void:
		_barracks_id = barracks_id
		_count = count

	func label() -> String:
		return LABEL

	# Straight to Barracks: Simulation is at gdlint's limit of public methods.
	func apply(sim: Simulation) -> void:
		var instant := sim.waves.phase != Waves.Phase.WAVE
		var error := sim.barracks.train(_barracks_id, _count, instant)
		if not error.is_empty():
			sim.reject_command("%s: %s" % [LABEL, error])


class CancelTraining:
	extends Commands.Play

	const LABEL := "cancel training"

	var _barracks_id: int
	var _slot: int

	func _init(barracks_id: int, slot: int) -> void:
		_barracks_id = barracks_id
		_slot = slot

	func label() -> String:
		return LABEL

	# Straight to Barracks: Simulation is at gdlint's limit of public methods.
	func apply(sim: Simulation) -> void:
		var error := sim.barracks.cancel(_barracks_id, _slot)
		if not error.is_empty():
			sim.reject_command("%s: %s" % [LABEL, error])


## Sets where a barracks sends the soldiers it trains.
class SetRallyPoint:
	extends Commands.Play

	const LABEL := "rally point"

	var _barracks_id: int
	var _cell: Vector2i

	func _init(barracks_id: int, cell: Vector2i) -> void:
		_barracks_id = barracks_id
		_cell = cell

	func label() -> String:
		return LABEL

	# Straight to Barracks: Simulation is at gdlint's limit of public methods.
	func apply(sim: Simulation) -> void:
		var error := sim.barracks.set_rally(_barracks_id, _cell)
		if not error.is_empty():
			sim.reject_command("%s: %s" % [LABEL, error])


## New soldiers from a barracks stand where they appear again.
class ClearRallyPoint:
	extends Commands.Play

	const LABEL := "clear rally point"

	var _barracks_id: int

	func _init(barracks_id: int) -> void:
		_barracks_id = barracks_id

	func label() -> String:
		return LABEL

	# Straight to Barracks: Simulation is at gdlint's limit of public methods.
	func apply(sim: Simulation) -> void:
		var error := sim.barracks.clear_rally(_barracks_id)
		if not error.is_empty():
			sim.reject_command("%s: %s" % [LABEL, error])


## Sends soldiers to a map position in a formation, read from the command card when the order
## is given so replays are exact.
class Move:
	extends Commands.Play

	const LABEL := "move"

	var _soldier_ids: PackedInt32Array
	var _target: Vector2
	var _formation: StringName

	func _init(soldier_ids: PackedInt32Array, target: Vector2, formation: StringName) -> void:
		_soldier_ids = soldier_ids
		_target = target
		_formation = formation

	func label() -> String:
		return LABEL

	# Straight to Soldiers: Simulation is at gdlint's limit of public methods.
	func apply(sim: Simulation) -> void:
		var error := sim.soldiers.move(_soldier_ids, _target, _formation)
		if not error.is_empty():
			sim.reject_command("%s: %s" % [LABEL, error])


## Ends soldiers' orders: each stands where it is.
class Stop:
	extends Commands.Play

	const LABEL := "stop"

	var _soldier_ids: PackedInt32Array

	func _init(soldier_ids: PackedInt32Array) -> void:
		_soldier_ids = soldier_ids

	func label() -> String:
		return LABEL

	# Straight to Soldiers: Simulation is at gdlint's limit of public methods.
	func apply(sim: Simulation) -> void:
		sim.soldiers.stop(_soldier_ids)


class Restart:
	extends Commands.Command

	func apply(sim: Simulation) -> void:
		sim.request_restart()


class SetSetting:
	extends Commands.Command

	var _group: String
	var _key: String
	var _value: Variant

	func _init(group: String, key: String, value: Variant) -> void:
		_group = group
		_key = key
		_value = value

	func apply(sim: Simulation) -> void:
		sim.change_setting(_group, _key, _value)


class SetPaused:
	extends Commands.TimeControl

	var _paused: bool

	func _init(paused: bool) -> void:
		_paused = paused

	func apply(sim: Simulation) -> void:
		sim.set_paused(_paused)


class SetSpeed:
	extends Commands.TimeControl

	var _speed: int

	func _init(speed: int) -> void:
		_speed = speed

	func apply(sim: Simulation) -> void:
		sim.set_speed(_speed)


class StepOneTick:
	extends Commands.TimeControl

	func apply(sim: Simulation) -> void:
		sim.step_one_tick()


class AddGold:
	extends Commands.Play

	var _amount: int

	func _init(amount: int) -> void:
		_amount = amount

	func label() -> String:
		return "add gold"

	func apply(sim: Simulation) -> void:
		sim.add_gold(_amount)


class JumpToWave:
	extends Commands.Play

	const LABEL := "jump to wave"

	var _wave: int

	func _init(wave: int) -> void:
		_wave = wave

	func label() -> String:
		return LABEL

	func apply(sim: Simulation) -> void:
		sim.jump_to_wave(_wave)


class KillEnemies:
	extends Commands.Play

	const LABEL := "kill enemies"

	var _count: int

	func _init(count: int) -> void:
		_count = count

	func label() -> String:
		return LABEL

	func apply(sim: Simulation) -> void:
		sim.kill_enemies(_count)


## Debug: soldiers beside the base for free, placed one by one by the new-soldier rule.
class AddSoldiers:
	extends Commands.Play

	const LABEL := "add soldiers"

	var _count: int

	func _init(count: int) -> void:
		_count = count

	func label() -> String:
		return LABEL

	# Straight to Soldiers: Simulation is at gdlint's limit of public methods.
	func apply(sim: Simulation) -> void:
		if _count < 1:
			sim.reject_command("%s: the count must be at least 1" % LABEL)
			return
		if sim.soldiers.add_beside(sim.map.base, _count) < _count:
			sim.reject_command("%s: no free cell beside the base" % LABEL)
