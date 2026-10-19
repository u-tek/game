extends Control
## Screen "campaign" (style v4 "Signal", the approved poster look; docs/dev/ui-style-v4.md): one
## chapter as a printed survey poster on the paper matte. A dark band down the left carries the
## chapter boss as a red halftone print and the micro type (back, ©, sheet number, date); the
## chapter name runs huge down the poster in compressed type, two-tone where it crosses the band.
## The centrepiece is the chapter's exploded survey map (src/ui/v4/survey/survey_map.gd: a real 3D
## terrain slab printed as halftone relief, with CONTOURS, HYDROGRAPHY and the STAGE sheet pulled
## apart above it, leader lines and mono ids); tap a stage mark to select it, drag to turn the map.
## Top right, the chapter's title block (sheet number, name, coordinates, host, counter, cleared);
## down the right edge, the chapter index as vertical labels with ticks (STORY, CH 01-06, locked
## ones dim). Under the map, the selected stage's cartouche (id, name, power check, enemy echoes,
## first-clear rewards, BOSS / CLEARED stamps), the TEAM stamp and the Fight pass stuck on.
## The first visit to a newly opened chapter shows its story intro.
## params: open_stage (int) selects that stage (and its chapter); intro (bool, default true).

const Poster := preload("res://src/ui/v4/survey/poster.gd")
const SurveyMap := preload("res://src/ui/v4/survey/survey_map.gd")
const SceneBackdrop := preload("res://src/ui/battle/scene_backdrop.gd")
const StageInfo := preload("res://src/ui/battle/stage_info.gd")

## Game setting holding the highest chapter index whose intro the player has seen.
const INTRO_KEY := "chapter_intro_seen"
const W := 720.0
const BAND_W := 132.0
## The index column on the right edge.
const RULE_W := 48.0
const INK := Color("101113")
const PAPER := Color("e9e8e2")
const SIG := Color("ff4b1f")

var _params: Dictionary = {}
var _chapter := -1
var _selected := -1
var _root: Control
var _poster: Control
var _pr := Rect2()
var _map: SurveyMap
var _sheet: Control
var _pass_slot: Control
var _fight_btn: Button
var _popup: Control
var _stage_y := 0.0


func setup(params: Dictionary) -> void:
	_params = params
	UI.set_full_bleed(true)
	Poster.matte(self)
	_root = Control.new()
	_root.name = "Sheet"
	_root.mouse_filter = MOUSE_FILTER_IGNORE
	_root.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(_root)
	var open := int(params.get("open_stage", -1))
	var focus := open if open >= 0 and Game.stage_status(open) != "locked" else _default_stage()
	var preview := int(params.get("preview_chapter", -1))
	if preview >= 0 and preview < Game.chapters().size() and OS.is_debug_build():
		# Screenshots / design review (debug builds): print any chapter, locked or not.
		focus = int(Game.chapters()[preview].get("first_stage", 0)) + int(Game.chapters()[preview].get("stage_count", 10)) - 1
	_show_chapter(int(Game.stage(focus).get("chapter", 0)), focus)
	Game.changed.connect(_refresh)
	_after_layout.call_deferred()


## The screen's own entrance (UI calls it instead of the generic stagger): the map's sheets lift
## off the terrain by themselves.
func intro() -> void:
	pass


func _exit_tree() -> void:
	if Game.changed.is_connected(_refresh):
		Game.changed.disconnect(_refresh)


func _refresh() -> void:
	if _selected >= 0 and is_inside_tree():
		_build_cartouche(_selected)


## The stage to show by default: the next one to clear (or the last stage).
func _default_stage() -> int:
	return mini(Game.cleared_count(), Game.stages().size() - 1)


## Index of the chapter the player is currently in.
func _frontier_chapter() -> int:
	var chs := Game.chapters()
	return clampi(int(Game.stage(_default_stage()).get("chapter", 0)), 0, chs.size() - 1)


# ------------------------------------------------------------------ the poster

## Shows chapter `ci` (the whole poster is printed for it) and selects stage `focus`.
func _show_chapter(ci: int, focus: int) -> void:
	_chapter = ci
	for c in _root.get_children():
		_root.remove_child(c)
		c.queue_free()
	_build_poster(Game.chapters()[ci])
	_select(focus)


func _build_poster(ch: Dictionary) -> void:
	var vh := get_viewport_rect().size.y
	var top := UI.content_top()
	var bottom := UI.content_bottom()
	_pr = Rect2(18, top + 12, W - 36, vh - bottom - 58 - (top + 12))
	_poster = Poster.poster(_root, _pr)
	var p := _poster
	var pw := _pr.size.x
	var ph := _pr.size.y
	var ci := int(ch.get("index", 0))
	var faction := str(ch.get("faction", "celestial"))
	var first := int(ch.get("first_stage", 0))
	var count := int(ch.get("stage_count", 10))
	var boss_id := _boss_of(Game.stage(first + count - 1))
	var done := clampi(Game.cleared_count() - first, 0, count)
	# The cartouche and the pass share the bottom; the map takes what is left above them.
	_stage_y = ph - 352.0

	# ---- The dark band: the chapter boss as a red halftone print, micro type.
	var band_c := Poster.BAND if faction != "celestial" else Color("1d1f23")
	Poster.rect(p, Rect2(0, 0, BAND_W, ph), band_c)
	if boss_id != "":
		var ink := Color(1.0, 0.36, 0.16, 0.95) if faction != "fallen" else Color(0.86, 0.84, 0.8, 0.85)
		Poster.halftone_print(p, boss_id, Rect2(0, ph * 0.36, BAND_W, ph * 0.64), ink, 6.5)
	var back_l := Poster.t("<  BACK", 13, PAPER)
	Poster.at(p, back_l, Vector2(20, 22))
	var back := Poster.hit(p, Rect2(0, 0, BAND_W, 88), func() -> void: UI.back(), "Back", "Back")
	back.tooltip_text = "Back"
	Poster.vlabel(p, "©2026 HH, SURVEY SHEET %02d. ALL RIGHTS RESERVED." % (ci + 1), Vector2(42, 96), 10, Color(PAPER, 0.8))
	Poster.at(p, Poster.t("No.\n%03d" % (ci + 1), 12, Color(PAPER, 0.85)), Vector2(70, ph * 0.3))
	Poster.at(p, Poster.t(Poster.date_short(), 12, Color(PAPER, 0.85)), Vector2(70, ph * 0.3 + 40))

	# ---- The chapter name, huge, down the poster (two-tone across the band).
	var name_txt := str(ch.get("name", ""))
	Poster.giant_side(p, name_txt, 150, 150.0, 104.0, 0.0, BAND_W, faction == "infernal")

	# ---- The survey map.
	_map = SurveyMap.new()
	_map.name = "SurveyMap"
	_map.position = Vector2(0, 100)
	_map.size = Vector2(pw - RULE_W - 4, _stage_y - 100 + 6)
	_map.overscan = Vector2(120, 120)
	_map.shift = Vector2(1.6, -0.25)
	# Raised stage labels stay below the title block (view px; the view starts 120 px higher).
	_map.label_floor = 132.0 + 120.0 - 100.0
	p.add_child(_map)
	var stages: Array = []
	for j in count:
		var st := Game.stage(first + j)
		stages.append({"id": str(st.get("id", "")), "name": str(st.get("name", "")), "status": Game.stage_status(first + j),
			"boss": bool(st.get("is_boss", false))})
	_map.show_chapter(ci, faction, stages)
	_map.stage_pressed.connect(func(j: int) -> void: _on_node(first + j))

	# ---- The title block (top right).
	var x0 := 252.0
	var tb := Control.new()
	tb.mouse_filter = MOUSE_FILTER_IGNORE
	tb.position = Vector2(x0, 16)
	p.add_child(tb)
	var tw := pw - RULE_W - 12 - x0
	Poster.at(tb, Poster.t("SURVEY No.%03d" % (ci + 1), 12, INK), Vector2(0, 0))
	var dl := Poster.t("CH %02d / %02d" % [ci + 1, Game.chapters().size()], 12, INK)
	dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	dl.size = Vector2(tw, 16)
	Poster.at(tb, dl, Vector2(0, 0))
	Poster.hline(tb, 0, 20, tw, Color(INK, 0.7))
	var nm := Poster.t(name_txt.to_upper(), 28, INK, "wide_black")
	Kit.fit_label(nm, tw - 96, 28, 16)
	Poster.at(tb, nm, Vector2(-2, 24))
	Poster.at(tb, Poster.t(Poster.coords(7919 * (ci + 3)), 11, Color(INK, 0.75), "mono"), Vector2(0, 62))
	var ctr := StageInfo.counter_of(faction)
	var host := "%s HOST" % str(Kit.FACTION_NAMES.get(faction, faction)).to_upper()
	var line := "%s   ·   COUNTER %s +20%%" % [host, str(Kit.FACTION_NAMES.get(ctr, ctr)).to_upper()] if ctr != "" else host
	Poster.at(tb, Poster.t(line, 11, INK, "mono_bold"), Vector2(0, 80))
	var cl := Poster.t("%02d/%02d" % [done, count], 22, SIG if done >= count else INK, "wide_black")
	cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cl.size = Vector2(tw, 26)
	Poster.at(tb, cl, Vector2(0, 30))
	var cc := Poster.t("CLEARED", 9, Color(INK, 0.7), "mono_bold")
	cc.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cc.size = Vector2(tw, 12)
	Poster.at(tb, cc, Vector2(0, 58))

	# ---- The index down the right edge: STORY, then the six chapters.
	var rx := pw - RULE_W
	Poster.vline(p, rx, 0, ph, Color(INK, 0.55))
	Poster.vlabel(p, "©2026 ·", Vector2(rx + 34, 12), 12, INK)
	var items: Array = [{"text": "STORY", "name": "Story", "on_pressed": func() -> void: _show_intro(ci, Callable())}]
	for chd: Dictionary in Game.chapters():
		var k := int(chd.get("index", 0))
		var unlocked := Game.stage_status(int(chd.get("first_stage", 0))) != "locked"
		items.append({"text": "CH %02d" % (k + 1) if unlocked else "CH %02d  X" % (k + 1), "name": "Chapter_%d" % (k + 1),
			"active": k == ci, "dim": not unlocked, "on_pressed": func() -> void: _on_tab(k)})
	var step := clampf((_stage_y - 96.0) / items.size(), 88.0, 104.0)
	Poster.side_menu(p, rx, 96.0, step, items)

	# ---- The cartouche (rebuilt per selected stage) and the pass slot.
	_sheet = Control.new()
	_sheet.name = "StagePanel"
	_sheet.mouse_filter = MOUSE_FILTER_IGNORE
	_sheet.position = Vector2(BAND_W, _stage_y)
	_sheet.size = Vector2(rx - BAND_W, ph - _stage_y)
	p.add_child(_sheet)
	_pass_slot = Control.new()
	_pass_slot.name = "PassSlot"
	_pass_slot.mouse_filter = MOUSE_FILTER_IGNORE
	_pass_slot.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_root.add_child(_pass_slot)

	# ---- Under the poster: the date and the boss's signature.
	var fy := _pr.end.y + 12.0
	Poster.at(_root, Poster.t(Poster.date_long(), 22, INK, "regular"), Vector2(20, fy + 8))
	var sig := Poster.t(str(Game.hero_def(boss_id).get("name", "")) if boss_id != "" else "", 40, INK, "serif_italic")
	sig.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sig.size = Vector2(300, 46)
	Poster.at(_root, sig, Vector2(W - 24 - 300, fy - 6))
	var swash := Poster.rect(_root, Rect2(W - 230, fy + 38, 200, 2), INK)
	swash.rotation = -0.05
	Poster.grain(_root)
	SignalKit.relight(_root)


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


func _on_tab(ci: int) -> void:
	var ch: Dictionary = Game.chapters()[ci]
	var first := int(ch.get("first_stage", 0))
	if Game.stage_status(first) == "locked":
		UI.toast("Clear %s first" % str(Game.stage(first - 1).get("id", "the previous chapter")))
		return
	if ci == _chapter:
		return
	var focus := _default_stage()
	if int(Game.stage(focus).get("chapter", 0)) != ci:
		focus = first + int(ch.get("stage_count", 10)) - 1
	_show_chapter(ci, focus)


# ------------------------------------------------------------------ flow

func _after_layout(intro: bool = true) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_inside_tree() or not intro:
		return
	var frontier := _frontier_chapter()
	var seen_v: Variant = Game.setting(INTRO_KEY)
	var seen: int = int(seen_v) if (seen_v is int or seen_v is float) else -1
	if bool(_params.get("intro", true)) and seen < frontier and Game.stage_status(int(Game.chapters()[frontier].first_stage)) != "locked":
		Game.set_setting(INTRO_KEY, frontier)
		_show_intro(frontier, Callable())


func _on_node(i: int) -> void:
	if Game.stage_status(i) == "locked":
		var prev := Game.stage(maxi(0, Game.cleared_count()))
		UI.toast("Clear %s first" % str(prev.get("id", "the previous stage")))
		Kit.shake(_sheet, 6)
		return
	Kit.sfx("tap")
	_select(i)


func _select(i: int) -> void:
	_selected = i
	var first := int(Game.chapters()[_chapter].get("first_stage", 0))
	if _map:
		_map.select(i - first)
	_build_cartouche(i)


# ------------------------------------------------------------------ the cartouche

## The selected stage, printed: id and name, the power check, enemy echoes with the counter,
## first-clear rewards, BOSS / CLEARED stamps; then the TEAM stamp and the Fight pass.
func _build_cartouche(i: int) -> void:
	for c in _sheet.get_children():
		_sheet.remove_child(c)
		c.queue_free()
	for c in _pass_slot.get_children():
		_pass_slot.remove_child(c)
		c.queue_free()
	_fight_btn = null
	var st := Game.stage(i)
	if st.is_empty():
		return
	var status := Game.stage_status(i)
	var team := int(Game.team_power())
	var rec := int(st.get("recommended_power", 0))
	var boss := bool(st.get("is_boss", false))
	var sw := _sheet.size.x
	var s := _sheet
	# A paper title block with a hairline frame (the map tucks behind it).
	Poster.rect(s, Rect2(0, 0, sw, 178), PAPER)
	Poster.hline(s, 0, 0, sw, INK, 1.5)
	Poster.hline(s, 0, 74, sw, Color(INK, 0.4))
	Poster.vline(s, sw * 0.62, 74, 104, Color(INK, 0.4))
	Poster.hline(s, 0, 178, sw, Color(INK, 0.4))
	# Row 1: STAGE id, name, power check.
	Poster.at(s, Poster.t("STAGE", 10, Color(INK, 0.7)), Vector2(14, 8))
	var idl := Poster.t(str(st.id), 40, SIG if status == "current" else INK, "wide_black")
	Poster.at(s, idl, Vector2(12, 18))
	var idw := idl.get_minimum_size().x
	var nm := Poster.t(str(st.get("name", "")).to_upper(), 36, INK, "compressed")
	var name_w := sw - idw - 40 - 162
	Kit.fit_label(nm, name_w, 36, 15)
	nm.clip_text = true
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nm.custom_minimum_size.x = minf(nm.get_minimum_size().x, name_w)
	nm.size.x = name_w
	Poster.at(s, nm, Vector2(idw + 28, 10))
	var verdict := StageInfo.verdict_light(team, rec)
	for row: Array in [["REC PWR %s" % Kit.format_full(rec), INK, "mono_bold", 10.0], ["TEAM %s" % Kit.format_num(team), Color(INK, 0.75), "mono", 30.0],
			[str(verdict[0]).to_upper(), verdict[1], "mono_bold", 50.0]]:
		var l := Poster.t(str(row[0]), 12, row[1], str(row[2]))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		l.size = Vector2(150, 16)
		Poster.at(s, l, Vector2(sw - 162, float(row[3])))
	var ch: Dictionary = Game.chapters()[int(st.get("chapter", 0))]
	Poster.at(s, Poster.t(("CH.%02d  ·  %s" % [int(st.get("chapter", 0)) + 1, str(ch.get("name", ""))]).to_upper(), 10, Color(INK, 0.7), "mono"), Vector2(idw + 30, 54))
	# Rubber stamps on the cartouche's top rule: BOSS in signal, CLEARED in ink.
	if boss:
		Poster.rubber(s, "BOSS", Vector2(sw - 236, -12), SIG, 14, -0.08)
	if status == "cleared":
		Poster.rubber(s, "CLEARED", Vector2(sw - 160, -13), Color(INK, 0.85), 14, 0.05)
	# Row 2: enemy echoes and the counter | first-clear rewards.
	var foe := StageInfo.main_faction(st)
	var ctr := StageInfo.counter_of(foe)
	var eh := "ENEMY ECHOES"
	if ctr != "":
		eh += "  ·  COUNTER %s +20%%" % str(Kit.FACTION_NAMES.get(ctr, ctr)).to_upper()
	Poster.at(s, Poster.t(eh, 10, INK), Vector2(14, 82))
	var strip := Poster.echo_strip(StageInfo.enemy_slots(st), 46.0)
	Poster.at(s, strip, Vector2(14, 100))
	var weak := str(BattleSim.BEATS.get(foe, ""))
	var n_weak := int(StageInfo.team_factions().get(weak, 0))
	if weak != "" and n_weak > 0:
		var wl := Poster.t("CAREFUL: +20%% VS YOUR %d %s" % [n_weak, str(Kit.FACTION_NAMES.get(weak, weak)).to_upper()], 9, SIG, "mono_bold")
		Poster.at(s, wl, Vector2(14, 164))
	var rx := sw * 0.62 + 12
	Poster.at(s, Poster.t("FIRST CLEAR", 10, INK), Vector2(rx, 82))
	if status != "cleared":
		var rl := Poster.reward_lines(st.get("first_clear_reward", {}), sw - rx - 10, 11)
		Poster.at(s, rl, Vector2(rx, 100))
	else:
		var cl := Poster.t("CLAIMED.\nREPLAYS ARE\nPRACTICE.", 11, Color(INK, 0.7), "mono")
		Poster.at(s, cl, Vector2(rx, 100))

	# The TEAM stamp and the Fight pass, stuck on over the bottom of the poster.
	var pp := _pr.position
	var ph := _pr.size.y
	Poster.stamp_disc(_pass_slot, "TEAM · FORMATION · POWER · ", Kit.format_num(team), pp + Vector2(BAND_W + 22, ph - 152), 112.0, -0.12,
		func() -> void:
			# Coming back from the team screen selects this stage again.
			UI.current_params = {"open_stage": i, "intro": false}
			UI.go("formation"), "Team", "Team")
	var spec := {"width": 400.0, "kicker": "ENGAGE // CH.%02d" % (int(st.get("chapter", 0)) + 1), "title": "STAGE %s" % str(st.id),
		"sub": str(st.get("name", "")).to_upper(), "action": "FIGHT  >>>", "icon": "sword",
		"info": "REC PWR %s" % Kit.format_full(rec)}
	var pass_root := Poster.pass_on(_pass_slot, spec, Vector2(pp.x + _pr.size.x - 412, pp.y + ph - 176), func() -> void: _fight(i), "Fight", "Fight")
	_fight_btn = Poster.pass_hit(pass_root)
	SignalKit.relight(_pass_slot)
	# First-session guidance: the next stage's Fight.
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
	var cap := Kit.label("SURVEY No.%03d  ·  CHAPTER %02d" % [ci + 1, ci + 1], 13, PAPER, "mono_bold")
	cap.position = Vector2(16, 14)
	art.add_child(cap)
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
	hr.add_child(Kit.label("COUNTER", 20, Kit.ACCENT_DEEP, "mono_bold"))
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
