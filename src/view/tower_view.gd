class_name TowerView
extends Node

const TINT := Color(0.62, 0.66, 0.75)

var _simulation: Simulation
var _parent: Node2D
var _texture: Texture2D
var _sprites: Dictionary[int, Sprite2D] = {}


func setup(simulation: Simulation, parent: Node2D) -> void:
	_parent = parent
	_texture = load(Atlas.PATH)
	for sprite: Sprite2D in _sprites.values():
		sprite.queue_free()
	_sprites.clear()
	_simulation = simulation
	simulation.building_placed.connect(_add)
	simulation.building_destroyed.connect(_remove)


func _add(id: int) -> void:
	var building := _simulation.buildings.building(id)
	if building.kind != Buildings.TOWER:
		return
	var region := Atlas.region(Atlas.TOWER, Atlas.TOWER_SIZE)
	var sprite := Sprite2D.new()
	sprite.texture = _texture
	sprite.region_enabled = true
	sprite.region_rect = region
	sprite.centered = false
	sprite.offset = -Vector2(region.size.x / 2.0, region.size.y - Atlas.UNIT.y)
	sprite.modulate = TINT
	sprite.position = GridTransform.grid_to_world(building.centre)
	_parent.add_child(sprite)
	_sprites[id] = sprite


func _remove(id: int) -> void:
	var sprite: Sprite2D = _sprites.get(id)
	if sprite != null:
		sprite.queue_free()
		_sprites.erase(id)
