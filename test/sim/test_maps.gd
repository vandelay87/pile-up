class_name TestMaps
extends RefCounted


static func open_field() -> MapData:
	var data := {
		"version": 1,
		"width": 4,
		"height": 4,
		"rows": ["....", "....", "....", "...."],
		"base": {"origin": [1, 1], "size": [2, 2]},
		"spawn_edges": ["N"],
	}
	return MapData.from_json(JSON.stringify(data)).map
