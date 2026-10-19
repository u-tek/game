extends Button
## One bottom-nav tab (style v2), built by main.gd. A flat white glyph over an uppercase
## condensed label; inactive tabs are grey, the active one is white with a short white bar
## above it. The centre tab (center = true) is a raised hexagon plate that rises above the
## nav bar; when active its rim turns cyan and glows. The glyph squashes on touch-down and
## springs back on release; with shared_ink the nav (main.gd) draws one sliding bar instead
## of each tab's own.

const KitBox := preload("res://src/ui/components/kit_box.gd")

const ICON := 60.0
const DIM := Color("aeb3ba")

var tab_id := ""
var center := false
## main.gd slides one shared bar between tabs; the tab's own bar stays hidden.
var shared_ink := false
var _bar: ColorRect
var _icon: TextureRect
var _label: Label
var _hex: Control
var _active := false
var _tw: Tween
var _press_tw: Tween
var _hop_tw: Tween
## The glyph's resting top offset (the hop returns here).
var _icon_top := 0.0


func setup(id: String, text: String, icon_name: String, is_center: bool = false) -> void:
	tab_id = id
	center = is_center
	name = "Tab_" + id
	theme_type_variation = &"BareButton"
	focus_mode = FOCUS_NONE
	mouse_filter = MOUSE_FILTER_STOP
	size_flags_horizontal = SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(96, 112)

	if center:
		_hex = Control.new()
		_hex.name = "Hex"
		_hex.mouse_filter = MOUSE_FILTER_IGNORE
		_hex.anchor_left = 0.5
		_hex.anchor_right = 0.5
		_hex.offset_left = -50
		_hex.offset_right = 50
		_hex.offset_top = -22
		_hex.offset_bottom = 78
		_hex.draw.connect(_draw_hex)
		add_child(_hex)
		# First-session guide marks ring the hexagon itself (Guide reads this).
		set_meta("guide_hex", Vector2(-22.0 + 50.0, 48.0))
	else:
		_bar = ColorRect.new()
		_bar.mouse_filter = MOUSE_FILTER_IGNORE
		_bar.color = Color.WHITE
		_bar.anchor_left = 0.5
		_bar.anchor_right = 0.5
		_bar.offset_left = -44
		_bar.offset_right = 44
		_bar.offset_top = 4
		_bar.offset_bottom = 8
		_bar.modulate.a = 0.0
		add_child(_bar)

	var isz := ICON + (4.0 if center else 0.0)
	var top := -2.0 if center else 14.0
	_icon = Kit.icon(icon_name, isz)
	_icon.anchor_left = 0.5
	_icon.anchor_right = 0.5
	_icon.offset_left = -isz * 0.5
	_icon.offset_right = isz * 0.5
	_icon.offset_top = top
	_icon.offset_bottom = top + isz
	_icon_top = top
	_icon.pivot_offset = Vector2(isz, isz) * 0.5
	add_child(_icon)

	_label = Kit.label(text.to_upper(), 23, DIM, "cond_bold", 0)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.anchor_left = 0.0
	_label.anchor_right = 1.0
	_label.offset_top = 78
	_label.offset_bottom = 104
	add_child(_label)
	if _hex:
		_hex.pivot_offset = Vector2(50, 50)
	button_down.connect(func() -> void: _squash(true))
	button_up.connect(func() -> void: _squash(false))
	_apply(false)


## Touch-down squash of the glyph (and the Lobby hexagon); release springs it back.
func _squash(down: bool) -> void:
	if _press_tw and _press_tw.is_valid():
		_press_tw.kill()
	_press_tw = create_tween().set_parallel(true)
	var parts: Array[Control] = [_icon]
	if _hex:
		parts.append(_hex)
	for p in parts:
		if down:
			_press_tw.tween_property(p, "scale", Vector2(0.86, 0.86), 0.07).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		else:
			_press_tw.tween_property(p, "scale", Vector2.ONE, 0.34).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var m := Color(1.2, 1.2, 1.2) if down else Color.WHITE
	_press_tw.tween_property(_label, "modulate", m, 0.08 if down else 0.25)


## Highlights this tab.
func set_active(on: bool, animate: bool = true) -> void:
	if on == _active:
		return
	_active = on
	_apply(animate and is_inside_tree())


## Red dot on the icon (something to do on that tab).
func set_dot(show: bool) -> void:
	Kit.set_dot(_icon, show, 20.0, Vector2(-6, -2))


func _apply(animate: bool) -> void:
	var col := Color.WHITE if _active else DIM
	_label.add_theme_color_override("font_color", col)
	if _hex:
		_hex.queue_redraw()
	if _tw and _tw.is_valid():
		_tw.kill()
	var bar_a := 1.0 if _active and not shared_ink else 0.0
	if not animate:
		_icon.modulate = col
		if _bar:
			_bar.modulate.a = bar_a
		return
	_tw = create_tween().set_parallel(true)
	_tw.tween_property(_icon, "modulate", col, 0.15)
	if _bar:
		_tw.tween_property(_bar, "modulate:a", bar_a, 0.18)
	if _active:
		# The new tab's glyph hops: up and back with a spring.
		_icon.scale = Vector2(0.84, 0.84)
		_tw.tween_property(_icon, "scale", Vector2.ONE, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		if not Kit.motion_ok():
			return
		var y0 := _icon_top
		var hop := func(v: float) -> void:
			_icon.offset_top = y0 - v
			_icon.offset_bottom = y0 - v + _icon.custom_minimum_size.y
		if _hop_tw and _hop_tw.is_valid():
			_hop_tw.kill()
		_hop_tw = create_tween()
		_hop_tw.tween_method(hop, 0.0, 7.0, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_hop_tw.tween_method(hop, 7.0, 0.0, 0.3).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


func _draw_hex() -> void:
	var ci := _hex.get_canvas_item()
	var c := Vector2(_hex.size.x * 0.5, 50.0)
	var r := 48.0
	var pts := KitBox.hex_points(c, r)
	if _active:
		KitBox.soft_shadow(ci, pts, Color(Kit.ACCENT, 0.55), 16.0)
	else:
		KitBox.soft_shadow(ci, pts, Color(0, 0, 0, 0.5), 10.0, Vector2(0, 3))
	KitBox.fill_poly(ci, pts, Color("1b2b48"), Color("0b1222"))
	KitBox.hatch(ci, pts, Color(1, 1, 1, 0.05), 8.0, 2.0, 0.5, 1.0)
	KitBox.stroke_poly(ci, KitBox.offset_poly(pts, -7.0), Color(1, 1, 1, 0.16), 1.5)
	KitBox.stroke_poly(ci, pts, Kit.ACCENT if _active else Color(1, 1, 1, 0.35), 3.0 if _active else 2.0)
