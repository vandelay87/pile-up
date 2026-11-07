class_name Waves
extends RefCounted

enum Phase { BUILD, WAVE }

const SPAWN_JITTER := 0.25
# A spawn plan entry for one scattered enemy; every other entry is a burst's size.
const SCATTERED := 0
const MIN_STRETCH_WIDTH := 1.0

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
var _plan := PackedInt32Array()
# The plan entry to spawn next, and how many bursts have landed, which picks the next one's edge.
var _next_entry := 0
var _bursts_spawned := 0
var _wave := 0
var _kills := 0


func _init(
	run_settings: Settings,
	run_map: MapData,
	run_enemies: Enemies,
	rng: RandomNumberGenerator,
	bloater_seed: int
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


# Wave [param wave]'s spawns in order: its bursts, with its scattered enemies spread evenly
# between them. Of a wave of N, round(N × scatter_share(wave)) are scattered and the rest come in
# bursts of round(burst_size × burst_growth^(wave − 1)), the last one short. The k-th scattered
# enemy (k from 0) comes after burst floor(k × bursts ÷ scattered).
func spawn_plan(wave: int) -> PackedInt32Array:
	var total := size(wave)
	var scattered := roundi(total * scatter_share(wave))
	var in_bursts := total - scattered
	var burst := maxi(1, roundi(_settings.burst_size * pow(_settings.burst_growth, wave - 1)))
	var bursts := ceili(float(in_bursts) / burst)
	var plan := PackedInt32Array()
	var k := 0
	while k < scattered and bursts == 0:
		plan.append(SCATTERED)
		k += 1
	for i in bursts:
		plan.append(mini(burst, in_bursts - i * burst))
		while k < scattered and k * bursts / scattered == i:
			plan.append(SCATTERED)
			k += 1
	return plan


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
	_plan = spawn_plan(wave)
	_next_entry = 0
	_bursts_spawned = 0
	_spawn_budget = _cost(_plan[0]) if not _plan.is_empty() else 0.0


# Spawns the plan's entries in order, each once the budget covers it: a burst on a stretch of
# the next of the wave's edges in turn, a scattered enemy alone on a random cell of a random
# edge. Each tick adds the spawn rate to the budget, so the average rate holds.
func spawn() -> void:
	if phase != Phase.WAVE:
		return
	while _next_entry < _plan.size() and _spawn_budget >= _cost(_plan[_next_entry]):
		var entry := _plan[_next_entry]
		_spawn_budget -= _cost(entry)
		_next_entry += 1
		if entry == SCATTERED:
			var edge := edges[_rng.randi_range(0, edges.size() - 1)]
			_spawn_on(_random_cell(_map.spawn_cells(edge)))
			continue
		var stretch := _stretch(edges[_bursts_spawned % edges.size()], entry)
		_bursts_spawned += 1
		for _k in entry:
			_spawn_on(_random_cell(stretch))
	_spawn_budget += spawn_rate(_wave)


# The share of wave [param wave] spawned as scattered enemies: scatter_share_start at wave 1,
# falling in a straight line to scatter_share_end at scatter_share_end_wave, then holding there.
func scatter_share(wave: int) -> float:
	var span := _settings.scatter_share_end_wave - 1
	var progress := 1.0 if span <= 0 else clampf(float(wave - 1) / span, 0.0, 1.0)
	return lerpf(_settings.scatter_share_start, _settings.scatter_share_end, progress)


# Enemies a second that wave [param wave] spawns at: spawn_rate, grown by spawn_rate_growth a
# wave.
func spawn_rate(wave: int) -> float:
	return _settings.spawn_rate * pow(_settings.spawn_rate_growth, wave - 1)


# How wide, in cells along the edge, a burst of [param burst] lands: burst_width for a burst of
# burst_size, growing with the square root of the burst, and never under 1 cell.
func stretch_width(burst: int) -> float:
	return maxf(
		MIN_STRETCH_WIDTH, _settings.burst_width * sqrt(float(burst) / _settings.burst_size)
	)


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


# Budget, in enemy-ticks, that a plan entry costs.
func _cost(entry: int) -> float:
	return Simulation.TICKS_PER_SECOND * maxi(entry, 1)


# The spawn cells of [param edge] within half a burst's stretch of a random one of them,
# measured along the edge.
func _stretch(edge: String, burst: int) -> Array[Vector2i]:
	var cells := _map.spawn_cells(edge)
	var centre := _random_cell(cells)
	var half := stretch_width(burst) / 2.0
	var stretch: Array[Vector2i] = []
	for cell in cells:
		var offset := cell - centre
		if absi(offset.x) + absi(offset.y) <= half:
			stretch.append(cell)
	return stretch


func _random_cell(cells: Array[Vector2i]) -> Vector2i:
	return cells[_rng.randi_range(0, cells.size() - 1)]


func _spawn_on(cell: Vector2i) -> void:
	var jitter := Vector2(
		_rng.randf_range(-SPAWN_JITTER, SPAWN_JITTER), _rng.randf_range(-SPAWN_JITTER, SPAWN_JITTER)
	)
	var pos := MapData.centre_of(cell) + jitter
	if _bloater_slots[_spawned] == 1:
		_enemies.spawn(pos, _bloater_hp, Enemies.Kind.BLOATER)
	else:
		_enemies.spawn(pos, _hp)
	_spawned += 1


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
