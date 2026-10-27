extends Control
## Screen "campaign" (style v4 "Signal", the approved poster look; docs/dev/ui-style-v4.md): one
## chapter as a printed survey poster on the paper matte. A dark band down the left carries the
## chapter boss as a red halftone print and the micro type (back, ©, sheet number, date); the
## chapter name runs huge down the poster in compressed type, two-tone where it crosses the band.
## The centrepiece is the chapter's survey map (src/ui/v4/survey/survey_map.gd, built like the
## owner's isometric-terrain reference): a physical relief model of the chapter's world lying on the
## poster, its stage route a molten river, valleys lit warm, clouds drifting over it with their
## shadows, each stage a mark on the river with an id tag on a thin leader; tap a mark to select it,
## drag to turn the model. Printed with it: the survey data slip (area, relief, river, surface
## temperature in two units), the scale bar with a north arrow, and under the model the route profile
## (a sine wave through the stage circles; tap a circle to select that stage). The map is alive but
## calm (still with Reduce motion); BACK (SignalKit.back_button) sits at the top of the band.
## Top right, the chapter's title block (sheet number, name, coordinates, host, counter, cleared);
## down the right edge, the index (STORY, WORLDS, the chapter's place among the six). Under the map,
## the selected stage's cartouche (id, name, power check, enemy echoes, first-clear rewards, BOSS /
## CLEARED stamps), the TEAM stamp and the Fight pass stuck on.
## Chapters are worlds: WORLDS on the index zooms out to the chapter dossier (WorldDossier, built
## like the owner's planet-dossier reference: the chapter's planet turning in a printed instrument,
## the name between ‹ › arrows, a mono data list, the ENTER pass); tapping the world or ENTER dives
## into its survey map. The first visit to a newly opened chapter opens on its world, and entering
## it shows the chapter's story intro.
## params: open_stage (int) selects that stage (and its chapter); intro (bool, default true: false
## skips the first-visit world and the story); debug builds: preview_chapter (int) prints that
## chapter's map, dossier (int) that chapter's world, locked or not (look_open: printed as open).

const Poster := preload("res://src/ui/v4/survey/poster.gd")
const SurveyMap := preload("res://src/ui/v4/survey/survey_map.gd")
const SurveyLegend := preload("res://src/ui/v4/survey/survey_legend.gd")
const TerrainGen := preload("res://src/ui/v4/survey/terrain_gen.gd")
const WorldDossier := preload("res://src/ui/v4/survey/world_dossier.gd")
const SceneBackdrop := preload("res://src/ui/battle/scene_backdrop.gd")
const StageInfo := preload("res://src/ui/battle/stage_info.gd")

## Game setting holding the highest chapter index whose intro the player has seen.
const INTRO_KEY := "chapter_intro_seen"
const W := 720.0
const BAND_W := 132.0
## The index column on the right edge.
const RULE_W := 48.0
## The route profile's strip under the map.
const PROFILE_H := 92.0
const INK := SignalKit.INK
const PAPER := SignalKit.PAPER
const SIG := SignalKit.SIGNAL

var _params: Dictionary = {}
var _chapter := -1
var _selected := -1
var _root: Control
var _poster: Control
var _pr := Rect2()
var _map: SurveyMap
var _profile: Control
var _sheet: Control
var _pass_slot: Control
var _fight_btn: Button
var _popup: Control
var _stage_y := 0.0
## The chapter dossier while it shows (null on the map), and true while it dives into a map.
var _dossier: WorldDossier
var _diving := false


func setup(params: Dictionary) -> void:
	_params = params
	UI.set_full_bleed(true)
	Poster.matte(self)
	_root = Control.new()
	_root.name = "Sheet"
	_root.mouse_filter = MOUSE_FILTER_IGNORE
	_root.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(_root)
	Game.changed.connect(_refresh)
	var open := int(params.get("open_stage", -1))
	var focus := open if open >= 0 and Game.stage_status(open) != "locked" else _default_stage()
	var preview := int(params.get("preview_chapter", -1))
	var dossier := int(params.get("dossier", -1))
	if dossier >= 0 and dossier < Game.chapters().size() and OS.is_debug_build():
		# Screenshots / design review (debug builds): any chapter's world, locked or not;
		# auto_enter (s) dives into it after that long, auto_out (s) comes back out.
		_show_dossier(dossier)
		if params.has("auto_enter"):
			get_tree().create_timer(float(params["auto_enter"])).timeout.connect(func() -> void:
				if is_inside_tree():
					_enter_world(dossier)
					if params.has("auto_out"):
						get_tree().create_timer(float(params["auto_out"])).timeout.connect(func() -> void:
							if is_inside_tree():
								_show_worlds()))
		return
	if preview >= 0 and preview < Game.chapters().size() and OS.is_debug_build():
		# Screenshots / design review (debug builds): print any chapter, locked or not.
		focus = int(Game.chapters()[preview].get("first_stage", 0)) + int(Game.chapters()[preview].get("stage_count", 10)) - 1
	elif bool(params.get("intro", true)) and _intro_due():
		# A newly opened chapter (from the Lobby, or the battle's Next into a new chapter): its world
		# comes first; entering it shows the story.
		_show_dossier(_frontier_chapter())
		return
	_show_chapter(int(Game.stage(focus).get("chapter", 0)), focus)


## The screen's own entrance (UI calls it instead of the generic stagger): the map's model settles
## onto the poster, the world's instrument draws on, by themselves.
func intro() -> void:
	pass


func _exit_tree() -> void:
	if Game.changed.is_connected(_refresh):
		Game.changed.disconnect(_refresh)


func _refresh() -> void:
	if _selected >= 0 and is_inside_tree() and _dossier == null and _sheet != null and is_instance_valid(_sheet):
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
	_dossier = null
	_diving = false
	_clear()
	_build_poster(Game.chapters()[ci])
	_select(focus)


func _clear() -> void:
	for c in _root.get_children():
		_root.remove_child(c)
		c.queue_free()
	_map = null
	_profile = null
	_sheet = null
	_fight_btn = null


## The poster rect (inside the matte, between the masthead and the date line).
func _poster_rect() -> Rect2:
	var vh := get_viewport_rect().size.y
	var top := UI.content_top()
	var bottom := UI.content_bottom()
	return Rect2(18, top + 12, W - 36, vh - bottom - 58 - (top + 12))


# ------------------------------------------------------------------ the worlds (chapter select)

## True when the frontier chapter is open and its story has not been shown yet.
func _intro_due() -> bool:
	var frontier := _frontier_chapter()
	var seen_v: Variant = Game.setting(INTRO_KEY)
	var seen: int = int(seen_v) if (seen_v is int or seen_v is float) else -1
	return seen < frontier and Game.stage_status(int(Game.chapters()[frontier].first_stage)) != "locked"


## Prints chapter `ci` as a world on its dossier. arriving: the planet zooms out to its place (coming
## back from a map).
func _show_dossier(ci: int, arriving: bool = false) -> void:
	_chapter = ci
	_selected = -1
	_diving = false
	_clear()
	_pr = _poster_rect()
	_poster = Poster.poster(_root, _pr)
	_dossier = WorldDossier.new()
	_dossier.name = "WorldDossier"
	_dossier.size = _pr.size
	_dossier.look_open = OS.is_debug_build() and bool(_params.get("look_open", false))
	_poster.add_child(_dossier)
	_dossier.build(ci)
	_dossier.enter_pressed.connect(func() -> void: _enter_world(ci))
	_dossier.switch_pressed.connect(func(k: int) -> void:
		if k >= 0 and k < Game.chapters().size() and not _diving:
			Kit.sfx("tap")
			_show_dossier(k))
	var back := SignalKit.back_button(func() -> void: UI.back(), true)
	back.position = Vector2(0, 2)
	_poster.add_child(back)
	# Under the poster: the date and the world's code as a signature.
	var fy := _pr.end.y + 12.0
	Poster.at(_root, Poster.t(Poster.date_long(), 22, INK, "regular"), Vector2(20, fy + 8))
	var wd := WorldDossier.world_of(ci)
	var sig := Poster.t("World %s" % str(wd.get("code", "")), 40, INK, "serif_italic")
	sig.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sig.size = Vector2(300, 46)
	Poster.at(_root, sig, Vector2(W - 24 - 300, fy - 6))
	Poster.rect(_root, Rect2(W - 230, fy + 38, 200, 2), INK).rotation = -0.05
	Poster.grain(_root)
	SignalKit.relight(_root)
	# First-session guidance: into the frontier world.
	if _dossier.enter_button:
		Guide.mark(_dossier.enter_button, ci == _frontier_chapter() and Guide.step() == "battle", -1)
	if arriving:
		_dossier.arrive()


## Into chapter `ci`'s survey map: the dossier dives into the planet, then the map prints; a chapter
## seen for the first time shows its story.
func _enter_world(ci: int) -> void:
	if _diving:
		return
	var first := int(Game.chapters()[ci].get("first_stage", 0))
	if Game.stage_status(first) == "locked" and not (OS.is_debug_build() and _params.has("dossier")):
		UI.toast("Clear %s first" % str(Game.stage(first - 1).get("id", "the previous chapter")))
		if _dossier and _dossier.world_view:
			Kit.shake(_dossier.world_view, 6)
		return
	_diving = true
	Kit.sfx("tap")
	if _dossier and _dossier.enter_button:
		Guide.mark(_dossier.enter_button, false)
	var focus := _default_stage()
	var open := int(_params.get("open_stage", -1))
	if open >= 0 and int(Game.stage(open).get("chapter", -1)) == ci and Game.stage_status(open) != "locked":
		focus = open
	elif int(Game.stage(focus).get("chapter", 0)) != ci:
		focus = first + int(Game.chapters()[ci].get("stage_count", 10)) - 1
	var go := func() -> void:
		if not is_inside_tree():
			return
		_show_chapter(ci, focus)
		_flash()
		_maybe_intro(ci)
	if _dossier:
		_dossier.dive(go)
	else:
		go.call()


## Out of the map to the dossier (WORLDS): the planet zooms out to its place.
func _show_worlds() -> void:
	_show_dossier(_chapter, true)


## A paper flash over the poster as the map prints in after the dive.
func _flash() -> void:
	if not Kit.motion_ok():
		return
	var f := ColorRect.new()
	f.color = PAPER
	f.mouse_filter = MOUSE_FILTER_IGNORE
	f.position = _pr.position
	f.size = _pr.size
	_root.add_child(f)
	var tw := f.create_tween()
	tw.tween_property(f, "modulate:a", 0.0, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(f.queue_free)


## The story of chapter `ci` the first time its map opens.
func _maybe_intro(ci: int) -> void:
	if ci != _frontier_chapter() or not _intro_due():
		return
	Game.set_setting(INTRO_KEY, ci)
	_show_intro(ci, Callable())


func _build_poster(ch: Dictionary) -> void:
	_pr = _poster_rect()
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
	Poster.vlabel(p, "©2026 HH, SURVEY SHEET %02d. ALL RIGHTS RESERVED." % (ci + 1), Vector2(42, 108), 10, Color(PAPER, 0.8))
	Poster.at(p, Poster.t("No.\n%03d" % (ci + 1), 12, Color(PAPER, 0.85)), Vector2(70, ph * 0.3))
	Poster.at(p, Poster.t(Poster.date_short(), 12, Color(PAPER, 0.85)), Vector2(70, ph * 0.3 + 40))

	# ---- The chapter name, huge, down the poster (two-tone across the band).
	var name_txt := str(ch.get("name", ""))
	Poster.giant_side(p, name_txt, 150, 150.0, 104.0, 0.0, BAND_W, faction == "infernal")

	# ---- The survey map: the terrain model over the middle, the route profile under it.
	var rx := pw - RULE_W
	var map_bottom := _stage_y - PROFILE_H - 4.0
	_map = SurveyMap.new()
	_map.name = "SurveyMap"
	_map.position = Vector2(0, 100)
	_map.size = Vector2(rx - 4, map_bottom - 100)
	_map.overscan = Vector2(120, 40)
	_map.yaw = -24.0
	_map.pitch = -40.0
	_map.ortho_width = 16.0
	_map.target_y = 0.55
	_map.shift = Vector2(1.3, -1.35)
	# Raised stage labels stay below the title block (view px; the view starts 120 px higher).
	_map.label_floor = 129.0 + 120.0 - 100.0
	p.add_child(_map)
	var stages: Array = []
	for j in count:
		var st := Game.stage(first + j)
		stages.append({"id": str(st.get("id", "")), "name": str(st.get("name", "")), "status": Game.stage_status(first + j),
			"boss": bool(st.get("is_boss", false))})
	_map.show_chapter(ci, faction, stages)
	_map.stage_pressed.connect(func(j: int) -> void: _on_node(first + j))
	# The legend: the route profile (tap a circle to pick a stage), the survey data table, the scale.
	_profile = SurveyLegend.RouteProfile.new()
	_profile.name = "RouteProfile"
	_profile.stages = stages
	_profile.title = "THE ROUTE  ·  MOLTEN RIVER"
	_profile.length_km = _map.route_lengths().x * 0.85
	_profile.position = Vector2(BAND_W + 10, map_bottom + 2)
	_profile.size = Vector2(rx - BAND_W - 18, PROFILE_H)
	_profile.pressed.connect(func(j: int) -> void: _on_node(first + j))
	p.add_child(_profile)
	# Survey data in two units, from the model (1 world unit = 0.85 km, relief drawn 2x).
	var tg := _map.terrain
	var km := 0.85
	var area := TerrainGen.W * TerrainGen.D * km * km
	var relief := int(round((tg.h_max - tg.h_min) * km * 1000.0 * 0.5))
	var river := _map.route_lengths().x * km
	var temp := "--"
	var temp_f := ""
	for ro: Variant in WorldDossier.world_of(ci).get("readouts", []):
		if ro is Array and str(ro[0]).to_lower().begins_with("surface"):
			temp = str(ro[1])
			temp_f = "%d °F" % int(round(temp.to_int() * 9.0 / 5.0 + 32.0))
	var tbl := SurveyLegend.DataTable.new()
	tbl.name = "SurveyData"
	tbl.rows = [["Area", "%.1f km²" % area, "%.1f sq mi" % (area * 0.3861)], ["Relief", "%s m" % Kit.format_full(relief), "%s ft" % Kit.format_full(int(relief * 3.281))],
		["River", "%.1f km" % river, "%.1f mi" % (river * 0.6214)], ["Surface", temp, temp_f]]
	tbl.position = Vector2(BAND_W + 16, 112)
	tbl.size = Vector2(202, 84)
	p.add_child(tbl)
	var sb := SurveyLegend.ScaleBar.new()
	sb.position = Vector2(rx - 166, map_bottom - 68)
	sb.size = Vector2(150, 66)
	p.add_child(sb)
	# Stage tags and labels keep clear of both (view px: the view starts 120 px above the map).
	var vo := Vector2(0, 120.0 - 100.0)
	_map.avoid = [Rect2(tbl.position + vo - Vector2(12, 10), tbl.size + Vector2(18, 10)), Rect2(sb.position + vo - Vector2(6, 4), sb.size + Vector2(8, 6)),
		Rect2(-40, 0, BAND_W + 46, 2000)]

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

	# ---- The index down the right edge: STORY, WORLDS (the chapter select: out to the dossier), and
	# the chapter's place among the worlds.
	Poster.vline(p, rx, 0, ph, Color(INK, 0.55))
	Poster.vlabel(p, "©2026 ·", Vector2(rx + 34, 12), 12, INK)
	var items: Array = [{"text": "STORY", "name": "Story", "on_pressed": func() -> void: _show_intro(ci, Callable())},
		{"text": "WORLDS", "name": "Worlds", "active": true, "on_pressed": _show_worlds}]
	Poster.side_menu(p, rx, 96.0, 112.0, items)
	var iy := 96.0 + 112.0 * 2.0 + 10.0
	Poster.vlabel(p, "CH %02d / %02d" % [ci + 1, Game.chapters().size()], Vector2(rx + 32, iy), 14, INK)
	for k in Game.chapters().size():
		var on := k == ci
		var open_k := Game.stage_status(int(Game.chapters()[k].get("first_stage", 0))) != "locked"
		Poster.rect(p, Rect2(rx + 12, iy + 110 + k * 16, 10 if on else 6, 2 if not on else 3), SIG if on else Color(INK, 0.75 if open_k else 0.3))

	# BACK at the top of the dark band (it overhangs onto the paper), over the map's picture.
	var back := SignalKit.back_button(func() -> void: UI.back(), false)
	back.position = Vector2(0, 2)
	p.add_child(back)

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
	if _profile and is_instance_valid(_profile):
		_profile.set("selected", i - first)
		_profile.queue_redraw()
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
