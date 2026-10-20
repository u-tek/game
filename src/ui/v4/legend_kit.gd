class_name LegendKit
extends RefCounted
## Legendary pieces for the style v4 poster screens (owner, 2026-10-20: "the legendary heroes get
## different power ups, and their pages look more built out and more powerful. and cooler. with
## exclusive features"). A Legendary's dossier (hero_detail_screen.gd) is printed with hot-stamped
## gold holo foil; her awakening (Game.awaken, docs/dev/unity-port.md 8.6) lights sigil seals.
##
##   foil_material(mode, palette)    the legend_foil shader: 0 foil (type, shapes), 1 frame, 2 sheen
##   foil_label(text, size, weight)  type stamped in gold foil
##   foil_rect(parent, rect, mode)   a foil frame round a poster, or a sheen over a dark band
##   aura(size, strength)            a soft gold glow behind a hero (no bloom needed)
##   Seal                            a sigil seal for one awakening tier: debossed when locked, gold
##                                   foil when lit, a breathing signal ring on the next one
##   CrownStamp                      the Ascended rubber stamp (crown, rim text), inked signal red
##   awaken_mark(tier, size)         the small A1 / A2 / A3 foil seal on a roster card
##   AwakenFx                        the awakening moment over the whole screen: print plates slam
##                                   shut, foil sweeps, a flash, her faction's growth surges in, the
##                                   seal stamps on (Reduce motion: the final frame, still)

const FOIL := preload("res://src/ui/shaders/legend_foil.gdshader")
const RAYS := preload("res://src/ui/components/rays.gd")
const PK := preload("res://src/ui/v4/hero_poster_kit.gd")

const INK := Color("101113")
const PAPER := Color("e9e8e2")
const SIG := Color("ff4b1f")
const GOLD := Color("d9a441")
const GOLD_HI := Color("ffe2a0")
const GOLD_DEEP := Color("7a5212")
## Gold halftone ink for a Legendary's dark bands (the red print, in gold).
const GOLD_PRINT := Color(1.0, 0.82, 0.44, 0.95)
## Dark felt stock of the legend sheet.
const FELT := Color("17181b")
## What each awakening tier unlocks (A1, A2, A3).
const UNLOCKS: Array[String] = ["LEGEND PASSIVE", "EMPOWERED ULTIMATE", "ASCENDED"]
## Foil palettes (sRGB): dark, mid, light. "deep" is gold that reads on light paper.
const PALETTES := {
	"gold": [Color(0.40, 0.26, 0.07), Color(0.87, 0.67, 0.29), Color(1.0, 0.95, 0.74)],
	"deep": [Color(0.42, 0.27, 0.05), Color(0.74, 0.52, 0.15), Color(0.98, 0.85, 0.50)],
	"pale": [Color(0.55, 0.42, 0.18), Color(0.90, 0.76, 0.42), Color(1.0, 0.97, 0.84)],
	# Dark metallic gold, for big type on light paper.
	"ink": [Color(0.20, 0.12, 0.02), Color(0.47, 0.30, 0.06), Color(0.80, 0.60, 0.24)],
}


static func is_legend(def: Dictionary) -> bool:
	return str(def.get("rarity", "")) == "legendary" and not (def.get("legend", {}) as Dictionary).is_empty()


## "+12%" for an awakening tier's total stat bonus.
static func bonus_text(tier: int) -> String:
	return "+%d%%" % (Progression.awaken_stat_bp(tier) / 100)


static func foil_material(mode: int = 0, palette: String = "gold", opts: Dictionary = {}) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = FOIL
	var pal: Array = PALETTES.get(palette, PALETTES["gold"])
	m.set_shader_parameter("mode", mode)
	m.set_shader_parameter("dark", pal[0])
	m.set_shader_parameter("mid", pal[1])
	m.set_shader_parameter("light", pal[2])
	m.set_shader_parameter("drift", 1.0 if Kit.motion_ok() else 0.0)
	for k: String in opts:
		m.set_shader_parameter(k, opts[k])
	return m


## Type stamped in foil (a Label whose glyphs are painted by the foil shader).
static func foil_label(text: String, size: int, weight: String = "compressed", palette: String = "gold", opts: Dictionary = {}) -> Label:
	var l := Kit.label(text, size, Color.WHITE, weight)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var o := {"band_px": maxf(size * 3.0, 120.0), "seed": float(text.hash() % 97)}
	o.merge(opts, true)
	l.material = foil_material(0, palette, o)
	return l


## A foil frame (mode 1) round `r` or a sheen (mode 2) over it, in `parent`.
static func foil_rect(parent: Node, r: Rect2, mode: int, opts: Dictionary = {}, palette: String = "gold") -> ColorRect:
	var c := ColorRect.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.color = Color.WHITE
	c.position = r.position
	c.size = r.size
	var o := {"rect_size": r.size}
	o.merge(opts, true)
	c.material = foil_material(mode, palette, o)
	parent.add_child(c)
	return c


static var _aura_tex: GradientTexture2D


## A soft round gold glow, `size` across (alpha `strength`), for behind a hero's figure.
static func aura(size: Vector2, strength: float = 0.5, color: Color = Color(1.0, 0.80, 0.38)) -> TextureRect:
	if _aura_tex == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.35, 0.7, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0.14), Color(1, 1, 1, 0)])
		_aura_tex = GradientTexture2D.new()
		_aura_tex.gradient = g
		_aura_tex.fill = GradientTexture2D.FILL_RADIAL
		_aura_tex.fill_from = Vector2(0.5, 0.5)
		_aura_tex.fill_to = Vector2(0.5, 0.0)
		_aura_tex.width = 256
		_aura_tex.height = 256
	var t := TextureRect.new()
	t.name = "Aura"
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.texture = _aura_tex
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.size = size
	t.modulate = Color(color.r, color.g, color.b, strength)
	return t


## Slowly turning gold rays (still under Reduce motion), `side` px square.
static func rays(side: float, alpha: float = 0.22) -> Control:
	var r: Control = RAYS.new()
	r.name = "Rays"
	r.size = Vector2(side, side)
	r.set("color", Color(1.0, 0.82, 0.42, alpha))
	r.set("ray_count", 18)
	r.set("speed", 0.06 if Kit.motion_ok() else 0.0)
	return r


static func seal(tier: int, state: String, side: float) -> Seal:
	var s := Seal.new()
	s.tier = tier
	s.state = state
	s.size = Vector2(side, side)
	s.custom_minimum_size = s.size
	return s


## The small foil seal on a roster card ("A2"), `side` px.
static func awaken_mark(tier: int, side: float = 40.0) -> Control:
	var s := seal(tier, "lit", side)
	s.mini = true
	s.name = "AwakenMark"
	return s


# ------------------------------------------------------------------ seal

## A sigil seal for awakening tier `tier` (1-3). state: "locked" (debossed into dark felt), "next"
## (debossed, a breathing signal ring: the one you can awaken now), "lit" (gold foil, engraved).
## mini: just "A<tier>" in the middle (roster cards).
class Seal:
	extends Control
	var tier := 1
	var state := "locked"
	var mini := false
	## 0..1 extra impact ring (the awakening animation stamps it on).
	var impact := 0.0
	var _disc: Control
	var _eng: Control
	var _t := 0.0

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE

	func _ready() -> void:
		_build()
		set_process(state == "next" and Kit.motion_ok())

	func set_state(s: String) -> void:
		state = s
		if is_inside_tree():
			for c in get_children():
				remove_child(c)
				c.queue_free()
			_build()
			set_process(state == "next" and Kit.motion_ok())

	func _build() -> void:
		var lit := state == "lit"
		if lit:
			_disc = _Shape.new()
			_disc.size = size
			_disc.material = LegendKit.foil_material(0, "gold", {"band_px": maxf(size.x * 1.6, 60.0)})
			add_child(_disc)
		_eng = _Engrave.new()
		_eng.size = size
		_eng.set_meta("seal", self)
		add_child(_eng)

	## Redraw the engraving (impact ring, pulse).
	func refresh() -> void:
		if _eng:
			_eng.queue_redraw()

	func _process(delta: float) -> void:
		_t += delta
		if _eng:
			_eng.queue_redraw()

	func pulse_t() -> float:
		return _t


## The seal's scalloped disc (filled; the foil paints it).
class _Shape:
	extends Control

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		draw_colored_polygon(_scallop(c, r * 0.97, r * 0.06, 28), Color.WHITE)

	static func _scallop(c: Vector2, r: float, bump: float, n: int) -> PackedVector2Array:
		var pts := PackedVector2Array()
		var steps := n * 6
		for i in steps:
			var a := TAU * i / steps
			var rr := r - bump + bump * absf(sin(a * n * 0.5))
			pts.append(c + Vector2(cos(a), sin(a)) * rr)
		return pts


## The seal's engraving: rings, a star sigil, the numeral and rim text (or the locked deboss).
class _Engrave:
	extends Control

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var s: Variant = get_meta("seal", null)
		if s == null:
			return
		var tier: int = s.tier
		var state: String = s.state
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		var lit := state == "lit"
		var ink := Color(0.20, 0.11, 0.02, 0.88) if lit else Color(0.913, 0.91, 0.886, 0.30)
		var shade := Color(0, 0, 0, 0.55)
		if s.mini:
			var f := Kit.font("wide_black")
			var fs := int(r * 0.78)
			var txt := "A%d" % tier
			var w := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_arc(c, r * 0.74, 0, TAU, 40, ink, maxf(1.0, r * 0.06), true)
			draw_string(f, c + Vector2(-w * 0.5, fs * 0.36), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)
			return
		if not lit:
			# Debossed into the felt: a shadowed wall above, a pale lip below.
			var outline := _Shape._scallop(c + Vector2(0, -1), r * 0.97, r * 0.06, 28)
			outline.append(outline[0])
			draw_polyline(outline, shade, 2.0, true)
			var outline2 := _Shape._scallop(c + Vector2(0, 1), r * 0.97, r * 0.06, 28)
			outline2.append(outline2[0])
			draw_polyline(outline2, Color(1, 1, 1, 0.10), 1.5, true)
			draw_circle(c, r * 0.9, Color(0, 0, 0, 0.18))
		draw_arc(c, r * 0.80, 0, TAU, 72, ink, maxf(1.2, r * 0.025), true)
		draw_arc(c, r * 0.72, 0, TAU, 72, ink, maxf(1.0, r * 0.012), true)
		# The sigil: an eight-pointed star behind the numeral (a halo-and-horn burst).
		var pts := PackedVector2Array()
		for k in 16:
			var a := -PI * 0.5 + k * PI / 8.0
			var rr := r * (0.62 if k % 2 == 0 else 0.30)
			pts.append(c + Vector2(cos(a), sin(a)) * rr)
		pts.append(pts[0])
		draw_polyline(pts, Color(ink, ink.a * 0.65), maxf(1.0, r * 0.015), true)
		var f2 := Kit.font("wide_black")
		var fs2 := int(r * 0.52)
		var num := Kit.roman(tier)
		var w2 := f2.get_string_size(num, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2).x
		if lit:
			draw_string(f2, c + Vector2(-w2 * 0.5, fs2 * 0.36 + 1.0), num, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, Color(1, 0.95, 0.8, 0.5))
		draw_string(f2, c + Vector2(-w2 * 0.5, fs2 * 0.36), num, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, ink)
		# Rim text.
		var rim := "AWAKENING · %s · HALO & HORN · " % Kit.roman(tier)
		var fm := Kit.font("mono_bold")
		var fsz := clampi(int(r * 0.11), 8, 14)
		for i in rim.length():
			var a2 := -PI * 0.5 + TAU * i / rim.length()
			var pos := c + Vector2(cos(a2), sin(a2)) * (r * 0.86)
			draw_set_transform(pos, a2 + PI * 0.5, Vector2.ONE)
			draw_char(fm, Vector2(-fsz * 0.3, fsz * 0.38), rim[i], fsz, ink)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		if state == "next":
			var k2: float = 0.5 + 0.5 * sin(float(s.pulse_t()) * TAU / 1.6)
			var col := Color(SIG_C.r, SIG_C.g, SIG_C.b, 0.45 + 0.5 * k2)
			var n := 36
			for i in n:
				if i % 2 == 0:
					var a3 := TAU * i / n + float(s.pulse_t()) * 0.25
					draw_arc(c, r * 1.02, a3, a3 + TAU / n, 4, col, maxf(2.0, r * 0.035), true)
		if float(s.impact) > 0.0:
			var k3: float = s.impact
			draw_arc(c, r * (1.0 + 0.9 * (1.0 - k3)), 0, TAU, 64, Color(1.0, 0.85, 0.5, k3 * 0.8), 2.0 + 10.0 * k3, true)

	const SIG_C := Color("ff4b1f")


# ------------------------------------------------------------------ crown stamp

## The Ascended stamp: a rubber stamp inked in signal (crown in the middle, rim text, rough ink).
class CrownStamp:
	extends Control
	var label := "ASCENDED · "
	var ink := Color(1.0, 0.29, 0.12, 0.88)

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		draw_arc(c, r - 3.0, 0, TAU, 80, ink, 4.0, true)
		draw_arc(c, r * 0.68, 0, TAU, 80, ink, 2.0, true)
		# The crown: five points on a band.
		var w := r * 0.82
		var h := r * 0.52
		var base := c + Vector2(-w * 0.5, h * 0.42)
		var pts := PackedVector2Array([
			base, base + Vector2(0, -h * 0.62), base + Vector2(w * 0.18, -h * 0.3), base + Vector2(w * 0.32, -h * 0.92),
			base + Vector2(w * 0.5, -h * 0.4), base + Vector2(w * 0.68, -h * 0.92), base + Vector2(w * 0.82, -h * 0.3),
			base + Vector2(w, -h * 0.62), base + Vector2(w, 0)])
		draw_colored_polygon(pts, ink)
		draw_rect(Rect2(base + Vector2(0, h * 0.1), Vector2(w, h * 0.16)), ink)
		for k in [0.0, 0.32, 0.68, 1.0]:
			var tip := base + Vector2(w * float(k), -h * (0.62 if k == 0.0 or k == 1.0 else 0.92) - r * 0.05)
			draw_circle(tip, r * 0.045, ink)
		# Rim text.
		var fm := Kit.font("mono_bold")
		var fsz := clampi(int(r * 0.17), 9, 16)
		for i in label.length():
			var a := -PI * 0.5 + TAU * i / label.length()
			var pos := c + Vector2(cos(a), sin(a)) * (r * 0.84)
			draw_set_transform(pos, a + PI * 0.5, Vector2.ONE)
			draw_char(fm, Vector2(-fsz * 0.3, fsz * 0.38), label[i], fsz, ink)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		# Worn rubber: a few paper-coloured nicks.
		var rng := RandomNumberGenerator.new()
		rng.seed = 7331
		for i in 26:
			var a2 := rng.randf() * TAU
			var rr := r * rng.randf_range(0.3, 1.0)
			draw_circle(c + Vector2(cos(a2), sin(a2)) * rr, rng.randf_range(0.8, 2.4), Color(0.913, 0.91, 0.886, 0.85))


# ------------------------------------------------------------------ the awakening moment

## The awakening over the whole screen (add it to a full-window layer; it frees itself). Timeline:
## 0-0.3 s two print plates slam shut ("AWAKENING" across the seam in foil), a foil glint sweeps
## them, 0.82 s a paper-white flash as they fly apart on her, gold aura and rays, her faction's
## growth surging in from the corners; 1.35-1.55 s the tier's seal drops and stamps on; then the
## unlock in type; 3.6 s it fades. Tap after 0.6 s to skip to the end. `midpoint` is called under the
## flash (the page rebuilds there); `finished` when it is gone. Reduce motion: the last frame, still.
class AwakenFx:
	extends Control
	signal finished
	var hero_id := ""
	var skin := ""
	var faction := "celestial"
	var tier := 1
	var name_text := ""
	var title_text := ""
	var unlock_name := ""
	var midpoint := Callable()

	const T_SLAM := 0.30
	const T_FLASH := 0.82
	const T_SEAL := 1.55
	const T_OUT := 3.6
	const T_END := 3.95

	var _t := 0.0
	var _mid_done := false
	var _motion := true
	var _vs := Vector2(720, 1280)
	var _content: Control
	var _back: ColorRect
	var _top: Control
	var _bot: Control
	var _top_sheen: ColorRect
	var _bot_sheen: ColorRect
	var _stage: Control
	var _hero: TextureRect
	var _aura: Control
	var _rays: Control
	var _growth: Array[Control] = []
	var _seal: Control
	var _texts: Array[Control] = []
	var _flash: ColorRect
	var _shake := 0.0
	var _played := {}

	func _ready() -> void:
		set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		mouse_filter = MOUSE_FILTER_STOP
		_motion = Kit.motion_ok()
		_vs = get_viewport_rect().size
		_build()
		if not _motion:
			# Reduce motion: the last frame, still (it fades out at the end like any popup).
			_t = T_SEAL + 0.9
			_fire_mid()
		_apply()

	func _build() -> void:
		var vs := _vs
		_back = ColorRect.new()
		_back.color = INK
		_back.mouse_filter = MOUSE_FILTER_IGNORE
		_back.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		add_child(_back)
		_content = Control.new()
		_content.mouse_filter = MOUSE_FILTER_IGNORE
		_content.size = vs
		add_child(_content)
		# ---- The stage: felt, the aura and rays, her art, the growth, the seal and the type.
		_stage = Control.new()
		_stage.mouse_filter = MOUSE_FILTER_IGNORE
		_stage.size = vs
		_content.add_child(_stage)
		var feel := ColorRect.new()
		feel.color = Color("121316")
		feel.mouse_filter = MOUSE_FILTER_IGNORE
		feel.size = vs
		_stage.add_child(feel)
		var hero_h := vs.y * 0.56
		var feet_y := vs.y * 0.76
		var ar := LegendKit.aura(Vector2(vs.x * 1.3, vs.x * 1.3), 0.55)
		ar.position = Vector2(vs.x * 0.5, feet_y - hero_h * 0.55) - ar.size * 0.5
		_stage.add_child(ar)
		_aura = ar
		_rays = LegendKit.rays(vs.x * 1.6, 0.2)
		_rays.position = Vector2(vs.x * 0.5, feet_y - hero_h * 0.55) - _rays.size * 0.5
		_stage.add_child(_rays)
		var tex := HeroArt.texture(hero_id, skin)
		_hero = TextureRect.new()
		_hero.mouse_filter = MOUSE_FILTER_IGNORE
		_hero.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_hero.stretch_mode = TextureRect.STRETCH_SCALE
		if tex:
			var ur := HeroArt.used_rect(tex)
			var at := AtlasTexture.new()
			at.atlas = tex
			at.region = ur
			_hero.texture = at
			var k := hero_h / maxf(ur.size.y, 1.0)
			k = minf(k, vs.x * 0.92 / maxf(ur.size.x, 1.0))
			_hero.size = ur.size * k
		else:
			_hero.size = Vector2(hero_h * 0.5, hero_h)
		_hero.position = Vector2(vs.x * 0.5 - _hero.size.x * 0.5, feet_y - _hero.size.y)
		_hero.pivot_offset = Vector2(_hero.size.x * 0.5, _hero.size.y)
		_stage.add_child(_hero)
		# Her faction's growth, one piece per corner (each turns on its corner as it surges in).
		var ppu := clampf(vs.x / 8.6, 60.0, 110.0)
		var corners := [["tl", Vector2(0, 0)], ["tr", Vector2(vs.x, 0)], ["br", Vector2(vs.x, vs.y)], ["bl", Vector2(0, vs.y)]]
		for cn: Array in corners:
			var g := PhysicalKit.growth(faction, str(cn[0]), _stage, cn[1] as Vector2, ppu)
			if g:
				_growth.append(g)
		# Top masthead: LEGEND · NAME, her legend title in foil.
		var kick := Kit.label("LEGEND  ·  %s  ·  AWAKENING %s" % [name_text.to_upper(), Kit.roman(tier)], 14, Color(PAPER, 0.8), "mono_bold")
		kick.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		kick.size = Vector2(vs.x, 20)
		kick.position = Vector2(0, maxf(UI.safe_top(), 24.0) + 30.0)
		_stage.add_child(kick)
		var tl := LegendKit.foil_label(title_text.to_upper(), 46, "compressed")
		tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tl.size = Vector2(vs.x - 40, 60)
		tl.position = Vector2(20, kick.position.y + 24)
		_stage.add_child(tl)
		_texts.append(kick)
		_texts.append(tl)
		# The seal and the unlock.
		var side := minf(vs.x * 0.36, 280.0)
		_seal = LegendKit.seal(tier, "lit", side)
		_seal.position = Vector2(vs.x * 0.5 - side * 0.5, feet_y - side * 0.42)
		_seal.pivot_offset = Vector2(side, side) * 0.5
		_stage.add_child(_seal)
		var big := LegendKit.foil_label("AWAKENED", 92, "compressed")
		big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		big.size = Vector2(vs.x, 100)
		big.position = Vector2(0, _seal.position.y + side + 2)
		_stage.add_child(big)
		var un := Kit.label("%s  //  %s" % [LegendKit.UNLOCKS[clampi(tier - 1, 0, 2)], unlock_name.to_upper()], 15, PAPER, "mono_bold")
		un.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		un.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		un.size = Vector2(vs.x - 60, 20)
		un.position = Vector2(30, big.position.y + 100)
		_stage.add_child(un)
		var st := Kit.label("%s ALL STATS  ·  A%d OF 3" % [LegendKit.bonus_text(tier), tier], 13, Color(1.0, 0.82, 0.45), "mono_bold")
		st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		st.size = Vector2(vs.x, 18)
		st.position = Vector2(0, un.position.y + un.get_minimum_size().y + 8)
		_stage.add_child(st)
		_texts.append_array([big, un, st])
		for c in _texts:
			c.set_meta("y0", c.position.y)
		# ---- The plates (over the stage until they part).
		_top = _plate(true)
		_bot = _plate(false)
		# ---- The flash.
		_flash = ColorRect.new()
		_flash.color = Color(0.98, 0.97, 0.94, 0.0)
		_flash.mouse_filter = MOUSE_FILTER_IGNORE
		_flash.size = vs
		_content.add_child(_flash)

	## One print plate (half the screen and a little more): a dark band, her gold halftone print, a
	## foil frame, and half of "AWAKENING" (the word is set across the seam).
	func _plate(top: bool) -> Control:
		var vs := _vs
		var h := vs.y * 0.5 + 24.0
		var p := Control.new()
		p.mouse_filter = MOUSE_FILTER_IGNORE
		p.clip_contents = true
		p.size = Vector2(vs.x, h)
		_content.add_child(p)
		var band := ColorRect.new()
		band.color = Color("141517")
		band.mouse_filter = MOUSE_FILTER_IGNORE
		band.size = p.size
		p.add_child(band)
		var ht := PK.halftone_print(hero_id, skin, Vector2(vs.x, vs.y), 8.0, Color(LegendKit.GOLD_PRINT, 0.42), 0.9)
		ht.position = Vector2(0, 0 if top else -(vs.y * 0.5 - 24.0))
		p.add_child(ht)
		var fr := LegendKit.foil_rect(p, Rect2(Vector2(0, -20 if not top else 0), Vector2(vs.x, h + 20)), 1, {"inset": 16.0, "frame_w": 4.0})
		fr.name = "Frame"
		# The word, centred on the seam (y = vs.y / 2), on an ink strip with foil rules, drawn in each
		# plate's own coordinates.
		var fs := 160
		var word := LegendKit.foil_label("AWAKENING", fs, "compressed")
		word.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		var f := Kit.font("compressed")
		var tw := PK.text_w("AWAKENING", fs)
		var k := minf(1.0, (vs.x - 50.0) / maxf(tw, 1.0))
		word.scale = Vector2(k, k)
		word.size = Vector2(tw, f.get_height(fs))
		# Caps centred on the seam: the baseline sits at the label's top + ascent.
		var cap := fs * 0.72
		var oy := 0.0 if top else vs.y * 0.5 - 24.0
		var strip_h := cap * k + 44.0
		var strip := ColorRect.new()
		strip.color = Color(0.03, 0.03, 0.035, 0.92)
		strip.mouse_filter = MOUSE_FILTER_IGNORE
		strip.position = Vector2(0, vs.y * 0.5 - strip_h * 0.5 - oy)
		strip.size = Vector2(vs.x, strip_h)
		p.add_child(strip)
		for e in [-1.0, 1.0]:
			LegendKit.foil_rect(p, Rect2(0, vs.y * 0.5 + e * (strip_h * 0.5 + 3.0) - 1.5 - oy, vs.x, 3.0), 0, {"band_px": 300.0})
		word.position = Vector2(vs.x * 0.5 - tw * k * 0.5, vs.y * 0.5 - k * (f.get_ascent(fs) - cap * 0.5) - oy)
		p.add_child(word)
		var sh := LegendKit.foil_rect(p, Rect2(Vector2.ZERO, p.size), 2, {"strength": 0.0, "band_px": 420.0})
		if top:
			_top_sheen = sh
		else:
			_bot_sheen = sh
		var mark := Kit.label("HALO & HORN  ·  LEGEND FILE  ·  %s" % name_text.to_upper(), 12, Color(PAPER, 0.6), "mono_bold")
		mark.position = Vector2(34, 34) if top else Vector2(34, h - 52)
		p.add_child(mark)
		return p

	func _gui_input(ev: InputEvent) -> void:
		var mb := ev as InputEventMouseButton
		if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			if _t < 0.6:
				return
			if _t < T_OUT - 0.4:
				_fire_mid()
				_t = T_OUT - 0.4
				_apply()

	## Jump the timeline (shots of a moment).
	func seek(t: float) -> void:
		_t = t
		if _t >= T_FLASH:
			_fire_mid()
		_apply()

	func _fire_mid() -> void:
		if _mid_done:
			return
		_mid_done = true
		if midpoint.is_valid():
			midpoint.call()

	func _process(delta: float) -> void:
		_t += delta
		if _motion:
			_cue(0.02, "riser", 0)
			_cue(T_SLAM, "slam", 30)
			_cue(T_FLASH, "burst", 20)
			_cue(T_SEAL, "legendary", 45)
		if _t >= T_FLASH:
			_fire_mid()
		if _t >= T_END:
			finished.emit()
			queue_free()
			return
		_apply()

	func _cue(at: float, sound: String, haptic_ms: int) -> void:
		if _t >= at and not _played.has(sound):
			_played[sound] = true
			Kit.sfx(sound)
			if haptic_ms > 0:
				Kit.haptic(haptic_ms)
			if sound == "slam" or sound == "legendary":
				_shake = 1.0

	static func _ease_out(x: float) -> float:
		var k := clampf(x, 0.0, 1.0)
		return 1.0 - pow(1.0 - k, 3.0)

	static func _back_out(x: float) -> float:
		var k := clampf(x, 0.0, 1.0)
		var c1 := 1.70158
		return 1.0 + (c1 + 1.0) * pow(k - 1.0, 3.0) + c1 * pow(k - 1.0, 2.0)

	func _apply() -> void:
		var vs := _vs
		var t := _t
		var h := vs.y * 0.5 + 24.0
		# Backdrop and fade out.
		var fade := 1.0 - clampf((t - T_OUT) / (T_END - T_OUT), 0.0, 1.0)
		modulate.a = fade
		_back.color.a = clampf(t / 0.18, 0.0, 1.0) * 0.94
		# Plates: slam shut (accelerating), hold, fly apart at the flash.
		var close := clampf(t / T_SLAM, 0.0, 1.0)
		close = close * close
		var part := _ease_out((t - T_FLASH) / 0.42)
		var top_y := lerpf(-h, 0.0, close) - part * (h + 40.0)
		var bot_y := lerpf(vs.y, vs.y - h, close) + part * (h + 40.0)
		_top.position = Vector2(0, top_y)
		_bot.position = Vector2(0, bot_y)
		var plates_on := t < T_FLASH + 0.45
		_top.visible = plates_on
		_bot.visible = plates_on
		# The foil glint sweeping the closed plates.
		var sweep := clampf((t - T_SLAM) / (T_FLASH - T_SLAM), 0.0, 1.0)
		for sh: ColorRect in [_top_sheen, _bot_sheen]:
			var m := sh.material as ShaderMaterial
			m.set_shader_parameter("strength", sin(sweep * PI) * 1.6)
			m.set_shader_parameter("shift", sweep * 2.2 - 0.6)
		# The flash.
		var fl := 0.0
		if t >= T_FLASH:
			fl = 1.0 - _ease_out((t - T_FLASH) / 0.5)
		elif t >= T_FLASH - 0.06:
			fl = (t - (T_FLASH - 0.06)) / 0.06
		_flash.color.a = clampf(fl, 0.0, 1.0) if _motion else 0.0
		# The stage under the plates.
		_stage.visible = t >= T_FLASH - 0.06
		var rise := _ease_out((t - T_FLASH) / 0.6)
		_hero.scale = Vector2.ONE * lerpf(0.9, 1.0, rise)
		_aura.modulate.a = 0.55 * rise + 0.15 * sin(t * 3.0) * rise
		_rays.modulate.a = rise
		for i in _growth.size():
			var g := _growth[i]
			var k := _back_out((t - T_FLASH - 0.05 - i * 0.07) / 0.55)
			var k0 := clampf((t - T_FLASH - 0.05 - i * 0.07) / 0.55, 0.0, 1.0)
			g.scale = Vector2.ONE * maxf(0.001, lerpf(0.15, 1.0, k))
			g.rotation = lerpf(-0.45 if i % 2 == 0 else 0.45, 0.0, _ease_out(k0))
			g.modulate.a = clampf(k0 * 3.0, 0.0, 1.0)
		# The seal drops from above the glass and stamps on.
		var sd := clampf((t - (T_SEAL - 0.2)) / 0.2, 0.0, 1.0)
		_seal.visible = t >= T_SEAL - 0.2
		_seal.scale = Vector2.ONE * lerpf(2.8, 1.0, sd * sd)
		_seal.modulate.a = clampf(sd * 2.0, 0.0, 1.0)
		_seal.set("impact", clampf(1.0 - (t - T_SEAL) / 0.45, 0.0, 1.0) if t >= T_SEAL else 0.0)
		_seal.call("refresh")
		# The type: the masthead with the stage, the rest after the seal lands.
		for i in _texts.size():
			var c := _texts[i]
			var at := T_FLASH + 0.2 if i < 2 else T_SEAL + 0.08 + (i - 2) * 0.12
			var k2 := _ease_out((t - at) / 0.3)
			c.modulate.a = k2
			c.position.y = float(c.get_meta("y0", c.position.y)) + (1.0 - k2) * 18.0
		# Impact shake.
		if _shake > 0.0 and _motion:
			_content.position = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 14.0 * _shake
			_shake = maxf(0.0, _shake - get_process_delta_time() * 4.0)
		else:
			_content.position = Vector2.ZERO
