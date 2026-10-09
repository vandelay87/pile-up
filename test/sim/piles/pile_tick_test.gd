extends GdUnitTestSuite

var _settings: Settings
var _events: Array[String]


func before_test() -> void:
	_settings = Settings.load_file(Settings.DEFAULTS_PATH).settings
	_events = []


func test_a_killed_enemys_body_lands_at_step_1_of_the_next_tick() -> void:
	var sim := _sim()
	var id := sim.enemies.spawn(Vector2(2.5, 2.5), _settings.enemy_hp)
	sim.enemies.damage(id, 100.0)
	sim.tick()
	assert_int(sim.piles.level(Vector2i(2, 2))).is_equal(0)
	var seen: Array[int] = []
	sim.step_observer = func(step: int) -> void:
		if step == Simulation.Step.SPAWN_ENEMIES:
			seen.append(sim.piles.level(Vector2i(2, 2)))

	sim.tick()

	assert_array(seen).contains_exactly([1])
	assert_array(_events).contains(["piles [(2, 2)]"])


func test_both_fields_include_a_new_pile_on_the_tick_it_lands() -> void:
	var sim := _sim()
	sim.piles.queue_bodies(PackedVector2Array([Vector2(2.5, 2.5), Vector2(2.5, 2.5)]))

	sim.tick()

	assert_int(sim.piles.level(Vector2i(2, 2))).is_equal(2)
	assert_bool(FieldChecks.matches_full_rebuild(sim)).is_true()
	assert_array(_events).contains(["fields changed"])


func test_no_pile_signal_or_field_change_on_a_tick_without_bodies() -> void:
	var sim := _sim()

	sim.tick()

	assert_array(_events).is_empty()


func test_changing_a_pile_slow_rebuilds_the_fields() -> void:
	var sim := _sim()
	sim.piles.queue_bodies(PackedVector2Array([Vector2(2.5, 2.5)]))
	sim.tick()
	_events.clear()

	sim.queue_command(Commands.SetSetting.new("piles", "slow_level_1", 50))
	sim.tick()

	assert_bool(FieldChecks.matches_full_rebuild(sim)).is_true()
	assert_array(_events).contains(["fields changed"])


func _sim() -> Simulation:
	var rows: Array[String] = []
	for y in 10:
		rows.append("..........")
	var map := TestMaps.from_rows(rows, Rect2i(6, 6, 2, 2), ["N"] as Array[String])
	var sim := Simulation.new(_settings, map, 1)
	sim.pile_changed.connect(
		func(cells: Array[Vector2i]) -> void: _events.append("piles %s" % [cells])
	)
	sim.fields_changed.connect(func() -> void: _events.append("fields changed"))
	return sim
