extends SceneTree
## End-to-end check of the core-loop screens through the real main scene (headless):
##   tools/gd --headless --path . -s tests/tools/battle_screen_e2e.gd -- --fresh
## Runs: campaign Fight -> battle at 1x to the result panel -> Next Stage -> Skip -> Retry ->
## leave mid-fight; then manual ultimates on a replay at 4x. Checks that every battle reports
## to Game.complete_stage exactly once and ends on a result panel. Exit code 1 on failure.

var _fails: Array[String] = []
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
	_game.set_setting("battle_speed", 1)
	_game.set_setting("auto_ultimates", true)

	# Campaign -> Fight on the current stage, watched to the end at 1x.
	_ui.go("campaign", {"intro": false})
	await create_timer(0.5).timeout
	var idx: int = _game.cleared_count()
	var before := _results()
	_ui.current.call("_fight", idx)
	await process_frame
	_check(_ui.current_name == "battle", "Fight did not open the battle")
	await _wait_result(_ui.current, "1x stage %d" % idx)
	_check(_results() - before == 1, "1x battle reported %d results" % (_results() - before))

	# Next Stage, then Skip.
	var won: bool = bool(_ui.current.get("_sim").outcome().victory)
	if won and idx + 1 < _game.stages().size():
		_ui.current.call("_on_result_action", "next")
		await process_frame
		_check(_ui.current_name == "battle" or _ui.current_name == "campaign", "Next did not navigate")
	if _ui.current_name == "battle":
		before = _results()
		await create_timer(1.5).timeout
		_ui.current.call("_skip")
		await _wait_result(_ui.current, "skip")
		_check(_results() - before == 1, "skipped battle reported %d results" % (_results() - before))
		# Retry, then leave mid-fight: one defeat.
		_ui.current.call("_on_result_action", "retry")
		await process_frame
		before = _results()
		await create_timer(2.0).timeout
		_ui.go("home")
		await create_timer(0.3).timeout
		_check(_results() - before == 1, "leaving mid-fight reported %d results" % (_results() - before))

	# Manual ultimates at 4x on the first stage: tap every ready portrait.
	_game.set_setting("battle_speed", 4)
	_game.set_setting("auto_ultimates", false)
	before = _results()
	_ui.go("battle", {"stage_index": 0})
	await _wait_result(_ui.current, "manual 4x", true)
	_check(_results() - before == 1, "manual battle reported %d results" % (_results() - before))
	_game.set_setting("auto_ultimates", true)
	_game.set_setting("battle_speed", 1)

	for f in _fails:
		printerr("E2E FAIL ", f)
	print("E2E: %d failures" % _fails.size())
	quit(1 if _fails.size() > 0 else 0)


func _results() -> int:
	return int(_game.counter("battles_won")) + int(_game.counter("battles_lost"))


func _wait_result(scr: Node, label: String, tap_ultimates: bool = false) -> void:
	var t0 := Time.get_ticks_msec()
	while is_instance_valid(scr) and str(scr.get("_phase")) != "result":
		await create_timer(0.1).timeout
		if tap_ultimates and is_instance_valid(scr):
			var views: Dictionary = scr.get("_views")
			for uid: String in scr.get("_portraits"):
				var v: Node = views[uid]
				if int(v.get("energy")) >= 1000 and not v.get("dead"):
					scr.call("_on_portrait", uid)
		if Time.get_ticks_msec() - t0 > 120000:
			_check(false, "%s: no result after 120 s" % label)
			return
	if not is_instance_valid(scr):
		_check(false, "%s: screen freed before the result" % label)
		return
	await create_timer(0.3).timeout
	var panel := false
	for c in scr.get("_overlay").get_children():
		if c.has_method("show_victory"):
			panel = true
	var out: Dictionary = scr.get("_sim").outcome()
	print("E2E %s: victory=%s battle=%d ms real=%d ms" % [label, out.victory, out.duration_ms, Time.get_ticks_msec() - t0])
	_check(panel, "%s: no result panel" % label)


func _check(ok: bool, msg: String) -> void:
	if not ok:
		_fails.append(msg)
