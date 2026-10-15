extends RefCounted
## Daily quests (counters, claim, reset at local midnight) and shop offers (limits).

const BASE_MS := 1_702_083_600_000 # 01:00 UTC
const DAY := 24 * 3600 * 1000


func _game() -> Node:
	var g: Node = load("res://src/core/game.gd").new()
	g.save_path = ""
	g.tz_bias_ms = 0
	g.now_override_ms = BASE_MS
	g.new_game()
	return g


func _quest(g: Node, id: String) -> Dictionary:
	for q in g.quests():
		if q.id == id:
			return q
	return {}


func test_quest_list_shape(t: TestCtx) -> void:
	var g := _game()
	var qs: Array = g.quests()
	t.ok(qs.size() >= 5, "about six daily quests")
	for q in qs:
		for k in ["id", "title", "progress", "goal", "reward", "claimed"]:
			t.ok(q.has(k), "quest has %s" % k)
		t.eq(q.progress, 0)
		t.ok(int(q.reward.get("gems", 0)) > 0 or int(q.reward.get("scrolls", 0)) > 0 or int(q.reward.get("gold", 0)) > 0)
	g.free()


func test_progress_claim_and_notify(t: TestCtx) -> void:
	var g := _game()
	var events: Array = []
	g.notify.connect(func(e: Dictionary) -> void: events.append(e))
	t.eq(g.claim_quest("dq_summon").ok, false, "not finished yet")
	g.summon(1, true)
	var q := _quest(g, "dq_summon")
	t.eq(q.progress, 1)
	t.ok(q.ready)
	var ready := false
	for e in events:
		if e.type == "quest_ready" and e.id == "dq_summon":
			ready = true
	t.ok(ready, "quest_ready notified")
	var gems: int = g.currency("gems")
	var r: Dictionary = g.claim_quest("dq_summon")
	t.ok(r.ok, r.error)
	t.eq(g.currency("gems"), gems + int(q.reward.gems))
	t.ok(_quest(g, "dq_summon").claimed)
	t.eq(g.claim_quest("dq_summon").ok, false, "only once")
	t.eq(g.claim_quest("nope").ok, false)
	g.free()


func test_battles_and_levels_drive_quests(t: TestCtx) -> void:
	var g := _game()
	for i in 3:
		g.complete_stage(0, {"victory": true})
	t.eq(_quest(g, "dq_win").progress, 3)
	g.complete_stage(0, {"victory": false})
	t.eq(_quest(g, "dq_win").progress, 3, "losses don't count")
	g.level_up_many("uriela", 5)
	t.eq(_quest(g, "dq_level").progress, 5)
	g.quick_claim()
	t.eq(_quest(g, "dq_quick").progress, 1)
	g.now_override_ms = BASE_MS + 3600000
	g.claim_idle()
	g.now_override_ms = BASE_MS + 7200000
	g.claim_idle()
	t.eq(_quest(g, "dq_idle").progress, 2)
	g.free()


func test_meta_quest_counts_claims(t: TestCtx) -> void:
	var g := _game()
	g.summon(1, true)
	g.quick_claim()
	g.claim_quest("dq_summon")
	g.claim_quest("dq_quick")
	t.eq(_quest(g, "dq_all").progress, 2)
	g.free()


func test_daily_reset_at_local_midnight(t: TestCtx) -> void:
	var g := _game()
	g.summon(1, true)
	g.claim_quest("dq_summon")
	t.ok(_quest(g, "dq_summon").claimed)
	# 22:59 the same day: still the same day.
	g.now_override_ms = BASE_MS + 22 * 3600000 - 60000
	t.ok(_quest(g, "dq_summon").claimed)
	# After midnight: fresh quests.
	g.now_override_ms = BASE_MS + 23 * 3600000 + 1000
	var q := _quest(g, "dq_summon")
	t.eq(q.claimed, false)
	t.eq(q.progress, 0)
	# Midnight follows the player's time zone.
	g.tz_bias_ms = 2 * 3600000
	g.now_override_ms = BASE_MS + 23 * 3600000 + 1000
	t.eq(g.today(), g.day_of(BASE_MS + 23 * 3600000 + 1000))
	t.eq(g.day_of(BASE_MS + 21 * 3600000 + 1000), g.day_of(BASE_MS + 23 * 3600000), "UTC+2 day boundary is 22:00 UTC")
	g.free()


func test_offers_shape_and_free_purchase(t: TestCtx) -> void:
	var g := _game()
	var offers: Array = g.offers()
	t.ok(offers.size() >= 5)
	var ids := {}
	for o in offers:
		ids[o.id] = true
		for k in ["id", "name", "description", "price_label", "reward", "limit", "purchased", "tag"]:
			t.ok(o.has(k), "offer has %s" % k)
	for id in ["starter_pack", "monthly_card", "scroll_bundle", "gems_s"]:
		t.ok(ids.has(id), "offer %s exists" % id)
	var gems: int = g.currency("gems")
	var r: Dictionary = g.buy_offer("gems_s")
	t.ok(r.ok)
	t.eq(g.currency("gems"), gems + 330, "test purchase grants the reward")
	g.free()


func test_offer_limits(t: TestCtx) -> void:
	var g := _game()
	t.ok(g.buy_offer("starter_pack").ok)
	var r: Dictionary = g.buy_offer("starter_pack")
	t.eq(r.ok, false, "starter pack once")
	t.eq(r.error, "Purchase limit reached")
	for i in 3:
		t.ok(g.buy_offer("scroll_bundle").ok)
	t.eq(g.buy_offer("scroll_bundle").ok, false, "scroll bundle limit 3")
	for i in 5:
		t.ok(g.buy_offer("gems_m").ok, "gem packs unlimited")
	t.ok(g.buy_offer("daily_gift").ok)
	t.eq(g.buy_offer("daily_gift").ok, false, "daily gift once a day")
	var gift := {}
	for o in g.offers():
		if o.id == "daily_gift":
			gift = o
	t.eq(gift.purchased, 1)
	t.eq(gift.available, false)
	g.now_override_ms = BASE_MS + DAY
	t.ok(g.buy_offer("daily_gift").ok, "daily gift resets")
	t.eq(g.buy_offer("starter_pack").ok, false, "lifetime limits don't reset")
	t.eq(g.buy_offer("nope").ok, false)
	g.free()


func test_monthly_card(t: TestCtx) -> void:
	var g := _game()
	var gems: int = g.currency("gems")
	t.ok(g.buy_offer("monthly_card").ok)
	t.eq(g.currency("gems"), gems + 300, "300 now")
	t.eq(g.monthly_card_days_left(), 30)
	g.offers() # same day: no extra payout
	t.eq(g.currency("gems"), gems + 300)
	for d in range(1, 31):
		g.now_override_ms = BASE_MS + d * DAY
		g.quests()
	t.eq(g.currency("gems"), gems + 300 + 30 * 100, "100 a day for 30 days")
	g.now_override_ms = BASE_MS + 31 * DAY
	g.quests()
	t.eq(g.currency("gems"), gems + 300 + 30 * 100, "then it stops")
	t.eq(g.monthly_card_days_left(), 0)
	g.free()
