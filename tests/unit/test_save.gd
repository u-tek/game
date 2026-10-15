extends RefCounted
## Save/load: round trip, defaults-merge for old saves, corrupted saves, rich test state.

const BASE_MS := 1_702_083_600_000
const PATH := "user://unit_test_save.json"


func _game(path: String = "") -> Node:
	var g: Node = load("res://src/core/game.gd").new()
	g.save_path = path
	g.tz_bias_ms = 0
	g.now_override_ms = BASE_MS
	return g


func _cleanup() -> void:
	for f in DirAccess.get_files_at("user://"):
		if f.begins_with("unit_test_save"):
			DirAccess.remove_absolute(ProjectSettings.globalize_path("user://" + f))


func test_round_trip(t: TestCtx) -> void:
	_cleanup()
	var a := _game(PATH)
	a.new_game()
	a.dev_add("gems", 1234)
	a.summon(10)
	a.dev_skip_time(3 * 3600 * 1000)
	a.claim_idle()
	a.level_up("uriela")
	a.set_setting("battle_speed", 2)
	a.save()
	t.ok(FileAccess.file_exists(PATH), "save written")
	var b := _game(PATH)
	b.load_or_create()
	t.eq(JSON.stringify(b.state), JSON.stringify(a.state), "state survives a round trip")
	t.ok(b.state.currencies.gems is int, "numbers load back as ints")
	t.ok(b.state.heroes.uriela.level is int)
	t.eq(b.setting("battle_speed"), 2)
	t.eq(b.owned_heroes().size(), a.owned_heroes().size())
	a.free()
	b.free()
	_cleanup()


func test_defaults_merge_for_missing_keys(t: TestCtx) -> void:
	_cleanup()
	# An "old" save: missing settings, shop, idle.carry, counters and a hero's gear map.
	var old := {
		"version": 1, "created_at": BASE_MS, "player_name": "Old",
		"currencies": {"gold": 77, "gems": 5},
		"heroes": {"uriela": {"id": "uriela", "level": 7, "stars": 2}, "ghost": {"id": "ghost", "level": 3}},
		"formation": ["uriela", "ghost", "", ""],
		"campaign": {"cleared": 4},
		"idle": {"last_claim_at": BASE_MS - 3600000},
	}
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(old))
	f.close()
	var g := _game(PATH)
	g.load_or_create()
	t.eq(g.state.player_name, "Old")
	t.eq(g.currency("gold"), 77, "kept existing values")
	t.eq(g.currency("scrolls"), 0, "missing currency defaults (scrolls)")
	t.eq(g.cleared_count(), 4)
	t.eq(g.setting("auto_ultimates"), true, "settings filled from defaults")
	t.eq(g.setting("battle_speed"), 1)
	t.ok(g.state.shop.has("purchases"), "shop filled")
	t.ok(g.state.idle.has("carry") and g.state.idle.has("quick_claims_used"), "idle filled")
	t.eq(int(g.hero("uriela").level), 7)
	t.eq(g.hero("uriela").gear, {}, "hero gear map added")
	t.eq(g.owns("ghost"), false, "unknown heroes dropped")
	t.eq(g.formation(), ["uriela", "", "", "", ""], "formation repaired")
	t.ok(g.idle_status().elapsed_ms >= 3600000, "idle timer kept")
	g.free()
	_cleanup()


func test_corrupted_save_is_backed_up(t: TestCtx) -> void:
	_cleanup()
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string("{this is not json")
	f.close()
	var g := _game(PATH)
	g.load_or_create()
	t.eq(g.owned_heroes().size(), 3, "fresh game after a corrupted save")
	var backups := 0
	for name in DirAccess.get_files_at("user://"):
		if name.begins_with("unit_test_save.corrupt-"):
			backups += 1
			t.eq(FileAccess.get_file_as_string("user://" + name), "{this is not json", "backup keeps the bad text")
	t.eq(backups, 1, "one backup written")
	# And the replacement save is valid JSON again.
	var j := JSON.new()
	t.eq(j.parse(FileAccess.get_file_as_string(PATH)), OK)
	g.free()
	_cleanup()


func test_missing_save_creates_new_game(t: TestCtx) -> void:
	_cleanup()
	var g := _game(PATH)
	g.load_or_create()
	t.eq(g.owned_heroes().size(), 3)
	t.ok(FileAccess.file_exists(PATH))
	t.eq(int(g.state.version), g.SAVE_VERSION)
	g.free()
	_cleanup()


func test_reset_save(t: TestCtx) -> void:
	_cleanup()
	var g := _game(PATH)
	g.load_or_create()
	g.dev_add("gems", 5000)
	g.reset_save()
	t.eq(g.currency("gems"), 1800)
	g.free()
	_cleanup()


func test_rich_state(t: TestCtx) -> void:
	var g := _game()
	g.make_rich_state()
	t.eq(g.owned_heroes().size(), 15)
	t.eq(g.currency("gems"), 50000)
	t.eq(g.currency("gold"), 500000)
	t.eq(g.currency("hero_exp"), 300000)
	t.eq(g.currency("scrolls"), 30)
	t.eq(g.currency("dust"), 2000)
	t.eq(g.cleared_count(), 12)
	t.eq(g.gear_items().size(), 10)
	var equipped := 0
	for it in g.gear_items():
		if it.equipped_by != "":
			equipped += 1
	t.ok(equipped > 0 and equipped < 10, "some gear equipped (%d)" % equipped)
	t.near(float(g.idle_status().elapsed_ms), 5.0 * 3600000.0, 1000.0, "idle 5 h")
	var progress := 0
	for q in g.quests():
		progress += int(q.progress)
	t.ok(progress > 0, "some quest progress")
	var levels := {}
	for h in g.owned_heroes():
		levels[h.level] = true
		t.ok(int(h.level) <= g.max_level(h.id))
	t.ok(levels.size() > 5, "varied levels")
	t.eq(g.formation().has(""), false)
	g.free()
