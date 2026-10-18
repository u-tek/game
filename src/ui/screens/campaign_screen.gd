extends Control
## Screen "campaign" (style v2, docs/dev/ui-style-v2.md section 6): one chapter at a time on
## its full-bleed chapter art. A dark header strip holds Back, the chapter tabs (CH. 1-3,
## locked ones show a lock) and the chapter progress. Below it, a scrolling tactical map:
## the chapter title, a technical route and hexagon stage nodes (cleared cyan, current with
## a glowing orange rim, bosses with a red roof and the boss's face). Tapping a node selects
## it; the white stage panel pinned at the bottom shows the selected stage (id, name,
## recommended power, enemy echoes and the counter faction, first-clear rewards) with Team
## and Fight. The first visit to a newly opened chapter shows its story intro.
## params: open_stage (int) selects that stage (and its chapter); intro (bool, default true).

const SceneBackdrop := preload("res://src/ui/battle/scene_backdrop.gd")
const StageNode := preload("res://src/ui/battle/stage_node.gd")
const CampaignPath := preload("res://src/ui/battle/campaign_path.gd")
const StageInfo := preload("res://src/ui/battle/stage_info.gd")

const ROW_H := 140.0
const NODE := 100.0
const BOSS_NODE := 128.0
## Map space above the first node (chapter title) and below the last.
const MAP_TOP := 320.0
const MAP_BOTTOM := 90.0
const GRID := 60.0
## Game setting holding the highest chapter index whose intro the player has seen.
const INTRO_KEY := "chapter_intro_seen"

var _params: Dictionary = {}
var _chapter := -1
var _selected := -1
var _backdrop: Control
var _col: VBoxContainer
var _tabs_slot: HBoxContainer
var _progress: Label
var _scroll: ScrollContainer
var _map: Control
var _path: Control
var _nodes: Dictionary = {}
var _panel_body: VBoxContainer
var _fight_btn: Button
var _popup: Control


func setup(params: Dictionary) -> void:
	_params = params
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
	var map_holder := Control.new()
	map_holder.size_flags_vertical = SIZE_EXPAND_FILL
	map_holder.mouse_filter = MOUSE_FILTER_PASS
	map_holder.clip_contents = true
	_col.add_child(map_holder)
	_scroll = Kit.scroll(Control.new())
	_scroll.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	map_holder.add_child(_scroll)
	# Soft scrim under the header strip: map nodes passing beneath fade out instead of
	# being sliced by its edge.
	var scrim := TextureRect.new()
	scrim.name = "HeaderScrim"
	scrim.mouse_filter = MOUSE_FILTER_IGNORE
	scrim.texture = Kit.vgradient(Color("0e1628f5"), Color("0e162800"))
	scrim.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	scrim.stretch_mode = TextureRect.STRETCH_SCALE
	scrim.anchor_right = 1.0
	scrim.offset_bottom = 46
	map_holder.add_child(scrim)
	var panel := Kit.info_panel(18)
	panel.name = "StagePanel"
	_panel_body = Kit.vbox(8)
	panel.add_child(_panel_body)
	var pm := Kit.margin(panel, 10, 8)
	pm.add_theme_constant_override("margin_bottom", 8 + int(UI.pinned_bottom_inset()))
	_col.add_child(pm)
	_place_col()
	resized.connect(_place_col)

	var open := int(params.get("open_stage", -1))
	var focus := open if open >= 0 and Game.stage_status(open) != "locked" else _default_stage()
	_show_chapter(int(Game.stage(focus).get("chapter", 0)), focus)
	Game.changed.connect(_refresh)
	_after_layout.call_deferred()


func _exit_tree() -> void:
	if Game.changed.is_connected(_refresh):
		Game.changed.disconnect(_refresh)


func _place_col() -> void:
	_col.offset_top = UI.content_top()
	_col.offset_bottom = -UI.content_bottom()


func _refresh() -> void:
	if _selected >= 0 and is_inside_tree():
		_build_panel(_selected)


## The stage to show by default: the next one to clear (or the last stage).
func _default_stage() -> int:
	return mini(Game.cleared_count(), Game.stages().size() - 1)


## Index of the chapter the player is currently in.
func _frontier_chapter() -> int:
	var chs := Game.chapters()
	return clampi(int(Game.stage(_default_stage()).get("chapter", 0)), 0, chs.size() - 1)


# ------------------------------------------------------------------ header

func _build_header() -> Control:
	var bar := PanelContainer.new()
	bar.name = "Header"
	bar.mouse_filter = MOUSE_FILTER_PASS
	bar.add_theme_stylebox_override("panel", Kit.box(Color("080c19e6"), Color("0e1628e6"), Color.TRANSPARENT, 0, 0, 0))
	var row := Kit.hbox(8)
	var back := Kit.icon_button("back", func() -> void: UI.back(), Kit.BUTTON_H, "round")
	back.name = "Back"
	row.add_child(back)
	_tabs_slot = Kit.hbox(0)
	row.add_child(_tabs_slot)
	row.add_child(Kit.spacer(0, 0, true))
	var pv := Kit.vbox(0)
	pv.mouse_filter = MOUSE_FILTER_IGNORE
	pv.alignment = BoxContainer.ALIGNMENT_CENTER
	var cap := Kit.label("CLEARED", 16, Kit.INK_DIM, "cond_bold")
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pv.add_child(cap)
	_progress = Kit.label("", 34, Color.WHITE, "cond_bold")
	_progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pv.add_child(_progress)
	row.add_child(pv)
	bar.add_child(Kit.margin(row, 10, 4))
	return bar


func _rebuild_tabs() -> void:
	for c in _tabs_slot.get_children():
		c.queue_free()
	var opts: Array = []
	var chs := Game.chapters()
	var compact := chs.size() > 3       # more chapters than "CH. n" tabs fit beside Back: numbers only
	for ch: Dictionary in chs:
		var unlocked := Game.stage_status(int(ch.get("first_stage", 0))) != "locked"
		var num := int(ch.get("index", 0)) + 1
		var o := {"text": ("%d" % num) if compact else ("CH. %d" % num)}
		if not unlocked:
			o["icon"] = "lock"
			if compact:
				o["text"] = ""
		opts.append(o)
	var tabs := Kit.tab_strip(opts, _chapter, _on_tab, 76.0 if compact else 140.0)
	_tabs_slot.add_child(tabs)


func _on_tab(ci: int) -> void:
	var ch: Dictionary = Game.chapters()[ci]
	var first := int(ch.get("first_stage", 0))
	if Game.stage_status(first) == "locked":
		UI.toast("Clear %s first" % str(Game.stage(first - 1).get("id", "the previous chapter")))
		_rebuild_tabs.call_deferred()
		return
	var focus := _default_stage()
	if int(Game.stage(focus).get("chapter", 0)) != ci:
		focus = first + int(ch.get("stage_count", 10)) - 1
	_show_chapter(ci, focus)
	_after_layout.call_deferred(false)


# ------------------------------------------------------------------ map

## Shows chapter `ci` (backdrop, tabs, map) and selects stage `focus`.
func _show_chapter(ci: int, focus: int) -> void:
	_chapter = ci
	var ch: Dictionary = Game.chapters()[ci]
	for c in _backdrop.get_children():
		c.queue_free()
	var bd := SceneBackdrop.new()
	bd.kind = str(ch.get("background", "chapter-1"))
	bd.horizon = 0.3
	bd.dim = 0.3
	bd.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_backdrop.add_child(bd)
	_rebuild_tabs()
	var first := int(ch.get("first_stage", 0))
	var count := int(ch.get("stage_count", 10))
	var done := clampi(Game.cleared_count() - first, 0, count)
	_progress.text = "%d / %d" % [done, count]
	_progress.add_theme_color_override("font_color", Kit.ACCENT_HI if done >= count else Color.WHITE)
	_build_map(ch)
	_select(focus)


func _build_map(ch: Dictionary) -> void:
	if _map and is_instance_valid(_map):
		_map.queue_free()
	_nodes.clear()
	var first := int(ch.get("first_stage", 0))
	var count := int(ch.get("stage_count", 10))
	_map = Control.new()
	_map.name = "Map"
	_map.mouse_filter = MOUSE_FILTER_PASS
	_map.custom_minimum_size = Vector2(0, MAP_TOP + ROW_H * (count - 1) + BOSS_NODE * 0.5 + MAP_BOTTOM)
	_map.draw.connect(_draw_grid)
	var old := _scroll.get_child(0)
	_scroll.remove_child(old)
	old.queue_free()
	_scroll.add_child(_map)
	_map.size_flags_horizontal = SIZE_EXPAND_FILL
	_map.add_child(_title_block(ch))
	_path = CampaignPath.new()
	_path.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_map.add_child(_path)
	var tint := HeroArt.faction_color(str(ch.get("faction", "celestial")))
	for j in count:
		var i := first + j
		var st := Game.stage(i)
		if st.is_empty():
			continue
		var status := Game.stage_status(i)
		var boss := bool(st.get("is_boss", false))
		var n := StageNode.new()
		n.name = "Stage_%s" % str(st.id)
		n.setup(str(st.id), status, boss, tint, BOSS_NODE if boss else NODE, _boss_of(st) if boss else "")
		var idx := i
		Kit.make_tappable(n, func() -> void: _on_node(idx))
		_map.add_child(n)
		_nodes[i] = n
		var lab := _node_label(st, status)
		_map.add_child(lab)
		n.set_meta("label", lab)
		if status == "current":
			var marker := Kit.tag("NEXT", Kit.ORANGE, Color.WHITE, 20)
			_map.add_child(marker)
			n.set_meta("marker", marker)
	_map.set_meta("first", first)
	_map.set_meta("count", count)
	_map.resized.connect(_layout_map)


## Chapter title over the art at the top of the map: "CHAPTER 2" with a technical line and
## the Story button, the chapter name, the enemy faction.
func _title_block(ch: Dictionary) -> Control:
	var v := Kit.vbox(0)
	v.name = "ChapterTitle"
	v.mouse_filter = MOUSE_FILTER_PASS
	v.anchor_right = 1.0
	v.offset_left = 24
	v.offset_right = -18
	v.offset_top = 22
	var ci := int(ch.get("index", 0))
	var top := Kit.hbox(10)
	top.mouse_filter = MOUSE_FILTER_PASS
	top.add_child(Kit.label("CHAPTER %d" % (ci + 1), 24, Kit.ACCENT_HI, "cond_bold"))
	var tl := Kit.deco("techline", Vector2(60, 10), Color(1, 1, 1, 0.45))
	tl.size_flags_horizontal = SIZE_EXPAND_FILL
	tl.size_flags_vertical = SIZE_SHRINK_CENTER
	top.add_child(tl)
	var story := Kit.secondary_button("Story", func() -> void: _show_intro(ci, Callable()), "info")
	story.custom_minimum_size = Vector2(150, Kit.BUTTON_H)
	story.add_theme_font_size_override("font_size", 24)
	top.add_child(story)
	v.add_child(top)
	var t := Kit.title(str(ch.get("name", "")).to_upper(), 62)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	v.add_child(t)
	var row := Kit.hbox(10)
	row.mouse_filter = MOUSE_FILTER_IGNORE
	var badge := Kit.faction_badge(str(ch.get("faction", "celestial")), 32)
	badge.size_flags_vertical = SIZE_SHRINK_CENTER
	row.add_child(badge)
	row.add_child(Kit.label("ECHOES", 19, Color(1, 1, 1, 0.8), "cond_bold"))
	v.add_child(row)
	return v


## Faint technical grid with crosses over the map.
func _draw_grid() -> void:
	var w := _map.size.x
	var h := _map.size.y
	var col := Color(1, 1, 1, 0.045)
	var x := fmod(w * 0.5, GRID)
	while x < w:
		_map.draw_line(Vector2(x, 0), Vector2(x, h), col, 1.0)
		x += GRID
	var y := 0.0
	while y < h:
		_map.draw_line(Vector2(0, y), Vector2(w, y), col, 1.0)
		y += GRID
	var k := 0
	x = fmod(w * 0.5, GRID)
	while x < w:
		y = GRID * 2.0
		while y < h:
			if (k + int(y / GRID)) % 3 == 0:
				_map.draw_line(Vector2(x - 6, y), Vector2(x + 6, y), Color(1, 1, 1, 0.22), 1.5)
				_map.draw_line(Vector2(x, y - 6), Vector2(x, y + 6), Color(1, 1, 1, 0.22), 1.5)
			y += GRID * 2.0
		x += GRID * 2.0
		k += 1


func _node_label(st: Dictionary, status: String) -> Control:
	var v := Kit.vbox(2)
	v.mouse_filter = MOUSE_FILTER_IGNORE
	var name_l := Kit.label(str(st.name), 25, Kit.INK if status != "locked" else Kit.INK_DIM, "extrabold", 5)
	v.add_child(name_l)
	var row := Kit.hbox(6)
	row.mouse_filter = MOUSE_FILTER_IGNORE
	if status == "cleared":
		row.add_child(Kit.tag("CLEARED", Kit.ACCENT_DEEP, Color.WHITE, 17))
	else:
		var rec := int(st.get("recommended_power", 0))
		row.add_child(Kit.icon("power", 24))
		var c := StageInfo.power_color(int(Game.team_power()), rec) if status == "current" else Kit.INK_DIM
		row.add_child(Kit.label(Kit.format_num(rec), 22, c, "cond_bold", 4))
	v.add_child(row)
	return v


## Positions nodes on a sine route across the map width; labels go on the roomier side.
func _layout_map() -> void:
	if _map == null or not is_instance_valid(_map):
		return
	var first: int = _map.get_meta("first")
	var count: int = _map.get_meta("count")
	var w := _map.size.x
	var pts := PackedVector2Array()
	var reached := -1
	for j in count:
		var i := first + j
		var c := Vector2(w * (0.5 + 0.24 * sin(j * 1.15 + 0.6)), MAP_TOP + j * ROW_H)
		pts.append(c)
		if Game.stage_status(i) != "locked":
			reached = j
		if not _nodes.has(i):
			continue
		var n: Control = _nodes[i]
		n.position = c - n.size * 0.5
		var lab: Control = n.get_meta("label")
		var ls := lab.get_combined_minimum_size()
		var r := n.size.x * 0.5 + 12.0
		var left_side := c.x < w * 0.5
		for ch in lab.get_children():
			if ch is BoxContainer:
				(ch as BoxContainer).alignment = BoxContainer.ALIGNMENT_BEGIN if left_side else BoxContainer.ALIGNMENT_END
			elif ch is Label:
				(ch as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if left_side else HORIZONTAL_ALIGNMENT_RIGHT
		lab.size = ls
		lab.position = Vector2(c.x + r, c.y - ls.y * 0.5) if left_side else Vector2(c.x - r - ls.x, c.y - ls.y * 0.5)
		if n.has_meta("marker"):
			var mk: Control = n.get_meta("marker")
			var ms := mk.get_combined_minimum_size()
			mk.position = Vector2(c.x - ms.x * 0.5, c.y - n.size.y * 0.5 - ms.y - 2.0)
			mk.set_meta("y0", mk.position.y)
	_path.call("set_points", pts, reached)
	_map.queue_redraw()


func _process(_delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for i: int in _nodes:
		var n: Control = _nodes[i]
		if n.has_meta("marker"):
			var mk: Control = n.get_meta("marker")
			if mk.has_meta("y0"):
				mk.position.y = float(mk.get_meta("y0")) + sin(t * 4.0) * 4.0


## The boss of a stage (or its first enemy).
func _boss_of(st: Dictionary) -> String:
	var first := ""
	for e: Variant in st.get("enemies", []):
		if e is Dictionary:
			if first == "":
				first = str((e as Dictionary).get("hero_id", ""))
			if bool((e as Dictionary).get("is_boss", false)):
				return str((e as Dictionary).get("hero_id", ""))
	return first


# ------------------------------------------------------------------ flow

func _after_layout(intro: bool = true) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_inside_tree():
		return
	_scroll_to(_selected)
	if not intro:
		return
	var frontier := _frontier_chapter()
	var seen_v: Variant = Game.setting(INTRO_KEY)
	var seen: int = int(seen_v) if (seen_v is int or seen_v is float) else -1
	if bool(_params.get("intro", true)) and seen < frontier and Game.stage_status(int(Game.chapters()[frontier].first_stage)) != "locked":
		Game.set_setting(INTRO_KEY, frontier)
		_show_intro(frontier, Callable())


func _scroll_to(stage_index: int) -> void:
	if not _nodes.has(stage_index):
		return
	var n: Control = _nodes[stage_index]
	var y := n.position.y + n.size.y * 0.5
	var target := maxf(0.0, y - _scroll.size.y * 0.5)
	# Never leave the chapter title half under the header: show it whole while the node still
	# fits below it, otherwise scroll it fully away.
	var title := _map.get_node_or_null("ChapterTitle") as Control if _map else null
	if title:
		var tb := title.position.y + title.get_combined_minimum_size().y + 6.0
		if target > 0.0 and target < tb:
			target = 0.0 if y + n.size.y * 0.5 + 56.0 <= _scroll.size.y else tb
	_scroll.scroll_vertical = int(target)


func _on_node(i: int) -> void:
	if Game.stage_status(i) == "locked":
		var prev := Game.stage(maxi(0, Game.cleared_count()))
		UI.toast("Clear %s first" % str(prev.get("id", "the previous stage")))
		if _nodes.has(i):
			Kit.shake(_nodes[i], 8)
		return
	_select(i)


func _select(i: int) -> void:
	_selected = i
	for k: int in _nodes:
		(_nodes[k] as Control).set("selected", k == i)
	_build_panel(i)


# ------------------------------------------------------------------ stage panel

func _build_panel(i: int) -> void:
	for c in _panel_body.get_children():
		_panel_body.remove_child(c)
		c.queue_free()
	_fight_btn = null
	var st := Game.stage(i)
	if st.is_empty():
		return
	var status := Game.stage_status(i)
	var team := int(Game.team_power())
	var rec := int(st.get("recommended_power", 0))
	var ch: Dictionary = Game.chapters()[int(st.get("chapter", 0))]
	# Short screens (16:9 with insets) get a tighter panel so the map keeps some room.
	var compact := get_viewport_rect().size.y - UI.content_top() - UI.content_bottom() < 1000.0
	_panel_body.add_theme_constant_override("separation", 6 if compact else 8)

	# Stage id, name and the power check.
	var head := Kit.hbox(14)
	head.mouse_filter = MOUSE_FILTER_IGNORE
	var idv := Kit.vbox(0)
	idv.mouse_filter = MOUSE_FILTER_IGNORE
	idv.add_child(Kit.label("STAGE", 16, Kit.TEXT_DIM, "cond_bold"))
	idv.add_child(Kit.label(str(st.id), 46, Kit.ACCENT_DEEP, "title"))
	head.add_child(idv)
	var nv := Kit.vbox(2)
	nv.mouse_filter = MOUSE_FILTER_IGNORE
	nv.size_flags_horizontal = SIZE_EXPAND_FILL
	nv.alignment = BoxContainer.ALIGNMENT_CENTER
	var nm := Kit.label(str(st.get("name", "")), 28, Kit.TEXT, "extrabold")
	nm.clip_text = true
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nm.custom_minimum_size.x = 120
	nv.add_child(nm)
	var tags := Kit.hbox(6)
	tags.mouse_filter = MOUSE_FILTER_IGNORE
	tags.add_child(Kit.label(("CH. %d  ·  %s" % [int(st.get("chapter", 0)) + 1, str(ch.get("name", ""))]).to_upper(), 18, Kit.TEXT_DIM, "cond_bold"))
	if bool(st.get("is_boss", false)):
		tags.add_child(Kit.tag("BOSS", Kit.EMBER, Color.WHITE, 16))
	if status == "cleared":
		tags.add_child(Kit.tag("CLEARED", Kit.ACCENT_DEEP, Color.WHITE, 16))
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

	# Enemy echoes and the counter faction.
	var foe := StageInfo.main_faction(st)
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
	_panel_body.add_child(StageInfo.lineup(StageInfo.enemy_slots(st), 62 if compact else 72, true, true))
	var weak := str(BattleSim.BEATS.get(foe, ""))
	var n_weak := int(StageInfo.team_factions().get(weak, 0))
	if weak != "" and n_weak > 0 and not compact:
		var w := Kit.body("Careful: %s echoes deal +20%% damage to your %d %s hero%s." % [
			str(Kit.FACTION_NAMES.get(foe, foe)), n_weak, str(Kit.FACTION_NAMES.get(weak, weak)), "" if n_weak == 1 else "es"], 19, Color("c2410c"))
		w.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_panel_body.add_child(w)

	# First-clear rewards.
	var rw := Kit.hbox(12)
	rw.mouse_filter = MOUSE_FILTER_IGNORE
	var rcap := Kit.label("FIRST\nCLEAR", 18, Kit.TEXT_DIM, "cond_bold")
	rcap.add_theme_constant_override("line_spacing", -4)
	rw.add_child(rcap)
	if status != "cleared":
		var list := Kit.reward_list(st.get("first_clear_reward", {}), 60 if compact else 68, false, false, true)
		list.size_flags_horizontal = SIZE_EXPAND_FILL
		rw.add_child(list)
	else:
		var c := Kit.body("Claimed. Replays are practice: no first-clear rewards.", 20, Kit.TEXT_DIM)
		rw.add_child(c)
	_panel_body.add_child(rw)

	# Team and Fight.
	var row := Kit.hbox(12)
	var team_b := Kit.light_button("Team", func() -> void:
		# Coming back from the team screen selects this stage again.
		UI.current_params = {"open_stage": i, "intro": false}
		UI.go("formation"), "team")
	team_b.custom_minimum_size = Vector2(190, 88 if compact else 92)
	row.add_child(team_b)
	_fight_btn = Kit.orange_button("Fight", func() -> void: _fight(i), "sword")
	_fight_btn.size_flags_horizontal = SIZE_EXPAND_FILL
	_fight_btn.custom_minimum_size.y = 88 if compact else 92
	row.add_child(_fight_btn)
	_panel_body.add_child(row)
	# First-session guidance: the next stage's Fight button.
	Guide.mark(_fight_btn, status == "current" and Guide.step() == "battle", 0)


func _fight(i: int) -> void:
	var any := false
	for id: String in Game.formation():
		if id != "":
			any = true
	if not any:
		UI.toast("Place at least one hero in your formation", "bad")
		UI.go("formation")
		return
	# Coming back from the battle lands on the map with the next stage selected.
	UI.current_params = {}
	UI.go("battle", {"stage_index": i})


# ------------------------------------------------------------------ chapter intro

func _show_intro(ci: int, then: Callable) -> void:
	var chs := Game.chapters()
	if ci < 0 or ci >= chs.size():
		return
	var ch: Dictionary = chs[ci]
	var v := Kit.vbox(18)
	var art := Control.new()
	art.custom_minimum_size = Vector2(588, 240)
	art.clip_contents = true
	var bd := SceneBackdrop.new()
	bd.kind = str(ch.get("background", "chapter-1"))
	bd.horizon = 0.6
	bd.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	art.add_child(bd)
	var fr := Panel.new()
	fr.mouse_filter = MOUSE_FILTER_IGNORE
	fr.add_theme_stylebox_override("panel", Kit.box(Color.TRANSPARENT, Color.TRANSPARENT, Color(1, 1, 1, 0.5), 3, 1))
	fr.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	art.add_child(fr)
	var rib := Kit.ribbon("Chapter %d" % (ci + 1), 380, Kit.ACCENT, Color.WHITE, 36)
	rib.set_anchors_preset(PRESET_CENTER_BOTTOM)
	rib.offset_left = -190
	rib.offset_right = 190
	rib.offset_top = -86
	rib.offset_bottom = -10
	art.add_child(rib)
	v.add_child(art)
	var intro := Kit.body(str(ch.get("intro", "")), 26, Kit.TEXT)
	intro.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	intro.custom_minimum_size.x = 580
	v.add_child(intro)
	var foe := str(ch.get("faction", "celestial"))
	var ctr := StageInfo.counter_of(foe)
	var hint := PanelContainer.new()
	hint.add_theme_stylebox_override("panel", Kit.style("light_inset", 12))
	var hr := Kit.hbox(10)
	hr.alignment = BoxContainer.ALIGNMENT_CENTER
	hr.add_child(Kit.label("COUNTER", 20, Kit.ACCENT_DEEP, "cond_bold"))
	hr.add_child(Kit.faction_badge(ctr, 34, true, true))
	hr.add_child(Kit.label("heroes deal +20% here", 24, Color("1f9e63"), "extrabold"))
	hint.add_child(hr)
	v.add_child(hint)
	var m_ref: Array[Control] = []
	var go := Kit.primary_button("Onward", func() -> void:
		if not m_ref.is_empty():
			UI.close_modal(m_ref[0])
		if then.is_valid():
			then.call())
	go.custom_minimum_size.x = 320
	go.size_flags_horizontal = SIZE_SHRINK_CENTER
	v.add_child(go)
	_popup = UI.popup(str(ch.get("name", "")), v, then, 640, true)
	m_ref.append(_popup)
