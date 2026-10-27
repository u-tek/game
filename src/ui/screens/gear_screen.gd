extends Control
## Screen "gear" (bottom-nav Gear tab; params open: gear uid or "first", pick: true), style v4
## "Signal": the gear inventory as a printed catalogue sheet in the approved Lobby poster's look
## (docs/dev/ui-style-v4.md). On the paper matte: the house line with the counts, the printed index
## of slots (01 ALL / 02 WEAPON / 03 ARMOR / 04 HELM / 05 CHARM), a "spare only" switch and the sort
## as printed type. Under them the sheet scrolls: a header with a dark band (the lead hero's red
## halftone print) and "GEAR" set huge, two-tone across it, then the pieces as studio objects on
## the paper: each a brushed silver part in its slot's silhouette with the slot glyph engraved, a
## signal tier sticker, and its catalogue caption (number, name, score, wearer or SPARE); a status
## light marks a spare piece that would improve a team hero. Tap a piece for its sheet: the object
## shot, its stats as a bracketed mono table, who wears it, and the actions: Equip to a hero (the
## pass; a hero list showing what each one wears in that slot and the score change), Unequip, Open
## the wearer's page, or Salvage a spare piece for gold and dust.

## Where the slot tabs start: under the Back row.
const HEAD_ROW := 84.0
const PK := preload("res://src/ui/v4/poster_kit.gd")

const COLS := 4
const SLOTS: Array[String] = ["weapon", "armor", "helm", "charm"]
const SORTS: Array[String] = ["tier", "score", "slot"]
const SORT_NAMES := {"tier": "Tier", "score": "Score", "slot": "Slot"}
const INK := PK.INK
const PAPER := PK.PAPER
const SIG := PK.SIGNAL
const HEAD_H := 168.0
const CELL_H := 236.0

static var _slot_idx := 0
static var _spare_only := false
static var _sort_idx := 0

var _scroll: ScrollContainer
var _sheet_wrap: Control
var _count: Label
var _empty: Control
var _sort_btn: Button
var _spare_chip: Button
var _tabs_box: Control
var _modal: Control
var _tile := 150.0
var _sig := ""
var _w := 720.0


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
	_w = get_viewport_rect().size.x
	_tile = floorf((_w - 36 - 40 - (COLS - 1) * 12.0) / COLS)
	PK.matte(self)
	# Back (Gear is reached from the Bag's armoury and hero pages), the catalogue line beside it.
	var back := SignalKit.back_button(func() -> void: UI.back())
	back.position = Vector2(4, 0)
	add_child(back)
	PK.at(self, PK.t("GEAR CATALOGUE Nº 04", 13, INK, "mono_bold"), Vector2(190, 22))
	_count = PK.t("", 11, Color(INK, 0.75), "mono")
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_count.size = Vector2(_w - 210, 14)
	PK.at(self, _count, Vector2(190, 44))
	# The printed index of slots.
	_tabs_box = Control.new()
	_tabs_box.name = "SlotChips"
	_tabs_box.mouse_filter = MOUSE_FILTER_IGNORE
	_tabs_box.position = Vector2(18, HEAD_ROW)
	_tabs_box.size = Vector2(_w - 36, Kit.BUTTON_H)
	add_child(_tabs_box)
	_build_tabs()
	# Spare-only switch and the sort, as printed type.
	_spare_chip = PK.print_button("", func() -> void:
		_spare_only = not _spare_only
		_dress_switches()
		_refresh(true), {"size": Vector2(250, Kit.BUTTON_H), "text_size": 14, "underline": false})
	_spare_chip.name = "SpareChip"
	_spare_chip.toggle_mode = false
	PK.at(self, _spare_chip, Vector2(28, HEAD_ROW + Kit.BUTTON_H - 14))
	_sort_btn = PK.print_button("", _open_sort, {"size": Vector2(250, Kit.BUTTON_H), "text_size": 14, "align": "right", "underline": false})
	_sort_btn.name = "Sort"
	PK.at(self, _sort_btn, Vector2(_w - 28 - 250, HEAD_ROW + Kit.BUTTON_H - 14))
	PK.rule(self, Rect2(18, HEAD_ROW + Kit.BUTTON_H * 2 - 14, _w - 36, 1), Color(INK, 0.55))
	_dress_switches()

	var top := HEAD_ROW + Kit.BUTTON_H * 2 - 12
	_sheet_wrap = Control.new()
	_sheet_wrap.name = "Sheet"
	_sheet_wrap.mouse_filter = MOUSE_FILTER_PASS
	_sheet_wrap.custom_minimum_size = Vector2(_w - 36, 400)
	var m := Kit.margin(_sheet_wrap, 18, 0)
	m.add_theme_constant_override("margin_top", 22)
	m.add_theme_constant_override("margin_bottom", 40 + int(UI.pinned_bottom_inset()))
	_scroll = Kit.scroll(m)
	_scroll.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_scroll.offset_top = top
	add_child(_scroll)
	PK.grain(self, 0.06)


func _build_tabs() -> void:
	for c in _tabs_box.get_children():
		_tabs_box.remove_child(c)
		c.queue_free()
	var items: Array = ["All"]
	for s in SLOTS:
		items.append(str(Kit.GEAR_SLOT_NAMES[s]))
	var row := PK.index_tabs(items, _slot_idx, func(i: int) -> void:
		_slot_idx = i
		_build_tabs.call_deferred()
		_refresh(true), _w - 36)
	_tabs_box.add_child(row)


func _dress_switches() -> void:
	(_spare_chip.get_meta("text_label") as Label).text = ("■  SPARE ONLY" if _spare_only else "□  SPARE ONLY")
	(_spare_chip.get_meta("text_label") as Label).add_theme_color_override("font_color", SIG if _spare_only else INK)
	(_sort_btn.get_meta("text_label") as Label).text = "SORT: %s  ↓" % str(SORT_NAMES[SORTS[_sort_idx]]).to_upper()


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


## The hero printed on the sheet's band: the first team hero with art.
static func _lead() -> String:
	for id: Variant in Game.formation():
		if str(id) != "" and HeroArt.has_art(str(id)):
			return str(id)
	return ""


# ------------------------------------------------------------------ refresh

func _refresh(reset_scroll: bool = false) -> void:
	if not is_inside_tree() or _sheet_wrap == null:
		return
	var all := Game.gear_items()
	var worn := 0
	for it in all:
		if str(it.get("equipped_by", "")) != "":
			worn += 1
	_count.text = "%d ITEMS  ·  %d WORN  ·  %d SPARE" % [all.size(), worn, all.size() - worn]
	var items := _items()
	var sig := JSON.stringify(items) + JSON.stringify(Game.formation()) + str(_sort_idx) + str(_slot_idx) + str(_spare_only)
	if sig == _sig and not reset_scroll:
		return
	_sig = sig
	var keep := _scroll.scroll_vertical
	for c in _sheet_wrap.get_children():
		_sheet_wrap.remove_child(c)
		c.queue_free()
	_build_sheet(items, all.size(), worn)
	if reset_scroll:
		_scroll.scroll_vertical = 0
	else:
		_restore.call_deferred(keep)


func _restore(y: int) -> void:
	if is_instance_valid(_scroll):
		_scroll.scroll_vertical = y


## The catalogue sheet: the header (band, giant GEAR) and the pieces (the counts are at the top).
func _build_sheet(items: Array[Dictionary], _total: int, _worn: int) -> void:
	var pw := _w - 36
	var rows := ceili(float(items.size()) / COLS)
	var ph := HEAD_H + maxf(1.0, float(rows)) * CELL_H + 40.0
	if items.is_empty():
		ph = HEAD_H + 260.0
	_sheet_wrap.custom_minimum_size = Vector2(pw, ph + 10)
	var p := PK.poster(_sheet_wrap, Rect2(0, 0, pw, ph))
	var bw := 168.0
	var band := PK.band(p, Rect2(0, 0, bw, HEAD_H), _lead(), "", {"from": 0.0, "cell": 6.0})
	PK.at(band, PK.t("Nº 04", 12, Color(PAPER, 0.9), "mono_bold"), Vector2(14, 14))
	PK.at(band, PK.t("©2026 HH · ARMOURY", 9, Color(PAPER, 0.75), "mono_bold"), Vector2(14, HEAD_H - 22))
	# "GEAR" set huge, two-tone across the band; the counts as a bracketed table beside it.
	var f := Kit.font("compressed")
	var fs := 250
	while fs > 110 and (64.0 + f.get_string_size("GEAR", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 20.0 > pw - 40.0
			or PK.caps(f, fs).y - PK.caps(f, fs).x > HEAD_H - 64.0):
		fs -= 10
	var cp := PK.caps(f, fs)
	PK.giant(p, "GEAR", fs, [[0.0, bw, PAPER], [bw, pw - bw, INK]], Vector2(64, 16.0 - cp.x), Vector2(pw + 300, fs * 1.3), 0.0)
	var cap_end := 16.0 + cp.y - cp.x
	var x := bw + 20
	PK.at(p, PK.t("TAP A PIECE TO EQUIP, COMPARE OR SALVAGE IT.", 10, Color(INK, 0.75), "mono"), Vector2(x, minf(cap_end + 12, HEAD_H - 22)))
	PK.rule(p, Rect2(0, HEAD_H, pw, 1), Color(INK, 0.55))
	_empty = Control.new()
	_empty.name = "Empty"
	_empty.mouse_filter = MOUSE_FILTER_IGNORE
	_empty.visible = items.is_empty()
	p.add_child(_empty)
	if items.is_empty():
		var msg := "NO SPARE GEAR HERE." if _spare_only else ("NO GEAR YET." if _slot_idx == 0 else "NO GEAR IN THIS SLOT YET.")
		var el := PK.t(msg + "\nCLEAR STAGES AND COLLECT THE SANCTUM\nTO FIND SOME.", 14, INK, "mono_bold")
		el.position = Vector2(x, HEAD_H + 60)
		_empty.add_child(el)
		PK.at(_empty, PK.stencil("00", 120, Color(INK, 0.12), PAPER), Vector2(30, HEAD_H + 50))
		# Where it comes from, one tap away.
		if not _spare_only:
			var go := PK.print_button("TO THE CAMPAIGN  →", func() -> void: UI.go("campaign"), {"size": Vector2(300, 88), "text_size": 14})
			go.name = "ToCampaign"
			_empty.add_child(go)
			go.position = Vector2(x - 6, HEAD_H + 140)
		return
	var cw := _tile
	for i in items.size():
		var it := items[i]
		var cell := _cell(it, i, cw)
		cell.position = Vector2(20 + (i % COLS) * (cw + 12.0), HEAD_H + 20 + (i / COLS) * CELL_H)
		p.add_child(cell)
	PK.grain(p, 0.05)


## One piece on the sheet: the object, its tier sticker, its caption; a tap opens its sheet.
func _cell(it: Dictionary, i: int, cw: float) -> Button:
	var uid := str(it.uid)
	var slot := str(it.slot)
	var b := PK.bare_button(Vector2(cw, CELL_H - 12))
	b.name = "Gear_" + uid
	var s := minf(cw - 24.0, 124.0)
	var obj := PK.gear_object(slot, s, b, Vector2((cw - s) * 0.5, 10), str(it.get("name", "")), int(it.get("tier", 1)))
	# (Ink stickers on the sheet: ten signal ones made the page red; the piece's own sheet keeps signal.)
	var st := PK.sticker([[Kit.roman(int(it.tier)), 15, "wide_black"]], {"fill": "ink", "pad": 6, "rotation": -0.12 + 0.05 * (i % 3), "shadow": 0.25})
	PK.at(b, st, Vector2(cw - st.size.x - 6, 4))
	var who := str(it.get("equipped_by", ""))
	if _team_gain(it) > 0:
		PK.led(b, Vector2(6, 8), "breathe")
	var y := s + 22.0
	PK.at(b, PK.t("Nº %02d · %s" % [i + 1, str(Kit.GEAR_SLOT_NAMES.get(slot, slot)).to_upper()], 9, Color(INK, 0.7), "mono_bold"), Vector2(4, y))
	var n := PK.t(str(it.get("name", "")).to_upper(), 12, INK, "mono_bold")
	n.clip_text = true
	n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	n.size = Vector2(cw - 6, 18)
	PK.at(b, n, Vector2(4, y + 14))
	PK.at(b, PK.t("SCORE %s" % Kit.format_full(int(Game.gear_score(uid))), 10, INK, "mono"), Vector2(4, y + 32))
	var wl := PK.t(str(Game.hero_def(who).get("name", who)).to_upper() if who != "" else "SPARE", 10, INK if who != "" else Color(INK, 0.5), "mono_bold")
	PK.at(b, wl, Vector2(4, y + 48))
	if who != "":
		PK.rule(b, Rect2(4, y + 64, minf(wl.get_minimum_size().x, cw - 8), 1), INK)
	PK.wire(b, [obj], func() -> void: _open(uid))
	return b


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
			_dress_switches()
			_refresh(true)
		var b := PK.plate_button(text, cb, {"size": Vector2(420, Kit.BUTTON_H), "preset": "signal" if i == _sort_idx else "silver",
			"kicker": "SORT %02d" % (i + 1), "text_size": 22})
		col.add_child(b)
	_modal = UI.popup("Sort By", col, Callable(), 500.0, true)


# ------------------------------------------------------------------ item sheet

func _open(uid: String) -> void:
	var it := Game.gear_item(uid)
	if it.is_empty():
		return
	_close_modal()
	var slot := str(it.slot)
	var col := Kit.vbox(14)
	col.custom_minimum_size.x = 540
	# The object shot on paper: the part, its sticker, its name and particulars.
	var shot := Control.new()
	shot.custom_minimum_size = Vector2(540, 220)
	shot.mouse_filter = MOUSE_FILTER_IGNORE
	var paper := ColorRect.new()
	paper.color = PAPER
	paper.mouse_filter = MOUSE_FILTER_IGNORE
	paper.size = Vector2(540, 220)
	shot.add_child(paper)
	PK.gear_object(slot, 176, shot, Vector2(26, 22), str(it.get("name", "")), int(it.get("tier", 1)))
	var st := PK.sticker([[Kit.roman(int(it.tier)), 22, "wide_black"]], {"fill": "signal", "pad": 8, "rotation": -0.1})
	PK.at(shot, st, Vector2(176, 14))
	var nl := PK.t(str(it.get("name", "")).to_upper(), 26, INK, "wide_black")
	nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nl.size = Vector2(300, 70)
	nl.custom_minimum_size.x = 300
	PK.at(shot, nl, Vector2(226, 26))
	PK.at(shot, PK.t("TIER %s  ·  %s" % [Kit.roman(int(it.tier)), str(Kit.GEAR_SLOT_NAMES.get(slot, "Gear")).to_upper()], 12, INK, "mono_bold"), Vector2(226, 104))
	PK.at(shot, PK.t("SCORE", 11, INK, "mono"), Vector2(226, 134))
	PK.at(shot, PK.t(Kit.format_full(int(Game.gear_score(uid))), 40, SIG, "compressed"), Vector2(224, 146))
	var br := PK.brackets(Vector2(540, 220), Color(INK, 0.7), 16.0)
	shot.add_child(br)
	col.add_child(shot)
	# The stats as a bracketed mono table (the score row highlighted).
	var rows: Array = []
	var stats: Dictionary = it.get("stats", {})
	for k: Variant in stats:
		rows.append([str(Kit.STAT_NAMES.get(str(k), str(k))).to_upper(), _stat_text(str(k), int(stats[k]))])
	rows.append(["GEAR SCORE", Kit.format_full(int(Game.gear_score(uid))), true])
	var who := str(it.get("equipped_by", ""))
	var who_name := str(Game.hero_def(who).get("name", who))
	if who != "":
		rows.append(["WORN BY", who_name.to_upper()])
	else:
		var sv := GearRules.salvage_value(int(it.tier))
		var parts: Array[String] = []
		for c: Variant in sv:
			parts.append("%s %s" % [Kit.format_full(int(sv[c])), str(Kit.CURRENCY_SHORT.get(str(c), str(c))).to_upper()])
		rows.append(["SPARE · SALVAGES FOR", "  ".join(parts)])
	col.add_child(PK.data_table(rows, 540.0, {"size": 15, "row_h": 32.0, "bar": Color(0, 0, 0, 0.06)}))

	# Equipping is label-maker tape (the button family), stuck on under the table.
	var equip := SignalKit.tape_button("EQUIP TO HERO  →", func() -> void: _open_hero_pick(uid), SignalKit.SIGNAL, "Equip to hero")
	equip.name = "Equip"
	var eq_row := Kit.hbox(14)
	eq_row.mouse_filter = MOUSE_FILTER_IGNORE
	eq_row.add_child(equip)
	var eq_note := PK.t("SCORE %s
COMPARE EVERY HERO
IN THIS SLOT" % Kit.format_full(int(Game.gear_score(uid))), 10, Color(INK, 0.7), "mono")
	eq_note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	eq_row.add_child(eq_note)
	col.add_child(eq_row)
	var row2 := Kit.hbox(12)
	if who != "":
		var un := PK.plate_button("Unequip", func() -> void:
			Game.unequip(who, slot)
			_close_modal()
			UI.toast("Took it off %s" % who_name), {"size": Vector2(264, Kit.BUTTON_H), "kicker": "TAKE OFF", "text_size": 20})
		var go := PK.plate_button("Open Hero", func() -> void:
			_close_modal()
			UI.go("hero_detail", {"hero_id": who}), {"size": Vector2(264, Kit.BUTTON_H), "kicker": who_name.to_upper(), "icon": "heroes", "text_size": 20})
		row2.add_child(un)
		row2.add_child(go)
	else:
		var sal := PK.plate_button("Salvage", func() -> void: _salvage(uid), {"size": Vector2(540, Kit.BUTTON_H), "preset": "graphite",
			"kicker": "BREAK IT DOWN FOR GOLD AND DUST", "icon": "refresh", "text_size": 22})
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


## One hero in the list: her framed portrait print, name (TEAM in signal), what she wears in the
## slot and the score change, and Equip (or Worn).
func _hero_pick_row(id: String, uid: String, slot: String, gain: int, in_team: bool) -> Control:
	var rp := Control.new()
	rp.custom_minimum_size = Vector2(556, 104)
	rp.mouse_filter = MOUSE_FILTER_IGNORE
	var bg := ColorRect.new()
	bg.color = PAPER
	bg.mouse_filter = MOUSE_FILTER_IGNORE
	bg.size = Vector2(556, 98)
	rp.add_child(bg)
	var pic := HeroArt.make_portrait(id, 88, Kit.hero_look(id))
	pic.mouse_filter = MOUSE_FILTER_IGNORE
	pic.position = Vector2(5, 5)
	rp.add_child(pic)
	PK.hairbox(rp, Rect2(4, 4, 90, 90), Color(INK, 0.7))
	var nm := PK.t(str(Game.hero_def(id).get("name", id)).to_upper(), 20, INK, "wide_black")
	PK.at(rp, nm, Vector2(108, 10))
	if in_team:
		PK.at(rp, PK.t("TEAM", 11, SIG, "mono_bold"), Vector2(112 + nm.get_minimum_size().x, 16))
	var worn := str(Game.hero(id).get("gear", {}).get(slot, ""))
	var wears := "WEARS %s" % str(Game.gear_item(worn).get("name", "")).to_upper() if worn != "" and worn != uid else ("WEARS THIS NOW" if worn == uid else "NOTHING IN THIS SLOT")
	var wl := PK.t(wears, 11, INK, "mono")
	wl.clip_text = true
	wl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	wl.size = Vector2(290, 16)
	PK.at(rp, wl, Vector2(108, 44))
	if worn != uid:
		PK.at(rp, PK.t("SCORE %s%d" % ["+" if gain >= 0 else "", gain], 13, SIG if gain > 0 else INK, "mono_bold"), Vector2(108, 66))
	var b: Button
	if worn == uid:
		b = PK.plate_button("Worn", Callable(), {"size": Vector2(140, Kit.BUTTON_H), "text_size": 20, "disabled": true})
	else:
		b = PK.plate_button("Equip", func() -> void:
			var r := Game.equip(id, uid)
			_close_modal()
			if bool(r.get("ok", false)):
				UI.sfx("reward")
				UI.toast("%s equipped" % str(Game.hero_def(id).get("name", id)), "good")
			else:
				UI.toast(str(r.get("error", "Can't equip")), "bad"), {"size": Vector2(140, Kit.BUTTON_H), "preset": "signal", "text_size": 20})
	b.position = Vector2(556 - 146, 5)
	rp.add_child(b)
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
