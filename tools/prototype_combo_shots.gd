# PROTOTYPE (#104): renders each combo look with towers in different states. Run non-headless:
# Godot --path . --resolution 1600x1000 --script tools/prototype_combo_shots.gd -- <out dir>
extends SceneTree

var _main: Main
var _frames := 0
var _out := ""
var _towers: Array[Buildings.Building] = []


func _initialize() -> void:
	_out = OS.get_cmdline_user_args()[0]
	var scene: PackedScene = load("res://src/view/main.tscn")
	_main = scene.instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frames += 1
	var sim: Simulation = _main.simulation
	if _frames == 5:
		sim.run_state.add_gold(5000)
		var base: Rect2i = sim.map.base
		var placed := 0
		for y in range(base.position.y - 12, base.end.y + 12, 3):
			for x in range(base.position.x - 12, base.end.x + 12, 3):
				if placed >= 8:
					break
				if sim.buildings.can_place(Buildings.TOWER, Vector2i(x, y)):
					sim.queue_command(Commands.Build.new(Buildings.TOWER, Vector2i(x, y)))
					placed += 1
		var cam: Camera2D = _main.get_node("Camera")
		cam.position = GridTransform.grid_to_world(Vector2(base.get_center()))
	if _frames == 9:
		for b in sim.buildings.built:
			if b.kind == Buildings.TOWER:
				_towers.append(b)
		var sel: Selection = _main.get_node("Selection")
		sel._building_id = _towers[1].id
	if _frames > 9 and _frames < 400:
		# Counts: x1, x2 mid, x3 nearly x4, x4 cap, tier-up just now, break just now...
		var states := [[2, 0.9], [7, 0.6], [18, 0.2], [27, 0.95], [3, 0.9], [11, 0.5], [5, 0.3], [0, 0.0]]
		for i in _towers.size():
			var b: Buildings.Building = _towers[i]
			var st: Array = states[i % states.size()]
			if _frames == 10:
				var c: int = st[0]
				b.combo_count = c
			var frac: float = st[1]
			b.combo_ticks = roundi(frac * PrototypeCombo.timer_ticks())
		if _frames == 200:
			# Fire events: tower 4 tiers up, tower 6 breaks.
			PrototypeCombo.on_kill(_towers[4])
			_towers[6].combo_count = 0
			_towers[6].combo_ticks = 0
			_towers[1].combo_count += 1
	for v: String in ["A", "B", "C", "D"]:
		var at: int = 160 + 60 * ["A", "B", "C", "D"].find(v)
		if _frames == at - 50:
			PrototypeComboView.variant = v
		if _frames == at - 46:
			_towers[4].combo_count = 3
			_towers[6].combo_count = 5
		if _frames == at - 40:
			PrototypeCombo.on_kill(_towers[4])
			_towers[6].combo_count = 0
			_towers[1].combo_count += 1
		if _frames == at - 32:
			root.get_texture().get_image().save_png("%s/combo_%s.png" % [_out, v])
	return _frames > 420
