class_name Simulation
extends RefCounted

signal command_rejected(reason: String)
signal pile_changed(cells: Array[Vector2i])
signal fields_changed
signal gold_changed(gold: int)
signal base_hp_changed(hp: float)
signal kills_changed(kills: int)
signal enemies_left_changed(left: int)
signal combo_changed(tier: int)
signal payout(amount: int, tier: int)
signal building_placed(id: int)
signal shots_fired(shots: Array[Buildings.Shot])
signal phase_changed(phase: Waves.Phase)
signal wave_started(edges: PackedStringArray)
signal game_over
signal restart_requested

enum Step {
	DRAIN_COMMANDS,
	LAND_BODIES_AND_UPDATE_FIELDS,
	SPAWN_ENEMIES,
	REBUILD_SPATIAL_HASH,
	MOVE_ENEMIES,
	FIRE_TOWERS,
	REMOVE_DEAD,
	CHECK_WAVE_END,
}

const TICKS_PER_SECOND := 60
const SPEEDS: Array[int] = [1, 2, 4]
const DECAY_REBUILD_TICKS := 12

var settings: Settings
var map: MapData
var occupancy: Occupancy
var piles: Piles
var routing: Routing
var enemies: Enemies
var waves: Waves
var buildings: Buildings
var run_state: RunState
var structures: Structures
var step_observer := Callable()
var tick_count := 0
var paused := false
var speed := 1
var tick_cost := TickCost.new()
var combo_tier: int:
	get:
		return run_state.combo_tier
var enemies_left: int:
	get:
		return waves.enemies_left

var _command_queue: Array[Commands.Command] = []
var _rejections: Array[String] = []
var _fields_changed := false
var _changed_cells: Array[Vector2i] = []
var _decay_due := false
var _rebuild_swap_tick := 0
var _placed: Array[int] = []
var _shots: Array[Buildings.Shot] = []
var _run_seed: int
var _pending_steps := 0
var _wave_started := false
var _restart_requested := false
var _reported_gold: int
var _reported_base_hp: float
var _reported_kills := 0
var _reported_combo_tier := 1
var _multiplied_payout := false
var _reported_enemies_left: int
var _wave_ended := false
var _reported_phase := Waves.Phase.BUILD
var _reported_game_over := false


func _init(run_settings: Settings, run_map: MapData, run_seed: int = 0) -> void:
	settings = run_settings
	map = run_map
	_run_seed = run_seed
	occupancy = Occupancy.new(map.width, map.height)
	piles = Piles.new(settings, map, occupancy, _system_rng("piles"))
	routing = Routing.new(settings, map, occupancy, piles)
	run_state = RunState.new(settings)
	structures = Structures.new(map, piles, run_state)
	enemies = (
		Enemies
		. new(
			settings,
			map,
			occupancy,
			piles,
			routing,
			structures,
			_system_rng("enemies"),
			_system_rng("swarm"),
		)
	)
	waves = Waves.new(settings, map, enemies, _system_rng("waves"))
	buildings = Buildings.new(settings, map, occupancy, piles, routing, enemies, run_state)
	_reported_gold = run_state.gold
	_reported_base_hp = run_state.base_hp
	_reported_enemies_left = waves.enemies_left


func queue_command(command: Commands.Command) -> void:
	_command_queue.append(command)


func reject_command(reason: String) -> void:
	_rejections.append(reason)


func change_setting(group: String, key: String, new_value: Variant) -> void:
	var error := settings.change(group, key, new_value)
	if not error.is_empty():
		reject_command(error)
		return
	var costs_walls := group == "enemies" and key in ["speed", "wall_damage"]
	if (group in ["routing", "piles"] or costs_walls) and routing.rebuild():
		_fields_changed = true


func next_wave() -> void:
	_start_wave(run_state.wave + 1, Commands.NextWave.LABEL)


func jump_to_wave(wave: int) -> void:
	if wave < 1:
		reject_command("%s: the wave must be at least 1" % Commands.JumpToWave.LABEL)
		return
	_start_wave(wave, Commands.JumpToWave.LABEL)


func decay_piles() -> void:
	_decay_due = true


func is_decay_rebuild_in_flight() -> bool:
	return _decay_due or routing.is_rebuilding()


func build(kind: StringName, origin: Vector2i) -> void:
	var error := buildings.build(kind, origin)
	if not error.is_empty():
		reject_command("%s: %s" % [Commands.Build.label_for(kind), error])
		return
	var placed := buildings.built[buildings.built.size() - 1]
	_placed.append(placed.id)
	_changed_cells.append_array(placed.footprint)


func add_gold(amount: int) -> void:
	run_state.add_gold(amount)


func request_restart() -> void:
	_restart_requested = true


func next_run(new_seed: int) -> Simulation:
	return Simulation.new(settings.for_next_run(), map, new_seed)


func set_paused(value: bool) -> void:
	paused = value
	_pending_steps = 0


func set_speed(value: int) -> void:
	if value not in SPEEDS:
		reject_command("speed: expected one of %s, got %d" % [SPEEDS, value])
		return
	speed = value


func step_one_tick() -> void:
	if paused:
		_pending_steps += 1


func run_frame() -> void:
	if paused:
		_drain_time_controls()
		_emit_signals()
	var was_paused := paused
	var ticks := _pending_steps if was_paused else speed
	_pending_steps = 0
	for n in ticks:
		var started := Time.get_ticks_usec()
		tick()
		tick_cost.record((Time.get_ticks_usec() - started) / 1000.0, Time.get_ticks_msec())
		if paused and not was_paused:
			break


func tick() -> void:
	_drain_commands()
	if run_state.is_game_over:
		tick_count += 1
		_emit_signals()
		return
	_land_bodies_and_update_fields()
	_spawn_enemies()
	_rebuild_spatial_hash()
	_move_enemies()
	_fire_towers()
	_remove_dead()
	_check_wave_end()
	tick_count += 1
	_emit_signals()


func _emit_signals() -> void:
	if run_state.gold != _reported_gold:
		_reported_gold = run_state.gold
		gold_changed.emit(_reported_gold)
	if run_state.base_hp != _reported_base_hp:
		_reported_base_hp = run_state.base_hp
		base_hp_changed.emit(_reported_base_hp)
	if run_state.kills != _reported_kills:
		_reported_kills = run_state.kills
		kills_changed.emit(_reported_kills)
	_emit_enemies_left()
	if run_state.combo_tier != _reported_combo_tier:
		_reported_combo_tier = run_state.combo_tier
		combo_changed.emit(_reported_combo_tier)
	if _multiplied_payout:
		_multiplied_payout = false
		payout.emit(run_state.payout, run_state.payout_tier)
	var placed := _placed
	_placed = []
	for id in placed:
		building_placed.emit(id)
	if not piles.changed.is_empty():
		pile_changed.emit(piles.take_changes())
	if not _shots.is_empty():
		var shots := _shots
		_shots = []
		shots_fired.emit(shots)
	if waves.phase != _reported_phase:
		_reported_phase = waves.phase
		phase_changed.emit(_reported_phase)
	if _wave_started:
		_wave_started = false
		wave_started.emit(waves.edges)
	if _fields_changed:
		_fields_changed = false
		fields_changed.emit()
	var rejections := _rejections
	_rejections = []
	for reason in rejections:
		command_rejected.emit(reason)
	if run_state.is_game_over and not _reported_game_over:
		_reported_game_over = true
		game_over.emit()
	if _restart_requested:
		_restart_requested = false
		restart_requested.emit()


# Enemies left reaches 0 as a wave ends, then shows the next wave's size: both are reported.
func _emit_enemies_left() -> void:
	if _wave_ended:
		_wave_ended = false
		if _reported_enemies_left != 0:
			_reported_enemies_left = 0
			enemies_left_changed.emit(0)
	if waves.enemies_left != _reported_enemies_left:
		_reported_enemies_left = waves.enemies_left
		enemies_left_changed.emit(_reported_enemies_left)


func _drain_commands() -> void:
	_observe(Step.DRAIN_COMMANDS)
	var commands := _command_queue
	_command_queue = []
	for command in commands:
		if run_state.is_game_over and command is Commands.Play:
			var play := command as Commands.Play
			reject_command("%s: the run is over" % play.label())
		else:
			command.apply(self)


func _drain_time_controls() -> void:
	var commands := _command_queue
	_command_queue = []
	for command in commands:
		if command is Commands.TimeControl or command is Commands.Restart:
			command.apply(self)
		else:
			_command_queue.append(command)


func _land_bodies_and_update_fields() -> void:
	_observe(Step.LAND_BODIES_AND_UPDATE_FIELDS)
	piles.land()
	_changed_cells.append_array(piles.take_field_changes())
	if _decay_due:
		_decay_due = false
		_changed_cells.clear()
		piles.decay()
		routing.start_rebuild()
		_rebuild_swap_tick = tick_count + DECAY_REBUILD_TICKS
	elif routing.is_rebuilding() and tick_count >= _rebuild_swap_tick:
		if routing.finish_rebuild():
			_fields_changed = true
		else:
			_rebuild_swap_tick = tick_count + DECAY_REBUILD_TICKS
	if not _changed_cells.is_empty():
		var cells := _changed_cells
		_changed_cells = []
		if routing.update(cells):
			_fields_changed = true


func _spawn_enemies() -> void:
	_observe(Step.SPAWN_ENEMIES)
	waves.spawn()


func _rebuild_spatial_hash() -> void:
	_observe(Step.REBUILD_SPATIAL_HASH)
	enemies.rebuild_spatial_hash()


func _move_enemies() -> void:
	_observe(Step.MOVE_ENEMIES)
	enemies.move(waves.in_wave_tail())


func _fire_towers() -> void:
	_observe(Step.FIRE_TOWERS)
	_shots = buildings.fire()


func _remove_dead() -> void:
	_observe(Step.REMOVE_DEAD)
	var deaths := enemies.remove_dead()
	piles.queue_bodies(deaths)
	run_state.record_kills(deaths.size(), tick_count)
	_multiplied_payout = run_state.payout_tier > 1
	waves.record_kills(deaths.size())


func _check_wave_end() -> void:
	_observe(Step.CHECK_WAVE_END)
	if not run_state.is_game_over and waves.check_end():
		_wave_ended = true
		decay_piles()


func _start_wave(wave: int, label: String) -> void:
	if waves.phase == Waves.Phase.WAVE:
		reject_command("%s: a wave is already running" % label)
		return
	if map.spawn_edges.is_empty():
		reject_command("%s: the map has no spawn edges" % label)
		return
	if is_decay_rebuild_in_flight():
		reject_command("%s: the fields are still rebuilding after decay" % label)
		return
	run_state.wave = wave
	waves.start(wave)
	_wave_started = true


func _system_rng(system: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([_run_seed, system])
	return rng


func _observe(step: Step) -> void:
	if step_observer.is_valid():
		step_observer.call(step)
