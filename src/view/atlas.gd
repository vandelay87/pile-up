class_name Atlas
extends RefCounted

const PATH := "res://assets/atlas.png"
const UNIT := GridTransform.TILE_SIZE
const SIZE_IN_UNITS := Vector2i(5, 7)
const SOURCE_ID := 0

const CLEAR := Vector2i(0, 0)
const ROCK := Vector2i(1, 0)
const PILE_ROW := 1
const PILE_SIZE := Vector2i(1, 2)
const PILE_SLAB_HEIGHT := 6
const BASE := Vector2i(0, 3)
const BASE_SIZE := Vector2i(1, 3)
const TOWER := Vector2i(1, 3)
const TOWER_SIZE := Vector2i(2, 4)
const ENEMY_REGION := Rect2i(192, 96, 16, 24)
const TRACER_REGION := Rect2i(256, 96, 16, 4)


static func pile(level: int) -> Vector2i:
	return Vector2i(level - 1, PILE_ROW)


static func region(coords: Vector2i, size_in_units: Vector2i) -> Rect2i:
	return Rect2i(coords * UNIT, size_in_units * UNIT)


static func make_tile_set() -> TileSet:
	var tile_set := TileSet.new()
	tile_set.tile_shape = TileSet.TILE_SHAPE_ISOMETRIC
	tile_set.tile_layout = TileSet.TILE_LAYOUT_DIAMOND_DOWN
	tile_set.tile_size = GridTransform.TILE_SIZE

	var source := TileSetAtlasSource.new()
	source.texture = load(PATH)
	source.texture_region_size = UNIT
	_add_tile(source, CLEAR, Vector2i.ONE)
	_add_tile(source, ROCK, Vector2i.ONE)
	_add_tile(source, BASE, BASE_SIZE)
	for level in range(1, Piles.WALL_LEVEL + 1):
		_add_tile(source, pile(level), PILE_SIZE)
		source.get_tile_data(pile(level), 0).y_sort_origin = 1 - UNIT.y / 2
	tile_set.add_source(source, SOURCE_ID)
	return tile_set


static func _add_tile(source: TileSetAtlasSource, coords: Vector2i, size: Vector2i) -> void:
	source.create_tile(coords, size)
	var tile := source.get_tile_data(coords, 0)
	tile.texture_origin = Vector2i(0, (size.y - 1) * UNIT.y / 2)
