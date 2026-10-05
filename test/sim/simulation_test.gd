extends GdUnitTestSuite

const ONE_TICK: Array[String] = [
	"step 0", "step 1", "step 2", "step 3", "step 4", "step 5", "step 6", "step 7"
]

var _sim: Simulation
var _trace: Array[String]


func before_test() -> void:
	_sim = Simulation.new()
	_trace = []
	_sim.step_observer = func(step: int) -> void: _trace.append("step %d" % step)


func test_tick_runs_steps_0_to_7_in_order_exactly_once() -> void:
	_sim.tick()

	assert_array(_trace).contains_exactly(ONE_TICK)


func test_command_queued_before_a_tick_is_drained_at_step_0_of_that_tick() -> void:
	_sim.queue_command(RecordingCommand.new(_trace, "command"))
	assert_array(_trace).is_empty()

	_sim.tick()

	assert_array(_trace).contains_exactly(_one_tick_applying("command"))


func _one_tick_applying(label: String) -> Array[String]:
	var trace: Array[String] = ONE_TICK.duplicate()
	trace.insert(1, label)
	return trace


class RecordingCommand:
	extends Commands.Command

	var _trace: Array[String]
	var _label: String

	func _init(trace: Array[String], label: String) -> void:
		_trace = trace
		_label = label

	func apply(_sim: Simulation) -> void:
		_trace.append(_label)
