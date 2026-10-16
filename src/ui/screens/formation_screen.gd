extends Control
## Screen "formation": pick the five heroes who fight. The battlefield shows the front row
## (2 slots, facing the enemy) above the back row (3 slots). Tap an empty slot to select it,
## then tap a hero below to place them there; tapping a listed hero with no slot selected puts
## them in the best free slot (front for guardians and strikers). Tap a placed hero to take
## them out. Team power, the faction bonus (3/4/5 of one faction) and a counter hint for the
## next stage update live. Every valid change is saved right away with Game.set_formation.

const SLOT_ORDER_FRONT: Array[int] = [0, 1, 2, 3, 4]
const SLOT_ORDER_BACK: Array[int] = [2, 3, 4, 0, 1]
const FRONT_ROLES: Array[String] = ["guardian", "striker"]
const DARK_INK := Color("3d2306")

static var _filter_idx := 0

var _auto_btn: Button
var _slots: Array = ["", "", "", "", ""]
var _selected := -1
var _slot_holders: Array[Control] = []
var _slot_size := 140.0
var _compact := false

var _power_label: Label
var _power_value := -1
var _bonus_box: HBoxContainer
var _bonus_note: Label
var _hint_box: VBoxContainer
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
	_compact = size.y < 1050.0
	_slot_size = 112.0 if _compact else 128.0

	var col := Kit.vbox(10 if _compact else 14)
	col.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	col.offset_left = 22
	col.offset_right = -22
	col.offset_top = 8
	col.offset_bottom = -14
	add_child(col)

	# Header: back, title, team power.
	var pw := Kit.hbox(6)
	pw.mouse_filter = MOUSE_FILTER_IGNORE
	pw.custom_minimum_size.x = 150
	pw.alignment = BoxContainer.ALIGNMENT_END
	pw.add_child(Kit.icon("power", 40))
	_power_label = Kit.number(0, 32, Kit.GOLD_LIGHT)
	pw.add_child(_power_label)
	col.add_child(Kit.screen_header("Formation", Callable(), pw))

	col.add_child(_build_field())
	_hint_box = Kit.vbox(6)
	var hint_panel := Kit.card(14)
	hint_panel.add_child(_hint_box)
	col.add_child(hint_panel)

	var fac_opts: Array = ["All"]
	for f: String in Kit.FACTIONS:
		fac_opts.append({"text": "", "icon": "faction_" + f})
	if _compact:
		_filter_idx = 0 # short screens: no room for the filter row
	else:
		col.add_child(Kit.segmented(fac_opts, _filter_idx, func(i: int) -> void:
			_filter_idx = i
			_refresh_list(), 88))

	_grid = Kit.grid(5, 12)
	var gm := Kit.margin(_grid, 2, 8)
	_list_scroll = Kit.scroll(gm)
	_list_scroll.custom_minimum_size.y = 140
	col.add_child(_list_scroll)

	_warn = Kit.caption("", 22, Color("ff8a70"))
	_warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_warn.visible = false
	col.add_child(_warn)

	var buttons := Kit.hbox(14)
	var auto := Kit.secondary_button("Auto-fill", _on_auto, "auto")
	auto.size_flags_horizontal = SIZE_EXPAND_FILL
	buttons.add_child(auto)
	_auto_btn = auto
	var done := Kit.primary_button("Done", func() -> void: UI.back(), "check")
	done.size_flags_horizontal = SIZE_EXPAND_FILL
	buttons.add_child(done)
	col.add_child(buttons)
	_refresh()


func _build_field() -> Control:
	var field := Kit.panel("glass", 14 if _compact else 18)
	var v := Kit.vbox(4 if _compact else 8)
	field.add_child(v)
	# Faction counts and the bonus they give.
	var top := Kit.hbox(10)
	_bonus_box = Kit.hbox(10)
	_bonus_box.mouse_filter = MOUSE_FILTER_IGNORE
	top.add_child(_bonus_box)
	_bonus_note = Kit.caption("", 20)
	_bonus_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_bonus_note.size_flags_horizontal = SIZE_EXPAND_FILL
	_bonus_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	top.add_child(_bonus_note)
	v.add_child(top)
	v.add_child(Kit.divider())
	_slot_holders.clear()
	for row: int in 2:
		if not _compact:
			var cap := Kit.hbox(8)
			cap.alignment = BoxContainer.ALIGNMENT_CENTER
			cap.mouse_filter = MOUSE_FILTER_IGNORE
			cap.add_child(Kit.icon("sword" if row == 0 else "role_guardian", 22, Kit.INK_DIM))
			cap.add_child(Kit.caption("Front row: faces the enemy first" if row == 0 else "Back row: protected by the front", 20))
			v.add_child(cap)
		var r := Kit.hbox(30 if row == 0 else 20)
		r.alignment = BoxContainer.ALIGNMENT_CENTER
		var idxs: Array = [0, 1] if row == 0 else [2, 3, 4]
		for i in idxs:
			var holder := Control.new()
			holder.custom_minimum_size = Vector2(_slot_size, _slot_size + 28)
			holder.mouse_filter = MOUSE_FILTER_PASS
			r.add_child(holder)
			_slot_holders.append(holder)
		v.add_child(r)
	return field


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
	for i in 5:
		var holder := _slot_holders[i]
		for c in holder.get_children():
			holder.remove_child(c)
			c.queue_free()
		var id := str(_slots[i])
		var idx := i
		if id == "":
			var e := Kit.empty_slot(_slot_size, "Front" if i < 2 else "Back", func() -> void: _tap_slot(idx))
			holder.add_child(e)
			if _selected == i:
				var ring := Panel.new()
				ring.mouse_filter = MOUSE_FILTER_IGNORE
				ring.add_theme_stylebox_override("panel", Kit.box(Color.TRANSPARENT, Color.TRANSPARENT, Kit.GOLD_LIGHT, 16.0, 4))
				ring.position = Vector2(-5, -5)
				ring.size = Vector2(_slot_size + 10, _slot_size + 10)
				holder.add_child(ring)
				var tw := ring.create_tween().set_loops()
				tw.tween_property(ring, "modulate:a", 0.35, 0.5).set_trans(Tween.TRANS_SINE)
				tw.tween_property(ring, "modulate:a", 1.0, 0.5).set_trans(Tween.TRANS_SINE)
				var pick := Kit.caption("Pick a hero", 19, Kit.GOLD_LIGHT)
				pick.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				pick.position = Vector2(-10, _slot_size + 2)
				pick.size = Vector2(_slot_size + 20, 26)
				holder.add_child(pick)
		else:
			var card := Kit.hero_card(id, {"size": _slot_size, "show_name": true, "show_level": false, "on_pressed": func() -> void: _tap_slot(idx)})
			holder.add_child(card)
			var x := Panel.new()
			x.mouse_filter = MOUSE_FILTER_IGNORE
			x.add_theme_stylebox_override("panel", Kit.box(Color("3a1020"), Color("1a0810"), Color("ff8a70"), 999.0, 2))
			x.size = Vector2(34, 34)
			x.position = Vector2(_slot_size - 22, -10)
			var xi := Kit.icon("close", 20, Color("ffd2c8"))
			xi.position = Vector2(7, 7)
			xi.size = Vector2(20, 20)
			x.add_child(xi)
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
		c.queue_free()
	var counts := _faction_counts(_slots)
	var best := ""
	for f: String in Kit.FACTIONS:
		var n := int(counts.get(f, 0))
		if n > 0 and (best == "" or n > int(counts.get(best, 0))):
			best = f
		var chip := Kit.hbox(2)
		chip.mouse_filter = MOUSE_FILTER_IGNORE
		var ic := Kit.faction_icon(f, 36)
		chip.add_child(ic)
		chip.add_child(Kit.label("%d" % n, 26, Kit.faction_color(f).lerp(Color.WHITE, 0.35) if n > 0 else Kit.INK_DIM, "black", 4))
		if n == 0:
			chip.modulate.a = 0.45
		_bonus_box.add_child(chip)
	var bp := BattleSim.faction_bonus_bp(int(counts.get(best, 0))) if best != "" else 0
	if bp > 0:
		var t := Kit.tag("+%d%% HP & ATK" % (bp / 100), Kit.faction_color(best), DARK_INK if best == "celestial" else Color.WHITE, 20)
		t.size_flags_vertical = SIZE_SHRINK_CENTER
		_bonus_box.add_child(t)
		_bonus_note.text = "%s bonus active" % str(Kit.FACTION_NAMES.get(best, best))
		_bonus_note.add_theme_color_override("font_color", Kit.GOOD)
	else:
		_bonus_note.text = "Faction bonus: 3 / 4 / 5 alike give +%d / %d / %d%%" % [
			BattleSim.faction_bonus_bp(3) / 100, BattleSim.faction_bonus_bp(4) / 100, BattleSim.faction_bonus_bp(5) / 100]
		_bonus_note.add_theme_color_override("font_color", Kit.INK_DIM)


func _refresh_hint() -> void:
	for c in _hint_box.get_children():
		c.queue_free()
	var st := Game.current_stage()
	if st.is_empty():
		var done := Kit.caption("Every stage is cleared. Replay stages from the campaign map.", 22)
		done.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_hint_box.add_child(done)
		return
	var enemy_counts := {}
	for e: Dictionary in st.get("enemies", []):
		var f := str(Game.hero_def(str(e.hero_id)).get("faction", ""))
		enemy_counts[f] = int(enemy_counts.get(f, 0)) + 1
	var head := Kit.hbox(8)
	head.mouse_filter = MOUSE_FILTER_IGNORE
	var t := Kit.label("Next: %s  %s" % [str(st.id), str(st.name)], 24, Kit.GOLD_LIGHT, "extrabold")
	t.size_flags_horizontal = SIZE_EXPAND_FILL
	t.clip_text = true
	t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	head.add_child(t)
	head.add_child(Kit.caption("Enemies", 20))
	for f: String in Kit.FACTIONS:
		if enemy_counts.has(f):
			head.add_child(Kit.faction_icon(f, 32))
			head.add_child(Kit.label("x%d" % int(enemy_counts[f]), 22, Kit.INK, "black", 4))
	_hint_box.add_child(head)
	# Which of our factions beat theirs, and how many of them are fielded.
	var mine := _faction_counts(_slots)
	var row := Kit.hbox(8)
	row.mouse_filter = MOUSE_FILTER_IGNORE
	row.add_child(Kit.caption("Counter with", 20))
	var fielded := 0
	var shown := {}
	for ef: String in Kit.FACTIONS:
		if not enemy_counts.has(ef):
			continue
		for f: String in Kit.FACTIONS:
			if str(BattleSim.BEATS.get(f, "")) == ef and not shown.has(f):
				shown[f] = true
				row.add_child(Kit.faction_icon(f, 30))
				var nm := Kit.label(str(Kit.FACTION_NAMES.get(f, f)), 22, Kit.faction_color(f).lerp(Color.WHITE, 0.3), "extrabold")
				row.add_child(nm)
				fielded += int(mine.get(f, 0))
	var adv := Kit.caption("(+%d%% damage)" % (BattleSim.ADVANTAGE_BP / 100), 20, Kit.GOOD)
	adv.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(adv)
	row.add_child(Kit.label("%d in team" % fielded, 22, Kit.GOOD if fielded > 0 else Kit.INK_DIM, "black"))
	_hint_box.add_child(row)


func _refresh_list() -> void:
	if _grid == null:
		return
	var keep := _list_scroll.scroll_vertical
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	var owned := Game.owned_heroes()
	var shown := 0
	for h: Dictionary in owned:
		var id := str(h.id)
		var fac := str(Game.hero_def(id).get("faction", ""))
		if _filter_idx > 0 and fac != Kit.FACTIONS[_filter_idx - 1]:
			continue
		shown += 1
		var in_team := _slots.has(id)
		var cb := func() -> void: _tap_hero(id)
		var card := Kit.hero_card(id, {"size": 118, "show_name": true, "checked": in_team, "on_pressed": cb})
		_grid.add_child(card)
	if shown == 0:
		var l := Kit.caption("No heroes of this faction yet.", 22)
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
