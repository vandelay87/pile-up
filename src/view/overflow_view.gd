# PROTOTYPE (overflow, #94): the pressure gauge above each crush. An active crush always shows
# its gauge; the debug overlay also shows building pressure, numbers and the crush band.
class_name OverflowView
extends Node2D

const WIDTH := 72.0
const HEIGHT := 9.0
const RAISE := 70.0
const BACK := Color(0.08, 0.08, 0.1, 0.85)
const EDGE := Color(0.9, 0.9, 0.9, 0.9)
const TIER_COLOURS := {
	Overflow.Tier.NONE: Color(0.75, 0.75, 0.75),
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
const BAND_TINT := Color(1.0, 0.5, 0.2, 0.12)

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
	var overflow := _simulation.overflow
	var font := ThemeDB.fallback_font
	if _debug:
		_draw_band()
		var total := (
			"tumbling %d   tumbled %d" % [overflow.climbing_count(), overflow.total_climbers]
		)
		var corner := GridTransform.cell_to_world(Vector2i(_simulation.map.base.position))
		draw_string(font, corner + Vector2(-60, -90), total, HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
	for crush: Overflow.Crush in overflow.crushes.values():
		if not crush.active and not _debug:
			continue
		if crush.pressure <= 0.0:
			continue
		_draw_gauge(overflow, crush, font)


func _draw_gauge(overflow: Overflow, crush: Overflow.Crush, font: Font) -> void:
	var gauge_max := overflow.num("gauge_max")
	var top_left := GridTransform.grid_to_world(crush.centre) + Vector2(-WIDTH / 2.0, -RAISE)
	var alpha := 1.0 if crush.active else 0.4
	draw_rect(Rect2(top_left, Vector2(WIDTH, HEIGHT)), BACK * Color(1, 1, 1, alpha))
	var filled := WIDTH * clampf(crush.pressure / gauge_max, 0.0, 1.0)
	var colour: Color = TIER_COLOURS[crush.tier]
	colour.a = alpha
	draw_rect(Rect2(top_left, Vector2(filled, HEIGHT)), colour)
	for key: String in ["trickle_at", "stream_at", "surge_at"]:
		var x := WIDTH * clampf(overflow.num(key) / gauge_max, 0.0, 1.0)
		draw_line(
			top_left + Vector2(x, -2),
			top_left + Vector2(x, HEIGHT + 2),
			EDGE * Color(1, 1, 1, alpha)
		)
	draw_rect(Rect2(top_left, Vector2(WIDTH, HEIGHT)), EDGE * Color(1, 1, 1, alpha), false)
	var text: String = TIER_NAMES[crush.tier]
	if _debug:
		text = "%s %.0f  s%d c%.1f" % [text, crush.pressure, crush.stalled, crush.contact]
	if not text.is_empty():
		draw_string(
			font,
			top_left + Vector2(0, -4),
			text,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			13,
			colour if crush.tier != Overflow.Tier.NONE else EDGE
		)


func _draw_band() -> void:
	var map := _simulation.map
	var mask := _simulation.enemies.progress_mask
	if mask.is_empty():
		return
	for index in mask.size():
		if mask[index] == 0:
			continue
		var cell := map.cell_of(index)
		var points := PackedVector2Array()
		for corner: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]:
			points.append(GridTransform.grid_to_world(Vector2(cell + corner)))
		draw_colored_polygon(points, BAND_TINT)
