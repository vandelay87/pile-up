extends GdUnitTestSuite

# v6 removed the bounties, the combo group, the second-edge chance and the wave-numbered keys: a
# defaults file that still has them is rejected.


func test_the_removed_and_renamed_settings_are_rejected() -> void:
	var removed := [
		["enemies", "bounty", 1],
		["bloaters", "bounty", 2],
		["brutes", "bounty", 4],
		["waves", "second_edge_chance", 50],
		["waves", "scatter_share_end_wave", 12],
		["waves", "wave_tail_per_wave", 2],
		["bloaters", "first_wave", 5],
		["bloaters", "waves_per_step", 6],
		["jumpers", "first_wave", 8],
		["brutes", "first_wave", 12],
		["brutes", "waves_per_step", 6],
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
