extends GdUnitTestSuite


func test_tick_runs_steps_0_to_7_in_order_exactly_once() -> void:
	var sim := Simulation.new()
	var trace: Array[String] = []
	sim.step_observer = func(step: int) -> void: trace.append("step %d" % step)

	sim.tick()

	assert_array(trace).contains_exactly(
		["step 0", "step 1", "step 2", "step 3", "step 4", "step 5", "step 6", "step 7"]
	)


func test_command_queued_before_a_tick_is_drained_at_step_0_of_that_tick() -> void:
	var sim := Simulation.new()
	var trace: Array[String] = []
	sim.step_observer = func(step: int) -> void: trace.append("step %d" % step)

	sim.queue_command(RecordingCommand.new(trace))
	assert_array(trace).is_empty()

	sim.tick()

	var expected: Array[String] = [
		"step 0", "command", "step 1", "step 2", "step 3", "step 4", "step 5", "step 6", "step 7"
	]
	assert_array(trace).contains_exactly(expected)


class RecordingCommand:
	extends Commands.Command

	var _trace: Array[String]

	func _init(trace: Array[String]) -> void:
		_trace = trace

	func apply(_sim: Simulation) -> void:
		_trace.append("command")
