# Times the incremental field updates headless under a heavy wave: a dense crowd near the base,
# with a body landing in it every tick, four times the v1 kill rate bench_sim uses.
# Run with: godot --headless --script res://tools/bench_repair.gd
extends SceneTree

const RUN_SEED := 1
const CROWD_SEED := 1
const ENEMIES := 1000
const MEASURED_TICKS := 600

var _sim: Simulation
var _repair_msec := PackedFloat64Array()


func _init() -> void:
	var settings := Settings.load_file(Settings.DEFAULTS_PATH).settings
	var map := MapData.load_file(settings.map_path).map
	_sim = Simulation.new(settings, map, RUN_SEED)
	var crowd := BenchCrowd.new(_sim, CROWD_SEED)
	_sim.pile_changed.connect(_record_repair)
	for t in MEASURED_TICKS:
		crowd.top_up(ENEMIES)
		crowd.drop_body()
		_sim.tick()

	_repair_msec.sort()
	print(
		(
			"Field repair under a heavy wave: %d enemies, a body every tick for %d ticks"
			% [ENEMIES, MEASURED_TICKS]
		)
	)
	print("Full rebuild of both fields at load: %.2f ms" % _sim.routing.last_rebuild_msec)
	print("")
	print("| Updates | Median | p95 | Worst |")
	print("|---|---|---|---|")
	print(
		(
			"| %d | %.2f ms | %.2f ms | %.2f ms |"
			% [
				_repair_msec.size(),
				_percentile(0.5),
				_percentile(0.95),
				_percentile(1.0),
			]
		)
	)
	quit()


func _record_repair(_cells: Array[Vector2i]) -> void:
	_repair_msec.append(_sim.routing.last_update_msec)


func _percentile(fraction: float) -> float:
	return _repair_msec[maxi(ceili(_repair_msec.size() * fraction) - 1, 0)]
