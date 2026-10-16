extends Control
## Screen "gear" (bottom-nav Gear tab): the gear inventory on a light page. Minimal v2
## version built by the UI shell so the tab works; the meta-screens owner finishes it.
## Filter chips by slot, a 4-column grid of equipment tiles (best tier first) with the
## wearer under each, and an item sheet (stats, who wears it, Salvage for spare pieces).

const COLS := 4
const TILE := 150.0
const SLOTS: Array[String] = ["weapon", "armor", "helm", "charm"]

static var _slot_idx := 0

var _grid: GridContainer
var _count: Label
var _empty: Control
var _sheet: Control


func setup(_params: Dictionary) -> void:
	_build()
	Game.changed.connect(_refresh)
	_refresh()


func _exit_tree() -> void:
	if Game.changed.is_connected(_refresh):
		Game.changed.disconnect(_refresh)


func _build() -> void:
	# Dark header strip with the page tab, then the light page.
	var head := Kit.hbox(12)
	head.set_anchors_and_offsets_preset(PRESET_TOP_WIDE)
	head.offset_left = 16
	head.offset_right = -16
	head.offset_top = 10
	head.offset_bottom = 10 + Kit.BUTTON_H
	head.add_child(Kit.tab_strip([{"text": "Gear", "icon": "nav_gear"}], 0, Callable(), 220.0))
	head.add_child(Kit.spacer(0, 0, true))
	_count = Kit.label("", 24, Kit.INK_DIM, "cond_bold")
	head.add_child(_count)
	add_child(head)

	var page := Kit.page_bg("light")
	page.offset_top = 10 + Kit.BUTTON_H
	add_child(page)

	var col := Kit.vbox(14)
	col.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	col.offset_top = 10 + Kit.BUTTON_H + 16
	col.offset_left = 20
	col.offset_right = -20
	add_child(col)
	var opts: Array = ["ALL"]
	for s in SLOTS:
		opts.append({"icon": "gear_" + s})
	var chips := Kit.filter_chips(opts, _slot_idx, func(i: int) -> void:
		_slot_idx = i
		_refresh())
	col.add_child(chips)
	var hint := Kit.caption("Gear drops from the campaign and the Sanctum. Equip it from a hero's page.", 20, Kit.TEXT_DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(hint)

	_grid = Kit.grid(COLS, 14)
	var sc := Kit.scroll(Kit.margin(_grid, 4, 8))
	col.add_child(sc)
	_empty = Kit.empty_state("No gear in this slot yet. Clear stages to find some.", "nav_gear", true)
	_empty.size_flags_vertical = SIZE_EXPAND_FILL
	col.add_child(_empty)


func _items() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var want := "" if _slot_idx == 0 else SLOTS[_slot_idx - 1]
	for it: Dictionary in Game.gear_items():
		if want == "" or str(it.get("slot", "")) == want:
			out.append(it)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.tier) != int(b.tier):
			return int(a.tier) > int(b.tier)
		if str(a.slot) != str(b.slot):
			return SLOTS.find(str(a.slot)) < SLOTS.find(str(b.slot))
		return str(a.uid) < str(b.uid))
	return out


func _refresh() -> void:
	for c in _grid.get_children():
		c.queue_free()
	var items := _items()
	_count.text = "%d ITEMS" % Game.gear_items().size()
	_empty.visible = items.is_empty()
	_grid.get_parent().get_parent().visible = not items.is_empty()
	for it in items:
		var cell := Kit.vbox(4)
		cell.custom_minimum_size.x = TILE
		var uid := str(it.uid)
		cell.add_child(Kit.equip_slot(str(it.slot), it, TILE, func() -> void: _open(uid)))
		var n := Kit.label(str(it.get("name", "")), 18, Kit.TEXT, "cond_bold")
		n.clip_text = true
		n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		n.custom_minimum_size.x = TILE
		cell.add_child(n)
		var who := str(it.get("equipped_by", ""))
		var w := Kit.label(str(Game.hero_def(who).get("name", who)).to_upper() if who != "" else "SPARE", 16,
			Kit.ACCENT_DEEP if who != "" else Kit.TEXT_DIM, "cond_bold")
		cell.add_child(w)
		_grid.add_child(cell)


func _open(uid: String) -> void:
	var it := Game.gear_item(uid)
	if it.is_empty():
		return
	var col := Kit.vbox(14)
	col.custom_minimum_size.x = 540
	var top := Kit.hbox(18)
	top.add_child(Kit.equip_slot(str(it.slot), it, 128))
	var info := Kit.vbox(4)
	info.size_flags_horizontal = SIZE_EXPAND_FILL
	info.add_child(Kit.label(str(it.get("name", "")), 30, Kit.TEXT, "title"))
	info.add_child(Kit.label("%s  ·  TIER %s" % [str(Kit.GEAR_SLOT_NAMES.get(str(it.slot), "Gear")).to_upper(), Kit.roman(int(it.tier))], 22, Kit.TEXT_DIM, "cond_bold"))
	info.add_child(Kit.label("Score %s" % Kit.format_full(int(Game.gear_score(uid))), 22, Kit.ACCENT_DEEP, "cond_bold"))
	top.add_child(info)
	col.add_child(top)
	col.add_child(Kit.header_bar("Stats"))
	var stats: Dictionary = it.get("stats", {})
	for k: Variant in stats:
		col.add_child(Kit.stat_row(str(k), int(stats[k]), null, "", true))
	var who := str(it.get("equipped_by", ""))
	var m_ref: Array[Control] = []
	if who != "":
		var l := Kit.body("Worn by %s. Unequip it on the hero's page to salvage it." % str(Game.hero_def(who).get("name", who)), 22, Kit.TEXT_DIM)
		col.add_child(l)
		var go := Kit.primary_button("Open %s" % str(Game.hero_def(who).get("name", who)), func() -> void:
			if not m_ref.is_empty():
				UI.close_modal(m_ref[0])
			UI.go("hero_detail", {"hero_id": who}))
		col.add_child(go)
	else:
		var sal := Kit.danger_button("Salvage", func() -> void:
			if not m_ref.is_empty():
				UI.close_modal(m_ref[0])
			var r := Game.salvage_gear(uid)
			if bool(r.get("ok", false)):
				UI.show_reward("Salvaged", r.get("value", {}))
			else:
				UI.toast(str(r.get("error", "Can't salvage that")), "bad"), "refresh")
		col.add_child(sal)
	m_ref.append(UI.popup("Gear", col, Callable(), 600.0, true))
