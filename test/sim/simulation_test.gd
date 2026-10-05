extends GdUnitTestSuite

const ONE_TICK: Array[String] = [
	"step 0", "step 1", "step 2", "step 3", "step 4", "step 5", "step 6", "step 7"
]

var _sim: Simulation
var _trace: Array[String]


func before_test() -> void:
	_sim = Simulation.new(Settings.from_json("{}", {}).settings)
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


func test_command_queued_during_a_tick_is_drained_at_step_0_of_the_next_tick() -> void:
	var follow_up := RecordingCommand.new(_trace, "follow-up")
	_sim.queue_command(RecordingCommand.new(_trace, "first", follow_up))

	_sim.tick()
	assert_array(_trace).contains_exactly(_one_tick_applying("first"))

	_trace.clear()
	_sim.tick()
	assert_array(_trace).contains_exactly(_one_tick_applying("follow-up"))


func test_rejected_command_is_reported_after_the_last_step_of_the_tick() -> void:
	_sim.command_rejected.connect(func(reason: String) -> void: _trace.append(reason))
	_sim.queue_command(RejectingCommand.new("no"))

	_sim.tick()

	assert_array(_trace).contains_exactly(ONE_TICK + ["no"])


func _one_tick_applying(label: String) -> Array[String]:
	var trace: Array[String] = ONE_TICK.duplicate()
	trace.insert(1, label)
	return trace


class RecordingCommand:
	extends Commands.Command

	var _trace: Array[String]
	var _label: String
	var _follow_up: Commands.Command

	func _init(trace: Array[String], label: String, follow_up: Commands.Command = null) -> void:
		_trace = trace
		_label = label
		_follow_up = follow_up

	func apply(sim: Simulation) -> void:
		_trace.append(_label)
		if _follow_up != null:
			sim.queue_command(_follow_up)


class RejectingCommand:
	extends Commands.Command

	var _reason: String

	func _init(reason: String) -> void:
		_reason = reason

	func apply(sim: Simulation) -> void:
		sim.reject_command(_reason)
