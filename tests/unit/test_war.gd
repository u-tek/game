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


func test_champion_week(t: TestCtx) -> void:
	var g := _open()
	t.ok((g.war().champion as Dictionary).is_empty(), "no champion without a side")
	t.ok(g.war_champion_setup().is_empty(), "no fight without a side")
	g.war_choose_side("heaven")
	var ch: Dictionary = g.war().champion
	var week := WarRules.week_of(g.model.today())
	t.eq(str(ch.hero), WarRules.champion_for(week, "heaven"), "Heaven meets Hell's champion")
	t.ok(str(HeroData.get_def(str(ch.hero)).faction) == "infernal", "Hell's champions are Infernal")
	t.eq(int(ch.tries_left), WarRules.CHAMP_TRIES)
	var setup: Dictionary = g.war_champion_setup()
	t.eq((setup.enemies as Array).size(), 1, "she fights alone")
	t.ok(bool((setup.enemies as Array)[0].is_boss), "as a boss")
	t.eq(int(setup.max_ms), WarRules.CHAMP_MAX_MS)
	# The battle's max HP for her matches the view's hp.
	var sim := BattleSim.new(setup)
	t.eq(int(sim.unit("e0").max_hp), int(ch.hp), "champion_hp matches the battle")
	# Damage adds up; tiers pay once as they are reached.
	var hp := int(ch.hp)
	var gems := int(g.currency("gems"))
	var r: Dictionary = g.complete_champion({"damage_dealt": {"a0": hp * 12 / 100, "e0": 999999}})
	t.ok(bool(r.ok))
	t.eq(int(r.value.damage), hp * 12 / 100, "only the team's damage counts")
	t.eq(r.value.tiers, [0], "the 10% tier is reached")
	t.ok(int(g.currency("gems")) > gems, "the tier pays")
	r = g.complete_champion({"damage_dealt": {"a1": hp * 40 / 100}})
	t.eq(r.value.tiers, [1, 2], "25% and 50% reached together")
	r = g.complete_champion({"damage_dealt": {"a1": 1}})
	t.eq(r.value.tiers, [], "nothing new")
	t.ok(not bool(g.complete_champion({"damage_dealt": {}}).ok), "three tries a day")
	t.ok(g.war_champion_setup().is_empty(), "no setup with no tries left")
	# The next day: tries back, the week's damage kept.
	g.now_override_ms = BASE_MS + DAY if WarRules.week_of(g.model.day_of(BASE_MS + DAY)) == week else BASE_MS
	if WarRules.week_of(g.model.today()) == week:
		g.now_override_ms = BASE_MS + DAY
		ch = g.war().champion
		if WarRules.week_of(g.model.today()) == week:
			t.eq(int(ch.tries_left), WarRules.CHAMP_TRIES, "tries reset each day")
			t.ok(int(ch.damage) > 0, "damage kept for the week")
	_done()


func test_district_buildings_keepers_and_idle(t: TestCtx) -> void:
	var g := _open()
	var base: Dictionary = g.model.idle_rates()
	t.eq(base, IdleRules.per_hour(g.model.cleared_count()), "no side: no district bonus")
	g.war_choose_side("hell")
	var d: Dictionary = g.district()
	t.eq(str(d.name), DistrictRules.quarter_name("hell"))
	t.ok(bool((d.buildings as Array)[0].open), "the first building opens at once")
	t.ok(not bool((d.buildings as Array)[1].open), "the next waits for souls")
	t.ok(int(g.model.idle_rates().gold) > int(base.gold), "the open building raises the gold rate")
	t.ok(not bool(g.district_set_keeper(1, "kessa").ok), "a closed building takes no keeper")
	g.model.state.war.souls_total = 1200
	t.ok(bool((g.district().buildings as Array)[2].open), "1200 souls open the market")
	var owned: Array = g.owned_heroes()
	var inf := ""
	var cel := ""
	for h: Dictionary in owned:
		var f := str(HeroData.get_def(str(h.id)).faction)
		if f == "infernal" and inf == "":
			inf = str(h.id)
		elif f == "celestial" and cel == "":
			cel = str(h.id)
	if inf == "":
		g.model.add_hero("kessa")
		inf = "kessa"
	if cel == "":
		g.model.add_hero("uriela")
		cel = "uriela"
	var before := int(g.model.idle_rates().gold)
	t.ok(bool(g.district_set_keeper(0, inf).ok))
	var b0: Dictionary = (g.district().buildings as Array)[0]
	t.ok(bool(b0.doubled), "an Infernal keeper doubles a Hell building")
	t.ok(int(g.model.idle_rates().gold) > before, "and the rate goes up")
	t.ok(bool(g.district_set_keeper(2, inf).ok), "moving her")
	t.eq(str((g.district().buildings as Array)[0].keeper), "", "frees the old building")
	t.ok(bool(g.district_set_keeper(0, cel).ok))
	t.ok(not bool((g.district().buildings as Array)[0].doubled), "a Celestial keeper doesn't double for Hell")
	t.ok(not bool(g.district_set_keeper(0, "nobody").ok), "unknown hero refused")
	# Levels: gold raises an open building; its bonus grows to x3 at the top.
	var lv0: Dictionary = (g.district().buildings as Array)[0]
	t.eq(int(lv0.level), 1)
	var cost := int((lv0.upgrade_cost as Dictionary).gold)
	g.model.state.currencies.gold = cost - 1
	t.ok(not bool(g.district_upgrade(0).ok), "not enough gold")
	g.model.state.currencies.gold = 100000000
	var r0 := int(g.model.idle_rates().gold)
	t.ok(bool(g.district_upgrade(0).ok))
	t.eq(int(g.model.state.currencies.gold), 100000000 - cost, "the gold is spent")
	t.ok(int(g.model.idle_rates().gold) > r0, "a level raises the rate")
	for k in 3:
		t.ok(bool(g.district_upgrade(0).ok))
	var top: Dictionary = (g.district().buildings as Array)[0]
	t.eq(int(top.level), DistrictRules.MAX_LEVEL)
	t.eq(int(top.bonus_bp), DistrictRules.level_bonus(int(DistrictRules.BUILDINGS[0].bonus_bp), DistrictRules.MAX_LEVEL), "x3 at the top")
	t.ok(not bool(g.district_upgrade(0).ok), "no higher")
	t.ok(not bool(g.district_upgrade(7).ok), "a closed building can't be raised")
	# Arranging the quarter: a free lot takes the building; the road, the edge and others refuse.
	t.ok(bool(g.district_place(0, 3, 6).ok), "its own lot")
	t.ok(not bool(g.district_place(0, 7, 6).ok), "past the edge")
	t.ok(not bool(g.district_place(7, 3, 3).ok), "on the road")
	t.ok(not bool(g.district_place(4, 5, 5).ok), "on the market")
	t.ok(bool(g.district_place(7, 3, 2).ok), "a free lot")
	t.eq((g.district().buildings as Array)[7].spot, [3, 2])
	var st: Dictionary = g.model.state.duplicate(true)
	st.war.layout["1"] = [3, 2]
	g.model.migrate(st)
	t.eq((g.model.state.war.layout as Dictionary).size(), 0, "a layout that no longer fits goes back to the plan")
	# Decor: bought onto a free lot, moved, refused on the road and on buildings, sold back for half.
	g.model.state.currencies.gold = 1000000
	t.ok(bool(g.district_decor_buy("fountain", 1, 2).ok))
	t.eq(int(g.model.state.currencies.gold), 1000000 - 60000)
	t.ok(not bool(g.district_decor_buy("tree", 1, 2).ok), "one prop a lot")
	t.ok(not bool(g.district_decor_buy("tree", 1, 3).ok), "not on the road")
	t.ok(not bool(g.district_decor_buy("tree", 3, 6).ok), "not on the gate")
	t.ok(not bool(g.district_decor_buy("castle", 1, 4).ok), "unknown kind")
	t.ok(bool(g.district_decor_move(0, 2, 4).ok))
	t.ok(not bool(g.district_place(3, 2, 4).ok), "a building can't stand on a prop")
	t.ok(bool(g.district_decor_remove(0).ok))
	t.eq(int(g.model.state.currencies.gold), 1000000 - 30000, "half back")
	t.eq((g.district().decor as Array).size(), 0)
	_done()
