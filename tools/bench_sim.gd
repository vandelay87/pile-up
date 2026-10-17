# Times the tick driver headless with a dense crowd near the base, and checks that two runs
# with the same seed end in the same state. A body drops into the crowd every BODY_INTERVAL ticks,
# about the kill rate of a v1 wave, and every DECAY_INTERVAL ticks the piles decay and the fields
# rebuild on the worker. A branch of pylons runs up the west way to a tower, and every
# PYLON_INTERVAL ticks its first pylon is destroyed (cutting the branch off) or rebuilt, so power is
# recomputed. A wave runs throughout, so two repair yards beside the base send their drones to the
# crowd's ring of towers, which the crowd attacks; every REBUILD_INTERVAL ticks any broken tower or
# yard is built again where it can be. The crowd stalls against the towers until their crushes
# overflow at a surge, so enemies tumble over the ring. Grinders stand in the ring between the
# towers, under the crush, grinding the crowd pressed on them and the tumblers crossing them.
# Every CHAIN_INTERVAL ticks a wall is raised in the crowd and a chain of bloaters set off beside
# it, blowing through the crowd and erasing the wall. BenchCrowd's army of soldiers stands in and
# around the ring, firing into the crowd and fought by it, a group of them is sent across it
# through the crowd every BenchCrowd.ORDER_INTERVAL ticks, and those that die are replaced.
# Exits non-zero when any check fails.
# Run with: godot --headless --script res://tools/bench_sim.gd
extends SceneTree

const RUN_SEED := 1
const CROWD_SEED := 1
const ENEMIES := 1000
const WARMUP_TICKS := 120
const MEASURED_TICKS := 600
const BODY_INTERVAL := 15
const DECAY_INTERVAL := 200
const PYLON_INTERVAL := 100
const REBUILD_INTERVAL := 60
const CHAIN_INTERVAL := 90
# Bloaters in each chain, in a line out from the wall, each in the last one's reach.
const CHAIN_BLOATERS := 5
const CHAIN_SPACING := 1.5
# A late wave: its size keeps it out of the wave tail for the whole run, with a trickle of spawns.
const WAVE := 20
# Two yards beside the base, with the crowd's towers in their repair areas.
const YARDS: Array[Vector2i] = [Vector2i(58, 51), Vector2i(50, 59)]
# A pylon on the base grid's edge, one on that pylon's edge, and a tower beyond it.
const BRANCH_PYLONS: Array[Vector2i] = [Vector2i(48, 44), Vector2i(47, 34)]
const BRANCH_TOWER := Vector2i(38, 25)
# Grinders in the crowd's ring, halfway between its towers.
const GRINDERS := 8
const GRINDER_STEPS_IN := 4
# A backstop only: CI runners differ by about 2x, so the sim-budget job gates on this run against
# its base on the same runner (tools/sim_budget.sh). 39.3 ms (3x a 13.09 ms CI mean) fell inside
# that noise once the bench grew; 80 ms is about 4.6x the M5's 17.4 ms.
const BUDGET_MSEC := 80.0


class RunResult:
	extends RefCounted

	var digest: int
	## Ticks each drone spent repairing, summed over the drones.
	var repair_ticks := 0
	## Ticks with a crush at a surge, and the enemies that started tumbling.
	var surge_ticks := 0
	var tumbles := 0
	## Grinder-ticks spent grinding at least one enemy, summed over the grinders.
	var grinding_ticks := 0
	## Bloaters blown up, and walls the chains erased.
	var blasts := 0
	var walls_erased := 0
	## Soldiers fielded at the start, out of BenchCrowd's army.
	var soldiers := 0
	## Shots the soldiers fired, and enemies they killed.
	var soldier_shots := 0
	var soldier_kills := 0
	## Enemy-ticks spent attacking a soldier, summed over the enemies, and soldiers that died.
	var attack_ticks := 0
	var soldier_deaths := 0
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

	print("Drones spent %d drone-ticks repairing" % first.repair_ticks)
	print("A crush surged for %d ticks; %d enemies tumbled" % [first.surge_ticks, first.tumbles])
	print("Grinders spent %d grinder-ticks grinding" % first.grinding_ticks)
	print("%d bloaters blew up; chains erased %d walls" % [first.blasts, first.walls_erased])
	print("%d of an army of %d soldiers fielded" % [first.soldiers, BenchCrowd.ARMY])
	print("Soldiers fired %d shots and killed %d" % [first.soldier_shots, first.soldier_kills])
	print(
		(
			"Enemies spent %d enemy-ticks attacking soldiers; %d soldiers died"
			% [first.attack_ticks, first.soldier_deaths]
		)
	)

	var failed := false
	if first.repair_ticks == 0:
		printerr("No drone repaired anything")
		failed = true
	if first.surge_ticks == 0 or first.tumbles == 0:
		printerr("No crush overflowed at a surge")
		failed = true
	if first.grinding_ticks == 0:
		printerr("No grinder ground anything")
		failed = true
	if first.walls_erased == 0:
		printerr("No bloater chain erased a wall")
		failed = true
	if first.soldiers != BenchCrowd.ARMY:
		printerr("The army was not all fielded")
		failed = true
	if first.soldier_shots == 0 or first.soldier_kills == 0:
		printerr("No soldier fired and killed")
		failed = true
	if first.attack_ticks == 0:
		printerr("No soldier was attacked")
		failed = true
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
	crowd.field_army()
	var result := RunResult.new()
	result.soldiers = sim.soldiers.count
	var grinders := _build_grinders(sim)
	_build_branch(sim)
	_build_yards(sim)
	sim.queue_command(Commands.JumpToWave.new(WAVE))
	var tumbling: Dictionary[int, bool] = {}
	var chain_wall := Vector2i(-1, -1)
	sim.blasts.connect(
		func(went_off: Array[Blasts.Blast]) -> void: result.blasts += went_off.size()
	)
	# Holding the soldiers rather than the sim keeps the sim free of a reference cycle.
	var soldiers := sim.soldiers
	sim.shots_fired.connect(
		func(shots: Array[Buildings.Shot]) -> void:
			for shot in shots:
				if soldiers.index_of(shot.shooter_id) != Soldiers.NONE:
					result.soldier_shots += 1
	)
	sim.soldiers_died.connect(
		func(deaths: SoldierDeaths) -> void: result.soldier_deaths += deaths.size()
	)
	for t in WARMUP_TICKS + MEASURED_TICKS:
		crowd.top_up(ENEMIES)
		crowd.top_up_army()
		crowd.send_army(t)
		if t % PYLON_INTERVAL == PYLON_INTERVAL - 1:
			_cut_or_relink(sim)
		if t % REBUILD_INTERVAL == REBUILD_INTERVAL - 1:
			_rebuild(sim, crowd, grinders)
		if t % BODY_INTERVAL == 0:
			crowd.drop_body()
		if t % DECAY_INTERVAL == DECAY_INTERVAL - 1:
			sim.decay_piles()
		if t % CHAIN_INTERVAL == 0:
			chain_wall = crowd.raise_wall()
		elif t % CHAIN_INTERVAL == 1 and sim.piles.level(chain_wall) == Piles.WALL_LEVEL:
			_set_off_chain(sim, chain_wall)
		else:
			chain_wall = Vector2i(-1, -1)
		var started := Time.get_ticks_usec()
		sim.tick()
		if t >= WARMUP_TICKS:
			result.tick_msec.append((Time.get_ticks_usec() - started) / 1000.0)
		for drone in sim.repair_yards.drones:
			if drone.state == RepairYards.State.REPAIRING:
				result.repair_ticks += 1
		for building in sim.buildings.built:
			if building.touching > 0:
				result.grinding_ticks += 1
		_count_overflow(sim, result, tumbling)
		for i in sim.enemies.count:
			if sim.enemies.soldier_targets[i] != Enemies.NONE:
				result.attack_ticks += 1
		if t % CHAIN_INTERVAL == 1 and chain_wall.x >= 0 and sim.piles.level(chain_wall) == 0:
			result.walls_erased += 1
	for i in sim.soldiers.count:
		result.soldier_kills += sim.soldiers.kills[i]
	result.digest = hash(
		[
			BenchCrowd.digest(sim),
			sim.power_grid.cells,
			_buildings_digest(sim),
			sim.enemies.tumbling.slice(0, sim.enemies.count),
		]
	)
	return result


# Counts a surge tick and each enemy that started tumbling; [param tumbling] holds the ids
# tumbling at the last count.
func _count_overflow(sim: Simulation, result: RunResult, tumbling: Dictionary[int, bool]) -> void:
	for crush in sim.overflow.crushes():
		if crush.tier == Overflow.Tier.SURGE:
			result.surge_ticks += 1
			break
	var now: Dictionary[int, bool] = {}
	for i in sim.enemies.count:
		if sim.enemies.tumbling[i] == 1:
			now[sim.enemies.ids[i]] = true
			if not tumbling.has(sim.enemies.ids[i]):
				result.tumbles += 1
	tumbling.clear()
	tumbling.merge(now)


# Spawns a line of bloaters out from [param wall] and kills the first, beside the wall: the chain
# runs down the line.
func _set_off_chain(sim: Simulation, wall: Vector2i) -> void:
	var start := Vector2(wall) + Vector2(0.5, 0.5)
	var outwards := (start - Vector2(sim.map.base.get_center())).normalized()
	var first := Enemies.NONE
	for k in CHAIN_BLOATERS:
		var pos := start + outwards * CHAIN_SPACING * (k + 1)
		var cell := Vector2i(pos.floor())
		if not sim.map.in_bounds(cell):
			break
		var id := sim.enemies.spawn(pos, sim.settings.bloater_hp, Enemies.Kind.BLOATER)
		if first == Enemies.NONE:
			first = id
	sim.enemies.kill(first)


func _build_yards(sim: Simulation) -> void:
	sim.add_gold(YARDS.size() * sim.settings.repair_yard_cost)
	for origin in YARDS:
		sim.queue_command(Commands.Build.new(Buildings.REPAIR_YARD, origin))
	sim.tick()
	if sim.repair_yards.drones.size() != YARDS.size():
		printerr("The repair yards were not all built")


# Builds the grinders in the crowd's ring, each stepped in towards the base until it clears rock,
# returning their origins.
func _build_grinders(sim: Simulation) -> Array[Vector2i]:
	var centre := Vector2(sim.map.base.get_center())
	var origins: Array[Vector2i] = []
	sim.add_gold(GRINDERS * sim.buildings.cost_of(Buildings.GRINDER))
	for k in GRINDERS:
		var angle := TAU * (k + 0.5) / GRINDERS
		var origin := Vector2i.ZERO
		for step in GRINDER_STEPS_IN:
			var at := centre + Vector2.from_angle(angle) * (BenchCrowd.TOWER_RADIUS - step)
			origin = Buildings.origin_at(Buildings.GRINDER, at)
			if sim.buildings.can_place(Buildings.GRINDER, origin):
				break
		origins.append(origin)
		sim.queue_command(Commands.Build.new(Buildings.GRINDER, origin))
	sim.tick()
	for origin in origins:
		if sim.occupancy.building_at(origin) == Occupancy.EMPTY:
			printerr("The grinder at %s was not built" % origin)
	return origins


# Queues every broken yard, crowd tower and grinder to be built again; piles may block some.
func _rebuild(sim: Simulation, crowd: BenchCrowd, grinders: Array[Vector2i]) -> void:
	for origin in YARDS:
		_rebuild_at(sim, Buildings.REPAIR_YARD, origin)
	for origin in crowd.tower_origins:
		_rebuild_at(sim, Buildings.TOWER, origin)
	for origin in grinders:
		_rebuild_at(sim, Buildings.GRINDER, origin)


func _rebuild_at(sim: Simulation, kind: StringName, origin: Vector2i) -> void:
	if sim.occupancy.building_at(origin) != Occupancy.EMPTY:
		return
	sim.add_gold(sim.buildings.cost_of(kind))
	sim.queue_command(Commands.Build.new(kind, origin))


func _buildings_digest(sim: Simulation) -> int:
	var state := []
	for building in sim.buildings.built:
		state.append([building.id, building.hp])
	for drone in sim.repair_yards.drones:
		state.append([drone.yard_id, drone.state, drone.position, drone.target_id, drone.repaired])
	return hash(state)


func _build_branch(sim: Simulation) -> void:
	sim.add_gold(BRANCH_PYLONS.size() * sim.settings.pylon_cost + sim.settings.tower_cost)
	for origin in BRANCH_PYLONS:
		sim.queue_command(Commands.Build.new(Buildings.PYLON, origin))
	sim.queue_command(Commands.Build.new(Buildings.TOWER, BRANCH_TOWER))
	sim.tick()
	var tower := sim.buildings.building(sim.occupancy.building_at(BRANCH_TOWER))
	if tower == null or not tower.powered:
		printerr("The pylon branch did not build a powered tower")


# Destroys the branch's first pylon when it stands, or queues it to be built again.
func _cut_or_relink(sim: Simulation) -> void:
	var link := sim.occupancy.building_at(BRANCH_PYLONS[0])
	if link != Occupancy.EMPTY:
		sim.buildings.damage(link, sim.buildings.building(link).hp)
		return
	sim.add_gold(sim.settings.pylon_cost)
	sim.queue_command(Commands.Build.new(Buildings.PYLON, BRANCH_PYLONS[0]))
