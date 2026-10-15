extends Button
## Hero card widget. Build it with Kit.hero_card(hero_id, opts); see that doc for options.
## Layout (size s): faction emblem top-left, level top-right, stars along the bottom over a
## dark shade, rarity frame with a light inner bevel, optional name caption below.

const KitBox := preload("res://src/ui/components/kit_box.gd")

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
	var rc := Kit.rarity_color(rarity)
	var entry := _owned_entry()
	var owned: bool = bool(opts.get("owned", not entry.is_empty()))
	var stars: int = int(opts.get("stars", entry.get("stars", Kit.RARITY_STARS.get(rarity, 1))))
	var level: int = int(opts.get("level", entry.get("level", 0)))
	var locked: bool = bool(opts.get("locked", false))
	var b := maxf(3.0, roundf(s * 0.028))
	var radius := b * 3.0

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
		rb.radius = radius + 5
		rb.border_width = 4
		rb.border_color = Kit.GOLD_LIGHT
		rb.shadow_size = 14
		rb.shadow_color = Color(Kit.GOLD, 0.7)
		rb.shadow_offset = Vector2.ZERO
		ring.add_theme_stylebox_override("panel", rb.commit())
		ring.position = Vector2(-6, -6)
		ring.size = Vector2(s + 12, s + 12)
		face.add_child(ring)

	# Back plate in a dark rarity gradient (shows around transparent portraits).
	var back := Panel.new()
	back.mouse_filter = MOUSE_FILTER_IGNORE
	var bb := KitBox.new()
	bb.radius = radius
	bb.top_color = rc.darkened(0.35)
	bb.bottom_color = rc.darkened(0.78)
	bb.shadow_size = 5
	bb.shadow_color = Color(0, 0, 0, 0.45)
	back.add_theme_stylebox_override("panel", bb.commit())
	back.size = Vector2(s, s)
	face.add_child(back)

	var p: Control = HeroArt.make_portrait(hero_id, s - b * 2.0)
	_ignore_mouse(p)
	p.position = Vector2(b, b)
	p.size = Vector2(s - b * 2.0, s - b * 2.0)
	if not owned:
		p.material = Kit.grayscale_material()
		_use_parent_material(p)
	face.add_child(p)

	# Bottom shade so stars / text read on any art.
	var shade := TextureRect.new()
	shade.mouse_filter = MOUSE_FILTER_IGNORE
	shade.texture = _shade()
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.position = Vector2(b, s * 0.58)
	shade.size = Vector2(s - b * 2.0, s * 0.42 - b)
	face.add_child(shade)

	# Rarity frame with inner bevel line.
	var frame := Panel.new()
	frame.mouse_filter = MOUSE_FILTER_IGNORE
	var fb := KitBox.new()
	fb.fill = false
	fb.radius = radius
	fb.border_width = int(b)
	fb.border_color = rc if owned else rc.lerp(Color("4a4560"), 0.6)
	fb.inner_color = Color(rc.lightened(0.65), 0.6 if owned else 0.25)
	fb.inner_inset = b
	fb.inner_width = 1
	if rarity == "legendary" and owned:
		fb.ornament_color = Color("fff3c4")
		fb.ornament_size = maxf(3.0, s * 0.025)
		fb.inner_inset = b + 1
	frame.add_theme_stylebox_override("panel", fb.commit())
	frame.size = Vector2(s, s)
	face.add_child(frame)

	# Faction emblem (top-left).
	if bool(opts.get("show_faction", true)) and faction != "":
		var fs := s * 0.27
		var disc := Panel.new()
		disc.mouse_filter = MOUSE_FILTER_IGNORE
		var db := KitBox.new()
		db.radius = 999
		db.top_color = Color("2a2150")
		db.bottom_color = Color("0e0a1c")
		db.border_width = 2
		db.border_color = Kit.faction_color(faction).darkened(0.1)
		disc.add_theme_stylebox_override("panel", db.commit())
		disc.position = Vector2(b + 2, b + 2)
		disc.size = Vector2(fs, fs)
		face.add_child(disc)
		var fi := Kit.faction_icon(faction, fs * 0.82)
		fi.position = disc.position + Vector2(fs * 0.09, fs * 0.09)
		fi.size = Vector2(fs * 0.82, fs * 0.82)
		face.add_child(fi)

	# Level (top-right; moves above the stars when a tag takes the corner).
	var tag_text := str(opts.get("tag", ""))
	if bool(opts.get("show_level", true)) and level > 0 and owned:
		var lv := Kit.label("Lv.%d" % level, int(maxf(16.0, s * 0.14)), Kit.INK, "black", maxi(4, int(s * 0.035)))
		lv.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		lv.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		if tag_text == "":
			lv.position = Vector2(s * 0.3, b + 1)
		else:
			lv.position = Vector2(s * 0.3, s - b - s * 0.42)
		lv.size = Vector2(s * 0.7 - b - 5, s * 0.2)
		face.add_child(lv)

	# Stars (bottom).
	if bool(opts.get("show_stars", true)) and stars > 0:
		var ss := clampf(s * 0.15, 14.0, 34.0)
		var row := Kit.star_row(stars, 0, ss)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.position = Vector2(b, s - b - ss - s * 0.025)
		row.size = Vector2(s - b * 2.0, ss)
		face.add_child(row)

	if bool(opts.get("shard", false)):
		var sh := Kit.icon("shard", s * 0.36)
		sh.position = Vector2(b + 2, s - b - s * 0.38)
		sh.size = Vector2(s * 0.36, s * 0.36)
		face.add_child(sh)

	if locked or bool(opts.get("checked", false)):
		var ov := Panel.new()
		ov.mouse_filter = MOUSE_FILTER_IGNORE
		var ob := KitBox.new()
		ob.radius = radius
		ob.top_color = Color(0.03, 0.02, 0.08, 0.62)
		ob.bottom_color = Color(0.03, 0.02, 0.08, 0.72)
		ov.add_theme_stylebox_override("panel", ob.commit())
		ov.size = Vector2(s, s)
		face.add_child(ov)
		var ic := Kit.icon("lock" if locked else "check", s * 0.4, Color.WHITE if locked else Kit.GOOD)
		ic.position = Vector2(s * 0.3, s * 0.3)
		ic.size = Vector2(s * 0.4, s * 0.4)
		face.add_child(ic)

	if tag_text != "":
		var t := Kit.tag(tag_text, Kit.GOLD if tag_text != "BOSS" else Kit.EMBER, Color("3d2306") if tag_text != "BOSS" else Color.WHITE, int(maxf(14.0, s * 0.12)))
		t.z_index = 2
		face.add_child(t)
		t.position = Vector2(s - t.get_combined_minimum_size().x - 2, -maxf(6.0, s * 0.06))

	if bool(opts.get("dot", false)):
		Kit.set_dot(self, true, maxf(18.0, s * 0.15), Vector2(-4, -4))

	if show_name:
		var n := Kit.label(str(def.get("name", hero_id)), int(maxf(16.0, s * 0.13)), Kit.INK if owned else Kit.INK_DIM, "extrabold", 0)
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
		g.set_color(0, Color(0.04, 0.02, 0.1, 0.0))
		g.set_color(1, Color(0.04, 0.02, 0.1, 0.85))
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
