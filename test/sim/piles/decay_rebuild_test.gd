extends GdUnitTestSuite

const WAVE_TICKS := 2000

var _sim: Simulation
var _events: Array[String]


func before_test() -> void:
	var settings := Settings.load_file(Settings.DEFAULTS_PATH).settings
	settings.change("run", "starting_lives", 100)
	settings.change("piles", "decay_chance", 100)
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


func test_wave_end_decays_the_piles_at_step_1_of_the_next_tick_and_starts_a_rebuild() -> void:
	_play_wave()
	assert_int(_sim.piles.level(Vector2i(1, 6))).is_equal(2)

	_sim.tick()

	assert_int(_sim.piles.level(Vector2i(1, 6))).is_equal(1)
	assert_bool(_sim.routing.is_rebuilding()).is_true()
	assert_array(_events).contains(["piles [(1, 6)]"])


func test_a_body_from_the_last_kill_lands_before_the_wave_decay() -> void:
	_play_wave()
	_sim.piles.queue_bodies(PackedVector2Array([Vector2(5.5, 1.5)]))

	_sim.tick()

	assert_int(_sim.piles.level(Vector2i(5, 1))).is_equal(0)


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


func test_the_rebuild_swaps_in_at_a_fixed_tick_however_soon_the_worker_finishes() -> void:
	_play_wave()
	_sim.tick()
	OS.delay_msec(500)
	for tick in Simulation.DECAY_REBUILD_TICKS - 1:
		_sim.tick()
	assert_bool(_sim.routing.is_rebuilding()).is_true()
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


func test_a_tower_built_during_the_rebuild_restarts_it_and_is_in_the_swapped_in_fields() -> void:
	_play_wave()
	_sim.tick()

	_sim.queue_command(Commands.Build.new(Buildings.TOWER, Vector2i(5, 5)))
	for tick in Simulation.DECAY_REBUILD_TICKS:
		_sim.tick()
	assert_bool(_sim.routing.is_rebuilding()).is_true()
	for tick in Simulation.DECAY_REBUILD_TICKS:
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
