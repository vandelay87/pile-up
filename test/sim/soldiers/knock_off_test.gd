extends GdUnitTestSuite

## Knock-off: a tumble over a soldier's wall cell knocks it off among the enemies that came over.
##
## A one-cell lane from the west to a 2×2 base in the east, with a wall across it at x = 10 and
## a dead-end nook above the wall cell, walled too. Enemies spawned west of the wall walk into it
## and are held there; a high fill takes the crush to a surge within a second or two, and every
## tumble goes straight over (10, 1) to land at (11, 1).

const ROWS: Array[String] = [
	"##########.#########",
	"....................",
	"##################..",
]
const BASE := Rect2i(18, 1, 2, 2)
const WALL := Vector2i(10, 1)
const NOOK := Vector2i(10, 0)
const LANDING := Vector2i(11, 1)
const TOUGH := 1000.0

var _settings: Settings
var _sim: Simulation


func before_test() -> void:
	var settings := TestSettings.without_swarm_spread()
	settings.change("run", "base_hp", 10000)
	_settings = settings.for_next_run()
	_settings.change("piles", "wall_hp", TOUGH)
	_settings.change("overflow", "leak", 5.0)
	_settings.change("overflow", "fill_per_stalled", 10.0)
	_sim = Simulation.new(_settings, TestMaps.from_rows(ROWS, BASE), 1)
	var bodies := PackedVector2Array()
	for cell: Vector2i in [WALL, NOOK]:
		for n in Piles.WALL_LEVEL:
			bodies.append(Vector2(cell) + Vector2(0.5, 0.5))
	_sim.piles.queue_bodies(Deaths.bodies_at(bodies))
	_sim.tick()


func test_a_tumble_over_a_soldiers_wall_cell_knocks_it_to_the_landing_side_at_elevation_0() -> void:
	var id := _sim.soldiers.add(WALL)
	_crowd(12)
	_run_until_tumbling()

	var index := _sim.soldiers.index_of(id)
	assert_object(_cell_of(id)).is_equal(LANDING)
	assert_int(_sim.soldiers.elevation(index)).is_equal(0)
	assert_object(_sim.soldiers.spot(index)).is_equal(WALL)


func test_with_no_ground_past_the_wall_a_soldier_lands_where_the_tumble_lands() -> void:
	# Every cell between the wall and the base is a level-2 pile; the lane west of the wall,
	# where the crowd stands, is the only ground.
	var bodies := PackedVector2Array()
	for x in range(LANDING.x, BASE.position.x):
		for n in 2:
			bodies.append(Vector2(x + 0.5, 1.5))
	_sim.piles.queue_bodies(Deaths.bodies_at(bodies))
	_sim.tick()
	var id := _sim.soldiers.add(WALL)
	_crowd(12)
	_run_until_tumbling()

	var index := _sim.soldiers.index_of(id)
	assert_object(_cell_of(id)).is_equal(LANDING)
	assert_int(_sim.soldiers.elevation(index)).is_equal(2)


func test_a_soldier_on_another_cell_of_the_wall_stays() -> void:
	var id := _sim.soldiers.add(NOOK)
	_crowd(12)
	_run_until_tumbling()

	for tick in 2 * Simulation.TICKS_PER_SECOND:
		_sim.tick()
		assert_object(_sim.soldiers.positions[_sim.soldiers.index_of(id)]).is_equal(
			MapData.centre_of(NOOK)
		)

	assert_int(_sim.overflow.crushes()[0].tier).is_equal(Overflow.Tier.SURGE)


func test_a_knocked_off_soldier_that_survives_returns_to_its_spot() -> void:
	var id := _sim.soldiers.add(WALL)
	_crowd(12)
	_run_until_tumbling()
	assert_object(_cell_of(id)).is_equal(LANDING)
	_sim.queue_command(Commands.SetSetting.new("overflow", "enabled", 0))

	for tick in 5 * Simulation.TICKS_PER_SECOND:
		_sim.tick()

	var index := _sim.soldiers.index_of(id)
	assert_int(index).is_not_equal(Soldiers.NONE)
	assert_object(_sim.soldiers.positions[index]).is_equal(MapData.centre_of(WALL))
	assert_int(_sim.soldiers.orders[index]).is_equal(Soldiers.NONE)
	assert_int(_sim.soldiers.elevation(index)).is_equal(Piles.WALL_LEVEL)


func test_soldiers_at_a_landing_cell_dont_stop_a_tumble_landing_there() -> void:
	# More soldiers on the landing cell than the landing crowd allows enemies.
	for n in _settings.landing_crowd + 2:
		_sim.soldiers.add(LANDING)
	_crowd(12)

	var id := _run_until_tumbling()

	assert_object(_sim.overflow.tumble(id).landing()).is_equal(LANDING)


func _cell_of(id: int) -> Vector2i:
	return Vector2i(_sim.soldiers.positions[_sim.soldiers.index_of(id)].floor())


# Spawns tough enemies along the lane west of the wall.
func _crowd(count: int) -> void:
	for n in count:
		_sim.enemies.spawn(Vector2(1.0 + 8.0 * (n + 0.5) / count, 1.5), TOUGH)


# Ticks until a tumbler has crossed into the wall cell, returning its id.
func _run_until_tumbling() -> int:
	for tick in 10 * Simulation.TICKS_PER_SECOND:
		_sim.tick()
		for i in _sim.enemies.count:
			var id := _sim.enemies.ids[i]
			if _sim.overflow.is_tumbling(id) and _sim.enemies.positions[i].x >= WALL.x:
				return id
	fail("no tumble crossed the wall")
	return Enemies.NONE
