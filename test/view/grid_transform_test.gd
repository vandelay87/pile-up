extends GdUnitTestSuite


func _layer() -> TileMapLayer:
	var layer: TileMapLayer = auto_free(TileMapLayer.new())
	layer.tile_set = Atlas.make_tile_set()
	return layer


func test_cell_centres_match_map_to_local() -> void:
	var layer := _layer()

	for y in range(-20, 20):
		for x in range(-20, 20):
			var cell := Vector2i(x, y)
			assert_vector(GridTransform.cell_to_world(cell)).is_equal(layer.map_to_local(cell))


func test_flooring_the_inverse_matches_local_to_map() -> void:
	var layer := _layer()
	var rng := RandomNumberGenerator.new()
	rng.seed = 21

	for i in 5000:
		var point := Vector2(rng.randf_range(-1500.0, 1500.0), rng.randf_range(-800.0, 800.0))
		assert_vector(GridTransform.world_to_cell(point)).is_equal(layer.local_to_map(point))


func test_grid_positions_round_trip_through_world_space() -> void:
	var position := Vector2(12.25, 40.75)

	var world := GridTransform.grid_to_world(position)

	assert_vector(GridTransform.world_to_grid(world)).is_equal_approx(position, Vector2(1e-4, 1e-4))
