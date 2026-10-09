extends GdUnitTestSuite

const WAVE_TICKS := 2000

var _sim: Simulation
var _events: Array[String]


func before_test() -> void:
	var settings := Settings.load_file(Settings.DEFAULTS_PATH).settings
	settings.change("run", "starting_lives", 100)
	settings = settings.for_next_run()
	var rows: Array[String] = []
	for y in 8:
		rows.append("........")
	var map := TestMaps.from_rows(rows, Rect2i(3, 3, 2, 2), ["N"] as Array[String])
	_sim = Simulation.new(settings, map, 1)
	_events = []
	_sim.command_rejected.connect(func(reason: String) -> void: _events.append(reason))
	_sim.pile_changed.connect(
		func(cells: Array[Vector2i]) -> void: _events.append("piles %s" % [cells])
	)
	_sim.fields_changed.connect(func() -> void: _events.append("fields changed"))
	_sim.piles.queue_bodies(PackedVector2Array([Vector2(1.5, 6.5), Vector2(1.5, 6.5)]))
	_sim.tick()


func test_wave_end_decays_the_piles_and_starts_a_rebuild() -> void:
	_play_wave()

	assert_int(_sim.piles.level(Vector2i(1, 6))).is_equal(1)
	assert_bool(_sim.routing.is_rebuilding()).is_true()
	assert_array(_events).contains(["piles [(1, 6)]"])


func test_next_wave_is_rejected_while_the_decay_rebuild_is_in_flight() -> void:
	_play_wave()

	_sim.queue_command(Commands.NextWave.new())
	_sim.tick()

	assert_int(_sim.run_state.wave).is_equal(1)
	assert_array(_events).contains(["next wave: the fields are still rebuilding after decay"])


func test_jump_to_wave_is_rejected_while_the_decay_rebuild_is_in_flight() -> void:
	_play_wave()

	_sim.queue_command(Commands.JumpToWave.new(5))
	_sim.tick()

	assert_int(_sim.run_state.wave).is_equal(1)
	assert_array(_events).contains(["jump to wave: the fields are still rebuilding after decay"])


func test_the_finished_rebuild_is_swapped_in_at_step_1_and_equals_a_full_rebuild() -> void:
	_play_wave()
	_sim.routing.wait_for_rebuild()
	assert_bool(FieldChecks.matches_full_rebuild(_sim)).is_false()
	var swapped: Array[bool] = []
	_sim.step_observer = func(step: int) -> void:
		if step == Simulation.Step.SPAWN_ENEMIES:
			swapped.append(FieldChecks.matches_full_rebuild(_sim))

	_sim.tick()

	assert_array(swapped).contains_exactly([true])
	assert_bool(_sim.routing.is_rebuilding()).is_false()
	assert_array(_events).contains(["fields changed"])
	_sim.queue_command(Commands.NextWave.new())
	_sim.tick()
	assert_int(_sim.run_state.wave).is_equal(2)


func test_a_tower_built_during_the_rebuild_is_in_the_swapped_in_fields() -> void:
	_play_wave()

	_sim.queue_command(Commands.BuildTower.new(Vector2i(5, 5)))
	_sim.tick()
	_sim.routing.wait_for_rebuild()
	_sim.tick()

	assert_bool(_sim.occupancy.is_occupied(Vector2i(5, 5))).is_true()
	assert_bool(_sim.routing.is_rebuilding()).is_false()
	assert_bool(FieldChecks.matches_full_rebuild(_sim)).is_true()


func _play_wave() -> void:
	_sim.queue_command(Commands.NextWave.new())
	for tick in WAVE_TICKS:
		_sim.tick()
		if _sim.waves.phase == Waves.Phase.BUILD:
			return
	fail("the wave did not end within %d ticks" % WAVE_TICKS)
