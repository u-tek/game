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

const FILES: Array[String] = ["rng", "progression", "idle", "gear", "stats", "summon", "battles", "session", "save"]
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
			var afford: Array = []
			for c in [[1, 40, 4000, 2400], [1, 40, 0, 99999], [35, 40, 10 ** 7, 10 ** 7], [20, 60, 50000, 30000]]:
				afford.append({"level": c[0], "cap": c[1], "gold": c[2], "hero_exp": c[3]})
			return {
				"about": "Progression (src/core/progression.gd): level costs (level -> level + 1), caps, star shards, star-up costs, shards to dust, affordable levels.",
				"level_cost": range(1, 140).map(func(l: int) -> Dictionary: return {"level": l}),
				"level_cap": range(0, 8).map(func(s: int) -> Dictionary: return {"stars": s}),
				"star_shards": range(0, 8).map(func(s: int) -> Dictionary: return {"stars": s}),
				"star_up_cost": star_cases,
				"add_shards": add_cases,
				"affordable_levels": afford,
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
			var scores: Array = []
			for st in [{"atk": 140}, {"hp": 2190, "def": 66}, {"crit": 1500, "spd": 15, "atk": 52}, {}]:
				scores.append({"stats": st})
			return {
				"about": "StatCalc (src/core/stat_calc.gd): hero stats (level, stars, gear, stat passives), power, gear score; and every campaign stage's enemies as built from data/stages.json, with echo stats and enemy power.",
				"hero_stats": cases,
				"gear_score": scores,
				"stages": range(StageData.count()).map(func(s: int) -> Dictionary: return {"index": s}),
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
			}
		"battles":
			return {
				"about": "BattleSim (src/core/battle_sim.gd): setup + seed -> every event of every step() in order, outcome() and the final units. manual_ultimates: before step number `tick` (1 = first step), request_ultimate(uid); `accepted` is its result. Then run_to_end() on a fresh sim must give the same outcome.",
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
		adds.append({"stars": c.stars, "shards_have": c.shards_have, "n": c.n, "rarity": c.rarity,
			"out": Progression.add_shards(int(c.stars), int(c.shards_have), int(c.n), str(c.rarity))})
	var aff: Array = []
	for c in f.affordable_levels:
		aff.append({"level": c.level, "cap": c.cap, "gold": c.gold, "hero_exp": c.hero_exp,
			"out": Progression.affordable_levels(int(c.level), int(c.cap), int(c.gold), int(c.hero_exp))})
	return {"level_cost": lc, "level_cap": caps, "star_shards": shards, "star_up_cost": suc, "add_shards": adds,
		"affordable_levels": aff}


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
		var st := StatCalc.stats(str(c.hero_id), int(c.level), int(c.stars), c.gear)
		hs.append({"hero_id": c.hero_id, "level": c.level, "stars": c.stars, "gear": c.gear, "out": st,
			"power": StatCalc.power(st)})
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
	return {"hero_stats": hs, "gear_score": gs, "stages": stages}


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
	return {"banner": f.banner, "rarity_for_roll": rolls, "cases": cases}


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

static func _unit(uid: String, hero_id: String, slot: int, level: int, stars: int, boss: bool = false) -> Dictionary:
	return {"uid": uid, "hero_id": hero_id, "side": "ally" if uid.begins_with("a") else "enemy", "slot": slot,
		"level": level, "stars": stars, "stats": StatCalc.stats(hero_id, level, stars), "is_boss": boss}


static func _team(prefix: String, spec: Array) -> Array:
	var out: Array = []
	for s in spec:
		out.append(_unit("%s%d" % [prefix, s[1]], s[0], s[1], s[2], s[3], s.size() > 4 and s[4]))
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
		"setup": manual, "auto_ultimates": false, "manual_ultimates": _manual_requests(manual)})
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
		var events: Array = []
		var tick := 0
		while not sim.is_over():
			tick += 1
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
		{"name": "current_save_unchanged", "now_ms": BASE_MS + 5 * HOUR, "input": normalize(full.state)},
	]


static func _save(f: Dictionary) -> Dictionary:
	var cases: Array = []
	for c in f.cases:
		var m := _new_model(int(c.now_ms))
		var input: Dictionary = normalize(c.input)
		cases.append({"name": c.name, "now_ms": c.now_ms, "input": c.input, "out": m.migrate(input)})
	return {"cases": cases}
