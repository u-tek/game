class_name Kit
extends RefCounted
## Kit: static UI builders for Halo & Horn. Every screen builds its UI with these so the
## whole game shares one look ("Twilight cathedral": dark indigo glass, gold hairlines).
##
## Quick reference (all static, all return ready-to-add Controls):
##   Tokens     Kit.BG, PANEL, PANEL_HI, LINE, INK, INK_DIM, GOLD, GOLD_LIGHT, EMBER, VIOLET,
##              SKY, GOOD, RARE, EPIC, LEGENDARY, OUTLINE; SIZE_SMALL/BODY/BUTTON/HEADER/HERO;
##              BUTTON_H (88), GAP (16), PAD (24)
##   Text       label, title, header, body, number, caption, font
##   Buttons    primary_button, secondary_button, danger_button, icon_button, cost_button,
##              segmented, toggle, make_tappable, add_press_fx
##   Layout     vbox, hbox, grid, flow, scroll, margin, center, spacer, expand, add, divider
##   Panels     panel ("glass" | "card" | "inset" | "plain"), card, style
##   Widgets    progress_bar/set_progress, star_row, currency_icon, currency_chip/set_chip_amount,
##              reward_list, reward_tile, faction_badge, role_badge, rarity_badge, tag,
##              hero_card, dot/set_dot, section_header, stat_row, empty_state, icon, glow, rays
##   Colors     faction_color, rarity_color, rarity_frame, tier_color
##   Numbers    format_num (12.5K / 3.4M), format_full (1,234,567), format_time (2h 05m)
##   Motion     pop_in, pulse, shake, count_to
##
## Conventions: sizes are viewport px on the 720 px wide canvas. Builders never touch Game
## state except hero_card (reads owned level/stars when not given) and reward tiles.

const KitBox := preload("res://src/ui/components/kit_box.gd")
const HeroCard := preload("res://src/ui/components/hero_card.gd")
const Filigree := preload("res://src/ui/components/filigree.gd")
const Dot := preload("res://src/ui/components/dot.gd")
const Rays := preload("res://src/ui/components/rays.gd")

# ------------------------------------------------------------------ design tokens

const BG := Color("120e24")
const PANEL := Color("1d1738e6")
const PANEL_HI := Color("2a2150")
const LINE := Color("e8c36a59")
const INK := Color("f3ecdf")
const INK_DIM := Color("a99fc4")
const GOLD := Color("f2c14e")
const GOLD_LIGHT := Color("ffe5a0")
const GOLD_DEEP := Color("b07a1c")
const EMBER := Color("d9412b")
const VIOLET := Color("8e6ce0")
const SKY := Color("6fc3e8")
const RARE := Color("4fa3e0")
const EPIC := Color("b36bf0")
const LEGENDARY := Color("f5b83d")
const GOOD := Color("5cd6a0")
## Dark indigo used for text outlines and icon outlines.
const OUTLINE := Color("1a1030")
const RED_DOT := Color("ff4536")

const SIZE_SMALL := 22
const SIZE_BODY := 26
const SIZE_BUTTON := 32
const SIZE_HEADER := 40
const SIZE_HERO := 56

## Minimum touch target height.
const BUTTON_H := 88
const GAP := 16
const PAD := 24

const CURRENCIES: Array[String] = ["gold", "gems", "scrolls", "hero_exp", "dust"]
const CURRENCY_NAMES := {
	"gold": "Gold", "gems": "Gems", "scrolls": "Summon Scrolls", "hero_exp": "Hero EXP", "dust": "Dust",
}
const FACTIONS: Array[String] = ["celestial", "infernal", "fallen"]
const FACTION_NAMES := {"celestial": "Celestial", "infernal": "Infernal", "fallen": "Fallen"}
const ROLES: Array[String] = ["guardian", "striker", "caster", "support", "assassin"]
const ROLE_NAMES := {
	"guardian": "Guardian", "striker": "Striker", "caster": "Caster", "support": "Support", "assassin": "Assassin",
}
const RARITY_NAMES := {"rare": "Rare", "epic": "Epic", "legendary": "Legendary"}
const RARITY_STARS := {"rare": 1, "epic": 2, "legendary": 3}
const STAT_NAMES := {"hp": "HP", "atk": "Attack", "def": "Defense", "spd": "Speed", "crit": "Crit"}
const GEAR_SLOT_NAMES := {"weapon": "Weapon", "armor": "Armor", "helm": "Helm", "charm": "Charm"}
const MAX_STARS := 6

const _FONT_FILES := {
	"regular": "res://assets/fonts/Nunito-Regular.ttf",
	"bold": "res://assets/fonts/Nunito-Bold.ttf",
	"extrabold": "res://assets/fonts/Nunito-ExtraBold.ttf",
	"black": "res://assets/fonts/Nunito-Black.ttf",
	"title": "res://assets/fonts/MarcellusSC-Regular.ttf",
}

static var _fonts: Dictionary = {}
static var _icons: Dictionary = {}
static var _glow_textures: Dictionary = {}
static var _gray_material: ShaderMaterial


# ------------------------------------------------------------------ fonts & icons

## Font by weight: "regular", "bold", "extrabold", "black" (Nunito) or "title" (Marcellus SC).
static func font(weight: String = "bold") -> Font:
	if not _fonts.has(weight):
		var path: String = _FONT_FILES.get(weight, _FONT_FILES["bold"])
		_fonts[weight] = load(path)
	return _fonts[weight]


## Texture of a UI icon in assets/art/ui/<name>.svg (null if missing, never crashes).
static func icon_texture(name: String) -> Texture2D:
	if _icons.has(name):
		return _icons[name]
	var path := "res://assets/art/ui/%s.svg" % name
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path)
	else:
		push_warning("Kit: missing icon '%s'" % name)
	_icons[name] = tex
	return tex


## Square icon TextureRect. `color` tints (white = original colors).
static func icon(name: String, size: float = 40.0, color: Color = Color.WHITE) -> TextureRect:
	var t := TextureRect.new()
	t.texture = icon_texture(name)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.custom_minimum_size = Vector2(size, size)
	t.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.modulate = color
	return t


# ------------------------------------------------------------------ text

## Generic label. weight: "regular" | "bold" | "extrabold" | "black" | "title".
## outline > 0 adds a dark outline (use on top of art).
static func label(text: String, size: int = SIZE_BODY, color: Color = INK, weight: String = "bold", outline: int = 0) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(weight))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if outline > 0:
		l.add_theme_constant_override("outline_size", outline)
		l.add_theme_color_override("font_outline_color", OUTLINE)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


## Big display title (hero names, victory banners): Marcellus SC, gold, outline + shadow.
static func title(text: String, size: int = SIZE_HERO, color: Color = GOLD_LIGHT) -> Label:
	var l := label(text, size, color, "title", maxi(4, size / 8))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", maxi(2, size / 14))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


## Screen / panel header: Marcellus SC 40, gold-cream.
static func header(text: String, size: int = SIZE_HEADER, color: Color = GOLD_LIGHT) -> Label:
	var l := label(text, size, color, "title", 4)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
	l.add_theme_constant_override("shadow_offset_y", 2)
	return l


## Body text: Nunito, word-wrapped by default (expands horizontally to get a width).
static func body(text: String, size: int = SIZE_BODY, color: Color = INK, wrap: bool = true) -> Label:
	var l := label(text, size, color, "bold")
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.custom_minimum_size.x = 40
	return l


## Number display: Nunito Black with a dark outline. ints are compact-formatted (12.5K).
static func number(value: Variant, size: int = SIZE_BUTTON, color: Color = INK) -> Label:
	var text := format_num(int(value)) if (value is int or value is float) else str(value)
	return label(text, size, color, "black", maxi(4, size / 6))


## Small secondary text (22 px, dim).
static func caption(text: String, size: int = SIZE_SMALL, color: Color = INK_DIM) -> Label:
	return label(text, size, color, "bold")


# ------------------------------------------------------------------ buttons

## Gold call-to-action button (88 px tall). icon = optional assets/art/ui icon name.
static func primary_button(text: String, on_pressed: Callable = Callable(), icon_name: String = "") -> Button:
	return _button(text, &"PrimaryButton", on_pressed, icon_name)


## Indigo glass button with gold border, for secondary actions.
static func secondary_button(text: String, on_pressed: Callable = Callable(), icon_name: String = "") -> Button:
	return _button(text, &"SecondaryButton", on_pressed, icon_name)


## Ember red button for destructive actions (reset save, dismantle).
static func danger_button(text: String, on_pressed: Callable = Callable(), icon_name: String = "") -> Button:
	return _button(text, &"DangerButton", on_pressed, icon_name)


## Square/round icon button with an 88 px touch target.
## look: "round" (glass disc), "gold" (gold disc), "bare" (icon only).
static func icon_button(icon_name: String, on_pressed: Callable = Callable(), size: float = 88.0, look: String = "round") -> Button:
	var b := Button.new()
	b.theme_type_variation = &"BareButton"
	b.custom_minimum_size = Vector2(maxf(size, 64.0), maxf(size, 64.0))
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	b.tooltip_text = ""
	var disc_size := size * 0.78
	if look != "bare":
		var disc := Panel.new()
		disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		disc.add_theme_stylebox_override("panel", UITheme.style("disc_gold" if look == "gold" else "disc"))
		_center_child(b, disc, Vector2(disc_size, disc_size))
	var ic := icon(icon_name, disc_size * (0.62 if look != "bare" else 0.9))
	_center_child(b, ic, ic.custom_minimum_size)
	add_press_fx(b)
	if on_pressed.is_valid():
		_connect_pressed(b, on_pressed)
	return b


## Button with a label and a price line, e.g. ("Summon x10", "gems", 2700).
## look: "primary" | "secondary". Shows the price in red when the player can't afford it
## (pass affordable = false), still pressable so the screen can explain why.
static func cost_button(text: String, currency_id: String, amount: int, on_pressed: Callable = Callable(), look: String = "primary", affordable: bool = true) -> Button:
	var b := _button("", &"PrimaryButton" if look == "primary" else &"SecondaryButton", on_pressed, "")
	b.custom_minimum_size = Vector2(240, 104)
	var dark := look == "primary"
	var col := vbox(0)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := label(text, 30, Color("3d2306") if dark else INK, "extrabold")
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(t)
	var price := hbox(6)
	price.alignment = BoxContainer.ALIGNMENT_CENTER
	price.mouse_filter = Control.MOUSE_FILTER_IGNORE
	price.add_child(currency_icon(currency_id, 30))
	var pc := Color("8a1c0c") if not affordable and dark else (EMBER if not affordable else (Color("3d2306") if dark else GOLD_LIGHT))
	price.add_child(label(format_full(amount), 24, pc, "black"))
	col.add_child(price)
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_bottom = -6
	b.add_child(col)
	b.set_meta("price_box", price)
	return b


## Row of toggle tabs (one selected). options: Array of String or {text, icon}.
## on_select(index: int) fires when the selection changes.
static func segmented(options: Array, selected: int, on_select: Callable = Callable(), height: float = 80.0) -> HBoxContainer:
	var row := hbox(8)
	var group := ButtonGroup.new()
	for i in options.size():
		var opt: Variant = options[i]
		var b := Button.new()
		b.theme_type_variation = &"SegmentButton"
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_filter = Control.MOUSE_FILTER_PASS
		b.custom_minimum_size = Vector2(0, height)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.clip_text = true
		if opt is Dictionary:
			b.text = str(opt.get("text", ""))
			if opt.has("icon"):
				b.icon = icon_texture(str(opt.icon))
				b.add_theme_constant_override("icon_max_width", int(height * 0.5))
				b.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		else:
			b.text = str(opt)
		b.button_pressed = i == selected
		var idx := i
		b.toggled.connect(func(on: bool) -> void:
			if on:
				UI.sfx("tap")
				if on_select.is_valid():
					on_select.call(idx))
		row.add_child(b)
	return row


## On/off switch (settings). on_toggled(on: bool).
static func toggle(on: bool, on_toggled: Callable = Callable()) -> CheckButton:
	var c := CheckButton.new()
	c.button_pressed = on
	c.focus_mode = Control.FOCUS_NONE
	c.mouse_filter = Control.MOUSE_FILTER_PASS
	c.custom_minimum_size = Vector2(120, BUTTON_H)
	c.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	c.toggled.connect(func(v: bool) -> void:
		UI.sfx("tap")
		if on_toggled.is_valid():
			on_toggled.call(v))
	return c


## Makes any Control tappable: adds an invisible full-size Button on top, a press
## animation on `target` and the tap sound. Returns the overlay Button.
static func make_tappable(target: Control, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.theme_type_variation = &"BareButton"
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	b.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	target.add_child(b)
	add_press_fx(b, target)
	_connect_pressed(b, on_pressed)
	return b


## Press animation (squash to 94% and spring back) on `button`, scaling `target`
## (defaults to the button). Safe inside ScrollContainers (cancelled presses restore).
static func add_press_fx(button: BaseButton, target: Control = null) -> void:
	var t: Control = target if target else button
	t.resized.connect(func() -> void: t.pivot_offset = t.size * 0.5)
	button.button_down.connect(func() -> void:
		button.set_meta("_down_at", button.get_global_mouse_position())
		_scale_to(t, 0.94, 0.06))
	button.button_up.connect(func() -> void: _scale_to(t, 1.0, 0.18))
	button.draw.connect(func() -> void:
		var mode := button.get_draw_mode()
		if mode != BaseButton.DRAW_PRESSED and mode != BaseButton.DRAW_HOVER_PRESSED and t.scale.x < 0.999:
			_scale_to(t, 1.0, 0.18))


static func _scale_to(c: Control, s: float, dur: float) -> void:
	if not c.is_inside_tree():
		return
	var prev: Variant = c.get_meta("_press_tween", null)
	if prev is Tween and (prev as Tween).is_valid():
		(prev as Tween).kill()
	var tw := c.create_tween()
	if s < 1.0:
		tw.tween_property(c, "scale", Vector2(s, s), dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	else:
		tw.tween_property(c, "scale", Vector2.ONE, dur).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	c.set_meta("_press_tween", tw)


## Connects `pressed` with the tap sound and a drag guard (a press that turned into a
## scroll gesture does not fire).
static func _connect_pressed(b: BaseButton, cb: Callable, sound: String = "tap") -> void:
	b.pressed.connect(func() -> void:
		var down: Variant = b.get_meta("_down_at", null)
		if down is Vector2 and (down as Vector2).distance_to(b.get_global_mouse_position()) > 36.0:
			return
		if sound != "":
			UI.sfx(sound)
		if cb.is_valid():
			cb.call())


static func _button(text: String, variation: StringName, on_pressed: Callable, icon_name: String) -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = variation
	b.custom_minimum_size = Vector2(160, BUTTON_H)
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	if icon_name != "":
		b.icon = icon_texture(icon_name)
		b.add_theme_constant_override("icon_max_width", 44)
		b.add_theme_constant_override("h_separation", 12)
		b.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_press_fx(b)
	if on_pressed.is_valid():
		_connect_pressed(b, on_pressed)
	return b


static func _center_child(parent: Control, child: Control, sz: Vector2) -> void:
	child.set_anchors_preset(Control.PRESET_CENTER)
	child.offset_left = -sz.x * 0.5
	child.offset_right = sz.x * 0.5
	child.offset_top = -sz.y * 0.5
	child.offset_bottom = sz.y * 0.5
	parent.add_child(child)


# ------------------------------------------------------------------ layout

## Vertical stack with `gap` px between children.
static func vbox(gap: int = GAP) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", gap)
	v.mouse_filter = Control.MOUSE_FILTER_PASS
	return v


## Horizontal row with `gap` px between children.
static func hbox(gap: int = GAP) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", gap)
	h.mouse_filter = Control.MOUSE_FILTER_PASS
	return h


## Grid with `columns` columns and equal gaps.
static func grid(columns: int, gap: int = GAP) -> GridContainer:
	var g := GridContainer.new()
	g.columns = columns
	g.add_theme_constant_override("h_separation", gap)
	g.add_theme_constant_override("v_separation", gap)
	g.mouse_filter = Control.MOUSE_FILTER_PASS
	return g


## Wrapping row (reward lists, tags). center = center each line.
static func flow(gap: int = GAP, center_items: bool = false) -> HFlowContainer:
	var f := HFlowContainer.new()
	f.add_theme_constant_override("h_separation", gap)
	f.add_theme_constant_override("v_separation", gap)
	f.mouse_filter = Control.MOUSE_FILTER_PASS
	if center_items:
		f.alignment = FlowContainer.ALIGNMENT_CENTER
	return f


## Vertical touch-scroll area around `content` (content fills the width).
## Put the ScrollContainer in a layout slot that gives it a height (e.g. expand it).
static func scroll(content: Control) -> ScrollContainer:
	var s := ScrollContainer.new()
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	s.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	s.scroll_deadzone = 14
	s.follow_focus = false
	s.mouse_filter = Control.MOUSE_FILTER_PASS
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.add_child(content)
	return s


## Wraps `child` in a MarginContainer (h = left/right, v = top/bottom).
static func margin(child: Control, h: int = PAD, v: int = 0) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", h)
	m.add_theme_constant_override("margin_right", h)
	m.add_theme_constant_override("margin_top", v)
	m.add_theme_constant_override("margin_bottom", v)
	m.mouse_filter = Control.MOUSE_FILTER_PASS
	if child:
		m.add_child(child)
	return m


## Centers `child` in the available space.
static func center(child: Control) -> CenterContainer:
	var c := CenterContainer.new()
	c.mouse_filter = Control.MOUSE_FILTER_PASS
	c.add_child(child)
	return c


## Empty space. expand = take all free space in the parent box.
static func spacer(w: float = 0.0, h: float = 0.0, expand_fill: bool = false) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if expand_fill:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c


## Sets horizontal (and optionally vertical) expand-fill; returns the control.
static func expand(c: Control, vertical: bool = false) -> Control:
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if vertical:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c


## Adds several children at once; returns the parent. Kit.add(row, [a, b, c])
static func add(parent: Node, children: Array) -> Node:
	for c: Variant in children:
		if c is Node:
			parent.add_child(c)
	return parent


## Thin gold hairline that fades out at both ends.
static func divider(width: float = 0.0) -> Control:
	var row := hbox(0)
	row.custom_minimum_size = Vector2(width, 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Filigree.new()
	l.direction = -1
	l.ornament = false
	var r := Filigree.new()
	r.direction = 1
	r.ornament = false
	add(row, [l, r])
	return row


# ------------------------------------------------------------------ panels

## Panel container. kind: "glass" (ornate double gold line, default), "card" (lighter,
## for list rows), "inset" (sunken, for groups inside panels), "plain" (no border).
## pad overrides the inner padding (-1 = default for the kind).
static func panel(kind: String = "glass", pad: int = -1) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	var variations := {"glass": &"GlassPanel", "card": &"CardPanel", "inset": &"InsetPanel", "plain": &"PlainPanel"}
	p.theme_type_variation = variations.get(kind, &"GlassPanel")
	if pad >= 0:
		p.add_theme_stylebox_override("panel", style(kind, pad))
	return p


## A list-row card (shorthand for panel("card", pad)).
static func card(pad: int = -1) -> PanelContainer:
	return panel("card", pad)


## A fresh StyleBox preset (see UITheme.style for kinds). pad = content margin override.
static func style(kind: String, pad: int = -1) -> StyleBox:
	return UITheme.style(kind, pad)


## Custom house box: vertical gradient, optional border / hairline. For one-off frames.
static func box(top: Color, bottom: Color, border: Color = Color.TRANSPARENT, radius: float = 16.0, border_width: int = 2, pad: int = 0) -> StyleBox:
	var b := KitBox.new()
	b.top_color = top
	b.bottom_color = bottom
	b.radius = radius
	if border.a > 0.0:
		b.border_color = border
		b.border_width = border_width
	b.set_content_margin_all(pad)
	return b.commit()


# ------------------------------------------------------------------ progress & stars

## Rounded progress bar with gloss. text (optional) is drawn centered on the bar.
static func progress_bar(value: float, max_value: float, color: Color = GOOD, height: float = 24.0, text: String = "") -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.min_value = 0
	bar.max_value = maxf(max_value, 0.0001)
	bar.value = clampf(value, 0.0, bar.max_value)
	bar.custom_minimum_size = Vector2(80, height)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := KitBox.new()
	bg.radius = height * 0.5
	bg.top_color = Color("07050f")
	bg.bottom_color = Color("1a1433")
	bg.border_width = 1
	bg.border_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.35)
	bar.add_theme_stylebox_override("background", bg.commit())
	var fg := KitBox.new()
	fg.radius = height * 0.5
	fg.top_color = color.lightened(0.35)
	fg.bottom_color = color.darkened(0.2)
	fg.gloss = 0.35
	fg.border_width = 1
	fg.border_color = color.darkened(0.55)
	bar.add_theme_stylebox_override("fill", fg.commit())
	var l := label(text, int(clampf(height * 0.8, 16, 26)), INK, "black", 4)
	l.name = "Text"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	l.visible = text != ""
	bar.add_child(l)
	return bar


## Updates a Kit progress bar (animated by default). max_value < 0 keeps the old max.
static func set_progress(bar: ProgressBar, value: float, max_value: float = -1.0, text: String = "", animate: bool = true) -> void:
	if max_value >= 0.0:
		bar.max_value = maxf(max_value, 0.0001)
	var target := clampf(value, 0.0, bar.max_value)
	if animate and bar.is_inside_tree():
		bar.create_tween().tween_property(bar, "value", target, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	else:
		bar.value = target
	var l := bar.get_node_or_null("Text") as Label
	if l:
		l.text = text
		l.visible = text != ""


## Row of gold stars. max_stars > stars shows the missing ones as dim slots.
static func star_row(stars: int, max_stars: int = 0, size: float = 28.0) -> HBoxContainer:
	var row := hbox(int(-size * 0.12))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var total := maxi(stars, max_stars)
	for i in total:
		var filled := i < stars
		row.add_child(icon("star" if filled else "star_empty", size))
	return row


# ------------------------------------------------------------------ currencies

## Icon for a currency id ("gold", "gems", "scrolls", "hero_exp", "dust").
static func currency_icon(currency_id: String, size: float = 40.0) -> TextureRect:
	return icon(currency_id, size)


## Pill showing a currency icon and amount (compact formatted). on_plus = tap action
## (shows a small "+" and makes the whole chip tappable). Update with set_chip_amount.
static func currency_chip(currency_id: String, amount: int, on_plus: Callable = Callable(), min_width: float = 0.0) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.theme_type_variation = &"ChipPanel"
	chip.mouse_filter = Control.MOUSE_FILTER_PASS
	chip.custom_minimum_size = Vector2(min_width, 52)
	var row := hbox(6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(currency_icon(currency_id, 44))
	var n := label(format_num(amount), 25, INK, "black", 4)
	n.name = "Amount"
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(n)
	if on_plus.is_valid():
		row.add_child(icon("plus_badge", 30))
	else:
		row.add_child(spacer(4))
	chip.add_child(row)
	chip.set_meta("amount", amount)
	chip.set_meta("amount_label", n)
	if on_plus.is_valid():
		make_tappable(chip, on_plus)
	return chip


## Updates a currency chip; animate counts up/down and pulses on change.
static func set_chip_amount(chip: Control, amount: int, animate: bool = true) -> void:
	var l := chip.get_meta("amount_label", null) as Label
	if l == null:
		return
	var old: int = chip.get_meta("amount", amount)
	chip.set_meta("amount", amount)
	if old == amount:
		l.text = format_num(amount)
		return
	if animate and chip.is_inside_tree():
		count_to(l, old, amount, 0.45)
		pulse(chip, 1.08)
	else:
		l.text = format_num(amount)


# ------------------------------------------------------------------ rewards

## Normalizes a Reward dict into display entries [{kind, id, amount}] in a stable order:
## heroes, shards, gems, scrolls, gold, hero_exp, dust, gear. kind: "currency" | "hero" |
## "shard" | "gear".
static func reward_entries(reward: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for h: Variant in reward.get("heroes", []):
		out.append({"kind": "hero", "id": str(h), "amount": 1})
	var shards: Variant = reward.get("shards", {})
	if shards is Dictionary:
		for hid: Variant in shards:
			out.append({"kind": "shard", "id": str(hid), "amount": int(shards[hid])})
	for c: String in ["gems", "scrolls", "gold", "hero_exp", "dust"]:
		if int(reward.get(c, 0)) > 0:
			out.append({"kind": "currency", "id": c, "amount": int(reward[c])})
	for g: Variant in reward.get("gear", []):
		out.append({"kind": "gear", "id": str(g), "amount": 1})
	return out


## Wrapping, centered list of reward tiles for a Reward dict (currencies, heroes, shards, gear).
static func reward_list(reward: Dictionary, tile: float = 112.0, show_names: bool = true, center_items: bool = true) -> HFlowContainer:
	var f := flow(14, center_items)
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for e in reward_entries(reward):
		f.add_child(reward_tile(e.kind, e.id, int(e.amount), tile, show_names))
	return f


## One reward tile. kind: "currency" (id = currency id), "hero", "shard" (id = hero id),
## "gear" (id = gear uid). show_name adds a caption under the tile.
static func reward_tile(kind: String, id: String, amount: int, tile: float = 112.0, show_name: bool = true) -> Control:
	var col := vbox(4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name_text := ""
	var face: Control
	match kind:
		"hero":
			face = hero_card(id, {"size": tile, "show_level": false})
			name_text = str(_def(id).get("name", id))
		"shard":
			face = hero_card(id, {"size": tile, "show_level": false, "show_stars": false, "shard": true})
			var amt := label("x%s" % format_num(amount), int(tile * 0.2), INK, "black", 5)
			_corner(face, amt, Vector2(1, 1), Vector2(-8, -4))
			name_text = "%s Shards" % str(_def(id).get("name", id))
		"gear":
			var item := _gear_item(id)
			var slot := str(item.get("slot", "weapon"))
			var tier := int(item.get("tier", 1))
			face = _tile_box(tile, tier_color(tier))
			var gi := icon("gear_" + slot, tile * 0.62)
			_center_child(face, gi, gi.custom_minimum_size)
			var tl := label("T%d" % tier, int(tile * 0.18), tier_color(tier).lightened(0.3), "black", 4)
			_corner(face, tl, Vector2(0, 0), Vector2(8, 2))
			name_text = str(item.get("name", GEAR_SLOT_NAMES.get(slot, "Gear")))
		_:
			var accent := {"gold": GOLD, "gems": SKY, "scrolls": VIOLET, "hero_exp": GOOD, "dust": EPIC}
			face = _tile_box(tile, accent.get(id, GOLD))
			var ci := icon(id, tile * 0.66)
			_center_child(face, ci, ci.custom_minimum_size)
			var amt := label(format_num(amount), int(tile * 0.22), INK, "black", 5)
			_corner(face, amt, Vector2(1, 1), Vector2(-8, -2))
			name_text = str(CURRENCY_NAMES.get(id, id.capitalize()))
	col.add_child(face)
	if show_name:
		var n := caption(name_text, 18, INK_DIM)
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		n.custom_minimum_size.x = tile
		n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		n.clip_text = true
		col.add_child(n)
	col.custom_minimum_size.x = tile
	return col


static func _tile_box(tile: float, accent: Color) -> Control:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(tile, tile)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var b := KitBox.new()
	b.radius = 14
	b.top_color = accent.darkened(0.55).lerp(PANEL_HI, 0.35)
	b.bottom_color = Color("100c22")
	b.border_width = 3
	b.border_color = accent.darkened(0.1)
	b.inner_color = Color(accent.r, accent.g, accent.b, 0.35)
	b.inner_inset = 4
	b.gloss = 0.08
	b.shadow_size = 4
	b.shadow_color = Color(0, 0, 0, 0.35)
	p.add_theme_stylebox_override("panel", b.commit())
	return p


## Places `child` at a corner of `parent` (anchor (0|1, 0|1)) with an offset; the child
## grows inward.
static func _corner(parent: Control, child: Control, anchor: Vector2, off: Vector2) -> void:
	child.anchor_left = anchor.x
	child.anchor_right = anchor.x
	child.anchor_top = anchor.y
	child.anchor_bottom = anchor.y
	child.grow_horizontal = Control.GROW_DIRECTION_BEGIN if anchor.x > 0.5 else Control.GROW_DIRECTION_END
	child.grow_vertical = Control.GROW_DIRECTION_BEGIN if anchor.y > 0.5 else Control.GROW_DIRECTION_END
	child.offset_left = off.x
	child.offset_right = off.x
	child.offset_top = off.y
	child.offset_bottom = off.y
	parent.add_child(child)


static func _def(hero_id: String) -> Dictionary:
	var d: Variant = Game.hero_def(hero_id)
	return d if d is Dictionary else {}


static func _gear_item(uid: String) -> Dictionary:
	var items: Variant = Game.gear_items()
	if items is Array:
		for it: Variant in items:
			if it is Dictionary and str(it.get("uid", "")) == uid:
				return it
	return {}


# ------------------------------------------------------------------ factions, roles, rarity

## Faction accent color (celestial gold, infernal ember, fallen violet).
static func faction_color(faction: String) -> Color:
	match faction:
		"celestial":
			return GOLD
		"infernal":
			return EMBER
		"fallen":
			return VIOLET
	return INK_DIM


## Rarity color (rare blue, epic purple, legendary gold).
static func rarity_color(rarity: String) -> Color:
	match rarity:
		"rare":
			return RARE
		"epic":
			return EPIC
		"legendary":
			return LEGENDARY
	return INK_DIM


## Gear tier color 1-5 (grey, green, blue, purple, gold).
static func tier_color(tier: int) -> Color:
	var cols := [Color("9a94ad"), GOOD, RARE, EPIC, LEGENDARY]
	return cols[clampi(tier - 1, 0, 4)]


## Frame StyleBox in the rarity color (border only), for custom portraits/cards.
static func rarity_frame(rarity: String, width: int = 4, radius: float = 12.0) -> StyleBox:
	var c := rarity_color(rarity)
	var b := KitBox.new()
	b.fill = false
	b.radius = radius
	b.border_width = width
	b.border_color = c
	b.inner_color = Color(c.lightened(0.6), 0.55)
	b.inner_inset = width
	return b.commit()


## Faction emblem icon (celestial halo-sun, infernal horned flame, fallen broken halo).
static func faction_icon(faction: String, size: float = 40.0) -> TextureRect:
	return icon("faction_" + faction, size)


## Role icon (guardian, striker, caster, support, assassin), tintable.
static func role_icon(role: String, size: float = 36.0, color: Color = Color.WHITE) -> TextureRect:
	return icon("role_" + role, size, color)


## Faction emblem + name in the faction color.
static func faction_badge(faction: String, size: float = 40.0, show_name: bool = true) -> HBoxContainer:
	var row := hbox(8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(faction_icon(faction, size))
	if show_name:
		var c := faction_color(faction).lerp(Color.WHITE, 0.25)
		row.add_child(label(str(FACTION_NAMES.get(faction, faction.capitalize())), int(size * 0.62), c, "title", 4))
	return row


## Role pill: icon + role name.
static func role_badge(role: String, size: float = 36.0, show_name: bool = true) -> PanelContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = &"TagPanel"
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := hbox(6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(role_icon(role, size))
	if show_name:
		row.add_child(label(str(ROLE_NAMES.get(role, role.capitalize())), int(size * 0.62), INK, "extrabold"))
	p.add_child(row)
	return p


## Pill with the rarity name on a rarity-colored gradient ("LEGENDARY").
static func rarity_badge(rarity: String, size: int = 20) -> PanelContainer:
	var c := rarity_color(rarity)
	return tag(str(RARITY_NAMES.get(rarity, rarity.capitalize())).to_upper(), c, Color.WHITE if rarity != "legendary" else Color("3d2306"), size)


## Small pill tag, e.g. tag("NEW"), tag("BOSS", Kit.EMBER, Color.WHITE).
static func tag(text: String, color: Color = GOLD, text_color: Color = Color("3d2306"), size: int = 20) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var b := KitBox.new()
	b.radius = 999
	b.top_color = color.lightened(0.3)
	b.bottom_color = color.darkened(0.12)
	b.border_width = 2
	b.border_color = color.darkened(0.6)
	b.gloss = 0.25
	b.content_margin_left = size * 0.6
	b.content_margin_right = size * 0.6
	b.content_margin_top = 1
	b.content_margin_bottom = 2
	p.add_theme_stylebox_override("panel", b.commit())
	var l := label(text, size, text_color, "black")
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p


# ------------------------------------------------------------------ hero card

## Square hero card: portrait (HeroArt.make_portrait), rarity frame, faction emblem, level,
## stars. Returns a Button (tap with opts.on_pressed).
## opts (all optional):
##   size: float = 152        level: int, stars: int (default: owned values or rarity base)
##   owned: bool (default Game.owns)  unowned cards are greyed out
##   locked: bool             dark overlay with a lock
##   selected: bool           gold glow ring + check
##   show_name: bool = false  name caption under the card
##   show_level / show_stars / show_faction: bool = true
##   dot: bool                red notification dot
##   tag: String              small pill top-right ("NEW", "x2", "BOSS")
##   shard: bool              shard overlay (for shard rewards)
##   on_pressed: Callable
static func hero_card(hero_id: String, opts: Dictionary = {}) -> Button:
	var c := HeroCard.new()
	c.setup(hero_id, opts)
	return c


# ------------------------------------------------------------------ notification dot

## Red notification dot (with white rim).
static func dot(size: float = 22.0) -> Control:
	var d := Dot.new()
	d.custom_minimum_size = Vector2(size, size)
	d.size = Vector2(size, size)
	return d


## Shows/hides a red dot at the top-right corner of `target` (must not be a Container;
## Buttons and plain Controls are fine).
static func set_dot(target: Control, show: bool, size: float = 22.0, inset: Vector2 = Vector2(6, 6)) -> void:
	var d := target.get_node_or_null("KitDot") as Control
	if d == null:
		if not show:
			return
		d = dot(size)
		d.name = "KitDot"
		_corner(target, d, Vector2(1, 0), Vector2(-inset.x, inset.y))
		d.offset_left = -inset.x - size
		d.offset_right = -inset.x
		d.offset_top = inset.y
		d.offset_bottom = inset.y + size
	d.visible = show


# ------------------------------------------------------------------ headers & rows

## Centered section title between two gold filigree lines:  ——◆  Title  ◆——
static func section_header(text: String, size: int = 30, color: Color = GOLD_LIGHT) -> HBoxContainer:
	var row := hbox(14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.custom_minimum_size.y = size + 16
	var l := Filigree.new()
	l.direction = -1
	var r := Filigree.new()
	r.direction = 1
	var t := header(text, size, color)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add(row, [l, t, r])
	return row


## Stat line for hero details: icon, name, value (right aligned). stat: hp/atk/def/spd/crit.
## delta (optional) shows a green "+N" after the value (level-up previews).
static func stat_row(stat: String, value: Variant, delta: Variant = null, label_text: String = "") -> HBoxContainer:
	var row := hbox(12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.custom_minimum_size.y = 44
	row.add_child(icon("stat_" + stat, 36))
	var n := label(label_text if label_text != "" else str(STAT_NAMES.get(stat, stat.to_upper())), SIZE_BODY, INK_DIM, "bold")
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(n)
	var vt := str(value)
	if value is int:
		vt = format_full(value)
	row.add_child(label(vt, SIZE_BODY, INK, "black"))
	if delta != null:
		var dt := str(delta)
		if delta is int:
			dt = format_full(delta)
		row.add_child(label("+" + dt, SIZE_BODY - 2, GOOD, "black"))
	return row


## Friendly empty-list message with an optional icon.
static func empty_state(text: String, icon_name: String = "") -> VBoxContainer:
	var v := vbox(12)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if icon_name != "":
		var ic := icon(icon_name, 96, Color(1, 1, 1, 0.5))
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(ic)
	var l := body(text, SIZE_BODY, INK_DIM)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	return v


# ------------------------------------------------------------------ light effects

## Soft radial glow sprite (for behind portraits, chests, summons).
static func glow(color: Color = GOLD, size: float = 240.0) -> TextureRect:
	var key := color.to_html()
	if not _glow_textures.has(key):
		var g := Gradient.new()
		g.set_color(0, Color(color, 0.85))
		g.set_color(1, Color(color, 0.0))
		g.add_point(0.35, Color(color, 0.38))
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5)
		gt.fill_to = Vector2(0.5, 0.0)
		gt.width = 128
		gt.height = 128
		_glow_textures[key] = gt
	var t := TextureRect.new()
	t.texture = _glow_textures[key]
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.custom_minimum_size = Vector2(size, size)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


## Slowly rotating light rays (reward popups, summon reveals). Place centered behind art.
static func rays(color: Color = GOLD, size: float = 520.0, count: int = 14) -> Control:
	var r := Rays.new()
	r.color = color
	r.ray_count = count
	r.custom_minimum_size = Vector2(size, size)
	r.size = Vector2(size, size)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## Material that greys out a CanvasItem (unowned heroes). amount 0..1.
static func grayscale_material() -> ShaderMaterial:
	if _gray_material == null:
		var sh := Shader.new()
		sh.code = "shader_type canvas_item;\nuniform float amount : hint_range(0.0, 1.0) = 1.0;\nuniform float dim = 0.62;\nvoid fragment() {\n\tvec4 c = texture(TEXTURE, UV) * COLOR;\n\tfloat g = dot(c.rgb, vec3(0.299, 0.587, 0.114));\n\tCOLOR = vec4(mix(c.rgb, vec3(g) * vec3(0.92, 0.9, 1.0), amount) * dim, c.a);\n}\n"
		_gray_material = ShaderMaterial.new()
		_gray_material.shader = sh
	return _gray_material


# ------------------------------------------------------------------ motion

## Pops a control in (scale 0.6 -> 1 with overshoot, fade in). Call after it is in the tree.
static func pop_in(c: Control, delay: float = 0.0, dur: float = 0.32) -> void:
	if not c.is_inside_tree():
		return
	c.pivot_offset = c.size * 0.5
	c.scale = Vector2(0.6, 0.6)
	c.modulate.a = 0.0
	var tw := c.create_tween().set_parallel(true)
	tw.tween_property(c, "scale", Vector2.ONE, dur).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "modulate:a", 1.0, dur * 0.6).set_delay(delay)


## Quick scale bump (feedback on value changes).
static func pulse(c: Control, amount: float = 1.12) -> void:
	if not c.is_inside_tree():
		return
	c.pivot_offset = c.size * 0.5
	var tw := c.create_tween()
	tw.tween_property(c, "scale", Vector2(amount, amount), 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Horizontal shake (errors, can't afford).
static func shake(c: Control, strength: float = 10.0) -> void:
	if not c.is_inside_tree():
		return
	var x := c.position.x
	var tw := c.create_tween()
	for i in 4:
		tw.tween_property(c, "position:x", x + (strength if i % 2 == 0 else -strength) * (1.0 - i * 0.2), 0.04)
	tw.tween_property(c, "position:x", x, 0.04)


## Animates a Label's number from `from` to `to` (compact formatted).
static func count_to(l: Label, from: int, to: int, dur: float = 0.5, full: bool = false) -> void:
	if not l.is_inside_tree():
		l.text = format_full(to) if full else format_num(to)
		return
	var tw := l.create_tween()
	tw.tween_method(func(v: float) -> void:
		l.text = format_full(int(v)) if full else format_num(int(v)), float(from), float(to), dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


# ------------------------------------------------------------------ number formatting

## Compact number: 950, 1,800, 12.5K, 125K, 3.4M, 1.2B.
static func format_num(n: int) -> String:
	var a := absi(n)
	var sign_s := "-" if n < 0 else ""
	if a < 10000:
		return sign_s + format_full(a)
	var units := [[1000000000000.0, "T"], [1000000000.0, "B"], [1000000.0, "M"], [1000.0, "K"]]
	for u: Array in units:
		var div: float = u[0]
		if float(a) >= div:
			var v := float(a) / div
			var s: String
			if v < 100.0:
				s = str(floorf(v * 10.0) / 10.0)
				if s.ends_with(".0"):
					s = s.substr(0, s.length() - 2)
			else:
				s = str(int(floorf(v)))
			return sign_s + s + str(u[1])
	return sign_s + str(a)


## Full number with thousands separators: 1,234,567.
static func format_full(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if n < 0 else "") + out


## Duration: "45s", "12m 05s", "2h 05m", "3d 4h".
static func format_time(ms: int) -> String:
	var s := maxi(ms, 0) / 1000
	if s < 60:
		return "%ds" % s
	var m := s / 60
	if m < 60:
		return "%dm %02ds" % [m, s % 60]
	var h := m / 60
	if h < 48:
		return "%dh %02dm" % [h, m % 60]
	return "%dd %dh" % [h / 24, h % 24]
