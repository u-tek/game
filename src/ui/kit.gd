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
##   Print (v4 poster sheets, 2026-10-19)  dialog (the printed sheet every popup uses),
##              tick_rule, fill_dial/set_dial, sheet_pass (the compact OG pass), reward_receipt,
##              halftone_ramp, loading_veil, print_label; the light-family widgets (buttons,
##              chips, segments, tabs, rows, header_bar, section_header, empty_state, divider,
##              reward tiles, light progress bars) are drawn in the poster style too
##   Widgets    progress_bar/set_progress, star_row, currency_icon, currency_chip/
##              set_chip_amount, cost_row, reward_list, reward_tile, faction_badge, role_badge,
##              rarity_badge, rarity_mark, tag, hero_card, portrait_card, name_plate,
##              equip_slot, hex_badge, new_badge/set_new, dot/set_dot, section_header,
##              screen_header, stat_row, empty_state, icon, deco, glow, rays, ribbon,
##              art_background, art_crop, vgradient
##   Economy    have(currency_id), can_afford(costs)
##   Colors     faction_color, rarity_color, rarity_frame, tier_color
##   Numbers    format_num (12.5K / 3.4M), format_full (1,234,567), format_time (2h 05m)
##   Motion     pop_in, pulse, shake, deny, count_to, offset_in, stagger_in, float_text,
##              sparkle, spinner, add_shine, add_glow_pulse, motion_ok
##
## Conventions: sizes are viewport px on the 720 px wide canvas. Light-on-dark is the
## default (INK text on dark chrome); builders that also live on light pages take a
## `light` flag (TEXT colors). Builders only read Game (never write): hero cards (owned
## level/stars when not given), reward tiles (gear names), cost rows / costs buttons /
## have / can_afford (currency amounts). Buttons play UI.sfx("tap") and a light haptic.
## Every clickable Kit widget uses MOUSE_FILTER_PASS so it works inside Kit.scroll lists (a
## drag scrolls instead of pressing). Touch targets are at least BUTTON_H (88 px) tall.
##
## Feel (2026-10-19): every Kit button, tile and card squashes and brightens the instant a
## finger lands and springs back past full size on release (add_press_fx); a tap on a
## disabled button shakes "no". Primary and orange buttons, banners and the lobby call to
## action catch a light sweep now and then (add_shine); orange buttons breathe a glow.
## Progress bars fill in, currency amounts count with a colour flash, tabs slide their
## underline, switches slide their knob. Settings > Reduce motion (motion_ok() false) turns
## the decorative motion off; press feedback stays.

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
const Shine := preload("res://src/ui/components/shine.gd")
const Spinner := preload("res://src/ui/components/spinner.gd")
const Sparkle := preload("res://src/ui/components/sparkle.gd")
const ToggleSwitch := preload("res://src/ui/components/toggle_switch.gd")
const PrintBits := preload("res://src/ui/components/print_bits.gd")
const PlateScript := preload("res://src/ui/components/plate.gd")

# ------------------------------------------------------------------ design tokens
# Style v4 "Signal" (owner, 2026-10-19: industrial glass, one signal red-orange, clean with grit
# on big moments; docs/dev/ui-style-v4.md). Graphite and smoked glass, bone-metal plates, hairlines,
# mono data type. The token names are v2's so every screen keeps compiling.

# Dark chrome (bars, glass panels over art). Text on it: INK / INK_DIM.
const BG := Color("0b0c0e")
const CHROME := Color("060708")
const PANEL := Color("14171ce0")
const PANEL_HI := Color("23272d")
const LINE := Color(1, 1, 1, 0.13)
const INK := Color("f1f0eb")
const INK_DIM := Color("8f9399")
## Text outlines and icon outlines (near-black).
const OUTLINE := Color("050506")

# Bone-metal plates (the light family). Text on it: TEXT / TEXT_DIM.
const PAPER := Color("e3e3de")
const WHITE := Color("f2f1ed")
const TEXT := Color("111214")
const TEXT_DIM := Color("5d6166")
const LINE_LIGHT := Color("c3c5bf")

# Accents.
## Signal red-orange: THE accent (primary buttons, selected chips, active tabs, meters, focus).
const ACCENT := Color("ff4b1f")
const ACCENT_HI := Color("ff8a62")
## Deep signal: pressed primary, accent text on bone.
const ACCENT_DEEP := Color("c9300d")
## The "go now" highlight (same family, hotter): the battle call to action, guide marks.
const ORANGE := Color("ff5a1a")
const ORANGE_HI := Color("ffae86")
## "N" new badges, notification dots and status lights.
const NEW_RED := Color("ff3b1f")
const RED_DOT := Color("ff3b1f")

# Signal extras.
## Status-light red (Kit.led).
const LED := Color("ff3b1f")
## Off-white bone and the brushed sage-grey metal of plates.
const BONE := Color("ecebe5")
const METAL_TOP := Color("d6d9d3")
const METAL_BOTTOM := Color("b4bab4")
## Smoked glass fill (Kit.panel glass kinds blur what is behind them; glass.gdshader).
const GLASS := Color("15181dad")

# The poster house style (docs/dev/ui-style-v4.md section 0): the paper matte, printed poster
# paper, sticker white, the dark band and the print ink (TEXT is the same ink).
const MATTE := Color("f5f4f0")
const SHEET := Color("e9e8e2")
const SHEET_WHITE := Color("f4f3ef")
const BAND := Color("141517")
## The red halftone print ink (bands, ramps).
const PRINT_RED := Color(1.0, 0.36, 0.16, 0.95)

# Semantic colors.
const GOLD := Color("f2c45a")
const GOLD_LIGHT := Color("ffe2a0")
const GOLD_DEEP := Color("a8751c")
const EMBER := Color("e8262e")
const VIOLET := Color("9a7cff")
const SKY := Color("8fb8d6")
const GOOD := Color("4fd8a0")
const RARE := Color("6aaee6")
const EPIC := Color("b07cff")
const LEGENDARY := Color("ffb02e")

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

## Font weights (style v4). Archivo is one variable font (width 62-125, weight 100-900): body and
## buttons at normal width, titles expanded and heavy, numbers and uppercase labels semi-condensed.
## JetBrains Mono carries data readouts ("mono", "mono_bold"); Instrument Serif the big editorial
## moments ("serif"). Each entry is [file, width, weight]; width 0 = a static face.
const _ARCHIVO := "res://assets/fonts/Archivo-Variable.ttf"
const _MONO := "res://assets/fonts/JetBrainsMono-Variable.ttf"
const _FONT_FILES := {
	"regular": [_ARCHIVO, 100, 460],
	"medium": [_ARCHIVO, 100, 500],
	"bold": [_ARCHIVO, 100, 600],
	"semibold": [_ARCHIVO, 100, 600],
	"extrabold": [_ARCHIVO, 104, 720],
	"black": [_ARCHIVO, 88, 760],
	"title": [_ARCHIVO, 118, 820],
	"cond_light": [_ARCHIVO, 82, 480],
	"cond": [_ARCHIVO, 84, 600],
	"cond_bold": [_ARCHIVO, 86, 700],
	"cond_black": [_ARCHIVO, 92, 820],
	"wide": [_ARCHIVO, 125, 640],
	"wide_black": [_ARCHIVO, 125, 900],
	"mono": [_MONO, 0, 450],
	"mono_bold": [_MONO, 0, 700],
	"serif": ["res://assets/fonts/InstrumentSerif-Regular.ttf", -1, 0],
	# Poster faces: Archivo at its narrowest and heaviest; the serif slanted (signatures, captions).
	"compressed": [_ARCHIVO, 62, 820],
	"compressed_light": [_ARCHIVO, 62, 500],
	"serif_italic": ["res://assets/fonts/InstrumentSerif-Regular.ttf", -2, 0],
}

static var _fonts: Dictionary = {}
static var _icons: Dictionary = {}
static var _glow_textures: Dictionary = {}
static var _grad_textures: Dictionary = {}
static var _crops: Dictionary = {}
## Hero id -> the looks (HeroArt.art_key) art_crop holds crops of, oldest first; at most
## CROP_LOOKS per hero, so trying skins and toggling nudity never piles up full-size stills.
static var _crop_looks: Dictionary = {}
const CROP_LOOKS := 2
static var _gray_material: ShaderMaterial


# ------------------------------------------------------------------ fonts & icons

## Font by weight: "regular"/"medium", "bold"/"semibold", "extrabold", "black", "title",
## "cond_light", "cond", "cond_bold", "cond_black", "wide", "wide_black" (Archivo), "mono",
## "mono_bold" (JetBrains Mono), "serif", "serif_italic" (Instrument Serif), "compressed",
## "compressed_light" (Archivo at its narrowest, for poster type).
static func font(weight: String = "bold") -> Font:
	if not _fonts.has(weight):
		var spec: Array = _FONT_FILES.get(weight, _FONT_FILES["bold"])
		var base: Font = load(spec[0])
		if int(spec[1]) == -2:
			var it := FontVariation.new()
			it.base_font = base
			it.variation_transform = Transform2D(Vector2(1.0, 0.0), Vector2(0.22, 1.0), Vector2.ZERO)
			_fonts[weight] = it
		elif int(spec[1]) < 0:
			_fonts[weight] = base
		else:
			var fv := FontVariation.new()
			fv.base_font = base
			var axes := {"wght": float(spec[2])}
			if int(spec[1]) > 0:
				axes["wdth"] = float(spec[1])
			fv.variation_opentype = axes
			_fonts[weight] = fv
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


## The skin a hero wears on cards, avatars and banners: opts.skin when given ("" = the base
## look, for enemies), else the player's equipped skin (Game.equipped_skin; "" for heroes she
## has not dressed, and without a game). HeroArt still shows adult art when nudity is on.
static func hero_look(hero_id: String, opts: Dictionary = {}) -> String:
	if opts.has("skin"):
		return str(opts["skin"])
	var g := autoload("Game")
	var st: Variant = g.get("state") if g else null
	if st is Dictionary and (st as Dictionary).has("skins") and g.has_method("equipped_skin"):
		return str(g.call("equipped_skin", hero_id))
	return ""


## Plays a UI sound through the UI autoload (no-op without it). pitch > 0 sets the playback
## pitch (rising pitches for a run of pops).
static func sfx(sound_name: String, pitch: float = -1.0) -> void:
	var ui := autoload("UI")
	if ui:
		ui.call("sfx", sound_name, pitch)


## A short vibration through the UI autoload (phones only; follows the Vibration setting).
## amplitude 0..1 (iOS/Android intensity), -1 = the device default.
static func haptic(ms: int = 10, amplitude: float = -1.0) -> void:
	var ui := autoload("UI")
	if ui:
		ui.call("haptic", ms, amplitude)


## False when the player turned on Settings > Reduce motion: decorative motion (screen slides,
## content stagger, shine sweeps, glow pulses, fill-ins) is skipped. Press feedback stays.
static func motion_ok() -> bool:
	var g := autoload("Game")
	if g == null or not g.has_method("setting"):
		return true
	return g.call("setting", "reduce_motion") != true


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
			tint = TEXT
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
	_dress_button(b, look)
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
	_dress_button(b, look)
	return b


## Idle life for a call-to-action button: the hot orange "go now" plate catches a glint now and
## then and breathes a glow. The signal plate (primary) is flat print: no gloss (style v4).
static func _dress_button(b: Button, look: String) -> void:
	if look == "orange":
		add_shine(b)
		add_glow_pulse(b, ORANGE)


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
		bx.top_color = SHEET_WHITE
		bx.bottom_color = SHEET_WHITE
	elif look == "light":
		bx.top_color = Color(TEXT, 0.08)
		bx.bottom_color = Color(TEXT, 0.08)
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
		add_press_fx(b)
		var idx := i
		b.toggled.connect(func(on: bool) -> void:
			if on:
				sfx("tab")
				haptic(10, 0.3)
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
		add_press_fx(b)
		var idx := i
		b.toggled.connect(func(on: bool) -> void:
			if on:
				sfx("tab")
				haptic(10, 0.3)
				if on_select.is_valid():
					on_select.call(idx))
		row.add_child(b)
	return row


## Tab strip (page tabs, dialog tabs): the active tab is a white plate with a cyan top bar
## and near-black text, the others are dark glass with light text. options: String or
## {text, icon}. on_select(index). Each tab is 88 px tall. The cyan bar ("Ink") slides from
## the old tab to the new one.
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
		# The active plate without its own bar: the shared Ink draws (and slides) it.
		b.add_theme_stylebox_override("pressed", UITheme.style("tab_on_flat"))
		b.add_theme_stylebox_override("hover_pressed", UITheme.style("tab_on_flat"))
		var text := str(opt.get("text", "")) if opt is Dictionary else str(opt)
		b.text = text.to_upper()
		if opt is Dictionary and opt.has("icon"):
			b.icon = icon_texture(str(opt.icon))
			b.add_theme_constant_override("icon_max_width", 34)
			b.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		var ink := ColorRect.new()
		ink.name = "Ink"
		ink.color = ACCENT
		ink.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ink.z_index = 1
		ink.anchor_right = 1.0
		ink.offset_bottom = 5
		ink.visible = i == selected
		b.add_child(ink)
		b.button_pressed = i == selected
		add_press_fx(b)
		var idx := i
		b.toggled.connect(func(on: bool) -> void:
			if on:
				_slide_ink(row, b)
				sfx("tab")
				haptic(10, 0.3)
				if on_select.is_valid():
					on_select.call(idx))
		row.add_child(b)
	return row


## Moves a tab strip's cyan bar from the tab that had it to `to` (an eased slide that also
## takes on the new tab's width).
static func _slide_ink(row: Control, to: Button) -> void:
	var ink := to.get_node_or_null("Ink") as Control
	if ink == null:
		return
	var from: Button = null
	for c in row.get_children():
		if c != to and c is Button:
			var other := (c as Button).get_node_or_null("Ink") as Control
			if other and other.visible:
				from = c as Button
				other.visible = false
	ink.visible = true
	var prev: Variant = ink.get_meta("_tw") if ink.has_meta("_tw") else null
	if prev is Tween and (prev as Tween).is_valid():
		(prev as Tween).kill()
	if from == null or not motion_ok() or not to.is_inside_tree():
		ink.offset_left = 0
		ink.offset_right = 0
		return
	var dx := from.position.x - to.position.x
	ink.offset_left = dx
	ink.offset_right = dx + from.size.x - to.size.x
	var tw := ink.create_tween().set_parallel(true)
	tw.tween_property(ink, "offset_left", 0.0, 0.32).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(ink, "offset_right", 0.0, 0.32).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	ink.set_meta("_tw", tw)


## On/off switch (settings): an animated Aero switch (ToggleSwitch, still a CheckButton).
## on_toggled(on: bool).
static func toggle(on: bool, on_toggled: Callable = Callable()) -> CheckButton:
	var c := ToggleSwitch.new()
	c.button_pressed = on
	c.custom_minimum_size = Vector2(120, BUTTON_H)
	c.toggled.connect(func(v: bool) -> void:
		sfx("toggle", 1.1 if v else 0.9)
		haptic(12, 0.4)
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


## Press feel for `button`, shown on `target` (defaults to the button): the instant a finger
## lands it squashes (small buttons a bit more than big plates) and lights up; on release it
## springs a little past full size and settles. A press that turns into a scroll (or slides
## off) restores quietly. A tap on a disabled button shakes it with the "no" sound (deny).
static func add_press_fx(button: BaseButton, target: Control = null) -> void:
	var t: Control = target if target else button
	t.pivot_offset = t.size * 0.5
	t.resized.connect(func() -> void: t.pivot_offset = t.size * 0.5)
	button.button_down.connect(func() -> void:
		button.set_meta("_down_at", button.get_global_mouse_position())
		_press_down(t))
	button.button_up.connect(func() -> void: _press_up(t, true))
	button.draw.connect(func() -> void:
		if not t.has_meta("_held"):
			return
		var mode := button.get_draw_mode()
		if mode != BaseButton.DRAW_PRESSED and mode != BaseButton.DRAW_HOVER_PRESSED:
			_press_up(t, false))
	button.gui_input.connect(func(ev: InputEvent) -> void:
		if not button.disabled:
			return
		var mb := ev as InputEventMouseButton
		if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			deny(t))


static func _press_down(t: Control) -> void:
	if not t.is_inside_tree():
		return
	t.set_meta("_held", true)
	_kill_tween(t, "_press_tween")
	var area := maxf(t.size.x * t.size.y, 1.0)
	var k := 1.0 - clampf(11.0 / sqrt(area), 0.035, 0.08)
	var tw := t.create_tween()
	tw.tween_property(t, "scale", Vector2(k, k), 0.07).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.set_meta("_press_tween", tw)
	_brighten_to(t, 1.14, 0.06)


static func _press_up(t: Control, spring: bool) -> void:
	if not t.has_meta("_held"):
		return
	t.remove_meta("_held")
	if not t.is_inside_tree():
		t.scale = Vector2.ONE
		return
	_kill_tween(t, "_press_tween")
	var tw := t.create_tween()
	if spring and motion_ok():
		var over := 1.0 + (1.0 - t.scale.x) * 0.6
		tw.tween_property(t, "scale", Vector2(over, over), 0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(t, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		tw.tween_property(t, "scale", Vector2.ONE, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.set_meta("_press_tween", tw)
	_brighten_to(t, 1.0, 0.3)


## Lights `t` up (modulate above 1) for presses, but only when nothing else tints it: a
## colour or a fade set by a screen is left alone.
static func _brighten_to(t: Control, to: float, dur: float) -> void:
	var m := t.modulate
	if absf(m.r - m.g) > 0.001 or absf(m.g - m.b) > 0.001 or m.r < 0.999 or m.r > 1.2:
		return
	_kill_tween(t, "_bright_tween")
	var tw := t.create_tween()
	tw.tween_method(func(v: float) -> void:
		if is_instance_valid(t):
			t.modulate = Color(v, v, v, t.modulate.a), m.r, to, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.set_meta("_bright_tween", tw)


static func _kill_tween(c: Object, key: String) -> void:
	if c.has_meta(key):
		var prev: Variant = c.get_meta(key)
		if prev is Tween and (prev as Tween).is_valid():
			(prev as Tween).kill()


## "Not allowed" feedback on `c`: a short shake, the deny sound and a firm buzz.
static func deny(c: Control) -> void:
	sfx("deny")
	haptic(22, 0.7)
	shake(c, 8.0)


## Connects `pressed` with the tap sound, a light haptic tick and a drag guard (a press that
## turned into a scroll gesture does not fire).
static func _connect_pressed(b: BaseButton, cb: Callable, sound: String = "tap") -> void:
	b.pressed.connect(func() -> void:
		var down: Variant = b.get_meta("_down_at") if b.has_meta("_down_at") else null
		if down is Vector2 and (down as Vector2).distance_to(b.get_global_mouse_position()) > 36.0:
			return
		if sound != "":
			sfx(sound)
		haptic(10, 0.35)
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
	if text != "" or icon_name != "":
		_dress_button(b, "primary" if variation == &"PrimaryButton" else ("orange" if variation == &"OrangeButton" else ""))
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
## opts: size (Vector2(330, 136)), color (ACCENT), hero_id, skin (hero_look: default the
## player's equipped skin, "" = base look), texture, sub_color, pages (carousel dot count,
## 0 = none), page (active dot).
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
		tex = art_crop(hid, (sz.x * 0.46) / sz.y, 1.15, hero_look(hid, opts))
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
	# Featured banners catch the light more often than buttons.
	add_shine(face, Callable(), 0.26, Vector2(3.2, 5.5), Vector2(0.5, 1.6))
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
	# The chevron nudges right now and then: "this way".
	if motion_ok():
		var nudge := func(v: float) -> void:
			ai.offset_left = -40.0 + v
			ai.offset_right = -14.0 + v
		ai.ready.connect(func() -> void:
			var tw := ai.create_tween().set_loops()
			tw.tween_interval(2.6)
			tw.tween_method(nudge, 0.0, 7.0, 0.16).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			tw.tween_method(nudge, 7.0, 0.0, 0.38).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_method(nudge, 0.0, 5.0, 0.14).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			tw.tween_method(nudge, 5.0, 0.0, 0.34).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT), CONNECT_ONE_SHOT)
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


## Rounded-square avatar (a hero's head crop, in her equipped skin) with a white rim and an
## optional small dark caption tag under it (player name). Tappable when on_pressed is valid.
## size = tile px.
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
		art.texture = art_crop(hero_id, 1.0, 1.6, hero_look(hero_id))
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


## A printed hairline rule with ticks (style v4). light = ink for paper, else paper-white.
static func divider(width: float = 0.0, light: bool = false) -> Control:
	var r := tick_rule(width, Color(TEXT, 0.4) if light else Color(1, 1, 1, 0.35))
	if width <= 0.0:
		r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return r


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
	if kind == "glass" or not variations.has(kind):
		glassify(p)
	return p


static var _glass_mat: ShaderMaterial

## Frosted glass: the control's own StyleBox fill (alpha 0.60-0.80, the glass kinds) blurs what is
## behind it (src/ui/shaders/glass.gdshader). Children are unaffected. Returns the control.
static func glassify(c: CanvasItem) -> CanvasItem:
	if _glass_mat == null:
		_glass_mat = ShaderMaterial.new()
		_glass_mat.shader = load("res://src/ui/shaders/glass.gdshader")
	c.material = _glass_mat
	return c


## A list-row card (shorthand for panel("card", pad)).
static func card(pad: int = -1) -> PanelContainer:
	return panel("card", pad)


## White info panel (the hero detail column, light page cards).
static func info_panel(pad: int = -1) -> PanelContainer:
	return panel("white", pad)


## Header band for a sheet section ("READY TO COLLECT", "FIRST CLEAR REWARDS"), style v4 print: an
## ink band across the paper with a signal tick at its start, the title in paper-white mono and a
## small barcode at the end. right = optional control at the end (replaces the barcode).
static func header_bar(text: String, right: Control = null, icon_name: String = "") -> PanelContainer:
	var p := PanelContainer.new()
	p.name = "HeaderBar"
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	p.add_theme_stylebox_override("panel", UITheme.style("header_bar"))
	p.custom_minimum_size.y = 44
	var row := hbox(12)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	if icon_name != "":
		var ic := icon(icon_name, 22, MATTE)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(ic)
	var l := label(text.to_upper(), 16, MATTE, "mono_bold")
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	if right:
		right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(right)
	else:
		var bc := SignalKit.barcode(Vector2(64, 14), Color(MATTE, 0.55), 40 + text.length())
		bc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(bc)
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


## Standard dialog, style v4 print (the poster house style): a printed sheet lying on the matte.
## At the top a mono serial line ("SHEET No.27 · HALO & HORN", after the optional glyph) and a
## printed "× CLOSE" (an 88 px target); the title set big in compressed type over a hairline rule
## with ticks (a signal lead at its start); `content` in the body; a footer strip (sheet code, date,
## barcode). Behind it all: crop marks and the title again as a faint giant word turned on its side
## and cut by the sheet edge; still grain on top. light = false prints a dark band sheet (paper-white
## type, a red halftone ramp behind the close) for content built with light text (INK). Returns
## the dialog panel; its close Button is get_meta("close_button") (UI.popup wires it), the title
## Label get_meta("title_label"). width in px.
static func dialog(title_text: String, content: Control, width: float = 640.0, light: bool = true, icon_name: String = "") -> PanelContainer:
	var ink := TEXT if light else MATTE
	var no := _sheet_no(title_text)
	var panel_c := PanelContainer.new()
	panel_c.name = "Dialog"
	panel_c.theme_type_variation = &"DialogPanel" if light else &"ModalPanel"
	panel_c.add_theme_stylebox_override("panel", UITheme.style("dialog" if light else "dialog_dark"))
	panel_c.custom_minimum_size.x = width
	# The print under everything (clipped to the sheet).
	var prints := Control.new()
	prints.name = "Print"
	prints.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prints.clip_contents = true
	panel_c.add_child(prints)
	if not light:
		var ramp := halftone_ramp(Vector2(300, 134), PRINT_RED, 7.0, "right")
		ramp.anchor_left = 1.0
		ramp.anchor_right = 1.0
		ramp.offset_left = -300
		ramp.offset_right = 0
		ramp.offset_top = 0
		ramp.offset_bottom = 134
		prints.add_child(ramp)
	var ghost := label(title_text.to_upper(), 236, Color(ink, 0.055), "compressed")
	ghost.name = "Ghost"
	ghost.rotation = PI * 0.5
	prints.add_child(ghost)
	var marks := PrintBits.CropMarks.new()
	marks.color = Color(ink, 0.4)
	marks.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	prints.add_child(marks)
	# Turned clockwise, the word's top sits at x: push it past the right edge so the sheet cuts it.
	prints.resized.connect(func() -> void: ghost.position = Vector2(prints.size.x + 116.0, 128.0))

	var col := vbox(0)
	col.name = "Sheet"
	panel_c.add_child(col)
	var head := Control.new()
	head.name = "Header"
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.custom_minimum_size = Vector2(0, 134)
	col.add_child(head)
	var sx := 28.0
	if icon_name != "":
		var ic := icon(icon_name, 22, ink)
		ic.position = Vector2(sx, 19)
		ic.size = Vector2(22, 22)
		head.add_child(ic)
		sx += 32.0
	var serial := label("SHEET No.%02d  ·  HALO & HORN" % no, 12, ink, "mono_bold")
	serial.position = Vector2(sx, 20)
	head.add_child(serial)
	var t := label(title_text.to_upper(), 76, ink, "compressed")
	t.name = "Title"
	t.position = Vector2(25, 34)
	var avail := width - 28.0 - 150.0
	fit_label(t, avail, 76, 40)
	if t.get_theme_font("font").get_string_size(t.text, HORIZONTAL_ALIGNMENT_LEFT, -1, t.get_theme_font_size("font_size")).x > avail:
		# Still too long at the smallest size: cut it with an ellipsis before the close.
		t.clip_text = true
		t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		t.size = Vector2(avail, 83)
	head.add_child(t)
	var rule := tick_rule(0.0, Color(ink, 0.55), {"lead": ACCENT})
	rule.set_anchors_preset(Control.PRESET_TOP_WIDE)
	rule.offset_left = 28
	rule.offset_right = -28
	rule.offset_top = 116
	rule.offset_bottom = 130
	head.add_child(rule)
	var close := _print_close(ink)
	close.anchor_left = 1.0
	close.anchor_right = 1.0
	close.offset_left = -150
	close.offset_right = -6
	close.offset_top = 0
	close.offset_bottom = BUTTON_H
	head.add_child(close)

	var body_m := margin(content, 28, 0)
	body_m.name = "Body"
	body_m.add_theme_constant_override("margin_top", 18)
	body_m.add_theme_constant_override("margin_bottom", 22)
	col.add_child(body_m)

	var foot := Control.new()
	foot.name = "Foot"
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	foot.custom_minimum_size = Vector2(0, 46)
	var fr := ColorRect.new()
	fr.color = Color(ink, 0.22)
	fr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fr.set_anchors_preset(Control.PRESET_TOP_WIDE)
	fr.offset_left = 28
	fr.offset_right = -28
	fr.offset_bottom = 1
	foot.add_child(fr)
	var code := label("HH-%04d  ·  %s  ·  PRINTED SHEET" % [no * 37 % 10000, _print_date()], 10, Color(ink, 0.6), "mono")
	code.position = Vector2(28, 14)
	foot.add_child(code)
	var bc := SignalKit.barcode(Vector2(112, 16), Color(ink, 0.7), no)
	bc.anchor_left = 1.0
	bc.anchor_right = 1.0
	bc.offset_left = -140
	bc.offset_right = -28
	bc.offset_top = 15
	bc.offset_bottom = 31
	foot.add_child(bc)
	col.add_child(foot)
	panel_c.add_child(SignalKit.grain(0.045, true))
	panel_c.set_meta("close_button", close)
	panel_c.set_meta("title_label", t)
	return panel_c


## A stable two-digit sheet number for a title (SHEET No.27).
static func _sheet_no(s: String) -> int:
	return 10 + absi(hash(s)) % 89


## Today as printed on sheets: "2026.10.19".
static func _print_date() -> String:
	var d := Time.get_date_dict_from_system()
	return "%d.%02d.%02d" % [int(d.year), int(d.month), int(d.day)]


## The printed "× CLOSE" at a sheet's top-right corner (a bare Button, 150 x 88 target; the
## label dims while held). Its pressed signal is wired by the caller (UI.popup).
static func _print_close(ink: Color) -> Button:
	var b := Button.new()
	b.name = "Close"
	b.theme_type_variation = &"BareButton"
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	b.custom_minimum_size = Vector2(144, BUTTON_H)
	var txt := "×  CLOSE"
	var l := label(txt, 14, ink, "mono_bold")
	l.name = "Text"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.anchor_left = 0.0
	l.anchor_right = 1.0
	l.offset_right = -22
	l.offset_top = 12
	l.offset_bottom = 40
	b.add_child(l)
	var tw := font("mono_bold").get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	var u := ColorRect.new()
	u.color = Color(ink, 0.8)
	u.mouse_filter = Control.MOUSE_FILTER_IGNORE
	u.anchor_left = 1.0
	u.anchor_right = 1.0
	u.offset_left = -22 - tw
	u.offset_right = -22
	u.offset_top = 39
	u.offset_bottom = 40
	b.add_child(u)
	b.button_down.connect(func() -> void: b.modulate.a = 0.5)
	b.button_up.connect(func() -> void: b.modulate.a = 1.0)
	return b


# ------------------------------------------------------------------ print (v4 poster sheets)

## Mono micro type (labels, serials, dates), uppercase. weight "mono" | "mono_bold".
static func print_label(text: String, size: int = 12, color: Color = TEXT, weight: String = "mono_bold") -> Label:
	return label(text.to_upper(), size, color, weight)


## A printed hairline with ticks (14 px tall; the rule runs through the middle). width 0 = set
## by the layout. opts: step (12), major (5), tick (4), lead (a signal bar over the start; Color),
## filled (0..1: a meter, the ticks up to there tall and in signal; set later with set_filled).
static func tick_rule(width: float, color: Color = Color(0.067, 0.071, 0.078, 0.55), opts: Dictionary = {}) -> Control:
	var r := PrintBits.TickRule.new()
	r.color = color
	r.step = float(opts.get("step", 12.0))
	r.major = int(opts.get("major", 5))
	r.tick = float(opts.get("tick", 4.0))
	if opts.has("lead"):
		r.lead = opts["lead"]
	if opts.has("filled"):
		r.filled = float(opts["filled"])
	if opts.has("fill_color"):
		r.fill_color = opts["fill_color"]
	r.custom_minimum_size = Vector2(width, 14)
	r.size = r.custom_minimum_size
	return r


## A halftone ramp: printed dots growing toward `toward` ("right" | "left" | "down" | "up") in
## `ink` (the red print by default). A TextureRect of `sz`; place or anchor it.
static func halftone_ramp(sz: Vector2, ink: Color = PRINT_RED, cell: float = 7.0, toward: String = "right") -> TextureRect:
	var g := Gradient.new()
	g.set_color(0, Color.BLACK)
	g.set_color(1, Color.WHITE)
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 64
	gt.height = 64
	match toward:
		"left":
			gt.fill_from = Vector2(1, 0.5)
			gt.fill_to = Vector2(0, 0.5)
		"down":
			gt.fill_from = Vector2(0.5, 0)
			gt.fill_to = Vector2(0.5, 1)
		"up":
			gt.fill_from = Vector2(0.5, 1)
			gt.fill_to = Vector2(0.5, 0)
		_:
			gt.fill_from = Vector2(0, 0.5)
			gt.fill_to = Vector2(1, 0.5)
	var t := TextureRect.new()
	t.texture = gt
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.custom_minimum_size = sz
	t.size = sz
	t.material = SignalKit.halftone_material(cell, ink, true)
	return t


## A printed fill dial (the Sanctum's gauge): a ring of 60 ticks with the filled ones in signal and
## a signal arc, the value in compressed type in the middle (meta "value_label"), a mono caption
## above it ("caption_label") and a mono line under it ("sub_label"). Update with set_dial.
static func fill_dial(sz: float, caption_text: String = "FILL", sub_text: String = "") -> Control:
	var d := PrintBits.Dial.new()
	d.custom_minimum_size = Vector2(sz, sz)
	d.size = d.custom_minimum_size
	var v := label("0%", int(sz * 0.27), TEXT, "compressed")
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_top = -sz * 0.03
	v.offset_bottom = -sz * 0.03
	d.add_child(v)
	var cap := label(caption_text.to_upper(), 11, Color(TEXT, 0.65), "mono_bold")
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.set_anchors_preset(Control.PRESET_TOP_WIDE)
	cap.offset_top = sz * 0.27
	cap.offset_bottom = sz * 0.27 + 16
	d.add_child(cap)
	var sub := label(sub_text.to_upper(), 11, Color(TEXT, 0.65), "mono_bold")
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.set_anchors_preset(Control.PRESET_TOP_WIDE)
	sub.offset_top = sz * 0.64
	sub.offset_bottom = sz * 0.64 + 16
	d.add_child(sub)
	d.set_meta("value_label", v)
	d.set_meta("caption_label", cap)
	d.set_meta("sub_label", sub)
	return d


## Sets a fill_dial's fill (0..1) and, when given, its value and under-line text.
static func set_dial(d: Control, frac: float, value_text: String = "", sub_text: String = "") -> void:
	if d == null or not is_instance_valid(d):
		return
	if d.has_method("set_frac"):
		d.call("set_frac", frac)
	if value_text != "" and d.has_meta("value_label"):
		(d.get_meta("value_label") as Label).text = value_text
	if sub_text != "" and d.has_meta("sub_label"):
		(d.get_meta("sub_label") as Label).text = sub_text.to_upper()


## The compact pass (the poster's OG-pass call to action, 124 px tall) as one Button, for a sheet's
## main action: a brushed silver plate (an etched kicker and title, a knob with the icon) over a
## glowing signal plate (an outlined action pill and a mono info line). spec: width (540), kicker,
## title, action ("COLLECT  >>>"), info, icon, disabled (graphite plate, dim print), text (the
## Button's own words, drawn invisible, for tests and screen readers). The info Label is
## get_meta("info_label"). Press: both plates sink, the tap sound plays, then on_pressed.
static func sheet_pass(spec: Dictionary, on_pressed: Callable = Callable()) -> Button:
	var w: float = spec.get("width", 540.0)
	var off := bool(spec.get("disabled", false))
	var b := Button.new()
	b.theme_type_variation = &"BareButton"
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	b.custom_minimum_size = Vector2(w, 124)
	b.size = b.custom_minimum_size
	if spec.has("text"):
		b.text = str(spec["text"])
		for k: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color", "font_hover_pressed_color"]:
			b.add_theme_color_override(k, Color(0, 0, 0, 0))
	var sig := SignalKit.plate("graphite" if off else "signal", Vector2(6, 56), Vector2(w - 10, 66), {"cuts": [0, 10, 14, 0],
		"glow": 0.0 if off else 0.35, "glow_radius": 12.0, "pulse": 0.0 if off else 0.4, "topo": 0.5}, b)
	var top_sz := Vector2(w, 66)
	var silver := SignalKit.plate("silver", Vector2.ZERO, top_sz, {"shape": PlateScript.tab_bottom(top_sz, 12, w * 0.36, w * 0.66, 12),
		"topo": 0.5, "screws": [Vector2(11, 11), Vector2(w - 11, 11)]}, b)
	silver.z_index = 1
	var kick := SignalKit.etch(str(spec.get("kicker", "")), 10, "mono_bold")
	kick.position = Vector2(26, 8)
	silver.add_child(kick)
	var title_txt := str(spec.get("title", ""))
	var ts := 24
	var avail := w - 26.0 - (78.0 if spec.has("icon") else 24.0)
	var tf := font("wide_black")
	while ts > 14 and tf.get_string_size(title_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, ts).x > avail:
		ts -= 1
	var title := SignalKit.etch(title_txt, ts, "wide_black")
	title.position = Vector2(24, 21 + (24 - ts) * 0.5)
	silver.add_child(title)
	if spec.has("icon"):
		var knob := SignalKit.plate("dial", Vector2(w - 62, 7), Vector2(42, 42), {"circle": true, "shadow": 0.5}, silver)
		var ic := icon(str(spec["icon"]), 20, Color(1, 1, 1, 0.95))
		ic.position = Vector2(11, 11)
		ic.size = Vector2(20, 20)
		knob.add_child(ic)
	var act := SignalKit.pill(str(spec.get("action", "COLLECT  >>>")), 18, Color(1, 1, 1, 0.45) if off else Color.WHITE)
	act.position = Vector2(16, 20)
	sig.add_child(act)
	var info := label(str(spec.get("info", "")), 10, Color(1, 1, 1, 0.5 if off else 0.92), "mono")
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	info.position = Vector2(maxf(w * 0.56, 40.0 + act.get_combined_minimum_size().x), 18)
	info.size = Vector2(w - 26.0 - info.position.x, 40)
	sig.add_child(info)
	b.set_meta("info_label", info)
	b.disabled = off
	b.button_down.connect(func() -> void:
		b.set_meta("_down_at", b.get_global_mouse_position())
		silver.call("set_pressed_look", true)
		sig.call("set_pressed_look", true)
		haptic(12))
	b.button_up.connect(func() -> void:
		silver.call("set_pressed_look", false)
		sig.call("set_pressed_look", false))
	b.gui_input.connect(func(ev: InputEvent) -> void:
		if not b.disabled:
			return
		var mb := ev as InputEventMouseButton
		if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			deny(b))
	if on_pressed.is_valid():
		_connect_pressed(b, on_pressed)
	return b


## Rewards as a printed receipt (UI.show_reward, the Sanctum sheet): one row per entry in
## reward_entries order: a small icon (a framed portrait for heroes and shards), the name in mono, a
## dotted leader and the amount in compressed type. opts: compact (smaller rows), ink (type
## colour), rules (a hairline under each row, default true). Returns a VBox; meta "icons" holds
## each row's icon in entry order and "rows" the rows (UI.show_reward animates them and flies the
## currencies from the icons).
static func reward_receipt(reward: Dictionary, width: float, opts: Dictionary = {}) -> VBoxContainer:
	var compact := bool(opts.get("compact", false))
	var ink: Color = opts.get("ink", TEXT)
	var rules := bool(opts.get("rules", true))
	var rh := 40.0 if compact else 50.0
	var v := vbox(0)
	v.name = "Receipt"
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.custom_minimum_size.x = width
	var icons: Array[Control] = []
	var rows: Array[Control] = []
	var name_size := 15 if compact else 17
	var nf := font("mono_bold")
	for e: Dictionary in reward_entries(reward):
		var row := hbox(12)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.custom_minimum_size = Vector2(width, rh)
		var ic := _receipt_icon(e, rh - 14.0, ink)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(ic)
		icons.append(ic)
		var nm_text := _receipt_name(e)
		var nm := label(nm_text, name_size, ink, "mono_bold")
		nm.clip_text = true
		nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		nm.custom_minimum_size.x = minf(nf.get_string_size(nm_text, HORIZONTAL_ALIGNMENT_LEFT, -1, name_size).x + 2.0, width * 0.56)
		row.add_child(nm)
		var lead := PrintBits.Leader.new()
		lead.color = Color(ink, 0.4)
		lead.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lead)
		var amt := label(_receipt_amount(e), 30 if compact else 38, ink, "compressed")
		amt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(amt)
		v.add_child(row)
		rows.append(row)
		if rules:
			var hr := ColorRect.new()
			hr.color = Color(ink, 0.14)
			hr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			hr.custom_minimum_size = Vector2(width, 1)
			v.add_child(hr)
	v.set_meta("icons", icons)
	v.set_meta("rows", rows)
	return v


static func _receipt_icon(e: Dictionary, s: float, ink: Color) -> Control:
	var kind := str(e.get("kind", ""))
	var id := str(e.get("id", ""))
	match kind:
		"currency":
			return icon(id, s)
		"hero", "shard":
			var fr := Panel.new()
			fr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			fr.custom_minimum_size = Vector2(s, s)
			fr.clip_contents = true
			var sb := StyleBoxFlat.new()
			sb.bg_color = SHEET
			sb.border_color = Color(ink, 0.7)
			sb.set_border_width_all(1)
			fr.add_theme_stylebox_override("panel", sb)
			var art := TextureRect.new()
			art.texture = art_crop(id, 1.0, 1.7, hero_look(id))
			art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			art.mouse_filter = Control.MOUSE_FILTER_IGNORE
			art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			art.offset_left = 1
			art.offset_top = 1
			art.offset_right = -1
			art.offset_bottom = -1
			fr.add_child(art)
			return fr
		"gear":
			return icon("gear_" + str(_gear_item(id).get("slot", "weapon")), s, ink)
		"gear_drop":
			var slot := id.split(":")[0] if id.contains(":") else ""
			return icon("gear_" + (slot if slot != "" else "weapon"), s, ink)
	return icon("chest", s, ink)


static func _receipt_name(e: Dictionary) -> String:
	var kind := str(e.get("kind", ""))
	var id := str(e.get("id", ""))
	match kind:
		"currency":
			return str(CURRENCY_SHORT.get(id, id.capitalize())).to_upper()
		"hero":
			return "%s  ·  NEW HERO" % str(_def(id).get("name", id)).to_upper()
		"shard":
			return "%s SHARDS" % str(_def(id).get("name", id)).to_upper()
		"gear":
			var item := _gear_item(id)
			var slot := str(item.get("slot", "weapon"))
			return "%s  ·  T%s" % [str(item.get("name", GEAR_SLOT_NAMES.get(slot, "Gear"))).to_upper(), roman(int(item.get("tier", 1)))]
		"gear_drop":
			var parts := id.split(":")
			var slot := parts[0] if parts.size() > 0 else ""
			var tier := int(parts[1]) if parts.size() > 1 else 0
			var nm := str(GEAR_SLOT_NAMES.get(slot, "Gear")).to_upper() if slot != "" else "GEAR"
			return nm + ("  ·  T%s" % roman(tier) if tier > 0 else "")
	return id.to_upper()


static func _receipt_amount(e: Dictionary) -> String:
	if str(e.get("kind", "")) == "currency":
		return "+" + format_full(int(e.get("amount", 0)))
	return "x%d" % int(e.get("amount", 1))


## The full-screen loading veil (UI.busy, main.gd show_veil): a dark printed band over everything
## with a red halftone ramp rising from the foot, a mono stand-by line, the caption set big in
## compressed paper-white type (the Label named "Caption") and a printed rule whose signal run
## slides back and forth; still grain on top. It blocks taps (MOUSE_FILTER_STOP).
static func loading_veil() -> Control:
	var v := Control.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(BAND, 0.96)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.add_child(shade)
	var ramp := halftone_ramp(Vector2(720, 560), Color(1.0, 0.36, 0.16, 0.8), 8.0, "down")
	ramp.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	ramp.offset_top = -560
	ramp.offset_bottom = 0
	ramp.offset_left = 0
	ramp.offset_right = 0
	v.add_child(ramp)
	var col := vbox(18)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var kick := label("STAND BY  ·  SHEET No.%02d  ·  %s" % [_sheet_no("veil"), _print_date()], 13, Color(MATTE, 0.7), "mono_bold")
	kick.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(kick)
	var l := label("", 96, MATTE, "compressed")
	l.name = "Caption"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 640
	l.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	l.add_theme_constant_override("line_spacing", -18)
	col.add_child(l)
	var sw := PrintBits.Sweep.new()
	sw.custom_minimum_size = Vector2(440, 22)
	sw.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(sw)
	var foot := label("HALO & HORN  ·  ©2026 HH", 11, Color(MATTE, 0.5), "mono")
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(foot)
	v.add_child(col)
	v.add_child(SignalKit.grain(0.06, true))
	return v


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
	if light:
		# Style v4 print: an ink-ruled track on the paper, a flat printed fill.
		var pbg := StyleBoxFlat.new()
		pbg.bg_color = Color(TEXT, 0.06)
		pbg.border_color = Color(TEXT, 0.5)
		pbg.set_border_width_all(1)
		bar.add_theme_stylebox_override("background", pbg)
		var pfg := StyleBoxFlat.new()
		pfg.bg_color = color
		bar.add_theme_stylebox_override("fill", pfg)
	else:
		var bg := KitBox.new()
		bg.radius = r
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
	var l := label(text, int(clampf(height * 0.8, 16, 26)), TEXT if light else Color.WHITE, "mono_bold" if light else "cond_bold", 0 if light else 3)
	l.name = "Text"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	l.visible = text != ""
	bar.add_child(l)
	# Fill in from empty when it first appears (and when its first value arrives right after).
	bar.set_meta("_born", Time.get_ticks_msec())
	bar.tree_entered.connect(func() -> void: _fill_in(bar), CONNECT_ONE_SHOT)
	return bar


static func _fill_in(bar: ProgressBar) -> void:
	var target := bar.value
	if target <= bar.min_value or not motion_ok():
		return
	bar.value = bar.min_value
	_tween_bar(bar, target, 0.75, 0.1)


static func _tween_bar(bar: ProgressBar, target: float, dur: float, delay: float = 0.0) -> void:
	_kill_tween(bar, "_fill_tw")
	var tw := bar.create_tween()
	tw.tween_property(bar, "value", target, dur).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	bar.set_meta("_fill_tw", tw)


## Updates a Kit progress bar (animated by default; a bar that just appeared fills in even
## when animate is off). max_value < 0 keeps the old max.
static func set_progress(bar: ProgressBar, value: float, max_value: float = -1.0, text: String = "", animate: bool = true) -> void:
	if max_value >= 0.0:
		bar.max_value = maxf(max_value, 0.0001)
	var target := clampf(value, 0.0, bar.max_value)
	var young := Time.get_ticks_msec() - int(bar.get_meta("_born", -100000)) < 450
	if bar.is_inside_tree() and (animate or (young and motion_ok())):
		_tween_bar(bar, target, 0.35 if animate and not young else 0.75)
	else:
		_kill_tween(bar, "_fill_tw")
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
		var counting: Variant = l.get_meta("_count_tw") if l.has_meta("_count_tw") else null
		if not (counting is Tween and (counting as Tween).is_running()):
			l.text = format_num(amount)
		return
	if animate and chip.is_inside_tree():
		count_to(l, old, amount, 0.7)
		pulse(chip, 1.07)
		var gain := amount > old
		_flash(l, Color("a8f7ff") if gain else Color("ffb27a"))
		if gain and chip.is_visible_in_tree() and motion_ok():
			float_text(chip, "+" + format_num(amount - old), Color("8dffc8"))
	else:
		l.text = format_num(amount)


## Tints a label (its modulate) with `col` and eases it back to white: number changes.
static func _flash(l: CanvasItem, col: Color, dur: float = 0.8) -> void:
	_kill_tween(l, "_flash_tw")
	l.modulate = col
	var tw := l.create_tween()
	tw.tween_property(l, "modulate", Color.WHITE, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	l.set_meta("_flash_tw", tw)


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
			_corner(face, _amount_tag("x%s" % format_num(amount), tile), Vector2(1, 1), Vector2(-4, -4))
			name_text = str(_def(id).get("name", id))
		"gear":
			var item := _gear_item(id)
			var slot := str(item.get("slot", "weapon"))
			var tier := int(item.get("tier", 1))
			face = _tile_box(tile, tier_color(tier))
			var gi := icon("gear_" + slot, tile * 0.54, TEXT)
			_center_child(face, gi, gi.custom_minimum_size)
			_corner(face, _amount_tag(roman(tier), tile, false), Vector2(0, 0), Vector2(4, 4))
			name_text = str(item.get("name", GEAR_SLOT_NAMES.get(slot, "Gear")))
		"gear_drop":
			var parts := id.split(":")
			var slot := parts[0] if parts.size() > 0 else ""
			var tier := int(parts[1]) if parts.size() > 1 else 0
			var accent := tier_color(tier) if tier > 0 else SKY
			face = _tile_box(tile, accent)
			var gi := icon("gear_" + (slot if slot != "" else "weapon"), tile * 0.54, TEXT)
			_center_child(face, gi, gi.custom_minimum_size)
			if tier > 0:
				_corner(face, _amount_tag(roman(tier), tile, false), Vector2(0, 0), Vector2(4, 4))
			if amount > 1 or slot == "":
				_corner(face, _amount_tag("x%d" % amount, tile), Vector2(1, 1), Vector2(-4, -8))
			name_text = str(GEAR_SLOT_NAMES.get(slot, "Gear")) if slot != "" else "Gear"
		_:
			var accent := {"gold": GOLD, "gems": ACCENT, "scrolls": VIOLET, "hero_exp": GOOD, "dust": EPIC}
			face = _tile_box(tile, accent.get(id, GOLD))
			var ci := icon(id, tile * 0.58)
			_center_child(face, ci, ci.custom_minimum_size)
			_corner(face, _amount_tag(format_num(amount), tile), Vector2(1, 1), Vector2(-4, -8))
			name_text = str(CURRENCY_SHORT.get(id, id.capitalize()))
	col.add_child(face)
	if show_name:
		var n := label(name_text.to_upper(), 13, TEXT_DIM if light else INK_DIM, "mono_bold")
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		n.custom_minimum_size.x = tile
		n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		n.clip_text = true
		col.add_child(n)
	col.custom_minimum_size.x = tile
	return col


## An item tile, style v4 print (rewards, gear): sticker paper ruled in ink with crop marks inside
## and a coloured base strip (tier / currency colour).
static func _tile_box(tile: float, accent: Color) -> Control:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(tile, tile)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var b := StyleBoxFlat.new()
	b.bg_color = SHEET_WHITE
	b.border_color = Color(TEXT, 0.45)
	b.set_border_width_all(1)
	b.shadow_color = Color(0, 0, 0, 0.18)
	b.shadow_size = 4
	b.shadow_offset = Vector2(0, 2)
	p.add_theme_stylebox_override("panel", b)
	var marks := PrintBits.CropMarks.new()
	marks.color = Color(TEXT, 0.3)
	marks.arm = maxf(5.0, tile * 0.07)
	marks.inset = maxf(4.0, tile * 0.05)
	marks.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	p.add_child(marks)
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


## A small printed tag for a tile corner: an amount (ink block, paper mono type) or, solid = false,
## a tier numeral (ink outline on the sticker).
static func _amount_tag(text: String, tile: float, solid: bool = true) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = TEXT if solid else Color(SHEET_WHITE, 0.9)
	sb.border_color = TEXT
	sb.set_border_width_all(0 if solid else 1)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 0
	sb.content_margin_bottom = 1
	p.add_theme_stylebox_override("panel", sb)
	p.add_child(label(text, int(clampf(tile * 0.16, 12.0, 20.0)), MATTE if solid else TEXT, "mono_bold"))
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
##   skin: String             the look (default: the player's equipped skin, hero_look;
##                            "" = base look, for enemies)
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
	# A filled slot shows the piece's own render (tools/blender/gear_objects.py), else the slot glyph.
	var noun := str(item.get("name", "")).get_slice(" ", str(item.get("name", "")).get_slice_count(" ") - 1).to_lower()
	var art_path := "res://assets/art/ui/gear/%s_%d.png" % [noun, clampi(tier, 1, 5)]
	if not empty and noun != "" and ResourceLoader.exists(art_path):
		var tr := TextureRect.new()
		tr.texture = load(art_path) as Texture2D
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tr.offset_left = size * 0.08
		tr.offset_top = size * 0.08
		tr.offset_right = -size * 0.08
		tr.offset_bottom = -size * 0.08
		face.add_child(tr)
	else:
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

## Section title, style v4 print: the uppercase title in compressed type, then a hairline with
## ticks to the right edge. light = ink type and rule for paper (else paper-white on dark).
static func section_header(text: String, size: int = 30, color: Color = INK, light: bool = false) -> HBoxContainer:
	var row := hbox(14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.custom_minimum_size.y = size + 14
	var tc := TEXT if light and color == INK else color
	var t := label(text.to_upper(), int(size * 1.2), tc, "compressed")
	row.add_child(t)
	var r := tick_rule(40.0, Color(tc, 0.5))
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
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


## Empty-list message, style v4 print: an optional faint glyph, the line in the slanted serif and a
## mono "NOTHING ON FILE" under it. light = for paper (ink), else paper-white on dark.
static func empty_state(text: String, icon_name: String = "", light: bool = false) -> VBoxContainer:
	var v := vbox(8)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ink := TEXT if light else INK
	if icon_name != "":
		var ic := icon(icon_name, 64, Color(ink, 0.25))
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(ic)
	var l := label(text, 30, Color(ink, 0.72), "serif_italic")
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.custom_minimum_size.x = 40
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	var tag := label("—  NOTHING ON FILE  —", 11, Color(ink, 0.5), "mono_bold")
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(tag)
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
## placeholder silhouettes (uses HeroArt.portrait_region). skin_id: the look ("" = base; pass
## hero_look(id) for the player's heroes). Cached AtlasTexture, keyed by what the art shows
## (HeroArt.art_key), so equipping a skin or toggling nudity gives the new crop.
static func art_crop(hero_id: String, aspect: float, zoom: float = 1.0, skin_id: String = "") -> Texture2D:
	var look := HeroArt.art_key(hero_id, skin_id)
	var key := "%s:%.3f:%.2f" % [look, aspect, zoom]
	_remember_look(hero_id, look)
	if _crops.has(key):
		return _crops[key]
	var tex := HeroArt.texture(hero_id, skin_id)
	if tex == null:
		return null
	var pr := HeroArt.portrait_region(hero_id, skin_id)
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


## Drops the crops of a hero's oldest look once she has more than CROP_LOOKS (a full still is
## ~11 MB of video memory; a card still on screen keeps its own crop alive).
static func _remember_look(hero_id: String, look: String) -> void:
	var looks: Array = _crop_looks.get(hero_id, [])
	looks.erase(look)
	looks.append(look)
	while looks.size() > CROP_LOOKS:
		var old := str(looks.pop_front()) + ":"
		for k: Variant in _crops.keys():
			if str(k).begins_with(old):
				_crops.erase(k)
	_crop_looks[hero_id] = looks


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


## Quick scale bump (feedback on value changes). A new pulse replaces a running one.
static func pulse(c: Control, amount: float = 1.12) -> void:
	if not c.is_inside_tree():
		return
	_kill_tween(c, "_pulse_tw")
	c.pivot_offset = c.size * 0.5
	var tw := c.create_tween()
	tw.tween_property(c, "scale", Vector2(amount, amount), 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "scale", Vector2.ONE, 0.26).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	c.set_meta("_pulse_tw", tw)


## Horizontal shake (errors, can't afford). Safe in containers (it never leaves the control
## off its laid-out place).
static func shake(c: Control, strength: float = 10.0) -> void:
	if not c.is_inside_tree():
		return
	_kill_tween(c, "_shake_tw")
	if c.has_meta("_shake_done"):
		(c.get_meta("_shake_done") as Callable).call()
	var drv := _offset_driver(c)
	var apply: Callable = drv[0]
	var done: Callable = drv[1]
	c.set_meta("_shake_done", done)
	var tw := c.create_tween()
	var x := 0.0
	for i in 5:
		var to := (strength if i % 2 == 0 else -strength) * (1.0 - i * 0.18)
		tw.tween_method(func(v: float) -> void: apply.call(Vector2(v, 0)), x, to, 0.035 if i == 0 else 0.05)
		x = to
	tw.tween_method(func(v: float) -> void: apply.call(Vector2(v, 0)), x, 0.0, 0.05)
	tw.tween_callback(func() -> void:
		done.call()
		if is_instance_valid(c):
			c.remove_meta("_shake_done"))
	c.set_meta("_shake_tw", tw)


## Animates a Label's number from `from` to `to` (compact formatted). A new count replaces a
## running one.
static func count_to(l: Label, from: int, to: int, dur: float = 0.5, full: bool = false) -> void:
	if not l.is_inside_tree():
		l.text = format_full(to) if full else format_num(to)
		return
	_kill_tween(l, "_count_tw")
	var tw := l.create_tween()
	tw.tween_method(func(v: float) -> void:
		l.text = format_full(int(v)) if full else format_num(int(v)), float(from), float(to), dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	l.set_meta("_count_tw", tw)


## Moves `c` by an offset that survives its container re-laying it out: returns
## [apply(offset: Vector2), finish()]. finish() removes the offset and stops listening.
static func _offset_driver(c: Control) -> Array:
	# Weak references only: these callables can outlive `c` and its parent.
	var ref: WeakRef = weakref(c)
	var st := {"off": Vector2.ZERO, "want": Vector2.ZERO, "live": true}
	var apply := func(v: Vector2) -> void:
		var n := ref.get_ref() as Control
		if n == null or not st.live:
			return
		st.want = v
		var d: Vector2 = v - (st.off as Vector2)
		if d != Vector2.ZERO:
			n.position += d
		st.off = v
	var parent := c.get_parent() as Container
	var pref: WeakRef = weakref(parent)
	var resort := func() -> void:
		# The container just put `c` back in its slot (without our offset): re-apply it.
		st.off = Vector2.ZERO
		apply.call(st.want)
	if parent:
		parent.sort_children.connect(resort)
	var unhook := func() -> void:
		st.live = false
		var p := pref.get_ref() as Container if pref else null
		if p and p.sort_children.is_connected(resort):
			p.sort_children.disconnect(resort)
	var finish := func() -> void:
		apply.call(Vector2.ZERO)
		unhook.call()
	# Leaving the tree (freed, or turned into a transition ghost) ends it where it is.
	c.tree_exiting.connect(unhook, CONNECT_ONE_SHOT)
	return [apply, finish]


## Brings `c` in from `from` px away (and fades it in from transparent to its own alpha)
## after `delay` s: screen content, list rows, lobby plates. Works for children of
## containers too. No-op with Reduce motion.
static func offset_in(c: Control, from: Vector2, delay: float = 0.0, dur: float = 0.34, fade: bool = true) -> void:
	if not c.is_inside_tree() or not motion_ok():
		return
	var a0 := c.modulate.a
	if fade:
		c.modulate.a = 0.0
	var drv := _offset_driver(c)
	var apply: Callable = drv[0]
	apply.call(from)
	var tw := c.create_tween().set_parallel(true)
	tw.tween_method(apply, from, Vector2.ZERO, dur).set_delay(delay).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	if fade:
		tw.tween_property(c, "modulate:a", a0, dur * 0.65).set_delay(delay).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.chain().tween_callback(drv[1])


## Staggered entrance for a freshly built screen (UI.go does this): the header blocks, then
## the rows of its scrolling list (the first few), each rising in a little after the one
## before. Backgrounds stay put. No-op with Reduce motion.
static func stagger_in(root: Control, delay: float = 0.0, step: float = 0.035, max_items: int = 12, rise: float = 26.0) -> void:
	if not motion_ok():
		return
	var items: Array[Control] = []
	_stagger_collect(root, items, 0)
	var i := 0
	for c in items:
		if i >= max_items:
			break
		offset_in(c, Vector2(0, rise), delay + minf(i * step, 0.3), 0.36)
		i += 1


static func _stagger_collect(n: Node, items: Array[Control], depth: int) -> void:
	for ch in n.get_children():
		var c := ch as Control
		if c == null or not c.visible or c.top_level or _is_backdrop(c):
			continue
		if c is ScrollContainer:
			var list := _list_in(c, 0)
			if list == null:
				items.append(c)
				continue
			var k := 0
			for r in list.get_children():
				var rc := r as Control
				if rc and rc.visible and not rc.top_level:
					items.append(rc)
					k += 1
					if k >= 8:
						break
		elif depth < 2 and c is VBoxContainer and _wraps_scroll(c):
			_stagger_collect(c, items, depth + 1)
		else:
			items.append(c)


## The list container inside a scroll (through margins / single-child wrappers), or null.
static func _list_in(n: Node, depth: int) -> Container:
	if depth > 5:
		return null
	if n is ScrollContainer or n is MarginContainer or n is CenterContainer or (n is PanelContainer and n.get_child_count() == 1):
		for c in n.get_children():
			if c is Control and (c as Control).visible:
				return _list_in(c, depth + 1)
		return null
	if n is BoxContainer or n is GridContainer or n is FlowContainer:
		var vis := 0
		for c in n.get_children():
			if c is Control and (c as Control).visible:
				vis += 1
		return n as Container if vis >= 2 else null
	return null


static func _wraps_scroll(c: Control) -> bool:
	for ch in c.get_children():
		if ch is ScrollContainer:
			return true
	return false


static func _is_backdrop(c: Control) -> bool:
	if c is TextureRect or c is ColorRect:
		return true
	var s: Variant = c.get_script()
	if s is Script and (s as Script).resource_path.contains("backdrop"):
		return true
	var n := String(c.name)
	for key: String in ["Bg", "Backdrop", "Background", "Shade", "Veil", "Stripes"]:
		if n.contains(key):
			return true
	return c.mouse_filter == Control.MOUSE_FILTER_IGNORE and c.get_child_count() == 0


## A number or word that floats up from `anchor` and fades ("+1,500" over a currency).
static func float_text(anchor: Control, text: String, color: Color = GOOD, size: int = 24) -> void:
	if not anchor.is_inside_tree():
		return
	var l := label(text, size, color, "cond_bold", 4)
	l.top_level = true
	l.z_index = 20
	anchor.add_child(l)
	var ms := l.get_combined_minimum_size()
	l.size = ms
	var p := anchor.global_position + Vector2(anchor.size.x * 0.5 - ms.x * 0.5, anchor.size.y * 0.5)
	l.position = p
	l.pivot_offset = ms * 0.5
	l.scale = Vector2(0.6, 0.6)
	var tw := l.create_tween().set_parallel(true)
	tw.tween_property(l, "position:y", p.y - 40.0, 0.85).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.4).set_delay(0.5)
	tw.chain().tween_callback(l.queue_free)


## A burst of glints at `at` (local to `parent`, which must not be a Container).
static func sparkle(parent: Control, at: Vector2, color: Color = Color.WHITE, count: int = 7, radius: float = 64.0) -> void:
	if not parent.is_inside_tree() or not motion_ok():
		return
	var s := Sparkle.new()
	s.color = color
	s.count = count
	s.radius = radius
	s.star = clampf(radius * 0.2, 7.0, 16.0)
	s.position = at
	s.z_index = 5
	parent.add_child(s)


## Loading spinner (an aqua arc turning around a faint ring), `size` px square.
static func spinner(size: float = 64.0, color: Color = ACCENT_HI) -> Control:
	var s := Spinner.new()
	s.color = color
	s.custom_minimum_size = Vector2(size, size)
	s.size = Vector2(size, size)
	return s


## A light sweep across `c` now and then (Shine). shape: () -> outline in c's local
## coordinates (default: c's KitBox stylebox). every / first: seconds between sweeps and
## before the first. Returns the Shine node (sweep_now() plays one at once).
static func add_shine(c: Control, shape: Callable = Callable(), strength: float = 0.32, every: Vector2 = Vector2(4.5, 8.5), first: Vector2 = Vector2(0.8, 3.5)) -> Control:
	var s := Shine.new()
	s.name = "Shine"
	s.shape = shape
	s.strength = strength
	s.every = every
	s.first = first
	c.add_child(s)
	return s


## A soft glow behind `c` (drawn behind it) that breathes: the main call to action.
static func add_glow_pulse(c: Control, color: Color = ORANGE, size: int = 16, radius: int = 16) -> Control:
	var g := Panel.new()
	g.name = "GlowPulse"
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.show_behind_parent = true
	g.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var sb := StyleBoxFlat.new()
	sb.draw_center = false
	sb.bg_color = Color(color, 0.0)
	sb.shadow_color = Color(color, 0.5)
	sb.shadow_size = size
	sb.set_corner_radius_all(radius)
	sb.anti_aliasing = true
	g.add_theme_stylebox_override("panel", sb)
	c.add_child(g)
	if motion_ok():
		g.modulate.a = 0.3
		g.ready.connect(func() -> void:
			var tw := g.create_tween().set_loops()
			tw.tween_property(g, "modulate:a", 1.0, 1.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			tw.tween_property(g, "modulate:a", 0.3, 1.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT), CONNECT_ONE_SHOT)
	else:
		g.modulate.a = 0.6
	return g


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
