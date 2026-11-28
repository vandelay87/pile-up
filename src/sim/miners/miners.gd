class_name Miners
extends RefCounted

## The miners, each mining the deposit it stands on, and the one pace that sets them all. For now
## the base is the only miner. A mining miner takes [code]mining.base_rate × income(pace)[/code]
## minerals a second in equal shares each tick, split by its deposit's mix (its starting
## contents), so every mineral in it runs out on the same tick. Once nothing is left it is dry and
## stays dry.

enum Pace { OFF, LOW, MEDIUM, HIGH }

## The base's miner id, as [constant Perches.BASE] names it.
const BASE := Perches.BASE
## A share of its deposit this small left is float error, not minerals: the miner is dry.
const DRY_SHARE := 1e-9

var pace := Pace.OFF

var _settings: Settings
var _base: MapData.Deposit
# Every mineral the base's deposit held at the start.
var _base_total: int
# The share of the base's deposit still in it, from 1 down to 0.
var _base_left := 1.0
var _changed := PackedInt32Array()


## Minerals by kind, fractional: what a tick mined, or what is left in a deposit.
class Minerals:
	extends RefCounted

	var gold := 0.0
	var aether := 0.0

	func _init(gold_amount := 0.0, aether_amount := 0.0) -> void:
		gold = gold_amount
		aether = aether_amount


func _init(run_settings: Settings, map: MapData) -> void:
	_settings = run_settings
	_base = map.base_deposit
	_base_total = _base.gold + _base.aether
	if _base_total == 0:
		_base_left = 0.0


## Sets the pace, from this tick's mining on; an error once every miner is dry.
func set_pace(new_pace: Pace) -> String:
	if all_dry():
		return "every deposit is dry"
	pace = new_pace
	return ""


## Step 2: mines each mining miner's share of its deposit, capped at what is left.
func step() -> Minerals:
	var mined := Minerals.new()
	if not is_mining(BASE):
		return mined
	var share := minf(_minerals_per_tick() / _base_total, _base_left)
	_base_left -= share
	if _base_left <= DRY_SHARE:
		# The last tick takes whatever float error left, so the deposit is mined out exactly.
		share += _base_left
		_base_left = 0.0
		_changed.append(BASE)
	mined.gold = share * _base.gold
	mined.aether = share * _base.aether
	return mined


## Whether the miner mines this tick: the pace is above Off and it isn't dry.
func is_mining(id: int) -> bool:
	return pace != Pace.OFF and not is_dry(id)


## Whether nothing is left in the miner's deposit. A dry miner stays dry.
func is_dry(id: int) -> bool:
	assert(id == BASE, "unknown miner %d" % id)
	return _base_left == 0.0


## Whether no miner has anything left to mine: the pace is then locked.
func all_dry() -> bool:
	return is_dry(BASE)


## What is left in the miner's deposit, by kind.
func remaining(id: int) -> Minerals:
	assert(id == BASE, "unknown miner %d" % id)
	return Minerals.new(_base_left * _base.gold, _base_left * _base.aether)


## The gold a second at the current pace across every mining miner, for the HUD.
func gold_rate() -> float:
	if not is_mining(BASE):
		return 0.0
	return _minerals_per_tick() * Simulation.TICKS_PER_SECOND * _base.gold / _base_total


## The miners that ran dry since the last call.
func take_changed() -> PackedInt32Array:
	var changed := _changed
	_changed = PackedInt32Array()
	return changed


## The pace's share of [code]mining.base_rate[/code]: 0 at Off.
func income(of_pace: Pace) -> float:
	match of_pace:
		Pace.LOW:
			return _settings.mining_income_low
		Pace.MEDIUM:
			return _settings.mining_income_medium
		Pace.HIGH:
			return _settings.mining_income_high
	return 0.0


func _minerals_per_tick() -> float:
	return _settings.mining_base_rate * income(pace) / Simulation.TICKS_PER_SECOND
