extends RefCounted
## Misprints (data/prints.json, PrintRules, GameModel prints/showcase): editions and serials,
## determinism, the flaw and grade tables, trimming keeps every notable print, the showcase, the
## summon results carrying prints without changing the pulls, and save migration.

const BASE_MS := 1_702_083_600_000
const HOUR := 3600000
const DAY := 86400000


var _made: Array[Node] = []


func _game(now_ms: int = BASE_MS) -> Node:
	var g: Node = load("res://src/core/game.gd").new()
	_made.append(g)
	g.save_path = ""
	g.tz_bias_ms = 0
	g.now_override_ms = now_ms
	return g


## Frees every Game node this test made (call at the end of each test).
func _done() -> void:
	for g in _made:
		if is_instance_valid(g):
			g.free()
	_made.clear()


func _ids(n: int) -> Array:
	var out: Array = []
	var all := HeroData.ids()
	for i in n:
		out.append(all[i % all.size()])
	return out


func test_editions(t: TestCtx) -> void:
	var e := EconomyData.BANNER_EPOCH_DAY
	var ed := PrintRules.edition_on("standard", e, e)
	t.eq(int(ed.edition), 1, "the first edition opens on the epoch")
	t.eq(int(ed.open_day), e)
	t.eq(int(PrintRules.edition_on("standard", e + 27, e).edition), 1, "28 days per standard edition")
	t.eq(int(PrintRules.edition_on("standard", e + 28, e).edition), 2)
	t.eq(int(PrintRules.edition_on("standard", e + 28, e).open_day), e + 28)
	t.eq(int(PrintRules.edition_on("featured", e + 7, e).edition), 2, "7 days per featured edition")
	t.eq(int(PrintRules.edition_on("faction", e + 6, e).edition), 3, "3 days per faction edition")
	t.eq(int(PrintRules.edition_on("standard", e - 1, e).edition), 1, "before the epoch: edition 1")
	t.eq(int(PrintRules.edition_on("nope", e, e).run), int(PrintRules.edition_on("standard", e, e).run), "unknown banners print like the standard one")


func test_serials_and_printings(t: TestCtx) -> void:
	var e := EconomyData.BANNER_EPOCH_DAY
	# hours_open 10 on the standard banner (6 an hour): the first print is No. 61.
	var a := PrintRules.make_prints("standard", _ids(10), e, e, 10, {}, 5, 0)
	var ps: Array = a.prints
	t.eq(ps.size(), 10)
	t.eq(int(ps[0].serial), 61, "1 + hours_open * per_hour")
	t.eq(int(ps[0].run), 5000)
	t.eq(int(ps[0].edition), 1)
	for i in range(1, ps.size()):
		t.ok(int(ps[i].serial) > int(ps[i - 1].serial), "serials rise in pull order")
		t.ok(int(ps[i].serial) - int(ps[i - 1].serial) <= 1 + int(PrintRules._d.other_takers_max), "other collectors take a few between")
	t.eq(int(a.ed.e), 0)
	t.ok(int(a.ed.n) >= 10, "the edition counts every print taken")
	# The same edition continues from where it stopped; a new edition starts again.
	var b := PrintRules.make_prints("standard", _ids(1), e + 1, e, 10, a.ed, 5, 10)
	t.eq(int(b.prints[0].serial), 61 + int(a.ed.n), "continues the edition's count")
	var c := PrintRules.make_prints("standard", _ids(1), e + 28, e, 0, a.ed, 5, 11)
	t.eq(int(c.prints[0].serial), 1, "a new edition starts again at No. 1")
	t.eq(int(c.prints[0].edition), 2)
	# Past the run, the next printing.
	var d := PrintRules.make_prints("standard", _ids(1), e, e, 0, {"e": 0, "n": 5000}, 5, 0)
	t.eq(int(d.prints[0].printing), 2)
	t.eq(int(d.prints[0].serial), 1)
	t.eq(PrintRules.serial_text(d.prints[0]), "No. 0001")


func test_deterministic(t: TestCtx) -> void:
	var e := EconomyData.BANNER_EPOCH_DAY
	var a := PrintRules.make_prints("featured", _ids(30), e + 2, e, 50, {}, 99, 7)
	var b := PrintRules.make_prints("featured", _ids(30), e + 2, e, 50, {}, 99, 7)
	t.eq(JSON.stringify(a), JSON.stringify(b), "same inputs, same prints")
	var c := PrintRules.make_prints("featured", _ids(30), e + 2, e, 50, {}, 99, 8)
	t.ok(JSON.stringify(a.prints) != JSON.stringify(c.prints), "another seq rolls other flaws and grades")


func test_tables(t: TestCtx) -> void:
	t.eq(PrintRules.flaw_for_roll(0), "shift")
	t.eq(PrintRules.flaw_for_roll(259), "shift")
	t.eq(PrintRules.flaw_for_roll(260), "swap")
	t.eq(PrintRules.flaw_for_roll(549), "double")
	t.eq(PrintRules.flaw_for_roll(599), "flood")
	t.eq(PrintRules.flaw_for_roll(600), "", "6% of prints are misprinted")
	t.eq(PrintRules.grade_for_roll(0), 10, "1% Gem Mint")
	t.eq(PrintRules.grade_for_roll(99), 10)
	t.eq(PrintRules.grade_for_roll(100), 9)
	t.eq(PrintRules.grade_for_roll(9999), 3)
	t.eq(PrintRules.grade_name(10), "Gem Mint")
	t.eq(PrintRules.flaw_name("ghost"), "Missing plate")
	t.eq(PrintRules.flaw_adj("shift"), "off-register")
	# Over many prints the rates come out close to the table.
	var e := EconomyData.BANNER_EPOCH_DAY
	var out := PrintRules.make_prints("standard", _ids(5000), e, e, 0, {}, 2024, 0)
	var flaws := 0
	var holo := 0
	for p: Dictionary in out.prints:
		if str(p.flaw) != "":
			flaws += 1
		if bool(p.holo):
			holo += 1
		if str(p.flaw) == "swap":
			t.ok(PrintRules.inks().has(str(p.ink)), "a wrong ink names its ink")
		else:
			t.eq(str(p.ink), "")
	t.ok(flaws > 200 and flaws < 400, "about 6%% misprinted (%d of 5000)" % flaws)
	t.ok(holo > 40 and holo < 120, "about 1.5%% holo (%d of 5000)" % holo)


func test_trim_keeps_notables(t: TestCtx) -> void:
	var list: Array = []
	for i in 400:
		var p := {"uid": "p%d" % i, "hero": "uriela", "serial": 1000 + i, "printing": 1, "flaw": "", "holo": false, "grade": 6}
		if i % 50 == 3:
			p.flaw = "shift"
		if i == 10:
			p.holo = true
		if i == 20:
			p.grade = 10
		if i == 30:
			p.serial = 7
		if i == 40:
			p["first"] = true
		if i == 41:
			p["from"] = "rival"
		list.append(p)
	var out := PrintRules.trim(list)
	var uids := {}
	var plain := 0
	for p: Dictionary in out:
		uids[str(p.uid)] = true
		if not PrintRules.notable(p):
			plain += 1
	t.eq(plain, PrintRules.KEEP_PLAIN, "keeps the newest plain prints only")
	for p: Dictionary in list:
		if PrintRules.notable(p):
			t.ok(uids.has(str(p.uid)), "notable %s kept" % p.uid)
	t.ok(uids.has("p399"), "the newest plain print stays")
	t.ok(not uids.has("p0"), "the oldest plain print goes")
	t.eq(str(out[0].uid), "p3", "order kept (oldest first)")
	t.eq(PrintRules.trim(list.slice(0, 5)).size(), 5, "a short list is untouched")
	# Scores: holo beats a flaw beats a plain print; a higher grade breaks ties.
	var base := {"grade": 7, "serial": 900, "printing": 2}
	var fl := base.duplicate()
	fl["flaw"] = "flood"
	var ho := base.duplicate()
	ho["holo"] = true
	t.ok(PrintRules.score(ho) > PrintRules.score(fl) and PrintRules.score(fl) > PrintRules.score(base))


func test_summon_carries_prints(t: TestCtx) -> void:
	var g := _game()
	g.new_game()
	g.dev_add("gems", 100000)
	var st: Dictionary = g.state
	var seed_v := int(st.summon.seed)
	var tot := int(st.summon.total_pulls)
	var pity := int(st.summon.pity)
	var expect := SummonRules.pull(EconomyData.BANNER, seed_v, tot, pity, 10)
	var r: Dictionary = g.summon(10)
	t.ok(r.ok)
	var res: Array = r.value
	t.eq(res.size(), 10)
	var seen := {}
	for i in res.size():
		t.eq(str(res[i].hero_id), str(expect.results[i].hero_id), "the pulls are the same as without prints")
		var p: Dictionary = res[i].print
		t.eq(str(p.hero), str(res[i].hero_id), "the print is of that hero")
		t.eq(str(p.banner), "standard")
		t.ok(int(p.serial) >= 1 and int(p.serial) <= int(p.run))
		t.ok(int(p.grade) >= 1 and int(p.grade) <= 10)
		t.eq(bool(p.first), bool(res[i].is_new), "first = the hero was new")
		t.ok(not seen.has(str(p.uid)), "unique uids")
		seen[str(p.uid)] = true
	t.eq(int(g.state.prints.seq), 10)
	t.eq(int(g.state.prints.total), 10)
	t.eq(g.prints().size(), 10, "every print is in the album")
	t.eq(str(g.prints()[0].uid), str(res[9].print.uid), "newest first")
	# A later pull on the same edition gets a later serial.
	g.now_override_ms = BASE_MS + 5 * HOUR
	var r2: Dictionary = g.summon(1)
	t.ok(int(r2.value[0].print.serial) > int(res[9].print.serial), "pulling later gets a higher number")
	# Other banners print their own editions.
	var r3: Dictionary = g.summon(1, false, "featured")
	t.eq(str(r3.value[0].print.banner), "featured")
	t.ok(g.state.prints.ed.has("featured"))
	_done()


func test_dev_looks_and_filters(t: TestCtx) -> void:
	var g := _game()
	g.new_game()
	g.dev_add("gems", 100000)
	g.dev_print_looks([{"flaw": "shift"}, {"holo": true}, {"flaw": "swap", "ink": "gold", "grade": 10}])
	var r: Dictionary = g.summon(10)
	t.eq(str(r.value[0].print.flaw), "shift")
	t.eq(bool(r.value[1].print.holo), true)
	t.eq(str(r.value[2].print.ink), "gold")
	t.eq(int(r.value[2].print.grade), 10)
	t.eq(g.model.dev_print_looks.size(), 0, "the looks are used once")
	t.ok(g.prints("misprint").size() >= 2)
	t.ok(g.prints("holo").size() >= 1)
	t.ok(g.prints("top").size() >= 1)
	t.eq(g.prints("rival").size(), 0)
	t.eq(g.prints("hero:%s" % str(r.value[0].hero_id)).size() >= 1, true)
	var s: Dictionary = g.print_stats()
	t.eq(int(s.total), 10)
	t.eq(int(s.best_grade), 10)
	t.ok(int(s.misprints) >= 2)
	t.ok(not (s.best as Dictionary).is_empty())
	_done()


func test_showcase(t: TestCtx) -> void:
	var g := _game()
	g.new_game()
	g.dev_add("gems", 100000)
	g.summon(10)
	var all: Array = g.prints()
	var u: Array = [str(all[0].uid), str(all[3].uid), str(all[5].uid)]
	t.ok(g.set_showcase(u).ok)
	t.eq(g.showcase().size(), 3)
	t.eq(str(g.showcase()[1].uid), u[1], "showcase order kept")
	t.eq(g.set_showcase(u + [str(all[6].uid)]).ok, false, "three at most")
	t.eq(g.set_showcase(["nope"]).ok, false, "unknown prints refused")
	t.eq(g.set_showcase([u[0], u[0]]).ok, false, "no print twice")
	t.ok(g.set_showcase([]).ok)
	t.eq(g.showcase().size(), 0)
	_done()


func test_save_round_trip_and_migration(t: TestCtx) -> void:
	var g := _game()
	g.new_game()
	g.dev_add("gems", 100000)
	g.summon(10)
	g.set_showcase([str(g.prints()[0].uid)])
	var saved: Dictionary = g.intify(JSON.parse_string(JSON.stringify(g.state)))
	var g2 := _game()
	g2.migrate(saved)
	t.eq(JSON.stringify(g2.prints()), JSON.stringify(g.prints()), "the album survives a save")
	t.eq(g2.showcase().size(), 1)
	# An old save without the block gets an empty album.
	var old := {"version": 1, "heroes": {"uriela": {"id": "uriela", "level": 3, "stars": 1}}}
	var g3 := _game()
	g3.migrate(old)
	t.eq(g3.prints().size(), 0)
	t.eq(int(g3.state.prints.seq), 0)
	t.ok(int(g3.state.prints.seed) != 0, "a print seed is made")
	# Damaged entries are dropped or repaired.
	var bad := {"version": 1, "heroes": {"uriela": {"id": "uriela"}}, "prints": {"seed": 5, "seq": -3, "total": 1,
		"ed": {"standard": {"e": 0, "n": -9}, "bogus": {"e": 1}}, "list": [{"uid": "p1", "hero": "uriela", "grade": 99, "flaw": "smudge"},
		{"uid": "p1", "hero": "uriela"}, {"uid": "p2", "hero": "ghost"}, "junk", {"hero": "kessa"}], "showcase": ["p1", "p9", "p1"]}}
	var g4 := _game()
	g4.migrate(bad)
	var ps: Dictionary = g4.state.prints
	t.eq(int(ps.seq), 0)
	t.eq((ps.list as Array).size(), 1, "only the valid, unique print stays")
	t.eq(int(ps.list[0].grade), 10)
	t.eq(str(ps.list[0].flaw), "", "an unknown flaw is cleared")
	t.eq(ps.ed.keys(), ["standard"])
	t.eq(int(ps.ed.standard.n), 0)
	t.eq(ps.showcase, ["p1"])
	_done()
