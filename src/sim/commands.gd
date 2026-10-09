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
