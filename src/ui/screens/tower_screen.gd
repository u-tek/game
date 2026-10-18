extends Control
## Screen "tower": the Spire (TowerData, data/tower.json). Full-bleed backdrop of the next
## floor, a header (Back, title, best floor), a ladder of floors around the next one (cleared
## below, locked above, boss floors marked) and a white panel for the next floor: power check,
## enemy echoes, first-clear rewards, Team and Fight. Before the unlock it says which stage
## opens it; after the top floor it says so.

const SceneBackdrop := preload("res://src/ui/battle/scene_backdrop.gd")
const StageInfo := preload("res://src/ui/battle/stage_info.gd")
## Floors shown on the ladder: this many above the next one and below it.
const ABOVE := 3
const BELOW := 1

var _backdrop: Control
var _col: VBoxContainer
var _best_label: Label
var _ladder: VBoxContainer
var _panel_body: VBoxContainer
var _fight_btn: Button


func setup(_params: Dictionary) -> void:
	UI.set_full_bleed(true)
	_backdrop = Control.new()
	_backdrop.name = "BackdropSlot"
	_backdrop.mouse_filter = MOUSE_FILTER_IGNORE
	_backdrop.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(_backdrop)
	_col = Kit.vbox(0)
	_col.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(_col)
	_col.add_child(_build_header())
	var mid := CenterContainer.new()
	mid.size_flags_vertical = SIZE_EXPAND_FILL
	mid.mouse_filter = MOUSE_FILTER_IGNORE
	_ladder = Kit.vbox(10)
	_ladder.name = "Ladder"
	_ladder.mouse_filter = MOUSE_FILTER_IGNORE
	mid.add_child(_ladder)
	_col.add_child(mid)
	var panel := Kit.info_panel(18)
	panel.name = "FloorPanel"
	_panel_body = Kit.vbox(8)
	panel.add_child(_panel_body)
	var pm := Kit.margin(panel, 10, 8)
	pm.add_theme_constant_override("margin_bottom", 8 + int(UI.pinned_bottom_inset()))
	_col.add_child(pm)
	_place_col()
	resized.connect(_place_col)
	Game.changed.connect(_refresh)
	_refresh()


func _exit_tree() -> void:
	if Game.changed.is_connected(_refresh):
		Game.changed.disconnect(_refresh)


func _place_col() -> void:
	_col.offset_top = UI.content_top()
	_col.offset_bottom = -UI.content_bottom()


func _refresh() -> void:
	if not is_inside_tree():
		return
	var nxt := mini(Game.tower_next(), Game.tower_floors())
	_show_backdrop(str(Game.tower_floor(nxt).get("background", "chapter-4")))
	_best_label.text = "%d / %d" % [Game.tower_best(), Game.tower_floors()]
	_build_ladder()
	_build_panel()


func _show_backdrop(kind: String) -> void:
	for c in _backdrop.get_children():
		if str(c.get("kind")) == kind:
			return
		_backdrop.remove_child(c)
		c.queue_free()
	var bd := SceneBackdrop.new()
	bd.kind = kind
	bd.dim = 0.2
	bd.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_backdrop.add_child(bd)


# ------------------------------------------------------------------ header

func _build_header() -> Control:
	var bar := PanelContainer.new()
	bar.name = "Header"
	bar.mouse_filter = MOUSE_FILTER_PASS
	bar.add_theme_stylebox_override("panel", Kit.box(Color("080c19e6"), Color("0e1628e6"), Color.TRANSPARENT, 0, 0, 0))
	var row := Kit.hbox(12)
	var back := Kit.icon_button("back", func() -> void: UI.back(), Kit.BUTTON_H, "round")
	back.name = "Back"
	row.add_child(back)
	var tv := Kit.vbox(0)
	tv.mouse_filter = MOUSE_FILTER_IGNORE
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	tv.add_child(Kit.label(TowerData.NAME.to_upper(), 34, Color.WHITE, "title"))
	tv.add_child(Kit.label("CLIMB AS HIGH AS YOU CAN", 15, Kit.INK_DIM, "cond_bold"))
	row.add_child(tv)
	row.add_child(Kit.spacer(0, 0, true))
	var pv := Kit.vbox(0)
	pv.mouse_filter = MOUSE_FILTER_IGNORE
	pv.alignment = BoxContainer.ALIGNMENT_CENTER
	var cap := Kit.label("BEST FLOOR", 16, Kit.INK_DIM, "cond_bold")
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pv.add_child(cap)
	_best_label = Kit.label("", 34, Color.WHITE, "cond_bold")
	_best_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pv.add_child(_best_label)
	row.add_child(pv)
	bar.add_child(Kit.margin(row, 10, 4))
	return bar


# ------------------------------------------------------------------ ladder

func _build_ladder() -> void:
	for c in _ladder.get_children():
		_ladder.remove_child(c)
		c.queue_free()
	var nxt := Game.tower_next()
	var top := mini(nxt + ABOVE, Game.tower_floors())
	var bottom := maxi(1, nxt - BELOW)
	for f in range(top, bottom - 1, -1):
		_ladder.add_child(_floor_plate(f, nxt))


## One floor on the ladder: number, boss tag, and its state (cleared / next / locked).
func _floor_plate(f: int, nxt: int) -> Control:
	var fl := Game.tower_floor(f)
	var is_next := f == nxt
	var cleared := f < nxt
	var w := 460.0 if is_next else 380.0
	var fill := Color("18c3e8f0") if is_next else (Color("0d1824d0") if cleared else Color("0d1824a0"))
	var edge := Color("ffffff") if is_next else Color("ffffff40")
	var p := PanelContainer.new()
	p.name = "Floor_%d" % f
	p.mouse_filter = MOUSE_FILTER_IGNORE
	p.custom_minimum_size = Vector2(w, 74.0 if is_next else 58.0)
	p.size_flags_horizontal = SIZE_SHRINK_CENTER
	p.add_theme_stylebox_override("panel", Kit.box(fill, fill.darkened(0.25), edge, 18.0, 2, 0))
	var row := Kit.hbox(10)
	row.mouse_filter = MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	if cleared:
		row.add_child(Kit.icon("check", 26, Kit.GOOD))
	elif not is_next:
		row.add_child(Kit.icon("lock", 24, Kit.INK_DIM))
	var txt := Kit.label("FLOOR %d" % f, 34 if is_next else 26, Color.WHITE if is_next or cleared else Kit.INK_DIM, "cond_bold")
	row.add_child(txt)
	if bool(fl.get("is_boss", false)):
		row.add_child(Kit.tag("BOSS", Kit.EMBER, Color.WHITE, 16))
	elif f % 5 == 0:
		row.add_child(Kit.icon("gems", 26))
	p.add_child(Kit.margin(row, 14, 6))
	return p


# ------------------------------------------------------------------ next-floor panel

func _build_panel() -> void:
	for c in _panel_body.get_children():
		_panel_body.remove_child(c)
		c.queue_free()
	_fight_btn = null
	if not Game.tower_unlocked():
		var need := TowerData.UNLOCK_CLEARED
		var st := Game.stage(need - 1)
		_panel_body.add_child(Kit.header_bar("Locked"))
		var msg := Kit.body("Clear stage %s in the campaign to open %s." % [str(st.get("id", need)), TowerData.NAME], 24, Kit.TEXT)
		msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_panel_body.add_child(msg)
		var go := Kit.orange_button("Campaign", func() -> void: UI.go("campaign"), "campaign")
		go.custom_minimum_size.y = 92
		_panel_body.add_child(go)
		return
	var f := Game.tower_next()
	if f > Game.tower_floors():
		_panel_body.add_child(Kit.header_bar("Summit"))
		var top := Kit.body("You cleared every floor of %s. More floors are coming." % TowerData.NAME, 24, Kit.TEXT)
		top.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_panel_body.add_child(top)
		return
	var fl := Game.tower_floor(f)
	var team := int(Game.team_power())
	var rec := int(fl.get("recommended_power", 0))
	var compact := get_viewport_rect().size.y - UI.content_top() - UI.content_bottom() < 1000.0

	var head := Kit.hbox(14)
	head.mouse_filter = MOUSE_FILTER_IGNORE
	var idv := Kit.vbox(0)
	idv.mouse_filter = MOUSE_FILTER_IGNORE
	idv.add_child(Kit.label("FLOOR", 16, Kit.TEXT_DIM, "cond_bold"))
	idv.add_child(Kit.label(str(f), 46, Kit.ACCENT_DEEP, "title"))
	head.add_child(idv)
	var nv := Kit.vbox(2)
	nv.mouse_filter = MOUSE_FILTER_IGNORE
	nv.size_flags_horizontal = SIZE_EXPAND_FILL
	nv.alignment = BoxContainer.ALIGNMENT_CENTER
	nv.add_child(Kit.label(TowerData.NAME, 28, Kit.TEXT, "extrabold"))
	var tags := Kit.hbox(6)
	tags.mouse_filter = MOUSE_FILTER_IGNORE
	tags.add_child(Kit.label(("Best %d" % Game.tower_best()).to_upper(), 18, Kit.TEXT_DIM, "cond_bold"))
	if bool(fl.get("is_boss", false)):
		tags.add_child(Kit.tag("BOSS", Kit.EMBER, Color.WHITE, 16))
	nv.add_child(tags)
	head.add_child(nv)
	var pv := StageInfo.verdict_light(team, rec)
	var rv := Kit.vbox(0)
	rv.mouse_filter = MOUSE_FILTER_IGNORE
	rv.alignment = BoxContainer.ALIGNMENT_CENTER
	var rl := Kit.label("REC. POWER", 16, Kit.TEXT_DIM, "cond_bold")
	rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rv.add_child(rl)
	var rrow := Kit.hbox(4)
	rrow.mouse_filter = MOUSE_FILTER_IGNORE
	rrow.alignment = BoxContainer.ALIGNMENT_END
	rrow.add_child(Kit.icon("power", 26))
	rrow.add_child(Kit.label(Kit.format_full(rec), 32, Kit.TEXT, "cond_bold"))
	rv.add_child(rrow)
	var vrow := Kit.hbox(6)
	vrow.mouse_filter = MOUSE_FILTER_IGNORE
	vrow.alignment = BoxContainer.ALIGNMENT_END
	vrow.add_child(Kit.label("TEAM %s" % Kit.format_num(team), 17, pv[1], "cond_bold"))
	vrow.add_child(Kit.tag(str(pv[0]).to_upper(), pv[1], Color.WHITE, 15))
	rv.add_child(vrow)
	head.add_child(rv)
	_panel_body.add_child(head)

	var foe := StageInfo.main_faction(fl)
	var ctr := StageInfo.counter_of(foe)
	var chip: Control = null
	if ctr != "":
		var cr := Kit.hbox(6)
		cr.mouse_filter = MOUSE_FILTER_IGNORE
		cr.add_child(Kit.label("COUNTER", 18, Kit.INK_DIM, "cond_bold"))
		cr.add_child(Kit.faction_icon(ctr, 26))
		cr.add_child(Kit.label("+20%", 20, Kit.GOOD, "cond_bold"))
		chip = cr
	_panel_body.add_child(Kit.header_bar("Enemy echoes", chip))
	_panel_body.add_child(StageInfo.lineup(StageInfo.enemy_slots(fl), 62 if compact else 72, true, true))

	var rw := Kit.hbox(12)
	rw.mouse_filter = MOUSE_FILTER_IGNORE
	var rcap := Kit.label("FIRST\nCLEAR", 18, Kit.TEXT_DIM, "cond_bold")
	rcap.add_theme_constant_override("line_spacing", -4)
	rw.add_child(rcap)
	var list := Kit.reward_list(fl.get("first_clear_reward", {}), 60 if compact else 68, false, false, true)
	list.size_flags_horizontal = SIZE_EXPAND_FILL
	rw.add_child(list)
	_panel_body.add_child(rw)

	var row := Kit.hbox(12)
	var team_b := Kit.light_button("Team", func() -> void: UI.go("formation"), "team")
	team_b.custom_minimum_size = Vector2(190, 88 if compact else 92)
	row.add_child(team_b)
	_fight_btn = Kit.orange_button("Fight", func() -> void: _fight(f), "sword")
	_fight_btn.name = "FightFloor"
	_fight_btn.size_flags_horizontal = SIZE_EXPAND_FILL
	_fight_btn.custom_minimum_size.y = 88 if compact else 92
	row.add_child(_fight_btn)
	_panel_body.add_child(row)


func _fight(f: int) -> void:
	if Game.formation().all(func(x: Variant) -> bool: return str(x) == ""):
		UI.toast("Place at least one hero in your formation", "bad")
		UI.go("formation")
		return
	UI.go("battle", {"mode": "tower", "floor": f})
