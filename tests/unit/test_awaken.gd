extends RefCounted
## Awakening: Legendaries past max stars awaken three times (A1 legend passive, A2 empowered
## ultimate, A3 Ascended), paid in their own shards plus dust; every tier raises all stats.

const BASE_MS := 1_702_083_600_000
const LEGENDARIES: Array[String] = ["seraphiel", "argentiel", "sanariel", "mordessa", "drezza", "zecchina",
	"noctaire", "nadira", "gantra"]
const EFFECT_TYPES: Array[String] = ["stat", "start_energy", "team_start_energy", "team_aura", "start_shield",
	"heal_bonus", "thorns", "damage_reduction", "on_hit_status", "on_attack_heal", "low_hp_bonus", "on_kill",
	"lifesteal", "crit_damage", "double_strike", "ult_bonus"]
const ULT_TYPES: Array[String] = ["damage", "heal", "shield", "status", "energy"]


func _game() -> Node:
	var g: Node = load("res://src/core/game.gd").new()
	g.save_path = ""
	g.tz_bias_ms = 0
	g.now_override_ms = BASE_MS
	g.new_game()
	return g


## A Legendary at max stars holding `shards`, with `dust` dust.
func _maxed(g: Node, id: String, shards: int, dust: int) -> void:
	g.model.add_hero(id)
	g.state.heroes[id].stars = EconomyData.MAX_STARS
	g.state.heroes[id].shards = shards
	g.state.currencies.dust = dust


func test_every_legendary_has_a_legend_block(t: TestCtx) -> void:
	var g := _game()
	var n := 0
	for d: Dictionary in g.all_hero_defs():
		var lg: Dictionary = d.get("legend", {})
		if str(d.rarity) != "legendary":
			t.eq(lg, {}, "%s: only Legendaries have a legend block" % d.id)
			continue
		n += 1
		t.ok(LEGENDARIES.has(str(d.id)), "%s is a known Legendary" % d.id)
		t.ok(str(lg.get("title", "")).length() > 3, "%s legend title" % d.id)
		var lore: Array = lg.get("lore", [])
		t.eq(lore.size(), 3, "%s has 3 lore lines" % d.id)
		for line: Variant in lore:
			t.ok(str(line).length() > 20 and str(line).length() <= 110, "%s lore line length" % d.id)
		var p: Dictionary = lg.get("passive", {})
		t.eq(int(p.get("unlock_awaken", 0)), 1, "%s legend passive at A1" % d.id)
		t.ok(str(p.get("name", "")) != "" and str(p.get("description", "")).length() > 20, "%s legend passive text" % d.id)
		t.ok((p.get("effects", []) as Array).size() >= 2, "%s legend passive has 2+ effects (stronger)" % d.id)
		for e: Dictionary in p.get("effects", []):
			t.ok(EFFECT_TYPES.has(str(e.type)), "%s legend passive effect type %s" % [d.id, e.type])
		var u: Dictionary = lg.get("ult_bonus", {})
		t.eq(int(u.get("unlock_awaken", 0)), 2, "%s empowered ultimate at A2" % d.id)
		t.ok(str(u.get("name", "")) != "" and str(u.get("description", "")).length() > 20, "%s ult bonus text" % d.id)
		for e: Dictionary in u.get("effects", []):
			t.ok(ULT_TYPES.has(str(e.type)), "%s ult bonus effect type %s" % [d.id, e.type])
		t.ok(not (u.get("effects", []) as Array).is_empty(), "%s ult bonus effects" % d.id)
		# The descriptions carry the numbers.
		t.ok(str(p.description).contains("%") or str(p.description).contains("energy"), "%s passive numbers" % d.id)
		t.ok(str(u.description).contains("%") or str(u.description).contains(" s"), "%s ult bonus numbers" % d.id)
	t.eq(n, LEGENDARIES.size(), "every Legendary has a legend block")
	g.free()


func test_progression_awaken_cost(t: TestCtx) -> void:
	t.eq(Progression.max_awaken("legendary"), 3)
	t.eq(Progression.max_awaken("epic"), 0, "epics cannot awaken")
	t.eq(Progression.max_awaken("rare"), 0, "rares cannot awaken")
	t.eq(Progression.awaken_cost(6, 0, 0, "epic"), {})
	t.eq(Progression.awaken_cost(6, 3, 500, "legendary"), {}, "fully awakened")
	var per := Progression.dust_per_shard("legendary")
	var c := Progression.awaken_cost(6, 0, 100, "legendary")
	t.eq(int(c.tier), 1)
	t.eq(int(c.shards), EconomyData.AWAKEN_SHARDS[0])
	t.eq(int(c.dust), EconomyData.AWAKEN_DUST[0], "enough shards: base dust only")
	t.eq(int(c.shards_used), EconomyData.AWAKEN_SHARDS[0])
	t.eq(bool(c.stars_ok), true)
	c = Progression.awaken_cost(6, 1, 20, "legendary")
	t.eq(int(c.tier), 2)
	t.eq(int(c.dust), EconomyData.AWAKEN_DUST[1] + (EconomyData.AWAKEN_SHARDS[1] - 20) * per, "missing shards cost dust")
	t.eq(int(c.shards_used), 20)
	c = Progression.awaken_cost(5, 0, 200, "legendary")
	t.eq(bool(c.stars_ok), false, "below max stars: shown but not allowed")
	t.eq(Progression.awaken_stat_bp(0), 0)
	t.eq(Progression.awaken_stat_bp(1), EconomyData.AWAKEN_STAT_BP[0])
	t.eq(Progression.awaken_stat_bp(3), EconomyData.AWAKEN_STAT_BP[2])
	t.eq(Progression.awaken_stat_bp(9), EconomyData.AWAKEN_STAT_BP[2], "clamped")
	t.ok(EconomyData.AWAKEN_STAT_BP[0] < EconomyData.AWAKEN_STAT_BP[1] and EconomyData.AWAKEN_STAT_BP[1] < EconomyData.AWAKEN_STAT_BP[2], "each tier adds more")


func test_shards_kept_for_awakening(t: TestCtx) -> void:
	var left := 0
	for s in EconomyData.AWAKEN_SHARDS:
		left += s
	t.eq(Progression.awaken_shards_left(0, "legendary"), left)
	t.eq(Progression.awaken_shards_left(3, "legendary"), 0)
	t.eq(Progression.awaken_shards_left(0, "epic"), 0)
	# A maxed Legendary keeps a dupe's shards for her awakenings ...
	var r := Progression.add_shards(6, 0, 40, "legendary", 0)
	t.eq(r, {"shards": 40, "dust": 0})
	# ... up to what they can still use; the rest becomes dust as before.
	r = Progression.add_shards(6, left - 10, 40, "legendary", 0)
	t.eq(r, {"shards": left, "dust": 30 * Progression.dust_per_excess_shard("legendary")})
	r = Progression.add_shards(6, 0, 40, "legendary", 3)
	t.eq(r, {"shards": 0, "dust": 40 * Progression.dust_per_excess_shard("legendary")}, "fully awakened: all dust")
	r = Progression.add_shards(6, 0, 20, "epic", 0)
	t.eq(r, {"shards": 0, "dust": 20 * Progression.dust_per_excess_shard("epic")}, "epics unchanged")
	# Through the model: a maxed Legendary's duplicate.
	var g := _game()
	_maxed(g, "noctaire", 0, 0)
	var got: Dictionary = g.model.receive_hero("noctaire")
	t.eq(int(got.dust), 0, "kept for awakening")
	t.eq(int(g.hero("noctaire").shards), EconomyData.DUPE_SHARDS.legendary)
	g.state.heroes.noctaire.awaken = 3
	got = g.model.receive_hero("noctaire")
	t.eq(int(got.dust), EconomyData.DUPE_SHARDS.legendary * EconomyData.dust_per_excess_shard("legendary"), "A3: dupes become dust")
	g.free()


func test_awaken_through_the_tiers(t: TestCtx) -> void:
	var g := _game()
	var events: Array = []
	g.notify.connect(func(e: Dictionary) -> void: events.append(e))
	t.eq(g.awaken("noctaire").ok, false, "not owned")
	t.eq(g.awaken_cost("uriela"), {}, "a Rare cannot awaken")
	t.eq(g.awaken("uriela").error, "Only Legendary heroes can awaken")
	g.model.add_hero("noctaire")
	t.eq(int(g.hero("noctaire").awaken), 0, "new heroes start at A0")
	t.eq(g.awaken_tier("noctaire"), 0)
	g.state.currencies.dust = 99999
	t.eq(bool(g.awaken_cost("noctaire").stars_ok), false)
	t.eq(g.can_awaken("noctaire"), false, "needs max stars")
	t.eq(g.awaken("noctaire").error, "Awakening needs %d stars" % EconomyData.AWAKEN_MIN_STARS)
	_maxed(g, "noctaire", 300, 0)
	t.eq(g.can_awaken("noctaire"), false, "no dust")
	t.eq(g.awaken("noctaire").ok, false)
	var p0: int = g.hero_power("noctaire")
	var s0: Dictionary = g.hero_stats("noctaire")
	g.state.currencies.dust = EconomyData.AWAKEN_DUST[0]
	t.eq(g.can_awaken("noctaire"), true)
	var r: Dictionary = g.awaken("noctaire")
	t.eq(r.ok, true)
	t.eq(r.value, {"awaken": 1, "unlock": "legend_passive"})
	t.eq(int(g.hero("noctaire").shards), 300 - EconomyData.AWAKEN_SHARDS[0])
	t.eq(g.currency("dust"), 0)
	t.eq(events.back(), {"type": "awaken", "hero_id": "noctaire", "awaken": 1, "unlock": "legend_passive"})
	t.eq(g.counter("awakenings"), 1)
	var s1: Dictionary = g.hero_stats("noctaire")
	for k in ["hp", "atk", "def", "spd", "crit"]:
		t.ok(int(s1[k]) > int(s0[k]), "A1 raises %s" % k)
	t.ok(g.hero_power("noctaire") > p0)
	# A2 and A3.
	g.state.currencies.dust = 999999
	r = g.awaken("noctaire")
	t.eq(r.value, {"awaken": 2, "unlock": "ult_bonus"})
	r = g.awaken("noctaire")
	t.eq(r.value, {"awaken": 3, "unlock": "ascended"})
	t.eq(g.awaken_cost("noctaire"), {}, "fully awakened")
	t.eq(g.awaken("noctaire").error, "Already fully awakened")
	t.eq(g.can_awaken("noctaire"), false)
	g.free()


func test_missing_shards_paid_in_dust(t: TestCtx) -> void:
	var g := _game()
	_maxed(g, "seraphiel", 10, 0)
	var c: Dictionary = g.awaken_cost("seraphiel")
	var need: int = EconomyData.AWAKEN_SHARDS[0]
	t.eq(int(c.dust), EconomyData.AWAKEN_DUST[0] + (need - 10) * EconomyData.dust_per_shard("legendary"))
	g.state.currencies.dust = int(c.dust) - 1
	t.eq(g.awaken("seraphiel").error, "Not enough shards or dust")
	g.state.currencies.dust = int(c.dust)
	t.eq(g.awaken("seraphiel").ok, true)
	t.eq(int(g.hero("seraphiel").shards), 0)
	t.eq(g.currency("dust"), 0)
	g.free()


func test_stats_and_passives_by_tier(t: TestCtx) -> void:
	var lg := HeroKits.legend("seraphiel")
	t.eq(HeroKits.active_passives("seraphiel", 6).size(), 2)
	t.eq(HeroKits.active_passives("seraphiel", 6, 0).size(), 2)
	var a1 := HeroKits.active_passives("seraphiel", 6, 1)
	t.eq(a1.size(), 3, "A1: the legend passive")
	t.eq(a1[2], lg.passive)
	var a2 := HeroKits.active_passives("seraphiel", 6, 2)
	t.eq(a2.size(), 4, "A2: plus the empowered ultimate")
	t.eq(str(a2[3].effects[0].type), "ult_bonus")
	t.eq(a2[3].effects[0].effects, lg.ult_bonus.effects)
	t.eq(HeroKits.active_passives("seraphiel", 6, 3).size(), 4, "A3 adds no passive")
	t.eq(HeroKits.active_passives("uriela", 6, 3).size(), 2, "awaken means nothing to a Rare")
	t.eq(HeroKits.legend("uriela"), {})
	# Stats: A0 matches the old formula, each tier adds its bonus (and A1 the legend passive's stats).
	var base := StatCalc.stats("seraphiel", 100, 6)
	t.eq(StatCalc.stats("seraphiel", 100, 6, [], 0), base)
	var bonus := {"hp_bp": 0, "atk_bp": 0, "def_bp": 0, "spd_bp": 0, "crit_bp": 0}
	for e in HeroKits.passive_effects("seraphiel", 6, "stat"):
		for k in bonus:
			bonus[k] += int(e.get(k, 0))
	var a3 := StatCalc.stats("seraphiel", 100, 6, [], 3)
	var aw := Progression.awaken_stat_bp(3)
	for e in (lg.passive.effects as Array):
		if str(e.type) == "stat":
			for k in bonus:
				bonus[k] += int(e.get(k, 0))
	var bs: Dictionary = HeroKits.get_kit("seraphiel").base_stats
	var hp_raw: int = int(bs.hp) * StatCalc.level_mult_bp(100) / 10000 * StatCalc.star_mult_bp(6) / 10000
	t.eq(int(a3.hp), hp_raw * (10000 + int(bonus.hp_bp) + aw) / 10000, "A3 hp")
	var crit_raw: int = int(bs.crit) + int(bonus.crit_bp)
	t.eq(int(a3.crit), mini(crit_raw * (10000 + aw) / 10000, StatCalc.CRIT_CAP_BP), "A3 crit")
	t.ok(int(a3.atk) > int(base.atk) and int(a3.spd) > int(base.spd))


func test_battle_uses_legend_kit(t: TestCtx) -> void:
	# The empowered ultimate's extra effects land in battle: Seraphiel's A2 shields her allies.
	var ally := func(aw: int) -> Dictionary:
		var u := {"uid": "a0", "hero_id": "seraphiel", "side": "ally", "slot": 2, "level": 80, "stars": 6,
			"stats": StatCalc.stats("seraphiel", 80, 6, [], aw), "is_boss": false}
		if aw > 0:
			u["awaken"] = aw
		return u
	var foes: Array = []
	for i in 3:
		foes.append({"uid": "e%d" % i, "hero_id": "cassiel", "side": "enemy", "slot": i, "level": 60, "stars": 5,
			"stats": StatCalc.stats("cassiel", 60, 5), "is_boss": false})
	var shields := {}
	for aw in [0, 2]:
		var sim := BattleSim.new({"seed": 7, "allies": [ally.call(aw)], "enemies": foes.duplicate(true)})
		var u: Dictionary = sim.unit("a0")
		t.eq(int(u.pas.start_energy), 400 if aw >= 1 else 0, "legend passive start energy at A%d" % aw)
		t.eq((u.pas.ult_bonus as Array).size(), 2 if aw >= 2 else 0, "ult bonus effects at A%d" % aw)
		var shielded := false
		while not sim.is_over() and not shielded:
			for e: Dictionary in sim.step():
				if str(e.type) == "shield" and str(e.get("target", "")) == "a0":
					shielded = true
		shields[aw] = shielded
	t.eq(shields[0], false, "A0: her ultimate has no shield")
	t.eq(shields[2], true, "A2: her ultimate shields her allies")
	# Game builds ally setups with the tier.
	var g := _game()
	_maxed(g, "seraphiel", 0, 0)
	g.state.heroes.seraphiel.awaken = 2
	g.set_formation(["seraphiel", "", "", "", ""])
	var setup: Dictionary = g.stage_battle_setup(0)
	t.eq(int(setup.allies[0].get("awaken", 0)), 2)
	t.eq(setup.allies[0].stats, g.hero_stats("seraphiel"))
	g.state.heroes.seraphiel.awaken = 0
	t.eq(g.stage_battle_setup(0).allies[0].has("awaken"), false, "A0 setups stay as before")
	g.free()


func test_save_migration(t: TestCtx) -> void:
	var g := _game()
	var st: Dictionary = g.state.duplicate(true)
	st.heroes["seraphiel"] = {"id": "seraphiel", "level": 100, "stars": 6, "shards": 5}
	st.heroes["noctaire"] = {"id": "noctaire", "level": 100, "stars": 6, "shards": 5, "awaken": 9}
	st.heroes["mordessa"] = {"id": "mordessa", "level": 50, "stars": 4, "awaken": 2}
	st.heroes["cassiel"] = {"id": "cassiel", "level": 50, "stars": 6, "awaken": 2}
	st.heroes["nadira"] = {"id": "nadira", "level": 50, "stars": 6, "awaken": 2.0}
	for id in st.heroes:
		if id in ["uriela", "kessa", "lucen"]:
			st.heroes[id].erase("awaken")
	var out: Dictionary = g.migrate(st)
	t.eq(int(out.heroes.seraphiel.awaken), 0, "old saves: A0")
	t.eq(int(out.heroes.uriela.awaken), 0, "old saves: A0 for everyone")
	t.eq(int(out.heroes.noctaire.awaken), 3, "clamped to A3")
	t.eq(int(out.heroes.mordessa.awaken), 0, "below max stars: no awakening")
	t.eq(int(out.heroes.cassiel.awaken), 0, "an Epic cannot awaken")
	t.eq(out.heroes.nadira.awaken, 2, "a float tier becomes an int")
	g.free()
