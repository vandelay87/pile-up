class_name Blasts
extends RefCounted

## Step 9: every bloater in the death list blows up where it died. Its blast kills each living
## enemy within the blast radius, credited to the bloater's killer, and a bloater it kills
## blows up in turn, so chains resolve breadth-first. Once every kill is credited, each
## building with a cell centre in reach of a blast takes the blast damage once, as does the
## base, and every pile and wall in reach is erased.

var _settings: Settings
var _map: MapData
var _enemies: Enemies
var _buildings: Buildings
var _piles: Piles
var _run_state: RunState
var _base_cells: Array[Vector2i]


## One bloater blowing up: where, and who gets the credit for its kills.
class Blast:
	extends RefCounted

	var position: Vector2
	var killer: int

	func _init(blast_position: Vector2, blast_killer: int) -> void:
		position = blast_position
		killer = blast_killer


func _init(
	run_settings: Settings,
	run_map: MapData,
	run_enemies: Enemies,
	run_buildings: Buildings,
	run_piles: Piles,
	run_state: RunState,
) -> void:
	_settings = run_settings
	_map = run_map
	_enemies = run_enemies
	_buildings = run_buildings
	_piles = run_piles
	_run_state = run_state
	_base_cells = _map.base_cells()


## Blows up every bloater in [param deaths], adding each blast kill to it in kill order, and
## returns the blasts in the order they went off.
func resolve(deaths: Deaths) -> Array[Blast]:
	var blasts: Array[Blast] = []
	var radius := _settings.blast_radius
	var k := 0
	# Blast kills join the list as they fall, so the loop reaches the bloaters among them.
	while k < deaths.size():
		if deaths.kinds[k] == Enemies.Kind.BLOATER:
			if blasts.is_empty():
				# Removal moved enemies between slots since step 3.
				_enemies.rebuild_spatial_hash()
			var blast := Blast.new(deaths.positions[k], deaths.killers[k])
			blasts.append(blast)
			_kill_around(blast, radius, deaths)
		k += 1
	if blasts.is_empty():
		return blasts
	_enemies.remove_dead()
	for blast in blasts:
		_hurt_structures(blast.position, radius)
		_erase_piles(blast.position, radius)
	return blasts


func _kill_around(blast: Blast, radius: float, deaths: Deaths) -> void:
	for i in _enemies.living_within(blast.position, radius):
		_enemies.kill(_enemies.ids[i])
		deaths.add(_enemies.ids[i], _enemies.positions[i], _enemies.kinds[i], blast.killer, true)
		_buildings.count_kill(blast.killer)


func _hurt_structures(centre: Vector2, radius: float) -> void:
	var damage := _settings.blast_damage
	for building: Buildings.Building in _buildings.built.duplicate():
		if _any_in_reach(building.footprint, centre, radius):
			_buildings.damage(building.id, damage)
	if _any_in_reach(_base_cells, centre, radius):
		_run_state.damage_base(damage)


func _erase_piles(centre: Vector2, radius: float) -> void:
	var low := Vector2i((centre - Vector2(radius, radius)).floor())
	var high := Vector2i((centre + Vector2(radius, radius)).floor())
	for y in range(maxi(low.y, 0), mini(high.y + 1, _map.height)):
		for x in range(maxi(low.x, 0), mini(high.x + 1, _map.width)):
			var cell := Vector2i(x, y)
			if _in_reach(cell, centre, radius):
				_piles.erase(cell)


static func _any_in_reach(cells: Array[Vector2i], centre: Vector2, radius: float) -> bool:
	for cell in cells:
		if _in_reach(cell, centre, radius):
			return true
	return false


static func _in_reach(cell: Vector2i, centre: Vector2, radius: float) -> bool:
	return (Vector2(cell) + Vector2(0.5, 0.5)).distance_to(centre) <= radius
