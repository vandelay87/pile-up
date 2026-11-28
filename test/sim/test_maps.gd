class_name TestMaps
extends RefCounted


static func open_field() -> MapData:
	return from_rows(["....", "....", "....", "...."], Rect2i(1, 1, 2, 2))


## A map from its rows. Each deposit is {"name", "origin" (a Vector2i), "gold", "aether"}; the
## base's deposit holds [param base_deposit]'s gold and Aether, by default the version 1 ones.
static func from_rows(
	rows: Array[String],
	base: Rect2i,
	spawn_edges: Array[String] = [],
	deposits: Array[Dictionary] = [],
	base_deposit := Vector2i(MapData.DEFAULT_BASE_GOLD, MapData.DEFAULT_BASE_AETHER),
) -> MapData:
	var deposit_data := []
	for deposit in deposits:
		var origin: Vector2i = deposit["origin"]
		(
			deposit_data
			. append(
				{
					"name": deposit["name"],
					"origin": [origin.x, origin.y],
					"gold": deposit["gold"],
					"aether": deposit["aether"],
				}
			)
		)
	var data := {
		"version": 2,
		"width": rows[0].length(),
		"height": rows.size(),
		"rows": rows,
		"base": {"origin": [base.position.x, base.position.y], "size": [base.size.x, base.size.y]},
		"spawn_edges": spawn_edges,
		"base_deposit": {"gold": base_deposit.x, "aether": base_deposit.y},
		"deposits": deposit_data,
	}
	var result := MapData.from_json(JSON.stringify(data))
	assert(result.error.is_empty(), result.error)
	return result.map
