class_name RunState
extends RefCounted

var gold: int
var base_hp: float
var wave := 0
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


func record_kills(kills: int) -> void:
	gold += kills * _settings.enemy_bounty


func damage_base(amount: float) -> void:
	if is_game_over:
		return
	base_hp = maxf(0.0, base_hp - amount)
	if base_hp == 0.0:
		is_game_over = true
