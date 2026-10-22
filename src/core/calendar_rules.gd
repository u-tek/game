class_name CalendarRules
extends RefCounted
## Real days the game notices: the holidays in data/calendar.json and each heroine's birthday. Pure
## functions on the local day number (days since 1970-01-01 in the player's time zone, as
## GameModel.today()); the claims live in GameModel. Port spec: docs/dev/unity-port.md section 9f.
## Fixture: data/fixtures/calendar.json.
##
##   civil(day)          = [year, month, day] on the proleptic Gregorian calendar, integer math only
##                         (truncating division, valid for any day number)
##   day_number(y, m, d) = the day number of a date (the inverse of civil)
##   md(day)             = "MM-DD"
##   events(day, owned, player_md = "")
##                       = the day's events in order: the player's own birthday when player_md (MM-DD,
##                         from the intake form) matches, then every holiday whose md matches (data
##                         order), then the birthday of every owned heroine whose md matches (in the
##                         order of data birthdays). Each {"kind": "player" | "day" | "birthday",
##                         "id": "player" | holiday id | hero id, "key": "you-<year>" | "<id>-<year>" |
##                         "bday-<hero>-<year>", "gift": {currency: n}}.
##                         A key is claimable once, so each gift comes once a year. A 02-29
##                         birthday only comes in leap years.
##   clean_md(s)         = s as "MM-DD" when it is a real date (02-29 allowed), else "".
##   skin_price(p, day, hero) = p * (10000 - skin_discount_bp(day, hero)) / 10000: her skins are
##                         birthday.skin_discount_bp off on her birthday

static var _d: Dictionary = GameData.file("calendar")


static func civil(day: int) -> Array[int]:
	var z := day + 719468
	var era := (z if z >= 0 else z - 146096) / 146097
	var doe := z - era * 146097
	var yoe := (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
	var doy := doe - (365 * yoe + yoe / 4 - yoe / 100)
	var mp := (5 * doy + 2) / 153
	var d := doy - (153 * mp + 2) / 5 + 1
	var m := mp + 3 if mp < 10 else mp - 9
	var y := yoe + era * 400 + (1 if m <= 2 else 0)
	return [y, m, d]


static func day_number(y: int, m: int, d: int) -> int:
	var yy := y - (1 if m <= 2 else 0)
	var era := (yy if yy >= 0 else yy - 399) / 400
	var yoe := yy - era * 400
	var doy := (153 * (m - 3 if m > 2 else m + 9) + 2) / 5 + d - 1
	var doe := yoe * 365 + yoe / 4 - yoe / 100 + doy
	return era * 146097 + doe - 719468


static func md(day: int) -> String:
	var c := civil(day)
	return "%02d-%02d" % [c[1], c[2]]


static func events(day: int, owned: Array, player_md: String = "") -> Array:
	var c := civil(day)
	var key_md := "%02d-%02d" % [c[1], c[2]]
	var out: Array = []
	if player_md != "" and player_md == key_md:
		out.append({"kind": "player", "id": "player", "key": "you-%d" % c[0], "gift": (_d.player_birthday.gift as Dictionary).duplicate()})
	for h: Dictionary in _d.days:
		if str(h.md) == key_md:
			out.append({"kind": "day", "id": str(h.id), "key": "%s-%d" % [str(h.id), c[0]], "gift": (h.gift as Dictionary).duplicate()})
	var bd: Dictionary = _d.birthdays
	for id: Variant in bd:
		if str(bd[id]) == key_md and owned.has(str(id)):
			out.append({"kind": "birthday", "id": str(id), "key": "bday-%s-%d" % [str(id), c[0]],
				"gift": (_d.birthday.gift as Dictionary).duplicate()})
	return out


const MONTH_DAYS: Array[int] = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]


## A month-day as "MM-DD" if it is a real date (02-29 allowed), else "".
static func clean_md(s: String) -> String:
	var parts := s.split("-")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return ""
	var m := int(parts[0])
	var d := int(parts[1])
	if m < 1 or m > 12 or d < 1 or d > MONTH_DAYS[m - 1]:
		return ""
	return "%02d-%02d" % [m, d]


## Her skins' discount on her birthday (bp; 0 on any other day).
static func skin_discount_bp(day: int, hero_id: String) -> int:
	var b := birthday(hero_id)
	return int(_d.birthday.get("skin_discount_bp", 0)) if b != "" and b == md(day) else 0


## A skin's price in gems on `day`: its tier price, less her birthday discount.
static func skin_price(price_gems: int, day: int, hero_id: String) -> int:
	return price_gems * (10000 - skin_discount_bp(day, hero_id)) / 10000


## A heroine's birthday as "MM-DD" ("" if she has none).
static func birthday(hero_id: String) -> String:
	return str((_d.birthdays as Dictionary).get(hero_id, ""))


## A holiday's data entry ({} when unknown).
static func holiday(id: String) -> Dictionary:
	for h: Dictionary in _d.days:
		if str(h.id) == id:
			return h
	return {}


## Her line for an event, by her faction: a holiday's own line; for a birthday "mine" when it is
## hers and "other" (with {her} as the birthday heroine's name) when it is someone else's; for the
## player's birthday its line with {name} (pass the player's name as her_name).
static func line(ev: Dictionary, speaker_id: String, speaker_faction: String, her_name: String) -> String:
	if str(ev.get("kind", "")) == "player":
		return str((_d.player_birthday.lines as Dictionary).get(speaker_faction, "")).replace("{name}", her_name)
	if str(ev.get("kind", "")) == "birthday":
		var b: Dictionary = _d.birthday
		if str(ev.id) == speaker_id:
			return str((b.mine as Dictionary).get(speaker_faction, ""))
		return str((b.other as Dictionary).get(speaker_faction, "")).replace("{her}", her_name)
	return str((holiday(str(ev.get("id", ""))).get("lines", {}) as Dictionary).get(speaker_faction, ""))


## The Lobby band's ink on a holiday that has one ("" otherwise): the first of the day's holidays.
static func ink(day: int) -> String:
	var key_md := md(day)
	for h: Dictionary in _d.days:
		if str(h.md) == key_md and str(h.get("ink", "")) != "":
			return str(h.ink)
	return ""


## The stamp's word for an event.
static func stamp(ev: Dictionary) -> String:
	if str(ev.get("kind", "")) == "player":
		return str(_d.player_birthday.stamp)
	if str(ev.get("kind", "")) == "birthday":
		return str(_d.birthday.stamp)
	return str(holiday(str(ev.get("id", ""))).get("stamp", ""))
