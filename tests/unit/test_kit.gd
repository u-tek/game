extends RefCounted
## UI shell: Kit's pure helpers (no scene tree needed).


func test_format_num_compact(t: TestCtx) -> void:
	t.eq(Kit.format_num(0), "0")
	t.eq(Kit.format_num(950), "950")
	t.eq(Kit.format_num(1800), "1,800")
	t.eq(Kit.format_num(9999), "9,999")
	t.eq(Kit.format_num(12500), "12.5K")
	t.eq(Kit.format_num(12000), "12K")
	t.eq(Kit.format_num(125400), "125K")
	t.eq(Kit.format_num(3400000), "3.4M")
	t.eq(Kit.format_num(1250000000), "1.2B")
	t.eq(Kit.format_num(-12500), "-12.5K")


func test_format_full(t: TestCtx) -> void:
	t.eq(Kit.format_full(0), "0")
	t.eq(Kit.format_full(999), "999")
	t.eq(Kit.format_full(1000), "1,000")
	t.eq(Kit.format_full(1234567), "1,234,567")
	t.eq(Kit.format_full(-2700), "-2,700")


func test_format_time(t: TestCtx) -> void:
	t.eq(Kit.format_time(45000), "45s")
	t.eq(Kit.format_time(725000), "12m 05s")
	t.eq(Kit.format_time(7500000), "2h 05m")
	t.eq(Kit.format_time(-5), "0s")


func test_reward_entries_order(t: TestCtx) -> void:
	var e := Kit.reward_entries({"gold": 100, "gems": 5, "heroes": ["seraphiel"], "shards": {"kessa": 10}, "dust": 0})
	t.eq(e.size(), 4)
	t.eq(e[0].kind, "hero")
	t.eq(e[1].kind, "shard")
	t.eq(e[1].amount, 10)
	t.eq(e[2].id, "gems")
	t.eq(e[3].id, "gold")


func test_colors(t: TestCtx) -> void:
	t.eq(Kit.rarity_color("legendary"), Kit.LEGENDARY)
	t.eq(Kit.faction_color("infernal"), Kit.EMBER)
	t.eq(Kit.tier_color(9), Kit.LEGENDARY)
