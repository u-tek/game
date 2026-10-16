extends Control
## App background (style v2), drawn once. mode "dark" (default): graphite gradient, a soft
## cyan light from the upper right, a broad band of faint diagonal hatching and a few thin
## technical rule lines. mode "light": the same grammar on pale paper, for light pages.
## Screens with their own art simply cover it.

const KitBox := preload("res://src/ui/components/kit_box.gd")

var mode := "dark":
	set(v):
		mode = v
		queue_redraw()

var _glow: GradientTexture2D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var g := Gradient.new()
	g.set_color(0, Color(0.07, 0.62, 0.95, 0.16))
	g.set_color(1, Color(0.07, 0.62, 0.95, 0.0))
	_glow = GradientTexture2D.new()
	_glow.gradient = g
	_glow.fill = GradientTexture2D.FILL_RADIAL
	_glow.fill_from = Vector2(0.5, 0.5)
	_glow.fill_to = Vector2(0.5, 0.0)
	_glow.width = 256
	_glow.height = 256
	resized.connect(queue_redraw)


func _draw() -> void:
	var ci := get_canvas_item()
	var w := size.x
	var h := size.y
	var light := mode == "light"
	var top := Color("f4f6f8") if light else Color("1d1f24")
	var bot := Color("e2e6ea") if light else Color("0c0d0f")
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h), Vector2(0, h)]),
		PackedColorArray([top, top, bot, bot]))
	if not light:
		var gr := w * 0.95
		draw_texture_rect(_glow, Rect2(Vector2(w * 0.85, h * 0.12) - Vector2(gr, gr), Vector2(gr, gr) * 2.0), false)
	var ink := Color(0, 0, 0) if light else Color(1, 1, 1)
	# Broad diagonal band of hatching across the middle.
	var band := PackedVector2Array([Vector2(0, h * 0.30), Vector2(w, h * 0.12), Vector2(w, h * 0.44), Vector2(0, h * 0.62)])
	KitBox.hatch(ci, band, Color(ink, 0.035), 14.0, 3.0)
	# Technical rule lines with end ticks.
	var lc := Color(ink, 0.07)
	for y_k: float in [0.18, 0.71, 0.86]:
		var y := roundf(h * y_k)
		draw_line(Vector2(w * 0.06, y), Vector2(w * 0.94, y), lc, 1.0)
		draw_rect(Rect2(w * 0.06, y - 4.0, 2.0, 8.0), lc)
		draw_rect(Rect2(w * 0.94 - 2.0, y - 4.0, 2.0, 8.0), lc)
	# A few faint hexagon outlines, lower left.
	for i in 3:
		var c := Vector2(w * (0.12 + 0.13 * i), h * (0.78 - 0.04 * (i % 2)))
		KitBox.stroke_poly(ci, KitBox.hex_points(c, w * 0.07), Color(ink, 0.05 - i * 0.01), 2.0)
	# Edge vignette.
	draw_polygon(PackedVector2Array([Vector2(0, h * 0.75), Vector2(w, h * 0.75), Vector2(w, h), Vector2(0, h)]),
		PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, 0.06 if light else 0.3), Color(0, 0, 0, 0.06 if light else 0.3)]))
