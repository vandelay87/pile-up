# Spike for "Routing to more than one target: what it costs". Throwaway.
# Run with: godot --headless --path . --script res://spikes/routing_targets.gd (from the repo root).
# Never merged; linked from the ticket "Routing to more than one target: what it costs" (#268).
# Runs bench_settle's heavy wave (1,000 enemies, a body every tick, a tower every 60 ticks) and,
# beside the sim's own Routing (the base), K extra Routing instances each seeded from a 4x4 target
# elsewhere on the map, fed the same changed cells. Times their update + step per tick, the ticks
# they take to settle, and full builds; and a single field seeded from all targets at once.
extends SceneTree

const ENEMIES := 1000
const MEASURED_TICKS := 600
const TOWER_INTERVAL := 60
const TOWER_RADIUS := 17.0
const TARGET_SIZE := Vector2i(4, 4)

var _sim: Simulation


func _init() -> void:
	var settings := Settings.load_file(Settings.DEFAULTS_PATH).settings
	settings.change("run", "base_power_area", 20)
	var map := MapData.load_file(settings.map_path).map
	print("Map %dx%d = %d cells" % [map.width, map.height, map.width * map.height])
	_sim = Simulation.new(settings, map, 1)
	var targets := _pick_targets(map, 8)
	print("Targets: %s" % [targets])

	_time_full_builds(map, targets)
	_time_big_map_builds()

	for k: int in [1, 2, 4, 8]:
		_sim = Simulation.new(settings, map, 1)
		_run_wave(settings, map, targets.slice(0, k))
	quit()


func _pick_targets(map: MapData, count: int) -> Array[Rect2i]:
	# Open, reachable 4x4 spots at least 12 cells from the base, spread by farthest-point
	# sampling (the base counts as already chosen), like outposts on deposits.
	var candidates: Array[Rect2i] = []
	var centre := Vector2(map.base.get_center())
	for y in range(0, map.height - TARGET_SIZE.y, 2):
		for x in range(0, map.width - TARGET_SIZE.x, 2):
			var rect := Rect2i(Vector2i(x, y), TARGET_SIZE)
			if not _open(map, rect) or Vector2(rect.get_center()).distance_to(centre) < 12.0:
				continue
			if _sim.routing.value(Routing.Route.SENSIBLE, rect.position) == Routing.UNREACHABLE:
				continue
			candidates.append(rect)
	var chosen: Array[Vector2] = [centre]
	var targets: Array[Rect2i] = []
	for i in count:
		var best := candidates[0]
		var best_distance := -1.0
		for rect in candidates:
			var nearest := INF
			for c in chosen:
				nearest = minf(nearest, Vector2(rect.get_center()).distance_to(c))
			if nearest > best_distance:
				best_distance = nearest
				best = rect
		targets.append(best)
		chosen.append(Vector2(best.get_center()))
	return targets


func _open(map: MapData, rect: Rect2i) -> bool:
	if not Rect2i(0, 0, map.width, map.height).encloses(rect):
		return false
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if map.rock[y * map.width + x] == 1:
				return false
	return true


func _map_with_base(map: MapData, rect: Rect2i) -> MapData:
	return MapData.new(map.width, map.height, map.rock, rect, map.spawn_edges, map.no_build)


func _routing_for(map: MapData, rect: Rect2i) -> Routing:
	return Routing.new(_sim.settings, _map_with_base(map, rect), _sim.occupancy, _sim.piles, _sim.structures)


func _time_full_builds(map: MapData, targets: Array[Rect2i]) -> void:
	var samples := PackedFloat64Array()
	for i in 10:
		var routing := _routing_for(map, targets[i % targets.size()])
		samples.append(routing.last_rebuild_msec)
	samples.sort()
	print("Full build of one target's 2 fields (current map), median of 10: %.2f ms" % samples[5])
	# One field seeded from the base and all 8 targets: nearest wins.
	var factors: PackedFloat64Array = _sim.routing._factors[Routing.Route.SENSIBLE]
	var solid: PackedByteArray = _sim.routing._solid
	var seeds: Array[Vector2i] = map.base_cells()
	for rect in targets:
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				seeds.append(Vector2i(x, y))
	var one := PackedFloat64Array()
	var multi := PackedFloat64Array()
	for i in 10:
		one.append(_time_seeded(map, factors, solid, map.base_cells()))
		multi.append(_time_seeded(map, factors, solid, seeds))
	one.sort()
	multi.sort()
	print("One field, base seeds only: %.2f ms; base + 8 targets as seeds: %.2f ms" % [one[5], multi[5]])


func _time_seeded(
	map: MapData, factors: PackedFloat64Array, solid: PackedByteArray, seeds: Array[Vector2i]
) -> float:
	var started := Time.get_ticks_usec()
	var count := map.width * map.height
	var field := Routing.Field.new()
	field.values.resize(count)
	field.values.fill(Routing.UNREACHABLE)
	field.parents.resize(count)
	field.parents.fill(-1)
	field.parent_offsets.resize(count)
	field.parent_offsets.fill(8)
	field.directions.resize(count)
	var heap := Routing._Heap.new(count)
	for cell in seeds:
		var index := map.index_of(cell)
		field.values[index] = 0.0
		heap.push(0.0, index)
	Routing._settle(map.width, map.height, factors, solid, field, heap, PackedInt32Array(), -1)
	for cell in count:
		field.directions[cell] = Routing._directions[field.parent_offsets[cell]]
	return (Time.get_ticks_usec() - started) / 1000.0


func _time_big_map_builds() -> void:
	for side: Vector2i in [Vector2i(112, 76), Vector2i(160, 110), Vector2i(224, 152)]:
		var count := side.x * side.y
		var rock := PackedByteArray()
		rock.resize(count)
		var no_build := PackedByteArray()
		no_build.resize(count)
		var factors := PackedFloat64Array()
		factors.resize(count)
		factors.fill(1.0)
		var solid := PackedByteArray()
		solid.resize(count)
		var base := Rect2i(side / 2 - Vector2i(2, 2), Vector2i(4, 4))
		var map := MapData.new(side.x, side.y, rock, base, PackedStringArray(["N"]), no_build)
		var samples := PackedFloat64Array()
		for i in 5:
			samples.append(_time_seeded(map, factors, solid, map.base_cells()))
		samples.sort()
		print("Open %dx%d (%d cells): one field %.2f ms" % [side.x, side.y, count, samples[2]])


func _run_wave(settings: Settings, map: MapData, targets: Array[Rect2i]) -> void:
	var extras: Array[Routing] = []
	for rect in targets:
		extras.append(_routing_for(map, rect))
	var crowd := BenchCrowd.new(_sim, 1)
	# Catch the extras up with the crowd's towers.
	for routing in extras:
		routing.rebuild()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var centre := Vector2(map.base.get_center())
	var base_msec := PackedFloat64Array()
	var extra_msec := PackedFloat64Array()
	var extra_cells := PackedFloat64Array()
	var settle_runs := PackedFloat64Array()
	var settle_started := -1
	var base_settle_runs := PackedFloat64Array()
	var base_started := -1
	for t in MEASURED_TICKS:
		crowd.top_up(ENEMIES)
		crowd.drop_body()
		if t % TOWER_INTERVAL == 0:
			_sim.add_gold(settings.tower_cost)
			_sim.queue_command(Commands.Build.new(Buildings.TOWER, _tower_spot(centre, rng)))
		var routing := _sim.routing
		var factors_before: Array = [
			routing._factors[0].duplicate(), routing._factors[1].duplicate(), routing._solid.duplicate()
		]
		_sim.tick()
		base_msec.append(routing.last_update_msec + routing.last_step_msec)
		if routing.is_settling() and base_started < 0:
			base_started = t
		elif not routing.is_settling() and base_started >= 0:
			base_settle_runs.append(t - base_started)
			base_started = -1
		var cells: Array[Vector2i] = []
		var after: Array = [routing._factors[0], routing._factors[1], routing._solid]
		for index in map.width * map.height:
			if (
				factors_before[0][index] != after[0][index]
				or factors_before[1][index] != after[1][index]
				or factors_before[2][index] != after[2][index]
			):
				cells.append(map.cell_of(index))
		var tick_msec := 0.0
		var tick_cells := 0
		var settling := false
		for extra in extras:
			var started := Time.get_ticks_usec()
			if not cells.is_empty():
				extra.update(cells)
			extra.step()
			tick_msec += (Time.get_ticks_usec() - started) / 1000.0
			tick_cells += extra.last_step_cells
			settling = settling or extra.is_settling()
		extra_msec.append(tick_msec)
		extra_cells.append(tick_cells)
		if settling and settle_started < 0:
			settle_started = t
		elif not settling and settle_started >= 0:
			settle_runs.append(t - settle_started)
			settle_started = -1
	print("")
	print("K = %d extra targets, %d ticks of heavy wave" % [targets.size(), MEASURED_TICKS])
	print("  Base fields (today): %s" % _stats(base_msec))
	print("  Extra fields, all K: %s" % _stats(extra_msec))
	print("  Extra cells worked per tick: %s" % _stats(extra_cells, ""))
	print("  Base settle run length (ticks): %s" % _stats(base_settle_runs, ""))
	print("  Extras settle run length (ticks, until all K settled): %s" % _stats(settle_runs, ""))


func _stats(samples: PackedFloat64Array, unit := " ms") -> String:
	if samples.is_empty():
		return "none"
	var sorted := samples.duplicate()
	sorted.sort()
	var total := 0.0
	for s: float in sorted:
		total += s
	return (
		"mean %.2f%s, median %.2f%s, p95 %.2f%s, worst %.2f%s (n=%d)"
		% [
			total / sorted.size(), unit,
			sorted[sorted.size() / 2], unit,
			sorted[maxi(ceili(sorted.size() * 0.95) - 1, 0)], unit,
			sorted[-1], unit, sorted.size()
		]
	)


func _tower_spot(centre: Vector2, rng: RandomNumberGenerator) -> Vector2i:
	var origin := Vector2i.ZERO
	for attempt in 100:
		var spot := centre + Vector2.from_angle(rng.randf() * TAU) * TOWER_RADIUS
		origin = Buildings.origin_at(Buildings.TOWER, spot)
		if _sim.buildings.can_place(Buildings.TOWER, origin):
			break
	return origin
