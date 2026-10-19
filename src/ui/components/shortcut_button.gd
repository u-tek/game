extends Button
## Big lobby shortcut (Kit.shortcut), style v2: a translucent plate drawn as a slightly
## tapered quad, as if the panel were turned a little toward the centre of the screen
## (side = -1 sits on the left and its right edge is shorter; side = 1 mirrors it).
## Looks:
##   "blue"    cyan-blue glass, white glyph and text (shop-like primary destinations)
##   "white"   pale glass, dark glyph inside a thin hexagon frame, dark text
##   "orange"  dark glass with a glowing orange rim (the "go fight" call to action)
##   "dark"    deep blue glass with a cyan rim and hatching, cyan text (meters, idle)
## A sub control (meter, art strip) can sit in the lower part with set_sub(). The plate,
## glyph and text scale together on press. The orange plate's glow breathes (a separate
## layer whose alpha a looping tween drives: no per-frame redraw) and the orange and blue
## plates catch a light sweep now and then.

const KitBox := preload("res://src/ui/components/kit_box.gd")

var look := "blue"
var side := -1
## How much shorter the far edge is (fraction of the height).
var taper := 0.12
var title := ""
var icon_name := ""
## Glyph size as a fraction of the plate height (0 = no glyph).
var icon_k := 0.56
var title_size := 0

var face: Control
var _plate: Control
var _icon: TextureRect
var _label: Label
var _sub: Control
var _art: Control
var _title_tag: Control
var _t := 0.0
## Behind the plate: the orange call-to-action glow (alpha pulses).
var _glow: Control
var _shine: Control


func setup(text_: String, icon_: String, look_: String, side_: int, size_: Vector2) -> void:
	title = text_
	icon_name = icon_
	look = look_
	side = side_
	theme_type_variation = &"BareButton"
	focus_mode = FOCUS_NONE
	mouse_filter = MOUSE_FILTER_PASS
	custom_minimum_size = size_
	name = "Shortcut_" + text_.to_pascal_case()

	face = Control.new()
	face.name = "Face"
	face.mouse_filter = MOUSE_FILTER_IGNORE
	face.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(face)
	if look == "orange":
		_glow = Control.new()
		_glow.name = "Glow"
		_glow.mouse_filter = MOUSE_FILTER_IGNORE
		_glow.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		_glow.draw.connect(func() -> void:
			KitBox.soft_shadow(_glow.get_canvas_item(), quad(), Color(1.0, 0.55, 0.1, 0.5), 18.0, Vector2(0, 2)))
		face.add_child(_glow)
		_glow.modulate.a = 0.62
		_glow.ready.connect(func() -> void:
			if not Kit.motion_ok():
				return
			var tw := _glow.create_tween().set_loops()
			tw.tween_property(_glow, "modulate:a", 1.0, 1.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			tw.tween_property(_glow, "modulate:a", 0.45, 1.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT), CONNECT_ONE_SHOT)
	_plate = Control.new()
	_plate.name = "Plate"
	_plate.mouse_filter = MOUSE_FILTER_IGNORE
	_plate.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_plate.draw.connect(_draw_plate)
	face.add_child(_plate)

	if icon_name != "":
		_icon = Kit.icon(icon_name, 64.0, _fg())
		_icon.name = "Glyph"
		face.add_child(_icon)
	_label = Kit.label(title, 40, _fg(true), "extrabold", 0)
	_label.name = "Title"
	_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.0 if look == "white" else 0.45))
	_label.add_theme_constant_override("shadow_offset_y", 2)
	face.add_child(_label)
	if look == "orange" or look == "blue":
		_shine = Kit.add_shine(face, quad, 0.3 if look == "orange" else 0.22,
			Vector2(3.5, 6.0) if look == "orange" else Vector2(6.0, 10.0))
	resized.connect(_layout)
	_layout()


## Keeps the glint above anything added to the face later (meters, art, tags).
func _shine_on_top() -> void:
	if _shine and is_instance_valid(_shine):
		face.move_child(_shine, face.get_child_count() - 1)


## Puts `c` in the lower part of the plate (under the title), e.g. a Kit.percent_meter.
func set_sub(c: Control) -> void:
	if _sub and is_instance_valid(_sub):
		_sub.queue_free()
	_sub = c
	if c:
		c.mouse_filter = MOUSE_FILTER_IGNORE
		face.add_child(c)
	_shine_on_top()
	_layout()


## A small tag right after the title text (e.g. the Sanctum's level). "" removes it.
func set_title_tag(text: String) -> void:
	if text == "":
		if _title_tag and is_instance_valid(_title_tag):
			_title_tag.queue_free()
		_title_tag = null
		return
	if _title_tag == null or not is_instance_valid(_title_tag):
		_title_tag = Kit.tag(text, Color("10304f"), Color("bfe8ff"), 17)
		_title_tag.name = "TitleTag"
		face.add_child(_title_tag)
		_shine_on_top()
	else:
		(_title_tag.get_child(0) as Label).text = text
	_layout()


## A small framed art strip in the lower right (event / boss art), like a mini banner
## stuck on the plate. caption = optional tag text on it.
func set_art(tex: Texture2D, caption: String = "") -> void:
	if _art and is_instance_valid(_art):
		_art.queue_free()
	_art = null
	if tex == null:
		return
	var frame := Panel.new()
	frame.name = "ArtStrip"
	frame.mouse_filter = MOUSE_FILTER_IGNORE
	frame.clip_contents = true
	var bx := KitBox.new()
	bx.radius = 2
	bx.top_color = Color("111b30")
	bx.bottom_color = Color("080d1b")
	bx.border_width = 1.5
	bx.border_color = Color(1, 1, 1, 0.75)
	frame.add_theme_stylebox_override("panel", bx.commit())
	var tr := TextureRect.new()
	tr.texture = tex
	tr.mouse_filter = MOUSE_FILTER_IGNORE
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	tr.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	tr.offset_left = 2
	tr.offset_top = 2
	tr.offset_right = -2
	tr.offset_bottom = -2
	frame.add_child(tr)
	if caption != "":
		var t := Kit.tag(caption, Kit.ORANGE_HI, Kit.TEXT, 18)
		t.position = Vector2(4, 4)
		frame.add_child(t)
	face.add_child(frame)
	_art = frame
	_shine_on_top()
	_layout()


func _fg(text: bool = false) -> Color:
	match look:
		"white":
			return Color("1b2b48")
		"dark":
			return Color("8fd9ff") if text else Color("7fcfff")
	return Color.WHITE


func _layout() -> void:
	if face == null:
		return
	var w := size.x if size.x > 0.0 else custom_minimum_size.x
	var h := size.y if size.y > 0.0 else custom_minimum_size.y
	face.pivot_offset = Vector2(w, h) * 0.5
	var x := w * 0.06 if side < 0 else w * 0.06 + h * taper * 0.25
	if _sub:
		# Meter plates: the glyph becomes a large faint watermark on the left, the title sits
		# in the upper part and the sub control overlaps the lower left.
		var big := h * 0.86
		if _icon:
			_icon.custom_minimum_size = Vector2(big, big)
			_icon.size = Vector2(big, big)
			_icon.position = Vector2(x - 4.0, (h - big) * 0.5)
			_icon.modulate = Color(_fg(), 0.32)
		var tx := x + big * 0.62
		var fs2 := title_size if title_size > 0 else int(clampf(h * 0.24, 24.0, 42.0))
		_label.add_theme_font_size_override("font_size", fs2)
		_label.position = Vector2(tx, h * 0.04)
		_label.size = Vector2(maxf(w - tx - w * 0.05, 10.0), h * 0.42)
		Kit.fit_label(_label, _label.size.x, fs2, int(fs2 * 0.7))
		_place_title_tag(fs2)
		var ms := _sub.get_combined_minimum_size()
		_sub.size = Vector2(minf(ms.x, w * 0.86), ms.y)
		_sub.position = Vector2(w * 0.04, h - ms.y - h * 0.07)
		_plate.queue_redraw()
		if _glow:
			_glow.queue_redraw()
		return
	if _art:
		var aw := w * 0.46
		var ah := h * 0.46
		_art.size = Vector2(aw, ah)
		_art.position = Vector2(w - aw - w * 0.03, h - ah - h * 0.06)
	var body_h := h * (0.58 if _art else 1.0)
	var isz := body_h * icon_k * (1.25 if _art else 1.0)
	if _icon:
		_icon.custom_minimum_size = Vector2(isz, isz)
		_icon.size = Vector2(isz, isz)
		_icon.position = Vector2(x + (12.0 if look == "white" else 0.0), (h - isz) * 0.5 + 2.0 if not _art else h * 0.06)
		_icon.modulate = Color(_fg(), 0.5 if _art else 1.0)
		x += isz * (0.72 if _art else 1.0) + (34.0 if look == "white" else 16.0)
	var fs := title_size if title_size > 0 else int(clampf(h * 0.3, 24.0, 46.0))
	_label.add_theme_font_size_override("font_size", fs)
	_label.position = Vector2(x, 0)
	_label.size = Vector2(maxf(w - x - w * 0.05, 10.0), body_h)
	Kit.fit_label(_label, _label.size.x, fs, int(fs * 0.7))
	_place_title_tag(fs)
	_plate.queue_redraw()
	if _glow:
		_glow.queue_redraw()


func _place_title_tag(_fs: int) -> void:
	if _title_tag == null or not is_instance_valid(_title_tag):
		return
	var f := _label.get_theme_font("font")
	var used := _label.get_theme_font_size("font_size")
	var tw := f.get_string_size(_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, used).x
	var ts := _title_tag.get_combined_minimum_size()
	_title_tag.size = ts
	_title_tag.position = Vector2(_label.position.x + tw + 10.0, _label.position.y + (_label.size.y - ts.y) * 0.5 + 2.0)


## Outline of the plate in local coordinates.
func quad() -> PackedVector2Array:
	var w := _plate.size.x
	var h := _plate.size.y
	if KitBox.aero:
		# Aero: a rounded glass plate instead of the tapered tactical plate.
		return KitBox.shape_points(Rect2(0, 0, w, h), minf(h * 0.24, 30.0), 0.0, 0, 0.0, 10)
	var d := h * taper
	if side < 0:
		return PackedVector2Array([Vector2(0, 0), Vector2(w, d * 0.18), Vector2(w, h - d * 0.82), Vector2(0, h)])
	return PackedVector2Array([Vector2(0, d * 0.18), Vector2(w, 0), Vector2(w, h), Vector2(0, h - d * 0.82)])


func _draw_plate() -> void:
	var ci := _plate.get_canvas_item()
	var q := quad()
	var b := KitBox._bounds(q)
	if KitBox.aero:
		_draw_aero(ci, q, b)
		return
	match look:
		"blue":
			KitBox.soft_shadow(ci, q, Color(0, 0.1, 0.3, 0.35), 10.0, Vector2(0, 4))
			KitBox.fill_poly(ci, q, Color("1d93f2e6"), Color("0f63d6d9"), true)
			KitBox.hatch(ci, q, Color(1, 1, 1, 0.07), 9.0, 2.0, 0.55, 1.0)
			_top_glint(ci, q, Color(1, 1, 1, 0.35))
			KitBox.stroke_poly(ci, KitBox.offset_poly(q, -1.0), Color("8fd0ff"), 1.5)
		"white":
			# Pale glass (about 70% opaque): the art shows through.
			KitBox.soft_shadow(ci, q, Color(0, 0, 0, 0.22), 10.0, Vector2(0, 4))
			KitBox.fill_poly(ci, q, Color("f7f8fab8"), Color("dde1e6a3"), true)
			KitBox.hatch(ci, q, Color(0, 0, 0, 0.04), 9.0, 2.0, 0.6, 1.0)
			KitBox.stroke_poly(ci, KitBox.offset_poly(q, -1.0), Color(1, 1, 1, 0.9), 1.5)
			if _icon:
				# The glyph sits in a thin hexagon frame with a faint hatched hex behind it.
				var c := _icon.position + _icon.size * 0.5
				var hr := _icon.size.x * 0.72
				var back := KitBox.hex_points(c, hr)
				KitBox.fill_poly(ci, back, Color(1, 1, 1, 0.35), Color(1, 1, 1, 0.12))
				KitBox.hatch(ci, back, Color(0, 0, 0, 0.06), 6.0, 1.5, 0.0, 1.0)
				KitBox.stroke_poly(ci, back, Color("1b2b48"), 2.5)
				KitBox.stroke_poly(ci, KitBox.hex_points(c, hr + 7.0), Color(0.16, 0.18, 0.2, 0.25), 1.0)
			_ticks(ci, q, Color(0, 0, 0, 0.3))
		"orange":
			var k := 0.5 + 0.5 * sin(_t * 2.6)
			KitBox.soft_shadow(ci, q, Color(1.0, 0.55, 0.1, 0.32 + 0.18 * k), 16.0)
			KitBox.fill_poly(ci, q, Color("2a1a0abf"), Color("1a1006a6"), true)
			KitBox.hatch(ci, q, Color(1.0, 0.6, 0.2, 0.12), 10.0, 2.0, 0.0, 1.0)
			KitBox.stroke_poly(ci, KitBox.offset_poly(q, -1.5), Color("ffa43a"), 3.0)
			KitBox.stroke_poly(ci, KitBox.offset_poly(q, -6.0), Color(1.0, 0.75, 0.4, 0.3), 1.0)
		"dark":
			# Deep blue glass (about 55-60% opaque).
			KitBox.soft_shadow(ci, q, Color(0, 0, 0, 0.24), 8.0, Vector2(0, 3))
			KitBox.fill_poly(ci, q, Color("0b2b4f9e"), Color("061a338c"), true)
			KitBox.hatch(ci, q, Color(0.4, 0.75, 1.0, 0.13), 8.0, 2.0, 0.0, 1.0)
			KitBox.stroke_poly(ci, KitBox.offset_poly(q, -1.0), Color("3aa0ff"), 2.0)
			_ticks(ci, q, Color("3aa0ff"))
	# Short bright bar along the top edge (the "technical" mark).
	var y0 := q[0].y if side < 0 else q[1].y
	var x0 := b.position.x + b.size.x * (0.06 if side < 0 else 0.7)
	if look != "white":
		_plate.draw_rect(Rect2(x0, y0 + 1.0, b.size.x * 0.24, 3.0), Color(1, 1, 1, 0.55) if look != "orange" else Color("ffd08a"))


## Aero Y2K plate: glossy glass in the look's colour, a white highlight on the upper half, a chrome rim
## and, for the white plate, a round glass bubble behind the glyph.
func _draw_aero(ci: RID, q: PackedVector2Array, b: Rect2) -> void:
	var top: Color
	var bot: Color
	var rim: Color
	var glow := Color(0, 0, 0, 0.26)
	match look:
		"blue":
			top = Color("2fd6f2ee")
			bot = Color("0a86c2e0")
			rim = Color("b9f6ff")
		"white":
			top = Color("ffffffcc")
			bot = Color("d8eef6b0")
			rim = Color(1, 1, 1, 0.95)
		"orange":
			# Its glow is the separate breathing layer behind the plate.
			top = Color("ffb04ee8")
			bot = Color("e8641ad8")
			rim = Color("ffe2b0")
			glow = Color(0, 0, 0, 0)
		_:
			top = Color("1c5a86b0")
			bot = Color("0a2a48a0")
			rim = Color("7fe8ff")
	if glow.a > 0.0:
		KitBox.soft_shadow(ci, q, glow, 9.0, Vector2(0, 4))
	KitBox.fill_poly(ci, q, top, bot, false)
	# Gloss: the upper ~45% of the plate gets a soft white highlight (the Frutiger Aero "jelly").
	var gl := Rect2(b.position + Vector2(6, 4), Vector2(b.size.x - 12, b.size.y * 0.46))
	if gl.size.x > 8 and gl.size.y > 4:
		var gp := KitBox.shape_points(gl, minf(gl.size.y * 0.5, 22.0), 0.0, 0, 0.0, 8)
		var cols := PackedColorArray()
		for p in gp:
			var t := clampf((p.y - gl.position.y) / gl.size.y, 0.0, 1.0)
			cols.append(Color(1, 1, 1, (0.42 if look != "white" else 0.6) * (1.0 - t)))
		KitBox._fan(ci, gp, cols, gl.get_center(), Color(1, 1, 1, 0.18))
	KitBox.stroke_poly(ci, KitBox.offset_poly(q, -1.0), rim, 2.0)
	if look == "white" and _icon:
		var c := _icon.position + _icon.size * 0.5
		var hr := _icon.size.x * 0.7
		var bubble := KitBox.hex_points(c, hr)
		KitBox.fill_poly(ci, bubble, Color("e9fbff"), Color("9fdcec"))
		KitBox.stroke_poly(ci, bubble, Color("5cc9e6"), 2.0)


func _top_glint(ci: RID, q: PackedVector2Array, col: Color) -> void:
	RenderingServer.canvas_item_add_line(ci, q[0] + Vector2(6, 2), q[1] + Vector2(-6, 2), col, 1.0, true)


## Two tiny double ticks near the right corners (decoration).
func _ticks(ci: RID, q: PackedVector2Array, col: Color) -> void:
	var tr := q[1]
	var br := q[2]
	for p: Vector2 in [tr + Vector2(-14, 10), br + Vector2(-14, -22)]:
		RenderingServer.canvas_item_add_rect(ci, Rect2(p, Vector2(2, 10)), col)
		RenderingServer.canvas_item_add_rect(ci, Rect2(p + Vector2(5, 0), Vector2(2, 10)), col)
