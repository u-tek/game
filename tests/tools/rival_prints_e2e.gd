extends SceneTree
## End-to-end check of the Rival and the misprints through the real main scene (headless):
##   tools/gd --headless --path . -s tests/tools/rival_prints_e2e.gd -- --fresh
## Summon x10 with a forced misprint and holo (tapped through: the misprint beat plays, the results
## carry prints) -> the print album (filters, the print sheet, Show on profile) -> the profile's
## showcase -> the Rival while locked, then unlocked (the intro on the first visit) -> Fight (battle
## mode "rival", Skip, her result poster, Done back to her poster) -> a loss tags the Lobby (the RIVAL
## label lit), a win cleans it. Exit code 1 on any failed check.

var _fails: Array[String] = []
var _checks := 0
var _game: Node
var _ui: Node


func _initialize() -> void:
	create_timer(240.0).timeout.connect(func() -> void:
		printerr("E2E: timed out")
		quit(2))
	_run.call_deferred()


func _run() -> void:
	var main: Node = load("res://src/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	_game = root.get_node("Game")
	_ui = root.get_node("UI")
	await _summon()
	await _album()
	await _profile()
	await _rival()
	await _lobby_tag()
	for f in _fails:
		printerr("E2E FAIL ", f)
	print("E2E rival and prints: %d checks, %d failures" % [_checks, _fails.size()])
	quit(1 if _fails.size() > 0 else 0)


# ------------------------------------------------------------------ helpers

func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_fails.append(what)
		printerr("  FAIL: ", what)


func _frames(n: int = 3) -> void:
	for i in n:
		await process_frame


func _go(screen: String, params: Dictionary = {}) -> Control:
	_close_modals()
	_ui.go(screen, params)
	await _frames(5)
	_check(_ui.current_name == screen, "navigate to %s (at %s)" % [screen, _ui.current_name])
	return _ui.current


func _close_modals() -> void:
	var guard := 0
	while _ui.has_modal() and guard < 20:
		_ui.handle_back()
		guard += 1


func _find_button(from: Node, text: String) -> Button:
	if from is Button:
		var b := from as Button
		if b.text.contains(text) and not b.disabled:
			return b
		for c in b.find_children("*", "Label", true, false):
			if (c as Label).text.contains(text) and not b.disabled:
				return b
	for c in from.get_children():
		var r := _find_button(c, text)
		if r:
			return r
	return null


func _top_modal() -> Node:
	var layer: Control = _ui.root.get("modal_layer")
	if layer == null or layer.get_child_count() == 0:
		return null
	return layer.get_child(layer.get_child_count() - 1)


func _overlay_tap(s: Control) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = false
	s.call("_on_overlay_input", ev)


# ------------------------------------------------------------------ summon

func _summon() -> void:
	_game.dev_add("gems", 60000)
	var s := await _go("summon")
	_game.dev_print_looks([{"flaw": "shift"}, {"holo": true}])
	s.call("_do_summon", 10, false)
	await _frames(2)
	var res: Array = s.get("_results")
	_check(res.size() == 10, "x10 gives 10 results")
	var with_prints := 0
	for r: Dictionary in res:
		if r.get("print") is Dictionary and int((r.print as Dictionary).get("serial", 0)) > 0:
			with_prints += 1
	_check(with_prints == 10, "every result carries a numbered print (%d)" % with_prints)
	if res.size() >= 2:
		_check(str(res[0].print.flaw) == "shift", "the forced misprint")
		_check(bool(res[1].print.holo), "the forced holo")
	# Tap through: the misprint's beat (its stamp and the flip) plays before the next hero.
	var saw_flaw := false
	var t0 := Time.get_ticks_msec()
	var last_tap := t0
	while Time.get_ticks_msec() - t0 < 30000 and str(s.get("_phase")) != "results":
		await process_frame
		var seq: Node = s.get("_seq")
		var rv: Variant = seq.get("_reveal") if seq else null
		if rv is Control and is_instance_valid(rv) and (rv as Control).find_child("FlawStamp", true, false) != null:
			saw_flaw = true
		if Time.get_ticks_msec() - last_tap > 150:
			last_tap = Time.get_ticks_msec()
			_overlay_tap(s)
	_check(str(s.get("_phase")) == "results", "the run reaches the contact sheet")
	_check(saw_flaw, "a misprint reveal has its rubber stamp")
	_check((s.get("_cards") as Array).size() == 10, "the contact sheet shows 10 prints")
	s.call("_finish")
	await _frames(2)


# ------------------------------------------------------------------ album

func _album() -> void:
	var p := await _go("prints")
	var n: int = _game.prints().size()
	_check(n >= 10, "the album holds the summon's prints (%d)" % n)
	_check((p.get("_slots") as Array).size() == n, "one slot per print")
	_check((p.get("_cards") as Array).size() >= mini(n, 6), "the slabs in view are built")
	p.call("_set_filter", "misprint")
	await _frames(4)
	p = _ui.current
	var list: Array = p.get("_list")
	_check(list.size() >= 1, "the Misprints tab lists the misprint")
	for x: Dictionary in list:
		_check(str(x.get("flaw", "")) != "", "Misprints shows only flawed prints")
	p.call("_open_sheet", 0)
	await _frames(3)
	var m := _top_modal()
	_check(m != null and m.find_child("PrintSheet", true, false) != null, "a tap opens the print sheet")
	var show := _find_button(m, "Show on profile") if m else null
	_check(show != null, "the sheet has Show on profile")
	if show:
		show.pressed.emit()
		await _frames(3)
	_check(_game.showcase().size() == 1, "the print is on the profile")
	_close_modals()


func _profile() -> void:
	var pf := await _go("profile")
	_check(pf.find_child("Showcase_0", true, false) != null, "the profile shows the showcased print")


# ------------------------------------------------------------------ the Rival

func _rival() -> void:
	var r := await _go("rival")
	_check(not bool(_game.rival_unlocked()), "Rue is locked at the start")
	_check(_find_button(r, "Fight") == null, "no Fight while she is sealed")
	_game.model.state.campaign.cleared = RivalRules.UNLOCK_CLEARED
	r = await _go("home")
	r = await _go("rival")
	await _frames(4)
	_check(bool(_game.state.rival.met), "the first visit introduces her")
	_check(_top_modal() != null and _top_modal().find_child("RueIntro", true, false) != null, "her intro sheet shows")
	_close_modals()
	await _frames(2)
	r = _ui.current
	var fight := _find_button(r, "Fight")
	_check(fight != null, "her poster has the Fight pass")
	var fights0 := int(_game.state.rival.fights)
	if fight:
		fight.pressed.emit()
	await _frames(4)
	_check(_ui.current_name == "battle", "Fight opens the battle (%s)" % _ui.current_name)
	if _ui.current_name != "battle":
		return
	var b: Node = _ui.current
	_check(str(b.get("_mode")) == "rival", "the battle is in rival mode")
	await create_timer(1.0).timeout
	b.call("_skip")
	var t0 := Time.get_ticks_msec()
	while is_instance_valid(b) and str(b.get("_phase")) != "result" and Time.get_ticks_msec() - t0 < 30000:
		await create_timer(0.1).timeout
	await create_timer(0.4).timeout
	_check(is_instance_valid(b) and str(b.get("_phase")) == "result", "the fight reaches its result")
	_check(int(_game.state.rival.fights) == fights0 + 1, "the fight is reported once")
	var poster := false
	for c in b.get("_overlay").get_children():
		if c.has_method("show_rival"):
			poster = true
	_check(poster, "her result poster shows")
	var done := _find_button(b, "Done")
	_check(done != null, "the result has Done")
	if done:
		done.pressed.emit()
	await _frames(6)
	_check(_ui.current_name == "rival", "Done goes back to her poster (%s)" % _ui.current_name)


func _lobby_tag() -> void:
	_game.complete_rival({"victory": false})
	var h := await _go("home")
	await _frames(2)
	_check(h.find_child("SideRival", true, false) != null, "the Lobby has the RIVAL label")
	_check(h.find_child("RueTag", true, false) != null, "a loss: Rue tags the Lobby")
	var gems0 := int(_game.currency("gems"))
	_game.complete_rival({"victory": true})
	await _frames(3)
	_check(h.find_child("RueTag", true, false) == null or h.find_child("RueTag", true, false).is_queued_for_deletion(), "a win cleans her tag off")
	_check(int(_game.currency("gems")) >= gems0, "winning never costs")
