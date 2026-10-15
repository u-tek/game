extends Control
## App background: twilight sky gradient, faint stars, a high halo glow and the outline of
## a cathedral rose window. Drawn once (no per-frame cost). Screens with their own art
## simply cover it.

const SKY_TOP := Color("231a4a")
const SKY_MID := Color("140f2b")
const SKY_LOW := Color("0a0716")

var _stars: Array[Vector3] = []
var _glow: GradientTexture2D
var _warm: GradientTexture2D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rng := RandomNumberGenerator.new()
	rng.seed = 7741
	for i in 110:
		_stars.append(Vector3(rng.randf(), rng.randf() * 0.85, rng.randf()))
	_glow = _radial(Color(0.5, 0.38, 0.85, 0.32))
	_warm = _radial(Color(1.0, 0.82, 0.5, 0.12))
	resized.connect(queue_redraw)


static func _radial(c: Color) -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, c)
	g.set_color(1, Color(c, 0.0))
	g.add_point(0.45, Color(c, c.a * 0.45))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 0.0)
	t.width = 256
	t.height = 256
	return t


func _draw() -> void:
	var w := size.x
	var h := size.y
	# Sky gradient in three bands.
	var mid := h * 0.42
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, mid), Vector2(0, mid)]),
		PackedColorArray([SKY_TOP, SKY_TOP, SKY_MID, SKY_MID]))
	draw_polygon(PackedVector2Array([Vector2(0, mid), Vector2(w, mid), Vector2(w, h), Vector2(0, h)]),
		PackedColorArray([SKY_MID, SKY_MID, SKY_LOW, SKY_LOW]))
	# High halo glow (smooth radial textures).
	var gc := Vector2(w * 0.5, h * 0.22)
	var gr := w * 1.1
	draw_texture_rect(_glow, Rect2(gc - Vector2(gr, gr), Vector2(gr, gr) * 2.0), false)
	var wr := w * 0.45
	draw_texture_rect(_warm, Rect2(gc - Vector2(wr, wr), Vector2(wr, wr) * 2.0), false)
	# Stars.
	for s in _stars:
		var p := Vector2(s.x * w, s.y * h)
		var r := 0.8 + s.z * 1.6
		var a := 0.15 + s.z * 0.55
		draw_circle(p, r, Color(1.0, 0.95, 0.85, a), true, -1.0, true)
		if s.z > 0.93:
			var c := Color(1.0, 0.93, 0.75, a * 0.7)
			draw_line(p - Vector2(r * 4, 0), p + Vector2(r * 4, 0), c, 1.0, true)
			draw_line(p - Vector2(0, r * 4), p + Vector2(0, r * 4), c, 1.0, true)
	# Rose window outline (very faint gold).
	var rc := Vector2(w * 0.5, h * 0.36)
	var rr := w * 0.42
	var gold := Color(0.95, 0.78, 0.4, 0.05)
	draw_arc(rc, rr, 0, TAU, 96, gold, 2.0, true)
	draw_arc(rc, rr * 0.93, 0, TAU, 96, Color(gold, 0.04), 1.0, true)
	draw_arc(rc, rr * 0.36, 0, TAU, 64, gold, 1.5, true)
	for i in 12:
		var a := TAU * i / 12.0
		var dir := Vector2(cos(a), sin(a))
		draw_line(rc + dir * rr * 0.36, rc + dir * rr * 0.93, Color(gold, 0.045), 1.5, true)
		draw_arc(rc + dir * rr * 0.66, rr * 0.2, 0, TAU, 40, Color(gold, 0.04), 1.2, true)
	# Floor vignette.
	draw_polygon(PackedVector2Array([Vector2(0, h * 0.7), Vector2(w, h * 0.7), Vector2(w, h), Vector2(0, h)]),
		PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, 0.35), Color(0, 0, 0, 0.35)]))
