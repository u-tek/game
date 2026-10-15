extends SceneTree
## Balance report (not a unit test). Run:
##   tools/gd --headless --path . -s tests/tools/balance_report.gd [-- seeds=10 stages=0-29]
## For every stage, finds the lowest uniform hero level at which each player profile wins
## >= 70% of seeded battles, and compares it with the level the economy can afford.

const PROFILES := {
	"starters": {"uriela": 1, "lucen": 1, "kessa": 1},
	"typical": {"uriela": 1, "lucen": 1, "kessa": 1, "brakka": 2, "liora": 2},
	"day1": {"uriela": 2, "lucen": 2, "kessa": 1, "cassiel": 2, "sable": 2},
	"mid": {"uriela": 3, "lucen": 3, "kessa": 3, "brakka": 3, "liora": 3},
	"late": {"noctaire": 4, "lucen": 4, "uriela": 4, "orrin": 4, "sable": 4},
}

var seeds := 10


func _init() -> void:
	var lo := 0
	var hi := 29
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("seeds="):
			seeds = int(a.substr(6))
		elif a.begins_with("stages="):
			var p := a.substr(7).split("-")
			lo = int(p[0])
			hi = int(p[p.size() - 1])
		elif a.begins_with("profiles="):
			only = a.substr(9)
	var g = load("res://src/core/game.gd").new()
	g.save_path = ""
	g.now_override_ms = 1_700_000_000_000
	g.tz_bias_ms = 0
	var names: Array = PROFILES.keys()
	if only != "":
		names = only.split(",")
	print("stage  elv  rec_pow | afford5 afford3 | " + " | ".join(names.map(func(n): return "%-12s" % n)))
	var t0 := Time.get_ticks_msec()
	var battles := 0
	for i in range(lo, hi + 1):
		var st: Dictionary = StageData.stage(i)
		var row := "%-5s  %3d  %7d | %5d   %5d   |" % [st.id, int(st.enemies[0].level), int(st.recommended_power), afford(i, 5), afford(i, 3)]
		for pn in names:
			var res := min_level(g, PROFILES[pn], i)
			battles += int(res.battles)
			row += " L%-3d p%-6d %4.0fs |" % [res.level, res.power, res.dur / 1000.0] if res.level > 0 else " %-17s |" % "-"
		print(row)
	print("battles: %d, %.2f ms/battle" % [battles, float(Time.get_ticks_msec() - t0) / maxf(1, battles)])
	g.free()
	quit()


## Uniform level n heroes could reach with what the economy pays out before stage i,
## following the intended pacing (docs/dev/economy-v1.md): chapter 1 on day 1, chapter 2 on
## days 2-3, chapter 3 on days 4-8; ~16 h of idle claimed per day after day 1.
func afford(i: int, n: int) -> int:
	var xp: int = EconomyData.START_CURRENCIES.hero_exp
	var gold: int = EconomyData.START_CURRENCIES.gold
	for k in i:
		var r: Dictionary = StageData.stage(k).first_clear_reward
		xp += int(r.hero_exp)
		gold += int(r.gold)
	var days := 1
	if i >= 20:
		days = 3 + (i - 19 + 1) / 2
	elif i >= 10:
		days = 1 + (i - 9 + 4) / 5
	var hours := 3 + 16 * (days - 1)
	var ph := EconomyData.idle_per_hour(i)
	xp += hours * int(ph.hero_exp) + days * 3500
	gold += hours * int(ph.gold) + days * 10000
	var lv := 1
	while true:
		var c := EconomyData.level_cost(lv)
		if xp < int(c.hero_exp) * n or gold < int(c.gold) * n:
			break
		xp -= int(c.hero_exp) * n
		gold -= int(c.gold) * n
		lv += 1
	return lv


func min_level(g, prof: Dictionary, stage_i: int) -> Dictionary:
	var battles := [0]
	var lo := 1
	var hi := 140
	var best := {}
	if not wins_at(g, prof, stage_i, hi, battles).ok:
		return {"level": -1, "power": 0, "dur": 0, "battles": battles[0]}
	while lo < hi:
		var mid := (lo + hi) / 2
		var r := wins_at(g, prof, stage_i, mid, battles)
		if r.ok:
			hi = mid
		else:
			lo = mid + 1
	best = wins_at(g, prof, stage_i, lo, battles)
	return {"level": lo, "power": best.power, "dur": best.dur, "battles": battles[0]}


func wins_at(g, prof: Dictionary, stage_i: int, lv: int, battles: Array) -> Dictionary:
	setup_team(g, prof, lv)
	var wins := 0
	var dur := 0
	for s in seeds:
		var setup: Dictionary = g.stage_battle_setup(stage_i)
		setup.seed = 1000 + s * 7919
		var sim := BattleSim.new(setup)
		var out := sim.run_to_end()
		battles[0] += 1
		if out.victory:
			wins += 1
		dur += int(out.duration_ms)
	return {"ok": wins * 10 >= seeds * 7, "power": g.team_power(), "dur": dur / seeds}


func setup_team(g, prof: Dictionary, lv: int) -> void:
	g.new_game()
	g.state.heroes = {}
	for id in prof:
		g.state.heroes[id] = {"id": id, "level": 1, "stars": int(prof[id]), "shards": 0, "gear": {}}
		g.state.heroes[id].level = mini(lv, EconomyData.level_cap(maxi(int(prof[id]), 6)))
	g.auto_formation()
