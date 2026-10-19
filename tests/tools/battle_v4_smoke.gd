extends SceneTree
## Headless smoke check of the style v4 battle screen (not part of tools/check):
##   tools/gd --headless --path . -s tests/tools/battle_v4_smoke.gd -- --rich
## Opens a boss stage with manual ultimates and checks the printed HUD (the strip's controls, the
## boss band, the print cards reaching READY), then lands a forced victory and a forced defeat (the
## debug "result" param) and a Spire floor on their posters (the pass, Lobby, the tips). Exit code 1
## on failure.

var _fails: Array[String] = []
var _game: Node
var _ui: Node


func _initialize() -> void:
	create_timer(180.0).timeout.connect(func() -> void:
		printerr("SMOKE: timed out")
		quit(2))
	_run.call_deferred()


func _run() -> void:
	var main: Node = load("res://src/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	_game = root.get_node("Game")
	_ui = root.get_node("UI")
	_game.set_setting("battle_speed", 4)

	# A boss fight, manual ultimates: the HUD pieces exist and the cards fill up.
	_ui.go("battle", {"stage_index": 4, "manual": true})
	await create_timer(1.0).timeout
	var scr: Node = _ui.current
	for n in ["Hud_Exit", "Hud_Auto", "Hud_Speed", "Hud_Skip", "BossBand", "TopStrip", "BottomStrip"]:
		_check(scr.find_child(n, true, false) != null, "boss fight: no %s" % n)
	_check(_find_button(scr, "Skip") != null, "boss fight: Skip not found by its text")
	_check((scr.get("_portraits") as Dictionary).size() > 0, "boss fight: no ally cards")
	var ready := false
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 20000 and is_instance_valid(scr) and str(scr.get("_phase")) != "result":
		await create_timer(0.25).timeout
		for uid: String in scr.get("_portraits"):
			var p: Node = scr.get("_portraits")[uid]
			if int(p.get("energy")) >= 1000 and not p.get("dead"):
				ready = true
		if ready:
			break
	_check(ready, "manual: no card reached READY in 20 s")
	if is_instance_valid(scr):
		scr.call("_toggle_speed")
		scr.call("_toggle_auto")
		scr.call("_toggle_auto")
		scr.call("_skip")
	await _wait_result(scr, "boss skip")

	# Forced victory: the poster with the pass and Lobby.
	_ui.go("battle", {"stage_index": 2, "result": "victory"})
	await process_frame
	scr = _ui.current
	await _wait_result(scr, "victory")
	var res := _result(scr)
	_check(res != null, "victory: no poster")
	if res:
		_check(_find_button(res, "Next") != null or _find_button(res, "Campaign") != null, "victory: no Next / Campaign pass")
		_check(_find_button(res, "Lobby") != null, "victory: no Lobby")
		_check(res.find_child("HeroBox", true, false) != null, "victory: no hero box")

	# Forced defeat: Retry and the numbered tips.
	_ui.go("battle", {"stage_index": 3, "result": "defeat"})
	await process_frame
	scr = _ui.current
	await _wait_result(scr, "defeat")
	res = _result(scr)
	_check(res != null, "defeat: no poster")
	if res:
		_check(_find_button(res, "Retry") != null, "defeat: no Retry")
		_check(_find_button(res, "Lobby") != null, "defeat: no Lobby")
		_check(res.find_child("Tip1", true, false) != null, "defeat: no tips")
		res.call("_emit", "retry")
		await process_frame
		_check(_ui.current_name == "battle", "defeat: Retry did not restart")

	# A Spire floor, forced victory.
	if bool(_game.tower_unlocked()):
		_ui.go("battle", {"mode": "tower", "floor": int(_game.tower_next()), "result": "victory"})
		await process_frame
		scr = _ui.current
		if _ui.current_name == "battle":
			await _wait_result(scr, "spire victory")
			_check(_result(scr) != null, "spire: no poster")
	_ui.go("home")
	await create_timer(0.3).timeout
	_game.set_setting("battle_speed", 1)
	for f in _fails:
		printerr("SMOKE FAIL ", f)
	print("SMOKE: %d failures" % _fails.size())
	_ui.release_audio()
	await create_timer(0.1).timeout
	quit(1 if _fails.size() > 0 else 0)


func _result(scr: Node) -> Control:
	if not is_instance_valid(scr):
		return null
	for c in scr.get("_overlay").get_children():
		if c.has_method("show_victory"):
			return c as Control
	return null


func _wait_result(scr: Node, label: String) -> void:
	var t0 := Time.get_ticks_msec()
	while is_instance_valid(scr) and str(scr.get("_phase")) != "result":
		await create_timer(0.1).timeout
		if Time.get_ticks_msec() - t0 > 60000:
			_check(false, "%s: no result after 60 s" % label)
			return
	await create_timer(1.2).timeout
	if is_instance_valid(scr):
		var out: Dictionary = scr.get("_sim").outcome()
		print("SMOKE %s: real victory=%s" % [label, out.victory])


func _find_button(from: Node, text: String) -> Button:
	if from is Button:
		var b := from as Button
		if not b.disabled and b.is_visible_in_tree():
			if b.text.contains(text):
				return b
			for c in b.find_children("*", "Label", true, false):
				if (c as Label).text.contains(text):
					return b
	for c in from.get_children():
		var r := _find_button(c, text)
		if r:
			return r
	return null


func _check(ok: bool, msg: String) -> void:
	if not ok:
		_fails.append(msg)
