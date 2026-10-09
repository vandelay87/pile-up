class_name Simulation
extends RefCounted

signal command_rejected(reason: String)
signal fields_changed

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
const SPEEDS: Array[int] = [1, 2, 4]

var settings: Settings
var map: MapData
var occupancy: Occupancy
var routing: Routing
var enemies: Enemies
var step_observer := Callable()
var tick_count := 0
var paused := false
var speed := 1
var tick_cost := TickCost.new()

var _command_queue: Array[Commands.Command] = []
var _rejections: Array[String] = []
var _fields_changed := false
var _run_seed: int
var _debug_rng: RandomNumberGenerator
var _pending_steps := 0


func _init(run_settings: Settings, run_map: MapData, run_seed: int = 0) -> void:
	settings = run_settings
	map = run_map
	_run_seed = run_seed
	occupancy = Occupancy.new(map.width, map.height)
	routing = Routing.new(settings, map, occupancy)
	enemies = Enemies.new(settings, map, occupancy, routing, _system_rng("enemies"))
	_debug_rng = _system_rng("debug")


func queue_command(command: Commands.Command) -> void:
	_command_queue.append(command)


func reject_command(reason: String) -> void:
	_rejections.append(reason)


func change_setting(group: String, key: String, new_value: Variant) -> void:
	var error := settings.change(group, key, new_value)
	if not error.is_empty():
		reject_command(error)
		return
	if group == "routing":
		routing.rebuild()
		_fields_changed = true


func spawn_burst(count: int) -> void:
	var edges := map.spawn_edges
	for n in count:
		var cells := map.spawn_cells(edges[n % edges.size()])
		var cell := cells[_debug_rng.randi_range(0, cells.size() - 1)]
		var jitter := Vector2(
			_debug_rng.randf_range(-0.25, 0.25), _debug_rng.randf_range(-0.25, 0.25)
		)
		enemies.spawn(Vector2(cell) + Vector2(0.5, 0.5) + jitter)


func add_gold(_amount: int) -> void:
	reject_command("add gold: needs waves and run state")


func jump_to_wave(_wave: int) -> void:
	reject_command("jump to wave: needs waves and run state")


func set_paused(value: bool) -> void:
	paused = value


func set_speed(value: int) -> void:
	if value not in SPEEDS:
		reject_command("speed: expected one of %s, got %d" % [SPEEDS, value])
		return
	speed = value


func step() -> void:
	_pending_steps += 1


func run_frame() -> void:
	if paused:
		_drain_commands()
		_emit_signals()
	var stepping := paused
	var ticks := _pending_steps if stepping else speed
	_pending_steps = 0
	for n in ticks:
		var started := Time.get_ticks_usec()
		tick()
		tick_cost.record((Time.get_ticks_usec() - started) / 1000.0, Time.get_ticks_msec())
		if paused and not stepping:
			break


func tick() -> void:
	_drain_commands()
	_land_bodies_and_update_fields()
	_spawn_enemies()
	_rebuild_spatial_hash()
	_move_enemies()
	_fire_towers()
	_remove_dead_and_leaked()
	_check_wave_end()
	tick_count += 1
	_emit_signals()


func _emit_signals() -> void:
	if _fields_changed:
		_fields_changed = false
		fields_changed.emit()
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
	enemies.rebuild_spatial_hash()


func _move_enemies() -> void:
	_observe(Step.MOVE_ENEMIES)
	enemies.move()


func _fire_towers() -> void:
	_observe(Step.FIRE_TOWERS)


func _remove_dead_and_leaked() -> void:
	_observe(Step.REMOVE_DEAD_AND_LEAKED)
	enemies.remove_dead_and_leaked()


func _check_wave_end() -> void:
	_observe(Step.CHECK_WAVE_END)


func _system_rng(system: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([_run_seed, system])
	return rng


func _observe(step: Step) -> void:
	if step_observer.is_valid():
		step_observer.call(step)
