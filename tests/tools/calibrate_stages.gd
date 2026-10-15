extends SceneTree
## Stage calibrator (tool, not a unit test). Solves each stage's "level", "strength_bp" and
## "recommended_power" in data/stages.json for the current kits, battle rules and economy:
##   tools/gd --headless --path . -s tests/tools/calibrate_stages.gd [-- stages=3-29 seeds=12 write]
## Prints the values; with "write" it also stores them in data/stages.json (then regenerate
## the golden fixtures: tests/tools/make_fixtures.gd). Below, lv = level, pw = strength_bp,
## rec = recommended_power.
##
## Difficulty follows the economy, not a guess. Four pacing bots (tests/tools/pacing_bot.gd:
## an efficient free player with four short sessions a day, each bot with different summon
## luck) replay TIMELINE_H, clearing each stage at its hour. Just before that hour each bot's
## formation (levels, stars, gear) is recorded. Then for every stage:
##   lv  = enemy level: the bots' level then (second lowest), never below the previous stage
##   pw  = echo strength (basis points of ECHO_STAT_BP): the largest value at which at least
##         3 of the 4 recorded teams win >= 75% of seeds and their wins average <= 55 s,
##         minus MARGIN_BP so a less efficient player is not stuck for long
##   rec = recommended power: the second weakest bot team's power then
## Stages 1-1..1-3 instead: the three starter Rares at level 1 win >= 90% in <= 30 s.
## The other first-session stages (1-4, 1-5) use every bot's team at a lower level
## (FIRST_SESSION_LEVEL: a new player may not spend all the starting EXP), and all four
## teams must win, so the first wall never depends on summon luck.

const Bot := preload("res://tests/tools/pacing_bot.gd")
const JsonPretty := preload("res://tests/tools/json_pretty.gd")

## Hour of play (0 = the first session, 9:00 on day 1; sessions at 9, 13, 19, 23) by which an
## efficient free player clears each stage. Chapter 1 on day 1, chapter 2 on days 2-4,
## chapter 3 on days 5-10.
const TIMELINE_H: Array[int] = [
	0, 0, 0, 0, 0, 4, 4, 10, 10, 14,
	24, 28, 34, 38, 48, 52, 58, 62, 72, 82,
	96, 106, 120, 130, 144, 158, 168, 182, 196, 216,
]
const LUCKS: Array[int] = [0, 11, 22, 33]
const NEED_TEAMS := 3
const FIRST_SESSION_LEVEL := {3: 6, 4: 8}
const WIN_PCT := 75
const MAX_WIN_MS := 55000
const MARGIN_BP := 9500
const STARTER_WIN_PCT := 90
const MAX_STARTER_WIN_MS := 30000
const STARTER_MARGIN := 500
const PW_MIN := 3000
const PW_MAX := 40000
const PW_STEP := 250

var seeds := 12
## snaps[stage] = Array of {allies: [UnitSetup], level, power} (one per bot)
var snaps: Array = []


func _init() -> void:
	var lo := 0
	var hi := StageData.count() - 1
	var write := false
	for a in OS.get_cmdline_user_args():
		if a == "write":
			write = true
		if a.begins_with("stages="):
			var p := a.substr(7).split("-")
			lo = int(p[0])
			hi = int(p[p.size() - 1])
		elif a.begins_with("seeds="):
			seeds = int(a.substr(6))
	record_bots()
	var g = load("res://src/core/game.gd").new()
	g.save_path = ""
	g.now_override_ms = Bot.DAY_START_MS
	g.tz_bias_ms = 0
	var prev_lv := 0
	var prev_rec := 0
	var lvs: Array = []
	var pws: Array = []
	var recs: Array = []
	for i in StageData.count():
		var raw: Dictionary = StageData.raw_stage(i)
		if i < lo or i > hi:
			lvs.append(int(raw.level))
			pws.append(int(raw.strength_bp))
			recs.append(int(raw.recommended_power))
			prev_lv = int(raw.level)
			prev_rec = int(raw.recommended_power)
			continue
		var lv: int
		var pw: int
		var rec: int
		if i < StageData.STARTER_STAGES:
			lv = int(raw.level)
			pw = solve(func(p: int) -> bool: return starters_win(g, i, lv, p)) - STARTER_MARGIN
			rec = starter_power()
		else:
			var levels: Array = snaps[i].map(func(s: Dictionary) -> int: return int(s.level))
			var powers: Array = snaps[i].map(func(s: Dictionary) -> int: return int(s.power))
			levels.sort()
			powers.sort()
			lv = maxi(prev_lv + 1, int(levels[1]))
			var need := NEED_TEAMS
			if FIRST_SESSION_LEVEL.has(i):
				lv = int(FIRST_SESSION_LEVEL[i])
				need = LUCKS.size()
				powers.sort()
			pw = solve(func(p: int) -> bool: return bots_win(i, lv, p, need)) * MARGIN_BP / 10000 / PW_STEP * PW_STEP
			rec = int(powers[0]) if FIRST_SESSION_LEVEL.has(i) else int(powers[1])
		rec = maxi(rec, prev_rec)
		prev_lv = lv
		prev_rec = rec
		lvs.append(lv)
		pws.append(pw)
		recs.append(rec)
		print("%-5s h%3d  lv %2d  pw %5d  rec %5d  (bot levels %s)" % [StageData.stage(i).id, TIMELINE_H[i], lv, pw, rec,
			snaps[i].map(func(s: Dictionary) -> int: return int(s.level))])
	print("lv: ", lvs)
	print("pw: ", pws)
	print("rec: ", recs)
	if write:
		write_stages(lvs, pws, recs)
	g.free()
	quit()


## Stores the solved values in data/stages.json (key order and everything else unchanged).
func write_stages(lvs: Array, pws: Array, recs: Array) -> void:
	var data: Dictionary = GameData.stages().duplicate(true)
	var i := 0
	for ch in data.chapters:
		for st in ch.stages:
			st.level = int(lvs[i])
			st.strength_bp = int(pws[i])
			st.recommended_power = int(recs[i])
			i += 1
	if JsonPretty.write(GameData.DIR + "stages.json", data):
		print("wrote data/stages.json; now run tests/tools/make_fixtures.gd")


## Runs every bot along the timeline and records its team just before each stage is due.
func record_bots() -> void:
	snaps = []
	for i in StageData.count():
		snaps.append([])
	for luck in LUCKS:
		var bot = Bot.new()
		bot.start(luck)
		var next := 0
		for day in 12:
			for s in Bot.SESSIONS_H.size():
				bot.goto_session(day, s)
				bot.economy(day == 0 and s == 0)
				var hnow: int = Bot.session_hour(day, s)
				while next < StageData.count() and TIMELINE_H[next] <= hnow:
					var setup: Dictionary = bot.g.stage_battle_setup(next)
					var snap := {"allies": setup.allies, "level": bot.snapshot().level, "power": bot.g.team_power()}
					if FIRST_SESSION_LEVEL.has(next):
						snap = at_level(bot.g, int(FIRST_SESSION_LEVEL[next]))
					snaps[next].append(snap)
					bot.g.complete_stage(next, {"victory": true})
					bot.level_team()
					next += 1
				if bot.g.cleared_count() > 0:
					bot.replay_for_quests()
		bot.finish()


## The bot's current formation as if every hero were at level `lv` (same stars and gear).
func at_level(g, lv: int) -> Dictionary:
	var allies: Array = []
	var power := 0
	var f: Array = g.formation()
	for slot in f.size():
		var id: String = f[slot]
		if id == "":
			continue
		var stars: int = int(g.hero(id).stars)
		var st := StatCalc.stats(id, mini(lv, g.max_level(id)), stars, g.model.equipped_items(id))
		power += StatCalc.power(st)
		allies.append({"uid": "a%d" % slot, "hero_id": id, "side": "ally", "slot": slot, "level": lv,
			"stars": stars, "stats": st, "is_boss": false})
	return {"allies": allies, "level": lv, "power": power}


## Largest pw (multiple of PW_STEP) for which ok(pw) holds (ok must get harder as pw grows).
func solve(ok: Callable) -> int:
	var a := PW_MIN / PW_STEP
	var b := PW_MAX / PW_STEP
	if not ok.call(a * PW_STEP):
		return PW_MIN
	while a < b:
		var mid := (a + b + 1) / 2
		if ok.call(mid * PW_STEP):
			a = mid
		else:
			b = mid - 1
	return a * PW_STEP


func enemies(i: int, lv: int, pw: int) -> Array:
	var out: Array = []
	var echo_bp: int = StageData.ECHO_STAT_BP * pw / 10000
	for e in StageData.stage(i).enemies:
		out.append({"uid": "e%d" % int(e.slot), "hero_id": e.hero_id, "side": "enemy", "slot": int(e.slot),
			"level": lv, "stars": int(e.stars), "is_boss": bool(e.is_boss),
			"stats": StageData.echo_stats(e.hero_id, lv, int(e.stars), echo_bp)})
	return out


## Wins >= pct% of seeds, and the wins average <= max_ms.
func team_wins(allies: Array, foes: Array, pct: int, max_ms: int) -> bool:
	var w := 0
	var win_ms := 0
	for s in seeds:
		var out := BattleSim.new({"allies": allies, "enemies": foes, "seed": 1000 + s * 7919}).run_to_end()
		if out.victory:
			w += 1
			win_ms += int(out.duration_ms)
	return w > 0 and win_ms / w <= max_ms and w * 100 >= seeds * pct


func bots_win(i: int, lv: int, pw: int, need: int) -> bool:
	var foes := enemies(i, lv, pw)
	var ok := 0
	for s in snaps[i]:
		if team_wins(s.allies, foes, WIN_PCT, MAX_WIN_MS):
			ok += 1
	return ok >= need


func starter_allies() -> Array:
	var out: Array = []
	var slot_of := {"uriela": 0, "lucen": 1, "kessa": 2}
	for id in StageData.STARTER_TEAM:
		out.append({"uid": "a%d" % slot_of[id], "hero_id": id, "side": "ally", "slot": slot_of[id], "level": 1,
			"stars": int(StageData.STARTER_TEAM[id]), "stats": StatCalc.stats(id, 1, int(StageData.STARTER_TEAM[id])),
			"is_boss": false})
	return out


func starter_power() -> int:
	var total := 0
	for id in StageData.STARTER_TEAM:
		total += StatCalc.power(StatCalc.stats(id, 1, int(StageData.STARTER_TEAM[id])))
	return total


func starters_win(_g, i: int, lv: int, pw: int) -> bool:
	return team_wins(starter_allies(), enemies(i, lv, pw), STARTER_WIN_PCT, MAX_STARTER_WIN_MS)
