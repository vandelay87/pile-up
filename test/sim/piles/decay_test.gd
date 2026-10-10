extends GdUnitTestSuite

const WALL := Vector2i(3, 0)

var _settings: Settings


func before_test() -> void:
	_settings = Settings.load_file(Settings.DEFAULTS_PATH).settings


func test_at_100_percent_every_pile_loses_exactly_one_level() -> void:
	_set_chances(100, 100)
	var piles := _piles()
	_set_level(piles, Vector2i(0, 0), 1)
	_set_level(piles, Vector2i(2, 1), 2)
	_set_level(piles, Vector2i(3, 3), 4)
	_build_wall(piles, WALL)

	piles.decay()

	assert_int(piles.level(Vector2i(0, 0))).is_equal(0)
	assert_int(piles.level(Vector2i(2, 1))).is_equal(1)
	assert_int(piles.level(Vector2i(3, 3))).is_equal(3)
	assert_int(piles.level(WALL)).is_equal(Piles.WALL_LEVEL - 1)
	assert_float(piles.wall_hp(WALL)).is_equal(0.0)
	assert_array(piles.changed).contains_exactly_in_any_order(
		[Vector2i(0, 0), Vector2i(2, 1), Vector2i(3, 3), WALL]
	)


func test_at_0_percent_no_pile_loses_a_level() -> void:
	_set_chances(0, 0)
	var piles := _piles()
	_set_level(piles, Vector2i(0, 0), 1)
	_set_level(piles, Vector2i(3, 3), 4)
	_build_wall(piles, WALL)

	piles.decay()

	assert_int(piles.level(Vector2i(0, 0))).is_equal(1)
	assert_int(piles.level(Vector2i(3, 3))).is_equal(4)
	assert_int(piles.level(WALL)).is_equal(Piles.WALL_LEVEL)
	assert_float(piles.wall_hp(WALL)).is_equal(15.0)
	assert_array(piles.changed).is_empty()


func test_over_many_piles_the_loss_rate_is_near_each_chance() -> void:
	var map := TestMaps.from_rows(_rows(40, 40), Rect2i(39, 39, 1, 1))
	var piles := Piles.new(_settings, map, Occupancy.new(map.width, map.height), _rng(3))
	var cells := 0
	for y in 39:
		for x in 39:
			piles.levels[y * map.width + x] = 2 if (x + y) % 2 == 0 else Piles.WALL_LEVEL
			cells += 1

	piles.decay()

	var piles_lost := 0
	var walls_lost := 0
	for y in 39:
		for x in 39:
			var level := piles.level(Vector2i(x, y))
			if (x + y) % 2 == 0 and level == 1:
				piles_lost += 1
			elif (x + y) % 2 == 1 and level == Piles.WALL_LEVEL - 1:
				walls_lost += 1
	var pile_count := (cells + 1) / 2
	var wall_count := cells / 2
	assert_float(float(piles_lost) / pile_count).is_between(0.45, 0.55)
	assert_float(float(walls_lost) / wall_count).is_between(0.20, 0.30)


func test_a_damaged_wall_that_survives_keeps_its_hp() -> void:
	_set_chances(100, 0)
	var piles := _piles()
	_build_wall(piles, WALL)
	piles.damage_wall(WALL, 4.0)

	piles.decay()

	assert_int(piles.level(WALL)).is_equal(Piles.WALL_LEVEL)
	assert_float(piles.wall_hp(WALL)).is_equal(11.0)


func test_a_wall_rebuilt_from_level_4_has_full_hp() -> void:
	_set_chances(100, 100)
	var piles := _piles()
	_build_wall(piles, WALL)
	piles.damage_wall(WALL, 10.0)
	piles.decay()

	piles.queue_bodies(PackedVector2Array([Vector2(WALL) + Vector2(0.5, 0.5)]))
	piles.land()

	assert_int(piles.level(WALL)).is_equal(Piles.WALL_LEVEL)
	assert_float(piles.wall_hp(WALL)).is_equal(15.0)


func test_a_fallen_wall_rolls_like_any_other_pile() -> void:
	_set_chances(100, 0)
	var piles := _piles()
	_build_wall(piles, WALL)
	piles.damage_wall(WALL, 15.0)

	piles.decay()

	assert_int(piles.level(WALL)).is_equal(Piles.FALLEN_WALL_LEVEL - 1)


func test_the_same_seed_gives_the_same_decay() -> void:
	var first := _random_piles(_rng(11))
	var second := _random_piles(_rng(11))

	first.decay()
	second.decay()

	assert_array(Array(first.levels)).is_equal(Array(second.levels))
	assert_array(Array(first.levels)).is_not_equal(Array(_random_piles(_rng(11)).levels))


func test_the_run_seed_seeds_the_decay_rolls() -> void:
	var first := _decayed_sim(5)
	var second := _decayed_sim(5)
	var other := _decayed_sim(6)

	assert_array(Array(first.piles.levels)).is_equal(Array(second.piles.levels))
	assert_array(Array(first.piles.levels)).is_not_equal(Array(other.piles.levels))


func test_decay_with_no_piles_changes_nothing() -> void:
	var piles := _piles()

	piles.decay()

	assert_array(piles.changed).is_empty()


func test_taking_the_changes_empties_the_list() -> void:
	_set_chances(100, 100)
	var piles := _piles()
	_set_level(piles, Vector2i(1, 1), 2)
	piles.decay()

	var taken := piles.take_changes()
	piles.decay()

	assert_array(taken).contains_exactly([Vector2i(1, 1)])
	assert_array(piles.changed).contains_exactly([Vector2i(1, 1)])


func _random_piles(rng: RandomNumberGenerator) -> Piles:
	var map := TestMaps.from_rows(_rows(16, 16), Rect2i(15, 15, 1, 1))
	var piles := Piles.new(_settings, map, Occupancy.new(map.width, map.height), rng)
	for y in 15:
		for x in 15:
			piles.levels[y * map.width + x] = 1 + (x * 7 + y * 3) % 4
	return piles


func _decayed_sim(run_seed: int) -> Simulation:
	var map := TestMaps.from_rows(_rows(16, 16), Rect2i(15, 15, 1, 1))
	var sim := Simulation.new(_settings, map, run_seed)
	for y in 15:
		for x in 15:
			sim.piles.levels[y * map.width + x] = 2
	sim.decay_piles()
	sim.tick()
	return sim


func _set_chances(pile_percent: int, wall_percent: int) -> void:
	_settings.change("piles", "decay_chance", pile_percent)
	_settings.change("piles", "wall_decay_chance", wall_percent)


# Raises the cell to level 4, then lands the body that makes it a wall at full HP.
func _build_wall(piles: Piles, cell: Vector2i) -> void:
	_set_level(piles, cell, Piles.WALL_LEVEL - 1)
	piles.queue_bodies(PackedVector2Array([Vector2(cell) + Vector2(0.5, 0.5)]))
	piles.land()
	piles.take_changes()
	piles.take_field_changes()


func _set_level(piles: Piles, cell: Vector2i, level: int) -> void:
	piles.levels[cell.y * 4 + cell.x] = level


func _piles() -> Piles:
	var map := TestMaps.open_field()
	return Piles.new(_settings, map, Occupancy.new(map.width, map.height), _rng(1))


func _rng(rng_seed: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	return rng


static func _rows(width: int, height: int) -> Array[String]:
	var rows: Array[String] = []
	for y in height:
		rows.append(".".repeat(width))
	return rows
