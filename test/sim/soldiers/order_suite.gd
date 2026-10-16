extends GdUnitTestSuite

## Helpers for the order tests, at the Simulation seam. Each test draws its own map: '.' clear
## ground, '#' rock, 'W' a wall (5 bodies landed before the test starts) 'p' a level-2 pile and
## '3' or '4' a pile of that level.
## The base is 2×2 in the bottom-left corner, out of the way.

var _sim: Simulation
var _rejections: Array[String]


func _move(ids: Array, target: Vector2, formation: StringName) -> void:
	_sim.queue_command(Commands.Move.new(PackedInt32Array(ids), target, formation))


# Ticks until no soldier is under an order, failing after [param limit] ticks.
func _run_until_standing(limit: int) -> int:
	for tick in limit:
		_sim.tick()
		var walking := false
		for i in _sim.soldiers.count:
			walking = walking or _sim.soldiers.orders[i] != Soldiers.NONE
		if not walking:
			return tick + 1
	fail("soldiers still walking after %d ticks" % limit)
	return limit


# Ticks until the soldier [param id] stands, returning every cell it stood on along the way.
func _cells_walked(id: int, limit: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for tick in limit:
		_sim.tick()
		var cell := Vector2i(_position_of(id).floor())
		if cells.is_empty() or cells[-1] != cell:
			cells.append(cell)
		if _sim.soldiers.orders[_sim.soldiers.index_of(id)] == Soldiers.NONE:
			return cells
	fail("soldier still walking after %d ticks" % limit)
	return cells


func _path_cells(id: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for index in _sim.soldiers.path_left(_sim.soldiers.index_of(id)):
		cells.append(_sim.map.cell_of(index))
	return cells


func _add_row(first: Vector2i, wanted: int) -> Array:
	var ids := []
	for n in wanted:
		ids.append(_sim.soldiers.add(first + Vector2i(n, 0)))
	return ids


# Every soldier's position, spot, order, slot and remaining path.
func _state() -> Array:
	var state := []
	var soldiers := _sim.soldiers
	for i in soldiers.count:
		(
			state
			. append(
				[
					soldiers.positions[i],
					soldiers.spots[i],
					soldiers.orders[i],
					soldiers.slots[i],
					Array(soldiers.path_left(i)),
				]
			)
		)
	return state


func _spots() -> Array[Vector2i]:
	var spots: Array[Vector2i] = []
	for i in _sim.soldiers.count:
		spots.append(_sim.soldiers.spot(i))
	return spots


func _spot_of(id: int) -> Vector2i:
	return _sim.soldiers.spot(_sim.soldiers.index_of(id))


func _position_of(id: int) -> Vector2:
	return _sim.soldiers.positions[_sim.soldiers.index_of(id)]


# Rows with the base's 2×2 in the bottom-left corner. 'W' cells get a wall, 'p' cells a level-2
# pile and '3' or '4' cells a pile of that level before the test starts.
func _sim_from(rows: Array[String]) -> Simulation:
	var clear_rows: Array[String] = []
	var bodies := PackedVector2Array()
	for y in rows.size():
		var clear := rows[y]
		for mark: String in ["W", "p", "3", "4"]:
			clear = clear.replace(mark, ".")
		clear_rows.append(clear)
		for x in rows[y].length():
			var level: int = {"W": Piles.WALL_LEVEL, "p": 2, "3": 3, "4": 4}.get(rows[y][x], 0)
			for n in level:
				bodies.append(Vector2(x + 0.5, y + 0.5))
	var map := TestMaps.from_rows(clear_rows, Rect2i(0, rows.size() - 2, 2, 2))
	var sim := Simulation.new(Settings.load_file(Settings.DEFAULTS_PATH).settings, map)
	_rejections = []
	sim.command_rejected.connect(func(reason: String) -> void: _rejections.append(reason))
	if not bodies.is_empty():
		sim.piles.queue_bodies(Deaths.bodies_at(bodies))
		sim.tick()
	return sim
