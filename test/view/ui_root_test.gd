extends GdUnitTestSuite


func test_the_reference_size_has_scale_one() -> void:
	assert_float(UiRoot.scale_for(UiRoot.REFERENCE_SIZE)).is_equal(1.0)


func test_the_scale_fits_the_tighter_axis() -> void:
	assert_float(UiRoot.scale_for(Vector2(1728.0, 1296.0))).is_equal(1.5)


func test_a_large_window_is_capped() -> void:
	assert_float(UiRoot.scale_for(Vector2(3024.0, 1964.0))).is_equal(UiRoot.MAX_SCALE)


func test_a_small_window_is_floored() -> void:
	assert_float(UiRoot.scale_for(Vector2(200.0, 100.0))).is_equal(UiRoot.MIN_SCALE)
