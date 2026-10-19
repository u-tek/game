class_name PrintRules
extends RefCounted
## Misprints: every hero a summon gives comes as a numbered print of the banner's edition, and a
## few come out misprinted. Cosmetic only: prints never change stats and never fade. Pure
## functions on data/prints.json; the day, the hours since the edition opened and the save's
## counters are passed in (GameModel), never read from the clock here. Golden fixture:
## data/fixtures/prints.json. Port spec: docs/dev/unity-port.md section 8.5.
##
## Edition of a banner on `day`: index = SummonRules.period_index(day, epoch_day, days) (days from
## editions[banner]); edition = max(1, index + 1); it opened on epoch_day + index * days.
## The save keeps, per banner, {e: edition index, n: prints taken from it}; n restarts at 0 in a
## new edition. One summon's prints use one stream:
##   rng = SeededRng(SeededRng.mix(seed, seq))       (seq = prints made before this summon)
##   for each hero, in pull order:
##     raw      = 1 + hours_open * per_hour + n       (hours_open: whole hours since it opened)
##     printing = (raw - 1) / run + 1;  serial = (raw - 1) % run + 1
##     r = rng.range_int(0, 9999): the first flaw whose running bp total is > r, else none
##     holo  = rng.chance_bp(holo_bp)
##     g = rng.range_int(0, 9999): the first grade whose running bp total is > g
##     v = rng.range_int(0, 999)                      (picks the look of the flaw)
##     gap = rng.range_int(0, other_takers_max)       (other collectors in between)
##     ink = inks[v % inks.size()] for a "swap" flaw, else ""
##     n += 1 + gap
## Draws per print, always in this order: range_int, chance_bp, range_int, range_int, range_int.

static var _d: Dictionary = GameData.file("prints")
static var SEED: int = int(_d.seed)
static var EARLY_SERIAL: int = int(_d.early_serial)
static var KEEP_PLAIN: int = int(_d.keep_plain)
static var SHOWCASE_MAX: int = int(_d.showcase_max)


static func edition_def(banner_id: String) -> Dictionary:
	var eds: Dictionary = _d.editions
	return eds.get(banner_id, eds.standard)


## {index, edition, open_day, days, run, per_hour} of the banner's edition on `day`.
static func edition_on(banner_id: String, day: int, epoch_day: int) -> Dictionary:
	var ed := edition_def(banner_id)
	var days := maxi(1, int(ed.days))
	var idx := SummonRules.period_index(day, epoch_day, days)
	return {"index": idx, "edition": maxi(1, idx + 1), "open_day": epoch_day + idx * days, "days": days,
		"run": int(ed.run), "per_hour": int(ed.per_hour)}


## The flaw for a roll r in 0..9999 ("" = a clean print).
static func flaw_for_roll(r: int) -> String:
	var acc := 0
	for f: Dictionary in _d.flaws:
		acc += int(f.bp)
		if r < acc:
			return str(f.id)
	return ""


## The grade (1-10) for a roll g in 0..9999.
static func grade_for_roll(g: int) -> int:
	var acc := 0
	var last := 1
	for row: Array in _d.grades:
		acc += int(row[1])
		last = int(row[0])
		if g < acc:
			return last
	return last


## Prints for one summon. ed: the banner's saved {e, n}. Returns {prints: [{hero, banner,
## edition, printing, serial, run, flaw, ink, holo, grade, v}], ed: {e, n}}.
static func make_prints(banner_id: String, hero_ids: Array, day: int, epoch_day: int, hours_open: int,
		ed: Dictionary, seed_value: int, seq: int) -> Dictionary:
	var info := edition_on(banner_id, day, epoch_day)
	var n := int(ed.get("n", 0)) if int(ed.get("e", -999999)) == int(info.index) else 0
	var run := maxi(1, int(info.run))
	var inks: Array = _d.inks
	var rng := SeededRng.new(SeededRng.mix(seed_value, seq))
	var out: Array = []
	for hid: Variant in hero_ids:
		var raw := 1 + maxi(0, hours_open) * int(info.per_hour) + n
		var flaw := flaw_for_roll(rng.range_int(0, 9999))
		var holo := rng.chance_bp(int(_d.holo_bp))
		var grade := grade_for_roll(rng.range_int(0, 9999))
		var v := rng.range_int(0, 999)
		var gap := rng.range_int(0, int(_d.other_takers_max))
		out.append({"hero": str(hid), "banner": banner_id, "edition": int(info.edition),
			"printing": (raw - 1) / run + 1, "serial": (raw - 1) % run + 1, "run": run,
			"flaw": flaw, "ink": str(inks[v % inks.size()]) if flaw == "swap" else "",
			"holo": holo, "grade": grade, "v": v})
		n += 1 + gap
	return {"prints": out, "ed": {"e": int(info.index), "n": n}}


## True for a print worth keeping forever: a flaw, holo, grade 9+, an early serial, the first copy
## of a hero, or one won from the Rival.
static func notable(p: Dictionary) -> bool:
	return str(p.get("flaw", "")) != "" or bool(p.get("holo", false)) or int(p.get("grade", 0)) >= 9 \
		or int(p.get("serial", EARLY_SERIAL + 1)) <= EARLY_SERIAL or bool(p.get("first", false)) \
		or str(p.get("from", "")) != ""


## Collector's score (higher = rarer), for "best print" picks and sorting:
## grade * 100, + 3000 for holo, + 2000 + (300 - flaw bp) for a flaw, + 600 + (early_serial -
## serial) for an early serial, + 50 for a first printing.
static func score(p: Dictionary) -> int:
	var s := int(p.get("grade", 0)) * 100
	if bool(p.get("holo", false)):
		s += 3000
	var f := flaw_def(str(p.get("flaw", "")))
	if not f.is_empty():
		s += 2000 + (300 - int(f.bp))
	var serial := int(p.get("serial", EARLY_SERIAL + 1))
	if serial <= EARLY_SERIAL:
		s += 600 + (EARLY_SERIAL - serial)
	if int(p.get("printing", 1)) == 1:
		s += 50
	return s


## Keeps every notable print and the newest `keep_plain` plain ones (list is oldest first).
static func trim(list: Array, keep_plain: int = -1) -> Array:
	var keep := KEEP_PLAIN if keep_plain < 0 else keep_plain
	var plain := 0
	for p: Dictionary in list:
		if not notable(p):
			plain += 1
	var drop := maxi(0, plain - keep)
	var out: Array = []
	for p: Dictionary in list:
		if drop > 0 and not notable(p):
			drop -= 1
			continue
		out.append(p)
	return out


static func flaw_def(id: String) -> Dictionary:
	if id == "":
		return {}
	for f: Dictionary in _d.flaws:
		if str(f.id) == id:
			return f
	return {}


static func flaws() -> Array:
	return _d.flaws


static func grade_name(g: int) -> String:
	return str((_d.grade_names as Dictionary).get(str(g), ""))


## The flaw's printed name ("Off register"), "" for a clean print.
static func flaw_name(id: String) -> String:
	return str(flaw_def(id).get("name", ""))


## The flaw as an adjective for lines ("off-register"), "" for a clean print.
static func flaw_adj(id: String) -> String:
	return str(flaw_def(id).get("adj", ""))


## A swapped ink's printed name ("Acid green"), "" when none.
static func ink_name(ink: String) -> String:
	return str((_d.ink_names as Dictionary).get(ink, ""))


static func inks() -> Array:
	return _d.inks


## The serial as printed: "No. 0412".
static func serial_text(p: Dictionary) -> String:
	return "No. %04d" % int(p.get("serial", 0))
