class_name FieldChecks
extends RefCounted


static func matches_full_rebuild(sim: Simulation) -> bool:
	var rebuilt := Routing.new(sim.settings, sim.map, sim.occupancy, sim.piles)
	for route: Routing.Route in Routing.Route.values():
		for y in sim.map.height:
			for x in sim.map.width:
				var cell := Vector2i(x, y)
				if sim.routing.value(route, cell) != rebuilt.value(route, cell):
					return false
				if sim.routing.parent(route, cell) != rebuilt.parent(route, cell):
					return false
	return true
