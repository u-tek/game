extends Control
## A glowing summoning dais drawn as a flattened ring: soft light pool, a slowly turning
## rune circle and a bright rim. Home screen leader stand. Size it wide and short; the
## ellipse fills the rect.

var color := Color("f2c14e")
var spin := 0.18
var _t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_t += delta
	if is_visible_in_tree():
		queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var rx := size.x * 0.5
	var ry := maxf(size.y * 0.5, 1.0)
	var pulse := 0.5 + 0.5 * sin(_t * 1.7)
	draw_set_transform(c, 0.0, Vector2(1.0, ry / rx))
	# Light pool.
	for i in 7:
		var t := i / 7.0
		draw_circle(Vector2.ZERO, rx * (1.0 - t * 0.8), Color(color, 0.035 + 0.01 * pulse), true, -1.0, true)
	# Rim and rune circle.
	draw_arc(Vector2.ZERO, rx * 0.86, 0, TAU, 96, Color(color, 0.55), 4.0, true)
	draw_arc(Vector2.ZERO, rx * 0.8, 0, TAU, 96, Color(color, 0.25), 2.0, true)
	draw_arc(Vector2.ZERO, rx * 0.5, 0, TAU, 72, Color(color, 0.22), 2.0, true)
	var rot := _t * spin
	for i in 24:
		var a := rot + TAU * i / 24.0
		var d := Vector2(cos(a), sin(a))
		var inner := rx * (0.55 if i % 3 == 0 else 0.62)
		draw_line(d * inner, d * rx * 0.76, Color(color, 0.18 + (0.15 if i % 3 == 0 else 0.0)), 2.0, true)
	for i in 8:
		var a2 := -rot * 1.6 + TAU * i / 8.0
		var p := Vector2(cos(a2), sin(a2)) * rx * 0.68
		draw_circle(p, rx * 0.022, Color(color.lightened(0.4), 0.5 + 0.3 * pulse), true, -1.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
