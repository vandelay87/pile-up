class_name Main
extends Node

var simulation: Simulation:
	get:
		return _simulation

var _simulation: Simulation
var _map: MapData

@onready var _terrain: TileMapLayer = $Terrain
@onready var _base: TileMapLayer = $World/Base
@onready var _pile_layer: PileLayer = $World/Piles
@onready var _camera: MapCamera = $Camera
@onready var _world: Node2D = $World
@onready var _enemy_renderer: EnemyRenderer = $EnemyRenderer
@onready var _flow_overlay: FlowOverlay = $FlowOverlay
@onready var _debug_panel: DebugPanel = $DebugPanel
@onready var _stats_readout: StatsReadout = $StatsReadout
@onready var _hud: Hud = $Hud
@onready var _edge_highlight: EdgeHighlight = $EdgeHighlight
@onready var _tower_view: TowerView = $TowerView
@onready var _tracers: Tracers = $Tracers
@onready var _placement: Placement = $Placement
@onready var _range_overlay: RangeOverlay = $RangeOverlay
@onready var _pile_overlay: PileOverlay = $PileOverlay


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
	_map = loaded_map.map
	_draw_map(_map)
	_camera.frame(_map)
	_edge_highlight.setup(_map)
	_add_overlays()
	_hud.tower_requested.connect(_placement.enter)
	_start_run(Simulation.new(loaded.settings, _map, _new_seed()))
	print(
		(
			"Flow fields: full rebuild of both fields took %.1f ms"
			% _simulation.routing.last_rebuild_msec
		)
	)


func _physics_process(_delta: float) -> void:
	if _simulation != null:
		_simulation.run_frame()


func _start_run(simulation: Simulation) -> void:
	_simulation = simulation
	_simulation.restart_requested.connect(_restart, CONNECT_DEFERRED)
	_simulation.wave_started.connect(_edge_highlight.announce)
	_simulation.fields_changed.connect(_flow_overlay.queue_redraw)
	_pile_layer.setup(_simulation)
	_enemy_renderer.setup(_simulation, _world)
	_flow_overlay.setup(_simulation.routing, _map)
	_edge_highlight.clear()
	_debug_panel.setup(_simulation)
	_stats_readout.setup(_simulation)
	_hud.setup(_simulation)
	_tower_view.setup(_simulation, _world)
	_tracers.setup(_simulation, _enemy_renderer)
	_placement.setup(_simulation)
	_range_overlay.setup(_simulation)
	_pile_overlay.setup(_simulation)


func _restart() -> void:
	_start_run(_simulation.next_run(_new_seed()))


func _new_seed() -> int:
	var run_seed := randi()
	print("Run seed: %d" % run_seed)
	return run_seed


func _add_overlays() -> void:
	for route: Routing.Route in Routing.Route.values():
		var key: String = Routing.Route.find_key(route)
		var route_name := key.capitalize()
		_debug_panel.add_overlay(
			"Flow arrows: %s" % route_name, _flow_overlay.show_arrows.bind(route)
		)
		_debug_panel.add_overlay(
			"Field heatmap: %s" % route_name, _flow_overlay.show_heatmap.bind(route)
		)
	_debug_panel.add_overlay("Pile labels", _pile_overlay.show_labels)
	_debug_panel.add_overlay("Enemy route tint", _enemy_renderer.show_route_tint)
	_debug_panel.add_overlay("Tower range circles", _range_overlay.show_ranges)


func _draw_map(map: MapData) -> void:
	var tile_set := Atlas.make_tile_set()
	_terrain.tile_set = tile_set
	_base.tile_set = tile_set
	_pile_layer.tile_set = tile_set
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
