extends Control
## Screen "hero_detail" (params: hero_id, optional browse: [hero ids] for the prev/next arrows,
## scroll: px, show: gear slot to open its picker). Style v2 (docs/dev/ui-style-v2.md
## section 6): a light hatched page with faction-colored stripes along the bottom, the hero's
## full body large on the centre-left (the animated HeroSprite with its idle motion; tap them
## for a reaction), a technical caption top-left, and the white info column on the right:
## rarity mark and stars, the level / name plate, tier hex and power, the STATUS panel (stats
## with the next level's gain in green, Level Up with its cost: tap, hold to repeat, MAX; the
## shard bar and Star Up), the skill hexes, and the lower panel switched by side tabs: EQUIP
## (2 x 2 gear slots with a picker, Quick Equip, Unequip All), SKILLS, STORY. Back / Home sit
## bottom-left (the nav is hidden here), faint chevrons at the edges browse heroes.
## Unowned heroes get a greyed preview with a link to the Summon portal.

const Roster := preload("res://src/ui/screens/heroes_screen.gd")

const HOLD_DELAY := 0.42
const HOLD_START := 0.16
const HOLD_MIN := 0.045
const STAT_ORDER: Array[String] = ["hp", "atk", "def", "spd", "crit"]
const SLOTS: Array[String] = ["weapon", "armor", "helm", "charm"]
const COL_W := 324.0
## Gap between the info column and the right screen edge.
const COL_PAD := 12.0
## Side tabs (pinned left of the column) and the browse arrows (88 x 112 touch areas).
const TAB_W := 96.0
const TAB_H := 112.0
const ARROW := Vector2(88, 112)
const ARROW_TILE := 52.0
const SHORT_RED := Color("d42a12")
const TABS := [["equip", "Equip", "equip"], ["skills", "Skills", "skill"], ["skins", "Skins", "star"],
	["story", "Story", "codex"]]

## The lower-panel tab the player picked last (kept for the session).
static var _pref_tab := "equip"

var _tab := "equip"

var _id := ""
var _def: Dictionary = {}
var _owned := false
var _browse: Array[String] = []
var _faction_col := Kit.GOLD
var _compact := false

var _stage: Control
var _stripes: Control
var _anchor: Node2D
var _sprite: Node2D
## The skin the sprite was built with ("" = base look) and what it shows (HeroArt.art_key, which
## also follows the nudity setting); a change rebuilds the sprite.
var _sprite_skin := ""
var _sprite_key := ""
var _preview := ""        # a skin tried on from the Skins tab (not saved); "" = the equipped look
var _poke: Control
var _caption: Control
var _scroll: ScrollContainer
var _column: VBoxContainer
var _fx: Control
var _arrows: Array[Control] = []
var _tabs_box: VBoxContainer
var _more: Control
var _back_bar: Control
var _back_btn: Button
var _home_btn: Button

var _stars_box: HBoxContainer
var _plate_slot: HBoxContainer
var _team_tag: Control
var _power_label: Label
var _power_value := -1
var _stat_rows: VBoxContainer
var _stats_sig := ""
var _lvl_btn: Button
var _lvl_inner: VBoxContainer
var _max_btn: Button
var _max_inner: VBoxContainer
var _shard_bar: ProgressBar
var _star_slot: HBoxContainer
var _skill_row: HBoxContainer
var _tab_btns: Dictionary = {}
var _lower: VBoxContainer
var _lower_sig := ""
var _gear_modal: Control

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
	# The nav is hidden here: Back / Home sit bottom-left instead.
	UI.set_chrome(true, false)
	if _def.is_empty():
		_build_missing()
		return
	Roster.mark_seen(_id)
	_faction_col = Kit.faction_color(str(_def.faction))
	_owned = Game.owns(_id)
	_tab = "skills" if not _owned and _pref_tab == "equip" else _pref_tab
	# Screenshot/testing helper (params.tab): open on a given lower-panel tab.
	var want := str(params.get("tab", ""))
	# params.preview: open trying on a skin (as the "Try on" button does).
	_preview = str(params.get("preview", ""))
	for t: Array in TABS:
		if str(t[0]) == want and (want != "equip" or _owned):
			_tab = want
	if _browse.is_empty() or not _browse.has(_id):
		_browse.clear()
		for h: Dictionary in Game.owned_heroes():
			_browse.append(str(h.id))
		if not _browse.has(_id):
			_browse = [_id]
	var vh := get_viewport_rect().size.y - UI.content_top()
	_compact = vh - UI.safe_bottom() < 1180.0
	_build()
	resized.connect(_layout)
	Game.changed.connect(_refresh)
	_refresh()
	_layout.call_deferred()
	if params.has("scroll"):
		_scroll_to.call_deferred(int(params["scroll"]))
	if str(params.get("show", "")) != "":
		_open_gear_picker.call_deferred(str(params["show"]))


## Screenshot/testing helper (params.scroll): scroll the info column once laid out.
func _scroll_to(px: int) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(_scroll):
		_scroll.scroll_vertical = px


func _exit_tree() -> void:
	if Game.changed.is_connected(_refresh):
		Game.changed.disconnect(_refresh)
	if _gear_modal and is_instance_valid(_gear_modal):
		UI.close_modal(_gear_modal)


func _build_missing() -> void:
	add_child(Kit.page_bg("light"))
	var col := Kit.vbox(24)
	col.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	col.offset_left = 24
	col.offset_right = -24
	col.offset_top = 40
	add_child(col)
	col.add_child(Kit.empty_state("This hero could not be found.", "heroes", true))
	_add_back_bar()


# ------------------------------------------------------------------ build

func _build() -> void:
	add_child(Kit.page_bg("light"))
	# Faction stripes across the lower part of the page, fading in from above.
	_stripes = Control.new()
	_stripes.name = "Stripes"
	_stripes.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_stripes)
	var hatch := Kit.deco("hatch", Vector2(720, 560), Color(_faction_col, 0.32))
	hatch.set("spacing", 48.0)
	hatch.set("line_width", 20.0)
	hatch.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_stripes.add_child(hatch)
	var fade := TextureRect.new()
	fade.mouse_filter = MOUSE_FILTER_IGNORE
	fade.texture = Kit.vgradient(Color("f4f6f8"), Color(0.96, 0.965, 0.97, 0.0))
	fade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fade.stretch_mode = TextureRect.STRETCH_SCALE
	fade.anchor_right = 1.0
	fade.offset_bottom = 220
	_stripes.add_child(fade)

	# The hero: full body, centre-left.
	_stage = Control.new()
	_stage.name = "Stage"
	_stage.mouse_filter = MOUSE_FILTER_IGNORE
	_stage.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(_stage)
	var glow := Kit.glow(_faction_col, 720)
	glow.name = "Glow"
	glow.modulate.a = 0.22
	_stage.add_child(glow)
	_anchor = Node2D.new()
	_anchor.name = "HeroAnchor"
	_stage.add_child(_anchor)
	_sprite_skin = _shown_skin()
	_sprite_key = HeroArt.art_key(_id, _sprite_skin)
	_sprite = HeroArt.make_sprite(_id, _sprite_skin)
	_anchor.add_child(_sprite)
	if not _owned:
		_sprite.modulate = Color(0.46, 0.48, 0.53, 0.85)
	_poke = Control.new()
	_poke.name = "Poke"
	_poke.mouse_filter = MOUSE_FILTER_PASS
	add_child(_poke)
	Kit.make_tappable(_poke, _poke_hero)

	_build_caption()

	# A soft white veil under the info column so its text reads over any art.
	var veil := HBoxContainer.new()
	veil.name = "Veil"
	veil.mouse_filter = MOUSE_FILTER_IGNORE
	veil.add_theme_constant_override("separation", 0)
	var paper := Color(0.96, 0.965, 0.97, 0.62)
	for tex: Texture2D in [Kit.vgradient(Color(paper, 0.0), paper, true), Kit.vgradient(paper, paper)]:
		var t := TextureRect.new()
		t.mouse_filter = MOUSE_FILTER_IGNORE
		t.texture = tex
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_SCALE
		t.custom_minimum_size.x = 120
		t.size_flags_horizontal = SIZE_EXPAND_FILL if tex.get_width() == 4 else SIZE_FILL
		veil.add_child(t)
	add_child(veil)

	# The info column (scrolls only when the window is too short for it). It is exactly
	# COL_W wide; the 6 px side margins keep the panel shadows inside the scroll clip.
	_column = Kit.vbox(8 if _compact else 10)
	_column.name = "Column"
	_column.custom_minimum_size.x = COL_W
	var m := Kit.margin(_column, 6, 0)
	m.add_theme_constant_override("margin_top", 12 if _compact else 18)
	m.add_theme_constant_override("margin_bottom", 28)
	_scroll = Kit.scroll(m)
	_scroll.name = "InfoScroll"
	add_child(_scroll)
	_build_column()
	_scroll.get_v_scroll_bar().value_changed.connect(func(_v: float) -> void: _place_tabs())
	_scroll.get_v_scroll_bar().changed.connect(_place_tabs)

	# "More below" fade at the bottom of the column while it can still scroll.
	_more = Control.new()
	_more.name = "More"
	_more.mouse_filter = MOUSE_FILTER_IGNORE
	var mf := TextureRect.new()
	mf.mouse_filter = MOUSE_FILTER_IGNORE
	mf.texture = Kit.vgradient(Color(0.95, 0.957, 0.965, 0.0), Color(0.95, 0.957, 0.965, 0.96))
	mf.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mf.stretch_mode = TextureRect.STRETCH_SCALE
	mf.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_more.add_child(mf)
	var chev := Kit.icon("chevron_right", 30, Kit.ACCENT_DEEP)
	chev.name = "Chevron"
	chev.pivot_offset = Vector2(15, 15)
	chev.rotation = PI * 0.5
	chev.anchor_left = 0.5
	chev.anchor_right = 0.5
	chev.anchor_top = 1.0
	chev.anchor_bottom = 1.0
	chev.offset_left = -15
	chev.offset_right = 15
	chev.offset_top = -36
	chev.offset_bottom = -6
	_more.add_child(chev)
	add_child(_more)

	# Side tabs (Equip / Skills / Story), pinned left of the column: they follow the lower
	# panel while it is on screen and stop above Back / Home when it scrolls away.
	_tabs_box = Kit.vbox(4)
	_tabs_box.name = "SideTabs"
	for t: Array in TABS:
		var tid: String = t[0]
		if tid == "equip" and not _owned:
			continue
		var b := Kit.side_button(str(t[2]), str(t[1]), _select_tab.bind(tid), "accent" if tid == _tab else "dark")
		b.name = "Tab_" + tid
		b.custom_minimum_size = Vector2(TAB_W, TAB_H)
		_tabs_box.add_child(b)
		_tab_btns[tid] = b
	add_child(_tabs_box)

	_fx = Control.new()
	_fx.name = "Fx"
	_fx.mouse_filter = MOUSE_FILTER_IGNORE
	_fx.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(_fx)

	# Browse arrows flank the art (left screen edge, and just left of the column) so they
	# never sit on the column's buttons. 88 x 112 touch areas around a small dark tile.
	if _browse.size() > 1:
		for dir: int in [-1, 1]:
			var d := dir
			var arrow := Kit.icon_button("chevron_right", func() -> void: _browse_step(d), ARROW_TILE / 0.76, "round")
			arrow.name = "Prev" if dir < 0 else "Next"
			arrow.custom_minimum_size = ARROW
			arrow.size = ARROW
			# Slide the visible tile toward the outside of the touch area.
			var shift := -(ARROW.x - ARROW_TILE) * 0.5 + 8.0 if dir < 0 else (ARROW.x - ARROW_TILE) * 0.5 - 8.0
			for part: String in ["Disc", "Glyph"]:
				var c := arrow.get_node(part) as Control
				c.offset_left += shift
				c.offset_right += shift
			var g := arrow.get_node("Glyph") as TextureRect
			g.flip_h = dir < 0
			add_child(arrow)
			_arrows.append(arrow)
	_add_back_bar()


func _add_back_bar() -> void:
	var bb := Kit.back_bar()
	bb.anchor_top = 1.0
	bb.anchor_bottom = 1.0
	bb.offset_left = 14
	bb.offset_top = -Kit.BUTTON_H - 14 - UI.safe_bottom()
	bb.offset_bottom = -14 - UI.safe_bottom()
	add_child(bb)
	_back_bar = bb
	_back_btn = bb.get_node("Back") as Button
	_home_btn = bb.get_node("Home") as Button


## Top-left technical caption: role hex, "HERO INFORMATION", a technical line, faction and role.
## It sits on a soft paper scrim above the art, so wings and halos never swallow it.
func _build_caption() -> void:
	var scrim := PanelContainer.new()
	scrim.name = "CaptionScrim"
	scrim.mouse_filter = MOUSE_FILTER_IGNORE
	scrim.position = Vector2(10, 8)
	scrim.add_theme_stylebox_override("panel", Kit.box(Color(0.96, 0.965, 0.97, 0.9), Color(0.96, 0.965, 0.97, 0.8), Color.TRANSPARENT, 6.0, 0, 8))
	var cap := Kit.vbox(4)
	cap.name = "Caption"
	cap.mouse_filter = MOUSE_FILTER_IGNORE
	scrim.add_child(cap)
	var top := Kit.hbox(10)
	top.mouse_filter = MOUSE_FILTER_IGNORE
	top.add_child(Kit.hex_badge("role_" + str(_def.role), 60, Color("182640")))
	var tl := Kit.label("HERO\nINFORMATION", 16, Kit.TEXT_DIM, "cond_bold")
	tl.add_theme_constant_override("line_spacing", -4)
	top.add_child(tl)
	cap.add_child(top)
	cap.add_child(Kit.deco("techline", Vector2(150, 10), Color(0, 0, 0, 0.3)))
	var fr := Kit.hbox(6)
	fr.mouse_filter = MOUSE_FILTER_IGNORE
	fr.add_child(Kit.faction_icon(str(_def.faction), 28))
	fr.add_child(Kit.label(str(Kit.FACTION_NAMES.get(str(_def.faction), "")).to_upper(), 18, Kit.faction_color(str(_def.faction)).darkened(0.35), "cond_bold"))
	cap.add_child(fr)
	cap.add_child(Kit.label(str(Kit.ROLE_NAMES.get(str(_def.role), "")).to_upper(), 18, Kit.TEXT_DIM, "cond_bold"))
	add_child(scrim)
	_caption = scrim


func _build_column() -> void:
	var rarity := str(_def.rarity)
	# Rarity mark and star pips.
	var rr := Kit.hbox(8)
	rr.mouse_filter = MOUSE_FILTER_IGNORE
	rr.add_child(Kit.rarity_mark(rarity, 30 if _compact else 32))
	rr.add_child(Kit.spacer(0, 0, true))
	_stars_box = Kit.hbox(0)
	_stars_box.mouse_filter = MOUSE_FILTER_IGNORE
	_stars_box.size_flags_vertical = SIZE_SHRINK_CENTER
	rr.add_child(_stars_box)
	_column.add_child(rr)
	# Level / name plate (rebuilt on refresh) and the title line.
	_plate_slot = Kit.hbox(0)
	_plate_slot.mouse_filter = MOUSE_FILTER_IGNORE
	_column.add_child(_plate_slot)
	# Tier numeral hex and power.
	var pw := Kit.hbox(12)
	pw.mouse_filter = MOUSE_FILTER_IGNORE
	var hx := Kit.hex_badge("", 60 if _compact else 66, Color("182640"), Color.WHITE, str(Kit.RARITY_TIER.get(rarity, "I")))
	hx.set("cap", _faction_col)
	pw.add_child(hx)
	var pv := Kit.vbox(-6)
	pv.mouse_filter = MOUSE_FILTER_IGNORE
	pv.alignment = BoxContainer.ALIGNMENT_CENTER
	pv.add_child(Kit.label("POWER", 18, Kit.TEXT_DIM, "cond_bold"))
	_power_label = Kit.label("0", 46 if _compact else 52, Kit.TEXT, "title")
	pv.add_child(_power_label)
	pw.add_child(pv)
	pw.add_child(Kit.spacer(0, 0, true))
	_team_tag = Kit.tag("IN TEAM", Kit.ACCENT, Color.WHITE, 18)
	_team_tag.size_flags_vertical = SIZE_SHRINK_CENTER
	pw.add_child(_team_tag)
	_column.add_child(pw)

	_column.add_child(_build_status())
	_column.add_child(_build_skill_hexes())
	_column.add_child(_build_lower())


## STATUS: stat rows, then Level Up / MAX and the star row (owned), or the summon link.
func _build_status() -> Control:
	var p := Kit.info_panel(10)
	var v := Kit.vbox(6)
	p.add_child(v)
	v.add_child(Kit.header_bar("Status"))
	_stat_rows = Kit.vbox(0)
	v.add_child(_stat_rows)
	if not _owned:
		v.add_child(Kit.spacer(0, 2))
		var t := Kit.body("Not yet summoned. %s answers the Summon portal: every pull has a chance at a %s hero." % [
			str(_def.name), str(Kit.RARITY_NAMES.get(str(_def.rarity), "")).to_lower()], 20, Kit.TEXT_DIM)
		v.add_child(t)
		var go := Kit.primary_button("Go to Summon", func() -> void: UI.go("summon"), "summon")
		go.add_theme_font_size_override("font_size", 26)
		v.add_child(go)
		return p
	v.add_child(Kit.spacer(0, 2))
	var row := Kit.hbox(8)
	_lvl_btn = Kit.primary_button("", _on_level_tap)
	_lvl_btn.name = "LevelUp"
	_lvl_btn.custom_minimum_size = Vector2(0, 92 if _compact else 98)
	_lvl_btn.size_flags_horizontal = SIZE_EXPAND_FILL
	_lvl_btn.button_down.connect(_on_level_down)
	_lvl_btn.button_up.connect(func() -> void: _end_hold())
	_lvl_inner = Kit.vbox(4)
	_lvl_inner.mouse_filter = MOUSE_FILTER_IGNORE
	_lvl_inner.alignment = BoxContainer.ALIGNMENT_CENTER
	_lvl_inner.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_lvl_inner.offset_bottom = -4
	_lvl_btn.add_child(_lvl_inner)
	row.add_child(_lvl_btn)
	_max_btn = Kit.light_button("", _on_level_max)
	_max_btn.name = "LevelMax"
	_max_btn.custom_minimum_size = Vector2(88, 92 if _compact else 98)
	_max_inner = Kit.vbox(-4)
	_max_inner.mouse_filter = MOUSE_FILTER_IGNORE
	_max_inner.alignment = BoxContainer.ALIGNMENT_CENTER
	_max_inner.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_max_btn.add_child(_max_inner)
	row.add_child(_max_btn)
	v.add_child(row)
	var srow := Kit.hbox(8)
	var sv := Kit.vbox(2)
	sv.size_flags_horizontal = SIZE_EXPAND_FILL
	sv.alignment = BoxContainer.ALIGNMENT_CENTER
	var sh := Kit.hbox(4)
	sh.mouse_filter = MOUSE_FILTER_IGNORE
	sh.add_child(Kit.icon("shard", 26))
	sh.add_child(Kit.label("SHARDS", 17, Kit.TEXT_DIM, "cond_bold"))
	sv.add_child(sh)
	_shard_bar = Kit.progress_bar(0, 1, Kit.rarity_color(str(_def.rarity)), 22, "", true)
	sv.add_child(_shard_bar)
	srow.add_child(sv)
	_star_slot = Kit.hbox(0)
	srow.add_child(_star_slot)
	v.add_child(srow)
	return p


## Ultimate (faction-colored hex) and passives (white; locked ones show a lock). Tap = Skills tab.
func _build_skill_hexes() -> Control:
	_skill_row = Kit.hbox(2)
	_skill_row.name = "SkillHexes"
	return _skill_row


func _refresh_skill_hexes(stars: int) -> void:
	for c in _skill_row.get_children():
		_skill_row.remove_child(c)
		c.queue_free()
	var sz := 62.0 if _compact else 70.0
	var items: Array[Control] = []
	var ult := Kit.hex_badge("power", sz, _faction_col.darkened(0.1), Color.WHITE)
	ult.set("glow", Color(_faction_col, 0.45))
	ult.set("glow_size", 8.0)
	items.append(ult)
	for pas: Dictionary in _def.get("passives", []):
		var on := _owned and stars >= int(pas.unlock_stars)
		items.append(Kit.hex_badge("skill" if on else "lock", sz, Color.WHITE, Color("1b2b48") if on else Color(0.16, 0.18, 0.21, 0.45)))
	var lab := Kit.vbox(-4)
	lab.mouse_filter = MOUSE_FILTER_IGNORE
	lab.alignment = BoxContainer.ALIGNMENT_CENTER
	lab.add_child(Kit.label("SKILLS", 18, Kit.TEXT, "cond_bold"))
	lab.add_child(Kit.label("%d / %d" % [1 + _unlocked_passives(stars), 1 + (_def.get("passives", []) as Array).size()], 18, Kit.TEXT_DIM, "cond"))
	_skill_row.add_child(lab)
	_skill_row.add_child(Kit.spacer(0, 0, true))
	for it in items:
		var holder := Panel.new()
		holder.theme_type_variation = &"BareButton"
		holder.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		holder.custom_minimum_size = Vector2(maxf(sz, 86.0), maxf(sz, Kit.BUTTON_H))
		it.position = (holder.custom_minimum_size - Vector2(sz, sz)) * 0.5
		holder.add_child(it)
		Kit.make_tappable(holder, func() -> void: _select_tab("skills"))
		_skill_row.add_child(holder)


func _unlocked_passives(stars: int) -> int:
	var n := 0
	if not _owned:
		return 0
	for pas: Dictionary in _def.get("passives", []):
		if stars >= int(pas.unlock_stars):
			n += 1
	return n


## The lower panel (EQUIP / SKILLS / STORY), switched by the pinned side tabs.
func _build_lower() -> Control:
	_lower = Kit.vbox(8)
	_lower.name = "Lower"
	return _lower


func _select_tab(tid: String) -> void:
	if not _tab_btns.has(tid):
		return
	if tid != _tab:
		_tab = tid
		_pref_tab = tid
		for k: String in _tab_btns:
			var b := _tab_btns[k] as Button
			var tile := b.get_node("Face/Tile") as Panel
			tile.add_theme_stylebox_override("panel", Kit.style("tile_accent" if k == _tab else "tile_dark"))
		_lower_sig = ""
		_refresh_lower()
	_reveal_lower.call_deferred()


## Scrolls the column so the lower panel is in view (short screens).
func _reveal_lower() -> void:
	await get_tree().process_frame
	if not is_instance_valid(_scroll) or not is_instance_valid(_lower):
		return
	var top := _lower.get_global_rect().position.y - _scroll.get_global_rect().position.y
	var bottom := top + _lower.size.y
	var view := _scroll.size.y
	if top < 0.0 or bottom > view:
		var target := _scroll.scroll_vertical + int(top - 12.0)
		if _lower.size.y < view - 24.0:
			target = _scroll.scroll_vertical + int(bottom - view + 24.0)
		_scroll.create_tween().tween_property(_scroll, "scroll_vertical", maxi(target, 0), 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


# ------------------------------------------------------------------ layout & motion

func _layout() -> void:
	if _stage == null or size.y <= 0.0:
		return
	var w := size.x
	var h := size.y
	var sb := UI.safe_bottom()
	var avail := h - sb
	var col_x := w - COL_PAD - COL_W
	_scroll.position = Vector2(col_x - 6.0, 0)
	_fit_scroll()
	# Stripes along the bottom.
	_stripes.position = Vector2(0, h * 0.5)
	_stripes.size = Vector2(w, h * 0.5)
	# Hero: full body, feet near the bottom, standing centre-left.
	var feet_y := h - sb - 18.0
	var fig_h := (h - sb) * (0.94 if _compact else 0.97)
	_anchor.position = Vector2(w * 0.33, feet_y)
	if _sprite and is_instance_valid(_sprite):
		_sprite.scale = Vector2.ONE
		var hgt: float = _sprite.call("get_height")
		var k := fig_h / maxf(hgt, 1.0)
		_sprite.scale = Vector2(k, k)
	var glow := _stage.get_node("Glow") as Control
	glow.size = Vector2(720, 720)
	glow.position = Vector2(w * 0.33 - 360.0, feet_y - fig_h * 0.62 - 360.0)
	var veil := get_node("Veil") as Control
	veil.position = Vector2(col_x - 100.0, 0)
	veil.size = Vector2(w - col_x + 100.0, h)
	# Browse arrows at chest height: one on the left edge, one just left of the column.
	var ay := avail * 0.4 - ARROW.y * 0.5
	for i in _arrows.size():
		var a := _arrows[i]
		a.position = Vector2(0.0 if i == 0 else col_x - 8.0 - ARROW.x, ay)
	_poke.position = Vector2(ARROW.x, 170)
	_poke.size = Vector2(maxf(60.0, col_x - TAB_W - 20.0 - ARROW.x), maxf(100.0, avail - 290.0))
	_place_tabs()


## The column runs the full height (Back / Home sit left of it, under the art).
func _fit_scroll() -> void:
	if _scroll == null or size.y <= 0.0:
		return
	_scroll.size = Vector2(COL_W + 12.0, size.y - UI.safe_bottom())
	_place_tabs()


## Side tabs: level with the top of the lower panel, but never under Back / Home or above
## the arrow row. Also shows the "more below" fade while the column can still scroll.
func _place_tabs() -> void:
	if _tabs_box == null or not is_instance_valid(_lower) or size.y <= 0.0:
		return
	var avail := size.y - UI.safe_bottom()
	var tabs_h := _tabs_box.get_combined_minimum_size().y
	var col_x := size.x - COL_PAD - COL_W
	var lower_y := _lower.get_global_rect().position.y - get_global_rect().position.y
	var lo := avail * 0.4 + ARROW.y * 0.5 + 8.0
	var hi := avail - Kit.BUTTON_H - 14.0 - 16.0 - tabs_h
	_tabs_box.position = Vector2(col_x - 6.0 - TAB_W, clampf(lower_y, minf(lo, hi), hi))
	_tabs_box.size = Vector2(TAB_W, tabs_h)
	if _more:
		var bar := _scroll.get_v_scroll_bar()
		var left := bar.max_value - bar.page - bar.value
		_more.visible = left > 8.0
		_more.position = Vector2(col_x - 6.0, avail - 64.0)
		_more.size = Vector2(COL_W + 12.0, 64.0)


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


# ------------------------------------------------------------------ refresh

func _refresh() -> void:
	if not is_inside_tree() or _stage == null:
		return
	_owned = Game.owns(_id)
	if HeroArt.art_key(_id, _shown_skin()) != _sprite_key:
		_rebuild_sprite()
	var h := Game.hero(_id)
	var stars := int(h.get("stars", Kit.RARITY_STARS.get(str(_def.rarity), 1)))
	var level := int(h.get("level", 1))
	var cap := int(Game.max_level(_id))

	for c in _stars_box.get_children():
		_stars_box.remove_child(c)
		c.queue_free()
	_stars_box.add_child(Kit.star_row(stars, Kit.MAX_STARS if _owned else 0, 22))
	for c in _plate_slot.get_children():
		_plate_slot.remove_child(c)
		c.queue_free()
	var plate := Kit.name_plate(level, cap, str(_def.name), 28 if _compact else 30)
	plate.size_flags_horizontal = SIZE_EXPAND_FILL
	_plate_slot.add_child(plate)
	_team_tag.visible = Game.formation().has(_id)

	var p := int(Game.hero_power(_id))
	if _power_value >= 0 and p != _power_value:
		Kit.count_to(_power_label, _power_value, p, 0.5, true)
		Kit.pulse(_power_label, 1.08)
	else:
		_power_label.text = Kit.format_full(p)
	_power_value = p

	_refresh_stats(level, cap, stars)
	if _owned:
		_refresh_level(level, cap)
		_refresh_stars(stars)
	_refresh_skill_hexes(stars)
	_refresh_lower()
	_refresh_guide()


func _refresh_stats(level: int, cap: int, stars: int) -> void:
	var st := Game.hero_stats(_id)
	var nxt := {}
	if _owned and level < cap:
		nxt = Game.hero_stats_at(_id, level + 1, stars)
	var sig := JSON.stringify(st) + JSON.stringify(nxt)
	if sig == _stats_sig:
		return
	_stats_sig = sig
	for c in _stat_rows.get_children():
		_stat_rows.remove_child(c)
		c.queue_free()
	var i := 0
	for k: String in STAT_ORDER:
		var val := int(st.get(k, 0))
		var delta: Variant = null
		if not nxt.is_empty():
			var dv := int(nxt.get(k, 0)) - val
			if dv > 0:
				delta = _stat_text(k, dv)
		var rp := Kit.panel("row" if i % 2 == 0 else "light_inset", 0)
		var sr := Kit.stat_row(k, _stat_text(k, val), delta, "", true)
		sr.custom_minimum_size.y = 34 if _compact else 37
		rp.add_child(Kit.margin(sr, 10, 0))
		_stat_rows.add_child(rp)
		i += 1


## First-session guidance. Level up this hero when the guide wants it (the button is marked
## in _refresh_level); when another team hero should be leveled, point at the browse arrow
## toward them or at Back (the roster rings them). Any other step happens elsewhere and the
## nav is hidden here, so point at Home.
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
		Guide.mark(_back_btn, away and dir == 0, 0)
	if _home_btn:
		Guide.mark(_home_btn, step in ["claim", "summon", "formation", "battle"], 0)


func _stat_text(stat: String, v: int) -> String:
	if stat == "crit":
		if v % 100 == 0:
			return "%d%%" % (v / 100)
		return "%.1f%%" % (float(v) / 100.0)
	return Kit.format_full(v)


func _refresh_level(level: int, cap: int) -> void:
	for c in _lvl_inner.get_children():
		_lvl_inner.remove_child(c)
		c.queue_free()
	var cost := Game.level_up_cost(_id)
	if cost.is_empty():
		Guide.mark(_lvl_btn, false)
		_lvl_btn.disabled = true
		var t := Kit.label("Level Cap", 28, Color("9aa1aa"), "extrabold")
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_lvl_inner.add_child(t)
		_max_btn.disabled = true
		_set_max_text(0)
		return
	_lvl_btn.disabled = false
	# First-session guidance: level up team heroes (see _refresh_guide for the others).
	Guide.mark(_lvl_btn, Guide.should_level(_id))
	var t2 := Kit.label("Level Up", 28, Color.WHITE, "extrabold")
	t2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lvl_inner.add_child(t2)
	var pill := PanelContainer.new()
	pill.mouse_filter = MOUSE_FILTER_IGNORE
	pill.add_theme_stylebox_override("panel", Kit.box(Color(1, 1, 1, 0.94), Color(0.94, 0.95, 0.97, 0.94), Color.TRANSPARENT, 999.0, 0, 0))
	var pm := Kit.margin(Kit.cost_row(cost, 20, Kit.TEXT, true, SHORT_RED), 12, 0)
	pm.mouse_filter = MOUSE_FILTER_IGNORE
	pill.add_child(pm)
	var pc := Kit.center(pill)
	pc.mouse_filter = MOUSE_FILTER_IGNORE
	_lvl_inner.add_child(pc)
	var n := int(Game.affordable_levels(_id))
	_max_btn.disabled = n < 2
	_set_max_text(n if n >= 2 else 0)


## "MAX" over "+N" (the levels it would buy) on the light MAX button.
func _set_max_text(n: int) -> void:
	for c in _max_inner.get_children():
		_max_inner.remove_child(c)
		c.queue_free()
	var dim := _max_btn.disabled
	var a := Kit.label("MAX", 26, Color("9aa1aa") if dim else Kit.TEXT, "cond_bold")
	a.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_max_inner.add_child(a)
	if n > 0:
		var b := Kit.label("+%d" % n, 22, Kit.ACCENT_DEEP, "cond_bold")
		b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_max_inner.add_child(b)


func _refresh_stars(stars: int) -> void:
	for c in _star_slot.get_children():
		_star_slot.remove_child(c)
		c.queue_free()
	var c := Game.star_up_cost(_id)
	if c.is_empty():
		Kit.set_progress(_shard_bar, 1, 1, "MAX STARS", false)
		var done := Kit.light_button("Max Stars")
		done.disabled = true
		done.custom_minimum_size = Vector2(150, Kit.BUTTON_H)
		done.add_theme_font_size_override("font_size", 24)
		_star_slot.add_child(done)
		return
	var need := int(c.shards)
	var have := int(c.shards_have)
	Kit.set_progress(_shard_bar, mini(have, need), need, "%d / %d" % [have, need], false)
	var dust := int(c.dust)
	var b: Button
	if dust > 0:
		b = Kit.costs_button("Star Up", {"dust": dust}, _on_star_up, "light")
		b.custom_minimum_size = Vector2(150, 96)
	else:
		b = Kit.primary_button("Star Up", _on_star_up, "star")
		b.custom_minimum_size = Vector2(150, Kit.BUTTON_H)
		b.add_theme_font_size_override("font_size", 24)
		Kit.set_dot(b, true, 22, Vector2(6, 6))
	b.name = "StarUp"
	_star_slot.add_child(b)
	if stars < Kit.MAX_STARS:
		b.tooltip_text = ""


# ------------------------------------------------------------------ lower panel (tabs)

func _refresh_lower() -> void:
	var sig := _tab
	if _tab == "equip":
		sig += JSON.stringify(Game.hero(_id).get("gear", {})) + "|" + JSON.stringify(Game.gear_items())
	elif _tab == "skills":
		sig += str(Game.hero(_id).get("stars", 0))
	elif _tab == "skins":
		sig += JSON.stringify(Game.skins_for(_id)) + str(Game.currency("gems"))
	if sig == _lower_sig:
		return
	_lower_sig = sig
	for c in _lower.get_children():
		_lower.remove_child(c)
		c.queue_free()
	match _tab:
		"equip":
			_build_equip()
		"skills":
			_build_skills()
		"skins":
			_build_skins()
		_:
			_build_story()
	_fit_scroll.call_deferred()


func _build_equip() -> void:
	var p := Kit.info_panel(10)
	var v := Kit.vbox(8)
	p.add_child(v)
	v.add_child(Kit.header_bar("Equip"))
	var hg: Dictionary = Game.hero(_id).get("gear", {})
	var g := Kit.grid(2, 10)
	var any_better := false
	var any_worn := false
	var sz := 118.0 if _compact else 132.0
	for slot: String in SLOTS:
		var uid := str(hg.get(slot, ""))
		var item := Game.gear_item(uid) if uid != "" else {}
		any_worn = any_worn or uid != ""
		var s := slot
		var tile := Kit.equip_slot(slot, item, sz, func() -> void: _open_gear_picker(s))
		if _better_loose(slot, uid):
			any_better = true
			Kit.set_dot(tile, true, 22, Vector2(-4, -4))
		g.add_child(tile)
	v.add_child(Kit.center(g))
	var row := Kit.hbox(8)
	var q: Button
	if any_better:
		q = Kit.primary_button("Quick Equip", _on_auto_equip)
	else:
		q = Kit.light_button("Quick Equip", _on_auto_equip)
	q.name = "QuickEquip"
	var u := Kit.light_button("Unequip All", _on_unequip_all)
	u.name = "UnequipAll"
	u.disabled = not any_worn
	for b: Button in [q, u]:
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		b.custom_minimum_size.x = 0
		Kit.fit_button(b, (COL_W - 20.0 - 8.0) * 0.5, 22, 16)
		row.add_child(b)
	v.add_child(row)
	_lower.add_child(p)


func _build_skills() -> void:
	var p := Kit.info_panel(10)
	var v := Kit.vbox(8)
	p.add_child(v)
	v.add_child(Kit.header_bar("Skills"))
	var stars := int(Game.hero(_id).get("stars", Kit.RARITY_STARS.get(str(_def.rarity), 1)))
	var ult: Dictionary = _def.get("ultimate", {})
	v.add_child(_skill_entry("power", true, str(ult.get("name", "")), "ULTIMATE", str(ult.get("description", "")), true, 0))
	for pas: Dictionary in _def.get("passives", []):
		var on := _owned and stars >= int(pas.unlock_stars)
		v.add_child(_skill_entry("skill", false, str(pas.name), "PASSIVE", str(pas.description), on, int(pas.unlock_stars)))
	_lower.add_child(p)


func _skill_entry(icon_name: String, ult: bool, title_text: String, kind: String, desc: String, unlocked: bool, unlock_stars: int) -> Control:
	var rp := Kit.panel("light_inset", 10)
	var row := Kit.hbox(10)
	row.mouse_filter = MOUSE_FILTER_IGNORE
	rp.add_child(row)
	var hx: Control
	if ult:
		hx = Kit.hex_badge(icon_name, 52, _faction_col.darkened(0.1), Color.WHITE)
	else:
		hx = Kit.hex_badge(icon_name if unlocked else "lock", 52, Color.WHITE, Color("1b2b48") if unlocked else Color(0.16, 0.18, 0.21, 0.45))
	hx.size_flags_vertical = SIZE_SHRINK_BEGIN
	row.add_child(hx)
	var tv := Kit.vbox(2)
	tv.size_flags_horizontal = SIZE_EXPAND_FILL
	tv.mouse_filter = MOUSE_FILTER_IGNORE
	var head := Kit.hbox(6)
	head.mouse_filter = MOUSE_FILTER_IGNORE
	var n := Kit.label(title_text, 22, Kit.TEXT if unlocked else Kit.TEXT_DIM, "extrabold")
	n.size_flags_horizontal = SIZE_EXPAND_FILL
	n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.add_child(n)
	tv.add_child(head)
	var kt := Kit.label(kind if unlocked else "UNLOCKS AT %d STARS" % unlock_stars, 16, Kit.ACCENT_DEEP if unlocked else Kit.TEXT_DIM, "cond_bold")
	tv.add_child(kt)
	var d := Kit.body(desc, 19, Kit.TEXT if unlocked else Kit.TEXT_DIM)
	tv.add_child(d)
	row.add_child(tv)
	return rp


## Skins (cosmetic, docs/dev/skins.md): her base look plus each skin with Wear / Equipped /
## Buy (gems, confirmed) / Coming soon (art not built yet). Wearing one rebuilds the sprite.
func _build_skins() -> void:
	var p := Kit.info_panel(10)
	var v := Kit.vbox(10)
	p.add_child(v)
	v.add_child(Kit.header_bar("Skins"))
	var eq := Game.equipped_skin(_id)
	v.add_child(_skin_row_ui("", "Base look", str(_def.get("title", "")).to_upper(), "", eq == "", true, true, 0))
	var lines := SkinData.lines()
	for s in Game.skins_for(_id):
		var sub := ("%s  ·  %s" % [lines.get(str(s.line), str(s.line)), SkinData.tier_name(str(s.tier))]).to_upper()
		v.add_child(_skin_row_ui(str(s.id), str(s.name), sub, str(s.description), bool(s.equipped), bool(s.owned),
			bool(s.installed), int(s.price_gems)))
	if not _owned:
		v.add_child(Kit.body("Skins can be bought before she joins your team.", 18, Kit.TEXT_DIM))
	_lower.add_child(p)


func _skin_row_ui(sid: String, title: String, sub: String, desc: String, equipped: bool, owned: bool,
		installed: bool, price: int) -> Control:
	# Stacked (text over the button): the info column is narrow (COL_W), and a side-by-side row
	# would widen it past the screen edge.
	var row := Kit.panel("row", 10)
	row.name = "SkinRow_" + (sid if sid != "" else "base")
	var h := Kit.vbox(6)
	row.add_child(h)
	var top := Kit.hbox(10)
	top.mouse_filter = MOUSE_FILTER_IGNORE
	h.add_child(top)
	var pic := HeroArt.make_portrait(_id, 84, sid)
	pic.mouse_filter = MOUSE_FILTER_IGNORE
	pic.size_flags_vertical = SIZE_SHRINK_BEGIN
	top.add_child(pic)
	var info := Kit.vbox(2)
	info.size_flags_horizontal = SIZE_EXPAND_FILL
	info.mouse_filter = MOUSE_FILTER_IGNORE
	info.add_child(Kit.body(title, 22, Kit.TEXT))
	if sub != "":
		info.add_child(Kit.body(sub, 15, Kit.ACCENT_DEEP))
	if desc != "":
		info.add_child(Kit.body(desc, 16, Kit.TEXT_DIM))
	top.add_child(info)
	var b: Button
	if equipped:
		b = Kit.light_button("Equipped")
		b.disabled = true
	elif owned:
		b = Kit.secondary_button("Wear", func() -> void: _wear_skin(sid))
	elif not installed:
		b = Kit.light_button("Coming soon")
		b.disabled = true
	else:
		b = Kit.cost_button("Buy", "gems", price, func() -> void: _buy_skin(sid), "primary", Game.currency("gems") >= price)
	b.custom_minimum_size = Vector2(0, 88)
	b.size_flags_horizontal = SIZE_EXPAND_FILL
	if sid != "" and installed and not equipped:
		# Try on: show it on the stage without buying or wearing it (tap again to go back).
		var trying := _preview == sid
		var t := Kit.light_button("Back to equipped" if trying else "Try on",
			func() -> void: _try_on("" if trying else sid))
		t.name = "TryOn_" + sid
		t.custom_minimum_size = Vector2(0, 88)
		t.size_flags_horizontal = SIZE_EXPAND_FILL
		h.add_child(t)          # stacked: two buttons side by side overflow the narrow column
	h.add_child(b)
	return row


## The skin on the stage: the one being tried on, else the equipped one.
func _shown_skin() -> String:
	return _preview if _preview != "" and HeroArt.has_skin_art(_id, _preview) else Game.equipped_skin(_id)


func _try_on(sid: String) -> void:
	_preview = sid
	_rebuild_sprite()
	_lower_sig = ""          # redraw the rows (Try on / Back to equipped)
	_refresh_lower.call_deferred()


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


## Replace the sprite with one in the equipped skin (or the base look).
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
	if not _owned:
		_sprite.modulate = Color(0.46, 0.48, 0.53, 0.85)
	_layout()


func _build_story() -> void:
	var p := Kit.info_panel(10)
	var v := Kit.vbox(10)
	p.add_child(v)
	v.add_child(Kit.header_bar("Story"))
	var t := Kit.label(str(_def.get("title", "")).to_upper(), 20, Kit.ACCENT_DEEP, "cond_bold")
	v.add_child(t)
	v.add_child(Kit.body(str(_def.get("bio", "")), 21, Kit.TEXT))
	_lower.add_child(p)


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
	UI.go("hero_detail", {"hero_id": n, "browse": Array(_browse)})


func _poke_hero() -> void:
	if _sprite == null or not is_instance_valid(_sprite) or _victory_left > 0.0:
		return
	if _sprite.call("is_busy"):
		return
	_sprite.call("play", "hop" if randi() % 2 == 0 else "cast")


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
		if _lvl_btn:
			Kit.shake(_lvl_btn, 8)
	return false


func _on_star_up() -> void:
	var c := Game.star_up_cost(_id)
	if c.is_empty():
		return
	if not Game.can_star_up(_id):
		UI.toast("Not enough shards or dust", "bad")
		Kit.shake(_star_slot, 8)
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


# ------------------------------------------------------------------ celebration

func _hero_point() -> Vector2:
	if _sprite and is_instance_valid(_sprite):
		var gp: Vector2 = _sprite.call("get_point", "chest")
		var local := gp - _fx.global_position
		if local.y > 40.0 and local.y < size.y - 40.0:
			return local
	return Vector2(size.x * 0.33, size.y * 0.4)


func _burst(strength: float = 1.0, color: Color = Color(0, 0, 0, 0)) -> void:
	var b := Burst.new()
	b.color = color if color.a > 0.0 else Kit.ACCENT
	b.strength = strength
	b.position = _hero_point()
	_fx.add_child(b)


func _float_text(text: String, color: Color, size_px: int = 52) -> void:
	var l := Kit.title(text, size_px, color)
	l.add_theme_constant_override("outline_size", 8)
	l.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.9))
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
	_float_text("LV. %d" % lv if gained <= 1 else "LV. %d  (+%d)" % [lv, gained], Kit.ACCENT_DEEP, 50)
	if _lvl_btn:
		Kit.pulse(_lvl_btn, 1.04)
	UI.haptic(15)


func _celebrate_star(stars: int) -> void:
	UI.sfx("victory")
	UI.haptic(40)
	_burst(1.4, Kit.ORANGE)
	_burst(0.9, Kit.ACCENT_HI)
	_float_text("%d STARS" % stars, Kit.ORANGE, 60)
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
