class_name PrintCard
extends Control
## A print (misprints, data/prints.json) as a physical object: the hero's card printed on paper with
## its flaw (src/ui/shaders/misprint.gdshader), sealed in a clear acrylic grading slab. The slab's
## paper label carries the hero, the serial "No. 0412 / 5,000", the edition and printing and the
## grade (10 = Gem Mint, in signal for 9 and 10); a misprint gets a MISPRINT rubber stamp across the
## card, holo foil a HOLO FOIL sticker and a moving foil sheen, a print won from the Rival a RUE tag.
## The slab's gloss slides as the phone tilts (slab_gloss.gdshader).
##
##   var c := PrintCard.make(print_dict, Vector2(200, 300))        # compact below 190 px wide
##   c.set_flaw_amount(0.0)   # the reveal's flip: the clean print first, then the flaw
##
## Cosmetic only: nothing here changes the game.

const MISPRINT := preload("res://src/ui/shaders/misprint.gdshader")
const GLOSS := preload("res://src/ui/shaders/slab_gloss.gdshader")
const INK := Color("101113")
const PAPER := Color("e9e8e2")
const CARD := Color("f4f3ef")
const SIG := Color("ff4b1f")
## The swapped inks (sRGB): cyan, violet, acid green, gold.
const INK_COLORS := {"cyan": Color(0.0, 0.74, 0.86), "violet": Color(0.5, 0.26, 0.86), "acid": Color(0.6, 0.86, 0.04),
	"gold": Color(0.92, 0.66, 0.1)}
const FLAW_INDEX := {"": 0, "shift": 1, "swap": 2, "ghost": 3, "double": 4, "flood": 5}
const ORDINALS := ["", "1ST", "2ND", "3RD"]

var data: Dictionary = {}
var compact := false
var art: TextureRect
var mat: ShaderMaterial
var _gloss: ColorRect


## A print card of `sz` (slab included). opts: skin (the art look, default the base art), stamp
## (false hides the MISPRINT / HOLO marks), label (false: no slab label, the card fills the slab).
static func make(p: Dictionary, sz: Vector2, opts: Dictionary = {}) -> PrintCard:
	var c := PrintCard.new()
	c.data = p
	c.size = sz
	c.custom_minimum_size = sz
	c.compact = sz.x < 190.0
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c._build(opts)
	return c


## The misprint material for a hero art texture showing print `p` (also the summon reveal's flip).
## region: the art's region in its atlas (normalized); px: the misregistration in screen pixels.
static func material_for(p: Dictionary, region: Vector4 = Vector4(0, 0, 1, 1), px: float = 8.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = MISPRINT
	var flaw := str(p.get("flaw", ""))
	m.set_shader_parameter("flaw", int(FLAW_INDEX.get(flaw, 0)))
	var ink: Color = INK_COLORS.get(str(p.get("ink", "")), INK_COLORS.cyan)
	m.set_shader_parameter("ink", ink)
	m.set_shader_parameter("paper", CARD)
	var a := float(int(p.get("v", 0)) % 1000) / 1000.0 * TAU
	m.set_shader_parameter("dir", Vector2(cos(a), sin(a) * 0.6))
	m.set_shader_parameter("px", px)
	m.set_shader_parameter("holo", 1.0 if bool(p.get("holo", false)) else 0.0)
	m.set_shader_parameter("region", region)
	m.set_shader_parameter("seed", float(int(p.get("v", 0)) % 97))
	m.set_shader_parameter("motion", 1.0 if Kit.motion_ok() else 0.0)
	return m


## The region of an AtlasTexture in its atlas, normalized (the whole texture otherwise).
static func region_of(tex: Texture2D) -> Vector4:
	if tex is AtlasTexture and (tex as AtlasTexture).atlas:
		var at := tex as AtlasTexture
		var s := Vector2(at.atlas.get_size())
		return Vector4(at.region.position.x / s.x, at.region.position.y / s.y, at.region.size.x / s.x, at.region.size.y / s.y)
	return Vector4(0, 0, 1, 1)


## "No. 0412 / 5,000".
static func serial_line(p: Dictionary) -> String:
	return "No. %04d / %s" % [int(p.get("serial", 0)), Kit.format_full(int(p.get("run", 0)))]


## "ED.03 · 1ST PRINTING · STANDARD".
static func edition_line(p: Dictionary) -> String:
	var pr := int(p.get("printing", 1))
	var ord: String = ORDINALS[pr] if pr < ORDINALS.size() else "%dTH" % pr
	var b := EconomyData.banner_def(str(p.get("banner", "standard")))
	return "ED.%02d · %s PRINTING · %s" % [int(p.get("edition", 1)), ord, str(b.get("short", "Standard")).to_upper()]


## What makes the print special, in words ("Off register · Holo foil · Gem Mint 10").
static func flags_line(p: Dictionary) -> String:
	var parts: Array[String] = []
	var flaw := str(p.get("flaw", ""))
	if flaw != "":
		var fl := PrintRules.flaw_name(flaw)
		if flaw == "swap" and str(p.get("ink", "")) != "":
			fl += " (%s)" % PrintRules.ink_name(str(p.ink))
		parts.append(fl)
	if bool(p.get("holo", false)):
		parts.append("Holo foil")
	var g := int(p.get("grade", 0))
	if g >= 9:
		parts.append("%s %d" % [PrintRules.grade_name(g), g])
	if int(p.get("serial", 9999)) <= PrintRules.EARLY_SERIAL:
		parts.append("Early serial")
	if str(p.get("from", "")) == "rival":
		parts.append("Won from Rue")
	return " · ".join(parts)


func set_flaw_amount(k: float) -> void:
	if mat:
		mat.set_shader_parameter("amount", clampf(k, 0.0, 1.0))


func set_holo(k: float) -> void:
	if mat:
		mat.set_shader_parameter("holo", clampf(k, 0.0, 1.0))


# ------------------------------------------------------------------ build

func _build(opts: Dictionary) -> void:
	var w := size.x
	var h := size.y
	var m := maxf(6.0, roundf(w * 0.035))
	var with_label := bool(opts.get("label", true))
	var lh := maxf(36.0, roundf(h * (0.15 if compact else 0.165))) if with_label else 0.0
	# The acrylic body (behind everything) with its contact shadow.
	var body := Panel.new()
	body.name = "Slab"
	body.mouse_filter = MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.93, 0.94, 0.95, 0.62)
	sb.border_color = Color(1, 1, 1, 0.95)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(int(m * 1.4))
	sb.shadow_color = Color(0, 0, 0, 0.26)
	sb.shadow_size = int(maxf(6.0, w * 0.05))
	sb.shadow_offset = Vector2(0, maxf(3.0, w * 0.022))
	sb.anti_aliasing = true
	body.add_theme_stylebox_override("panel", sb)
	body.size = size
	add_child(body)
	# The well the card sits in (a hairline step in the acrylic).
	var well := Panel.new()
	well.mouse_filter = MOUSE_FILTER_IGNORE
	var ws := StyleBoxFlat.new()
	ws.bg_color = Color(0.86, 0.87, 0.88, 0.5)
	ws.border_color = Color(0, 0, 0, 0.1)
	ws.set_border_width_all(1)
	ws.set_corner_radius_all(int(m * 0.7))
	well.add_theme_stylebox_override("panel", ws)
	var top := m + lh + (m * 0.7 if with_label else 0.0)
	well.position = Vector2(m * 0.6, top - m * 0.4)
	well.size = Vector2(w - m * 1.2, h - top - m * 0.2)
	add_child(well)
	if with_label:
		_build_label(Rect2(m, m, w - 2.0 * m, lh))
	_build_card(Rect2(m + 2.0, top, w - 2.0 * m - 4.0, h - top - m), opts)
	# The acrylic's gloss over the whole slab.
	_gloss = ColorRect.new()
	_gloss.name = "Gloss"
	_gloss.mouse_filter = MOUSE_FILTER_IGNORE
	_gloss.size = size
	var gm := ShaderMaterial.new()
	gm.shader = GLOSS
	gm.set_shader_parameter("size", size)
	gm.set_shader_parameter("radius", m * 1.4)
	_gloss.material = gm
	add_child(_gloss)


## The paper label at the top of the slab: hero, serial, edition, the grade box.
func _build_label(r: Rect2) -> void:
	var p := data
	var lab := ColorRect.new()
	lab.name = "Label"
	lab.mouse_filter = MOUSE_FILTER_IGNORE
	lab.color = Color("f7f6f2")
	lab.position = r.position
	lab.size = r.size
	add_child(lab)
	var g := int(p.get("grade", 0))
	var top := g >= 9
	# The grade box on the right: number in compressed type, the grade's short name under it.
	var gw := clampf(r.size.y * 1.05, 34.0, 64.0)
	var gb := ColorRect.new()
	gb.mouse_filter = MOUSE_FILTER_IGNORE
	gb.color = SIG if top else INK
	gb.position = Vector2(r.size.x - gw, 0)
	gb.size = Vector2(gw, r.size.y)
	lab.add_child(gb)
	var gn := Kit.label(str(g), int(clampf(r.size.y * 0.7, 18.0, 44.0)), CARD, "compressed")
	gn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gn.size = Vector2(gw, r.size.y * 0.72)
	gn.position = Vector2(0, -2)
	gb.add_child(gn)
	var gname := PrintRules.grade_name(g).to_upper().replace("NEAR MINT", "NM").replace("EXCELLENT", "EX").replace("VERY GOOD", "VG")
	var gl := Kit.label(gname, 8 if compact else 9, Color(CARD, 0.92), "mono_bold")
	gl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gl.clip_text = true
	gl.size = Vector2(gw, 12)
	gl.position = Vector2(0, r.size.y - 13)
	gb.add_child(gl)
	var tw := r.size.x - gw - 10.0
	var d := HeroData.get_def(str(p.get("hero", "")))
	var nm := Kit.label(str(d.get("name", "?")).to_upper(), 13 if compact else 16, INK, "wide_black")
	Kit.fit_label(nm, tw, 13 if compact else 16, 9)
	nm.position = Vector2(6, 2 if compact else 3)
	lab.add_child(nm)
	var sl := Kit.label(("No. %04d" % int(p.get("serial", 0))) if compact else serial_line(p), 9 if compact else 11, SIG if int(p.get("serial", 9999)) <= PrintRules.EARLY_SERIAL else INK, "mono_bold")
	sl.clip_text = true
	sl.size = Vector2(tw, 14)
	sl.position = Vector2(6, r.size.y - (15 if compact else 30))
	lab.add_child(sl)
	if not compact:
		var etxt := edition_line(p)
		if Kit.font("mono").get_string_size(etxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x > tw:
			etxt = etxt.replace(" PRINTING", "")   # "ED.01 · 1ST · ENVOY" on a narrow slab
		var el := Kit.label(etxt, 8, Color(INK, 0.7), "mono")
		el.clip_text = true
		el.size = Vector2(tw, 12)
		el.position = Vector2(6, r.size.y - 15)
		lab.add_child(el)
	# A hairline under the label, like the cut of the insert.
	var rl := ColorRect.new()
	rl.mouse_filter = MOUSE_FILTER_IGNORE
	rl.color = Color(INK, 0.25)
	rl.position = Vector2(0, r.size.y - 1)
	rl.size = Vector2(r.size.x - gw, 1)
	lab.add_child(rl)


## The printed card: a white border, the art with its flaw, the name strip and the stamps.
func _build_card(r: Rect2, opts: Dictionary) -> void:
	var p := data
	var card := Control.new()
	card.name = "Card"
	card.mouse_filter = MOUSE_FILTER_IGNORE
	card.position = r.position
	card.size = r.size
	card.clip_contents = true
	add_child(card)
	var bg := ColorRect.new()
	bg.mouse_filter = MOUSE_FILTER_IGNORE
	bg.color = CARD
	bg.size = r.size
	card.add_child(bg)
	var b := maxf(4.0, roundf(r.size.x * 0.045))
	var foot := maxf(26.0, roundf(r.size.y * (0.15 if compact else 0.16)))
	var ar := Rect2(b, b, r.size.x - 2.0 * b, r.size.y - b - foot)
	var hid := str(p.get("hero", ""))
	var tex := Kit.art_crop(hid, ar.size.x / maxf(ar.size.y, 1.0), 1.0, str(opts.get("skin", "")))
	art = TextureRect.new()
	art.name = "Art"
	art.mouse_filter = MOUSE_FILTER_IGNORE
	art.texture = tex
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_SCALE
	art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	art.position = ar.position
	art.size = ar.size
	mat = material_for(p, region_of(tex), maxf(3.0, ar.size.x * 0.035))
	mat.set_shader_parameter("cell", clampf(ar.size.x / 48.0, 3.0, 6.0))
	art.material = mat
	card.add_child(art)
	# A hairline round the art (the printed frame).
	var fr := ReferenceRect.new()
	fr.mouse_filter = MOUSE_FILTER_IGNORE
	fr.border_color = Color(INK, 0.55)
	fr.border_width = 1.0
	fr.editor_only = false
	fr.position = ar.position
	fr.size = ar.size
	card.add_child(fr)
	# The foot: faction colour tick, the name in compressed type, rarity pips, the serial.
	var d := HeroData.get_def(hid)
	var fy := ar.end.y + 3.0
	var nm := Kit.label(str(d.get("name", hid)).to_upper(), int(clampf(foot * 0.62, 12.0, 34.0)), INK, "compressed")
	Kit.fit_label(nm, r.size.x * 0.62, int(clampf(foot * 0.62, 12.0, 34.0)), 10)
	nm.position = Vector2(b, fy - 2.0)
	card.add_child(nm)
	var rar := str(d.get("rarity", "rare"))
	var rl := Kit.label(str(Kit.RARITY_NAMES.get(rar, rar)).to_upper(), 7 if compact else 9, SIG if rar != "rare" else INK, "mono_bold")
	rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rl.size = Vector2(r.size.x * 0.4 - b, 12)
	rl.position = Vector2(r.size.x * 0.6, fy + 1.0)
	card.add_child(rl)
	var sn := Kit.label("%04d" % int(p.get("serial", 0)), 7 if compact else 9, Color(INK, 0.75), "mono")
	sn.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sn.size = Vector2(r.size.x * 0.4 - b, 12)
	sn.position = Vector2(r.size.x * 0.6, fy + (11.0 if compact else 14.0))
	card.add_child(sn)
	if not bool(opts.get("stamp", true)):
		return
	var flaw := str(p.get("flaw", ""))
	if flaw != "":
		var st := Stamp.new()
		st.text = "MISPRINT"
		st.sub = PrintRules.flaw_name(flaw).to_upper()
		st.color = SIG
		var sw := r.size.x * 0.86
		st.size = Vector2(sw, sw * 0.3)
		st.position = Vector2((r.size.x - sw) * 0.5, ar.end.y - sw * 0.42)
		st.pivot_offset = st.size * 0.5
		st.rotation = -0.2
		st.name = "MisprintStamp"
		card.add_child(st)
	if bool(p.get("holo", false)):
		var hs := HoloSticker.new()
		var d2 := clampf(r.size.x * 0.3, 30.0, 92.0)
		hs.size = Vector2(d2, d2)
		hs.position = Vector2(r.size.x - d2 - b * 0.6, b * 0.6)
		hs.name = "HoloSticker"
		card.add_child(hs)
	if str(p.get("from", "")) == "rival":
		var tag := Kit.label(" RUE ", 9 if compact else 11, CARD, "wide_black")
		var tb := ColorRect.new()
		tb.mouse_filter = MOUSE_FILTER_IGNORE
		tb.color = INK
		tb.size = tag.get_minimum_size() + Vector2(4, 0)
		tb.position = Vector2(b + 4, b + 4)
		tb.rotation = -0.06
		tb.add_child(tag)
		card.add_child(tb)


## A rubber stamp: a double-ruled box, the word in wide black, a small sub line, ink that missed in
## places (a seeded speckle), so it reads as stamped by hand.
class Stamp:
	extends Control
	var text := "MISPRINT"
	var sub := ""
	var color := Color("ff4b1f")
	var seed_v := 7

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := Color(color, 0.92)
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, c, false, maxf(2.0, size.y * 0.06))
		draw_rect(r.grow(-maxf(4.0, size.y * 0.11)), c, false, maxf(1.0, size.y * 0.025))
		var f := Kit.font("wide_black")
		var fs := int(size.y * (0.4 if sub != "" else 0.55))
		var tw := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		while fs > 6 and tw > size.x * 0.86:
			fs -= 1
			tw = f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var ty := size.y * (0.56 if sub != "" else 0.68)
		draw_string(f, Vector2((size.x - tw) * 0.5, ty), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, c)
		if sub != "":
			var fm := Kit.font("mono_bold")
			var ss := maxi(6, int(size.y * 0.15))
			var sw := fm.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, ss).x
			draw_string(fm, Vector2((size.x - sw) * 0.5, size.y * 0.84), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, ss, c)
		# Where the ink missed: paper-coloured specks (a stamp is never perfectly inked).
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_v
		var paper := Color("f4f3ef")
		for i in int(size.x * size.y / 95.0):
			var pt := Vector2(rng.randf() * size.x, rng.randf() * size.y)
			draw_circle(pt, rng.randf_range(0.4, 1.3), Color(paper, rng.randf_range(0.5, 0.95)))


## A round holographic sticker: a rainbow ring that turns with time, HOLO FOIL in the middle.
class HoloSticker:
	extends Control
	var _t := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		if not Kit.motion_ok():
			return
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var rad := minf(size.x, size.y) * 0.5
		draw_circle(c + Vector2(1, 2), rad, Color(0, 0, 0, 0.22))
		var n := 48
		for i in n:
			var a0 := TAU * i / n
			var a1 := TAU * (i + 1) / n
			var hue := fmod(float(i) / n + _t * 0.08, 1.0)
			var col := Color.from_hsv(hue, 0.45, 1.0)
			draw_colored_polygon(PackedVector2Array([c, c + Vector2(cos(a0), sin(a0)) * rad, c + Vector2(cos(a1), sin(a1)) * rad]), col)
		draw_circle(c, rad * 0.62, Color("f4f3ef"))
		draw_arc(c, rad * 0.62, 0, TAU, 48, Color(1, 1, 1, 0.9), 1.0, true)
		draw_arc(c, rad - 0.5, 0, TAU, 48, Color(1, 1, 1, 0.8), 1.0, true)
		var f := Kit.font("wide_black")
		var fs := maxi(6, int(rad * 0.36))
		var w1 := f.get_string_size("HOLO", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(f, c + Vector2(-w1 * 0.5, -1), "HOLO", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("101113"))
		var fm := Kit.font("mono_bold")
		var fs2 := maxi(5, int(rad * 0.22))
		var w2 := fm.get_string_size("FOIL", HORIZONTAL_ALIGNMENT_LEFT, -1, fs2).x
		draw_string(fm, c + Vector2(-w2 * 0.5, fs2 + 1), "FOIL", HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, Color("101113"))
