class_name UITheme
extends RefCounted
## The app Theme, built in code from the design tokens in Kit (style v4 "Signal", see
## docs/dev/ui-style-v4.md; v2 layouts in docs/dev/ui-style-v2.md). main.gd applies it to the root window, so every Control in the
## game inherits it. Kit builders select looks with theme_type_variation:
##   Buttons  PrimaryButton (cyan-blue), SecondaryButton (graphite), DangerButton (red),
##            LightButton (white, for light panels), OrangeButton (highlight),
##            SegmentButton (filter chips / toggle tabs), BareButton (invisible)
##   Panels   GlassPanel (dark translucent, default), CardPanel, InsetPanel, PlainPanel,
##            ChipPanel, TagPanel, ToastPanel, ModalPanel (dark chrome family) and
##            WhitePanel, PaperPanel, LightInsetPanel, RowPanel, DialogPanel, SpeechPanel,
##            BarPanel (light family and accents)
## UITheme.style(kind) returns a fresh StyleBox for any preset (see the match below).
##
## Legacy kinds keep their names and suit light text (Kit.INK) because older screens put
## white text in them; the light kinds pair with dark text (Kit.TEXT).

const KitBox := preload("res://src/ui/components/kit_box.gd")

static var _theme: Theme

const SKEW := 0.176 # tan(10 deg): the house slant


## The shared Theme instance (built on first use).
static func get_theme() -> Theme:
	if _theme == null:
		_theme = build()
	return _theme


## A fresh StyleBox for a preset. pad >= 0 overrides all content margins.
## Style v4 "Signal" (docs/dev/ui-style-v4.md): smoked glass and graphite with hairlines and cut
## corners on dark; bone-metal plates on the light side; signal red-orange for the accent.
## Glass fills keep their alpha in 0.60-0.80: Kit.panel gives the glass kinds a material that
## blurs what is behind them there (src/ui/shaders/glass.gdshader).
## Dark chrome: glass, card, inset, plain, chip, tag, toast, modal, topbar, navbar, disc,
##   disc_gold, speech, pill, bar, bar_accent
## Light (bone metal): white, paper, light_inset, row, row_alt, dialog, dialog_header, slot
## Buttons: btn_<primary|secondary|danger|light|orange>[_hover|_pressed|_disabled],
##   seg_off, seg_on, seg_on_pressed, tab_on, tab_off
## Other: empty, line_edit, line_edit_focus
static func style(kind: String, pad: int = -1) -> StyleBox:
	var b := KitBox.new()
	var m := Vector4(18, 14, 18, 14) # left, top, right, bottom
	b.radius = 2
	match kind:
		# ---------------- dark chrome family
		"glass":
			b.top_color = Color("1a1d23b8")
			b.bottom_color = Color("121418bd")
			b.border_width = 1.0
			b.border_color = Color(1, 1, 1, 0.13)
			b.top_line_color = Color(1, 1, 1, 0.16)
			b.corner_marks_color = Color(1, 1, 1, 0.3)
			b.corner_marks_size = 9
			b.corner_marks_inset = 5
			b.chamfer = 14
			b.chamfer_corners = 5
			m = Vector4(24, 20, 24, 20)
		"card":
			b.top_color = Color("1c1f25eb")
			b.bottom_color = Color("15171ceb")
			b.border_width = 1.0
			b.border_color = Color(1, 1, 1, 0.09)
			b.chamfer = 10
			b.chamfer_corners = 4
			m = Vector4(18, 14, 18, 14)
		"inset":
			b.top_color = Color("07080ab0")
			b.bottom_color = Color("0a0b0db0")
			b.border_width = 1.0
			b.border_color = Color(1, 1, 1, 0.07)
			m = Vector4(16, 12, 16, 12)
		"plain":
			b.top_color = Color("16191ee6")
			b.bottom_color = Color("121418e6")
			m = Vector4(18, 14, 18, 14)
		"chip":
			b.top_color = Color("0a0b0dc7")
			b.bottom_color = Color("0a0b0dc7")
			b.border_width = 1.0
			b.border_color = Color(1, 1, 1, 0.12)
			m = Vector4(10, 2, 12, 2)
		"pill":
			b.radius = 999
			b.top_color = Color("0a0b0dc7")
			b.bottom_color = Color("0a0b0dc7")
			b.border_width = 1.0
			b.border_color = Color(1, 1, 1, 0.14)
			m = Vector4(10, 2, 14, 2)
		"tag":
			b.top_color = Color("24272d")
			b.bottom_color = Color("1c1f24")
			b.border_width = 1.0
			b.border_color = Color(1, 1, 1, 0.12)
			b.chamfer = 6
			b.chamfer_corners = 4
			m = Vector4(10, 3, 14, 3)
		"toast":
			b.top_color = Color("1a1d22f7")
			b.bottom_color = Color("121418f7")
			b.border_width = 1.0
			b.border_color = Color(1, 1, 1, 0.2)
			b.accent_color = Kit.ACCENT
			b.accent_left = 4
			b.chamfer = 10
			b.chamfer_corners = 5
			b.shadow_size = 16
			b.shadow_color = Color(0, 0, 0, 0.6)
			b.shadow_offset = Vector2(0, 6)
			m = Vector4(30, 16, 28, 16)
		"modal":
			b.top_color = Color("17191ef7")
			b.bottom_color = Color("101215f7")
			b.border_width = 1.0
			b.border_color = Color(1, 1, 1, 0.14)
			b.top_line_color = Color(1, 1, 1, 0.18)
			b.corner_marks_color = Color(1, 1, 1, 0.3)
			b.corner_marks_size = 12
			b.corner_marks_inset = 7
			b.chamfer = 18
			b.chamfer_corners = 5
			b.shadow_size = 26
			b.shadow_color = Color(0, 0, 0, 0.55)
			b.shadow_offset = Vector2(0, 10)
			m = Vector4(30, 26, 30, 30)
		"speech":
			b.top_color = Color("0a0b0d8c")
			b.bottom_color = Color("0a0b0d8c")
			b.border_width = 1.0
			b.border_color = Color(1, 1, 1, 0.1)
			b.chamfer = 8
			b.chamfer_corners = 8
			m = Vector4(26, 16, 26, 20)
		"bar":
			b.top_color = Color("1d2025")
			b.bottom_color = Color("16181c")
			m = Vector4(16, 6, 16, 6)
		"bar_accent":
			b.top_color = Color("1d2025")
			b.bottom_color = Color("16181c")
			b.accent_color = Kit.ACCENT
			b.accent_left = 4
			m = Vector4(20, 6, 16, 6)
		"topbar":
			b.radius = 0
			b.top_color = Color("060708f2")
			b.bottom_color = Color("0b0c0ec7")
			m = Vector4(0, 0, 0, 0)
		"topbar_clear":
			b.radius = 0
			b.top_color = Color("000000b3")
			b.bottom_color = Color("00000000")
			m = Vector4(0, 0, 0, 0)
		"navbar":
			b.radius = 0
			b.top_color = Color("111317f5")
			b.bottom_color = Color("060708")
			b.top_line_color = Color(1, 1, 1, 0.14)
			m = Vector4(0, 0, 0, 0)
		"navbar_clear":
			b.radius = 0
			b.top_color = Color("00000000")
			b.bottom_color = Color("000000e6")
			m = Vector4(0, 0, 0, 0)
		"power_chip":
			b.top_color = Color("0a0b0deb")
			b.bottom_color = Color("0a0b0deb")
			b.border_width = 1.0
			b.border_color = Color(1, 1, 1, 0.25)
			m = Vector4(6, 0, 8, 0)
		"disc":
			b.radius = 999
			b.top_color = Color("1a1d22d9")
			b.bottom_color = Color("121418d9")
			b.border_width = 1.0
			b.border_color = Color(1, 1, 1, 0.18)
			m = Vector4(0, 0, 0, 0)
		"disc_gold":
			b.radius = 999
			b.top_color = Kit.ACCENT.lightened(0.1)
			b.bottom_color = Kit.ACCENT_DEEP
			b.shadow_size = 8
			b.shadow_color = Color(1.0, 0.3, 0.1, 0.3)
			b.shadow_offset = Vector2.ZERO
			m = Vector4(0, 0, 0, 0)
		# ---------------- light family (bone metal)
		"white":
			b.top_color = Color("f0efeb")
			b.bottom_color = Color("dcdcd6")
			b.border_width = 1.0
			b.border_color = Color("c4c6c0")
			b.corner_marks_color = Color(0, 0, 0, 0.22)
			b.corner_marks_size = 8
			b.corner_marks_inset = 5
			b.chamfer = 12
			b.chamfer_corners = 5
			b.shadow_size = 10
			b.shadow_color = Color(0, 0, 0, 0.3)
			b.shadow_offset = Vector2(0, 4)
			m = Vector4(20, 16, 20, 16)
		"paper":
			b.top_color = Kit.PAPER
			b.bottom_color = Kit.PAPER.darkened(0.04)
			m = Vector4(20, 16, 20, 16)
		"light_inset":
			b.top_color = Color("d8d9d3")
			b.bottom_color = Color("e2e3dd")
			b.border_width = 1.0
			b.border_color = Color("c6c8c2")
			m = Vector4(14, 10, 14, 10)
		"row", "row_alt":
			b.radius = 0
			b.top_color = Color("efeeea") if kind == "row" else Color("e5e5e0")
			b.bottom_color = b.top_color
			m = Vector4(14, 6, 14, 6)
		"dialog":
			b.top_color = Color("efeeea")
			b.bottom_color = Color("dededa")
			b.chamfer = 18
			b.chamfer_corners = 5
			b.shadow_size = 30
			b.shadow_color = Color(0, 0, 0, 0.55)
			b.shadow_offset = Vector2(0, 10)
			m = Vector4(0, 0, 0, 0)
		"dialog_header":
			b.radius = 0
			b.top_color = Color("1d1f23")
			b.bottom_color = Color("121316")
			b.accent_color = Kit.ACCENT
			b.accent_left = 6
			b.hatch_color = Color(1, 1, 1, 0.05)
			b.hatch_from = 0.62
			b.hatch_spacing = 8
			b.hatch_width = 1.5
			m = Vector4(28, 0, 12, 0)
		"slot":
			b.top_color = Color("e2e3dd")
			b.bottom_color = Color("d0d2cc")
			b.border_width = 1.0
			b.border_color = Color("bcbfb8")
			b.chamfer = 8
			b.chamfer_corners = 4
			m = Vector4(6, 6, 6, 6)
		"reward_panel":
			b.top_color = Color("f0efeb")
			b.bottom_color = Color("dcdcd6")
			b.hatch_color = Color(0, 0, 0, 0.035)
			b.hatch_spacing = 8
			b.hatch_width = 1.5
			b.hatch_from = 0.6
			b.accent_color = Kit.ACCENT
			b.accent_top = 4
			b.chamfer = 18
			b.chamfer_corners = 5
			b.shadow_size = 30
			b.shadow_color = Color(0, 0, 0, 0.55)
			b.shadow_offset = Vector2(0, 10)
			m = Vector4(30, 24, 30, 30)
		"dialog_dark":
			b.top_color = Color("17191ef7")
			b.bottom_color = Color("101215f7")
			b.border_width = 1.0
			b.border_color = Color(1, 1, 1, 0.12)
			b.top_line_color = Color(1, 1, 1, 0.16)
			b.chamfer = 18
			b.chamfer_corners = 5
			b.shadow_size = 30
			b.shadow_color = Color(0, 0, 0, 0.55)
			b.shadow_offset = Vector2(0, 10)
			m = Vector4(0, 0, 0, 0)
		"header_bar":
			b.top_color = Color("1e2126")
			b.bottom_color = Color("16181c")
			b.hatch_color = Color(1, 1, 1, 0.05)
			b.hatch_from = 0.72
			b.hatch_spacing = 6
			b.hatch_width = 1.5
			b.accent_color = Kit.ACCENT
			b.accent_left = 4
			m = Vector4(18, 6, 12, 6)
		"plate_level":
			b.top_color = Color("24272d")
			b.bottom_color = Color("1a1c21")
			m = Vector4(14, 2, 14, 2)
		"plate_name":
			b.radius = 0
			b.top_color = Color("0a0b0d")
			b.bottom_color = Color("0a0b0d")
			b.hatch_color = Color(1, 1, 1, 0.05)
			b.hatch_from = 0.8
			b.hatch_spacing = 6
			b.hatch_width = 1.5
			m = Vector4(18, 2, 18, 2)
		"tile_dark":
			b.top_color = Color("1b1e24d9")
			b.bottom_color = Color("121418d9")
			b.border_width = 1.0
			b.border_color = Color(1, 1, 1, 0.2)
			b.chamfer = 10
			b.chamfer_corners = 5
			b.shadow_size = 6
			b.shadow_color = Color(0, 0, 0, 0.35)
			b.shadow_offset = Vector2(0, 3)
			m = Vector4(0, 0, 0, 0)
		"tile_accent":
			b.top_color = Color("ff5a2e")
			b.bottom_color = Color("e63a10")
			b.border_width = 1.0
			b.border_color = Color("ffb199")
			b.chamfer = 10
			b.chamfer_corners = 5
			b.shadow_size = 8
			b.shadow_color = Color(1.0, 0.28, 0.08, 0.3)
			b.shadow_offset = Vector2.ZERO
			m = Vector4(0, 0, 0, 0)
		"tile_orange":
			b.top_color = Color("ff6a2a")
			b.bottom_color = Color("f0440e")
			b.border_width = 1.0
			b.border_color = Color("ffc0a0")
			b.chamfer = 10
			b.chamfer_corners = 5
			b.shadow_size = 10
			b.shadow_color = Color(1.0, 0.35, 0.1, 0.4)
			b.shadow_offset = Vector2.ZERO
			m = Vector4(0, 0, 0, 0)
		"tile_white":
			b.top_color = Color("f2f1ed")
			b.bottom_color = Color("d6d8d2")
			b.border_width = 1.0
			b.border_color = Color("ffffff")
			b.chamfer = 10
			b.chamfer_corners = 5
			b.shadow_size = 6
			b.shadow_color = Color(0, 0, 0, 0.35)
			b.shadow_offset = Vector2(0, 3)
			m = Vector4(0, 0, 0, 0)
		"disc_light":
			b.radius = 999
			b.top_color = Color("f2f1ed")
			b.bottom_color = Color("dcdcd6")
			b.border_width = 1.0
			b.border_color = Color("bfc2bb")
			b.shadow_size = 4
			b.shadow_color = Color(0, 0, 0, 0.2)
			b.shadow_offset = Vector2(0, 2)
			m = Vector4(0, 0, 0, 0)
		"notice":
			b.top_color = Color("0a0b0dc7")
			b.bottom_color = Color("0a0b0dc7")
			b.border_width = 1.0
			b.border_color = Color(1, 1, 1, 0.12)
			b.chamfer = 8
			b.chamfer_corners = 5
			m = Vector4(0, 0, 0, 0)
		"meter":
			b.top_color = Color("0d0e10e6")
			b.bottom_color = Color("08090ae6")
			b.border_width = 1.0
			b.border_color = Color(Kit.ACCENT, 0.8)
			b.hatch_color = Color(Kit.ACCENT, 0.1)
			b.hatch_spacing = 6
			b.hatch_width = 1.5
			m = Vector4(10, 6, 14, 6)
		"avatar":
			b.top_color = Color("23262c")
			b.bottom_color = Color("0e0f12")
			b.border_width = 2.0
			b.border_color = Color(Kit.BONE, 0.9)
			b.chamfer = 10
			b.chamfer_corners = 5
			b.shadow_size = 6
			b.shadow_color = Color(0, 0, 0, 0.45)
			b.shadow_offset = Vector2(0, 3)
			m = Vector4(0, 0, 0, 0)
		"chip_off":
			b.top_color = Color("1f2227")
			b.bottom_color = Color("17191d")
			b.border_width = 1.0
			b.border_color = Color(1, 1, 1, 0.12)
			b.chamfer = 6
			b.chamfer_corners = 5
			m = Vector4(6, 4, 6, 4)
		"chip_on":
			b.top_color = Color("ff5a2e")
			b.bottom_color = Color("e63a10")
			b.border_width = 1.0
			b.border_color = Color("ffb199")
			b.chamfer = 6
			b.chamfer_corners = 5
			b.shadow_size = 7
			b.shadow_color = Color(1.0, 0.28, 0.08, 0.35)
			b.shadow_offset = Vector2.ZERO
			m = Vector4(6, 4, 6, 4)
		# ---------------- buttons
		"btn_primary", "btn_primary_hover", "btn_primary_pressed":
			b.top_color = Color("ff5a2e")
			b.bottom_color = Color("e8390f")
			b.border_width = 1.0
			b.border_color = Color("ffa486")
			b.chamfer = 12
			b.chamfer_corners = 5
			b.shadow_size = 8
			b.shadow_color = Color(1.0, 0.25, 0.06, 0.26)
			b.shadow_offset = Vector2(0, 2)
			b.hatch_color = Color(1, 1, 1, 0.09)
			b.hatch_from = 0.76
			b.hatch_spacing = 6
			b.hatch_width = 1.5
			if kind == "btn_primary_hover":
				b.top_color = b.top_color.lightened(0.08)
			elif kind == "btn_primary_pressed":
				b.top_color = Color("db3611")
				b.bottom_color = Color("c42c0b")
		"btn_secondary", "btn_secondary_hover", "btn_secondary_pressed":
			b.top_color = Color("23262ce8")
			b.bottom_color = Color("17191de8")
			b.border_width = 1.0
			b.border_color = Color(1, 1, 1, 0.22)
			b.top_line_color = Color(1, 1, 1, 0.1)
			b.chamfer = 12
			b.chamfer_corners = 5
			b.shadow_size = 6
			b.shadow_color = Color(0, 0, 0, 0.32)
			b.shadow_offset = Vector2(0, 3)
			if kind == "btn_secondary_hover":
				b.top_color = b.top_color.lightened(0.07)
			elif kind == "btn_secondary_pressed":
				b.top_color = Color("141619e8")
				b.bottom_color = Color("111316e8")
		"btn_danger", "btn_danger_hover", "btn_danger_pressed":
			b.top_color = Color("2b1213")
			b.bottom_color = Color("1d0b0c")
			b.border_width = 1.5
			b.border_color = Color("ff4d3d")
			b.chamfer = 12
			b.chamfer_corners = 5
			b.hatch_color = Color(1.0, 0.3, 0.24, 0.12)
			b.hatch_from = 0.76
			b.hatch_spacing = 6
			b.hatch_width = 1.5
			b.shadow_size = 6
			b.shadow_color = Color(0.5, 0.05, 0.0, 0.3)
			b.shadow_offset = Vector2(0, 3)
			if kind == "btn_danger_hover":
				b.top_color = b.top_color.lightened(0.06)
			elif kind == "btn_danger_pressed":
				b.top_color = Color("1d0b0c")
				b.bottom_color = Color("150809")
		"btn_light", "btn_light_hover", "btn_light_pressed":
			b.top_color = Color("f2f1ed")
			b.bottom_color = Color("d6d8d2")
			b.border_width = 1.0
			b.border_color = Color("b9bcb5")
			b.chamfer = 12
			b.chamfer_corners = 5
			b.shadow_size = 5
			b.shadow_color = Color(0, 0, 0, 0.2)
			b.shadow_offset = Vector2(0, 2)
			if kind == "btn_light_pressed":
				b.top_color = Color("dcdcd6")
				b.bottom_color = Color("cbcdc7")
		"btn_orange", "btn_orange_hover", "btn_orange_pressed":
			b.top_color = Color("ff6a2a")
			b.bottom_color = Color("f2400c")
			b.border_width = 1.0
			b.border_color = Color("ffc4a8")
			b.chamfer = 12
			b.chamfer_corners = 5
			b.hatch_color = Color(1, 1, 1, 0.11)
			b.hatch_from = 0.7
			b.hatch_spacing = 6
			b.hatch_width = 1.5
			b.shadow_size = 12
			b.shadow_color = Color(1.0, 0.32, 0.08, 0.45)
			b.shadow_offset = Vector2.ZERO
			if kind == "btn_orange_pressed":
				b.top_color = Color("e8480e")
				b.bottom_color = Color("d0390a")
		"btn_primary_disabled", "btn_secondary_disabled", "btn_danger_disabled", "btn_orange_disabled":
			# Flat and quiet: clearly "not now", never mistaken for a pressed button.
			b.top_color = Color("25282dd9")
			b.bottom_color = Color("1b1d21d9")
			b.border_width = 1.0
			b.border_color = Color(1, 1, 1, 0.08)
			b.chamfer = 12
			b.chamfer_corners = 5
		"btn_light_disabled":
			b.top_color = Color("dcdcd7")
			b.bottom_color = Color("cfd0ca")
			b.border_width = 1.0
			b.border_color = Color("c4c6c0")
			b.chamfer = 12
			b.chamfer_corners = 5
		"seg_off":
			b.top_color = Color("1a1d22cc")
			b.bottom_color = Color("14161acc")
			b.border_width = 1.0
			b.border_color = Color(1, 1, 1, 0.12)
			b.chamfer = 6
			b.chamfer_corners = 5
			m = Vector4(14, 6, 14, 6)
		"seg_on", "seg_on_pressed":
			b.top_color = Color("ff5a2e")
			b.bottom_color = Color("e8390f")
			b.border_width = 1.0
			b.border_color = Color("ffa486")
			b.chamfer = 6
			b.chamfer_corners = 5
			b.shadow_size = 6
			b.shadow_color = Color(1.0, 0.28, 0.08, 0.3)
			b.shadow_offset = Vector2.ZERO
			m = Vector4(14, 6, 14, 6)
		"tab_on", "tab_on_flat":
			# tab_on_flat: the same plate without the accent bar (Kit.tab_strip slides its own).
			b.radius = 0
			b.top_color = Color("f2f1ed")
			b.bottom_color = Color("e2e2dd")
			if kind == "tab_on":
				b.accent_color = Kit.ACCENT
				b.accent_top = 4
			m = Vector4(18, 8, 18, 6)
		"tab_off":
			b.radius = 0
			b.top_color = Color("16181dd9")
			b.bottom_color = Color("101215d9")
			b.accent_color = Color(1, 1, 1, 0.12)
			b.accent_top = 1
			m = Vector4(18, 8, 18, 6)
		"line_edit", "line_edit_focus":
			b.top_color = Color("0a0b0d")
			b.bottom_color = Color("111316")
			b.border_width = 1.5
			b.border_color = Kit.ACCENT if kind == "line_edit_focus" else Color(1, 1, 1, 0.16)
			m = Vector4(18, 10, 18, 10)
		"empty":
			b.fill = false
			m = Vector4(0, 0, 0, 0)
		_:
			push_warning("UITheme.style: unknown kind '%s'" % kind)
	if kind.begins_with("btn_"):
		m = Vector4(26, 8, 26, 8)
		if kind.ends_with("_pressed"):
			b.offset_y = 2.0
			b.shadow_size = maxi(b.shadow_size - 4, 0)
			m.y += 2.0
	if pad >= 0:
		m = Vector4(pad, pad, pad, pad)
	b.content_margin_left = m.x
	b.content_margin_top = m.y
	b.content_margin_right = m.z
	b.content_margin_bottom = m.w
	return b.commit()


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
		t.set_color("font_color", v[0], Kit.INK)
	t.set_type_variation("CaptionLabel", "Label")
	t.set_font_size("font_size", "CaptionLabel", Kit.SIZE_SMALL)
	t.set_color("font_color", "CaptionLabel", Kit.INK_DIM)
	t.set_type_variation("NumberLabel", "Label")
	t.set_font("font", "NumberLabel", Kit.font("black"))
	t.set_font_size("font_size", "NumberLabel", Kit.SIZE_BUTTON)

	# RichTextLabel.
	t.set_color("default_color", "RichTextLabel", Kit.INK)
	t.set_font("normal_font", "RichTextLabel", Kit.font("regular"))
	t.set_font("bold_font", "RichTextLabel", Kit.font("extrabold"))
	t.set_font_size("normal_font_size", "RichTextLabel", Kit.SIZE_BODY)
	t.set_font_size("bold_font_size", "RichTextLabel", Kit.SIZE_BODY)

	# Buttons: the plain Button looks like the secondary button.
	_button_type(t, "Button", "btn_secondary", Kit.INK, Color("8e9bb0"))
	_button_type(t, "PrimaryButton", "btn_primary", Color.WHITE, Color("8e9bb0"))
	_button_type(t, "SecondaryButton", "btn_secondary", Kit.INK, Color("8e9bb0"))
	_button_type(t, "DangerButton", "btn_danger", Color("ff8a7a"), Color("8e9bb0"))
	_button_type(t, "LightButton", "btn_light", Kit.TEXT, Color("a3acb6"))
	_button_type(t, "OrangeButton", "btn_orange", Color.WHITE, Color("8e9bb0"))
	for v in ["PrimaryButton", "SecondaryButton", "DangerButton", "LightButton", "OrangeButton"]:
		t.set_type_variation(v, "Button")
	for v in ["Button", "PrimaryButton", "SecondaryButton", "DangerButton", "OrangeButton"]:
		t.set_constant("outline_size", v, 0)
	t.set_color("font_shadow_color", "PrimaryButton", Color(0.35, 0.04, 0.0, 0.35))
	t.set_constant("shadow_offset_y", "PrimaryButton", 1)

	t.set_type_variation("SegmentButton", "Button")
	for st in ["normal", "hover", "disabled"]:
		t.set_stylebox(st, "SegmentButton", style("seg_off"))
	t.set_stylebox("pressed", "SegmentButton", style("seg_on"))
	t.set_stylebox("hover_pressed", "SegmentButton", style("seg_on"))
	t.set_stylebox("focus", "SegmentButton", StyleBoxEmpty.new())
	t.set_font("font", "SegmentButton", Kit.font("cond"))
	t.set_font_size("font_size", "SegmentButton", 26)
	t.set_color("font_color", "SegmentButton", Color("c9ced5"))
	t.set_color("font_hover_color", "SegmentButton", Kit.INK)
	t.set_color("font_pressed_color", "SegmentButton", Color.WHITE)
	t.set_color("font_hover_pressed_color", "SegmentButton", Color.WHITE)
	t.set_color("font_focus_color", "SegmentButton", Color("c9ced5"))
	t.set_color("font_disabled_color", "SegmentButton", Color("6d727a"))
	t.set_color("icon_normal_color", "SegmentButton", Color(0.82, 0.84, 0.87))
	t.set_color("icon_pressed_color", "SegmentButton", Color.WHITE)
	t.set_color("icon_hover_pressed_color", "SegmentButton", Color.WHITE)

	# Page / dialog tabs (Kit.tab_strip): white active plate with a cyan top bar.
	t.set_type_variation("TabButton", "Button")
	for st in ["normal", "hover", "disabled"]:
		t.set_stylebox(st, "TabButton", style("tab_off"))
	t.set_stylebox("pressed", "TabButton", style("tab_on"))
	t.set_stylebox("hover_pressed", "TabButton", style("tab_on"))
	t.set_stylebox("focus", "TabButton", StyleBoxEmpty.new())
	t.set_font("font", "TabButton", Kit.font("cond_bold"))
	t.set_font_size("font_size", "TabButton", 28)
	t.set_color("font_color", "TabButton", Color("d5d9de"))
	t.set_color("font_hover_color", "TabButton", Color.WHITE)
	t.set_color("font_focus_color", "TabButton", Color("d5d9de"))
	t.set_color("font_pressed_color", "TabButton", Kit.TEXT)
	t.set_color("font_hover_pressed_color", "TabButton", Kit.TEXT)
	t.set_color("icon_normal_color", "TabButton", Color("d5d9de"))
	t.set_color("icon_pressed_color", "TabButton", Kit.ACCENT)
	t.set_color("icon_hover_pressed_color", "TabButton", Kit.ACCENT)
	t.set_constant("h_separation", "TabButton", 10)

	t.set_type_variation("BareButton", "Button")
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		t.set_stylebox(st, "BareButton", StyleBoxEmpty.new())

	# Panels.
	t.set_stylebox("panel", "PanelContainer", style("glass"))
	t.set_stylebox("panel", "Panel", style("glass"))
	var panels := {
		"GlassPanel": "glass", "CardPanel": "card", "InsetPanel": "inset", "PlainPanel": "plain",
		"ChipPanel": "chip", "TagPanel": "tag", "ToastPanel": "toast", "ModalPanel": "modal",
		"WhitePanel": "white", "PaperPanel": "paper", "LightInsetPanel": "light_inset", "RowPanel": "row",
		"DialogPanel": "dialog", "SpeechPanel": "speech", "BarPanel": "bar",
	}
	for v: String in panels:
		t.set_type_variation(v, "PanelContainer")
		t.set_stylebox("panel", v, style(panels[v]))

	# Scrollbars: invisible and zero-width (touch scrolling needs no chrome; pages show more
	# content through cut-off rows and bottom fades instead of a debug-looking bar).
	var none := _blank_icon()
	for sb in ["VScrollBar", "HScrollBar"]:
		for st in ["scroll", "scroll_focus", "grabber", "grabber_highlight", "grabber_pressed"]:
			t.set_stylebox(st, sb, StyleBoxEmpty.new())
		for ic in ["increment", "increment_highlight", "increment_pressed", "decrement", "decrement_highlight", "decrement_pressed"]:
			t.set_icon(ic, sb, none)
	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())

	# Progress bar defaults (Kit.progress_bar sets its own).
	var pb_bg := KitBox.new()
	pb_bg.radius = 1
	pb_bg.top_color = Color("060708")
	pb_bg.bottom_color = Color("101215")
	t.set_stylebox("background", "ProgressBar", pb_bg.commit())
	var pb_fg := KitBox.new()
	pb_fg.radius = 3
	pb_fg.top_color = Kit.ACCENT.lightened(0.2)
	pb_fg.bottom_color = Kit.ACCENT
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
		for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
			t.set_color(c, cb, Kit.INK)
		t.set_constant("icon_max_width", cb, 0)

	# Line edit.
	t.set_stylebox("normal", "LineEdit", style("line_edit"))
	t.set_stylebox("focus", "LineEdit", style("line_edit_focus"))
	t.set_stylebox("read_only", "LineEdit", style("line_edit"))
	t.set_color("font_color", "LineEdit", Kit.INK)
	t.set_color("font_placeholder_color", "LineEdit", Color(Kit.INK_DIM, 0.6))
	t.set_color("caret_color", "LineEdit", Kit.ACCENT)
	t.set_color("selection_color", "LineEdit", Color(Kit.ACCENT, 0.3))
	t.set_font_size("font_size", "LineEdit", Kit.SIZE_BODY)

	# Slider.
	var track := KitBox.new()
	track.radius = 3
	track.top_color = Color("060708")
	track.bottom_color = Color("111316")
	track.border_width = 1
	track.border_color = Color(1, 1, 1, 0.12)
	track.content_margin_top = 4
	track.content_margin_bottom = 4
	t.set_stylebox("slider", "HSlider", track.commit())
	var area := KitBox.new()
	area.radius = 3
	area.top_color = Kit.ACCENT.lightened(0.15)
	area.bottom_color = Kit.ACCENT
	area.content_margin_top = 4
	area.content_margin_bottom = 4
	t.set_stylebox("grabber_area", "HSlider", area.commit())
	t.set_stylebox("grabber_area_highlight", "HSlider", area)
	var knob := Kit.icon_texture("knob")
	if knob:
		t.set_icon("grabber", "HSlider", knob)
		t.set_icon("grabber_highlight", "HSlider", knob)

	# Tabs (if a screen uses TabBar / TabContainer): white active tab with a cyan top bar.
	for tb in ["TabBar", "TabContainer"]:
		t.set_stylebox("tab_selected", tb, style("tab_on"))
		t.set_stylebox("tab_hovered", tb, style("tab_off"))
		t.set_stylebox("tab_unselected", tb, style("tab_off"))
		t.set_stylebox("tab_disabled", tb, style("tab_off"))
		t.set_stylebox("tab_focus", tb, StyleBoxEmpty.new())
		t.set_color("font_selected_color", tb, Kit.TEXT)
		t.set_color("font_unselected_color", tb, Kit.INK_DIM)
		t.set_color("font_hovered_color", tb, Kit.INK)
		t.set_font("font", tb, Kit.font("extrabold"))
		t.set_font_size("font_size", tb, 26)
		t.set_constant("h_separation", tb, 8)
	t.set_stylebox("panel", "TabContainer", style("white"))

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


static func _button_type(t: Theme, type: String, base: String, text: Color, disabled_text: Color) -> void:
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
	t.set_color("font_disabled_color", type, disabled_text)
	t.set_constant("h_separation", type, 12)
	t.set_constant("icon_max_width", type, 44)


static func _blank_icon() -> Texture2D:
	var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(img)
