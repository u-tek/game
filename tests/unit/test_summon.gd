extends RefCounted
## Summoning: costs, free daily pull, pity, 10-pull guarantee, rates, duplicates.

const BASE_MS := 1_702_083_600_000 # 01:00 UTC


func _game() -> Node:
	var g: Node = load("res://src/core/game.gd").new()
	g.save_path = ""
	g.tz_bias_ms = 0
	g.now_override_ms = BASE_MS
	g.new_game()
	return g


func test_banner_shape(t: TestCtx) -> void:
	var g := _game()
	var b: Dictionary = g.banner()
	for k in ["id", "name", "cost_one", "cost_ten", "rates", "pity_legendary", "pool"]:
		t.ok(b.has(k), "banner has %s" % k)
	t.eq(b.cost_one, 300)
	t.eq(b.cost_ten, 2700)
	t.eq(b.pity_legendary, 60)
	t.eq(int(b.rates.legendary) + int(b.rates.epic) + int(b.rates.rare), 10000, "rates add up to 100%")
	t.eq(b.pool.size(), 15)
	g.free()


func test_scrolls_first_then_gems(t: TestCtx) -> void:
	var g := _game()
	t.eq(g.currency("scrolls"), 10)
	t.eq(g.currency("gems"), 1800)
	var r: Dictionary = g.summon(10)
	t.ok(r.ok, r.error)
	t.eq(r.value.size(), 10)
	t.eq(g.currency("scrolls"), 0, "10-pull paid with scrolls")
	t.eq(g.currency("gems"), 1800, "gems untouched")
	r = g.summon(10)
	t.eq(r.ok, false, "not enough for a 10-pull")
	t.eq(r.error, "Not enough gems")
	r = g.summon(1)
	t.ok(r.ok)
	t.eq(g.currency("gems"), 1500, "single pull costs 300 gems")
	g.dev_add("scrolls", 1)
	r = g.summon(1)
	t.ok(r.ok)
	t.eq(g.currency("scrolls"), 0, "single pull prefers a scroll")
	t.eq(g.currency("gems"), 1500)
	t.eq(g.summon(3).ok, false, "only 1 or 10")
	g.free()


func test_free_daily_pull(t: TestCtx) -> void:
	var g := _game()
	t.ok(g.free_pull_available())
	var gems: int = g.currency("gems")
	var r: Dictionary = g.summon(1, true)
	t.ok(r.ok, r.error)
	t.eq(g.currency("gems"), gems, "free pull is free")
	t.eq(g.currency("scrolls"), 10)
	t.eq(g.free_pull_available(), false)
	t.eq(g.summon(1, true).ok, false, "only once per day")
	t.eq(g.summon(10, true).ok, false, "free pull is single only")
	g.now_override_ms = BASE_MS + 24 * 3600 * 1000
	t.ok(g.free_pull_available(), "available again the next day")
	g.free()


func test_pity_guarantees_legendary(t: TestCtx) -> void:
	var g := _game()
	g.state.summon.pity = 59
	var r: Dictionary = g.summon(1, true)
	t.eq(r.value[0].rarity, "legendary", "60th pull without a legendary is legendary")
	t.eq(g.pity_count(), 0, "pity resets")
	# Long run: never more than 60 pulls between legendaries.
	g.dev_add("gems", 2700 * 60)
	g.state.currencies.scrolls = 0
	var gap := 0
	var max_gap := 0
	for i in 60:
		for p in g.summon(10).value:
			gap += 1
			if p.rarity == "legendary":
				max_gap = maxi(max_gap, gap)
				gap = 0
			t.eq(int(p.pity), gap, "pity counter tracks pulls since last legendary")
	max_gap = maxi(max_gap, gap)
	t.ok(max_gap <= 60, "max gap %d" % max_gap)
	g.free()


func test_ten_pull_has_epic_or_better(t: TestCtx) -> void:
	var g := _game()
	g.dev_add("gems", 2700 * 200)
	g.state.currencies.scrolls = 0
	for i in 200:
		var r: Dictionary = g.summon(10)
		var best := false
		for p in r.value:
			if p.rarity != "rare":
				best = true
		if not best:
			t.ok(false, "10-pull %d had no epic or legendary" % i)
			break
	g.free()


func test_rates_over_many_pulls(t: TestCtx) -> void:
	var g := _game()
	g.state.summon.seed = 424242
	var n := 6000
	g.dev_add("gems", 300 * n)
	g.state.currencies.scrolls = 0
	var counts := {"rare": 0, "epic": 0, "legendary": 0}
	var forced := 0
	for i in n:
		var pity_before: int = g.pity_count()
		var p: Dictionary = g.summon(1).value[0]
		if pity_before >= 59:
			forced += 1
			continue
		counts[p.rarity] += 1
	var rolled := n - forced
	t.near(float(counts.legendary) / rolled, 0.02, 0.006, "legendary ~2%")
	t.near(float(counts.epic) / rolled, 0.18, 0.02, "epic ~18%")
	t.near(float(counts.rare) / rolled, 0.80, 0.02, "rare ~80%")
	g.free()


func test_new_heroes_and_duplicates(t: TestCtx) -> void:
	var g := _game()
	var events: Array = []
	g.notify.connect(func(e: Dictionary) -> void: events.append(e))
	g.dev_add("gems", 2700 * 30)
	g.state.currencies.scrolls = 0
	var seen := {}
	for id in ["uriela", "lucen", "kessa"]:
		seen[id] = true
	var total_shards := 0
	for i in 30:
		for p in g.summon(10).value:
			t.eq(p.is_new, not seen.has(p.hero_id), "is_new for %s" % p.hero_id)
			if p.is_new:
				t.eq(p.shards, 0)
			else:
				t.eq(p.shards, EconomyData.DUPE_SHARDS[p.rarity], "dupe shards by rarity")
				total_shards += int(p.shards)
			seen[p.hero_id] = true
			t.ok(g.owns(p.hero_id))
	var new_events := 0
	for e in events:
		if e.type == "new_hero":
			new_events += 1
	t.eq(new_events, seen.size() - 3, "new_hero notified once per new hero")
	t.ok(total_shards > 0)
	# New heroes fill empty formation slots.
	t.ok(not g.formation().has(""), "formation filled")
	g.free()


func test_maxed_duplicates_become_dust(t: TestCtx) -> void:
	var g := _game()
	g.state.heroes.uriela.stars = 6
	var r: Dictionary = g.model.receive_hero("uriela")
	t.eq(r.is_new, false)
	t.eq(int(r.dust), EconomyData.DUPE_SHARDS.rare * EconomyData.dust_per_excess_shard("rare"))
	t.eq(g.currency("dust"), int(r.dust))
	t.eq(int(g.state.heroes.uriela.shards), 0)
	g.free()


func test_summons_are_reproducible_per_save(t: TestCtx) -> void:
	var a := _game()
	var b := _game()
	a.state.summon.seed = 99
	b.state.summon.seed = 99
	t.eq(JSON.stringify(a.summon(10).value), JSON.stringify(b.summon(10).value), "same save state, same results (no save-scumming)")
	a.free()
	b.free()
