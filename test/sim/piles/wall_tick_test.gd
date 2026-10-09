extends GdUnitTestSuite

const WALL := Vector2i(3, 3)

var _settings: Settings
var _events: Array[String]


func before_test() -> void:
	_settings = Settings.load_file(Settings.DEFAULTS_PATH).settings
	_events = []


func test_a_broken_wall_updates_the_fields_at_step_1_of_the_next_tick() -> void:
	var sim := _sim_with_wall()
	sim.step_observer = func(step: int) -> void:
		if step == Simulation.Step.MOVE_ENEMIES:
			sim.piles.damage_wall(WALL, _settings.wall_hp)

	sim.tick()
	sim.step_observer = Callable()

	assert_int(sim.piles.level(WALL)).is_equal(Piles.FALLEN_WALL_LEVEL)
	assert_bool(FieldChecks.matches_full_rebuild(sim)).is_false()
	assert_array(_events).contains_exactly(["piles [(3, 3)]"])

	_events.clear()
	sim.tick()

	assert_bool(FieldChecks.matches_full_rebuild(sim)).is_true()
	assert_array(_events).contains_exactly(["fields changed"])


func test_a_bucket_change_updates_the_fields_next_tick() -> void:
	var sim := _sim_with_wall()
	sim.piles.damage_wall(WALL, _settings.wall_hp_bucket)

	sim.tick()

	assert_bool(FieldChecks.matches_full_rebuild(sim)).is_true()


func test_changing_what_a_wall_costs_rebuilds_the_fields() -> void:
	for key: String in ["speed", "wall_damage"]:
		var sim := _sim_with_wall()

		sim.queue_command(Commands.SetSetting.new("enemies", key, 3.0))
		sim.tick()

		assert_bool(FieldChecks.matches_full_rebuild(sim)).is_true()


func test_enemies_break_a_wall_and_the_fields_repair_the_next_tick() -> void:
	_settings.change("enemies", "heading_offset", 0.0)
	var sim := _corridor_sim(1)
	var fallen_at := -1
	for t in 40 * Simulation.TICKS_PER_SECOND:
		sim.tick()
		if sim.piles.level(Vector2i(4, 1)) == Piles.FALLEN_WALL_LEVEL:
			fallen_at = t
			break
	assert_int(fallen_at).is_greater(0)
	assert_bool(FieldChecks.matches_full_rebuild(sim)).is_false()

	sim.tick()

	assert_bool(FieldChecks.matches_full_rebuild(sim)).is_true()


func test_a_run_with_walls_is_identical_for_the_same_seed() -> void:
	var first := _corridor_sim(7)
	var second := _corridor_sim(7)
	for t in 20 * Simulation.TICKS_PER_SECOND:
		first.tick()
		second.tick()

	assert_array(Array(first.piles.wall_hps)).is_equal(Array(second.piles.wall_hps))
	assert_array(Array(first.enemies.positions)).is_equal(Array(second.enemies.positions))


func test_decay_reopens_a_wall_corner_after_the_rebuild() -> void:
	var sim := _sim_with_wall()
	sim.decay_piles()

	for t in Simulation.DECAY_REBUILD_TICKS + 2:
		sim.tick()

	assert_int(sim.piles.level(WALL)).is_equal(Piles.WALL_LEVEL - 1)
	assert_bool(FieldChecks.matches_full_rebuild(sim)).is_true()


func _corridor_sim(run_seed: int) -> Simulation:
	var map := TestMaps.from_rows(
		["..........", "..........", ".........."], Rect2i(9, 0, 1, 3), ["W"] as Array[String]
	)
	var sim := Simulation.new(_settings, map, run_seed)
	var bodies := PackedVector2Array()
	for y in 3:
		for n in Piles.WALL_LEVEL:
			bodies.append(Vector2(4.5, y + 0.5))
	sim.piles.queue_bodies(bodies)
	var rng := RandomNumberGenerator.new()
	rng.seed = run_seed
	for n in 9:
		sim.enemies.spawn(Vector2(rng.randf_range(0.5, 3.5), rng.randf_range(0.4, 2.6)), 1000.0)
	return sim


func _sim_with_wall() -> Simulation:
	var rows: Array[String] = []
	for y in 8:
		rows.append("........")
	var map := TestMaps.from_rows(rows, Rect2i(6, 6, 2, 2), ["N"] as Array[String])
	var sim := Simulation.new(_settings, map, 1)
	var bodies := PackedVector2Array()
	for n in Piles.WALL_LEVEL:
		bodies.append(Vector2(WALL) + Vector2(0.5, 0.5))
	sim.piles.queue_bodies(bodies)
	sim.tick()
	sim.pile_changed.connect(
		func(cells: Array[Vector2i]) -> void: _events.append("piles %s" % [cells])
	)
	sim.fields_changed.connect(func() -> void: _events.append("fields changed"))
	return sim
