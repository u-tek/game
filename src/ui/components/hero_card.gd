extends Button
## Square hero card (Kit.hero_card), style v2: head-and-shoulders portrait on a pale studio
## backdrop, role hex top-left, dark footer with "LV.12" and star pips, rarity strip along
## the bottom, optional name caption below. See Kit.hero_card for the options. The tall
## roster card is Kit.portrait_card.

const KitBox := preload("res://src/ui/components/kit_box.gd")
const HexBadge := preload("res://src/ui/components/hex_badge.gd")
const Deco := preload("res://src/ui/components/deco.gd")

static var _shade_tex: GradientTexture2D

var hero_id := ""
var opts: Dictionary = {}
var face: Control


func setup(id: String, o: Dictionary = {}) -> void:
	hero_id = id
	opts = o
	theme_type_variation = &"BareButton"
	focus_mode = FOCUS_NONE
	mouse_filter = MOUSE_FILTER_PASS
	var s: float = float(o.get("size", 152.0))
	var show_name: bool = bool(o.get("show_name", false))
	var name_h := (s * 0.15 + 8.0) if show_name else 0.0
	custom_minimum_size = Vector2(s, s + name_h)
	_build(s, show_name)
	Kit.add_press_fx(self, face)
	var cb: Variant = o.get("on_pressed", null)
	if cb is Callable and (cb as Callable).is_valid():
		Kit._connect_pressed(self, cb)


func _build(s: float, show_name: bool) -> void:
	var def: Dictionary = Kit._def(hero_id)
	var rarity := str(def.get("rarity", "rare"))
	var faction := str(def.get("faction", ""))
	var role := str(def.get("role", ""))
	var rc := Kit.rarity_color(rarity)
	var entry := _owned_entry()
	var owned: bool = bool(opts.get("owned", not entry.is_empty()))
	var stars: int = int(opts.get("stars", entry.get("stars", Kit.RARITY_STARS.get(rarity, 1))))
	var level: int = int(opts.get("level", entry.get("level", 0)))
	var locked: bool = bool(opts.get("locked", false))
	var k := s / 152.0

	face = Control.new()
	face.mouse_filter = MOUSE_FILTER_IGNORE
	face.position = Vector2.ZERO
	face.size = Vector2(s, s)
	face.custom_minimum_size = Vector2(s, s)
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
		ring.size = Vector2(s + 10, s + 10)
		face.add_child(ring)

	var clip := Panel.new()
	clip.clip_contents = true
	clip.mouse_filter = MOUSE_FILTER_IGNORE
	var bb := KitBox.new()
	bb.radius = 3
	var tint := Kit.faction_color(faction) if faction != "" else Kit.INK_DIM
	bb.top_color = Color("f6f7f9")
	bb.bottom_color = Color("dfe3e8").lerp(tint, 0.14)
	bb.hatch_color = Color(0, 0, 0, 0.05)
	bb.hatch_spacing = 8.0 * k
	bb.shadow_size = 5
	bb.shadow_color = Color(0, 0, 0, 0.3)
	bb.shadow_offset = Vector2(0, 2)
	clip.add_theme_stylebox_override("panel", bb.commit())
	clip.size = Vector2(s, s)
	face.add_child(clip)

	var p: Control = HeroArt.make_portrait(hero_id, s)
	_ignore_mouse(p)
	p.position = Vector2(0, s * 0.02)
	p.size = Vector2(s, s)
	if not owned:
		p.material = Kit.grayscale_material()
		_use_parent_material(p)
	clip.add_child(p)

	var shade := TextureRect.new()
	shade.mouse_filter = MOUSE_FILTER_IGNORE
	shade.texture = _shade()
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.position = Vector2(0, s * 0.56)
	shade.size = Vector2(s, s * 0.44)
	clip.add_child(shade)
	var glow := TextureRect.new()
	glow.mouse_filter = MOUSE_FILTER_IGNORE
	glow.texture = Kit.vgradient(Color(rc, 0.0), Color(rc, 0.5 if owned else 0.12))
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.position = Vector2(0, s * 0.78)
	glow.size = Vector2(s, s * 0.22)
	clip.add_child(glow)
	var strip := ColorRect.new()
	strip.mouse_filter = MOUSE_FILTER_IGNORE
	strip.color = rc if owned else Color("8a9098")
	var sh := maxf(3.0, 5.0 * k)
	strip.position = Vector2(0, s - sh)
	strip.size = Vector2(s, sh)
	clip.add_child(strip)

	# Role hex (top-left; the faction mark sits inside it when there is no role).
	if bool(opts.get("show_faction", true)) and (role != "" or faction != ""):
		var hs := maxf(26.0, 40.0 * k)
		var hx := HexBadge.new()
		hx.size = Vector2(hs, hs)
		hx.position = Vector2(4.0 * k, 4.0 * k)
		hx.fill = Color("1b2a47")
		hx.fill_bottom = Color("0d1527")
		hx.border = Kit.faction_color(faction).lerp(Color.WHITE, 0.25) if faction != "" else Color(1, 1, 1, 0.7)
		hx.border_width = maxf(1.5, 2.2 * k)
		if faction != "":
			hx.set_icon("faction_" + faction, Color.WHITE, 0.6)
		else:
			hx.set_icon("role_" + role, Color.WHITE, 0.52)
		clip.add_child(hx)

	# Level (bottom-left) and stars (bottom-right pips).
	var tag_text := str(opts.get("tag", ""))
	if bool(opts.get("show_level", true)) and level > 0 and owned:
		var lv := Kit.label("LV.%d" % level, int(maxf(15.0, 23.0 * k)), Color.WHITE, "cond_bold", 0)
		lv.position = Vector2(6.0 * k, s - sh - 30.0 * k)
		lv.size = Vector2(s * 0.6, 26.0 * k)
		clip.add_child(lv)
	if bool(opts.get("show_stars", true)) and stars > 0:
		var pips := Deco.new()
		pips.kind = "pips"
		pips.count = stars
		pips.filled = stars
		pips.color = Color("ffd25a") if owned else Color("c3c8ce")
		var ph := maxf(7.0, 10.0 * k)
		pips.size = Vector2(minf(ph * stars * 1.3, s * 0.5), ph)
		pips.position = Vector2(s - pips.size.x - 6.0 * k, s - sh - ph - 10.0 * k)
		clip.add_child(pips)

	if bool(opts.get("shard", false)):
		var shi := Kit.icon("shard", s * 0.34)
		shi.position = Vector2(s * 0.62, s * 0.06)
		shi.size = Vector2(s * 0.34, s * 0.34)
		clip.add_child(shi)

	if locked or bool(opts.get("checked", false)):
		var ov := ColorRect.new()
		ov.mouse_filter = MOUSE_FILTER_IGNORE
		ov.color = Color(0.05, 0.06, 0.07, 0.62)
		ov.size = Vector2(s, s)
		clip.add_child(ov)
		var ic := Kit.icon("lock" if locked else "check", s * 0.38, Color.WHITE if locked else Kit.ACCENT_HI)
		ic.position = Vector2(s * 0.31, s * 0.28)
		ic.size = Vector2(s * 0.38, s * 0.38)
		clip.add_child(ic)

	var frame := Panel.new()
	frame.mouse_filter = MOUSE_FILTER_IGNORE
	var fb := KitBox.new()
	fb.fill = false
	fb.radius = 3
	fb.border_width = 1.0
	fb.border_color = Color(0, 0, 0, 0.3)
	frame.add_theme_stylebox_override("panel", fb.commit())
	frame.size = Vector2(s, s)
	face.add_child(frame)

	if tag_text == "N" or tag_text == "NEW":
		var nb := Kit.new_badge(maxf(22.0, 30.0 * k))
		nb.position = Vector2(s - nb.size.x * 0.75, -nb.size.y * 0.3)
		face.add_child(nb)
	elif tag_text != "":
		var t := Kit.tag(tag_text, Kit.EMBER if tag_text == "BOSS" else Kit.ACCENT, Color.WHITE, int(maxf(14.0, s * 0.11)))
		t.z_index = 2
		face.add_child(t)
		t.position = Vector2(s - t.get_combined_minimum_size().x + 4.0, -maxf(6.0, s * 0.05))

	if bool(opts.get("dot", false)):
		Kit.set_dot(self, true, maxf(16.0, s * 0.13), Vector2(-4, -4))

	if show_name:
		var light: bool = bool(opts.get("light", false))
		var col := (Kit.TEXT if owned else Kit.TEXT_DIM) if light else (Kit.INK if owned else Kit.INK_DIM)
		var n := Kit.label(str(def.get("name", hero_id)), int(maxf(16.0, s * 0.14)), col, "bold", 0)
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		n.clip_text = true
		n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		n.position = Vector2(-6, s + 4)
		n.size = Vector2(s + 12, s * 0.15 + 4)
		add_child(n)


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


static func _shade() -> GradientTexture2D:
	if _shade_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(0.07, 0.07, 0.08, 0.0))
		g.set_color(1, Color(0.07, 0.07, 0.08, 0.92))
		_shade_tex = GradientTexture2D.new()
		_shade_tex.gradient = g
		_shade_tex.fill_from = Vector2(0, 0)
		_shade_tex.fill_to = Vector2(0, 1)
		_shade_tex.width = 4
		_shade_tex.height = 64
	return _shade_tex


static func _ignore_mouse(n: Node) -> void:
	if n is Control:
		(n as Control).mouse_filter = MOUSE_FILTER_IGNORE
	for c in n.get_children():
		_ignore_mouse(c)


static func _use_parent_material(n: Node) -> void:
	for c in n.get_children():
		if c is CanvasItem:
			(c as CanvasItem).use_parent_material = true
		_use_parent_material(c)
