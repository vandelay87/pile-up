class_name Main
extends Node

const DEBUG_BURST_SIZE := 300

var simulation: Simulation:
	get:
		return _simulation

var _simulation: Simulation

@onready var _terrain: TileMapLayer = $Terrain
@onready var _base: TileMapLayer = $World/Base
@onready var _camera: MapCamera = $Camera
@onready var _world: Node2D = $World
@onready var _enemy_renderer: EnemyRenderer = $EnemyRenderer


func _ready() -> void:
	Engine.physics_ticks_per_second = Simulation.TICKS_PER_SECOND
	var loaded := Settings.load_file(Settings.DEFAULTS_PATH)
	if loaded.settings == null:
		_fail("invalid settings", loaded.error)
		return
	var loaded_map := MapData.load_file(loaded.settings.map_path)
	if loaded_map.map == null:
		_fail("invalid map", loaded_map.error)
		return
	var run_seed := randi()
	_simulation = Simulation.new(loaded.settings, loaded_map.map, run_seed)
	print("Run seed: %d" % run_seed)
	print(
		(
			"Flow fields: full rebuild of both fields took %.1f ms"
			% _simulation.routing.last_rebuild_msec
		)
	)
	_draw_map(loaded_map.map)
	_camera.frame(loaded_map.map)
	_enemy_renderer.setup(_simulation.enemies, _world)


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if _simulation != null and key.pressed and not key.echo and key.keycode == KEY_B:
		_simulation.queue_command(Commands.SpawnBurst.new(DEBUG_BURST_SIZE))


func _physics_process(_delta: float) -> void:
	if _simulation != null:
		_simulation.tick()


func _draw_map(map: MapData) -> void:
	var tile_set := Atlas.make_tile_set()
	_terrain.tile_set = tile_set
	_base.tile_set = tile_set
	for y in map.height:
		for x in map.width:
			var cell := Vector2i(x, y)
			_terrain.set_cell(
				cell, Atlas.SOURCE_ID, Atlas.ROCK if map.is_rock(cell) else Atlas.CLEAR
			)
	for cell in map.base_cells():
		_base.set_cell(cell, Atlas.SOURCE_ID, Atlas.BASE)


func _fail(title: String, error: String) -> void:
	push_error(error)
	OS.alert(error, "pile-up: %s" % title)
	get_tree().quit(1)
