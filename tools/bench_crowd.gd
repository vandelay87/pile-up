# Keeps a dense crowd of enemies in a ring around the base, with a ring of towers firing into it,
# for the benchmarks.
class_name BenchCrowd
extends RefCounted

const INNER_RADIUS := 6.0
const OUTER_RADIUS := 14.0
const LIVES := 1_000_000
const TOWERS := 8
const TOWER_RADIUS := 10.0

var _sim: Simulation
var _rng := RandomNumberGenerator.new()
var _centre: Vector2


func _init(sim: Simulation, crowd_seed: int) -> void:
	_sim = sim
	_sim.run_state.lives = LIVES
	_rng.seed = crowd_seed
	_centre = Vector2(sim.map.base.get_center())
	_sim.run_state.add_gold(TOWERS * _sim.settings.tower_cost)
	for k in TOWERS:
		var centre := _centre + Vector2.from_angle(TAU * k / TOWERS) * TOWER_RADIUS
		_sim.queue_command(Commands.BuildTower.new(Towers.origin_at(centre)))
	_sim.tick()


static func digest(sim: Simulation) -> int:
	var enemies := sim.enemies
	return hash(
		[
			enemies.count,
			enemies.ids.slice(0, enemies.count),
			enemies.positions.slice(0, enemies.count),
			enemies.hp.slice(0, enemies.count),
		]
	)


func top_up(target: int) -> void:
	while _sim.enemies.count < target:
		_sim.enemies.spawn(_free_spot(), _sim.settings.enemy_hp)


func _free_spot() -> Vector2:
	while true:
		var angle := _rng.randf_range(0.0, TAU)
		var radius := _rng.randf_range(INNER_RADIUS, OUTER_RADIUS)
		var pos := _centre + Vector2.from_angle(angle) * radius
		var cell := Vector2i(pos.floor())
		if _sim.map.in_bounds(cell) and not _sim.map.is_rock(cell) and not _sim.map.is_base(cell):
			return pos
	return _centre
