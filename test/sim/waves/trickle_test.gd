extends GdUnitTestSuite

# The trickle: normal enemies alone from any spawn edge, one every 2.5 s at threat 1 and ×1.05 as
# often a point of threat, at every pace and in a wave alike. They belong to no wave.

const EDGES: Array[String] = ["N", "E", "S", "W"]

var _sim: Simulation
var _spawned := {}


func before_test() -> void:
	var settings := Settings.load_file(Settings.DEFAULTS_PATH).settings
	var rows: Array[String] = []
	for y in 16:
		rows.append("................")
	_sim = Simulation.new(settings, TestMaps.from_rows(rows, Rect2i(7, 7, 2, 2), EDGES), 1)
	_spawned = {}


func test_at_off_the_trickle_sends_a_normal_enemy_every_2_5_seconds_from_any_edge() -> void:
	var cells := {}
	for edge in EDGES:
		for cell in _sim.map.spawn_cells(edge):
			cells[cell] = edge
	var edges_seen := {}

	for tick in 150 * 40:
		_sim.tick()
		for i in _sim.enemies.count:
			var id := _sim.enemies.ids[i]
			if _spawned.has(id):
				continue
			if _spawned.is_empty():
				assert_int(tick).is_equal(149)
			_spawned[id] = true
			assert_int(_sim.enemies.kinds[i]).is_equal(Enemies.Kind.NORMAL)
			assert_int(_sim.enemies.waves[i]).is_equal(Waves.NO_WAVE)
			var cell := Vector2i(_sim.enemies.positions[i].floor())
			edges_seen[cells.get(cell, "")] = true
		_kill_all()

	# Threat rises by time alone at Off, so the gaps shorten a little: 40.1 over the 100 s.
	assert_int(_spawned.size()).is_equal(40)
	assert_array(edges_seen.keys()).contains_exactly_in_any_order(EDGES)


func test_the_trickle_grows_by_5_percent_a_point_of_threat() -> void:
	_sim.queue_command(Commands.JumpToThreat.new(11.0))

	for tick in 100 * Simulation.TICKS_PER_SECOND:
		_sim.tick()
		_count_new()
		_kill_all()

	# 0.4 × 1.05^10 = 0.652 a second over 100 s, a little more as time adds threat.
	assert_int(_spawned.size()).is_equal(65)


func test_the_trickle_keeps_coming_in_a_wave_and_counts_towards_none() -> void:
	_sim.settings.change("waves", "size_roll", 0)
	_sim.queue_command(Commands.SendWave.new())
	_sim.tick()
	var size := _sim.waves.open_size
	for tick in 149:
		_sim.tick()

	var trickle: Array[int] = []
	for i in _sim.enemies.count:
		if _sim.enemies.waves[i] == Waves.NO_WAVE:
			trickle.append(_sim.enemies.ids[i])
	assert_int(trickle.size()).is_equal(1)
	var left := _sim.waves.enemies_left
	_sim.enemies.kill(trickle[0])
	_sim.tick()

	assert_int(_sim.waves.enemies_left).is_equal(left)
	assert_int(_sim.waves.open_size).is_equal(size)


func test_trickle_enemies_always_push_through_as_in_the_wave_tail() -> void:
	assert_int(_sim.waves.tail_mask()[0]).is_equal(1)


func _count_new() -> void:
	for i in _sim.enemies.count:
		_spawned[_sim.enemies.ids[i]] = true


func _kill_all() -> void:
	for i in _sim.enemies.count:
		_sim.enemies.kill(_sim.enemies.ids[i])
