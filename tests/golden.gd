extends RefCounted
## Golden fixtures: data/fixtures/<name>.json hold rule inputs and the exact outputs the rules
## produce. A port (Unity/C#) replays the inputs and must match every output; the Godot build
## checks itself the same way (tests/unit/test_fixtures.gd). Format and meaning of every file:
## docs/dev/unity-port.md section 6.
##
##   build(name)            fixture with this file's inputs and freshly computed outputs
##                          (tests/tools/make_fixtures.gd writes it)
##   compute(name, stored)  recomputes every output from the inputs stored in a fixture
##
## Outputs are compared as JSON values: objects by key (order-free), arrays in order.

const FILES: Array[String] = ["rng", "progression", "idle", "gear", "stats", "summon", "battles", "session", "save", "prints", "rival", "war"]
const REGENERATE := "tools/gd --headless --path . -s tests/tools/make_fixtures.gd"
## Fixed clock for model-driven fixtures: 2023-12-09 01:00 UTC.
const BASE_MS := 1_702_083_600_000
const HOUR := 3600000
const DAY := 86400000


static func build(name: String) -> Dictionary:
	return compute(name, inputs(name))


static func compute(name: String, f: Dictionary) -> Dictionary:
	var out: Dictionary
	match name:
		"rng": out = _rng(f)
		"progression": out = _progression(f)
		"idle": out = _idle(f)
		"gear": out = _gear(f)
		"stats": out = _stats(f)
		"summon": out = _summon(f)
		"battles": out = _battles(f)
		"session": out = _session(f)
		"save": out = _save(f)
		"prints": out = _prints(f)
		"rival": out = _rival(f)
		"war": out = _war(f)
		_: return {}
	var head := {"version": 1, "about": str(f.get("about", "")), "regenerate": REGENERATE}
	head.merge(out)
	return head


## Normalizes any value to what JSON would give back (ints stay ints).
static func normalize(v: Variant) -> Variant:
	return GameData.intify(JSON.parse_string(JSON.stringify(v, "", false)))


## "" when equal, else the path and values of the first difference.
static func diff(a: Variant, b: Variant, path: String = "") -> String:
	if typeof(a) != typeof(b):
		return "%s: %s vs %s" % [path, _short(a), _short(b)]
	if a is Dictionary:
		for k in a:
			if not b.has(k):
				return "%s/%s: missing in actual" % [path, k]
			var d := diff(a[k], b[k], "%s/%s" % [path, k])
			if d != "":
				return d
		for k in b:
			if not a.has(k):
				return "%s/%s: unexpected key" % [path, k]
		return ""
	if a is Array:
		for i in mini(a.size(), b.size()):
			var d := diff(a[i], b[i], "%s/%d" % [path, i])
			if d != "":
				return d
		if a.size() != b.size():
			return "%s: %d items vs %d" % [path, a.size(), b.size()]
		return ""
	return "" if a == b else "%s: expected %s, got %s" % [path, _short(a), _short(b)]


static func _short(v: Variant) -> String:
	var s := JSON.stringify(v)
	return s if s.length() <= 120 else s.left(117) + "..."


# =============================================================== inputs

static func inputs(name: String) -> Dictionary:
	match name:
		"rng":
			var seqs: Array = []
			for s in [12345, 0, 1, -1, 2147483647, 1099511627776, -123456789]:
				seqs.append({"seed": s})
			var mixes: Array = []
			for ab in [[0, 0], [12345, 0x2545F491], [-5, 7], [1099511627779, -9], [1702083600000 & 0x7FFFFFFF, 7919], [99, 120]]:
				mixes.append({"a": ab[0], "b": ab[1]})
			return {
				"about": "SeededRng (src/core/rng.gd): next_u32 sequences after seeding, mix(a, b), and the helpers. range_int/chance_bp/pick list successive results from one generator.",
				"sequences": seqs,
				"mix": mixes,
				"range_int": [{"seed": 99, "lo": 0, "hi": 9999}, {"seed": 99, "lo": 90, "hi": 110}, {"seed": 5, "lo": 3, "hi": 3}],
				"chance_bp": [{"seed": 7, "bp": 2500}, {"seed": 7, "bp": 0}, {"seed": 7, "bp": 10000}],
				"pick": [{"seed": 3, "size": 4}, {"seed": 3, "size": 15}],
			}
		"progression":
			var star_cases: Array = []
			for c in [[1, 0, "rare"], [1, 4, "rare"], [2, 25, "epic"], [3, 10, "legendary"], [5, 0, "legendary"], [6, 50, "rare"]]:
				star_cases.append({"stars": c[0], "shards_have": c[1], "rarity": c[2]})
			var add_cases: Array = []
			for c in [[1, 0, 10, "rare"], [5, 90, 40, "legendary"], [6, 0, 20, "epic"], [4, 150, 20, "epic"]]:
				add_cases.append({"stars": c[0], "shards_have": c[1], "n": c[2], "rarity": c[3]})
			# With an awakening tier: a Legendary keeps what her awakenings can still use.
			for c in [[6, 0, 40, "legendary", 0], [6, 330, 40, "legendary", 1], [6, 270, 40, "legendary", 2],
					[6, 0, 40, "legendary", 3], [6, 0, 20, "epic", 0], [3, 500, 120, "legendary", 0]]:
				add_cases.append({"stars": c[0], "shards_have": c[1], "n": c[2], "rarity": c[3], "awaken": c[4]})
			var aw_cases: Array = []
			for c in [[6, 0, 100, "legendary"], [6, 1, 20, "legendary"], [6, 2, 0, "legendary"], [6, 3, 500, "legendary"],
					[5, 0, 200, "legendary"], [6, 0, 50, "epic"], [6, 0, 50, "rare"]]:
				aw_cases.append({"stars": c[0], "awaken": c[1], "shards_have": c[2], "rarity": c[3]})
			var afford: Array = []
			for c in [[1, 40, 4000, 2400], [1, 40, 0, 99999], [35, 40, 10 ** 7, 10 ** 7], [20, 60, 50000, 30000]]:
				afford.append({"level": c[0], "cap": c[1], "gold": c[2], "hero_exp": c[3]})
			return {
				"about": "Progression (src/core/progression.gd): level costs (level -> level + 1), caps, star shards, star-up costs, shards to dust (add_shards with an optional awaken tier, default 0), affordable levels, awakening costs and the awakening stat bonus by tier.",
				"level_cost": range(1, 140).map(func(l: int) -> Dictionary: return {"level": l}),
				"level_cap": range(0, 8).map(func(s: int) -> Dictionary: return {"stars": s}),
				"star_shards": range(0, 8).map(func(s: int) -> Dictionary: return {"stars": s}),
				"star_up_cost": star_cases,
				"add_shards": add_cases,
				"affordable_levels": afford,
				"awaken_cost": aw_cases,
				"awaken_stat_bp": range(0, 5).map(func(a: int) -> Dictionary: return {"awaken": a}),
			}
		"idle":
			var accrue: Array = []
			for c in [[3 * HOUR, 0, {}, 0], [12 * HOUR, 12, {}, 0], [600000, 5, {"gold": 1800000, "dust": 3599999}, 10000000],
					[1, 30, {}, 0], [43200000, 30, {"gems": 100}, 10799999]]:
				accrue.append({"elapsed_ms": c[0], "cleared": c[1], "carry": c[2], "gear_ms": c[3]})
			return {
				"about": "IdleRules (src/core/idle_rules.gd): income per hour by stages cleared, accrual with carry and gear timer, the elapsed cap, quick claims.",
				"per_hour": [0, 1, 9, 10, 15, 29, 30].map(func(c: int) -> Dictionary: return {"cleared": c}),
				"elapsed": [[BASE_MS + HOUR, BASE_MS], [BASE_MS + 30 * HOUR, BASE_MS], [BASE_MS - 5, BASE_MS]].map(
					func(c: Array) -> Dictionary: return {"now_ms": c[0], "last_claim_at": c[1]}),
				"accrue": accrue,
				"quick_claim": range(0, 6).map(func(u: int) -> Dictionary: return {"used": u}),
				"quick_reward": [[0, 0], [12, 9000000], [30, 10799999]].map(
					func(c: Array) -> Dictionary: return {"cleared": c[0], "gear_ms": c[1]}),
			}
		"gear":
			var items: Array = []
			var seq := 1
			for slot in ["weapon", "armor", "helm", "charm", "boots"]:
				for tier in [1, 3, 5, 9]:
					items.append({"slot": slot, "tier": tier, "rng_seed": 104729 + seq * 31, "seq": seq})
					seq += 1
			return {
				"about": "GearRules (src/core/gear_rules.gd): drop tier by stages cleared, random drop slots, item creation (stats rolled, name), salvage value.",
				"tier_for": range(0, 36, 3).map(func(c: int) -> Dictionary: return {"cleared": c}),
				"random_slot": range(0, 12).map(func(q: int) -> Dictionary: return {"rng_seed": 555555, "gear_seq": q}),
				"make_item": items,
				"salvage": range(1, 6).map(func(t: int) -> Dictionary: return {"tier": t}),
			}
		"stats":
			var cases: Array = []
			var gear_sets := [[], [{"stats": {"atk": 30}}, {"stats": {"hp": 500, "def": 15}}],
				[{"stats": {"crit": 800, "spd": 8, "atk": 22}}, {"stats": {"hp": 1700, "def": 48}}]]
			var i := 0
			for h in HeroData.all():
				for ls in [[1, 1], [20, 3], [60, 5], [140, 6]]:
					cases.append({"hero_id": h.id, "level": ls[0], "stars": ls[1], "gear": gear_sets[i % 3]})
					i += 1
			# Awakened Legendaries (awaken tier: stat bonus, legend passive stats).
			for h in HeroData.all():
				if str(h.rarity) != "legendary":
					continue
				for a in [1, 2, 3]:
					cases.append({"hero_id": h.id, "level": 100 + a * 10, "stars": 6, "gear": gear_sets[i % 3], "awaken": a})
					i += 1
			var scores: Array = []
			for st in [{"atk": 140}, {"hp": 2190, "def": 66}, {"crit": 1500, "spd": 15, "atk": 52}, {}]:
				scores.append({"stats": st})
			return {
				"about": "StatCalc (src/core/stat_calc.gd): hero stats (level, stars, gear, stat passives; awaken when given, default 0), power, gear score; every campaign stage's enemies as built from data/stages.json, with echo stats and enemy power; and sample Spire floors built by TowerData (src/data/tower.gd) from data/tower.json.",
				"hero_stats": cases,
				"gear_score": scores,
				"stages": range(StageData.count()).map(func(s: int) -> Dictionary: return {"index": s}),
				"tower": [1, 2, 5, 7, 10, 11, 20, 30, 59, 60, 61, 65, 80, 100, 119, 120].map(func(f: int) -> Dictionary: return {"floor": f}),
			}
		"summon":
			return {
				"about": "SummonRules.pull (src/core/summon_rules.gd) on the standard banner: each case chains summons of `counts` pulls from {seed, total_pulls, pity}; out lists the result of every summon.",
				"banner": str(EconomyData.BANNER.id),
				"rarity_for_roll": [0, 199, 200, 1999, 2000, 9999].map(func(r: int) -> Dictionary: return {"roll": r}),
				"cases": [
					{"name": "fresh_ten_pull", "seed": 12345, "total_pulls": 0, "pity": 0, "counts": [10]},
					{"name": "pity_59_forces_legendary", "seed": 777, "total_pulls": 100, "pity": 59, "counts": [1, 1]},
					{"name": "pity_reached_inside_ten_pull", "seed": 4242, "total_pulls": 50, "pity": 55, "counts": [10]},
					{"name": "ten_pull_guarantee_upgrades_tenth", "seed": _guarantee_seed(), "total_pulls": 0, "pity": 0, "counts": [10]},
					{"name": "long_chain", "seed": 99, "total_pulls": 0, "pity": 0,
						"counts": [10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 1, 1, 1, 1, 1]},
				],
				"about_banners": "banner_cases: SummonRules.pull on the banner with this id (data/banner.json) and opts (featured + lost on the featured banner, faction on the faction banner, target on the wish banner); like cases they chain, and on the featured banner opts.lost chains from each summon's out.lost. rotation: for each day index, featured_for / faction_for, the next rotation day of both, and each limited banner's limit_period and limit_resets_day (epoch_day from banner.json).",
				"epoch_day": EconomyData.BANNER_EPOCH_DAY,
				"banner_cases": [
					{"name": "featured_long_chain", "banner": "featured", "seed": 31337, "total_pulls": 0, "pity": 0,
						"opts": {"featured": "mordessa", "lost": false}, "counts": _tens(30)},
					{"name": "featured_lost_forces_featured", "banner": "featured", "seed": 5, "total_pulls": 70, "pity": 59,
						"opts": {"featured": "noctaire", "lost": true}, "counts": [1, 10]},
					{"name": "featured_pity_rolls_the_5050", "banner": "featured", "seed": 8080, "total_pulls": 12, "pity": 59,
						"opts": {"featured": "seraphiel", "lost": false}, "counts": [1, 1, 10]},
					{"name": "faction_celestial_chain", "banner": "faction", "seed": 2024, "total_pulls": 0, "pity": 0,
						"opts": {"faction": "celestial"}, "counts": _tens(12)},
					{"name": "faction_infernal_pity", "banner": "faction", "seed": 9, "total_pulls": 300, "pity": 75,
						"opts": {"faction": "infernal"}, "counts": [10, 1]},
					{"name": "faction_fallen", "banner": "faction", "seed": 4711, "total_pulls": 3, "pity": 0,
						"opts": {"faction": "fallen"}, "counts": [10, 10, 10]},
					{"name": "wish_target_chain", "banner": "wish", "seed": 606, "total_pulls": 0, "pity": 0,
						"opts": {"target": "noctaire"}, "counts": _tens(15)},
					{"name": "wish_pity_gives_target", "banner": "wish", "seed": 17, "total_pulls": 44, "pity": 59,
						"opts": {"target": "seraphiel"}, "counts": [1, 10]},
					{"name": "envoy_no_legendary", "banner": "envoy", "seed": 1234, "total_pulls": 0, "pity": 0,
						"opts": {}, "counts": [10, 10, 10, 10, 1, 1, 1]},
				],
				"rotation": [-15, -8, -1, 0, 1, 2, 3, 6, 7, 13, 14, 20, 21, 22, 100, 365].map(func(k: int) -> Dictionary:
					return {"day": EconomyData.BANNER_EPOCH_DAY + k}),
			}
		"battles":
			return {
				"about": "BattleSim (src/core/battle_sim.gd): setup + seed -> every event of every step() in order, outcome() and the final units. inputs (optional): before step number `tick` (1 = first step), set_spotlight(uid) (kind spotlight) or set_mark(uid) (kind mark); then manual_ultimates: request_ultimate(uid); `accepted` is each call's result. Then run_to_end() on a fresh sim must give the same outcome.",
				"battles": _battle_inputs(),
			}
		"session":
			return {
				"about": "GameModel (src/core/game_model.gd) end to end: a new player's first two days. Clock starts at start_ms (tz_bias_ms 0); each step first advances the clock by advance_ms, then calls the method with args (\"battle\" = stage_battle_setup + BattleSim.run_to_end + complete_stage). results[i] holds the return value and the notifications queued by step i; final_state is the whole save state.",
				"start_ms": BASE_MS,
				"tz_bias_ms": 0,
				"steps": _session_steps(),
			}
		"save":
			return {
				"about": "GameModel.migrate (save repair): an old or damaged save (numbers as ints) at clock now_ms -> the repaired state.",
				"cases": _save_cases(),
			}
		"prints":
			return _prints_inputs()
		"rival":
			return _rival_inputs()
		"war":
			return _war_inputs()
	return {}


# =============================================================== compute

static func _rng(f: Dictionary) -> Dictionary:
	var seqs: Array = []
	for c in f.sequences:
		var rng := SeededRng.new(int(c.seed))
		var vals: Array = []
		for i in 12:
			vals.append(rng.next_u32())
		seqs.append({"seed": c.seed, "next_u32": vals})
	var mixes: Array = []
	for c in f.mix:
		mixes.append({"a": c.a, "b": c.b, "out": SeededRng.mix(int(c.a), int(c.b))})
	var ranges: Array = []
	for c in f.range_int:
		var rng := SeededRng.new(int(c.seed))
		var vals: Array = []
		for i in 10:
			vals.append(rng.range_int(int(c.lo), int(c.hi)))
		vals.append(rng.next_u32())
		ranges.append({"seed": c.seed, "lo": c.lo, "hi": c.hi, "out": vals.slice(0, 10), "next_u32_after": vals[10]})
	var chances: Array = []
	for c in f.chance_bp:
		var rng := SeededRng.new(int(c.seed))
		var vals: Array = []
		for i in 10:
			vals.append(rng.chance_bp(int(c.bp)))
		chances.append({"seed": c.seed, "bp": c.bp, "out": vals, "next_u32_after": rng.next_u32()})
	var picks: Array = []
	for c in f.pick:
		var rng := SeededRng.new(int(c.seed))
		var arr := range(int(c.size))
		var vals: Array = []
		for i in 10:
			vals.append(rng.pick(arr))
		picks.append({"seed": c.seed, "size": c.size, "out": vals})
	return {"sequences": seqs, "mix": mixes, "range_int": ranges, "chance_bp": chances, "pick": picks}


static func _progression(f: Dictionary) -> Dictionary:
	var lc: Array = []
	for c in f.level_cost:
		var cost := Progression.level_cost(int(c.level))
		lc.append({"level": c.level, "gold": cost.gold, "hero_exp": cost.hero_exp})
	var caps: Array = []
	for c in f.level_cap:
		caps.append({"stars": c.stars, "cap": Progression.level_cap(int(c.stars))})
	var shards: Array = []
	for c in f.star_shards:
		shards.append({"stars": c.stars, "next": Progression.star_shards(int(c.stars)), "to_max": Progression.shards_to_max(int(c.stars))})
	var suc: Array = []
	for c in f.star_up_cost:
		suc.append({"stars": c.stars, "shards_have": c.shards_have, "rarity": c.rarity,
			"out": Progression.star_up_cost(int(c.stars), int(c.shards_have), str(c.rarity))})
	var adds: Array = []
	for c in f.add_shards:
		var e := {"stars": c.stars, "shards_have": c.shards_have, "n": c.n, "rarity": c.rarity,
			"out": Progression.add_shards(int(c.stars), int(c.shards_have), int(c.n), str(c.rarity), int(c.get("awaken", 0)))}
		if c.has("awaken"):
			e["awaken"] = c.awaken
		adds.append(e)
	var awc: Array = []
	for c in f.get("awaken_cost", []):
		awc.append({"stars": c.stars, "awaken": c.awaken, "shards_have": c.shards_have, "rarity": c.rarity,
			"out": Progression.awaken_cost(int(c.stars), int(c.awaken), int(c.shards_have), str(c.rarity))})
	var awb: Array = []
	for c in f.get("awaken_stat_bp", []):
		awb.append({"awaken": c.awaken, "out": Progression.awaken_stat_bp(int(c.awaken))})
	var aff: Array = []
	for c in f.affordable_levels:
		aff.append({"level": c.level, "cap": c.cap, "gold": c.gold, "hero_exp": c.hero_exp,
			"out": Progression.affordable_levels(int(c.level), int(c.cap), int(c.gold), int(c.hero_exp))})
	return {"level_cost": lc, "level_cap": caps, "star_shards": shards, "star_up_cost": suc, "add_shards": adds,
		"affordable_levels": aff, "awaken_cost": awc, "awaken_stat_bp": awb}


static func _idle(f: Dictionary) -> Dictionary:
	var ph: Array = []
	for c in f.per_hour:
		ph.append({"cleared": c.cleared, "out": IdleRules.per_hour(int(c.cleared))})
	var el: Array = []
	for c in f.elapsed:
		el.append({"now_ms": c.now_ms, "last_claim_at": c.last_claim_at, "out": IdleRules.elapsed(int(c.now_ms), int(c.last_claim_at))})
	var acc: Array = []
	for c in f.accrue:
		acc.append({"elapsed_ms": c.elapsed_ms, "cleared": c.cleared, "carry": c.carry, "gear_ms": c.gear_ms,
			"out": IdleRules.accrue(int(c.elapsed_ms), IdleRules.per_hour(int(c.cleared)), c.carry, int(c.gear_ms))})
	var qc: Array = []
	for c in f.quick_claim:
		qc.append({"used": c.used, "cost": IdleRules.quick_claim_cost(int(c.used)), "left": IdleRules.quick_claims_left(int(c.used))})
	var qr: Array = []
	for c in f.quick_reward:
		qr.append({"cleared": c.cleared, "gear_ms": c.gear_ms,
			"out": IdleRules.quick_reward(IdleRules.per_hour(int(c.cleared)), int(c.gear_ms))})
	return {"per_hour": ph, "elapsed": el, "accrue": acc, "quick_claim": qc, "quick_reward": qr}


static func _gear(f: Dictionary) -> Dictionary:
	var tiers: Array = []
	for c in f.tier_for:
		tiers.append({"cleared": c.cleared, "out": GearRules.tier_for(int(c.cleared))})
	var slots: Array = []
	for c in f.random_slot:
		slots.append({"rng_seed": c.rng_seed, "gear_seq": c.gear_seq, "out": GearRules.random_slot(int(c.rng_seed), int(c.gear_seq))})
	var items: Array = []
	for c in f.make_item:
		items.append({"slot": c.slot, "tier": c.tier, "rng_seed": c.rng_seed, "seq": c.seq,
			"out": GearRules.make_item(str(c.slot), int(c.tier), int(c.rng_seed), int(c.seq))})
	var salv: Array = []
	for c in f.salvage:
		salv.append({"tier": c.tier, "out": GearRules.salvage_value(int(c.tier))})
	return {"tier_for": tiers, "random_slot": slots, "make_item": items, "salvage": salv}


static func _stats(f: Dictionary) -> Dictionary:
	var hs: Array = []
	for c in f.hero_stats:
		var st := StatCalc.stats(str(c.hero_id), int(c.level), int(c.stars), c.gear, int(c.get("awaken", 0)))
		var e := {"hero_id": c.hero_id, "level": c.level, "stars": c.stars, "gear": c.gear, "out": st,
			"power": StatCalc.power(st)}
		if c.has("awaken"):
			e["awaken"] = c.awaken
		hs.append(e)
	var gs: Array = []
	for c in f.gear_score:
		gs.append({"stats": c.stats, "out": StatCalc.gear_score({"stats": c.stats})})
	var stages: Array = []
	for c in f.stages:
		var st: Dictionary = StageData.stage(int(c.index))
		var enemies: Array = []
		for e in st.enemies:
			var en: Dictionary = e.duplicate()
			en["stats"] = StageData.echo_stats(e.hero_id, int(e.level), int(e.stars), int(e.echo_bp))
			enemies.append(en)
		stages.append({"index": c.index, "id": st.id, "enemies": enemies, "enemy_power": st.enemy_power,
			"recommended_power": st.recommended_power, "first_clear_reward": st.first_clear_reward})
	var floors: Array = []
	for c in f.get("tower", []):
		var fl: Dictionary = TowerData.get_floor(int(c.floor))
		var en2: Array = []
		for e in fl.enemies:
			var en: Dictionary = e.duplicate()
			en["stats"] = StageData.echo_stats(e.hero_id, int(e.level), int(e.stars), int(e.echo_bp))
			en2.append(en)
		floors.append({"floor": c.floor, "id": fl.id, "enemies": en2, "is_boss": fl.is_boss, "background": fl.background,
			"enemy_power": fl.enemy_power, "recommended_power": fl.recommended_power, "first_clear_reward": fl.first_clear_reward})
	return {"hero_stats": hs, "gear_score": gs, "stages": stages, "tower": floors}


static func _summon(f: Dictionary) -> Dictionary:
	var cases: Array = []
	for c in f.cases:
		var seed_value := int(c.seed)
		var total := int(c.total_pulls)
		var pity := int(c.pity)
		var outs: Array = []
		for n in c.counts:
			var r := SummonRules.pull(EconomyData.BANNER, seed_value, total, pity, int(n))
			outs.append(r)
			total = int(r.total_pulls)
			pity = int(r.pity)
		cases.append({"name": c.name, "seed": c.seed, "total_pulls": c.total_pulls, "pity": c.pity,
			"counts": c.counts, "out": outs})
	var rolls: Array = []
	for c in f.rarity_for_roll:
		rolls.append({"roll": c.roll, "out": SummonRules.rarity_for_roll(int(c.roll), EconomyData.BANNER)})
	var bcases: Array = []
	for c in f.get("banner_cases", []):
		var b := EconomyData.banner_def(str(c.banner))
		var opts: Dictionary = (c.opts as Dictionary).duplicate(true)
		var total := int(c.total_pulls)
		var pity := int(c.pity)
		var outs: Array = []
		for n in c.counts:
			var r := SummonRules.pull(b, int(c.seed), total, pity, int(n), opts)
			outs.append(r)
			total = int(r.total_pulls)
			pity = int(r.pity)
			if r.has("lost"):
				opts["lost"] = bool(r.lost)
		bcases.append({"name": c.name, "banner": c.banner, "seed": c.seed, "total_pulls": c.total_pulls, "pity": c.pity,
			"opts": c.opts, "counts": c.counts, "out": outs})
	var epoch := int(f.get("epoch_day", 0))
	var rot: Array = []
	var fb := EconomyData.banner_def("featured")
	var cb := EconomyData.banner_def("faction")
	var wb := EconomyData.banner_def("wish")
	var eb := EconomyData.banner_def("envoy")
	for c in f.get("rotation", []):
		var d := int(c.day)
		rot.append({"day": c.day, "out": {
			"featured": SummonRules.featured_for(fb, d, epoch),
			"featured_next_change": SummonRules.next_change_day(d, epoch, int(fb.rotation_days)),
			"faction": SummonRules.faction_for(cb, d, epoch),
			"faction_next_change": SummonRules.next_change_day(d, epoch, int(cb.rotation_days)),
			"wish_period": SummonRules.limit_period(wb, d, epoch),
			"wish_resets": SummonRules.limit_resets_day(wb, d, epoch),
			"envoy_period": SummonRules.limit_period(eb, d, epoch),
			"envoy_resets": SummonRules.limit_resets_day(eb, d, epoch),
		}})
	var out := {"banner": f.banner, "rarity_for_roll": rolls, "cases": cases}
	if f.has("banner_cases"):
		out.merge({"about_banners": f.about_banners, "epoch_day": f.epoch_day, "banner_cases": bcases, "rotation": rot})
	return out


static func _tens(n: int) -> Array:
	var a: Array = []
	for i in n:
		a.append(10)
	return a


## A seed whose first 10-pull (total_pulls 0, pity 0) has nine Rares and rolls a tenth Rare,
## which the guarantee upgrades to Epic.
static func _guarantee_seed() -> int:
	var b := EconomyData.BANNER
	for s in range(1, 100000):
		var rng := SeededRng.new(SeededRng.mix(s, 0))
		var pool := SummonRules.pool_by_rarity(b)
		var all_rare := true
		for i in 9:
			var rar := SummonRules.roll_rarity(rng, i, b)
			if rar != "rare":
				all_rare = false
				break
			rng.pick(pool[rar])
		if all_rare and SummonRules.roll_rarity(rng, 9, b) == "rare":
			return s
	return 1


# ---------------------------------------------------------------- battles

static func _unit(uid: String, hero_id: String, slot: int, level: int, stars: int, boss: bool = false, awaken: int = 0) -> Dictionary:
	var u := {"uid": uid, "hero_id": hero_id, "side": "ally" if uid.begins_with("a") else "enemy", "slot": slot,
		"level": level, "stars": stars, "stats": StatCalc.stats(hero_id, level, stars, [], awaken), "is_boss": boss}
	if awaken > 0:
		u["awaken"] = awaken
	return u


## spec rows: [hero_id, slot, level, stars, (is_boss), (awaken)].
static func _team(prefix: String, spec: Array) -> Array:
	var out: Array = []
	for s in spec:
		out.append(_unit("%s%d" % [prefix, s[1]], s[0], s[1], s[2], s[3], s.size() > 4 and s[4], int(s[5]) if s.size() > 5 else 0))
	return out


static func _battle_inputs() -> Array:
	var m := _new_model(BASE_MS)
	m.new_game()
	var opening: Dictionary = m.stage_battle_setup(0)
	var boss_enemies: Array = []
	for e in StageData.stage(4).enemies:
		boss_enemies.append({"uid": "e%d" % int(e.slot), "hero_id": e.hero_id, "side": "enemy", "slot": int(e.slot),
			"level": int(e.level), "stars": int(e.stars), "is_boss": bool(e.is_boss),
			"stats": StageData.echo_stats(e.hero_id, int(e.level), int(e.stars), int(e.echo_bp))})
	var out: Array = []
	out.append({"name": "opening_stage_1_1", "about": "A new player's formation (three level 1 Rares) against stage 1-1, as Game.stage_battle_setup builds it.",
		"setup": {"seed": opening.seed, "allies": opening.allies, "enemies": opening.enemies},
		"auto_ultimates": true, "manual_ultimates": []})
	out.append({"name": "boss_1_5", "about": "Stage 1-5 boss (Cassiel echo: boss multipliers, halved stuns) against a first-session team.",
		"setup": {"seed": 515, "allies": _team("a", [["brakka", 0, 9, 2], ["uriela", 1, 9, 1], ["liora", 2, 9, 2],
			["vesper", 3, 9, 2], ["kessa", 4, 9, 1]]), "enemies": boss_enemies},
		"auto_ultimates": true, "manual_ultimates": []})
	out.append({"name": "five_star_kits_a", "about": "Ten heroes at 5 stars (every passive active): infernal-leaning allies vs a fallen team.",
		"setup": {"seed": 20231209, "allies": _team("a", [["cassiel", 0, 60, 5], ["mordessa", 1, 60, 5], ["liora", 2, 60, 5],
			["imra", 3, 60, 5], ["nuriel", 4, 60, 5]]),
			"enemies": _team("e", [["orrin", 0, 60, 5], ["brakka", 1, 60, 5], ["sable", 2, 60, 5], ["ashra", 3, 60, 5],
			["vesper", 4, 60, 5]])},
		"auto_ultimates": true, "manual_ultimates": []})
	out.append({"name": "five_star_kits_b", "about": "The other five heroes at 5-6 stars (celestial faction bonus) vs a mixed team.",
		"setup": {"seed": 4711, "allies": _team("a", [["uriela", 0, 80, 5], ["lucen", 1, 80, 5], ["seraphiel", 2, 80, 5],
			["kessa", 3, 80, 5], ["noctaire", 4, 80, 6]]),
			"enemies": _team("e", [["cassiel", 0, 90, 6], ["brakka", 1, 90, 4], ["liora", 2, 90, 3], ["vesper", 3, 90, 3],
			["imra", 4, 90, 3]])},
		"auto_ultimates": true, "manual_ultimates": []})
	var manual := {"seed": 8080, "allies": _team("a", [["cassiel", 0, 52, 3], ["uriela", 1, 52, 3], ["liora", 2, 52, 3],
		["seraphiel", 3, 52, 3], ["nuriel", 4, 52, 3]]),
		"enemies": _team("e", [["brakka", 0, 44, 3, true], ["kessa", 1, 40, 3], ["vesper", 2, 40, 3], ["imra", 3, 40, 3]])}
	out.append({"name": "manual_ultimates", "about": "auto_ultimates off: allies cast only when requested (requests 3 ticks after a bar fills, plus some refused ones); enemy boss.",
		"setup": manual, "auto_ultimates": false, "manual_ultimates": _manual_requests(manual),
		# Spotlight and Mark: accepted, refused in the switch cooldown, refused when already set.
		"inputs": [{"tick": 8, "kind": "spotlight", "uid": "a0"}, {"tick": 12, "kind": "spotlight", "uid": "a2"},
			{"tick": 15, "kind": "mark", "uid": "e2"}, {"tick": 40, "kind": "spotlight", "uid": "a2"},
			{"tick": 50, "kind": "mark", "uid": "e2"}, {"tick": 60, "kind": "mark", "uid": "e3"}]})
	out.append({"name": "legends_awakened", "about": "Awakened Legendaries on both sides (UnitSetup awaken 1-3: legend passives from A1, empowered ultimates from A2).",
		"setup": {"seed": 6161, "allies": _team("a", [["argentiel", 0, 110, 6, false, 1], ["gantra", 1, 110, 6, false, 2],
			["seraphiel", 2, 110, 6, false, 2], ["sanariel", 3, 110, 6, false, 3], ["mordessa", 4, 110, 6, false, 2]]),
			"enemies": _team("e", [["drezza", 0, 120, 6, false, 2], ["zecchina", 1, 120, 6, false, 3], ["noctaire", 2, 120, 6, false, 2],
			["nadira", 3, 120, 6, false, 2], ["cassiel", 4, 120, 6]])},
		"auto_ultimates": true, "manual_ultimates": []})
	out.append({"name": "timeout", "about": "Two sturdy teams and max_ms 20000: the battle ends by timeout (a defeat).",
		"setup": {"seed": 99, "max_ms": 20000, "allies": _team("a", [["orrin", 0, 30, 4], ["cassiel", 1, 30, 4], ["sable", 2, 30, 4]]),
			"enemies": _team("e", [["brakka", 0, 30, 4], ["orrin", 1, 30, 4], ["liora", 2, 30, 4]])},
		"auto_ultimates": true, "manual_ultimates": []})
	return out


## A deterministic request list for the manual battle: each ally asks 3 ticks after it could
## cast; tick 5 asks for an ally with no energy (refused).
static func _manual_requests(setup: Dictionary) -> Array:
	var sim := BattleSim.new(setup)
	sim.auto_ultimates = false
	var ready_at := {}
	var reqs: Array = [{"tick": 5, "uid": "a1"}]
	var tick := 0
	while not sim.is_over():
		tick += 1
		for r in reqs:
			if int(r.tick) == tick:
				sim.request_ultimate(str(r.uid))
		sim.step()
		for u in sim.units:
			if u.side != "ally":
				continue
			if sim.can_ultimate(u.uid):
				if not ready_at.has(u.uid):
					ready_at[u.uid] = tick
					reqs.append({"tick": tick + 3, "uid": u.uid})
			else:
				ready_at.erase(u.uid)
	return reqs


static func _battles(f: Dictionary) -> Dictionary:
	var out: Array = []
	for b in f.battles:
		var setup: Dictionary = b.setup
		var sim := BattleSim.new(setup)
		sim.auto_ultimates = bool(b.auto_ultimates)
		var reqs: Array = []
		var ins: Array = []
		var events: Array = []
		var tick := 0
		while not sim.is_over():
			tick += 1
			for r in b.get("inputs", []):
				if int(r.tick) == tick:
					var ok := sim.set_spotlight(str(r.uid)) if str(r.kind) == "spotlight" else sim.set_mark(str(r.uid))
					ins.append({"tick": r.tick, "kind": r.kind, "uid": r.uid, "accepted": ok})
			for r in b.manual_ultimates:
				if int(r.tick) == tick:
					reqs.append({"tick": r.tick, "uid": r.uid, "accepted": sim.request_ultimate(str(r.uid))})
			events.append_array(sim.step())
		var units: Array = []
		for u in sim.units:
			units.append({"uid": u.uid, "hp": u.hp, "max_hp": u.max_hp, "shield": u.shield, "energy": u.energy,
				"alive": u.alive, "statuses": u.statuses})
		var entry := {"name": b.name, "about": b.get("about", ""), "setup": setup, "auto_ultimates": b.auto_ultimates,
			"manual_ultimates": reqs if not reqs.is_empty() else b.manual_ultimates, "steps": tick,
			"outcome": sim.outcome(), "final_units": units}
		if b.has("inputs"):
			entry["inputs"] = ins
		if b.manual_ultimates.is_empty():
			# Skip must land on the same battle as watching it.
			entry["skip_outcome"] = BattleSim.new(setup).run_to_end()
		entry["events"] = events
		out.append(entry)
	return {"battles": out}


# ---------------------------------------------------------------- GameModel sessions

static func _new_model(start_ms: int) -> GameModel:
	var m := GameModel.new()
	m.tz_bias_ms = 0
	var clock := {"now": start_ms}
	m.set_meta("clock", clock)
	m.clock = func() -> int: return int(clock.now)
	return m


static func _advance(m: GameModel, ms: int) -> void:
	var clock: Dictionary = m.get_meta("clock")
	clock.now = int(clock.now) + ms


static func _session_steps() -> Array:
	var s: Array = []
	var add := func(call: String, args: Array = [], advance_ms: int = 0) -> void:
		s.append({"advance_ms": advance_ms, "call": call, "args": args})
	add.call("new_game")
	add.call("idle_status")
	add.call("summon", [10])
	add.call("summon", [1, true])
	add.call("summon", [10])
	for i in 6:
		add.call("summon", [1])
	add.call("buy_offer", ["daily_gift"])
	add.call("auto_formation")
	add.call("formation")
	add.call("team_power")
	for i in 5:
		add.call("battle", [i])
	add.call("owned_heroes")
	add.call("level_up_many", ["uriela", 6])
	add.call("affordable_levels", ["lucen"])
	add.call("battle", [3], 60000)
	add.call("idle_status", [], 3 * HOUR)
	add.call("claim_idle")
	add.call("quick_claim")
	add.call("quick_claim")
	add.call("quests")
	for q in ["dq_summon", "dq_win", "dq_idle", "dq_quick", "dq_level"]:
		add.call("claim_quest", [q])
	add.call("gear_items")
	add.call("star_up_cost", ["uriela"])
	add.call("star_up", ["uriela"])
	add.call("set_formation", [["kessa", "uriela", "lucen", "", ""]])
	add.call("faction_bonus")
	add.call("auto_formation")
	add.call("faction_bonus")
	for i in 4:
		add.call("battle", [3 + i], 0)
	add.call("claim_idle", [], 5 * HOUR)
	add.call("quick_claim")
	add.call("buy_offer", ["monthly_card"])
	add.call("quests", [], 18 * HOUR)
	add.call("free_pull_available")
	add.call("summon", [1, true])
	add.call("claim_idle")
	add.call("offers")
	add.call("salvage_gear", ["g1"])
	add.call("set_setting", ["battle_speed", 4])
	add.call("dev_add", ["dust", 500])
	add.call("upgrade_ready", ["kessa"])
	add.call("hero_stats", ["kessa"])
	add.call("monthly_card_days_left", [], DAY)
	add.call("offers")
	# The other banners: payment, the wish target, limits, per-banner pity, rotation views.
	add.call("dev_add", ["gems", 20000])
	add.call("summon", [1, false, "wish"])
	add.call("set_wish_target", ["mordessa"])
	add.call("summon", [10, false, "wish"])
	add.call("summon", [10, false, "featured"])
	add.call("summon", [10, false, "faction"])
	add.call("summon", [1, true, "featured"])
	add.call("dev_add", ["gold", 60000])
	add.call("summon", [10, false, "envoy"])
	add.call("summon", [1, false, "envoy"])
	add.call("summon_left", ["envoy"])
	add.call("pity_count", ["featured"])
	add.call("banners", [], DAY)
	add.call("summon", [1, false, "envoy"])
	add.call("banners", [], 7 * DAY)
	# Prints (every summon above made some) and the Rival while she is still locked.
	add.call("print_stats")
	add.call("prints", ["misprint"])
	add.call("set_showcase", [["p1", "p12"]])
	add.call("showcase")
	add.call("rival")
	return s


static func _session(f: Dictionary) -> Dictionary:
	var m := _new_model(int(f.start_ms))
	m.tz_bias_ms = int(f.tz_bias_ms)
	var results: Array = []
	for st in f.steps:
		_advance(m, int(st.advance_ms))
		var args: Array = st.args
		var value: Variant
		if str(st.call) == "battle":
			var i := int(args[0])
			var setup := m.stage_battle_setup(i)
			var outcome := BattleSim.new(setup).run_to_end()
			value = {"seed": setup.seed, "victory": outcome.victory, "duration_ms": outcome.duration_ms,
				"complete": m.complete_stage(i, outcome)}
		else:
			value = m.callv(str(st.call), args)
		results.append({"call": st.call, "value": value, "notify": m.outbox.duplicate()})
		m.outbox.clear()
	return {"start_ms": f.start_ms, "tz_bias_ms": f.tz_bias_ms, "steps": f.steps, "results": results,
		"final_state": m.state}


# ---------------------------------------------------------------- save migration

static func _save_cases() -> Array:
	var full := _new_model(BASE_MS)
	full.new_game()
	full.summon(10)
	full.summon(1, false, "featured")
	full.set_wish_target("seraphiel")
	_advance(full, 4 * HOUR)
	full.claim_idle()
	return [
		{"name": "old_save_missing_keys", "now_ms": BASE_MS + HOUR, "input": {
			"version": 1, "created_at": BASE_MS, "player_name": "Old",
			"currencies": {"gold": 77, "gems": 5},
			"heroes": {"uriela": {"id": "uriela", "level": 7, "stars": 2}, "ghost": {"id": "ghost", "level": 3}},
			"formation": ["uriela", "ghost", "", ""],
			"campaign": {"cleared": 4},
			"idle": {"last_claim_at": BASE_MS - HOUR}}},
		{"name": "damaged_values", "now_ms": BASE_MS, "input": {
			"version": 1, "heroes": {"ghost": {"level": 9}},
			"gear": [{"uid": 5, "slot": "weapon", "tier": 9, "stats": {"atk": 10}, "equipped_by": "nobody"},
				{"uid": "g6", "slot": "boots"}, "junk"],
			"settings": {"battle_speed": 3, "sound": "yes"},
			"campaign": {"cleared": 999},
			"formation": "uriela"}},
		{"name": "old_save_keeps_summon_counters", "now_ms": BASE_MS + HOUR, "input": {
			"version": 1, "created_at": BASE_MS,
			"heroes": {"uriela": {"id": "uriela", "level": 3, "stars": 1}},
			"summon": {"pity": 37, "total_pulls": 120, "last_free_pull_day": 19699, "seed": 4242}}},
		{"name": "damaged_banner_states", "now_ms": BASE_MS, "input": {
			"version": 1, "heroes": {"kessa": {"id": "kessa"}},
			"summon": {"pity": 75, "total_pulls": -4, "seed": 1, "banners": {
				"featured": {"pity": 90, "lost": "yes", "pulls": 12},
				"wish": {"target": "uriela", "pity": 3},
				"envoy": {"pity": 7, "period": 5, "period_pulls": -2},
				"bogus": {"pity": 1},
				"faction": "junk"}}}},
		{"name": "current_save_unchanged", "now_ms": BASE_MS + 5 * HOUR, "input": normalize(full.state)},
	]


static func _save(f: Dictionary) -> Dictionary:
	var cases: Array = []
	for c in f.cases:
		var m := _new_model(int(c.now_ms))
		var input: Dictionary = normalize(c.input)
		cases.append({"name": c.name, "now_ms": c.now_ms, "input": c.input, "out": m.migrate(input)})
	return {"cases": cases}


# ---------------------------------------------------------------- prints (misprints)

static func _prints_inputs() -> Dictionary:
	var e := EconomyData.BANNER_EPOCH_DAY
	var heroes: Array = []
	for id in HeroData.ids():
		heroes.append(id)
	var ten := heroes.slice(0, 10)
	var make: Array = [
		{"name": "fresh_standard_ten", "banner": "standard", "hero_ids": ten, "day": e + 3, "epoch_day": e, "hours_open": 77, "ed": {}, "seed": 31337, "seq": 0},
		{"name": "same_edition_continues", "banner": "standard", "hero_ids": ten.slice(0, 3), "day": e + 4, "epoch_day": e, "hours_open": 101, "ed": {"e": 0, "n": 25}, "seed": 31337, "seq": 10},
		{"name": "new_edition_restarts", "banner": "standard", "hero_ids": ten.slice(3, 6), "day": e + 29, "epoch_day": e, "hours_open": 5, "ed": {"e": 0, "n": 900}, "seed": 31337, "seq": 13},
		{"name": "second_printing", "banner": "faction", "hero_ids": ten, "day": e + 2, "epoch_day": e, "hours_open": 70, "ed": {"e": 0, "n": 400}, "seed": 9, "seq": 400},
		{"name": "featured_before_epoch", "banner": "featured", "hero_ids": ten.slice(0, 1), "day": e - 9, "epoch_day": e, "hours_open": 0, "ed": {}, "seed": 2, "seq": 7},
		{"name": "envoy_whole_roster", "banner": "envoy", "hero_ids": heroes, "day": e + 15, "epoch_day": e, "hours_open": 15, "ed": {"e": 2, "n": 33}, "seed": -77, "seq": 5000},
	]
	# A long run on one seed, so every flaw, holo and most grades turn up.
	var long_ids: Array = []
	for i in 240:
		long_ids.append(heroes[(i * 7) % heroes.size()])
	make.append({"name": "long_run", "banner": "featured", "hero_ids": long_ids, "day": e + 1, "epoch_day": e, "hours_open": 30, "ed": {},
		"seed": _long_run_seed(long_ids, e), "seq": 0})
	var editions: Array = []
	for b: String in ["standard", "featured", "faction", "wish", "envoy", "unknown"]:
		for k: int in [-30, -1, 0, 1, 6, 7, 27, 28, 29, 100]:
			editions.append({"banner": b, "day": e + k, "epoch_day": e})
	var samples: Array = [
		{"hero": "kessa", "serial": 412, "printing": 1, "flaw": "", "holo": false, "grade": 7},
		{"hero": "kessa", "serial": 12, "printing": 1, "flaw": "", "holo": false, "grade": 6},
		{"hero": "kessa", "serial": 900, "printing": 2, "flaw": "shift", "holo": false, "grade": 5},
		{"hero": "kessa", "serial": 900, "printing": 1, "flaw": "flood", "holo": true, "grade": 10},
		{"hero": "kessa", "serial": 101, "printing": 1, "flaw": "", "holo": false, "grade": 9},
		{"hero": "kessa", "serial": 3000, "printing": 3, "flaw": "", "holo": false, "grade": 8, "first": true},
		{"hero": "kessa", "serial": 3000, "printing": 3, "flaw": "", "holo": false, "grade": 8, "from": "rival"},
		{"hero": "kessa", "serial": 2000, "printing": 1, "flaw": "", "holo": false, "grade": 3},
	]
	var trim_list: Array = []
	for i in 12:
		trim_list.append({"uid": "p%d" % (i + 1), "hero": "uriela", "serial": 500 + i, "printing": 1,
			"flaw": "ghost" if i == 2 else "", "holo": i == 7, "grade": 10 if i == 9 else 6})
	return {
		"about": "PrintRules (src/core/print_rules.gd) on data/prints.json: edition_on(banner, day, epoch_day), flaw_for_roll, grade_for_roll, make_prints (each case's inputs -> out {prints, ed}), notable and score of sample prints, and trim(list, keep_plain) (out with keep_plain, out_default with the file's keep_plain).",
		"editions": editions,
		"flaw_rolls": [0, 259, 260, 399, 400, 489, 490, 549, 550, 599, 600, 9999],
		"grade_rolls": [0, 99, 100, 699, 700, 2499, 2500, 5499, 5500, 7999, 8000, 9199, 9200, 9699, 9700, 9999],
		"make_prints": make,
		"samples": samples,
		"trim": {"list": trim_list, "keep_plain": 3},
	}


## The first seed from 424242 up whose long run has every flaw and a holo foil.
static func _long_run_seed(ids: Array, e: int) -> int:
	for s in range(424242, 425242):
		var out := PrintRules.make_prints("featured", ids, e + 1, e, 30, {}, s, 0)
		var seen := {}
		for p: Dictionary in out.prints:
			seen[str(p.flaw)] = true
			if bool(p.holo):
				seen["holo"] = true
		if seen.size() >= 7:
			return s
	return 424242


static func _prints(f: Dictionary) -> Dictionary:
	var eds: Array = []
	for c in f.editions:
		eds.append({"banner": c.banner, "day": c.day, "epoch_day": c.epoch_day,
			"out": PrintRules.edition_on(str(c.banner), int(c.day), int(c.epoch_day))})
	var made: Array = []
	for c in f.make_prints:
		var cc: Dictionary = (c as Dictionary).duplicate(true)
		cc.erase("out")
		cc["out"] = PrintRules.make_prints(str(c.banner), c.hero_ids, int(c.day), int(c.epoch_day), int(c.hours_open), c.ed,
			int(c.seed), int(c.seq))
		made.append(cc)
	var samples: Array = []
	for s in f.samples:
		var p: Dictionary = s.get("print", s)
		samples.append({"print": p, "notable": PrintRules.notable(p), "score": PrintRules.score(p)})
	var flaws: Array = []
	for r in f.flaw_rolls:
		flaws.append(PrintRules.flaw_for_roll(int(r)))
	var grades: Array = []
	for r in f.grade_rolls:
		grades.append(PrintRules.grade_for_roll(int(r)))
	return {
		"editions": eds,
		"flaw_rolls": f.flaw_rolls,
		"flaws": flaws,
		"grade_rolls": f.grade_rolls,
		"grades": grades,
		"make_prints": made,
		"samples": samples,
		"trim": {"list": f.trim.list, "keep_plain": f.trim.keep_plain,
			"out": PrintRules.trim(f.trim.list, int(f.trim.keep_plain)), "out_default": PrintRules.trim(f.trim.list)},
	}


# ---------------------------------------------------------------- the Rival

static func _war_inputs() -> Dictionary:
	var e := WarRules.EPOCH_DAY
	var days: Array = []
	for k in [-9, -8, -1, 0, 1, 6, 7, 13, 14, 40]:
		days.append(e + k)
	# A player's log over two weeks: a few sectors, one huge push to show the clamp.
	var log := {str(e + 7): {"3": 400, "1": 80}, str(e + 8): {"3": 1200}, str(e + 9): {"0": 40, "6": 3000},
		str(e + 13): {"3": 200}, str(e + 15): {"2": 120}}
	var cases: Array = []
	for c: Array in [[1, e + 7, "heaven"], [1, e + 9, "heaven"], [1, e + 13, "heaven"], [1, e + 13, "hell"], [1, e + 13, ""],
			[1, e + 30, "hell"], [2, e + 15, "heaven"], [0, e + 6, "heaven"], [-1, e - 1, "hell"]]:
		cases.append({"week": c[0], "upto_day": c[1], "side": c[2]})
	return {
		"about": "WarRules (src/core/war_rules.gd) on data/war.json: week_of / week_start, sim_push for each day x sector x side, control(week, upto_day, log, side) with the standing, and reward(won, held).",
		"days": days,
		"push_days": [e, e + 1, e + 8],
		"log": log,
		"cases": cases,
		"reward_cases": [[false, 0], [true, 4], [false, 3], [true, 7]],
		"champ_weeks": [-3, -1, 0, 1, 2, 7, 8, 15],
		"champ_avgs": [1, 2, 9, 30, 64],
		"champ_stats": [["mordessa", 50], ["seraphiel", 18], ["brakka", 72]],
		"champ_tiers": [[1000000, 0], [1000000, 99999], [1000000, 100000], [1000000, 520000], [371625, 371625], [371625, 9999999]],
	}


static func _war(f: Dictionary) -> Dictionary:
	var weeks: Array = []
	for d: Variant in f.days:
		weeks.append([WarRules.week_of(int(d)), WarRules.week_start(WarRules.week_of(int(d)))])
	var pushes: Array = []
	for d: Variant in f.push_days:
		for s in WarRules.sector_count():
			pushes.append([WarRules.sim_push(int(d), s, "heaven"), WarRules.sim_push(int(d), s, "hell")])
	var cases: Array = []
	for c: Dictionary in f.cases:
		var ctl := WarRules.control(int(c.week), int(c.upto_day), f.log, str(c.side))
		cases.append({"week": c.week, "upto_day": c.upto_day, "side": c.side, "control": ctl, "standing": WarRules.standing(ctl)})
	var rewards: Array = []
	for r: Array in f.reward_cases:
		rewards.append(WarRules.reward(bool(r[0]), int(r[1])))
	var champs: Array = []
	for w: Variant in f.champ_weeks:
		champs.append([WarRules.champion_for(int(w), "heaven"), WarRules.champion_for(int(w), "hell"), WarRules.champion_for(int(w), "")])
	var levels: Array = []
	for a: Variant in f.champ_avgs:
		levels.append(WarRules.champion_level(int(a)))
	var cstats: Array = []
	for c: Array in f.champ_stats:
		cstats.append(WarRules.champion_stats(str(c[0]), int(c[1])))
	var ctiers: Array = []
	for c: Array in f.champ_tiers:
		ctiers.append(WarRules.tiers_reached(int(c[0]), int(c[1])))
	return {"days": f.days, "weeks": weeks, "push_days": f.push_days, "pushes": pushes, "log": f.log, "cases": cases,
		"reward_cases": f.reward_cases, "rewards": rewards, "champ_weeks": f.champ_weeks, "champions": champs,
		"champ_avgs": f.champ_avgs, "champ_levels": levels, "champ_stats": f.champ_stats, "champ_stats_out": cstats,
		"champ_tiers": f.champ_tiers, "champ_tiers_out": ctiers}


static func _rival_inputs() -> Dictionary:
	var e := EconomyData.BANNER_EPOCH_DAY
	var stars_cases: Array = []
	for c: Array in [["uriela", 0, 1], ["uriela", 5, 3], ["uriela", 40, 6], ["seraphiel", 0, 1], ["seraphiel", 9, 4], ["cassiel", 3, 2]]:
		stars_cases.append({"hero_id": c[0], "dupes": c[1], "cap": c[2]})
	var level_cases: Array = []
	for c: Array in [[1, 0, false], [30, 1, false], [30, 2, true], [55, 6, false], [2, 4, true], [80, -3, true]]:
		level_cases.append({"avg": c[0], "day": e + int(c[1]), "countering": c[2]})
	var all := {}
	for id in HeroData.ids():
		all[id] = 3
	var team_cases: Array = [
		{"heroes": {"noctaire": 0, "orrin": 0, "sable": 0, "lucen": 0, "ashra": 0}, "cap": 3, "level": 12, "prefer": ""},
		{"heroes": all, "cap": 4, "level": 40, "prefer": ""},
		{"heroes": all, "cap": 4, "level": 40, "prefer": "celestial"},
		{"heroes": {"uriela": 8, "kessa": 1, "cassiel": 0, "imra": 2, "mordessa": 0, "noctaire": 4, "liora": 0}, "cap": 5, "level": 60, "prefer": "infernal"},
		{"heroes": {"orrin": 0, "brakka": 0}, "cap": 2, "level": 9, "prefer": "fallen"},
	]
	var sims: Array = [
		{"name": "first_week", "seed": 12345, "steps": [{"today": e + 2, "owns": ["uriela", "kessa"]}, {"today": e + 9, "owns": ["uriela", "kessa", "mordessa"]}]},
		{"name": "catch_up_cap", "seed": 777, "steps": [{"today": e - 40, "owns": []}, {"today": e + 3, "owns": ["noctaire"]}, {"today": e + 3, "owns": []}, {"today": e + 1, "owns": []}]},
		{"name": "long_month", "seed": 660601, "steps": [{"today": e + 5, "owns": []}, {"today": e + 12, "owns": []}, {"today": e + 19, "owns": []}, {"today": e + 26, "owns": []}]},
	]
	var days: Array = []
	for k in range(-4, 10):
		days.append(e + k)
	return {
		"about": "RivalRules (src/core/rival_rules.gd) on data/rival.json: banner_on and the counter wheel, stars_for, level_on, team (her five best as echoes), new_state(seed) then catch_up(state, today, epoch_day, owns) steps (the days simulated, the state after each step and best_untaken), haul, cleared_on / tower_on ([player cleared, player Spire best, day]) and lines ([kind, seed, day, salt, fills]).",
		"epoch_day": e,
		"banner_days": days,
		"factions": ["celestial", "infernal", "fallen", ""],
		"stars": stars_cases,
		"levels": level_cases,
		"teams": team_cases,
		"sims": sims,
		"hauls": [0, 6, 25, 60],
		"leads": [[12, 30, e], [12, 30, e + 1], [59, 119, e + 2], [0, 0, e + 3], [60, 120, e + 4]],
		"lines": [["intro", 5, e, 0, {}], ["idle", 5, e + 1, 3, {"you": "Envoy"}], ["win", 99, e + 2, 1, {"you": "Envoy"}],
			["misprint", 7, e + 3, 2, {"hero": "Kessa", "flaw": "off-register"}], ["counter", 7, e, 4, {"faction": "Celestial", "main": "Infernal"}],
			["nope", 1, e, 0, {}]],
	}


static func _rival(f: Dictionary) -> Dictionary:
	var e := int(f.epoch_day)
	var sims: Array = []
	for c in f.sims:
		var rs := RivalRules.new_state(int(c.seed))
		var outs: Array = []
		for st in c.steps:
			var owns := {}
			for id in st.owns:
				owns[str(id)] = true
			var n := RivalRules.catch_up(rs, int(st.today), e, owns)
			outs.append({"days": n, "state": normalize(rs), "best_untaken": RivalRules.best_untaken(rs)})
		sims.append({"name": c.name, "seed": c.seed, "steps": c.steps, "out": outs})
	var banners: Array = []
	for d in f.banner_days:
		banners.append(RivalRules.banner_on(int(d), e))
	var counters: Array = []
	for x in f.factions:
		counters.append(RivalRules.counter_faction(str(x)))
	var stars: Array = []
	for c in f.stars:
		stars.append({"hero_id": c.hero_id, "dupes": c.dupes, "cap": c.cap, "out": RivalRules.stars_for(str(c.hero_id), int(c.dupes), int(c.cap))})
	var levels: Array = []
	for c in f.levels:
		levels.append({"avg": c.avg, "day": c.day, "countering": c.countering, "out": RivalRules.level_on(int(c.avg), int(c.day), bool(c.countering))})
	var teams: Array = []
	for c in f.teams:
		teams.append({"heroes": c.heroes, "cap": c.cap, "level": c.level, "prefer": c.prefer,
			"out": RivalRules.team(c.heroes, int(c.cap), int(c.level), str(c.prefer))})
	var hauls: Array = []
	for c in f.hauls:
		hauls.append(RivalRules.haul(int(c)))
	var leads: Array = []
	for c in f.leads:
		leads.append([RivalRules.cleared_on(int(c[0]), int(c[2])), RivalRules.tower_on(int(c[1]), int(c[2]))])
	var lines: Array = []
	for c in f.lines:
		lines.append(RivalRules.line(str(c[0]), int(c[1]), int(c[2]), int(c[3]), c[4]))
	return {
		"epoch_day": f.epoch_day,
		"banner_days": f.banner_days,
		"banners": banners,
		"factions": f.factions,
		"counters": counters,
		"stars": stars,
		"levels": levels,
		"teams": teams,
		"sims": sims,
		"hauls": f.hauls,
		"haul_out": hauls,
		"leads": f.leads,
		"lead_out": leads,
		"lines": f.lines,
		"line_out": lines,
	}
