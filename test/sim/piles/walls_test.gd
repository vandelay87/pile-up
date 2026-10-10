extends GdUnitTestSuite

const WALL := Vector2i(2, 2)

var _settings: Settings
var _piles: Piles


func before_test() -> void:
	_settings = Settings.load_file(Settings.DEFAULTS_PATH).settings
	_settings.change("piles", "wall_decay_chance", 100)
	var map := TestMaps.from_rows(
		["........", "........", "........", "........", "........"], Rect2i(7, 4, 1, 1)
	)
	_piles = Piles.new(_settings, map, Occupancy.new(map.width, map.height))
	var bodies := PackedVector2Array()
	for n in Piles.WALL_LEVEL:
		bodies.append(Vector2(WALL) + Vector2(0.5, 0.5))
	_piles.queue_bodies(bodies)
	_piles.land()
	_piles.take_changes()
	_piles.take_field_changes()


func test_damage_lowers_wall_hp_at_once() -> void:
	_piles.damage_wall(WALL, 4.5)

	assert_float(_piles.wall_hp(WALL)).is_equal_approx(10.5, 1e-9)
	assert_int(_piles.level(WALL)).is_equal(Piles.WALL_LEVEL)


func test_a_bucket_change_queues_one_field_update() -> void:
	_piles.damage_wall(WALL, 4.0)
	assert_array(_piles.take_field_changes()).is_empty()

	_piles.damage_wall(WALL, 0.5)
	_piles.damage_wall(WALL, 0.5)

	assert_array(_piles.take_field_changes()).contains_exactly([WALL])
	assert_array(_piles.take_changes()).contains_exactly([WALL])


func test_at_0_hp_the_wall_falls_to_a_level_3_pile() -> void:
	_piles.damage_wall(WALL, 14.0)
	_piles.take_field_changes()

	_piles.damage_wall(WALL, 1.0)

	assert_int(_piles.level(WALL)).is_equal(3)
	assert_float(_piles.wall_hp(WALL)).is_equal(0.0)
	assert_array(_piles.take_field_changes()).contains_exactly([WALL])


func test_damage_to_a_fallen_wall_or_a_pile_does_nothing() -> void:
	_piles.damage_wall(WALL, 15.0)
	_piles.take_field_changes()

	_piles.damage_wall(WALL, 5.0)
	_piles.damage_wall(Vector2i(0, 0), 5.0)

	assert_int(_piles.level(WALL)).is_equal(3)
	assert_int(_piles.level(Vector2i(0, 0))).is_equal(0)
	assert_array(_piles.take_field_changes()).is_empty()


func test_walls_nearby_counts_the_walls_in_each_cells_3x3_block() -> void:
	assert_int(_nearby(Vector2i(1, 1))).is_equal(1)
	assert_int(_nearby(Vector2i(3, 3))).is_equal(1)
	assert_int(_nearby(Vector2i(4, 2))).is_equal(0)

	_piles.damage_wall(WALL, _settings.wall_hp)
	assert_int(_nearby(Vector2i(1, 1))).is_equal(0)

	_piles.queue_bodies(PackedVector2Array([Vector2(WALL) + Vector2(0.5, 0.5)]))
	_piles.queue_bodies(PackedVector2Array([Vector2(WALL) + Vector2(0.5, 0.5)]))
	_piles.land()
	assert_int(_nearby(Vector2i(2, 2))).is_equal(1)
	_piles.decay()
	assert_int(_nearby(Vector2i(2, 2))).is_equal(0)


func _nearby(cell: Vector2i) -> int:
	return _piles.walls_nearby[cell.y * 8 + cell.x]
