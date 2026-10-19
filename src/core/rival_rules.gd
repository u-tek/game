class_name RivalRules
extends RefCounted
## The Rival "Rue": another summoner simulated on the phone (no server). She pulls on the same
## banners every day, keeps her best prints, climbs alongside the player and can be fought. Pure
## functions on data/rival.json; the day, the player's team and the save's rival block are passed
## in (GameModel), never read from the clock here. Nothing she does takes anything from the player.
## Golden fixture: data/fixtures/rival.json. Port spec: docs/dev/unity-port.md section 9c.
##
## Her heroes (rs.heroes = {id: dupes}, start_heroes with 0 dupes on the first sync):
##   stars(id) = clamp(start_stars(rarity) + dupes / dupes_per_star, start_stars, min(cap, MAX_STARS))
##               cap = the player's best formation stars + stars_over_you
##   level     = max(1, the player's formation average level (integer division; 1 with no team)
##               + level_wobble[posmod(day, 7)] + (counter_level when she counter-picks));
##               each hero then clamped to 1..level_cap(her stars)
##   counter   = she counter-picks once fights >= learn_after and the player has a main faction
##               (the faction most of the formation belongs to; ties go to battle.json's factions
##               order): she prefers the faction whose BEATS entry is that main faction
##   team      = her heroes sorted by (preferred faction first, power of StatCalc.stats(id, level,
##               stars) desc, roster order asc), the first 5; then placed front-liners first
##               (FRONT_PRIORITY[role] desc, then that order) in slots 0..4; each fights as an echo at
##               echo_bp = StageData.ECHO_STAT_BP * strength_bp / 10000
## Her day (sim_day), for each day she has not simulated yet (catch_up: at most catch_up_days,
## ending today):
##   bid  = banner_cycle[posmod(day - epoch_day, size)];  b = banner.json's banner bid
##   opts = featured: {featured: featured_for(b, day), lost: rs.lost}; faction: {faction:
##          faction_for(b, day)}; wish: {target: wish_choices(b)[0]}
##   roll = SummonRules.pull(b, rs.seed, rs.pulls, rs.pity[bid] (0), pulls_per_day, opts)
##   rs.pulls, rs.pity[bid] (and rs.lost) from the roll; each result in order: a new hero joins
##   with 0 dupes, a known one gains a dupe; a Legendary queues an event: "featured_first" when it
##   is the featured hero and the player does not own her, else "legendary"
##   her prints: PrintRules.make_prints(bid, ids, day, epoch_day, hours, rs.ed[bid] ({}),
##          mix(rs.seed, PrintRules.SEED), rs.print_seq) with hours = (day - open_day) * 24 +
##          pull_hour (open_day of that banner's edition); print k gets n = print_seq + k + 1,
##          uid "rue-<n>", day, first (her new hero), taken false; then print_seq += count;
##          a print with a flaw queues "misprint", one with holo foil "holo" (in pull order)
##   she keeps a print when keeps(p): a flaw, holo, grade >= 9 or serial <= early_serial; her
##   list is sorted by (taken last, score desc, n asc), cut to prints_max, then by (score desc,
##   n asc)
##   events become feed entries in order: {n: ++feed_seq, day, type, hero, flaw, ink, line}
##   (line: line(type, rs.seed, day, k) with k = the event's index that day, filled with hero =
##   her name, flaw = PrintRules.flaw_adj); the feed is newest first, cut to feed_max
## Lines: line(kind, seed, day, salt) = lines[kind][posmod(mix(seed, day) + salt, size)] (so the
## events of one day, salts 0, 1, 2 ..., never repeat a line while the kind has more), then fill()
## replaces {hero} {you} {flaw} {faction} {main} and capitalises the first letter.

static var _d: Dictionary = GameData.file("rival")
static var NAME: String = str(_d.name)
static var TITLE: String = str(_d.title)
static var UNLOCK_CLEARED: int = int(_d.unlock_cleared)
static var SEED: int = int(_d.seed)
static var PULLS_PER_DAY: int = int(_d.pulls_per_day)
static var CATCH_UP_DAYS: int = int(_d.catch_up_days)
static var FEED_MAX: int = int(_d.feed_max)
static var PRINTS_MAX: int = int(_d.prints_max)
static var STRENGTH_BP: int = int(_d.strength_bp)

## Event kinds that go into her feed (and the line lists that voice them).
const EVENTS: Array[String] = ["featured_first", "legendary", "misprint", "holo"]


## The rival block of a new save. save_seed: a per-save number (GameModel passes one derived
## from the clock at the start, like rng_seed).
static func new_state(save_seed: int) -> Dictionary:
	return {"seed": SeededRng.mix(save_seed, SEED), "met": false, "day": -1, "heroes": {}, "pulls": 0,
		"pity": {}, "lost": false, "ed": {}, "print_seq": 0, "prints": [], "feed": [], "feed_seq": 0, "seen": 0,
		"wins": 0, "losses": 0, "fights": 0, "haul_day": -1, "tag_you": false, "tag_her": false, "tag_v": 0}


static func data() -> Dictionary:
	return _d


static func start_heroes() -> Array:
	return _d.start_heroes


## The banner she pulls on that day.
static func banner_on(day: int, epoch_day: int) -> String:
	var cyc: Array = _d.banner_cycle
	return str(cyc[posmod(day - epoch_day, cyc.size())])


## The faction that beats `main` on the counter wheel ("" when main is "").
static func counter_faction(main: String) -> String:
	if main == "":
		return ""
	for f in BattleSim.FACTIONS:
		if str(BattleSim.BEATS.get(f, "")) == main:
			return f
	return ""


## Her stars for a hero with `dupes` duplicates, under the cap (the player's best + stars_over_you).
static func stars_for(hero_id: String, dupes: int, cap: int) -> int:
	var s0 := Progression.start_stars(str(HeroData.get_def(hero_id).get("rarity", "rare")))
	var top := mini(cap + int(_d.stars_over_you), EconomyData.MAX_STARS)
	return maxi(s0, mini(s0 + maxi(0, dupes) / maxi(1, int(_d.dupes_per_star)), top))


## Her team level on `day`, before each hero's own level cap.
static func level_on(avg_level: int, day: int, countering: bool) -> int:
	var wob: Array = _d.level_wobble
	var lv := avg_level + int(wob[posmod(day, wob.size())])
	if countering:
		lv += int(_d.counter_level)
	return maxi(1, lv)


## True once she has fought the player often enough to counter-pick (and there is a main faction).
static func counters(fights: int, main: String) -> bool:
	return fights >= int(_d.learn_after) and main != ""


## The echo strength her heroes fight at.
static func echo_bp() -> int:
	return StageData.ECHO_STAT_BP * STRENGTH_BP / 10000


## Her five best heroes as enemy entries [{hero_id, level, stars, slot, is_boss, echo_bp, power}]
## in slot order. heroes: {id: dupes}; cap: the player's best stars; level: level_on(...);
## prefer: the faction to stack ("" = none).
static func team(heroes: Dictionary, cap: int, level: int, prefer: String) -> Array:
	var cands: Array = []
	var ids := HeroData.ids()
	for i in ids.size():
		var id := ids[i]
		if not heroes.has(id):
			continue
		var st := stars_for(id, int(heroes[id]), cap)
		var lv := clampi(level, 1, Progression.level_cap(st))
		var pw := StatCalc.power(StatCalc.stats(id, lv, st))
		var pref := 1 if prefer != "" and str(HeroData.get_def(id).faction) == prefer else 0
		cands.append([pref, pw, i, id, lv, st])
	cands.sort_custom(func(a: Array, b: Array) -> bool:
		if a[0] != b[0]:
			return a[0] > b[0]
		if a[1] != b[1]:
			return a[1] > b[1]
		return a[2] < b[2])
	var picks := cands.slice(0, 5)
	var order: Array = []
	for k in picks.size():
		order.append([int(EconomyData.FRONT_PRIORITY.get(str(HeroData.get_def(str(picks[k][3])).role), 0)), k])
	order.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0] if a[0] != b[0] else a[1] < b[1])
	var eb := echo_bp()
	var out: Array = []
	for s in order.size():
		var c: Array = picks[int(order[s][1])]
		var lv2 := int(c[4])
		var st2 := int(c[5])
		out.append({"hero_id": str(c[3]), "level": lv2, "stars": st2, "slot": s, "is_boss": false, "echo_bp": eb,
			"power": StatCalc.power(StageData.echo_stats(str(c[3]), lv2, st2, eb))})
	return out


## Her strongest hero (the first pick of team(): the face on her poster), "" with no heroes.
static func ace(team_list: Array) -> String:
	var best := ""
	var best_p := -1
	for e: Dictionary in team_list:
		if int(e.power) > best_p:
			best_p = int(e.power)
			best = str(e.hero_id)
	return best


## True for a print she keeps: a flaw, holo foil, grade 9+ or an early serial.
static func keeps(p: Dictionary) -> bool:
	return str(p.get("flaw", "")) != "" or bool(p.get("holo", false)) or int(p.get("grade", 0)) >= 9 \
		or int(p.get("serial", PrintRules.EARLY_SERIAL + 1)) <= PrintRules.EARLY_SERIAL


## Simulates one day of her pulls into rs (changed in place). owns: {hero id: true} the player
## owns. Returns that day's events [{type, hero, flaw, ink}] in order (also added to her feed).
static func sim_day(rs: Dictionary, day: int, epoch_day: int, owns: Dictionary) -> Array:
	var bid := banner_on(day, epoch_day)
	var b := EconomyData.banner_def(bid)
	var kind := str(b.get("kind", "standard"))
	var opts := {}
	match kind:
		"featured":
			opts = {"featured": SummonRules.featured_for(b, day, epoch_day), "lost": bool(rs.lost)}
		"faction":
			opts = {"faction": SummonRules.faction_for(b, day, epoch_day)}
		"wish":
			var ch := SummonRules.wish_choices(b)
			opts = {"target": str(ch[0]) if not ch.is_empty() else ""}
	var pity: Dictionary = rs.pity
	var roll := SummonRules.pull(b, int(rs.seed), int(rs.pulls), int(pity.get(bid, 0)), PULLS_PER_DAY, opts)
	rs.pulls = int(roll.total_pulls)
	pity[bid] = int(roll.pity)
	if roll.has("lost"):
		rs.lost = bool(roll.lost)
	var heroes: Dictionary = rs.heroes
	var ids: Array = []
	var firsts: Array = []
	var events: Array = []
	for r: Dictionary in roll.results:
		var hid := str(r.hero_id)
		var is_new := not heroes.has(hid)
		heroes[hid] = 0 if is_new else int(heroes[hid]) + 1
		ids.append(hid)
		firsts.append(is_new)
		if str(r.rarity) == "legendary":
			var first := bool(r.get("featured", false)) and not owns.has(hid)
			events.append({"type": "featured_first" if first else "legendary", "hero": hid, "flaw": "", "ink": ""})
	var info := PrintRules.edition_on(bid, day, epoch_day)
	var hours := (day - int(info.open_day)) * 24 + int(_d.pull_hour)
	var eds: Dictionary = rs.ed
	var made := PrintRules.make_prints(bid, ids, day, epoch_day, hours, eds.get(bid, {}),
		SeededRng.mix(int(rs.seed), PrintRules.SEED), int(rs.print_seq))
	eds[bid] = made.ed
	var kept: Array = rs.prints
	var seq := int(rs.print_seq)
	for k in (made.prints as Array).size():
		var p: Dictionary = made.prints[k]
		var n := seq + k + 1
		p["n"] = n
		p["uid"] = "rue-%d" % n
		p["day"] = day
		p["first"] = bool(firsts[k])
		p["taken"] = false
		if str(p.flaw) != "":
			events.append({"type": "misprint", "hero": str(p.hero), "flaw": str(p.flaw), "ink": str(p.ink)})
		if bool(p.holo):
			events.append({"type": "holo", "hero": str(p.hero), "flaw": str(p.flaw), "ink": str(p.ink)})
		if keeps(p):
			kept.append(p)
	rs.print_seq = seq + ids.size()
	rs.prints = sort_prints(kept)
	var feed: Array = rs.feed
	for k in events.size():
		var e: Dictionary = events[k]
		rs.feed_seq = int(rs.feed_seq) + 1
		var fills := {"hero": str(HeroData.get_def(str(e.hero)).get("name", e.hero)), "flaw": PrintRules.flaw_adj(str(e.flaw))}
		feed.push_front({"n": int(rs.feed_seq), "day": day, "type": str(e.type), "hero": str(e.hero), "flaw": str(e.flaw),
			"ink": str(e.ink), "line": line(str(e.type), int(rs.seed), day, k, fills)})
	if feed.size() > FEED_MAX:
		feed.resize(FEED_MAX)
	return events


## Her kept prints: untaken first, best first, cut to prints_max; returned best first.
static func sort_prints(list: Array) -> Array:
	var a := list.duplicate()
	a.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		if bool(x.get("taken", false)) != bool(y.get("taken", false)):
			return not bool(x.get("taken", false))
		var sx := PrintRules.score(x)
		var sy := PrintRules.score(y)
		if sx != sy:
			return sx > sy
		return int(x.get("n", 0)) < int(y.get("n", 0)))
	if a.size() > PRINTS_MAX:
		a.resize(PRINTS_MAX)
	a.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		var sx := PrintRules.score(x)
		var sy := PrintRules.score(y)
		if sx != sy:
			return sx > sy
		return int(x.get("n", 0)) < int(y.get("n", 0)))
	return a


## Brings her up to `today`: the start roster on the first call, then every day after rs.day, at
## most catch_up_days of them (the last ones). A clock that went back simulates nothing. Returns
## the number of days simulated.
static func catch_up(rs: Dictionary, today: int, epoch_day: int, owns: Dictionary) -> int:
	var heroes: Dictionary = rs.heroes
	if heroes.is_empty():
		for id: Variant in _d.start_heroes:
			heroes[str(id)] = 0
	if int(rs.day) < 0:
		rs.day = today - 1
	if today <= int(rs.day):
		return 0
	var from := maxi(int(rs.day) + 1, today - CATCH_UP_DAYS + 1)
	for d in range(from, today + 1):
		sim_day(rs, d, epoch_day, owns)
	rs.day = today
	return today - from + 1


## The best print she has not given away yet ({} when none).
static func best_untaken(rs: Dictionary) -> Dictionary:
	var best := {}
	for p: Dictionary in rs.prints:
		if bool(p.get("taken", false)):
			continue
		if best.is_empty() or PrintRules.score(p) > PrintRules.score(best) or \
				(PrintRules.score(p) == PrintRules.score(best) and int(p.n) < int(best.n)):
			best = p
	return best


## The haul for a first win of the day: {gems, gold, dust}. cleared: the player's stages cleared.
static func haul(cleared: int) -> Dictionary:
	var h: Dictionary = _d.haul
	return {"gems": int(h.gems), "gold": int(h.gold_base) + int(h.gold_per_stage) * cleared, "dust": int(h.dust)}


## Her campaign progress and Spire floor on `day`: a step ahead of (or behind) the player's.
static func cleared_on(player_cleared: int, day: int) -> int:
	var lead: Array = _d.stage_lead
	return clampi(player_cleared + int(lead[posmod(day, lead.size())]), 0, StageData.count())


static func tower_on(player_best: int, day: int) -> int:
	var lead: Array = _d.tower_lead
	return clampi(player_best + int(lead[posmod(day, lead.size())]), 0, TowerData.FLOORS)


## The battle backdrop for a fight on `day`.
static func background(day: int) -> String:
	var bgs: Array = _d.backgrounds
	return str(bgs[posmod(day, bgs.size())])


## One of her lines of `kind`, picked by day and salt and filled (see the header).
static func line(kind: String, seed_value: int, day: int, salt: int, fills: Dictionary = {}) -> String:
	var lines: Dictionary = _d.lines
	var arr: Array = lines.get(kind, [])
	if arr.is_empty():
		return ""
	return fill(str(arr[posmod(SeededRng.mix(seed_value, day) + salt, arr.size())]), fills)


## Replaces {hero} {you} {flaw} {faction} {main} and capitalises the first letter.
static func fill(text: String, fills: Dictionary) -> String:
	var t := text
	for k: Variant in fills:
		t = t.replace("{%s}" % str(k), str(fills[k]))
	if t.length() > 0:
		t = t.left(1).to_upper() + t.substr(1)
	return t
