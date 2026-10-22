extends RefCounted
## The War for Souls (WarRules + GameModel.war*): choosing a side, souls from victories landing in
## the focused sector, the week's standing and claiming last week's reward.

const BASE_MS := 1_702_083_600_000
const DAY := 86400000

var _made: Array[Node] = []


func _game(now_ms: int = BASE_MS) -> Node:
	var g: Node = load("res://src/core/game.gd").new()
	_made.append(g)
	g.save_path = ""
	g.tz_bias_ms = 0
	g.now_override_ms = now_ms
	return g


func _done() -> void:
	for g in _made:
		if is_instance_valid(g):
			g.free()
	_made.clear()


func _open() -> Node:
	var g := _game()
	g.new_game()
	g.model.state.campaign.cleared = WarRules.UNLOCK_CLEARED
	return g


func test_front_opens_and_sides(t: TestCtx) -> void:
	var g := _game()
	g.new_game()
	t.ok(not g.war_unlocked(), "the front waits for the campaign")
	t.ok(not bool(g.war_choose_side("heaven").ok), "no side before it opens")
	g.model.state.campaign.cleared = WarRules.UNLOCK_CLEARED
	t.ok(g.war_unlocked())
	t.ok(not bool(g.war_choose_side("purgatory").ok), "only heaven or hell")
	t.ok(bool(g.war_choose_side("hell").ok))
	t.eq(str(g.war().side), "hell")
	# Before any souls this week a player may still switch; after, not until next week.
	t.ok(bool(g.war_choose_side("heaven").ok), "switch before fighting")
	g.model._war_add_souls(40)
	t.ok(not bool(g.war_choose_side("hell").ok), "no switching mid-week")
	_done()


func test_victories_send_souls_to_the_focus(t: TestCtx) -> void:
	var g := _open()
	var before: Array = (g.war().sectors as Array).map(func(s: Dictionary) -> int: return int(s.control))
	var r: Dictionary = g.complete_stage(0, {"victory": true})
	t.eq(int(r.value.get("souls", -1)), 0, "no side yet: no souls sent")
	g.war_choose_side("heaven")
	t.ok(bool(g.war_set_focus(2).ok))
	t.ok(not bool(g.war_set_focus(99).ok), "unknown sector")
	r = g.complete_stage(0, {"victory": true})
	t.eq(int(r.value.souls), WarRules.SOULS_PER_WIN, "a win sends souls_per_win")
	var w: Dictionary = g.war()
	t.eq(int(w.souls_today), WarRules.SOULS_PER_WIN)
	t.eq(int(w.souls_week), WarRules.SOULS_PER_WIN)
	var after: int = int((w.sectors as Array)[2].control)
	t.eq(after, int(before[2]) + WarRules.SOULS_PER_WIN * WarRules.CONTROL_PER_SOUL_BP, "Heaven's souls push sector 2 its way")
	r = g.complete_stage(0, {"victory": false})
	t.eq(int(g.war().souls_today), WarRules.SOULS_PER_WIN, "a defeat sends nothing (and takes nothing)")
	_done()


func test_claim_last_week(t: TestCtx) -> void:
	var g := _open()
	g.war_choose_side("hell")
	g.war_set_focus(4)
	for i in 3:
		g.complete_stage(0, {"victory": true})
	t.ok((g.war().claim as Dictionary).is_empty(), "nothing to claim during the week")
	# A week later: last week's result is waiting; claiming pays once.
	g.now_override_ms = BASE_MS + 7 * DAY
	var cl: Dictionary = g.war().claim
	t.ok(not cl.is_empty(), "last week's result is claimable")
	var gems := int(g.currency("gems"))
	var r: Dictionary = g.war_claim()
	t.ok(bool(r.ok))
	t.ok(int(g.currency("gems")) > gems, "the claim pays gems")
	t.ok(int(r.value.reward.get("gems", 0)) >= int(WarRules.reward(false, 0).gems), "everyone gets the base share")
	t.ok(not bool(g.war_claim().ok), "only once")
	_done()


func test_save_round_trip_and_repair(t: TestCtx) -> void:
	var g := _open()
	g.war_choose_side("heaven")
	g.complete_stage(0, {"victory": true})
	var st: Dictionary = g.model.state.duplicate(true)
	st.war.side = "limbo"
	st.war.focus = 42
	st.war.log["x"] = {"1": 5}
	st.war.log[str(g.model.today())]["99"] = 7
	var g2 := _game()
	g2.model.migrate(GameData.intify(JSON.parse_string(JSON.stringify(st))))
	var ws: Dictionary = g2.model.state.war
	t.eq(str(ws.side), "", "unknown side cleared")
	t.eq(int(ws.focus), WarRules.sector_count() - 1, "focus clamped")
	t.ok(not (ws.log as Dictionary).has("x"), "bad day keys dropped")
	t.ok(not (ws.log[str(g2.model.today())] as Dictionary).has("99"), "bad sectors dropped")
	_done()
