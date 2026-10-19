extends RefCounted
## Golden fixtures (data/fixtures/*.json, see tests/golden.gd): the rules must reproduce every
## stored output exactly. A Unity/C# port runs the same checks (docs/dev/unity-port.md).
## A failure after a change that should not alter results is a bug. After an intended rules
## or tuning change, regenerate: tools/gd --headless --path . -s tests/tools/make_fixtures.gd

const Golden := preload("res://tests/golden.gd")


func _stored(name: String) -> Dictionary:
	var path := "res://data/fixtures/%s.json" % name
	if not FileAccess.file_exists(path):
		return {}
	var v: Variant = GameData.intify(JSON.parse_string(FileAccess.get_file_as_string(path)))
	return v if v is Dictionary else {}


func _check(t: TestCtx, name: String) -> Dictionary:
	var stored := _stored(name)
	if stored.is_empty():
		t.ok(false, "data/fixtures/%s.json missing or invalid (run tests/tools/make_fixtures.gd)" % name)
		return {}
	var fresh: Variant = Golden.normalize(Golden.compute(name, stored))
	var d := Golden.diff(stored, fresh)
	t.eq(d, "", "%s.json no longer matches the rules" % name)
	return stored


func test_fixture_rng(t: TestCtx) -> void:
	var f := _check(t, "rng")
	if not f.is_empty():
		t.eq(f.sequences[0].seed, 12345)
		t.eq(f.sequences[0].next_u32.slice(0, 3), [1330226942, 157105557, 1930860194], "same reference as test_rng")


func test_fixture_progression(t: TestCtx) -> void:
	var f := _check(t, "progression")
	if not f.is_empty():
		t.eq(f.level_cost.size(), 139, "every level 1..139")


func test_fixture_idle(t: TestCtx) -> void:
	_check(t, "idle")


func test_fixture_gear(t: TestCtx) -> void:
	_check(t, "gear")


func test_fixture_stats(t: TestCtx) -> void:
	var f := _check(t, "stats")
	if not f.is_empty():
		t.eq(f.stages.size(), StageData.count(), "every stage's enemies recorded")


func test_fixture_summon(t: TestCtx) -> void:
	var f := _check(t, "summon")
	if f.is_empty():
		return
	var names := {}
	for c in f.cases:
		names[c.name] = c
	var forced: Dictionary = names.get("ten_pull_guarantee_upgrades_tenth", {})
	t.ok(not forced.is_empty() and forced.out[0].results[9].rarity == "epic", "guarantee case ends in an Epic")
	t.eq(names.pity_59_forces_legendary.out[0].results[0].rarity, "legendary")
	# The banner cases must cover what a port has to get right: a won and a lost 50/50, the
	# guarantee after a loss, a faction-only pool, the wish target and an envoy without Legendaries.
	var bn := {}
	for c in f.get("banner_cases", []):
		bn[c.name] = c
	t.eq(bn.size(), 9, "nine banner cases")
	var won := false
	var lost_then_featured := false
	var lost_any := false
	var prev_lost := false
	for o in bn.featured_long_chain.out:
		for r in o.results:
			if r.rarity == "legendary":
				if r.featured and not prev_lost:
					won = true
				if r.featured and prev_lost:
					lost_then_featured = true
				if not r.featured:
					lost_any = true
				prev_lost = not r.featured
	t.ok(won and lost_any and lost_then_featured, "featured chain has a won 50/50, a lost one and the guarantee")
	t.eq(bn.featured_lost_forces_featured.out[0].results[0].hero_id, "noctaire")
	for o in bn.faction_celestial_chain.out:
		for r in o.results:
			t.eq(str(HeroData.get_def(r.hero_id).faction), "celestial")
	var wished := 0
	for o in bn.wish_target_chain.out:
		for r in o.results:
			if r.rarity == "legendary":
				wished += 1
				t.eq(r.hero_id, "noctaire")
	t.ok(wished > 0, "the wish chain has a Legendary")
	for o in bn.envoy_no_legendary.out:
		for r in o.results:
			t.ok(r.rarity != "legendary")
	t.eq(f.rotation.size(), 16)


func test_fixture_battles(t: TestCtx) -> void:
	var f := _check(t, "battles")
	if f.is_empty():
		return
	t.ok(f.battles.size() >= 3, "at least 3 battles")
	# Together the battles must exercise every event kind and flag a port has to reproduce.
	var seen := {}
	for b in f.battles:
		t.eq(b.events.back().type, "end", "%s ends with an end event" % b.name)
		if b.has("skip_outcome"):
			t.eq(b.skip_outcome, b.outcome, "%s: skip equals watching" % b.name)
		for e in b.events:
			seen[e.type] = true
			for k in ["crit", "advantage", "from_ultimate", "dot", "execute", "timeout"]:
				if e.get(k, false) == true:
					seen[k] = true
	for k in ["attack", "damage", "heal", "shield", "status", "ultimate", "energy", "death", "end",
			"crit", "advantage", "from_ultimate", "dot", "execute", "timeout"]:
		t.ok(seen.has(k), "battle fixtures cover '%s'" % k)


func test_fixture_session(t: TestCtx) -> void:
	var f := _check(t, "session")
	if not f.is_empty():
		t.ok(int(f.final_state.campaign.cleared) >= 3, "the scripted player clears some stages")


func test_fixture_save(t: TestCtx) -> void:
	var f := _check(t, "save")
	for c in f.get("cases", []):
		if c.name == "current_save_unchanged":
			t.eq(Golden.diff(c.input, c.out), "", "a valid current save passes migrate unchanged")
