class_name DroneView
extends Node2D

## Draws every repair yard's drone each frame from RepairYards, above the y-sorted world: parked
## on its yard's pad at home, higher up in flight. A building a drone is repairing shows a steady
## repair effect over it.

const PARKED_HEIGHT := 16.0
const FLIGHT_HEIGHT := 44.0
const EFFECT_HEIGHT := 36.0

var _simulation: Simulation
var _texture: Texture2D


func setup(simulation: Simulation) -> void:
	_simulation = simulation
	_texture = load(Atlas.PATH)
	queue_redraw()


func _process(_delta: float) -> void:
	if _simulation != null:
		queue_redraw()


func _draw() -> void:
	if _simulation == null:
		return
	var repairing: Dictionary[int, bool] = {}
	for drone in _simulation.repair_yards.drones:
		if drone.state == RepairYards.State.REPAIRING:
			repairing[drone.target_id] = true
	for id in repairing:
		var building := _simulation.buildings.building(id)
		if building != null:
			_draw_region(Atlas.REPAIR_EFFECT_REGION, building.centre, EFFECT_HEIGHT)
	for drone in _simulation.repair_yards.drones:
		var height := PARKED_HEIGHT if drone.state == RepairYards.State.HOME else FLIGHT_HEIGHT
		_draw_region(Atlas.DRONE_REGION, drone.position, height)


func _draw_region(region: Rect2i, grid_position: Vector2, height: float) -> void:
	var at := GridTransform.grid_to_world(grid_position) + Vector2.UP * height
	var rect := Rect2(at - Vector2(region.size) / 2.0, region.size)
	draw_texture_rect_region(_texture, rect, Rect2(region))
