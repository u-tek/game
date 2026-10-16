extends Control
## Screen "formation" (bottom-nav Team tab), style v2: pick the five heroes who fight.
## A dark header with the TEAM tab and the team power, then the squad on a dark glass floor:
## five tall portrait cards in a row, the FRONT pair (slots 0-1, facing the enemy) and the
## BACK three (slots 2-4), with the faction bonus and a counter hint for the next stage under
## them. Below, a light page with faction filter chips and the bench (square hero cards; the
## ones in the team are checked), then Auto-fill and Battle.
## Tap an empty slot to select it (cyan ring), then a bench hero to place them there; tapping
## a bench hero with no slot selected puts them in the best free slot (front for guardians
## and strikers). Tap a placed hero to take them out. Every valid change is saved right away
## with Game.set_formation.

const SLOT_ORDER_FRONT: Array[int] = [0, 1, 2, 3, 4]
const SLOT_ORDER_BACK: Array[int] = [2, 3, 4, 0, 1]
const FRONT_ROLES: Array[String] = ["guardian", "striker"]
const BENCH_COLS := 5

static var _filter_idx := 0

var _auto_btn: Button
var _slots: Array = ["", "", "", "", ""]
var _selected := -1
var _slot_holders: Array[Control] = []
var _slot_w := 126.0
var _bench_card := 120.0
var _compact := false

var _power_label: Label
var _power_value := -1
var _bonus_box: HBoxContainer
var _hint_box: HBoxContainer
var _grid: GridContainer
var _list_scroll: ScrollContainer
var _warn: Label
var _built := false


func setup(_params: Dictionary) -> void:
	_slots = Game.formation()
	if size.y > 0.0:
		_build()
	else:
		resized.connect(_build, CONNECT_ONE_SHOT)
	Game.changed.connect(_on_game_changed)


func _exit_tree() -> void:
	if Game.changed.is_connected(_on_game_changed):
		Game.changed.disconnect(_on_game_changed)


func _on_game_changed() -> void:
	# Another source (auto-fill, a new hero) changed the saved team: follow it unless the
	# player is mid-edit with an empty team (which can't be saved).
	if _has_hero(_slots):
		_slots = Game.formation()
	_refresh()


# ------------------------------------------------------------------ build

func _build() -> void:
	if _built:
		return
	_built = true
	_compact = size.y < 1100.0
	var w := size.x
	_slot_w = floorf(minf(112.0 if size.y < 1000.0 else 128.0, (w - 32.0 - 4 * 8.0 - 14.0) / 5.0))
	_bench_card = floorf(minf(112.0 if size.y < 1000.0 else 124.0, (w - 40.0 - (BENCH_COLS - 1) * 12.0) / BENCH_COLS))

	# Dark header: the page tab, team power on the right.
	var head := Kit.hbox(10)
	head.set_anchors_and_offsets_preset(PRESET_TOP_WIDE)
	head.offset_left = 16
	head.offset_right = -16
	head.offset_top = 10
	head.offset_bottom = 10 + Kit.BUTTON_H
	head.add_child(Kit.tab_strip([{"text": "Team", "icon": "nav_team"}], 0, Callable(), 210.0))
	head.add_child(Kit.spacer(0, 0, true))
	var pw := Kit.hbox(6)
	pw.mouse_filter = MOUSE_FILTER_IGNORE
	pw.size_flags_vertical = SIZE_SHRINK_CENTER
	pw.add_child(Kit.icon("power", 40))
	var pv := Kit.vbox(-8)
	pv.mouse_filter = MOUSE_FILTER_IGNORE
	pv.add_child(Kit.label("TEAM POWER", 17, Kit.INK_DIM, "cond_bold"))
	_power_label = Kit.label("0", 44, Kit.INK, "title")
	pv.add_child(_power_label)
	pw.add_child(pv)
	head.add_child(pw)
	add_child(head)

	var stage := _build_stage()
	stage.position = Vector2(12, 10 + Kit.BUTTON_H + 10)
	stage.size = Vector2(w - 24, 0)
	add_child(stage)
	var stage_h := stage.get_combined_minimum_size().y
	var page_top := 10 + Kit.BUTTON_H + 10 + stage_h + 12

	var page := Kit.page_bg("light")
	page.offset_top = page_top
	add_child(page)

	var col := Kit.vbox(8)
	col.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	col.offset_top = page_top + 12
	col.offset_left = 16
	col.offset_right = -16
	col.offset_bottom = -14
	add_child(col)
	var chips := Kit.hbox(10)
	var fac_opts: Array = ["ALL"]
	for f: String in Kit.FACTIONS:
		fac_opts.append({"icon": "faction_" + f})
	chips.add_child(Kit.filter_chips(fac_opts, _filter_idx, func(i: int) -> void:
		_filter_idx = i
		_refresh_list()))
	var hint := Kit.label("Tap a hero to add or remove them. Tap an empty slot first to choose where.", 19, Kit.TEXT_DIM, "bold")
	hint.size_flags_horizontal = SIZE_EXPAND_FILL
	hint.custom_minimum_size.x = 120
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.add_theme_constant_override("line_spacing", -2)
	chips.add_child(hint)
	col.add_child(chips)

	_grid = Kit.grid(BENCH_COLS, 12)
	_grid.add_theme_constant_override("v_separation", 10)
	var gm := Kit.margin(_grid, 4, 6)
	_list_scroll = Kit.scroll(gm)
	_list_scroll.custom_minimum_size.y = 140
	col.add_child(_list_scroll)

	_warn = Kit.label("", 21, Color("d42a12"), "extrabold")
	_warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_warn.visible = false
	col.add_child(_warn)

	var buttons := Kit.hbox(12)
	var auto := Kit.light_button("Auto-fill", _on_auto, "auto")
	auto.name = "AutoFill"
	auto.size_flags_horizontal = SIZE_EXPAND_FILL
	buttons.add_child(auto)
	_auto_btn = auto
	var go := Kit.primary_button("Battle", func() -> void: UI.go("campaign"), "sword")
	go.name = "Battle"
	go.size_flags_horizontal = SIZE_EXPAND_FILL
	buttons.add_child(go)
	col.add_child(buttons)
	_refresh()


## The squad floor: FRONT / BACK captions, five slots, the faction bonus and the counter hint.
func _build_stage() -> Control:
	var field := Kit.panel("glass", 12)
	field.name = "Squad"
	var v := Kit.vbox(6 if _compact else 8)
	field.add_child(v)
	var slot_h := roundf(_slot_w * 1.62)
	# Captions over the two rows: a technical line with the row name.
	var caps := Kit.hbox(14)
	caps.alignment = BoxContainer.ALIGNMENT_CENTER
	caps.mouse_filter = MOUSE_FILTER_IGNORE
	caps.add_child(_row_caption("FRONT", "Faces the enemy", 2))
	caps.add_child(_row_caption("BACK", "Protected", 3))
	v.add_child(caps)
	var r := Kit.hbox(14)
	r.alignment = BoxContainer.ALIGNMENT_CENTER
	_slot_holders.clear()
	for grp: Array in [[0, 1], [2, 3, 4]]:
		var g := Kit.hbox(8)
		for i: int in grp:
			var holder := Control.new()
			holder.name = "Slot%d" % i
			holder.custom_minimum_size = Vector2(_slot_w, slot_h)
			holder.mouse_filter = MOUSE_FILTER_PASS
			g.add_child(holder)
			_slot_holders.append(holder)
		r.add_child(g)
	v.add_child(r)
	# Faction counts and the bonus they give, then the next stage's counter hint.
	_bonus_box = Kit.hbox(10)
	_bonus_box.mouse_filter = MOUSE_FILTER_IGNORE
	_bonus_box.custom_minimum_size.y = 40
	v.add_child(_bonus_box)
	_hint_box = Kit.hbox(8)
	_hint_box.mouse_filter = MOUSE_FILTER_IGNORE
	_hint_box.custom_minimum_size.y = 40
	v.add_child(_hint_box)
	return field


func _row_caption(title_text: String, sub: String, slots: int) -> Control:
	var wdt := slots * _slot_w + (slots - 1) * 8.0
	var c := Kit.vbox(0)
	c.mouse_filter = MOUSE_FILTER_IGNORE
	c.custom_minimum_size.x = wdt
	var h := Kit.hbox(8)
	h.mouse_filter = MOUSE_FILTER_IGNORE
	h.add_child(Kit.label(title_text, 22, Kit.INK, "cond_black"))
	h.add_child(Kit.label(sub.to_upper(), 16, Kit.INK_DIM, "cond_bold"))
	c.add_child(h)
	c.add_child(Kit.deco("techline", Vector2(wdt, 8), Color(1, 1, 1, 0.3)))
	return c


# ------------------------------------------------------------------ refresh

func _refresh() -> void:
	if not _built or not is_inside_tree():
		return
	_refresh_slots()
	_refresh_summary()
	_refresh_hint()
	_refresh_list()
	# First-session guidance: Auto-fill when it would clearly help.
	Guide.mark(_auto_btn, Guide.step() == "formation")


func _refresh_slots() -> void:
	var slot_h := roundf(_slot_w * 1.62)
	for i in 5:
		var holder := _slot_holders[i]
		for c in holder.get_children():
			holder.remove_child(c)
			c.queue_free()
		var id := str(_slots[i])
		var idx := i
		if id == "":
			var e := Kit.empty_slot(_slot_w, "Front" if i < 2 else "Back", func() -> void: _tap_slot(idx))
			e.custom_minimum_size = Vector2(_slot_w, slot_h)
			e.size = e.custom_minimum_size
			holder.add_child(e)
			if _selected == i:
				var ring := Panel.new()
				ring.mouse_filter = MOUSE_FILTER_IGNORE
				ring.add_theme_stylebox_override("panel", Kit.box(Color(Kit.ACCENT, 0.12), Color(Kit.ACCENT, 0.12), Kit.ACCENT_HI, 6.0, 3))
				ring.position = Vector2(-4, -4)
				ring.size = Vector2(_slot_w + 8, slot_h + 8)
				holder.add_child(ring)
				var tw := ring.create_tween().set_loops()
				tw.tween_property(ring, "modulate:a", 0.35, 0.5).set_trans(Tween.TRANS_SINE)
				tw.tween_property(ring, "modulate:a", 1.0, 0.5).set_trans(Tween.TRANS_SINE)
				var pick := Kit.tag("PICK A HERO", Kit.ACCENT, Color.WHITE, 16)
				holder.add_child(pick)
				pick.position = Vector2((_slot_w - pick.get_combined_minimum_size().x) * 0.5, slot_h * 0.3)
		else:
			var card := Kit.portrait_card(id, {"size": _slot_w, "on_pressed": func() -> void: _tap_slot(idx)})
			holder.add_child(card)
			var x := Kit.hex_badge("close", 32, Color("26282c"), Color.WHITE)
			x.position = Vector2(_slot_w - 24, -10)
			holder.add_child(x)


func _refresh_summary() -> void:
	var power := 0
	for id: Variant in _slots:
		if str(id) != "":
			power += int(Game.hero_power(str(id)))
	if _power_value >= 0 and power != _power_value:
		Kit.count_to(_power_label, _power_value, power, 0.45, true)
		Kit.pulse(_power_label, 1.1)
	else:
		_power_label.text = Kit.format_full(power)
	_power_value = power

	for c in _bonus_box.get_children():
		_bonus_box.remove_child(c)
		c.queue_free()
	var counts := _faction_counts(_slots)
	var best := ""
	_bonus_box.add_child(Kit.label("FACTIONS", 18, Kit.INK_DIM, "cond_bold"))
	for f: String in Kit.FACTIONS:
		var n := int(counts.get(f, 0))
		if n > 0 and (best == "" or n > int(counts.get(best, 0))):
			best = f
		var chip := Kit.hbox(2)
		chip.mouse_filter = MOUSE_FILTER_IGNORE
		chip.add_child(Kit.faction_icon(f, 32))
		chip.add_child(Kit.label("%d" % n, 26, Kit.faction_color(f).lerp(Color.WHITE, 0.35) if n > 0 else Kit.INK_DIM, "cond_bold"))
		if n == 0:
			chip.modulate.a = 0.45
		_bonus_box.add_child(chip)
	_bonus_box.add_child(Kit.spacer(0, 0, true))
	var bp := BattleSim.faction_bonus_bp(int(counts.get(best, 0))) if best != "" else 0
	if bp > 0:
		var t := Kit.tag("%s +%d%% HP & ATK" % [str(Kit.FACTION_NAMES.get(best, best)).to_upper(), bp / 100], Kit.faction_color(best).darkened(0.1), Color.WHITE, 18)
		t.size_flags_vertical = SIZE_SHRINK_CENTER
		_bonus_box.add_child(t)
	else:
		var l := Kit.label("3 / 4 / 5 ALIKE: +%d / %d / %d%%" % [
			BattleSim.faction_bonus_bp(3) / 100, BattleSim.faction_bonus_bp(4) / 100, BattleSim.faction_bonus_bp(5) / 100], 18, Kit.INK_DIM, "cond_bold")
		_bonus_box.add_child(l)


## Next stage: its enemy factions and which of ours counter them (and how many are fielded).
func _refresh_hint() -> void:
	for c in _hint_box.get_children():
		_hint_box.remove_child(c)
		c.queue_free()
	var st := Game.current_stage()
	if st.is_empty():
		_hint_box.add_child(Kit.label("Every stage is cleared. Replay stages from the campaign map.", 20, Kit.INK_DIM, "bold"))
		return
	var enemy_counts := {}
	for e: Dictionary in st.get("enemies", []):
		var f := str(Game.hero_def(str(e.hero_id)).get("faction", ""))
		enemy_counts[f] = int(enemy_counts.get(f, 0)) + 1
	var tg := Kit.tag("NEXT %s" % str(st.id), Kit.ORANGE, Color.WHITE, 18)
	tg.size_flags_vertical = SIZE_SHRINK_CENTER
	_hint_box.add_child(tg)
	for f: String in Kit.FACTIONS:
		if enemy_counts.has(f):
			_hint_box.add_child(Kit.faction_icon(f, 28))
			_hint_box.add_child(Kit.label("x%d" % int(enemy_counts[f]), 20, Kit.INK, "cond_bold"))
	_hint_box.add_child(Kit.spacer(0, 0, true))
	var mine := _faction_counts(_slots)
	_hint_box.add_child(Kit.label("COUNTER", 18, Kit.INK_DIM, "cond_bold"))
	var fielded := 0
	var shown := {}
	for ef: String in Kit.FACTIONS:
		if not enemy_counts.has(ef):
			continue
		for f: String in Kit.FACTIONS:
			if str(BattleSim.BEATS.get(f, "")) == ef and not shown.has(f):
				shown[f] = true
				_hint_box.add_child(Kit.faction_icon(f, 28))
				fielded += int(mine.get(f, 0))
	var adv := Kit.label("+%d%%" % (BattleSim.ADVANTAGE_BP / 100), 20, Kit.GOOD, "cond_bold")
	_hint_box.add_child(adv)
	_hint_box.add_child(Kit.label("%d IN TEAM" % fielded, 18, Kit.ACCENT_HI if fielded > 0 else Kit.INK_DIM, "cond_bold"))


func _refresh_list() -> void:
	if _grid == null:
		return
	var keep := _list_scroll.scroll_vertical
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	var owned := Game.owned_heroes()
	var ids: Array[String] = []
	for h: Dictionary in owned:
		var id := str(h.id)
		var fac := str(Game.hero_def(id).get("faction", ""))
		if _filter_idx > 0 and fac != Kit.FACTIONS[_filter_idx - 1]:
			continue
		ids.append(id)
	# Strongest first, the ones in the team before the rest.
	ids.sort_custom(func(a: String, b: String) -> bool:
		var ta := _slots.has(a)
		var tb := _slots.has(b)
		if ta != tb:
			return ta
		var pa := int(Game.hero_power(a))
		var pb := int(Game.hero_power(b))
		return pa > pb if pa != pb else a < b)
	for id in ids:
		var in_team := _slots.has(id)
		var cb := func() -> void: _tap_hero(id)
		var card := Kit.hero_card(id, {"size": _bench_card, "show_name": true, "light": true, "selected": in_team, "on_pressed": cb})
		if in_team:
			var chk := Kit.hex_badge("check", 32, Kit.ACCENT, Color.WHITE)
			chk.position = Vector2(_bench_card - 24, -8)
			card.add_child(chk)
		_grid.add_child(card)
	if ids.is_empty():
		var l := Kit.label("No heroes of this faction yet.", 22, Kit.TEXT_DIM, "bold")
		l.custom_minimum_size = Vector2(600, 120)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_grid.add_child(l)
	_restore_list_scroll.call_deferred(keep)


func _restore_list_scroll(y: int) -> void:
	if is_instance_valid(_list_scroll):
		_list_scroll.scroll_vertical = y


# ------------------------------------------------------------------ editing

func _tap_slot(i: int) -> void:
	var id := str(_slots[i])
	if id != "":
		_slots[i] = ""
		_selected = i
		_commit()
		return
	_selected = -1 if _selected == i else i
	_refresh_slots()


func _tap_hero(id: String) -> void:
	var at := _slots.find(id)
	if at >= 0:
		if _selected >= 0:
			_slots[at] = ""
			_slots[_selected] = id
			_selected = -1
		else:
			_slots[at] = ""
		_commit()
		return
	var target := _selected
	if target < 0 or str(_slots[target]) != "":
		target = _best_free_slot(id)
	if target < 0:
		UI.toast("The team is full. Tap a hero in the team to take them out.")
		for h in _slot_holders:
			Kit.shake(h, 6)
		return
	_slots[target] = id
	_selected = -1
	_commit()
	if target < _slot_holders.size():
		for c in _slot_holders[target].get_children():
			if c is Control:
				Kit.pop_in(c as Control, 0.0, 0.28)


## Front for guardians and strikers, back for everyone else, else any free slot.
func _best_free_slot(id: String) -> int:
	var role := str(Game.hero_def(id).get("role", ""))
	var order: Array = SLOT_ORDER_FRONT if FRONT_ROLES.has(role) else SLOT_ORDER_BACK
	for i in order:
		if str(_slots[i]) == "":
			return i
	return -1


func _commit() -> void:
	if _has_hero(_slots):
		_warn.visible = false
		var r := Game.set_formation(_slots.duplicate())
		if not bool(r.get("ok", false)):
			UI.toast(str(r.get("error", "Couldn't save the team")), "bad")
		# Game.changed refreshes everything.
	else:
		_warn.text = "Place at least one hero. Your last saved team is kept until then."
		_warn.visible = true
		_refresh()


func _on_auto() -> void:
	Game.auto_formation()
	_selected = -1
	_slots = Game.formation()
	_refresh()
	UI.sfx("reward")
	UI.toast("Strongest team placed and equipped", "good")
	for h in _slot_holders:
		for c in h.get_children():
			if c is Control:
				Kit.pop_in(c as Control, randf() * 0.12, 0.3)


static func _has_hero(slots: Array) -> bool:
	for s: Variant in slots:
		if str(s) != "":
			return true
	return false


func _faction_counts(slots: Array) -> Dictionary:
	var counts := {}
	for s: Variant in slots:
		var id := str(s)
		if id == "":
			continue
		var f := str(Game.hero_def(id).get("faction", ""))
		counts[f] = int(counts.get(f, 0)) + 1
	return counts
