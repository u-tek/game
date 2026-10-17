extends Control
## Screen "gear" (bottom-nav Gear tab; params open: gear uid or "first", pick: true), style v2: the gear inventory on a light page.
## A dark header with the GEAR tab, the item count and the sort dropdown (tier, score, slot);
## square filter chips (ALL + the four slots, and SPARE for unworn pieces); a 4-column grid of
## equipment tiles (Kit.equip_slot: slot glyph, tier numeral, tier-colored strip) with the
## name and the wearer under each; a red dot marks a spare piece that would improve a team
## hero. Tap a tile for the item sheet: stats, who wears it, and the actions: Equip to a hero
## (a hero list showing what each one wears in that slot and the score change), Unequip,
## Open the wearer's page, or Salvage a spare piece for gold and dust.

const COLS := 4
const SLOTS: Array[String] = ["weapon", "armor", "helm", "charm"]
const SORTS: Array[String] = ["tier", "score", "slot"]
const SORT_NAMES := {"tier": "Tier", "score": "Score", "slot": "Slot"}

static var _slot_idx := 0
static var _spare_only := false
static var _sort_idx := 0

var _grid: GridContainer
var _scroll: ScrollContainer
var _count: Label
var _hint: Label
var _empty: Control
var _sort_btn: Button
var _spare_chip: Button
var _modal: Control
var _tile := 150.0
var _sig := ""


func setup(params: Dictionary) -> void:
	_build()
	Game.changed.connect(_refresh)
	_refresh()
	# Shot/testing helpers: open: <gear uid> | "first" (item sheet), pick: true (its hero list).
	var o := str(params.get("open", ""))
	if o == "first":
		var items := _items()
		o = str(items[0].uid) if not items.is_empty() else ""
	if o != "":
		if bool(params.get("pick", false)):
			_open_hero_pick.call_deferred(o)
		else:
			_open.call_deferred(o)


func _exit_tree() -> void:
	if Game.changed.is_connected(_refresh):
		Game.changed.disconnect(_refresh)
	_close_modal()


func _build() -> void:
	var w := get_viewport_rect().size.x
	# Tiles span the whole gutter (16 px page margins, 4 px grid margins), like the heroes grid.
	_tile = floorf((w - 32.0 - 8.0 - (COLS - 1) * 14.0) / COLS)
	# Dark header strip with the page tab, then the light page.
	var head := Kit.hbox(12)
	head.set_anchors_and_offsets_preset(PRESET_TOP_WIDE)
	head.offset_left = 16
	head.offset_right = -16
	head.offset_top = 10
	head.offset_bottom = 10 + Kit.BUTTON_H
	head.add_child(Kit.tab_strip([{"text": "Gear", "icon": "nav_gear"}], 0, Callable(), 200.0))
	head.add_child(Kit.spacer(0, 0, true))
	var cv := Kit.vbox(-6)
	cv.mouse_filter = MOUSE_FILTER_IGNORE
	cv.alignment = BoxContainer.ALIGNMENT_CENTER
	cv.add_child(Kit.label("ITEMS", 16, Kit.INK_DIM, "cond_bold"))
	_count = Kit.label("", 34, Kit.INK, "title")
	cv.add_child(_count)
	head.add_child(cv)
	_sort_btn = Kit.secondary_button("", _open_sort, "sort")
	_sort_btn.name = "Sort"
	_sort_btn.custom_minimum_size = Vector2(170, Kit.BUTTON_H)
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
	for s in SLOTS:
		opts.append({"icon": "gear_" + s})
	var sc := Kit.filter_chips(opts, _slot_idx, func(i: int) -> void:
		_slot_idx = i
		_refresh(true))
	sc.name = "SlotChips"
	chips.add_child(sc)
	chips.add_child(Kit.spacer(0, 0, true))
	var spare := Kit.filter_chips(["SPARE"], 0 if _spare_only else -1, Callable())
	_spare_chip = spare.get_child(0) as Button
	_spare_chip.name = "SpareChip"
	_spare_chip.button_group = null
	_spare_chip.custom_minimum_size.x = 120
	_spare_chip.toggled.connect(func(on: bool) -> void:
		Kit.sfx("tap")
		_spare_only = on
		_refresh(true))
	chips.add_child(spare)
	col.add_child(chips)
	_hint = Kit.label("", 20, Kit.TEXT_DIM, "bold")
	_hint.custom_minimum_size.y = 26
	col.add_child(_hint)

	_grid = Kit.grid(COLS, 14)
	_grid.add_theme_constant_override("v_separation", 12)
	var gm := Kit.margin(_grid, 4, 8)
	gm.add_theme_constant_override("margin_bottom", 28)
	_scroll = Kit.scroll(gm)
	col.add_child(_scroll)
	_empty = Kit.empty_state("", "nav_gear", true)
	_empty.size_flags_vertical = SIZE_EXPAND_FILL
	col.add_child(_empty)


# ------------------------------------------------------------------ data

func _items() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var want := "" if _slot_idx == 0 else SLOTS[_slot_idx - 1]
	for it: Dictionary in Game.gear_items():
		if want != "" and str(it.get("slot", "")) != want:
			continue
		if _spare_only and str(it.get("equipped_by", "")) != "":
			continue
		out.append(it)
	var score := {}
	for it in out:
		score[str(it.uid)] = int(Game.gear_score(str(it.uid)))
	var mode: String = SORTS[_sort_idx]
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ka: Array = _key(a, mode, score)
		var kb: Array = _key(b, mode, score)
		for i in ka.size():
			if ka[i] != kb[i]:
				return ka[i] > kb[i]
		return str(a.uid) < str(b.uid))
	return out


static func _key(it: Dictionary, mode: String, score: Dictionary) -> Array:
	var s := int(score.get(str(it.uid), 0))
	var slot_rank := SLOTS.size() - SLOTS.find(str(it.slot))
	match mode:
		"score":
			return [s, int(it.tier)]
		"slot":
			return [slot_rank, int(it.tier), s]
	return [int(it.tier), slot_rank, s]


## Best gain this spare piece would give a team hero in its slot (0 = none).
func _team_gain(it: Dictionary) -> int:
	if str(it.get("equipped_by", "")) != "":
		return 0
	var s := int(Game.gear_score(str(it.uid)))
	var best := 0
	for id: Variant in Game.formation():
		var hid := str(id)
		if hid == "":
			continue
		var worn := str(Game.hero(hid).get("gear", {}).get(str(it.slot), ""))
		var cur := int(Game.gear_score(worn)) if worn != "" else 0
		best = maxi(best, s - cur)
	return best


# ------------------------------------------------------------------ refresh

func _refresh(reset_scroll: bool = false) -> void:
	if not is_inside_tree() or _grid == null:
		return
	_sort_btn.text = str(SORT_NAMES[SORTS[_sort_idx]]).to_upper()
	var all := Game.gear_items()
	var worn := 0
	for it in all:
		if str(it.get("equipped_by", "")) != "":
			worn += 1
	_count.text = str(all.size())
	_hint.text = "%d worn  ·  %d spare.  Tap a piece to equip, compare or salvage it." % [worn, all.size() - worn]
	var items := _items()
	var sig := JSON.stringify(items) + JSON.stringify(Game.formation()) + str(_sort_idx)
	if sig == _sig and not reset_scroll:
		return
	_sig = sig
	var keep := _scroll.scroll_vertical
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	_empty.visible = items.is_empty()
	_scroll.visible = not items.is_empty()
	if items.is_empty():
		var msg := "No spare gear here." if _spare_only else ("No gear yet." if _slot_idx == 0 else "No gear in this slot yet.")
		(_empty.get_child(_empty.get_child_count() - 1) as Label).text = msg + " Clear stages and collect the Sanctum to find some."
	for it in items:
		_grid.add_child(_cell(it))
	if reset_scroll:
		_scroll.scroll_vertical = 0
	else:
		_restore.call_deferred(keep)


func _restore(y: int) -> void:
	if is_instance_valid(_scroll):
		_scroll.scroll_vertical = y


func _cell(it: Dictionary) -> Control:
	var cell := Kit.vbox(2)
	cell.custom_minimum_size.x = _tile
	var uid := str(it.uid)
	var tile := Kit.equip_slot(str(it.slot), it, _tile, func() -> void: _open(uid))
	if _team_gain(it) > 0:
		Kit.set_dot(tile, true, 22, Vector2(-4, -4))
	cell.add_child(tile)
	var n := Kit.label(str(it.get("name", "")), 19, Kit.TEXT, "cond_bold")
	n.clip_text = true
	n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	n.custom_minimum_size.x = _tile
	cell.add_child(n)
	var who := str(it.get("equipped_by", ""))
	var w := Kit.label(str(Game.hero_def(who).get("name", who)).to_upper() if who != "" else "SPARE", 17,
		Kit.ACCENT_DEEP if who != "" else Kit.TEXT_DIM, "cond_bold")
	cell.add_child(w)
	return cell


# ------------------------------------------------------------------ sort

func _open_sort() -> void:
	var col := Kit.vbox(10)
	col.custom_minimum_size.x = 420
	for i in SORTS.size():
		var idx := i
		var text := "By " + str(SORT_NAMES[SORTS[i]])
		var cb := func() -> void:
			_sort_idx = idx
			_close_modal()
			_refresh(true)
		var b := Kit.primary_button(text, cb, "check") if i == _sort_idx else Kit.light_button(text, cb)
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		col.add_child(b)
	_modal = UI.popup("Sort By", col, Callable(), 500.0, true)


# ------------------------------------------------------------------ item sheet

func _open(uid: String) -> void:
	var it := Game.gear_item(uid)
	if it.is_empty():
		return
	_close_modal()
	var col := Kit.vbox(12)
	col.custom_minimum_size.x = 540
	var top := Kit.hbox(18)
	top.add_child(Kit.equip_slot(str(it.slot), it, 128))
	var info := Kit.vbox(2)
	info.size_flags_horizontal = SIZE_EXPAND_FILL
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	var nl := Kit.label(str(it.get("name", "")), 32, Kit.TEXT, "title")
	nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(nl)
	var tr := Kit.hbox(8)
	tr.add_child(Kit.tag("TIER %s" % Kit.roman(int(it.tier)), Kit.tier_color(int(it.tier)), Color.WHITE, 18))
	tr.add_child(Kit.label(str(Kit.GEAR_SLOT_NAMES.get(str(it.slot), "Gear")).to_upper(), 20, Kit.TEXT_DIM, "cond_bold"))
	info.add_child(tr)
	var sc := Kit.hbox(6)
	sc.add_child(Kit.label("SCORE", 18, Kit.TEXT_DIM, "cond_bold"))
	sc.add_child(Kit.label(Kit.format_full(int(Game.gear_score(uid))), 30, Kit.ACCENT_DEEP, "cond_bold"))
	info.add_child(sc)
	top.add_child(info)
	col.add_child(top)
	col.add_child(Kit.header_bar("Stats"))
	var stats: Dictionary = it.get("stats", {})
	var i := 0
	for k: Variant in stats:
		var rp := Kit.panel("row" if i % 2 == 0 else "light_inset", 0)
		rp.add_child(Kit.margin(Kit.stat_row(str(k), _stat_text(str(k), int(stats[k])), null, "", true), 12, 0))
		col.add_child(rp)
		i += 1
	var who := str(it.get("equipped_by", ""))
	var who_name := str(Game.hero_def(who).get("name", who))
	var status := Kit.panel("light_inset", 10)
	var sr := Kit.hbox(12)
	if who != "":
		sr.add_child(Kit.avatar(who, 64))
		var wl := Kit.vbox(0)
		wl.size_flags_horizontal = SIZE_EXPAND_FILL
		wl.alignment = BoxContainer.ALIGNMENT_CENTER
		wl.add_child(Kit.label("WORN BY", 17, Kit.TEXT_DIM, "cond_bold"))
		wl.add_child(Kit.label(who_name, 26, Kit.TEXT, "extrabold"))
		sr.add_child(wl)
	else:
		sr.add_child(Kit.hex_badge("gear_" + str(it.slot), 56, Color("182640"), Color.WHITE))
		var sv := GearRules.salvage_value(int(it.tier))
		var wl2 := Kit.vbox(2)
		wl2.size_flags_horizontal = SIZE_EXPAND_FILL
		wl2.alignment = BoxContainer.ALIGNMENT_CENTER
		wl2.add_child(Kit.label("SPARE  ·  SALVAGES FOR", 17, Kit.TEXT_DIM, "cond_bold"))
		wl2.add_child(Kit.cost_row(sv, 22, Kit.TEXT, false))
		(wl2.get_child(1) as HBoxContainer).alignment = BoxContainer.ALIGNMENT_BEGIN
		sr.add_child(wl2)
	status.add_child(sr)
	col.add_child(status)

	var row := Kit.hbox(12)
	var equip := Kit.primary_button("Equip to Hero", func() -> void: _open_hero_pick(uid), "equip")
	equip.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(equip)
	col.add_child(row)
	var row2 := Kit.hbox(12)
	if who != "":
		var un := Kit.light_button("Unequip", func() -> void:
			Game.unequip(who, str(it.slot))
			_close_modal()
			UI.toast("Took it off %s" % who_name))
		var go := Kit.light_button("Open Hero", func() -> void:
			_close_modal()
			UI.go("hero_detail", {"hero_id": who}), "heroes")
		for b: Button in [un, go]:
			b.size_flags_horizontal = SIZE_EXPAND_FILL
			row2.add_child(b)
	else:
		var sal := Kit.danger_button("Salvage", func() -> void: _salvage(uid), "refresh")
		sal.size_flags_horizontal = SIZE_EXPAND_FILL
		row2.add_child(sal)
	col.add_child(row2)
	_modal = UI.popup("Gear", col, Callable(), 600.0, true)


func _salvage(uid: String) -> void:
	_close_modal()
	var r := Game.salvage_gear(uid)
	if bool(r.get("ok", false)):
		UI.show_reward("Salvaged", r.get("value", {}))
	else:
		UI.toast(str(r.get("error", "Can't salvage that")), "bad")


## Hero list for "Equip to Hero": every owned hero (team first), what they wear in this slot
## and how the score would change.
func _open_hero_pick(uid: String) -> void:
	var it := Game.gear_item(uid)
	if it.is_empty():
		return
	_close_modal()
	var slot := str(it.slot)
	var score := int(Game.gear_score(uid))
	var team: Array = Game.formation()
	var ids: Array[String] = []
	for h: Dictionary in Game.owned_heroes():
		ids.append(str(h.id))
	var gain := {}
	for id in ids:
		var worn := str(Game.hero(id).get("gear", {}).get(slot, ""))
		gain[id] = score - (int(Game.gear_score(worn)) if worn != "" else 0)
	ids.sort_custom(func(a: String, b: String) -> bool:
		var ta := team.has(a)
		var tb := team.has(b)
		if ta != tb:
			return ta
		if int(gain[a]) != int(gain[b]):
			return int(gain[a]) > int(gain[b])
		return a < b)
	var list := Kit.vbox(8)
	for id in ids:
		list.add_child(_hero_pick_row(id, uid, slot, int(gain[id]), team.has(id)))
	var sc := Kit.scroll(list)
	sc.custom_minimum_size = Vector2(560, minf(ids.size() * 112.0, get_viewport_rect().size.y * 0.6))
	_modal = UI.popup("Equip %s" % str(it.get("name", "")), sc, Callable(), 620.0, true)


func _hero_pick_row(id: String, uid: String, slot: String, gain: int, in_team: bool) -> Control:
	var rp := Kit.panel("row", 8)
	var row := Kit.hbox(12)
	rp.add_child(row)
	row.add_child(Kit.hero_card(id, {"size": 88}))
	var info := Kit.vbox(2)
	info.size_flags_horizontal = SIZE_EXPAND_FILL
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	var nr := Kit.hbox(8)
	nr.add_child(Kit.label(str(Game.hero_def(id).get("name", id)), 24, Kit.TEXT, "extrabold"))
	if in_team:
		var tg := Kit.tag("TEAM", Kit.ACCENT, Color.WHITE, 15)
		tg.size_flags_vertical = SIZE_SHRINK_CENTER
		nr.add_child(tg)
	info.add_child(nr)
	var worn := str(Game.hero(id).get("gear", {}).get(slot, ""))
	var wears := "Wears %s" % str(Game.gear_item(worn).get("name", "")) if worn != "" and worn != uid else ("Wears this now" if worn == uid else "Nothing in this slot")
	var wl := Kit.label(wears, 18, Kit.TEXT_DIM, "bold")
	wl.clip_text = true
	wl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	info.add_child(wl)
	if worn != uid:
		var gl := Kit.label("SCORE %s%d" % ["+" if gain >= 0 else "", gain], 18, Color("1f9e63") if gain > 0 else Color("d42a12"), "cond_bold")
		info.add_child(gl)
	row.add_child(info)
	var b: Button
	if worn == uid:
		b = Kit.light_button("Worn")
		b.disabled = true
	else:
		b = Kit.primary_button("Equip", func() -> void:
			var r := Game.equip(id, uid)
			_close_modal()
			if bool(r.get("ok", false)):
				UI.sfx("reward")
				UI.toast("%s equipped" % str(Game.hero_def(id).get("name", id)), "good")
			else:
				UI.toast(str(r.get("error", "Can't equip")), "bad"))
	b.custom_minimum_size = Vector2(124, Kit.BUTTON_H)
	b.add_theme_font_size_override("font_size", 24)
	b.size_flags_vertical = SIZE_SHRINK_CENTER
	row.add_child(b)
	return rp


func _stat_text(stat: String, v: int) -> String:
	if stat == "crit":
		if v % 100 == 0:
			return "%d%%" % (v / 100)
		return "%.1f%%" % (float(v) / 100.0)
	return Kit.format_full(v)


func _close_modal() -> void:
	if _modal and is_instance_valid(_modal):
		UI.close_modal(_modal)
	_modal = null
