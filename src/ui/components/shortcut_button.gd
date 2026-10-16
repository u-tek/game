extends Button
## Big lobby shortcut (Kit.shortcut), style v2: a translucent plate drawn as a slightly
## tapered quad, as if the panel were turned a little toward the centre of the screen
## (side = -1 sits on the left and its right edge is shorter; side = 1 mirrors it).
## Looks:
##   "blue"    cyan-blue glass, white glyph and text (shop-like primary destinations)
##   "white"   pale glass, dark glyph inside thin corner brackets, dark text
##   "orange"  dark glass with a glowing orange rim (the "go fight" call to action)
##   "dark"    deep blue glass with a cyan rim and hatching, cyan text (meters, idle)
## A sub control (meter, art strip) can sit in the lower part with set_sub(). The plate,
## glyph and text scale together on press.

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
var _t := 0.0


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
	resized.connect(_layout)
	_layout()


## Puts `c` in the lower part of the plate (under the title), e.g. a Kit.percent_meter.
func set_sub(c: Control) -> void:
	if _sub and is_instance_valid(_sub):
		_sub.queue_free()
	_sub = c
	if c:
		c.mouse_filter = MOUSE_FILTER_IGNORE
		face.add_child(c)
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
	bx.top_color = Color("1a1c21")
	bx.bottom_color = Color("0d0e11")
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
	_layout()


func _fg(text: bool = false) -> Color:
	match look:
		"white":
			return Color("2a2d33")
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
		var ms := _sub.get_combined_minimum_size()
		_sub.size = Vector2(minf(ms.x, w * 0.86), ms.y)
		_sub.position = Vector2(w * 0.04, h - ms.y - h * 0.07)
		_plate.queue_redraw()
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
	_plate.queue_redraw()


## Outline of the plate in local coordinates.
func quad() -> PackedVector2Array:
	var w := _plate.size.x
	var h := _plate.size.y
	var d := h * taper
	if side < 0:
		return PackedVector2Array([Vector2(0, 0), Vector2(w, d * 0.18), Vector2(w, h - d * 0.82), Vector2(0, h)])
	return PackedVector2Array([Vector2(0, d * 0.18), Vector2(w, 0), Vector2(w, h), Vector2(0, h - d * 0.82)])


func _process(delta: float) -> void:
	if look == "orange" and is_visible_in_tree():
		_t += delta
		_plate.queue_redraw()


func _draw_plate() -> void:
	var ci := _plate.get_canvas_item()
	var q := quad()
	var b := KitBox._bounds(q)
	match look:
		"blue":
			KitBox.soft_shadow(ci, q, Color(0, 0.1, 0.3, 0.35), 10.0, Vector2(0, 4))
			KitBox.fill_poly(ci, q, Color("1d93f2e6"), Color("0f63d6d9"), true)
			KitBox.hatch(ci, q, Color(1, 1, 1, 0.07), 9.0, 2.0, 0.55, 1.0)
			_top_glint(ci, q, Color(1, 1, 1, 0.35))
			KitBox.stroke_poly(ci, KitBox.offset_poly(q, -1.0), Color("8fd0ff"), 1.5)
		"white":
			KitBox.soft_shadow(ci, q, Color(0, 0, 0, 0.28), 10.0, Vector2(0, 4))
			KitBox.fill_poly(ci, q, Color("f7f8faeb"), Color("dde1e6e0"), true)
			KitBox.hatch(ci, q, Color(0, 0, 0, 0.035), 9.0, 2.0, 0.6, 1.0)
			KitBox.stroke_poly(ci, KitBox.offset_poly(q, -1.0), Color(1, 1, 1, 0.9), 1.5)
			if _icon:
				var r := Rect2(_icon.position - Vector2(12, 12), _icon.size + Vector2(24, 24))
				KitBox.corner_marks(ci, r, Color("2a2d33"), r.size.x * 0.22, 3.0)
			_ticks(ci, q, Color(0, 0, 0, 0.3))
		"orange":
			var k := 0.5 + 0.5 * sin(_t * 2.6)
			KitBox.soft_shadow(ci, q, Color(1.0, 0.55, 0.1, 0.32 + 0.18 * k), 16.0)
			KitBox.fill_poly(ci, q, Color("2a1a0abf"), Color("1a1006a6"), true)
			KitBox.hatch(ci, q, Color(1.0, 0.6, 0.2, 0.12), 10.0, 2.0, 0.0, 1.0)
			KitBox.stroke_poly(ci, KitBox.offset_poly(q, -1.5), Color("ffa43a"), 3.0)
			KitBox.stroke_poly(ci, KitBox.offset_poly(q, -6.0), Color(1.0, 0.75, 0.4, 0.3), 1.0)
		"dark":
			KitBox.soft_shadow(ci, q, Color(0, 0, 0, 0.3), 8.0, Vector2(0, 3))
			KitBox.fill_poly(ci, q, Color("0b2b4fc7"), Color("061a33b3"), true)
			KitBox.hatch(ci, q, Color(0.4, 0.75, 1.0, 0.13), 8.0, 2.0, 0.0, 1.0)
			KitBox.stroke_poly(ci, KitBox.offset_poly(q, -1.0), Color("3aa0ff"), 2.0)
			_ticks(ci, q, Color("3aa0ff"))
	# Short bright bar along the top edge (the "technical" mark).
	var y0 := q[0].y if side < 0 else q[1].y
	var x0 := b.position.x + b.size.x * (0.06 if side < 0 else 0.7)
	if look != "white":
		_plate.draw_rect(Rect2(x0, y0 + 1.0, b.size.x * 0.24, 3.0), Color(1, 1, 1, 0.55) if look != "orange" else Color("ffd08a"))


func _top_glint(ci: RID, q: PackedVector2Array, col: Color) -> void:
	RenderingServer.canvas_item_add_line(ci, q[0] + Vector2(6, 2), q[1] + Vector2(-6, 2), col, 1.0, true)


## Two tiny double ticks near the right corners (decoration).
func _ticks(ci: RID, q: PackedVector2Array, col: Color) -> void:
	var tr := q[1]
	var br := q[2]
	for p: Vector2 in [tr + Vector2(-14, 10), br + Vector2(-14, -22)]:
		RenderingServer.canvas_item_add_rect(ci, Rect2(p, Vector2(2, 10)), col)
		RenderingServer.canvas_item_add_rect(ci, Rect2(p + Vector2(5, 0), Vector2(2, 10)), col)
