extends SceneTree
## Headless smoke run of the poster-look Campaign, Spire and Quests screens (style v4): opens each
## through the real main scene, prints every chapter's survey map, switches tabs, selects stages,
## taps a stage mark and the route profile, prints every chapter's world dossier, zooms out to the
## worlds and dives back into a map, checks a new chapter opens on its world and shows its story,
## checks the Fight / Claim / Enter controls carry their words, and claims quests.
##   tools/gd --headless --path . -s tests/tools/v4_survey_smoke.gd -- --rich
## Exit code 1 on failure (scan the output for SCRIPT ERROR as well).

var _fails: Array[String] = []
var _game: Node
var _ui: Node


func _initialize() -> void:
	create_timer(120.0).timeout.connect(func() -> void:
		printerr("SMOKE: timed out")
		quit(2))
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails.append(what)


func _find_button(from: Node, text: String) -> Button:
	if from is Button and (from as Button).text.contains(text):
		return from as Button
	for c in from.get_children():
		var r := _find_button(c, text)
		if r:
			return r
	return null


## Prints pairs of visible labels on the current screen whose boxes overlap (engraved labels on
## plates are skipped: they are stacked on purpose), and labels that leave the screen.
func _lint(tag: String) -> void:
	var scr: Control = _ui.current
	var boxes: Array = []
	for n in scr.find_children("*", "Label", true, false):
		var l := n as Label
		if not l.is_visible_in_tree() or l.text.strip_edges() == "" or l.modulate.a < 0.05:
			continue
		var on_plate := false
		var a: Node = l.get_parent()
		while a and a != scr:
			if a.get("preset") != null or a.get("label") != null and a.get("value") != null:
				on_plate = true
				break
			a = a.get_parent()
		if on_plate:
			continue
		var xf := l.get_global_transform()
		var sz := l.size
		var pts := [xf * Vector2.ZERO, xf * Vector2(sz.x, 0), xf * sz, xf * Vector2(0, sz.y)]
		var r := Rect2(pts[0], Vector2.ZERO)
		for q: Vector2 in pts:
			r = r.expand(q)
		# The ink box of the text, not the whole control (labels are often wider than their words).
		var ms := l.get_minimum_size()
		if l.rotation == 0.0 and absf(xf.get_rotation()) < 0.01 and l.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT:
			r = Rect2(r.end.x - ms.x, r.position.y, ms.x, r.size.y)
		elif l.rotation == 0.0 and absf(xf.get_rotation()) < 0.01:
			r = Rect2(r.position, Vector2(minf(ms.x, r.size.x), r.size.y))
		var g := r.grow(-2.0)
		if g.size.x <= 0.0 or g.size.y <= 0.0:
			continue
		boxes.append([l.text.replace("
", " ").substr(0, 24), g])
	var vis := root.get_visible_rect()
	for i in boxes.size():
		var ri: Rect2 = boxes[i][1]
		if not vis.encloses(ri.grow(-1.0)):
			print("LINT %s off-screen: '%s' %s" % [tag, boxes[i][0], str(ri)])
		for j in range(i + 1, boxes.size()):
			var rj: Rect2 = boxes[j][1]
			if ri.intersects(rj) and boxes[i][0] != boxes[j][0]:
				var inter := ri.intersection(rj)
				if inter.get_area() > 12.0:
					print("LINT %s overlap: '%s' x '%s' (%d px2)" % [tag, boxes[i][0], boxes[j][0], int(inter.get_area())])


func _run() -> void:
	var main: Node = load("res://src/main.tscn").instantiate()
	root.add_child(main)
	await _frames(4)
	_game = root.get_node("Game")
	_ui = root.get_node("UI")
	# A newly opened chapter (its story not seen yet) opens on its world; entering it shows the
	# story. (Runs first: the "seen" mark only ever goes up.)
	var seen_v: Variant = _game.setting("chapter_intro_seen")
	var seen: int = int(seen_v) if (seen_v is int or seen_v is float) else -1
	_ui.go("campaign")
	await _frames(4)
	var s: Control = _ui.current
	if seen < int(s.call("_frontier_chapter")):
		_check(s.find_child("WorldDossier", true, false) != null, "a new chapter opens on its world")
		s.call("_enter_world", int(s.get("_chapter")))
		await create_timer(1.2).timeout
		_check(s.find_child("SurveyMap", true, false) != null, "entering the world prints its map")
		_check(_ui.has_modal(), "entering a new world shows its story")
		while _ui.has_modal():
			_ui.handle_back()
			await _frames(1)
	else:
		print("SMOKE note: the story of the frontier chapter was already seen; first-visit check skipped")
	# Campaign: the frontier chapter, then every chapter as a preview.
	_ui.go("campaign", {"intro": false})
	await _frames(6)
	s = _ui.current
	_check(_ui.current_name == "campaign", "campaign opens")
	_check(_find_button(s, "Fight") != null, "campaign has a Fight button")
	_check(_find_button(s, "Team") != null, "campaign has a Team stamp")
	_check(s.find_child("SurveyMap", true, false) != null, "campaign prints the survey map")
	_lint("campaign")
	for ci in _game.chapters().size():
		_ui.go("campaign", {"intro": false, "preview_chapter": ci})
		await _frames(3)
		_check(_ui.current_name == "campaign", "campaign preview %d" % ci)
		_lint("campaign ch%d" % (ci + 1))
	_ui.go("campaign", {"intro": false})
	await _frames(3)
	s = _ui.current
	s.call("_on_tab", 0)
	await _frames(2)
	s.call("_on_tab", 5)
	await _frames(2)
	s.call("_select", 0)
	await _frames(2)
	# A tap on a stage mark selects it.
	var m: Control = s.find_child("SurveyMap", true, false)
	if m:
		await _frames(30)
		var pt: Vector2 = m.call("stage_point", 1)
		var before: int = int(s.get("_selected"))
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		for down in [true, false]:
			ev = ev.duplicate()
			ev.pressed = down
			ev.position = m.get_global_transform() * pt
			ev.global_position = ev.position
			root.push_input(ev, true)
			await _frames(2)
		print("tap stage: selected %d -> %d" % [before, int(s.get("_selected"))])
	# A tap on the route profile's circles selects that stage too.
	var prof: Control = s.find_child("RouteProfile", true, false)
	_check(prof != null, "campaign prints the route profile")
	_check(s.find_child("SurveyData", true, false) != null, "campaign prints the survey data")
	if prof:
		var pst: Array = prof.get("stages")
		var cw := prof.size.x / maxf(float(pst.size()), 1.0)
		var ev2 := InputEventMouseButton.new()
		ev2.button_index = MOUSE_BUTTON_LEFT
		ev2.pressed = false
		ev2.position = Vector2(cw * 0.5 + 8.0, 50.0)
		prof.call("_gui_input", ev2)
		await _frames(2)
		_check(int(s.get("_selected")) == int(_game.chapters()[int(s.get("_chapter"))].get("first_stage", 0)), "profile tap selects the first stage")
	s.call("_show_intro", 0, Callable())
	await _frames(3)
	while _ui.has_modal():
		_ui.handle_back()
		await _frames(1)
	# The worlds: every chapter's dossier (planet, data list, ENTER or the locked key).
	for ci in _game.chapters().size():
		_ui.go("campaign", {"dossier": ci})
		await _frames(4)
		var d: Control = (_ui.current as Node).find_child("WorldDossier", true, false)
		_check(d != null, "dossier %d prints" % (ci + 1))
		_check((_ui.current as Node).find_child("World", true, false) != null, "dossier %d has its planet" % (ci + 1))
		var open: bool = _game.stage_status(int(_game.chapters()[ci].get("first_stage", 0))) != "locked"
		var eb := _find_button(_ui.current, "Enter")
		_check(not open or eb != null, "dossier %d has the ENTER pass" % (ci + 1))
		_lint("dossier ch%d" % (ci + 1))
	# WORLDS on the map zooms out to the dossier; ‹ › switch; ENTER dives back into a map.
	_ui.go("campaign", {"intro": false})
	await _frames(3)
	s = _ui.current
	s.call("_show_worlds")
	await create_timer(0.8).timeout
	_check(s.find_child("WorldDossier", true, false) != null, "WORLDS opens the dossier")
	var front: int = int(s.get("_chapter"))
	s.call("_show_dossier", maxi(front - 1, 0))
	await _frames(3)
	s.call("_show_dossier", front)
	await _frames(3)
	s.call("_enter_world", front)
	await create_timer(1.2).timeout
	_check(s.find_child("SurveyMap", true, false) != null, "ENTER dives into the survey map")
	while _ui.has_modal():
		_ui.handle_back()
		await _frames(1)
	# The Spire.
	_ui.go("tower")
	await _frames(6)
	_check(_ui.current_name == "tower", "tower opens")
	_lint("tower")
	var fb: Node = (_ui.current as Node).find_child("FightFloor", true, false)
	_check(fb == null or (fb is Button and (fb as Button).text == "Fight"), "tower Fight carries its word")
	# Quests: claim one, then all.
	_ui.go("quests")
	await _frames(6)
	_check(_ui.current_name == "quests", "quests opens")
	_lint("quests")
	var q: Control = _ui.current
	q.call("_claim_all")
	await _frames(3)
	while _ui.has_modal():
		_ui.handle_back()
		await _frames(1)
	q.call("_refresh")
	await _frames(3)
	_lint("quests after claims")
	for f in _fails:
		printerr("SMOKE FAIL ", f)
	print("SMOKE v4 survey: %d failures" % _fails.size())
	_ui.release_audio()
	await create_timer(0.1).timeout
	quit(1 if _fails.size() > 0 else 0)
