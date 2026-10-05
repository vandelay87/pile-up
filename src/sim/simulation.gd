class_name Simulation
extends RefCounted

var step_observer := Callable()

var _command_queue: Array[Commands.Command] = []


func queue_command(command: Commands.Command) -> void:
	_command_queue.append(command)


func tick() -> void:
	_observe(0)
	_drain_commands()
	_observe(1)
	_land_bodies_and_update_fields()
	_observe(2)
	_spawn_enemies()
	_observe(3)
	_rebuild_spatial_hash()
	_observe(4)
	_move_enemies()
	_observe(5)
	_fire_towers()
	_observe(6)
	_remove_dead_and_leaked()
	_observe(7)
	_check_wave_end()


func _drain_commands() -> void:
	var commands := _command_queue
	_command_queue = []
	for command in commands:
		command.apply(self)


func _land_bodies_and_update_fields() -> void:
	pass


func _spawn_enemies() -> void:
	pass


func _rebuild_spatial_hash() -> void:
	pass


func _move_enemies() -> void:
	pass


func _fire_towers() -> void:
	pass


func _remove_dead_and_leaked() -> void:
	pass


func _check_wave_end() -> void:
	pass


func _observe(step: int) -> void:
	if step_observer.is_valid():
		step_observer.call(step)
