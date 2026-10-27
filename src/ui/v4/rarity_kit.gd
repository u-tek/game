extends RefCounted
## The rarity language (owner, 2026-10-20: "i want each rarity of hero to have its own reveal
## animation in the summon pool, so more flashy depending on rarity. and i want this to carry over to
## the hero list"). One look per rarity, from the summon's press run to her card in the roster, in the
## poster look's own terms (printing: plates, inks, foil):
##   Rare       a plain print: one plate, ink on paper.
##   Epic       a two-plate print: a violet and a teal ink plate, a hair out of register at the edge,
##              and a slow violet foil sheen running across.
##   Legendary  gold foil: foil that catches the light as the phone tilts (ui_tilt) and sparkles, her
##              faction's growth (the Blender thorns, jelly and moss) curling slowly on a corner, a
##              LEGEND tab and a shimmer on her name.
## The summon (src/ui/summon/: the portal's tells, every reveal, the pips, the contact sheet) and the
## cards (PosterCard: the roster and the team bench) take their colours and pieces from here.
##   const RK := preload("res://src/ui/v4/rarity_kit.gd")
## Shaders: foil.gdshader, growth_twist.gdshader, halftone_burst.gdshader, name_shimmer.gdshader (all
## animate on the GPU's clock: nothing per card runs on the CPU while the roster scrolls; offscreen
## cards are culled). Reduce motion (Kit.motion_ok) holds them still.

const FOIL := preload("res://src/ui/shaders/foil.gdshader")
const GROWTH := preload("res://src/ui/shaders/growth_twist.gdshader")
const BURST := preload("res://src/ui/shaders/halftone_burst.gdshader")
const SHIMMER := preload("res://src/ui/shaders/name_shimmer.gdshader")
const Fx := preload("res://src/ui/summon/summon_fx.gd")

const INK := SignalKit.INK
const PAPER := SignalKit.PAPER
const SIGNAL := SignalKit.SIGNAL
## Epic: the first plate (violet), the second (teal), and the band's deep violet.
const VIOLET := Color("8048e8")
const TEAL := Color("12b3c4")
const VIOLET_DEEP := Color("1b1236")
## Legendary: the foil's mid tone, highlight and shadow; GOLD_INK is gold as a flat printed ink.
const GOLD := Color("c49231")
const GOLD_HI := Color("ffeab0")
const GOLD_LO := Color("4c3209")
const GOLD_INK := Color("b8892c")

const RANK := {"rare": 0, "epic": 1, "legendary": 2}


static func rank(rarity: String) -> int:
	return int(RANK.get(rarity, 0))


## The rarity's ink: black for a Rare, violet for an Epic, gold for a Legendary.
static func ink(rarity: String) -> Color:
	match rarity:
		"legendary":
			return GOLD_INK
		"epic":
			return VIOLET
	return INK


static func motion() -> float:
	return 1.0 if Kit.motion_ok() else 0.0


# ------------------------------------------------------------------ materials

## A foil material. kind "gold" | "violet"; mode 0 sheet, 1 sheen, 2 die, 3 sweep (foil.gdshader).
## opts: any of the shader's uniforms by name.
static func foil_material(kind: String, mode: int, opts: Dictionary = {}) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = FOIL
	m.set_shader_parameter("mode", mode)
	if kind == "violet":
		m.set_shader_parameter("base", Color("7a62e6"))
		m.set_shader_parameter("hi", Color("e9e2ff"))
		m.set_shader_parameter("lo", Color("2c1a6e"))
		m.set_shader_parameter("rainbow", 0.0)
	else:
		m.set_shader_parameter("base", GOLD)
		m.set_shader_parameter("hi", GOLD_HI)
		m.set_shader_parameter("lo", GOLD_LO)
	m.set_shader_parameter("motion", motion())
	for k: String in opts:
		m.set_shader_parameter(k, opts[k])
	return m


## A ColorRect of foil at `rect` in `parent`.
static func foil_rect(parent: Node, rect: Rect2, kind: String, mode: int, opts: Dictionary = {}) -> ColorRect:
	var r := ColorRect.new()
	r.name = "Foil"
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.position = rect.position
	r.size = rect.size
	var o := opts.duplicate()
	o["rect_size"] = rect.size
	r.material = foil_material(kind, mode, o)
	parent.add_child(r)
	return r


## Her faction's growth piece (PhysicalKit.growth: thorns or jelly and moss) on the growing, twisting
## shader, its poster corner at `at`, `ppu` screen px per world unit. opts: grow (1.0), breathe (0.0),
## twist (0.05), speed (0.35), phase (random), rot. Returns the TextureRect (null if missing).
static func growth(faction: String, shape: String, parent: Node, at: Vector2, ppu: float, opts: Dictionary = {}) -> TextureRect:
	var tr := PhysicalKit.growth(faction, shape, parent, at, ppu, float(opts.get("rot", 0.0)))
	if tr == null:
		return null
	var m := ShaderMaterial.new()
	m.shader = GROWTH
	var sz := tr.size
	m.set_shader_parameter("origin", Vector2(tr.pivot_offset.x / maxf(sz.x, 1.0), tr.pivot_offset.y / maxf(sz.y, 1.0)))
	m.set_shader_parameter("aspect", sz.x / maxf(sz.y, 1.0))
	# The farthest corner of the piece from its origin (aspect corrected, UV units of the height).
	var o := tr.pivot_offset / maxf(sz.y, 1.0)
	var far := 0.0
	for c: Vector2 in [Vector2.ZERO, Vector2(sz.x, 0), Vector2(0, sz.y), sz]:
		far = maxf(far, (c / maxf(sz.y, 1.0) - o).length())
	m.set_shader_parameter("reach", far)
	m.set_shader_parameter("grow", float(opts.get("grow", 1.0)))
	m.set_shader_parameter("breathe", float(opts.get("breathe", 0.0)))
	m.set_shader_parameter("twist", float(opts.get("twist", 0.05)))
	m.set_shader_parameter("speed", float(opts.get("speed", 0.35)))
	m.set_shader_parameter("phase", float(opts.get("phase", randf() * 6.0)))
	m.set_shader_parameter("motion", motion())
	tr.material = m
	return tr


## A shimmer of foil light along a label's text (a Legendary's name).
static func shimmer(l: Control, length_px: float, seed_v: float = 0.0) -> void:
	var m := ShaderMaterial.new()
	m.shader = SHIMMER
	m.set_shader_parameter("length_px", length_px)
	m.set_shader_parameter("motion", motion())
	m.set_shader_parameter("seed", seed_v)
	l.material = m


## The radial halftone burst over a rect (the Epic press): set_k(m, k) runs it.
static func halftone_burst(parent: Node, rect: Rect2, center: Vector2, ink1: Color, ink2: Color = Color(0, 0, 0, 0)) -> ColorRect:
	var r := ColorRect.new()
	r.name = "HalftoneBurst"
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.position = rect.position
	r.size = rect.size
	var m := ShaderMaterial.new()
	m.shader = BURST
	m.set_shader_parameter("rect_size", rect.size)
	m.set_shader_parameter("center", center)
	m.set_shader_parameter("reach", rect.size.length() * 0.8)
	m.set_shader_parameter("ink", ink1)
	m.set_shader_parameter("ink2", ink2)
	m.set_shader_parameter("k", 0.0)
	r.material = m
	r.visible = false
	parent.add_child(r)
	return r


# ------------------------------------------------------------------ cards

## The rarity's frame on a printed card (PosterCard, the contact sheet's prints). `clip` is the card's
## clipped poster (the sheen and the plate edge go in it), `face` its unclipped root (the growth and
## the tab stick out of it), `size` the card's size. A Rare gets nothing. opts: k (scale, 1 at 218 px
## wide), faction, name_label (a Label to shimmer), name_len (its length in px), live (true: animated;
## false for prints not owned yet), seed. Returns the frame (a Frame: intro(delay) plays its entrance)
## or null for a Rare.
static func card_frame(clip: Control, face: Control, size: Vector2, rarity: String, opts: Dictionary = {}) -> Frame:
	if rarity != "epic" and rarity != "legendary":
		return null
	var k := float(opts.get("k", size.x / 218.0))
	var live := bool(opts.get("live", true)) and Kit.motion_ok()
	var sd := float(opts.get("seed", randf() * 10.0))
	var f := Frame.new()
	f.rarity = rarity
	f.k = k
	f.size = size
	if rarity == "epic":
		var edge := PlateEdge.new()
		edge.name = "PlateEdge"
		edge.k = k
		edge.size = size
		clip.add_child(edge)
		f.edge = edge
		var sheen := foil_rect(clip, Rect2(Vector2.ZERO, size), "violet", 1, {"sheen": 0.34, "sparkle": 0.0, "glint": 1.0,
			"travel": true, "speed": 0.08, "seed": sd, "motion": 1.0 if live else 0.0, "sweep_w": 0.14})
		sheen.name = "EpicSheen"
		f.foil = sheen
		if bool(opts.get("dim", false)):
			_dim(f)
		face.add_child(f)
		return f
	# Legendary: gold holo foil (a solid frame and a sheen), the growth, the tab, the name's shimmer.
	var gold := foil_rect(clip, Rect2(Vector2.ZERO, size), "gold", 1, {"edge": maxf(3.5, 6.0 * k), "sheen": 0.24,
		"sparkle": 1.0 if live else 0.0, "rainbow": 0.22, "glint": 1.0, "speed": 0.07, "seed": sd,
		"motion": 1.0 if live else 0.0, "sweep_w": 0.16})
	gold.name = "LegendFoil"
	f.foil = gold
	var fac := str(opts.get("faction", "celestial"))
	if bool(opts.get("growth", true)):
		# Thin, on the top right corner: along the top edge and down the right side, under the lights.
		var g := growth(fac, "tr", face, Vector2(size.x - 1.0 * k, 1.0 * k), 22.0 * k,
			{"twist": 0.09, "speed": 0.42, "breathe": 0.55, "grow": 1.0, "phase": sd})
		if g:
			g.name = "LegendGrowth"
			if not live:
				(g.material as ShaderMaterial).set_shader_parameter("motion", 0.0)
			f.growth = g
	var tab := LegendTab.new()
	tab.name = "LegendTab"
	tab.k = k
	tab.size = Vector2(78, 22) * k
	tab.position = Vector2(float(opts.get("tab_x", 58.0 * k)), -11.0 * k)
	tab.pivot_offset = tab.size * 0.5
	tab.rotation = -0.035
	face.add_child(tab)
	f.tab = tab
	var nl: Variant = opts.get("name_label", null)
	if nl is Control and live:
		shimmer(nl as Control, float(opts.get("name_len", 300.0)), sd)
	if bool(opts.get("dim", false)):
		_dim(f)
	face.add_child(f)
	return f


## A frame on a print not owned yet (the codex): its pieces printed faint.
static func _dim(f: Frame) -> void:
	for c: CanvasItem in [f.edge, f.foil, f.growth, f.tab]:
		if c:
			c.modulate = Color(0.78, 0.78, 0.78, 0.55)


## The frame's handle: its pieces and its entrance (intro).
class Frame:
	extends Control
	var rarity := "epic"
	var k := 1.0
	var edge: Control
	var foil: ColorRect
	var growth: TextureRect
	var tab: Control

	func _init() -> void:
		name = "RarityFrame"
		mouse_filter = MOUSE_FILTER_IGNORE

	## The card's rarity entrance (the roster's first view, a new hero): an Epic's plates come into
	## register and its sheen passes once; a Legendary's foil flashes across, her growth grows out of
	## the corner and the LEGEND tab slams on. Nothing under Reduce motion.
	func intro(delay: float = 0.0) -> void:
		if not Kit.motion_ok():
			return
		if not is_inside_tree():
			# Built before its list joined the screen: play once it is in.
			tree_entered.connect(intro.bind(delay), CONNECT_ONE_SHOT)
			return
		var tw := create_tween()
		tw.tween_interval(delay)
		var fm := foil.material as ShaderMaterial if foil else null
		if rarity == "epic":
			if edge:
				edge.set("spread", 1.0)
				tw.tween_property(edge, "spread", 0.0, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			if fm:
				tw.parallel().tween_method(func(x: float) -> void: fm.set_shader_parameter("sweep", x), 0.0, 1.0, 0.7)
				tw.tween_callback(func() -> void: fm.set_shader_parameter("sweep", -1.0))
			return
		if growth:
			var gm := growth.material as ShaderMaterial
			gm.set_shader_parameter("grow", 0.0)
			tw.tween_method(func(x: float) -> void: gm.set_shader_parameter("grow", x), 0.0, 1.0, 0.9).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		if fm:
			tw.parallel().tween_method(func(x: float) -> void: fm.set_shader_parameter("sweep", x), 0.0, 1.0, 0.8)
		if tab:
			tab.scale = Vector2(2.2, 2.2)
			tab.modulate.a = 0.0
			tw.parallel().tween_property(tab, "modulate:a", 1.0, 0.08).set_delay(0.25)
			tw.parallel().tween_property(tab, "scale", Vector2.ONE, 0.3).set_delay(0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		if fm:
			tw.tween_callback(func() -> void: fm.set_shader_parameter("sweep", -1.0))


## An Epic's plate edge: a violet and a teal hairline frame, a hair out of register (spread pulls
## them further apart: the entrance), with registration ticks at two corners.
class PlateEdge:
	extends Control
	var k := 1.0
	var spread := 0.0:
		set(v):
			spread = v
			queue_redraw()

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var w := maxf(1.5, 2.2 * k)
		var inset := 3.0 * k
		var o := Vector2(1.6, 1.2) * k * (1.0 + 6.0 * spread)
		var r := Rect2(Vector2(inset, inset), size - Vector2(inset, inset) * 2.0)
		draw_rect(Rect2(r.position - o, r.size), Color(TEAL, 0.9), false, w)
		draw_rect(Rect2(r.position + o, r.size), Color(VIOLET, 0.95), false, w)
		# Registration ticks (a small cross in a circle) on the top right and bottom left.
		for c: Vector2 in [Vector2(size.x - 12.0 * k, 12.0 * k), Vector2(12.0 * k, size.y - 12.0 * k)]:
			var col := Color(VIOLET, 0.8)
			draw_arc(c, 3.5 * k, 0.0, TAU, 16, col, maxf(1.0, k), true)
			draw_line(c - Vector2(6, 0) * k, c + Vector2(6, 0) * k, col, maxf(1.0, k))
			draw_line(c - Vector2(0, 6) * k, c + Vector2(0, 6) * k, col, maxf(1.0, k))


## The LEGEND tab: a small ink tab stuck over the card's top edge, LEGEND in gold with a foil rule.
class LegendTab:
	extends Control
	var k := 1.0
	var text := "LEGEND"

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(Rect2(r.position + Vector2(1.5, 2.5) * k, r.size), Color(0, 0, 0, 0.25))
		draw_rect(r, INK)
		draw_rect(Rect2(0, size.y - 3.0 * k, size.x, 3.0 * k), GOLD)
		var f := Kit.font("wide_black")
		var fs := maxi(7, int(11.0 * k))
		var tw := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		while fs > 6 and tw > size.x - 10.0 * k:
			fs -= 1
			tw = f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(f, Vector2((size.x - tw) * 0.5, size.y * 0.5 + fs * 0.36 - 1.0 * k), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, GOLD_HI)
		# A star either side.
		for x: float in [6.0 * k, size.x - 6.0 * k]:
			draw_circle(Vector2(x, size.y * 0.45), 1.6 * k, GOLD)


## Sparks off the press (the Legendary plate hitting the paper): gold streaks flung out from points
## along `emit` (a rect's edges), falling. Driven by `t` (seconds since the press; the reveal's clock
## sets it, so a held frame holds them); hidden outside 0..life.
class Sparks:
	extends Control
	var emit := Rect2(0, 0, 100, 100)
	var count := 70
	var life := 1.1
	var t := -1.0:
		set(v):
			t = v
			visible = t >= 0.0 and t <= life
			if visible:
				queue_redraw()
	var _p := PackedFloat32Array()

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE

	func _ready() -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = 90210
		_p.resize(count * 6)
		var per := emit.size.x * 2.0 + emit.size.y * 2.0
		for i in count:
			# A point on the rect's edge and an outward direction (bias upward: sparks leap).
			var u := rng.randf() * per
			var at := Vector2.ZERO
			var n := Vector2.ZERO
			if u < emit.size.x:
				at = emit.position + Vector2(u, 0)
				n = Vector2(0, -1)
			elif u < emit.size.x * 2.0:
				at = emit.position + Vector2(u - emit.size.x, emit.size.y)
				n = Vector2(0, 1)
			elif u < emit.size.x * 2.0 + emit.size.y:
				at = emit.position + Vector2(0, u - emit.size.x * 2.0)
				n = Vector2(-1, 0)
			else:
				at = emit.position + Vector2(emit.size.x, u - emit.size.x * 2.0 - emit.size.y)
				n = Vector2(1, 0)
			var dir := (n + Vector2(rng.randf_range(-0.9, 0.9), rng.randf_range(-1.0, 0.2))).normalized()
			var sp := rng.randf_range(450.0, 1350.0)
			_p[i * 6] = at.x
			_p[i * 6 + 1] = at.y
			_p[i * 6 + 2] = dir.x * sp
			_p[i * 6 + 3] = dir.y * sp
			_p[i * 6 + 4] = rng.randf_range(0.35, 1.0) * life
			_p[i * 6 + 5] = rng.randf_range(1.6, 3.6)
		visible = false

	func _draw() -> void:
		if t < 0.0:
			return
		var g := 1500.0
		for i in count:
			var l := _p[i * 6 + 4]
			if t > l:
				continue
			var k := t / l
			var p0 := Vector2(_p[i * 6], _p[i * 6 + 1])
			var v := Vector2(_p[i * 6 + 2], _p[i * 6 + 3])
			var drag := 1.0 - 0.45 * k
			var p := p0 + v * t * drag + Vector2(0, 0.5 * g * t * t)
			var vel := v * drag + Vector2(0, g * t)
			var tail := p - vel.normalized() * minf(vel.length() * 0.06, 64.0)
			var col := GOLD_HI.lerp(GOLD, k)
			col.a = 1.0 - k * k
			var wd := _p[i * 6 + 5] * (1.0 - 0.5 * k)
			# A hot orange halo under a pale gold streak, a white-hot head.
			draw_line(tail, p, Color(1.0, 0.55, 0.12, col.a * 0.35), wd * 2.6, true)
			draw_line(tail, p, col, wd, true)
			draw_circle(p, wd * 0.75, Color(1, 0.98, 0.9, col.a))
