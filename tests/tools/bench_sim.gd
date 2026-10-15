extends SceneTree
## Benchmark (tool): worst-case 90 s stalemate (tanks + healers on both sides), and a
## typical campaign battle. Prints best/avg microseconds per full battle.
##   tools/gd --headless --path . -s tests/tools/bench_sim.gd

const STARS := 5

func _init() -> void:
	var team := ["cassiel", "brakka", "liora", "sable", "imra"]
	var best := 1 << 40
	var total := 0
	var runs := 8
	var out := {}
	for r in runs:
		var setup := {"allies": [], "enemies": [], "seed": 77 + r}
		for i in 5:
			setup.allies.append({"uid": "a%d" % i, "hero_id": team[i], "slot": i, "level": 30, "stars": STARS})
			setup.enemies.append({"uid": "e%d" % i, "hero_id": team[i], "slot": i, "level": 30, "stars": STARS})
		var t0 := Time.get_ticks_usec()
		var sim := BattleSim.new(setup)
		while not sim.is_over():
			sim.step()
		var us := Time.get_ticks_usec() - t0
		best = mini(best, us)
		total += us
		out = sim.outcome()
	print("stalemate step loop: best %d us, avg %d us, duration %d ms, winner %s" % [best, total / runs, out.duration_ms, out.winner])
	best = 1 << 40
	total = 0
	for r in runs:
		var setup := {"allies": [], "enemies": [], "seed": 177 + r}
		for i in 5:
			setup.allies.append({"uid": "a%d" % i, "hero_id": team[i], "slot": i, "level": 30, "stars": STARS})
			setup.enemies.append({"uid": "e%d" % i, "hero_id": team[i], "slot": i, "level": 30, "stars": STARS})
		var t0 := Time.get_ticks_usec()
		BattleSim.new(setup).run_to_end()
		var us := Time.get_ticks_usec() - t0
		best = mini(best, us)
		total += us
	print("stalemate run_to_end: best %d us, avg %d us" % [best, total / runs])
	quit()
