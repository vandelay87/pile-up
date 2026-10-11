extends GdUnitTestSuite

const CROWD := 120
# The crowd reaches the base about 8 s in and packs against it over the next 8 s.
const ARRIVAL_TICKS := 8 * Simulation.TICKS_PER_SECOND
const PACKING_TICKS := 8 * Simulation.TICKS_PER_SECOND
# Below this an enemy is standing still, not stepping back and forth.
const STILL := 1e-4
# A jittering crowd turns back on about half its steps; a settling one on a few in a hundred.
const MAX_REVERSAL_SHARE := 0.1
# Enough steps that the share means something: a tenth of the enemy-ticks.
const MIN_STEPS := CROWD * PACKING_TICKS / 10
# Walkers start attacking as they arrive, but attackers squeezed off their targets flip between
# attacking and walking every few ticks, hundreds of times over the packing.
const MAX_ATTACK_FLIPS := 40
const MIN_ATTACKERS := 10

var _settings: Settings


# The defaults, swarm spread included: the jitter showed in real crowds.
func before_test() -> void:
	_settings = Settings.load_file(Settings.DEFAULTS_PATH).settings
	_settings.change("run", "base_hp", 10000)


func test_a_crowd_packing_against_the_base_settles_instead_of_jittering() -> void:
	var sim := _crowd_sim()
	for tick in ARRIVAL_TICKS:
		sim.tick()
	var last := sim.enemies.positions.duplicate()
	var last_steps := PackedVector2Array()
	last_steps.resize(CROWD)
	var steps := 0
	var reversals := 0
	var was_attacking := _attacking(sim)
	var attack_flips := 0

	for tick in PACKING_TICKS:
		sim.tick()
		for i in CROWD:
			var moved := sim.enemies.positions[i] - last[i]
			var before := last_steps[i]
			if moved.length() > STILL and before.length() > STILL:
				steps += 1
				if moved.dot(before) < 0.0:
					reversals += 1
			last_steps[i] = moved
			last[i] = sim.enemies.positions[i]
		var attacking := _attacking(sim)
		for i in CROWD:
			if attacking[i] != was_attacking[i]:
				attack_flips += 1
		was_attacking = attacking

	assert_int(steps).is_greater(MIN_STEPS)
	assert_float(float(reversals) / maxi(steps, 1)).is_less(MAX_REVERSAL_SHARE)
	assert_int(attack_flips).is_less(MAX_ATTACK_FLIPS)
	assert_int(_attacking(sim).count(true)).is_greater(MIN_ATTACKERS)


func _attacking(sim: Simulation) -> Array[bool]:
	var attacking: Array[bool] = []
	for i in CROWD:
		attacking.append(sim.enemies.structure_targets[i] != Enemies.NONE)
	return attacking


# An open field with the base at the east edge and a seeded crowd scattered in the west.
func _crowd_sim() -> Simulation:
	var rows: Array[String] = []
	for y in 16:
		rows.append("................................")
	var sim := Simulation.new(_settings, TestMaps.from_rows(rows, Rect2i(28, 6, 4, 4)), 1)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for n in CROWD:
		var pos := Vector2(rng.randf_range(2.0, 14.0), rng.randf_range(2.0, 14.0))
		sim.enemies.spawn(pos, _settings.enemy_hp)
	return sim
