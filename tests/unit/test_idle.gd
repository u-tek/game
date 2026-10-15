extends RefCounted
## Idle rewards: accrual, 12 h cap, carry, quick claims, gear drops, notifications.

const BASE_MS := 1_702_083_600_000 # 01:00 UTC
const HOUR := 3600 * 1000


func _game() -> Node:
	var g: Node = load("res://src/core/game.gd").new()
	g.save_path = ""
	g.tz_bias_ms = 0
	g.now_override_ms = BASE_MS
	g.new_game()
	return g


func test_status_shape(t: TestCtx) -> void:
	var g := _game()
	var s: Dictionary = g.idle_status()
	for k in ["elapsed_ms", "cap_ms", "full", "pending", "per_hour", "quick_claims_left", "quick_claim_cost"]:
		t.ok(s.has(k), "idle_status has %s" % k)
	t.eq(s.cap_ms, 12 * HOUR)
	t.eq(s.elapsed_ms, 0)
	t.eq(s.full, false)
	t.eq(s.quick_claims_left, 4)
	t.eq(s.quick_claim_cost, 0, "first quick claim is free")
	g.free()


func test_accrual_and_cap(t: TestCtx) -> void:
	var g := _game()
	var ph: Dictionary = g.idle_status().per_hour
	g.now_override_ms = BASE_MS + 3 * HOUR
	var s: Dictionary = g.idle_status()
	t.eq(s.elapsed_ms, 3 * HOUR)
	t.eq(int(s.pending.gold), int(ph.gold) * 3)
	t.eq(int(s.pending.hero_exp), int(ph.hero_exp) * 3)
	t.eq(int(s.pending.get("gear_count", 0)), 1, "one gear piece per 3 h")
	g.now_override_ms = BASE_MS + 30 * HOUR
	s = g.idle_status()
	t.eq(s.elapsed_ms, 12 * HOUR, "capped at 12 h")
	t.ok(s.full)
	t.eq(int(s.pending.gold), int(ph.gold) * 12)
	var gold: int = g.currency("gold")
	var r: Dictionary = g.claim_idle()
	t.eq(int(r.gold), int(ph.gold) * 12)
	t.eq(g.currency("gold"), gold + int(ph.gold) * 12)
	t.eq(r.get("gear", []).size(), 4, "four gear pieces for 12 h")
	t.eq(g.idle_status().elapsed_ms, 0, "timer restarts after a claim")
	t.eq(g.idle_status().pending.size(), 0)
	g.free()


func test_frequent_claims_lose_nothing(t: TestCtx) -> void:
	var a := _game()
	var b := _game()
	var start_a: int = a.currency("dust")
	var start_b: int = b.currency("dust")
	for i in 72:
		a.now_override_ms = BASE_MS + (i + 1) * 10 * 60 * 1000
		a.claim_idle()
	b.now_override_ms = BASE_MS + 12 * HOUR
	b.claim_idle()
	t.eq(a.currency("dust") - start_a, b.currency("dust") - start_b, "carry keeps fractional dust")
	t.near(float(a.currency("gold")), float(b.currency("gold")), 1.0, "gold equal")
	t.eq(a.gear_items().size(), b.gear_items().size(), "same number of gear drops")
	a.free()
	b.free()


func test_rate_scales_with_stages(t: TestCtx) -> void:
	var g := _game()
	var r0: Dictionary = g.idle_status().per_hour
	g.state.campaign.cleared = 10
	var r10: Dictionary = g.idle_status().per_hour
	g.state.campaign.cleared = 30
	var r30: Dictionary = g.idle_status().per_hour
	for k in ["gold", "hero_exp", "dust"]:
		t.ok(int(r10[k]) > int(r0[k]) and int(r30[k]) > int(r10[k]), "%s grows with progress" % k)
	t.ok(int(r30.gems) > int(r0.gems), "gem trickle grows")
	g.free()


func test_quick_claims(t: TestCtx) -> void:
	var g := _game()
	var ph: Dictionary = g.idle_status().per_hour
	var gems: int = g.currency("gems")
	var gold: int = g.currency("gold")
	var r: Dictionary = g.quick_claim()
	t.ok(r.ok, r.error)
	t.eq(int(r.value.gold), int(ph.gold) * 2, "2 hours of gold")
	t.eq(g.currency("gold"), gold + int(ph.gold) * 2)
	t.eq(g.currency("gems"), gems + int(r.value.get("gems", 0)), "first one is free")
	var costs := [50, 100, 150]
	for c in costs:
		t.eq(g.idle_status().quick_claim_cost, c)
		var before: int = g.currency("gems")
		r = g.quick_claim()
		t.ok(r.ok, r.error)
		t.eq(g.currency("gems"), before - c + int(r.value.get("gems", 0)), "costs %d gems" % c)
	t.eq(g.idle_status().quick_claims_left, 0)
	r = g.quick_claim()
	t.eq(r.ok, false)
	t.eq(r.error, "No quick claims left today")
	# Quick claims don't touch the idle timer.
	t.eq(g.idle_status().elapsed_ms, 0)
	# Next day: reset.
	g.now_override_ms = BASE_MS + 24 * HOUR
	t.eq(g.idle_status().quick_claims_left, 4)
	t.eq(g.idle_status().quick_claim_cost, 0)
	g.free()


func test_quick_claim_needs_gems(t: TestCtx) -> void:
	var g := _game()
	g.quick_claim()
	g.state.currencies.gems = 10
	var r: Dictionary = g.quick_claim()
	t.eq(r.ok, false)
	t.eq(r.error, "Not enough gems")
	t.eq(g.currency("gems"), 10)
	g.free()


func test_gear_auto_equips_on_formation(t: TestCtx) -> void:
	var g := _game()
	g.now_override_ms = BASE_MS + 12 * HOUR
	var r: Dictionary = g.claim_idle()
	var equipped := 0
	for uid in r.gear:
		var it: Dictionary = g.gear_item(uid)
		t.ok(not it.is_empty())
		for k in ["uid", "slot", "tier", "name", "stats", "equipped_by"]:
			t.ok(it.has(k), "gear has %s" % k)
		if it.equipped_by != "":
			equipped += 1
			t.ok(g.formation().has(it.equipped_by), "equipped on a formation hero")
	t.ok(equipped > 0, "new gear was auto-equipped")
	g.free()


func test_idle_full_notify_and_clock_rewind(t: TestCtx) -> void:
	var g := _game()
	var events: Array = []
	g.notify.connect(func(e: Dictionary) -> void: events.append(e.type))
	g.dev_skip_time(13 * HOUR)
	t.ok(events.has("idle_full"), "idle_full notified")
	g.claim_idle()
	# Clock moved backwards: no payout, timer restarts.
	g.now_override_ms = BASE_MS - 5 * HOUR
	t.eq(g.idle_status().elapsed_ms, 0)
	t.eq(g.claim_idle().size(), 0)
	g.free()
