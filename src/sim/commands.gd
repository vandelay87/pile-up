class_name Commands
extends RefCounted


class Command:
	extends RefCounted

	func apply(_sim: Simulation) -> void:
		pass


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


class SpawnBurst:
	extends Commands.Command

	var _count: int

	func _init(count: int) -> void:
		_count = count

	func apply(sim: Simulation) -> void:
		sim.spawn_burst(_count)


class SetPaused:
	extends Commands.Command

	var _paused: bool

	func _init(paused: bool) -> void:
		_paused = paused

	func apply(sim: Simulation) -> void:
		sim.set_paused(_paused)


class SetSpeed:
	extends Commands.Command

	var _speed: int

	func _init(speed: int) -> void:
		_speed = speed

	func apply(sim: Simulation) -> void:
		sim.set_speed(_speed)


class Step:
	extends Commands.Command

	func apply(sim: Simulation) -> void:
		sim.step()


class AddGold:
	extends Commands.Command

	var _amount: int

	func _init(amount: int) -> void:
		_amount = amount

	func apply(sim: Simulation) -> void:
		sim.add_gold(_amount)


class JumpToWave:
	extends Commands.Command

	var _wave: int

	func _init(wave: int) -> void:
		_wave = wave

	func apply(sim: Simulation) -> void:
		sim.jump_to_wave(_wave)
