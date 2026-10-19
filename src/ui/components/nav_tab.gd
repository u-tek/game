extends Button
## One footer-strip tab (style v4 "Signal", the poster look; docs/dev/ui-style-v4.md), built by
## main.gd: a small ink glyph over a numbered mono label ("03 LOBBY") printed on the paper strip.
## Inactive tabs are faded ink, the active one is signal red-orange; main.gd slides one signal
## underline between tabs (shared_ink). The glyph squashes on touch-down and springs back. A red
## dot marks a tab with something to do.

const ICON := 34.0
const INK := Color("101113")

var tab_id := ""
var center := false
## main.gd slides one shared underline between tabs; kept for the old API.
var shared_ink := true
var _icon: TextureRect
var _label: Label
var _active := false
var _tw: Tween
var _press_tw: Tween
var _hop_tw: Tween
var _icon_top := 16.0


## text is printed as given (main.gd numbers it: "03 Lobby"). is_center is kept for the old API.
func setup(id: String, text: String, icon_name: String, is_center: bool = false) -> void:
	tab_id = id
	center = is_center
	name = "Tab_" + id
	theme_type_variation = &"BareButton"
	focus_mode = FOCUS_NONE
	mouse_filter = MOUSE_FILTER_STOP
	size_flags_horizontal = SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(96, 104)

	_icon = Kit.icon(icon_name, ICON, INK)
	_icon.anchor_left = 0.5
	_icon.anchor_right = 0.5
	_icon.offset_left = -ICON * 0.5
	_icon.offset_right = ICON * 0.5
	_icon.offset_top = _icon_top
	_icon.offset_bottom = _icon_top + ICON
	_icon.pivot_offset = Vector2(ICON, ICON) * 0.5
	add_child(_icon)

	_label = Kit.label(text.to_upper(), 14, INK, "mono_bold", 0)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.anchor_left = 0.0
	_label.anchor_right = 1.0
	_label.offset_top = 58
	_label.offset_bottom = 78
	add_child(_label)
	button_down.connect(func() -> void: _squash(true))
	button_up.connect(func() -> void: _squash(false))
	_apply(false)


## Bottom of the label: main.gd puts the shared underline just under it.
func ink_y() -> float:
	return 84.0


## Touch-down squash of the glyph; release springs it back.
func _squash(down: bool) -> void:
	if _press_tw and _press_tw.is_valid():
		_press_tw.kill()
	_press_tw = create_tween().set_parallel(true)
	if down:
		_press_tw.tween_property(_icon, "scale", Vector2(0.86, 0.86), 0.07).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	else:
		_press_tw.tween_property(_icon, "scale", Vector2.ONE, 0.34).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Highlights this tab.
func set_active(on: bool, animate: bool = true) -> void:
	if on == _active:
		return
	_active = on
	_apply(animate and is_inside_tree())


## Red dot beside the glyph (something to do on that tab).
func set_dot(show: bool) -> void:
	Kit.set_dot(_icon, show, 16.0, Vector2(-10, -4))


func _apply(animate: bool) -> void:
	var col := SignalKit.SIGNAL if _active else Color(INK, 0.52)
	_label.add_theme_color_override("font_color", col)
	if _tw and _tw.is_valid():
		_tw.kill()
	if not animate:
		_icon.modulate = col
		return
	_tw = create_tween().set_parallel(true)
	_tw.tween_property(_icon, "modulate", col, 0.15)
	if _active:
		# The new tab's glyph hops: up and back with a spring.
		_icon.scale = Vector2(0.84, 0.84)
		_tw.tween_property(_icon, "scale", Vector2.ONE, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		if not Kit.motion_ok():
			return
		var y0 := _icon_top
		var hop := func(v: float) -> void:
			_icon.offset_top = y0 - v
			_icon.offset_bottom = y0 - v + ICON
		if _hop_tw and _hop_tw.is_valid():
			_hop_tw.kill()
		_hop_tw = create_tween()
		_hop_tw.tween_method(hop, 0.0, 6.0, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_hop_tw.tween_method(hop, 6.0, 0.0, 0.3).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
