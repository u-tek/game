extends Button
## Tall portrait hero card (Kit.portrait_card): the roster card of style v2.
## Layout at width w (height w * RATIO), all measures scale with k = w / 158:
##   pale studio backdrop with hatching, waist-up crop of the full-body art
##   (Kit.art_crop), role hex + faction hex top-left, decorative barcode top-right,
##   footer: dark-to-rarity gradient, "LV." over a big two-digit level on the left,
##   name bottom-right, rarity chevrons + star pips above the name, rarity strip at the
##   bottom edge. Options: see Kit.portrait_card.

const KitBox := preload("res://src/ui/components/kit_box.gd")
const HexBadge := preload("res://src/ui/components/hex_badge.gd")
const Deco := preload("res://src/ui/components/deco.gd")

const RATIO := 1.62

static var _foot_tex: GradientTexture2D

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
	var w: float = float(o.get("size", 158.0))
	var h := roundf(w * RATIO)
	custom_minimum_size = Vector2(w, h)
	_build(w, h)
	Kit.add_press_fx(self, face)
	var cb: Variant = o.get("on_pressed", null)
	if cb is Callable and (cb as Callable).is_valid():
		Kit._connect_pressed(self, cb)


func _build(w: float, h: float) -> void:
	var def: Dictionary = Kit._def(hero_id)
	var rarity := str(def.get("rarity", "rare"))
	var faction := str(def.get("faction", "celestial"))
	var role := str(def.get("role", "striker"))
	var rc := Kit.rarity_color(rarity)
	var entry := _owned_entry()
	var owned: bool = bool(opts.get("owned", not entry.is_empty()))
	var stars: int = int(opts.get("stars", entry.get("stars", Kit.RARITY_STARS.get(rarity, 1))))
	var level: int = int(opts.get("level", entry.get("level", 1 if owned else 0)))
	var k := w / 158.0

	face = Control.new()
	face.name = "Face"
	face.mouse_filter = MOUSE_FILTER_IGNORE
	face.size = Vector2(w, h)
	add_child(face)

	if bool(opts.get("selected", false)):
		var ring := Panel.new()
		ring.mouse_filter = MOUSE_FILTER_IGNORE
		var rb := KitBox.new()
		rb.fill = false
		rb.radius = 6
		rb.border_width = 4
		rb.border_color = Kit.ACCENT
		rb.shadow_size = 12
		rb.shadow_color = Color(Kit.ACCENT, 0.6)
		rb.shadow_offset = Vector2.ZERO
		ring.add_theme_stylebox_override("panel", rb.commit())
		ring.position = Vector2(-5, -5)
		ring.size = Vector2(w + 10, h + 10)
		face.add_child(ring)

	var clip := Panel.new()
	clip.name = "Clip"
	clip.clip_contents = true
	clip.mouse_filter = MOUSE_FILTER_IGNORE
	var bg := KitBox.new()
	bg.radius = 3
	var tint := Kit.faction_color(faction)
	bg.top_color = Color("f7f8fa")
	bg.bottom_color = Color("e4e8ec").lerp(tint, 0.12)
	bg.hatch_color = Color(0, 0, 0, 0.05)
	bg.hatch_spacing = 9.0 * k
	bg.hatch_from = 0.0
	bg.shadow_size = 6
	bg.shadow_color = Color(0, 0, 0, 0.28)
	bg.shadow_offset = Vector2(0, 3)
	clip.add_theme_stylebox_override("panel", bg.commit())
	clip.size = Vector2(w, h)
	face.add_child(clip)

	# Big faint diagonal band behind the art (studio light).
	var band := Deco.new()
	band.kind = "hatch"
	band.color = Color(tint, 0.10)
	band.spacing = 26.0 * k
	band.line_width = 10.0 * k
	band.position = Vector2(0, 0)
	band.size = Vector2(w, h * 0.7)
	clip.add_child(band)

	var art := TextureRect.new()
	art.name = "Art"
	art.mouse_filter = MOUSE_FILTER_IGNORE
	art.texture = Kit.art_crop(hero_id, w / (h * 0.94))
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	art.position = Vector2(0, h * 0.02)
	art.size = Vector2(w, h * 0.94)
	if not owned:
		art.material = Kit.grayscale_material()
	clip.add_child(art)

	# Footer: dark gradient rising from the bottom, rarity glow at the base.
	var foot := TextureRect.new()
	foot.mouse_filter = MOUSE_FILTER_IGNORE
	foot.texture = _footer()
	foot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	foot.stretch_mode = TextureRect.STRETCH_SCALE
	foot.position = Vector2(0, h * 0.56)
	foot.size = Vector2(w, h * 0.44)
	clip.add_child(foot)
	var glow := TextureRect.new()
	glow.mouse_filter = MOUSE_FILTER_IGNORE
	glow.texture = Kit.vgradient(Color(rc, 0.0), Color(rc, 0.55 if owned else 0.15))
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.position = Vector2(0, h * 0.8)
	glow.size = Vector2(w, h * 0.2)
	clip.add_child(glow)
	var strip := ColorRect.new()
	strip.mouse_filter = MOUSE_FILTER_IGNORE
	strip.color = rc if owned else Color("8a9098")
	strip.position = Vector2(0, h - maxf(4.0, 6.0 * k))
	strip.size = Vector2(w, maxf(4.0, 6.0 * k))
	clip.add_child(strip)

	# Barcode (top-right, decorative).
	var bc := Deco.new()
	bc.kind = "barcode"
	bc.color = Color(0.1, 0.11, 0.13, 0.45)
	bc.seed_value = hero_id.hash() & 0xffff
	bc.position = Vector2(w - 16.0 * k, 10.0 * k)
	bc.size = Vector2(9.0 * k, 34.0 * k)
	clip.add_child(bc)
	var bc2 := Deco.new()
	bc2.kind = "dots"
	bc2.color = Color(0.1, 0.11, 0.13, 0.4)
	bc2.position = Vector2(w - 16.0 * k, 48.0 * k)
	bc2.size = Vector2(9.0 * k, 3.0 * k)
	clip.add_child(bc2)

	# Role hex and faction hex (top-left).
	var hs := 34.0 * k
	var role_hex := HexBadge.new()
	role_hex.size = Vector2(hs, hs)
	role_hex.position = Vector2(6.0 * k, 7.0 * k)
	role_hex.fill = Color("ffffff")
	role_hex.fill_bottom = Color("e3e6ea")
	role_hex.border = Color(0.12, 0.13, 0.15, 0.85)
	role_hex.border_width = maxf(1.5, 2.0 * k)
	role_hex.set_icon("role_" + role, Color("1b1d21"), 0.52)
	clip.add_child(role_hex)
	var fac_hex := HexBadge.new()
	fac_hex.size = Vector2(hs, hs)
	fac_hex.position = Vector2(6.0 * k, 7.0 * k + hs * 0.92)
	fac_hex.fill = Color("2a2c31")
	fac_hex.fill_bottom = Color("16171a")
	fac_hex.border = Color(1, 1, 1, 0.75)
	fac_hex.border_width = maxf(1.5, 2.0 * k)
	fac_hex.set_icon("faction_" + faction, Color.WHITE, 0.6)
	clip.add_child(fac_hex)

	# Rarity chevrons + star pips (right, above the name).
	var chev := Deco.new()
	chev.kind = "chevrons"
	chev.count = {"rare": 1, "epic": 2, "legendary": 3}.get(rarity, 1)
	chev.color = rc if owned else Color("9aa0a8")
	chev.size = Vector2(46.0 * k, 34.0 * k)
	chev.position = Vector2(w - chev.size.x - 8.0 * k, h - 76.0 * k)
	clip.add_child(chev)
	if bool(opts.get("show_stars", true)):
		var pips := Deco.new()
		pips.kind = "pips"
		pips.count = maxi(stars, 1)
		pips.filled = stars
		pips.color = Color("ffd25a") if owned else Color("c3c8ce")
		pips.color2 = Color(1, 1, 1, 0.5)
		pips.size = Vector2(minf(10.0 * k * pips.count * 1.25, w * 0.5), 10.0 * k)
		pips.position = Vector2(w - pips.size.x - 8.0 * k, h - 44.0 * k)
		clip.add_child(pips)

	# Level (left) and name (right) in the footer.
	if bool(opts.get("show_level", true)) and level > 0:
		var lv := Kit.label("LV.", int(16.0 * k), Color.WHITE, "cond", 0)
		lv.position = Vector2(8.0 * k, h - 60.0 * k)
		lv.size = Vector2(40.0 * k, 18.0 * k)
		clip.add_child(lv)
		var num := Kit.label("%02d" % level, int(44.0 * k), Color.WHITE, "cond_light", 0)
		num.position = Vector2(6.0 * k, h - 48.0 * k)
		num.size = Vector2(70.0 * k, 40.0 * k)
		num.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		clip.add_child(num)
	var nm := str(def.get("name", hero_id))
	var name_l := Kit.label(nm, int(21.0 * k), Color.WHITE if owned else Color("c8ccd2"), "bold", 0)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	name_l.position = Vector2(w * 0.38, h - 34.0 * k)
	name_l.size = Vector2(w * 0.62 - 8.0 * k, 26.0 * k)
	Kit.fit_label(name_l, name_l.size.x, int(21.0 * k), int(14.0 * k))
	clip.add_child(name_l)

	if not owned and not bool(opts.get("hide_unowned_note", false)):
		var veil := ColorRect.new()
		veil.mouse_filter = MOUSE_FILTER_IGNORE
		veil.color = Color(0.92, 0.93, 0.95, 0.18)
		veil.size = Vector2(w, h)
		clip.add_child(veil)

	var locked: bool = bool(opts.get("locked", false))
	if locked or bool(opts.get("checked", false)):
		var ov := ColorRect.new()
		ov.mouse_filter = MOUSE_FILTER_IGNORE
		ov.color = Color(0.05, 0.06, 0.07, 0.62)
		ov.size = Vector2(w, h)
		clip.add_child(ov)
		var ic := Kit.icon("lock" if locked else "check", 54.0 * k, Color.WHITE if locked else Kit.ACCENT_HI)
		ic.position = Vector2((w - 54.0 * k) * 0.5, (h - 54.0 * k) * 0.42)
		ic.size = Vector2(54.0 * k, 54.0 * k)
		clip.add_child(ic)

	# Thin outer line.
	var frame := Panel.new()
	frame.mouse_filter = MOUSE_FILTER_IGNORE
	var fb := KitBox.new()
	fb.fill = false
	fb.radius = 3
	fb.border_width = 1.0
	fb.border_color = Color(0, 0, 0, 0.25)
	frame.add_theme_stylebox_override("panel", fb.commit())
	frame.size = Vector2(w, h)
	face.add_child(frame)

	if bool(opts.get("selected", false)):
		var chk := Kit.hex_badge("check", 36.0 * k, Kit.ACCENT, Color.WHITE)
		chk.position = Vector2(w - 30.0 * k, -8.0 * k)
		face.add_child(chk)

	var tag_text := str(opts.get("tag", ""))
	if tag_text == "N" or bool(opts.get("new", false)):
		var nb := Kit.new_badge(30.0 * k)
		nb.position = Vector2(w - 22.0 * k, -8.0 * k)
		face.add_child(nb)
	elif tag_text != "":
		var t := Kit.tag(tag_text, Kit.EMBER if tag_text == "BOSS" else Kit.ACCENT, Color.WHITE, int(maxf(14.0, 16.0 * k)))
		t.z_index = 2
		face.add_child(t)
		t.position = Vector2(w - t.get_combined_minimum_size().x + 4.0, -8.0 * k)

	if bool(opts.get("dot", false)):
		Kit.set_dot(self, true, maxf(16.0, 20.0 * k), Vector2(-6, -6))


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


static func _footer() -> GradientTexture2D:
	if _foot_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(0.07, 0.07, 0.08, 0.0))
		g.set_color(1, Color(0.07, 0.07, 0.08, 0.96))
		g.add_point(0.45, Color(0.07, 0.07, 0.08, 0.72))
		_foot_tex = GradientTexture2D.new()
		_foot_tex.gradient = g
		_foot_tex.fill_from = Vector2(0, 0)
		_foot_tex.fill_to = Vector2(0, 1)
		_foot_tex.width = 4
		_foot_tex.height = 128
	return _foot_tex
