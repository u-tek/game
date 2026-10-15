extends RefCounted
## Hero definitions, levels, stars, stats, formation and gear.

const BASE_MS := 1_702_083_600_000


func _game() -> Node:
	var g: Node = load("res://src/core/game.gd").new()
	g.save_path = ""
	g.tz_bias_ms = 0
	g.now_override_ms = BASE_MS
	g.new_game()
	return g


func test_hero_defs_are_complete(t: TestCtx) -> void:
	var g := _game()
	var defs: Array = g.all_hero_defs()
	t.eq(defs.size(), 15)
	var ult_names := {}
	for d in defs:
		var ident := HeroData.get_def(d.id)
		for k in ["id", "name", "title", "faction", "role", "rarity", "bio", "look"]:
			t.eq(d[k], ident[k], "%s identity field %s preserved" % [d.id, k])
		for k in ["hp", "atk", "def", "spd", "crit"]:
			t.ok(int(d.base_stats.get(k, 0)) > 0, "%s base_stats.%s" % [d.id, k])
		t.ok(d.ultimate.name != "" and d.ultimate.description.length() > 20, "%s ultimate text" % d.id)
		t.ok(not d.ultimate.effects.is_empty(), "%s ultimate effects" % d.id)
		ult_names[d.ultimate.name] = true
		t.eq(d.passives.size(), 2, "%s has 2 passives" % d.id)
		t.eq(int(d.passives[0].unlock_stars), 3)
		t.eq(int(d.passives[1].unlock_stars), 5)
		for p in d.passives:
			t.ok(p.name != "" and p.description != "" and not p.effects.is_empty(), "%s passive %s" % [d.id, p.get("id", "")])
	t.eq(ult_names.size(), 15, "ultimate names are unique")
	t.eq(g.hero_def("nobody"), {})
	g.free()


func test_new_game_state(t: TestCtx) -> void:
	var g := _game()
	t.eq(g.owned_heroes().size(), 3)
	for id in ["uriela", "kessa", "lucen"]:
		t.ok(g.owns(id), "starter %s" % id)
		t.eq(int(g.hero(id).stars), 1, "rares start at 1 star")
	t.eq(g.currency("gems"), 1800)
	t.eq(g.currency("scrolls"), 10)
	t.eq(g.cleared_count(), 0)
	t.eq(g.formation().size(), 5)
	t.ok(g.team_power() > 0)
	t.ok(g.free_pull_available())
	g.free()


func test_level_up_costs_and_cap(t: TestCtx) -> void:
	var g := _game()
	var events: Array = []
	g.notify.connect(func(e: Dictionary) -> void: events.append(e))
	var cost: Dictionary = g.level_up_cost("uriela")
	t.eq(cost, EconomyData.level_cost(1))
	var gold: int = g.currency("gold")
	var xp: int = g.currency("hero_exp")
	var p0: int = g.hero_power("uriela")
	var r: Dictionary = g.level_up("uriela")
	t.ok(r.ok, r.error)
	t.eq(int(g.hero("uriela").level), 2)
	t.eq(g.currency("gold"), gold - int(cost.gold))
	t.eq(g.currency("hero_exp"), xp - int(cost.hero_exp))
	t.ok(g.hero_power("uriela") > p0, "power grows")
	t.eq(events.back().type, "level_up")
	# Costs rise with level.
	t.ok(int(EconomyData.level_cost(30).hero_exp) > int(EconomyData.level_cost(10).hero_exp))
	# Cap: 20 + 20 * stars.
	t.eq(g.max_level("uriela"), 40)
	g.dev_add("gold", 10000000)
	g.dev_add("hero_exp", 10000000)
	r = g.level_up_many("uriela", 999)
	t.ok(r.ok)
	t.eq(int(g.hero("uriela").level), 40)
	t.eq(g.level_up_cost("uriela"), {}, "no cost at cap")
	r = g.level_up("uriela")
	t.eq(r.ok, false, "cannot pass the cap")
	# Not enough resources.
	g.state.currencies.gold = 0
	r = g.level_up("kessa")
	t.eq(r.ok, false)
	t.eq(r.error, "Not enough gold")
	t.eq(g.level_up("nobody").ok, false)
	g.free()


func test_star_up_with_shards_and_dust(t: TestCtx) -> void:
	var g := _game()
	t.eq(g.star_up_cost("uriela").shards, 10)
	t.eq(g.star_up("uriela").ok, false, "no shards, no dust")
	g.state.heroes.uriela.shards = 10
	var r: Dictionary = g.star_up("uriela")
	t.ok(r.ok, r.error)
	t.eq(int(g.hero("uriela").stars), 2)
	t.eq(int(g.hero("uriela").shards), 0)
	t.eq(g.max_level("uriela"), 60, "cap rises with stars")
	t.ok(g.upgrade_ready("uriela"), "starting gold and EXP afford a level")
	g.state.currencies.gold = 0
	t.eq(g.upgrade_ready("uriela"), false, "no gold, no shards: nothing to upgrade")
	g.state.currencies.gold = 4000
	# 2 -> 3 needs 20 shards; with 5 shards the rest is paid in dust at 10 per shard.
	g.state.heroes.uriela.shards = 5
	var c: Dictionary = g.star_up_cost("uriela")
	t.eq(c.shards, 20)
	t.eq(c.dust, 15 * EconomyData.dust_per_shard("rare"))
	t.eq(c.dust_per_shard, 10, "rare shards cost 10 dust")
	t.ok(EconomyData.dust_per_shard("legendary") > EconomyData.dust_per_shard("epic")
		and EconomyData.dust_per_shard("epic") > EconomyData.dust_per_shard("rare"), "rarer shards cost more dust")
	for rarity in ["rare", "epic", "legendary"]:
		t.ok(EconomyData.dust_per_excess_shard(rarity) < EconomyData.dust_per_shard(rarity), "excess shards convert at a loss (%s)" % rarity)
	g.dev_add("dust", 149)
	t.eq(g.star_up("uriela").ok, false, "1 dust short")
	g.dev_add("dust", 1)
	var events: Array = []
	g.notify.connect(func(e: Dictionary) -> void: events.append(e))
	r = g.star_up("uriela")
	t.ok(r.ok, r.error)
	t.eq(g.currency("dust"), 0)
	t.eq(int(g.hero("uriela").stars), 3)
	t.eq(events.back().type, "star_up")
	t.eq(events.back().get("passive", ""), "Bastion Drills", "3 stars unlocks the first passive")
	t.ok(g.passive_unlocked("uriela", 0))
	t.eq(g.passive_unlocked("uriela", 1), false)
	# Max stars.
	g.state.heroes.uriela.stars = 6
	t.eq(g.star_up_cost("uriela"), {})
	t.eq(g.star_up("uriela").ok, false)
	t.eq(g.max_level("uriela"), 140)
	g.free()


func test_stats_scale(t: TestCtx) -> void:
	var a := StatCalc.stats("lucen", 1, 1)
	var b := StatCalc.stats("lucen", 20, 1)
	var c := StatCalc.stats("lucen", 20, 4)
	for k in ["hp", "atk", "def"]:
		t.ok(int(b[k]) > int(a[k]) and int(c[k]) > int(b[k]), "%s grows with level and stars" % k)
	t.eq(int(a.hp), int(HeroKits.get_kit("lucen").base_stats.hp), "level 1, 1 star = base stats")
	t.ok(StatCalc.power(c) > StatCalc.power(b))
	# Legendaries start stronger.
	var g := _game()
	t.ok(g.hero_power("seraphiel") > g.hero_power("uriela"), "unowned defs report base power")
	g.free()


func test_formation_rules(t: TestCtx) -> void:
	var g := _game()
	t.eq(g.set_formation(["uriela", "uriela", "", "", ""]).ok, false, "no duplicates")
	t.eq(g.set_formation(["", "", "", "", ""]).ok, false, "need a hero")
	t.eq(g.set_formation(["seraphiel", "", "", "", ""]).ok, false, "must own heroes")
	t.eq(g.set_formation(["uriela", ""]).ok, false, "5 slots")
	var r: Dictionary = g.set_formation(["", "kessa", "uriela", "", "lucen"])
	t.ok(r.ok)
	t.eq(g.formation(), ["", "kessa", "uriela", "", "lucen"])
	g.model.add_hero("brakka")
	g.model.add_hero("liora")
	g.auto_formation()
	var f: Array = g.formation()
	t.ok(f.slice(0, 2).has("brakka"), "guardian goes in front: %s" % [f])
	t.ok(f.slice(2).has("liora"), "support goes in back: %s" % [f])
	t.eq(f.has(""), false)
	g.free()


func test_new_heroes_join_an_unfilled_formation(t: TestCtx) -> void:
	var g := _game()
	t.eq(g.formation().filter(func(x: String) -> bool: return x != "").size(), 3)
	g.model.receive_hero("brakka")
	var f: Array = g.formation()
	t.ok(f.slice(0, 2).has("brakka"), "a new guardian takes the front row: %s" % [f])
	g.model.receive_hero("liora")
	f = g.formation()
	t.ok(f.slice(2).has("liora"), "a new support goes to the back row: %s" % [f])
	t.eq(f.has(""), false, "formation filled")
	# A full formation is the player's: new heroes never reshuffle it.
	var before: Array = g.formation()
	g.model.receive_hero("cassiel")
	t.eq(g.formation(), before, "full formation unchanged")
	t.ok(g.owns("cassiel"))
	g.free()


func test_faction_bonus_query(t: TestCtx) -> void:
	var g := _game()
	t.eq(g.faction_bonus(), {})
	for id in ["cassiel", "liora", "nuriel"]:
		g.model.add_hero(id)
	g.set_formation(["cassiel", "uriela", "liora", "nuriel", ""])
	t.eq(g.faction_bonus(), {"faction": "celestial", "count": 4, "bonus_pct": 10})
	g.free()


func test_gear_equip_and_auto(t: TestCtx) -> void:
	var g := _game()
	var w1: String = g.model.create_gear("weapon", 1)
	var w3: String = g.model.create_gear("weapon", 3)
	var r: Dictionary = g.equip("uriela", w1)
	t.ok(r.ok)
	t.eq(g.gear_item(w1).equipped_by, "uriela")
	var atk_before: int = int(g.hero_stats("uriela").atk)
	g.auto_equip("uriela")
	t.eq(g.gear_item(w3).equipped_by, "uriela", "auto-equip picks the better weapon")
	t.eq(g.gear_item(w1).equipped_by, "", "old weapon returns to the bag")
	t.ok(int(g.hero_stats("uriela").atk) > atk_before)
	# Equipping another hero's item moves it.
	g.equip("kessa", w3)
	t.eq(g.gear_item(w3).equipped_by, "kessa")
	t.eq(g.hero("uriela").gear.has("weapon"), false)
	t.eq(g.unequip("kessa", "weapon").ok, true)
	t.eq(g.gear_item(w3).equipped_by, "")
	# A formation hero's auto-equip takes gear off benched heroes, never off teammates.
	g.model.add_hero("cassiel")
	g.equip("cassiel", w3)
	g.set_formation(["uriela", "kessa", "lucen", "", ""])
	g.auto_equip("uriela")
	t.eq(g.gear_item(w3).equipped_by, "uriela", "benched Cassiel's weapon moves to Uriela")
	g.auto_equip("kessa")
	t.eq(g.gear_item(w3).equipped_by, "uriela", "teammates keep their gear")
	t.eq(g.gear_item(w1).equipped_by, "kessa", "the loose weapon goes to Kessa")
	g.auto_equip("cassiel")
	t.eq(g.gear_item(w3).equipped_by, "uriela", "a benched hero never takes from the team")
	g.unequip("kessa", "weapon")
	var s: Dictionary = g.salvage_gear(w1)
	t.ok(s.ok)
	t.ok(int(s.value.gold) > 0)
	t.eq(g.gear_item(w1), {})
	g.free()


func test_owned_heroes_sorted_by_power(t: TestCtx) -> void:
	var g := _game()
	g.dev_add("gold", 100000)
	g.dev_add("hero_exp", 100000)
	g.level_up_many("kessa", 10)
	var list: Array = g.owned_heroes()
	t.eq(list[0].id, "kessa")
	for i in list.size() - 1:
		t.ok(g.hero_power(list[i].id) >= g.hero_power(list[i + 1].id))
	g.free()


func test_full_bag_salvages_weakest_then_oldest(t: TestCtx) -> void:
	var g := _game()
	# 50 identical weapons: the team equips the first three, the bag keeps 40 loose pieces.
	for i in 50:
		g.state.gear.append({"uid": "w%d" % i, "slot": "weapon", "tier": 1, "name": "Worn Blade",
			"stats": {"atk": 5}, "equipped_by": ""})
	g.state.gear.append({"uid": "junk", "slot": "weapon", "tier": 1, "name": "Worn Blade",
		"stats": {"atk": 1}, "equipped_by": ""})
	var gold: int = g.currency("gold")
	g.model.grant({"gear_drops": [{"slot": "helm", "tier": 1}]})
	var loose: Array = []
	for it in g.gear_items():
		if it.equipped_by == "":
			loose.append(it.uid)
	t.eq(loose.size(), 40, "bag trimmed to the limit")
	t.eq(loose.has("junk"), false, "the weakest piece goes first")
	t.eq(loose[0], "w11", "equal pieces: the oldest are salvaged first (w3..w10 gone)")
	t.eq(g.currency("gold"), gold + 9 * EconomyData.SALVAGE_GOLD_PER_TIER, "salvage pays per tier")
	g.free()
