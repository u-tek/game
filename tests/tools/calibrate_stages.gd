extends SceneTree
## Stage calibrator (tool, not a unit test). For each stage, finds the enemy level at which
## the "typical" profile (3 starter Rares + 2 Epics, no gear) needs the target uniform
## level to win >= 70% of seeded battles. Prints suggested "lv" values for stages.gd.
##   tools/gd --headless --path . -s tests/tools/calibrate_stages.gd [-- stages=0-9]

const TYPICAL := {"uriela": 1, "lucen": 1, "kessa": 1, "brakka": 2, "liora": 2}
const TARGET: Array[int] = [
	1, 1, 2, 4, 6, 8, 10, 12, 14, 17,
	19, 20, 22, 23, 25, 26, 28, 29, 31, 33,
	35, 36, 38, 40, 42, 43, 45, 47, 49, 52,
]
var seeds := 8


func _init() -> void:
	var lo := 0
	var hi := 29
	for a in OS.get_cmdline_user_args():
		if a.begins_with("stages="):
			var p := a.substr(7).split("-")
			lo = int(p[0])
			hi = int(p[p.size() - 1])
	var g = load("res://src/core/game.gd").new()
	g.save_path = ""
	g.now_override_ms = 1_700_000_000_000
	g.tz_bias_ms = 0
	var out: Array = []
	for i in range(lo, hi + 1):
		var base_lv: int = int(StageData.STAGES[i].lv)
		# Find the largest enemy level whose required player level is <= target.
		var a := 1
		var b := 90
		while a < b:
			var mid := (a + b + 1) / 2
			if required(g, i, mid) <= TARGET[i]:
				a = mid
			else:
				b = mid - 1
		var req := required(g, i, a)
		out.append(a)
		print("%s: enemy lv %d (was %d) -> typical needs L%d (target %d)" % [StageData.stage(i).id, a, base_lv, req, TARGET[i]])
	print("levels: ", out)
	g.free()
	quit()


## Minimum uniform level for TYPICAL to win >= 70% vs stage i with enemies at level elv.
func required(g, i: int, elv: int) -> int:
	var lo := 1
	var hi := 140
	if not wins(g, i, elv, hi):
		return 999
	while lo < hi:
		var mid := (lo + hi) / 2
		if wins(g, i, elv, mid):
			hi = mid
		else:
			lo = mid + 1
	return lo


func wins(g, i: int, elv: int, plv: int) -> bool:
	g.new_game()
	g.state.heroes = {}
	for id in TYPICAL:
		g.state.heroes[id] = {"id": id, "level": plv, "stars": int(TYPICAL[id]), "shards": 0, "gear": {}}
	g.auto_formation()
	var st: Dictionary = StageData.stage(i)
	var base_lv: int = int(StageData.STAGES[i].lv)
	var w := 0
	for s in seeds:
		var setup: Dictionary = g.stage_battle_setup(i)
		setup.seed = 1000 + s * 7919
		for k in setup.enemies.size():
			var e: Dictionary = setup.enemies[k]
			var lv: int = maxi(1, elv + int(st.enemies[k].level) - base_lv)
			e.level = lv
			e.stats = StatCalc.stats(e.hero_id, lv, int(e.stars))
		var sim := BattleSim.new(setup)
		if sim.run_to_end().victory:
			w += 1
	return w * 10 >= seeds * 7
