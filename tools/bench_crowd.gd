# Keeps a dense crowd of enemies in a ring around the base for the benchmarks.
class_name BenchCrowd
extends RefCounted

const INNER_RADIUS := 6.0
const OUTER_RADIUS := 14.0

var _sim: Simulation
var _rng := RandomNumberGenerator.new()
var _centre: Vector2


func _init(sim: Simulation, crowd_seed: int) -> void:
	_sim = sim
	_rng.seed = crowd_seed
	_centre = Vector2(sim.map.base.get_center())


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
		_sim.enemies.spawn(_free_spot())


func _free_spot() -> Vector2:
	while true:
		var angle := _rng.randf_range(0.0, TAU)
		var radius := _rng.randf_range(INNER_RADIUS, OUTER_RADIUS)
		var pos := _centre + Vector2.from_angle(angle) * radius
		var cell := Vector2i(pos.floor())
		if _sim.map.in_bounds(cell) and not _sim.map.is_rock(cell) and not _sim.map.is_base(cell):
			return pos
	return _centre
