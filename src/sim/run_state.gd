class_name RunState
extends RefCounted

var gold: int
var base_hp: float
var wave := 0
var kills := 0
# The gold the last pay paid, and the highest tier it paid at.
var payout := 0
var payout_tier := 1
var is_game_over := false

var _settings: Settings


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


# Each death, in order, pays its kind's bounty times its killer's combo tier after counting
# that kill: x1 with no killer, or one destroyed this tick. A bloater that blew itself up pays no
# bounty of its own.
func pay(deaths: Deaths, combos: Combos, tick: int) -> void:
	payout = 0
	payout_tier = 1
	for i in deaths.size():
		var tier := combos.record(deaths.killers[i], tick)
		if deaths.pays_bounty(i):
			payout += _settings.enemy_bounty_of(deaths.kinds[i] as Enemies.Kind) * tier
		payout_tier = maxi(payout_tier, tier)
	kills += deaths.size()
	gold += payout


func damage_base(amount: float) -> void:
	if is_game_over:
		return
	base_hp = maxf(0.0, base_hp - amount)
	if base_hp == 0.0:
		is_game_over = true
