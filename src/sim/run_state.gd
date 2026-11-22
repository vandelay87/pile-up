class_name RunState
extends RefCounted

const WHOLE_TOLERANCE := 1e-6

var gold: int
var base_hp: float
var wave := 0
var kills := 0
## The minerals mined this run, by kind, fractional.
var gold_mined := 0.0
var aether_mined := 0.0
var is_game_over := false

var _settings: Settings
# The mined gold paid into [member gold] so far, a whole number.
var _gold_paid := 0


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


## Adds a tick's mined minerals, and pays each whole gold into [member gold] as the mined total
## passes it.
func credit(mined: Miners.Minerals) -> void:
	gold_mined += mined.gold
	aether_mined += mined.aether
	# A total a hair under a whole number from float error has reached it.
	var whole := floori(gold_mined + WHOLE_TOLERANCE)
	gold += whole - _gold_paid
	_gold_paid = whole


## Every death is a kill; kills pay nothing.
func record_kills(deaths: Deaths) -> void:
	kills += deaths.size()


func damage_base(amount: float) -> void:
	if is_game_over:
		return
	base_hp = maxf(0.0, base_hp - amount)
	if base_hp == 0.0:
		is_game_over = true
