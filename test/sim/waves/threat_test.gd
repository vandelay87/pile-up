extends GdUnitTestSuite

# Threat starts at 1 and rises with time (1 point per 1,000 s) and with every mineral mined
# (1 point per 360). It never falls; kills play no part.

const PACES: Array[Miners.Pace] = [Miners.Pace.LOW, Miners.Pace.MEDIUM, Miners.Pace.HIGH]
# Minerals a second at each pace, by the defaults: 3.2 at High, ×0.3 at Low and ×0.5 at Medium.
const RATES := [0.96, 1.6, 3.2]

var _sim: Simulation
var _rejections: Array[String]


func before_test() -> void:
	var rows: Array[String] = []
	for y in 8:
		rows.append("........")
	var map := TestMaps.from_rows(rows, Rect2i(3, 3, 2, 2))
	_sim = Simulation.new(Settings.load_file(Settings.DEFAULTS_PATH).settings, map, 1)
	_rejections = []
	_sim.command_rejected.connect(func(reason: String) -> void: _rejections.append(reason))


func test_a_run_starts_at_threat_1() -> void:
	assert_float(_sim.threat.value).is_equal(1.0)
	assert_int(_sim.threat.whole()).is_equal(1)


func test_at_off_threat_rises_by_time_alone_a_point_every_1000_seconds() -> void:
	_run(600)

	assert_float(_sim.threat.value).is_equal_approx(1.01, 1e-9)

	_run(60000 - 600)

	assert_float(_sim.threat.value).is_equal_approx(2.0, 1e-9)
	assert_int(_sim.threat.whole()).is_equal(2)


func test_each_pace_adds_a_point_of_threat_every_360_minerals_mined() -> void:
	for i in PACES.size():
		before_test()
		_sim.queue_command(Commands.SetPace.new(PACES[i]))
		_run(60)

		var rate: float = RATES[i]
		assert_float(_sim.threat.value).is_equal_approx(1.0 + 0.001 + rate / 360.0, 1e-9)


func test_threat_never_falls_as_the_pace_drops() -> void:
	_sim.queue_command(Commands.SetPace.new(Miners.Pace.HIGH))
	var last := _sim.threat.value
	for tick in 600:
		if tick == 300:
			_sim.queue_command(Commands.SetPace.new(Miners.Pace.OFF))
		_sim.tick()
		assert_float(_sim.threat.value).is_greater(last)
		last = _sim.threat.value


func test_jump_to_threat_sets_the_threat_but_never_lowers_it() -> void:
	_sim.queue_command(Commands.JumpToThreat.new(12.5))
	_sim.tick()

	assert_float(_sim.threat.value).is_equal_approx(12.5 + 0.001 / 60.0, 1e-9)
	assert_int(_sim.threat.whole()).is_equal(12)

	_sim.queue_command(Commands.JumpToThreat.new(3.0))
	_sim.tick()

	assert_float(_sim.threat.value).is_greater(12.5)
	assert_array(_rejections).contains_exactly(["jump to threat: the threat never falls"])


func _run(ticks: int) -> void:
	for tick in ticks:
		_sim.tick()
