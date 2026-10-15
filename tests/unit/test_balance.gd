extends RefCounted
## Balance sanity: the campaign difficulty curve does what the design says.

const BASE_MS := 1_702_083_600_000


func _game() -> Node:
	var g: Node = load("res://src/core/game.gd").new()
	g.save_path = ""
	g.tz_bias_ms = 0
	g.now_override_ms = BASE_MS
	g.new_game()
	return g


func _wins(g: Node, stage_index: int, seeds: int) -> int:
	var w := 0
	for s in seeds:
		var setup: Dictionary = g.stage_battle_setup(stage_index)
		setup.seed = 5000 + s * 7919
		if BattleSim.new(setup).run_to_end().victory:
			w += 1
	return w


func test_starters_win_first_stage(t: TestCtx) -> void:
	var g := _game()
	var w := _wins(g, 0, 20)
	t.ok(w >= 18, "starter team wins 1-1 in %d/20 seeds (need >= 18)" % w)
	g.free()


func test_starters_win_opening_stages_without_upgrades(t: TestCtx) -> void:
	# A brand-new player can clear 1-1..1-3 before touching any upgrade; 1-4 is the first wall.
	var g := _game()
	for i in 3:
		var w := _wins(g, i, 20)
		t.ok(w >= 18, "L1 starters win %s in %d/20 seeds" % [g.stage(i).id, w])
	t.ok(_wins(g, 3, 10) <= 2, "1-4 asks for levels or summons")
	g.free()


func test_starters_lose_chapter_one_boss(t: TestCtx) -> void:
	var g := _game()
	var w := _wins(g, 9, 20)
	t.eq(w, 0, "unupgraded starters must lose the 1-10 boss (won %d/20)" % w)
	g.free()


func test_rich_state_wins_chapter_one_boss(t: TestCtx) -> void:
	var g := _game()
	g.make_rich_state()
	var w := _wins(g, 9, 20)
	t.ok(w >= 19, "--rich state wins 1-10 in %d/20 seeds" % w)
	g.free()


func test_summons_are_needed_by_stage_six(t: TestCtx) -> void:
	# Three starters at a level the first five clears can pay for still struggle at 1-6.
	var g := _game()
	for id in ["uriela", "lucen", "kessa"]:
		g.state.heroes[id].level = 12
	var w := _wins(g, 5, 10)
	t.ok(w <= 3, "three starters at L12 win 1-6 in %d/10 seeds (should need summoned heroes)" % w)
	g.free()


func test_campaign_shape(t: TestCtx) -> void:
	var g := _game()
	t.eq(g.chapters().size(), 3)
	t.eq(g.stages().size(), 30)
	var prev_level := 0
	var prev_power := 0
	for st in g.stages():
		t.ok(int(st.recommended_power) >= prev_power, "recommended power never drops (%s)" % st.id)
		prev_power = int(st.recommended_power)
		for k in ["index", "id", "chapter", "name", "enemies", "recommended_power", "first_clear_reward", "is_boss"]:
			t.ok(st.has(k), "stage has %s" % k)
		var local: int = int(st.index) % 10
		t.eq(st.is_boss, local == 4 or local == 9, "%s boss flag" % st.id)
		var bosses := 0
		var lv := 0
		for e in st.enemies:
			t.ok(not HeroData.get_def(e.hero_id).is_empty(), "echo of a roster hero")
			if e.is_boss:
				bosses += 1
			lv = maxi(lv, int(e.level))
		t.eq(bosses, 1 if st.is_boss else 0, "%s has its boss" % st.id)
		t.ok(lv >= prev_level, "enemy levels never drop (%s)" % st.id)
		prev_level = lv
		t.ok(int(st.first_clear_reward.get("gold", 0)) > 0)
		if st.is_boss:
			t.ok(int(st.first_clear_reward.get("gems", 0)) > 0, "%s boss gives gems" % st.id)
	for c in g.chapters():
		for k in ["index", "id", "name", "intro", "background"]:
			t.ok(c.has(k))
		t.ok(String(c.intro).length() > 60, "chapter intro written")
	g.free()


func test_stage_flow(t: TestCtx) -> void:
	var g := _game()
	t.eq(g.current_stage().id, "1-1")
	t.eq(g.complete_stage(1, {"victory": true}).ok, false, "can't skip ahead")
	var r: Dictionary = g.complete_stage(0, {"victory": true})
	t.ok(r.ok)
	t.ok(r.value.first_clear)
	t.ok(int(r.value.reward.get("gold", 0)) > 0)
	t.eq(g.current_stage().id, "1-2")
	r = g.complete_stage(0, {"victory": true})
	t.eq(r.value.first_clear, false, "replays don't pay first-clear rewards")
	t.eq(r.value.reward, {})
	r = g.complete_stage(1, {"victory": false})
	t.ok(r.ok)
	t.eq(r.value.victory, false)
	t.eq(g.cleared_count(), 1)
	# A stage with a gear drop creates and equips real items.
	r = g.complete_stage(1, {"victory": true})
	t.eq(r.value.reward.get("gear", []).size(), 1, "1-2 drops gear")
	g.free()


func test_battle_setup_shape(t: TestCtx) -> void:
	var g := _game()
	var s: Dictionary = g.stage_battle_setup(4)
	t.eq(s.allies.size(), 3)
	t.eq(s.enemies.size(), g.stage(4).enemies.size())
	for u in s.allies + s.enemies:
		for k in ["uid", "hero_id", "side", "slot", "level", "stars", "stats", "is_boss"]:
			t.ok(u.has(k), "unit setup has %s" % k)
	t.ok(s.has("seed"))
	t.ok(g.stage_battle_setup(4).seed != s.seed, "each attempt gets a new seed")
	g.free()


## Pacing guard: an efficient free player (4 short sessions a day, spends everything well)
## clears about chapter 1 on day 1 and does not run through chapter 2 on day 2.
func test_free_player_pacing(t: TestCtx) -> void:
	var bot = load("res://tests/tools/pacing_bot.gd").new()
	bot.start()
	var after_first := 0
	var by_day := []
	for day in 2:
		for s in 4:
			bot.goto_session(day, s)
			bot.economy(day == 0 and s == 0)
			bot.push(2)
			if day == 0 and s == 0:
				after_first = bot.g.cleared_count()
		by_day.append(bot.g.cleared_count())
	t.ok(after_first >= 4 and after_first <= 8, "first session clears %d stages (want 4-8: past the starters, around the 1-5 boss)" % after_first)
	t.ok(by_day[0] >= 7 and by_day[0] <= 13, "day 1 ends with %d stages cleared (want about chapter 1)" % by_day[0])
	t.ok(by_day[1] >= 11 and by_day[1] <= 19, "day 2 ends with %d stages cleared (chapter 2 takes days)" % by_day[1])
	bot.finish()
