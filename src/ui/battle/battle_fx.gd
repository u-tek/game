extends RefCounted
## Battle effects. Static spawners that add short-lived nodes to a layer and free them:
##   BattleFx.number(layer, pos, text, color, size, rise)   floating damage / heal number
##   BattleFx.projectile(layer, from, to, dur, color)       glowing bolt with a trail
##   BattleFx.slash(layer, pos, color, flip)                melee crescent
##   BattleFx.burst(layer, pos, color, radius)              impact ring + sparks
## `layer` is a CanvasItem; positions are in that layer's local space.

static var _glow_tex: Texture2D


static func glow_texture() -> Texture2D:
	if _glow_tex == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0)])
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 64
		t.height = 64
		_glow_tex = t
	return _glow_tex


## Floating number/text that pops, rises and fades. size = font px.
static func number(layer: Node, pos: Vector2, text: String, color: Color, size: int = 32, rise: float = 70.0, delay: float = 0.0) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", Kit.font("black"))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("outline_size", maxi(6, size / 5))
	l.add_theme_color_override("font_outline_color", Color(0.06, 0.02, 0.1))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var w := Kit.font("black").get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 16.0
	l.size = Vector2(w, size * 1.4)
	l.position = pos - l.size * 0.5
	l.pivot_offset = l.size * 0.5
	layer.add_child(l)
	l.scale = Vector2(0.4, 0.4)
	l.modulate.a = 0.0
	var tw := l.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.set_parallel(true)
	tw.tween_property(l, "modulate:a", 1.0, 0.06)
	tw.tween_property(l, "scale", Vector2.ONE * (1.25 if size >= 40 else 1.0), 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "position:y", l.position.y - rise, 0.75).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.chain().tween_property(l, "modulate:a", 0.0, 0.25)
	tw.tween_callback(l.queue_free)


static func projectile(layer: Node, from: Vector2, to: Vector2, dur: float, color: Color) -> void:
	var p := Bolt.new()
	p.from = from
	p.to = to
	p.dur = maxf(dur, 0.05)
	p.color = color
	p.glow = glow_texture()
	p.arrived.connect(func(at: Vector2) -> void:
		if is_instance_valid(layer):
			burst(layer, at, color, 42.0, 6))
	layer.add_child(p)


static func slash(layer: Node, pos: Vector2, color: Color, flip: bool, size: float = 70.0) -> void:
	var s := Slash.new()
	s.position = pos
	s.color = color
	s.radius = size
	s.rotation = randf_range(-0.6, 0.6) + (PI if flip else 0.0)
	layer.add_child(s)


static func burst(layer: Node, pos: Vector2, color: Color, radius: float = 60.0, sparks: int = 8) -> void:
	var b := Burst.new()
	b.position = pos
	b.color = color
	b.radius = radius
	b.sparks = sparks
	layer.add_child(b)


## Glowing bolt: an additive orb with a short fading trail; bursts on arrival.
class Bolt extends Node2D:
	signal arrived(at: Vector2)
	var glow: Texture2D
	var from := Vector2.ZERO
	var to := Vector2.ZERO
	var dur := 0.2
	var color := Color.WHITE
	var _t := 0.0
	var _trail: Array[Vector2] = []

	func _ready() -> void:
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		material = m
		position = from

	func _process(delta: float) -> void:
		_t += delta
		var k := clampf(_t / dur, 0.0, 1.0)
		var arc := sin(k * PI) * minf(60.0, from.distance_to(to) * 0.15)
		position = from.lerp(to, k) + Vector2(0, -arc)
		_trail.push_front(position)
		if _trail.size() > 7:
			_trail.pop_back()
		queue_redraw()
		if k >= 1.0:
			arrived.emit(to)
			queue_free()

	func _draw() -> void:
		var tex := glow
		if tex == null:
			return
		for i in range(_trail.size() - 1, -1, -1):
			var p := _trail[i] - position
			var s := 34.0 * (1.0 - i / 8.0)
			draw_texture_rect(tex, Rect2(p - Vector2(s, s) * 0.5, Vector2(s, s)), false, Color(color, 0.5 * (1.0 - i / 8.0)))
		draw_texture_rect(tex, Rect2(Vector2(-30, -30), Vector2(60, 60)), false, color)
		draw_texture_rect(tex, Rect2(Vector2(-12, -12), Vector2(24, 24)), false, Color(1, 1, 1, 0.95))


## Crescent swipe for melee hits.
class Slash extends Node2D:
	var color := Color.WHITE
	var radius := 70.0
	var _t := 0.0
	const LIFE := 0.24

	func _process(delta: float) -> void:
		_t += delta
		if _t >= LIFE:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var k := _t / LIFE
		var a0 := -2.2 + k * 1.2
		var a1 := a0 + 1.9
		var pts := PackedVector2Array()
		var n := 16
		for i in n + 1:
			var a := lerpf(a0, a1, i / float(n))
			pts.append(Vector2(cos(a), sin(a)) * radius)
		for i in range(n, -1, -1):
			var a := lerpf(a0, a1, i / float(n))
			var th := sin(i / float(n) * PI) * radius * 0.28
			pts.append(Vector2(cos(a), sin(a)) * (radius - th))
		var alpha := 1.0 - k
		draw_colored_polygon(pts, Color(color, 0.85 * alpha))
		draw_polyline(pts.slice(0, n + 1), Color(1, 1, 1, alpha), 3.0, true)


## Expanding ring with sparks.
class Burst extends Node2D:
	var color := Color.WHITE
	var radius := 60.0
	var sparks := 8
	var _t := 0.0
	var _dirs: Array[Vector2] = []
	const LIFE := 0.36

	func _ready() -> void:
		for i in sparks:
			_dirs.append(Vector2.from_angle(TAU * i / float(sparks) + randf_range(-0.3, 0.3)) * randf_range(0.7, 1.15))

	func _process(delta: float) -> void:
		_t += delta
		if _t >= LIFE:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var k := _t / LIFE
		var e := 1.0 - pow(1.0 - k, 3.0)
		var a := 1.0 - k
		draw_circle(Vector2.ZERO, radius * 0.45 * (1.0 - k), Color(1, 1, 1, 0.6 * a), true, -1.0, true)
		draw_arc(Vector2.ZERO, radius * (0.3 + 0.7 * e), 0, TAU, 32, Color(color, 0.9 * a), 4.0 * (1.0 - k) + 1.0, true)
		for d in _dirs:
			var p0 := d * radius * (0.2 + 0.6 * e)
			var p1 := d * radius * (0.35 + 0.95 * e)
			draw_line(p0, p1, Color(color.lightened(0.4), a), 3.0, true)
