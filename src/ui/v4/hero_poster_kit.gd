extends RefCounted
## Poster pieces for the style v4 screens that keep the look of the approved Lobby poster (lobby_v5;
## owner, 2026-10-19: "i want that visual style to be maintained throughout the UI"): the paper matte,
## printed poster panels with a soft drop shadow, dark bands carrying a red halftone print of a hero,
## giant compressed type turned on its side (two-tone where it crosses a band), mono micro type,
## hairline rules with tick labels, signatures, star pips, framed pixel squares, a soft red echo of a
## hero and the pass (SignalKit.pass_button's look with text that can change and an optional knob
## button). Used by the hero dossier, the roster catalogue and the team poster.
## (A sibling of poster_kit.gd, which the summon, shop and gear screens use; both were built in parallel
## and are to be merged into SignalKit.)
##   const PK := preload("res://src/ui/v4/hero_poster_kit.gd")

const Plate := preload("res://src/ui/components/plate.gd")
const MOSAIC := preload("res://src/ui/v4/pixel_mosaic.gdshader")
const ECHO := preload("res://src/ui/v4/soft_echo.gdshader")

const MATTE := Color("f5f4f0")
const PAPER := Color("e9e8e2")
const INK := Color("101113")
const BAND := Color("141517")
const SIG := Color("ff4b1f")
## Red halftone ink on the dark bands (the Lobby poster's print).
const PRINT := Color(1.0, 0.36, 0.16, 0.95)
## Engraved ink on silver.
const ETCH := Color("131416")


static func t(text: String, size: int, color: Color = INK, weight: String = "mono") -> Label:
	return Kit.label(text, size, color, weight)


static func at(parent: Node, c: Control, pos: Vector2) -> Control:
	c.position = pos
	parent.add_child(c)
	return c


## The paper matte under a whole screen.
static func matte(parent: Node) -> ColorRect:
	var m := ColorRect.new()
	m.name = "Matte"
	m.color = MATTE
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(m)
	return m


## A printed poster at `rect` (paper, soft drop shadow on the matte). Returns the clipped poster
## Control to build in, in its own coordinates.
static func poster(parent: Node, rect: Rect2, shadow: int = 22, paper: Color = PAPER) -> Control:
	var sh := Panel.new()
	sh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ss := StyleBoxFlat.new()
	ss.bg_color = paper
	ss.shadow_color = Color(0, 0, 0, 0.28)
	ss.shadow_size = shadow
	ss.shadow_offset = Vector2(0, roundf(shadow * 0.36))
	sh.add_theme_stylebox_override("panel", ss)
	sh.position = rect.position
	sh.size = rect.size
	parent.add_child(sh)
	var p := Control.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.clip_contents = true
	p.position = rect.position
	p.size = rect.size
	parent.add_child(p)
	return p


static func rect(parent: Node, r: Rect2, color: Color) -> ColorRect:
	var c := ColorRect.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.color = color
	c.position = r.position
	c.size = r.size
	parent.add_child(c)
	return c


## A hairline (1 px unless size says otherwise).
static func rule(parent: Node, pos: Vector2, size: Vector2, color: Color = Color(INK, 0.55)) -> ColorRect:
	return rect(parent, Rect2(pos, size), color)


## Mono micro type turned clockwise (reads downwards), like the Lobby poster's side labels. Its
## position is the top-right corner of the turned text.
static func vlabel(text: String, size: int, color: Color = INK, weight: String = "mono_bold") -> Label:
	var l := t(text, size, color, weight)
	l.rotation = PI * 0.5
	return l


## The red halftone print of a hero for a dark band: head to waist, cover-cropped into `size`.
static func halftone_print(hero_id: String, skin: String, size: Vector2, cell: float = 7.0, ink: Color = PRINT, zoom: float = 1.0) -> TextureRect:
	var ht := TextureRect.new()
	ht.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ht.size = size
	var tex := HeroArt.texture(hero_id, skin)
	if tex == null:
		return ht
	var face := HeroArt.portrait_region(hero_id, skin)
	var at_tex := AtlasTexture.new()
	at_tex.atlas = tex
	var half := Vector2(face.size.x * 0.42, face.size.y * 0.62) / maxf(zoom, 0.1)
	var reg := Rect2(face.get_center() - half, Vector2(half.x * 2.0, face.size.y * 1.9 / maxf(zoom, 0.1)))
	at_tex.region = reg.intersection(Rect2(Vector2.ZERO, Vector2(tex.get_size())))
	ht.texture = at_tex
	ht.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ht.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	ht.material = SignalKit.halftone_material(cell, ink, true)
	return ht


## A soft, out-of-focus red copy of a hero's full art (the Lobby poster's echo), `height` px tall,
## feet at the bottom of the rect.
static func echo(hero_id: String, skin: String, height: float, alpha: float = 0.38) -> TextureRect:
	var e := TextureRect.new()
	e.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tex := HeroArt.texture(hero_id, skin)
	e.texture = tex
	e.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	e.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	var asp := 0.5
	if tex:
		asp = float(tex.get_width()) / maxf(float(tex.get_height()), 1.0)
	e.size = Vector2(height * asp, height)
	var m := ShaderMaterial.new()
	m.shader = ECHO
	m.set_shader_parameter("tint", Color(1.0, 0.3, 0.12, alpha))
	m.set_shader_parameter("lod", 6.5)
	e.material = m
	return e


## Giant type turned clockwise (reads downwards), drawn once per region in that region's ink and
## clipped to it, so it changes colour where it crosses a band (the Lobby poster's trick).
## regions: [[Rect2, Color], ...] in `parent` coordinates. bb: BBCode (a [color] keyword keeps its
## colour in every copy). pos: where the turned block's top-right corner sits; block: the block's
## size before turning (width = its length down the poster). turned false: set level, pos = its
## top-left corner.
static func giant(parent: Control, bb: String, font_size: int, pos: Vector2, block: Vector2, regions: Array,
		line_sep: int = -14, weight: String = "compressed", turned: bool = true) -> void:
	for r: Array in regions:
		var rr: Rect2 = r[0]
		var clip := Control.new()
		clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip.clip_contents = true
		clip.position = rr.position
		clip.size = rr.size
		parent.add_child(clip)
		var rt := RichTextLabel.new()
		rt.bbcode_enabled = true
		rt.text = bb
		rt.fit_content = false
		rt.scroll_active = false
		rt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rt.add_theme_font_override("normal_font", Kit.font(weight))
		rt.add_theme_font_size_override("normal_font_size", font_size)
		rt.add_theme_color_override("default_color", r[1])
		rt.add_theme_constant_override("line_separation", line_sep)
		rt.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rt.size = block
		rt.rotation = PI * 0.5 if turned else 0.0
		rt.position = pos - rr.position
		clip.add_child(rt)


## Width of `text` in a font at a size (for fitting giant type).
static func text_w(text: String, size: int, weight: String = "compressed") -> float:
	return Kit.font(weight).get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


## A framed pixel square: a crop of the hero's art (`focus` "face" | "chest" | "hips") as a mosaic of
## flat cells inside a hairline frame with a small solid tab at one corner.
static func pixel_square(hero_id: String, skin: String, focus: String, side: float, cells: int = 8,
		frame: Color = INK) -> Control:
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.size = Vector2(side, side)
	root.custom_minimum_size = root.size
	var tex := HeroArt.texture(hero_id, skin)
	if tex:
		var face := HeroArt.portrait_region(hero_id, skin)
		var ts := Vector2(tex.get_size())
		var c := face.get_center()
		var s := face.size.x * 0.7
		match focus:
			"chest":
				c += Vector2(0, face.size.y * 0.95)
				s = face.size.x * 0.8
			"hips":
				c += Vector2(0, face.size.y * 2.1)
				s = face.size.x * 0.9
		var reg := Rect2(c - Vector2(s, s) * 0.5, Vector2(s, s))
		reg.position = reg.position.clamp(Vector2.ZERO, (ts - reg.size).max(Vector2.ZERO))
		var tr := TextureRect.new()
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		tr.position = Vector2(4, 4)
		tr.size = Vector2(side - 8, side - 8)
		var m := ShaderMaterial.new()
		m.shader = MOSAIC
		m.set_shader_parameter("region", Vector4(reg.position.x / ts.x, reg.position.y / ts.y, reg.size.x / ts.x, reg.size.y / ts.y))
		m.set_shader_parameter("cells", float(cells))
		m.set_shader_parameter("lod", clampf(log(s / cells) / log(2.0) - 0.5, 0.0, 8.0))
		tr.material = m
		root.add_child(tr)
	var f := Frame.new()
	f.color = frame
	f.size = root.size
	root.add_child(f)
	return root


## The pass for a screen's main action (the OG-pass look of SignalKit.pass_button) whose text can
## change: set_text(), set_knob(), set_live(). knob_button: the round knob is its own button
## (knob_hit), e.g. MAX on the Level Up pass.
static func make_pass(width: float, icon_name: String = "flag", knob_button: bool = false, code: bool = true) -> Pass:
	var p := Pass.new()
	p.build(width, icon_name, knob_button, code)
	return p


## Text cut into silver (light lip below, dark wall above). set_etch() changes it.
static func etch(text: String, size: int, weight: String = "mono_bold", fill: Color = ETCH) -> Control:
	var box := Control.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for layer: Array in [[Color(1, 1, 1, 0.7), Vector2(0, 1)], [Color(0, 0, 0, 0.45), Vector2(0, -1)], [fill, Vector2.ZERO]]:
		var l := Kit.label(text, size, layer[0], weight)
		l.position = layer[1]
		box.add_child(l)
	box.size = (box.get_child(2) as Label).get_minimum_size()
	return box


static func set_etch(box: Control, text: String, fill: Color = ETCH) -> void:
	for i in box.get_child_count():
		var l := box.get_child(i) as Label
		l.text = text
		if i == 2:
			l.add_theme_color_override("font_color", fill)
		l.size = l.get_minimum_size()
	box.size = (box.get_child(2) as Label).get_minimum_size()


## Film grain over a screen (still, like ink on stock); add it last.
static func grain(parent: Node, amount: float = 0.06) -> void:
	parent.add_child(SignalKit.grain(amount, true))


## A hairline frame with a small solid tab on its top-right corner (the dossier's pixel squares).
class Frame:
	extends Control
	var color := Color("101113")
	var tab := 7.0

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), color, false, 1.5)
		draw_rect(Rect2(Vector2(size.x - tab * 0.5, -tab * 0.5), Vector2(tab, tab)), color)


## Star pips: `filled` of `count`, five-pointed, ink.
class Stars:
	extends Control
	var count := 6
	var filled := 3
	var color := Color("101113")
	var empty := Color(0.06, 0.07, 0.08, 0.3)
	var gap := 3.0

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE

	func _get_minimum_size() -> Vector2:
		var d := size.y if size.y > 0.0 else 14.0
		return Vector2(count * d + (count - 1) * gap, d)

	func _draw() -> void:
		var d := size.y
		for i in count:
			var c := Vector2(i * (d + gap) + d * 0.5, d * 0.52)
			var pts := PackedVector2Array()
			for k in 10:
				var r := d * (0.5 if k % 2 == 0 else 0.21)
				var a := -PI * 0.5 + k * PI / 5.0
				pts.append(c + Vector2(cos(a), sin(a)) * r)
			if i < filled:
				draw_colored_polygon(pts, color)
			else:
				pts.append(pts[0])
				draw_polyline(pts, empty, 1.2, true)


## A thin printed chevron (browse arrows): points left when dir < 0.
class Chevron:
	extends Control
	var color := Color("101113")
	var dir := 1
	var width := 2.0

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var a := Vector2(w * 0.3, h * 0.1)
		var b := Vector2(w * 0.7, h * 0.5)
		var c := Vector2(w * 0.3, h * 0.9)
		if dir < 0:
			a.x = w - a.x
			b.x = w - b.x
			c.x = w - c.x
		draw_polyline(PackedVector2Array([a, b, c]), color, width, true)


## A long thin printed arrow pointing left (the dossier's back arrow).
class Arrow:
	extends Control
	var color := Color("101113")
	var width := 2.0

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var y := size.y * 0.5
		draw_line(Vector2(2, y), Vector2(size.x, y), color, width, true)
		draw_polyline(PackedVector2Array([Vector2(size.y * 0.5 + 2, 2), Vector2(2, y), Vector2(size.y * 0.5 + 2, size.y - 2)]), color, width, true)


## The pass (see make_pass): a brushed silver plate (matrix code, kicker, title, sub line, a machined
## knob) over a glowing signal plate (an outlined action pill and an info line). Both sink on press.
class Pass:
	extends Control
	var w := 400.0
	var hit: Button
	var knob_hit: Button
	var silver: Control
	var sig: Control
	var knob: Control
	var _kick: Control
	var _title: Control
	var _sub: Control
	var _pill: PanelContainer
	var _pill_l: Label
	var _info: Label
	var _knob_top: Label
	var _knob_bot: Label

	func build(width: float, icon_name: String, knob_button: bool, code: bool) -> void:
		w = width
		mouse_filter = MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(w, 176)
		size = custom_minimum_size
		sig = SignalKit.plate("signal", Vector2(8, 78), Vector2(w - 14, 96), {"cuts": [0, 12, 18, 0], "glow": 0.4,
			"glow_radius": 14.0, "pulse": 0.5, "topo": 0.6}, self)
		var top_sz := Vector2(w, 94)
		silver = SignalKit.plate("silver", Vector2.ZERO, top_sz, {"shape": Plate.tab_bottom(top_sz, 14, w * 0.33, w * 0.65, 14),
			"topo": 0.5, "screws": [Vector2(13, 13), Vector2(w - 13, 13), Vector2(13, 66), Vector2(w - 13, 66)]}, self)
		silver.z_index = 1
		var x := 26.0
		if code:
			var m := SignalKit.matrix(Vector2(58, 58))
			m.position = Vector2(26, 13)
			silver.add_child(m)
			x = 98.0
		_kick = _etch_box("", 10, "mono_bold")
		_kick.position = Vector2(x, 12)
		silver.add_child(_kick)
		_title = _etch_box("", 30, "wide_black")
		_title.position = Vector2(x - 2, 26)
		silver.add_child(_title)
		_sub = _etch_box("", 10, "mono")
		_sub.position = Vector2(x, 66)
		silver.add_child(_sub)
		knob = SignalKit.plate("dial", Vector2(w - 82, 20), Vector2(50, 50), {"circle": true, "shadow": 0.5}, silver)
		if knob_button:
			_knob_top = Kit.label("", 12, Color(1, 1, 1, 0.95), "mono_bold")
			_knob_bot = Kit.label("", 10, Color("ffb08f"), "mono_bold")
			for l: Label in [_knob_top, _knob_bot]:
				l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				l.size = Vector2(50, 14)
				knob.add_child(l)
			_knob_top.position = Vector2(0, 11)
			_knob_bot.position = Vector2(0, 25)
		else:
			var ic := Kit.icon(icon_name, 22, Color(1, 1, 1, 0.95))
			ic.position = Vector2(14, 14)
			knob.add_child(ic)
		_pill = SignalKit.pill("", 20)
		_pill_l = _pill.get_child(0) as Label
		_pill.position = Vector2(18, 32)
		sig.add_child(_pill)
		_info = Kit.label("", 10, Color(1, 1, 1, 0.85), "mono")
		_info.position = Vector2(w * 0.56, 44)
		sig.add_child(_info)
		hit = Button.new()
		hit.name = "PassHit"
		hit.theme_type_variation = &"BareButton"
		hit.focus_mode = FOCUS_NONE
		hit.mouse_filter = MOUSE_FILTER_PASS
		hit.z_index = 2
		hit.position = Vector2(-4, -4)
		hit.size = Vector2(w + 8, 184)
		hit.button_down.connect(func() -> void:
			hit.set_meta("_down_at", hit.get_global_mouse_position())
			if not hit.disabled:
				_press(true)
				Kit.haptic(12))
		hit.button_up.connect(func() -> void: _press(false))
		hit.gui_input.connect(func(ev: InputEvent) -> void:
			var mb := ev as InputEventMouseButton
			if hit.disabled and mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				Kit.deny(self))
		add_child(hit)
		if knob_button:
			knob_hit = Button.new()
			knob_hit.name = "KnobHit"
			knob_hit.theme_type_variation = &"BareButton"
			knob_hit.focus_mode = FOCUS_NONE
			knob_hit.mouse_filter = MOUSE_FILTER_PASS
			knob_hit.z_index = 3
			knob_hit.size = Vector2(88, 88)
			knob_hit.position = Vector2(w - 57 - 44, 45 - 44)
			knob_hit.button_down.connect(func() -> void:
				knob_hit.set_meta("_down_at", knob_hit.get_global_mouse_position())
				if not knob_hit.disabled:
					(knob as Plate).set_pressed_look(true)
					Kit.haptic(12))
			knob_hit.button_up.connect(func() -> void: (knob as Plate).set_pressed_look(false))
			knob_hit.gui_input.connect(func(ev: InputEvent) -> void:
				var mb := ev as InputEventMouseButton
				if knob_hit.disabled and mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
					Kit.deny(knob))
			add_child(knob_hit)

	func _press(down: bool) -> void:
		(silver as Plate).set_pressed_look(down)
		(sig as Plate).set_pressed_look(down)

	func set_text(kicker: String, title: String, sub: String, action: String, info: String = "", sub_fill: Color = Color("131416")) -> void:
		_put_etch(_kick, kicker)
		_put_etch(_title, title)
		_put_etch(_sub, sub, sub_fill)
		_pill_l.text = action
		_info.text = info
		# The title shrinks to fit left of the knob.
		var room := w - _title.position.x - 92.0
		var tl := _title.get_child(2) as Label
		if tl.get_minimum_size().x > room:
			var k := room / maxf(tl.get_minimum_size().x, 1.0)
			_title.scale = Vector2(k, k)
			_title.position.y = 26 + (1.0 - k) * 18.0
		else:
			_title.scale = Vector2.ONE
			_title.position.y = 26

	func set_knob(top: String, bottom: String, on: bool) -> void:
		if _knob_top:
			_knob_top.text = top
			_knob_bot.text = bottom
		if knob_hit:
			knob_hit.disabled = not on
		knob.modulate = Color(1, 1, 1, 1.0 if on else 0.55)

	## Live (pressable) or spent: a spent pass greys its signal plate and refuses taps.
	func set_live(on: bool) -> void:
		hit.disabled = not on
		sig.modulate = Color.WHITE if on else Color(0.55, 0.55, 0.55, 1.0)

	static func _etch_box(text: String, size: int, weight: String) -> Control:
		var box := Control.new()
		box.mouse_filter = MOUSE_FILTER_IGNORE
		for layer: Array in [[Color(1, 1, 1, 0.7), Vector2(0, 1)], [Color(0, 0, 0, 0.45), Vector2(0, -1)], [Color("131416"), Vector2.ZERO]]:
			var l := Kit.label(text, size, layer[0], weight)
			l.position = layer[1]
			box.add_child(l)
		return box

	static func _put_etch(box: Control, text: String, fill: Color = Color("131416")) -> void:
		for i in box.get_child_count():
			var l := box.get_child(i) as Label
			l.text = text
			if i == 2:
				l.add_theme_color_override("font_color", fill)
			l.size = l.get_minimum_size()
		box.size = (box.get_child(2) as Label).get_minimum_size()


## The Level Up control as an arcade push button (owner, 2026-10-19: not every button the same
## pass): a signal cap in a machined silver bezel beside a silver plate with the etched readouts and
## the MAX knob. Same interface as Pass (hit, knob_hit, set_text, set_knob, set_live).
class PressPass:
	extends Pass
	var _cap_ic: Control
	var _act: Label

	func build(width: float, _icon_name: String = "upgrade", knob_button: bool = true, _code: bool = false) -> void:
		w = width
		mouse_filter = MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(w, 176)
		size = custom_minimum_size
		silver = SignalKit.plate("silver", Vector2(60, 36), Vector2(w - 60, 128), {"cuts": [0, 16, 16, 0], "topo": 0.5,
			"screws": [Vector2(w - 74, 14), Vector2(w - 74, 114)]}, self)
		# The cap sits under the bezel ring; the ring's hole shows it.
		sig = SignalKit.plate("signal", Vector2(22, 38), Vector2(124, 124), {"circle": true, "glow": 0.35, "glow_radius": 12.0,
			"pulse": 0.6, "shadow": 0.0}, self)
		var bezel := SignalKit.plate("silver", Vector2(6, 22), Vector2(156, 156), {"circle": true, "shadow": 0.55,
			"hole": Vector3(78, 78, 56), "topo": 0.4}, self)
		bezel.name = "Bezel"
		_cap_ic = Kit.icon("upgrade", 44, Color(1, 1, 1, 0.96))
		_cap_ic.position = Vector2(40, 30)
		_cap_ic.size = Vector2(44, 44)
		sig.add_child(_cap_ic)
		var x := 116.0
		_kick = Pass._etch_box("", 10, "mono_bold")
		_kick.position = Vector2(x, 12)
		silver.add_child(_kick)
		_title = Pass._etch_box("", 28, "wide_black")
		_title.position = Vector2(x - 2, 26)
		silver.add_child(_title)
		_sub = Pass._etch_box("", 10, "mono")
		_sub.position = Vector2(x, 64)
		silver.add_child(_sub)
		_act = Kit.label("", 12, Color("ff4b1f"), "mono_bold")
		_act.position = Vector2(x, 84)
		silver.add_child(_act)
		_info = Kit.label("", 10, Color("131416"), "mono")
		_info.position = Vector2(x, 102)
		silver.add_child(_info)
		knob = SignalKit.plate("dial", Vector2(w - 60 - 70, 20), Vector2(54, 54), {"circle": true, "shadow": 0.5}, silver)
		if knob_button:
			_knob_top = Kit.label("", 12, Color(1, 1, 1, 0.95), "mono_bold")
			_knob_bot = Kit.label("", 10, Color("ffb08f"), "mono_bold")
			for l: Label in [_knob_top, _knob_bot]:
				l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				l.size = Vector2(54, 14)
				knob.add_child(l)
			_knob_top.position = Vector2(0, 13)
			_knob_bot.position = Vector2(0, 27)
		hit = Button.new()
		hit.name = "PassHit"
		hit.theme_type_variation = &"BareButton"
		hit.focus_mode = FOCUS_NONE
		hit.mouse_filter = MOUSE_FILTER_PASS
		hit.position = Vector2(-4, 10)
		hit.size = Vector2(w + 8, 170)
		hit.button_down.connect(func() -> void:
			hit.set_meta("_down_at", hit.get_global_mouse_position())
			if not hit.disabled:
				_press(true)
				Kit.haptic(14))
		hit.button_up.connect(func() -> void: _press(false))
		hit.gui_input.connect(func(ev: InputEvent) -> void:
			var mb := ev as InputEventMouseButton
			if hit.disabled and mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				Kit.deny(self))
		add_child(hit)
		if knob_button:
			knob_hit = Button.new()
			knob_hit.name = "KnobHit"
			knob_hit.theme_type_variation = &"BareButton"
			knob_hit.focus_mode = FOCUS_NONE
			knob_hit.mouse_filter = MOUSE_FILTER_PASS
			knob_hit.size = Vector2(96, 96)
			knob_hit.position = Vector2(w - 70 - 21, 36 + 47 - 48)
			knob_hit.button_down.connect(func() -> void:
				if not knob_hit.disabled:
					(knob as Plate).set_pressed_look(true)
					Kit.haptic(12))
			knob_hit.button_up.connect(func() -> void: (knob as Plate).set_pressed_look(false))
			knob_hit.gui_input.connect(func(ev: InputEvent) -> void:
				var mb := ev as InputEventMouseButton
				if knob_hit.disabled and mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
					Kit.deny(knob))
			add_child(knob_hit)

	func _press(down: bool) -> void:
		# Only the cap goes down, deep, like a real arcade button.
		(sig as Plate).set_pressed_look(down)
		sig.scale = Vector2(0.94, 0.94) if down else Vector2.ONE
		sig.pivot_offset = sig.size * 0.5

	func set_text(kicker: String, title: String, sub: String, action: String, info: String = "", sub_fill: Color = Color("131416")) -> void:
		Pass._put_etch(_kick, kicker)
		Pass._put_etch(_title, title)
		Pass._put_etch(_sub, sub, sub_fill)
		_act.text = action.replace(">>>", "").strip_edges()
		_info.text = info
		var room := w - 60.0 - _title.position.x - 84.0
		var tl := _title.get_child(2) as Label
		if tl.get_minimum_size().x > room:
			var k := room / maxf(tl.get_minimum_size().x, 1.0)
			_title.scale = Vector2(k, k)
			_title.position.y = 26 + (1.0 - k) * 16.0
		else:
			_title.scale = Vector2.ONE
			_title.position.y = 26


static func make_press(width: float) -> PressPass:
	var p := PressPass.new()
	p.build(width)
	return p
