extends Control
## Screen "campaign": the campaign as a winding road of stage medallions, one section per
## chapter (cleared / current / locked, bosses crowned). Tapping a stage opens its preview:
## enemy echoes, counter hint, power check, first-clear rewards, Fight and Edit Formation.
## The first visit to a newly opened chapter shows its story intro.
## params: open_stage (int) opens that stage's preview; intro (bool, default true).

const SceneBackdrop := preload("res://src/ui/battle/scene_backdrop.gd")
const StageNode := preload("res://src/ui/battle/stage_node.gd")
const CampaignPath := preload("res://src/ui/battle/campaign_path.gd")
const StageInfo := preload("res://src/ui/battle/stage_info.gd")

const ROW_H := 136.0
const NODE := 100.0
const BOSS_NODE := 126.0
const MAP_PAD := 70.0
## Game setting holding the highest chapter index whose intro the player has seen.
const INTRO_KEY := "chapter_intro_seen"

var _scroll: ScrollContainer
var _list: VBoxContainer
var _maps: Array[Control] = []
var _nodes: Dictionary = {}
var _power_label: Label
var _params: Dictionary = {}
var _popup: Control


func setup(params: Dictionary) -> void:
	_params = params
	var frontier := _frontier_chapter()
	var bd := SceneBackdrop.new()
	bd.kind = str(Game.chapters()[frontier].get("background", "chapter-1"))
	bd.horizon = 0.34
	bd.dim = 0.35
	bd.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(bd)

	var col := Kit.vbox(6)
	col.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	col.offset_left = 12
	col.offset_right = -12
	col.offset_top = 6
	add_child(col)
	var chip := Kit.panel("inset", 10)
	var pr := Kit.hbox(4)
	pr.mouse_filter = MOUSE_FILTER_IGNORE
	pr.add_child(Kit.icon("power", 30))
	_power_label = Kit.label("", 22, Kit.GOLD_LIGHT, "black", 4)
	pr.add_child(_power_label)
	chip.add_child(pr)
	col.add_child(Kit.screen_header("Campaign", Callable(), chip))

	_list = Kit.vbox(18)
	_scroll = Kit.scroll(Kit.margin(_list, 4, 8))
	col.add_child(_scroll)
	for ch: Dictionary in Game.chapters():
		_list.add_child(_chapter_section(ch))
	_list.add_child(Kit.spacer(0, 40))

	Game.changed.connect(_refresh)
	_refresh()
	_after_layout.call_deferred()


func _exit_tree() -> void:
	if Game.changed.is_connected(_refresh):
		Game.changed.disconnect(_refresh)


func _refresh() -> void:
	if _power_label:
		_power_label.text = Kit.format_num(int(Game.team_power()))


## Index of the chapter the player is currently in.
func _frontier_chapter() -> int:
	var chs := Game.chapters()
	var idx := mini(Game.cleared_count(), Game.stages().size() - 1)
	return clampi(int(Game.stage(idx).get("chapter", 0)), 0, chs.size() - 1)


# ------------------------------------------------------------------ chapter sections

func _chapter_section(ch: Dictionary) -> Control:
	var v := Kit.vbox(0)
	var first := int(ch.get("first_stage", 0))
	var count := int(ch.get("stage_count", 10))
	var cleared := Game.cleared_count()
	var unlocked := cleared >= first
	v.add_child(_chapter_banner(ch, clampi(cleared - first, 0, count), unlocked))
	var map := Control.new()
	map.custom_minimum_size = Vector2(0, MAP_PAD * 2.0 + ROW_H * (count - 1) + BOSS_NODE * 0.5)
	map.mouse_filter = MOUSE_FILTER_PASS
	var path := CampaignPath.new()
	path.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	path.color = Kit.GOLD
	map.add_child(path)
	map.set_meta("path", path)
	map.set_meta("first", first)
	map.set_meta("count", count)
	var tint := HeroArt.faction_color(str(ch.get("faction", "celestial")))
	for j in count:
		var i := first + j
		var st := Game.stage(i)
		if st.is_empty():
			continue
		var status := Game.stage_status(i)
		var boss := bool(st.get("is_boss", false))
		var n := StageNode.new()
		n.setup(str(st.id), status, boss, tint, BOSS_NODE if boss else NODE)
		var idx := i
		Kit._connect_pressed(n, func() -> void: _on_node(idx))
		map.add_child(n)
		_nodes[i] = n
		var lab := _node_label(st, status)
		map.add_child(lab)
		n.set_meta("label", lab)
		if status == "current":
			var marker := _next_marker()
			map.add_child(marker)
			n.set_meta("marker", marker)
	map.resized.connect(_layout_map.bind(map))
	_maps.append(map)
	v.add_child(map)
	return v


func _chapter_banner(ch: Dictionary, done: int, unlocked: bool) -> Control:
	var b := Control.new()
	b.custom_minimum_size = Vector2(0, 210)
	b.clip_contents = true
	b.mouse_filter = MOUSE_FILTER_PASS
	var art := SceneBackdrop.new()
	art.kind = str(ch.get("background", "chapter-1"))
	art.horizon = 0.62
	art.dim = 0.0 if unlocked else 0.45
	art.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	b.add_child(art)
	# Text shade on the left.
	var shade := Panel.new()
	shade.mouse_filter = MOUSE_FILTER_IGNORE
	shade.add_theme_stylebox_override("panel", Kit.box(Color(0.03, 0.02, 0.08, 0.15), Color(0.03, 0.02, 0.08, 0.75), Color.TRANSPARENT, 0))
	shade.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	b.add_child(shade)
	var frame := Panel.new()
	frame.mouse_filter = MOUSE_FILTER_IGNORE
	var fb := Kit.box(Color.TRANSPARENT, Color.TRANSPARENT, Color(Kit.GOLD, 0.7), 18, 2)
	frame.add_theme_stylebox_override("panel", fb)
	frame.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	b.add_child(frame)
	var v := Kit.vbox(2)
	v.mouse_filter = MOUSE_FILTER_IGNORE
	v.anchor_right = 1.0
	v.anchor_top = 1.0
	v.anchor_bottom = 1.0
	v.offset_left = 26
	v.offset_right = -26
	v.offset_top = -150
	v.offset_bottom = -16
	v.alignment = BoxContainer.ALIGNMENT_END
	var ci := int(ch.get("index", 0))
	v.add_child(Kit.label("CHAPTER %d" % (ci + 1), 22, Kit.GOLD, "black", 5))
	v.add_child(Kit.title(str(ch.get("name", "")), 46))
	(v.get_child(1) as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	var row := Kit.hbox(14)
	row.mouse_filter = MOUSE_FILTER_IGNORE
	var fac := str(ch.get("faction", "celestial"))
	row.add_child(Kit.faction_badge(fac, 30))
	row.add_child(Kit.label("echoes", 22, Kit.INK, "bold", 4))
	row.add_child(Kit.spacer(0, 0, true))
	if unlocked:
		var count := int(ch.get("stage_count", 10))
		row.add_child(Kit.label("%d / %d" % [done, count], 24, Kit.GOOD if done >= count else Kit.INK, "black", 5))
		if done >= count:
			row.add_child(Kit.icon("check", 30))
	else:
		row.add_child(Kit.icon("lock", 30))
		row.add_child(Kit.label("Clear %s" % _prev_boss_id(int(ch.get("first_stage", 0))), 22, Kit.INK_DIM, "extrabold", 4))
	v.add_child(row)
	b.add_child(v)
	if unlocked:
		var story := Kit.icon_button("info", func() -> void: _show_intro(ci, Callable()), 72, "round")
		story.anchor_left = 1.0
		story.anchor_right = 1.0
		story.offset_left = -84
		story.offset_right = -12
		story.offset_top = 12
		story.offset_bottom = 84
		b.add_child(story)
	return b


func _prev_boss_id(first_stage: int) -> String:
	var st := Game.stage(first_stage - 1)
	return str(st.get("id", "")) if not st.is_empty() else ""


func _node_label(st: Dictionary, status: String) -> Control:
	var v := Kit.vbox(0)
	v.mouse_filter = MOUSE_FILTER_IGNORE
	var name_l := Kit.label(str(st.name), 25, Kit.INK if status != "locked" else Kit.INK_DIM, "extrabold", 6)
	v.add_child(name_l)
	var row := Kit.hbox(6)
	row.mouse_filter = MOUSE_FILTER_IGNORE
	if bool(st.get("is_boss", false)):
		row.add_child(Kit.tag("BOSS", Kit.EMBER, Color.WHITE, 17))
	if status == "cleared":
		row.add_child(Kit.label("Cleared", 21, Kit.GOOD, "black", 4))
	else:
		var rec := int(st.get("recommended_power", 0))
		row.add_child(Kit.icon("power", 24))
		var c := StageInfo.power_color(int(Game.team_power()), rec) if status == "current" else Kit.INK_DIM
		row.add_child(Kit.label(Kit.format_num(rec), 21, c, "black", 4))
	v.add_child(row)
	return v


func _next_marker() -> Control:
	var m := Kit.tag("NEXT", Kit.GOLD, Color("3d2306"), 20)
	m.set_meta("bob", true)
	return m


## Positions nodes on a sine road across the map width; labels go on the roomier side.
func _layout_map(map: Control) -> void:
	var first: int = map.get_meta("first")
	var count: int = map.get_meta("count")
	var w := map.size.x
	var pts := PackedVector2Array()
	var reached := -1
	for j in count:
		var i := first + j
		var c := Vector2(w * (0.5 + 0.25 * sin(j * 1.15 + 0.6)), MAP_PAD + j * ROW_H)
		pts.append(c)
		if Game.stage_status(i) != "locked":
			reached = j
		if not _nodes.has(i):
			continue
		var n: Control = _nodes[i]
		n.position = c - n.size * 0.5
		var lab: Control = n.get_meta("label")
		var ls := lab.get_combined_minimum_size()
		var r := n.size.x * 0.5 + 14.0
		var left_side := c.x < w * 0.5
		for ch in lab.get_children():
			if ch is BoxContainer:
				(ch as BoxContainer).alignment = BoxContainer.ALIGNMENT_BEGIN if left_side else BoxContainer.ALIGNMENT_END
			elif ch is Label:
				(ch as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if left_side else HORIZONTAL_ALIGNMENT_RIGHT
		lab.size = ls
		if left_side:
			lab.position = Vector2(c.x + r, c.y - ls.y * 0.5)
		else:
			lab.position = Vector2(c.x - r - ls.x, c.y - ls.y * 0.5)
		if n.has_meta("marker"):
			var mk: Control = n.get_meta("marker")
			var ms := mk.get_combined_minimum_size()
			mk.position = Vector2(c.x - ms.x * 0.5, c.y - n.size.y * 0.5 - ms.y - 8)
			mk.set_meta("y0", mk.position.y)
	var path: Control = map.get_meta("path")
	path.call("set_points", pts, reached)


func _process(_delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for i: int in _nodes:
		var n: Control = _nodes[i]
		if n.has_meta("marker"):
			var mk: Control = n.get_meta("marker")
			if mk.has_meta("y0"):
				mk.position.y = float(mk.get_meta("y0")) + sin(t * 4.0) * 5.0


# ------------------------------------------------------------------ flow

func _after_layout() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_inside_tree():
		return
	var target := int(_params.get("open_stage", -1))
	var focus := target if target >= 0 else mini(Game.cleared_count(), Game.stages().size() - 1)
	_scroll_to(focus)
	var open := func() -> void:
		if target >= 0 and is_inside_tree():
			_open_stage(target)
	var frontier := _frontier_chapter()
	var seen_v: Variant = Game.setting(INTRO_KEY)
	var seen: int = int(seen_v) if (seen_v is int or seen_v is float) else -1
	if bool(_params.get("intro", true)) and seen < frontier and Game.stage_status(int(Game.chapters()[frontier].first_stage)) != "locked":
		Game.set_setting(INTRO_KEY, frontier)
		_show_intro(frontier, open)
	else:
		open.call()


func _scroll_to(stage_index: int) -> void:
	if not _nodes.has(stage_index):
		return
	var n: Control = _nodes[stage_index]
	var y := n.global_position.y - _list.global_position.y
	_scroll.scroll_vertical = int(maxf(0.0, y - _scroll.size.y * 0.42))


func _on_node(i: int) -> void:
	var status := Game.stage_status(i)
	if status == "locked":
		var prev := Game.stage(maxi(0, Game.cleared_count()))
		UI.toast("Clear %s first" % str(prev.get("id", "the previous stage")))
		if _nodes.has(i):
			Kit.shake(_nodes[i], 8)
		return
	_open_stage(i)


# ------------------------------------------------------------------ popups

func _show_intro(ci: int, then: Callable) -> void:
	var chs := Game.chapters()
	if ci < 0 or ci >= chs.size():
		return
	var ch: Dictionary = chs[ci]
	var v := Kit.vbox(18)
	var art := Control.new()
	art.custom_minimum_size = Vector2(560, 230)
	art.clip_contents = true
	var bd := SceneBackdrop.new()
	bd.kind = str(ch.get("background", "chapter-1"))
	bd.horizon = 0.6
	bd.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	art.add_child(bd)
	var fr := Panel.new()
	fr.mouse_filter = MOUSE_FILTER_IGNORE
	fr.add_theme_stylebox_override("panel", Kit.box(Color.TRANSPARENT, Color.TRANSPARENT, Color(Kit.GOLD, 0.7), 14, 2))
	fr.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	art.add_child(fr)
	var rib := Kit.ribbon("Chapter %d" % (ci + 1), 380, Kit.GOLD, Color("3d2306"), 36)
	rib.set_anchors_preset(PRESET_CENTER_BOTTOM)
	rib.offset_left = -190
	rib.offset_right = 190
	rib.offset_top = -86
	rib.offset_bottom = -10
	art.add_child(rib)
	v.add_child(art)
	var intro := Kit.body(str(ch.get("intro", "")), 27, Kit.INK)
	intro.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	intro.custom_minimum_size.x = 560
	v.add_child(intro)
	var foe := str(ch.get("faction", "celestial"))
	var ctr := StageInfo.counter_of(foe)
	var hint := Kit.hbox(10)
	hint.alignment = BoxContainer.ALIGNMENT_CENTER
	hint.add_child(Kit.faction_badge(ctr, 34))
	hint.add_child(Kit.label("heroes deal +20% here", 24, Kit.GOOD, "extrabold"))
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
	var m := UI.popup(str(ch.get("name", "")), v, then, 640)
	m_ref.append(m)


func _open_stage(i: int) -> void:
	var st := Game.stage(i)
	if st.is_empty():
		return
	var status := Game.stage_status(i)
	var team := int(Game.team_power())
	var rec := int(st.get("recommended_power", 0))
	var v := Kit.vbox(14)
	v.custom_minimum_size.x = 600

	var sub := Kit.hbox(10)
	sub.alignment = BoxContainer.ALIGNMENT_CENTER
	var ch: Dictionary = Game.chapters()[int(st.get("chapter", 0))]
	sub.add_child(Kit.caption("Chapter %d  ·  %s" % [int(st.get("chapter", 0)) + 1, str(ch.get("name", ""))], 22))
	if bool(st.get("is_boss", false)):
		sub.add_child(Kit.tag("BOSS", Kit.EMBER, Color.WHITE, 18))
	if status == "cleared":
		sub.add_child(Kit.tag("CLEARED", Kit.GOOD, Color("0e3024"), 18))
	v.add_child(sub)

	v.add_child(Kit.section_header("Enemy Echoes", 26))
	v.add_child(StageInfo.lineup(StageInfo.enemy_slots(st), 104, true))
	v.add_child(StageInfo.counter_hint(st))

	# Power check.
	var pv := StageInfo.verdict(team, rec)
	var prow := Kit.hbox(10)
	prow.alignment = BoxContainer.ALIGNMENT_CENTER
	prow.add_child(Kit.icon("power", 34))
	prow.add_child(Kit.label("Your team %s" % Kit.format_full(team), 25, pv[1], "black", 4))
	prow.add_child(Kit.caption("vs", 22))
	prow.add_child(Kit.label("Rec. %s" % Kit.format_full(rec), 25, Kit.INK, "black", 4))
	prow.add_child(Kit.tag(str(pv[0]), pv[1], Color("1a1030"), 18))
	v.add_child(prow)

	v.add_child(Kit.section_header("Your Team", 26))
	v.add_child(StageInfo.lineup(StageInfo.team_slots(), 88, false))

	if status != "cleared":
		v.add_child(Kit.section_header("First Clear", 26))
		v.add_child(StageInfo.reward_preview(st.get("first_clear_reward", {}), 84))
	else:
		var c := Kit.body("Already cleared. Replays are practice: no first-clear rewards.", 22, Kit.INK_DIM)
		c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(c)

	var m_ref: Array[Control] = []
	var row := Kit.hbox(14)
	var edit := Kit.secondary_button("Formation", func() -> void:
		if not m_ref.is_empty():
			UI.close_modal(m_ref[0])
		# Coming back from the formation screen reopens this preview.
		UI.current_params = {"open_stage": i, "intro": false}
		UI.go("formation"), "heroes")
	edit.size_flags_horizontal = SIZE_EXPAND_FILL
	var fight := Kit.primary_button("Fight", func() -> void:
		if not m_ref.is_empty():
			UI.close_modal(m_ref[0])
		_fight(i), "sword")
	fight.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(edit)
	row.add_child(fight)
	v.add_child(row)
	_popup = UI.popup("%s  %s" % [str(st.id), str(st.name)], v, Callable(), 680)
	m_ref.append(_popup)


func _fight(i: int) -> void:
	var any := false
	for id: String in Game.formation():
		if id != "":
			any = true
	if not any:
		UI.toast("Place at least one hero in your formation", "bad")
		UI.go("formation")
		return
	# Coming back from the battle lands on the map (no preview), new chapter intros included.
	UI.current_params = {}
	UI.go("battle", {"stage_index": i})
