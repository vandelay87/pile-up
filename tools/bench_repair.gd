# Times the incremental field updates headless under a heavy wave: a dense crowd near the base,
# with a body landing in it every tick, four times the v1 kill rate bench_sim uses, and a tower
# built just outside the crowd every TOWER_INTERVAL ticks. Walls form in the crowd and its attacks
# change their HP buckets and break them.
# Run with: godot --headless --script res://tools/bench_repair.gd
extends SceneTree

const RUN_SEED := 1
const CROWD_SEED := 1
const TOWER_SEED := 1
const ENEMIES := 1000
const MEASURED_TICKS := 600
const TOWER_INTERVAL := 60
const TOWER_RADIUS := 17.0

var _sim: Simulation
var _landed := false
var _tower_built := false
var _wall_hit := false
var _levels_before := PackedByteArray()
var _landing_msec := PackedFloat64Array()
var _tower_msec := PackedFloat64Array()
var _wall_msec := PackedFloat64Array()


func _init() -> void:
	var settings := Settings.load_file(Settings.DEFAULTS_PATH).settings
	var map := MapData.load_file(settings.map_path).map
	_sim = Simulation.new(settings, map, RUN_SEED)
	var crowd := BenchCrowd.new(_sim, CROWD_SEED)
	var rng := RandomNumberGenerator.new()
	rng.seed = TOWER_SEED
	var centre := Vector2(map.base.get_center())
	_sim.pile_changed.connect(_on_pile_changed)
	_sim.building_placed.connect(func(_id: int) -> void: _tower_built = true)
	for t in MEASURED_TICKS:
		crowd.top_up(ENEMIES)
		crowd.drop_body()
		if t % TOWER_INTERVAL == 0:
			var spot := centre + Vector2.from_angle(rng.randf() * TAU) * TOWER_RADIUS
			_sim.add_gold(settings.tower_cost)
			_sim.queue_command(
				Commands.Build.new(Buildings.TOWER, Buildings.origin_at(Buildings.TOWER, spot))
			)
		var wall_update := _wall_hit
		_landed = false
		_tower_built = false
		_wall_hit = false
		_levels_before = _sim.piles.levels.duplicate()
		_sim.tick()
		if _tower_built:
			_tower_msec.append(_sim.routing.last_update_msec)
		elif wall_update:
			_wall_msec.append(_sim.routing.last_update_msec)
		elif _landed:
			_landing_msec.append(_sim.routing.last_update_msec)

	print(
		(
			"Field repair under a heavy wave: %d enemies, a body every tick for %d ticks"
			% [ENEMIES, MEASURED_TICKS]
		)
	)
	print("Full rebuild of both fields at load: %.2f ms" % _sim.routing.last_rebuild_msec)
	print("")
	print("| Tick | Updates | Median | p95 | Worst |")
	print("|---|---|---|---|---|")
	print(_row("Bodies landed", _landing_msec))
	print(_row("Tower built", _tower_msec))
	print(_row("Wall hit or broken", _wall_msec))
	quit()


func _on_pile_changed(cells: Array[Vector2i]) -> void:
	for cell in cells:
		if _levels_before[cell.y * _sim.map.width + cell.x] == Piles.WALL_LEVEL:
			_wall_hit = true
		else:
			_landed = true


func _row(label: String, samples: PackedFloat64Array) -> String:
	if samples.is_empty():
		return "| %s | 0 | - | - | - |" % label
	var sorted := samples.duplicate()
	sorted.sort()
	var values := [
		label,
		sorted.size(),
		_percentile(sorted, 0.5),
		_percentile(sorted, 0.95),
		sorted[-1],
	]
	return "| %s | %d | %.2f ms | %.2f ms | %.2f ms |" % values


func _percentile(sorted: PackedFloat64Array, fraction: float) -> float:
	return sorted[maxi(ceili(sorted.size() * fraction) - 1, 0)]
