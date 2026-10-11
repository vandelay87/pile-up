class_name FieldChecks
extends RefCounted


static func matches_full_rebuild(sim: Simulation) -> bool:
	var rebuilt := Routing.new(sim.settings, sim.map, sim.occupancy, sim.piles, sim.structures)
	return routings_match(sim.routing, rebuilt, sim.map)


static func routings_match(routing: Routing, other: Routing, map: MapData) -> bool:
	for route: Routing.Route in Routing.Route.values():
		for y in map.height:
			for x in map.width:
				var cell := Vector2i(x, y)
				if routing.value(route, cell) != other.value(route, cell):
					return false
				if routing.parent(route, cell) != other.parent(route, cell):
					return false
	return true
