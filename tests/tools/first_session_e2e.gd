extends SceneTree
## First-session walk: boots the real main scene on a fresh save and plays it by tapping
## whatever the first-session guide highlights (Guide marks), the way a new player follows
## the arrows. Taps are real pointer events at the marked control. When nothing is marked it
## does what a player would: OK on reward popups, taps through the summon reveal and presses
## Done, presses Skip in battles.
##
##   tools/gd --headless --path . -s tests/tools/first_session_e2e.gd -- --fresh
## Rendered, with one PNG per step (look at them with the Read tool):
##   flock /tmp/halo-godot.lock xvfb-run -a -s "-screen 0 1800x2400x24" godot --path . \
##     --rendering-driver opengl3 --resolution 720x1560 -s tests/tools/first_session_e2e.gd \
##     -- --fresh --safe-area-sim --shots=/abs/path/to/dir
##
## Checks that following the guide goes claim -> summon -> (formation) -> battle 1-1 ->
## level up -> quests -> more battles, clears the first three stages, and that every
## marked control can be tapped. Exit code 1 on failure.

## Steps before giving up. The summon reveal takes a tap or two per hero (about 25 for the
## free pull and the first 10-pull).
const MAX_TAPS := 160

var _game: Node
var _ui: Node
var _shots := ""
var _n := 0
var _fails: Array[String] = []
var _steps_seen: Array[String] = []
var _log: Array[String] = []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			_shots = a.substr(8)
	create_timer(600.0).timeout.connect(func() -> void:
		printerr("E2E: timed out")
		quit(2))
	_run.call_deferred()


func _run() -> void:
	var main: Node = load("res://src/main.tscn").instantiate()
	root.add_child(main)
	await _frames(6)
	_game = root.get_node("Game")
	_ui = root.get_node("UI")
	if _shots != "":
		DirAccess.make_dir_recursive_absolute(_shots)
	var idle_rounds := 0
	for i in MAX_TAPS:
		var step: String = Guide.step()
		if _steps_seen.is_empty() or _steps_seen.back() != step:
			_steps_seen.append(step)
		var acted := await _act(step)
		if acted:
			idle_rounds = 0
		else:
			idle_rounds += 1
			if idle_rounds >= 3:
				break
		if step == "" and not _ui.has_modal() and _ui.current_name != "battle":
			break
	await _shot("end")
	_verify()
	for l in _log:
		print(l)
	print("guide steps: ", " -> ".join(_steps_seen))
	for f in _fails:
		printerr("E2E FAIL ", f)
	print("E2E first session: cleared %d, level_ups %d, %d failures" % [
		_game.cleared_count(), _game.counter("level_ups"), _fails.size()])
	_ui.release_audio()
	await _wait(0.1)
	quit(1 if _fails.size() > 0 else 0)


func _verify() -> void:
	var order := ["claim", "summon", "battle", "level", "quests"]
	var at := -1
	for want in order:
		var idx := _steps_seen.find(want)
		if idx < 0:
			_fails.append("the guide never suggested '%s' (saw %s)" % [want, str(_steps_seen)])
		elif idx < at:
			_fails.append("'%s' came out of order (saw %s)" % [want, str(_steps_seen)])
		else:
			at = idx
	if int(_game.cleared_count()) < 3:
		_fails.append("following the guide cleared only %d stages" % int(_game.cleared_count()))
	if int(_game.counter("summons")) < 11:
		_fails.append("expected the free pull and a 10-pull, got %d summons" % int(_game.counter("summons")))
	if _game.quests_ready_count() > 0 and Guide.step() != "":
		_fails.append("quests left unclaimed while the guide is still active")


## One action: tap the highlighted control, or a sensible fallback. Returns false if idle.
func _act(step: String) -> bool:
	# The battle screen plays on its own: skip to the result.
	if _ui.current_name == "battle" and not _ui.has_modal():
		var scr: Control = _ui.current
		if str(scr.get("_phase")) != "result":
			var skip := _find_button(scr, "Skip")
			if skip and skip.is_visible_in_tree():
				await _shot("battle")
				await _tap(skip, "Skip")
				await _wait(1.5)
				return true
			await _wait(0.5)
			return true
	# Summon reveal: tap through, then Done.
	if _ui.current_name == "summon" and str(_ui.current.get("_phase")) not in ["", "results"]:
		await _wait(0.4)
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = false
		_ui.current.call("_on_overlay_input", ev)
		return true
	var mark := _best_mark()
	var layer: Control = _ui.root.get("modal_layer")
	if mark and _ui.has_modal() and not layer.is_ancestor_of(mark):
		mark = null # a popup is on top: deal with it first
	if mark:
		var target := mark.get_parent() as Control
		await _shot(step)
		await _tap(target, "%s on %s" % [_label_of(target), _ui.current_name])
		await _wait(0.6)
		return true
	if _ui.current_name == "summon" and str(_ui.current.get("_phase")) == "results":
		await _shot("summon results")
		var done := _find_button(_ui.current, "Done")
		if done:
			await _tap(done, "Done on summon results")
			await _wait(0.6)
			return true
	if _ui.has_modal():
		var top := layer.get_child(layer.get_child_count() - 1)
		for text in ["OK", "Onward", "Continue", "Done"]:
			var b := _find_button(top, text)
			if b:
				await _shot("popup")
				await _tap(b, "%s in a popup" % text)
				await _wait(0.6)
				return true
		_ui.handle_back()
		await _wait(0.3)
		return true
	await _wait(0.5)
	return false


## The visible guide mark to follow: popups first, then the screen, then the nav.
func _best_mark() -> Control:
	var marks: Array[Control] = []
	for n in root.find_children("GuideMark", "Control", true, false):
		var c := n as Control
		if c.is_queued_for_deletion() or not c.is_visible_in_tree():
			continue
		var host := c.get_parent() as Control
		if host == null or (host is BaseButton and (host as BaseButton).disabled):
			continue
		marks.append(c)
	if marks.is_empty():
		return null
	var layer: Control = _ui.root.get("modal_layer")
	for m in marks:
		if layer.is_ancestor_of(m):
			return m
	for m in marks:
		if _ui.current and (_ui.current as Node).is_ancestor_of(m):
			return m
	return marks[0]


## A real tap (press and release) at the middle of `c`.
func _tap(c: Control, what: String) -> void:
	_n += 1
	_log.append("%3d  %-10s %s" % [_n, Guide.step(), what])
	var pos := c.get_global_rect().get_center()
	for down in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = down
		ev.position = pos
		ev.global_position = pos
		root.push_input(ev, true)
		await _frames(2)


func _label_of(c: Control) -> String:
	if c is Button and (c as Button).text != "":
		return "'%s'" % (c as Button).text
	for l in c.find_children("*", "Label", true, false):
		var t := (l as Label).text.strip_edges()
		if t != "":
			return "'%s'" % t
	return c.name


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


func _shot(tag: String) -> void:
	if _shots == "":
		return
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png("%s/%02d_%s.png" % [_shots, _n, tag.replace(" ", "_")])


func _wait(sec: float) -> void:
	await create_timer(sec).timeout


func _frames(n: int) -> void:
	for i in n:
		await process_frame
