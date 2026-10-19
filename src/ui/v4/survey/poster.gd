extends RefCounted
## Poster-page pieces for the screens rebuilt in the approved Lobby poster look (style v4 "Signal",
## src/ui/screens/lobby_v5_screen.gd, docs/dev/ui-style-v4.md): the paper matte, a printed poster
## panel with its shadow, dark bands with a red halftone print, giant two-tone type turned on its
## side, mono micro type, vertical menu labels with ticks, hairline rules, printed reward lines,
## echo squares and invisible hit areas (draw small, hit big). Used by the campaign, the Spire and
## the quests sheet.

const Plate := preload("res://src/ui/components/plate.gd")
const HUD := preload("res://src/ui/components/hud.gd")

const W := 720.0
const MATTE := Color("f5f4f0")
const PAPER := Color("e9e8e2")
const INK := Color("101113")
const BAND := Color("141517")
const SIGNAL := Color("ff4b1f")


## The paper matte behind everything.
static func matte(parent: Control) -> ColorRect:
	var m := ColorRect.new()
	m.color = MATTE
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(m)
	return m


## A printed poster on the matte: a soft shadow and a clipped paper panel (returned).
static func poster(parent: Control, r: Rect2) -> Control:
	var shadow := Panel.new()
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ss := StyleBoxFlat.new()
	ss.bg_color = PAPER
	ss.shadow_color = Color(0, 0, 0, 0.28)
	ss.shadow_size = 22
	ss.shadow_offset = Vector2(0, 8)
	shadow.add_theme_stylebox_override("panel", ss)
	shadow.position = r.position
	shadow.size = r.size
	parent.add_child(shadow)
	var p := Control.new()
	p.position = r.position
	p.size = r.size
	p.clip_contents = true
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(p)
	return p


static func rect(parent: Control, r: Rect2, color: Color) -> ColorRect:
	var c := ColorRect.new()
	c.color = color
	c.position = r.position
	c.size = r.size
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(c)
	return c


static func t(text: String, size: int, color: Color = INK, weight: String = "mono_bold") -> Label:
	return Kit.label(text, size, color, weight)


static func at(parent: Node, c: Control, pos: Vector2) -> Control:
	c.position = pos
	parent.add_child(c)
	return c


## A label turned 90 degrees clockwise (reads downwards), its top-left at pos.
static func vlabel(parent: Node, text: String, pos: Vector2, size: int = 12, color: Color = INK, weight: String = "mono_bold") -> Label:
	var l := t(text, size, color, weight)
	l.rotation = PI * 0.5
	l.position = pos
	parent.add_child(l)
	return l


## A hero as a halftone print (head to waist, cover-cropped) filling r. ink: the dot colour.
static func halftone_print(parent: Control, hero_id: String, r: Rect2, ink: Color = Color(1.0, 0.36, 0.16, 0.95), cell: float = 7.0, light_dots: bool = true) -> TextureRect:
	var tex := HeroArt.texture(hero_id, "")
	if tex == null:
		return null
	var face := HeroArt.portrait_region(hero_id, "")
	var at := AtlasTexture.new()
	at.atlas = tex
	var reg := Rect2(face.get_center() - Vector2(face.size.x * 0.42, face.size.y * 0.62), Vector2(face.size.x * 0.84, face.size.y * 1.9))
	at.region = reg.intersection(Rect2(Vector2.ZERO, Vector2(tex.get_size())))
	var ht := TextureRect.new()
	ht.texture = at
	ht.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ht.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ht.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	ht.position = r.position
	ht.size = r.size
	ht.material = SignalKit.halftone_material(cell, ink, light_dots)
	parent.add_child(ht)
	return ht


## Giant compressed type turned on its side (reads downwards), two-tone: paper where it crosses the
## dark band [band_x, band_x + band_w), ink elsewhere. x_top: the x of the line's top edge (the
## glyphs run to its left by about one line height). keyword: the last word in signal.
static func giant_side(p: Control, text: String, font_size: int, x_top: float, y0: float, band_x: float, band_w: float, keyword := false) -> void:
	var words := text.to_upper().split(" ")
	var bb := text.to_upper()
	if keyword and words.size() > 1:
		bb = " ".join(words.slice(0, words.size() - 1)) + " [color=#%s]%s[/color]" % [SIGNAL.to_html(false), words[words.size() - 1]]
	var sides := [[0.0, band_x, INK], [band_x, band_w, PAPER], [band_x + band_w, p.size.x - band_x - band_w, INK]]
	for side: Array in sides:
		if float(side[1]) <= 0.0:
			continue
		var clip := Control.new()
		clip.clip_contents = true
		clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip.position = Vector2(side[0], 0)
		clip.size = Vector2(side[1], p.size.y)
		p.add_child(clip)
		var rt := RichTextLabel.new()
		rt.bbcode_enabled = true
		rt.text = bb
		rt.scroll_active = false
		rt.autowrap_mode = TextServer.AUTOWRAP_OFF
		rt.add_theme_font_override("normal_font", Kit.font("compressed"))
		rt.add_theme_font_size_override("normal_font_size", font_size)
		rt.add_theme_color_override("default_color", side[2])
		rt.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rt.size = Vector2(p.size.y * 2.0, font_size * 1.3)
		rt.rotation = PI * 0.5
		rt.position = Vector2(x_top - float(side[0]), y0)
		clip.add_child(rt)


## A hairline rule.
static func hline(parent: Control, x: float, y: float, w: float, color: Color = Color(INK, 0.55), th: float = 1.0) -> ColorRect:
	return rect(parent, Rect2(x, y, w, th), color)


static func vline(parent: Control, x: float, y: float, h: float, color: Color = Color(INK, 0.55), th: float = 1.0) -> ColorRect:
	return rect(parent, Rect2(x, y, th, h), color)


## An invisible tap area (a bare Button) over r, MOUSE_FILTER_STOP. name: node name (tests).
static func hit(parent: Control, r: Rect2, on_pressed: Callable, node_name: String = "", text: String = "") -> Button:
	var b := Button.new()
	b.theme_type_variation = &"BareButton"
	b.focus_mode = Control.FOCUS_NONE
	b.flat = true
	b.position = r.position
	b.size = r.size
	if node_name != "":
		b.name = node_name
	if text != "":
		# Carries the button's words for tests and accessibility; drawn by the print around it.
		b.text = text
		for k: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color", "font_hover_pressed_color"]:
			b.add_theme_color_override(k, Color(0, 0, 0, 0))
	if on_pressed.is_valid():
		b.pressed.connect(func() -> void:
			Kit.sfx("tap")
			Kit.haptic(10)
			on_pressed.call())
	parent.add_child(b)
	return b


## Vertical menu labels along a hairline rule at x (the Lobby poster's side menu). items:
## [{text, on_pressed, active, dim, name}]; each gets a tick on the rule and an 88 px tall hit area
## reaching into the poster. Returns the hit buttons in order.
static func side_menu(p: Control, x: float, y0: float, step: float, items: Array) -> Array[Button]:
	var out: Array[Button] = []
	for i in items.size():
		var it: Dictionary = items[i]
		var y := y0 + i * step
		var active := bool(it.get("active", false))
		var dim := bool(it.get("dim", false))
		var col := SIGNAL if active else Color(INK, 0.4 if dim else 1.0)
		vlabel(p, str(it.get("text", "")), Vector2(x + 32, y), 14, col)
		rect(p, Rect2(x - 4, y + 2, 9, 1), INK)
		if active:
			var led := HUD.Led.new()
			led.size = Vector2(16, 16)
			led.position = Vector2(x + 17, y - 22)
			led.mode = "breathe"
			p.add_child(led)
		var w := maxf(step, 88.0)
		var b := hit(p, Rect2(x - 40, y - 12, 88, w), it.get("on_pressed", Callable()), str(it.get("name", "")), str(it.get("text", "")))
		out.append(b)
	return out


## The pass button (SignalKit) rotated a touch and stuck on; its hit button carries `text` (for the
## tests' "Fight" / "Claim") and the node name.
static func pass_on(parent: Control, spec: Dictionary, pos: Vector2, on_pressed: Callable, text: String, node_name: String, tilt: float = -0.035) -> Control:
	var root := SignalKit.pass_button(spec, on_pressed)
	root.position = pos
	root.rotation = tilt
	parent.add_child(root)
	var hb := root.get_child(root.get_child_count() - 1) as Button
	if hb:
		hb.name = node_name
		hb.text = text
		hb.focus_mode = Control.FOCUS_NONE
		for k: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color", "font_hover_pressed_color"]:
			hb.add_theme_color_override(k, Color(0, 0, 0, 0))
	return root


## The button inside a pass (for guide marks).
static func pass_hit(pass_root: Control) -> Button:
	return pass_root.get_child(pass_root.get_child_count() - 1) as Button


## A round inspection stamp on a silver disc (collage), optionally tappable.
static func stamp_disc(parent: Control, label: String, value: String, pos: Vector2, sz: float = 112.0, tilt: float = -0.12, on_pressed: Callable = Callable(), node_name: String = "", text: String = "") -> Control:
	var disc := SignalKit.plate("silver", pos, Vector2(sz, sz), {"circle": true, "shadow": 0.5}, parent)
	disc.add_child(SignalKit.stamp(label, value, sz))
	disc.rotation = tilt
	disc.pivot_offset = Vector2(sz, sz) * 0.5
	if on_pressed.is_valid():
		var pad := maxf(0.0, (88.0 - sz) * 0.5) + 4.0
		var b := hit(parent, Rect2(pos - Vector2(pad, pad), Vector2(sz, sz) + Vector2(pad, pad) * 2.0), on_pressed, node_name, text)
		b.button_down.connect(func() -> void: (disc as Plate).set_pressed_look(true))
		b.button_up.connect(func() -> void: (disc as Plate).set_pressed_look(false))
	return disc


## A rubber-stamp word (outlined, turned): CLEARED, BOSS, LOCKED.
static func rubber(parent: Control, text: String, pos: Vector2, color: Color = SIGNAL, size: int = 16, tilt: float = -0.08) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_color = Color(color, 0.9)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	p.add_theme_stylebox_override("panel", sb)
	p.add_child(t(text, size, Color(color, 0.95), "wide_black"))
	p.position = pos
	p.rotation = tilt
	parent.add_child(p)
	return p


## Rewards as printed entries in `cols` columns: a small icon, the amount in mono bold and a short
## name in mono. Returns a GridContainer.
static func reward_lines(reward: Dictionary, width: float, size: int = 12, color: Color = INK, cols: int = 2) -> GridContainer:
	var g := GridContainer.new()
	g.columns = cols
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.add_theme_constant_override("h_separation", 8)
	g.add_theme_constant_override("v_separation", 2)
	var cw := (width - 8.0 * (cols - 1)) / cols
	for e: Dictionary in Kit.reward_entries(reward):
		var row := Kit.hbox(5)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.custom_minimum_size.x = cw
		var kind := str(e.kind)
		var id := str(e.id)
		var name := ""
		var amount := ""
		var icon := ""
		match kind:
			"currency":
				name = {"hero_exp": "EXP", "scrolls": "SCROLL", "gems": "GEMS", "gold": "GOLD", "dust": "DUST"}.get(id, id.to_upper())
				amount = Kit.format_num(int(e.amount))
				icon = id
			"gear_drop":
				var parts := id.split(":")
				var slot := parts[0] if parts.size() > 0 else ""
				var tier := int(parts[1]) if parts.size() > 1 else 0
				name = ("%s%s" % [str(Kit.GEAR_SLOT_NAMES.get(slot, "GEAR")).to_upper(), (" T" + Kit.roman(tier)) if tier > 0 else ""])
				amount = "x%d" % int(e.amount)
				icon = "gear_" + (slot if slot != "" else "weapon")
			"hero", "shard":
				name = str(Game.hero_def(id).get("name", id)).to_upper()
				amount = "x%d" % int(e.amount)
				icon = "heroes"
			_:
				name = "GEAR"
				amount = "x%d" % int(e.amount)
				icon = "gear_weapon"
		row.add_child(Kit.icon(icon, size + 5, Color.WHITE if kind == "currency" else color))
		row.add_child(t(amount, size, color, "mono_bold"))
		var nl := t(name, size - 2, Color(color, 0.7), "mono")
		nl.clip_text = true
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(nl)
		g.add_child(row)
	return g


## Echo squares: a stage's enemies as small framed portraits (front 0-1 | back 2-4), level under
## each, BOSS in signal. units: 5 slots ({} = empty).
static func echo_strip(units: Array, sq: float = 50.0, color: Color = INK) -> HBoxContainer:
	var row := Kit.hbox(6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for s in 5:
		if s == 2:
			var sep := ColorRect.new()
			sep.color = Color(color, 0.5)
			sep.custom_minimum_size = Vector2(1, sq)
			sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(sep)
		var u: Dictionary = units[s] if s < units.size() else {}
		var v := Kit.vbox(2)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var box := Panel.new()
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.custom_minimum_size = Vector2(sq, sq)
		box.clip_contents = true
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(color, 0.06)
		sb.border_color = Color(color, 0.7) if not u.is_empty() else Color(color, 0.25)
		sb.set_border_width_all(1)
		box.add_theme_stylebox_override("panel", sb)
		if not u.is_empty():
			var hid := str(u.get("hero_id", ""))
			var crop: Variant = Kit.art_crop(hid, 1.0, 1.25)
			if crop is Texture2D:
				var tr := TextureRect.new()
				tr.texture = crop
				tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
				tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
				tr.position = Vector2(1, 1)
				tr.size = Vector2(sq - 2, sq - 2)
				box.add_child(tr)
			if bool(u.get("is_boss", false)):
				var bt := rect(box, Rect2(0, sq - 13, sq, 13), SIGNAL)
				var bl := t("BOSS", 9, Color.WHITE, "mono_bold")
				bl.position = Vector2(4, sq - 14)
				box.add_child(bl)
				bt.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(box)
		var lv := t(("LV.%d" % int(u.get("level", 1))) if not u.is_empty() else "--", 10, Color(color, 0.8), "mono")
		lv.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lv.custom_minimum_size.x = sq
		v.add_child(lv)
		row.add_child(v)
	return row


## Still paper grain over everything (add last).
static func grain(parent: Control) -> void:
	parent.add_child(SignalKit.grain(0.06, true))


## Deterministic survey coordinates for a chapter ("34°12'08\"N  118°41'22\"E").
static func coords(seed_value: int) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var la := rng.randi_range(8, 61)
	var lo := rng.randi_range(4, 170)
	return "%02d°%02d'%02d\"N  %03d°%02d'%02d\"E" % [la, rng.randi_range(0, 59), rng.randi_range(0, 59), lo, rng.randi_range(0, 59), rng.randi_range(0, 59)]


## Today's date as the posters print it ("2026 10/19") and short ("19.10.26").
static func date_long() -> String:
	var d := Time.get_date_dict_from_system()
	return "%04d %02d/%02d" % [int(d.year), int(d.month), int(d.day)]


static func date_short() -> String:
	var d := Time.get_date_dict_from_system()
	return "%02d.%02d.%02d" % [int(d.day), int(d.month), int(d.year) % 100]
