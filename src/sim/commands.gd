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
