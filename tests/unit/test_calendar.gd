extends RefCounted
## Real days (CalendarRules + GameModel.calendar*): the date maths, today's holidays and the owned
## heroines' birthdays, and each gift taken once a year.

const DAY := 86400000

var _made: Array[Node] = []


func _game(y: int, m: int, d: int) -> Node:
	var g: Node = load("res://src/core/game.gd").new()
	_made.append(g)
	g.save_path = ""
	g.tz_bias_ms = 0
	g.now_override_ms = CalendarRules.day_number(y, m, d) * DAY + 15 * 3600000
	return g


func _done() -> void:
	for g in _made:
		if is_instance_valid(g):
			g.free()
	_made.clear()


func test_civil_dates(t: TestCtx) -> void:
	t.eq(CalendarRules.civil(0), [1970, 1, 1], "day 0")
	t.eq(CalendarRules.civil(-1), [1969, 12, 31], "the day before")
	t.eq(CalendarRules.civil(CalendarRules.day_number(2024, 2, 29)), [2024, 2, 29], "a leap day")
	t.eq(CalendarRules.civil(CalendarRules.day_number(2026, 10, 31)), [2026, 10, 31])
	t.eq(CalendarRules.day_number(2000, 3, 1) - CalendarRules.day_number(2000, 2, 28), 2, "2000 was a leap year")
	t.eq(CalendarRules.day_number(1900, 3, 1) - CalendarRules.day_number(1900, 2, 28), 1, "1900 was not")
	var ok := true
	for day in range(-800, 70000, 37):
		var c := CalendarRules.civil(day)
		if CalendarRules.day_number(c[0], c[1], c[2]) != day:
			ok = false
	t.ok(ok, "civil and day_number round-trip")
	t.eq(CalendarRules.md(CalendarRules.day_number(2026, 1, 9)), "01-09")


func test_holiday_inks_and_decor(t: TestCtx) -> void:
	var hw := CalendarRules.day_number(2026, 10, 31)
	t.eq(CalendarRules.ink(hw), "ff8a1c", "Halloween prints in pumpkin")
	t.eq(CalendarRules.decor(hw), "halloween", "Halloween hangs its bats")
	t.eq(CalendarRules.decor(hw + 1), "", "the day after: nothing hung")
	t.eq(CalendarRules.decor(CalendarRules.day_number(2027, 10, 31)), "halloween", "every year")
	t.eq(CalendarRules.night(hw), "candle", "Halloween night by candlelight")
	t.eq(CalendarRules.night(hw + 1), "", "not the night after")
	# Every decor named in the calendar is a set the Lobby can hang, with its renders.
	var sets: Dictionary = load("res://src/ui/components/garland.gd").SETS
	for h: Dictionary in CalendarRules._d.days:
		var dec := str(h.get("decor", ""))
		if dec == "":
			continue
		t.ok(sets.has(dec), "decor %s is a garland set" % dec)
		for spec: Array in sets.get(dec, []):
			t.ok(ResourceLoader.exists("res://assets/art/ui/holiday/%s.png" % spec[0]), "render %s" % spec[0])
			t.ok(ResourceLoader.exists("res://assets/art/ui/holiday/%s_shadow.png" % spec[0]), "shadow %s" % spec[0])


func test_events(t: TestCtx) -> void:
	var hw := CalendarRules.day_number(2026, 10, 31)
	var ev := CalendarRules.events(hw, [])
	t.eq(ev.size(), 1)
	t.eq(str(ev[0].key), "halloween-2026")
	t.eq(str(ev[0].kind), "day")
	t.eq(CalendarRules.events(hw + 1, ["vesper"]).size(), 0, "an ordinary day")
	var vb := CalendarRules.day_number(2027, 11, 5)
	t.eq(CalendarRules.events(vb, []).size(), 0, "no birthday for a heroine you don't have")
	var bv := CalendarRules.events(vb, ["seraphiel", "vesper"])
	t.eq(bv.size(), 1)
	t.eq(str(bv[0].key), "bday-vesper-2027")
	t.eq(CalendarRules.line(bv[0], "vesper", "infernal", "Vesper"), "My birthday, envoy. I expect to be spoiled.")
	t.ok(CalendarRules.line(bv[0], "seraphiel", "celestial", "Vesper").begins_with("It's Vesper's"), "the others name her")
	t.ok(CalendarRules.line(ev[0], "noctaire", "fallen", "").length() > 10, "a holiday line by faction")
	# Every heroine has a birthday, none on a holiday and no two on one day.
	var seen := {}
	var holidays := {}
	for d: Dictionary in GameData.file("calendar").days:
		holidays[str(d.md)] = true
	for id in HeroData.ids():
		var b := CalendarRules.birthday(id)
		t.ok(b != "" and not seen.has(b) and not holidays.has(b), "a birthday of her own: " + id)
		seen[b] = true


func test_claim_once_a_year(t: TestCtx) -> void:
	var g := _game(2026, 10, 31)
	g.new_game()
	var gems := int(g.model.state.currencies.gems)
	var today: Array = g.calendar_today()
	t.eq(today.size(), 1)
	t.ok(not bool(today[0].claimed))
	var r: Dictionary = g.claim_calendar("halloween-2026")
	t.ok(bool(r.ok), str(r.error))
	t.eq(int(g.model.state.currencies.gems), gems + 200)
	t.ok(bool(g.calendar_today()[0].claimed))
	t.ok(not bool(g.claim_calendar("halloween-2026").ok), "once")
	t.ok(not bool(g.claim_calendar("christmas-2026").ok), "not today")
	# A year on: a new key, and last year's claim is pruned after CALENDAR_KEEP_DAYS.
	g.now_override_ms += 365 * DAY
	t.eq(str(g.calendar_today()[0].key), "halloween-2027")
	t.ok(bool(g.claim_calendar("halloween-2027").ok))
	g.now_override_ms += 40 * DAY
	g.model.migrate(g.model.state.duplicate(true))
	t.ok((g.model.state.calendar.claimed as Dictionary).has("halloween-2026"), "last year's stamp is kept (the profile's record lists it)")
	g.now_override_ms += (GameModel.CALENDAR_KEEP_DAYS - 365) * DAY
	g.model.migrate(g.model.state.duplicate(true))
	t.ok(not (g.model.state.calendar.claimed as Dictionary).has("halloween-2026"), "claims older than CALENDAR_KEEP_DAYS are dropped")
	t.ok((g.model.state.calendar.claimed as Dictionary).has("halloween-2027"))
	_done()


func test_birthday_skin_sale(t: TestCtx) -> void:
	var g := _game(2026, 11, 5)
	g.new_game()
	var skins: Array = SkinData.for_hero("vesper")
	if skins.is_empty():
		t.ok(true, "no skins for vesper")
		_done()
		return
	var sid := str(skins[0].id)
	var full := int(skins[0].price_gems)
	t.eq(g.model.skin_price(sid), full * 8000 / 10000, "20% off on her birthday")
	t.ok(bool((g.model.skins_for("vesper")[0] as Dictionary).sale))
	g.model.state.currencies.gems = full
	t.ok(bool(g.model.buy_skin(sid).ok))
	t.eq(int(g.model.state.currencies.gems), full - full * 8000 / 10000, "charged the sale price")
	g.now_override_ms += 86400000
	t.eq(g.model.skin_price(str(skins[1].id) if skins.size() > 1 else sid), int(skins[1].price_gems) if skins.size() > 1 else full, "full price the next day")
	_done()


func test_birthday_claim(t: TestCtx) -> void:
	var g := _game(2026, 11, 5)
	g.new_game()
	t.eq(g.calendar_today().size(), 0, "not hers yet")
	g.model.receive_hero("vesper")
	var today: Array = g.calendar_today()
	t.eq(today.size(), 1)
	var exp := int(g.model.state.currencies.hero_exp)
	t.ok(bool(g.claim_calendar("bday-vesper-2026").ok))
	t.eq(int(g.model.state.currencies.hero_exp), exp + 2000)
	_done()


func test_player_birthday(t: TestCtx) -> void:
	t.eq(CalendarRules.clean_md("2-29"), "02-29")
	t.eq(CalendarRules.clean_md("04-31"), "", "April has 30 days")
	t.eq(CalendarRules.clean_md("13-01"), "")
	t.eq(CalendarRules.clean_md("x-1"), "")
	var g := _game(2026, 12, 3)
	g.new_game()
	g.complete_intake("Aria", [], "12-03")
	t.eq(str(g.model.state.player_birthday), "12-03")
	var today: Array = g.calendar_today()
	t.eq(today.size(), 1)
	t.eq(str(today[0].kind), "player")
	t.eq(str(today[0].key), "you-2026")
	t.ok(CalendarRules.line(today[0], "seraphiel", "celestial", "Aria").begins_with("Happy birthday, Aria."))
	t.ok(bool(g.claim_calendar("you-2026").ok))
	# A bad date never overwrites a good one; save repair drops a bad one.
	g.complete_intake("Aria", [], "02-30")
	t.eq(str(g.model.state.player_birthday), "12-03")
	var st: Dictionary = g.model.state.duplicate(true)
	st.player_birthday = "99-99"
	g.model.migrate(st)
	t.eq(str(g.model.state.player_birthday), "")
	_done()
