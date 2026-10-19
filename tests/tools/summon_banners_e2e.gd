extends SceneTree
## End-to-end check of the five summon banners through the real main scene (headless):
##   tools/gd --headless --path . -s tests/tools/summon_banners_e2e.gd -- --rich
## For every banner: the poster builds without errors, the index shows it, both pull tickets are
## on screen, above the nav and at least 88 px tall, the nav stays up; real taps on the index switch
## banners; a pull on each banner plays the sequence with the chrome hidden, the results bring the
## top bar and the nav back with an Again ticket; the wish picker sets the wish; the envoy's daily
## limit stamps its tickets SOLD OUT. Exit code 1 on any failed check.

const IDS := ["standard", "featured", "faction", "wish", "envoy"]

var _fails: Array[String] = []
var _checks := 0
var _game: Node
var _ui: Node


func _initialize() -> void:
	create_timer(300.0).timeout.connect(func() -> void:
		printerr("E2E: timed out")
		quit(2))
	_run.call_deferred()


func _run() -> void:
	# A phone-shaped window (headless runs default to a square one).
	if OS.get_cmdline_user_args().has("--phone"):
		root.size = Vector2i(720, 1560)
		await _frames(2)
	var main: Node = load("res://src/main.tscn").instantiate()
	root.add_child(main)
	await _frames(4)
	_game = root.get_node("Game")
	_ui = root.get_node("UI")
	if _game.owned_heroes().size() < 10:
		_game.make_rich_state()
	await _layouts()
	await _index_taps()
	await _pulls()
	await _wish()
	await _envoy_limit()
	for f in _fails:
		printerr("E2E FAIL ", f)
	print("E2E summon banners: %d checks, %d failures" % [_checks, _fails.size()])
	quit(1 if _fails.size() > 0 else 0)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_fails.append(what)
		printerr("  FAIL: ", what)


func _frames(n: int = 3) -> void:
	for i in n:
		await process_frame


func _go(params: Dictionary) -> Control:
	while _ui.has_modal():
		_ui.handle_back()
	_ui.go("summon", params)
	await _frames(6)
	# Let the screen's slide-in finish before measuring.
	await create_timer(0.7).timeout
	_check(_ui.current_name == "summon", "navigate to summon %s" % str(params))
	return _ui.current


## Controls inside a ScrollContainer under `from` that would stop a finger drag on a phone
## (mouse_filter STOP on something bigger than a small widget that isn't pressed itself; the same
## rule as tests/tools/scroll_audit.gd).
func _scroll_blockers(from: Node) -> Array[String]:
	var out: Array[String] = []
	if from == null:
		return out
	for sc in from.find_children("*", "ScrollContainer", true, false):
		for n in (sc as Node).find_children("*", "Control", true, false):
			var c := n as Control
			if c is ScrollBar or c is BaseButton or c is ScrollContainer or c is Range or c is LineEdit:
				continue
			if c.mouse_filter == Control.MOUSE_FILTER_STOP and c.is_visible_in_tree() and c.size.x * c.size.y > 120.0 * 120.0:
				out.append("%s %s" % [c.get_class(), c.name])
	return out


func _tap(c: Control) -> void:
	var pos := c.get_global_rect().get_center()
	for down in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = down
		ev.position = pos
		ev.global_position = pos
		root.push_input(ev, true)
		await _frames(2)


func _layouts() -> void:
	var vp: Vector2 = root.get_visible_rect().size
	print("  viewport ", vp)
	for id: String in IDS:
		var s := await _go({"banner": id})
		_check(str(s.get("_bid")) == id, "%s: the poster opens on it" % id)
		_check(_ui.chrome_nav and _ui.chrome_top, "%s: the nav and top bar stay up" % id)
		var nav_top: float = vp.y - float(_ui.content_bottom())
		for n in ["Summon1", "Summon10"]:
			var t := s.find_child(n, true, false) as Control
			_check(t != null and t.is_visible_in_tree(), "%s: ticket %s shows" % [id, n])
			if t == null:
				continue
			var r := t.get_global_rect()
			_check(r.size.y >= 88.0, "%s: %s is a big enough target (%s)" % [id, n, r])
			_check(r.position.x >= -8.0 and r.end.x <= vp.x + 8.0, "%s: %s inside the screen (%s)" % [id, n, r])
			_check(r.end.y <= nav_top + 4.0, "%s: %s above the nav (%s, nav at %d)" % [id, n, r, nav_top])
			print("  %-9s %-9s %s" % [id, n, r])
		var idx := s.find_child("BannerIndex", true, false) as Control
		_check(idx != null and idx.is_visible_in_tree(), "%s: the banner index shows" % id)
		_check(s.find_child("Rates", true, false) != null, "%s: RATES on the poster" % id)
		s.call("_open_rates")
		await _frames(4)
		_check(_ui.has_modal(), "%s: RATES opens the odds" % id)
		var blockers := _scroll_blockers(_ui.root.get("modal_layer"))
		_check(blockers.is_empty(), "%s: nothing in the odds sheet swallows a finger drag %s" % [id, str(blockers)])
		while _ui.has_modal():
			_ui.handle_back()
		await _frames(2)


## Real taps on the printed index switch the poster.
func _index_taps() -> void:
	var s := await _go({"banner": "standard"})
	for i in IDS.size():
		var idx := s.find_child("BannerIndex", true, false) as Control
		var tab := idx.get_node_or_null("Tab%d" % i) as Control if idx else null
		_check(tab != null, "index tab %d" % i)
		if tab == null:
			continue
		await _tap(tab)
		await _frames(4)
		_check(str(s.get("_bid")) == IDS[i], "tapping %s in the index shows it (at %s)" % [IDS[i], str(s.get("_bid"))])
	await _tap(s.find_child("BannerIndex", true, false).get_node("Tab0"))
	await _frames(3)


## One pull on every banner: chrome hidden for the reveal, back for the results, Again is a ticket.
func _pulls() -> void:
	_game.dev_add("gems", 30000)
	_game.dev_add("gold", 200000)
	for id: String in IDS:
		var s := await _go({"banner": id})
		var before: int = _game.counter("summons")
		s.call("_do_summon", 1, false)
		await _frames(2)
		_check(int(_game.counter("summons")) == before + 1, "%s: the pull happened" % id)
		_check(str(s.get("_phase")) == "charge", "%s: the sequence starts" % id)
		_check(not _ui.chrome_nav and not _ui.chrome_top, "%s: chrome hidden for the reveal" % id)
		var seq: Node = s.get("_seq")
		seq.call("skip_all")
		await _frames(3)
		_check(str(s.get("_phase")) == "results", "%s: results" % id)
		_check(_ui.chrome_nav and _ui.chrome_top, "%s: nav and top bar back on the results" % id)
		var again := seq.find_child("Again", true, false) as Control
		_check(again != null and again.has_meta("info_label"), "%s: Again is a ticket" % id)
		var done := seq.find_child("Done", true, false) as Control
		_check(done != null, "%s: Done on the results" % id)
		if again and done:
			var nav_top: float = root.get_visible_rect().size.y - float(_ui.content_bottom())
			_check(again.get_global_rect().end.y <= nav_top + 4.0 and done.get_global_rect().end.y <= nav_top + 4.0,
				"%s: Again and Done above the nav (%s, %s, nav %d)" % [id, again.get_global_rect(), done.get_global_rect(), nav_top])
		var res: Array = s.get("_results")
		if id == "envoy" and not res.is_empty():
			_check(str((res[0] as Dictionary).rarity) != "legendary", "envoy: no Legendary")
		if id == "featured" and not res.is_empty():
			_check((res[0] as Dictionary).has("featured"), "featured: results say featured or not")
		s.call("_finish")
		await _frames(3)
		_check(_ui.chrome_nav and _ui.chrome_top, "%s: Done keeps the chrome" % id)
		_check(str(s.get("_bid")) == id, "%s: back on the same banner" % id)


## The wish: without a target the tickets open the picker; picking sets the wish.
func _wish() -> void:
	_game.model.state.summon.banners.wish.target = ""
	var s := await _go({"banner": "wish"})
	var t1 := s.find_child("Summon1", true, false) as Button
	_check(t1 != null and not t1.disabled, "wish: the ticket is live without a wish (it opens the picker)")
	if t1:
		await _tap(t1)
		await _frames(3)
	_check(_ui.has_modal(), "wish: a ticket without a wish opens the picker")
	var layer: Control = _ui.root.get("modal_layer")
	var blockers := _scroll_blockers(layer)
	_check(blockers.is_empty(), "wish: nothing in the picker swallows a finger drag %s" % str(blockers))
	var choose := layer.find_child("Choose_mordessa", true, false) as Control if layer else null
	_check(choose != null, "wish: the picker shows the choices")
	if choose:
		await _tap(choose)
		await _frames(4)
	_check(str(_game.wish_target()) == "mordessa", "wish: picking sets the wish (%s)" % str(_game.wish_target()))
	_check(not _ui.has_modal(), "wish: the picker closes")
	var print_b := s.find_child("Wish_seraphiel", true, false) as Control
	_check(print_b != null, "wish: the choices are on the band")
	if print_b:
		await _tap(print_b)
		await _frames(4)
	_check(str(_game.wish_target()) == "seraphiel", "wish: tapping a print on the band wishes for her")


## The envoy's tickets are stamped SOLD OUT once today's draws are used.
func _envoy_limit() -> void:
	_game.dev_add("gold", 500000)
	var s := await _go({"banner": "envoy"})
	var left: int = _game.summon_left("envoy")
	while left > 0:
		var r: Dictionary = _game.summon(10 if left >= 10 else 1, false, "envoy")
		_check(bool(r.ok), "envoy draw: %s" % str(r.error))
		left = _game.summon_left("envoy")
	await _frames(3)
	var t10 := s.find_child("Summon10", true, false) as Button
	_check(t10 != null and t10.disabled, "envoy: SOLD OUT after today's draws")
	s.call("_try_summon", 1)
	await _frames(2)
	_check(str(s.get("_phase")) == "", "envoy: no draw past the limit")
