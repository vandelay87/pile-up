# Measures the kill rate a strong late-game defence reaches, to judge whether the combo's x2
# and x3 tiers are in reach. For each tower count it packs that many towers on the base's power
# grid, nearest the base first, then plays each late wave from its start to its end and reports
# the most kills in any combo window and the share of the wave spent at x2 and at x3. The window
# is counted here from the kills per tick, independently of the simulation's own combo. The base
# gets the most HP the settings allow so a wave runs to its end; the base HP lost shows how much
# got through. Each wave starts on a fresh map, so no piles from earlier waves shape it.
# Run with: godot --headless --script res://tools/measure_combo.gd
extends SceneTree

const RUN_SEED := 1
# 20 towers already hold the base at wave 18; more test whether firepower raises the kill rate.
const TOWER_COUNTS: Array[int] = [20, 40]
# A mid-run wave for comparison, and the late waves the combo is tuned against.
const WAVES: Array[int] = [10, 15, 18]
# The most base HP the settings allow.
const BASE_HP := 10000
# Far beyond any wave, so no wave can end early by running out of time.
const MAX_TICKS := 60 * 60 * Simulation.TICKS_PER_SECOND


func _init() -> void:
	var settings := Settings.load_file(Settings.DEFAULTS_PATH).settings
	var error := settings.change("run", "base_hp", BASE_HP)
	if not error.is_empty():
		printerr(error)
		quit(1)
		return
	var map := MapData.load_file(settings.map_path).map
	print(
		(
			"Combo window %d ticks; x2 from %d kills, x3 from %d. Spawn rate %s/s."
			% [
				settings.combo_window_ticks,
				settings.combo_tier_2_kills,
				settings.combo_tier_3_kills,
				settings.spawn_rate,
			]
		)
	)
	# Per run: towers placed, the wave, its size, how long it ran, the mean kill rate, the most kills
	# in one window, the share of ticks at x2 and at x3, and the base HP lost.
	print("towers | wave | size | wave s | kills/s | max/window | at x2 | at x3 | base HP lost")
	for towers in TOWER_COUNTS:
		for wave in WAVES:
			_measure(settings, map, towers, wave)
	quit()


func _measure(settings: Settings, map: MapData, towers: int, wave: int) -> void:
	var sim := Simulation.new(settings, map, RUN_SEED)
	var placed := _build_towers(sim, towers)
	sim.queue_command(Commands.JumpToWave.new(wave))
	var window := settings.combo_window_ticks
	var kills_at := PackedInt32Array()
	var in_window := 0
	var most := 0
	# Ticks spent at each tier, indexed by tier.
	var ticks_at := PackedInt32Array()
	ticks_at.resize(settings.combo_cap + 1)
	var start_kills := sim.run_state.kills
	var last_kills := start_kills
	var ticks := 0
	while ticks < MAX_TICKS:
		sim.tick()
		ticks += 1
		var killed := sim.run_state.kills - last_kills
		last_kills = sim.run_state.kills
		kills_at.append(killed)
		in_window += killed
		if kills_at.size() > window:
			in_window -= kills_at[kills_at.size() - 1 - window]
		most = maxi(most, in_window)
		ticks_at[sim.combo_tier] += 1
		if sim.waves.phase == Waves.Phase.BUILD or sim.run_state.is_game_over:
			break
	var seconds := float(ticks) / Simulation.TICKS_PER_SECOND
	print(
		(
			"%6d | %4d | %4d | %6.1f | %7.2f | %10d | %4.0f%% | %4.0f%% | %12d"
			% [
				placed,
				wave,
				sim.waves.size(wave),
				seconds,
				(last_kills - start_kills) / seconds,
				most,
				100.0 * ticks_at[2] / ticks,
				100.0 * ticks_at[3] / ticks,
				settings.base_hp - ceili(sim.run_state.base_hp),
			]
		)
	)


# Packs towers on the base's grid, nearest the base first, so every one is powered.
func _build_towers(sim: Simulation, count: int) -> int:
	sim.queue_command(Commands.AddGold.new(count * sim.buildings.cost_of(Buildings.TOWER)))
	sim.tick()
	var centre := Vector2(sim.map.base.get_center())
	var area := sim.power_grid.base_area()
	var size := Buildings.footprint_size(Buildings.TOWER)
	var origins: Array[Vector2i] = []
	for y in range(area.position.y, area.end.y - size.y + 1):
		for x in range(area.position.x, area.end.x - size.x + 1):
			origins.append(Vector2i(x, y))
	origins.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool:
			return (
				Buildings.centre_of(Buildings.TOWER, a).distance_squared_to(centre)
				< Buildings.centre_of(Buildings.TOWER, b).distance_squared_to(centre)
			)
	)
	var placed := 0
	for origin in origins:
		if placed == count:
			break
		if sim.buildings.can_place(Buildings.TOWER, origin):
			sim.build(Buildings.TOWER, origin)
			placed += 1
	return placed
