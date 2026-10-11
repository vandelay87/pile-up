class_name OverflowView
extends Node2D

## The pressure gauge above each active crush's stalled enemies, from Overflow.crushes() each
## frame: segments for the three tiers in yellow, orange and red, with the tier's name. The
## Overflow overlay also tints each barrier's band, shows inactive gauges faded, and puts each
## crush's gauge reading, stalled count and tier on it as numbers.

const WIDTH := 72.0
const HEIGHT := 9.0
## World pixels from the stalled enemies' mean position up to the gauge.
const RAISE := 70.0
const BACK := Color(0.08, 0.08, 0.1, 0.85)
const EDGE := Color(0.9, 0.9, 0.9, 0.9)
const BELOW_TIERS := Color(0.75, 0.75, 0.75)
const TIER_COLOURS := {
	Overflow.Tier.NONE: BELOW_TIERS,
	Overflow.Tier.TRICKLE: Color(1.0, 0.85, 0.3),
	Overflow.Tier.STREAM: Color(1.0, 0.55, 0.15),
	Overflow.Tier.SURGE: Color(1.0, 0.2, 0.15),
}
const TIER_NAMES := {
	Overflow.Tier.NONE: "",
	Overflow.Tier.TRICKLE: "trickle",
	Overflow.Tier.STREAM: "stream",
	Overflow.Tier.SURGE: "SURGE",
}
const INACTIVE_ALPHA := 0.4
const BAND_TINT := Color(1.0, 0.5, 0.2, 0.12)
const FONT_SIZE := 13

var _simulation: Simulation
var _debug := false


func setup(simulation: Simulation) -> void:
	_simulation = simulation
	z_index = RenderingServer.CANVAS_ITEM_Z_MAX


func show_debug(on: bool) -> void:
	_debug = on


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if _simulation == null:
		return
	if _debug:
		_draw_band()
	for crush in _simulation.overflow.crushes():
		if crush.active or _debug:
			_draw_gauge(crush)


func _draw_gauge(crush: Overflow.Crush) -> void:
	var settings := _simulation.settings
	var gauge_max := settings.gauge_max
	var top_left := GridTransform.grid_to_world(crush.centre) + Vector2(-WIDTH / 2.0, -RAISE)
	var fade := Color(1, 1, 1, 1.0 if crush.active else INACTIVE_ALPHA)
	draw_rect(Rect2(top_left, Vector2(WIDTH, HEIGHT)), BACK * fade)
	# Each tier's stretch of the fill in its own colour, from its threshold to the next.
	var starts: Array[float] = [0.0, settings.trickle_at, settings.stream_at, settings.surge_at]
	var tiers: Array[Overflow.Tier] = [
		Overflow.Tier.NONE, Overflow.Tier.TRICKLE, Overflow.Tier.STREAM, Overflow.Tier.SURGE
	]
	for k in starts.size():
		var end := gauge_max if k == starts.size() - 1 else starts[k + 1]
		var from := _x_of(starts[k], gauge_max)
		var to := _x_of(minf(crush.gauge, end), gauge_max)
		if to > from:
			var colour: Color = TIER_COLOURS[tiers[k]]
			draw_rect(Rect2(top_left + Vector2(from, 0), Vector2(to - from, HEIGHT)), colour * fade)
	for k in range(1, starts.size()):
		var x := _x_of(starts[k], gauge_max)
		draw_line(top_left + Vector2(x, -2), top_left + Vector2(x, HEIGHT + 2), EDGE * fade)
	draw_rect(Rect2(top_left, Vector2(WIDTH, HEIGHT)), EDGE * fade, false)
	var text: String = TIER_NAMES[crush.tier]
	if _debug:
		text = ("%s %.0f  stalled %d" % [text, crush.gauge, crush.stalled]).strip_edges()
	if text.is_empty():
		return
	var text_colour: Color = TIER_COLOURS[crush.tier] if crush.tier != Overflow.Tier.NONE else EDGE
	draw_string(
		ThemeDB.fallback_font,
		top_left + Vector2(0, -4),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		FONT_SIZE,
		text_colour * fade
	)


func _x_of(reading: float, gauge_max: float) -> float:
	return WIDTH * clampf(reading / gauge_max, 0.0, 1.0)


func _draw_band() -> void:
	var map := _simulation.map
	var mask := _simulation.overflow.band_mask
	for index in mask.size():
		if mask[index] == 0:
			continue
		var cell := map.cell_of(index)
		var points := PackedVector2Array()
		for corner: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]:
			points.append(GridTransform.grid_to_world(Vector2(cell + corner)))
		draw_colored_polygon(points, BAND_TINT)
