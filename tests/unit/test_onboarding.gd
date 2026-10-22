extends RefCounted
## The intake form (the onboarding): a new player starts un-onboarded, completing it keeps the name
## and a cleaned signature, old saves with progress count as onboarded, replaying resets the flag.

const BASE_MS := 1_702_083_600_000

var _made: Array[Node] = []


func _game() -> Node:
	var g: Node = load("res://src/core/game.gd").new()
	_made.append(g)
	g.save_path = ""
	g.tz_bias_ms = 0
	g.now_override_ms = BASE_MS
	return g


func _done() -> void:
	for g in _made:
		if is_instance_valid(g):
			g.free()
	_made.clear()


func test_new_player_signs_the_form(t: TestCtx) -> void:
	var g := _game()
	g.new_game()
	t.ok(not g.onboarded(), "a new player hasn't answered the call")
	t.eq(g.signature(), [], "no signature yet")
	var r: Dictionary = g.complete_intake("  Aria the Very Long Name Indeed  ", [[10, 20, 30, 40, 2000, -5], [1, 2], "junk"])
	t.ok(bool(r.ok))
	t.ok(g.onboarded())
	t.eq(str(g.state.player_name), "Aria the Very Lo", "the name, trimmed to 16")
	t.eq(g.signature(), [[10, 20, 30, 40, 1000, 0]], "strokes cleaned: clamped, short and bad ones dropped")
	g.complete_intake("", [])
	t.eq(str(g.state.player_name), "Aria the Very Lo", "a blank name keeps the old one")
	g.reset_intake()
	t.ok(not g.onboarded(), "replaying the opening")
	_done()


func test_old_saves(t: TestCtx) -> void:
	var g := _game()
	g.new_game()
	var st: Dictionary = g.state.duplicate(true)
	st.erase("onboarded")
	st.erase("signature")
	st.campaign.cleared = 4
	var m: Dictionary = g.model.migrate(GameData.intify(JSON.parse_string(JSON.stringify(st))))
	t.ok(bool(m.onboarded), "a save with progress skips the intake form")
	t.eq(m.signature, [])
	var st2: Dictionary = g.state.duplicate(true)
	st2.erase("onboarded")
	st2.campaign.cleared = 0
	t.ok(not bool(g.model.migrate(GameData.intify(JSON.parse_string(JSON.stringify(st2)))).onboarded), "a fresh save still gets it")
	var st3: Dictionary = g.state.duplicate(true)
	st3.signature = "scribble"
	t.eq(g.model.migrate(GameData.intify(JSON.parse_string(JSON.stringify(st3)))).signature, [], "a bad signature is dropped")
	_done()
