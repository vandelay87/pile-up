# PROTOTYPE, throwaway (Combo prototype #104): four looks for a building's combo above it,
# cycled with Left and Right (or start on one with `-- --combo=C`). K fakes kills on every
# powered tower so many combos run at once; G adds 1000 gold. Hidden at x1, as decided in #97.
# The same drawing is reused large in the bottom HUD's details (see PrototypeBottomHud).
class_name PrototypeComboView
extends Node2D

const VARIANTS: Array[String] = ["A", "B", "C", "D"]
const NAMES := {
	"A": "Ring: tier in a ring, timer inside",
	"B": "Badge: tier and count, bars below",
	"C": "Number: grows with tier, pips to next",
	"D": "Aura and chevrons: no numbers",
}
## Tier colours: shades of gold, kept apart from the pressure gauge's yellow, orange and red.
const TIER_COLOURS := {
	2: Color(0.95, 0.85, 0.45),
	3: Color(1.0, 0.75, 0.1),
	4: Color(1.0, 0.97, 0.8),
}
const BACK := Color(0.07, 0.07, 0.09, 0.85)
const BREAK_RED := Color(0.95, 0.25, 0.2)
## World pixels from a tower's ground centre to its top, and the on-screen size factor.
const RAISE := 60.0
const SCREEN_SCALE := 1.3
const BREAK_SECONDS := 0.8
const TIER_UP_SECONDS := 0.45
const BEAT_SECONDS := 0.15
const POP_SECONDS := 0.8

static var variant := "A"
static var instance: PrototypeComboView

var fake_kills := false
var _simulation: Simulation
var _fx: Dictionary[int, Fx] = {}


## What the view remembers of one building's combo, to animate its events.
class Fx:
	extends RefCounted

	var count := 0
	var tier := 1
	var timer := 0.0
	var since_kill := 99.0
	var since_tier_up := 99.0
	var since_break := 99.0
	var break_tier := 1
	var break_count := 0
	var pops: Array[Array] = []  # [age, text]
	var fake_rate := 0.0
	var fake_reroll := 0.0
	var position := Vector2.ZERO
	var ground := PackedVector2Array()

	func visible() -> bool:
		return tier >= 2 or since_break < PrototypeComboView.BREAK_SECONDS or not pops.is_empty()


func setup(simulation: Simulation) -> void:
	_simulation = simulation
	_fx.clear()
	z_index = RenderingServer.CANVAS_ITEM_Z_MAX
	instance = self


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--combo="):
			var picked := arg.trim_prefix("--combo=").to_upper()
			if picked in VARIANTS:
				variant = picked


static func cycle(step: int) -> void:
	var i := VARIANTS.find(variant)
	variant = VARIANTS[wrapi(i + step, 0, VARIANTS.size())]


static func label() -> String:
	return "%s  %s" % [variant, NAMES[variant]]


func fx_of(id: int) -> Fx:
	return _fx.get(id, null)


func _process(delta: float) -> void:
	if _simulation == null:
		return
	var seen := {}
	for building in _simulation.buildings.built:
		if building.kind != Buildings.TOWER:
			continue
		seen[building.id] = true
		var fx: Fx = _fx.get(building.id)
		if fx == null:
			fx = Fx.new()
			fx.position = GridTransform.grid_to_world(building.centre)
			fx.ground = _ground(building)
			_fx[building.id] = fx
		if fake_kills and building.powered:
			_fake(building, fx, delta)
		_observe(building, fx, delta)
	for id: int in _fx.keys():
		if not seen.has(id):
			_fx.erase(id)
	queue_redraw()


func _fake(building: Buildings.Building, fx: Fx, delta: float) -> void:
	fx.fake_reroll -= delta
	if fx.fake_reroll <= 0.0:
		fx.fake_rate = randf_range(0.0, 3.5)
		fx.fake_reroll = randf_range(3.0, 7.0)
	if randf() < fx.fake_rate * delta:
		PrototypeCombo.on_kill(building)


func _observe(building: Buildings.Building, fx: Fx, delta: float) -> void:
	fx.since_kill += delta
	fx.since_tier_up += delta
	fx.since_break += delta
	for pop in fx.pops:
		pop[0] += delta
	fx.pops = fx.pops.filter(func(pop: Array) -> bool: return pop[0] < POP_SECONDS)
	var count := building.combo_count
	if count < fx.count:
		if fx.tier >= 2:
			fx.since_break = 0.0
			fx.break_tier = fx.tier
			fx.break_count = fx.count
		fx.count = 0
		fx.tier = 1
	if count > fx.count:
		var tier := PrototypeCombo.tier(count)
		if tier > fx.tier:
			fx.since_tier_up = 0.0
		fx.since_kill = 0.0
		var bounty := _simulation.settings.enemy_bounty
		if tier >= 2:
			fx.pops.append([0.0, "+%d" % (bounty * tier * (count - fx.count))])
		fx.count = count
		fx.tier = tier
	fx.timer = float(building.combo_ticks) / PrototypeCombo.timer_ticks()


func _ground(building: Buildings.Building) -> PackedVector2Array:
	var size := Vector2(Buildings.footprint_size(building.kind))
	var o := Vector2(building.origin) - Vector2(0.25, 0.25)
	var e := size + Vector2(0.5, 0.5)
	var points := PackedVector2Array()
	for corner: Vector2 in [Vector2(0, 0), Vector2(e.x, 0), e, Vector2(0, e.y)]:
		points.append(GridTransform.grid_to_world(o + corner) - GridTransform.grid_to_world(building.centre))
	return points


# Drawn at a steady size on screen, whatever the zoom, so a zoomed-out late wave stays legible.
func _draw() -> void:
	var camera := get_viewport().get_camera_2d()
	var zoom := camera.zoom.x if camera != null else 1.0
	var s := clampf(SCREEN_SCALE / zoom, 0.5, 6.0)
	for fx: Fx in _fx.values():
		if fx.visible():
			draw_combo(self, fx.position, fx, s, RAISE + 20.0 * s)


## Draws one combo for a building whose ground centre is `at`, `lift` pixels above it.
static func draw_combo(
	ci: CanvasItem, at: Vector2, fx: Fx, s: float, lift: float, ground_scale := 1.0
) -> void:
	var top := at + Vector2(0, -lift)
	match variant:
		"A":
			_draw_ring(ci, top, fx, s)
		"B":
			_draw_badge(ci, top, fx, s, at)
		"C":
			_draw_number(ci, top, fx, s)
		"D":
			_draw_aura(ci, top, fx, s, at, ground_scale)


static func _colour(tier: int) -> Color:
	return TIER_COLOURS.get(mini(tier, 4), Color.WHITE)


static func _ease(seconds: float, length: float) -> float:
	return clampf(1.0 - seconds / length, 0.0, 1.0)


static func _text(ci: CanvasItem, centre: Vector2, text: String, size: float, colour: Color) -> void:
	var font := ThemeDB.fallback_font
	var px := maxi(1, roundi(size))
	var dims := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px)
	var pos := centre + Vector2(-dims.x / 2.0, dims.y * 0.3)
	ci.draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, maxi(2, px / 5), Color(0, 0, 0, colour.a))
	ci.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, colour)


static func _draw_break_text(ci: CanvasItem, top: Vector2, fx: Fx, s: float, text: String) -> void:
	var k := fx.since_break / BREAK_SECONDS
	if k >= 1.0:
		return
	var colour := BREAK_RED
	colour.a = 1.0 - k
	_text(ci, top + Vector2(0, 26 * k * s), text, 14 * s, colour)


# --- A: ring. Outer arc fills to the next tier, inner arc is the timer running down. ------


static func _draw_ring(ci: CanvasItem, top: Vector2, fx: Fx, s: float) -> void:
	if fx.tier < 2:
		_draw_break_text(ci, top, fx, s, "x%d" % fx.break_tier)
		if fx.since_break < BREAK_SECONDS:
			var k := fx.since_break / BREAK_SECONDS
			var red := BREAK_RED
			red.a = 1.0 - k
			for i in 4:
				var a := i * TAU / 4.0 + k * 0.8
				ci.draw_arc(top, 14 * s * (1 + k * 0.6), a, a + 0.9, 8, red, 3 * s)
		return
	var colour := _colour(fx.tier)
	var beat := 1.0 + 0.18 * _ease(fx.since_kill, BEAT_SECONDS)
	var up := _ease(fx.since_tier_up, TIER_UP_SECONDS)
	var r := 14.0 * s * beat
	ci.draw_circle(top, r + 2 * s, BACK)
	ci.draw_arc(top, r, 0, TAU, 32, Color(1, 1, 1, 0.15), 3 * s)
	ci.draw_arc(top, r, -PI / 2, -PI / 2 + TAU * PrototypeCombo.progress(fx.count), 32, colour, 3 * s)
	var timer_colour := Color(1, 1, 1, 0.75) if fx.timer > 0.3 else BREAK_RED
	ci.draw_arc(top, r - 5 * s, -PI / 2, -PI / 2 + TAU * fx.timer, 32, timer_colour, 1.5 * s)
	_text(ci, top, "x%d" % fx.tier, 13 * s * (1 + up * 0.8), colour.lerp(Color.WHITE, up))
	if up > 0.0:
		var ring := colour
		ring.a = up
		ci.draw_arc(top, r * (1 + 2.0 * (1 - up)), 0, TAU, 32, ring, 2 * s)


# --- B: badge. "x3 | 14" pill, a progress bar to the next tier, a timer line under it,
# and "+gold" pops rising off the building. ------------------------------------------------


static func _draw_badge(ci: CanvasItem, top: Vector2, fx: Fx, s: float, at: Vector2) -> void:
	for pop in fx.pops:
		var k: float = pop[0] / POP_SECONDS
		var gold := Color(1, 0.85, 0.2, 1.0 - k)
		var pop_text: String = pop[1]
		_text(ci, at + Vector2(14 * s, (-60 - 40 * k) * s), pop_text, 11 * s, gold)
	var w := 50.0 * s
	var h := 17.0 * s
	if fx.tier < 2:
		if fx.since_break < BREAK_SECONDS:
			var k := fx.since_break / BREAK_SECONDS
			var rect := Rect2(top + Vector2(-w / 2, -h / 2 + 22 * k * s), Vector2(w, h))
			ci.draw_rect(rect, Color(0.5, 0.08, 0.06, 0.9 * (1 - k)))
			_text(ci, rect.get_center(), "break", 12 * s, Color(1, 0.8, 0.8, 1 - k))
		return
	var colour := _colour(fx.tier)
	var up := _ease(fx.since_tier_up, TIER_UP_SECONDS)
	var beat := _ease(fx.since_kill, BEAT_SECONDS)
	var rect := Rect2(top - Vector2(w / 2, h / 2), Vector2(w, h))
	ci.draw_rect(rect, BACK.lerp(colour, up * 0.6))
	ci.draw_rect(rect, colour, false, 1.5 * s)
	_text(ci, rect.position + Vector2(w * 0.27, h / 2), "x%d" % fx.tier, 13 * s, colour)
	ci.draw_line(rect.position + Vector2(w * 0.52, 3 * s), rect.position + Vector2(w * 0.52, h - 3 * s), Color(1, 1, 1, 0.3), 1.0 * s)
	_text(ci, rect.position + Vector2(w * 0.76, h / 2), "%d" % fx.count, 12 * s * (1 + beat * 0.35), Color.WHITE)
	var bar := Rect2(rect.position + Vector2(0, h + 2 * s), Vector2(w, 4 * s))
	ci.draw_rect(bar, BACK)
	ci.draw_rect(Rect2(bar.position, Vector2(w * PrototypeCombo.progress(fx.count), bar.size.y)), colour)
	var tw := w * fx.timer
	var timer_colour := Color(1, 1, 1, 0.8) if fx.timer > 0.3 else BREAK_RED
	var ty := bar.end.y + 2 * s
	ci.draw_line(Vector2(top.x - tw / 2, ty), Vector2(top.x + tw / 2, ty), timer_colour, 2 * s)
	if up > 0.0:
		var c := colour
		c.a = up
		_text(ci, top + Vector2(0, (-16 - 18 * (1 - up)) * s), "x%d!" % fx.tier, 18 * s, c)


# --- C: the number alone. It grows with the tier and fades as the timer runs down; pips
# under it fill towards the next tier. -----------------------------------------------------


static func _draw_number(ci: CanvasItem, top: Vector2, fx: Fx, s: float) -> void:
	if fx.tier < 2:
		if fx.since_break < BREAK_SECONDS:
			var k := fx.since_break / BREAK_SECONDS
			var grey := Color(0.6, 0.6, 0.6, 1 - k)
			var size := (17.0 + 6.0 * (fx.break_tier - 2)) * s
			_text(ci, top + Vector2(10 * k * s, 30 * k * k * s), "x%d" % fx.break_tier, size, grey)
		return
	var colour := _colour(fx.tier)
	var up := _ease(fx.since_tier_up, TIER_UP_SECONDS * 0.7)
	var beat := _ease(fx.since_kill, BEAT_SECONDS)
	colour.a = 0.35 + 0.65 * fx.timer
	if fx.timer < 0.25 and fmod(fx.timer * 20.0, 1.0) < 0.5:
		colour.a = 0.2
	var size := (17.0 + 6.0 * (fx.tier - 2)) * s * (1 + up * 1.2 + beat * 0.12)
	_text(ci, top, "x%d" % fx.tier, size, colour.lerp(Color.WHITE, up))
	var next := PrototypeCombo.next_of(fx.tier)
	if next < 0:
		return
	var start := PrototypeCombo.floor_of(fx.tier)
	var pips := next - start
	var filled := fx.count - start
	var gap := 5.0 * s
	var y := top.y + size * 0.55 + 4 * s
	var x0 := top.x - gap * (pips - 1) / 2.0
	for i in pips:
		var p := Vector2(x0 + i * gap, y)
		var r := 1.7 * s
		if i == filled - 1:
			r *= 1 + beat
		if i < filled:
			ci.draw_circle(p, r, colour)
		else:
			ci.draw_arc(p, r, 0, TAU, 8, Color(1, 1, 1, 0.35), 1.0 * s)


# --- D: no numbers. A ground aura round the building burns down like a fuse with the timer;
# chevrons above stack one per tier, the next one filling with progress. -----------------


static func _draw_aura(
	ci: CanvasItem, top: Vector2, fx: Fx, s: float, at: Vector2, ground_scale: float
) -> void:
	var ground := PackedVector2Array()
	for p in fx.ground:
		ground.append(at + p * ground_scale)
	if ground.is_empty():
		return
	var closed := ground.duplicate()
	closed.append(ground[0])
	if fx.tier < 2:
		if fx.since_break < BREAK_SECONDS:
			var k := fx.since_break / BREAK_SECONDS
			if fmod(k * 8.0, 1.0) < 0.6:
				ci.draw_polyline(closed, Color(BREAK_RED, 1 - k), 3 * s)
		return
	var colour := _colour(fx.tier)
	var beat := _ease(fx.since_kill, BEAT_SECONDS)
	var up := _ease(fx.since_tier_up, TIER_UP_SECONDS)
	var glow := colour
	glow.a = 0.18 + 0.3 * beat
	ci.draw_colored_polygon(ground, Color(colour, 0.08 + 0.12 * beat))
	ci.draw_polyline(closed, glow, (4 + 3 * fx.tier) * s)
	ci.draw_polyline(_fuse(closed, fx.timer), colour, (1.5 + fx.tier) * s)
	if up > 0.0:
		var wide := PackedVector2Array()
		for p in closed:
			wide.append(at + (p - at) * (1 + 0.8 * (1 - up)))
		ci.draw_polyline(wide, Color(colour, up), 2 * s)
	var cw := 22.0 * s
	var ch := 8.0 * s
	var step := 9.0 * s
	var tiers := fx.tier - 1
	for i in tiers + 1:
		var c := top + Vector2(0, -i * step + (tiers * step) / 2.0)
		var points := PackedVector2Array([c + Vector2(-cw / 2, 0), c + Vector2(0, -ch), c + Vector2(cw / 2, 0)])
		if i < tiers:
			ci.draw_polyline(points, Color.BLACK, 5 * s)
			ci.draw_polyline(points, colour.lerp(Color.WHITE, up), 3 * s)
		elif PrototypeCombo.next_of(fx.tier) >= 0:
			ci.draw_polyline(points, Color(1, 1, 1, 0.25), 3 * s)
			var p := PrototypeCombo.progress(fx.count)
			if p > 0.0:
				ci.draw_polyline(_fuse(points, p), Color(colour, 0.7), 3 * s)


## The first `fraction` of a polyline's length.
static func _fuse(points: PackedVector2Array, fraction: float) -> PackedVector2Array:
	var total := 0.0
	for i in points.size() - 1:
		total += points[i].distance_to(points[i + 1])
	var left := total * clampf(fraction, 0.0, 1.0)
	var out := PackedVector2Array([points[0]])
	for i in points.size() - 1:
		var d := points[i].distance_to(points[i + 1])
		if left >= d:
			out.append(points[i + 1])
			left -= d
		else:
			out.append(points[i].lerp(points[i + 1], left / d))
			break
	if out.size() < 2:
		out.append(points[0])
	return out
