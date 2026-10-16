extends Control
## Screen "heroes": the roster. Owned heroes first (sorted by power, rarity or level), then
## the heroes still to be summoned as dark cards. Filter by faction and role; a red dot marks
## a hero who can level up or star up right now. Tap a card to open hero_detail.
## Filters, sort and scroll position are remembered for the session (static vars), so coming
## back from a hero's page lands where the player left off.

const COLS := 4
const CARD := 146.0
const GAP := 18
const SORTS: Array[String] = ["power", "rarity", "level"]
const SORT_NAMES := {"power": "By Power", "rarity": "By Rarity", "level": "By Level"}
const RARITY_RANK := {"legendary": 3, "epic": 2, "rare": 1}

static var _faction_idx := 0
static var _role_idx := 0
static var _sort_idx := 0
static var _scroll_y := 0

var _form_btn: Button
var _guide_level_id := ""
var _scroll: ScrollContainer
var _list: VBoxContainer
var _count_label: Label
var _sort_btn: Button
var _restore_scroll := true


func setup(_params: Dictionary) -> void:
	_build()
	Game.changed.connect(_refresh)
	_refresh()


func _exit_tree() -> void:
	if Game.changed.is_connected(_refresh):
		Game.changed.disconnect(_refresh)
	if _scroll:
		_scroll_y = _scroll.scroll_vertical


# ------------------------------------------------------------------ build

func _build() -> void:
	var col := Kit.vbox(12)
	col.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	col.offset_left = 24
	col.offset_right = -24
	col.offset_top = 14
	add_child(col)

	var head := Kit.hbox(12)
	head.custom_minimum_size.y = 88
	var titles := Kit.vbox(0)
	titles.alignment = BoxContainer.ALIGNMENT_CENTER
	titles.size_flags_horizontal = SIZE_EXPAND_FILL
	titles.add_child(Kit.header("Heroes", 44))
	_count_label = Kit.caption("", 22)
	titles.add_child(_count_label)
	head.add_child(titles)
	var form := Kit.secondary_button("Formation", func() -> void: UI.go("formation"), "heroes")
	form.custom_minimum_size = Vector2(252, 88)
	_form_btn = form
	form.size_flags_vertical = SIZE_SHRINK_CENTER
	head.add_child(form)
	col.add_child(head)

	var row1 := Kit.hbox(12)
	var fac_opts: Array = ["All"]
	for f: String in Kit.FACTIONS:
		fac_opts.append({"text": "", "icon": "faction_" + f})
	var fac := Kit.segmented(fac_opts, _faction_idx, func(i: int) -> void:
		_faction_idx = i
		_refresh(true), 88)
	fac.size_flags_horizontal = SIZE_EXPAND_FILL
	row1.add_child(fac)
	_sort_btn = Kit.secondary_button(str(SORT_NAMES[SORTS[_sort_idx]]), _cycle_sort, "refresh")
	_sort_btn.custom_minimum_size = Vector2(232, 88)
	_sort_btn.add_theme_font_size_override("font_size", 28)
	row1.add_child(_sort_btn)
	col.add_child(row1)

	var role_opts: Array = ["All"]
	for r: String in Kit.ROLES:
		role_opts.append({"text": "", "icon": "role_" + r})
	var roles := Kit.segmented(role_opts, _role_idx, func(i: int) -> void:
		_role_idx = i
		_refresh(true), 88)
	col.add_child(roles)

	_list = Kit.vbox(18)
	var m := Kit.margin(_list, 0, 0)
	m.add_theme_constant_override("margin_top", 12)
	m.add_theme_constant_override("margin_left", 4)
	m.add_theme_constant_override("margin_right", 16)
	m.add_theme_constant_override("margin_bottom", 28)
	_scroll = Kit.scroll(m)
	col.add_child(_scroll)


func _cycle_sort() -> void:
	_sort_idx = (_sort_idx + 1) % SORTS.size()
	_sort_btn.text = str(SORT_NAMES[SORTS[_sort_idx]])
	_refresh(true)


# ------------------------------------------------------------------ refresh

func _refresh(reset_scroll: bool = false) -> void:
	if not is_inside_tree() or _list == null:
		return
	var keep := _scroll.scroll_vertical
	# First-session guidance: the Formation button, or the hero to level next.
	var step := Guide.step()
	Guide.mark(_form_btn, step == "formation", 0)
	_guide_level_id = Guide.level_target() if step == "level" else ""
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
		if Game.owns(id):
			owned_total += 1
		if not _passes(d):
			continue
		if Game.owns(id):
			owned_ids.append(id)
		else:
			unowned_ids.append(id)
	_count_label.text = "%d of %d summoned" % [owned_total, total]
	_sort_ids(owned_ids)
	unowned_ids.sort_custom(func(a: String, b: String) -> bool:
		var ra := int(RARITY_RANK.get(str(Game.hero_def(a).rarity), 0))
		var rb := int(RARITY_RANK.get(str(Game.hero_def(b).rarity), 0))
		return ra > rb if ra != rb else a < b)

	if owned_ids.is_empty() and unowned_ids.is_empty():
		var es := Kit.empty_state("No heroes match these filters.", "heroes")
		es.custom_minimum_size.y = 360
		_list.add_child(es)
	if not owned_ids.is_empty():
		var g := Kit.grid(COLS, GAP)
		for id in owned_ids:
			g.add_child(_owned_cell(id, owned_ids))
		_list.add_child(g)
	elif not unowned_ids.is_empty():
		var none := Kit.caption("You haven't summoned a hero like this yet.", 24)
		none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		none.custom_minimum_size.y = 80
		_list.add_child(none)
	if not unowned_ids.is_empty():
		_list.add_child(Kit.spacer(0, 6))
		_list.add_child(Kit.section_header("Not yet summoned", 28, Kit.INK_DIM))
		var hint := Kit.caption("Find them in the Summon portal.", 22)
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_list.add_child(hint)
		var g2 := Kit.grid(COLS, GAP)
		for id in unowned_ids:
			g2.add_child(_unowned_cell(id, unowned_ids))
		_list.add_child(g2)

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
			_:
				key[id] = [power, rank, 0]
	ids.sort_custom(func(a: String, b: String) -> bool:
		var ka: Array = key[a]
		var kb: Array = key[b]
		for i in ka.size():
			if ka[i] != kb[i]:
				return ka[i] > kb[i]
		return a < b)


func _owned_cell(id: String, browse: Array[String]) -> Control:
	var cell := Kit.vbox(2)
	cell.mouse_filter = MOUSE_FILTER_PASS
	var card := Kit.hero_card(id, {
		"size": CARD, "show_name": true,
		"on_pressed": func() -> void: _open(id, browse),
	})
	card.size_flags_horizontal = SIZE_SHRINK_CENTER
	# Upgrade dot pushed out onto the corner so it never covers the level.
	if Game.upgrade_ready(id):
		Kit.set_dot(card, true, 24, Vector2(-10, -10))
	if id == _guide_level_id:
		Guide.mark(card, true, 0)
	cell.add_child(card)
	var pw := Kit.hbox(4)
	pw.alignment = BoxContainer.ALIGNMENT_CENTER
	pw.mouse_filter = MOUSE_FILTER_IGNORE
	pw.add_child(Kit.icon("power", 22))
	pw.add_child(Kit.label(Kit.format_num(Game.hero_power(id)), 20, Kit.GOLD_LIGHT, "black", 4))
	cell.add_child(pw)
	return cell


func _unowned_cell(id: String, browse: Array[String]) -> Control:
	var card := Kit.hero_card(id, {
		"size": CARD, "show_name": true, "owned": false, "show_level": false,
		"on_pressed": func() -> void: _open(id, browse),
	})
	card.size_flags_horizontal = SIZE_SHRINK_CENTER
	card.modulate = Color(0.78, 0.76, 0.86)
	return card


func _open(id: String, browse: Array[String]) -> void:
	_scroll_y = _scroll.scroll_vertical
	UI.go("hero_detail", {"hero_id": id, "browse": Array(browse)})
