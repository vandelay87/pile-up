class_name AlertStrip
extends Control
## A thin bar along the console's top edge, filling with the alert: orange, then red from the
## warning, with a tick at the warning. Empty through a wave.

const HEIGHT := 5.0
const TRACK_COLOUR := Color(0.0, 0.0, 0.0, 0.55)
const FILL_COLOUR := Color(1.0, 0.6, 0.15)
const WARN_COLOUR := Color(0.95, 0.2, 0.15)
const TICK_COLOUR := Color(1.0, 1.0, 1.0, 0.8)

## How full the alert is, from 0 to 1.
var fill := 0.0:
	set(value):
		if value != fill:
			fill = value
			queue_redraw()
## Where the warning falls, from 0 to 1.
var warn_at := 0.75:
	set(value):
		if value != warn_at:
			warn_at = value
			queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), TRACK_COLOUR)
	var colour := WARN_COLOUR if fill >= warn_at else FILL_COLOUR
	draw_rect(Rect2(Vector2.ZERO, Vector2(size.x * clampf(fill, 0.0, 1.0), size.y)), colour)
	var tick_x := size.x * warn_at
	draw_line(Vector2(tick_x, 0.0), Vector2(tick_x, size.y), TICK_COLOUR, 2.0)
