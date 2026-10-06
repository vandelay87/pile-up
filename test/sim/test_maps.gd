class_name TestMaps
extends RefCounted


static func open_field() -> MapData:
	return from_rows(["....", "....", "....", "...."], Rect2i(1, 1, 2, 2))


static func from_rows(
	rows: Array[String], base: Rect2i, spawn_edges: Array[String] = []
) -> MapData:
	var data := {
		"version": 1,
		"width": rows[0].length(),
		"height": rows.size(),
		"rows": rows,
		"base": {"origin": [base.position.x, base.position.y], "size": [base.size.x, base.size.y]},
		"spawn_edges": spawn_edges,
	}
	return MapData.from_json(JSON.stringify(data)).map
