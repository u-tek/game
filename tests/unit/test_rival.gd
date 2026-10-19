extends RefCounted
## The Rival "Rue" (data/rival.json, RivalRules, GameModel rival_*): the unlock, her daily sim
## (deterministic, the catch-up cap, a clock going back), her stars and level, counter-picking,
## the battle setup, a win (tags, the haul once a day, her print) and a loss (costs nothing), the
## feed light and save migration.

const BASE_MS := 1_702_083_600_000
const HOUR := 3600000
const DAY := 86400000


var _made: Array[Node] = []


func _game(now_ms: int = BASE_MS) -> Node:
	var g: Node = load("res://src/core/game.gd").new()
	_made.append(g)
	g.save_path = ""
	g.tz_bias_ms = 0
	g.now_override_ms = now_ms
	return g


## Frees every Game node this test made (call at the end of each test).
func _done() -> void:
	for g in _made:
		if is_instance_valid(g):
			g.free()
	_made.clear()


## A new game with the campaign far enough for her to show up.
func _open() -> Node:
	var g := _game()
	g.new_game()
	g.model.state.campaign.cleared = RivalRules.UNLOCK_CLEARED
	return g


func _wallet(g: Node) -> String:
	return JSON.stringify([g.state.currencies, g.state.heroes, g.state.prints.list, g.state.gear])


func test_unlock(t: TestCtx) -> void:
	var g := _game()
	g.new_game()
	t.eq(g.rival_unlocked(), false, "locked at the start")
	var v: Dictionary = g.rival()
	t.eq(bool(v.unlocked), false)
	t.eq(str(v.name), "Rue")
	t.ok(not v.has("team"), "no team before she shows up")
	t.eq(g.rival_battle_setup(), {}, "no fight while locked")
	t.eq(g.complete_rival({"victory": true}).ok, false)
	t.eq(g.rival_alert(), false)
	t.eq(int(g.state.rival.pulls), 0, "she does nothing while locked")
	g.model.state.campaign.cleared = RivalRules.UNLOCK_CLEARED
	t.ok(g.rival_unlocked())
	v = g.rival()
	t.eq(bool(v.unlocked), true)
	t.eq((v.team as Array).size(), 5, "five heroes from the start")
	t.eq(int(v.pulls), RivalRules.PULLS_PER_DAY, "her first day's pulls")
	t.eq(bool(v.met), false)
	t.eq(str(v.line_kind), "intro")
	t.ok(str(v.line) != "")
	_done()


func test_meet_and_feed_light(t: TestCtx) -> void:
	var g := _open()
	var m: Dictionary = g.rival_meet()
	t.ok(m.ok)
	t.ok(str(m.value.line).length() > 5)
	t.eq(bool(g.rival().met), true)
	t.ok(g.rival_alert(), "a haul is waiting on a new day")
	# Read the feed, take the haul: the light goes out until something new happens.
	g.rival_seen()
	t.eq(int(g.rival().new_feed), 0)
	g.complete_rival({"victory": true})
	t.eq(g.rival_alert(), false)
	g.now_override_ms = BASE_MS + 3 * DAY
	t.ok(g.rival_alert(), "a new day: a new haul")
	_done()


func test_sim_deterministic_and_capped(t: TestCtx) -> void:
	var e := EconomyData.BANNER_EPOCH_DAY
	var a := RivalRules.new_state(42)
	var b := RivalRules.new_state(42)
	RivalRules.catch_up(a, e + 3, e, {})
	RivalRules.catch_up(b, e + 3, e, {})
	t.eq(JSON.stringify(a), JSON.stringify(b), "same seed, same Rue")
	t.eq((a.heroes as Dictionary).size() >= RivalRules.start_heroes().size(), true)
	for id: Variant in RivalRules.start_heroes():
		t.ok(a.heroes.has(str(id)), "she starts with %s" % id)
	# Far behind: only the last catch_up_days days are simulated.
	var c := RivalRules.new_state(7)
	RivalRules.catch_up(c, e, e, {})
	var pulls0 := int(c.pulls)
	var n := RivalRules.catch_up(c, e + 100, e, {})
	t.eq(n, RivalRules.CATCH_UP_DAYS, "at most a week of catching up")
	t.eq(int(c.pulls) - pulls0, RivalRules.CATCH_UP_DAYS * RivalRules.PULLS_PER_DAY)
	t.eq(int(c.day), e + 100)
	# Same day again, or a clock that went back: nothing.
	t.eq(RivalRules.catch_up(c, e + 100, e, {}), 0)
	t.eq(RivalRules.catch_up(c, e + 90, e, {}), 0)
	t.eq(int(c.day), e + 100, "the clock going back changes nothing")
	t.ok((c.feed as Array).size() <= RivalRules.FEED_MAX)
	t.ok((c.prints as Array).size() <= RivalRules.PRINTS_MAX)
	for p: Dictionary in c.prints:
		t.ok(RivalRules.keeps(p), "she keeps only notable prints")
	# Feed: newest first, numbered.
	var feed: Array = c.feed
	for i in range(1, feed.size()):
		t.ok(int(feed[i - 1].n) > int(feed[i].n), "newest first")
		t.ok(str(feed[i].line) != "", "every entry has a line")


func test_model_catch_up_cap(t: TestCtx) -> void:
	var g := _open()
	g.rival()
	var p0 := int(g.state.rival.pulls)
	g.now_override_ms = BASE_MS + 30 * DAY
	g.rival()
	t.eq(int(g.state.rival.pulls) - p0, RivalRules.CATCH_UP_DAYS * RivalRules.PULLS_PER_DAY, "a month away: one week of her pulls")
	_done()


func test_stars_and_level(t: TestCtx) -> void:
	t.eq(RivalRules.stars_for("uriela", 0, 6), 1)
	t.eq(RivalRules.stars_for("uriela", 4, 6), 3, "a star per two dupes")
	t.eq(RivalRules.stars_for("uriela", 40, 3), 3, "never past the player's best")
	t.eq(RivalRules.stars_for("seraphiel", 0, 1), Progression.start_stars("legendary"), "never below her start stars")
	t.eq(RivalRules.stars_for("uriela", 99, 99), EconomyData.MAX_STARS)
	var wob: Array = RivalRules.data().level_wobble
	t.eq(RivalRules.level_on(30, 0, false), 30 + int(wob[0]))
	t.eq(RivalRules.level_on(30, 3, true), 30 + int(wob[3]) + int(RivalRules.data().counter_level))
	t.eq(RivalRules.level_on(1, 0, true), 1, "never below 1")
	t.eq(RivalRules.counter_faction("infernal"), "celestial", "celestial beats infernal")
	t.eq(RivalRules.counter_faction("celestial"), "fallen")
	t.eq(RivalRules.counter_faction(""), "")


func test_team_and_counter_pick(t: TestCtx) -> void:
	var all := {}
	for id in HeroData.ids():
		all[id] = 2
	var tm := RivalRules.team(all, 4, 40, "")
	t.eq(tm.size(), 5)
	var slots: Array = []
	for e: Dictionary in tm:
		slots.append(int(e.slot))
		t.eq(int(e.echo_bp), RivalRules.echo_bp())
		t.ok(int(e.level) <= Progression.level_cap(int(e.stars)))
	t.eq(slots, [0, 1, 2, 3, 4])
	var pref := RivalRules.team(all, 4, 40, "celestial")
	for e: Dictionary in pref:
		t.eq(str(HeroData.get_def(str(e.hero_id)).faction), "celestial", "she stacks the counter faction")
	# The model: after learn_after fights she counters the player's main faction.
	var g := _open()
	g.rival_meet()
	t.eq(str(g.rival().counter.faction), "", "she doesn't know you yet")
	for i in int(RivalRules.data().learn_after):
		g.complete_rival({"victory": i % 2 == 0})
	var v: Dictionary = g.rival()
	var main := str(v.counter.main)
	t.ok(main != "", "she has read your main faction")
	t.eq(str(v.counter.faction), RivalRules.counter_faction(main))
	t.eq(str(v.line_kind) in ["win", "lose", "counter"], true)
	_done()


func test_battle_setup(t: TestCtx) -> void:
	var g := _open()
	var s: Dictionary = g.rival_battle_setup()
	t.eq((s.enemies as Array).size(), 5)
	t.ok((s.allies as Array).size() > 0)
	t.eq(bool(s.rival), true)
	t.ok(HeroArt.background(str(s.background)) != null, "her backdrop exists")
	var e0: Dictionary = s.enemies[0]
	t.eq(str(e0.side), "enemy")
	var want := StageData.echo_stats(str(e0.hero_id), int(e0.level), int(e0.stars), RivalRules.echo_bp())
	t.eq(int(e0.stats.hp), int(want.hp), "her heroes fight as echoes at strength_bp")
	var s2: Dictionary = g.rival_battle_setup()
	t.ok(int(s.seed) != int(s2.seed), "every attempt has its own seed")
	var out := BattleSim.new(s).run_to_end()
	t.ok(out.has("victory"), "the fight runs")
	_done()


func test_win_haul_once_a_day(t: TestCtx) -> void:
	var g := _open()
	g.rival()
	# Give her a print to lose.
	var rs: Dictionary = g.state.rival
	(rs.prints as Array).append({"uid": "rue-999", "n": 999, "hero": "kessa", "banner": "standard", "edition": 1, "printing": 1,
		"serial": 7, "run": 5000, "flaw": "double", "ink": "", "holo": true, "grade": 9, "v": 3, "day": 0, "first": false, "taken": false})
	var gems0 := int(g.currency("gems"))
	var gold0 := int(g.currency("gold"))
	var n0: int = g.prints().size()
	var r: Dictionary = g.complete_rival({"victory": true})
	t.ok(r.ok)
	t.eq(bool(r.value.haul), true, "the first win today pays her haul")
	var h := RivalRules.haul(g.cleared_count())
	t.eq(int(g.currency("gems")) - gems0, int(h.gems))
	t.eq(int(g.currency("gold")) - gold0, int(h.gold))
	t.eq(str(r.value.print.uid), "rue-999", "her best untaken print")
	t.eq(str(r.value.print.from), "rival")
	t.eq(g.prints().size(), n0 + 1, "copied into the album")
	t.eq(str(g.prints("rival")[0].uid), "rue-999")
	t.eq(bool(g.state.rival.tag_her), true, "you tag her poster")
	t.eq(bool(g.state.rival.tag_you), false)
	t.eq(int(g.rival().record.wins), 1)
	# A second win the same day: recorded, no haul.
	var gems1 := int(g.currency("gems"))
	var r2: Dictionary = g.complete_rival({"victory": true})
	t.eq(bool(r2.value.haul), false)
	t.eq(int(g.currency("gems")), gems1)
	t.eq(int(g.rival().record.wins), 2)
	t.eq(bool(g.rival().haul_ready), false)
	# Tomorrow: another haul.
	g.now_override_ms = BASE_MS + DAY
	t.eq(bool(g.rival().haul_ready), true)
	t.eq(bool(g.complete_rival({"victory": true}).value.haul), true)
	_done()


func test_loss_costs_nothing(t: TestCtx) -> void:
	var g := _open()
	g.rival_meet()
	var before := _wallet(g)
	var r: Dictionary = g.complete_rival({"victory": false})
	t.ok(r.ok)
	t.eq(bool(r.value.victory), false)
	t.eq(r.value.reward, {})
	t.eq(_wallet(g), before, "losing to her takes nothing")
	t.eq(bool(g.state.rival.tag_you), true, "she tags your Lobby poster")
	t.eq(bool(g.state.rival.tag_her), false)
	t.eq(int(g.rival().record.losses), 1)
	t.eq(str(g.rival().line_kind), "win", "she gloats")
	t.eq(bool(g.rival().haul_ready), true, "the haul still waits for a win")
	g.complete_rival({"victory": true})
	t.eq(bool(g.state.rival.tag_you), false, "beating her clears her tag")
	_done()


func test_save_round_trip_and_migration(t: TestCtx) -> void:
	var g := _open()
	g.rival_meet()
	g.complete_rival({"victory": false})
	var saved: Dictionary = g.intify(JSON.parse_string(JSON.stringify(g.state)))
	var g2 := _game()
	g2.migrate(saved)
	t.eq(JSON.stringify(g2.rival()), JSON.stringify(g.rival()), "she survives a save")
	# An old save without the block: a fresh Rue.
	var g3 := _game()
	g3.migrate({"version": 1, "heroes": {"uriela": {"id": "uriela", "level": 3, "stars": 1}}, "campaign": {"cleared": 9}})
	t.eq(bool(g3.state.rival.met), false)
	t.eq(int(g3.state.rival.fights), 0)
	t.ok(int(g3.state.rival.seed) != 0)
	t.eq((g3.rival().team as Array).size(), 5)
	# Damaged values are repaired.
	var g4 := _game()
	g4.migrate({"version": 1, "heroes": {"kessa": {"id": "kessa"}}, "rival": {"heroes": {"ghost": 3, "orrin": -2, "kessa": 4},
		"pity": {"standard": 500, "bogus": 3}, "wins": -1, "seen": 99, "feed_seq": 5, "prints": ["junk", {"uid": "rue-1", "hero": "kessa"}],
		"feed": "junk", "tag_you": "yes"}})
	var rs: Dictionary = g4.state.rival
	t.eq(rs.heroes, {"orrin": 0, "kessa": 4})
	t.eq(rs.pity, {"standard": 59})
	t.eq(int(rs.wins), 0)
	t.eq(int(rs.seen), 5)
	t.eq((rs.prints as Array).size(), 1)
	t.eq(rs.feed, [])
	t.eq(rs.tag_you, false)
	_done()
