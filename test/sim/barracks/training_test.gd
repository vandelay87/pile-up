extends GdUnitTestSuite

## A 24×24 open field with a 4×4 base at (10, 10), centred on (12, 12); the base powers cells
## 0..23. A wave of one slow enemy from the east edge keeps the wave running. The barracks at
## (15, 10) has the ring x 14..17, y 9..12; its cell nearest the base's centre is (14, 11),
## tied with (14, 12) and taking the lower index.

const BASE := Rect2i(10, 10, 4, 4)
const SIZE := 24
const BARRACKS := Vector2i(15, 10)

var _sim: Simulation
var _rejections: Array[String]


func before_test() -> void:
	var settings := Settings.load_file(Settings.DEFAULTS_PATH).settings
	settings.change("waves", "wave_1_size", 1)
	settings = settings.for_next_run()
	settings.change("enemies", "speed", 0.1)
	var rows: Array[String] = []
	for y in SIZE:
		rows.append(".".repeat(SIZE))
	var edges: Array[String] = ["E"]
	_sim = Simulation.new(settings, TestMaps.from_rows(rows, BASE, edges), 1)
	_sim.add_gold(10000 - _sim.run_state.gold)
	_rejections = []
	_sim.command_rejected.connect(func(reason: String) -> void: _rejections.append(reason))


func test_build_phase_training_pays_and_trains_at_once_beside_the_barracks() -> void:
	var barracks := _build(BARRACKS)
	_sim.queue_command(Commands.Train.new(barracks.id, 1))
	_sim.tick()

	assert_int(_sim.run_state.gold).is_equal(9770)
	assert_int(_sim.soldiers.count).is_equal(1)
	assert_object(_sim.soldiers.spot(0)).is_equal(Vector2i(14, 11))
	assert_int(_sim.barracks.queue_of(barracks.id).size()).is_equal(0)


func test_a_train_queues_as_many_as_the_queue_holds_then_is_rejected() -> void:
	var barracks := _build(BARRACKS)
	_start_wave()
	_train(barracks.id, 1)
	_train(barracks.id, 5)
	_train(barracks.id, 1)

	assert_int(_sim.barracks.queue_of(barracks.id).size()).is_equal(5)
	assert_int(_sim.run_state.gold).is_equal(9800 - 5 * 30)
	assert_array(_rejections).contains_exactly(["train: the queue is full"])


func test_capacity_is_ten_a_barracks_and_used_counts_soldiers_and_queued_ones() -> void:
	var barracks := _build(BARRACKS)
	_add_soldiers(8)
	_start_wave()
	_train(barracks.id, 5)

	assert_int(_sim.barracks.capacity()).is_equal(10)
	assert_int(_sim.barracks.used()).is_equal(10)
	assert_int(_sim.barracks.queue_of(barracks.id).size()).is_equal(2)
	_train(barracks.id, 1)
	assert_array(_rejections).contains_exactly(["train: capacity is full"])

	_build(Vector2i(15, 14))
	assert_int(_sim.barracks.capacity()).is_equal(20)


func test_a_train_queues_only_what_the_gold_pays_for() -> void:
	var barracks := _build(BARRACKS)
	_start_wave()
	_sim.add_gold(70 - _sim.run_state.gold)
	_train(barracks.id, 5)
	_train(barracks.id, 1)

	assert_int(_sim.barracks.queue_of(barracks.id).size()).is_equal(2)
	assert_int(_sim.run_state.gold).is_equal(10)
	assert_array(_rejections).contains_exactly(["train: not enough gold"])


func test_over_capacity_soldiers_stay_but_training_is_refused() -> void:
	var barracks := _build(BARRACKS)
	_add_soldiers(12)
	_train(barracks.id, 1)

	assert_int(_sim.soldiers.count).is_equal(12)
	assert_int(_sim.run_state.gold).is_equal(9800)
	assert_array(_rejections).contains_exactly(["train: capacity is full"])


func test_a_train_needs_a_barracks_and_a_count_of_one_or_five() -> void:
	var barracks := _build(BARRACKS)
	var pylon := _build_kind(Buildings.PYLON, Vector2i(20, 10))
	_train(pylon.id, 1)
	_train(barracks.id, 2)

	assert_array(_rejections).contains_exactly(
		["train: not a barracks", "train: the count must be 1 or 5"]
	)
	assert_int(_sim.soldiers.count).is_equal(0)


func test_cancelling_a_slot_refunds_what_it_cost() -> void:
	var barracks := _build(BARRACKS)
	_start_wave()
	_train(barracks.id, 1)
	_sim.queue_command(Commands.SetSetting.new("soldiers", "cost", 50))
	_train(barracks.id, 1)
	_sim.queue_command(Commands.CancelTraining.new(barracks.id, 1))
	_sim.tick()

	assert_array(Array(_sim.barracks.queue_of(barracks.id))).contains_exactly([30])
	assert_int(_sim.run_state.gold).is_equal(9800 - 30)


func test_cancelling_a_slot_that_isnt_queued_is_rejected() -> void:
	var barracks := _build(BARRACKS)
	_start_wave()
	_train(barracks.id, 1)
	_sim.queue_command(Commands.CancelTraining.new(barracks.id, 1))
	_sim.queue_command(Commands.CancelTraining.new(-5, 0))
	_sim.tick()

	assert_array(_rejections).contains_exactly(
		["cancel training: no such slot", "cancel training: not a barracks"]
	)
	assert_int(_sim.barracks.queue_of(barracks.id).size()).is_equal(1)


func test_during_a_wave_each_soldier_takes_300_ticks_counting_the_tick_it_was_queued() -> void:
	var barracks := _build(BARRACKS)
	_start_wave()
	_sim.queue_command(Commands.Train.new(barracks.id, 1))
	_sim.queue_command(Commands.Train.new(barracks.id, 1))
	_sim.tick()
	_run(298)
	assert_int(_sim.soldiers.count).is_equal(0)

	_run(1)
	assert_int(_sim.soldiers.count).is_equal(1)
	assert_object(_sim.soldiers.spot(0)).is_equal(Vector2i(14, 11))
	assert_int(_sim.barracks.queue_of(barracks.id).size()).is_equal(1)
	_run(299)
	assert_int(_sim.soldiers.count).is_equal(1)
	_run(1)
	assert_int(_sim.soldiers.count).is_equal(2)


func test_wave_training_pauses_while_unpowered_and_resumes_where_it_left_off() -> void:
	var barracks := _build(BARRACKS)
	_start_wave()
	_train(barracks.id, 1)
	_run(99)
	assert_int(_sim.barracks.ticks_left(barracks.id)).is_equal(200)

	_sim.queue_command(Commands.SetSetting.new("run", "base_power_area", 0))
	_run(201)
	assert_int(_sim.barracks.ticks_left(barracks.id)).is_equal(200)

	_sim.queue_command(Commands.SetSetting.new("run", "base_power_area", 10))
	_run(199)
	assert_int(_sim.soldiers.count).is_equal(0)
	_run(1)
	assert_int(_sim.soldiers.count).is_equal(1)


func test_wave_training_pauses_while_the_barracks_is_under_repair() -> void:
	var barracks := _build(BARRACKS)
	var yard := _build_kind(Buildings.REPAIR_YARD, Vector2i(15, 14))
	_sim.queue_command(Commands.SetRepairThreshold.new(yard.id, 100))
	_start_wave()
	_train(barracks.id, 1)
	_sim.buildings.damage(barracks.id, 50.0)
	var drone := _sim.repair_yards.drone(yard.id)
	while drone.state != RepairYards.State.REPAIRING:
		_sim.tick()
	_sim.tick()
	var left := _sim.barracks.ticks_left(barracks.id)
	_run(60)
	assert_int(_sim.barracks.ticks_left(barracks.id)).is_equal(left)

	while drone.state == RepairYards.State.REPAIRING:
		_sim.tick()
	_run(2)
	assert_int(_sim.barracks.ticks_left(barracks.id)).is_less(left)


func test_at_wave_end_every_queue_trains_at_once_in_build_order() -> void:
	var first := _build(BARRACKS)
	var second := _build(Vector2i(4, 4))
	_start_wave()
	_sim.queue_command(Commands.Train.new(second.id, 1))
	_sim.queue_command(Commands.Train.new(first.id, 5))
	_sim.queue_command(Commands.KillEnemies.new(1))
	_sim.tick()

	assert_int(_sim.waves.phase).is_equal(Waves.Phase.BUILD)
	assert_int(_sim.soldiers.count).is_equal(6)
	assert_object(_sim.soldiers.spot(0)).is_equal(Vector2i(14, 11))
	assert_bool(Rect2i(3, 3, 4, 4).has_point(_sim.soldiers.spot(5))).is_true()
	assert_int(_sim.barracks.queue_of(first.id).size()).is_equal(0)
	assert_int(_sim.barracks.queue_of(second.id).size()).is_equal(0)


func test_a_destroyed_barracks_refunds_its_queue_and_lowers_capacity_but_no_soldier_dies() -> void:
	var barracks := _build(BARRACKS)
	_build(Vector2i(4, 4))
	_train(barracks.id, 5)
	_start_wave()
	_train(barracks.id, 5)
	_sim.buildings.damage(barracks.id, 1000.0)
	_sim.tick()

	assert_int(_sim.run_state.gold).is_equal(10000 - 2 * 200 - 5 * 30)
	assert_int(_sim.soldiers.count).is_equal(5)
	assert_int(_sim.barracks.capacity()).is_equal(10)
	assert_int(_sim.barracks.used()).is_equal(5)
	assert_int(_sim.barracks.queue_of(barracks.id).size()).is_equal(0)


func test_a_queue_or_timer_start_change_is_reported_at_the_end_of_the_tick() -> void:
	var barracks := _build(BARRACKS)
	_start_wave()
	var changed: Array[int] = []
	_sim.training_changed.connect(func(id: int) -> void: changed.append(id))
	_sim.queue_command(Commands.Train.new(barracks.id, 1))
	_sim.queue_command(Commands.Train.new(barracks.id, 1))
	_sim.tick()
	assert_array(changed).contains_exactly([barracks.id])

	_run(298)
	assert_array(changed).contains_exactly([barracks.id])
	_run(1)
	assert_array(changed).contains_exactly([barracks.id, barracks.id])
	_sim.queue_command(Commands.CancelTraining.new(barracks.id, 0))
	_sim.tick()
	assert_array(changed).contains_exactly([barracks.id, barracks.id, barracks.id])


func _add_soldiers(count: int) -> void:
	_sim.queue_command(Commands.AddSoldiers.new(count))
	_sim.tick()


func _start_wave() -> void:
	_sim.queue_command(Commands.NextWave.new())
	_sim.tick()


func _train(barracks_id: int, count: int) -> void:
	_sim.queue_command(Commands.Train.new(barracks_id, count))
	_sim.tick()


func _run(ticks: int) -> void:
	for n in ticks:
		_sim.tick()


func _build(origin: Vector2i) -> Buildings.Building:
	return _build_kind(Buildings.BARRACKS, origin)


func _build_kind(kind: StringName, origin: Vector2i) -> Buildings.Building:
	_sim.queue_command(Commands.Build.new(kind, origin))
	_sim.tick()
	return _building_at(origin)


func _building_at(cell: Vector2i) -> Buildings.Building:
	return _sim.buildings.building(_sim.occupancy.building_at(cell))
