class_name Heights
extends RefCounted

## How tall the things on the map are drawn, in world pixels above the ground: a pile by its
## level, and a building or the base by its sprite's opaque height less its footprint's
## diamond, so the heights follow the art. Tumbles, perched enemies and their bodies' falls are
## drawn from these.

# Each sprite's roof height, by its atlas region, once measured.
static var _roofs: Dictionary[Rect2i, float] = {}


## The roof height of a building of [param kind].
static func building(kind: StringName) -> float:
	var region: Array = TowerView.REGIONS[kind]
	var coords: Vector2i = region[0]
	var size: Vector2i = region[1]
	return _roof(coords, size, Buildings.footprint_size(kind))


## The roof height of the base, drawn a cell at a time.
static func base() -> float:
	return _roof(Atlas.BASE, Atlas.BASE_SIZE, Vector2i.ONE)


## The height of whatever stands on [param cell]: the base, a building or a pile.
static func of_cell(simulation: Simulation, cell: Vector2i) -> float:
	if not simulation.map.in_bounds(cell):
		return 0.0
	if simulation.map.is_base(cell):
		return base()
	var built := simulation.buildings.building(simulation.occupancy.building_at(cell))
	if built != null:
		return building(built.kind)
	return simulation.piles.level(cell) * Atlas.PILE_SLAB_HEIGHT


## The roof height of [param target], a building id or [constant Perches.BASE], or 0 when it
## is gone.
static func of_target(simulation: Simulation, target: int) -> float:
	if target == Perches.BASE:
		return base()
	var built := simulation.buildings.building(target)
	return building(built.kind) if built != null else 0.0


# The height of the opaque top of the sprite at [param coords] above its footprint's diamond,
# measured once from the atlas.
static func _roof(coords: Vector2i, size_in_units: Vector2i, footprint: Vector2i) -> float:
	var key := Rect2i(coords, size_in_units)
	if _roofs.has(key):
		return _roofs[key]
	var region := Atlas.region(coords, size_in_units)
	var image := (load(Atlas.PATH) as Texture2D).get_image()
	var top := image.get_region(region).get_used_rect().position.y
	var diamond := (footprint.x + footprint.y) * Atlas.UNIT.y / 2.0
	var roof := region.size.y - diamond - top
	_roofs[key] = roof
	return roof
