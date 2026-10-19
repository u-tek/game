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


## Floating number/text that pops, rises and fades. size = font px. life scales how long it
## stays (fast battle speeds pass < 1 so numbers don't pile up).
static func number(layer: Node, pos: Vector2, text: String, color: Color, size: int = 32, rise: float = 70.0, delay: float = 0.0, life: float = 1.0) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", Kit.font("black"))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("outline_size", maxi(6, size / 5))
	l.add_theme_color_override("font_outline_color", Color(0.03, 0.035, 0.045))
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
	tw.tween_property(l, "position:y", l.position.y - rise, 0.75 * life).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.chain().tween_property(l, "modulate:a", 0.0, 0.25 * life)
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


## The effect classes below blend additively (glows add light instead of covering what is
## behind), each with one shared material.
## Glowing bolt: a bright comet (core, halo, tapering streak and shed sparks) on a slight
## arc; bursts on arrival.
class Bolt extends Node2D:
	static var _mat: CanvasItemMaterial
	signal arrived(at: Vector2)
	var glow: Texture2D
	var from := Vector2.ZERO
	var to := Vector2.ZERO
	var dur := 0.2
	var color := Color.WHITE
	var _t := 0.0
	var _trail: Array[Vector2] = []
	var _sparks: Array = []        # [pos, vel, life]

	func _ready() -> void:
		if _mat == null:
			_mat = CanvasItemMaterial.new()
			_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		material = _mat
		position = from

	func _process(delta: float) -> void:
		_t += delta
		var k := clampf(_t / dur, 0.0, 1.0)
		var arc := sin(k * PI) * minf(60.0, from.distance_to(to) * 0.15)
		var prev := position
		position = from.lerp(to, k) + Vector2(0, -arc)
		_trail.push_front(position)
		if _trail.size() > 12:
			_trail.pop_back()
		var dir := (position - prev).normalized() if position != prev else Vector2.RIGHT
		if _sparks.size() < 24:
			_sparks.append([position, -dir.rotated(randf_range(-0.9, 0.9)) * randf_range(60.0, 180.0), 0.28])
		for sp: Array in _sparks:
			sp[0] += sp[1] * delta
			sp[1] *= 0.9
			sp[2] -= delta
		_sparks = _sparks.filter(func(sp: Array) -> bool: return float(sp[2]) > 0.0)
		queue_redraw()
		if k >= 1.0:
			arrived.emit(to)
			queue_free()

	func _draw() -> void:
		var tex := glow
		if tex == null:
			return
		var n := _trail.size()
		for i in range(n - 1, 0, -1):
			var a := _trail[i] - position
			var b := _trail[i - 1] - position
			var f := 1.0 - i / float(n)
			draw_line(a, b, Color(color, 0.55 * f), 18.0 * f + 2.0, true)
			draw_line(a, b, Color(1, 1, 1, 0.6 * f), 5.0 * f + 1.0, true)
		for sp: Array in _sparks:
			var q: Vector2 = sp[0] - position
			var l := clampf(float(sp[2]) / 0.28, 0.0, 1.0)
			draw_texture_rect(tex, Rect2(q - Vector2(7, 7), Vector2(14, 14)), false, Color(color.lightened(0.3), l))
		draw_texture_rect(tex, Rect2(Vector2(-46, -46), Vector2(92, 92)), false, Color(color, 0.75))
		draw_texture_rect(tex, Rect2(Vector2(-22, -22), Vector2(44, 44)), false, color.lightened(0.4))
		draw_texture_rect(tex, Rect2(Vector2(-10, -10), Vector2(20, 20)), false, Color(1, 1, 1, 1))


## Melee swipe: a fast crescent sweep in three layers (wide soft glow, colored body, white-hot
## edge), a leading streak and sparks thrown off the arc.
class Slash extends Node2D:
	static var _mat: CanvasItemMaterial
	var color := Color.WHITE
	var radius := 70.0
	var _t := 0.0
	var _sparks: Array = []        # [pos, vel]
	const LIFE := 0.3

	func _ready() -> void:
		if _mat == null:
			_mat = CanvasItemMaterial.new()
			_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		material = _mat
		for i in 9:
			var a := randf_range(-1.6, 0.4)
			var p := Vector2(cos(a), sin(a)) * radius
			_sparks.append([p, Vector2(cos(a), sin(a)).rotated(PI * 0.5) * randf_range(-80.0, -260.0) + p.normalized() * randf_range(40.0, 160.0)])

	func _process(delta: float) -> void:
		_t += delta
		if _t >= LIFE:
			queue_free()
			return
		for sp: Array in _sparks:
			sp[0] += sp[1] * delta
			sp[1] = sp[1] * 0.88 + Vector2(0, 300.0) * delta
		queue_redraw()

	func _band(a0: float, a1: float, r: float, thick: float, col: Color) -> void:
		var pts := PackedVector2Array()
		var n := 18
		for i in n + 1:
			var a := lerpf(a0, a1, i / float(n))
			pts.append(Vector2(cos(a), sin(a)) * r)
		for i in range(n, -1, -1):
			var a := lerpf(a0, a1, i / float(n))
			var th := sin(i / float(n) * PI) * thick
			pts.append(Vector2(cos(a), sin(a)) * (r - th))
		draw_colored_polygon(pts, col)

	func _draw() -> void:
		var k := _t / LIFE
		var sweep := 1.0 - pow(1.0 - minf(k * 2.2, 1.0), 3.0)        # fast in, then hold
		var a1 := -2.4 + sweep * 2.6
		var a0 := a1 - 2.0 * (0.35 + 0.65 * sweep)
		var fade := 1.0 - maxf(0.0, (k - 0.35) / 0.65)
		_band(a0, a1, radius * 1.12, radius * 0.5, Color(color, 0.28 * fade))
		_band(a0, a1, radius, radius * 0.3, Color(color, 0.8 * fade))
		_band(a0 + 0.2, a1, radius * 0.98, radius * 0.1, Color(1, 1, 1, 0.95 * fade))
		var tip := Vector2(cos(a1), sin(a1)) * radius
		draw_line(tip, tip + Vector2(cos(a1 + PI * 0.5), sin(a1 + PI * 0.5)) * radius * 0.7 * fade, Color(1, 1, 1, 0.8 * fade), 3.0, true)
		for sp: Array in _sparks:
			var v: Vector2 = sp[1]
			draw_line(sp[0], sp[0] - v * 0.03, Color(color.lightened(0.5), fade), 2.5, true)


## Impact: a white flash, a four-point star, a shockwave ring and sparks with drag and gravity.
class Burst extends Node2D:
	static var _mat: CanvasItemMaterial
	var color := Color.WHITE
	var radius := 60.0
	var sparks := 8
	var _t := 0.0
	var _sp: Array = []            # [pos, vel]
	var _rot := 0.0
	const LIFE := 0.42

	func _ready() -> void:
		if _mat == null:
			_mat = CanvasItemMaterial.new()
			_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		material = _mat
		_rot = randf() * TAU
		for i in sparks + sparks / 2:
			var d := Vector2.from_angle(TAU * i / float(sparks + sparks / 2) + randf_range(-0.35, 0.35))
			_sp.append([d * radius * 0.15, d * radius * randf_range(5.0, 9.0)])

	func _process(delta: float) -> void:
		_t += delta
		if _t >= LIFE:
			queue_free()
			return
		for s: Array in _sp:
			s[0] += s[1] * delta
			s[1] = s[1] * 0.86 + Vector2(0, 520.0) * delta
		queue_redraw()

	func _draw() -> void:
		var k := _t / LIFE
		var e := 1.0 - pow(1.0 - k, 3.0)
		var a := 1.0 - k
		var flash := maxf(0.0, 1.0 - k * 4.0)
		draw_circle(Vector2.ZERO, radius * (0.55 + 0.4 * e), Color(color, 0.35 * a), true, -1.0, true)
		draw_circle(Vector2.ZERO, radius * 0.5 * (1.0 - k * 0.6), Color(1, 1, 1, 0.9 * flash), true, -1.0, true)
		# four-point star (two long, two short rays), spinning a little
		var star := radius * (1.6 - k) * flash + radius * 0.2
		for i in 4:
			var d := Vector2.from_angle(_rot + i * PI * 0.5 + k * 0.6)
			var l := star * (1.0 if i % 2 == 0 else 0.55)
			var w := d.orthogonal() * radius * 0.07
			draw_colored_polygon(PackedVector2Array([w, d * l, -w]), Color(1, 1, 1, 0.85 * flash + 0.15 * a))
		draw_arc(Vector2.ZERO, radius * (0.4 + 1.0 * e), 0, TAU, 40, Color(color.lightened(0.3), 0.9 * a), 6.0 * (1.0 - k) + 1.0, true)
		for s: Array in _sp:
			var v: Vector2 = s[1]
			draw_line(s[0], s[0] - v * 0.035, Color(color.lightened(0.5), a), 3.0 * a + 1.0, true)
