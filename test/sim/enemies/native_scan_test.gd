extends GdUnitTestSuite

## The C++ neighbour scan (#201) against the GDScript one it replaces: a dense crowd with
## attackers, tumblers, the dead and stacked enemies moves bit for bit the same either way.

const SIZE := 20
const TICKS := 40


func test_the_native_scan_is_loaded() -> void:
	assert_bool(ClassDB.class_exists(&"NeighbourScan")).is_true()


func test_a_dense_crowd_moves_the_same_with_the_native_scan() -> void:
	# Neighbour cap and personal-space radius: uncapped and capped, with personal space at the
	# default, off, and reaching past the 3×3.
	for case: Vector2 in [
		Vector2(0, 0.7), Vector2(0, 0), Vector2(8, 0.7), Vector2(8, 0), Vector2(3, 1.6)
	]:
		var native := _crowd(int(case.x), case.y)
		var scripted := _crowd(int(case.x), case.y)
		scripted.native_scan = false
		assert_bool(native.native_scan).is_true()

		for tick in TICKS:
			_tick(native)
			_tick(scripted)

		assert_int(native.count).is_equal(scripted.count)
		for i in native.count:
			assert_int(native.ids[i]).is_equal(scripted.ids[i])
			assert_vector(native.positions[i]).is_equal(scripted.positions[i])


func _crowd(cap: int, personal_space: float) -> Enemies:
	var settings := Settings.load_file(Settings.DEFAULTS_PATH).settings
	settings.change("enemies", "neighbour_cap", cap)
	settings.change("enemies", "personal_space_radius", personal_space)
	var rows: Array[String] = []
	for y in SIZE:
		rows.append(".".repeat(SIZE))
	var systems := TestSystems.new(settings, TestMaps.from_rows(rows, Rect2i(18, 18, 2, 2)))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var enemies := systems.enemies(systems.routing(), rng)
	var place := RandomNumberGenerator.new()
	place.seed = 11
	for n in 400:
		var pos := Vector2(place.randf_range(1.0, 13.0), place.randf_range(1.0, 13.0))
		enemies.spawn(pos, settings.enemy_hp, Enemies.Kind.NORMAL)
		if n % 25 == 0:
			# Stacked exactly on the last one, for the tie break.
			enemies.spawn(pos, settings.enemy_hp, Enemies.Kind.NORMAL)
	for i in enemies.count:
		if i % 13 == 0:
			enemies.soldier_targets[i] = 0
		elif i % 17 == 0:
			enemies.tumbling[i] = 1
		elif i % 19 == 0:
			enemies.hp[i] = 0.0
	return enemies


# No remove_dead: the dead stay in the crowd, as a debug kill leaves them before REMOVE_DEAD.
func _tick(enemies: Enemies) -> void:
	enemies.rebuild_spatial_hash()
	enemies.move()
