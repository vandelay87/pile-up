extends GdUnitTestSuite

const FIRST := Simulation.Step.DRAIN_COMMANDS
const SECOND := Simulation.Step.LAND_BODIES_AND_UPDATE_FIELDS
const THIRD := Simulation.Step.SPAWN_ENEMIES


func test_a_step_lasts_until_the_next_one_starts_and_the_last_until_the_tick_ends() -> void:
	var profile := StepProfile.new()
	profile.mark(FIRST, 1_000)
	profile.mark(SECOND, 1_500)
	profile.mark(THIRD, 3_500)
	profile.finish_tick(4.0)

	var table := profile.table()

	assert_float(table.tick.mean_msec).is_equal_approx(4.0, 0.0001)
	assert_float(table.steps[FIRST].mean_msec).is_equal_approx(0.5, 0.0001)
	assert_float(table.steps[SECOND].mean_msec).is_equal_approx(2.0, 0.0001)
	assert_float(table.steps[THIRD].mean_msec).is_equal_approx(1.5, 0.0001)


# Ticks k = 1..100 take k + 1 ms. The first step takes 2 ms in the fastest tick and 1 ms in the
# rest; the second step takes what is left.
func test_a_step_reports_its_p99_max_share_and_mean_inside_the_worst_ticks() -> void:
	var profile := StepProfile.new()
	for k in range(1, 101):
		var first_usec := 2_000 if k == 1 else 1_000
		profile.mark(FIRST, 0)
		profile.mark(SECOND, first_usec)
		profile.finish_tick(k + 1.0)

	var table := profile.table()

	assert_float(table.tick.mean_msec).is_equal_approx(51.5, 0.0001)
	assert_float(table.tick.p99_msec).is_equal_approx(100.0, 0.0001)
	assert_float(table.tick.max_msec).is_equal_approx(101.0, 0.0001)
	assert_float(table.tick.share).is_equal_approx(1.0, 0.0001)
	assert_float(table.tick.worst_mean_msec).is_equal_approx(101.0, 0.0001)
	var first := table.steps[FIRST]
	assert_float(first.mean_msec).is_equal_approx(1.01, 0.0001)
	assert_float(first.max_msec).is_equal_approx(2.0, 0.0001)
	assert_float(first.share).is_equal_approx(0.019612, 0.00001)
	assert_float(first.worst_mean_msec).is_equal_approx(1.0, 0.0001)
	var second := table.steps[SECOND]
	assert_float(second.mean_msec).is_equal_approx(50.49, 0.0001)
	assert_float(second.p99_msec).is_equal_approx(99.0, 0.0001)
	assert_float(second.max_msec).is_equal_approx(100.0, 0.0001)
	assert_float(second.share).is_equal_approx(0.980388, 0.00001)
	assert_float(second.worst_mean_msec).is_equal_approx(100.0, 0.0001)


# Time.get_ticks_usec() passes 2^31 (2,147,483,648) after about 36 minutes up.
func test_a_tick_keeps_its_step_times_across_the_32_bit_microsecond_boundary() -> void:
	var profile := StepProfile.new()
	profile.mark(FIRST, 2_147_483_000)
	profile.mark(SECOND, 2_147_484_000)
	profile.finish_tick(3.0)

	var table := profile.table()

	assert_float(table.steps[FIRST].mean_msec).is_equal_approx(1.0, 0.0001)
	assert_float(table.steps[SECOND].mean_msec).is_equal_approx(2.0, 0.0001)
