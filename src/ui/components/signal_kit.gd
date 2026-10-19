class_name SignalKit
extends RefCounted
## Style v4 "Signal" building blocks shared by every rebuilt screen (docs/dev/ui-style-v4.md). Kit
## keeps the tokens, fonts and the restyled v2 widgets; this file holds the v4 pieces: lit plates,
## engraving, the pass button (the owner's "THIS is how I want the main buttons to look"), print
## details (stamp, matrix code, barcode, coil, pill) and the halftone / grain layers.
##
##   SignalKit.plate(preset, pos, size, opts, parent)   a Plate (see plate.gd for presets / opts)
##   SignalKit.pass_button(spec, on_pressed)            the OG-pass call to action (silver over signal)
##   SignalKit.etch(text, size, weight, on_light)       text cut into metal
##   SignalKit.etch_icon(name, size, on_light)          an icon cut into metal
##   SignalKit.pill(text, size, color)                  outlined capsule label
##   SignalKit.stamp(label, value, size)                round inspection stamp
##   SignalKit.matrix(size) / barcode(size, color) / coil(size)
##   SignalKit.halftone_material(cell, ink, light_dots) / grain(amount, still)
##   SignalKit.relight(node)                            light plates by the glowing ones (deferred)

const Plate := preload("res://src/ui/components/plate.gd")
const HUD := preload("res://src/ui/components/hud.gd")

const SIGNAL := Color("ff4b1f")
const PAPER := Color("e9e8e2")
const MATTE := Color("f5f4f0")
const INK := Color("101113")
## Engraved ink on silver / slate.
const ETCH := Color("131416")


## A Plate at pos (added to parent when given). opts: cuts [TL, TR, BR, BL], shape (polygon),
## circle, screws (Array of Vector2), glow, glow_radius, pulse, topo, shadow (alpha), recess, bevel,
## hole (Vector3: a round cut-out, x, y centre and z radius in body px).
static func plate(preset: String, pos: Vector2, size: Vector2, opts: Dictionary = {}, parent: Node = null) -> Control:
	var p := Plate.new()
	p.preset = preset
	p.position = pos
	p.size = size
	if opts.has("cuts"):
		p.cuts = opts["cuts"]
	if opts.has("shape"):
		p.shape = opts["shape"]
	p.circle = opts.get("circle", false)
	if opts.has("screws"):
		for s: Vector2 in opts["screws"]:
			p.screws.append(s)
	p.glow = opts.get("glow", 0.0)
	p.glow_radius = opts.get("glow_radius", 18.0)
	p.pulse = opts.get("pulse", 0.0)
	p.topo = opts.get("topo", 0.0)
	p.shadow_a = opts.get("shadow", 0.6)
	p.recess = opts.get("recess", false)
	if opts.has("bevel"):
		p.bevel = opts["bevel"]
	if opts.has("hole"):
		p.hole = opts["hole"]
	if parent:
		parent.add_child(p)
	return p


## Text cut into a plate: a light lip below, a dark wall above, the fill in the plate's shadow tone.
## on_light: silver / slate / paper; false: graphite.
static func etch(text: String, size: int, weight: String = "mono_bold", on_light: bool = true) -> Control:
	var box := Control.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := ETCH if on_light else Color(1, 1, 1, 0.58)
	var lip := Color(1, 1, 1, 0.7) if on_light else Color(1, 1, 1, 0.12)
	var wall := Color(0, 0, 0, 0.45) if on_light else Color(0, 0, 0, 0.85)
	for layer: Array in [[lip, Vector2(0, 1)], [wall, Vector2(0, -1)], [fill, Vector2.ZERO]]:
		var l := Kit.label(text, size, layer[0], weight)
		l.position = layer[1]
		box.add_child(l)
	box.custom_minimum_size = (box.get_child(2) as Label).get_minimum_size()
	box.size = box.custom_minimum_size
	return box


## An icon cut into a plate (same lip / wall as etch).
static func etch_icon(icon_name: String, size: float, on_light: bool = true) -> Control:
	var box := Control.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.custom_minimum_size = Vector2(size, size)
	box.size = box.custom_minimum_size
	var fill := ETCH if on_light else Color(1, 1, 1, 0.6)
	var lip := Color(1, 1, 1, 0.55) if on_light else Color(1, 1, 1, 0.1)
	var wall := Color(0, 0, 0, 0.4) if on_light else Color(0, 0, 0, 0.8)
	for layer: Array in [[lip, Vector2(0, 1)], [wall, Vector2(0, -1)], [fill, Vector2.ZERO]]:
		var ic := Kit.icon(icon_name, size, layer[0])
		ic.position = layer[1]
		box.add_child(ic)
	return box


## Outlined capsule label (the OG pass's "OG PASS" pill).
static func pill(text: String, size: int = 20, color: Color = Color.WHITE, weight: String = "wide_black") -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0, 0, 0, 0.1)
	ps.border_color = Color(color, 0.92)
	ps.set_border_width_all(2)
	ps.set_corner_radius_all(40)
	ps.content_margin_left = 18
	ps.content_margin_right = 18
	ps.content_margin_top = 2
	ps.content_margin_bottom = 2
	p.add_theme_stylebox_override("panel", ps)
	p.add_child(Kit.label(text, size, color, weight))
	return p


## The pass button: a brushed silver plate (matrix code, kicker, title, sub line, a machined knob
## with an icon) over a glowing signal plate (an outlined action pill and an info line), the shape of
## the owner's OG-pass reference. spec keys: width (400), kicker, title, sub, action, info, icon,
## code (true). Press: both plates sink, the face brightens, a tap sound and haptic.
static func pass_button(spec: Dictionary, on_pressed: Callable = Callable()) -> Control:
	var w: float = spec.get("width", 400.0)
	var root := Control.new()
	root.custom_minimum_size = Vector2(w, 176)
	root.size = root.custom_minimum_size
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sig := plate("signal", Vector2(8, 78), Vector2(w - 14, 96), {"cuts": [0, 12, 18, 0], "glow": 0.4, "glow_radius": 14.0,
		"pulse": 0.5, "topo": 0.6}, root)
	var top_sz := Vector2(w, 94)
	var silver := plate("silver", Vector2.ZERO, top_sz, {"shape": Plate.tab_bottom(top_sz, 14, w * 0.33, w * 0.65, 14), "topo": 0.5,
		"screws": [Vector2(13, 13), Vector2(w - 13, 13), Vector2(13, 66), Vector2(w - 13, 66)]}, root)
	silver.z_index = 1
	var x := 26.0
	if spec.get("code", true):
		var code := matrix(Vector2(58, 58))
		code.position = Vector2(26, 13)
		silver.add_child(code)
		x = 98.0
	var kick := etch(str(spec.get("kicker", "")), 10, "mono_bold")
	kick.position = Vector2(x, 12)
	silver.add_child(kick)
	var title := etch(str(spec.get("title", "")), 30, "wide_black")
	title.position = Vector2(x - 2, 26)
	silver.add_child(title)
	var sub := etch(str(spec.get("sub", "")), 10, "mono")
	sub.position = Vector2(x, 66)
	silver.add_child(sub)
	var knob := plate("dial", Vector2(w - 82, 20), Vector2(50, 50), {"circle": true, "shadow": 0.5}, silver)
	var ic := Kit.icon(str(spec.get("icon", "flag")), 22, Color(1, 1, 1, 0.95))
	ic.position = Vector2(14, 14)
	knob.add_child(ic)
	var act := pill(str(spec.get("action", "ENGAGE  >>>")), 20)
	act.position = Vector2(18, 32)
	sig.add_child(act)
	if spec.has("info"):
		var info := Kit.label(str(spec["info"]), 10, Color(1, 1, 1, 0.85), "mono")
		info.position = Vector2(w * 0.58, 44)
		sig.add_child(info)
	var hit := Button.new()
	hit.theme_type_variation = &"BareButton"
	hit.mouse_filter = Control.MOUSE_FILTER_PASS
	hit.position = Vector2(-4, -4)
	hit.size = Vector2(w + 8, 184)
	hit.button_down.connect(func() -> void:
		(silver as Plate).set_pressed_look(true)
		(sig as Plate).set_pressed_look(true)
		Kit.haptic(12))
	hit.button_up.connect(func() -> void:
		(silver as Plate).set_pressed_look(false)
		(sig as Plate).set_pressed_look(false))
	if on_pressed.is_valid():
		hit.pressed.connect(func() -> void:
			Kit.sfx("tap")
			on_pressed.call())
	root.add_child(hit)
	return root


## Round inspection stamp: text around the rim, a big value in the middle.
static func stamp(label: String, value: String, size: float = 112.0) -> Control:
	var s := _Stamp.new()
	s.label = label
	s.value = value
	s.custom_minimum_size = Vector2(size, size)
	s.size = s.custom_minimum_size
	return s


static func matrix(size: Vector2) -> Control:
	var m := _Matrix.new()
	m.custom_minimum_size = size
	m.size = size
	return m


static func barcode(size: Vector2, color: Color = INK, seed_value: int = 289) -> Control:
	var b := _Barcode.new()
	b.color = color
	b.seed_value = seed_value
	b.custom_minimum_size = size
	b.size = size
	return b


static func coil(size: Vector2) -> Control:
	var c := _Coil.new()
	c.custom_minimum_size = size
	c.size = size
	return c


## Halftone material for a TextureRect (dots follow brightness, or darkness when light_dots false).
static func halftone_material(cell: float = 7.0, ink: Color = Color(1.0, 0.36, 0.16, 0.95), light_dots: bool = true) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://src/ui/shaders/halftone.gdshader")
	m.set_shader_parameter("cell", cell)
	m.set_shader_parameter("ink", ink)
	m.set_shader_parameter("light_dots", light_dots)
	m.set_shader_parameter("gain", 1.25)
	return m


## Full-rect film grain (multiplied). Add it last.
static func grain(amount: float = 0.045, still: bool = false) -> ColorRect:
	var g := ColorRect.new()
	g.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = load("res://src/ui/shaders/grain.gdshader")
	m.set_shader_parameter("amount", amount)
	m.set_shader_parameter("still", still or not Kit.motion_ok())
	g.material = m
	return g


## Lights every plate by the glowing plates and tubes near it, once the layout has settled.
static func relight(node: Node) -> void:
	var tree := node.get_tree()
	if tree == null:
		return
	await tree.process_frame
	await tree.process_frame
	if is_instance_valid(node):
		Plate.relight_all(tree)


class _Stamp:
	extends Control
	var label := "SANCTUM · "
	var value := "41%"
	var ink := Color(0.1, 0.11, 0.12, 0.85)

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		draw_arc(c, r - 6.0, 0.0, TAU, 64, ink, 1.5, true)
		draw_arc(c, r - 22.0, 0.0, TAU, 64, ink, 1.0, true)
		var f := Kit.font("mono_bold")
		for i in label.length():
			var a := -PI * 0.5 + TAU * i / label.length()
			var pos := c + Vector2(cos(a), sin(a)) * (r - 14.0)
			draw_set_transform(pos, a + PI * 0.5, Vector2.ONE)
			draw_char(f, Vector2(-3.0, 3.5), label[i], 9, ink)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var fb := Kit.font("wide_black")
		var fs := int(clampf(r * 0.42, 12.0, 40.0))
		var w := fb.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(fb, c + Vector2(-w * 0.5, fs * 0.38), value, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)


## Decorative matrix code with three finder squares (not a scannable code).
class _Matrix:
	extends Control

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var n := 21
		var c := size.x / n
		var rng := RandomNumberGenerator.new()
		rng.seed = 2044
		var ink := Color("1e2023")
		for y in n:
			for x in n:
				if (x < 7 and y < 7) or (x >= n - 7 and y < 7) or (x < 7 and y >= n - 7):
					continue
				if rng.randf() < 0.48:
					draw_rect(Rect2(x * c, y * c, c, c), ink)
		for f: Vector2 in [Vector2(0, 0), Vector2(n - 7, 0), Vector2(0, n - 7)]:
			draw_rect(Rect2(f * c, Vector2(7, 7) * c), ink)
			draw_rect(Rect2((f + Vector2(1, 1)) * c, Vector2(5, 5) * c), Color("d8dbd7"))
			draw_rect(Rect2((f + Vector2(2, 2)) * c, Vector2(3, 3) * c), ink)


## Decorative barcode (seeded bars, not a real code).
class _Barcode:
	extends Control
	var color := Color("101113")
	var seed_value := 289

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var x := 0.0
		while x < size.x:
			var bw := float(rng.randi_range(1, 4))
			if rng.randf() < 0.7:
				draw_rect(Rect2(x, 0, minf(bw, size.x - x), size.y), color)
			x += bw + float(rng.randi_range(1, 3))


## A coil spring seen end-on in perspective, in heavy ink.
class _Coil:
	extends Control

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var n := 30
		var y := 40.0
		for i in n:
			var k := float(i) / n
			var rx := lerpf(92.0, 16.0, pow(k, 0.8)) * size.x / 240.0
			var ry := rx * lerpf(0.55, 0.2, k)
			var cx := size.x * 0.5 + sin(k * 5.0) * 10.0 * (1.0 - k)
			var w := lerpf(7.0, 1.5, k)
			draw_set_transform(Vector2(cx, y), 0.0, Vector2(1.0, ry / maxf(rx, 0.01)))
			draw_arc(Vector2.ZERO, rx, 0.0, TAU, 64, Color(0.06, 0.065, 0.07, lerpf(0.95, 0.6, k)), w, true)
			y += lerpf(26.0, 8.0, k) * size.y / 650.0
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
