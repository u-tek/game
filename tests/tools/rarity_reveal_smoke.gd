extends SceneTree
## Headless smoke run of the rarity language (src/ui/v4/rarity_kit.gd) through the real main scene:
## the summon reveal of each rarity (demo results, nothing saved) played on its own clock, untouched,
## then tapped through (a tap jumps to the press, the next lands it, the next moves on), with Reduce
## motion off and on; checks each reveal settles in its time (Rare about 1 s, Epic about 1.8 s,
## Legendary about 3.5 s; Reduce motion much shorter), that a Legendary's dark lifts, that the x10 run
## and Skip still reach the contact sheet with every card framed by rarity, and that the hero list's
## and the team bench's cards carry their rarity frames.
##   tools/gd --headless --path . -s tests/tools/rarity_reveal_smoke.gd -- --rich
## Exit code 1 on failure (scan the output for SCRIPT ERROR as well).

var _fails: Array[String] = []
var _checks := 0
var _game: Node
var _ui: Node


func _initialize() -> void:
	create_timer(180.0).timeout.connect(func() -> void:
		printerr("SMOKE: timed out")
		quit(2))
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_fails.append(what)
		printerr("  FAIL: ", what)


func _run() -> void:
	var main: Node = load("res://src/main.tscn").instantiate()
	root.add_child(main)
	await _frames(3)
	_game = root.get_node("Game")
	_ui = root.get_node("UI")
	for rm: bool in [false, true]:
		_game.set_setting("reduce_motion", rm)
		for rarity: String in ["rare", "epic", "legendary"]:
			await _reveal_clock(rarity, rm)
			await _reveal_taps(rarity, rm)
	_game.set_setting("reduce_motion", false)
	await _ten()
	await _cards()
	for f in _fails:
		printerr("SMOKE FAIL ", f)
	print("SMOKE rarity reveals: %d checks, %d failures" % [_checks, _fails.size()])
	quit(1 if _fails.size() > 0 else 0)


## Opens the summon screen on a made-up single result of `rarity` at its reveal.
func _open(rarity: String) -> Control:
	_ui.go("summon", {"demo": rarity, "card": 0})
	await _frames(4)
	return _ui.current


## Lets the reveal play by itself and times how long it takes to settle.
func _reveal_clock(rarity: String, rm: bool) -> void:
	var s := await _open(rarity)
	var seq: Node = s.get("_seq")
	var r: Node = seq.get("_reveal") if seq else null
	_check(r != null and str(r.get("rarity")) == rarity, "%s reveal shows (rm %s)" % [rarity, rm])
	if r == null:
		return
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 8000 and is_instance_valid(r) and not bool(r.get("settled")):
		await process_frame
	var took := (Time.get_ticks_msec() - t0) / 1000.0
	var want: float = {"rare": 1.0, "epic": 1.8, "legendary": 3.5}[rarity]
	if rm:
		want /= float((r.get_script() as GDScript).get_script_constant_map().get("RM_SPEED", 3.0))
	_check(is_instance_valid(r) and bool(r.get("settled")), "%s settles by itself (rm %s)" % [rarity, rm])
	# Headless frames are uneven: allow a generous margin, but the order of the rarities must hold.
	_check(took >= want * 0.6 and took <= want * 1.8 + 0.6, "%s takes about %.1f s (took %.2f, rm %s)" % [rarity, want, took, rm])
	if rarity == "legendary":
		var bd: Node = seq.get("_backdrop")
		await create_timer(0.5).timeout
		_check(bd != null and float(bd.call("darkness")) < 0.2, "the Legendary's dark lifts once she has landed (rm %s)" % rm)
	if rarity != "rare":
		_check(r.get("_hburst") != null if rarity == "epic" else r.get("_plate") != null, "%s builds its press" % rarity)
	_ui.go("home")
	await _frames(3)


## Taps through: the first tap jumps to the press, the next lands it, the next moves on.
func _reveal_taps(rarity: String, rm: bool) -> void:
	var s := await _open(rarity)
	var seq: Node = s.get("_seq")
	var t0 := Time.get_ticks_msec()
	var taps := 0
	while Time.get_ticks_msec() - t0 < 6000 and str(s.get("_phase")) != "results":
		await _frames(2)
		seq.call("tap")
		taps += 1
	_check(str(s.get("_phase")) == "results", "%s taps through to the results (rm %s)" % [rarity, rm])
	_check(taps <= 4, "%s needs at most 4 taps (took %d, rm %s)" % [rarity, taps, rm])
	var bd: Node = seq.get("_backdrop")
	await _frames(30)
	_check(bd != null and float(bd.call("darkness")) < 0.3, "%s: the room is lit on the results (rm %s)" % [rarity, rm])
	_ui.go("home")
	await _frames(3)


## The x10 run, played a little then skipped: the contact sheet frames each print by rarity.
func _ten() -> void:
	_ui.go("summon", {"demo": "ten"})
	await _frames(4)
	var s: Control = _ui.current
	await create_timer(3.2).timeout
	_check(str(s.get("_phase")) == "reveal", "x10: the charge opens on the first reveal")
	var seq: Node = s.get("_seq")
	seq.call("skip_all")
	await _frames(20)
	var cards: Array = s.get("_cards")
	_check(cards.size() == 10, "x10: Skip shows 10 prints (got %d)" % cards.size())
	var res: Array = s.get("_results")
	for i in cards.size():
		var rr := str((res[i] as Dictionary).get("rarity", "rare"))
		var fr: Array = (cards[i] as Node).find_children("RarityFrame", "", true, false)
		_check((fr.size() == 1) == (rr != "rare"), "x10: print %d (%s) has %s rarity frame" % [i, rr, "a" if rr != "rare" else "no"])
		if rr == "legendary":
			_check(not (cards[i] as Node).find_children("LegendTab", "", true, false).is_empty(), "x10: the Legendary print has its LEGEND tab")
	_ui.go("home")
	await _frames(3)


## The hero list and the team bench: every card framed by its rarity.
func _cards() -> void:
	_ui.go("heroes")
	await _frames(6)
	var scr: Node = _ui.current
	var seen := {"rare": 0, "epic": 0, "legendary": 0}
	for n in scr.find_children("PortraitCard_*", "", true, false):
		var id := str(n.get("hero_id"))
		var rr := str(_game.hero_def(id).get("rarity", "rare"))
		var fr: Variant = n.get("rarity_frame")
		_check((fr != null) == (rr != "rare"), "roster: %s (%s) framed right" % [id, rr])
		if rr == "legendary" and fr != null:
			_check((fr as Node).get("growth") != null and (fr as Node).get("tab") != null, "roster: %s has her growth and LEGEND tab" % id)
		seen[rr] = int(seen[rr]) + 1
	_check(int(seen.rare) > 0 and int(seen.epic) > 0 and int(seen.legendary) > 0, "roster shows every rarity (%s)" % str(seen))
	_ui.go("formation")
	await _frames(6)
	var bench := 0
	for n in _ui.current.find_children("PortraitCard_*", "", true, false):
		if n.get("rarity_frame") != null:
			bench += 1
	_check(bench > 0, "team bench cards carry rarity frames (%d)" % bench)
	_ui.go("home")
	await _frames(3)
