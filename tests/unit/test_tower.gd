extends RefCounted
## The Spire (data/tower.json, TowerData, GameModel tower_*): floor building (deterministic,
## difficulty never drops, bosses, rewards), the unlock, the climb (only the next floor, rewards
## once), losing, and the save round trip and migration.

const BASE_MS := 1_702_083_600_000
const PATH := "user://unit_test_save_tower.json"


func _game(path: String = "") -> Node:
	var g: Node = load("res://src/core/game.gd").new()
	g.save_path = path
	g.tz_bias_ms = 0
	g.now_override_ms = BASE_MS
	return g


func _cleanup() -> void:
	for f in DirAccess.get_files_at("user://"):
		if f.begins_with("unit_test_save_tower"):
			DirAccess.remove_absolute(ProjectSettings.globalize_path("user://" + f))


func test_floors_are_built_from_rules(t: TestCtx) -> void:
	t.eq(TowerData.get_floor(0), {}, "no floor 0")
	t.eq(TowerData.get_floor(TowerData.FLOORS + 1), {}, "no floor past the top")
	var prev_level := 0
	var prev_rec := 0
	for f in range(1, TowerData.FLOORS + 1):
		var fl := TowerData.get_floor(f)
		t.eq(fl.id, "F%d" % f)
		t.eq((fl.enemies as Array).size(), 5, "floor %d has five echoes" % f)
		var heroes := {}
		var bosses := 0
		var slots: Array = []
		var lv := 0
		for e in fl.enemies:
			t.ok(not HeroData.get_def(e.hero_id).is_empty(), "echo of a roster hero")
			t.ok(not heroes.has(e.hero_id), "floor %d: no hero twice" % f)
			heroes[e.hero_id] = true
			slots.append(int(e.slot))
			if e.is_boss:
				bosses += 1
				t.eq(int(e.slot), 2, "the boss leads from slot 2")
			lv = int(e.level)
		t.eq(slots, [0, 1, 2, 3, 4], "slots in order")
		t.eq(bosses, 1 if f % 10 == 0 else 0, "floor %d boss count" % f)
		t.eq(bool(fl.is_boss), f % 10 == 0)
		t.ok(lv >= prev_level, "levels never drop (floor %d)" % f)
		t.ok(int(fl.recommended_power) >= prev_rec, "recommended power never drops (floor %d)" % f)
		prev_level = lv
		prev_rec = int(fl.recommended_power)
		var r: Dictionary = fl.first_clear_reward
		t.ok(int(r.get("gold", 0)) > 0 and int(r.get("hero_exp", 0)) > 0 and int(r.get("dust", 0)) > 0)
		t.eq(int(r.get("gems", 0)) > 0, f % 5 == 0, "gems every fifth floor (%d)" % f)
		t.eq(r.has("gear_drops"), f % 10 == 0, "gear on boss floors (%d)" % f)
		t.ok(HeroArt.background(str(fl.background)) != null, "floor %d backdrop art" % f)
	# Floor f fights at campaign stage f's level; past the campaign, one more level per floor.
	var n := StageData.count()
	t.eq(int(TowerData.get_floor(1).enemies[0].level), int(StageData.raw_stage(0).level))
	t.eq(int(TowerData.get_floor(n).enemies[0].level), int(StageData.raw_stage(n - 1).level))
	t.eq(int(TowerData.get_floor(n + 5).enemies[0].level), int(StageData.raw_stage(n - 1).level) + 5)
	# Same floor, same team (seeded), and teams differ between floors.
	TowerData._cache.clear()
	var again := TowerData.get_floor(7)
	t.eq(JSON.stringify(again.enemies), JSON.stringify(TowerData.get_floor(7).enemies))
	t.ok(JSON.stringify(TowerData.get_floor(7).enemies) != JSON.stringify(TowerData.get_floor(8).enemies))


func test_unlock_and_climb(t: TestCtx) -> void:
	var g := _game()
	g.new_game()
	t.eq(g.tower_unlocked(), false, "locked at the start")
	t.eq(g.tower_battle_setup(1), {}, "no battle while locked")
	t.eq(g.complete_tower(1, {"victory": true}).ok, false)
	g.model.state.campaign.cleared = TowerData.UNLOCK_CLEARED
	t.ok(g.tower_unlocked(), "open after stage %d" % TowerData.UNLOCK_CLEARED)
	t.eq(g.tower_next(), 1)
	t.eq(g.tower_battle_setup(2), {}, "only the next floor")
	var setup: Dictionary = g.tower_battle_setup(1)
	t.ok((setup.allies as Array).size() > 0 and (setup.enemies as Array).size() == 5)
	t.eq(int(setup.floor), 1)
	t.eq(g.complete_tower(2, {"victory": true}).ok, false, "can't skip a floor")
	var gold: int = g.currency("gold")
	var lost: Dictionary = g.complete_tower(1, {"victory": false})
	t.ok(lost.ok and not bool(lost.value.victory))
	t.eq(g.tower_best(), 0, "a loss changes nothing")
	t.eq(g.currency("gold"), gold)
	var won: Dictionary = g.complete_tower(1, {"victory": true})
	t.ok(won.ok and bool(won.value.first_clear))
	t.eq(g.tower_best(), 1)
	t.eq(g.tower_next(), 2)
	t.eq(g.currency("gold"), gold + int(TowerData.reward(1).gold), "floor reward paid")
	t.eq(g.complete_tower(1, {"victory": true}).ok, false, "a cleared floor can't pay twice")
	t.eq(g.counter("tower_floors"), 1)
	# A boss floor pays gems, a scroll and gear.
	g.model.state.tower.best = 9
	var gems: int = g.currency("gems")
	var scrolls: int = g.currency("scrolls")
	var items: int = (g.gear_items() as Array).size()
	t.ok(g.complete_tower(10, {"victory": true}).ok)
	t.eq(g.currency("gems"), gems + int(TowerData.reward(10).gems))
	t.eq(g.currency("scrolls"), scrolls + 1)
	t.eq((g.gear_items() as Array).size(), items + 1)
	g.free()


func test_tower_survives_save_and_migrate(t: TestCtx) -> void:
	_cleanup()
	var a := _game(PATH)
	a.new_game()
	a.model.state.campaign.cleared = TowerData.UNLOCK_CLEARED
	a.model.state.tower.best = 12
	a.save()
	var b := _game(PATH)
	b.load_or_create()
	t.eq(b.tower_best(), 12, "best floor after load")
	var s: Dictionary = b.model.state.duplicate(true)
	s.erase("tower")
	t.eq(b.model.migrate(s).tower, {"best": 0}, "old saves start at the bottom")
	var s2: Dictionary = b.model.state.duplicate(true)
	s2.tower.best = 99999
	t.eq(int(b.model.migrate(s2).tower.best), TowerData.FLOORS, "clamped to the top")
	a.free()
	b.free()
	_cleanup()
