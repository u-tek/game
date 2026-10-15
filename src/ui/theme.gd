class_name UITheme
extends RefCounted
## The app Theme, built in code from the design tokens in Kit (docs/dev/architecture.md
## section 7: "Twilight cathedral"). main.gd applies it to the root window, so every
## Control in the game inherits it. Kit builders select looks with theme_type_variation:
##   Buttons  PrimaryButton (gold), SecondaryButton (indigo glass), DangerButton (ember),
##            SegmentButton (toggle tabs), BareButton (invisible, for custom content)
##   Panels   GlassPanel (ornate default), CardPanel, InsetPanel, PlainPanel, ChipPanel,
##            TagPanel, ToastPanel, ModalPanel
## UITheme.style(kind) returns a fresh StyleBox for any preset (see the match below).

const KitBox := preload("res://src/ui/components/kit_box.gd")

static var _theme: Theme

const _BTN_TEXT_DARK := Color("3d2306")


## The shared Theme instance (built on first use).
static func get_theme() -> Theme:
	if _theme == null:
		_theme = build()
	return _theme


## A fresh StyleBox for a preset. pad >= 0 overrides all content margins.
## Kinds: glass, card, inset, plain, chip, tag, toast, modal, topbar, navbar, disc,
## disc_gold, btn_<primary|secondary|danger>[_hover|_pressed|_disabled], seg_off, seg_on,
## seg_on_pressed, empty, line_edit, line_edit_focus.
static func style(kind: String, pad: int = -1) -> StyleBox:
	var b := KitBox.new()
	var m := Vector4(18, 14, 18, 14) # left, top, right, bottom
	match kind:
		"glass":
			b.radius = 22
			b.top_color = Color("271e4ef2")
			b.bottom_color = Color("161130ee")
			b.border_width = 2
			b.border_color = Color(0.91, 0.765, 0.416, 0.45)
			b.inner_color = Color(0.91, 0.765, 0.416, 0.14)
			b.inner_inset = 6
			b.ornament_color = Color(0.95, 0.76, 0.31, 0.85)
			b.ornament_size = 4
			b.shadow_size = 12
			b.shadow_color = Color(0, 0, 0, 0.42)
			b.shadow_offset = Vector2(0, 6)
			b.top_line_color = Color(1, 1, 1, 0.07)
			m = Vector4(28, 24, 28, 24)
		"card":
			b.radius = 16
			b.top_color = Color("251d4ae8")
			b.bottom_color = Color("181231e8")
			b.border_width = 2
			b.border_color = Color(0.91, 0.765, 0.416, 0.3)
			b.shadow_size = 6
			b.shadow_color = Color(0, 0, 0, 0.35)
			b.shadow_offset = Vector2(0, 3)
			b.top_line_color = Color(1, 1, 1, 0.06)
			m = Vector4(18, 16, 18, 16)
		"inset":
			b.radius = 14
			b.top_color = Color("0a0718bb")
			b.bottom_color = Color("141029bb")
			b.border_width = 1
			b.border_color = Color(0.91, 0.765, 0.416, 0.18)
			m = Vector4(16, 12, 16, 12)
		"plain":
			b.radius = 16
			b.top_color = Color("1f1840e6")
			b.bottom_color = Color("1a1436e6")
			m = Vector4(18, 14, 18, 14)
		"chip":
			b.radius = 999
			b.top_color = Color("0b0818ee")
			b.bottom_color = Color("1e1840ee")
			b.border_width = 2
			b.border_color = Color(0.91, 0.765, 0.416, 0.5)
			b.top_line_color = Color(1, 1, 1, 0.05)
			m = Vector4(4, 2, 12, 2)
		"tag":
			b.radius = 999
			b.top_color = Color("2c2356")
			b.bottom_color = Color("1a1436")
			b.border_width = 1
			b.border_color = Color(0.91, 0.765, 0.416, 0.4)
			m = Vector4(8, 3, 16, 3)
		"toast":
			b.radius = 26
			b.top_color = Color("2d2459f7")
			b.bottom_color = Color("1a1437f7")
			b.border_width = 2
			b.border_color = Color(0.91, 0.765, 0.416, 0.65)
			b.inner_color = Color(0.91, 0.765, 0.416, 0.12)
			b.inner_inset = 5
			b.shadow_size = 16
			b.shadow_color = Color(0, 0, 0, 0.5)
			b.shadow_offset = Vector2(0, 6)
			m = Vector4(30, 14, 30, 16)
		"modal":
			b.radius = 26
			b.top_color = Color("2a2154fa")
			b.bottom_color = Color("150f2dfa")
			b.border_width = 2
			b.border_color = Color(0.95, 0.8, 0.45, 0.7)
			b.inner_color = Color(0.91, 0.765, 0.416, 0.22)
			b.inner_inset = 7
			b.ornament_color = Color(1.0, 0.85, 0.45, 0.95)
			b.ornament_size = 5
			b.shadow_size = 30
			b.shadow_color = Color(0, 0, 0, 0.55)
			b.shadow_offset = Vector2(0, 10)
			b.top_line_color = Color(1, 1, 1, 0.1)
			m = Vector4(36, 32, 36, 32)
		"topbar":
			b.radius = 0
			b.top_color = Color("07050ff7")
			b.bottom_color = Color("1c1640f2")
			b.border_width = 2
			b.border_color = Color(0.91, 0.765, 0.416, 0.55)
			b.shadow_size = 12
			b.shadow_color = Color(0, 0, 0, 0.45)
			b.shadow_offset = Vector2(0, 5)
			m = Vector4(0, 0, 0, 0)
		"navbar":
			b.radius = 0
			b.top_color = Color("251c4cfa")
			b.bottom_color = Color("07050ffc")
			b.border_width = 2
			b.border_color = Color(0.91, 0.765, 0.416, 0.6)
			b.shadow_size = 16
			b.shadow_color = Color(0, 0, 0, 0.5)
			b.shadow_offset = Vector2(0, -5)
			m = Vector4(0, 0, 0, 0)
		"disc":
			b.radius = 999
			b.top_color = Color("3b2e74")
			b.bottom_color = Color("1b1540")
			b.border_width = 2
			b.border_color = Color(0.91, 0.765, 0.416, 0.75)
			b.gloss = 0.16
			b.lip = 3
			b.lip_color = Color("0b0820")
			b.shadow_size = 5
			b.shadow_color = Color(0, 0, 0, 0.45)
			m = Vector4(0, 0, 0, 0)
		"disc_gold":
			_gold(b)
			b.radius = 999
			b.lip = 3
			m = Vector4(0, 0, 0, 0)
		"btn_primary", "btn_primary_hover", "btn_primary_pressed":
			_gold(b)
			if kind == "btn_primary_hover":
				b.top_color = b.top_color.lightened(0.08)
				b.bottom_color = b.bottom_color.lightened(0.08)
		"btn_secondary", "btn_secondary_hover", "btn_secondary_pressed":
			b.radius = 22
			b.top_color = Color("43357f")
			b.bottom_color = Color("251c52")
			b.border_width = 2
			b.border_color = Color(0.93, 0.78, 0.45, 0.85)
			b.gloss = 0.14
			b.lip = 6
			b.lip_color = Color("110b2b")
			b.top_line_color = Color(1, 1, 1, 0.2)
			b.shadow_size = 6
			b.shadow_color = Color(0, 0, 0, 0.4)
			if kind == "btn_secondary_hover":
				b.top_color = b.top_color.lightened(0.07)
		"btn_danger", "btn_danger_hover", "btn_danger_pressed":
			b.radius = 22
			b.top_color = Color("ff7a58")
			b.bottom_color = Color("c42e1b")
			b.border_width = 2
			b.border_color = Color("3d0a04")
			b.gloss = 0.24
			b.lip = 6
			b.lip_color = Color("6e1408")
			b.top_line_color = Color(1, 1, 1, 0.5)
			b.shadow_size = 6
			b.shadow_color = Color(0, 0, 0, 0.4)
			if kind == "btn_danger_hover":
				b.top_color = b.top_color.lightened(0.07)
		"btn_primary_disabled", "btn_secondary_disabled", "btn_danger_disabled":
			b.radius = 22
			b.top_color = Color("4c4664")
			b.bottom_color = Color("332e4b")
			b.border_width = 2
			b.border_color = Color("17132a")
			b.gloss = 0.05
			b.lip = 6
			b.lip_color = Color("1f1a31")
			b.shadow_size = 4
			b.shadow_color = Color(0, 0, 0, 0.3)
		"seg_off":
			b.radius = 18
			b.top_color = Color("1d1640e8")
			b.bottom_color = Color("130e2ae8")
			b.border_width = 2
			b.border_color = Color(0.91, 0.765, 0.416, 0.3)
			b.lip = 3
			b.lip_color = Color("0a0718")
			m = Vector4(14, 6, 14, 9)
		"seg_on", "seg_on_pressed":
			_gold(b)
			b.radius = 18
			b.lip = 3
			b.shadow_size = 8
			b.shadow_color = Color(0.95, 0.75, 0.3, 0.35)
			b.shadow_offset = Vector2.ZERO
			m = Vector4(14, 6, 14, 9)
		"line_edit", "line_edit_focus":
			b.radius = 14
			b.top_color = Color("07050f")
			b.bottom_color = Color("161230")
			b.border_width = 2
			b.border_color = Color(0.91, 0.765, 0.416, 0.85 if kind == "line_edit_focus" else 0.3)
			m = Vector4(18, 10, 18, 10)
		"empty":
			b.fill = false
			m = Vector4(0, 0, 0, 0)
		_:
			push_warning("UITheme.style: unknown kind '%s'" % kind)
	# Button content margins keep the label centered on the face (above the lip), and
	# pressed states sink the face by the lip difference.
	if kind.begins_with("btn_") or kind.begins_with("seg_"):
		if not kind.begins_with("seg_"):
			m = Vector4(28, 8, 28, 8 + b.lip)
		if kind.ends_with("_pressed"):
			var sink := b.lip - 2.0
			b.offset_y = sink
			b.lip = 2.0
			b.shadow_size = maxi(b.shadow_size - 3, 0)
			m.y += sink
			m.w -= sink
	if pad >= 0:
		m = Vector4(pad, pad, pad, pad)
	b.content_margin_left = m.x
	b.content_margin_top = m.y
	b.content_margin_right = m.z
	b.content_margin_bottom = m.w
	return b.commit()


static func _gold(b: KitBox) -> void:
	b.radius = 22
	b.top_color = Color("ffe28f")
	b.bottom_color = Color("e0a332")
	b.border_width = 2
	b.border_color = Color("5c3a0a")
	b.gloss = 0.32
	b.lip = 6
	b.lip_color = Color("9a6312")
	b.top_line_color = Color(1, 1, 1, 0.75)
	b.shadow_size = 6
	b.shadow_color = Color(0, 0, 0, 0.42)


## Builds the Theme from scratch.
static func build() -> Theme:
	var t := Theme.new()
	t.default_font = Kit.font("bold")
	t.default_font_size = Kit.SIZE_BODY

	# Labels.
	t.set_color("font_color", "Label", Kit.INK)
	t.set_color("font_outline_color", "Label", Kit.OUTLINE)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0))
	for v: Array in [["TitleLabel", Kit.SIZE_HERO], ["HeaderLabel", Kit.SIZE_HEADER]]:
		t.set_type_variation(v[0], "Label")
		t.set_font("font", v[0], Kit.font("title"))
		t.set_font_size("font_size", v[0], v[1])
		t.set_color("font_color", v[0], Kit.GOLD_LIGHT)
		t.set_constant("outline_size", v[0], 4)
	t.set_type_variation("CaptionLabel", "Label")
	t.set_font_size("font_size", "CaptionLabel", Kit.SIZE_SMALL)
	t.set_color("font_color", "CaptionLabel", Kit.INK_DIM)
	t.set_type_variation("NumberLabel", "Label")
	t.set_font("font", "NumberLabel", Kit.font("black"))
	t.set_font_size("font_size", "NumberLabel", Kit.SIZE_BUTTON)
	t.set_constant("outline_size", "NumberLabel", 5)

	# RichTextLabel.
	t.set_color("default_color", "RichTextLabel", Kit.INK)
	t.set_font("normal_font", "RichTextLabel", Kit.font("bold"))
	t.set_font("bold_font", "RichTextLabel", Kit.font("black"))
	t.set_font_size("normal_font_size", "RichTextLabel", Kit.SIZE_BODY)
	t.set_font_size("bold_font_size", "RichTextLabel", Kit.SIZE_BODY)

	# Buttons: the plain Button looks like the secondary button.
	_button_type(t, "Button", "btn_secondary", Kit.INK)
	_button_type(t, "PrimaryButton", "btn_primary", _BTN_TEXT_DARK)
	_button_type(t, "SecondaryButton", "btn_secondary", Kit.INK)
	_button_type(t, "DangerButton", "btn_danger", Color("fff4ea"))
	for v in ["PrimaryButton", "SecondaryButton", "DangerButton"]:
		t.set_type_variation(v, "Button")
	t.set_constant("outline_size", "SecondaryButton", 0)
	t.set_color("font_outline_color", "DangerButton", Color("5a1006"))
	t.set_constant("outline_size", "DangerButton", 3)
	t.set_constant("outline_size", "Button", 0)

	t.set_type_variation("SegmentButton", "Button")
	for st in ["normal", "hover", "disabled"]:
		t.set_stylebox(st, "SegmentButton", style("seg_off"))
	t.set_stylebox("pressed", "SegmentButton", style("seg_on"))
	t.set_stylebox("hover_pressed", "SegmentButton", style("seg_on"))
	t.set_stylebox("focus", "SegmentButton", StyleBoxEmpty.new())
	t.set_font("font", "SegmentButton", Kit.font("extrabold"))
	t.set_font_size("font_size", "SegmentButton", 26)
	t.set_color("font_color", "SegmentButton", Kit.INK_DIM)
	t.set_color("font_hover_color", "SegmentButton", Kit.INK)
	t.set_color("font_pressed_color", "SegmentButton", _BTN_TEXT_DARK)
	t.set_color("font_hover_pressed_color", "SegmentButton", _BTN_TEXT_DARK)
	t.set_color("font_focus_color", "SegmentButton", Kit.INK_DIM)
	t.set_color("font_disabled_color", "SegmentButton", Color("6d6688"))
	t.set_color("icon_pressed_color", "SegmentButton", Color.WHITE)

	t.set_type_variation("BareButton", "Button")
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		t.set_stylebox(st, "BareButton", StyleBoxEmpty.new())

	# Panels.
	t.set_stylebox("panel", "PanelContainer", style("glass"))
	t.set_stylebox("panel", "Panel", style("glass"))
	var panels := {
		"GlassPanel": "glass", "CardPanel": "card", "InsetPanel": "inset", "PlainPanel": "plain",
		"ChipPanel": "chip", "TagPanel": "tag", "ToastPanel": "toast", "ModalPanel": "modal",
	}
	for v: String in panels:
		t.set_type_variation(v, "PanelContainer")
		t.set_stylebox("panel", v, style(panels[v]))

	# Scrollbars: thin gold indicator, no arrows.
	var none := _blank_icon()
	for sb in ["VScrollBar", "HScrollBar"]:
		var track := StyleBoxFlat.new()
		track.bg_color = Color(1, 1, 1, 0.04)
		track.set_corner_radius_all(3)
		track.set_content_margin_all(3)
		t.set_stylebox("scroll", sb, track)
		t.set_stylebox("scroll_focus", sb, track)
		for g: Array in [["grabber", 0.4], ["grabber_highlight", 0.6], ["grabber_pressed", 0.8]]:
			var grab := StyleBoxFlat.new()
			grab.bg_color = Color(Kit.GOLD, g[1])
			grab.set_corner_radius_all(3)
			grab.set_content_margin_all(3)
			t.set_stylebox(g[0], sb, grab)
		for ic in ["increment", "increment_highlight", "increment_pressed", "decrement", "decrement_highlight", "decrement_pressed"]:
			t.set_icon(ic, sb, none)
	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())

	# Progress bar defaults (Kit.progress_bar sets its own).
	var pb_bg := KitBox.new()
	pb_bg.radius = 12
	pb_bg.top_color = Color("07050f")
	pb_bg.bottom_color = Color("1a1433")
	pb_bg.border_width = 1
	pb_bg.border_color = Color(0.91, 0.765, 0.416, 0.35)
	t.set_stylebox("background", "ProgressBar", pb_bg.commit())
	var pb_fg := KitBox.new()
	pb_fg.radius = 12
	pb_fg.top_color = Kit.GOOD.lightened(0.35)
	pb_fg.bottom_color = Kit.GOOD.darkened(0.2)
	pb_fg.gloss = 0.3
	t.set_stylebox("fill", "ProgressBar", pb_fg.commit())
	t.set_color("font_color", "ProgressBar", Kit.INK)
	t.set_font_size("font_size", "ProgressBar", 20)

	# Toggles (CheckButton / CheckBox).
	var on := Kit.icon_texture("toggle_on")
	var off := Kit.icon_texture("toggle_off")
	for cb in ["CheckButton", "CheckBox"]:
		for st in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
			t.set_stylebox(st, cb, StyleBoxEmpty.new())
		if on and off:
			for suffix in ["", "_mirrored"]:
				t.set_icon("checked" + suffix, cb, on)
				t.set_icon("unchecked" + suffix, cb, off)
				t.set_icon("checked_disabled" + suffix, cb, on)
				t.set_icon("unchecked_disabled" + suffix, cb, off)
			t.set_icon("radio_checked", cb, on)
			t.set_icon("radio_unchecked", cb, off)
		t.set_color("font_color", cb, Kit.INK)
		t.set_color("font_hover_color", cb, Kit.INK)
		t.set_color("font_pressed_color", cb, Kit.INK)
		t.set_color("font_hover_pressed_color", cb, Kit.INK)
		t.set_color("font_focus_color", cb, Kit.INK)

	# Line edit.
	t.set_stylebox("normal", "LineEdit", style("line_edit"))
	t.set_stylebox("focus", "LineEdit", style("line_edit_focus"))
	t.set_stylebox("read_only", "LineEdit", style("line_edit"))
	t.set_color("font_color", "LineEdit", Kit.INK)
	t.set_color("font_placeholder_color", "LineEdit", Color(Kit.INK_DIM, 0.6))
	t.set_color("caret_color", "LineEdit", Kit.GOLD)
	t.set_color("selection_color", "LineEdit", Color(Kit.GOLD, 0.3))
	t.set_font_size("font_size", "LineEdit", Kit.SIZE_BODY)

	# Slider.
	var track := KitBox.new()
	track.radius = 6
	track.top_color = Color("07050f")
	track.bottom_color = Color("1a1433")
	track.border_width = 1
	track.border_color = Color(0.91, 0.765, 0.416, 0.35)
	track.content_margin_top = 6
	track.content_margin_bottom = 6
	t.set_stylebox("slider", "HSlider", track.commit())
	var area := KitBox.new()
	area.radius = 6
	area.top_color = Kit.GOLD.lightened(0.2)
	area.bottom_color = Kit.GOLD_DEEP
	area.content_margin_top = 6
	area.content_margin_bottom = 6
	t.set_stylebox("grabber_area", "HSlider", area.commit())
	t.set_stylebox("grabber_area_highlight", "HSlider", area)
	var knob := Kit.icon_texture("knob")
	if knob:
		t.set_icon("grabber", "HSlider", knob)
		t.set_icon("grabber_highlight", "HSlider", knob)

	# Tabs (if a screen uses TabBar / TabContainer).
	for tb in ["TabBar", "TabContainer"]:
		t.set_stylebox("tab_selected", tb, style("seg_on", 14))
		t.set_stylebox("tab_hovered", tb, style("seg_off", 14))
		t.set_stylebox("tab_unselected", tb, style("seg_off", 14))
		t.set_stylebox("tab_disabled", tb, style("seg_off", 14))
		t.set_stylebox("tab_focus", tb, StyleBoxEmpty.new())
		t.set_color("font_selected_color", tb, _BTN_TEXT_DARK)
		t.set_color("font_unselected_color", tb, Kit.INK_DIM)
		t.set_color("font_hovered_color", tb, Kit.INK)
		t.set_font("font", tb, Kit.font("extrabold"))
		t.set_font_size("font_size", tb, 24)
		t.set_constant("h_separation", tb, 8)
	t.set_stylebox("panel", "TabContainer", style("glass"))

	# Popups / tooltips.
	t.set_stylebox("panel", "PopupMenu", style("card", 12))
	t.set_stylebox("panel", "TooltipPanel", style("card", 12))
	t.set_stylebox("panel", "PopupPanel", style("glass"))
	t.set_color("font_color", "PopupMenu", Kit.INK)
	t.set_color("font_color", "TooltipLabel", Kit.INK)
	t.set_stylebox("normal", "OptionButton", style("btn_secondary"))
	t.set_stylebox("hover", "OptionButton", style("btn_secondary_hover"))
	t.set_stylebox("pressed", "OptionButton", style("btn_secondary_pressed"))
	t.set_stylebox("disabled", "OptionButton", style("btn_secondary_disabled"))
	t.set_stylebox("focus", "OptionButton", StyleBoxEmpty.new())
	return t


static func _button_type(t: Theme, type: String, base: String, text: Color) -> void:
	t.set_stylebox("normal", type, style(base))
	t.set_stylebox("hover", type, style(base + "_hover"))
	t.set_stylebox("pressed", type, style(base + "_pressed"))
	t.set_stylebox("hover_pressed", type, style(base + "_pressed"))
	t.set_stylebox("disabled", type, style(base + "_disabled"))
	t.set_stylebox("focus", type, StyleBoxEmpty.new())
	t.set_font("font", type, Kit.font("extrabold"))
	t.set_font_size("font_size", type, Kit.SIZE_BUTTON)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		t.set_color(c, type, text)
	t.set_color("font_disabled_color", type, Color("8e86a6"))
	t.set_constant("h_separation", type, 12)
	t.set_constant("icon_max_width", type, 44)


static func _blank_icon() -> Texture2D:
	var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(img)
