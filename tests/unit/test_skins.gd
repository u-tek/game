extends RefCounted
## Cosmetic skins (data/skins.json, docs/dev/skins.md): data integrity, buying with gems,
## equipping, save round trip, migration of bad saves, and the art fallback to the base look.

const BASE_MS := 1_702_083_600_000
const PATH := "user://unit_test_save_skins.json"


func _game(path: String = "") -> Node:
	var g: Node = load("res://src/core/game.gd").new()
	g.save_path = path
	g.tz_bias_ms = 0
	g.now_override_ms = BASE_MS
	return g


func _cleanup() -> void:
	for f in DirAccess.get_files_at("user://"):
		if f.begins_with("unit_test_save_skins"):
			DirAccess.remove_absolute(ProjectSettings.globalize_path("user://" + f))


func test_skin_data_is_consistent(t: TestCtx) -> void:
	var all := SkinData.all()
	t.eq(all.size(), 60, "four packs x 15 heroes")
	var ids := {}
	var lines := SkinData.lines()
	for s in all:
		t.ok(not ids.has(s.id), "unique id " + s.id)
		ids[s.id] = true
		t.ok(not HeroData.get_def(s.hero).is_empty(), "known hero for " + s.id)
		t.ok(lines.has(s.line), "known line for " + s.id)
		t.ok(s.price_gems > 0, "priced: " + s.id)
		t.ok(s.art != "" and not s.art.contains("/"), "art folder name: " + s.id)
		t.ok(s.name != "" and s.description != "", "named and described: " + s.id)
	for h in HeroData.all():
		t.eq(SkinData.for_hero(h.id).size(), 4, "one skin per pack: " + h.id)
	for line in lines:
		var n := 0
		for s in all:
			if s.line == line:
				n += 1
		t.eq(n, 15, "pack covers all 15: " + line)
	t.eq(SkinData.get_def("nope"), {}, "unknown id")
	t.eq(SkinData.get_def("seraphiel_tidal_diva").price_gems, 1480, "deluxe price")
	t.eq(SkinData.get_def("cassiel_lifeguard_unit").price_gems, 980, "standard price")


func test_buy_and_equip(t: TestCtx) -> void:
	var g := _game()
	g.new_game()
	var m: GameModel = g.model
	var sid := "uriela_surf_racer"
	m.state.currencies.gems = 500
	var r: Dictionary = m.buy_skin(sid)
	t.eq(r.ok, false, "too few gems")
	t.eq(r.error, "Not enough gems")
	m.state.currencies.gems = 5000
	r = m.buy_skin(sid)
	t.ok(r.ok, "bought")
	t.eq(m.currency("gems"), 5000 - 980, "gems paid")
	t.ok(m.owns_skin(sid))
	t.eq(m.buy_skin(sid).error, "Already owned", "no double purchase")
	t.eq(m.equipped_skin("uriela"), "", "buying does not equip")
	t.eq(m.equip_skin("kessa", sid).ok, false, "a skin only fits its own hero")
	t.eq(m.equip_skin("uriela", "uriela_pit_bunny").error, "You don't own that skin")
	t.ok(m.equip_skin("uriela", sid).ok, "equipped")
	t.eq(m.equipped_skin("uriela"), sid)
	var list: Array[Dictionary] = m.skins_for("uriela")
	t.eq(list.size(), 4)
	t.ok(list[0].owned and list[0].equipped, "flags on the list")
	t.ok(not list[1].owned and not list[1].equipped)
	t.ok(m.equip_skin("uriela", "").ok, "back to the base look")
	t.eq(m.equipped_skin("uriela"), "")
	t.eq(m.buy_skin("nope").error, "Unknown skin")
	g.free()


func test_game_refuses_skins_without_art(t: TestCtx) -> void:
	var g := _game()
	g.new_game()
	g.dev_add("gems", 10000)
	var sid := "kessa_card_shark"
	if HeroArt.has_skin_art("kessa", sid):
		t.ok(true, "kessa_card_shark art is installed; nothing to check")
	else:
		var r: Dictionary = g.buy_skin(sid)
		t.eq(r.ok, false, "no art, no sale")
		t.eq(r.error, "Coming soon")
		t.ok(not g.owns_skin(sid))
		var s: Dictionary = g.skins_for("kessa")[1]
		t.eq(s.installed, false, "installed flag")
	g.free()


func test_skins_survive_save_and_load(t: TestCtx) -> void:
	_cleanup()
	var a := _game(PATH)
	a.new_game()
	a.model.state.currencies.gems = 10000
	a.model.buy_skin("mordessa_high_roller")
	a.model.equip_skin("mordessa", "mordessa_high_roller")
	a.save()
	var b := _game(PATH)
	b.load_or_create()
	t.ok(b.owns_skin("mordessa_high_roller"), "owned after load")
	t.eq(b.equipped_skin("mordessa"), "mordessa_high_roller", "equipped after load")
	t.eq(JSON.stringify(b.state.skins), JSON.stringify(a.state.skins))
	a.free()
	b.free()
	_cleanup()


func test_migrate_cleans_skin_state(t: TestCtx) -> void:
	var g := _game()
	g.new_game()
	var s: Dictionary = g.model.state.duplicate(true)
	s.skins = {"owned": ["liora_pearl_lagoon", "ghost_skin", "liora_pearl_lagoon", "vesper_red_tide"],
		"equipped": {"liora": "liora_pearl_lagoon", "vesper": "vesper_dealers_choice",
			"kessa": "vesper_red_tide", "ghost": "liora_pearl_lagoon"}}
	var out: Dictionary = g.model.migrate(s)
	t.eq(out.skins.owned, ["liora_pearl_lagoon", "vesper_red_tide"], "unknown and duplicate ids dropped")
	t.eq(out.skins.equipped, {"liora": "liora_pearl_lagoon"}, "only owned skins on their own hero")
	var old: Dictionary = g.model.state.duplicate(true)
	old.erase("skins")
	t.eq(g.model.migrate(old).skins, {"owned": [], "equipped": {}}, "old saves get empty skin state")
	g.free()


func test_art_falls_back_to_the_base_look(t: TestCtx) -> void:
	t.eq(HeroArt.has_skin_art("uriela", "kessa_card_shark"), false, "another hero's skin never resolves")
	t.eq(HeroArt.has_skin_art("uriela", ""), false)
	if HeroArt.has_art("uriela") and not HeroArt.has_skin_art("uriela", "uriela_surf_racer"):
		t.eq(HeroArt.texture("uriela", "uriela_surf_racer"), HeroArt.texture("uriela"),
			"a skin without built art shows the base still")
		t.eq(HeroArt.portrait_region("uriela", "uriela_surf_racer"), HeroArt.portrait_region("uriela"))
	t.eq(RigData.art_dir("uriela", "surf_racer"), "res://assets/art/heroes/uriela/skins/surf_racer/")
	t.eq(RigData.exists("uriela", "surf_racer"), false, "no skin art built yet")
