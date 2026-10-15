extends SceneTree
## Debug tool: run one stage battle and print a per-unit summary.
##   tools/gd --headless --path . -s tests/tools/inspect_battle.gd -- stage=6 plv=9 elv=2 seed=1

const TYPICAL := {"uriela": 1, "lucen": 1, "kessa": 1, "brakka": 2, "liora": 2}


func _init() -> void:
	var stage_i := 0
	var plv := 1
	var elv := -1
	var seed := 1000
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		match kv[0]:
			"stage": stage_i = int(kv[1])
			"plv": plv = int(kv[1])
			"elv": elv = int(kv[1])
			"seed": seed = int(kv[1])
	var g = load("res://src/core/game.gd").new()
	g.save_path = ""
	g.now_override_ms = 1_700_000_000_000
	g.tz_bias_ms = 0
	g.new_game()
	g.state.heroes = {}
	for id in TYPICAL:
		g.state.heroes[id] = {"id": id, "level": plv, "stars": int(TYPICAL[id]), "shards": 0, "gear": {}}
	g.auto_formation()
	var setup: Dictionary = g.stage_battle_setup(stage_i)
	setup.seed = seed
	if elv > 0:
		for e in setup.enemies:
			e.level = elv
			e.stats = StageData.echo_stats(e.hero_id, elv, int(e.stars))
	var sim := BattleSim.new(setup)
	var ults := {}
	var deaths := {}
	var counts := {}
	var t0 := Time.get_ticks_usec()
	while not sim.is_over():
		for e in sim.step():
			counts[e.type] = int(counts.get(e.type, 0)) + 1
			if e.type == "ultimate":
				ults[e.src] = int(ults.get(e.src, 0)) + 1
			if e.type == "death":
				deaths[e.unit] = e.t
	var us := Time.get_ticks_usec() - t0
	var out := sim.outcome()
	print("stage %s  winner=%s  %d ms  sim %d us  events %s" % [StageData.stage(stage_i).id, out.winner, out.duration_ms, us, counts])
	for u in sim.units:
		print("%s %-9s %-6s L%-3d hp %5d/%5d atk %4d def %4d spd %3d | dmg %6d heal %6d ults %d died %s" % [
			u.uid, u.hero_id, u.side, u.level, u.hp, u.max_hp, u.atk, u.def, u.spd,
			out.damage_dealt.get(u.uid, 0), out.healing_done.get(u.uid, 0), ults.get(u.uid, 0), deaths.get(u.uid, "-")])
	g.free()
	quit()
