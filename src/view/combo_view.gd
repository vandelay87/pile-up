class_name ComboView
extends Node2D

## Draws a gold ring above each building and soldier with a combo, from Combos each frame, at a
## steady size on screen whatever the zoom; hidden at x1. Its tier sits in the middle, an outer
## arc fills towards the next tier (full at the cap) and an inner arc is the timer, red when
## nearly out.
## combo_events animate it: a kill pulses it, a tier-up sends a ring outwards as the number
## swells, and a break scatters red arc fragments as the old tier drops away.

## Tier colours: shades of gold, kept apart from the pressure gauge's yellow, orange and red.
const TIER_COLOURS := {
	1: Color(0.75, 0.7, 0.55),
	2: Color(0.95, 0.85, 0.45),
	3: Color(1.0, 0.75, 0.1),
}
const BACK := Color(0.07, 0.07, 0.09, 0.85)
const TRACK := Color(1, 1, 1, 0.15)
const TIMER_COLOUR := Color(1, 1, 1, 0.75)
const BREAK_RED := Color(0.95, 0.25, 0.2)
## The share of the timer left below which it turns red.
const TIMER_LOW := 0.3
## World pixels from a building's ground centre to its top, and the on-screen size factor.
const RAISE := 60.0
## World pixels from a soldier's feet to the top of its head, before its pile lift.
const SOLDIER_RAISE := 26.0
const SCREEN_SCALE := 1.9
const BREAK_SECONDS := 0.8
const TIER_UP_SECONDS := 0.45
const BEAT_SECONDS := 0.15

var _simulation: Simulation
var _rings: Dictionary[int, Ring] = {}


## What the view shows of one building's combo: the simulation's numbers this frame, and how
## long since each event, to animate it.
class Ring:
	extends RefCounted

	var tier := 1
	var progress := 0.0
	var timer := 0.0
	var since_kill := 99.0
	var since_tier_up := 99.0
	var since_break := 99.0
	var break_tier := 1

	func is_shown() -> bool:
		return tier >= 2 or since_break < ComboView.BREAK_SECONDS


func setup(simulation: Simulation) -> void:
	_simulation = simulation
	_rings.clear()
	z_index = RenderingServer.CANVAS_ITEM_Z_MAX
	_simulation.combo_events.connect(_animate)
	queue_redraw()


## The building's ring as shown this frame, or null when it has no combo.
func ring_of(building_id: int) -> Ring:
	return _rings.get(building_id, null)


func _animate(events: Array[Combos.Event]) -> void:
	for event in events:
		var ring := _ring_for(event.building_id)
		match event.kind:
			Combos.EventKind.KILL:
				ring.since_kill = 0.0
			Combos.EventKind.TIER_UP:
				ring.since_tier_up = 0.0
			Combos.EventKind.BREAK:
				if event.tier >= 2:
					ring.since_break = 0.0
					ring.break_tier = event.tier


func _ring_for(building_id: int) -> Ring:
	var ring: Ring = _rings.get(building_id)
	if ring == null:
		ring = Ring.new()
		_rings[building_id] = ring
	return ring


func _process(delta: float) -> void:
	if _simulation == null:
		return
	var combos := _simulation.combos
	for id: int in _rings.keys():
		var combo := combos.combo(id)
		if combo == null:
			_rings.erase(id)
			continue
		var ring := _rings[id]
		ring.since_kill += delta
		ring.since_tier_up += delta
		ring.since_break += delta
		ring.tier = combo.tier
		ring.progress = combos.progress(combo.count)
		ring.timer = combos.timer_left(id, _simulation.tick_count)
	queue_redraw()


func _draw() -> void:
	if _simulation == null:
		return
	var camera := get_viewport().get_camera_2d()
	var zoom := camera.zoom.x if camera != null else 1.0
	var s := clampf(SCREEN_SCALE / zoom, 0.5, 6.0)
	for id: int in _rings:
		var ring := _rings[id]
		if not ring.is_shown():
			continue
		var top := _top_of(id)
		if top.is_finite():
			draw_ring(self, top + Vector2(0, -20.0 * s), ring, s)


# The top of the building or soldier [param id] in world pixels, or INF when it is gone.
func _top_of(id: int) -> Vector2:
	var building := _simulation.buildings.building(id)
	if building != null:
		return GridTransform.grid_to_world(building.centre) + Vector2(0, -RAISE)
	var soldiers := _simulation.soldiers
	var index := soldiers.index_of(id)
	if index == Soldiers.NONE:
		return Vector2.INF
	var foot := GridTransform.grid_to_world(soldiers.positions[index])
	return foot + Vector2(0, -SOLDIER_RAISE - SoldierRenderer.lift(soldiers, index))


## Draws a ring centred on [param at], [param s] times its base size of 14 pixels. Hidden at x1
## except for a break; [param show_idle] draws an x1 ring dimmed instead, for the details.
static func draw_ring(
	ci: CanvasItem, at: Vector2, ring: Ring, s: float, show_idle := false
) -> void:
	if ring.tier < 2:
		_draw_break(ci, at, ring, s)
		if not show_idle or ring.since_break < BREAK_SECONDS:
			return
	var colour: Color = TIER_COLOURS.get(ring.tier, Color.WHITE)
	var beat := 1.0 + 0.18 * _ease(ring.since_kill, BEAT_SECONDS)
	var up := _ease(ring.since_tier_up, TIER_UP_SECONDS)
	var r := 14.0 * s * beat
	ci.draw_circle(at, r + 2 * s, BACK)
	ci.draw_arc(at, r, 0, TAU, 32, TRACK, 3 * s)
	if ring.progress > 0.0:
		ci.draw_arc(at, r, -PI / 2, -PI / 2 + TAU * ring.progress, 32, colour, 3 * s)
	if ring.timer > 0.0:
		var timer_colour := TIMER_COLOUR if ring.timer > TIMER_LOW else BREAK_RED
		ci.draw_arc(at, r - 5 * s, -PI / 2, -PI / 2 + TAU * ring.timer, 32, timer_colour, 1.5 * s)
	_text(ci, at, "x%d" % ring.tier, 15 * s * (1 + up * 0.8), colour.lerp(Color.WHITE, up))
	if up > 0.0:
		var burst := colour
		burst.a = up
		ci.draw_arc(at, r * (1 + 2.0 * (1 - up)), 0, TAU, 32, burst, 2 * s)


# The old tier falls away in red as four arc fragments scatter outwards.
static func _draw_break(ci: CanvasItem, at: Vector2, ring: Ring, s: float) -> void:
	var k := ring.since_break / BREAK_SECONDS
	if k >= 1.0:
		return
	var red := BREAK_RED
	red.a = 1.0 - k
	_text(ci, at + Vector2(0, 26 * k * s), "x%d" % ring.break_tier, 14 * s, red)
	for i in 4:
		var a := i * TAU / 4.0 + k * 0.8
		ci.draw_arc(at, 14 * s * (1 + k * 0.6), a, a + 0.9, 8, red, 3 * s)


static func _ease(seconds: float, length: float) -> float:
	return clampf(1.0 - seconds / length, 0.0, 1.0)


static func _text(
	ci: CanvasItem, centre: Vector2, text: String, size: float, colour: Color
) -> void:
	var font := ThemeDB.fallback_font
	var px := maxi(1, roundi(size))
	var dims := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px)
	var pos := centre + Vector2(-dims.x / 2.0, dims.y * 0.3)
	var outline := Color(0, 0, 0, colour.a)
	ci.draw_string_outline(
		font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, maxi(2, px / 5), outline
	)
	ci.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, colour)
