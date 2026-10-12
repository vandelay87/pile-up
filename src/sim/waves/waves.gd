class_name Waves
extends RefCounted

enum Phase { BUILD, WAVE }

const SPAWN_JITTER := 0.25

var phase := Phase.BUILD
var edges := PackedStringArray()
# Wave size minus kills this wave, unspawned enemies included; the next wave's size between
# waves.
var enemies_left: int:
	get:
		return _size - _kills if phase == Phase.WAVE else size(_wave + 1)

var _settings: Settings
var _map: MapData
var _enemies: Enemies
var _rng: RandomNumberGenerator
# Seeds each wave's bloater roll with the wave number, so a wave's count is the same however
# often, and whenever, it is asked for.
var _bloater_seed := 0
var _hp := 0.0
var _bloater_hp := 0.0
# 1 for each spawn slot of this wave that is a bloater.
var _bloater_slots := PackedByteArray()
var _spawned := 0
var _size := 0
var _spawn_budget := 0.0
var _wave := 0
var _kills := 0


func _init(
	run_settings: Settings,
	run_map: MapData,
	run_enemies: Enemies,
	rng: RandomNumberGenerator,
	bloater_seed := 0
) -> void:
	_settings = run_settings
	_map = run_map
	_enemies = run_enemies
	_rng = rng
	_bloater_seed = bloater_seed


func size(wave: int) -> int:
	return roundi(_settings.wave_1_size * pow(_settings.wave_growth, wave - 1))


# How many of wave [param wave]'s spawns are bloaters: none before the first bloater wave, then
# 1, and one more every waves_per_step waves, whatever the wave's size. Each wave rolls once for
# one fewer (miss_chance) or one more (extra_chance).
func bloater_count(wave: int) -> int:
	var first := _settings.first_bloater_wave
	if wave < first:
		return 0
	var count := 1 + (wave - first) / _settings.bloater_waves_per_step
	var roll_rng := RandomNumberGenerator.new()
	roll_rng.seed = hash([_bloater_seed, wave])
	var roll := roll_rng.randf()
	if roll < _settings.bloater_miss_chance:
		return count - 1
	if roll >= 1.0 - _settings.bloater_extra_chance:
		return count + 1
	return count


func enemy_hp(wave: int, kind := Enemies.Kind.NORMAL) -> float:
	return _settings.enemy_hp_of(kind) * pow(_settings.hp_growth, wave - 1)


func start(wave: int) -> void:
	phase = Phase.WAVE
	_wave = wave
	_kills = 0
	edges = _pick_edges()
	_size = size(wave)
	_hp = enemy_hp(wave)
	_bloater_hp = enemy_hp(wave, Enemies.Kind.BLOATER)
	_pick_bloater_slots(bloater_count(wave))
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
			var pos := Vector2(cell) + Vector2(0.5, 0.5) + jitter
			if _bloater_slots[_spawned] == 1:
				_enemies.spawn(pos, _bloater_hp, Enemies.Kind.BLOATER)
			else:
				_enemies.spawn(pos, _hp)
			_spawned += 1
	_spawn_budget += _settings.spawn_rate


# The last stretch of a wave, when the stragglers push through rather than go the long way.
func in_wave_tail() -> bool:
	var tail := _settings.wave_tail + _settings.wave_tail_per_wave * _wave
	return phase == Phase.WAVE and enemies_left <= tail


func record_kills(kills: int) -> void:
	if phase == Phase.WAVE:
		_kills += kills


func check_end() -> bool:
	if phase != Phase.WAVE or _spawned < _size or _enemies.count > 0:
		return false
	phase = Phase.BUILD
	return true


# Picks [param count] of the wave's spawn slots, without replacement, to be bloaters.
func _pick_bloater_slots(count: int) -> void:
	_bloater_slots.resize(_size)
	_bloater_slots.fill(0)
	var picked := 0
	while picked < mini(count, _size):
		var slot := _rng.randi_range(0, _size - 1)
		if _bloater_slots[slot] == 0:
			_bloater_slots[slot] = 1
			picked += 1


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
