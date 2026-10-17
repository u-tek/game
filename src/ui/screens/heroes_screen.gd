extends Control
## Screen "heroes" (style v2 roster, docs/dev/ui-style-v2.md section 6): a dark header strip
## with the page tabs (HEROES = owned heroes, CODEX = every hero, the ones still to be
## summoned greyed out like a dex) and the sort dropdown, then a light hatched page with
## square filter chips (ALL + the five roles, plus a Filter chip for faction and rarity),
## a hint line and the 4-column grid of tall portrait cards (Kit.portrait_card: waist-up art,
## role hex + tier numeral, "LV." and the level bottom-left, name, rarity chevrons).
## A red dot marks a team hero who can level or star up now, an "N" a hero summoned this
## session and not opened yet. Tap a card to open hero_detail (browse = the shown order).
## Tabs, filters, sort and scroll position are remembered for the session (static vars).
## Params: tab: 0 | 1 (Heroes / Codex).

const COLS := 4
const CARD_GAP := 12
const ROW_GAP := 18
const SORTS: Array[String] = ["power", "rarity", "level", "stars"]
const SORT_NAMES := {"power": "Power", "rarity": "Rarity", "level": "Level", "stars": "Stars"}
const RARITY_RANK := {"legendary": 3, "epic": 2, "rare": 1}
const RARITIES: Array[String] = ["rare", "epic", "legendary"]

static var _tab_idx := 0
static var _faction_idx := 0
static var _role_idx := 0
static var _rarity_idx := 0
static var _sort_idx := 0
static var _scroll_y := 0
## Heroes summoned this session that the player hasn't opened yet ("N" badges).
static var _new_ids := {}

var _guide_level_id := ""
var _scroll: ScrollContainer
var _list: VBoxContainer
var _hint: Label
var _sort_btn: Button
var _filter_chip: Button
var _modal: Control
var _restore_scroll := true
var _card_w := 160.0


## The summon screen calls this for every hero a summon brings in for the first time.
static func mark_new(hero_id: String) -> void:
	_new_ids[hero_id] = true


## Hero detail calls this when the hero's page opens (clears the "N" badge).
static func mark_seen(hero_id: String) -> void:
	_new_ids.erase(hero_id)


static func is_new(hero_id: String) -> bool:
	return _new_ids.has(hero_id)


func setup(params: Dictionary) -> void:
	if params.has("tab"):
		_tab_idx = clampi(int(params["tab"]), 0, 1)
	_build()
	Game.changed.connect(_refresh)
	_refresh()


func _exit_tree() -> void:
	if Game.changed.is_connected(_refresh):
		Game.changed.disconnect(_refresh)
	if _scroll:
		_scroll_y = _scroll.scroll_vertical
	_close_modal()


# ------------------------------------------------------------------ build

func _build() -> void:
	var w := get_viewport_rect().size.x
	_card_w = floorf(minf(160.0, (w - 36.0 - CARD_GAP * (COLS - 1)) / COLS))

	# Dark header strip: page tabs left, the sort dropdown right. The active tab is a white
	# plate that runs into the light page below.
	var head := Kit.hbox(10)
	head.set_anchors_and_offsets_preset(PRESET_TOP_WIDE)
	head.offset_left = 16
	head.offset_right = -16
	head.offset_top = 10
	head.offset_bottom = 10 + Kit.BUTTON_H
	var tabs := Kit.tab_strip([{"text": "Heroes", "icon": "nav_heroes"}, {"text": "Codex", "icon": "codex"}], _tab_idx, func(i: int) -> void:
		_tab_idx = i
		_refresh(true), 196.0)
	head.add_child(tabs)
	head.add_child(Kit.spacer(0, 0, true))
	_sort_btn = Kit.secondary_button("", _open_sort, "sort")
	_sort_btn.name = "Sort"
	_sort_btn.custom_minimum_size = Vector2(176, Kit.BUTTON_H)
	_sort_btn.add_theme_font_override("font", Kit.font("cond_bold"))
	_sort_btn.add_theme_font_size_override("font_size", 28)
	head.add_child(_sort_btn)
	add_child(head)

	var page := Kit.page_bg("light")
	page.offset_top = 10 + Kit.BUTTON_H
	add_child(page)

	var col := Kit.vbox(8)
	col.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	col.offset_top = 10 + Kit.BUTTON_H + 16
	col.offset_left = 16
	col.offset_right = -16
	add_child(col)

	var chips := Kit.hbox(4)
	var opts: Array = ["ALL"]
	for r: String in Kit.ROLES:
		opts.append({"icon": "role_" + r})
	var role_chips := Kit.filter_chips(opts, _role_idx, func(i: int) -> void:
		_role_idx = i
		_refresh(true))
	role_chips.name = "RoleChips"
	chips.add_child(role_chips)
	chips.add_child(Kit.spacer(0, 0, true))
	# Faction / rarity filter: one more chip that opens the filter dialog (cyan when active).
	var fc := Kit.filter_chips([{"icon": "filter"}], -1, Callable())
	_filter_chip = fc.get_child(0) as Button
	_filter_chip.name = "FilterChip"
	_filter_chip.button_group = null
	_filter_chip.pressed.connect(func() -> void:
		Kit.sfx("tap")
		_filter_chip.set_pressed_no_signal(_faction_idx > 0 or _rarity_idx > 0)
		_open_filter())
	chips.add_child(fc)
	col.add_child(chips)

	_hint = Kit.label("", 20, Kit.TEXT_DIM, "bold")
	_hint.custom_minimum_size.y = 26
	col.add_child(_hint)

	_list = Kit.vbox(14)
	var m := Kit.margin(_list, 0, 0)
	m.add_theme_constant_override("margin_top", 8)
	m.add_theme_constant_override("margin_bottom", 28)
	_scroll = Kit.scroll(m)
	col.add_child(_scroll)


# ------------------------------------------------------------------ refresh

func _refresh(reset_scroll: bool = false) -> void:
	if not is_inside_tree() or _list == null:
		return
	var keep := _scroll.scroll_vertical
	_sort_btn.text = str(SORT_NAMES[SORTS[_sort_idx]]).to_upper()
	_filter_chip.set_pressed_no_signal(_faction_idx > 0 or _rarity_idx > 0)
	for c in _filter_chip.get_children():
		if c.name == "FacMark":
			_filter_chip.remove_child(c)
			c.queue_free()
	if _faction_idx > 0:
		var fm := Kit.faction_icon(Kit.FACTIONS[_faction_idx - 1], 30)
		fm.name = "FacMark"
		fm.position = Vector2(_filter_chip.custom_minimum_size.x - 34, 4)
		fm.size = Vector2(30, 30)
		_filter_chip.add_child(fm)
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

	if _tab_idx == 0:
		_hint.text = "Heroes you can place in your team.  %d of %d summoned." % [owned_total, total]
	else:
		_hint.text = "Every hero who answers the portal.  %d of %d collected." % [owned_total, total]

	var shown: Array[String] = []
	shown.append_array(owned_ids)
	shown.append_array(unowned_ids)
	if shown.is_empty():
		var es := Kit.empty_state("No heroes match these filters." if owned_total > 0 or _tab_idx == 1 else "No heroes yet. Summon some!", "heroes", true)
		es.custom_minimum_size.y = 420
		_list.add_child(es)
	else:
		var g := Kit.grid(COLS, CARD_GAP)
		g.add_theme_constant_override("v_separation", ROW_GAP)
		g.size_flags_horizontal = SIZE_SHRINK_BEGIN
		for id in shown:
			g.add_child(_card(id, shown))
		# Left-aligned like a roster, the full 4-column width centred on the page.
		var gw := COLS * _card_w + (COLS - 1) * CARD_GAP
		var pad := maxi(0, int((get_viewport_rect().size.x - 32.0 - gw) * 0.5))
		var gm := Kit.margin(g, 0, 0)
		gm.add_theme_constant_override("margin_left", pad)
		_list.add_child(gm)
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


func _card(id: String, browse: Array[String]) -> Control:
	var own := Game.owns(id)
	var dot := false
	if own:
		if Game.formation().has(id) and Game.upgrade_ready(id):
			dot = true
		else:
			var sc := Game.star_up_cost(id)
			dot = not sc.is_empty() and int(sc.get("shards_have", 0)) >= int(sc.get("shards", 1))
	var card := Kit.portrait_card(id, {
		"size": _card_w, "owned": own, "new": own and is_new(id), "dot": dot,
		"on_pressed": func() -> void: _open(id, browse),
	})
	if id == _guide_level_id:
		Guide.mark(card, true, 0)
	return card


## Under a short roster: how many heroes are still out there, with a jump to the codex.
func _codex_teaser(missing: int) -> Control:
	var row := Kit.panel("light_inset", 12)
	var h := Kit.hbox(14)
	h.add_child(Kit.hex_badge("summon", 56, Color("182640"), Color.WHITE))
	var t := Kit.label("%d more hero%s answer the Summon portal." % [missing, "" if missing == 1 else "es"], 22, Kit.TEXT, "bold")
	t.size_flags_horizontal = SIZE_EXPAND_FILL
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	h.add_child(t)
	var b := Kit.light_button("Codex", _select_tab.bind(1), "codex")
	b.custom_minimum_size.x = 176
	h.add_child(b)
	row.add_child(h)
	return row


## Presses a page tab (its toggled handler switches the page).
func _select_tab(i: int) -> void:
	var tabs := find_child("TabStrip", true, false) as HBoxContainer
	if tabs and i < tabs.get_child_count():
		(tabs.get_child(i) as Button).button_pressed = true


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
		_close_modal()
		_reselect_roles()
		_refresh(true), "refresh")
	var ok := Kit.primary_button("OK", _close_modal)
	reset.size_flags_horizontal = SIZE_EXPAND_FILL
	ok.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(reset)
	row.add_child(ok)
	col.add_child(Kit.spacer(0, 4))
	col.add_child(row)
	_modal = UI.popup("Filter", col, Callable(), 600.0, true)


## Back to ALL roles (pressing the chip runs its handler).
func _reselect_roles() -> void:
	var rc := find_child("RoleChips", true, false) as HBoxContainer
	if rc and rc.get_child_count() > 0:
		(rc.get_child(0) as Button).button_pressed = true


func _close_modal() -> void:
	if _modal and is_instance_valid(_modal):
		UI.close_modal(_modal)
	_modal = null


func _open(id: String, browse: Array[String]) -> void:
	_scroll_y = _scroll.scroll_vertical
	UI.go("hero_detail", {"hero_id": id, "browse": Array(browse)})
