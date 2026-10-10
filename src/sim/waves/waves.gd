class_name Waves
extends RefCounted

enum Phase { BUILD, WAVE }

const SPAWN_JITTER := 0.25

var phase := Phase.BUILD
var edges := PackedStringArray()

var _settings: Settings
var _map: MapData
var _enemies: Enemies
var _rng: RandomNumberGenerator
var _hp := 0.0
var _spawned := 0
var _size := 0
var _spawn_budget := 0.0


func _init(
	run_settings: Settings, run_map: MapData, run_enemies: Enemies, rng: RandomNumberGenerator
) -> void:
	_settings = run_settings
	_map = run_map
	_enemies = run_enemies
	_rng = rng


func size(wave: int) -> int:
	return roundi(_settings.wave_1_size * pow(_settings.wave_growth, wave - 1))


func enemy_hp(wave: int) -> float:
	return _settings.enemy_hp * pow(_settings.hp_growth, wave - 1)


func start(wave: int) -> void:
	phase = Phase.WAVE
	edges = _pick_edges()
	_size = size(wave)
	_hp = enemy_hp(wave)
	_spawned = 0
	_spawn_budget = Simulation.TICKS_PER_SECOND * _settings.clump_size


# Enemies arrive in bursts of clump_size, each on a random cell of the burst's edge.
# A burst costs clump_size seconds of spawn rate, so the average rate holds.
func spawn() -> void:
	if phase != Phase.WAVE:
		return
	var clump := _settings.clump_size
	var burst_cost := Simulation.TICKS_PER_SECOND * clump
	while _spawned < _size and _spawn_budget >= burst_cost:
		_spawn_budget -= burst_cost
		var cells := _map.spawn_cells(edges[(_spawned / clump) % edges.size()])
		for _k in mini(clump, _size - _spawned):
			var cell := cells[_rng.randi_range(0, cells.size() - 1)]
			var jitter := Vector2(
				_rng.randf_range(-SPAWN_JITTER, SPAWN_JITTER),
				_rng.randf_range(-SPAWN_JITTER, SPAWN_JITTER)
			)
			_enemies.spawn(Vector2(cell) + Vector2(0.5, 0.5) + jitter, _hp)
			_spawned += 1
	_spawn_budget += _settings.spawn_rate


func check_end() -> bool:
	if phase != Phase.WAVE or _spawned < _size or _enemies.count > 0:
		return false
	phase = Phase.BUILD
	return true


func _pick_edges() -> PackedStringArray:
	var candidates := _map.spawn_edges.duplicate()
	var picked := PackedStringArray()
	picked.append(_take(candidates))
	if not candidates.is_empty() and _rng.randf() < _settings.second_edge_chance:
		picked.append(_take(candidates))
	return picked


func _take(candidates: PackedStringArray) -> String:
	var index := _rng.randi_range(0, candidates.size() - 1)
	var edge := candidates[index]
	candidates.remove_at(index)
	return edge
