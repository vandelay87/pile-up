class_name RunState
extends RefCounted

var gold: int
var base_hp: float
var wave := 0
var kills := 0
var combo_tier := 1
# The gold the last record_kills paid, and the highest tier it paid at.
var payout := 0
var payout_tier := 1
var is_game_over := false

var _settings: Settings
# Ticks of the kills still in the combo window, oldest first, from _window_start on.
var _kill_ticks := PackedInt32Array()
var _window_start := 0


func _init(run_settings: Settings) -> void:
	_settings = run_settings
	gold = _settings.starting_gold
	base_hp = _settings.base_hp


func can_afford(cost: int) -> bool:
	return gold >= cost


func add_gold(amount: int) -> void:
	gold += amount


func spend(cost: int) -> void:
	gold -= cost


# Each kill pays the bounty times the combo tier, the tier counting that kill.
func record_kills(count: int, tick: int) -> void:
	_expire_kills(tick)
	payout = 0
	payout_tier = 1
	for k in count:
		_kill_ticks.append(tick)
		combo_tier = _tier()
		payout += _settings.enemy_bounty * combo_tier
		payout_tier = maxi(payout_tier, combo_tier)
	kills += count
	gold += payout


func damage_base(amount: float) -> void:
	if is_game_over:
		return
	base_hp = maxf(0.0, base_hp - amount)
	if base_hp == 0.0:
		is_game_over = true


func _expire_kills(tick: int) -> void:
	var oldest := tick - _settings.combo_window_ticks
	while _window_start < _kill_ticks.size() and _kill_ticks[_window_start] <= oldest:
		_window_start += 1
	if _window_start > 1024 and _window_start * 2 > _kill_ticks.size():
		_kill_ticks = _kill_ticks.slice(_window_start)
		_window_start = 0
	combo_tier = _tier()


func _tier() -> int:
	var in_window := _kill_ticks.size() - _window_start
	if in_window >= _settings.combo_tier_3_kills:
		return 3
	if in_window >= _settings.combo_tier_2_kills:
		return 2
	return 1
