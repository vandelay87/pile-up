extends Node

## PROTOTYPE, throwaway: wayfinder ticket "HUD: pace, alert and the end of a run" (#286).
## Lives only on the prototype/v6-hud branch and is never merged. It runs the real game
## (main.tscn) and fakes v6's mining loop over it, to judge how the new controls and readouts
## look and read. Three layouts compete for the pace, the alert, threat, quota and Extract,
## cycled with Tab:
##   A  In the console: everything inside the existing bottom bar, the alert a strip along its top.
##   B  On the base: the pace, the alert ring and the quota drawn on the drill in the world.
##   C  Top strip: a strip across the top of the screen, with banners for waves.
## The smaller readouts get one plain take each, the same in every layout: what's left in each
## deposit under its miner, a rig's on/off switch, which miner a wave is heading for, a soldier
## under repair, and the Debrief.
##
## Fakes: the alert fills by v6's rule (about 60 s at High, x0.6 Low, x0.8 Medium, 0 at Off) and
## starts a REAL wave when full (v5's waves, sized by wave number, not threat). Bounty is taken
## back each frame so gold comes only from the fake mining. Threat, minerals, the quota, the two
## rigs (drawn only, not real buildings) and the siege are faked here. Real enemies still head for
## the base whatever the rigs do; the target marker shows where v6 would send them.
## Keys: Tab layout, [ ] pace, F5 fake time x5, F6 near the quota, F7 lose, F8 dry the base,
## F9 hurt every soldier (to see the repair mark near a repair yard).

const MAIN_SCENE := preload("res://src/view/main.tscn")
const VARIANTS: Array[String] = ["A  In the console", "B  On the base", "C  Top strip"]
const PACES: Array[String] = ["Off", "Low", "Medium", "High"]
const INCOME: Array[float] = [0.0, 0.3, 0.5, 1.0]
const FILL: Array[float] = [0.0, 0.6, 0.8, 1.0]
const FILL_SECONDS := 60.0
const MINE_RATE := 8.0
const WARN_AT := 0.75
const SIEGE_FILL := 2.5
const COUNTDOWN := 75.0
const QUOTA := 960.0
const REPAIR_REACH := 6.0

const GOLD := Color(1.0, 0.85, 0.2)
const AETHER := Color(0.65, 0.5, 1.0)
const ALERT := Color(1.0, 0.6, 0.15)
const DANGER := Color(1.0, 0.3, 0.25)
const QUIET := Color(0.55, 0.8, 1.0)
const DIM := Color(0.7, 0.7, 0.72)
const OK := Color(0.4, 0.9, 0.45)
const PANEL_BG := Color(0.08, 0.09, 0.11, 0.92)
const PANEL_EDGE := Color(0.45, 0.4, 0.3)
const PACE_COLOURS: Array[Color] = [
	Color(0.55, 0.55, 0.6), Color(0.45, 0.8, 0.5), Color(1.0, 0.8, 0.3), Color(1.0, 0.45, 0.3)
]

var _main: Main
var _sim: Simulation
var _hud: Hud
var _variant := 0
var _boost := 1.0

# Fake v6 run, reset by _hook.
var _pace := 2
var _alert := 0.0
var _threat := 1.0
var _time := 0.0
var _pace_time: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _miners: Array[Miner] = []
var _gold_frac := 0.0
var _last_gold := 0
var _gold_mined := 0.0
var _aether_mined := 0.0
var _warned := false
var _in_wave := false
var _wave_pending := false
var _wave_size := 0
var _edges := PackedStringArray()
var _extracting := false
var _countdown := 0.0
var _ended := false
var _peak_wave := 0

var _world: WorldOverlay
var _ui: UiRoot
var _legend := Label.new()
# A
var _a_alert_strip := AlertStrip.new()
var _a_pace_row := HBoxContainer.new()
var _a_pace: Array[Button] = []
var _a_extract := Button.new()
var _a_extra_rows: Array[Control] = []
var _a_mining := Label.new()
var _a_aether := Label.new()
var _wave_name: Label
var _left_name: Label
# B
var _b_panel := VBoxContainer.new()
var _b_pace: Array[Button] = []
var _b_extract := Button.new()
var _b_text := Label.new()
var _b_shout := Label.new()
var _b_shout_tween: Tween
# C
var _c_strip := PanelContainer.new()
var _c_pace: Array[Button] = []
var _c_bar := AlertStrip.new()
var _c_bar_text := Label.new()
var _c_threat := Label.new()
var _c_rate := Label.new()
var _c_quota := AlertStrip.new()
var _c_quota_text := Label.new()
var _c_extract := Button.new()
var _c_banner := Label.new()
var _c_banner_tween: Tween
# Shared plain takes
var _miner_tags: Array[MinerTag] = []
var _debrief := PanelContainer.new()
var _debrief_text := RichTextLabel.new()


class Miner:
	extends RefCounted
	var name := ""
	var cell := Vector2.ZERO
	var is_base := false
	var on := true
	var gold_left := 0.0
	var aether_left := 0.0
	var gold_share := 0.85

	func is_dry() -> bool:
		return gold_left <= 0.0 and aether_left <= 0.0


class MinerTag:
	extends VBoxContainer
	var miner: Miner
	var text := Label.new()
	var toggle := Button.new()


## A horizontal gauge: fill 0..1, coloured, with a tick at the warning mark.
class AlertStrip:
	extends Control
	var fill := 0.0
	var colour := ALERT
	var tick := -1.0
	var back := Color(0, 0, 0, 0.55)

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), back)
		draw_rect(Rect2(Vector2.ZERO, Vector2(size.x * clampf(fill, 0, 1), size.y)), colour)
		if tick >= 0.0:
			var x := size.x * tick
			draw_line(Vector2(x, 0), Vector2(x, size.y), Color(1, 1, 1, 0.8), 2.0)


class WorldOverlay:
	extends Node2D
	var proto: Node

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		proto.call("draw_world", self)


func _ready() -> void:
	process_priority = 100
	_main = MAIN_SCENE.instantiate() as Main
	add_child(_main)
	_hud = _main.get_node("Hud") as Hud
	_world = WorldOverlay.new()
	_world.proto = self
	_world.z_index = RenderingServer.CANVAS_ITEM_Z_MAX - 1
	_main.add_child(_world)
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	_ui = UiRoot.add_to(layer)
	_build_a()
	_build_b()
	_build_c()
	_build_debrief()
	_legend.add_theme_font_size_override("font_size", 12)
	_legend.add_theme_constant_override("outline_size", 4)
	_legend.add_theme_color_override("font_outline_color", Color.BLACK)
	_legend.position = Vector2(8, 110)
	_ui.add_child(_legend)


func _process(delta: float) -> void:
	if _main.simulation == null:
		return
	if _main.simulation != _sim:
		_hook(_main.simulation)
	_take_back_bounty()
	if not _sim.paused and not _ended:
		_step(delta * _sim.speed * _boost)
	_hud._next_wave.visible = false
	_hud._game_over.visible = false
	_refresh()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_TAB:
			_variant = (_variant + 1) % VARIANTS.size()
		KEY_BRACKETLEFT:
			_set_pace(_pace - 1)
		KEY_BRACKETRIGHT:
			_set_pace(_pace + 1)
		KEY_F5:
			_boost = 5.0 if _boost == 1.0 else 1.0
		KEY_F6:
			var gap := QUOTA - 15.0 - _aether_mined
			if gap > 0:
				_aether_mined += gap
				_miners[0].aether_left -= gap
		KEY_F7:
			_end(false)
		KEY_F8:
			_miners[0].gold_left = 0
			_miners[0].aether_left = 0
		KEY_F9:
			for i in _sim.soldiers.count:
				_sim.soldiers.hp[i] = _sim.settings.soldier_hp * 0.4
		_:
			return
	get_viewport().set_input_as_handled()


# --- The fake run --------------------------------------------------------------------------------


func _hook(sim: Simulation) -> void:
	_sim = sim
	_sim.phase_changed.connect(_on_phase)
	_sim.game_over.connect(_end.bind(false))
	_last_gold = _sim.run_state.gold
	_pace = 2
	_alert = 0.0
	_threat = 1.0
	_time = 0.0
	_pace_time = [0.0, 0.0, 0.0, 0.0]
	_gold_mined = 0.0
	_aether_mined = 0.0
	_warned = false
	_in_wave = false
	_wave_pending = false
	_extracting = false
	_ended = false
	_peak_wave = 0
	_debrief.visible = false
	_miners.clear()
	var base := Miner.new()
	base.name = "Drill"
	base.is_base = true
	base.cell = Vector2(_sim.map.base.position) + Vector2(_sim.map.base.size) / 2.0
	base.gold_left = 20000.0
	base.aether_left = 1200.0
	base.gold_share = 0.85
	_miners.append(base)
	var spots := _deposit_spots(base.cell)
	var specs := [["Rig: near", 3000.0, 150.0, 0.95], ["Rig: far", 5000.0, 600.0, 0.85]]
	for k in mini(spots.size(), specs.size()):
		var spec: Array = specs[k]
		var rig := Miner.new()
		rig.name = str(spec[0])
		rig.cell = spots[k]
		var gold: float = spec[1]
		var aether: float = spec[2]
		var share: float = spec[3]
		rig.gold_left = gold
		rig.aether_left = aether
		rig.gold_share = share
		rig.on = k == 0
		_miners.append(rig)
	for tag in _miner_tags:
		tag.queue_free()
	_miner_tags.clear()
	for miner in _miners:
		_miner_tags.append(_make_tag(miner))


# Clear 3x3 spots for the fake rigs, away from the base and the map's edges.
func _deposit_spots(centre: Vector2) -> Array[Vector2]:
	var found: Array[Vector2] = []
	var map := _sim.map
	for step in 8:
		var direction := Vector2.from_angle(TAU * (step * 3 % 8) / 8.0)
		for distance in range(30, 14, -1):
			var cell := Vector2i((centre + direction * distance).round())
			if _clear_block(map, cell):
				var spot := Vector2(cell)
				var far_enough := true
				for other in found:
					if other.distance_to(spot) < 20:
						far_enough = false
				if far_enough:
					found.append(spot)
				break
		if found.size() == 2:
			break
	return found


func _clear_block(map: MapData, cell: Vector2i) -> bool:
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var c := cell + Vector2i(dx, dy)
			if c.x < 6 or c.y < 6 or c.x >= map.width - 6 or c.y >= map.height - 6:
				return false
			if map.is_rock(c) or map.base.has_point(c):
				return false
	return true


func _step(dt: float) -> void:
	_time += dt
	_pace_time[_pace] += dt
	var mined := 0.0
	if not _extracting:
		for miner in _running():
			var amount := MINE_RATE * INCOME[_pace] * dt
			var gold := minf(amount * miner.gold_share, miner.gold_left)
			var aether := minf(amount * (1.0 - miner.gold_share), miner.aether_left)
			miner.gold_left -= gold
			miner.aether_left -= aether
			_gold_mined += gold
			_aether_mined += aether
			_gold_frac += gold
			mined += gold + aether
	if _gold_frac >= 1.0:
		var whole := floori(_gold_frac)
		_gold_frac -= whole
		_sim.add_gold(whole)
		_last_gold += whole
		_sim.gold_changed.emit(_sim.run_state.gold)
	_threat += dt * 0.004 + mined * 0.00075
	if _extracting:
		_countdown -= dt
		_alert += dt / FILL_SECONDS * SIEGE_FILL
		if _alert >= 1.0:
			_alert = 0.0
			_siege_wave()
		if _countdown <= 0.0:
			_end(true)
		return
	if _in_wave or _wave_pending:
		return
	_alert += dt / FILL_SECONDS * _fill_rate()
	if _alert >= WARN_AT and not _warned:
		_warned = true
		_edges = _pick_edges()
		_announce("Wave coming from %s" % ", ".join(_edges), ALERT)
	if _warned:
		_highlight_edges()
	if _alert >= 1.0:
		_alert = 1.0
		_wave_pending = true
		_sim.queue_command(Commands.NextWave.new())


func _fill_rate() -> float:
	if _is_dry():
		return FILL[2]
	return FILL[_pace]


func _running() -> Array[Miner]:
	var running: Array[Miner] = []
	for miner in _miners:
		if miner.on and not miner.is_dry():
			running.append(miner)
	return running


# Every miner dry or no rig running beside a dry base: the pace no longer applies.
func _is_dry() -> bool:
	return _running().is_empty() and _miners[0].is_dry()


func _set_pace(pace: int) -> void:
	if _is_dry() or _extracting or _ended:
		return
	_pace = clampi(pace, 0, 3)


func _pick_edges() -> PackedStringArray:
	var all := _sim.map.spawn_edges.duplicate()
	var count := 1
	if _threat >= 15:
		count = 4
	elif _threat >= 10:
		count = 3
	elif _threat >= 6:
		count = 2
	var picked := PackedStringArray()
	while picked.size() < mini(count, all.size()):
		var edge := all[randi() % all.size()]
		if not edge in picked:
			picked.append(edge)
	return picked


var _highlight_wait := 0.0


func _highlight_edges() -> void:
	_highlight_wait -= get_process_delta_time()
	if _highlight_wait <= 0.0:
		_highlight_wait = 2.5
		(_main.get_node("EdgeHighlight") as EdgeHighlight).announce(_edges)


func _on_phase(phase: Waves.Phase) -> void:
	if phase == Waves.Phase.WAVE:
		_wave_pending = false
		_in_wave = true
		_alert = 0.0
		_wave_size = _sim.enemies_left
		_peak_wave = maxi(_peak_wave, _wave_size)
		_announce(_wave_text(), DANGER)
	else:
		_in_wave = false
		_warned = false
		if not _ended:
			_announce("Wave beaten: the quiet", QUIET)


func _wave_text() -> String:
	var text := "Wave: %d enemies" % _wave_size
	var specials := _sim.waves.special_counts(_sim.run_state.wave)
	for kind: String in ["bloaters", "jumpers", "brutes"]:
		var count: int = specials.get(kind, 0)
		if count > 0:
			text += " · %d %s" % [count, kind if count > 1 else kind.trim_suffix("s")]
	if not _edges.is_empty():
		text += " · from %s" % ", ".join(_edges)
	return text


func _extract() -> void:
	if _aether_mined < QUOTA or _extracting or _ended:
		return
	_extracting = true
	_countdown = COUNTDOWN
	_alert = 0.0
	_announce("Extracting: hold for %d s" % COUNTDOWN, AETHER)
	_siege_wave()


func _siege_wave() -> void:
	if _sim.waves.phase == Waves.Phase.WAVE:
		var size := _sim.waves.size(_sim.run_state.wave + 1)
		_sim.queue_command(Commands.SpawnEnemies.new(Enemies.Kind.NORMAL, size))
		_announce("Siege wave: %d more enemies" % size, DANGER)
	else:
		_sim.queue_command(Commands.NextWave.new())


func _take_back_bounty() -> void:
	var gold := _sim.run_state.gold
	if gold > _last_gold:
		_sim.run_state.gold = _last_gold
		_sim.gold_changed.emit(_last_gold)
	else:
		_last_gold = gold


func _end(won: bool) -> void:
	if _ended:
		return
	_ended = true
	if won:
		_sim.queue_command(Commands.SetPaused.new(true))
	var mined := int(_gold_mined + _aether_mined)
	var outcome := "[color=#7f7]Extracted[/color]" if won else "[color=#f66]Base destroyed[/color]"
	var yield_line := (
		"Yield  [b]%s[/b]" % _num(mined)
		if won
		else "Yield  [b]0[/b]   [s][color=#999]%s[/color][/s] lost" % _num(mined)
	)
	var t := "[center][font_size=30]%s[/font_size]\n%s[/center]\n\n" % [outcome, yield_line]
	t += "[color=#%s]Gold[/color]  %s      " % [GOLD.to_html(false), _num(int(_gold_mined))]
	t += "[color=#%s]Aether[/color]  %s\n" % [AETHER.to_html(false), _num(int(_aether_mined))]
	t += "Threat reached  %.1f      Time  %s      Kills  %s\n" % [
		_threat, _clock(_time), _num(_sim.run_state.kills)
	]
	t += "Biggest wave  %s\n\nTime at each pace\n" % _num(_peak_wave)
	var total := maxf(_time, 1.0)
	for p in 4:
		var share := _pace_time[p] / total
		var bar := "█".repeat(roundi(share * 30))
		t += "[color=#%s]%-7s %s[/color] %s\n" % [
			PACE_COLOURS[p].to_html(false), PACES[p], bar, _clock(_pace_time[p])
		]
	_debrief_text.text = t
	_debrief.visible = true


# --- Readouts ------------------------------------------------------------------------------------


func _refresh() -> void:
	_legend.text = (
		"PROTOTYPE v6 HUD\nlayout %s\n" % VARIANTS[_variant]
		+ "Tab layout · [ ] pace\nF5 time x%d · F6 near quota\nF7 lose · F8 dry base · F9 hurt"
		% int(_boost)
	)
	var a := _variant == 0
	var b := _variant == 1
	var c := _variant == 2
	_a_alert_strip.visible = a
	_a_pace_row.visible = a
	for row in _a_extra_rows:
		row.visible = a
	_wave_name.text = "Threat" if a else "Wave"
	_wave_name.visible = a
	_hud._wave.visible = a
	_left_name.visible = a
	_hud._enemies_left.visible = a
	_b_panel.visible = b
	_c_strip.visible = c
	_c_banner.visible = c
	_refresh_a()
	_refresh_b()
	_refresh_c()
	_refresh_tags()


func _refresh_a() -> void:
	_a_alert_strip.position = Vector2(0, _hud._bar.position.y - 8)
	_a_alert_strip.size = Vector2(_ui.size.x, 8)
	_a_alert_strip.fill = _alert
	_a_alert_strip.colour = _alert_colour()
	_a_alert_strip.tick = WARN_AT
	_a_alert_strip.queue_redraw()
	_hud._wave.text = "%.1f" % _threat
	if _in_wave:
		_left_name.text = "Enemies left"
		_hud._enemies_left.text = "%d / %d" % [_sim.enemies_left, _wave_size]
	else:
		_left_name.text = "Alert"
		_hud._enemies_left.text = _alert_words()
	_a_mining.text = _rate_text()
	_a_aether.text = "%s / %s" % [_num(int(_aether_mined)), _num(int(QUOTA))]
	_paint_pace(_a_pace)
	_paint_extract(_a_extract)


func _refresh_b() -> void:
	var anchor := _to_screen(GridTransform.grid_to_world(_miners[0].cell)) + Vector2(-250, -40)
	_b_panel.position = anchor
	_paint_pace(_b_pace)
	_paint_extract(_b_extract)
	var lines := PackedStringArray(["Threat %.1f   %s" % [_threat, _rate_text()]])
	if _in_wave:
		lines.append("%d / %d enemies left" % [_sim.enemies_left, _wave_size])
	else:
		lines.append(_alert_words())
	_b_text.text = "\n".join(lines)
	_b_shout.position = (
		_to_screen(GridTransform.grid_to_world(_miners[0].cell))
		- Vector2(_b_shout.size.x / 2.0, 120)
	)


func _refresh_c() -> void:
	_paint_pace(_c_pace)
	_paint_extract(_c_extract)
	if _in_wave:
		_c_bar.fill = float(_sim.enemies_left) / maxf(_wave_size, 1)
		_c_bar.colour = DANGER
		_c_bar.tick = -1
		_c_bar_text.text = "WAVE   %d / %d left" % [_sim.enemies_left, _wave_size]
	else:
		_c_bar.fill = _alert
		_c_bar.colour = _alert_colour()
		_c_bar.tick = WARN_AT
		_c_bar_text.text = _alert_words()
	_c_bar.queue_redraw()
	_c_threat.text = "Threat %.1f" % _threat
	_c_rate.text = _rate_text()
	_c_quota.fill = _aether_mined / QUOTA
	_c_quota.colour = AETHER if _aether_mined < QUOTA else OK
	_c_quota.queue_redraw()
	_c_quota_text.text = "Aether %s / %s" % [_num(int(_aether_mined)), _num(int(QUOTA))]
	if _extracting:
		_c_quota_text.text = "EXTRACTING  %s" % _clock(maxf(_countdown, 0))


func _refresh_tags() -> void:
	var target := _target()
	for tag in _miner_tags:
		var m := tag.miner
		var lines := PackedStringArray()
		if m.is_base:
			lines.append("Drill")
		else:
			lines.append("%s · %s" % [m.name, "running" if m.on and not m.is_dry() else "off"])
		if m.is_dry():
			lines.append("Dry")
		else:
			lines.append("Gold %s · Aether %s" % [_num(int(m.gold_left)), _num(int(m.aether_left))])
		if m == target:
			lines.append("▼ enemies heading here")
		tag.text.text = "\n".join(lines)
		tag.text.add_theme_color_override("font_color", DANGER if m == target else Color.WHITE)
		tag.toggle.visible = not m.is_base
		tag.toggle.text = "⏻ On" if m.on else "⏻ Off"
		tag.toggle.modulate = OK if m.on else DIM
		tag.position = (
			_to_screen(GridTransform.grid_to_world(m.cell)) + Vector2(-tag.size.x / 2.0, 26)
		)


# The running miner nearest the wave's first edge, while a wave is coming or on.
func _target() -> Miner:
	if not (_in_wave or _warned) or _edges.is_empty():
		return null
	var map := _sim.map
	var mids := {
		"N": Vector2(map.width / 2.0, 0),
		"S": Vector2(map.width / 2.0, map.height),
		"W": Vector2(0, map.height / 2.0),
		"E": Vector2(map.width, map.height / 2.0),
	}
	var from: Vector2 = mids.get(_edges[0], Vector2.ZERO)
	var best: Miner = null
	for miner in _miners:
		if not miner.on:
			continue
		if best == null or from.distance_to(miner.cell) < from.distance_to(best.cell):
			best = miner
	return best


func draw_world(canvas: Node2D) -> void:
	if _sim == null:
		return
	var font := ThemeDB.fallback_font
	# The fake rigs: a 3x3 footprint, lit when running.
	for miner in _miners:
		if miner.is_base:
			continue
		var r := Rect2(miner.cell - Vector2(1, 1), Vector2(3, 3))
		var corners := PackedVector2Array(
			[r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
		)
		var colour := Color(0.3, 0.75, 0.4, 0.85) if miner.on else Color(0.4, 0.4, 0.45, 0.85)
		canvas.draw_colored_polygon(GridTransform.XF * corners, colour)
		var deposit := Rect2(miner.cell - Vector2(2.5, 2.5), Vector2(6, 6))
		var outline := PackedVector2Array(
			[
				deposit.position,
				Vector2(deposit.end.x, deposit.position.y),
				deposit.end,
				Vector2(deposit.position.x, deposit.end.y),
				deposit.position
			]
		)
		canvas.draw_polyline(GridTransform.XF * outline, Color(GOLD, 0.6), 2.0)
	var target := _target()
	if target != null:
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 150.0)
		canvas.draw_polyline(
			GridTransform.circle(target.cell, 5.5 + pulse * 0.6), Color(DANGER, 0.9), 3.0
		)
	_draw_repair_marks(canvas)
	if _variant == 1:
		_draw_base_gauges(canvas, font)


func _draw_base_gauges(canvas: Node2D, font: Font) -> void:
	var centre := _miners[0].cell
	var radius := maxf(_sim.map.base.size.x, _sim.map.base.size.y) / 2.0 + 1.6
	canvas.draw_polyline(GridTransform.circle(centre, radius), Color(0, 0, 0, 0.5), 9.0)
	if _in_wave:
		var left := float(_sim.enemies_left) / maxf(_wave_size, 1)
		canvas.draw_polyline(_arc(centre, radius, left), DANGER, 7.0)
	elif _alert > 0.0:
		canvas.draw_polyline(_arc(centre, radius, _alert), _alert_colour(), 7.0)
	var warn := GridTransform.grid_to_world(centre + Vector2.from_angle(-PI / 2 + TAU * WARN_AT) * radius)
	canvas.draw_circle(warn, 4.0, Color.WHITE)
	var inner := radius - 0.9
	canvas.draw_polyline(GridTransform.circle(centre, inner), Color(0, 0, 0, 0.4), 5.0)
	var quota := clampf(_aether_mined / QUOTA, 0, 1)
	if quota > 0:
		canvas.draw_polyline(_arc(centre, inner, quota), AETHER if quota < 1 else OK, 4.0)
	# Pace pips under the drill.
	var foot := GridTransform.grid_to_world(centre) + Vector2(-30, 52)
	for p in range(1, 4):
		var lit := _pace >= p and not _is_dry()
		var colour := PACE_COLOURS[_pace] if lit else Color(0.2, 0.2, 0.22)
		canvas.draw_rect(Rect2(foot + Vector2((p - 1) * 22, -p * 5), Vector2(16, 6 + p * 5)), colour)
	canvas.draw_string(
		font, foot + Vector2(-4, 22), "DRY" if _is_dry() else PACES[_pace].to_upper(),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE
	)


func _arc(centre: Vector2, radius: float, fraction: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var steps := maxi(2, int(64 * fraction))
	for k in steps + 1:
		var angle := -PI / 2 + TAU * fraction * k / steps
		points.append(GridTransform.grid_to_world(centre + Vector2.from_angle(angle) * radius))
	return points


# Soldiers near a repair yard and below 70% HP move but hold fire: a green cross over them.
func _draw_repair_marks(canvas: Node2D) -> void:
	var yards: Array[Vector2] = []
	for building in _sim.buildings.built:
		if building.kind == Buildings.REPAIR_YARD and building.powered:
			yards.append(building.centre)
	if yards.is_empty():
		return
	var soldiers := _sim.soldiers
	for i in soldiers.count:
		if soldiers.hp[i] >= _sim.settings.soldier_hp * 0.7:
			continue
		var position := soldiers.positions[i]
		var near := false
		for yard in yards:
			if yard.distance_to(position) <= REPAIR_REACH:
				near = true
		if not near:
			continue
		var top := GridTransform.grid_to_world(position) + Vector2(0, -34)
		canvas.draw_rect(Rect2(top - Vector2(6, 2), Vector2(12, 4)), OK)
		canvas.draw_rect(Rect2(top - Vector2(2, 6), Vector2(4, 12)), OK)


# --- Building the layouts -----------------------------------------------------------------------


func _build_a() -> void:
	var grid := _hud._gold.get_parent() as GridContainer
	_wave_name = grid.get_child(_hud._wave.get_index() - 1) as Label
	_left_name = grid.get_child(_hud._enemies_left.get_index() - 1) as Label
	for pair: Array in [["Mining", _a_mining, GOLD], ["Aether", _a_aether, AETHER]]:
		var name_label := Label.new()
		name_label.text = pair[0]
		name_label.add_theme_font_size_override("font_size", 15)
		name_label.add_theme_color_override("font_color", DIM)
		var value: Label = pair[1]
		value.add_theme_font_size_override("font_size", 15)
		var colour: Color = pair[2]
		value.add_theme_color_override("font_color", colour)
		grid.add_child(name_label)
		grid.add_child(value)
		_a_extra_rows.append_array([name_label, value])
	var commands := _hud._next_wave.get_parent() as GridContainer
	var card := commands.get_parent() as PanelContainer
	card.remove_child(commands)
	var column := VBoxContainer.new()
	column.add_child(commands)
	column.add_child(_a_pace_row)
	card.add_child(column)
	_a_pace = _pace_buttons(_a_pace_row, ["Off", "Low", "Med", "High"], Vector2(40, 26))
	_setup_extract(_a_extract, Vector2(56, 26))
	_a_pace_row.add_child(_a_extract)
	_ui.add_child(_a_alert_strip)


func _build_b() -> void:
	_b_panel.add_theme_constant_override("separation", 2)
	var style := _style(Color(0.08, 0.09, 0.11, 0.75))
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", style)
	var inner := VBoxContainer.new()
	var row := HBoxContainer.new()
	_b_pace = _pace_buttons(row, ["Off", "Low", "Med", "High"], Vector2(38, 24))
	inner.add_child(row)
	_b_text.add_theme_font_size_override("font_size", 13)
	inner.add_child(_b_text)
	_setup_extract(_b_extract, Vector2(0, 26))
	inner.add_child(_b_extract)
	box.add_child(inner)
	_b_panel.add_child(box)
	_ui.add_child(_b_panel)
	_b_shout.add_theme_font_size_override("font_size", 18)
	_b_shout.add_theme_constant_override("outline_size", 6)
	_b_shout.add_theme_color_override("font_outline_color", Color.BLACK)
	_b_shout.modulate.a = 0
	_ui.add_child(_b_shout)


func _build_c() -> void:
	_c_strip.add_theme_stylebox_override("panel", _style(PANEL_BG))
	_c_strip.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE)
	_c_strip.grow_horizontal = Control.GROW_DIRECTION_BOTH
	var column := VBoxContainer.new()
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	_c_pace = _pace_buttons(top, ["Off", "Low", "Med", "High"], Vector2(44, 26))
	var gauge := Control.new()
	gauge.custom_minimum_size = Vector2(300, 26)
	_c_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	gauge.add_child(_c_bar)
	_c_bar_text.set_anchors_preset(Control.PRESET_FULL_RECT)
	_c_bar_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_c_bar_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_c_bar_text.add_theme_constant_override("outline_size", 4)
	_c_bar_text.add_theme_color_override("font_outline_color", Color.BLACK)
	gauge.add_child(_c_bar_text)
	top.add_child(gauge)
	_c_threat.add_theme_font_size_override("font_size", 16)
	top.add_child(_c_threat)
	_c_rate.add_theme_color_override("font_color", GOLD)
	top.add_child(_c_rate)
	column.add_child(top)
	var bottom := HBoxContainer.new()
	var quota := Control.new()
	quota.custom_minimum_size = Vector2(0, 18)
	quota.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_c_quota.set_anchors_preset(Control.PRESET_FULL_RECT)
	quota.add_child(_c_quota)
	_c_quota_text.set_anchors_preset(Control.PRESET_FULL_RECT)
	_c_quota_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_c_quota_text.add_theme_font_size_override("font_size", 12)
	_c_quota_text.add_theme_constant_override("outline_size", 4)
	_c_quota_text.add_theme_color_override("font_outline_color", Color.BLACK)
	quota.add_child(_c_quota_text)
	bottom.add_child(quota)
	_setup_extract(_c_extract, Vector2(70, 18))
	bottom.add_child(_c_extract)
	column.add_child(bottom)
	_c_strip.add_child(column)
	_ui.add_child(_c_strip)
	_c_strip.position.y = 4
	_c_banner.add_theme_font_size_override("font_size", 26)
	_c_banner.add_theme_constant_override("outline_size", 8)
	_c_banner.add_theme_color_override("font_outline_color", Color.BLACK)
	_c_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE)
	_c_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_c_banner.position.y = 84
	_c_banner.modulate.a = 0
	_ui.add_child(_c_banner)


func _build_debrief() -> void:
	_debrief.add_theme_stylebox_override("panel", _style(Color(0.06, 0.07, 0.09, 0.96)))
	_debrief_text.bbcode_enabled = true
	_debrief_text.fit_content = true
	_debrief_text.custom_minimum_size = Vector2(460, 0)
	_debrief_text.add_theme_font_override("mono_font", ThemeDB.fallback_font)
	var column := VBoxContainer.new()
	var title := Label.new()
	title.text = "Debrief"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", DIM)
	column.add_child(title)
	column.add_child(_debrief_text)
	var restart := Button.new()
	restart.text = "New run"
	restart.focus_mode = Control.FOCUS_NONE
	restart.pressed.connect(
		func() -> void:
			_sim.queue_command(Commands.SetPaused.new(false))
			_sim.queue_command(Commands.Restart.new())
	)
	column.add_child(restart)
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 20)
	margin.add_child(column)
	_debrief.add_child(margin)
	_debrief.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	_debrief.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_debrief.grow_vertical = Control.GROW_DIRECTION_BOTH
	_debrief.visible = false
	_ui.add_child(_debrief)


func _make_tag(miner: Miner) -> MinerTag:
	var tag := MinerTag.new()
	tag.miner = miner
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag.text.add_theme_font_size_override("font_size", 11)
	tag.text.add_theme_constant_override("outline_size", 4)
	tag.text.add_theme_color_override("font_outline_color", Color.BLACK)
	tag.text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.add_child(tag.text)
	tag.toggle.focus_mode = Control.FOCUS_NONE
	tag.toggle.add_theme_font_size_override("font_size", 11)
	tag.toggle.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	tag.toggle.pressed.connect(func() -> void: miner.on = not miner.on)
	tag.add_child(tag.toggle)
	_ui.add_child(tag)
	_ui.move_child(tag, 0)
	return tag


func _pace_buttons(parent: Container, names: Array, size: Vector2) -> Array[Button]:
	var buttons: Array[Button] = []
	var group := ButtonGroup.new()
	for p in names.size():
		var button := Button.new()
		button.text = names[p]
		button.toggle_mode = true
		button.button_group = group
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = size
		button.add_theme_font_size_override("font_size", 12)
		button.pressed.connect(_set_pace.bind(p))
		buttons.append(button)
		parent.add_child(button)
	return buttons


func _setup_extract(button: Button, size: Vector2) -> void:
	button.text = "Extract"
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = size
	button.add_theme_font_size_override("font_size", 12)
	button.pressed.connect(_extract)


func _paint_pace(buttons: Array[Button]) -> void:
	var locked := _is_dry() or _extracting or _ended
	for p in buttons.size():
		var button := buttons[p]
		button.set_pressed_no_signal(p == _pace and not locked)
		button.disabled = locked
		button.modulate = PACE_COLOURS[p] if p == _pace and not locked else Color.WHITE
		button.tooltip_text = "Dry: waves at Medium" if _is_dry() else ""


func _paint_extract(button: Button) -> void:
	if _extracting:
		button.disabled = true
		button.text = "Extracting %s" % _clock(maxf(_countdown, 0))
		button.modulate = AETHER
	elif _aether_mined >= QUOTA:
		button.disabled = false
		button.text = "Extract"
		button.modulate = OK
	else:
		button.disabled = true
		button.text = "Extract %d%%" % int(100 * _aether_mined / QUOTA)
		button.modulate = DIM


func _announce(text: String, colour: Color) -> void:
	_hud._show_toast(text)
	_hud._toast.add_theme_color_override("font_color", colour)
	_b_shout.text = text
	_b_shout.add_theme_color_override("font_color", colour)
	if _b_shout_tween != null:
		_b_shout_tween.kill()
	_b_shout.modulate.a = 1.0
	_b_shout_tween = create_tween()
	_b_shout_tween.tween_interval(2.5)
	_b_shout_tween.tween_property(_b_shout, "modulate:a", 0.0, 1.0)
	_c_banner.text = text
	_c_banner.add_theme_color_override("font_color", colour)
	if _c_banner_tween != null:
		_c_banner_tween.kill()
	_c_banner.modulate.a = 1.0
	_c_banner_tween = create_tween()
	_c_banner_tween.tween_interval(2.5)
	_c_banner_tween.tween_property(_c_banner, "modulate:a", 0.0, 1.0)


# --- Helpers -------------------------------------------------------------------------------------


func _alert_colour() -> Color:
	return DANGER if _alert >= WARN_AT else ALERT


func _alert_words() -> String:
	if _wave_pending:
		return "Wave arriving"
	if _is_dry():
		return "Alert %d%% (dry: at Medium)" % int(_alert * 100)
	if _pace == 0 and not _extracting:
		return "Alert %d%% · not filling" % int(_alert * 100)
	if _alert >= WARN_AT:
		return "Alert %d%% · wave coming" % int(_alert * 100)
	return "Alert %d%%" % int(_alert * 100)


func _rate_text() -> String:
	var rate := 0.0
	if not _extracting:
		for miner in _running():
			if miner.gold_left > 0:
				rate += MINE_RATE * INCOME[_pace] * miner.gold_share
	return "+%.1f gold/s" % rate


func _to_screen(world: Vector2) -> Vector2:
	var layer := _ui.get_parent() as CanvasLayer
	return (_main.get_viewport().get_canvas_transform() * world) / layer.scale.x


func _style(background: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = PANEL_EDGE
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(6)
	return style


static func _num(value: int) -> String:
	var digits := str(absi(value))
	var out := ""
	while digits.length() > 3:
		out = "," + digits.substr(digits.length() - 3) + out
		digits = digits.substr(0, digits.length() - 3)
	return ("-" if value < 0 else "") + digits + out


static func _clock(seconds: float) -> String:
	var s := int(seconds)
	return "%d:%02d" % [s / 60, s % 60]
