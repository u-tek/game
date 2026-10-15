extends SceneTree

func _init() -> void:
	var g = load("res://src/core/game.gd").new()
	g.save_path = ""
	g.now_override_ms = 1_700_000_000_000
	g.tz_bias_ms = 0
	g.new_game()
	print("formation ", g.formation(), " power ", g.team_power())
	for h in g.owned_heroes():
		print(h.id, " ", g.hero_stats(h.id), " p=", g.hero_power(h.id))
	var setup: Dictionary = g.stage_battle_setup(0)
	var sim := BattleSim.new(setup)
	var t0 := Time.get_ticks_usec()
	var n := 0
	var log: Array = []
	while not sim.is_over():
		var evs := sim.step()
		n += evs.size()
		for e in evs:
			if e.type in ["ultimate", "death", "end"]:
				log.append(e)
	print("events ", n, " time_us ", Time.get_ticks_usec() - t0)
	for e in log:
		print(e)
	print(sim.outcome())
	g.free()
	quit()
