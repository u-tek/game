extends RefCounted
## BattleSim: determinism, faction rules, ultimates, statuses, limits and speed.


func _unit(uid: String, hero_id: String, slot: int, level: int = 10, stars: int = 1, extra: Dictionary = {}) -> Dictionary:
	var u := {"uid": uid, "hero_id": hero_id, "slot": slot, "level": level, "stars": stars,
		"stats": StatCalc.stats(hero_id, level, stars), "is_boss": false}
	u.merge(extra, true)
	return u


func _team_setup(seed_value: int) -> Dictionary:
	return {
		"seed": seed_value,
		"allies": [_unit("a0", "brakka", 0, 12, 3), _unit("a1", "uriela", 1, 12, 3), _unit("a2", "liora", 2, 12, 3),
			_unit("a3", "vesper", 3, 12, 3), _unit("a4", "kessa", 4, 12, 3)],
		"enemies": [_unit("e0", "orrin", 0, 12, 3), _unit("e1", "lucen", 1, 12, 3), _unit("e2", "sable", 2, 12, 3),
			_unit("e3", "ashra", 3, 12, 3), _unit("e4", "noctaire", 4, 12, 3)],
	}


func _run_events(setup: Dictionary) -> Array:
	var sim := BattleSim.new(setup)
	var all: Array = []
	while not sim.is_over():
		all.append_array(sim.step())
	return all


func test_same_seed_same_events(t: TestCtx) -> void:
	var a := _run_events(_team_setup(1234))
	var b := _run_events(_team_setup(1234))
	t.ok(a.size() > 50, "battle produced events")
	t.eq(JSON.stringify(a), JSON.stringify(b), "same seed must replay identically")
	var c := _run_events(_team_setup(98765))
	t.ok(JSON.stringify(a) != JSON.stringify(c), "different seed should change the battle")


func test_run_to_end_matches_stepping(t: TestCtx) -> void:
	var s1 := BattleSim.new(_team_setup(42))
	while not s1.is_over():
		s1.step()
	var s2 := BattleSim.new(_team_setup(42))
	var out2 := s2.run_to_end()
	t.eq(JSON.stringify(s1.outcome()), JSON.stringify(out2))
	t.ok(out2.winner == "ally" or out2.winner == "enemy")
	t.eq(out2.victory, out2.winner == "ally")


## Skip (run_to_end builds no events) must land on exactly the same battle as watching it,
## including from the middle of a battle.
func test_skip_matches_watching(t: TestCtx) -> void:
	for seed_value in [42, 7, 1001]:
		var watched := BattleSim.new(_team_setup(seed_value))
		while not watched.is_over():
			watched.step()
		var skipped := BattleSim.new(_team_setup(seed_value))
		for i in 120:
			skipped.step()
		var out := skipped.run_to_end()
		t.eq(JSON.stringify(out), JSON.stringify(watched.outcome()), "outcome (seed %d)" % seed_value)
		for i in watched.units.size():
			var a: Dictionary = watched.units[i]
			var b: Dictionary = skipped.units[i]
			for k in ["hp", "shield", "energy", "alive", "statuses"]:
				t.eq(b[k], a[k], "%s.%s after skip (seed %d)" % [a.uid, k, seed_value])
		t.eq(skipped.step(), [], "a finished battle produces no events")


func test_event_shapes(t: TestCtx) -> void:
	var evs := _run_events(_team_setup(7))
	var need := {
		"attack": ["src", "target"],
		"damage": ["src", "target", "amount", "crit", "advantage", "from_ultimate", "hp_after", "shield_after"],
		"heal": ["src", "target", "amount", "hp_after"],
		"shield": ["src", "target", "amount", "shield_after"],
		"status": ["src", "target", "status", "duration_ms"],
		"ultimate": ["src", "skill_id", "skill_name", "targets"],
		"energy": ["unit", "energy"],
		"death": ["unit"],
		"end": ["winner"],
	}
	var seen := {}
	var last_t := 0
	for e in evs:
		t.ok(e.has("t") and e.has("type"), "event has t and type")
		t.ok(int(e.t) >= last_t, "events are in time order")
		last_t = int(e.t)
		seen[e.type] = true
		for k in need.get(e.type, []):
			if not e.has(k):
				t.ok(false, "%s event missing %s" % [e.type, k])
				return
	for k in ["attack", "damage", "ultimate", "energy", "death", "end"]:
		t.ok(seen.has(k), "saw %s events" % k)
	t.eq(evs.back().type, "end", "end is the last event")


func test_faction_advantage_plus_20(t: TestCtx) -> void:
	# Same stats on both targets; only the faction differs (Kessa infernal vs Nuriel celestial).
	var dummy_stats := {"hp": 999999, "atk": 1, "def": 50, "spd": 1, "crit": 0}
	var atk_stats := {"hp": 5000, "atk": 200, "def": 50, "spd": 100, "crit": 0}
	var dmg := {}
	for target in ["kessa", "nuriel"]:
		var setup := {"seed": 5,
			"allies": [{"uid": "a0", "hero_id": "uriela", "slot": 0, "stars": 1, "stats": atk_stats}],
			"enemies": [{"uid": "e0", "hero_id": target, "slot": 0, "stars": 1, "stats": dummy_stats}]}
		var sim := BattleSim.new(setup)
		sim.auto_ultimates = false
		var total := 0
		var adv := false
		for i in 60:
			for e in sim.step():
				if e.type == "damage" and e.src == "a0":
					total += int(e.amount)
					adv = adv or bool(e.advantage)
		dmg[target] = total
		t.eq(adv, target == "kessa", "advantage flag vs %s" % target)
	t.ok(int(dmg.nuriel) > 0)
	t.near(float(dmg.kessa) / float(dmg.nuriel), 1.2, 0.02, "celestial deals +20% to infernal")


func test_counter_wheel(t: TestCtx) -> void:
	t.eq(BattleSim.BEATS.celestial, "infernal")
	t.eq(BattleSim.BEATS.infernal, "fallen")
	t.eq(BattleSim.BEATS.fallen, "celestial")


func test_faction_team_bonus(t: TestCtx) -> void:
	var allies := [_unit("a0", "cassiel", 0), _unit("a1", "uriela", 1), _unit("a2", "liora", 2)]
	var sim := BattleSim.new({"seed": 1, "allies": allies, "enemies": [_unit("e0", "kessa", 0)]})
	var fb := sim.faction_bonus("ally")
	t.eq(fb.get("faction", ""), "celestial")
	t.eq(int(fb.get("bonus_bp", 0)), 600, "3 of a faction = +6%")
	var base_hp: int = int(allies[1].stats.hp)
	t.eq(int(sim.unit("a1").max_hp), base_hp * 10600 / 10000)
	t.eq(sim.faction_bonus("enemy"), {})


func test_boss_multiplier(t: TestCtx) -> void:
	var boss := _unit("e0", "cassiel", 0, 10, 2, {"is_boss": true})
	var sim := BattleSim.new({"seed": 1, "allies": [_unit("a0", "kessa", 0)], "enemies": [boss, _unit("e1", "kessa", 1)]})
	t.eq(int(sim.unit("e0").max_hp), int(boss.stats.hp) * BattleSim.BOSS_HP_BP / 10000)
	t.ok(sim.unit("e0").is_boss)


func test_timeout_is_defeat(t: TestCtx) -> void:
	var setup := _team_setup(3)
	setup["max_ms"] = 2000
	var sim := BattleSim.new(setup)
	var out := sim.run_to_end()
	t.eq(out.winner, "enemy")
	t.eq(out.victory, false)
	t.ok(out.timeout, "timeout flagged")
	t.eq(out.duration_ms, 2000)


func test_default_limit_is_90s(t: TestCtx) -> void:
	t.eq(BattleSim.MAX_MS, 90000)
	t.eq(BattleSim.TICK_MS, 100)
	var sim := BattleSim.new(_team_setup(3))
	sim.step()
	t.eq(sim.t_ms, 100)


func test_front_row_first_and_assassins_dive(t: TestCtx) -> void:
	var enemies := [_unit("e0", "cassiel", 0), _unit("e1", "orrin", 1), _unit("e2", "liora", 2), _unit("e3", "sable", 3)]
	var sim := BattleSim.new({"seed": 9, "allies": [_unit("a0", "uriela", 0), _unit("a2", "kessa", 2)], "enemies": enemies})
	sim.auto_ultimates = false
	var striker_targets := {}
	var assassin_targets := {}
	for i in 30:
		for e in sim.step():
			if e.type == "attack" and e.src == "a0":
				striker_targets[e.target] = true
			if e.type == "attack" and e.src == "a2":
				assassin_targets[e.target] = true
	t.ok(striker_targets.has("e0") and not striker_targets.has("e2") and not striker_targets.has("e3"), "striker hits front row: %s" % [striker_targets])
	t.ok(not assassin_targets.has("e0") and not assassin_targets.has("e1"), "assassin hits back row: %s" % [assassin_targets])


func test_manual_ultimate_and_auto_flag(t: TestCtx) -> void:
	var sim := BattleSim.new(_team_setup(11))
	sim.auto_ultimates = false
	t.eq(sim.request_ultimate("a1"), false, "no energy yet")
	t.eq(sim.request_ultimate("e1"), false, "cannot fire enemy ults")
	var a1: Dictionary = sim.unit("a1")
	# Allies with auto off keep full energy until asked.
	var saw_full := false
	for i in 200:
		for e in sim.step():
			if e.type == "ultimate" and str(e.src).begins_with("a"):
				t.ok(false, "ally fired without request")
		if sim.can_ultimate("a1"):
			saw_full = true
			break
	t.ok(saw_full, "ally energy filled up")
	t.ok(sim.request_ultimate("a1"), "request accepted")
	t.eq(sim.request_ultimate("a1"), false, "already queued")
	var fired := false
	for e in sim.step():
		if e.type == "ultimate" and e.src == "a1":
			fired = true
			t.eq(e.skill_id, "sunlance")
	t.ok(fired, "manual ultimate fired on next step")
	t.eq(int(a1.energy) < BattleSim.ENERGY_MAX, true, "energy spent")


## Every hero's ultimate fires and produces the effect events its kit describes.
func test_every_ultimate_is_implemented(t: TestCtx) -> void:
	var ult_ids := {}
	for h in HeroData.all():
		var kit := HeroKits.get_kit(h.id)
		ult_ids[kit.ultimate.id] = true
		var allies := [_unit("a0", "cassiel", 0, 20, 2), _unit("a2", h.id, 2, 20, 3), _unit("a3", "liora", 3, 20, 2)]
		var enemies := [_unit("e0", "orrin", 0, 20, 2), _unit("e1", "brakka", 1, 20, 2), _unit("e2", "ashra", 2, 20, 2),
			_unit("e3", "imra", 3, 20, 2)]
		var sim := BattleSim.new({"seed": 21, "allies": allies, "enemies": enemies})
		sim.auto_ultimates = false
		# Wound everyone a little so heals show up.
		for u in sim.units:
			u.hp = int(u.max_hp) * 6 / 10
		var caster: Dictionary = sim.unit("a2")
		caster.energy = BattleSim.ENERGY_MAX
		t.ok(sim.request_ultimate("a2"), "%s can request" % h.id)
		var types := {}
		var ult_ev := {}
		for e in sim.step():
			if e.type == "ultimate" and e.src == "a2":
				ult_ev = e
			elif not ult_ev.is_empty() and e.get("src", "") == "a2":
				types[e.type] = true
				if e.type == "status":
					types["status:" + str(e.status)] = true
		t.eq(ult_ev.get("skill_id", ""), kit.ultimate.id, "%s ultimate event" % h.id)
		t.ok(not ult_ev.get("targets", []).is_empty(), "%s ultimate has targets" % h.id)
		for eff in kit.ultimate.effects:
			var want: String = eff.type
			if want == "energy":
				continue
			if want == "status":
				want = "status:" + str(eff.status)
			t.ok(types.has(want), "%s ultimate produced %s (got %s)" % [h.id, want, types.keys()])
	t.eq(ult_ids.size(), 40, "40 distinct ultimates")


func test_stun_burn_and_expiry(t: TestCtx) -> void:
	var sim := BattleSim.new({"seed": 2, "allies": [_unit("a2", "seraphiel", 2, 20, 3), _unit("a3", "vesper", 3, 20, 2)],
		"enemies": [_unit("e0", "brakka", 0, 20, 2), _unit("e1", "orrin", 1, 20, 2)]})
	sim.auto_ultimates = false
	sim.unit("a2").energy = BattleSim.ENERGY_MAX
	sim.unit("a3").energy = BattleSim.ENERGY_MAX
	sim.request_ultimate("a2")
	sim.request_ultimate("a3")
	sim.step()
	var e0: Dictionary = sim.unit("e0")
	t.ok(e0.statuses.has("stun"), "stunned")
	t.ok(e0.statuses.has("burn"), "burning")
	var burn_ticks := 0
	var attacked_while_stunned := false
	for i in 16:
		for e in sim.step():
			if e.type == "damage" and e.get("dot", false) and e.target == "e0":
				burn_ticks += 1
			if e.type == "attack" and e.src == "e0" and sim.t_ms <= 1500:
				attacked_while_stunned = true
	t.ok(not attacked_while_stunned, "stunned unit does not attack")
	t.ok(not e0.statuses.has("stun"), "stun expired after 1.5 s")
	t.ok(burn_ticks >= 1, "burn ticks deal damage")
	for i in 60:
		sim.step()
	t.ok(not e0.statuses.has("burn") or not e0.alive, "burn expired")


func test_execute_and_taunt(t: TestCtx) -> void:
	var sim := BattleSim.new({"seed": 4, "allies": [_unit("a0", "brakka", 0, 30, 3), _unit("a2", "kessa", 2, 30, 3)],
		"enemies": [_unit("e0", "uriela", 0, 10, 1), _unit("e2", "ashra", 2, 10, 1), _unit("e3", "lucen", 3, 10, 1)]})
	sim.auto_ultimates = false
	var e2: Dictionary = sim.unit("e2")
	e2.hp = int(e2.max_hp) * 3 / 10
	sim.unit("a2").energy = BattleSim.ENERGY_MAX
	sim.unit("a0").energy = BattleSim.ENERGY_MAX
	sim.request_ultimate("a2")
	sim.request_ultimate("a0")
	var executed := false
	for e in sim.step():
		if e.type == "damage" and e.get("execute", false):
			executed = true
	t.ok(executed or not e2.alive, "Kessa finished the weak target")
	t.ok(sim.unit("a0").statuses.has("taunt"), "Brakka taunts")
	t.ok(int(sim.unit("a0").shield) > 0, "Brakka shielded")
	var others := 0
	for i in 30:
		for e in sim.step():
			if e.type == "attack" and str(e.src).begins_with("e") and e.target != "a0":
				others += 1
	t.eq(others, 0, "taunted enemies attack Brakka")


func test_passives_unlock_by_stars(t: TestCtx) -> void:
	# Noctaire 5 stars: on kill energy. Rare 1 star: no passives.
	t.eq(HeroKits.active_passives("uriela", 1).size(), 0)
	t.eq(HeroKits.active_passives("uriela", 3).size(), 1)
	t.eq(HeroKits.active_passives("uriela", 5).size(), 2)
	t.eq(HeroKits.active_passives("seraphiel", 3).size(), 1, "legendaries start with one passive")
	# Stat passives show in stats.
	var s2 := StatCalc.stats("uriela", 10, 2)
	var s3 := StatCalc.stats("uriela", 10, 3)
	t.ok(int(s3.atk) > int(s2.atk) * 112 / 100, "3-star Uriela gets +12% ATK on top of the star bonus")
	# Start-of-battle passives.
	var sim := BattleSim.new({"seed": 1, "allies": [_unit("a0", "cassiel", 0, 10, 5), _unit("a2", "nuriel", 2, 10, 5)],
		"enemies": [_unit("e0", "orrin", 0)]})
	t.ok(int(sim.unit("a0").shield) > 0, "Cassiel 5-star starts shielded")
	t.eq(int(sim.unit("a2").energy), 400, "Nuriel 5-star starts with 400 energy")


func test_ninety_second_battle_is_fast(t: TestCtx) -> void:
	# A deliberately tanky mirror that runs the full 90 s.
	var team := ["cassiel", "brakka", "liora", "sable", "imra"]
	var best := 1 << 40
	var out := {}
	for r in 5:
		var setup := {"allies": [], "enemies": [], "seed": 77 + r}
		for i in 5:
			setup.allies.append(_unit("a%d" % i, team[i], i, 30, 4))
			setup.enemies.append(_unit("e%d" % i, team[i], i, 30, 4))
		var t0 := Time.get_ticks_usec()
		out = BattleSim.new(setup).run_to_end()
		best = mini(best, Time.get_ticks_usec() - t0)
	t.eq(out.duration_ms, 90000, "the mirror lasts the full 90 s")
	t.ok(best < 50000, "90 s battle simulated in %d us (budget 50000)" % best)
