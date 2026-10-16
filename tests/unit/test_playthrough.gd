extends RefCounted
## First-days playthrough: a bot plays a brand-new game only through the Game API, the way a
## reasonable new player would, and checks that nobody is hard-stuck early.
##
## Each session the bot claims idle rewards (and the free quick claim), takes the free daily
## summon, summons with every scroll and with its gems, lets Auto-fill pick the team, stars up
## and levels the team with what it has, claims finished quests, then fights the next stage
## with BattleSim.run_to_end (the Skip path). After a loss it upgrades and retries a couple of
## times; when it can do nothing more it waits (dev_skip_time) and comes back, like a player
## checking in a few hours later.
##
## Several "luck" values change the start time, which seeds summons and battles, so the test
## covers good and bad summon luck. If this fails after a tuning change, re-solve the stages
## (tests/tools/calibrate_stages.gd) or adjust data/economy.json.
## Detailed numbers: tools/gd --headless --path . -s tests/tools/playthrough_report.gd

const HOUR := 3600000
## 09:00 UTC: the first session starts in the morning.
const START_MS := 1_702_112_400_000
## How long a stuck player stays away before the next check-in.
const WAIT_H := 3
## Losses in a row on one stage before the bot ends the session.
const RETRIES_PER_SESSION := 3
const LUCK: Array[int] = [0, 7_919, 104_729, 31_337, 271_828, 8_675_309]
## Chapter 1 = stages 0..9.
const CHAPTER_1 := 10


## Plays until `target` stages are cleared or `max_hours` of game time pass.
## spend_gems = false: a cautious player who only uses free pulls and scrolls.
## Returns {cleared, hours, attempts {stage: fights}, sessions {stage: sessions it was fought in},
## longest_wait_h, battles, problems [String]}.
func play(luck: int, target: int, max_hours: int, spend_gems: bool = true) -> Dictionary:
	var g: Node = load("res://src/core/game.gd").new()
	g.save_path = ""
	g.tz_bias_ms = 0
	g.now_override_ms = START_MS + luck
	g.new_game()
	var r := {"cleared": 0, "hours": 0, "attempts": {}, "sessions": {}, "longest_wait_h": 0,
		"battles": 0, "problems": []}
	var wait := 0
	while g.cleared_count() < target and int(r.hours) <= max_hours:
		_session(g, spend_gems, r)
		var before: int = g.cleared_count()
		var losses := 0
		var fought := {}
		while g.cleared_count() < target and losses < RETRIES_PER_SESSION:
			var i: int = g.cleared_count()
			var setup: Dictionary = g.stage_battle_setup(i)
			if (setup.get("allies", []) as Array).is_empty():
				r.problems.append("no team for stage %d" % i)
				break
			var out: Dictionary = BattleSim.new(setup).run_to_end()
			if not g.complete_stage(i, out).ok:
				r.problems.append("complete_stage failed on stage %d" % i)
				break
			r.battles += 1
			r.attempts[i] = int(r.attempts.get(i, 0)) + 1
			if not fought.has(i):
				fought[i] = true
				r.sessions[i] = int(r.sessions.get(i, 0)) + 1
			if out.victory:
				losses = 0
				_upgrade(g)
			else:
				losses += 1
				_upgrade(g)
		if g.cleared_count() > before:
			wait = 0
		if g.cleared_count() < target:
			g.dev_skip_time(WAIT_H * HOUR)
			r.hours += WAIT_H
			wait += WAIT_H
			r.longest_wait_h = maxi(int(r.longest_wait_h), wait)
	r.cleared = g.cleared_count()
	g.free()
	return r


## Everything a player does between fights.
func _session(g: Node, spend_gems: bool, r: Dictionary) -> void:
	g.claim_idle()
	if int(g.idle_status().quick_claim_cost) == 0 and not g.quick_claim().ok:
		r.problems.append("free quick claim failed")
	if g.free_pull_available() and not g.summon(1, true).ok:
		r.problems.append("free pull failed")
	while g.currency("scrolls") >= 10:
		g.summon(10)
	while g.currency("scrolls") >= 1:
		g.summon(1)
	if spend_gems:
		while g.currency("gems") >= int(g.banner().cost_ten):
			g.summon(10)
		while g.currency("gems") >= int(g.banner().cost_one):
			g.summon(1)
	_upgrade(g)


func _upgrade(g: Node) -> void:
	_claim_quests(g)
	g.auto_formation()
	for id in g.formation():
		if id != "" and g.can_star_up(id):
			g.star_up(id)
	_level_team(g)
	_claim_quests(g)


## Raise the lowest formation hero one level at a time while resources last.
func _level_team(g: Node) -> void:
	for guard in 2000:
		var low := ""
		var low_lv := 1 << 30
		for id in g.formation():
			if id != "" and int(g.hero(id).level) < low_lv and not g.level_up_cost(id).is_empty():
				low = id
				low_lv = int(g.hero(id).level)
		if low == "" or not g.level_up(low).ok:
			return


func _claim_quests(g: Node) -> void:
	for q in g.quests():
		if q.ready:
			g.claim_quest(q.id)


# ------------------------------------------------------------------ tests

func test_starter_team_wins_first_stage(t: TestCtx) -> void:
	# A player who taps Battle before doing anything else should still win 1-1.
	var wins := 0
	for luck in LUCK:
		var g: Node = load("res://src/core/game.gd").new()
		g.save_path = ""
		g.tz_bias_ms = 0
		g.now_override_ms = START_MS + luck
		g.new_game()
		t.eq(g.owned_heroes().size(), 3, "three starters")
		t.eq(g.formation().count(""), 2, "starters fill three slots")
		var out: Dictionary = BattleSim.new(g.stage_battle_setup(0)).run_to_end()
		if out.victory:
			wins += 1
		t.ok(int(out.duration_ms) <= 60000, "1-1 is a short fight (%d ms)" % int(out.duration_ms))
		g.free()
	t.eq(wins, LUCK.size(), "starters win 1-1 every time")


func test_chapter_one_within_two_days(t: TestCtx) -> void:
	for luck in LUCK:
		var r := play(luck, CHAPTER_1, 72)
		var tag := "luck %d: %s" % [luck, str(r)]
		t.eq((r.problems as Array).size(), 0, "API calls worked. " + tag)
		t.eq(int(r.cleared), CHAPTER_1, "chapter 1 cleared. " + tag)
		t.ok(int(r.hours) <= 48, "chapter 1 within ~2 days of play. " + tag)
		t.ok(int(r.longest_wait_h) <= 12, "never stuck for more than 12 h. " + tag)
		# Opening stages: won at the first try.
		for i in 3:
			t.eq(int(r.attempts.get(i, 99)), 1, "stage 1-%d at the first try. %s" % [i + 1, tag])
		# No chapter 1 stage blocks a player for more than three check-ins.
		for i in CHAPTER_1:
			t.ok(int(r.sessions.get(i, 99)) <= 3, "stage 1-%d within 3 sessions. %s" % [i + 1, tag])
			t.ok(int(r.attempts.get(i, 99)) <= 3 * RETRIES_PER_SESSION, "stage 1-%d: few retries. %s" % [i + 1, tag])


func test_first_session_progress(t: TestCtx) -> void:
	# The first sitting (no waiting) should clear a handful of stages: enough to feel progress,
	# not the whole chapter.
	for luck in LUCK:
		var r := play(luck, CHAPTER_1, 0)
		var tag := "luck %d: %s" % [luck, str(r)]
		t.ok(int(r.cleared) >= 4, "first session clears at least 1-4. " + tag)
		t.ok(int(r.cleared) < CHAPTER_1, "first session does not finish chapter 1. " + tag)


func test_cautious_player_not_stuck(t: TestCtx) -> void:
	# Spends no gems on summons (free pull and scrolls only): slower, but never walled.
	for luck in LUCK.slice(0, 3):
		var r := play(luck, CHAPTER_1, 120, false)
		var tag := "luck %d: %s" % [luck, str(r)]
		t.eq(int(r.cleared), CHAPTER_1, "cautious player clears chapter 1. " + tag)
		t.ok(int(r.hours) <= 72, "cautious player: chapter 1 within 3 days. " + tag)
		t.ok(int(r.longest_wait_h) <= 18, "cautious player never stuck for more than 18 h. " + tag)
