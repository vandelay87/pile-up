extends GdUnitTestSuite

# A rock wall two cells thick with a two-cell gap: every cell east of it routes through the gap,
# so a tower closing the gap changes thousands of field cells.
const WIDTH := 60
const HEIGHT := 40
const GAP := Vector2i(10, 19)
const BASE := Rect2i(2, 19, 2, 2)
const FAR := Vector2i(50, 20)
const MAX_TICKS := 100

var _sim: Simulation
var _reports: Array[int]


func before_test() -> void:
	var settings := Settings.load_file(Settings.DEFAULTS_PATH).settings
	_sim = Simulation.new(settings, TestMaps.from_rows(_rows(), BASE, ["E"] as Array[String]), 1)
	_reports = []
	_sim.fields_changed.connect(func() -> void: _reports.append(_sim.tick_count))
	_sim.queue_command(Commands.NextWave.new())
	_sim.tick()
	_sim.tick()


func test_a_tower_built_mid_wave_leaves_the_old_fields_until_both_swap_in_together() -> void:
	var sensible_before := _value(Routing.Route.SENSIBLE)
	var direct_before := _value(Routing.Route.DIRECT)
	var old_while_settling: Array[bool] = []

	_sim.queue_command(Commands.Build.new(Buildings.TOWER, GAP))
	_sim.tick()
	var ticks := 1
	while _sim.routing.is_settling() and ticks < MAX_TICKS:
		old_while_settling.append(
			(
				_value(Routing.Route.SENSIBLE) == sensible_before
				and _value(Routing.Route.DIRECT) == direct_before
			)
		)
		_sim.tick()
		ticks += 1

	assert_bool(_sim.occupancy.is_occupied(GAP)).is_true()
	assert_int(ticks).is_greater(1)
	assert_array(old_while_settling).not_contains([false])
	assert_array(_reports).contains_exactly([_sim.tick_count])
	assert_float(_value(Routing.Route.SENSIBLE)).is_greater(sensible_before)
	assert_float(_value(Routing.Route.DIRECT)).is_greater(direct_before)
	assert_bool(FieldChecks.matches_full_rebuild(_sim)).is_true()


func test_a_change_reaching_thousands_of_cells_works_no_more_than_the_budget_on_any_tick() -> void:
	var update_cells := PackedInt32Array()
	var step_cells := PackedInt32Array()

	_sim.queue_command(Commands.Build.new(Buildings.TOWER, GAP))
	_sim.tick()
	update_cells.append(_sim.routing.last_update_cells)
	step_cells.append(_sim.routing.last_step_cells)
	var ticks := 1
	while _sim.routing.is_settling() and ticks < MAX_TICKS:
		_sim.tick()
		update_cells.append(_sim.routing.last_update_cells)
		step_cells.append(_sim.routing.last_step_cells)
		ticks += 1

	var worked := 0
	for cells in step_cells:
		worked += cells
	assert_int(worked).is_greater(2000)
	for cells in update_cells:
		assert_int(cells).is_zero()
	for cells in step_cells:
		assert_int(cells).is_less_equal(Routing.SETTLE_CELLS_PER_TICK)
	assert_bool(FieldChecks.matches_full_rebuild(_sim)).is_true()


func test_a_small_change_swaps_in_on_the_tick_it_is_made() -> void:
	var before := _sim.routing.value(Routing.Route.DIRECT, Vector2i(5, 17))

	_sim.queue_command(Commands.Build.new(Buildings.TOWER, Vector2i(5, 17)))
	_sim.tick()

	assert_bool(_sim.routing.is_settling()).is_false()
	assert_array(_reports).contains_exactly([_sim.tick_count])
	assert_float(_sim.routing.value(Routing.Route.DIRECT, Vector2i(5, 17))).is_greater(before)
	assert_bool(FieldChecks.matches_full_rebuild(_sim)).is_true()


func _value(route: Routing.Route) -> float:
	return _sim.routing.value(route, FAR)


func _rows() -> Array[String]:
	var rows: Array[String] = []
	for y in HEIGHT:
		var wall := "." if y == GAP.y or y == GAP.y + 1 else "#"
		rows.append(".".repeat(GAP.x) + wall.repeat(2) + ".".repeat(WIDTH - GAP.x - 2))
	return rows
