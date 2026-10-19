extends Button
## A hero as a small printed poster (style v4, the Lobby poster's look; the roster catalogue and the
## team bench): paper with a soft shadow, a dark band down the left with her red halftone print and
## her name turned on its side in paper type, her art in full colour boxed by a hairline (the "Art"
## TextureRect, Kit.art_crop in the look she wears: Kit.hero_look follows skins and nudity), and a
## printed label strip: level in big compressed numerals, role, power, star pips and the rarity tier.
## Status lights in signal: in the team, ready to level or star up (blinking), new.
## Layout at width w (height w * ratio); everything scales with k = w / 218.
##   setup(hero_id, {size, ratio, owned, level, stars, new, dot, in_team, slot (her team position,
##   0-4, as a signal tab at the band's head: the team bench), compact (no label strip), skin,
##   on_pressed})
## Named "PortraitCard_<id>" like the card it replaces (tests find the art by that name).

const PK := preload("res://src/ui/v4/hero_poster_kit.gd")
const HUD := preload("res://src/ui/components/hud.gd")

var hero_id := ""
var opts: Dictionary = {}
var face: Control


func setup(id: String, o: Dictionary = {}) -> void:
	hero_id = id
	opts = o
	name = "PortraitCard_" + id
	theme_type_variation = &"BareButton"
	focus_mode = FOCUS_NONE
	mouse_filter = MOUSE_FILTER_PASS
	var w: float = float(o.get("size", 218.0))
	var h := roundf(w * float(o.get("ratio", 1.5)))
	custom_minimum_size = Vector2(w, h)
	_build(w, h)
	Kit.add_press_fx(self, face)
	var cb: Variant = o.get("on_pressed", null)
	if cb is Callable and (cb as Callable).is_valid():
		Kit._connect_pressed(self, cb)


func _build(w: float, h: float) -> void:
	var def: Dictionary = Kit._def(hero_id)
	var rarity := str(def.get("rarity", "rare"))
	var role := str(def.get("role", "striker"))
	var entry := _owned_entry()
	var owned: bool = bool(opts.get("owned", not entry.is_empty()))
	var stars: int = int(opts.get("stars", entry.get("stars", Kit.RARITY_STARS.get(rarity, 1))))
	var level: int = int(opts.get("level", entry.get("level", 1 if owned else 0)))
	var compact: bool = bool(opts.get("compact", false))
	var look := Kit.hero_look(hero_id, opts)
	var k := w / 218.0
	var band := roundf(50.0 * k)
	var foot := 0.0 if compact else roundf(62.0 * k)
	var ink := PK.INK if owned else Color(PK.INK, 0.55)

	face = Control.new()
	face.name = "Face"
	face.mouse_filter = MOUSE_FILTER_IGNORE
	face.size = Vector2(w, h)
	add_child(face)
	var p := PK.poster(face, Rect2(Vector2.ZERO, Vector2(w, h)), maxi(6, int(10 * k)))
	p.name = "Clip"

	# The band: her print and her name turned on its side, paper on dark.
	PK.rect(p, Rect2(0, 0, band, h), PK.BAND)
	var ht := PK.halftone_print(hero_id, look, Vector2(band, h * 0.62), maxf(4.0, 5.0 * k),
		PK.PRINT if owned else Color(0.62, 0.63, 0.64, 0.9), 1.1)
	ht.position = Vector2(0, h * 0.38)
	p.add_child(ht)
	# Her team position (the bench) as a signal tab at the band's head, else her catalogue number.
	var top_pad := 28.0 * k
	if not opts.has("slot"):
		var no := PK.t("No.\n%02d" % _number(), int(maxf(9.0, 10.0 * k)), Color(PK.PAPER, 0.85), "mono_bold")
		no.add_theme_constant_override("line_spacing", -3)
		PK.at(p, no, Vector2(5 * k, 4 * k))
		top_pad = 36.0 * k
	if opts.has("slot"):
		var tab := maxf(22.0, 26.0 * k)
		PK.rect(p, Rect2(0, 0, band, tab), PK.SIG)
		var sl := PK.t("%02d" % (int(opts["slot"]) + 1), int(maxf(11.0, 13.0 * k)), Color.WHITE, "mono_bold")
		sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		sl.size = Vector2(band, tab)
		PK.at(p, sl, Vector2.ZERO)
		top_pad = tab + 6.0 * k
	# Her name down the band.
	var nm := str(def.get("name", hero_id)).to_upper()
	var fs := clampi(int(80.0 * (h - top_pad - 12.0 * k) / maxf(PK.text_w(nm, 80), 1.0)), int(28 * k), int(band * 1.25))
	var nl := PK.t(nm, fs, PK.PAPER, "compressed")
	nl.rotation = PI * 0.5
	nl.position = Vector2(band + 2.0 * k + fs * 0.08, top_pad)
	p.add_child(nl)

	# Her art, full colour, boxed by a hairline.
	var ax := band + 6.0 * k
	var art_rect := Rect2(ax, 6.0 * k, w - ax - 6.0 * k, h - foot - 12.0 * k)
	PK.rect(p, art_rect, Color("dedcd4") if owned else Color("d4d4d2"))
	var art := TextureRect.new()
	art.name = "Art"
	art.mouse_filter = MOUSE_FILTER_IGNORE
	art.texture = Kit.art_crop(hero_id, art_rect.size.x / art_rect.size.y, 1.05, look)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	art.position = art_rect.position
	art.size = art_rect.size
	if not owned:
		art.material = Kit.grayscale_material()
		art.modulate = Color(1, 1, 1, 0.75)
	p.add_child(art)
	var fr := Panel.new()
	fr.mouse_filter = MOUSE_FILTER_IGNORE
	var fb := StyleBoxFlat.new()
	fb.draw_center = false
	fb.border_color = Color(PK.INK, 0.6)
	fb.set_border_width_all(1)
	fr.add_theme_stylebox_override("panel", fb)
	fr.position = art_rect.position
	fr.size = art_rect.size
	p.add_child(fr)

	# The label strip.
	if not compact:
		var fy := h - foot
		if owned and level > 0:
			PK.at(p, PK.t("LV", int(10 * k), ink, "mono_bold"), Vector2(ax, fy + 6 * k))
			var lv := PK.t("%02d" % level, int(40 * k), ink, "compressed")
			PK.at(p, lv, Vector2(ax + 18 * k, fy - 4 * k))
		else:
			PK.at(p, PK.t("NOT\nSUMMONED", int(10 * k), ink, "mono_bold"), Vector2(ax, fy + 8 * k))
		var mid_x := ax + 76.0 * k
		PK.at(p, PK.t(str(Kit.ROLE_NAMES.get(role, role)).to_upper(), int(10 * k), ink, "mono_bold"), Vector2(mid_x, fy + 7 * k))
		if owned:
			var g := Kit.autoload("Game")
			var pw := int(g.call("hero_power", hero_id)) if g and g.has_method("hero_power") else 0
			PK.at(p, PK.t("PWR %s" % Kit.format_num(pw), int(10 * k), ink, "mono"), Vector2(mid_x, fy + 22 * k))
		var pips := PK.Stars.new()
		pips.count = Kit.MAX_STARS if owned else maxi(stars, 1)
		pips.filled = stars if owned else 0
		pips.color = ink
		pips.gap = 1.5 * k
		pips.size = Vector2(pips.count * 9.0 * k + (pips.count - 1) * 1.5 * k, 9.0 * k)
		PK.at(p, pips, Vector2(mid_x, fy + 40 * k))
		var tier := PK.t(str(Kit.RARITY_TIER.get(rarity, "I")), int(34 * k), ink, "compressed")
		tier.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		tier.size = Vector2(44 * k, 40 * k)
		PK.at(p, tier, Vector2(w - 50 * k, fy + 2 * k))

	# Status lights and tags (signal).
	if bool(opts.get("in_team", false)) and not opts.has("slot"):
		var led := HUD.Led.new()
		led.name = "TeamLight"
		led.size = Vector2(18, 18) * k
		led.position = Vector2(ax + 4 * k, 10 * k)
		p.add_child(led)
	if bool(opts.get("dot", false)):
		var d := HUD.Led.new()
		d.name = "ReadyLight"
		d.mode = "blink"
		d.size = Vector2(22, 22) * k
		d.position = Vector2(w - 28 * k, 10 * k)
		face.add_child(d)
	if bool(opts.get("new", false)):
		var nb := SignalKit.pill("NEW", int(maxf(11.0, 12.0 * k)), PK.SIG, "mono_bold")
		var ps := nb.get_theme_stylebox("panel") as StyleBoxFlat
		ps.bg_color = PK.SIG
		(nb.get_child(0) as Label).add_theme_color_override("font_color", Color.WHITE)
		nb.position = Vector2(w - 60 * k, -8 * k)
		face.add_child(nb)


## Her catalogue number (order in data/heroes.json, from 1).
func _number() -> int:
	var g := Kit.autoload("Game")
	if g == null or not g.has_method("all_hero_defs"):
		return 0
	var i := 0
	for d: Variant in g.call("all_hero_defs"):
		i += 1
		if str((d as Dictionary).get("id", "")) == hero_id:
			return i
	return 0


func _owned_entry() -> Dictionary:
	var g := Kit.autoload("Game")
	var st: Variant = g.get("state") if g else null
	if st is Dictionary:
		var heroes: Variant = (st as Dictionary).get("heroes", {})
		if heroes is Dictionary and (heroes as Dictionary).has(hero_id):
			var e: Variant = heroes[hero_id]
			if e is Dictionary:
				return e
	return {}
