extends RefCounted
## Pieces for the collector screens (the prints album and the Rival) in the poster look, with the
## physical elements of the owner's 2026-10-19 references (rebuilt, never copied): debossed type
## pressed into the stock, frosted acrylic index tabs, HUD ring arcs and ticks with a barcode ring
## and a two-column mono data list around a specimen, leader lines to small labels, LEDs set into
## the surface, a hand-drawn marker scrawl and stickers (the Rival's graffiti).
##   const CK := preload("res://src/ui/v4/collect/collect_kit.gd")

const INK := Color("101113")
const PAPER := Color("e9e8e2")
const CARD := Color("f4f3ef")
const SIG := Color("ff4b1f")
const FELT := Color("8c8d8f")


## An invisible tap area for a scrolling page: drags pass through to the ScrollContainer (a finger
## can scroll from anywhere on a phone) and a press that turned into a scroll does not fire.
## text: its words for tests and readers (drawn invisible).
static func hit(parent: Control, r: Rect2, on_pressed: Callable, node_name: String = "", text: String = "") -> Button:
	var b := Button.new()
	b.theme_type_variation = &"BareButton"
	b.focus_mode = Control.FOCUS_NONE
	b.flat = true
	b.position = r.position
	b.size = r.size
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	if node_name != "":
		b.name = node_name
	if text != "":
		b.text = text
		for k: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color", "font_hover_pressed_color"]:
			b.add_theme_color_override(k, Color(0, 0, 0, 0))
	b.button_down.connect(func() -> void: b.set_meta("_down_at", b.get_global_mouse_position()))
	Kit._connect_pressed(b, on_pressed)
	parent.add_child(b)
	return b


## Type pressed into the stock: a dark wall above, a light lip below, the face a shade darker than
## the ground. ground: the colour it is pressed into.
static func deboss(text: String, size: int, ground: Color, weight: String = "wide_black", depth: float = 1.5) -> Control:
	var box := Control.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lip := Color(ground.lightened(0.6), 0.95)
	var wall := Color(ground.darkened(0.7), 0.9)
	var face := ground.darkened(0.3)
	for layer: Array in [[lip, Vector2(0, depth)], [wall, Vector2(-depth * 0.5, -depth)], [face, Vector2.ZERO]]:
		var l := Kit.label(text, size, layer[0], weight)
		l.position = layer[1]
		box.add_child(l)
	box.size = (box.get_child(2) as Label).get_minimum_size()
	return box


## A frosted acrylic index tab as a Button: a clear slab with a bright rim and a soft shadow, the label
## in mono, a count, and a small LED that lights when it is the selected one. 88 px tall target.
static func acrylic_tab(text: String, count: int, selected: bool, w: float, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.theme_type_variation = &"BareButton"
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(w, 88)
	b.size = b.custom_minimum_size
	b.text = text
	for k: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(k, Color(0, 0, 0, 0))
	var slab := Panel.new()
	slab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1.0, 0.36, 0.17, 0.82) if selected else Color(0.96, 0.97, 0.98, 0.55)
	sb.border_color = Color(1, 1, 1, 0.95)
	sb.border_width_top = 2
	sb.border_width_left = 2
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.corner_radius_top_left = 10
	sb.corner_radius_top_right = 10
	sb.corner_radius_bottom_left = 3
	sb.corner_radius_bottom_right = 3
	sb.shadow_color = Color(0, 0, 0, 0.22 if selected else 0.14)
	sb.shadow_size = 6
	sb.shadow_offset = Vector2(0, 3)
	sb.anti_aliasing = true
	slab.add_theme_stylebox_override("panel", sb)
	slab.position = Vector2(0, 14)
	slab.size = Vector2(w, 62)
	b.add_child(slab)
	# A frosted streak across the top of the slab.
	var streak := ColorRect.new()
	streak.mouse_filter = Control.MOUSE_FILTER_IGNORE
	streak.color = Color(1, 1, 1, 0.35 if not selected else 0.22)
	streak.position = Vector2(8, 4)
	streak.size = Vector2(w - 16, 3)
	slab.add_child(streak)
	var fg := CARD if selected else INK
	var l := Kit.label(text.to_upper(), 12, fg, "mono_bold")
	l.clip_text = true
	l.size = Vector2(w - 34, 16)
	l.position = Vector2(12, 12)
	slab.add_child(l)
	var n := Kit.label("%02d" % count, 26, fg, "compressed")
	n.position = Vector2(12, 26)
	slab.add_child(n)
	var led := HUDLed.new()
	led.on = selected
	led.position = Vector2(w - 22, 14)
	led.size = Vector2(10, 10)
	slab.add_child(led)
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	b.button_down.connect(func() -> void:
		b.set_meta("_down_at", b.get_global_mouse_position())
		slab.position.y = 17.0)
	b.button_up.connect(func() -> void: slab.position.y = 14.0)
	if on_pressed.is_valid():
		Kit._connect_pressed(b, on_pressed)
	return b


## A tiny LED set into the surface: a dark socket, the lens lit (signal) or dark.
class HUDLed:
	extends Control
	var on := false
	var color := Color("ff4b1f")
	var _t := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		if on and Kit.motion_ok():
			_t += delta
			queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		draw_circle(c, r + 1.5, Color(0, 0, 0, 0.35))
		if on:
			var k := 0.8 + 0.2 * sin(_t * 3.2)
			draw_circle(c, r * 1.9, Color(color, 0.16 * k))
			draw_circle(c, r, color.lerp(Color(1, 0.85, 0.7), 0.15 * k))
			draw_circle(c - Vector2(r * 0.3, r * 0.3), r * 0.35, Color(1, 1, 1, 0.75))
		else:
			draw_circle(c, r, Color(0.25, 0.08, 0.05))
			draw_circle(c - Vector2(r * 0.3, r * 0.3), r * 0.3, Color(1, 1, 1, 0.25))


## HUD ring around a specimen (the planet-sheet reference): partial arcs with gaps, a tick ring,
## short bars sitting on the arcs, corner brackets; the arcs turn slowly. Draws around `center`
## with `radius`.
class HudRing:
	extends Control
	var center := Vector2.ZERO
	var radius := 200.0
	var color := Color(0.063, 0.067, 0.075, 0.8)
	var accent := Color("ff4b1f")
	var _t := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		if Kit.motion_ok():
			_t += delta
			queue_redraw()

	func _draw() -> void:
		var c := center
		var r := radius
		var spin := _t * 0.08
		# The main arc: most of a circle, open at the bottom left.
		draw_arc(c, r, -PI * 0.92 + spin * 0.3, PI * 0.05 + spin * 0.3, 96, color, 1.4, true)
		draw_arc(c, r + 10.0, -PI * 0.62 - spin, -PI * 0.38 - spin, 24, color, 4.0, true)
		draw_arc(c, r - 14.0, PI * 0.18 + spin * 0.6, PI * 0.42 + spin * 0.6, 30, Color(color, 0.5), 1.0, true)
		# Bars sitting on the outer arc (segment readouts).
		for i in 5:
			var a := -PI * 0.88 + i * 0.07 + spin * 0.3
			var p0 := c + Vector2(cos(a), sin(a)) * (r + 4.0)
			var p1 := c + Vector2(cos(a + 0.05), sin(a + 0.05)) * (r + 4.0)
			draw_line(p0, p1, Color(color, 0.85 - i * 0.12), 5.0)
		# A tick ring on the right.
		for i in 40:
			var a := -0.5 + i * 0.025
			var long := i % 5 == 0
			var p0 := c + Vector2(cos(a), sin(a)) * (r + 24.0)
			var p1 := c + Vector2(cos(a), sin(a)) * (r + (34.0 if long else 29.0))
			draw_line(p0, p1, Color(color, 0.8 if long else 0.45), 1.0)
		# Sloped hairlines like a gauge's needles.
		for k in 3:
			var a := 0.55 + k * 0.12
			var p0 := c + Vector2(cos(a), sin(a)) * (r + 30.0)
			var p1 := c + Vector2(cos(a), sin(a)) * (r + 64.0)
			draw_line(p0, p1, Color(color, 0.7), 1.2, true)
		# An accent tick.
		var aa := -PI * 0.5 + spin * 0.3
		draw_line(c + Vector2(cos(aa), sin(aa)) * (r - 6.0), c + Vector2(cos(aa), sin(aa)) * (r + 14.0), accent, 3.0)
		# Small square markers at the four quarter points.
		for i in 4:
			var a := i * PI * 0.5 + PI * 0.25
			var p := c + Vector2(cos(a), sin(a)) * (r + 46.0)
			draw_rect(Rect2(p - Vector2(2.5, 2.5), Vector2(5, 5)), Color(color, 0.6), false, 1.0)


## L-shaped corner brackets and the centre ticks of a frame (the planet sheet's crop frame).
class CropFrame:
	extends Control
	var color := Color(0.063, 0.067, 0.075, 0.8)
	var arm := 16.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var a := arm
		for p: Array in [[Vector2(0, 0), Vector2(1, 1)], [Vector2(w, 0), Vector2(-1, 1)], [Vector2(0, h), Vector2(1, -1)], [Vector2(w, h), Vector2(-1, -1)]]:
			var o: Vector2 = p[0]
			var d: Vector2 = p[1]
			draw_line(o, o + Vector2(a * d.x, 0), color, 1.5)
			draw_line(o, o + Vector2(0, a * d.y), color, 1.5)
		draw_line(Vector2(w * 0.5, 0), Vector2(w * 0.5, 8), color, 1.0)
		draw_line(Vector2(w * 0.5, h), Vector2(w * 0.5, h - 8), color, 1.0)


## A ring of seeded bars (a circular barcode) with a small caption under it.
class BarcodeRing:
	extends Control
	var seed_v := 1
	var color := Color("101113")
	var caption := "ID"

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := Vector2(size.x * 0.5, size.x * 0.5)
		var r := size.x * 0.5
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_v
		var a := 0.0
		while a < TAU - 0.05:
			var wdt := rng.randf_range(0.03, 0.16)
			if rng.randf() < 0.62:
				var pts := PackedVector2Array()
				var steps := 4
				for i in steps + 1:
					var t := a + wdt * i / steps
					pts.append(c + Vector2(cos(t), sin(t)) * r)
				for i in range(steps, -1, -1):
					var t := a + wdt * i / steps
					pts.append(c + Vector2(cos(t), sin(t)) * (r * 0.62))
				draw_colored_polygon(pts, color)
			a += wdt + rng.randf_range(0.02, 0.06)
		var f := Kit.font("mono")
		var fs := 10
		var tw := f.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(f, Vector2(c.x - tw * 0.5, size.x + 14), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)


## A two-column mono data list (the planet sheet's): rows [key, value] or [key, value, true]; a
## highlighted row gets a pale bar, a tick and the value in square brackets. Gaps: an empty row.
class DataList:
	extends Control
	var rows: Array = []
	var color := Color("101113")
	var text_size := 13
	var row_h := 22.0
	var bar := Color(1, 1, 1, 0.65)

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var f := Kit.font("mono")
		var fb := Kit.font("mono_bold")
		var asc := f.get_ascent(text_size)
		var y := 0.0
		for r: Array in rows:
			if r.is_empty():
				y += row_h * 0.6
				continue
			var hi := r.size() > 2 and bool(r[2])
			var base := y + (row_h + asc) * 0.5 - 2.0
			if hi:
				draw_rect(Rect2(-6, y + 1, size.x + 12, row_h - 2), bar)
				draw_line(Vector2(-2, y + 5), Vector2(-2, y + row_h - 5), color, 2.0)
			draw_string(fb if hi else f, Vector2(8, base), str(r[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, text_size, color)
			var v := str(r[1])
			if hi:
				v = "[  %s  ]" % v
			var vw := (fb if hi else f).get_string_size(v, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size).x
			draw_string(fb if hi else f, Vector2(size.x - vw, base), v, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size, color)
			y += row_h


## An engraved corner ornament (the parchment poster reference): a double rule turning the corner,
## scrolls curling in at both ends, a leaf spray at the bend and fine hatching, in ink line work.
## `flip` mirrors it (x, y) for the other corners.
class Ornament:
	extends Control
	var color := Color(0.063, 0.067, 0.075, 0.85)
	var flip := Vector2(1, 1)

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _p(v: Vector2) -> Vector2:
		return Vector2(size.x * 0.5 + (v.x - size.x * 0.5) * flip.x, size.y * 0.5 + (v.y - size.y * 0.5) * flip.y)

	func _line(a: Vector2, b: Vector2, w: float = 1.2) -> void:
		draw_line(_p(a), _p(b), color, w, true)

	func _spiral(c: Vector2, r0: float, turns: float, dir: float, start: float) -> void:
		var pts := PackedVector2Array()
		var n := int(40 * turns)
		for i in n + 1:
			var t := float(i) / n
			var a := start + dir * t * turns * TAU
			var r := r0 * (1.0 - t * 0.85)
			pts.append(_p(c + Vector2(cos(a), sin(a)) * r))
		draw_polyline(pts, color, 1.2, true)

	func _leaf(at: Vector2, ang: float, l: float) -> void:
		var pts := PackedVector2Array()
		for i in 13:
			var t := float(i) / 12.0
			var x := t * l
			var y := sin(t * PI) * l * 0.28
			pts.append(_p(at + Vector2(x, y).rotated(ang)))
		for i in range(12, -1, -1):
			var t := float(i) / 12.0
			var x := t * l
			var y := -sin(t * PI) * l * 0.28
			pts.append(_p(at + Vector2(x, y).rotated(ang)))
		draw_polyline(pts, color, 1.0, true)
		_line(at, at + Vector2(l * 0.9, 0).rotated(ang), 0.8)

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var o := 6.0
		# The double rule round the corner.
		_line(Vector2(o, o), Vector2(w - 22, o), 1.6)
		_line(Vector2(o, o), Vector2(o, h - 22), 1.6)
		_line(Vector2(o + 6, o + 6), Vector2(w - 34, o + 6), 0.8)
		_line(Vector2(o + 6, o + 6), Vector2(o + 6, h - 34), 0.8)
		# Scrolls curling in at both ends.
		_spiral(Vector2(w - 18, o + 12), 12.0, 1.6, 1.0, -PI * 0.5)
		_spiral(Vector2(o + 12, h - 18), 12.0, 1.6, -1.0, PI)
		# A leaf spray at the bend and a dot.
		var c := Vector2(o + 26, o + 26)
		draw_circle(_p(c), 3.0, color)
		for k in 5:
			_leaf(c + Vector2(4, 4), 0.15 + k * 0.32, 22.0 + (k % 2) * 6.0)
		# Hatching along the inner rule.
		var x := o + 52.0
		while x < w - 48.0:
			_line(Vector2(x, o + 9), Vector2(x - 4, o + 14), 0.7)
			x += 6.0
		var y := o + 52.0
		while y < h - 48.0:
			_line(Vector2(o + 9, y), Vector2(o + 14, y - 4), 0.7)
			y += 6.0


## An engraved divider (fleuron): a rule with a lozenge at the middle and curls either side.
class Fleuron:
	extends Control
	var color := Color(0.063, 0.067, 0.075, 0.85)

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var cy := size.y * 0.5
		var cx := size.x * 0.5
		draw_line(Vector2(0, cy), Vector2(cx - 46, cy), color, 1.0)
		draw_line(Vector2(cx + 46, cy), Vector2(size.x, cy), color, 1.0)
		draw_colored_polygon(PackedVector2Array([Vector2(cx, cy - 7), Vector2(cx + 7, cy), Vector2(cx, cy + 7), Vector2(cx - 7, cy)]), color)
		for sgn: float in [-1.0, 1.0]:
			var pts := PackedVector2Array()
			for i in 41:
				var t := float(i) / 40.0
				var a := t * TAU * 1.25
				var r := 9.0 * (1.0 - t * 0.7)
				pts.append(Vector2(cx + sgn * (16.0 + t * 22.0) + sgn * cos(a) * r * 0.5, cy - sin(a) * r))
			draw_polyline(pts, color, 1.1, true)
			draw_circle(Vector2(cx + sgn * 46.0, cy), 2.2, color)


## A thin leader line from a point to a label (the terrain map's callouts): a dot, a diagonal, a
## horizontal run, and mono text over the run.
class Leader:
	extends Control
	var from := Vector2.ZERO
	var to := Vector2(60, -40)
	var text := ""
	var sub := ""
	var color := Color(0.063, 0.067, 0.075, 0.85)
	var run := 70.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_circle(from, 2.5, color)
		draw_line(from, to, color, 1.0, true)
		var dir := 1.0 if to.x >= from.x else -1.0
		var end := to + Vector2(run * dir, 0)
		draw_line(to, end, color, 1.0)
		var f := Kit.font("mono_bold")
		var fs := 11
		var x := to.x if dir > 0 else end.x
		draw_string(f, Vector2(x, to.y - 5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)
		if sub != "":
			draw_string(Kit.font("mono"), Vector2(x, to.y + 13), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(color, 0.75))


## A marker scrawl: words written by hand with a felt marker (single-stroke letters with a little
## wobble, round caps, ink pooling at the stroke ends). Letters: A-Z, space, ! and ?. `seed_v` sets
## the hand.
class Scrawl:
	extends Control
	var text := "RUE WAS HERE"
	var color := Color("ff4b1f")
	var stroke := 7.0
	var seed_v := 3
	var reveal := 1.0
	## Glyphs in a 0..1 box (y down) as polylines.
	const G := {
		"A": [[[0, 1], [0.5, 0], [1, 1]], [[0.22, 0.6], [0.78, 0.6]]],
		"B": [[[0, 1], [0, 0], [0.7, 0.04], [0.8, 0.25], [0.65, 0.47], [0, 0.5]], [[0.65, 0.47], [0.9, 0.7], [0.75, 0.97], [0, 1]]],
		"C": [[[0.95, 0.15], [0.6, 0], [0.2, 0.1], [0, 0.5], [0.2, 0.9], [0.6, 1], [0.95, 0.85]]],
		"D": [[[0, 0], [0, 1], [0.6, 0.95], [0.95, 0.5], [0.6, 0.05], [0, 0]]],
		"E": [[[0.9, 0], [0, 0], [0, 1], [0.9, 1]], [[0, 0.5], [0.7, 0.5]]],
		"F": [[[0.9, 0], [0, 0], [0, 1]], [[0, 0.5], [0.7, 0.5]]],
		"G": [[[0.95, 0.15], [0.6, 0], [0.2, 0.1], [0, 0.5], [0.2, 0.9], [0.6, 1], [0.95, 0.8], [0.95, 0.55], [0.55, 0.55]]],
		"H": [[[0, 0], [0, 1]], [[1, 0], [1, 1]], [[0, 0.5], [1, 0.5]]],
		"I": [[[0.5, 0], [0.5, 1]]],
		"K": [[[0, 0], [0, 1]], [[0.9, 0], [0, 0.6]], [[0.3, 0.42], [0.95, 1]]],
		"L": [[[0, 0], [0, 1], [0.85, 1]]],
		"M": [[[0, 1], [0.05, 0], [0.5, 0.65], [0.95, 0], [1, 1]]],
		"N": [[[0, 1], [0, 0], [1, 1], [1, 0]]],
		"O": [[[0.5, 0], [0.1, 0.2], [0, 0.55], [0.2, 0.92], [0.55, 1], [0.9, 0.8], [1, 0.42], [0.8, 0.08], [0.45, 0.02]]],
		"P": [[[0, 1], [0, 0], [0.7, 0.03], [0.9, 0.25], [0.7, 0.5], [0, 0.52]]],
		"R": [[[0, 1], [0, 0], [0.7, 0.03], [0.9, 0.25], [0.7, 0.5], [0, 0.52]], [[0.35, 0.52], [0.95, 1]]],
		"S": [[[0.9, 0.12], [0.55, 0], [0.12, 0.1], [0.08, 0.35], [0.5, 0.5], [0.9, 0.65], [0.85, 0.92], [0.45, 1], [0.05, 0.88]]],
		"T": [[[0, 0], [1, 0]], [[0.5, 0], [0.5, 1]]],
		"U": [[[0, 0], [0, 0.7], [0.2, 0.97], [0.55, 1], [0.85, 0.85], [1, 0.55], [1, 0]]],
		"V": [[[0, 0], [0.5, 1], [1, 0]]],
		"W": [[[0, 0], [0.22, 1], [0.5, 0.35], [0.78, 1], [1, 0]]],
		"Y": [[[0, 0], [0.5, 0.5], [1, 0]], [[0.5, 0.5], [0.5, 1]]],
		"!": [[[0.5, 0], [0.5, 0.7]], [[0.5, 0.92], [0.5, 1]]],
		"?": [[[0.1, 0.2], [0.4, 0], [0.85, 0.12], [0.8, 0.4], [0.5, 0.55], [0.5, 0.72]], [[0.5, 0.92], [0.5, 1]]],
	}

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_v
		var n := text.length()
		var lh := size.y
		var gw := lh * 0.62
		var gap := lh * 0.16
		var x := stroke
		var total_strokes := 0
		for ch in text:
			total_strokes += (G.get(ch, []) as Array).size()
		var shown := int(ceil(total_strokes * clampf(reveal, 0.0, 1.0)))
		var k := 0
		for i in n:
			var ch := text[i]
			if ch == " ":
				x += gw * 0.55
				continue
			var strokes: Array = G.get(ch, [])
			var tilt := rng.randf_range(-0.08, 0.08)
			var lift := rng.randf_range(-lh * 0.06, lh * 0.06)
			var sx := gw * (0.55 if ch == "I" or ch == "!" else rng.randf_range(0.9, 1.08))
			for s: Array in strokes:
				k += 1
				if k > shown:
					return
				var pts := PackedVector2Array()
				for q: Array in s:
					var px := float(q[0])
					var py := float(q[1])
					var p := Vector2(x + px * sx + (py - 0.5) * tilt * lh, stroke * 0.5 + lift + py * (lh - stroke))
					p += Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * stroke * 0.18
					pts.append(p)
				pts = _smooth(pts)
				draw_polyline(pts, Color(color, 0.92), stroke, true)
				# Ink pools where the marker stopped and started.
				draw_circle(pts[0], stroke * 0.55, Color(color, 0.95))
				draw_circle(pts[pts.size() - 1], stroke * 0.62, Color(color, 0.95))
			x += sx + gap

	func _smooth(pts: PackedVector2Array) -> PackedVector2Array:
		if pts.size() < 3:
			return pts
		var out := PackedVector2Array([pts[0]])
		for i in range(1, pts.size() - 1):
			out.append(pts[i].lerp(pts[i - 1], 0.18))
			out.append(pts[i])
			out.append(pts[i].lerp(pts[i + 1], 0.18))
		out.append(pts[pts.size() - 1])
		return out

	## Width the text needs at this height.
	static func width_for(t: String, h: float, stroke_w: float = 7.0) -> float:
		var gw := h * 0.62
		var w := stroke_w * 2.0
		for ch in t:
			w += gw * 0.55 if ch == " " else (gw * (0.55 if ch == "I" or ch == "!" else 1.0) + h * 0.16)
		return w


## A vinyl sticker: a rounded shape (circle or pill) with a white edge and a soft shadow, a fill and
## one or two lines of type; a small devil-horn doodle on top when `horns`.
class Sticker:
	extends Control
	var lines: Array = ["RUE"]
	var fill := Color("101113")
	var ink := Color("ff4b1f")
	var round := true
	var horns := false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var edge := 4.0
		if round:
			var c := size * 0.5
			var rad := minf(size.x, size.y) * 0.5 - 2.0
			draw_circle(c + Vector2(2, 4), rad, Color(0, 0, 0, 0.25))
			draw_circle(c, rad, Color("f7f6f2"))
			draw_circle(c, rad - edge, fill)
		else:
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color("f7f6f2")
			sb.set_corner_radius_all(int(size.y * 0.5))
			sb.shadow_color = Color(0, 0, 0, 0.25)
			sb.shadow_size = 5
			sb.shadow_offset = Vector2(2, 4)
			sb.anti_aliasing = true
			draw_style_box(sb, r)
			var sb2 := StyleBoxFlat.new()
			sb2.bg_color = fill
			sb2.set_corner_radius_all(int(size.y * 0.5 - edge))
			sb2.anti_aliasing = true
			draw_style_box(sb2, r.grow(-edge))
		if horns:
			var c := size * 0.5
			var rad := minf(size.x, size.y) * 0.5
			for sgn: float in [-1.0, 1.0]:
				var b0 := c + Vector2(sgn * rad * 0.45, -rad * 0.72)
				var tip := c + Vector2(sgn * rad * 0.78, -rad * 1.18)
				var b1 := c + Vector2(sgn * rad * 0.18, -rad * 0.86)
				draw_colored_polygon(PackedVector2Array([b0, tip, b1]), Color("f7f6f2"))
				draw_colored_polygon(PackedVector2Array([b0.lerp(c, 0.08), tip.lerp(c, 0.08), b1.lerp(c, 0.08)]), ink)
		var f := Kit.font("wide_black")
		var fm := Kit.font("mono_bold")
		var n := lines.size()
		for i in n:
			var s := str(lines[i])
			var big := i == 0
			var fs := int(size.y * (0.3 if big else 0.13))
			var font: Font = f if big else fm
			var tw := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			while fs > 6 and tw > size.x * 0.78:
				fs -= 1
				tw = font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var y := size.y * (0.56 if n == 1 else (0.5 if big else 0.72))
			draw_string(font, Vector2((size.x - tw) * 0.5, y + (fs * 0.3 if n == 1 else 0.0)), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)
