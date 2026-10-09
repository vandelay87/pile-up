class_name RunState
extends RefCounted

var gold: int
var lives: int
var wave := 0
var is_game_over := false

var _settings: Settings


func _init(run_settings: Settings) -> void:
	_settings = run_settings
	gold = _settings.starting_gold
	lives = _settings.starting_lives


func can_afford(cost: int) -> bool:
	return gold >= cost


func add_gold(amount: int) -> void:
	gold += amount


func record_removals(kills: int, leaks: int) -> void:
	gold += kills * _settings.enemy_bounty
	lives = maxi(0, lives - leaks)
	if lives == 0:
		is_game_over = true
