extends Button
## One bottom-nav tab (icon + label). The active tab sits on a raised violet plate with a
## gold glow, its icon lifts and grows, and its label turns gold. Built by main.gd.

const KitBox := preload("res://src/ui/components/kit_box.gd")

const ICON := 66.0

var tab_id := ""
var _plate: Panel
var _bar: Panel
var _glow: TextureRect
var _icon: TextureRect
var _label: Label
var _active := false
var _tw: Tween


func setup(id: String, text: String, icon_name: String) -> void:
	tab_id = id
	name = "Tab_" + id
	theme_type_variation = &"BareButton"
	focus_mode = FOCUS_NONE
	mouse_filter = MOUSE_FILTER_STOP
	size_flags_horizontal = SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(96, 112)

	_plate = Panel.new()
	_plate.mouse_filter = MOUSE_FILTER_IGNORE
	var pb := KitBox.new()
	pb.radius = 22
	pb.top_color = Color("4a3a92")
	pb.bottom_color = Color("221a4c00")
	pb.border_width = 0
	_plate.add_theme_stylebox_override("panel", pb.commit())
	_plate.anchor_left = 0.5
	_plate.anchor_right = 0.5
	_plate.offset_left = -62
	_plate.offset_right = 62
	_plate.offset_top = 2
	_plate.offset_bottom = 110
	_plate.modulate.a = 0.0
	add_child(_plate)

	# Lit gold bar on the nav's top edge above the active tab.
	_bar = Panel.new()
	_bar.mouse_filter = MOUSE_FILTER_IGNORE
	var bb := KitBox.new()
	bb.radius = 3
	bb.top_color = Color("fff3c4")
	bb.bottom_color = Color("f2b93a")
	bb.shadow_size = 10
	bb.shadow_color = Color(1.0, 0.78, 0.3, 0.7)
	bb.shadow_offset = Vector2.ZERO
	_bar.add_theme_stylebox_override("panel", bb.commit())
	_bar.anchor_left = 0.5
	_bar.anchor_right = 0.5
	_bar.offset_left = -34
	_bar.offset_right = 34
	_bar.offset_top = -5
	_bar.offset_bottom = 1
	_bar.modulate.a = 0.0
	add_child(_bar)

	_glow = Kit.glow(Kit.GOLD, 150)
	_glow.anchor_left = 0.5
	_glow.anchor_right = 0.5
	_glow.offset_left = -75
	_glow.offset_right = 75
	_glow.offset_top = -30
	_glow.offset_bottom = 120
	_glow.modulate.a = 0.0
	add_child(_glow)

	_icon = Kit.icon(icon_name, ICON)
	_icon.anchor_left = 0.5
	_icon.anchor_right = 0.5
	_icon.offset_left = -ICON * 0.5
	_icon.offset_right = ICON * 0.5
	_icon.offset_top = 12
	_icon.offset_bottom = 12 + ICON
	_icon.pivot_offset = Vector2(ICON, ICON) * 0.5
	add_child(_icon)

	_label = Kit.label(text, 21, Kit.INK_DIM, "extrabold", 4)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.anchor_left = 0.0
	_label.anchor_right = 1.0
	_label.offset_top = 80
	_label.offset_bottom = 108
	add_child(_label)
	_apply(false)


## Highlights this tab.
func set_active(on: bool, animate: bool = true) -> void:
	if on == _active:
		return
	_active = on
	_apply(animate and is_inside_tree())


## Red dot on the icon (something to do on that tab).
func set_dot(show: bool) -> void:
	Kit.set_dot(_icon, show, 22.0, Vector2(-8, -2))


func _apply(animate: bool) -> void:
	var lift := -7.0 if _active else 0.0
	var sc := Vector2(1.14, 1.14) if _active else Vector2.ONE
	var icon_col := Color.WHITE if _active else Color(0.8, 0.77, 0.9)
	var label_col := Kit.GOLD_LIGHT if _active else Kit.INK_DIM
	_label.add_theme_color_override("font_color", label_col)
	if _tw and _tw.is_valid():
		_tw.kill()
	if not animate:
		_icon.offset_top = 12 + lift
		_icon.offset_bottom = 12 + ICON + lift
		_icon.scale = sc
		_icon.modulate = icon_col
		_glow.modulate.a = 0.5 if _active else 0.0
		_plate.modulate.a = 1.0 if _active else 0.0
		_bar.modulate.a = 1.0 if _active else 0.0
		return
	_tw = create_tween().set_parallel(true)
	_tw.tween_property(_icon, "offset_top", 12 + lift, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tw.tween_property(_icon, "offset_bottom", 12 + ICON + lift, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tw.tween_property(_icon, "scale", sc, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tw.tween_property(_icon, "modulate", icon_col, 0.15)
	_tw.tween_property(_glow, "modulate:a", 0.5 if _active else 0.0, 0.2)
	_tw.tween_property(_plate, "modulate:a", 1.0 if _active else 0.0, 0.2)
	_tw.tween_property(_bar, "modulate:a", 1.0 if _active else 0.0, 0.2)
