extends GdUnitTestSuite

# v6 removed the bounties and the combo group: a defaults file that still has them is rejected.


func test_the_removed_bounty_and_combo_settings_are_rejected() -> void:
	var removed := [
		["enemies", "bounty", 1],
		["bloaters", "bounty", 2],
		["brutes", "bounty", 4],
	]
	for row: Array in removed:
		var data: Dictionary = JSON.parse_string(
			FileAccess.get_file_as_string(Settings.DEFAULTS_PATH)
		)
		data[row[0]][row[1]] = row[2]
		var result := Settings.from_json(JSON.stringify(data))
		assert_str(result.error).contains("%s.%s: unknown setting" % [row[0], row[1]])

	var with_combo: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string(Settings.DEFAULTS_PATH)
	)
	with_combo["combo"] = {"timer": 2, "tier_2_kills": 10, "tier_3_kills": 25, "cap": 3}
	assert_str(Settings.from_json(JSON.stringify(with_combo)).error).contains(
		"combo: unknown group"
	)
