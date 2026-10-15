extends SceneTree
## Stage calibrator (tool, not a unit test). Enemy levels in stages.gd rise steadily; this
## solves each stage's hidden echo strength "pw" (basis points) so that a reference team
## needs the TARGET uniform level to win reliably:
##   stages 1-1..1-3: the 3 starter Rares, >= 90% wins
##   later stages:    "typical" team (3 starters + 2 Epics, no gear), >= 70% wins
## Prints the pw values to paste into stages.gd.
##   tools/gd --headless --path . -s tests/tools/calibrate_stages.gd [-- stages=0-9 seeds=8]

const TYPICAL := StageData.REFERENCE_TEAM
const STARTERS := StageData.STARTER_TEAM
const STARTER_STAGES := StageData.STARTER_STAGES
const TARGET := StageData.CALIBRATION_LEVEL
const PW_MIN := 3000
const PW_MAX := 30000
const PW_STEP := 250

var seeds := 8


func _init() -> void:
	var lo := 0
	var hi := 29
	for a in OS.get_cmdline_user_args():
		if a.begins_with("stages="):
			var p := a.substr(7).split("-")
			lo = int(p[0])
			hi = int(p[p.size() - 1])
		elif a.begins_with("seeds="):
			seeds = int(a.substr(6))
	var g = load("res://src/core/game.gd").new()
	g.save_path = ""
	g.now_override_ms = 1_700_000_000_000
	g.tz_bias_ms = 0
	var out: Array = []
	for i in range(lo, hi + 1):
		# Largest pw whose required level is still <= target.
		var a := PW_MIN / PW_STEP
		var b := PW_MAX / PW_STEP
		while a < b:
			var mid := (a + b + 1) / 2
			if required(g, i, mid * PW_STEP) <= TARGET[i]:
				a = mid
			else:
				b = mid - 1
		var pw := a * PW_STEP
		out.append(pw)
		print("%s lv %d: pw %d (was %d) -> needs L%d (target %d)" % [StageData.stage(i).id,
			int(StageData.STAGES[i].lv), pw, int(StageData.STAGES[i].get("pw", 10000)), required(g, i, pw), TARGET[i]])
	print("pw: ", out)
	g.free()
	quit()


## Minimum uniform level for the reference team to beat stage i with echo strength pw.
func required(g, i: int, pw: int) -> int:
	var lo := 1
	var hi := 140
	if not wins(g, i, pw, hi):
		return 999
	while lo < hi:
		var mid := (lo + hi) / 2
		if wins(g, i, pw, mid):
			hi = mid
		else:
			lo = mid + 1
	return lo


func wins(g, i: int, pw: int, plv: int) -> bool:
	g.new_game()
	g.state.heroes = {}
	var prof: Dictionary = STARTERS if i < STARTER_STAGES else TYPICAL
	for id in prof:
		g.state.heroes[id] = {"id": id, "level": plv, "stars": int(prof[id]), "shards": 0, "gear": {}}
	g.auto_formation()
	var w := 0
	var echo_bp: int = StageData.ECHO_STAT_BP * pw / 10000
	for s in seeds:
		var setup: Dictionary = g.stage_battle_setup(i)
		setup.seed = 1000 + s * 7919
		for e in setup.enemies:
			e.stats = StageData.echo_stats(e.hero_id, int(e.level), int(e.stars), echo_bp)
		if BattleSim.new(setup).run_to_end().victory:
			w += 1
	return w * 10 >= seeds * (9 if i < STARTER_STAGES else 7)
