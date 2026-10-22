extends Control
## Screen "heroes" (params: tab: 0 | 1 = Heroes / Codex; scroll: px, a shot scrolled down). Style v4 (docs/dev/ui-style-v4.md): the
## roster as a printed catalogue sheet in the approved Lobby poster's look, on a paper matte.
## A masthead poster: a dark band with the team lead's red halftone print and the catalogue marks,
## "HEROES" (or "CODEX") set huge in compressed type crossing the band (paper over it, ink beyond),
## the count and the two pages as a printed index ("01 HEROES / 02 CODEX", signal underline). Under
## it the filters as printed tabs: ALL and the five roles (glyph and code), SORT (opens the sort list)
## and FILTER (faction and rarity), then a printed hint line and the catalogue: every hero as a small
## printed poster (src/ui/v4/poster_card.gd: her band and turned name, her art in full colour in the
## look she wears, level, role, power, stars, tier). Status lights: in the team; blinking when a team
## hero can level or star up now; NEW for a hero summoned this session and not opened yet. Tap a card
## to open her dossier (browse = the shown order). "03 PRINTS" in the index opens the print album. The Codex shows every hero, the ones still to be
## summoned printed grey; under a short roster a printed line points to it. Tabs, filters, sort and
## scroll position are remembered for the session (static vars).
## Every card wears her rarity's frame (the summon's rarity language, src/ui/v4/rarity_kit.gd: an
## Epic's violet plates and sheen, a Legendary's gold holo foil, growth, LEGEND tab and shimmering
## name). When the page opens, the first rows play their rarity entrance one after another, and so
## does every hero summoned this session and not opened yet, wherever she is in the list.

const PK := preload("res://src/ui/v4/hero_poster_kit.gd")
const PosterCard := preload("res://src/ui/v4/poster_card.gd")
const HUD := preload("res://src/ui/components/hud.gd")

const COLS := 3
const CARD_GAP := 14
const ROW_GAP := 22
const SORTS: Array[String] = ["power", "rarity", "level", "stars"]
const SORT_NAMES := {"power": "Power", "rarity": "Rarity", "level": "Level", "stars": "Stars"}
const RARITY_RANK := {"legendary": 3, "epic": 2, "rare": 1}
const RARITIES: Array[String] = ["rare", "epic", "legendary"]
const ROLE_CODES := {"guardian": "GRD", "striker": "STR", "caster": "CST", "support": "SUP", "assassin": "ASN"}
const INK := Color("101113")
const SIG := Color("ff4b1f")
const HEAD_H := 176.0
## The catalogue is never wider than this (tablets centre it on the matte).
const MAX_W := 760.0

static var _tab_idx := 0
static var _faction_idx := 0
static var _role_idx := 0
static var _rarity_idx := 0
static var _sort_idx := 0
static var _scroll_y := 0
## Heroes summoned this session that the player hasn't opened yet ("NEW" tags).
static var _new_ids := {}

var _guide_level_id := ""
var _scroll: ScrollContainer
var _list: VBoxContainer
var _hint: Label
var _count_l: Label
var _head: Control
var _head_sig := ""
var _tabs_row: Control
var _sort_l: Label
var _filter_l: Label
var _modal: Control
var _restore_scroll := true
var _card_w := 214.0
## The rarity entrances play on the page's first print only (not on every refresh).
var _intro_left := true


## The summon screen calls this for every hero a summon brings in for the first time.
static func mark_new(hero_id: String) -> void:
	_new_ids[hero_id] = true


## Hero detail calls this when the hero's page opens (clears the "NEW" tag).
static func mark_seen(hero_id: String) -> void:
	_new_ids.erase(hero_id)


static func is_new(hero_id: String) -> bool:
	return _new_ids.has(hero_id)


func setup(params: Dictionary) -> void:
	if params.has("tab"):
		_tab_idx = clampi(int(params["tab"]), 0, 1)
	# Shots: open scrolled this far down the catalogue.
	if params.has("scroll"):
		_scroll_y = int(params["scroll"])
	_build()
	Game.changed.connect(_refresh)
	_refresh()
	if params.has("closeup") and OS.is_debug_build():
		_closeup(str(params["closeup"]))


## Shots (debug builds): one hero's card big over the catalogue, to check her rarity frame up close.
func _closeup(id: String) -> void:
	var dim := ColorRect.new()
	dim.color = Color(PK.MATTE, 0.96)
	dim.mouse_filter = MOUSE_FILTER_IGNORE
	dim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(dim)
	var vw := get_viewport_rect().size
	var w := minf(vw.x - 160.0, 460.0)
	var card := PosterCard.new()
	card.setup(id, {"size": w, "ratio": 1.52, "owned": Game.owns(id), "in_team": Game.formation().has(id)})
	card.position = Vector2((vw.x - w) * 0.5, 60.0)
	add_child(card)
	card.play_intro(0.1)
	if Game.changed.is_connected(_refresh):
		Game.changed.disconnect(_refresh)
	if _scroll:
		_scroll_y = _scroll.scroll_vertical
	_close_modal()


# ------------------------------------------------------------------ build

func _build() -> void:
	var vw := get_viewport_rect().size.x
	# Wider windows (tablets) keep the sheet at phone width, centred on the matte.
	var w := minf(vw, MAX_W)
	var ox := floorf((vw - w) * 0.5)
	_card_w = floorf(minf(230.0, (w - 36.0 - CARD_GAP * (COLS - 1)) / COLS))
	PK.matte(self)
	# The matte line.
	PK.at(self, PK.t("HALO & HORN  ©2026", 12, INK, "mono_bold"), Vector2(ox + 20, 8))
	_count_l = PK.t("", 12, Color(INK, 0.7), "mono")
	_count_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_count_l.size = Vector2(420, 16)
	PK.at(self, _count_l, Vector2(ox + w - 20 - 420, 9))
	# The masthead poster (rebuilt when the page or the lead hero changes).
	_head = Control.new()
	_head.name = "Masthead"
	_head.mouse_filter = MOUSE_FILTER_IGNORE
	_head.position = Vector2(ox + 18, 32)
	_head.size = Vector2(w - 36, HEAD_H)
	add_child(_head)
	# The printed filter tabs.
	_tabs_row = Control.new()
	_tabs_row.name = "Tabs"
	_tabs_row.mouse_filter = MOUSE_FILTER_IGNORE
	_tabs_row.position = Vector2(ox + 18, 32 + HEAD_H + 14)
	_tabs_row.size = Vector2(w - 36, 64)
	add_child(_tabs_row)
	_build_tabs()
	_hint = PK.t("", 12, Color(INK, 0.65), "mono")
	_hint.position = Vector2(ox + 20, 32 + HEAD_H + 84)
	_hint.size = Vector2(w - 40, 16)
	_hint.clip_text = true
	add_child(_hint)
	PK.rule(self, Vector2(ox + 20, 32 + HEAD_H + 106), Vector2(w - 40, 1), Color(INK, 0.4))
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 22)
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_top", 16)
	m.add_theme_constant_override("margin_bottom", 40)
	m.add_theme_constant_override("margin_left", int(ox) + 18)
	m.add_theme_constant_override("margin_right", int(ox) + 18)
	m.add_child(_list)
	_scroll = Kit.scroll(m)
	_scroll.name = "Catalogue"
	_scroll.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_scroll.offset_top = 32 + HEAD_H + 108
	add_child(_scroll)
	PK.grain(self)


## Masthead: band with the lead's print, the giant page word, the count and the page index.
func _build_head(owned_total: int, total: int) -> void:
	var lead := ""
	for id: Variant in Game.formation():
		if str(id) != "" and lead == "":
			lead = str(id)
	if lead == "":
		lead = "noctaire"
	var sig := "%d|%s|%s|%d" % [_tab_idx, lead, HeroArt.art_key(lead, Game.equipped_skin(lead)), owned_total]
	if sig == _head_sig:
		return
	_head_sig = sig
	for c in _head.get_children():
		_head.remove_child(c)
		c.queue_free()
	var hw := _head.size.x
	var hh := _head.size.y
	var p := PK.poster(_head, Rect2(Vector2.ZERO, _head.size))
	var band := 170.0
	PK.rect(p, Rect2(0, 0, band, hh), PK.BAND)
	var ht := PK.halftone_print(lead, Game.equipped_skin(lead), Vector2(band, hh), 6.0, PK.PRINT, 1.3)
	p.add_child(ht)
	PK.at(p, PK.t("HH", 22, PK.PAPER, "wide_black"), Vector2(14, 12))
	PK.at(p, PK.t("™", 10, PK.PAPER, "mono"), Vector2(56, 13))
	PK.at(p, PK.t("CATALOGUE\nNo.%02d" % owned_total, 11, Color(PK.PAPER, 0.85), "mono_bold"), Vector2(14, hh - 44))
	var word := "HEROES" if _tab_idx == 0 else "CODEX"
	var bb := "%s[color=#%s].[/color]" % [word, SIG.to_html(false)]
	# As big as the masthead allows, from inside the band to the right-hand rule.
	var room := hw - 44.0 - 92.0 - 14.0
	var fs := clampi(int(120.0 * room / maxf(PK.text_w(word + ".", 120), 1.0)), 90, 150)
	PK.giant(p, bb, fs, Vector2(92, hh - fs * 1.02), Vector2(hw * 1.2, fs * 1.4),
		[[Rect2(0, 0, band, hh), PK.PAPER], [Rect2(band, 0, hw - band - 44, hh), INK]], 0, "compressed", false)
	# Right rule with the count and the page index as turned labels.
	PK.rule(p, Vector2(hw - 44, 0), Vector2(1, hh))
	PK.at(p, PK.vlabel("%02d / %02d" % [owned_total, total], 12, INK), Vector2(hw - 14, 12))
	# The page index: the two pages here, then the print album (a screen of its own).
	var ix := hw - 44.0 - 350.0
	for i in 3:
		var on := i == _tab_idx
		var l := PK.t("%02d %s" % [i + 1, ["HEROES", "CODEX", "PRINTS"][i]], 13, SIG if on else INK, "mono_bold")
		PK.at(p, l, Vector2(ix + i * 116, 14))
		if on:
			PK.rect(p, Rect2(ix + i * 116, 36, PK.text_w(l.text, 13, "mono_bold"), 3), SIG)
		var b := _hit(_head, Rect2(ix + i * 116 - 10, 0, 114, 88), _select_tab.bind(i) if i < 2 else func() -> void: UI.go("prints"))
		b.name = "Page_%d" % i if i < 2 else "PrintsPage"
		if i > 0:
			PK.at(p, PK.t("/", 13, Color(INK, 0.35), "mono"), Vector2(ix + i * 116 - 14, 14))


## The filter tabs: ALL + the roles, then SORT and FILTER, printed on the matte.
func _build_tabs() -> void:
	for c in _tabs_row.get_children():
		_tabs_row.remove_child(c)
		c.queue_free()
	var tw := _tabs_row.size.x
	var n := 1 + Kit.ROLES.size()
	var cw := 74.0
	for i in n:
		var on := i == _role_idx
		var col := SIG if on else INK
		var x := i * cw
		var text := "ALL" if i == 0 else str(ROLE_CODES.get(Kit.ROLES[i - 1], ""))
		if i > 0:
			var ic := Kit.icon("role_" + Kit.ROLES[i - 1], 24, col)
			ic.size = Vector2(24, 24)
			PK.at(_tabs_row, ic, Vector2(x + (cw - 24) * 0.5, 2))
		else:
			var a := PK.t("*", 20, col, "mono_bold")
			a.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			a.size = Vector2(cw, 24)
			PK.at(_tabs_row, a, Vector2(x, 2))
		var l := PK.t(text, 12, col, "mono_bold")
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.size = Vector2(cw, 16)
		PK.at(_tabs_row, l, Vector2(x, 32))
		if on:
			PK.rect(_tabs_row, Rect2(x + cw * 0.5 - 16, 52, 32, 3), SIG)
		if i < n - 1:
			PK.rule(_tabs_row, Vector2(x + cw, 8), Vector2(1, 38), Color(INK, 0.25))
		var idx := i
		var b := _hit(_tabs_row, Rect2(x, -12, cw, 88), func() -> void:
			_role_idx = idx
			# Deferred: the refresh reprints the tabs, this button included.
			_refresh.call_deferred(true))
		b.name = "Role_%d" % i
	# SORT and FILTER on the right.
	var sx := tw - 210.0
	PK.at(_tabs_row, PK.t("SORT", 10, Color(INK, 0.6), "mono_bold"), Vector2(sx, 6))
	_sort_l = PK.t(str(SORT_NAMES[SORTS[_sort_idx]]).to_upper() + " v", 15, INK, "mono_bold")
	PK.at(_tabs_row, _sort_l, Vector2(sx, 26))
	var sb := _hit(_tabs_row, Rect2(sx - 10, -12, 110, 88), _open_sort)
	sb.name = "Sort"
	var fx := tw - 96.0
	var active := _faction_idx > 0 or _rarity_idx > 0
	PK.at(_tabs_row, PK.t("FILTER", 10, Color(INK, 0.6), "mono_bold"), Vector2(fx, 6))
	var ft := "ALL"
	if active:
		var parts: Array[String] = []
		if _faction_idx > 0:
			parts.append(str(Kit.FACTION_NAMES.get(Kit.FACTIONS[_faction_idx - 1], "")).substr(0, 3).to_upper())
		if _rarity_idx > 0:
			parts.append(str(Kit.RARITY_TIER.get(RARITIES[_rarity_idx - 1], "")))
		ft = " ".join(parts)
	_filter_l = PK.t(ft + " v", 15, SIG if active else INK, "mono_bold")
	PK.at(_tabs_row, _filter_l, Vector2(fx, 26))
	var fb := _hit(_tabs_row, Rect2(fx - 10, -12, 106, 88), _open_filter)
	fb.name = "FilterChip"
	PK.rule(_tabs_row, Vector2(sx - 18, 8), Vector2(1, 38), Color(INK, 0.25))


func _hit(parent: Control, r: Rect2, cb: Callable) -> Button:
	var b := Button.new()
	b.theme_type_variation = &"BareButton"
	b.focus_mode = FOCUS_NONE
	b.mouse_filter = MOUSE_FILTER_PASS
	b.position = r.position
	b.size = r.size
	parent.add_child(b)
	Kit._connect_pressed(b, cb, "tab")
	return b


# ------------------------------------------------------------------ refresh

func _refresh(reset_scroll: bool = false) -> void:
	if not is_inside_tree() or _list == null:
		return
	var keep := _scroll.scroll_vertical
	# First-session guidance: the hero to level next.
	_guide_level_id = Guide.level_target() if Guide.step() == "level" else ""
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()

	var owned_ids: Array[String] = []
	var unowned_ids: Array[String] = []
	var total := 0
	var owned_total := 0
	for d: Dictionary in Game.all_hero_defs():
		total += 1
		var id := str(d.id)
		var own := Game.owns(id)
		if own:
			owned_total += 1
		if not _passes(d):
			continue
		if own:
			owned_ids.append(id)
		elif _tab_idx == 1:
			unowned_ids.append(id)
	_sort_ids(owned_ids)
	unowned_ids.sort_custom(func(a: String, b: String) -> bool:
		var ra := int(RARITY_RANK.get(str(Game.hero_def(a).rarity), 0))
		var rb := int(RARITY_RANK.get(str(Game.hero_def(b).rarity), 0))
		return ra > rb if ra != rb else a < b)

	_build_head(owned_total, total)
	_build_tabs()
	_count_l.text = "%02d OF %02d SUMMONED  ·  SORTED BY %s" % [owned_total, total, str(SORT_NAMES[SORTS[_sort_idx]]).to_upper()]
	if _tab_idx == 0:
		_hint.text = "HEROES YOU CAN PLACE IN YOUR TEAM.  TAP ONE FOR HER FILE."
	else:
		_hint.text = "EVERY HERO WHO ANSWERS THE PORTAL.  GREY ONES ARE STILL TO SUMMON."

	var shown: Array[String] = []
	shown.append_array(owned_ids)
	shown.append_array(unowned_ids)
	if shown.is_empty():
		var msg := "No heroes match these filters." if owned_total > 0 or _tab_idx == 1 else "No heroes yet. Summon some!"
		var es := PK.t(msg.to_upper(), 14, Color(INK, 0.6), "mono_bold")
		es.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		es.custom_minimum_size = Vector2(0, 300)
		es.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_list.add_child(es)
	else:
		var g := GridContainer.new()
		g.columns = COLS
		g.add_theme_constant_override("h_separation", CARD_GAP)
		g.add_theme_constant_override("v_separation", ROW_GAP)
		var n := 0
		for id in shown:
			var card := _card(id, shown)
			g.add_child(card)
			if _intro_left and (n < COLS * 3 or is_new(id)):
				card.play_intro(0.12 + 0.07 * mini(n, 12))
			n += 1
		_list.add_child(g)
		_intro_left = false
	if _tab_idx == 0 and owned_total < total:
		_list.add_child(_codex_teaser(total - owned_total))

	if reset_scroll:
		_scroll.scroll_vertical = 0
	elif _restore_scroll:
		_restore_scroll = false
		_set_scroll.call_deferred(_scroll_y)
	else:
		_set_scroll.call_deferred(keep)


func _set_scroll(y: int) -> void:
	if not is_inside_tree():
		return          # left the screen in the same frame as a refresh
	await get_tree().process_frame
	if is_instance_valid(_scroll):
		_scroll.scroll_vertical = y


func _passes(d: Dictionary) -> bool:
	if _faction_idx > 0 and str(d.faction) != Kit.FACTIONS[_faction_idx - 1]:
		return false
	if _role_idx > 0 and str(d.role) != Kit.ROLES[_role_idx - 1]:
		return false
	if _rarity_idx > 0 and str(d.rarity) != RARITIES[_rarity_idx - 1]:
		return false
	return true


func _sort_ids(ids: Array[String]) -> void:
	var key := {}
	for id in ids:
		var h := Game.hero(id)
		var power := int(Game.hero_power(id))
		var rank := int(RARITY_RANK.get(str(Game.hero_def(id).rarity), 0))
		match SORTS[_sort_idx]:
			"rarity":
				key[id] = [rank, int(h.get("stars", 1)), power]
			"level":
				key[id] = [int(h.get("level", 1)), int(h.get("stars", 1)), power]
			"stars":
				key[id] = [int(h.get("stars", 1)), rank, power]
			_:
				key[id] = [power, rank, 0]
	ids.sort_custom(func(a: String, b: String) -> bool:
		var ka: Array = key[a]
		var kb: Array = key[b]
		for i in ka.size():
			if ka[i] != kb[i]:
				return ka[i] > kb[i]
		return a < b)


func _card(id: String, browse: Array[String]) -> PosterCard:
	var own := Game.owns(id)
	var dot := false
	if own:
		if Game.formation().has(id) and Game.upgrade_ready(id):
			dot = true
		else:
			var sc := Game.star_up_cost(id)
			dot = not sc.is_empty() and int(sc.get("shards_have", 0)) >= int(sc.get("shards", 1))
	var card := PosterCard.new()
	card.setup(id, {
		"size": _card_w, "ratio": 1.52, "owned": own, "new": own and is_new(id), "dot": dot,
		"in_team": own and Game.formation().has(id),
		"on_pressed": func() -> void: _open(id, browse),
	})
	if id == _guide_level_id:
		Guide.mark(card, true, 0)
	# An awakened Legendary carries her tier: a small foil seal at the card's head (LegendKit).
	var aw := int(Game.awaken_tier(id)) if own else 0
	if aw > 0:
		var k := _card_w / 218.0
		var side := roundf(46.0 * k)
		var mk := LegendKit.awaken_mark(aw, side)
		# Over the art's bottom-right corner, just above the label strip (62 * k tall).
		mk.position = Vector2(_card_w - side - 6.0 * k, roundf(_card_w * 1.52) - 62.0 * k - side + 6.0 * k)
		card.add_child(mk)
	# Her birthday (the calendar): a small red tag over the art's top edge, today only.
	if own and CalendarRules.birthday(id) != "" and CalendarRules.birthday(id) == CalendarRules.md(Game.today()):
		var k2 := _card_w / 218.0
		var tag := ColorRect.new()
		tag.mouse_filter = MOUSE_FILTER_IGNORE
		tag.color = Color("ff4b1f")
		tag.size = Vector2(roundf(96.0 * k2), roundf(20.0 * k2))
		tag.position = Vector2(_card_w - tag.size.x - 8.0 * k2, 8.0 * k2)
		tag.rotation = 0.04
		card.add_child(tag)
		var tl := Kit.label("BIRTHDAY", int(roundf(10.0 * k2)), Color("f5f4f0"), "mono_bold")
		tl.mouse_filter = MOUSE_FILTER_IGNORE
		tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tl.size = tag.size
		tl.position = Vector2(0, roundf(2.0 * k2))
		tag.add_child(tl)
	return card


## Under a short roster: how many heroes are still out there, with a jump to the codex.
func _codex_teaser(missing: int) -> Control:
	var row := Control.new()
	row.custom_minimum_size = Vector2(0, 96)
	# Inside the roster's scroll: let finger drags through (a plain Control stops them).
	row.mouse_filter = MOUSE_FILTER_PASS
	var w := minf(get_viewport_rect().size.x, MAX_W) - 36.0
	PK.rule(row, Vector2(0, 8), Vector2(w, 1), Color(INK, 0.4))
	PK.at(row, PK.t("%02d MORE HERO%s ANSWER THE SUMMON PORTAL." % [missing, "" if missing == 1 else "ES"], 13, INK, "mono_bold"), Vector2(0, 30))
	var go := PK.t("02 CODEX ->", 15, SIG, "mono_bold")
	go.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	go.size = Vector2(200, 20)
	PK.at(row, go, Vector2(w - 200, 28))
	PK.rect(row, Rect2(w - PK.text_w(go.text, 15, "mono_bold"), 52, PK.text_w(go.text, 15, "mono_bold"), 3), SIG)
	var b := _hit(row, Rect2(0, 6, w, 88), _select_tab.bind(1))
	b.name = "CodexLink"
	return row


## Switches the page (0 Heroes, 1 Codex).
func _select_tab(i: int) -> void:
	if i == _tab_idx:
		return
	_tab_idx = i
	# Deferred: the refresh reprints the masthead, the pressed page label included.
	_refresh.call_deferred(true)


# ------------------------------------------------------------------ sort & filter

func _cycle_sort() -> void:
	_sort_idx = (_sort_idx + 1) % SORTS.size()
	_refresh(true)


func _open_sort() -> void:
	var col := Kit.vbox(10)
	col.custom_minimum_size.x = 420
	for i in SORTS.size():
		var idx := i
		var text := str(SORT_NAMES[SORTS[i]])
		var cb := func() -> void:
			_sort_idx = idx
			_close_modal()
			_refresh(true)
		var b := Kit.primary_button(text, cb, "check") if i == _sort_idx else Kit.light_button(text, cb)
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		col.add_child(b)
	_modal = UI.popup("Sort By", col, Callable(), 500.0, true)


func _open_filter() -> void:
	var col := Kit.vbox(14)
	col.custom_minimum_size.x = 520
	col.add_child(Kit.section_header("Faction", 26, Kit.INK, true))
	var fopts: Array = ["ALL"]
	for f: String in Kit.FACTIONS:
		fopts.append({"icon": "faction_" + f})
	col.add_child(Kit.filter_chips(fopts, _faction_idx, func(i: int) -> void:
		_faction_idx = i
		_refresh(true)))
	col.add_child(Kit.section_header("Rarity", 26, Kit.INK, true))
	col.add_child(Kit.filter_chips(["ALL", "I", "II", "III"], _rarity_idx, func(i: int) -> void:
		_rarity_idx = i
		_refresh(true)))
	var note := Kit.label("I Rare  ·  II Epic  ·  III Legendary", 20, Kit.TEXT_DIM, "bold")
	col.add_child(note)
	var row := Kit.hbox(14)
	var reset := Kit.light_button("Reset", func() -> void:
		_faction_idx = 0
		_rarity_idx = 0
		_role_idx = 0
		_close_modal()
		_refresh(true), "refresh")
	var ok := Kit.primary_button("OK", _close_modal)
	reset.size_flags_horizontal = SIZE_EXPAND_FILL
	ok.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(reset)
	row.add_child(ok)
	col.add_child(Kit.spacer(0, 4))
	col.add_child(row)
	_modal = UI.popup("Filter", col, Callable(), 600.0, true)


func _close_modal() -> void:
	if _modal and is_instance_valid(_modal):
		UI.close_modal(_modal)
	_modal = null


func _open(id: String, browse: Array[String]) -> void:
	_scroll_y = _scroll.scroll_vertical
	UI.go("hero_detail", {"hero_id": id, "browse": Array(browse)})
