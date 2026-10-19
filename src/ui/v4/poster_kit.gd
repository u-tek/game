extends RefCounted
## Style v4 "Signal" poster pieces for the Summon, Shop and Gear screens: the look of the approved
## Lobby poster (lobby_v5_screen.gd, docs/dev/ui-style-v4.md) in reusable parts. A paper matte, printed
## poster panels with a soft shadow, dark bands carrying a red halftone print of a hero, giant
## compressed type turned on its side and two-tone where it crosses a band, ink hairlines, mono micro
## type, a serif signature, objects stuck on like collage (the OG pass, a stamp on a silver disc) and
## still film grain over everything. Signal red-orange marks one keyword or accent per poster.
## No class_name (screens preload it: const PK := preload("res://src/ui/v4/poster_kit.gd")).
##
##   PosterKit.matte(parent)                       full-rect paper matte (#f5f4f0)
##   PosterKit.poster(parent, rect, fill)          shadowed, clipped poster panel; returns the panel
##   PosterKit.band(parent, rect, hero, skin, opts) dark band with the hero's red halftone print
##   PosterKit.halftone_hero(hero, skin, opts)     a halftone TextureRect of the hero (face crop)
##   PosterKit.giant(parent, bbcode, size, spans, pos, box, rot)  two-tone giant type (clip trick)
##   PosterKit.hero_fig(parent, hero, skin, feet, height)  the full-colour animated hero (centred on
##                                                 the painted figure; center_shift, figure_width)
##   PosterKit.still_rect(sprite, feet, height)    where her painted still lies under the live rig
##   PosterKit.gear_object(slot, size, parent, pos) a gear piece as a brushed silver studio object
##   PosterKit.wrap_lines(...) / caps(font, size)  measure giant type to place things under it
##   PosterKit.stamp_disc(parent, pos, d, label, value)    an inspection stamp on a silver disc
##   PosterKit.pass_button(spec, cb)               the OG pass built INSIDE a Button (its labels belong
##                                                 to the button, so tests and guide marks find them)
##   PosterKit.plate_button(text, cb, opts)        a machined plate with etched text, as a Button
##   PosterKit.print_button(text, cb, opts)        printed mono type with a hairline underline (88 px hit)
##   PosterKit.index_tabs(items, selected, cb)     printed section index "01 OFFERS / 02 GEMS ..."
##   PosterKit.bare_button(size) / wire(b, plates, cb)  an invisible button and the press feel, for
##                                                 objects that are buttons (gear pieces)
##   PosterKit.data_table(rows, width, opts)       mono rows, the highlighted value in brackets
##   PosterKit.brackets(size, color)               L-shaped corner marks
##   PosterKit.sticker(lines, opts)                a paper or signal sticker label with mono print
##   PosterKit.ticks(count, filled, size)          a printed tick bar (pity, progress)
##   PosterKit.stencil(text, size, color, cut)     chunky wide type with a stencil cut
##   PosterKit.chevrons(count, size, color)        heavy ">>>" chevrons
##   PosterKit.t(text, size, color, weight) / at(parent, c, pos) / vt(...) / rule(...) / hairbox(...)
##   PosterKit.grain(parent, amount)               still film grain on top (add it last)

const Plate := preload("res://src/ui/components/plate.gd")
const HUD := preload("res://src/ui/components/hud.gd")

const SIGNAL := Color("ff4b1f")
const INK := Color("101113")
const PAPER := Color("e9e8e2")
const MATTE := Color("f5f4f0")
const BAND := Color("141517")
const RED_INK := Color(1.0, 0.36, 0.16, 0.95)


static func t(text: String, size: int, color: Color = INK, weight: String = "mono") -> Label:
	return Kit.label(text, size, color, weight)


## Places `c` at `pos` under `parent` and returns it.
static func at(parent: Node, c: Control, pos: Vector2) -> Control:
	c.position = pos
	parent.add_child(c)
	return c


## Vertical micro type: turned clockwise (reads top to bottom), its top-left corner at pos.
static func vt(parent: Node, text: String, size: int, color: Color, pos: Vector2, weight: String = "mono_bold") -> Label:
	var l := t(text, size, color, weight)
	l.rotation = PI * 0.5
	l.position = pos
	parent.add_child(l)
	return l


static func rule(parent: Node, rect: Rect2, color: Color = INK) -> ColorRect:
	var r := ColorRect.new()
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.color = color
	r.position = rect.position
	r.size = rect.size
	parent.add_child(r)
	return r


## A hairline box (four 1 px rules).
static func hairbox(parent: Node, rect: Rect2, color: Color = Color(INK, 0.55)) -> void:
	rule(parent, Rect2(rect.position, Vector2(rect.size.x, 1)), color)
	rule(parent, Rect2(rect.position + Vector2(0, rect.size.y - 1), Vector2(rect.size.x, 1)), color)
	rule(parent, Rect2(rect.position, Vector2(1, rect.size.y)), color)
	rule(parent, Rect2(rect.position + Vector2(rect.size.x - 1, 0), Vector2(1, rect.size.y)), color)


static func matte(parent: Node) -> ColorRect:
	var m := ColorRect.new()
	m.name = "Matte"
	m.color = MATTE
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(m)
	return m


## A printed poster panel: a soft drop shadow on the matte and the paper, clipped. Content goes in
## the returned control (local coordinates). fill: the paper colour.
static func poster(parent: Node, rect: Rect2, fill: Color = PAPER, shadow: float = 0.28) -> Control:
	var sh := Panel.new()
	sh.name = "PosterShadow"
	sh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ss := StyleBoxFlat.new()
	ss.bg_color = fill
	ss.shadow_color = Color(0, 0, 0, shadow)
	ss.shadow_size = 22
	ss.shadow_offset = Vector2(0, 8)
	sh.add_theme_stylebox_override("panel", ss)
	sh.position = rect.position
	sh.size = rect.size
	parent.add_child(sh)
	var p := Control.new()
	p.name = "Poster"
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.clip_contents = true
	p.position = rect.position
	p.size = rect.size
	parent.add_child(p)
	p.set_meta("shadow", sh)
	return p


## A halftone print of the hero (head to waist, cover-cropped): a TextureRect with the halftone
## material. opts: cell (7), ink (red), light_dots (true), crop ("face" | "full"), gain (1.25).
static func halftone_hero(hero_id: String, skin: String, opts: Dictionary = {}) -> TextureRect:
	var ht := TextureRect.new()
	ht.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ht.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ht.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	var crop := str(opts.get("crop", "face"))
	# "portrait": the small head-and-shoulders file (light on memory, for long lists of posters).
	var tex: Texture2D = null
	if crop == "portrait":
		var pr := HeroArt.make_portrait(hero_id, 8, skin) as TextureRect
		tex = pr.texture
		pr.free()
	else:
		tex = HeroArt.texture(hero_id, skin)
	if tex == null:
		return ht
	if crop == "face":
		var face := HeroArt.portrait_region(hero_id, skin)
		var at_tex := AtlasTexture.new()
		at_tex.atlas = tex
		var zoom: float = opts.get("zoom", 1.0)
		var reg := Rect2(face.get_center() - Vector2(face.size.x * 0.42, face.size.y * 0.62) / zoom, Vector2(face.size.x * 0.84, face.size.y * 1.9) / zoom)
		at_tex.region = reg.intersection(Rect2(Vector2.ZERO, Vector2(tex.get_size())))
		ht.texture = at_tex
	else:
		ht.texture = tex
	var m := SignalKit.halftone_material(float(opts.get("cell", 7.0)), opts.get("ink", RED_INK), bool(opts.get("light_dots", true)))
	m.set_shader_parameter("gain", float(opts.get("gain", 1.25)))
	ht.material = m
	return ht


## A dark band with the hero's red halftone print filling its lower part. Returns the band (add
## micro type to it). opts: as halftone_hero, plus from (0.18: where the print starts, fraction of
## the band height), color (the band colour).
static func band(parent: Node, rect: Rect2, hero_id: String, skin: String, opts: Dictionary = {}) -> ColorRect:
	var b := ColorRect.new()
	b.name = "Band"
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.color = opts.get("color", BAND)
	b.position = rect.position
	b.size = rect.size
	b.clip_contents = true
	parent.add_child(b)
	if hero_id != "":
		var ht := halftone_hero(hero_id, skin, opts)
		var from: float = opts.get("from", 0.18)
		ht.position = Vector2(0, rect.size.y * from)
		ht.size = Vector2(rect.size.x, rect.size.y * (1.0 - from))
		b.add_child(ht)
		b.set_meta("print", ht)
	return b


## Giant display type, two-tone where it crosses bands (the Lobby poster's clip trick): one
## RichTextLabel per span, each clipped to its span. spans: [[x0, width, colour], ...] in parent
## coordinates (full parent height); pos / box: the text block's position and size in the parent;
## rot: its rotation (PI / 2 = turned clockwise). bbcode may colour one keyword. Returns the labels
## (animate them together: they share position, scale and alpha).
static func giant(parent: Control, bbcode: String, font_size: int, spans: Array, pos: Vector2, box: Vector2,
		rot: float = PI * 0.5, weight: String = "compressed", line_sep: int = -14) -> Array[RichTextLabel]:
	var out: Array[RichTextLabel] = []
	for sp: Array in spans:
		var clip := Control.new()
		clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip.clip_contents = true
		clip.position = Vector2(float(sp[0]), 0)
		clip.size = Vector2(float(sp[1]), parent.size.y)
		parent.add_child(clip)
		var rt := RichTextLabel.new()
		rt.bbcode_enabled = true
		rt.text = bbcode
		rt.fit_content = false
		rt.scroll_active = false
		rt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rt.add_theme_font_override("normal_font", Kit.font(weight))
		rt.add_theme_font_size_override("normal_font_size", font_size)
		rt.add_theme_color_override("default_color", sp[2])
		rt.add_theme_constant_override("line_separation", line_sep)
		rt.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rt.size = box
		rt.rotation = rot
		rt.position = pos - Vector2(float(sp[0]), 0)
		rt.set_meta("base", rt.position)
		clip.add_child(rt)
		out.append(rt)
	return out


## Greedy word wrap of `text` into lines no wider than `width` px in `font` at `fs`.
static func wrap_lines(text: String, font: Font, fs: int, width: float) -> Array[String]:
	var out: Array[String] = []
	var cur := ""
	for wd in text.split(" ", false):
		var tryl := wd if cur == "" else cur + " " + wd
		if cur != "" and font.get_string_size(tryl, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > width:
			out.append(cur)
			cur = wd
		else:
			cur = tryl
	if cur != "" or out.is_empty():
		out.append(cur)
	return out


## Cap height and the gap above the caps for a line of `font` at `fs` (px), to place things
## right under giant type: Vector2(top of the caps, bottom of the caps) from the line's top.
static func caps(font: Font, fs: int) -> Vector2:
	var a := font.get_ascent(fs)
	return Vector2(a - fs * 0.72, a)


## Moves / scales / fades a giant() block (all spans together). offset in parent px.
static func giant_pose(labels: Array[RichTextLabel], offset: Vector2, scale: float = 1.0, alpha: float = 1.0) -> void:
	for rt in labels:
		if not is_instance_valid(rt):
			continue
		rt.position = (rt.get_meta("base") as Vector2) + offset
		rt.scale = Vector2(scale, scale)
		rt.modulate.a = alpha


## The full-colour animated hero, feet at `feet` (parent px), `height` px tall. Returns the anchor
## (a Node2D holding the HeroSprite; the sprite is its first child).
static func hero_fig(parent: Node, hero_id: String, skin: String, feet: Vector2, height: float) -> Node2D:
	var anchor := Node2D.new()
	anchor.name = "HeroAnchor"
	anchor.position = feet
	parent.add_child(anchor)
	var sp := HeroArt.make_sprite(hero_id, skin)
	anchor.add_child(sp)
	var base_h: float = sp.call("get_height")
	var k := height / maxf(base_h, 1.0)
	sp.scale = Vector2(k, k)
	anchor.position.x -= center_shift(sp, height)
	return anchor


## How far the figure's middle sits right of her feet (px at `height`): poses that lean or carry
## a weapon to one side are centred on the painted figure (its opaque pixels), not on the feet.
static func center_shift(sprite: Node2D, height: float) -> float:
	var hs := sprite as HeroSprite
	if hs == null or hs.rig == null or hs.rig.rig == null or hs.rig.rig.bounds.position.y >= 0.0:
		return 0.0
	var b := hs.rig.rig.bounds
	var s := height / -b.position.y
	var used := _used_rect(hs.rig.rig.still_path)
	var mid := b.position.x + b.size.x * 0.5
	if used.size.x > 0.0:
		mid = used.get_center().x - 512.0
	return clampf(mid * s, -height * 0.2, height * 0.2)


## Width of the painted figure (its opaque pixels) in px at `height` (0 when unknown).
static func figure_width(sprite: Node2D, height: float) -> float:
	var hs := sprite as HeroSprite
	if hs == null or hs.rig == null or hs.rig.rig == null or hs.rig.rig.bounds.position.y >= 0.0:
		return 0.0
	return _used_rect(hs.rig.rig.still_path).size.x * height / -hs.rig.rig.bounds.position.y


static var _used_cache: Dictionary = {}


## The opaque part of a 1024 x 2048 still (image px), cached by path.
static func _used_rect(path: String) -> Rect2:
	if _used_cache.has(path):
		return _used_cache[path]
	var r := Rect2()
	# Headless runs have no texture data to read back (the dummy renderer).
	if path != "" and ResourceLoader.exists(path) and DisplayServer.get_name() != "headless":
		var tex: Texture2D = load(path)
		var img := tex.get_image() if tex else null
		if img and not img.is_empty():
			if img.is_compressed():
				img.decompress()
			var k := 1024.0 / float(img.get_width())
			var u := img.get_used_rect()
			r = Rect2(Vector2(u.position) * k, Vector2(u.size) * k)
	_used_cache[path] = r
	return r


## Where the hero's painted still lies when the sprite stands with its feet at `feet`, `height`
## tall (the still's soles sit at 512, 1990 of 1024 x 2048; HeroSprite maps the canvas 1:1 at
## BASE_SCALE). For a halftone or print copy that lines up with the live rig.
static func still_rect(sprite: Node2D, feet: Vector2, height: float) -> Rect2:
	var fig := 1278.0
	var hs := sprite as HeroSprite
	if hs and hs.rig and hs.rig.rig and hs.rig.rig.bounds.position.y < 0.0:
		fig = -hs.rig.rig.bounds.position.y
	var s := height / fig
	return Rect2(feet - Vector2(512, 1990) * s, Vector2(1024, 2048) * s)


## An inspection stamp on a silver disc (the Lobby's Sanctum stamp), turned a little.
static func stamp_disc(parent: Node, pos: Vector2, d: float, label: String, value: String, rot: float = -0.12) -> Control:
	var disc := SignalKit.plate("silver", pos, Vector2(d, d), {"circle": true, "shadow": 0.5}, parent)
	var st := SignalKit.stamp(label, value, d)
	disc.add_child(st)
	disc.pivot_offset = Vector2(d, d) * 0.5
	disc.rotation = rot
	disc.set_meta("stamp", st)
	return disc


## Silhouettes of the four gear slots as studio objects (unit square, x right, y down).
const GEAR_SHAPES := {
	"weapon": [Vector2(0.42, 0.02), Vector2(0.58, 0.02), Vector2(0.66, 0.14), Vector2(0.6, 0.76), Vector2(0.72, 0.82),
		Vector2(0.72, 0.88), Vector2(0.56, 0.88), Vector2(0.56, 0.98), Vector2(0.44, 0.98), Vector2(0.44, 0.88), Vector2(0.28, 0.88),
		Vector2(0.28, 0.82), Vector2(0.4, 0.76), Vector2(0.34, 0.14)],
	"armor": [Vector2(0.12, 0.08), Vector2(0.38, 0.08), Vector2(0.5, 0.16), Vector2(0.62, 0.08), Vector2(0.88, 0.08),
		Vector2(0.95, 0.22), Vector2(0.88, 0.62), Vector2(0.5, 0.96), Vector2(0.12, 0.62), Vector2(0.05, 0.22)],
	"helm": [Vector2(0.22, 0.92), Vector2(0.12, 0.62), Vector2(0.14, 0.36), Vector2(0.26, 0.16), Vector2(0.5, 0.06),
		Vector2(0.74, 0.16), Vector2(0.86, 0.36), Vector2(0.88, 0.62), Vector2(0.78, 0.92), Vector2(0.62, 0.92),
		Vector2(0.62, 0.68), Vector2(0.38, 0.68), Vector2(0.38, 0.92)],
	"charm": [Vector2(0.34, 0.12), Vector2(0.66, 0.12), Vector2(0.9, 0.38), Vector2(0.5, 0.95), Vector2(0.1, 0.38)],
}


## The rendered piece for a gear item ("Gilded Spear", tier 3): assets/art/ui/gear/<noun>_<tier>.png
## from tools/blender/gear_objects.py, or null.
static func gear_texture(item_name: String, tier: int) -> Texture2D:
	if item_name == "":
		return null
	var noun := item_name.get_slice(" ", item_name.get_slice_count(" ") - 1).to_lower()
	var path := "res://assets/art/ui/gear/%s_%d.png" % [noun, clampi(tier, 1, 5)]
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


## A gear piece as a studio object: its Cycles render (by item name and tier) on the paper, else a
## brushed silver part in its slot's silhouette with the slot glyph engraved. Size s x s.
static func gear_object(slot: String, s: float, parent: Node = null, pos: Vector2 = Vector2.ZERO, item_name: String = "",
		tier: int = 0) -> Control:
	var tex := gear_texture(item_name, tier)
	if tex:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.position = pos
		tr.size = Vector2(s, s)
		tr.pivot_offset = Vector2(s, s) * 0.5
		if parent:
			parent.add_child(tr)
		return tr
	var pts := PackedVector2Array()
	for v: Vector2 in GEAR_SHAPES.get(slot, GEAR_SHAPES["charm"]):
		pts.append(v * s)
	var screws: Array = []
	match slot:
		"armor":
			screws = [Vector2(0.2, 0.2) * s, Vector2(0.8, 0.2) * s]
		"helm":
			screws = [Vector2(0.24, 0.6) * s, Vector2(0.76, 0.6) * s]
	var p := SignalKit.plate("silver", pos, Vector2(s, s), {"shape": pts, "topo": 0.5, "shadow": 0.55, "screws": screws}, parent)
	var isz := s * (0.2 if slot == "weapon" else 0.3)
	var ic := SignalKit.etch_icon("gear_" + slot, isz, true)
	var cy := {"weapon": 0.36, "armor": 0.42, "helm": 0.36, "charm": 0.42}.get(slot, 0.4) as float
	ic.position = Vector2(s * 0.5 - isz * 0.5, s * cy - isz * 0.5)
	p.add_child(ic)
	return p


## Still film grain over everything (add it last).
static func grain(parent: Node, amount: float = 0.06) -> ColorRect:
	var g := SignalKit.grain(amount, true)
	g.name = "Grain"
	parent.add_child(g)
	return g


## The OG pass (brushed silver plate with a code, kicker, etched title, sub line and a knob, over a
## glowing signal plate with an action pill and an info line), as one Button. spec: width (400),
## kicker, title, sub, action, info, icon, code (true), disabled, title_size (30).
static func pass_button(spec: Dictionary, on_pressed: Callable = Callable()) -> Button:
	var w: float = spec.get("width", 400.0)
	var off := bool(spec.get("disabled", false))
	var b := bare_button(Vector2(w, 176))
	var sig := SignalKit.plate("graphite" if off else "signal", Vector2(8, 78), Vector2(w - 14, 96), {"cuts": [0, 12, 18, 0],
		"glow": 0.0 if off else 0.4, "glow_radius": 14.0, "pulse": 0.0 if off else 0.5, "topo": 0.6}, b)
	var top_sz := Vector2(w, 94)
	var silver := SignalKit.plate("silver", Vector2.ZERO, top_sz, {"shape": Plate.tab_bottom(top_sz, 14, w * 0.33, w * 0.65, 14), "topo": 0.5,
		"screws": [Vector2(13, 13), Vector2(w - 13, 13), Vector2(13, 66), Vector2(w - 13, 66)]}, b)
	var x := 26.0
	if spec.get("code", true):
		var code := SignalKit.matrix(Vector2(58, 58))
		code.position = Vector2(26, 13)
		silver.add_child(code)
		x = 98.0
	var kick := SignalKit.etch(str(spec.get("kicker", "")), 10, "mono_bold")
	kick.position = Vector2(x, 12)
	silver.add_child(kick)
	var title_txt := str(spec.get("title", ""))
	var ts := int(spec.get("title_size", 30))
	var avail := w - x - (92.0 if spec.has("icon") else 24.0)
	var tf := Kit.font("wide_black")
	while ts > 14 and tf.get_string_size(title_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, ts).x > avail:
		ts -= 1
	var title := SignalKit.etch(title_txt, ts, "wide_black")
	title.position = Vector2(x - 2, 26 + (30 - ts) * 0.6)
	silver.add_child(title)
	var sub := SignalKit.etch(str(spec.get("sub", "")), 10, "mono")
	sub.position = Vector2(x, 66)
	silver.add_child(sub)
	if spec.has("icon"):
		var knob := SignalKit.plate("dial", Vector2(w - 82, 20), Vector2(50, 50), {"circle": true, "shadow": 0.5}, silver)
		var ic := Kit.icon(str(spec["icon"]), 22, Color(1, 1, 1, 0.95))
		ic.position = Vector2(14, 14)
		knob.add_child(ic)
	var act := SignalKit.pill(str(spec.get("action", "ENGAGE  >>>")), int(spec.get("action_size", 20)), Color(1, 1, 1, 0.45) if off else Color.WHITE)
	act.position = Vector2(18, 32)
	sig.add_child(act)
	if spec.has("info"):
		var ix := maxf(w * 0.56, 34.0 + act.get_combined_minimum_size().x + 14.0)
		var info := t(str(spec["info"]), 10, Color(1, 1, 1, 0.5 if off else 0.9), "mono")
		info.position = Vector2(ix, 30)
		info.size = Vector2(w - 24 - ix, 40)
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sig.add_child(info)
		b.set_meta("info_label", info)
	b.disabled = off
	wire(b, [silver, sig], on_pressed)
	return b


## A machined plate as a button: etched text (and an optional kicker line and icon). opts: size,
## preset ("silver" | "graphite" | "slate" | "signal"), cuts, kicker, icon, text_size, weight,
## disabled, screws.
static func plate_button(text: String, on_pressed: Callable = Callable(), opts: Dictionary = {}) -> Button:
	var sz: Vector2 = opts.get("size", Vector2(200, 88))
	var preset := str(opts.get("preset", "silver"))
	var off := bool(opts.get("disabled", false))
	var b := bare_button(sz)
	var light := preset == "silver" or preset == "slate"
	var face := preset if not off else "slate"
	var pl := SignalKit.plate(face, Vector2(0, 6), sz - Vector2(0, 12), {"cuts": opts.get("cuts", [10, 0, 10, 0]),
		"topo": 0.4 if light else 0.0, "glow": 0.35 if preset == "signal" and not off else 0.0, "glow_radius": 12.0,
		"screws": [Vector2(10, (sz.y - 12) * 0.5), Vector2(sz.x - 10, (sz.y - 12) * 0.5)] if bool(opts.get("screws", false)) else []}, b)
	if off:
		pl.modulate = Color(1, 1, 1, 0.55)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	row.size = sz - Vector2(0, 12)
	var etched := light or off
	if opts.has("icon"):
		var ic: Control = SignalKit.etch_icon(str(opts["icon"]), 24, true) if etched else Kit.icon(str(opts["icon"]), 24, Color.WHITE)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(ic)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 0)
	if opts.has("kicker"):
		var k: Control = SignalKit.etch(str(opts["kicker"]), 10, "mono_bold", true) if etched else t(str(opts["kicker"]), 10, Color(1, 1, 1, 0.85), "mono_bold")
		col.add_child(k)
	var ts := int(opts.get("text_size", 22))
	var wt := str(opts.get("weight", "wide_black"))
	var tl: Control = SignalKit.etch(text, ts, wt, true) if etched else t(text, ts, Color.WHITE, wt)
	col.add_child(tl)
	row.add_child(col)
	pl.add_child(row)
	b.disabled = off
	wire(b, [pl], on_pressed)
	return b


## Printed type as a button (a poster label you can tap): mono text, an optional hairline
## underline and arrow, a big invisible hit area. opts: size (hit), text_size (16), color, weight,
## underline (true), align ("left" | "center" | "right"), disabled.
static func print_button(text: String, on_pressed: Callable = Callable(), opts: Dictionary = {}) -> Button:
	var sz: Vector2 = opts.get("size", Vector2(200, 88))
	var b := bare_button(sz)
	var col: Color = opts.get("color", INK)
	var off := bool(opts.get("disabled", false))
	if off:
		col = Color(col, 0.4)
	var l := t(text, int(opts.get("text_size", 16)), col, str(opts.get("weight", "mono_bold")))
	var align := str(opts.get("align", "left"))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if align == "center" else (HORIZONTAL_ALIGNMENT_RIGHT if align == "right" else HORIZONTAL_ALIGNMENT_LEFT)
	l.size = Vector2(sz.x, sz.y)
	l.position = Vector2.ZERO
	b.add_child(l)
	if bool(opts.get("underline", true)):
		var w := minf(l.get_minimum_size().x, sz.x)
		var x := 0.0 if align == "left" else ((sz.x - w) * 0.5 if align == "center" else sz.x - w)
		rule(b, Rect2(x, sz.y * 0.5 + int(opts.get("text_size", 16)) * 0.7, w, 1), Color(col, 0.8))
	b.set_meta("text_label", l)
	b.disabled = off
	wire(b, [], on_pressed, l)
	return b


## The printed section index (the Lobby footer): "01 OFFERS / 02 GEMS / 03 WARDROBE", the current
## one in signal with a short bar under it. on_select(i). Returns the row; its buttons are named
## "Tab<i>".
static func index_tabs(items: Array, selected: int, on_select: Callable, width: float = 684.0) -> Control:
	var row := Control.new()
	row.name = "IndexTabs"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.custom_minimum_size = Vector2(width, Kit.BUTTON_H)
	row.size = row.custom_minimum_size
	var cw := width / maxf(1.0, float(items.size()))
	for i in items.size():
		var on := i == selected
		var b := bare_button(Vector2(cw, Kit.BUTTON_H))
		b.name = "Tab%d" % i
		b.position = Vector2(i * cw, 0)
		var l := t("%02d %s" % [i + 1, str(items[i]).to_upper()], 15, SIGNAL if on else INK, "mono_bold")
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.size = Vector2(cw, Kit.BUTTON_H)
		b.add_child(l)
		if on:
			rule(b, Rect2(cw * 0.5 - 22, Kit.BUTTON_H * 0.5 + 18, 44, 3), SIGNAL)
		if i < items.size() - 1:
			var sl := t("/", 15, Color(INK, 0.35), "mono")
			sl.position = Vector2((i + 1) * cw - 5, Kit.BUTTON_H * 0.5 - 11)
			row.add_child(sl)
		var idx := i
		wire(b, [], func() -> void: on_select.call(idx), l)
		row.add_child(b)
	return row


static func bare_button(sz: Vector2) -> Button:
	var b := Button.new()
	b.theme_type_variation = &"BareButton"
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	b.custom_minimum_size = sz
	b.size = sz
	return b


## Press feel: plates sink while held (or the label dims); release plays the tap and calls back
## (a press that turned into a scroll does not fire); a disabled button shakes "no".
static func wire(b: Button, plates: Array, on_pressed: Callable, lbl: Control = null) -> void:
	b.button_down.connect(func() -> void:
		b.set_meta("_down_at", b.get_global_mouse_position())
		for p: Variant in plates:
			if p is Plate and is_instance_valid(p):
				(p as Plate).set_pressed_look(true)
			elif p is Control and is_instance_valid(p):
				(p as Control).scale = Vector2(0.95, 0.95)
		if lbl and is_instance_valid(lbl):
			lbl.modulate.a = 0.55
		Kit.haptic(12))
	b.button_up.connect(func() -> void:
		for p: Variant in plates:
			if p is Plate and is_instance_valid(p):
				(p as Plate).set_pressed_look(false)
			elif p is Control and is_instance_valid(p):
				(p as Control).scale = Vector2.ONE
		if lbl and is_instance_valid(lbl):
			lbl.modulate.a = 1.0)
	b.gui_input.connect(func(ev: InputEvent) -> void:
		if not b.disabled:
			return
		var mb := ev as InputEventMouseButton
		if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			Kit.deny(b))
	if on_pressed.is_valid():
		b.pressed.connect(func() -> void:
			var down: Variant = b.get_meta("_down_at") if b.has_meta("_down_at") else null
			if down is Vector2 and (down as Vector2).distance_to(b.get_global_mouse_position()) > 36.0:
				return
			Kit.sfx("tap")
			on_pressed.call())


## Mono data table (the planet-table reference): rows of [key, value] or [key, value, true]
## (highlighted: a pale bar, a tick and the value in brackets). opts: color, size (15), row_h (28),
## bar (highlight colour).
static func data_table(rows: Array, width: float, opts: Dictionary = {}) -> Control:
	var tb := _Table.new()
	tb.rows = rows
	tb.color = opts.get("color", INK)
	tb.text_size = int(opts.get("size", 15))
	tb.row_h = float(opts.get("row_h", 28.0))
	tb.bar = opts.get("bar", Color(1, 1, 1, 0.6))
	tb.custom_minimum_size = Vector2(width, rows.size() * tb.row_h)
	tb.size = tb.custom_minimum_size
	return tb


## L-shaped corner marks at the four corners of a `size` rect.
static func brackets(size: Vector2, color: Color = INK, arm: float = 18.0, width: float = 1.5) -> Control:
	var b := _Brackets.new()
	b.color = color
	b.arm = arm
	b.width = width
	b.size = size
	return b


## A sticker label: paper (or signal / ink) with mono print. lines: [[text, size, weight], ...] or
## strings. opts: fill ("paper" | "white" | "signal" | "ink"), width, pad (12), barcode (height),
## rotation (radians), shadow (alpha).
static func sticker(lines: Array, opts: Dictionary = {}) -> PanelContainer:
	var fill := str(opts.get("fill", "white"))
	var bg: Color = {"paper": PAPER, "white": Color("f4f3ef"), "signal": SIGNAL, "ink": Color("17181b")}.get(fill, PAPER)
	var fg := Color.WHITE if fill == "signal" or fill == "ink" else INK
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(int(opts.get("radius", 2)))
	sb.shadow_color = Color(0, 0, 0, float(opts.get("shadow", 0.3)))
	sb.shadow_size = int(opts.get("shadow_size", 5))
	sb.shadow_offset = Vector2(1, 3)
	var pad := int(opts.get("pad", 12))
	sb.content_margin_left = pad
	sb.content_margin_right = pad
	sb.content_margin_top = pad - 2
	sb.content_margin_bottom = pad - 2
	p.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", int(opts.get("gap", 2)))
	for ln: Variant in lines:
		if ln is Control:
			v.add_child(ln)
			continue
		var spec: Array = ln if ln is Array else [str(ln), 13, "mono"]
		var col: Color = spec[3] if spec.size() > 3 else fg
		var l := t(str(spec[0]), int(spec[1]), col, str(spec[2]))
		if opts.has("width"):
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(l)
	if opts.has("barcode"):
		v.add_child(SignalKit.barcode(Vector2(float(opts.get("barcode_w", 120.0)), float(opts["barcode"])), fg, int(opts.get("seed", 289))))
	p.add_child(v)
	if opts.has("width"):
		p.custom_minimum_size.x = float(opts["width"])
	p.size = p.get_combined_minimum_size()
	p.rotation = float(opts.get("rotation", 0.0))
	return p


## A printed tick bar: `count` ticks, the first `filled` in signal (the pity meter as print).
static func ticks(count: int, filled: int, size: Vector2, color: Color = INK, on: Color = SIGNAL) -> Control:
	var tk := _Ticks.new()
	tk.count = count
	tk.filled = filled
	tk.color = color
	tk.on = on
	tk.custom_minimum_size = size
	tk.size = size
	return tk


## Chunky wide type with a stencil cut: a thin band of `cut` (the paper colour) across it.
static func stencil(text: String, size: int, color: Color = INK, cut: Color = PAPER, weight: String = "wide_black") -> Control:
	var s := _Stencil.new()
	s.text = text
	s.font_size = size
	s.color = color
	s.cut = cut
	s.weight = weight
	var f := Kit.font(weight)
	s.custom_minimum_size = Vector2(f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x, size * 0.78)
	s.size = s.custom_minimum_size
	return s


static func chevrons(count: int, size: float, color: Color = INK) -> Control:
	var c := _Chevrons.new()
	c.count = count
	c.color = color
	c.custom_minimum_size = Vector2(count * size * 0.78 + size * 0.2, size)
	c.size = c.custom_minimum_size
	return c


static func led(parent: Node, pos: Vector2, mode: String = "breathe", color: Color = Color("ff3b1f")) -> Control:
	var l := HUD.Led.new()
	l.size = Vector2(16, 16)
	l.position = pos
	l.mode = mode
	l.color = color
	parent.add_child(l)
	return l


# ------------------------------------------------------------------ drawn pieces

class _Table:
	extends Control
	var rows: Array = []
	var color := Color("101113")
	var text_size := 15
	var row_h := 28.0
	var bar := Color(1, 1, 1, 0.6)

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var f := Kit.font("mono")
		var fb := Kit.font("mono_bold")
		var asc := f.get_ascent(text_size)
		for i in rows.size():
			var r: Array = rows[i]
			var y := i * row_h
			var hi := r.size() > 2 and bool(r[2])
			var base := y + (row_h - text_size) * 0.5 + asc * 0.82
			var key := str(r[0])
			var val := str(r[1])
			if key == "" and val == "":
				continue
			var fo: Font = fb if hi else f
			if hi:
				draw_rect(Rect2(0, y + 2, size.x, row_h - 4), bar)
				draw_rect(Rect2(6, y + 7, 2, row_h - 14), color)
			draw_string(fo, Vector2(18, base), key, HORIZONTAL_ALIGNMENT_LEFT, size.x * 0.6, text_size, color)
			var vw := fo.get_string_size(val, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size).x
			var vx := size.x - 18.0 - vw
			draw_string(fo, Vector2(vx, base), val, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size, color)
			if hi:
				var y0 := y + 4.0
				var y1 := y + row_h - 4.0
				for side in 2:
					var bx := vx - 12.0 if side == 0 else size.x - 6.0
					var dir := 1.0 if side == 0 else -1.0
					draw_line(Vector2(bx, y0), Vector2(bx, y1), color, 1.2)
					draw_line(Vector2(bx, y0), Vector2(bx + 5.0 * dir, y0), color, 1.2)
					draw_line(Vector2(bx, y1), Vector2(bx + 5.0 * dir, y1), color, 1.2)


class _Brackets:
	extends Control
	var color := Color("101113")
	var arm := 18.0
	var width := 1.5

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var w := size.x
		var h := size.y
		for c: Array in [[Vector2(0, 0), Vector2(1, 1)], [Vector2(w, 0), Vector2(-1, 1)], [Vector2(0, h), Vector2(1, -1)], [Vector2(w, h), Vector2(-1, -1)]]:
			var o: Vector2 = c[0]
			var d: Vector2 = c[1]
			draw_line(o, o + Vector2(arm * d.x, 0), color, width)
			draw_line(o, o + Vector2(0, arm * d.y), color, width)


class _Ticks:
	extends Control
	var count := 60
	var filled := 20
	var color := Color("101113")
	var on := Color("ff4b1f")

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var step := size.x / maxf(1.0, float(count))
		for i in count:
			var x := i * step + step * 0.5
			var long := i % 10 == 0
			var h := size.y if long else size.y * 0.62
			draw_line(Vector2(x, size.y - h), Vector2(x, size.y), on if i < filled else Color(color, 0.55), 2.0 if i < filled else 1.0)


class _Stencil:
	extends Control
	var text := ""
	var font_size := 120
	var color := Color("101113")
	var cut := Color("e9e8e2")
	var weight := "wide_black"

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var f := Kit.font(weight)
		var cap := font_size * 0.72
		draw_string(f, Vector2(0, (size.y + cap) * 0.5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
		draw_rect(Rect2(-4, size.y * 0.54, size.x + 8, maxf(2.0, font_size * 0.035)), cut)


class _Chevrons:
	extends Control
	var count := 3
	var color := Color("101113")

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var h := size.y
		var step := h * 0.78
		var th := h * 0.26
		for i in count:
			var x := i * step
			var pts := PackedVector2Array([Vector2(x, 0), Vector2(x + th, 0), Vector2(x + th + h * 0.5, h * 0.5),
				Vector2(x + th, h), Vector2(x, h), Vector2(x + h * 0.5, h * 0.5)])
			draw_colored_polygon(pts, color)
