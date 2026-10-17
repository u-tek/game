class_name Kit
extends RefCounted
## Kit: static UI builders for Halo & Horn, style v3 "Aero Y2K" (2026-10-17: v2's layout with rounded glass
## plates, bubble badges, gloss and an ocean-and-aqua palette; KitBox.aero). Was style v2 ("tactical gacha": dark translucent
## chrome over full-screen art, light paper pages with near-black text, one bright cyan-blue
## accent, orange highlights, condensed bold type, skewed plates, hex badges, hatching and
## thin technical lines). Spec: docs/dev/ui-style-v2.md. Every screen builds its UI with
## these so the whole game shares one look.
##
## Quick reference (all static, all return ready-to-add Controls):
##   Tokens     dark chrome: BG, CHROME, PANEL, PANEL_HI, LINE, INK, INK_DIM, OUTLINE
##              light pages: PAPER, WHITE, TEXT, TEXT_DIM, LINE_LIGHT
##              accents: ACCENT, ACCENT_HI, ACCENT_DEEP, ORANGE, ORANGE_HI, NEW_RED, RED_DOT
##              semantic: GOLD, GOLD_LIGHT, GOLD_DEEP, EMBER, VIOLET, SKY, GOOD, RARE, EPIC,
##              LEGENDARY; SIZE_SMALL/BODY/BUTTON/HEADER/HERO; BUTTON_H (88), GAP, PAD, SKEW
##   Text       label, title, header, body, number, caption, font, fit_label
##   Buttons    primary_button (cyan), secondary_button (graphite), danger_button, light_button
##              (white, for light pages), orange_button, icon_button, cost_button,
##              costs_button, segmented, filter_chips, tab_strip, toggle, make_tappable,
##              add_press_fx, empty_slot, back_bar
##   Lobby      shortcut (big tapered plate), side_button, speech_bubble, banner_card,
##              notice_bar, percent_meter, resource_pill, avatar
##   Layout     vbox, hbox, grid, flow, scroll, margin, center, spacer, expand, add, divider
##   Panels     panel ("glass" | "card" | "inset" | "plain" dark; "white" | "paper" |
##              "light_inset" | "row" light), card, info_panel, header_bar, dialog, style, box,
##              page_bg
##   Widgets    progress_bar/set_progress, star_row, currency_icon, currency_chip/
##              set_chip_amount, cost_row, reward_list, reward_tile, faction_badge, role_badge,
##              rarity_badge, rarity_mark, tag, hero_card, portrait_card, name_plate,
##              equip_slot, hex_badge, new_badge/set_new, dot/set_dot, section_header,
##              screen_header, stat_row, empty_state, icon, deco, glow, rays, ribbon,
##              art_background, art_crop, vgradient
##   Economy    have(currency_id), can_afford(costs)
##   Colors     faction_color, rarity_color, rarity_frame, tier_color
##   Numbers    format_num (12.5K / 3.4M), format_full (1,234,567), format_time (2h 05m)
##   Motion     pop_in, pulse, shake, count_to
##
## Conventions: sizes are viewport px on the 720 px wide canvas. Light-on-dark is the
## default (INK text on dark chrome); builders that also live on light pages take a
## `light` flag (TEXT colors). Builders only read Game (never write): hero cards (owned
## level/stars when not given), reward tiles (gear names), cost rows / costs buttons /
## have / can_afford (currency amounts). Buttons play UI.sfx("tap"). Every clickable Kit
## widget uses MOUSE_FILTER_PASS so it works inside Kit.scroll lists (a drag scrolls
## instead of pressing). Touch targets are at least BUTTON_H (88 px) tall.

const KitBox := preload("res://src/ui/components/kit_box.gd")
const HeroCard := preload("res://src/ui/components/hero_card.gd")
const PortraitCard := preload("res://src/ui/components/portrait_card.gd")
const Filigree := preload("res://src/ui/components/filigree.gd")
const Dot := preload("res://src/ui/components/dot.gd")
const Badge := preload("res://src/ui/components/badge.gd")
const HexBadge := preload("res://src/ui/components/hex_badge.gd")
const Deco := preload("res://src/ui/components/deco.gd")
const Rays := preload("res://src/ui/components/rays.gd")
const Ribbon := preload("res://src/ui/components/ribbon.gd")
const ShortcutButton := preload("res://src/ui/components/shortcut_button.gd")
const Backdrop := preload("res://src/ui/components/backdrop.gd")

# ------------------------------------------------------------------ design tokens

# Dark chrome (bars, glass panels over art). Text on it: INK / INK_DIM.
const BG := Color("0d1824")
const CHROME := Color("08111b")
const PANEL := Color("12233aeb")
const PANEL_HI := Color("1e3a56")
const LINE := Color(1, 1, 1, 0.14)
const INK := Color("f4f6f8")
const INK_DIM := Color("9ba2ac")
## Text outlines and icon outlines (near-black).
const OUTLINE := Color("080c19")

# Light pages (roster, hero info column, dialogs). Text on it: TEXT / TEXT_DIM.
const PAPER := Color("e8f3f8")
const WHITE := Color("ffffff")
const TEXT := Color("0e1729")
const TEXT_DIM := Color("6c737d")
const LINE_LIGHT := Color("cde1ea")

# Accents.
## The one bright cyan-blue: primary buttons, selected chips, active tabs, links, focus.
const ACCENT := Color("18c3e8")
const ACCENT_HI := Color("8cf2ff")
## Deep blue: dialog headers, pressed primary.
const ACCENT_DEEP := Color("0a8cc2")
## Orange highlight: the battle call to action, legendary footers, guide marks.
const ORANGE := Color("ff8a1e")
const ORANGE_HI := Color("ffc23a")
## "N" new badges.
const NEW_RED := Color("f2481f")
const RED_DOT := Color("ff4536")

# Semantic colors (kept from v1 so older screens still compile and read well).
const GOLD := Color("ffb627")
const GOLD_LIGHT := Color("ffd98a")
const GOLD_DEEP := Color("b86e0a")
const EMBER := Color("e8432a")
const VIOLET := Color("8f6cf0")
const SKY := Color("4fc3f7")
const GOOD := Color("37cf8a")
const RARE := Color("3b9cf2")
const EPIC := Color("a95cf2")
const LEGENDARY := Color("ff9b1e")

const SIZE_SMALL := 22
const SIZE_BODY := 26
const SIZE_BUTTON := 30
const SIZE_HEADER := 40
const SIZE_HERO := 56

## Minimum touch target height.
const BUTTON_H := 88
const GAP := 16
const PAD := 24
## The house slant: tan(10 degrees). Plates skew by this fraction of their height.
const SKEW := 0.176

const CURRENCIES: Array[String] = ["gold", "gems", "scrolls", "hero_exp", "dust"]
const CURRENCY_NAMES := {
	"gold": "Gold", "gems": "Gems", "scrolls": "Summon Scrolls", "hero_exp": "Hero EXP", "dust": "Dust",
}
## Short names for tight spots (reward tile captions).
const CURRENCY_SHORT := {"gold": "Gold", "gems": "Gems", "scrolls": "Scrolls", "hero_exp": "Hero EXP", "dust": "Dust"}
const FACTIONS: Array[String] = ["celestial", "infernal", "fallen"]
const FACTION_NAMES := {"celestial": "Celestial", "infernal": "Infernal", "fallen": "Fallen"}
const ROLES: Array[String] = ["guardian", "striker", "caster", "support", "assassin"]
const ROLE_NAMES := {
	"guardian": "Guardian", "striker": "Striker", "caster": "Caster", "support": "Support", "assassin": "Assassin",
}
const RARITY_NAMES := {"rare": "Rare", "epic": "Epic", "legendary": "Legendary"}
const RARITY_STARS := {"rare": 1, "epic": 2, "legendary": 3}
## Roman tier numeral shown in the card's second hex (rarity tier).
const RARITY_TIER := {"rare": "I", "epic": "II", "legendary": "III"}
const STAT_NAMES := {"hp": "HP", "atk": "Attack", "def": "Defense", "spd": "Speed", "crit": "Crit"}
const STAT_SHORT := {"hp": "HP", "atk": "ATK", "def": "DEF", "spd": "SPD", "crit": "CRIT"}
const GEAR_SLOT_NAMES := {"weapon": "Weapon", "armor": "Armor", "helm": "Helm", "charm": "Charm"}
const MAX_STARS := 6

## Font weights. Barlow (wide) for body and buttons, Barlow Condensed for titles, numbers
## and uppercase labels. Old weight names map onto the new faces.
const _FONT_FILES := {
	"regular": "res://assets/fonts/Barlow-Medium.ttf",
	"medium": "res://assets/fonts/Barlow-Medium.ttf",
	"bold": "res://assets/fonts/Barlow-SemiBold.ttf",
	"semibold": "res://assets/fonts/Barlow-SemiBold.ttf",
	"extrabold": "res://assets/fonts/Barlow-Bold.ttf",
	"black": "res://assets/fonts/BarlowCondensed-Bold.ttf",
	"title": "res://assets/fonts/BarlowCondensed-ExtraBold.ttf",
	"cond_light": "res://assets/fonts/BarlowCondensed-Medium.ttf",
	"cond": "res://assets/fonts/BarlowCondensed-SemiBold.ttf",
	"cond_bold": "res://assets/fonts/BarlowCondensed-Bold.ttf",
	"cond_black": "res://assets/fonts/BarlowCondensed-ExtraBold.ttf",
}

static var _fonts: Dictionary = {}
static var _icons: Dictionary = {}
static var _glow_textures: Dictionary = {}
static var _grad_textures: Dictionary = {}
static var _crops: Dictionary = {}
static var _gray_material: ShaderMaterial


# ------------------------------------------------------------------ fonts & icons

## Font by weight: "regular"/"medium", "bold"/"semibold", "extrabold" (Barlow) or "black",
## "title", "cond_light", "cond", "cond_bold", "cond_black" (Barlow Condensed).
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


## Square icon TextureRect. `color` tints (white = original colors). The UI glyphs are white
## so they take any tint: INK on dark chrome, TEXT on light pages, INK_DIM when inactive.
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


## An autoload node by name ("UI", "Game") or null. Kit looks autoloads up at runtime so
## it also compiles in -s scripts and unit tests where autoload names aren't registered.
static func autoload(node_name: String) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(node_name)


## Plays a UI sound through the UI autoload (no-op without it).
static func sfx(sound_name: String) -> void:
	var ui := autoload("UI")
	if ui:
		ui.call("sfx", sound_name)


# ------------------------------------------------------------------ text

## Generic label. weight: see font(). outline > 0 adds a near-black outline (use on art).
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


## Big display title (hero names, result banners): Barlow Condensed ExtraBold, white, soft
## drop shadow. Centered.
static func title(text: String, size: int = SIZE_HERO, color: Color = INK) -> Label:
	var l := label(text, size, color, "title", 0)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", maxi(2, size / 16))
	l.add_theme_constant_override("shadow_outline_size", maxi(2, size / 10))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


## Screen / panel header: Barlow Condensed ExtraBold 40 (text case kept as given).
static func header(text: String, size: int = SIZE_HEADER, color: Color = INK) -> Label:
	var l := label(text, size, color, "title", 0)
	if color.get_luminance() > 0.5:
		l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.4))
		l.add_theme_constant_override("shadow_offset_y", 2)
		l.add_theme_constant_override("shadow_outline_size", 3)
	return l


## Body text: Barlow SemiBold, word-wrapped by default (expands horizontally for a width).
static func body(text: String, size: int = SIZE_BODY, color: Color = INK, wrap: bool = true) -> Label:
	var l := label(text, size, color, "bold")
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.custom_minimum_size.x = 40
	return l


## Number display: Barlow Condensed Bold with a thin dark outline. ints are compact (12.5K).
static func number(value: Variant, size: int = SIZE_BUTTON, color: Color = INK) -> Label:
	var text := format_num(int(value)) if (value is int or value is float) else str(value)
	var dark := color.get_luminance() < 0.4
	return label(text, size, color, "black", 0 if dark else maxi(3, size / 9))


## Small secondary text (22 px, dim).
static func caption(text: String, size: int = SIZE_SMALL, color: Color = INK_DIM) -> Label:
	return label(text, size, color, "bold")


## Shrinks a label's font size (down to min_size) until its text fits `width` px.
static func fit_label(l: Label, width: float, max_size: int, min_size: int = 14) -> void:
	var f: Font = l.get_theme_font("font")
	var fs := max_size
	while fs > min_size and f.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > width:
		fs -= 1
	l.add_theme_font_size_override("font_size", fs)


# ------------------------------------------------------------------ buttons

## Cyan-blue call-to-action button (88 px tall). icon = optional assets/art/ui icon name.
static func primary_button(text: String, on_pressed: Callable = Callable(), icon_name: String = "") -> Button:
	return _button(text, &"PrimaryButton", on_pressed, icon_name)


## Dark graphite button with a light hairline, for secondary actions on dark chrome.
static func secondary_button(text: String, on_pressed: Callable = Callable(), icon_name: String = "") -> Button:
	return _button(text, &"SecondaryButton", on_pressed, icon_name)


## Red button for destructive actions (reset save, salvage).
static func danger_button(text: String, on_pressed: Callable = Callable(), icon_name: String = "") -> Button:
	return _button(text, &"DangerButton", on_pressed, icon_name)


## White button with dark text, for secondary actions on light pages and dialogs.
static func light_button(text: String, on_pressed: Callable = Callable(), icon_name: String = "") -> Button:
	return _button(text, &"LightButton", on_pressed, icon_name)


## Orange glowing button: the one "go fight / go now" action on a screen.
static func orange_button(text: String, on_pressed: Callable = Callable(), icon_name: String = "") -> Button:
	return _button(text, &"OrangeButton", on_pressed, icon_name)


## Square icon button with an 88 px touch target.
## look: "round" (dark glass tile, default), "gold" / "accent" (cyan tile), "light" (white
## tile, dark glyph), "bare" (glyph only).
static func icon_button(icon_name: String, on_pressed: Callable = Callable(), size: float = 88.0, look: String = "round") -> Button:
	var b := Button.new()
	b.theme_type_variation = &"BareButton"
	b.custom_minimum_size = Vector2(maxf(size, 64.0), maxf(size, 64.0))
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	b.tooltip_text = ""
	var disc_size := size * 0.76
	var tint := Color.WHITE
	if look != "bare":
		var disc := Panel.new()
		disc.name = "Disc"
		disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var kind := {"gold": "disc_gold", "accent": "disc_gold", "light": "disc_light"}.get(look, "disc") as String
		disc.add_theme_stylebox_override("panel", UITheme.style(kind))
		_center_child(b, disc, Vector2(disc_size, disc_size))
		if look == "light":
			tint = Color("1b2b48")
	var ic := icon(icon_name, disc_size * (0.6 if look != "bare" else 0.82), tint)
	ic.name = "Glyph"
	_center_child(b, ic, ic.custom_minimum_size)
	add_press_fx(b)
	if on_pressed.is_valid():
		_connect_pressed(b, on_pressed)
	return b


## Button with a label and a price line, e.g. ("Summon x10", "gems", 2700).
## look: "primary" | "secondary" | "light" | "orange". The price sits in a small pill under
## the label and turns red when the player has less than `amount` (or when affordable =
## false); the button stays pressable so the screen can explain why. amount <= 0 shows a
## green "FREE" in the pill instead (free daily summon).
static func cost_button(text: String, currency_id: String, amount: int, on_pressed: Callable = Callable(), look: String = "primary", affordable: bool = true) -> Button:
	var b := _button("", _variation(look), on_pressed, "")
	b.custom_minimum_size = Vector2(240, 108)
	var col := vbox(4)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := label(text, 30, _button_ink(look), "extrabold")
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(t)
	var short := not affordable or have(currency_id) < amount
	var pill := _price_pill(look)
	var price := hbox(6)
	price.alignment = BoxContainer.ALIGNMENT_CENTER
	price.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if amount <= 0:
		var free_ink := Color("12965c") if look in ["primary", "orange", "light"] else GOOD
		price.add_child(label("FREE", 24, free_ink, "black"))
	else:
		price.add_child(currency_icon(currency_id, 30))
		price.add_child(label(format_full(amount), 24, _price_ink(look, short), "black"))
	pill.add_child(price)
	col.add_child(center(pill))
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_bottom = -4
	b.add_child(col)
	b.set_meta("price_box", price)
	return b


## Icons + amounts for a cost dict, e.g. {"gold": 1200, "hero_exp": 300}. When
## check_afford is on, amounts the player can't pay are drawn in `short_color`.
static func cost_row(costs: Dictionary, size: int = 24, color: Color = INK, check_afford: bool = true, short_color: Color = Color("ff6a50")) -> HBoxContainer:
	var row := hbox(16)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for id: Variant in costs:
		var amt := int(costs[id])
		var pair := hbox(4)
		pair.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pair.add_child(currency_icon(str(id), size + 8))
		var ok := (not check_afford) or have(str(id)) >= amt
		pair.add_child(label(format_full(amt) if amt < 100000 else format_num(amt), size, color if ok else short_color, "black"))
		row.add_child(pair)
	return row


## Amount of a currency the player has (0 when Game isn't available).
static func have(currency_id: String) -> int:
	var g := autoload("Game")
	return int(g.call("currency", currency_id)) if g else 0


## True when the player can pay every amount in `costs` ({currency_id: amount}).
static func can_afford(costs: Dictionary) -> bool:
	for id: Variant in costs:
		if have(str(id)) < int(costs[id]):
			return false
	return true


## Like cost_button but for several currencies, e.g. ("Level Up", {"gold": 1200, "hero_exp": 300}).
## Amounts the player can't pay show in red automatically. look: as cost_button.
static func costs_button(text: String, costs: Dictionary, on_pressed: Callable = Callable(), look: String = "primary") -> Button:
	var b := _button("", _variation(look), on_pressed, "")
	b.custom_minimum_size = Vector2(240, 108)
	var col := vbox(4)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := label(text, 30, _button_ink(look), "extrabold")
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(t)
	var pill := _price_pill(look)
	pill.add_child(cost_row(costs, 22, _price_ink(look, false), true, _price_ink(look, true)))
	col.add_child(center(pill))
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_bottom = -4
	b.add_child(col)
	return b


## Fits a Kit text button into `width` px (tight rows): narrows its side padding to `pad`
## and shrinks the font (max_size down to min_size) until the text fits, so the button's
## minimum width never pushes its row wider than planned.
static func fit_button(b: Button, width: float, max_size: int = SIZE_BUTTON, min_size: int = 16, pad: float = 10.0) -> void:
	var bases := {&"PrimaryButton": "btn_primary", &"SecondaryButton": "btn_secondary", &"DangerButton": "btn_danger",
		&"LightButton": "btn_light", &"OrangeButton": "btn_orange"}
	var base := str(bases.get(b.theme_type_variation, "btn_secondary"))
	var suffix := {"normal": "", "hover": "_hover", "pressed": "_pressed", "hover_pressed": "_pressed", "disabled": "_disabled"}
	for st: String in suffix:
		var sb := UITheme.style(base + str(suffix[st]))
		sb.content_margin_left = pad
		sb.content_margin_right = pad
		b.add_theme_stylebox_override(st, sb)
	var f := b.get_theme_font("font")
	var fs := max_size
	while fs > min_size and f.get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > width - pad * 2.0 - 2.0:
		fs -= 1
	b.add_theme_font_size_override("font_size", fs)
	b.custom_minimum_size.x = minf(b.custom_minimum_size.x, width)


static func _variation(look: String) -> StringName:
	match look:
		"secondary":
			return &"SecondaryButton"
		"light":
			return &"LightButton"
		"orange":
			return &"OrangeButton"
		"danger":
			return &"DangerButton"
	return &"PrimaryButton"


static func _button_ink(look: String) -> Color:
	return TEXT if look == "light" else Color.WHITE


static func _price_pill(look: String) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bx := KitBox.new()
	bx.radius = 999
	if look == "primary" or look == "orange":
		bx.top_color = Color(1, 1, 1, 0.94)
		bx.bottom_color = Color(0.94, 0.95, 0.97, 0.94)
	elif look == "light":
		bx.top_color = Color("e4e8ec")
		bx.bottom_color = Color("e4e8ec")
	else:
		bx.top_color = Color(0, 0, 0, 0.4)
		bx.bottom_color = Color(0, 0, 0, 0.4)
	bx.content_margin_left = 14
	bx.content_margin_right = 16
	bx.content_margin_top = 0
	bx.content_margin_bottom = 0
	p.add_theme_stylebox_override("panel", bx.commit())
	return p


static func _price_ink(look: String, short: bool) -> Color:
	if look == "primary" or look == "orange" or look == "light":
		return Color("d42a12") if short else TEXT
	return Color("ff6a50") if short else INK


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
				b.add_theme_constant_override("icon_max_width", int(height * 0.56))
				b.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
				if b.text == "":
					b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		else:
			b.text = str(opt)
		b.button_pressed = i == selected
		var idx := i
		b.toggled.connect(func(on: bool) -> void:
			if on:
				sfx("tap")
				if on_select.is_valid():
					on_select.call(idx))
		row.add_child(b)
	return row


## Square filter chips (roster filters): dark graphite squares, the selected one cyan.
## options: Array of String ("ALL", "I") or {icon} / {text, icon}. Each chip is `size` px
## visually inside an 88 px touch square. on_select(index).
static func filter_chips(options: Array, selected: int, on_select: Callable = Callable(), size: float = 76.0) -> HBoxContainer:
	var row := hbox(4)
	row.name = "FilterChips"
	var group := ButtonGroup.new()
	var inset := maxf((BUTTON_H - size) * 0.5, 0.0)
	for i in options.size():
		var opt: Variant = options[i]
		var b := Button.new()
		b.theme_type_variation = &"SegmentButton"
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_filter = Control.MOUSE_FILTER_PASS
		b.custom_minimum_size = Vector2(maxf(size, BUTTON_H), BUTTON_H)
		for st: Array in [["normal", "chip_off"], ["hover", "chip_off"], ["disabled", "chip_off"], ["pressed", "chip_on"], ["hover_pressed", "chip_on"]]:
			var sb := UITheme.style(st[1])
			sb.set("draw_inset", Vector2(inset, inset))
			sb.content_margin_left += inset
			sb.content_margin_right += inset
			b.add_theme_stylebox_override(st[0], sb)
		var text := ""
		var icon_name := ""
		if opt is Dictionary:
			text = str(opt.get("text", ""))
			icon_name = str(opt.get("icon", ""))
		else:
			text = str(opt)
		b.text = text
		b.add_theme_font_override("font", font("cond_bold"))
		b.add_theme_font_size_override("font_size", 26 if text.length() <= 3 else 22)
		if icon_name != "":
			b.icon = icon_texture(icon_name)
			b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			b.add_theme_constant_override("icon_max_width", int(size * 0.5))
			b.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		b.button_pressed = i == selected
		var idx := i
		b.toggled.connect(func(on: bool) -> void:
			if on:
				sfx("tap")
				if on_select.is_valid():
					on_select.call(idx))
		row.add_child(b)
	return row


## Tab strip (page tabs, dialog tabs): the active tab is a white plate with a cyan top bar
## and near-black text, the others are dark glass with light text. options: String or
## {text, icon}. on_select(index). Each tab is 88 px tall.
static func tab_strip(options: Array, selected: int, on_select: Callable = Callable(), min_width: float = 200.0) -> HBoxContainer:
	var row := hbox(2)
	row.name = "TabStrip"
	var group := ButtonGroup.new()
	for i in options.size():
		var opt: Variant = options[i]
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_filter = Control.MOUSE_FILTER_PASS
		b.custom_minimum_size = Vector2(min_width, BUTTON_H)
		b.theme_type_variation = &"TabButton"
		var text := str(opt.get("text", "")) if opt is Dictionary else str(opt)
		b.text = text.to_upper()
		if opt is Dictionary and opt.has("icon"):
			b.icon = icon_texture(str(opt.icon))
			b.add_theme_constant_override("icon_max_width", 34)
			b.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		b.button_pressed = i == selected
		var idx := i
		b.toggled.connect(func(on: bool) -> void:
			if on:
				sfx("tap")
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
		sfx("tap")
		if on_toggled.is_valid():
			on_toggled.call(v))
	return c


## Makes any Control tappable: adds an invisible full-size Button on top, a press
## animation on `target` and the tap sound. Returns the overlay Button.
## `target` must be a PanelContainer, Panel or plain Control (in a Box/Grid container the
## overlay would become a layout item); wrap such content in Kit.panel(...) first.
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


## Press animation (squash to 95% and spring back) on `button`, scaling `target`
## (defaults to the button). Safe inside ScrollContainers (cancelled presses restore).
static func add_press_fx(button: BaseButton, target: Control = null) -> void:
	var t: Control = target if target else button
	t.pivot_offset = t.size * 0.5
	t.resized.connect(func() -> void: t.pivot_offset = t.size * 0.5)
	button.button_down.connect(func() -> void:
		button.set_meta("_down_at", button.get_global_mouse_position())
		_scale_to(t, 0.95, 0.06))
	button.button_up.connect(func() -> void: _scale_to(t, 1.0, 0.18))
	button.draw.connect(func() -> void:
		var mode := button.get_draw_mode()
		if mode != BaseButton.DRAW_PRESSED and mode != BaseButton.DRAW_HOVER_PRESSED and t.scale.x < 0.999:
			_scale_to(t, 1.0, 0.18))


static func _scale_to(c: Control, s: float, dur: float) -> void:
	if not c.is_inside_tree():
		return
	var prev: Variant = c.get_meta("_press_tween") if c.has_meta("_press_tween") else null
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
		var down: Variant = b.get_meta("_down_at") if b.has_meta("_down_at") else null
		if down is Vector2 and (down as Vector2).distance_to(b.get_global_mouse_position()) > 36.0:
			return
		if sound != "":
			sfx(sound)
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
		var bases := {&"PrimaryButton": "btn_primary", &"SecondaryButton": "btn_secondary", &"DangerButton": "btn_danger",
			&"LightButton": "btn_light", &"OrangeButton": "btn_orange"}
		_add_button_icon(b, str(bases.get(variation, "btn_secondary")), icon_name, 40.0, TEXT if variation == &"LightButton" else Color.WHITE)
	add_press_fx(b)
	if on_pressed.is_valid():
		_connect_pressed(b, on_pressed)
	return b


## Icon drawn just left of the (centered) button text; the pair stays centered and
## follows text changes. Uses per-button styleboxes with extra left padding.
static func _add_button_icon(b: Button, base: String, icon_name: String, isz: float = 40.0, tint: Color = Color.WHITE) -> void:
	var gap := 10.0
	var suffix := {"normal": "", "hover": "_hover", "pressed": "_pressed", "hover_pressed": "_pressed", "disabled": "_disabled"}
	for st: String in suffix:
		var sb := UITheme.style(base + str(suffix[st]))
		sb.content_margin_left += isz + gap
		b.add_theme_stylebox_override(st, sb)
	var ic := icon(icon_name, isz, tint)
	ic.name = "KitIcon"
	ic.size = Vector2(isz, isz)
	b.add_child(ic)
	var place := func() -> void:
		var f := b.get_theme_font("font")
		var fs := b.get_theme_font_size("font_size")
		var tw := f.get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x if b.text != "" else -gap
		var mode := b.get_draw_mode()
		var sb := b.get_theme_stylebox("pressed" if mode == BaseButton.DRAW_PRESSED or mode == BaseButton.DRAW_HOVER_PRESSED else "normal")
		var ml := sb.content_margin_left
		var mr := sb.content_margin_right
		var cx := ml + (b.size.x - ml - mr) * 0.5
		var top := sb.content_margin_top
		var bot := sb.content_margin_bottom
		ic.position = Vector2(roundf(cx - tw * 0.5 - gap - isz), roundf(top + (b.size.y - top - bot - isz) * 0.5))
		ic.modulate = Color(tint, 0.45) if b.disabled else tint
	b.draw.connect(place)
	b.resized.connect(place)


static func _center_child(parent: Control, child: Control, sz: Vector2) -> void:
	child.set_anchors_preset(Control.PRESET_CENTER)
	child.offset_left = -sz.x * 0.5
	child.offset_right = sz.x * 0.5
	child.offset_top = -sz.y * 0.5
	child.offset_bottom = sz.y * 0.5
	parent.add_child(child)


## Bottom-left "Back" + home pair (sub-screens without the nav, like hero detail): a cyan
## Back button with the exit glyph and a cyan square home button. on_back defaults to
## UI.back(), on_home to UI.go("home").
static func back_bar(on_back: Callable = Callable(), on_home: Callable = Callable()) -> HBoxContainer:
	var row := hbox(8)
	row.name = "BackBar"
	var cb := on_back
	if not cb.is_valid():
		cb = func() -> void:
			var u := autoload("UI")
			if u:
				u.call("back")
	var hb := on_home
	if not hb.is_valid():
		hb = func() -> void:
			var u := autoload("UI")
			if u:
				u.call("go", "home")
	var back := primary_button("Back", cb, "exit")
	back.name = "Back"
	back.custom_minimum_size = Vector2(200, BUTTON_H)
	row.add_child(back)
	var home := icon_button("home", hb, BUTTON_H, "accent")
	home.name = "Home"
	row.add_child(home)
	return row


# ------------------------------------------------------------------ lobby widgets

## Big lobby shortcut plate (tapered translucent quad with a glyph and a title).
## look: "blue" | "white" | "orange" | "dark" (see shortcut_button.gd). opts:
##   size: Vector2 = (330, 150)   side: "left" | "right" (which screen edge it hugs)
##   badge: "N" | "!" | "dot" | ""  sub: Control (a meter or art strip under the title)
##   title_size: int              icon_k: float (glyph size / plate height)
##   art: Texture2D               framed art strip in the lower right (art_caption: tag text)
static func shortcut(text: String, icon_name: String, look: String = "blue", on_pressed: Callable = Callable(), opts: Dictionary = {}) -> Button:
	var b := ShortcutButton.new()
	var sz: Vector2 = opts.get("size", Vector2(330, 150))
	b.taper = float(opts.get("taper", 0.12))
	b.icon_k = float(opts.get("icon_k", 0.56))
	b.title_size = int(opts.get("title_size", 0))
	b.setup(text, icon_name, look, 1 if str(opts.get("side", "left")) == "right" else -1, sz)
	var sub: Variant = opts.get("sub", null)
	if sub is Control:
		b.set_sub(sub)
	var art: Variant = opts.get("art", null)
	if art is Texture2D:
		b.set_art(art, str(opts.get("art_caption", "")))
	add_press_fx(b, b.face)
	if on_pressed.is_valid():
		_connect_pressed(b, on_pressed)
	_apply_badge(b, str(opts.get("badge", "")), 30.0, Vector2(-6, -10))
	return b


## Small lobby side button: a 72 px tile with a glyph and a label under it (shadowed white
## text), on a 96 x 116 touch area. look: "dark" (glass tile), "accent" (cyan tile),
## "orange" (orange tile), "white" (white tile, dark glyph), "diamond" (one dark glass diamond
## with a white glyph). badge: "N" | "!" | "dot" | "".
static func side_button(icon_name: String, text: String, on_pressed: Callable = Callable(), look: String = "dark", badge: String = "") -> Button:
	var b := Button.new()
	b.theme_type_variation = &"BareButton"
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	b.custom_minimum_size = Vector2(104, 120)
	b.name = "Side_" + text.to_pascal_case()
	var face := Control.new()
	face.name = "Face"
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	b.add_child(face)
	var tile := Panel.new()
	tile.name = "Tile"
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ts := 74.0
	tile.anchor_left = 0.5
	tile.anchor_right = 0.5
	tile.offset_left = -ts * 0.5
	tile.offset_right = ts * 0.5
	tile.offset_top = 4
	tile.offset_bottom = 4 + ts
	var glyph_tint := Color.WHITE
	if look == "diamond":
		# One frame only: a dark glass diamond with the white glyph on it.
		tile.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		tile.draw.connect(func() -> void:
			var ci := tile.get_canvas_item()
			var c := tile.size * 0.5
			var r := ts * 0.5
			var dia := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)])
			KitBox.soft_shadow(ci, dia, Color(0, 0, 0, 0.4), 6.0, Vector2(0, 2))
			KitBox.fill_poly(ci, dia, Color("121c31d9"), Color("090e1cd9"))
			KitBox.stroke_poly(ci, dia, Color(1, 1, 1, 0.45), 1.5))
	else:
		var kind := {"accent": "tile_accent", "orange": "tile_orange", "white": "tile_white"}.get(look, "tile_dark") as String
		tile.add_theme_stylebox_override("panel", UITheme.style(kind))
		if look == "white":
			glyph_tint = Color("111c31")
	face.add_child(tile)
	var isz := ts * (0.46 if look == "diamond" else 0.6)
	var ic := icon(icon_name, isz, glyph_tint)
	ic.name = "Glyph"
	_center_child(tile, ic, Vector2(isz, isz))
	var l := label(text, 22, Color.WHITE, "extrabold", 0)
	l.name = "Caption"
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.add_theme_constant_override("shadow_outline_size", 6)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.anchor_right = 1.0
	l.offset_left = -10
	l.offset_right = 10
	l.offset_top = 4 + ts + 6
	l.offset_bottom = 4 + ts + 34
	face.add_child(l)
	add_press_fx(b, face)
	if on_pressed.is_valid():
		_connect_pressed(b, on_pressed)
	_apply_badge(tile, badge, 28.0, Vector2(-12, -10))
	return b


## Character speech line over the lobby art: dark translucent box, bold name, text.
## Update later with set_meta("text_label") / set_meta("name_label").
static func speech_bubble(speaker: String, text: String, width: float = 560.0) -> PanelContainer:
	var p := PanelContainer.new()
	p.name = "SpeechBubble"
	p.theme_type_variation = &"SpeechPanel"
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.custom_minimum_size.x = width
	var v := vbox(6)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var n := label(speaker, 26, Color.WHITE, "extrabold")
	v.add_child(n)
	var t := body(text, 24, Color("f0f2f4"))
	t.add_theme_constant_override("line_spacing", 2)
	v.add_child(t)
	# The glass is light (about 45% black): a soft shadow keeps the words crisp over art.
	for lab: Label in [n, t]:
		lab.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
		lab.add_theme_constant_override("shadow_offset_y", 1)
		lab.add_theme_constant_override("shadow_outline_size", 3)
	p.add_child(v)
	p.set_meta("name_label", n)
	p.set_meta("text_label", t)
	return p


## Event / feature banner (top-left of the lobby): dark plate, faint hatching in `color`,
## optional hero art crop on the left, a big condensed title and a colored sub-plate.
## opts: size (Vector2(330, 136)), color (ACCENT), hero_id, texture, sub_color, pages
## (carousel dot count, 0 = none), page (active dot).
static func banner_card(title_text: String, subtitle: String = "", on_pressed: Callable = Callable(), opts: Dictionary = {}) -> Button:
	var sz: Vector2 = opts.get("size", Vector2(330, 136))
	var col: Color = opts.get("color", ACCENT)
	var b := Button.new()
	b.theme_type_variation = &"BareButton"
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	b.name = "Banner_" + title_text.to_pascal_case()
	var pages := int(opts.get("pages", 0))
	b.custom_minimum_size = Vector2(sz.x, sz.y + (22.0 if pages > 0 else 0.0))
	var face := Panel.new()
	face.name = "Face"
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.clip_contents = true
	face.size = sz
	face.custom_minimum_size = sz
	var bx := KitBox.new()
	bx.radius = 4
	bx.top_color = Color("111b30f0")
	bx.bottom_color = Color("080d1bf0")
	bx.horizontal = true
	bx.hatch_color = Color(col, 0.16)
	bx.hatch_spacing = 10
	bx.hatch_from = 0.35
	bx.shadow_size = 8
	bx.shadow_color = Color(0, 0, 0, 0.4)
	bx.border_width = 1.0
	bx.border_color = Color(1, 1, 1, 0.16)
	face.add_theme_stylebox_override("panel", bx.commit())
	b.add_child(face)
	var text_x := 18.0
	var tex: Variant = opts.get("texture", null)
	var hid := str(opts.get("hero_id", ""))
	if tex == null and hid != "":
		tex = art_crop(hid, (sz.x * 0.46) / sz.y, 1.15)
	if tex is Texture2D:
		var art := TextureRect.new()
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.texture = tex
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		art.size = Vector2(sz.x * 0.46, sz.y)
		face.add_child(art)
		var fade := TextureRect.new()
		fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fade.texture = vgradient(Color("0c132300"), Color("0c1323f5"), true)
		fade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		fade.stretch_mode = TextureRect.STRETCH_SCALE
		fade.position = Vector2(sz.x * 0.3, 0)
		fade.size = Vector2(sz.x * 0.18, sz.y)
		face.add_child(fade)
		text_x = sz.x * 0.47
	var t := label(title_text.to_upper(), int(sz.y * 0.3), Color.WHITE, "title", 0)
	t.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	t.add_theme_constant_override("shadow_offset_y", 2)
	t.position = Vector2(text_x, sz.y * 0.08)
	t.size = Vector2(sz.x - text_x - 12.0, sz.y * 0.58)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	var tf := font("title")
	var tfs := int(sz.y * 0.3)
	while tfs > 16 and (tf.get_multiline_string_size(t.text, HORIZONTAL_ALIGNMENT_LEFT, t.size.x, tfs).y > t.size.y * 1.12 \
			or tf.get_string_size(_longest_word(t.text), HORIZONTAL_ALIGNMENT_LEFT, -1, tfs).x > t.size.x):
		tfs -= 1
	t.add_theme_font_size_override("font_size", tfs)
	t.add_theme_constant_override("line_spacing", -int(tfs * 0.22))
	face.add_child(t)
	if subtitle != "":
		var sc: Color = opts.get("sub_color", ORANGE_HI)
		var sub := tag(subtitle.to_upper(), sc, TEXT if sc.get_luminance() > 0.5 else Color.WHITE, int(maxf(16.0, sz.y * 0.13)))
		sub.position = Vector2(text_x, sz.y * 0.7)
		face.add_child(sub)
	if pages > 0:
		var dots := Deco.new()
		dots.kind = "pips"
		dots.count = pages
		dots.filled = 0
		dots.color = Color.WHITE
		dots.color2 = Color(1, 1, 1, 0.45)
		dots.size = Vector2(pages * 16.0, 8.0)
		dots.position = Vector2((sz.x - dots.size.x) * 0.5, sz.y + 8.0)
		dots.set_meta("active", int(opts.get("page", 0)))
		dots.filled = int(opts.get("page", 0)) + 1
		b.add_child(dots)
	add_press_fx(b, face)
	if on_pressed.is_valid():
		_connect_pressed(b, on_pressed)
	_apply_badge(face, str(opts.get("badge", "")), 28.0, Vector2(-8, 6))
	return b


static func _longest_word(text: String) -> String:
	var best := ""
	for w in text.split(" ", false):
		if w.length() > best.length():
			best = w
	return best


## Objective strip ("Next: Stage 1-5"): dark glass bar with a cyan hexagon holding a glyph
## (default the objective flag) on the left, the text, and a white chevron on the right.
## The whole strip is the 88 px touch target.
static func notice_bar(text: String, on_pressed: Callable = Callable(), width: float = 420.0, icon_name: String = "flag") -> Button:
	var b := Button.new()
	b.theme_type_variation = &"BareButton"
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	b.name = "NoticeBar"
	b.custom_minimum_size = Vector2(width, BUTTON_H)
	var face := Control.new()
	face.name = "Face"
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	b.add_child(face)
	var bar := Panel.new()
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override("panel", UITheme.style("notice"))
	bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar.offset_left = 26
	bar.offset_top = 16
	bar.offset_bottom = -16
	face.add_child(bar)
	var hx := hex_badge(icon_name, 62, ACCENT, Color.WHITE)
	hx.name = "Glyph"
	hx.set("glow", Color(0, 0, 0, 0.35))
	hx.set("glow_size", 5.0)
	hx.position = Vector2(0, 13)
	face.add_child(hx)
	var l := label(text, 24, Color.WHITE, "extrabold")
	l.name = "Text"
	l.anchor_right = 1.0
	l.anchor_bottom = 1.0
	l.offset_left = 76
	l.offset_right = -48
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	face.add_child(l)
	var ai := icon("chevron_right", 26, Color(1, 1, 1, 0.9))
	ai.anchor_left = 1.0
	ai.anchor_right = 1.0
	ai.anchor_top = 0.5
	ai.anchor_bottom = 0.5
	ai.offset_left = -40
	ai.offset_right = -14
	ai.offset_top = -13
	ai.offset_bottom = 13
	face.add_child(ai)
	b.set_meta("text_label", l)
	add_press_fx(b, face)
	if on_pressed.is_valid():
		_connect_pressed(b, on_pressed)
	return b


## Fill meter plate (the Sanctum fill % on the idle shortcut): dark plate, glyph, a two-line
## uppercase caption, a big cyan percentage ("41%") and a thin bar; an optional level tag
## sits under the glyph. Update with set_percent_meter(m, pct).
static func percent_meter(caption_text: String, pct: float, icon_name: String = "sanctum", level_text: String = "") -> PanelContainer:
	var p := PanelContainer.new()
	p.name = "PercentMeter"
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", UITheme.style("meter"))
	var row := hbox(10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var left := vbox(0)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(icon(icon_name, 46, ACCENT_HI))
	if level_text != "":
		var lt := tag(level_text, Color("1d2a38"), INK, 15)
		left.add_child(lt)
	row.add_child(left)
	var mid := vbox(2)
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	var cap := label(caption_text.to_upper(), 20, Color.WHITE, "cond_bold")
	cap.add_theme_constant_override("line_spacing", -6)
	mid.add_child(cap)
	var bar := ProgressBar.new()
	bar.name = "Bar"
	bar.show_percentage = false
	bar.max_value = 100.0
	bar.value = clampf(pct, 0.0, 100.0)
	bar.custom_minimum_size = Vector2(110, 6)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.14)
	var fg := StyleBoxFlat.new()
	fg.bg_color = ACCENT
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fg)
	mid.add_child(bar)
	row.add_child(mid)
	var n := label("%d%%" % int(clampf(pct, 0.0, 999.0)), 46, ACCENT_HI, "cond_bold")
	n.custom_minimum_size.x = 92
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	n.name = "Percent"
	row.add_child(n)
	p.add_child(row)
	p.set_meta("percent_label", n)
	p.set_meta("bar", bar)
	return p


## Updates a percent_meter.
static func set_percent_meter(m: Control, pct: float) -> void:
	var n: Label = m.get_meta("percent_label") if m.has_meta("percent_label") else null
	if n:
		n.text = "%d%%" % int(clampf(pct, 0.0, 999.0))
	var bar: ProgressBar = m.get_meta("bar") if m.has_meta("bar") else null
	if bar:
		bar.value = clampf(pct, 0.0, 100.0)


## One dark glass bar holding several currencies ("[icon] 30,367 +"), the top-bar resource
## pill. entries: [{id, amount, on_plus (Callable, optional)}]. Each entry is tappable when
## it has on_plus; update an amount with set_chip_amount(pill.get_meta("entries")[id], n).
static func resource_pill(entries: Array, entry_width: float = 150.0) -> PanelContainer:
	var p := PanelContainer.new()
	p.name = "ResourcePill"
	p.theme_type_variation = &"ChipPanel"
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	var row := hbox(0)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	var map := {}
	var i := 0
	for e: Variant in entries:
		if not (e is Dictionary):
			continue
		var d := e as Dictionary
		var id := str(d.get("id", "gold"))
		if i > 0:
			var sep := ColorRect.new()
			sep.color = Color(1, 1, 1, 0.12)
			sep.custom_minimum_size = Vector2(1, 30)
			sep.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(sep)
		var cell := PanelContainer.new()
		cell.name = "Res_" + id
		cell.mouse_filter = Control.MOUSE_FILTER_PASS
		cell.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		cell.custom_minimum_size = Vector2(entry_width, 0)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var h := hbox(4)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(currency_icon(id, 40))
		var n := label(format_num(int(d.get("amount", 0))), 26, Color.WHITE, "black")
		n.name = "Amount"
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(n)
		var cb: Variant = d.get("on_plus", null)
		if cb is Callable and (cb as Callable).is_valid():
			h.add_child(icon("plus", 22, Color(1, 1, 1, 0.9)))
		h.add_child(spacer(8))
		cell.add_child(h)
		cell.set_meta("amount", int(d.get("amount", 0)))
		cell.set_meta("amount_label", n)
		if cb is Callable and (cb as Callable).is_valid():
			make_tappable(cell, cb)
		row.add_child(cell)
		map[id] = cell
		i += 1
	p.add_child(row)
	p.set_meta("entries", map)
	return p


## Rounded-square avatar (a hero's head crop) with a white rim and an optional small dark
## caption tag under it (player name). Tappable when on_pressed is valid. size = tile px.
static func avatar(hero_id: String, size: float = 76.0, caption_text: String = "", on_pressed: Callable = Callable()) -> Button:
	var b := Button.new()
	b.theme_type_variation = &"BareButton"
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	b.name = "Avatar"
	b.custom_minimum_size = Vector2(maxf(size, BUTTON_H), maxf(size + (22.0 if caption_text != "" else 0.0), BUTTON_H))
	var face := Control.new()
	face.name = "Face"
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	b.add_child(face)
	var frame := Panel.new()
	frame.name = "Frame"
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.clip_contents = true
	frame.add_theme_stylebox_override("panel", UITheme.style("avatar"))
	frame.anchor_left = 0.5
	frame.anchor_right = 0.5
	frame.offset_left = -size * 0.5
	frame.offset_right = size * 0.5
	frame.offset_top = 0
	frame.offset_bottom = size
	face.add_child(frame)
	if hero_id != "":
		var art := TextureRect.new()
		art.name = "Art"
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.texture = art_crop(hero_id, 1.0, 1.6)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		art.offset_left = 3
		art.offset_top = 3
		art.offset_right = -3
		art.offset_bottom = -3
		frame.add_child(art)
	if caption_text != "":
		var t := tag(caption_text.to_upper(), Color("0a101f"), Color.WHITE, 17)
		t.name = "Caption"
		t.anchor_left = 0.5
		t.anchor_right = 0.5
		t.grow_horizontal = Control.GROW_DIRECTION_BOTH
		t.offset_top = size - 8
		face.add_child(t)
		b.set_meta("caption", t)
	b.set_meta("frame", frame)
	add_press_fx(b, face)
	if on_pressed.is_valid():
		_connect_pressed(b, on_pressed)
	return b


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


## Thin technical hairline (fades out at both ends). light = for light pages.
static func divider(width: float = 0.0, light: bool = false) -> Control:
	var row := hbox(0)
	row.custom_minimum_size = Vector2(width, 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Filigree.new()
	l.direction = -1
	l.ornament = false
	var r := Filigree.new()
	r.direction = 1
	r.ornament = false
	if light:
		l.color = Color(0, 0, 0, 0.22)
		r.color = Color(0, 0, 0, 0.22)
	add(row, [l, r])
	return row


# ------------------------------------------------------------------ panels

## Panel container. Dark (light text): "glass" (default, dark translucent with corner
## marks), "card" (list rows), "inset" (sunken groups), "plain" (no border). Light (dark
## text): "white" (white card with shadow), "paper" (flat page tone), "light_inset"
## (grey well), "row" (flat white list row). pad overrides the inner padding.
static func panel(kind: String = "glass", pad: int = -1) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	var variations := {"glass": &"GlassPanel", "card": &"CardPanel", "inset": &"InsetPanel", "plain": &"PlainPanel",
		"white": &"WhitePanel", "paper": &"PaperPanel", "light_inset": &"LightInsetPanel", "row": &"RowPanel",
		"speech": &"SpeechPanel", "bar": &"BarPanel"}
	p.theme_type_variation = variations.get(kind, &"GlassPanel")
	if pad >= 0:
		p.add_theme_stylebox_override("panel", style(kind, pad))
	return p


## A list-row card (shorthand for panel("card", pad)).
static func card(pad: int = -1) -> PanelContainer:
	return panel("card", pad)


## White info panel (the hero detail column, light page cards).
static func info_panel(pad: int = -1) -> PanelContainer:
	return panel("white", pad)


## Dark header bar for a light panel section ("STATUS", "EQUIP"): graphite plate, uppercase
## condensed white text, hatching at the right end. right = optional control at the end.
static func header_bar(text: String, right: Control = null, icon_name: String = "") -> PanelContainer:
	var p := PanelContainer.new()
	p.name = "HeaderBar"
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	p.add_theme_stylebox_override("panel", UITheme.style("header_bar"))
	var row := hbox(10)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	if icon_name != "":
		row.add_child(icon(icon_name, 26))
	var l := label(text.to_upper(), 24, Color.WHITE, "cond_bold")
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	if right:
		right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(right)
	p.add_child(row)
	return p


## Light hatched page background (or "dark"): add as the first child of a screen that wants
## the light page look. Fills its parent.
static func page_bg(mode: String = "light") -> Control:
	var b := Backdrop.new()
	b.name = "PageBg"
	b.mode = mode
	b.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


## A fresh StyleBox preset (see UITheme.style for kinds). pad = content margin override.
static func style(kind: String, pad: int = -1) -> StyleBox:
	return UITheme.style(kind, pad)


## Custom house box: vertical gradient, optional border. For one-off frames.
static func box(top: Color, bottom: Color, border: Color = Color.TRANSPARENT, radius: float = 8.0, border_width: int = 2, pad: int = 0) -> StyleBox:
	var b := KitBox.new()
	b.top_color = top
	b.bottom_color = bottom
	b.radius = radius
	if border.a > 0.0:
		b.border_color = border
		b.border_width = border_width
	b.set_content_margin_all(pad)
	return b.commit()


## Standard dialog: a light panel with a blue header (title, optional glyph, white close X)
## and `content` in the body. light = false gives a graphite body for content built with
## light text (INK). Returns the dialog panel; its close Button is get_meta("close_button")
## (UI.popup wires it). width in px.
static func dialog(title_text: String, content: Control, width: float = 640.0, light: bool = true, icon_name: String = "") -> PanelContainer:
	var panel_c := PanelContainer.new()
	panel_c.name = "Dialog"
	panel_c.theme_type_variation = &"DialogPanel" if light else &"ModalPanel"
	panel_c.add_theme_stylebox_override("panel", UITheme.style("dialog" if light else "dialog_dark"))
	panel_c.custom_minimum_size.x = width
	var col := vbox(0)
	panel_c.add_child(col)
	var head := PanelContainer.new()
	head.name = "Header"
	head.add_theme_stylebox_override("panel", UITheme.style("dialog_header"))
	head.custom_minimum_size.y = 84
	var hrow := hbox(10)
	hrow.alignment = BoxContainer.ALIGNMENT_CENTER
	hrow.add_child(spacer(64))
	var mid := hbox(10)
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if icon_name != "":
		mid.add_child(icon(icon_name, 34))
	var t := label(title_text, 30, Color.WHITE, "extrabold")
	t.name = "Title"
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fit_label(t, width - 170.0 - (44.0 if icon_name != "" else 0.0), 30, 20)
	mid.add_child(t)
	hrow.add_child(mid)
	var close := icon_button("close", Callable(), BUTTON_H, "bare")
	close.name = "Close"
	close.custom_minimum_size = Vector2(64, 84)
	hrow.add_child(close)
	head.add_child(hrow)
	col.add_child(head)
	var body_m := margin(content, 26, 24)
	body_m.name = "Body"
	col.add_child(body_m)
	panel_c.set_meta("close_button", close)
	panel_c.set_meta("title_label", t)
	return panel_c


# ------------------------------------------------------------------ progress & stars

## Flat technical progress bar (squared ends, bright top edge on the fill). text (optional)
## is drawn centered on the bar. light = track for light pages.
static func progress_bar(value: float, max_value: float, color: Color = GOOD, height: float = 24.0, text: String = "", light: bool = false) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.min_value = 0
	bar.max_value = maxf(max_value, 0.0001)
	bar.value = clampf(value, 0.0, bar.max_value)
	bar.custom_minimum_size = Vector2(80, height)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var r := minf(3.0, height * 0.2)
	var bg := KitBox.new()
	bg.radius = r
	if light:
		bg.top_color = Color("d3d8de")
		bg.bottom_color = Color("dfe3e8")
	else:
		bg.top_color = Color(0, 0, 0, 0.55)
		bg.bottom_color = Color(0.05, 0.05, 0.06, 0.55)
		bg.border_width = 1
		bg.border_color = Color(1, 1, 1, 0.1)
	bar.add_theme_stylebox_override("background", bg.commit())
	var fg := KitBox.new()
	fg.radius = r
	fg.top_color = color.lightened(0.12)
	fg.bottom_color = color.darkened(0.08)
	fg.top_line_color = Color(color.lightened(0.6), 0.9)
	if height >= 16.0:
		fg.hatch_color = Color(1, 1, 1, 0.12)
		fg.hatch_spacing = 8.0
	bar.add_theme_stylebox_override("fill", fg.commit())
	var l := label(text, int(clampf(height * 0.8, 16, 26)), Color.WHITE, "cond_bold", 3)
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


## Row of stars. max_stars > stars shows the missing ones as dim slots.
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


## Dark glass chip showing a currency icon and amount (compact formatted). on_plus = tap
## action (shows a small "+" and makes the whole chip tappable). Update with set_chip_amount.
static func currency_chip(currency_id: String, amount: int, on_plus: Callable = Callable(), min_width: float = 0.0) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.theme_type_variation = &"ChipPanel"
	chip.mouse_filter = Control.MOUSE_FILTER_PASS
	chip.custom_minimum_size = Vector2(min_width, 52)
	var row := hbox(4)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(currency_icon(currency_id, 40))
	var n := label(format_num(amount), 26, Color.WHITE, "black")
	n.name = "Amount"
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(n)
	if on_plus.is_valid():
		row.add_child(icon("plus", 22, Color(1, 1, 1, 0.9)))
	else:
		row.add_child(spacer(4))
	chip.add_child(row)
	chip.set_meta("amount", amount)
	chip.set_meta("amount_label", n)
	if on_plus.is_valid():
		make_tappable(chip, on_plus)
	return chip


## Updates a currency chip (or a resource_pill entry); animate counts and pulses on change.
static func set_chip_amount(chip: Control, amount: int, animate: bool = true) -> void:
	if not chip.has_meta("amount_label"):
		return
	var l := chip.get_meta("amount_label") as Label
	if l == null:
		return
	var old: int = chip.get_meta("amount", amount)
	chip.set_meta("amount", amount)
	if old == amount:
		l.text = format_num(amount)
		return
	if animate and chip.is_inside_tree():
		count_to(l, old, amount, 0.45)
		pulse(chip, 1.06)
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
	# Previews: stage first-clear gear_drops [{slot, tier}] (grouped) and idle gear_count.
	var drops := {}
	var order: Array[String] = []
	for d: Variant in reward.get("gear_drops", []):
		if d is Dictionary:
			var key := "%s:%d" % [str(d.get("slot", "")), int(d.get("tier", 1))]
			if not drops.has(key):
				order.append(key)
			drops[key] = int(drops.get(key, 0)) + 1
	for key in order:
		out.append({"kind": "gear_drop", "id": key, "amount": int(drops[key])})
	if int(reward.get("gear_count", 0)) > 0:
		out.append({"kind": "gear_drop", "id": ":0", "amount": int(reward.gear_count)})
	return out


## Wrapping, centered list of reward tiles for a Reward dict. light = captions for light
## panels (dark text).
static func reward_list(reward: Dictionary, tile: float = 112.0, show_names: bool = true, center_items: bool = true, light: bool = false) -> HFlowContainer:
	var f := flow(14, center_items)
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for e in reward_entries(reward):
		f.add_child(reward_tile(e.kind, e.id, int(e.amount), tile, show_names, light))
	return f


## One reward tile: a pale item tile with a colored base strip and the amount bottom-right.
## kind: "currency" (id = currency id), "hero", "shard" (id = hero id), "gear" (id = gear
## uid), "gear_drop" (preview, id = "slot:tier"; empty slot = any slot, tier 0 = unknown;
## amount = how many). show_name adds a caption under the tile.
static func reward_tile(kind: String, id: String, amount: int, tile: float = 112.0, show_name: bool = true, light: bool = false) -> Control:
	var col := vbox(4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name_text := ""
	var face: Control
	match kind:
		"hero":
			face = hero_card(id, {"size": tile, "show_level": false, "owned": true})
			name_text = str(_def(id).get("name", id))
		"shard":
			face = hero_card(id, {"size": tile, "show_level": false, "show_stars": false, "shard": true, "owned": true})
			var amt := label("x%s" % format_num(amount), int(tile * 0.2), Color.WHITE, "black", 5)
			_corner(face, amt, Vector2(1, 1), Vector2(-8, -6))
			name_text = str(_def(id).get("name", id))
		"gear":
			var item := _gear_item(id)
			var slot := str(item.get("slot", "weapon"))
			var tier := int(item.get("tier", 1))
			face = _tile_box(tile, tier_color(tier))
			var gi := icon("gear_" + slot, tile * 0.56, Color("1c2d4b"))
			_center_child(face, gi, gi.custom_minimum_size)
			var hx := hex_badge("", tile * 0.3, Color("1b2a47"), Color.WHITE, roman(tier))
			hx.position = Vector2(4, 4)
			face.add_child(hx)
			name_text = str(item.get("name", GEAR_SLOT_NAMES.get(slot, "Gear")))
		"gear_drop":
			var parts := id.split(":")
			var slot := parts[0] if parts.size() > 0 else ""
			var tier := int(parts[1]) if parts.size() > 1 else 0
			var accent := tier_color(tier) if tier > 0 else SKY
			face = _tile_box(tile, accent)
			var gi := icon("gear_" + (slot if slot != "" else "weapon"), tile * 0.56, Color("1c2d4b"))
			_center_child(face, gi, gi.custom_minimum_size)
			if tier > 0:
				var hx := hex_badge("", tile * 0.3, Color("1b2a47"), Color.WHITE, roman(tier))
				hx.position = Vector2(4, 4)
				face.add_child(hx)
			if amount > 1 or slot == "":
				var amt := label("x%d" % amount, int(tile * 0.22), Color.WHITE, "black", 5)
				_corner(face, amt, Vector2(1, 1), Vector2(-8, -6))
			name_text = str(GEAR_SLOT_NAMES.get(slot, "Gear")) if slot != "" else "Gear"
		_:
			var accent := {"gold": GOLD, "gems": ACCENT, "scrolls": VIOLET, "hero_exp": GOOD, "dust": EPIC}
			face = _tile_box(tile, accent.get(id, GOLD))
			var ci := icon(id, tile * 0.62)
			_center_child(face, ci, ci.custom_minimum_size)
			var amt := label(format_num(amount), int(tile * 0.22), Color.WHITE, "black", 5)
			_corner(face, amt, Vector2(1, 1), Vector2(-8, -6))
			name_text = str(CURRENCY_SHORT.get(id, id.capitalize()))
	col.add_child(face)
	if show_name:
		var n := caption(name_text, 18, TEXT_DIM if light else INK_DIM)
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		n.custom_minimum_size.x = tile
		n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		n.clip_text = true
		col.add_child(n)
	col.custom_minimum_size.x = tile
	return col


## Pale item tile with a colored base strip (rewards, gear).
static func _tile_box(tile: float, accent: Color) -> Control:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(tile, tile)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var b := KitBox.new()
	b.radius = 4
	b.top_color = Color("f4f6f8")
	b.bottom_color = Color("d4d9df")
	b.border_width = 1
	b.border_color = Color(0, 0, 0, 0.18)
	b.hatch_color = Color(0, 0, 0, 0.045)
	b.hatch_spacing = 7
	b.hatch_from = 0.5
	b.shadow_size = 4
	b.shadow_color = Color(0, 0, 0, 0.3)
	b.shadow_offset = Vector2(0, 2)
	p.add_theme_stylebox_override("panel", b.commit())
	var strip := ColorRect.new()
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.color = accent
	strip.anchor_top = 1.0
	strip.anchor_bottom = 1.0
	strip.anchor_right = 1.0
	strip.offset_left = 1
	strip.offset_right = -1
	strip.offset_top = -maxf(4.0, tile * 0.055)
	strip.offset_bottom = -1
	p.add_child(strip)
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
	var g := autoload("Game")
	var d: Variant = g.hero_def(hero_id) if g else HeroData.get_def(hero_id)
	return d if d is Dictionary else {}


static func _gear_item(uid: String) -> Dictionary:
	var g := autoload("Game")
	if g == null:
		return {}
	var items: Variant = g.gear_items()
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


## Rarity color (rare blue, epic purple, legendary orange-gold).
static func rarity_color(rarity: String) -> Color:
	match rarity:
		"rare":
			return RARE
		"epic":
			return EPIC
		"legendary":
			return LEGENDARY
	return INK_DIM


## Gear tier color 1-5 (grey, green, blue, purple, orange-gold).
static func tier_color(tier: int) -> Color:
	var cols := [Color("9aa1aa"), GOOD, RARE, EPIC, LEGENDARY]
	return cols[clampi(tier - 1, 0, 4)]


## Roman numeral 1-10 ("I", "IV"); other numbers as digits.
static func roman(n: int) -> String:
	var r := ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"]
	return r[n - 1] if n >= 1 and n <= 10 else str(n)


## Frame StyleBox in the rarity color (border only), for custom portraits/cards.
static func rarity_frame(rarity: String, width: int = 3, radius: float = 4.0) -> StyleBox:
	var c := rarity_color(rarity)
	var b := KitBox.new()
	b.fill = false
	b.radius = radius
	b.border_width = width
	b.border_color = c
	return b.commit()


## Faction emblem icon (celestial halo-sun, infernal horned flame, fallen broken halo).
static func faction_icon(faction: String, size: float = 40.0) -> TextureRect:
	return icon("faction_" + faction, size)


## Role icon (guardian, striker, caster, support, assassin), tintable.
static func role_icon(role: String, size: float = 36.0, color: Color = Color.WHITE) -> TextureRect:
	return icon("role_" + role, size, color)


## Faction emblem + name in the faction color. light = darker name for light pages.
static func faction_badge(faction: String, size: float = 40.0, show_name: bool = true, light: bool = false) -> HBoxContainer:
	var row := hbox(8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(faction_icon(faction, size))
	if show_name:
		var c := faction_color(faction).darkened(0.35) if light else faction_color(faction).lerp(Color.WHITE, 0.2)
		row.add_child(label(str(FACTION_NAMES.get(faction, faction.capitalize())).to_upper(), int(size * 0.6), c, "cond_bold"))
	return row


## Role tag: dark plate with the role glyph and name.
static func role_badge(role: String, size: float = 36.0, show_name: bool = true) -> PanelContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = &"TagPanel"
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := hbox(6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(role_icon(role, size * 0.8))
	if show_name:
		row.add_child(label(str(ROLE_NAMES.get(role, role.capitalize())).to_upper(), int(size * 0.6), INK, "cond_bold"))
	p.add_child(row)
	return p


## Skewed rarity plate ("LEGENDARY") in the rarity color.
static func rarity_badge(rarity: String, size: int = 20) -> PanelContainer:
	var c := rarity_color(rarity)
	var p := tag(str(RARITY_NAMES.get(rarity, rarity.capitalize())).to_upper(), c, Color.WHITE, size)
	var b := KitBox.new()
	b.radius = 2
	b.skew = SKEW * 1.4
	b.top_color = c.lightened(0.1)
	b.bottom_color = c.darkened(0.1)
	b.horizontal = true
	b.hatch_color = Color(1, 1, 1, 0.16)
	b.hatch_spacing = 6
	b.hatch_from = 0.7
	b.content_margin_left = size * 0.9
	b.content_margin_right = size * 0.9
	b.content_margin_top = 0
	b.content_margin_bottom = 1
	p.add_theme_stylebox_override("panel", b.commit())
	return p


## Big rarity word for headers (hero detail): condensed extra-bold text in the rarity color
## with rarity chevrons in front. Returns an HBox.
static func rarity_mark(rarity: String, size: int = 40) -> HBoxContainer:
	var row := hbox(6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var c := rarity_color(rarity)
	var chev := deco("chevrons", Vector2(size * 0.9, size * 0.7), c)
	chev.set("count", int(RARITY_STARS.get(rarity, 1)))
	chev.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(chev)
	var l := label(str(RARITY_NAMES.get(rarity, rarity)).to_upper(), size, c, "title", 0)
	l.add_theme_color_override("font_shadow_color", Color(c.darkened(0.6), 0.5))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	row.add_child(l)
	return row


## Small flat tag, e.g. tag("NEW"), tag("BOSS", Kit.EMBER). Barlow Condensed, uppercase look.
static func tag(text: String, color: Color = ACCENT, text_color: Color = Color.WHITE, size: int = 20) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var b := KitBox.new()
	b.radius = 3
	b.top_color = color.lightened(0.08)
	b.bottom_color = color.darkened(0.08)
	b.content_margin_left = size * 0.5
	b.content_margin_right = size * 0.5
	b.content_margin_top = 0
	b.content_margin_bottom = 1
	p.add_theme_stylebox_override("panel", b.commit())
	var l := label(text, size, text_color, "cond_bold")
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p


## Hexagon badge with a glyph (icon_name) or short text (text), e.g. role marks, tier
## numerals, skill slots. Returns a sized Control (place it, or put it in a container).
static func hex_badge(icon_name: String, size: float = 44.0, fill: Color = Color("182640"), fg: Color = Color.WHITE, text: String = "") -> Control:
	var h := HexBadge.new()
	h.custom_minimum_size = Vector2(size, size)
	h.size = Vector2(size, size)
	h.fill = fill.lightened(0.06)
	h.fill_bottom = fill.darkened(0.12)
	var lightfill := fill.get_luminance() > 0.6
	h.border = Color(0.1, 0.11, 0.13, 0.85) if lightfill else Color(1, 1, 1, 0.6)
	h.border_width = maxf(1.5, size * 0.05)
	if icon_name != "":
		h.set_icon(icon_name, fg, 0.54)
	if text != "":
		h.set_text(text, fg, int(size * 0.44), "title")
	return h


## Red-orange "N" badge (new) or a short count/"!" in the same look.
static func new_badge(size: float = 30.0, text: String = "N") -> Control:
	var b := Badge.new()
	b.text = text
	b.custom_minimum_size = Vector2(size, size)
	b.size = Vector2(size, size)
	return b


## Shows/hides an "N" badge at the top-right corner of `target` (not a Container).
static func set_new(target: Control, show: bool, size: float = 30.0, inset: Vector2 = Vector2(-8, -8), text: String = "N") -> void:
	var b := target.get_node_or_null("KitNew") as Control
	if b == null:
		if not show:
			return
		b = new_badge(size, text)
		b.name = "KitNew"
		_corner(target, b, Vector2(1, 0), Vector2(-inset.x, inset.y))
		b.offset_left = -inset.x - size
		b.offset_right = -inset.x
		b.offset_top = inset.y
		b.offset_bottom = inset.y + size
	b.visible = show


static func _apply_badge(target: Control, badge: String, size: float, inset: Vector2) -> void:
	match badge:
		"N":
			set_new(target, true, size, inset)
		"!":
			var b := new_badge(size, "!")
			(b as Badge).round = true
			(b as Badge).color = ACCENT
			b.name = "KitNew"
			_corner(target, b, Vector2(1, 0), Vector2(-inset.x, inset.y))
			b.offset_left = -inset.x - size
			b.offset_right = -inset.x
			b.offset_top = inset.y
			b.offset_bottom = inset.y + size
		"dot":
			set_dot(target, true, size * 0.7, Vector2(inset.x + 4, inset.y + 4))


## Decoration: kind "hatch" | "barcode" | "brackets" | "chevrons" | "techline" | "pips" |
## "dots" | "cross" (see deco.gd). Returns the sized Control (set .count/.filled etc.).
static func deco(kind: String, size: Vector2, color: Color = Color(1, 1, 1, 0.12)) -> Control:
	var d := Deco.new()
	d.kind = kind
	d.color = color
	d.custom_minimum_size = size
	d.size = size
	return d


# ------------------------------------------------------------------ hero cards

## Square hero card: head-and-shoulders portrait on a pale studio tile, role/faction hex,
## level, star pips, rarity strip. Returns a Button (tap with opts.on_pressed).
## opts (all optional):
##   size: float = 152        level: int, stars: int (default: owned values or rarity base)
##   owned: bool (default Game.owns)  unowned cards are greyed out
##   locked: bool             dark overlay with a lock
##   selected: bool           cyan glow ring
##   checked: bool            dark overlay with a check
##   show_name: bool = false  name caption under the card (light: bool = dark caption)
##   show_level / show_stars / show_faction: bool = true
##   dot: bool                red notification dot
##   tag: String              "N" = new badge, otherwise a small tag ("x2", "BOSS")
##   shard: bool              shard overlay (for shard rewards)
##   on_pressed: Callable
static func hero_card(hero_id: String, opts: Dictionary = {}) -> Button:
	var c := HeroCard.new()
	c.setup(hero_id, opts)
	return c


## Tall roster card (4 per row on the 720 canvas at size ~158): waist-up art on a pale
## studio backdrop, role hex + tier numeral hex top-left, barcode top-right, dark-to-rarity
## footer with "LV." and a big two-digit level left and the name right, rarity chevrons and
## star pips. Same opts as hero_card (size = width; height = width * 1.62), plus new: bool.
static func portrait_card(hero_id: String, opts: Dictionary = {}) -> Button:
	var c := PortraitCard.new()
	c.setup(hero_id, opts)
	return c


## Level + name plate (hero detail): "LV.12/40" on a dark plate and the name on a black plate.
static func name_plate(level: int, max_level: int, hero_name: String, size: int = 30) -> HBoxContainer:
	var row := hbox(0)
	row.name = "NamePlate"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lvp := PanelContainer.new()
	lvp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lvp.add_theme_stylebox_override("panel", UITheme.style("plate_level"))
	var lv := hbox(2)
	lv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lv.add_child(label("LV.", int(size * 0.62), Color.WHITE, "cond_bold"))
	var n := label(str(level), size, ORANGE_HI, "title")
	n.name = "Level"
	lv.add_child(n)
	lv.add_child(label("/%d" % max_level, int(size * 0.62), INK_DIM, "cond_bold"))
	lvp.add_child(lv)
	row.add_child(lvp)
	var np := PanelContainer.new()
	np.mouse_filter = Control.MOUSE_FILTER_IGNORE
	np.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	np.add_theme_stylebox_override("panel", UITheme.style("plate_name"))
	var nl := label(hero_name, size, Color.WHITE, "extrabold")
	nl.name = "Name"
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nl.clip_text = true
	np.add_child(nl)
	row.add_child(np)
	return row


## Empty hero slot (formation, team picks): glass square with corner brackets, a faint plus
## and an optional caption ("Front", "Empty"). Returns a Button (tap with on_pressed).
static func empty_slot(size: float = 152.0, text: String = "", on_pressed: Callable = Callable()) -> Button:
	var b := Button.new()
	b.theme_type_variation = &"BareButton"
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	b.custom_minimum_size = Vector2(size, size)
	var p := Panel.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bx := KitBox.new()
	bx.radius = 4
	bx.top_color = Color(0.05, 0.06, 0.07, 0.55)
	bx.bottom_color = Color(0.08, 0.09, 0.1, 0.55)
	bx.border_width = 1
	bx.border_color = Color(1, 1, 1, 0.22)
	bx.hatch_color = Color(1, 1, 1, 0.04)
	bx.hatch_spacing = 10
	bx.corner_marks_color = Color(1, 1, 1, 0.5)
	bx.corner_marks_size = maxf(8.0, size * 0.1)
	bx.corner_marks_inset = 5
	p.add_theme_stylebox_override("panel", bx.commit())
	p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	b.add_child(p)
	var ic := icon("plus", size * 0.26, Color(1, 1, 1, 0.5))
	_center_child(b, ic, ic.custom_minimum_size)
	if text != "":
		var l := label(text.to_upper(), int(maxf(16.0, size * 0.12)), Color(INK_DIM, 0.9), "cond_bold")
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.anchor_top = 1.0
		l.anchor_bottom = 1.0
		l.anchor_right = 1.0
		l.offset_top = -size * 0.26
		l.offset_bottom = -size * 0.04
		b.add_child(l)
	add_press_fx(b)
	if on_pressed.is_valid():
		_connect_pressed(b, on_pressed)
	return b


## Equipment slot (hero detail 2x2, gear lists): pale square, the slot glyph in dark ink,
## tier numeral hex top-left and a tier-colored base strip; empty = faint glyph + plus.
## item = a GearItem dict ({} for empty). Returns a Button.
static func equip_slot(slot: String, item: Dictionary = {}, size: float = 132.0, on_pressed: Callable = Callable()) -> Button:
	var b := Button.new()
	b.theme_type_variation = &"BareButton"
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	b.custom_minimum_size = Vector2(maxf(size, BUTTON_H), maxf(size, BUTTON_H))
	b.name = "Equip_" + slot
	var empty := item.is_empty()
	var tier := int(item.get("tier", 1))
	var face: Control
	if empty:
		face = Panel.new()
		face.mouse_filter = Control.MOUSE_FILTER_IGNORE
		face.add_theme_stylebox_override("panel", UITheme.style("slot"))
	else:
		face = _tile_box(size, tier_color(tier))
	face.name = "Face"
	face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	b.add_child(face)
	var gi := icon("gear_" + slot, size * 0.54, Color(0.16, 0.18, 0.21, 0.28 if empty else 1.0))
	_center_child(face, gi, gi.custom_minimum_size)
	if empty:
		var pl := icon("plus", size * 0.22, Color(0.16, 0.18, 0.21, 0.55))
		_corner(face, pl, Vector2(1, 1), Vector2(-8, -8))
		pl.offset_left = -8 - size * 0.22
		pl.offset_top = -8 - size * 0.22
	else:
		var hx := hex_badge("", size * 0.28, Color("1b2a47"), Color.WHITE, roman(tier))
		hx.position = Vector2(5, 5)
		face.add_child(hx)
	add_press_fx(b, face)
	if on_pressed.is_valid():
		_connect_pressed(b, on_pressed)
	return b


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

## Section title: a small cyan block, the uppercase condensed title, then a technical
## hairline with end ticks to the right edge. light = dark text/lines for light pages.
static func section_header(text: String, size: int = 30, color: Color = INK, light: bool = false) -> HBoxContainer:
	var row := hbox(12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.custom_minimum_size.y = size + 14
	var mark := ColorRect.new()
	mark.color = ACCENT
	mark.custom_minimum_size = Vector2(6, size * 0.8)
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(mark)
	var tc := TEXT if light and color == INK else color
	var t := label(text.to_upper(), size, tc, "title")
	row.add_child(t)
	var r := Filigree.new()
	r.direction = 1
	r.color = Color(0, 0, 0, 0.3) if light else Color(1, 1, 1, 0.35)
	row.add_child(r)
	return row


## Standard top row for sub-screens: a dark square back button, the uppercase condensed
## title, optional control on the right. on_back defaults to UI.back().
static func screen_header(title_text: String, on_back: Callable = Callable(), right: Control = null) -> HBoxContainer:
	var row := hbox(10)
	row.custom_minimum_size.y = 96
	var cb := on_back
	if not cb.is_valid():
		cb = func() -> void:
			var u := autoload("UI")
			if u:
				u.call("back")
	var back := icon_button("back", cb, BUTTON_H, "round")
	back.name = "Back"
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(back)
	var t := header(title_text.to_upper(), SIZE_HEADER)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.clip_text = true
	t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(t)
	if right:
		right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(right)
	else:
		row.add_child(spacer(BUTTON_H))
	return row


## Stat line: icon, name, value (right aligned). stat: hp/atk/def/spd/crit.
## delta (optional) shows a green "+N" after the value (level-up previews).
## light = dark text for white panels (the info column status rows).
static func stat_row(stat: String, value: Variant, delta: Variant = null, label_text: String = "", light: bool = false) -> HBoxContainer:
	var row := hbox(12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.custom_minimum_size.y = 44
	row.add_child(icon("stat_" + stat, 30, TEXT if light else Color.WHITE))
	var n := label(label_text if label_text != "" else str(STAT_SHORT.get(stat, stat.to_upper())), SIZE_BODY - 2, TEXT_DIM if light else INK_DIM, "cond_bold")
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(n)
	var vt := str(value)
	if value is int:
		vt = format_full(value)
	row.add_child(label(vt, SIZE_BODY, TEXT if light else INK, "black"))
	if delta != null:
		var dt := str(delta)
		if delta is int:
			dt = format_full(delta)
		row.add_child(label("+" + dt, SIZE_BODY - 2, Color("1f9e63") if light else GOOD, "black"))
	return row


## Friendly empty-list message with an optional icon. light = for light pages.
static func empty_state(text: String, icon_name: String = "", light: bool = false) -> VBoxContainer:
	var v := vbox(12)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if icon_name != "":
		var ic := icon(icon_name, 96, Color(0, 0, 0, 0.25) if light else Color(1, 1, 1, 0.4))
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(ic)
	var l := body(text, SIZE_BODY, TEXT_DIM if light else INK_DIM)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	return v


# ------------------------------------------------------------------ light effects & art

## Soft radial glow sprite (behind portraits, chests, summons).
static func glow(color: Color = ACCENT, size: float = 240.0) -> TextureRect:
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


## Two-color linear gradient texture (top to bottom, or left to right), cached. Use in a
## TextureRect with STRETCH_SCALE for shades and footers.
static func vgradient(c0: Color, c1: Color, horizontal: bool = false) -> GradientTexture2D:
	var key := "%s-%s-%s" % [c0.to_html(), c1.to_html(), horizontal]
	if _grad_textures.has(key):
		return _grad_textures[key]
	var g := Gradient.new()
	g.set_color(0, c0)
	g.set_color(1, c1)
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(1, 0) if horizontal else Vector2(0, 1)
	gt.width = 64 if horizontal else 4
	gt.height = 4 if horizontal else 64
	_grad_textures[key] = gt
	return gt


## Crop of a hero's full-body art (HeroArt.texture) with aspect = width / height, framed
## from just above the head: ~0.6 gives a waist-up card crop, 1.0 a head-and-shoulders
## square. zoom > 1 crops tighter. Works the same for painted 1024x2048 art and the
## placeholder silhouettes (uses HeroArt.portrait_region). Cached AtlasTexture.
static func art_crop(hero_id: String, aspect: float, zoom: float = 1.0) -> Texture2D:
	var key := "%s:%.3f:%.2f" % [hero_id, aspect, zoom]
	if _crops.has(key):
		return _crops[key]
	var tex := HeroArt.texture(hero_id)
	if tex == null:
		return null
	var pr := HeroArt.portrait_region(hero_id)
	var tw := float(tex.get_width())
	var th := float(tex.get_height())
	var w := pr.size.x * 2.1 / maxf(zoom, 0.1)
	var h := w / maxf(aspect, 0.05)
	if h > th:
		h = th
		w = h * aspect
	if w > tw:
		w = tw
		h = w / aspect
	var cx := pr.get_center().x
	var top := pr.position.y - pr.size.y * 0.16 * zoom
	var r := Rect2(clampf(cx - w * 0.5, 0.0, maxf(tw - w, 0.0)), clampf(top, 0.0, maxf(th - h, 0.0)), w, h)
	var at := AtlasTexture.new()
	at.atlas = tex
	at.region = r
	at.filter_clip = true
	_crops[key] = at
	return at


## Slowly rotating light rays (reward popups, summon reveals). Place centered behind art.
static func rays(color: Color = ACCENT, size: float = 520.0, count: int = 14) -> Control:
	var r := Rays.new()
	r.color = color
	r.ray_count = count
	r.custom_minimum_size = Vector2(size, size)
	r.size = Vector2(size, size)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## Banner plate (skewed band with hatching and side ticks) with an uppercase condensed title
## ("VICTORY", reward popups). color: band color (Kit.ACCENT, Kit.ORANGE, Kit.EMBER for
## defeat...). Long text shrinks to fit. Change the text later with banner.set_text("...").
static func ribbon(text: String, width: float = 520.0, color: Color = ACCENT, text_color: Color = Color.WHITE, size: int = 44) -> Control:
	var r := Ribbon.new()
	r.text = text
	r.color = color
	r.text_color = text_color
	r.font_size = size
	r.custom_minimum_size = Vector2(width, size * 2.1)
	r.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return r


## Full-screen background art (e.g. HeroArt.background("home")) scaled to cover, with a
## dark fade at the top and bottom so chrome and text stay readable. Add it as the first
## child of the screen. tex may be null (only the shade is drawn).
static func art_background(tex: Texture2D, shade: float = 0.6) -> Control:
	var root := Control.new()
	root.name = "ArtBackground"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if tex:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		root.add_child(tr)
	var g := Gradient.new()
	g.set_color(0, Color(CHROME, shade))
	g.set_color(1, Color(CHROME, shade))
	g.add_point(0.2, Color(CHROME, 0.0))
	g.add_point(0.72, Color(CHROME, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 4
	gt.height = 256
	var sh := TextureRect.new()
	sh.texture = gt
	sh.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sh.stretch_mode = TextureRect.STRETCH_SCALE
	sh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sh.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(sh)
	return root


## Material that greys out a CanvasItem (unowned heroes). amount 0..1.
static func grayscale_material() -> ShaderMaterial:
	if _gray_material == null:
		var sh := Shader.new()
		sh.code = "shader_type canvas_item;\nuniform float amount : hint_range(0.0, 1.0) = 1.0;\nuniform float dim = 0.78;\nvoid fragment() {\n\tvec4 c = texture(TEXTURE, UV) * COLOR;\n\tfloat g = dot(c.rgb, vec3(0.299, 0.587, 0.114));\n\tCOLOR = vec4(mix(c.rgb, vec3(g), amount) * dim, c.a);\n}\n"
		_gray_material = ShaderMaterial.new()
		_gray_material.shader = sh
	return _gray_material


# ------------------------------------------------------------------ motion

## Pops a control in (scale 0.6 -> 1 with overshoot, fade in). Call after it is in the tree.
static func pop_in(c: Control, delay: float = 0.0, dur: float = 0.32) -> void:
	if not c.is_inside_tree():
		c.modulate.a = 1.0
		c.scale = Vector2.ONE
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
