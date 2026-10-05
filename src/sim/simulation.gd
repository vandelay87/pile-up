class_name Simulation
extends RefCounted

signal command_rejected(reason: String)

enum Step {
	DRAIN_COMMANDS,
	LAND_BODIES_AND_UPDATE_FIELDS,
	SPAWN_ENEMIES,
	REBUILD_SPATIAL_HASH,
	MOVE_ENEMIES,
	FIRE_TOWERS,
	REMOVE_DEAD_AND_LEAKED,
	CHECK_WAVE_END,
}

const TICKS_PER_SECOND := 60

var settings: Settings
var step_observer := Callable()

var _command_queue: Array[Commands.Command] = []
var _rejections: Array[String] = []


func _init(run_settings: Settings) -> void:
	settings = run_settings


func queue_command(command: Commands.Command) -> void:
	_command_queue.append(command)


func reject_command(reason: String) -> void:
	_rejections.append(reason)


func tick() -> void:
	_drain_commands()
	_land_bodies_and_update_fields()
	_spawn_enemies()
	_rebuild_spatial_hash()
	_move_enemies()
	_fire_towers()
	_remove_dead_and_leaked()
	_check_wave_end()
	_emit_signals()


func _emit_signals() -> void:
	var rejections := _rejections
	_rejections = []
	for reason in rejections:
		command_rejected.emit(reason)


func _drain_commands() -> void:
	_observe(Step.DRAIN_COMMANDS)
	var commands := _command_queue
	_command_queue = []
	for command in commands:
		command.apply(self)


func _land_bodies_and_update_fields() -> void:
	_observe(Step.LAND_BODIES_AND_UPDATE_FIELDS)


func _spawn_enemies() -> void:
	_observe(Step.SPAWN_ENEMIES)


func _rebuild_spatial_hash() -> void:
	_observe(Step.REBUILD_SPATIAL_HASH)


func _move_enemies() -> void:
	_observe(Step.MOVE_ENEMIES)


func _fire_towers() -> void:
	_observe(Step.FIRE_TOWERS)


func _remove_dead_and_leaked() -> void:
	_observe(Step.REMOVE_DEAD_AND_LEAKED)


func _check_wave_end() -> void:
	_observe(Step.CHECK_WAVE_END)


func _observe(step: Step) -> void:
	if step_observer.is_valid():
		step_observer.call(step)
