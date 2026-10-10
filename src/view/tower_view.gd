class_name TowerView
extends Node

## Draws towers, pylons and repair yards from building_placed, greys out unpowered ones with the
## unpowered icon on power_changed, and removes them on building_destroyed.

const TINT := Color(0.62, 0.66, 0.75)
const UNPOWERED_TINT := Color(0.32, 0.32, 0.34)
const REGIONS := {
	Buildings.TOWER: [Atlas.TOWER, Atlas.TOWER_SIZE],
	Buildings.PYLON: [Atlas.PYLON, Atlas.PYLON_SIZE],
	Buildings.REPAIR_YARD: [Atlas.REPAIR_YARD, Atlas.REPAIR_YARD_SIZE],
}

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
	simulation.power_changed.connect(_show_power)


func _add(id: int) -> void:
	var building := _simulation.buildings.building(id)
	if building == null or not REGIONS.has(building.kind):
		return
	var cell: Array = REGIONS[building.kind]
	var coords: Vector2i = cell[0]
	var size: Vector2i = cell[1]
	var region := Atlas.region(coords, size)
	var sprite := Sprite2D.new()
	sprite.texture = _texture
	sprite.region_enabled = true
	sprite.region_rect = region
	sprite.centered = false
	sprite.offset = -Vector2(region.size.x / 2.0, region.size.y - Atlas.UNIT.y)
	sprite.position = GridTransform.grid_to_world(building.centre)
	sprite.add_child(_unpowered_icon(region))
	_parent.add_child(sprite)
	_sprites[id] = sprite
	_show(building, sprite)


func _remove(id: int) -> void:
	var sprite: Sprite2D = _sprites.get(id)
	if sprite != null:
		sprite.queue_free()
		_sprites.erase(id)


func _show_power() -> void:
	for id in _sprites:
		var building := _simulation.buildings.building(id)
		if building != null:
			_show(building, _sprites[id])


func _show(building: Buildings.Building, sprite: Sprite2D) -> void:
	sprite.self_modulate = TINT if building.powered else UNPOWERED_TINT
	var icon := sprite.get_child(0) as Sprite2D
	icon.visible = not building.powered


# The icon floats over the building's top; self_modulate keeps the grey tint off it.
func _unpowered_icon(region: Rect2i) -> Sprite2D:
	var icon := Sprite2D.new()
	icon.texture = _texture
	icon.region_enabled = true
	icon.region_rect = Atlas.UNPOWERED_REGION
	icon.position = Vector2(0, Atlas.UNIT.y / 2.0 - region.size.y)
	return icon
