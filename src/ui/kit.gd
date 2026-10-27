class_name Kit
extends RefCounted
## Kit: static UI builders for Halo & Horn. Every screen builds its UI with these so the whole
## game shares one look: style v4 "Signal", the poster house style (paper matte, ink, red
## halftone, compressed type; spec: docs/dev/ui-style-v4.md). The token names date from style v2
## so every screen keeps compiling.
##
## Quick reference (all static, all return ready-to-add Controls):
##   Tokens     dark chrome: BG, CHROME, PANEL, PANEL_HI, LINE, INK, INK_DIM, OUTLINE
##              light pages: PAPER, WHITE, TEXT, TEXT_DIM, LINE_LIGHT, BONE
##              poster: MATTE, SHEET, SHEET_WHITE, BAND, PRINT_RED
##              accents: ACCENT, ACCENT_HI, ACCENT_DEEP, ORANGE, ORANGE_HI, NEW_RED, RED_DOT
##              semantic: GOLD, GOLD_LIGHT, GOLD_DEEP, EMBER, VIOLET, SKY, GOOD, RARE, EPIC,
##              LEGENDARY; SIZE_SMALL/BODY/BUTTON/HEADER/HERO; BUTTON_H (88), GAP, PAD
##   Text       label, title, body, font, fit_label
##   Buttons    primary_button, secondary_button, danger_button, light_button, icon_button,
##              segmented, filter_chips, toggle, make_tappable, add_press_fx, deny
##   Chrome     resource_pill (top bar currencies), avatar
##   Layout     vbox, hbox, grid, scroll, margin, spacer, add, divider
##   Panels     panel ("glass" | "card" | "inset" | "plain" dark; "white" | "paper" |
##              "light_inset" | "row" light), glassify, header_bar, dialog, style, box
##   Print      dialog (the printed sheet every popup uses), tick_rule, fill_dial/set_dial,
##              sheet_pass (the compact pass), reward_receipt, halftone_ramp, loading_veil,
##              print_label
##   Widgets    currency_icon, set_chip_amount, reward_entries, faction_icon, faction_badge, tag,
##              hex_badge, equip_slot, dot/set_dot, section_header, empty_state, icon,
##              art_crop, hero_look, vgradient, grayscale_material
##   Economy    have(currency_id)
##   Colors     faction_color, rarity_color, tier_color, roman
##   Numbers    format_num (12.5K / 3.4M), format_full (1,234,567), format_time (2h 05m)
##   Motion     pop_in, pulse, shake, count_to, offset_in, stagger_in, float_text, motion_ok
##
## Conventions: sizes are viewport px on the 720 px wide canvas. Light-on-dark is the
## default (INK text on dark chrome); builders that also live on light pages take a
## `light` flag (TEXT colors). Builders only read Game (never write): reward receipts (hero and
## gear names), have (currency amounts), hero_look (equipped skins). Buttons play UI.sfx("tap")
## and a light haptic. Every clickable Kit widget uses MOUSE_FILTER_PASS so it works inside
## Kit.scroll lists (a drag scrolls instead of pressing). Touch targets are at least BUTTON_H
## (88 px) tall.
##
## Feel (2026-10-19): every Kit button and tile squashes and brightens the instant a finger
## lands and springs back past full size on release (add_press_fx); a tap on a disabled button
## shakes "no". Currency amounts count with a colour flash, switches slide their knob.
## Settings > Reduce motion (motion_ok() false) turns the decorative motion off; press feedback
## stays.

const KitBox := preload("res://src/ui/components/kit_box.gd")
const Dot := preload("res://src/ui/components/dot.gd")
const HexBadge := preload("res://src/ui/components/hex_badge.gd")
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
## Off-white bone.
const BONE := Color("ecebe5")

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

const CURRENCY_NAMES := {
	"gold": "Gold", "gems": "Gems", "scrolls": "Summon Scrolls", "hero_exp": "Hero EXP", "dust": "Dust",
}
## Short names for tight spots.
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
## The phone's tilt as the "ui_tilt" shader global has it (main.gd sets both each frame), for scripts:
## the global itself can't be read back outside the editor.
static var tilt := Vector2.ZERO
static var _icons: Dictionary = {}
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
## Currencies are real objects (owner, 2026-10-23: "i want it to feel real"): rendered in Blender
## (tools/blender/currency_objects.py, assets/art/ui/currency/), shown in their own colours.
const REAL_ICONS: Array[String] = ["gems", "gold", "scrolls", "hero_exp", "dust"]


static func icon_texture(name: String) -> Texture2D:
	if _icons.has(name):
		return _icons[name]
	if name in REAL_ICONS and ResourceLoader.exists("res://assets/art/ui/currency/%s.png" % name):
		_icons[name] = load("res://assets/art/ui/currency/%s.png" % name)
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
	# A real object keeps its colours (a tint would flatten it into a glyph).
	t.modulate = Color.WHITE if name in REAL_ICONS else color
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


## Big display title (hero names, result banners): Archivo "title" (expanded, heavy), soft drop
## shadow. Centered.
static func title(text: String, size: int = SIZE_HERO, color: Color = INK) -> Label:
	var l := label(text, size, color, "title", 0)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", maxi(2, size / 16))
	l.add_theme_constant_override("shadow_outline_size", maxi(2, size / 10))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


## Body text: Archivo "bold", word-wrapped by default (expands horizontally for a width).
static func body(text: String, size: int = SIZE_BODY, color: Color = INK, wrap: bool = true) -> Label:
	var l := label(text, size, color, "bold")
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.custom_minimum_size.x = 40
	return l


## Shrinks a label's font size (down to min_size) until its text fits `width` px.
static func fit_label(l: Label, width: float, max_size: int, min_size: int = 14) -> void:
	var f: Font = l.get_theme_font("font")
	var fs := max_size
	while fs > min_size and f.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > width:
		fs -= 1
	l.add_theme_font_size_override("font_size", fs)


# ------------------------------------------------------------------ buttons

## The signal call-to-action button (88 px tall). icon = optional assets/art/ui icon name.
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


## Square icon button with an 88 px touch target.
## look: "round" (dark glass tile, default), "gold" / "accent" (signal tile), "light" (white
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


## Amount of a currency the player has (0 when Game isn't available).
static func have(currency_id: String) -> int:
	var g := autoload("Game")
	return int(g.call("currency", currency_id)) if g else 0


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


## Square filter chips (roster filters): printed outline squares, the selected one solid ink.
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


## On/off switch (settings): an animated switch (ToggleSwitch, still a CheckButton).
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


# ------------------------------------------------------------------ top-bar widgets

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
		h.add_child(currency_icon(id, 48))
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


## Empty space. expand = take all free space in the parent box.
static func spacer(w: float = 0.0, h: float = 0.0, expand_fill: bool = false) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if expand_fill:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	# The print under everything (clipped to the sheet), on real paper (light sheets).
	var prints := Control.new()
	prints.name = "Print"
	prints.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prints.clip_contents = true
	panel_c.add_child(prints)
	if light:
		PhysicalKit.paper_fill(prints, UITheme.PRINT_PAPER)
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
	# A real status light at the end of the serial line (orange: a sheet waiting on you).
	var led := PhysicalKit.Led.new("orange", "steady", 15.0)
	led.name = "SheetLed"
	led.position = Vector2(sx + serial.get_minimum_size().x + 12.0, 21)
	head.add_child(led)
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
	# The title pressed into the sheet.
	PhysicalKit.deboss(head, 3.0).add_child(t)
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
	var c := print_day()
	return "%d.%02d.%02d" % [c[0], c[1], c[2]]


## The model's day as [year, month, day] (the player's local calendar, the day the Lobby prints;
## the system's date without the Game autoload).
static func print_day() -> Array:
	var g := autoload("Game")
	if g != null and g.has_method("today"):
		return CalendarRules.civil(int(g.call("today")))
	var d := Time.get_date_dict_from_system()
	return [int(d.year), int(d.month), int(d.day)]


## Today as press marks print it short: "28.10.26".
static func print_date_short() -> String:
	var c := print_day()
	return "%02d.%02d.%02d" % [c[2], c[1], c[0] % 100]


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


# ------------------------------------------------------------------ currencies

## Icon for a currency id ("gold", "gems", "scrolls", "hero_exp", "dust").
static func currency_icon(currency_id: String, size: float = 40.0) -> TextureRect:
	return icon(currency_id, size)


## Updates a resource_pill entry (any Control with "amount" / "amount_label" metas); animate
## counts and pulses on change.
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


# ------------------------------------------------------------------ factions & rarity

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


## Faction emblem icon (celestial halo-sun, infernal horned flame, fallen broken halo).
static func faction_icon(faction: String, size: float = 40.0) -> TextureRect:
	return icon("faction_" + faction, size)


## Faction emblem + name in the faction color. light = darker name for light pages.
static func faction_badge(faction: String, size: float = 40.0, show_name: bool = true, light: bool = false) -> HBoxContainer:
	var row := hbox(8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(faction_icon(faction, size))
	if show_name:
		var c := faction_color(faction).darkened(0.35) if light else faction_color(faction).lerp(Color.WHITE, 0.2)
		row.add_child(label(str(FACTION_NAMES.get(faction, faction.capitalize())).to_upper(), int(size * 0.6), c, "cond_bold"))
	return row


## Small flat tag, e.g. tag("NEW"), tag("BOSS", Kit.EMBER). Archivo "cond_bold", uppercase look.
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


# ------------------------------------------------------------------ gear slots

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
static func dot(size: float = 22.0, color: Color = Color("ff4b1f")) -> Control:
	var d := Dot.new()
	d.set("color", color)
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


# ------------------------------------------------------------------ art

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
	# Centred between her face and her body, so a wide pose (bent over, a weapon held out) keeps
	# more of her in frame; the face always stays inside the crop.
	var fb := HeroArt.used_rect(tex)
	var cx := lerpf(pr.get_center().x, fb.get_center().x * tw / maxf(float(tex.get_width()), 1.0), 0.55)
	var lo := pr.end.x + 10.0 - w * 0.5
	var hi := pr.position.x - 10.0 + w * 0.5
	cx = clampf(cx, lo, hi) if lo <= hi else pr.get_center().x
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
