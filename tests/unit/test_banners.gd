extends RefCounted
## The five summon banners (data/banner.json, SummonRules, GameModel.summon): the data, the
## rotations, featured rate-up with its 50/50 and guarantee, the faction pool, the wish target and
## weekly limit, the envoy's gold draw and daily limit, per-banner pity and save migration.

const DAY := 86400000
const HOUR := 3600000


## A fresh game on day `epoch_day + k` at 01:00 (time zone 0).
func _game(k: int = 0) -> Node:
	var g: Node = load("res://src/core/game.gd").new()
	g.save_path = ""
	g.tz_bias_ms = 0
	g.now_override_ms = (EconomyData.BANNER_EPOCH_DAY + k) * DAY + HOUR
	g.new_game()
	return g


func _set_day(g: Node, k: int) -> void:
	g.now_override_ms = (EconomyData.BANNER_EPOCH_DAY + k) * DAY + HOUR


func test_banner_data_is_valid(t: TestCtx) -> void:
	var ids: Array[String] = []
	for b in EconomyData.BANNERS:
		var id := str(b.id)
		ids.append(id)
		t.ok(SummonRules.KINDS.has(str(b.get("kind", ""))), "%s has a known kind" % id)
		var r: Dictionary = b.rates
		t.eq(int(r.legendary) + int(r.epic) + int(r.rare), 10000, "%s rates add up to 100%%" % id)
		for hid in b.pool:
			t.ok(not HeroData.get_def(str(hid)).is_empty(), "%s pool hero %s exists" % [id, hid])
		var factions: Array = b.get("faction_rotation", [""]) if str(b.kind) == "faction" else [""]
		for fac: Variant in factions:
			var pool := SummonRules.pool_by_rarity(b, str(fac))
			for rar in ["rare", "epic", "legendary"]:
				var reachable: bool = int(r[rar]) > 0 or (rar == "legendary" and int(b.get("pity_legendary", 0)) > 0) \
					or str(b.get("ten_pull_guarantee", "")) == rar
				if reachable:
					t.ok(not (pool[rar] as Array).is_empty(), "%s %s has %s heroes" % [id, fac, rar])
		for c in ["cost_one", "cost_ten"]:
			t.ok(not (b[c] as Dictionary).is_empty(), "%s has %s" % [id, c])
	t.eq(ids, ["standard", "featured", "faction", "wish", "envoy"], "banner order")
	var feat := EconomyData.banner_def("featured")
	for hid in feat.featured_rotation:
		t.eq(str(HeroData.get_def(str(hid)).rarity), "legendary", "featured %s is a Legendary" % hid)
		t.ok((feat.pool as Array).has(hid), "featured %s is in the pool" % hid)
	var envoy := EconomyData.banner_def("envoy")
	t.eq(int(envoy.rates.legendary), 0, "envoy has no Legendary rate")
	t.eq(int(envoy.pity_legendary), 0, "envoy has no pity")
	t.eq((SummonRules.pool_by_rarity(envoy).legendary as Array).size(), 0, "envoy pool has no Legendary")
	t.eq(SummonRules.wish_choices(EconomyData.banner_def("wish")).size(), 9, "nine Legendaries to wish for")


func test_banner_views(t: TestCtx) -> void:
	var g := _game()
	var all: Array = g.banners()
	t.eq(all.size(), 5)
	t.eq(str(all[0].id), "standard")
	t.eq(str(g.banner().id), "standard", "banner() is still the standard banner")
	t.eq(g.banner().cost_one, 300)
	var fb: Dictionary = g.banner("featured")
	t.eq(str(fb.featured), "mordessa", "week 0 features the first of the rotation")
	t.eq(int(fb.next_change_day), EconomyData.BANNER_EPOCH_DAY + 7)
	t.eq(int(fb.ms_until_change), 7 * DAY - HOUR, "featured changes in 6 days 23 hours")
	var cb: Dictionary = g.banner("faction")
	t.eq(str(cb.faction), "fallen")
	t.eq(cb.pool, ["noctaire", "orrin", "sable", "lucen", "ashra", "nadira", "gantra", "severine", "benthe", "seyra",
		"rivette", "vandra", "ombre"], "today's pool is the faction's, in pool order")
	t.eq(int(cb.ms_until_change), DAY - HOUR)
	var eb: Dictionary = g.banner("envoy")
	t.eq(str(eb.currency), "gold")
	t.eq(eb.cost_one, 5000)
	t.eq(eb.scroll_cost_one, 0, "envoy takes no scrolls")
	t.eq(eb.limit_left, 10)
	var wb: Dictionary = g.banner("wish")
	t.eq(str(wb.target), "")
	t.eq(wb.limit_left, 30)
	t.eq(wb.limit_period, "week")
	t.eq(g.banner("nope"), {}, "unknown banner")
	g.free()


func test_rotations(t: TestCtx) -> void:
	var fb := EconomyData.banner_def("featured")
	var cb := EconomyData.banner_def("faction")
	var e := EconomyData.BANNER_EPOCH_DAY
	var want_f := {0: "mordessa", 6: "mordessa", 7: "noctaire", 13: "noctaire", 14: "seraphiel", 21: "drezza", 56: "sanariel",
		63: "mordessa", -1: "sanariel", -7: "sanariel", -8: "gantra"}
	for k: int in want_f:
		t.eq(SummonRules.featured_for(fb, e + k, e), want_f[k], "featured on day %d" % k)
	var want_c := {0: "fallen", 1: "celestial", 2: "infernal", 3: "fallen", -1: "infernal", -3: "fallen"}
	for k: int in want_c:
		t.eq(SummonRules.faction_for(cb, e + k, e), want_c[k], "faction on day %d" % k)
	t.eq(SummonRules.period_index(e - 1, e, 7), -1, "floor before the epoch")
	t.eq(SummonRules.period_index(e - 7, e, 7), -1)
	t.eq(SummonRules.period_index(e - 8, e, 7), -2)
	t.eq(SummonRules.next_change_day(e + 3, e, 7), e + 7)
	t.eq(SummonRules.next_change_day(e - 3, e, 7), e)
	t.eq(SummonRules.featured_for(cb, e, e), "", "only the featured banner has a featured hero")
	# The model follows the clock's day.
	var g := _game(9)
	t.eq(str(g.banner("featured").featured), "noctaire")
	t.eq(str(g.banner("faction").faction), "fallen")
	_set_day(g, 10)
	t.eq(str(g.banner("faction").faction), "celestial")
	g.free()


func test_featured_5050_and_guarantee(t: TestCtx) -> void:
	var b := EconomyData.banner_def("featured")
	var wins := 0
	var n := 3000
	for s in n:
		var r := SummonRules.pull(b, 1000 + s, 0, 59, 1, {"featured": "noctaire", "lost": false})
		var p: Dictionary = r.results[0]
		t.eq(p.rarity, "legendary")
		if p.hero_id == "noctaire":
			wins += 1
			t.eq(r.lost, false)
			t.eq(p.featured, true)
		else:
			t.ok(p.hero_id != "noctaire" and str(HeroData.get_def(str(p.hero_id)).rarity) == "legendary", "a lost 50/50 gives another Legendary")
			t.eq(r.lost, true, "a lost 50/50 sets the guarantee")
			t.eq(p.featured, false)
	t.near(float(wins) / n, 0.5, 0.04, "featured wins about half of the 50/50s")
	for s in 300:
		var r := SummonRules.pull(b, 77 + s, 5, 59, 1, {"featured": "noctaire", "lost": true})
		t.eq(r.results[0].hero_id, "noctaire", "after a loss the next Legendary is the featured one")
		t.eq(r.lost, false, "the guarantee is used up")
	# A long run in the model: after every lost 50/50 the next Legendary is featured.
	var g := _game()
	g.dev_add("gems", 2700 * 120)
	g.state.currencies.scrolls = 0
	var last_lost := false
	var legends := 0
	var max_gap := 0
	var gap := 0
	for i in 120:
		var r: Dictionary = g.summon(10, false, "featured")
		t.ok(r.ok, r.error)
		for p in r.value:
			gap += 1
			t.ok(p.has("featured"), "featured banner results say whether they are featured")
			if p.rarity == "legendary":
				legends += 1
				max_gap = maxi(max_gap, gap)
				gap = 0
				if last_lost:
					t.eq(p.hero_id, "mordessa", "guarantee after a loss")
				last_lost = p.hero_id != "mordessa"
				t.eq(bool(p.featured), p.hero_id == "mordessa")
	t.ok(legends >= 15, "1200 pulls give many Legendaries (%d)" % legends)
	t.ok(max_gap <= 60, "featured pity holds (max gap %d)" % max_gap)
	t.eq(g.pity_count(), 0, "the standard banner's pity is untouched")
	t.eq(bool(g.banner("featured").lost), last_lost, "the lost flag is saved")
	g.free()


func test_faction_pool_and_pity(t: TestCtx) -> void:
	var g := _game(1) # celestial
	g.dev_add("gems", 2700 * 60)
	g.state.currencies.scrolls = 0
	var counts := {"rare": 0, "epic": 0, "legendary": 0}
	var gap := 0
	var max_gap := 0
	for i in 60:
		var r: Dictionary = g.summon(10, false, "faction")
		t.ok(r.ok, r.error)
		for p in r.value:
			t.eq(str(g.hero_def(p.hero_id).faction), "celestial", "faction focus gives only celestials")
			counts[p.rarity] += 1
			gap += 1
			if p.rarity == "legendary":
				t.ok(SummonRules.pool_by_rarity(EconomyData.banner_def("faction"), "celestial").legendary.has(p.hero_id), "a celestial Legendary")
				max_gap = maxi(max_gap, gap)
				gap = 0
	t.ok(max_gap <= 80, "faction pity is 80 (max gap %d)" % max_gap)
	t.ok(counts.legendary >= 4, "legendaries do come (%d)" % counts.legendary)
	t.near(float(counts.epic) / 600.0, 0.24, 0.06, "epic about 24%")
	t.eq(g.pity_count(), 0, "standard pity untouched")
	t.eq(g.pity_count("faction"), gap, "the faction banner keeps its own pity")
	# The pity carries over when the faction changes.
	_set_day(g, 2)
	t.eq(str(g.banner("faction").faction), "infernal")
	t.eq(g.pity_count("faction"), gap)
	var r2: Dictionary = g.summon(1, false, "faction")
	t.eq(str(g.hero_def(r2.value[0].hero_id).faction), "infernal")
	g.free()


func test_wish_target_cost_and_weekly_limit(t: TestCtx) -> void:
	var g := _game(2)
	g.dev_add("gems", 100000)
	g.state.currencies.scrolls = 0
	var r: Dictionary = g.summon(1, false, "wish")
	t.eq(r.ok, false)
	t.eq(r.error, "Choose your wish first")
	t.eq(g.set_wish_target("uriela").ok, false, "only a Legendary can be wished for")
	t.eq(g.set_wish_target("seraphiel", "standard").ok, false, "only on the wish banner")
	t.ok(g.set_wish_target("noctaire").ok)
	t.eq(g.wish_target(), "noctaire")
	var gems: int = g.currency("gems")
	g.state.summon.banners.wish.pity = 59
	r = g.summon(1, false, "wish")
	t.ok(r.ok, r.error)
	t.eq(r.value[0].hero_id, "noctaire", "the wish pity gives the target")
	t.eq(g.currency("gems"), gems - 450, "a wish costs 450 gems")
	r = g.summon(10, false, "wish")
	t.eq(g.currency("gems"), gems - 450 - 4050, "ten wishes cost 4050 gems")
	g.dev_add("scrolls", 2)
	g.summon(1, false, "wish")
	t.eq(g.currency("scrolls"), 0, "a wish takes 2 scrolls first")
	t.eq(g.summon_left("wish"), 30 - 12)
	g.summon(10, false, "wish")
	t.eq(g.summon_left("wish"), 8)
	r = g.summon(10, false, "wish")
	t.eq(r.ok, false, "the weekly limit stops a 10-pull with 8 left")
	t.eq(r.error, "Only 8 pulls left this week")
	var spent: int = g.currency("gems")
	for i in 8:
		t.ok(g.summon(1, false, "wish").ok)
	r = g.summon(1, false, "wish")
	t.eq(r.error, "No pulls left this week")
	t.eq(g.currency("gems"), spent - 8 * 450, "a refused pull costs nothing")
	_set_day(g, 6)
	t.eq(g.summon_left("wish"), 0, "same week")
	_set_day(g, 7)
	t.eq(g.summon_left("wish"), 30, "a new week")
	# Every Legendary from the wish banner is the target.
	# Every Legendary from the wish banner is the target (34 weeks of three 10-pulls).
	g.set_wish_target("mordessa")
	g.dev_add("gems", 4050 * 102)
	var legends := 0
	for w in 34:
		_set_day(g, 7 + 7 * w)
		for i in 3:
			var rw: Dictionary = g.summon(10, false, "wish")
			t.ok(rw.ok, rw.error)
			for p in (rw.value if rw.ok else []):
				if p.rarity == "legendary":
					legends += 1
					t.eq(p.hero_id, "mordessa", "a wish Legendary is the target")
		t.eq(g.summon_left("wish"), 0)
	t.ok(legends >= 15, "legendaries do come (%d)" % legends)
	g.free()


func test_envoy_gold_daily_limit_no_legendary(t: TestCtx) -> void:
	var g := _game()
	g.state.currencies.gold = 0
	var r: Dictionary = g.summon(1, false, "envoy")
	t.eq(r.error, "Not enough gold")
	g.dev_add("gold", 1000000)
	var scrolls: int = g.currency("scrolls")
	var gems: int = g.currency("gems")
	r = g.summon(10, false, "envoy")
	t.ok(r.ok, r.error)
	t.eq(g.currency("gold"), 1000000 - 45000, "ten envoy draws cost 45000 gold")
	t.eq(g.currency("scrolls"), scrolls, "scrolls untouched")
	t.eq(g.currency("gems"), gems, "gems untouched")
	t.eq(g.summon_left("envoy"), 0)
	r = g.summon(1, false, "envoy")
	t.eq(r.error, "No pulls left today")
	_set_day(g, 1)
	t.eq(g.summon_left("envoy"), 10, "a new day")
	t.ok(g.summon(1, false, "envoy").ok)
	t.eq(g.currency("gold"), 1000000 - 50000, "one envoy draw costs 5000 gold")
	var epics := 0
	for d in range(2, 60):
		_set_day(g, d)
		g.dev_add("gold", 45000)
		var rr: Dictionary = g.summon(10, false, "envoy")
		t.ok(rr.ok, rr.error)
		var best := false
		for p in rr.value:
			t.ok(p.rarity != "legendary", "no Legendary from the envoy")
			if p.rarity == "epic":
				epics += 1
				best = true
		t.ok(best, "an envoy 10-pull has an Epic")
	t.eq(g.pity_count("envoy"), 0, "the envoy has no pity")
	t.near(float(epics) / 580.0, 0.16, 0.05, "epic about 15% plus the guarantee")
	g.free()


func test_free_pull_is_the_standard_banners(t: TestCtx) -> void:
	var g := _game()
	var r: Dictionary = g.summon(1, true, "featured")
	t.eq(r.ok, false)
	t.eq(r.error, "No free summon on this banner")
	t.ok(g.free_pull_available(), "the free pull is still there")
	t.ok(g.summon(1, true).ok)
	t.eq(g.summon(1, false, "nope").error, "Unknown banner")
	g.free()


func test_pity_counters_are_per_banner(t: TestCtx) -> void:
	var g := _game()
	g.dev_add("gems", 50000)
	g.state.currencies.scrolls = 0
	g.state.summon.pity = 30
	var total: int = g.state.summon.total_pulls
	g.summon(10, false, "featured")
	g.summon(10, false, "faction")
	t.eq(g.pity_count(), 30, "standard pity untouched by other banners")
	t.eq(int(g.state.summon.total_pulls), total + 20, "every pull advances the shared random stream")
	t.ok(g.pity_count("featured") <= 10)
	g.summon(1)
	t.eq(g.pity_count(), 31)
	g.free()


func test_old_save_keeps_counters(t: TestCtx) -> void:
	var g := _game()
	var old := {"version": 1, "created_at": 1, "heroes": {"uriela": {"id": "uriela"}},
		"summon": {"pity": 37, "total_pulls": 120, "last_free_pull_day": 5, "seed": 4242}}
	var s: Dictionary = g.model.migrate(old)
	t.eq(int(s.summon.pity), 37, "standard pity carries over")
	t.eq(int(s.summon.total_pulls), 120, "pull counter carries over")
	t.eq(int(s.summon.seed), 4242)
	t.eq(int(s.summon.last_free_pull_day), 5)
	t.eq((s.summon.banners as Dictionary).keys(), ["featured", "faction", "wish", "envoy"], "every other banner gets a state")
	t.eq(int(s.summon.banners.featured.pity), 0)
	t.eq(g.pity_count(), 37)
	# Damaged values are repaired.
	var bad := {"version": 1, "heroes": {"kessa": {"id": "kessa"}}, "summon": {"pity": 99, "total_pulls": -3,
		"banners": {"wish": {"target": "uriela", "pity": 70}, "featured": {"lost": "yes", "pity": -2}, "x": {}}}}
	s = g.model.migrate(bad)
	t.eq(int(s.summon.pity), 59)
	t.eq(int(s.summon.total_pulls), 0)
	t.eq(str(s.summon.banners.wish.target), "", "a target that is no choice is dropped")
	t.eq(int(s.summon.banners.wish.pity), 59)
	t.eq(bool(s.summon.banners.featured.lost), false)
	t.eq(int(s.summon.banners.featured.pity), 0)
	t.ok(not (s.summon.banners as Dictionary).has("x"), "unknown banners dropped")
	g.free()
