# Times the tick driver headless with a dense crowd near the base, and checks that two runs
# with the same seed end in the same state. A body drops into the crowd every BODY_INTERVAL ticks,
# about the kill rate of a v1 wave, and every DECAY_INTERVAL ticks the piles decay and the fields
# rebuild on the worker. The rebuild is waited for outside the
# timed region so it swaps in on the next tick in both runs. Exits non-zero when either check
# fails.
# Run with: godot --headless --script res://tools/bench_sim.gd
extends SceneTree

const RUN_SEED := 1
const CROWD_SEED := 1
const ENEMIES := 1000
const WARMUP_TICKS := 120
const MEASURED_TICKS := 600
const BODY_INTERVAL := 15
const DECAY_INTERVAL := 200
# 3x the 13.09 ms CI mean in https://github.com/vandelay87/pile-up/actions/runs/37919291329
const BUDGET_MSEC := 39.3


class RunResult:
	extends RefCounted

	var digest: int
	var tick_msec := PackedFloat64Array()


func _init() -> void:
	var settings := Settings.load_file(Settings.DEFAULTS_PATH).settings
	var map := MapData.load_file(settings.map_path).map
	var first := _run(settings, map)
	var second := _run(settings, map)

	var mean := 0.0
	var worst := 0.0
	for msec in first.tick_msec:
		mean += msec
		worst = maxf(worst, msec)
	mean /= first.tick_msec.size()
	print(
		(
			"Simulation budget: %d enemies, %d ticks after %d warm-up"
			% [ENEMIES, MEASURED_TICKS, WARMUP_TICKS]
		)
	)
	print("Tick mean %.2f ms, max %.2f ms (budget %.2f ms mean)" % [mean, worst, BUDGET_MSEC])

	var failed := false
	if first.digest != second.digest:
		printerr("Two runs with the same seed ended in different states")
		failed = true
	if mean > BUDGET_MSEC:
		printerr("Mean tick cost %.2f ms is over the %.2f ms budget" % [mean, BUDGET_MSEC])
		failed = true
	quit(1 if failed else 0)


func _run(settings: Settings, map: MapData) -> RunResult:
	var sim := Simulation.new(settings, map, RUN_SEED)
	var crowd := BenchCrowd.new(sim, CROWD_SEED)
	var result := RunResult.new()
	for t in WARMUP_TICKS + MEASURED_TICKS:
		crowd.top_up(ENEMIES)
		if t % BODY_INTERVAL == 0:
			crowd.drop_body()
		var decay_usec := 0
		if t % DECAY_INTERVAL == DECAY_INTERVAL - 1:
			var decay_started := Time.get_ticks_usec()
			sim.piles.decay()
			sim.routing.start_rebuild()
			decay_usec = Time.get_ticks_usec() - decay_started
			sim.routing.wait_for_rebuild()
		var started := Time.get_ticks_usec()
		sim.tick()
		if t >= WARMUP_TICKS:
			result.tick_msec.append((Time.get_ticks_usec() - started + decay_usec) / 1000.0)
	result.digest = BenchCrowd.digest(sim)
	return result
