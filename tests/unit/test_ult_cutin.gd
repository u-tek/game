extends RefCounted
## A heroine's ultimate cut-in (src/ui/battle/ult_cutin.gd) and what it stands on: its beats in
## order and short enough to play ten times a fight, its contact at each battle speed, her
## performance (anim warp/ult_cutin) keyed to the same impact beat, no white wash left on any
## ultimate, the two-tone print that switches back to her own look (an echo's violet included), the
## "cutins" setting (every cast / her first and by hand / by hand only).

const UltCutin := preload("res://src/ui/battle/ult_cutin.gd")


func test_beats_in_order_and_short(t: TestCtx) -> void:
	var beats: Array[float] = [UltCutin.T_CUT, UltCutin.T_SNAP, UltCutin.T_GHOST, UltCutin.T_RISE_SND,
		UltCutin.T_COIL, UltCutin.T_STRIKE, UltCutin.T_IMPACT, UltCutin.T_COLOUR, UltCutin.T_CONTACT,
		UltCutin.T_BARS_OUT, UltCutin.T_END]
	for i in range(1, beats.size()):
		t.ok(beats[i] > beats[i - 1], "beat %d after beat %d" % [i, i - 1])
	t.ok(UltCutin.T_END <= 2.2, "the whole take is at most 2.2 s at 1x")
	t.ok(UltCutin.REPEAT_FROM < UltCutin.T_COIL, "a repeat cast still has its pose")


func test_contact_time_at_each_speed(t: TestCtx) -> void:
	var c := UltCutin.new()
	t.near(c.contact_time(), 1.22, 0.001, "1x")
	c.rate = 1.5
	t.near(c.contact_time(), 1.22 / 1.5, 0.001, "2x")
	c.rate = 2.1
	t.near(c.contact_time(), 1.22 / 2.1, 0.001, "4x")
	c.free()


func test_key_word(t: TestCtx) -> void:
	t.eq(UltCutin._key_word("Eclipse Harvest"), "HARVEST")
	t.eq(UltCutin._key_word("Hymn of Judgment"), "JUDGMENT")
	t.eq(UltCutin._key_word("Sing to Me"), "SING", "never a short last word")
	t.eq(UltCutin._key_word(""), "ULTIMATE")


func test_her_performance_hits_on_the_impact(t: TestCtx) -> void:
	var a := RigAnim.from_file("res://assets/art/anim/warp/ult_cutin.anim.json")
	t.ok(a != null, "warp/ult_cutin loads")
	if a == null:
		return
	var hit := -1.0
	for e: Array in a.events:
		if str(e[1]) == "hit":
			hit = float(e[0])
	t.near(hit, UltCutin.T_IMPACT, 0.001, "her blow lands on the impact frame")
	t.ok(a.fx.is_empty(), "no glow or flash on her in the cut-in")
	for b: String in a.bones:
		t.ok(b in ["root", "hips", "torso", "chest", "neck", "head", "face", "hair_front"], "%s: a bone every quick rig has" % b)
	# Format 2 rigs find it too (anim/warp2/ falls back to anim/warp/).
	t.ok(RigAnim.find("ult_cutin", "", "warp2") != null, "found for format 2 rigs")


func test_no_white_wash_on_any_ultimate(t: TestCtx) -> void:
	var paths: Array[String] = ["res://assets/art/anim/ultimate.anim.json", "res://assets/art/anim/warp/ultimate.anim.json",
		"res://assets/art/anim/warp2/ultimate.anim.json"]
	for d: Dictionary in HeroData.all():
		var p := "res://assets/art/heroes/%s/anim/ultimate.anim.json" % str(d.id)
		if FileAccess.file_exists(p):
			paths.append(p)
	for p in paths:
		var a := RigAnim.from_file(p)
		t.ok(a != null and not a.fx.has("flash"), "%s: no flash track" % p)


func test_two_tone_switches_back(t: TestCtx) -> void:
	var spr := HeroArt.make_sprite(str(HeroData.all()[0].id)) as HeroSprite
	t.ok(spr != null and spr.rig != null, "a sprite to print")
	if spr == null or spr.rig == null:
		return
	spr.set_echo(true)
	spr.two_tone(true, Color("141517"), Color("ff5c29"), 0.4)
	var tint: Dictionary = spr.rig.get("_tint")
	t.eq(float(tint.get(&"map_hard", 0.0)), 1.0, "two-tone: the map cut hard")
	t.eq(float(tint.get(&"desat", -1.0)), 0.0, "two-tone: the echo's grey off")
	t.near(float(tint.get(&"map_cut", 0.0)), 0.4, 0.001, "two-tone: her own cut point")
	spr.two_tone(false)
	tint = spr.rig.get("_tint")
	t.eq(float(tint.get(&"map_hard", -1.0)), 0.0, "off: the map soft again")
	t.eq(float(tint.get(&"map_on", -1.0)), 0.0, "off: no map")
	t.near(float(tint.get(&"desat", 0.0)), 0.5, 0.001, "off: the echo's grey back")
	t.near(float(tint.get(&"shade", 0.0)), 0.7, 0.001, "off: the echo's violet back")
	spr.free()


func test_cutins_setting(t: TestCtx) -> void:
	var g: Node = load("res://src/core/game.gd").new()
	g.save_path = ""
	g.tz_bias_ms = 0
	g.now_override_ms = 1_702_083_600_000
	g.new_game()
	t.eq(g.setting("cutins"), null, "a new save has no choice (the battle reads it as 'first')")
	g.set_setting("cutins", "hand")
	t.eq(str(g.setting("cutins")), "hand", "by hand only")
	g.set_setting("cutins", "sometimes")
	t.eq(str(g.setting("cutins")), "hand", "an unknown value is refused")
	g.free()


func test_cut_points_are_baked(t: TestCtx) -> void:
	# tools/art_cuts.py writes them; a fight never reads a painting back from the GPU.
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/art/heroes/cuts.json"))
	t.ok(d is Dictionary and (d as Dictionary).size() > 0, "cuts.json")
	var id := str(HeroData.all()[0].id)
	var cut := UltCutin._cut_point(id, "")
	t.ok(UltCutin._baked.has(RigData.file_base(id, HeroArt._built_art(id, "")).trim_prefix("res://assets/art/heroes/")), "%s's base art is baked" % id)
	t.ok(cut >= 0.25 and cut <= 0.7, "within its range")
