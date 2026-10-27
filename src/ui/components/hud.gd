extends RefCounted
## HUD pieces for style v4 "Signal" (docs/dev/ui-style-v4.md). All geometry, drawn in _draw, crisp
## at any scale. Make them directly:
##   const HUD := preload("res://src/ui/components/hud.gd")
##   var led := HUD.Led.new()
##   Led      a status light with a soft glow; steady, blinking or breathing
##   Dots     stat dots (filled of max), round or square

## Status light with a glow.
class Led:
	extends Control
	var color := Color("ff3b1f")
	## "steady" | "blink" | "breathe"
	var mode := "steady"
	var period := 1.4
	var _t := 0.0

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE

	func _ready() -> void:
		set_process(mode != "steady" and Kit.motion_ok())

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		var k := 1.0
		if mode == "blink":
			k = 1.0 if fmod(_t, period) < period * 0.55 else 0.18
		elif mode == "breathe":
			k = 0.45 + 0.55 * (0.5 + 0.5 * sin(_t * TAU / period))
		for i in 5:
			var g := 1.0 - i / 5.0
			draw_circle(c, r * (0.45 + 0.55 * (i + 1) / 5.0), Color(color, 0.09 * k * g))
		draw_circle(c, r * 0.36, Color(color.lightened(0.35 * k), 0.35 + 0.65 * k))
		draw_circle(c - Vector2(r * 0.08, r * 0.1), r * 0.12, Color(1, 1, 1, 0.55 * k))


## Stat dots: `filled` of `count`.
class Dots:
	extends Control
	var count := 5
	var filled := 3
	var color := Color("f1f0eb")
	var empty := Color(1, 1, 1, 0.22)
	var square := false
	var gap := 6.0
	## A fixed dot size (px); 0 sizes them by the control's height (a fresh control measures 14,
	## which then sets its minimum size: set this for small dots).
	var dot := 0.0

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE

	func _get_minimum_size() -> Vector2:
		var d := dot if dot > 0.0 else (size.y if size.y > 0.0 else 14.0)
		return Vector2(count * d + (count - 1) * gap, d)

	func _draw() -> void:
		var d := dot if dot > 0.0 else size.y
		for i in count:
			var c := Vector2(i * (d + gap) + d * 0.5, d * 0.5)
			var on := i < filled
			if square:
				var r := Rect2(c - Vector2(d, d) * 0.4, Vector2(d, d) * 0.8)
				if on:
					draw_rect(r, color)
				else:
					draw_rect(r, empty, false, 1.0)
			elif on:
				draw_circle(c, d * 0.42, color)
			else:
				draw_arc(c, d * 0.38, 0.0, TAU, 24, empty, 1.5, true)
