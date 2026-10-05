class_name GridTransform
extends RefCounted

const TILE_SIZE := Vector2i(64, 32)
const XF := Transform2D(
	Vector2(TILE_SIZE.x / 2.0, TILE_SIZE.y / 2.0),
	Vector2(-TILE_SIZE.x / 2.0, TILE_SIZE.y / 2.0),
	Vector2(TILE_SIZE.x / 2.0, 0.0)
)

static var _inverse := XF.affine_inverse()


static func grid_to_world(position: Vector2) -> Vector2:
	return XF * position


static func world_to_grid(point: Vector2) -> Vector2:
	return _inverse * point


static func cell_to_world(cell: Vector2i) -> Vector2:
	return grid_to_world(Vector2(cell) + Vector2(0.5, 0.5))


static func world_to_cell(point: Vector2) -> Vector2i:
	return Vector2i(world_to_grid(point).floor())
