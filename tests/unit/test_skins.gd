extends RefCounted
## Cosmetic skins (data/skins.json, docs/dev/skins.md): data integrity, buying with gems,
## equipping, save round trip, migration of bad saves, and the art fallback to the base look;
## crops follow the skin (Kit.art_crop, Kit.hero_look), nudity swaps a skin to its adult art, and
## base looks without adult art (<id>/adult/) keep their art.

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
	t.eq(all.size(), 160, "four packs x 40 heroes")
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
		t.eq(n, 40, "pack covers all 40: " + line)
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
	t.eq(RigData.exists("uriela", "no_such_art"), false, "an art folder without a rig is not installed")


func test_installed_skin_art_loads(t: TestCtx) -> void:
	var built := 0
	for s: Dictionary in SkinData.all():
		var hero := str(s["hero"])
		if not HeroArt.has_skin_art(hero, str(s["id"])):
			continue
		built += 1
		t.ok(RigData.load_rig(hero, str(s["art"])) != null, "%s: rig loads" % s["id"])
		t.ok(HeroArt.texture(hero, str(s["id"])) != HeroArt.texture(hero), "%s: shows its own image" % s["id"])
		t.ok(HeroArt.portrait_region(hero, str(s["id"])).size.x > 0, "%s: has a portrait" % s["id"])
	t.ok(built > 0, "some skin art is installed (assets/art/heroes/<id>/skins/)")


func test_nudity_mode_drops_skins(t: TestCtx) -> void:
	var g := _game()
	g.new_game()
	t.eq(g.setting("nudity"), false, "off for a new player")
	t.eq(HeroArt.nudity, false)
	var sid := _starter_skin()
	t.ok(sid != "", "kessa has an installed skin")
	if sid != "":
		var tame := HeroArt.texture("kessa", sid)
		var base := HeroArt.texture("kessa")
		g.set_setting("nudity", true)
		t.ok(HeroArt.nudity, "Game syncs the setting to HeroArt")
		# 18+ mode (owner, 2026-10-22): skins are off; every hero shows her nude base look where built
		t.eq(HeroArt.art_key("kessa", sid), HeroArt.art_key("kessa"), "nudity on: the skin is ignored")
		t.eq(HeroArt.texture("kessa", sid), HeroArt.texture("kessa"), "nudity on: skin and base look match")
		t.ok(HeroArt.texture("kessa", sid) != tame, "nudity on: not the skin's art")
		if HeroArt.has_adult_art("kessa"):
			t.ok(HeroArt.texture("kessa") != base, "nudity on: her nude base look")
			t.eq(HeroArt.art_key("kessa"), "kessa@/adult")
		g.set_setting("nudity", false)
		t.eq(HeroArt.texture("kessa", sid), tame, "nudity off: back to the skin's art")
	t.eq(HeroArt.has_adult_art("uriela", "kessa_card_shark"), false, "another hero's skin never resolves")
	var s: Dictionary = g.model.state.duplicate(true)
	s.settings.erase("nudity")
	t.eq(g.model.migrate(s).settings.nudity, false, "old saves start with nudity off")
	g.set_setting("nudity", false)
	g.free()


## An installed skin of a starter hero (kessa), or "" when none is built.
func _starter_skin() -> String:
	for s: Dictionary in SkinData.for_hero("kessa"):
		if HeroArt.has_skin_art("kessa", str(s["id"])):
			return str(s["id"])
	return ""


func test_art_crop_follows_the_skin(t: TestCtx) -> void:
	HeroArt.nudity = false
	var sid := _starter_skin()
	t.ok(sid != "", "kessa has an installed skin")
	if sid == "":
		return
	var base := HeroArt.texture("kessa")
	var dressed := HeroArt.texture("kessa", sid)
	var c0 := Kit.art_crop("kessa", 0.6, 1.3) as AtlasTexture
	var c1 := Kit.art_crop("kessa", 0.6, 1.3, sid) as AtlasTexture
	t.eq(c0.atlas, base, "no skin: the crop cuts the base still")
	t.eq(c1.atlas, dressed, "a skin: the crop cuts the skin's still")
	t.ok(Kit.art_crop("kessa", 0.6, 1.3, sid) == c1, "cached per look")
	t.ok(HeroArt.art_key("kessa", sid) != HeroArt.art_key("kessa"), "the art key names the look")
	t.eq(HeroArt.art_key("kessa", "uriela_surf_racer"), HeroArt.art_key("kessa"), "another hero's skin is the base look")
	# Views take opts.skin ("" = base look, for enemies); the default is the player's equipped skin.
	t.eq(Kit.hero_look("kessa", {"skin": sid}), sid)
	t.eq(Kit.hero_look("kessa", {"skin": ""}), "", "an enemy keeps the base look")


func test_equipped_skin_and_nudity_show_the_nude_base_look(t: TestCtx) -> void:
	var sid := _starter_skin()
	if sid == "":
		t.ok(true, "no installed kessa skin; nothing to check")
		return
	var g := _game()
	g.new_game()
	g.dev_add("gems", 10000)
	t.ok(bool(g.buy_skin(sid).ok), "bought")
	t.ok(bool(g.equip_skin("kessa", sid).ok), "equipped")
	var worn: String = g.equipped_skin("kessa")
	t.eq(worn, sid)
	var tame_crop := Kit.art_crop("kessa", 0.6, 1.3, worn) as AtlasTexture
	g.set_setting("nudity", true)
	var crop := Kit.art_crop("kessa", 0.6, 1.3, worn) as AtlasTexture
	t.eq(crop.atlas, HeroArt.texture("kessa"), "nudity on: the card crop shows her base (nude) look")
	t.ok(crop != tame_crop, "the crop follows the toggle (new cache key)")
	if HeroArt.has_adult_art("kessa"):
		var pt := HeroArt._portrait_tex("kessa", worn)
		t.eq(pt.resource_path, RigData.file_base("kessa", RigData.adult_art()) + "_portrait.png", "nude portrait")
	g.set_setting("nudity", false)
	t.eq(Kit.art_crop("kessa", 0.6, 1.3, worn), tame_crop, "nudity off: the skin crop again")
	Kit.art_crop("kessa", 0.6, 1.3)
	t.ok((Kit._crop_looks.get("kessa", []) as Array).size() <= Kit.CROP_LOOKS, "the crop cache keeps two looks per hero")
	g.free()


func test_base_look_adult_art_falls_back(t: TestCtx) -> void:
	t.eq(RigData.adult_art(), "/adult", "the base look's nude art")
	t.eq(RigData.adult_art("card_shark"), "card_shark/adult")
	t.eq(RigData.art_dir("kessa", "/adult"), "res://assets/art/heroes/kessa/adult/")
	t.eq(RigData.file_base("kessa", "/adult"), "res://assets/art/heroes/kessa/adult/kessa", "files keep the hero's name")
	t.eq(RigData.art_dir("kessa", "card_shark/adult"), "res://assets/art/heroes/kessa/skins/card_shark/adult/")
	t.eq(RigData.file_base("kessa", "card_shark/adult"), "res://assets/art/heroes/kessa/skins/card_shark/adult/card_shark")
	t.eq(RigData.file_base("kessa"), "res://assets/art/heroes/kessa/kessa")
	t.eq(HeroArt.has_adult_art("kessa", "uriela_surf_racer"), false, "another hero's skin never resolves")
	var was := HeroArt.nudity
	for id in HeroData.ids():
		HeroArt.nudity = false
		var tame := HeroArt.texture(id)
		var tame_pr := HeroArt.portrait_region(id)
		var tame_por := HeroArt._portrait_tex(id)
		HeroArt.nudity = true
		if HeroArt.has_adult_art(id):
			var still: Texture2D = load(RigData.load_rig(id, "/adult").still_path)
			t.eq(HeroArt.texture(id), still, "%s: nudity shows the base look's adult art" % id)
			t.eq(HeroArt.art_key(id), id + "@/adult")
			continue
		# No nude base art yet (it is rendered later): the normal base art, unchanged.
		t.eq(HeroArt.texture(id), tame, "%s: no adult base art, the base still" % id)
		t.eq(HeroArt.portrait_region(id), tame_pr, "%s: same portrait framing" % id)
		t.eq(HeroArt._portrait_tex(id), tame_por, "%s: same portrait" % id)
		t.eq(HeroArt.art_key(id), id + "@", "%s: the art key stays the base look" % id)
		var spr := HeroArt.make_sprite(id) as HeroSprite
		t.ok(spr != null and spr.rig != null and spr.rig.rig != null, "%s: the sprite still builds" % id)
		if spr:
			spr.free()
	HeroArt.nudity = was
