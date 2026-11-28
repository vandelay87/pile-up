class_name Waves
extends RefCounted

## The alert, the waves it draws and the trickle. In the quiet the alert fills at the pace's
## speed; at [code]alert.warn_at[/code] the next wave's edges are picked, and full, a wave starts
## and the alert empties. It stays empty until that wave's last enemy dies, so waves never
## overlap. A wave's size, plan and special enemies are fixed as it starts, from the threat, the
## pace and a roll seeded by its index (the waves started this run before it). The trickle sends
## normal enemies alone from any spawn edge at every pace, quiet and wave alike, counting towards
## no wave.

enum Phase { QUIET, WAVE }

const SPAWN_JITTER := 0.25
# A spawn plan entry for one scattered enemy; every other entry is a burst's size.
const SCATTERED := 0
const MIN_STRETCH_WIDTH := 1.0
## The wave index of an enemy in no wave: the trickle's and debug spawns.
const NO_WAVE := -1
## The special kinds by their names in [method special_counts], in the order slots are picked.
const SPECIAL_KINDS := {
	"bloaters": Enemies.Kind.BLOATER,
	"jumpers": Enemies.Kind.JUMPER,
	"brutes": Enemies.Kind.BRUTE,
}
# Float slack for the alert reaching a mark and the trickle's budget reaching a whole enemy.
const _SLACK := 1e-9

var phase := Phase.QUIET
## How full the alert is, from 0 to 1. Empty through a wave.
var alert := 0.0
## The next wave's spawn edges once picked (at the warning, or as it starts), else empty.
var next_edges := PackedStringArray()
## Waves started this run: the next wave's index.
var started := 0
## The open waves' enemies not yet killed, unspawned ones included.
var enemies_left: int:
	get:
		var left := 0
		for wave in _open:
			left += wave.size - wave.kills
		return left
## The open waves' sizes, summed.
var open_size: int:
	get:
		var total := 0
		for wave in _open:
			total += wave.size
		return total

var _settings: Settings
var _map: MapData
var _enemies: Enemies
var _rng: RandomNumberGenerator
var _run_seed := 0
var _open: Array[Wave] = []
var _trickle_budget := 0.0
var _coming := false
var _just_started: Array[Wave] = []


## One wave as it was fixed when it started, and how far it has got.
class Wave:
	extends RefCounted

	var index: int
	## The threat as it started, and its whole points.
	var threat: float
	var whole_threat: int
	var size: int
	var edges: PackedStringArray
	## Its special enemies by kind name, as [method Waves.special_counts] gives them.
	var specials: Dictionary
	## Enemies left at or under this, its enemies push through as in the wave tail.
	var tail: int
	var kills := 0
	var spawned := 0
	var spawn_rate: float
	var plan: PackedInt32Array
	# The Enemies.Kind of each spawn slot, and each kind's HP, by Enemies.Kind.
	var slot_kinds := PackedByteArray()
	var hp_by_kind := PackedFloat64Array()
	# The plan entry to spawn next, and how many bursts have landed, which picks the next one's
	# edge.
	var next_entry := 0
	var bursts_spawned := 0
	var spawn_budget := 0.0

	func is_in_tail() -> bool:
		return size - kills <= tail


func _init(
	run_settings: Settings,
	run_map: MapData,
	run_enemies: Enemies,
	rng: RandomNumberGenerator,
	run_seed := 0,
) -> void:
	_settings = run_settings
	_map = run_map
	_enemies = run_enemies
	_rng = rng
	_run_seed = run_seed


## Step 2: the alert fills in the quiet, picks the next wave's edges at the warning and starts
## it when full; every open wave spawns by its plan; the trickle spawns. [param dry] is
## [method Miners.all_dry].
func step(pace: Miners.Pace, threat: Threat, dry: bool) -> void:
	if phase == Phase.QUIET and not _map.spawn_edges.is_empty():
		alert = minf(1.0, alert + _settings.alert_fill_per_tick * fill_factor(pace, dry))
		if alert >= _settings.alert_warn_at - _SLACK and next_edges.is_empty():
			next_edges = _pick_edges(threat.whole())
			_coming = true
		if alert >= 1.0 - _SLACK:
			_start(threat, size_factor(pace, dry))
	for wave in _open:
		_spawn(wave)
	_trickle(threat.value)


## Debug: fills the alert at once, so the next wave starts at this tick's step 2. An error during
## a wave, or on a map with no spawn edges.
func send_wave() -> String:
	if phase == Phase.WAVE:
		return "a wave is already running"
	if _map.spawn_edges.is_empty():
		return "the map has no spawn edges"
	alert = 1.0
	return ""


## How fast the alert fills, as a share of High's: none at Off, and the dry fill whatever the
## pace once every deposit is dry.
func fill_factor(pace: Miners.Pace, dry: bool) -> float:
	if dry:
		return _settings.value("alert", "dry_fill")
	match pace:
		Miners.Pace.LOW:
			return _settings.value("alert", "fill_low")
		Miners.Pace.MEDIUM:
			return _settings.value("alert", "fill_medium")
		Miners.Pace.HIGH:
			return _settings.value("alert", "fill_high")
	return 0.0


## A wave's size factor at [param pace]: the dry size while every deposit is dry, and at Off,
## where only a sent wave starts.
func size_factor(pace: Miners.Pace, dry: bool) -> float:
	if not dry:
		match pace:
			Miners.Pace.LOW:
				return _settings.value("waves", "size_low")
			Miners.Pace.MEDIUM:
				return _settings.value("waves", "size_medium")
			Miners.Pace.HIGH:
				return _settings.value("waves", "size_high")
	return _settings.value("waves", "dry_size")


## The size of wave [param index] starting at [param threat] with [param factor]:
## [code]round(wave_1_size × growth^(threat − 1) × factor × roll)[/code], at least 1, where the
## roll is uniform within ±size_roll, fixed per run and wave.
func size_for(threat: float, factor: float, index: int) -> int:
	var roll_rng := RandomNumberGenerator.new()
	roll_rng.seed = hash([_run_seed, "wave_roll", index])
	var roll := 1.0 + _settings.size_roll * roll_rng.randf_range(-1.0, 1.0)
	var grown := _settings.wave_1_size * pow(_settings.wave_growth, threat - 1.0)
	return maxi(1, roundi(grown * factor * roll))


## Wave [param index]'s special enemies at [param whole_threat] in a wave of [param size]:
## bloaters, then jumpers, then brutes, each kind given fewer if they would outnumber the wave.
## The bloater and brute rolls are seeded by the wave's index, so two waves at one threat roll
## apart.
func special_counts(whole_threat: int, size: int, index: int) -> Dictionary:
	var bloaters := mini(
		_stepped_count(whole_threat, "bloaters", hash([_run_seed, "bloaters", index])), size
	)
	var jumpers := mini(_jumper_count(whole_threat, size), size - bloaters)
	var brutes := mini(
		_stepped_count(whole_threat, "brutes", hash([_run_seed, "brutes", index])),
		size - bloaters - jumpers
	)
	return {"bloaters": bloaters, "jumpers": jumpers, "brutes": brutes}


# Wave spawns in order: its bursts, with its scattered enemies spread evenly between them. Of
# [param total], round(total × scatter_share(threat)) are scattered and the rest come in bursts
# of round(burst_size × burst_growth^(threat − 1)), the last one short. The k-th scattered enemy
# (k from 0) comes after burst floor(k × bursts ÷ scattered).
func spawn_plan(threat: float, total: int) -> PackedInt32Array:
	var scattered := roundi(total * scatter_share(threat))
	var in_bursts := total - scattered
	var burst := maxi(1, roundi(_settings.burst_size * pow(_settings.burst_growth, threat - 1.0)))
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


## A [param kind]'s HP at [param threat]: its HP × hp_growth^(threat − 1).
func enemy_hp(threat: float, kind := Enemies.Kind.NORMAL) -> float:
	return _settings.enemy_hp_of(kind) * pow(_settings.hp_growth, threat - 1.0)


# The share of a wave spawned as scattered enemies at [param threat]: scatter_share_start at
# threat 1, falling in a straight line to scatter_share_end at scatter_share_end_threat, then
# holding there.
func scatter_share(threat: float) -> float:
	var span := _settings.scatter_share_end_threat - 1
	var progress := 1.0 if span <= 0 else clampf((threat - 1.0) / span, 0.0, 1.0)
	return lerpf(_settings.scatter_share_start, _settings.scatter_share_end, progress)


# Enemies a second that a wave at [param threat] spawns at: spawn_rate, grown by
# spawn_rate_growth a point of threat.
func spawn_rate(threat: float) -> float:
	return _settings.spawn_rate * pow(_settings.spawn_rate_growth, threat - 1.0)


## The trickle's enemies a second at [param threat].
func trickle_rate(threat: float) -> float:
	return _settings.trickle_spawn_rate * pow(_settings.trickle_spawn_growth, threat - 1.0)


# How wide, in cells along the edge, a burst of [param burst] lands: burst_width for a burst of
# burst_size, growing with the square root of the burst, and never under 1 cell.
func stretch_width(burst: int) -> float:
	return maxf(
		MIN_STRETCH_WIDTH, _settings.burst_width * sqrt(float(burst) / _settings.burst_size)
	)


## Which waves' enemies may push through to the direct route, for [method Enemies.move]: entry
## [code]wave + 1[/code] is 1 for wave [code]wave[/code] once it is in its tail, and entry 0, for
## enemies in no wave, always is.
func tail_mask() -> PackedByteArray:
	var mask := PackedByteArray()
	mask.resize(started + 1)
	mask[0] = 1
	for wave in _open:
		mask[wave.index + 1] = 1 if wave.is_in_tail() else 0
	return mask


## The open waves, oldest first.
func open_waves() -> Array[Wave]:
	return _open


## Debug: sends [param count] enemies of [param kind] at once as one burst, at the threat's HP.
## They belong to no wave. They come from the next wave's first edge if it is picked, else the
## open wave's, else a random spawn edge. False when the map has no spawn edges.
func send(kind: Enemies.Kind, count: int, threat: float) -> bool:
	if _map.spawn_edges.is_empty():
		return false
	var edge := _random_edge()
	if not next_edges.is_empty():
		edge = next_edges[0]
	elif not _open.is_empty():
		edge = _open[0].edges[0]
	var hp := enemy_hp(threat, kind)
	var stretch := _stretch(edge, count)
	for _k in count:
		_enemies.spawn(_jittered(_random_cell(stretch)), hp, kind)
	return true


## Counts this tick's deaths towards their waves; the trickle's and debug spawns count towards
## none.
func record_kills(deaths: Deaths) -> void:
	for k in deaths.size():
		var index := deaths.waves[k]
		if index == NO_WAVE:
			continue
		for wave in _open:
			if wave.index == index:
				wave.kills += 1
				break


## Step 10: closes each open wave whose enemies have all spawned and died. True when one closed
## and no wave is left open: the wave-end rules fire and the alert refills.
func check_end() -> bool:
	var closed := false
	for i in range(_open.size() - 1, -1, -1):
		var wave := _open[i]
		if wave.spawned == wave.size and wave.kills >= wave.size:
			_open.remove_at(i)
			closed = true
	if not closed or not _open.is_empty():
		return false
	phase = Phase.QUIET
	return true


## Whether the next wave's edges were picked since the last call.
func take_coming() -> bool:
	var coming := _coming
	_coming = false
	return coming


## The waves started since the last call.
func take_started() -> Array[Wave]:
	var taken := _just_started
	_just_started = []
	return taken


func _start(threat: Threat, factor: float) -> void:
	var wave := Wave.new()
	wave.index = started
	started += 1
	wave.threat = threat.value
	wave.whole_threat = threat.whole()
	wave.edges = next_edges if not next_edges.is_empty() else _pick_edges(wave.whole_threat)
	next_edges = PackedStringArray()
	alert = 0.0
	phase = Phase.WAVE
	wave.size = size_for(wave.threat, factor, wave.index)
	wave.specials = special_counts(wave.whole_threat, wave.size, wave.index)
	wave.tail = _settings.wave_tail + _settings.wave_tail_per_threat * wave.whole_threat
	wave.spawn_rate = spawn_rate(wave.threat)
	for kind: Enemies.Kind in Enemies.Kind.values():
		wave.hp_by_kind.append(enemy_hp(wave.threat, kind))
	wave.slot_kinds.resize(wave.size)
	wave.slot_kinds.fill(Enemies.Kind.NORMAL)
	for name: String in SPECIAL_KINDS:
		var kind: Enemies.Kind = SPECIAL_KINDS[name]
		var count: int = wave.specials[name]
		_pick_slots(wave, kind, count)
	wave.plan = spawn_plan(wave.threat, wave.size)
	wave.spawn_budget = _cost(wave.plan[0]) if not wave.plan.is_empty() else 0.0
	_open.append(wave)
	_just_started.append(wave)


# Spawns the plan's entries in order, each once the budget covers it: a burst on a stretch of
# the next of the wave's edges in turn, a scattered enemy alone on a random cell of a random one
# of its edges. Each tick adds the spawn rate to the budget, so the average rate holds.
func _spawn(wave: Wave) -> void:
	while (
		wave.next_entry < wave.plan.size()
		and wave.spawn_budget >= _cost(wave.plan[wave.next_entry])
	):
		var entry := wave.plan[wave.next_entry]
		wave.spawn_budget -= _cost(entry)
		wave.next_entry += 1
		if entry == SCATTERED:
			var edge := wave.edges[_rng.randi_range(0, wave.edges.size() - 1)]
			_spawn_on(wave, _random_cell(_map.spawn_cells(edge)))
			continue
		var stretch := _stretch(wave.edges[wave.bursts_spawned % wave.edges.size()], entry)
		wave.bursts_spawned += 1
		for _k in entry:
			_spawn_on(wave, _random_cell(stretch))
	wave.spawn_budget += wave.spawn_rate


# Each tick adds the trickle's rate to its budget; each whole enemy spawns alone on a random
# spawn cell of a random spawn edge of the map.
func _trickle(threat: float) -> void:
	if _map.spawn_edges.is_empty():
		return
	_trickle_budget += trickle_rate(threat) / Simulation.TICKS_PER_SECOND
	if _trickle_budget < 1.0 - _SLACK:
		return
	var hp := enemy_hp(threat)
	while _trickle_budget >= 1.0 - _SLACK:
		_trickle_budget -= 1.0
		_enemies.spawn(_jittered(_random_cell(_map.spawn_cells(_random_edge()))), hp)


# None before the group's first threat, then 1, and one more every threat_per_step points. Each
# wave rolls once, on [param roll_seed], for one fewer (miss_chance) or one more (extra_chance).
func _stepped_count(whole_threat: int, group: String, roll_seed: int) -> int:
	var first: int = _settings.value(group, "first_threat")
	if whole_threat < first:
		return 0
	var per_step: int = _settings.value(group, "threat_per_step")
	var count := 1 + (whole_threat - first) / per_step
	var roll_rng := RandomNumberGenerator.new()
	roll_rng.seed = roll_seed
	var roll := roll_rng.randf()
	var miss_percent: int = _settings.value(group, "miss_chance")
	var extra_percent: int = _settings.value(group, "extra_chance")
	if roll < miss_percent / 100.0:
		return count - 1
	if roll >= 1.0 - extra_percent / 100.0:
		return count + 1
	return count


# None before the first jumper threat, then the jumper share of the wave, rounded, and no more
# than the cap when it is above 0.
func _jumper_count(whole_threat: int, size: int) -> int:
	var first: int = _settings.value("jumpers", "first_threat")
	if whole_threat < first:
		return 0
	var share: int = _settings.value("jumpers", "share")
	var count := roundi(size * share / 100.0)
	var cap: int = _settings.value("jumpers", "cap")
	return mini(count, cap) if cap > 0 else count


# Picks [param count] of the wave's normal spawn slots, without replacement, to be [param kind].
# special_counts leaves room for every pick.
func _pick_slots(wave: Wave, kind: Enemies.Kind, count: int) -> void:
	var picked := 0
	while picked < count:
		var slot := _rng.randi_range(0, wave.size - 1)
		if wave.slot_kinds[slot] == Enemies.Kind.NORMAL:
			wave.slot_kinds[slot] = kind
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


func _random_edge() -> String:
	return _map.spawn_edges[_rng.randi_range(0, _map.spawn_edges.size() - 1)]


func _spawn_on(wave: Wave, cell: Vector2i) -> void:
	var kind := wave.slot_kinds[wave.spawned] as Enemies.Kind
	_enemies.spawn(_jittered(cell), wave.hp_by_kind[kind], kind, wave.index)
	wave.spawned += 1


func _jittered(cell: Vector2i) -> Vector2:
	var jitter := Vector2(
		_rng.randf_range(-SPAWN_JITTER, SPAWN_JITTER), _rng.randf_range(-SPAWN_JITTER, SPAWN_JITTER)
	)
	return MapData.centre_of(cell) + jitter


# 1 edge, then 2, 3 and 4 from their threats, capped at the map's spawn edges, drawn at random
# without repeats.
func _pick_edges(whole_threat: int) -> PackedStringArray:
	var count := 1
	for key: String in ["two_edges_threat", "three_edges_threat", "four_edges_threat"]:
		var from: int = _settings.value("waves", key)
		if whole_threat >= from:
			count += 1
	var candidates := _map.spawn_edges.duplicate()
	var picked := PackedStringArray()
	while picked.size() < count and not candidates.is_empty():
		var index := _rng.randi_range(0, candidates.size() - 1)
		picked.append(candidates[index])
		candidates.remove_at(index)
	return picked
