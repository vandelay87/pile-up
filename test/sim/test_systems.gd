class_name TestSystems
extends RefCounted

## The systems under Routing and Enemies, wired as Simulation wires them, for the system-level
## tests the Simulation seam cannot reach (routing exactness, movement rules).

var settings: Settings
var map: MapData
var occupancy: Occupancy
var piles: Piles
var run_state: RunState
var buildings: Buildings
var structures: Structures


func _init(run_settings: Settings, run_map: MapData) -> void:
	settings = run_settings
	map = run_map
	occupancy = Occupancy.new(map.width, map.height)
	piles = Piles.new(settings, map, occupancy)
	run_state = RunState.new(settings)
	buildings = Buildings.new(settings, map, occupancy, piles, run_state)
	structures = Structures.new(map, occupancy, piles, buildings, run_state)


func routing() -> Routing:
	return Routing.new(settings, map, occupancy, piles, structures)


func enemies(run_routing: Routing, rng: RandomNumberGenerator) -> Enemies:
	return Enemies.new(settings, map, occupancy, piles, run_routing, structures, rng)


## Builds a tower for free, or returns null when it cannot be placed.
func build_tower(origin: Vector2i) -> Buildings.Building:
	run_state.add_gold(settings.tower_cost)
	if not buildings.build(Buildings.TOWER, origin).is_empty():
		return null
	return buildings.built.back()
