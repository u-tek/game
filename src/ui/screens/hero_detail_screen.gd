extends Control
## Screen "hero_detail" (params: hero_id, optional browse: [hero ids] for PREV / NEXT, scroll: px,
## show: gear slot to open its picker, tab: "equip" | "skills" | "skins" | "story" to open at that
## part of the file, preview: a skin to try on). Style v4 (docs/dev/ui-style-v4.md): a character
## dossier printed in the approved Lobby poster's look, on a paper matte, two sheets that scroll.
##
## Sheet 01, the poster: a dark band down the left with her red halftone print, her bio and title in
## paper type, framed pixel squares of her and the brand marks; her name set huge across the poster in
## compressed type (paper over the band, ink over the paper, a signal full stop); the hero in full
## colour (the live rig, tap her for a reaction) in front of it with a soft red echo, boxed by the
## right-hand rule; down that rule the menu as small vertical labels (LOBBY, PREV, the issue number,
## NEXT); top right the dossier data: her name and level, stat dots for HP / ATK / DEF / SPD / CRIT
## with the exact numbers and the next level's gain, the ID code, faction and role, rarity and stars,
## power and a signal IN TEAM. Stuck on like collage: the abilities capsule ("/ ULTIMATE > ...",
## "/ PASSIVE > ..."), the Star Up stamp on a silver disc (shards, dust; tap to star up), a barcode
## and her signature, and the Level Up pass over the bottom edge (tap, hold to repeat; the knob is MAX
## with the levels it would buy). Under the poster: the file index (01 DOSSIER / 02 ARMAMENT / 03
## ABILITIES / 04 WARDROBE, each jumps there; a status light when better gear waits), the date and
## her signature. "<- BACK" sits top left on the matte.
## Sheet 02, the file: a band with a giant "02", then ARMAMENT (four gear slots as framed squares with
## a picker, Quick Equip, Unequip All), ABILITIES (the capsule with every description and unlock) and
## WARDROBE (her base look and each skin: thumbnail, Try on / Back to equipped, Wear / Equipped / Buy
## / Coming soon). A strip with BACK and POSTER pins to the top once sheet 01 has scrolled away.
## Unowned heroes print grey with a Summon pass; there is no armament.
##
## A Legendary's page (LegendKit, src/ui/v4/legend_kit.gd; owner, 2026-10-20: "more built out and more
## powerful. and cooler. with exclusive features") is hot-stamped in gold holo foil that moves with
## the phone: a LEGEND masthead with her legend title on the matte, a foil frame round the poster, her
## print in gold, a holo sheen on the band, her faction's growth (thorns or jelly) round her figure and
## a gold aura once she has awakened; her legend passive on the capsule; past 6 stars the stamp disc
## becomes AWAKEN. A third sheet, the LEGEND FILE, sits between the poster and the file: three sigil
## seals (A1 legend passive, A2 empowered ultimate, A3 Ascended), the AWAKEN press with its cost (a big
## awakening animation, LegendKit.AwakenFx), her two exclusive cards (locked until their tier, with
## what they need) and three lore lines declassified one per tier. Ascended (A3): her name in gold
## foil, a crown stamp, a stronger aura with rays. Debug params: fx_awaken (tier) plays the animation,
## fx_at (s) freezes it at that moment (screenshots).

## The matte line above the poster: the big Back and the publication line.
const TOP_LINE := 100.0
const Roster := preload("res://src/ui/screens/heroes_screen.gd")
const PK := preload("res://src/ui/v4/hero_poster_kit.gd")
const HUD := preload("res://src/ui/components/hud.gd")

const HOLD_DELAY := 0.42
const HOLD_START := 0.16
const HOLD_MIN := 0.045
const STAT_ORDER: Array[String] = ["hp", "atk", "def", "spd", "crit"]
const SLOTS: Array[String] = ["weapon", "armor", "helm", "charm"]
## The poster sheet is never shorter than this (short windows scroll).
const MIN_H := 1080.0
## The dossier is never wider than this (tablets centre it on the matte).
const MAX_W := 760.0
const BAND := 196.0
## The right-hand rule's inset from the poster's right edge (the menu labels sit right of it).
const RULE_IN := 48.0
## Her body's height on the poster (share of the poster) and how far her feet sit below its bottom
## edge: the plate and the star disc cover her feet anyway (_fit_sprite).
const FIG_FILL := 0.95
const FIG_SINK := 0.06
const FOOT_H := 112.0
const INK := Color("101113")
const PAPER := Color("e9e8e2")
const MATTE := Color("f5f4f0")
const SIG := Color("ff4b1f")
const SHORT := Color("c9300d")
const FACTION_CODE := {"celestial": "CE", "infernal": "IN", "fallen": "FA"}
const SECTIONS := [["poster", "DOSSIER"], ["equip", "ARMAMENT"], ["skills", "ABILITIES"], ["skins", "WARDROBE"]]
## A Legendary's matte line is taller (the LEGEND masthead).
const LEGEND_TOP := 128.0
## The legend sheet's dark strip with the turned LEGEND type.
const LEGEND_STRIP := 128.0

## Base-stat range over every hero (stat dots rate a hero against the roster): stat -> [min, max].
static var _stat_range := {}

var _id := ""
var _def: Dictionary = {}
var _owned := false
var _browse: Array[String] = []

var _w := 720.0
var _free_h := 1176.0
var _sheet_h := 1176.0
var _built_for := Vector2.ZERO
var _ox := 0.0
var _scroll: ScrollContainer
var _page: Control
## Everything printed lives on the sheet (phone width, centred in the scrolling page).
var _sheet: Control
var _poster: Control
var _box: Control
var _anchor: Node2D
var _sprite: Node2D
var _fig_h := 900.0
## The skin the sprite was built with ("" = base look) and what it shows (HeroArt.art_key, which
## also follows the nudity setting); a change rebuilds the sprite.
var _sprite_skin := ""
var _sprite_key := ""
var _preview := ""        # a skin tried on from the wardrobe (not saved); "" = the equipped look
var _poke: Button
var _tap_n := 0
var _tap_at := -10.0
var _fx: Control
var _sticky: Control
var _arrows: Array[Control] = []
var _back_btn: Button
var _home_btn: Button

var _level_l: Label
var _power_l: Label
var _power_value := -1
var _team_l: Label
var _stars: Control
var _stat_cells: Array[Dictionary] = []
var _stats_sig := ""
var _pass: PK.Pass
var _lvl_btn: Button
var _max_btn: Button
var _star_disc: Control
var _star_stamp: Control
var _star_btn: Button
var _capsule: Control
var _capsule_sig := ""
var _index: Array[Dictionary] = []
var _gear_led: Control
var _file: VBoxContainer
var _file_poster: Control
var _file_shadow: Control
var _file_sig := ""
var _section_y := {}
var _gear_modal: Control

# A Legendary's page (LegendKit).
var _legend := false
var _aw := 0
var _legend_sheet: Control
var _legend_body: Control
var _legend_h := 0.0
var _legend_sig := ""
var _aw_press: PK.Pass
var _aw_btn: Button
var _seals: Array[Control] = []
var _awaken_fx: Control
## True from AWAKEN until the animation's flash (the page waits to reprint under it).
var _awaken_pending := false
var _fx_params := {}

var _holding := false
var _hold_t := 0.0
var _hold_next := 0.0
var _hold_count := 0
var _hold_gained := 0
var _victory_left := 0.0


func setup(params: Dictionary) -> void:
	_id = str(params.get("hero_id", ""))
	_def = Game.hero_def(_id)
	var b: Variant = params.get("browse", [])
	if b is Array:
		for x: Variant in b:
			_browse.append(str(x))
	# The nav stays (owner: the bottom nav on every screen but battle); the dossier adds a big Back.
	if _def.is_empty():
		_build_missing()
		return
	Roster.mark_seen(_id)
	_owned = Game.owns(_id)
	_legend = LegendKit.is_legend(_def)
	_aw = int(Game.awaken_tier(_id)) if _legend else 0
	_preview = str(params.get("preview", ""))
	if _browse.is_empty() or not _browse.has(_id):
		_browse.clear()
		for h: Dictionary in Game.owned_heroes():
			_browse.append(str(h.id))
		if not _browse.has(_id):
			_browse = [_id]
	_build()
	resized.connect(_on_resized)
	Game.changed.connect(_refresh)
	_refresh()
	if params.has("scroll"):
		_scroll_to.call_deferred(int(params["scroll"]))
	var want := str(params.get("tab", ""))
	if want != "":
		_jump.call_deferred({"equip": "equip", "skills": "skills", "skins": "skins", "story": "poster",
			"legend": "legend" if _legend else "poster"}.get(want, "poster"), false)
	if str(params.get("show", "")) != "":
		_open_gear_picker.call_deferred(str(params["show"]))
	if _legend and params.has("fx_awaken"):
		# Screenshots: play the awakening animation for this tier (nothing changes in the save).
		_fx_params = {"tier": clampi(int(params["fx_awaken"]), 1, 3), "at": float(params.get("fx_at", -1.0))}
		_debug_fx.call_deferred()


## Screenshot/testing helper (params.scroll): scroll the dossier once laid out.
func _scroll_to(px: int) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(_scroll):
		_scroll.scroll_vertical = px


func _exit_tree() -> void:
	if Game.changed.is_connected(_refresh):
		Game.changed.disconnect(_refresh)
	if _awaken_fx and is_instance_valid(_awaken_fx):
		_awaken_fx.queue_free()
	if _gear_modal and is_instance_valid(_gear_modal):
		UI.close_modal(_gear_modal)


func _dims() -> Vector2:
	var vp := get_viewport_rect().size
	return Vector2(vp.x, maxf(vp.y - UI.content_top() - UI.content_bottom(), 400.0))


func _on_resized() -> void:
	if _scroll == null or size.x <= 0.0:
		return
	var d := _dims()
	if absf(d.x - _built_for.x) > 2.0 or absf(d.y - _built_for.y) > 2.0:
		_rebuild.call_deferred()


func _rebuild() -> void:
	var keep := _scroll.scroll_vertical if is_instance_valid(_scroll) else 0
	for c in get_children():
		if c == _awaken_fx:
			continue
		remove_child(c)
		c.queue_free()
	_arrows.clear()
	_stat_cells.clear()
	_index.clear()
	_seals.clear()
	_stats_sig = ""
	_capsule_sig = ""
	_file_sig = ""
	_legend_sig = ""
	_power_value = -1
	_aw = int(Game.awaken_tier(_id)) if _legend else 0
	_build()
	_refresh()
	_scroll_to.call_deferred(keep)


func _build_missing() -> void:
	PK.matte(self)
	var d := _dims()
	var p := PK.poster(self, Rect2(18, TOP_LINE, d.x - 36, minf(d.y - TOP_LINE - 40, 700)))
	PK.rect(p, Rect2(0, 0, BAND, p.size.y), PK.BAND)
	PK.at(p, PK.t("HH", 34, PAPER, "wide_black"), Vector2(20, 18))
	PK.at(p, PK.t("FILE\nNOT\nFOUND.", 120, INK, "compressed"), Vector2(BAND + 24, 40))
	PK.at(p, PK.t("No record of this hero.", 14, INK, "mono"), Vector2(BAND + 28, p.size.y - 60))
	_back_btn = SignalKit.back_button(func() -> void: UI.back())
	add_child(_back_btn)
	_home_btn = _text_button(self, Rect2(d.x - 200, 0, 200, 88), "LOBBY", 13, func() -> void: UI.go("home"))
	_home_btn.name = "Home"
	PK.grain(self)


# ------------------------------------------------------------------ build

func _build() -> void:
	var d := _dims()
	_built_for = d
	# Wider windows (tablets) keep the poster at phone width, centred on the matte.
	_w = minf(d.x, MAX_W)
	_ox = floorf((d.x - _w) * 0.5)
	_free_h = d.y
	_sheet_h = maxf(_free_h, MIN_H)
	PK.matte(self)
	_page = Control.new()
	_page.name = "Page"
	_page.mouse_filter = MOUSE_FILTER_IGNORE
	_page.custom_minimum_size = Vector2(d.x, _sheet_h + 400)
	_sheet = Control.new()
	_sheet.name = "Sheet"
	_sheet.mouse_filter = MOUSE_FILTER_IGNORE
	_sheet.position = Vector2(_ox, 0)
	_sheet.size = Vector2(_w, _sheet_h)
	_page.add_child(_sheet)
	_scroll = Kit.scroll(_page)
	_scroll.name = "Dossier"
	_scroll.position = Vector2.ZERO
	_scroll.size = Vector2(d.x, _free_h)
	add_child(_scroll)
	_scroll.get_v_scroll_bar().value_changed.connect(func(_v: float) -> void: _on_scrolled())
	_build_poster()
	if _legend:
		_build_legend_sheet()
	_build_file_sheet()
	_fx = Control.new()
	_fx.name = "Fx"
	_fx.mouse_filter = MOUSE_FILTER_IGNORE
	_fx.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(_fx)
	_build_sticky()
	PK.grain(self)


## Sheet 01: the poster, its matte line on top and the index, date and signature under it.
func _build_poster() -> void:
	var w := _w
	var name_txt := str(_def.get("name", _id))
	var skin := _shown_skin()
	# ---- The matte line: BACK left, the publication line right.
	_back_btn = SignalKit.back_button(func() -> void: UI.back())
	_back_btn.position = Vector2(4, 0)
	_sheet.add_child(_back_btn)
	var top := LEGEND_TOP if _legend else TOP_LINE
	if _legend:
		_build_masthead(w)
	else:
		var pub := PK.t("HALO & HORN  ©2026  ·  DOSSIER %s" % _code(), 12, Color(INK, 0.7), "mono")
		pub.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		pub.size = Vector2(440, 16)
		PK.at(_sheet, pub, Vector2(w - 20 - 440, 40))

	var pr := Rect2(18, top, w - 36, _sheet_h - top - FOOT_H)
	_poster = PK.poster(_sheet, pr)
	var p := _poster
	var pw := pr.size.x
	var ph := pr.size.y

	# ---- The band: her red halftone print, brand marks, title and bio in paper type.
	PK.rect(p, Rect2(0, 0, BAND, ph), PK.BAND)
	var ht := PK.halftone_print(_id, skin, Vector2(BAND, ph * 0.58), 7.0, LegendKit.GOLD_PRINT if _legend else PK.PRINT, 1.25)
	ht.position = Vector2(0, ph * 0.42)
	p.add_child(ht)
	if _legend:
		# Hot-stamped holo: a glint that slides across the band as the phone tilts.
		LegendKit.foil_rect(p, Rect2(0, 0, BAND, ph), 2, {"strength": 0.45, "band_px": 300.0}).name = "BandSheen"
	PK.at(p, LegendKit.foil_label("HH", 34, "wide_black", "gold", {"band_px": 120.0}) if _legend else PK.t("HH", 34, PAPER, "wide_black"), Vector2(20, 16))
	PK.at(p, PK.t("™", 12, PAPER, "mono"), Vector2(84, 18))
	PK.at(p, PK.t("No.\n%02d" % _number(), 12, Color(PAPER, 0.85), "mono_bold"), Vector2(20, 72))
	PK.at(p, PK.t(_print_date(), 12, Color(PAPER, 0.85), "mono_bold"), Vector2(64, 78))
	var title := PK.t(str(_def.get("title", "")).to_upper(), 12, PAPER, "mono_bold")
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.size = Vector2(BAND - 46, 0)
	PK.at(p, title, Vector2(20, 120))
	var bio := PK.t(str(_def.get("bio", "")), 11, Color(PAPER, 0.88), "mono")
	bio.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bio.add_theme_constant_override("line_spacing", 0)
	bio.size = Vector2(BAND - 40, 0)
	var bio_y := 120 + title.get_minimum_size().y + 8
	PK.at(p, bio, Vector2(20, bio_y))
	# Barcode and her signature under the bio, in paper ink.
	var by := bio_y + bio.get_minimum_size().y + 12
	PK.at(p, SignalKit.barcode(Vector2(120, 22), PAPER, _id.hash() & 0xffff), Vector2(20, by))
	PK.at(p, PK.t(str(_def.get("name", _id)), 28, PAPER, "serif_italic"), Vector2(22, by + 22))
	# Her name repeated down the band's edge in micro type.
	var rep := PK.vlabel(("%s  ·  " % name_txt.to_upper()).repeat(14), 10, Color(PAPER, 0.42), "mono_bold")
	PK.at(p, rep, Vector2(BAND - 6, 6))
	# Framed pixel squares of her over the print.
	PK.at(p, PK.pixel_square(_id, skin, "face", 88, 9, PAPER), Vector2(20, ph * 0.555))
	PK.at(p, PK.pixel_square(_id, skin, "chest", 60, 7, PAPER), Vector2(116, ph * 0.555 + 58))

	# ---- Her name, huge across the poster: paper over the band, ink over the paper.
	var nm := name_txt.to_upper()
	var fs := clampi(int(240.0 * (pw - RULE_IN - 40.0) / maxf(PK.text_w(nm + ".", 240), 1.0)), 110, 300)
	var bb := "%s[color=#%s].[/color]" % [nm, SIG.to_html(false)]
	var name_y := ph * 0.45 - fs * 0.62
	if _legend and _owned and _aw >= 1:
		_build_legend_glow(p, Vector2(BAND + 262, ph + 10), ph * 0.82)
	PK.giant(p, bb, fs, Vector2(14, name_y), Vector2(pw * 1.4, fs * 1.4),
		[[Rect2(0, 0, BAND, ph), PAPER], [Rect2(BAND, 0, pw - BAND - RULE_IN, ph), INK]], 0, "compressed", false)
	if _legend and _aw >= 3:
		# Ascended: her name stamped in gold foil (bright on the band, deep gold on the paper).
		_foil_giant(p.get_child(p.get_child_count() - 1))

	# ---- The hero, full colour, in front of her name, boxed by the right-hand rule.
	_box = Control.new()
	_box.name = "HeroBox"
	_box.mouse_filter = MOUSE_FILTER_IGNORE
	_box.clip_contents = true
	_box.size = Vector2(pw - RULE_IN - 1, ph)
	p.add_child(_box)
	_fig_h = ph * 0.82
	var feet := Vector2(BAND + 262, ph + 10)
	var echo := PK.echo(_id, skin, _fig_h * 1.14, 0.36 if _owned else 0.16)
	echo.position = Vector2(feet.x - echo.size.x * 0.5 + 96, feet.y - echo.size.y - 30)
	_box.add_child(echo)
	if _legend:
		_build_legend_figure(feet, pw, ph)
	_anchor = Node2D.new()
	_anchor.name = "HeroAnchor"
	_anchor.position = feet
	_box.add_child(_anchor)
	_sprite_skin = skin
	_sprite_key = HeroArt.art_key(_id, skin)
	_sprite = HeroArt.make_sprite(_id, skin)
	_anchor.add_child(_sprite)
	_fit_sprite()
	_poke = Button.new()
	_poke.name = "Poke"
	_poke.theme_type_variation = &"BareButton"
	_poke.focus_mode = FOCUS_NONE
	_poke.mouse_filter = MOUSE_FILTER_PASS
	_poke.position = Vector2(pr.position.x + BAND + 140, pr.position.y + ph * 0.24)
	_poke.size = Vector2(250, ph * 0.46)
	_sheet.add_child(_poke)
	Kit._connect_pressed(_poke, _poke_hero, "")

	# ---- The right-hand rule and the menu down it.
	PK.rule(p, Vector2(pw - RULE_IN, 0), Vector2(1, ph))
	PK.at(p, PK.vlabel("©2026 ·", 12, INK), Vector2(pw - 34, 14))
	_home_btn = _edge_label(p, pr, "LOBBY", 0.1, func() -> void: UI.go("home"))
	_home_btn.name = "Home"
	if _browse.size() > 1:
		var i := _browse.find(_id)
		var prev := _edge_label(p, pr, "<- PREV", 0.25, func() -> void: _browse_step(-1))
		prev.name = "Prev"
		PK.at(p, PK.vlabel("%02d / %02d" % [i + 1, _browse.size()], 12, Color(INK, 0.5), "mono"), Vector2(pw - 16, ph * 0.355))
		var nxt := _edge_label(p, pr, "NEXT ->", 0.45, func() -> void: _browse_step(1))
		nxt.name = "Next"
		_arrows = [prev, nxt]

	# ---- The dossier data, top right (ink, in front of her).
	var x1 := BAND + 34.0
	var xr := pw - RULE_IN - 14.0
	PK.at(p, PK.t("%s  HH©" % nm, 14, INK, "mono_bold"), Vector2(x1, 16))
	_level_l = PK.t("", 14, INK, "mono_bold")
	_level_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_level_l.size = Vector2(200, 18)
	PK.at(p, _level_l, Vector2(xr - 200, 16))
	PK.rule(p, Vector2(x1, 40), Vector2(xr - x1, 1), Color(INK, 0.35))
	var cw := (xr - x1) / 5.0
	_stat_cells.clear()
	for k in STAT_ORDER.size():
		var stat := STAT_ORDER[k]
		var cx := x1 + k * cw
		PK.at(p, PK.t(str(Kit.STAT_SHORT.get(stat, stat.to_upper())), 11, INK, "mono_bold"), Vector2(cx, 48))
		var dots := HUD.Dots.new()
		dots.count = 5
		dots.filled = _rating(stat)
		dots.color = INK
		dots.empty = Color(INK, 0.3)
		dots.gap = 2.0
		dots.size = Vector2(5 * 9 + 4 * 2, 9)
		PK.at(p, dots, Vector2(cx, 67))
		var val := PK.t("", 13, INK, "mono_bold")
		PK.at(p, val, Vector2(cx, 82))
		var dl := PK.t("", 10, Color(INK, 0.55), "mono")
		PK.at(p, dl, Vector2(cx, 100))
		_stat_cells.append({"value": val, "delta": dl})
	var lines := [
		"%s  /  No.%02d" % [_code(), _number()],
		"%s  —  %s" % [str(Kit.FACTION_NAMES.get(str(_def.faction), "")).to_upper(), str(Kit.ROLE_NAMES.get(str(_def.role), "")).to_upper()],
		str(Kit.RARITY_NAMES.get(str(_def.rarity), "")).to_upper(),
	]
	var ly := 126.0
	for l: String in lines:
		var lab := PK.t(l, 13, INK, "mono")
		lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		lab.size = Vector2(320, 17)
		PK.at(p, lab, Vector2(xr - 320, ly))
		ly += 18.0
	_stars = PK.Stars.new()
	_stars.size = Vector2(6 * 11 + 5 * 3, 11)
	PK.at(p, _stars, Vector2(xr - _stars.size.x - PK.text_w(lines[2], 13, "mono") - 12, ly - 15))
	_power_l = PK.t("", 13, INK, "mono_bold")
	_power_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_power_l.size = Vector2(240, 17)
	PK.at(p, _power_l, Vector2(xr - 240 - 78, ly))
	_team_l = PK.t("IN TEAM", 13, SIG, "mono_bold")
	_team_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_team_l.size = Vector2(72, 17)
	PK.at(p, _team_l, Vector2(xr - 72, ly))

	# ---- Collage at the bottom: the abilities capsule, the Star Up stamp, barcode and signature.
	_capsule = Control.new()
	_capsule.name = "Capsule"
	_capsule.mouse_filter = MOUSE_FILTER_IGNORE
	_capsule.position = pr.position + Vector2(14, ph - (358 if _legend else 316))
	_capsule.size = Vector2(minf(400.0, pw - RULE_IN - 40.0), 158 if _legend else 116)
	_sheet.add_child(_capsule)
	if _owned:
		_star_disc = SignalKit.plate("silver", pr.position + Vector2(20, ph - 172), Vector2(112, 112), {"circle": true, "shadow": 0.5}, _sheet)
		_star_disc.rotation = -0.12
		_star_stamp = SignalKit.stamp("STAR UP · ", "", 112)
		_star_disc.add_child(_star_stamp)
		_star_btn = Button.new()
		_star_btn.name = "StarUp"
		_star_btn.theme_type_variation = &"BareButton"
		_star_btn.focus_mode = FOCUS_NONE
		_star_btn.mouse_filter = MOUSE_FILTER_PASS
		_star_btn.position = pr.position + Vector2(14, ph - 178)
		_star_btn.size = Vector2(124, 124)
		_sheet.add_child(_star_btn)
		Kit.add_press_fx(_star_btn, _star_disc)
		Kit._connect_pressed(_star_btn, _on_star_up)

	# ---- The pass over the poster's bottom edge: Level Up (owned) or Summon.
	if _owned:
		# Levelling is an arcade push button (the button family), not the battle pass.
		_pass = PK.make_press(392.0)
		_lvl_btn = _pass.hit
		_lvl_btn.name = "LevelUp"
		_lvl_btn.button_down.connect(_on_level_down)
		_lvl_btn.button_up.connect(func() -> void: _end_hold())
		_lvl_btn.pressed.connect(func() -> void:
			var down: Variant = _lvl_btn.get_meta("_down_at") if _lvl_btn.has_meta("_down_at") else null
			if down is Vector2 and (down as Vector2).distance_to(_lvl_btn.get_global_mouse_position()) > 36.0:
				return
			_on_level_tap())
		_max_btn = _pass.knob_hit
		_max_btn.name = "LevelMax"
		Kit._connect_pressed(_max_btn, _on_level_max)
	else:
		_pass = PK.make_pass(392.0, "summon", false)
		_pass.set_text("NOT YET SUMMONED", "SUMMON", "ANSWERS THE PORTAL · %s" % str(Kit.RARITY_NAMES.get(str(_def.rarity), "")).to_upper(),
			"SUMMON  >>>", "EVERY PULL HAS A CHANCE")
		Kit._connect_pressed(_pass.hit, func() -> void: UI.go("summon"))
		_pass.hit.name = "GoSummon"
	_pass.position = Vector2(pr.end.x - 404, pr.end.y - 176)
	_pass.rotation = -0.03
	_sheet.add_child(_pass)
	if _legend:
		# A foil frame round the whole poster (hot-stamped; she stands in front of it).
		LegendKit.foil_rect(p, Rect2(0, 0, pw, ph), 1, {"inset": 9.0, "frame_w": 3.0, "band_px": 340.0}).name = "FoilFrame"
		if _aw >= 3:
			_stamp_crown(pr, name_y, fs)

	# ---- Under the poster: the file index, the date and her signature.
	var nav_y := pr.end.y + 18.0
	var items: Array = []
	for s: Array in SECTIONS:
		if str(s[0]) == "equip" and not _owned:
			continue
		items.append(s)
		if _legend and str(s[0]) == "poster":
			items.append(["legend", "LEGEND"])
	var colw := (w - 40.0) / items.size()
	_index.clear()
	for i in items.size():
		var sid := str(items[i][0])
		var on := i == 0
		var l2 := PK.t("%02d %s" % [i + 1, items[i][1]], 13, SIG if on else INK, "mono_bold")
		l2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l2.size = Vector2(colw, 18)
		PK.at(_sheet, l2, Vector2(20 + i * colw, nav_y))
		if on:
			PK.rect(_sheet, Rect2(20 + i * colw + colw * 0.5 - 22, nav_y + 24, 44, 3), SIG)
		if i < items.size() - 1:
			PK.at(_sheet, PK.t("/", 13, Color(INK, 0.35), "mono"), Vector2(20 + (i + 1) * colw - 5, nav_y))
		if i > 0:
			var hb := _hit(_sheet, Rect2(20 + i * colw, nav_y - 18, colw, 88), _jump.bind(sid, true))
			hb.name = "Index_" + sid
		if sid == "equip":
			var led := HUD.Led.new()
			led.size = Vector2(14, 14)
			led.mode = "breathe"
			led.position = Vector2(20 + i * colw + colw * 0.5 + PK.text_w(l2.text, 13, "mono_bold") * 0.5 + 2, nav_y + 1)
			led.visible = false
			_sheet.add_child(led)
			_gear_led = led
	PK.at(_sheet, PK.t(_print_date(true), 26, INK, "regular"), Vector2(20, nav_y + 46))
	var sig := PK.t(name_txt, 54, INK, "serif_italic")
	sig.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sig.size = Vector2(300, 60)
	PK.at(_sheet, sig, Vector2(w - 24 - 300, nav_y + 24))
	var swash := PK.rect(_sheet, Rect2(w - 250, nav_y + 84, 220, 2), INK)
	swash.rotation = -0.06
	SignalKit.relight(self)


## A menu label down the right-hand rule: turned mono type, a tick on the rule, an 88 px target.
func _edge_label(p: Control, pr: Rect2, text: String, at_y: float, cb: Callable) -> Button:
	var pw := pr.size.x
	var ph := pr.size.y
	var l := PK.vlabel(text, 14, INK, "mono_bold")
	PK.at(p, l, Vector2(pw - 15, ph * at_y))
	PK.rule(p, Vector2(pw - RULE_IN - 4, ph * at_y + 2), Vector2(9, 1), INK)
	var tl := PK.text_w(text, 14, "mono_bold")
	return _hit(_sheet, Rect2(pr.position.x + pw - 92, pr.position.y + ph * at_y - 16, 92, maxf(88.0, tl + 32.0)), cb)


## An invisible 88 px (or larger) touch target over printed type.
func _hit(parent: Control, r: Rect2, cb: Callable) -> Button:
	var b := Button.new()
	b.theme_type_variation = &"BareButton"
	b.focus_mode = FOCUS_NONE
	b.mouse_filter = MOUSE_FILTER_PASS
	b.position = r.position
	b.size = r.size
	parent.add_child(b)
	Kit._connect_pressed(b, cb)
	return b


## Printed mono type that is a button (the label shows the press).
func _text_button(parent: Control, r: Rect2, text: String, size_px: int, cb: Callable) -> Button:
	var b := _hit(parent, r, cb)
	var l := PK.t(text, size_px, INK, "mono_bold")
	l.position = Vector2(20, 13)
	b.add_child(l)
	Kit.add_press_fx(b, l)
	return b


## Sheet 02: a second poster with a band, a giant "02" and the file's three parts.
func _build_file_sheet() -> void:
	var y2 := _sheet_h + 8.0
	if _legend and _legend_sheet:
		y2 = _legend_sheet.position.y + _legend_h + 26.0
	var pw := _w - 36.0
	_file_shadow = Panel.new()
	_file_shadow.mouse_filter = MOUSE_FILTER_IGNORE
	var ss := StyleBoxFlat.new()
	ss.bg_color = PAPER
	ss.shadow_color = Color(0, 0, 0, 0.28)
	ss.shadow_size = 22
	ss.shadow_offset = Vector2(0, 8)
	_file_shadow.add_theme_stylebox_override("panel", ss)
	_file_shadow.position = Vector2(18, y2)
	_file_shadow.size = Vector2(pw, 1200)
	_sheet.add_child(_file_shadow)
	_file_poster = Control.new()
	_file_poster.mouse_filter = MOUSE_FILTER_IGNORE
	_file_poster.clip_contents = true
	_file_poster.position = Vector2(18, y2)
	_file_poster.size = Vector2(pw, 1200)
	_sheet.add_child(_file_poster)
	var fp := _file_poster
	var bh := 176.0
	PK.rect(fp, Rect2(0, 0, pw, bh), PK.BAND)
	var ht := PK.halftone_print(_id, _shown_skin(), Vector2(pw * 0.5, bh), 6.0, PK.PRINT, 0.8)
	ht.position = Vector2(pw * 0.5, 0)
	fp.add_child(ht)
	PK.at(fp, PK.t("HH", 26, PAPER, "wide_black"), Vector2(20, 16))
	var fno := "03 / 03" if _legend else "02 / 02"
	PK.at(fp, PK.t("FILE %s\n%s  ·  %s" % [fno, _code(), str(_def.get("name", _id)).to_upper()], 12, Color(PAPER, 0.85), "mono_bold"), Vector2(20, 56))
	PK.at(fp, PK.t("ARMAMENT · ABILITIES · WARDROBE", 11, Color(PAPER, 0.6), "mono"), Vector2(20, bh - 28))
	# A giant "02", paper on the band and ink below it.
	var big := "03" if _legend else "02"
	PK.giant(fp, big, 280, Vector2(pw - PK.text_w(big, 280) - 30, bh - 196), Vector2(420, 330),
		[[Rect2(0, 0, pw, bh), PAPER], [Rect2(0, bh, pw, 400), INK]], 0, "compressed", false)
	_file = VBoxContainer.new()
	_file.name = "File"
	_file.add_theme_constant_override("separation", 18)
	_file.position = Vector2(24, bh + 104)
	_file.size = Vector2(pw - 48, 0)
	_file.custom_minimum_size.x = pw - 48
	fp.add_child(_file)
	_file.sort_children.connect(_fit_file)


## Sizes sheet 02 and the scroll page to the file's content.
func _fit_file() -> void:
	if not is_instance_valid(_file):
		return
	var h := _file.position.y + _file.get_combined_minimum_size().y + 150.0
	_file_shadow.size.y = h
	_file_poster.size.y = h
	_page.custom_minimum_size.y = _file_poster.position.y + h + 40.0
	_section_y["poster"] = 0.0
	if _legend and _legend_sheet:
		_section_y["legend"] = _legend_sheet.position.y - 100.0
	for c in _file.get_children():
		var key := str(c.get_meta("section", ""))
		if key != "":
			_section_y[key] = _file_poster.position.y + _file.position.y + (c as Control).position.y - 20.0


## The strip that pins to the top once the poster has scrolled away: BACK, her file, POSTER.
func _build_sticky() -> void:
	_sticky = Control.new()
	_sticky.name = "Sticky"
	_sticky.mouse_filter = MOUSE_FILTER_IGNORE
	_sticky.size = Vector2(_w + _ox * 2.0, 96)
	_sticky.visible = false
	add_child(_sticky)
	PK.rect(_sticky, Rect2(0, 0, _sticky.size.x, 96), MATTE)
	PK.rule(_sticky, Vector2(0, 96), Vector2(_sticky.size.x, 1), Color(INK, 0.5))
	var b := SignalKit.back_button(func() -> void: UI.back())
	b.name = "StickyBack"
	b.position = Vector2(_ox + 4, 0)
	_sticky.add_child(b)
	var mid := PK.t("%s  ·  %s  ·  %s" % [str(_def.get("name", _id)).to_upper(), _code(), "LEGEND FILE" if _legend else "FILE 02"], 12, Color(INK, 0.7), "mono")
	mid.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mid.size = Vector2(_w - 380, 16)
	PK.at(_sticky, mid, Vector2(_ox + 190, 40))
	var up := _text_button(_sticky, Rect2(_ox + _w - 190, 4, 190, 88), "POSTER ^", 13, func() -> void: _jump("poster", true))
	(up.get_child(0) as Label).position.y = 36
	up.name = "StickyTop"
	(up.get_child(0) as Label).position.x = 64


func _on_scrolled() -> void:
	if _sticky == null:
		return
	_sticky.visible = _scroll.scroll_vertical > _sheet_h - 120.0


## Scrolls to a part of the dossier ("poster", "equip", "skills", "skins").
func _jump(section: String, animate: bool = true) -> void:
	if not is_inside_tree():
		return
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_instance_valid(_scroll):
		return
	var y := int(_section_y.get(section, 0.0))
	if animate and Kit.motion_ok():
		_scroll.create_tween().tween_property(_scroll, "scroll_vertical", y, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	else:
		_scroll.scroll_vertical = y


func _fit_sprite() -> void:
	if _sprite == null or not is_instance_valid(_sprite):
		return
	# Full screen (owner 2026-10-20: "i want the characters to take up the whole screen ... her wings
	# can be off screen"): her body (HeroArt.fit_sprite, core) as tall as the poster, feet just under
	# its bottom edge behind the level-up plate; wings, weapon, tail and cape may run off the poster.
	var fig := _box.size.y * FIG_FILL
	var feet_y := _box.size.y * (1.0 + FIG_SINK)
	HeroArt.fit_sprite(_sprite, _anchor, Rect2(BAND - 150.0, feet_y - fig, _box.size.x - (BAND - 150.0), fig), BAND + 262.0, true)
	if not _owned:
		_sprite.modulate = Color(0.5, 0.5, 0.52, 0.9)


# ------------------------------------------------------------------ data helpers

func _number() -> int:
	var i := 0
	for d: Dictionary in Game.all_hero_defs():
		i += 1
		if str(d.id) == _id:
			return i
	return 0


func _code() -> String:
	return "HH-%s-%02d" % [str(FACTION_CODE.get(str(_def.get("faction", "")), "XX")), _number()]


func _print_date(long: bool = false) -> String:
	var dt := Time.get_date_dict_from_system()
	if long:
		return "%d %02d/%02d" % [int(dt.year), int(dt.month), int(dt.day)]
	return "%02d.%02d.%02d" % [int(dt.day), int(dt.month), int(dt.year) % 100]


## Stat dots (1-5): the hero's base stat against every hero's.
func _rating(stat: String) -> int:
	if _stat_range.is_empty():
		for d: Dictionary in Game.all_hero_defs():
			var bs: Dictionary = d.get("base_stats", {})
			for k: String in STAT_ORDER:
				var v := int(bs.get(k, 0))
				var r: Array = _stat_range.get(k, [v, v])
				_stat_range[k] = [mini(int(r[0]), v), maxi(int(r[1]), v)]
	var r2: Array = _stat_range.get(stat, [0, 1])
	var v2 := int((_def.get("base_stats", {}) as Dictionary).get(stat, 0))
	var span := maxi(int(r2[1]) - int(r2[0]), 1)
	return clampi(1 + int(round(4.0 * float(v2 - int(r2[0])) / span)), 1, 5)


func _stat_text(stat: String, v: int) -> String:
	if stat == "crit":
		if v % 100 == 0:
			return "%d%%" % (v / 100)
		return "%.1f%%" % (float(v) / 100.0)
	return Kit.format_full(v)


# ------------------------------------------------------------------ refresh

func _refresh() -> void:
	if not is_inside_tree() or _poster == null:
		return
	_owned = Game.owns(_id)
	if HeroArt.art_key(_id, _shown_skin()) != _sprite_key:
		_rebuild_sprite()
	var h := Game.hero(_id)
	var stars := int(h.get("stars", Kit.RARITY_STARS.get(str(_def.rarity), 1)))
	var level := int(h.get("level", 1))
	var cap := int(Game.max_level(_id))
	_level_l.text = "LV %d / %d" % [level, cap] if _owned else "LV — / %d" % cap
	_stars.set("count", Kit.MAX_STARS if _owned else maxi(stars, 1))
	_stars.set("filled", stars)
	_stars.queue_redraw()
	_team_l.visible = Game.formation().has(_id)
	var p := int(Game.hero_power(_id))
	if _power_value >= 0 and p != _power_value:
		_count_power(_power_value, p)
	else:
		_power_l.text = "PWR %s" % Kit.format_full(p)
	_power_value = p
	_refresh_stats(level, cap, stars)
	if _owned:
		_refresh_level(level, cap)
		_refresh_stars(stars)
	_refresh_capsule(stars)
	if _legend:
		_refresh_legend()
	if _gear_led:
		var better := false
		var hg: Dictionary = h.get("gear", {})
		for slot: String in SLOTS:
			better = better or _better_loose(slot, str(hg.get(slot, "")))
		_gear_led.visible = _owned and better
	_refresh_file()
	_refresh_guide()


func _count_power(from: int, to: int) -> void:
	var tw := _power_l.create_tween()
	tw.tween_method(func(v: float) -> void:
		if is_instance_valid(_power_l):
			_power_l.text = "PWR %s" % Kit.format_full(int(v)), float(from), float(to), 0.5)
	Kit.pulse(_power_l, 1.08)


func _refresh_stats(level: int, cap: int, stars: int) -> void:
	var st := Game.hero_stats(_id)
	var nxt := {}
	if _owned and level < cap:
		nxt = Game.hero_stats_at(_id, level + 1, stars)
	var sig := JSON.stringify(st) + JSON.stringify(nxt)
	if sig == _stats_sig:
		return
	_stats_sig = sig
	for i in STAT_ORDER.size():
		var k := STAT_ORDER[i]
		var val := int(st.get(k, 0))
		var cell := _stat_cells[i]
		(cell["value"] as Label).text = _stat_text(k, val)
		var dt := ""
		if not nxt.is_empty():
			var dv := int(nxt.get(k, 0)) - val
			if dv > 0:
				dt = "+" + _stat_text(k, dv)
		(cell["delta"] as Label).text = dt


## First-session guidance. Level up this hero when the guide wants it (the pass is marked in
## _refresh_level); when another team hero should be leveled, point at PREV / NEXT toward them or at
## BACK (the roster rings them). Any other step happens elsewhere and the nav is hidden here, so
## point at LOBBY.
func _refresh_guide() -> void:
	var step := Guide.step()
	var target := Guide.level_target() if step == "level" else ""
	var away := target != "" and target != _id and not Guide.should_level(_id)
	var dir := 0
	if away and _browse.has(target) and _browse.has(_id) and _arrows.size() == 2:
		var n := _browse.size()
		var fwd := (_browse.find(target) - _browse.find(_id) + n) % n
		dir = 1 if fwd <= n / 2 else -1
	for i in _arrows.size():
		Guide.mark(_arrows[i], away and dir == (-1 if i == 0 else 1), 0)
	if _back_btn:
		Guide.mark(_back_btn, away and dir == 0, 1)
	if _home_btn:
		Guide.mark(_home_btn, step in ["claim", "summon", "formation", "battle"], 0)


func _refresh_level(level: int, cap: int) -> void:
	var cost := Game.level_up_cost(_id)
	if cost.is_empty():
		Guide.mark(_lvl_btn, false)
		_pass.set_text("LEVEL UP // CAP REACHED", "LV %d" % level, "STAR UP TO RAISE THE CAP" if level >= cap else "", "MAXED", "LV %d / %d" % [level, cap])
		_pass.set_live(false)
		_pass.set_knob("MAX", "", false)
		return
	_pass.set_live(true)
	# First-session guidance: level up team heroes (see _refresh_guide for the others).
	Guide.mark(_lvl_btn, Guide.should_level(_id))
	var parts: Array[String] = []
	var short := false
	for cid: String in ["gold", "hero_exp"]:
		if cost.has(cid):
			var amt := int(cost[cid])
			parts.append("%s %s" % ["GOLD" if cid == "gold" else "EXP", Kit.format_full(amt)])
			short = short or Kit.have(cid) < amt
	for cid: Variant in cost.keys():
		if str(cid) != "gold" and str(cid) != "hero_exp":
			parts.append("%s %s" % [str(cid).to_upper(), Kit.format_full(int(cost[cid]))])
			short = short or Kit.have(str(cid)) < int(cost[cid])
	var gain := ""
	var nxt := Game.hero_stats_at(_id, level + 1, int(Game.hero(_id).get("stars", 1)))
	var st := Game.hero_stats(_id)
	var g: Array[String] = []
	for k: String in ["hp", "atk"]:
		var dv := int(nxt.get(k, 0)) - int(st.get(k, 0))
		if dv > 0:
			g.append("+%s %s" % [Kit.format_full(dv), str(Kit.STAT_SHORT.get(k, k)).to_upper()])
	gain = "  ".join(g)
	_pass.set_text("LEVEL UP // HOLD TO REPEAT", "LV %d > %d" % [level, level + 1], ("  ·  ".join(parts)) + ("  ·  SHORT" if short else ""),
		"LEVEL UP  >>>", gain, SHORT if short else PK.ETCH)
	var n := int(Game.affordable_levels(_id))
	_pass.set_knob("MAX", "+%d" % n if n >= 2 else "", n >= 2)


func _refresh_stars(stars: int) -> void:
	var c := Game.star_up_cost(_id)
	if c.is_empty() and _legend:
		# Past max stars a Legendary's disc is her awakening: tap for the legend file.
		var ac := Game.awaken_cost(_id)
		if ac.is_empty():
			_star_stamp.set("label", "ASCENDED · AWAKENED A3 · LEGEND · ")
			_star_stamp.set("value", "A3")
		else:
			_star_stamp.set("label", "AWAKEN · A%d · SHARDS %d/%d · " % [int(ac.tier), mini(int(ac.shards_have), int(ac.shards)), int(ac.shards)])
			_star_stamp.set("value", "A%d" % _aw)
		_star_btn.disabled = false
		_star_stamp.queue_redraw()
		return
	if c.is_empty():
		_star_stamp.set("label", "STARS · MAXED · %d OF %d · " % [stars, Kit.MAX_STARS])
		_star_stamp.set("value", "%d★" % stars if Kit.font("wide_black").has_char(0x2605) else "%d/%d" % [stars, Kit.MAX_STARS])
		_star_btn.disabled = true
	else:
		var need := int(c.shards)
		var have := int(c.shards_have)
		var dust := int(c.dust)
		var lab := "STAR UP · SHARDS %d/%d · " % [mini(have, need), need]
		if dust > 0:
			lab += "+%s DUST · " % Kit.format_full(dust)
		_star_stamp.set("label", lab)
		_star_stamp.set("value", "%d/%d" % [stars, Kit.MAX_STARS])
		_star_btn.disabled = false
	_star_stamp.queue_redraw()


## The abilities capsule on the poster: "/ ULTIMATE > ..." and "/ PASSIVE > ..." blocks.
func _refresh_capsule(stars: int) -> void:
	var sig := "%d|%s|%d" % [stars, _owned, _aw]
	if sig == _capsule_sig:
		return
	_capsule_sig = sig
	for c in _capsule.get_children():
		_capsule.remove_child(c)
		c.queue_free()
	var cs := _capsule.size
	var pill := Panel.new()
	pill.mouse_filter = MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = MATTE
	sb.border_color = INK
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(int(cs.y * 0.5))
	sb.shadow_color = Color(0, 0, 0, 0.18)
	sb.shadow_size = 8
	sb.shadow_offset = Vector2(0, 3)
	pill.add_theme_stylebox_override("panel", sb)
	pill.size = cs
	_capsule.add_child(pill)
	var lw := cs.x * 0.47
	var ult: Dictionary = _def.get("ultimate", {})
	PK.at(_capsule, PK.t("/ ULTIMATE", 11, INK, "mono_bold"), Vector2(30, 18))
	var un := PK.t("> " + str(ult.get("name", "")).to_upper(), 13, INK, "mono_bold")
	un.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	un.size = Vector2(lw - 34, 0)
	PK.at(_capsule, un, Vector2(30, 36))
	PK.at(_capsule, PK.t("TAP FOR THE FULL FILE", 9, Color(INK, 0.5), "mono"), Vector2(30, cs.y - 30))
	PK.rule(_capsule, Vector2(lw, 16), Vector2(1, cs.y - 32), INK)
	var y := 16.0
	for pas: Dictionary in _def.get("passives", []):
		var on := _owned and stars >= int(pas.unlock_stars)
		var col := INK if on else Color(INK, 0.45)
		PK.at(_capsule, PK.t("/ PASSIVE  %d★" % int(pas.unlock_stars) if Kit.font("mono_bold").has_char(0x2605) else "/ PASSIVE  %d STARS" % int(pas.unlock_stars), 10, col, "mono_bold"), Vector2(lw + 12, y))
		var pn := PK.t("> " + str(pas.name).to_upper() + ("" if on else "  (LOCKED)"), 12, col, "mono_bold")
		pn.size = Vector2(cs.x - lw - 30, 16)
		pn.clip_text = true
		PK.at(_capsule, pn, Vector2(lw + 12, y + 15))
		y += 42.0
	if _legend:
		# Her legend passive (A1), in deep gold once awakened.
		var lp: Dictionary = (_def.legend as Dictionary).get("passive", {})
		var on2 := _owned and _aw >= 1
		var col2 := LegendKit.GOLD_DEEP if on2 else Color(INK, 0.45)
		PK.at(_capsule, PK.t("/ LEGEND  ·  A1", 10, col2, "mono_bold"), Vector2(lw + 12, y))
		var ln := PK.t("> " + str(lp.get("name", "")).to_upper() + ("" if on2 else "  (LOCKED)"), 12, col2, "mono_bold")
		ln.size = Vector2(cs.x - lw - 30, 16)
		ln.clip_text = true
		PK.at(_capsule, ln, Vector2(lw + 12, y + 15))
	var hb := _hit(_capsule, Rect2(Vector2.ZERO, cs), _jump.bind("legend" if _legend else "skills", true))
	hb.name = "CapsuleHit"
	Kit.add_press_fx(hb, pill)


# ------------------------------------------------------------------ sheet 02 (the file)

func _refresh_file() -> void:
	var sig := "%s|%s|%s|%s|%s|%s|%d" % [_owned, JSON.stringify(Game.hero(_id).get("gear", {})), JSON.stringify(Game.gear_items()),
		JSON.stringify(Game.skins_for(_id)), Game.currency("gems"), _preview, _aw]
	sig += str(Game.hero(_id).get("stars", 0))
	if sig == _file_sig:
		return
	_file_sig = sig
	for c in _file.get_children():
		_file.remove_child(c)
		c.queue_free()
	if _owned:
		_build_armament()
	_build_abilities()
	_build_wardrobe()
	var end := HBoxContainer.new()
	end.add_theme_constant_override("separation", 14)
	end.add_child(SignalKit.barcode(Vector2(150, 34), INK, (_id + "end").hash() & 0xffff))
	var et := PK.t("END OF FILE\n%s  ·  %s" % [_code(), _print_date()], 11, INK, "mono_bold")
	et.size_flags_horizontal = SIZE_EXPAND_FILL
	end.add_child(et)
	end.add_child(PK.t(str(_def.get("name", _id)), 40, INK, "serif_italic"))
	_file.add_child(Kit.spacer(0, 10))
	_file.add_child(end)
	_fit_file.call_deferred()


## A section head in the file: "/ NAME", a hairline to the edge, a note on the right.
func _section(key: String, title_text: String, note: String) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	v.set_meta("section", key)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	head.mouse_filter = MOUSE_FILTER_IGNORE
	var t := PK.t("/ " + title_text, 15, INK, "mono_bold")
	head.add_child(t)
	var r := ColorRect.new()
	r.color = Color(INK, 0.5)
	r.custom_minimum_size = Vector2(0, 1)
	r.size_flags_horizontal = SIZE_EXPAND_FILL
	r.size_flags_vertical = SIZE_SHRINK_CENTER
	head.add_child(r)
	head.add_child(PK.t(note, 12, Color(INK, 0.6), "mono"))
	v.add_child(head)
	_file.add_child(v)
	return v


func _build_armament() -> void:
	var hg: Dictionary = Game.hero(_id).get("gear", {})
	var worn := 0
	for slot: String in SLOTS:
		if str(hg.get(slot, "")) != "":
			worn += 1
	var v := _section("equip", "ARMAMENT", "%d / 4 FITTED" % worn)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var any_better := false
	var side := floorf((_file.custom_minimum_size.x - 30.0) / 4.0)
	for slot: String in SLOTS:
		var uid := str(hg.get(slot, ""))
		var item := Game.gear_item(uid) if uid != "" else {}
		var s := slot
		var better := _better_loose(slot, uid)
		any_better = any_better or better
		row.add_child(_gear_slot(slot, item, side, better, func() -> void: _open_gear_picker(s)))
	v.add_child(row)
	var acts := HBoxContainer.new()
	acts.add_theme_constant_override("separation", 12)
	var q := _pill_button("QUICK EQUIP", _on_auto_equip, any_better)
	q.name = "QuickEquip"
	var u := _pill_button("UNEQUIP ALL", _on_unequip_all, false)
	u.name = "UnequipAll"
	u.disabled = worn == 0
	for b: Button in [q, u]:
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		acts.add_child(b)
	v.add_child(acts)


## A gear slot printed as a framed square: tier numeral, the slot glyph, its stat line under it; a
## status light when a better unworn piece waits. Tap opens the picker.
func _gear_slot(slot: String, item: Dictionary, side: float, better: bool, cb: Callable) -> Button:
	var b := Button.new()
	b.name = "Equip_" + slot
	b.theme_type_variation = &"BareButton"
	b.focus_mode = FOCUS_NONE
	b.mouse_filter = MOUSE_FILTER_PASS
	b.custom_minimum_size = Vector2(side, side + 44)
	var face := Control.new()
	face.mouse_filter = MOUSE_FILTER_IGNORE
	face.size = Vector2(side, side + 44)
	b.add_child(face)
	var empty := item.is_empty()
	PK.rect(face, Rect2(0, 0, side, side), MATTE)
	var fr := PK.Frame.new()
	fr.size = Vector2(side, side)
	face.add_child(fr)
	# A worn piece shows its own render (tools/blender/gear_objects.py); an empty slot its faint glyph.
	var art: Texture2D = null
	if not empty:
		var nm0 := str(item.get("name", ""))
		var path := "res://assets/art/ui/gear/%s_%d.png" % [nm0.get_slice(" ", nm0.get_slice_count(" ") - 1).to_lower(),
			clampi(int(item.get("tier", 1)), 1, 5)]
		if ResourceLoader.exists(path):
			art = load(path) as Texture2D
	if art:
		var tr := TextureRect.new()
		tr.texture = art
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.mouse_filter = MOUSE_FILTER_IGNORE
		tr.position = Vector2(side * 0.1, side * 0.14)
		tr.size = Vector2(side * 0.8, side * 0.72)
		face.add_child(tr)
	else:
		var ic := Kit.icon("gear_" + slot, side * 0.46, Color(INK, 0.22 if empty else 0.92))
		ic.position = Vector2(side * 0.27, side * 0.27)
		ic.size = Vector2(side * 0.46, side * 0.46)
		face.add_child(ic)
	PK.at(face, PK.t(str(Kit.GEAR_SLOT_NAMES.get(slot, slot)).to_upper(), 10, Color(INK, 0.6), "mono_bold"), Vector2(8, 6))
	if empty:
		PK.at(face, PK.t("+ EMPTY", 11, Color(INK, 0.55), "mono_bold"), Vector2(8, side - 22))
	else:
		var tier := int(item.get("tier", 1))
		var tl := PK.t(Kit.roman(tier), 34, INK, "compressed")
		tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		tl.size = Vector2(60, 40)
		PK.at(face, tl, Vector2(side - 70, side - 46))
	var st := PK.t(_gear_stat_text(item, true) if not empty else "—", 11, INK, "mono_bold")
	st.size = Vector2(side, 16)
	st.clip_text = true
	PK.at(face, st, Vector2(2, side + 8))
	var nm := PK.t(str(item.get("name", "")).to_upper() if not empty else "", 9, Color(INK, 0.6), "mono")
	nm.size = Vector2(side, 14)
	nm.clip_text = true
	PK.at(face, nm, Vector2(2, side + 26))
	if better:
		var led := HUD.Led.new()
		led.size = Vector2(18, 18)
		led.mode = "breathe"
		led.position = Vector2(side - 24, 6)
		face.add_child(led)
	Kit.add_press_fx(b, face)
	Kit._connect_pressed(b, cb)
	return b


## A printed pill button: an outlined capsule (signal fill when `hot`) inside an 88 px target.
func _pill_button(text: String, cb: Callable, hot: bool, h: float = 88.0) -> Button:
	var b := Button.new()
	b.theme_type_variation = &"BareButton"
	b.focus_mode = FOCUS_NONE
	b.mouse_filter = MOUSE_FILTER_PASS
	b.custom_minimum_size = Vector2(120, h)
	var pill := Panel.new()
	pill.name = "Pill"
	pill.mouse_filter = MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = SIG if hot else Color(MATTE, 0.0)
	sb.border_color = SIG if hot else INK
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(28)
	pill.add_theme_stylebox_override("panel", sb)
	pill.anchor_right = 1.0
	pill.anchor_bottom = 1.0
	pill.offset_top = (h - 56.0) * 0.5
	pill.offset_bottom = -(h - 56.0) * 0.5
	b.add_child(pill)
	var l := PK.t(text, 15, Color.WHITE if hot else INK, "mono_bold")
	l.name = "Text"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	pill.add_child(l)
	b.draw.connect(func() -> void: pill.modulate.a = 0.4 if b.disabled else 1.0)
	Kit.add_press_fx(b, pill)
	Kit._connect_pressed(b, cb)
	return b


func _build_abilities() -> void:
	var stars := int(Game.hero(_id).get("stars", Kit.RARITY_STARS.get(str(_def.rarity), 1)))
	var passives: Array = _def.get("passives", [])
	var on_n := 0
	for pas: Dictionary in passives:
		if _owned and stars >= int(pas.unlock_stars):
			on_n += 1
	var total := 1 + passives.size()
	if _legend:
		total += 2
		on_n += (1 if _owned and _aw >= 1 else 0) + (1 if _owned and _aw >= 2 else 0)
	var v := _section("skills", "ABILITIES", "%d / %d ACTIVE" % [1 + on_n, total])
	var cap := PanelContainer.new()
	cap.mouse_filter = MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = MATTE
	sb.border_color = INK
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(44)
	sb.content_margin_left = 34
	sb.content_margin_right = 34
	sb.content_margin_top = 26
	sb.content_margin_bottom = 26
	cap.add_theme_stylebox_override("panel", sb)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	cap.add_child(col)
	var ult: Dictionary = _def.get("ultimate", {})
	col.add_child(_ability("/ ULTIMATE  ·  TAP HER PORTRAIT IN BATTLE", str(ult.get("name", "")), str(ult.get("description", "")), true))
	for pas: Dictionary in passives:
		var on := _owned and stars >= int(pas.unlock_stars)
		var head := "/ PASSIVE  ·  UNLOCKED" if on else "/ PASSIVE  ·  UNLOCKS AT %d STARS" % int(pas.unlock_stars)
		col.add_child(_ability(head, str(pas.name), str(pas.description), on))
	if _legend:
		var lg: Dictionary = _def.legend
		for i in 2:
			var part: Dictionary = lg.get("passive" if i == 0 else "ult_bonus", {})
			var on3 := _owned and _aw >= i + 1
			var kind := "LEGEND PASSIVE" if i == 0 else "EMPOWERED ULTIMATE"
			var head3 := "/ %s  ·  %s" % [kind, "AWAKENED" if on3 else "UNLOCKS AT AWAKENING A%d" % (i + 1)]
			col.add_child(_ability(head3, str(part.get("name", "")), str(part.get("description", "")), on3))
	v.add_child(cap)


func _ability(head: String, title_text: String, desc: String, on: bool) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = MOUSE_FILTER_IGNORE
	var col := INK if on else Color(INK, 0.45)
	v.add_child(PK.t(head, 11, SIG if on and head.begins_with("/ ULTIMATE") else col, "mono_bold"))
	var t := PK.t("> " + title_text.to_upper(), 17, col, "mono_bold")
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(t)
	var d := PK.t(desc, 15, col, "regular")
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(d)
	return v


## Skins (cosmetic, docs/dev/skins.md): her base look plus each skin with Try on / Back to equipped
## and Wear / Equipped / Buy (gems, confirmed) / Coming soon (art not built yet).
func _build_wardrobe() -> void:
	var skins := Game.skins_for(_id)
	var v := _section("skins", "WARDROBE", "%d LOOKS" % (1 + skins.size()))
	var eq := Game.equipped_skin(_id)
	v.add_child(_skin_row("", "Base look", str(_def.get("title", "")).to_upper(), "", eq == "", true, true, 0))
	var lines := SkinData.lines()
	for s in skins:
		var sub := ("%s  ·  %s" % [lines.get(str(s.line), str(s.line)), SkinData.tier_name(str(s.tier))]).to_upper()
		v.add_child(_skin_row(str(s.id), str(s.name), sub, str(s.description), bool(s.equipped), bool(s.owned),
			bool(s.installed), int(s.price_gems)))
	if not _owned:
		v.add_child(PK.t("Skins can be bought before she joins your team.", 14, Color(INK, 0.6), "regular"))


func _skin_row(sid: String, title: String, sub: String, desc: String, equipped: bool, owned: bool,
		installed: bool, price: int) -> Control:
	var row := HBoxContainer.new()
	row.name = "SkinRow_" + (sid if sid != "" else "base")
	row.add_theme_constant_override("separation", 16)
	var shown := _shown_skin() == sid and HeroArt.has_skin_art(_id, sid) or (sid == "" and _shown_skin() == "")
	var thumb := Control.new()
	thumb.mouse_filter = MOUSE_FILTER_IGNORE
	thumb.custom_minimum_size = Vector2(128, 128)
	PK.rect(thumb, Rect2(0, 0, 128, 128), Color("dcdbd4"))
	var pic := HeroArt.make_portrait(_id, 124, sid)
	pic.mouse_filter = MOUSE_FILTER_IGNORE
	pic.position = Vector2(2, 2)
	thumb.add_child(pic)
	var fr := PK.Frame.new()
	fr.size = Vector2(128, 128)
	fr.color = SIG if shown else INK
	thumb.add_child(fr)
	thumb.size_flags_vertical = SIZE_SHRINK_BEGIN
	row.add_child(thumb)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 2)
	info.size_flags_horizontal = SIZE_EXPAND_FILL
	info.mouse_filter = MOUSE_FILTER_IGNORE
	info.add_child(PK.t(title.to_upper(), 40, INK, "compressed"))
	if sub != "":
		info.add_child(PK.t(sub, 11, Color(INK, 0.65), "mono_bold"))
	if desc != "":
		var d := PK.t(desc, 14, INK, "regular")
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(d)
	var acts := HBoxContainer.new()
	acts.add_theme_constant_override("separation", 10)
	if sid != "" and installed and not equipped:
		# Try on: show it on the poster without buying or wearing it (tap again to go back).
		var trying := _preview == sid
		var t := _pill_button("BACK TO EQUIPPED" if trying else "TRY ON", func() -> void: _try_on("" if trying else sid), false)
		t.name = "TryOn_" + sid
		t.size_flags_horizontal = SIZE_EXPAND_FILL
		acts.add_child(t)
	var b: Button
	if equipped:
		b = _pill_button("EQUIPPED", Callable(), false)
		b.disabled = true
	elif owned:
		b = _pill_button("WEAR", func() -> void: _wear_skin(sid), true)
	elif not installed:
		b = _pill_button("COMING SOON", Callable(), false)
		b.disabled = true
	else:
		b = _pill_button("BUY  ·  %s GEMS" % Kit.format_full(price), func() -> void: _buy_skin(sid), Game.currency("gems") >= price)
	b.size_flags_horizontal = SIZE_EXPAND_FILL
	acts.add_child(b)
	info.add_child(acts)
	row.add_child(info)
	return row


## The skin on the poster: the one being tried on, else the equipped one.
func _shown_skin() -> String:
	return _preview if _preview != "" and HeroArt.has_skin_art(_id, _preview) else Game.equipped_skin(_id)


func _try_on(sid: String) -> void:
	_preview = sid
	_rebuild_sprite()
	_file_sig = ""          # redraw the rows (Try on / Back to equipped)
	_refresh_file.call_deferred()
	if sid != "":
		_jump("poster", true)


func _wear_skin(sid: String) -> void:
	_preview = ""
	var r := Game.equip_skin(_id, sid)
	if not bool(r.get("ok", false)):
		UI.toast(str(r.get("error", "Could not equip")), "bad")


func _buy_skin(sid: String) -> void:
	var sd := SkinData.get_def(sid)
	if sd.is_empty():
		return
	UI.confirm("Buy %s for %s gems? Skins are cosmetic: no stat changes." % [sd.name, Kit.format_full(int(sd.price_gems))],
		func() -> void:
			var r := Game.buy_skin(sid)
			if not bool(r.get("ok", false)):
				UI.toast(str(r.get("error", "Purchase failed")), "bad")
				return
			_preview = ""
			Game.equip_skin(_id, sid),
		Callable(), "Buy")


## Replace the sprite with one in the shown skin (or the base look).
func _rebuild_sprite() -> void:
	if _anchor == null:
		return
	if _sprite and is_instance_valid(_sprite):
		_anchor.remove_child(_sprite)
		_sprite.queue_free()
	_sprite_skin = _shown_skin()
	_sprite_key = HeroArt.art_key(_id, _sprite_skin)
	_sprite = HeroArt.make_sprite(_id, _sprite_skin)
	_anchor.add_child(_sprite)
	_fit_sprite()


## True when an unworn item of this slot beats what the hero wears.
func _better_loose(slot: String, worn_uid: String) -> bool:
	var cur := Game.gear_score(worn_uid) if worn_uid != "" else -1
	for it: Dictionary in Game.gear_items():
		if str(it.slot) == slot and str(it.get("equipped_by", "")) == "" and Game.gear_score(str(it.uid)) > cur:
			return true
	return false


## "+56 ATK", or every stat ("+56 ATK  +3% CRIT").
func _gear_stat_text(item: Dictionary, short: bool) -> String:
	var parts: Array[String] = []
	var st: Dictionary = item.get("stats", {})
	for k: String in ["atk", "hp", "def", "spd", "crit"]:
		if not st.has(k):
			continue
		parts.append("+%s %s" % [_stat_text(k, int(st[k])), str(Kit.STAT_SHORT.get(k, k.to_upper()))])
		if short:
			break
	return "  ".join(parts)


# ------------------------------------------------------------------ actions

func _browse_step(dir: int) -> void:
	var i := _browse.find(_id)
	if i < 0 or _browse.size() < 2:
		return
	var n := _browse[(i + dir + _browse.size()) % _browse.size()]
	# _dir: the next hero slides in from the side the arrow points to.
	UI.go("hero_detail", {"hero_id": n, "browse": Array(_browse), "_dir": dir})


## Tapping her: the shared HeroReact (burst, camera punch, expression, a pose that changes tap by tap).
func _poke_hero() -> void:
	if _sprite == null or not is_instance_valid(_sprite):
		return
	var now := Time.get_ticks_msec() / 1000.0
	_tap_n = HeroReact.next_count(_tap_n, now - _tap_at)
	_tap_at = now
	var at := _poke.position + _poke.get_local_mouse_position()
	_victory_left = HeroReact.react(_sheet, _sprite, _anchor, at, _tap_n, _poster)
	if _tap_n >= 4:
		_tap_n = 0


func _process(delta: float) -> void:
	if _victory_left > 0.0:
		_victory_left -= delta
		if _victory_left <= 0.0 and _sprite and is_instance_valid(_sprite):
			_sprite.call("play_idle")
	if not _holding:
		return
	if _lvl_btn == null or not _lvl_btn.is_pressed():
		_end_hold()
		return
	var down: Variant = _lvl_btn.get_meta("_down_at") if _lvl_btn.has_meta("_down_at") else null
	if down is Vector2 and (down as Vector2).distance_to(_lvl_btn.get_global_mouse_position()) > 36.0:
		_end_hold()
		return
	_hold_t += delta
	if _hold_t >= _hold_next:
		_hold_count += 1
		if _do_level(1, true):
			_hold_gained += 1
			_hold_next = _hold_t + maxf(HOLD_MIN, HOLD_START * pow(0.86, _hold_count))
		else:
			_end_hold()


func _on_level_down() -> void:
	_holding = not _lvl_btn.disabled
	_hold_t = 0.0
	_hold_next = HOLD_DELAY
	_hold_count = 0
	_hold_gained = 0


func _end_hold() -> void:
	if not _holding:
		return
	_holding = false
	if _hold_gained > 0:
		UI.sfx("reward")
		_celebrate_level(_hold_gained)


func _on_level_tap() -> void:
	if _hold_count > 0:
		return # the hold already did the work
	if _do_level(1, false):
		UI.sfx("reward")
		_celebrate_level(1)


func _on_level_max() -> void:
	var n := int(Game.affordable_levels(_id))
	if n <= 0:
		UI.toast("Not enough gold or hero EXP", "bad")
		return
	var r := Game.level_up_many(_id, n)
	if not bool(r.get("ok", false)):
		UI.toast(str(r.get("error", "Can't level up")), "bad")
		return
	UI.sfx("reward")
	UI.haptic(20)
	_celebrate_level(int(r.value.get("levels_gained", n)))


## One level-up attempt. quiet = part of a hold (no toast on failure, just stop).
func _do_level(n: int, quiet: bool) -> bool:
	var r := Game.level_up_many(_id, n)
	if bool(r.get("ok", false)):
		if quiet:
			UI.sfx("tap")
			_burst(0.55)
		return true
	if not quiet or _hold_gained == 0:
		UI.toast(str(r.get("error", "Can't level up")), "bad")
		if _pass:
			Kit.shake(_pass, 8)
	return false


func _on_star_up() -> void:
	var c := Game.star_up_cost(_id)
	if c.is_empty() and _legend:
		_jump("legend", true)
		return
	if c.is_empty():
		return
	if not Game.can_star_up(_id):
		UI.toast("Not enough shards or dust", "bad")
		if _star_disc:
			Kit.shake(_star_disc, 8)
		return
	var run := func() -> void:
		var before := int(Game.hero(_id).get("stars", 1))
		var r := Game.star_up(_id)
		if not bool(r.get("ok", false)):
			UI.toast(str(r.get("error", "Can't star up")), "bad")
			return
		_celebrate_star(before + 1)
	if int(c.dust) > 0:
		UI.confirm("Use %s dust to cover %d missing shards and raise %s to %d stars?" % [
			Kit.format_full(int(c.dust)), int(c.shards) - int(c.shards_used), str(_def.name), int(Game.hero(_id).get("stars", 1)) + 1],
			run, Callable(), "Star Up")
	else:
		run.call()


func _on_auto_equip() -> void:
	var before := JSON.stringify(Game.hero(_id).get("gear", {}))
	Game.auto_equip(_id)
	if JSON.stringify(Game.hero(_id).get("gear", {})) == before:
		UI.toast("Already wearing the best gear available")
	else:
		UI.sfx("reward")
		UI.toast("Equipped the best gear", "good")
		_burst(0.7)


func _on_unequip_all() -> void:
	var hg: Dictionary = Game.hero(_id).get("gear", {})
	var n := 0
	for slot: String in SLOTS:
		if str(hg.get(slot, "")) != "":
			Game.unequip(_id, slot)
			n += 1
	if n > 0:
		UI.toast("Took off %d piece%s of gear" % [n, "" if n == 1 else "s"])


func _open_gear_picker(slot: String) -> void:
	if not _owned:
		return
	var items: Array[Dictionary] = []
	for it: Dictionary in Game.gear_items():
		if str(it.slot) == slot:
			items.append(it)
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var sa := Game.gear_score(str(a.uid))
		var sb := Game.gear_score(str(b.uid))
		return sa > sb if sa != sb else str(a.uid) < str(b.uid))
	var worn := str(Game.hero(_id).get("gear", {}).get(slot, ""))
	var list := Kit.vbox(8)
	if worn != "":
		list.add_child(Kit.label("EQUIPPED", 18, Kit.ACCENT_DEEP, "cond_bold"))
		list.add_child(_gear_pick_row(Game.gear_item(worn), true, -1))
	var cur := Game.gear_score(worn) if worn != "" else -1
	var others := 0
	for it in items:
		if str(it.uid) == worn:
			continue
		if others == 0:
			list.add_child(Kit.label("IN THE BAG", 18, Kit.TEXT_DIM, "cond_bold"))
		others += 1
		list.add_child(_gear_pick_row(it, false, cur))
	if others == 0:
		var es := Kit.empty_state("No other %s yet. Gear drops from the Sanctum and campaign stages." % str(Kit.GEAR_SLOT_NAMES.get(slot, slot)).to_lower(), "gear_" + slot, true)
		es.custom_minimum_size.y = 200
		list.add_child(es)
	var content: Control = list
	var rows := others + (1 if worn != "" else 0)
	if rows > 4:
		var sc := Kit.scroll(list)
		sc.custom_minimum_size = Vector2(560, minf(rows * 124.0 + 40.0, get_viewport_rect().size.y * 0.6))
		content = sc
	else:
		list.custom_minimum_size.x = 560
	_gear_modal = UI.popup(str(Kit.GEAR_SLOT_NAMES.get(slot, slot)), content, Callable(), 620.0, true)


func _gear_pick_row(it: Dictionary, worn_here: bool, cur_score: int) -> Control:
	var card := Kit.panel("row", 10)
	var row := Kit.hbox(12)
	card.add_child(row)
	row.add_child(Kit.equip_slot(str(it.slot), it, 96))
	var info := Kit.vbox(2)
	info.size_flags_horizontal = SIZE_EXPAND_FILL
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	var n := Kit.label(str(it.get("name", "Gear")), 24, Kit.TEXT, "extrabold")
	n.clip_text = true
	n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	info.add_child(n)
	var s := Kit.label(_gear_stat_text(it, false), 20, Color("1f9e63"), "cond_bold")
	s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(s)
	var meta := Kit.hbox(8)
	meta.mouse_filter = MOUSE_FILTER_IGNORE
	meta.add_child(Kit.tag("TIER %s" % Kit.roman(int(it.get("tier", 1))), Kit.tier_color(int(it.get("tier", 1))), Color.WHITE, 16))
	var score := Game.gear_score(str(it.uid))
	var sc_t := "SCORE %s" % Kit.format_full(score)
	if cur_score >= 0 and score != cur_score:
		sc_t += "  (%s%d)" % ["+" if score > cur_score else "", score - cur_score]
	meta.add_child(Kit.label(sc_t, 17, Kit.TEXT_DIM if cur_score < 0 or score <= cur_score else Color("1f9e63"), "cond_bold"))
	info.add_child(meta)
	var owner := str(it.get("equipped_by", ""))
	if owner != "" and not worn_here:
		info.add_child(Kit.label("Worn by %s" % str(Game.hero_def(owner).get("name", owner)), 18, Kit.ACCENT_DEEP, "bold"))
	row.add_child(info)
	var uid := str(it.uid)
	var slot := str(it.slot)
	var b: Button
	if worn_here:
		b = Kit.light_button("Remove", func() -> void:
			Game.unequip(_id, slot)
			_close_gear_modal())
	else:
		b = Kit.primary_button("Swap" if owner != "" else "Equip", func() -> void:
			var r := Game.equip(_id, uid)
			_close_gear_modal()
			if bool(r.get("ok", false)):
				UI.sfx("reward")
				_burst(0.6)
				if owner != "" and owner != _id:
					UI.toast("Taken from %s" % str(Game.hero_def(owner).get("name", owner)))
			else:
				UI.toast(str(r.get("error", "Can't equip")), "bad"))
	b.custom_minimum_size = Vector2(132, Kit.BUTTON_H)
	b.add_theme_font_size_override("font_size", 24)
	b.size_flags_vertical = SIZE_SHRINK_CENTER
	row.add_child(b)
	return card


func _close_gear_modal() -> void:
	if _gear_modal and is_instance_valid(_gear_modal):
		UI.close_modal(_gear_modal)
	_gear_modal = null


# ------------------------------------------------------------------ the Legendary page

## The LEGEND masthead on the matte line: LEGEND in foil, the three tier seals, her legend title.
func _build_masthead(w: float) -> void:
	var lg: Dictionary = _def.legend
	var word := LegendKit.foil_label("LEGEND", 86, "compressed", "deep", {"band_px": 220.0})
	word.name = "Masthead"
	var ww := PK.text_w("LEGEND", 86)
	PK.at(_sheet, word, Vector2(w - 22 - ww, 2))
	# Three small seals, lit up to her tier, left of the word.
	for i in 3:
		var sm := LegendKit.seal(i + 1, "lit" if _owned and _aw > i else "locked", 34.0)
		sm.mini = true
		PK.at(_sheet, sm, Vector2(w - 34 - ww - (3 - i) * 40.0, 34))
		if not (_owned and _aw > i):
			sm.modulate = Color(0.1, 0.1, 0.1, 0.5)
	var title := ("ASCENDED  ·  " if _aw >= 3 else "") + str(lg.get("title", "")).to_upper()
	var line := PK.t("%s  ·  A%d / 3  ·  %s" % [title, _aw, _code()], 12, Color(INK, 0.78), "mono_bold")
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	line.size = Vector2(w - 220, 16)
	PK.at(_sheet, line, Vector2(198, 92))
	LegendKit.foil_rect(_sheet, Rect2(198, 114, w - 220, 2), 0, {"band_px": 200.0}, "deep").name = "MastRule"


## Once she has awakened, a gold aura printed behind her (and her name): stronger, with rays, when
## she has Ascended.
func _build_legend_glow(p: Control, feet: Vector2, fig_h: float) -> void:
	var side := fig_h * (1.15 if _aw >= 3 else 0.95)
	var c := Vector2(feet.x + 10, feet.y - fig_h * 0.6)
	var holder := Control.new()
	holder.name = "LegendGlow"
	holder.mouse_filter = MOUSE_FILTER_IGNORE
	holder.clip_contents = true
	holder.position = Vector2(BAND, 0)
	holder.size = Vector2(p.size.x - BAND - RULE_IN, p.size.y)
	p.add_child(holder)
	if _aw >= 3:
		var r := LegendKit.rays(side * 1.3, 0.16)
		r.position = c - Vector2(BAND, 0) - r.size * 0.5
		holder.add_child(r)
	var a := LegendKit.aura(Vector2(side, side), 0.66 if _aw >= 3 else 0.44)
	a.position = c - Vector2(BAND, 0) - a.size * 0.5
	holder.add_child(a)


## Behind her on the poster: her faction's growth round the figure (a corner by the dossier data, one
## at her feet).
func _build_legend_figure(feet: Vector2, pw: float, ph: float) -> void:
	var faction := str(_def.get("faction", "celestial"))
	var ppu := clampf(pw / 11.5, 46.0, 64.0)
	var g1 := PhysicalKit.growth(faction, "tr", _box, Vector2(pw - RULE_IN - 30.0, 250.0), ppu)
	var g2 := PhysicalKit.growth(faction, "bl", _box, Vector2(BAND - 18.0, ph - 4.0), ppu * 1.08)
	for g: Control in [g1, g2]:
		if g:
			g.name = "Growth"


## Paints the giant name's two copies (the band's and the paper's) in foil.
func _foil_giant(host: Node) -> void:
	var i := 0
	for clip in host.get_children():
		for rt in clip.get_children():
			if rt is RichTextLabel:
				(rt as RichTextLabel).add_theme_color_override("default_color", Color.WHITE)
				rt.material = LegendKit.foil_material(0, "gold" if i == 0 else "ink", {"band_px": 520.0})
		i += 1


## The Ascended crown stamp, pressed onto the poster beside her name.
func _stamp_crown(pr: Rect2, name_y: float, fs: int) -> void:
	var st := LegendKit.CrownStamp.new()
	st.label = "ASCENDED · %s · " % str(_def.legend.get("title", "")).to_upper()
	st.size = Vector2(150, 150)
	st.pivot_offset = st.size * 0.5
	st.rotation = -0.22
	st.name = "CrownStamp"
	# On the open paper between the stat row and her name, left of the dossier lines.
	st.position = pr.position + Vector2(BAND + 22.0, clampf(name_y - 150.0, 116.0, 220.0))
	_sheet.add_child(st)


## Sheet 02 of a Legendary: the LEGEND FILE on dark felt (built once; its height never changes).
func _build_legend_sheet() -> void:
	var pw := _w - 36.0
	# The sheet first (its print goes on in the tree: labels only know their fonts there), then cut to
	# the printed height.
	_legend_sheet = PhysicalKit.sheet(_sheet, Rect2(18, _sheet_h + 26.0, pw, 2000.0), LegendKit.FELT, 0.34, {"relief": false})
	_legend_sheet.name = "LegendSheet"
	var body := Control.new()
	body.name = "LegendBody"
	body.mouse_filter = MOUSE_FILTER_IGNORE
	_legend_sheet.add_child(body)
	_legend_h = _fill_legend(body, pw)
	body.size = Vector2(pw, _legend_h)
	_legend_sheet.size.y = _legend_h
	var holder: Control = _legend_sheet.get_meta("shadow")
	holder.size.y = _legend_h
	var paper: ColorRect = _legend_sheet.get_meta("paper")
	paper.size = _legend_sheet.size + Vector2(PhysicalKit.MARGIN, PhysicalKit.MARGIN) * 2.0
	(paper.material as ShaderMaterial).set_shader_parameter("rect_size", paper.size)
	_legend_body = body
	_legend_sig = _legend_state_sig()


func _legend_state_sig() -> String:
	var h := Game.hero(_id)
	return "%s|%d|%d|%d|%d" % [_owned, _aw, int(h.get("stars", 0)), int(h.get("shards", 0)), Game.currency("dust")]


## Game changed: a new tier rebuilds the page (the awakening animation does it under its flash);
## new shards or dust reprint the legend file.
func _refresh_legend() -> void:
	if _legend_sheet == null:
		return
	var now := int(Game.awaken_tier(_id))
	if now != _aw:
		if not _awaken_pending and not (_awaken_fx and is_instance_valid(_awaken_fx)):
			_rebuild.call_deferred()
		return
	var sig := _legend_state_sig()
	if sig == _legend_sig:
		return
	_legend_sig = sig
	var body := Control.new()
	body.name = "LegendBody"
	body.mouse_filter = MOUSE_FILTER_IGNORE
	var at := _legend_body.get_index()
	_legend_sheet.remove_child(_legend_body)
	_legend_body.queue_free()
	_legend_sheet.add_child(body)
	_legend_sheet.move_child(body, at)
	var h := _fill_legend(body, _legend_sheet.size.x)
	body.size = Vector2(_legend_sheet.size.x, h)
	_legend_body = body
	if absf(h - _legend_h) > 1.0:
		_rebuild.call_deferred()


## Prints the legend file into `b` (pw wide); returns its height.
func _fill_legend(b: Control, pw: float) -> float:
	var lg: Dictionary = _def.legend
	var nm := str(_def.get("name", _id)).to_upper()
	var x0 := LEGEND_STRIP + 26.0
	var cw := pw - x0 - 26.0
	var gold := Color(1.0, 0.84, 0.5)
	var dim := Color(PAPER, 0.38)
	_seals.clear()
	_aw_press = null
	_aw_btn = null
	# ---- The strip down the left: LEGEND turned, in foil, and her name in micro type.
	PK.rect(b, Rect2(0, 0, LEGEND_STRIP, 4000), Color("1f2024"))
	LegendKit.foil_rect(b, Rect2(LEGEND_STRIP - 2, 0, 2, 4000), 0, {"band_px": 400.0})
	var lw := LegendKit.foil_label("LEGEND", 168, "compressed", "gold", {"band_px": 420.0})
	lw.rotation = PI * 0.5
	PK.at(b, lw, Vector2(LEGEND_STRIP + 18, 22))
	var rep_t := PK.vlabel(("%s  ·  LEGEND FILE  ·  " % nm).repeat(10), 10, Color(PAPER, 0.3), "mono_bold")
	PK.at(b, rep_t, Vector2(14, 640))
	var y := 30.0
	# ---- Head: kicker, her legend title, her state.
	PK.at(b, PK.t("FILE 02 / 03  ·  LEGEND FILE  ·  %s" % _code(), 12, Color(PAPER, 0.6), "mono_bold"), Vector2(x0, y))
	y += 26.0
	var tt := str(lg.get("title", "")).to_upper()
	# One line, as big as fits (up to 64 px).
	var tfs := clampi(int(64.0 * cw / maxf(PK.text_w(tt, 64), 1.0)), 30, 64)
	var title: Label
	if _aw >= 3:
		title = LegendKit.foil_label(tt, tfs, "compressed", "gold", {"band_px": 300.0})
	else:
		title = PK.t(tt, tfs, PAPER, "compressed")
	PK.at(b, title, Vector2(x0, y))
	y += title.get_minimum_size().y + 2.0
	var state := "NOT YET SUMMONED" if not _owned else ("ASCENDED  ·  AWAKENED A3 OF 3" if _aw >= 3 else ("AWAKENED A%d OF 3" % _aw if _aw > 0 else "NOT YET AWAKENED"))
	var st_line := "%s  ·  %s  ·  %s ALL STATS" % [nm, state, LegendKit.bonus_text(_aw)] if _aw > 0 else "%s  ·  %s  ·  AWAKENS AT %d STARS" % [nm, state, EconomyData.AWAKEN_MIN_STARS]
	var stl := PK.t(st_line, 12, gold, "mono_bold")
	stl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stl.size = Vector2(cw, 0)
	PK.at(b, stl, Vector2(x0, y))
	y += stl.get_minimum_size().y + 16.0
	LegendKit.foil_rect(b, Rect2(x0, y, cw, 2), 0, {"band_px": 260.0})
	y += 26.0
	# ---- Awakening: three seals, the press.
	y = _legend_head(b, x0, y, cw, "AWAKENING", "TIER %d / 3" % _aw)
	var side := floorf(minf(150.0, (cw - 48.0) / 3.0))
	var gap := (cw - side * 3.0) / 2.0
	var cost := Game.awaken_cost(_id)
	for i in 3:
		var stt := "lit" if _owned and _aw > i else ("next" if _owned and _aw == i and not cost.is_empty() and bool(cost.stars_ok) else "locked")
		var sl := LegendKit.seal(i + 1, stt, side)
		sl.name = "Seal%d" % (i + 1)
		PK.at(b, sl, Vector2(x0 + i * (side + gap), y))
		_seals.append(sl)
		var cap := PK.t("%s\n%s" % [Kit.roman(i + 1), LegendKit.UNLOCKS[i]], 10, gold if stt == "lit" else (Color(PAPER, 0.75) if stt == "next" else dim), "mono_bold")
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cap.size = Vector2(side + gap * 0.8, 30)
		PK.at(b, cap, Vector2(x0 + i * (side + gap) - gap * 0.4, y + side + 8))
	y += side + 52.0
	_aw_press = PK.make_press(cw)
	_aw_press.name = "AwakenPress"
	_aw_btn = _aw_press.hit
	_aw_btn.name = "Awaken"
	_aw_btn.text = "Awaken"
	for k: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color", "font_hover_pressed_color"]:
		_aw_btn.add_theme_color_override(k, Color(0, 0, 0, 0))
	Kit._connect_pressed(_aw_btn, _on_awaken)
	PK.at(b, _aw_press, Vector2(x0, y))
	_print_press(cost)
	y += 190.0
	var how := PK.t("Shards come from her duplicates. Dust covers any missing shard (%d each)." % Progression.dust_per_shard("legendary"), 12, dim, "mono")
	how.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	how.size = Vector2(cw, 0)
	PK.at(b, how, Vector2(x0, y))
	y += how.get_minimum_size().y + 30.0
	# ---- Her two exclusive cards.
	y = _legend_head(b, x0, y, cw, "EXCLUSIVE", "LEGENDARY ONLY")
	for i in 2:
		var part: Dictionary = lg.get("passive" if i == 0 else "ult_bonus", {})
		y += _legend_card(b, Rect2(x0 - 4, y, cw + 8, 0), i, part) + 22.0
	y += 10.0
	# ---- The legend file: three lines, declassified one per tier.
	var lore: Array = lg.get("lore", [])
	y = _legend_head(b, x0, y, cw, "LEGEND FILE", "%d / %d DECLASSIFIED" % [mini(_aw, lore.size()) if _owned else 0, lore.size()])
	y += _lore_sheet(b, Rect2(x0 - 4, y, cw + 8, 0), lore) + 34.0
	# ---- End of the file.
	PK.rule(b, Vector2(x0, y), Vector2(cw, 1), Color(PAPER, 0.3))
	y += 18.0
	PK.at(b, SignalKit.barcode(Vector2(140, 30), Color(PAPER, 0.7), (_id + "legend").hash() & 0xffff), Vector2(x0, y))
	PK.at(b, PK.t("END OF LEGEND FILE\n%s  ·  %s" % [_code(), _print_date()], 11, Color(PAPER, 0.6), "mono_bold"), Vector2(x0 + 156, y))
	var sig := LegendKit.foil_label(str(_def.get("name", _id)), 50, "serif_italic", "gold", {"band_px": 200.0})
	sig.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sig.size = Vector2(240, 60)
	PK.at(b, sig, Vector2(x0 + cw - 240, y - 14))
	y += 72.0
	return y


## A section head on the felt: "/ NAME", a hairline, a note on the right. Returns the next y.
func _legend_head(b: Control, x0: float, y: float, cw: float, title_text: String, note: String) -> float:
	var t := PK.t("/ " + title_text, 15, PAPER, "mono_bold")
	PK.at(b, t, Vector2(x0, y))
	var tw := PK.text_w("/ " + title_text, 15, "mono_bold")
	var nt := PK.t(note, 11, Color(PAPER, 0.5), "mono")
	nt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	nt.size = Vector2(240, 16)
	PK.at(b, nt, Vector2(x0 + cw - 240, y + 3))
	var nw := PK.text_w(note, 11, "mono")
	PK.rule(b, Vector2(x0 + tw + 12, y + 10), Vector2(maxf(cw - tw - nw - 34, 10.0), 1), Color(PAPER, 0.3))
	return y + 38.0


## The AWAKEN press's readouts for the next tier (or the state when she can't).
func _print_press(cost: Dictionary) -> void:
	if _aw_press == null:
		return
	var h := Game.hero(_id)
	if not _owned:
		_aw_press.set_text("AWAKENING // LOCKED", "NOT SUMMONED", "SUMMON HER, THEN STAR HER TO %d" % EconomyData.AWAKEN_MIN_STARS, "AWAKEN", "")
		_aw_press.set_live(false)
		_aw_press.set_knob("", "", false)
		return
	if cost.is_empty():
		_aw_press.set_text("AWAKENING // COMPLETE", "ASCENDED", "EVERY SEAL IS LIT", "FULLY AWAKENED", "%s ALL STATS" % LegendKit.bonus_text(3))
		_aw_press.set_live(false)
		_aw_press.set_knob("A3", "", false)
		return
	var tier := int(cost.tier)
	var need := int(cost.shards)
	var have := mini(int(cost.shards_have), need)
	var gain := "%s ALL STATS  ·  %s" % [LegendKit.bonus_text(tier), LegendKit.UNLOCKS[tier - 1]]
	if not bool(cost.stars_ok):
		_aw_press.set_text("AWAKENING // NEEDS %d STARS" % int(cost.min_stars), "AWAKEN A%d" % tier,
			"STARS %d / %d  ·  STAR HER UP FIRST" % [int(h.get("stars", 1)), int(cost.min_stars)], "AWAKEN", gain)
		_aw_press.set_live(false)
		_aw_press.set_knob("A%d" % _aw, "", false)
		return
	var short := Game.currency("dust") < int(cost.dust)
	var sub := "SHARDS %d/%d  ·  DUST %s" % [have, need, Kit.format_full(int(cost.dust))]
	if need > have:
		sub += "  (+%d MISSING)" % (need - have)
	if short:
		sub += "  ·  SHORT"
	_aw_press.set_text("AWAKENING // TIER %s" % Kit.roman(tier), "AWAKEN A%d" % tier, sub, "AWAKEN  >>>", gain, SHORT if short else PK.ETCH)
	_aw_press.set_live(true)
	_aw_press.set_knob("A%d" % _aw, "", false)


## One exclusive card (0 legend passive, 1 empowered ultimate): a paper slip stuck on the felt, its
## foil rule and kicker, the name and the full text; locked: printed faint with a LOCKED stamp and
## what it needs. Returns its height.
func _legend_card(b: Control, r: Rect2, i: int, part: Dictionary) -> float:
	var on := _owned and _aw >= i + 1
	var tier := i + 1
	var ink := INK if on else Color(INK, 0.62)
	var w := r.size.x
	var tw := w - 56.0
	var kind := "LEGEND PASSIVE" if i == 0 else "EMPOWERED ULTIMATE"
	# Locked: what it takes (every tier still missing, in shards and base dust).
	var need_sh := 0
	var need_du := 0
	for t2 in range(_aw if _owned else 0, tier):
		need_sh += EconomyData.AWAKEN_SHARDS[t2]
		need_du += EconomyData.AWAKEN_DUST[t2]
	var need := "AWAKEN TO A%d  ·  %d SHARDS + %s DUST" % [tier, need_sh, Kit.format_full(need_du)]
	if not _owned:
		need = "SUMMON HER, STAR HER TO %d, " % EconomyData.AWAKEN_MIN_STARS + need
	elif int(Game.hero(_id).get("stars", 1)) < EconomyData.AWAKEN_MIN_STARS:
		need = "STAR HER TO %d, THEN " % EconomyData.AWAKEN_MIN_STARS + need
	var foot := "ACTIVE IN BATTLE" if on else need
	if i == 1:
		foot += "  ·  ADDS TO %s" % str((_def.get("ultimate", {}) as Dictionary).get("name", "")).to_upper()
	# The slip's lines, each sized to its width first (so its wrapped height is known).
	var lines: Array[Label] = [
		PK.t("/ %s  ·  A%d  ·  EXCLUSIVE" % [kind, tier], 11, SIG if on else ink, "mono_bold"),
		PK.t("> " + str(part.get("name", "")).to_upper(), 21, ink, "mono_bold"),
		PK.t(str(part.get("description", "")), 15, ink, "regular"),
		PK.t(foot, 10, Color(INK, 0.55), "mono_bold"),
	]
	var gaps: Array[float] = [4.0, 4.0, 10.0, 0.0]
	var h := 26.0
	for k in lines.size():
		var l := lines[k]
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.position = Vector2(28, h)
		# Clear of the seal (lit: the first two lines) or the LOCKED stamp (locked: three).
		l.set_meta("w", tw - (84.0 if k <= 1 or (k == 2 and not on) else 0.0))
		h += _measure(b, l, float(l.get_meta("w"))) + gaps[k]
	h += 26.0
	var card := PhysicalKit.sheet(b, Rect2(r.position, Vector2(w, h)), PAPER if on else Color("c9c8c2"), 0.4, {"relief": false, "shadow_r": 14.0})
	card.name = "LegendCard%d" % tier
	var holder: Control = card.get_meta("shadow")
	var rot := -0.012 if i == 0 else 0.009
	for c2: Control in [card, holder]:
		c2.pivot_offset = c2.size * 0.5
		c2.rotation = rot
	LegendKit.foil_rect(card, Rect2(Vector2.ZERO, Vector2(w, h)), 1, {"inset": 6.0, "frame_w": 2.0, "band_px": 260.0}, "deep" if on else "pale")
	for l in lines:
		# Width first, then into the tree (it wraps at that width as it enters).
		l.size = Vector2(float(l.get_meta("w")), 0)
		card.add_child(l)
	if on:
		var sm := LegendKit.seal(tier, "lit", 58.0)
		sm.mini = true
		PK.at(card, sm, Vector2(w - 74, 14))
	else:
		var stamp := SignalKit.stamp("LOCKED · AWAKEN A%d · " % tier, "A%d" % tier, 84)
		stamp.rotation = 0.2
		PK.at(card, stamp, Vector2(w - 100, 10))
	return h


## Height of label `l` wrapped at `width`, measured on a copy in the tree under `b` (a label only knows
## its font there); its line count goes in meta "lines".
func _measure(b: Control, l: Label, width: float) -> float:
	var m := l.duplicate() as Label
	m.size = Vector2(width, 0)
	b.add_child(m)
	var h := m.get_minimum_size().y
	l.set_meta("lines", m.get_line_count())
	b.remove_child(m)
	m.free()
	return h


## The legend file itself: a paper dossier page stuck on the felt, her three lore lines numbered;
## a line still classified is a black redaction bar the shape of its words, with the tier that
## declassifies it, and the page carries a CLASSIFIED stamp until all three are open. Returns its height.
func _lore_sheet(b: Control, r: Rect2, lore: Array) -> float:
	var w := r.size.x
	var tw := w - 56.0 - 58.0
	var parts: Array[Control] = []
	var y := 24.0
	var head := PK.t("DOSSIER  ·  EYES ONLY  ·  %s  ·  %s" % [_code(), str(_def.get("name", _id)).to_upper()], 10, Color(SIG, 0.9), "mono_bold")
	head.position = Vector2(28, y)
	parts.append(head)
	y += 26.0
	var closed := 0
	for i in lore.size():
		var open := _owned and _aw >= i + 1
		var num := PK.t("%02d" % (i + 1), 34, INK if open else Color(INK, 0.45), "compressed")
		num.position = Vector2(26, y - 6)
		parts.append(num)
		var l := PK.t(str(lore[i]), 21, INK, "serif_italic")
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var lh := _measure(b, l, tw)
		var lines := maxi(1, int(l.get_meta("lines", 1)))
		if open:
			l.position = Vector2(84, y)
			l.set_meta("w", tw)
			parts.append(l)
			y += lh + 18.0
			continue
		closed += 1
		l.free()
		# Redacted: one ink bar per line of words, the last one shorter.
		var line_h := lh / lines
		for k in lines:
			var bw := tw * (0.5 + 0.35 * float((i * 7 + k * 3) % 5) / 4.0) if k == lines - 1 else tw * (0.97 - 0.05 * float(k % 2))
			var bar := ColorRect.new()
			bar.mouse_filter = MOUSE_FILTER_IGNORE
			bar.color = Color("0b0b0c")
			bar.position = Vector2(84, y + k * line_h + line_h * 0.18)
			bar.size = Vector2(bw, line_h * 0.66)
			parts.append(bar)
		var tag := PK.t("CLASSIFIED  ·  DECLASSIFIED AT AWAKENING A%d" % (i + 1), 11, SIG, "mono_bold")
		tag.position = Vector2(84, y + lh + 2)
		parts.append(tag)
		y += lh + 34.0
	y += 8.0
	var page := PhysicalKit.sheet(b, Rect2(r.position, Vector2(w, y)), PAPER, 0.42, {"relief": false, "shadow_r": 14.0})
	page.name = "LegendLore"
	var holder: Control = page.get_meta("shadow")
	for c2: Control in [page, holder]:
		c2.pivot_offset = c2.size * 0.5
		c2.rotation = -0.006
	PK.rule(page, Vector2(70, 14), Vector2(1, y - 28), Color(SIG, 0.5))
	for c in parts:
		if c.has_meta("w"):
			c.size = Vector2(float(c.get_meta("w")), 0)
		page.add_child(c)
	if closed > 0:
		var st := SignalKit.stamp("CLASSIFIED · %d OF %d SEALED · " % [closed, lore.size()], "%d/%d" % [lore.size() - closed, lore.size()], 92)
		st.rotation = -0.25
		st.set("ink", Color(SIG, 0.85))
		PK.at(page, st, Vector2(w - 108, y - 104))
	return y


## AWAKEN: confirm the price, awaken, then the big moment.
func _on_awaken() -> void:
	if not _legend or not _owned:
		return
	var c := Game.awaken_cost(_id)
	if c.is_empty():
		UI.toast("%s is fully awakened" % str(_def.name))
		return
	if not bool(c.stars_ok):
		UI.toast("Awakening needs %d stars" % int(c.min_stars), "bad")
		if _aw_press:
			Kit.shake(_aw_press, 8)
		return
	if not Game.can_awaken(_id):
		UI.toast("Not enough shards or dust", "bad")
		if _aw_press:
			Kit.shake(_aw_press, 8)
		return
	var missing := int(c.shards) - int(c.shards_used)
	var msg := "Awaken %s to A%d? Uses %d shards and %s dust" % [str(_def.name), int(c.tier), int(c.shards_used), Kit.format_full(int(c.dust))]
	if missing > 0:
		msg += " (the dust covers %d missing shards)" % missing
	UI.confirm(msg + ".", _do_awaken, Callable(), "Awaken")


func _do_awaken() -> void:
	# The page reprints under the animation's flash, not as the save changes.
	_awaken_pending = true
	var r := Game.awaken(_id)
	if not bool(r.get("ok", false)):
		_awaken_pending = false
		UI.toast(str(r.get("error", "Can't awaken")), "bad")
		return
	_play_awaken_fx(int(r.value.get("awaken", 1)), true)


## The awakening animation over the whole screen; rebuild = reprint the page under its flash.
func _play_awaken_fx(tier: int, rebuild: bool, freeze_at: float = -1.0) -> void:
	if _awaken_fx and is_instance_valid(_awaken_fx):
		_awaken_fx.queue_free()
	var lg: Dictionary = _def.legend
	var fx := LegendKit.AwakenFx.new()
	fx.name = "AwakenFx"
	fx.hero_id = _id
	fx.skin = _shown_skin()
	fx.faction = str(_def.get("faction", "celestial"))
	fx.tier = tier
	fx.name_text = str(_def.get("name", _id))
	fx.title_text = str(lg.get("title", ""))
	match tier:
		1:
			fx.unlock_name = str((lg.get("passive", {}) as Dictionary).get("name", ""))
		2:
			fx.unlock_name = str((lg.get("ult_bonus", {}) as Dictionary).get("name", ""))
		_:
			fx.unlock_name = str(lg.get("title", ""))
	if rebuild:
		fx.midpoint = func() -> void:
			_awaken_pending = false
			_rebuild()
	fx.finished.connect(func() -> void:
		_awaken_fx = null
		if tier - 1 < _seals.size() and is_instance_valid(_seals[tier - 1]):
			Kit.pulse(_seals[tier - 1], 1.12))
	var host: Variant = UI.call("_modal_layer")
	if host is Control:
		(host as Control).add_child(fx)
	else:
		fx.top_level = true
		fx.z_index = 105
		add_child(fx)
	_awaken_fx = fx
	if freeze_at >= 0.0:
		fx.seek(freeze_at)
		fx.set_process(false)


func _debug_fx() -> void:
	await get_tree().create_timer(0.25).timeout
	if is_inside_tree() and not _fx_params.is_empty():
		_play_awaken_fx(int(_fx_params.tier), false, float(_fx_params.at))


# ------------------------------------------------------------------ celebration

func _hero_point() -> Vector2:
	if _sprite and is_instance_valid(_sprite):
		var gp: Vector2 = _sprite.call("get_point", "chest")
		var local := gp - _fx.global_position
		if local.y > 40.0 and local.y < size.y - 40.0:
			return local
	return Vector2(size.x * 0.6, size.y * 0.4)


func _burst(strength: float = 1.0, color: Color = Color(0, 0, 0, 0)) -> void:
	var b := Burst.new()
	b.color = color if color.a > 0.0 else Kit.ACCENT
	b.strength = strength
	b.position = _hero_point()
	_fx.add_child(b)


func _float_text(text: String, color: Color, size_px: int = 52) -> void:
	var l := Kit.label(text, size_px, color, "compressed")
	l.add_theme_constant_override("outline_size", 10)
	l.add_theme_color_override("font_outline_color", Color(PAPER, 0.95))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size = Vector2(600, size_px * 1.6)
	var p := _hero_point()
	l.position = Vector2(p.x - 300.0, p.y - 120.0)
	l.pivot_offset = l.size * 0.5
	_fx.add_child(l)
	l.scale = Vector2(0.6, 0.6)
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "position:y", l.position.y - 90.0, 1.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.45).set_delay(0.95)
	tw.chain().tween_callback(l.queue_free)


func _celebrate_level(gained: int) -> void:
	var lv := int(Game.hero(_id).get("level", 1))
	_burst(1.0)
	_float_text("LV. %d" % lv if gained <= 1 else "LV. %d  (+%d)" % [lv, gained], SIG, 72)
	if _pass:
		Kit.pulse(_pass, 1.03)
	UI.haptic(15)


func _celebrate_star(stars: int) -> void:
	UI.sfx("victory")
	UI.haptic(40)
	_burst(1.4, Kit.ORANGE)
	_burst(0.9, Kit.ACCENT_HI)
	_float_text("%d STARS" % stars, SIG, 84)
	if _sprite and is_instance_valid(_sprite):
		_sprite.call("play_victory")
		_victory_left = 2.4
	for pas: Dictionary in _def.get("passives", []):
		if int(pas.unlock_stars) == stars:
			UI.toast("New passive unlocked: %s" % str(pas.name), "good")


## One-shot celebration: an expanding ring and sparks flying out (frees itself).
class Burst extends Control:
	var color := Color.WHITE
	var strength := 1.0
	var _t := 0.0
	var _dur := 0.9
	var _sparks: Array[Vector3] = []

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var count := int(10 + 14 * strength)
		for i in count:
			_sparks.append(Vector3(randf() * TAU, randf_range(140.0, 380.0) * strength, randf_range(3.0, 8.0)))

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()
		if _t >= _dur:
			queue_free()

	func _draw() -> void:
		var k := clampf(_t / _dur, 0.0, 1.0)
		var e := 1.0 - pow(1.0 - k, 3.0)
		draw_circle(Vector2.ZERO, 90.0 * strength * (1.0 - k), Color(color.lightened(0.5), 0.3 * (1.0 - k)))
		draw_arc(Vector2.ZERO, 30.0 + 230.0 * strength * e, 0, TAU, 64, Color(color, 0.85 * (1.0 - k)), 2.0 + 7.0 * (1.0 - k), true)
		for s in _sparks:
			var dir := Vector2.from_angle(s.x)
			var p := dir * s.y * e
			var tail := dir * s.y * maxf(0.0, e - 0.12)
			draw_line(tail, p, Color(color.lightened(0.2), 1.0 - k), s.z * (1.0 - k * 0.6), true)
			draw_circle(p, s.z * 0.6 * (1.0 - k * 0.5), Color(color.lightened(0.6), 1.0 - k))
