extends GdUnitTestSuite


func test_a_frame_splits_into_its_tick_process_render_and_the_rest() -> void:
	var profile := FrameProfile.new()
	profile.add_frame(16.0, 9.0, 2.0, 4.5, 1.5)

	var table := profile.table()

	assert_float(table.frame.mean_msec).is_equal_approx(16.0, 0.0001)
	assert_float(table.tick.mean_msec).is_equal_approx(9.0, 0.0001)
	assert_float(table.process.mean_msec).is_equal_approx(2.0, 0.0001)
	assert_float(table.render.mean_msec).is_equal_approx(4.5, 0.0001)
	assert_float(table.frame_setup.mean_msec).is_equal_approx(1.5, 0.0001)
	assert_float(table.other.mean_msec).is_equal_approx(0.5, 0.0001)


# Frames k = 1..100 take k + 1 ms, process for 0.25 ms and render for 0.5 ms, 0.1 ms of it frame
# setup. The fastest frame ticks for 1.25 ms and the rest for 1 ms, so the rest of each frame is
# what is left: 0 ms in the fastest, k - 0.75 ms in the others.
func test_each_part_reports_its_p99_max_share_and_mean_inside_the_worst_frames() -> void:
	var profile := FrameProfile.new()
	for k in range(1, 101):
		profile.add_frame(k + 1.0, 1.25 if k == 1 else 1.0, 0.25, 0.5, 0.1)

	var table := profile.table()

	assert_float(table.frame.mean_msec).is_equal_approx(51.5, 0.0001)
	assert_float(table.frame.p99_msec).is_equal_approx(100.0, 0.0001)
	assert_float(table.frame.max_msec).is_equal_approx(101.0, 0.0001)
	assert_float(table.frame.share).is_equal_approx(1.0, 0.0001)
	assert_float(table.frame.worst_mean_msec).is_equal_approx(101.0, 0.0001)
	assert_float(table.tick.mean_msec).is_equal_approx(1.0025, 0.0001)
	assert_float(table.tick.p99_msec).is_equal_approx(1.0, 0.0001)
	assert_float(table.tick.max_msec).is_equal_approx(1.25, 0.0001)
	assert_float(table.tick.share).is_equal_approx(0.019466, 0.00001)
	assert_float(table.tick.worst_mean_msec).is_equal_approx(1.0, 0.0001)
	assert_float(table.process.share).is_equal_approx(0.004854, 0.00001)
	assert_float(table.render.share).is_equal_approx(0.009709, 0.00001)
	assert_float(table.frame_setup.share).is_equal_approx(0.001942, 0.00001)
	assert_float(table.other.mean_msec).is_equal_approx(49.7475, 0.0001)
	assert_float(table.other.p99_msec).is_equal_approx(98.25, 0.0001)
	assert_float(table.other.max_msec).is_equal_approx(99.25, 0.0001)
	assert_float(table.other.share).is_equal_approx(0.965971, 0.00001)
	assert_float(table.other.worst_mean_msec).is_equal_approx(99.25, 0.0001)
