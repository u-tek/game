extends RefCounted
## Battle effects. Static spawners that add short-lived nodes to a layer and free them:
##   BattleFx.splash(layer, pos, color, size, flip)         the ultimate's ink crown landing
##   BattleFx.burst(layer, pos, color, radius)              a ring and sparks (the victory's sparkle)
## Every blow is printed by src/ui/battle/press_layer.gd; numbers are set by galley.gd.
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


static func burst(layer: Node, pos: Vector2, color: Color, radius: float = 60.0, sparks: int = 8) -> void:
	var b := Burst.new()
	b.position = pos
	b.color = color
	b.radius = radius
	b.sparks = sparks
	layer.add_child(b)


## An ink crown (a heroine's ultimate landing): the Blender-rendered splash
## (assets/art/ui/ult/ink_crown.png, 8 frames) printed in `color` and stepped through in 0.24 s,
## then it lifts off. Ink, not light: it covers what is under it.
static func splash(layer: Node, pos: Vector2, color: Color, size: float = 200.0, flip: bool = false) -> void:
	var s := Splash.new()
	s.position = pos
	s.modulate = color
	s.scale = Vector2(size / 512.0 * (-1.0 if flip else 1.0), size / 512.0)
	layer.add_child(s)


class Splash extends Sprite2D:
	const SHEET := preload("res://assets/art/ui/ult/ink_crown.png")
	var _t := 0.0

	func _ready() -> void:
		texture = SHEET
		hframes = 4
		vframes = 2
		frame = 0

	func _process(delta: float) -> void:
		_t += delta
		frame = mini(int(_t / 0.03), 7)
		if _t > 0.42:
			modulate.a = maxf(0.0, 1.0 - (_t - 0.42) / 0.3)
		if _t > 0.75:
			queue_free()


## The class below blends additively (a glow adds light instead of covering what is behind).
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
