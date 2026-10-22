class_name WarRules
extends RefCounted
## The War for Souls (docs/dev/feature-ideas.md, docs/dev/combat-v1.md), offline first: the
## afterlife's front between Heaven and Hell runs through seven sectors (data/war.json). Every day
## both sides push every sector with a simulated host of souls; the player fights for one side and
## sends the souls they win (souls_per_win per victory) into the sector they focus on. A sector's
## control is a running sum over the week; the side holding more sectors at the week's end wins it.
## Both sides are rewarded every week (the winners a little more): the war never takes anything.
## Pure functions on data/war.json; the day and the player's log are passed in (GameModel).
## Golden fixture: data/fixtures/war.json. Port spec: docs/dev/unity-port.md section 9d.
##
##   week_of(day)   = floor((day - epoch_day) / week_days)       (floor division, also before epoch)
##   week_start(w)  = epoch_day + w * week_days
##   sim_push(day, sector, side) = base + SeededRng(mix(mix(seed, day), sector * 2 + k)).range_int(0,
##                    spread), k = 0 for heaven, 1 for hell (one draw)
##   control(week, upto_day, log, side): c[s] = 0 for every sector; for each day d from week_start to
##     min(upto_day, week_start + week_days - 1), for each sector s:
##       diff = sim_push(d, s, heaven) - sim_push(d, s, hell)
##              + (souls the player logged on day d in sector s) * (+1 heaven / -1 hell; 0 no side)
##       c[s] = clamp(c[s] + diff * control_per_soul_bp, -control_max_bp, control_max_bp)
##     positive control: Heaven holds the sector; negative: Hell; 0: nobody.
##   standing(c) = {heaven: sectors > 0, hell: sectors < 0, winner: the side with more ("" on a tie)}
##   reward(won, held) = rewards.all, plus rewards.won when the player's side won, plus
##                       rewards.held_per_sector times the sectors their side held (summed per key)
## The Champion: each week the other side fields one heroine as a giant boss everyone on the player's
## side wears down (offline: the player's own damage). champion_for(week, side) = the OTHER side's
## pool [posmod(week, size)] (the heaven pool is Heaven's champions, so a heaven player meets the
## hell pool); champion_level(avg) = max(min_level, avg + level_over); her stats are
## StatCalc.stats(id, level, stars) with hp * hp_bp / 10000 and atk * atk_bp / 10000 (then the
## battle's boss multipliers and her passives: GameModel reads her max HP from a BattleSim with her
## alone); tiers_reached(hp, damage) = the indices of tiers with damage * 100 >= hp * pct, in order.
## The log: {"<day>": {"<sector>": souls}} (string keys, as saved).

static var _d: Dictionary = GameData.file("war")
static var NAME: String = str(_d.name)
static var UNLOCK_CLEARED: int = int(_d.unlock_cleared)
static var EPOCH_DAY: int = int(_d.epoch_day)
static var SEED: int = int(_d.seed)
static var WEEK_DAYS: int = int(_d.week_days)
static var SIDES: Array = _d.sides
static var SECTORS: Array = _d.sectors
static var SOULS_PER_WIN: int = int(_d.souls_per_win)
static var SIM_BASE: int = int(_d.sim.base)
static var SIM_SPREAD: int = int(_d.sim.spread)
static var CONTROL_PER_SOUL_BP: int = int(_d.control_per_soul_bp)
static var CONTROL_MAX_BP: int = int(_d.control_max_bp)
static var LOG_DAYS: int = int(_d.log_days)
static var _C: Dictionary = _d.champion
static var CHAMP_LEVEL_OVER: int = int(_C.level_over)
static var CHAMP_MIN_LEVEL: int = int(_C.min_level)
static var CHAMP_STARS: int = int(_C.stars)
static var CHAMP_HP_BP: int = int(_C.hp_bp)
static var CHAMP_ATK_BP: int = int(_C.atk_bp)
static var CHAMP_MAX_MS: int = int(_C.max_ms)
static var CHAMP_TRIES: int = int(_C.tries_per_day)
static var CHAMP_TIERS: Array = _C.tiers


static func sector_count() -> int:
	return SECTORS.size()


static func side_name(side: String) -> String:
	return str((_d.side_names as Dictionary).get(side, ""))


## The week a day belongs to (floor division from the epoch).
static func week_of(day: int) -> int:
	var x := day - EPOCH_DAY
	if x >= 0:
		return x / WEEK_DAYS
	return -((-x - 1) / WEEK_DAYS) - 1


static func week_start(week: int) -> int:
	return EPOCH_DAY + week * WEEK_DAYS


## Souls a side sends into a sector on a day (the simulated hosts of both sides).
static func sim_push(day: int, sector: int, side: String) -> int:
	var k := 0 if side == "heaven" else 1
	var rng := SeededRng.new(SeededRng.mix(SeededRng.mix(SEED, day), sector * 2 + k))
	return SIM_BASE + rng.range_int(0, SIM_SPREAD)


## Souls the player logged on `day` in `sector`.
static func logged(log: Dictionary, day: int, sector: int) -> int:
	var dl: Variant = log.get(str(day), null)
	if not (dl is Dictionary):
		return 0
	return int((dl as Dictionary).get(str(sector), 0))


## Control of every sector (bp, + Heaven / - Hell) for `week` up to and including `upto_day`.
static func control(week: int, upto_day: int, log: Dictionary, side: String) -> Array[int]:
	var n := sector_count()
	var c: Array[int] = []
	c.resize(n)
	c.fill(0)
	var sign := 1 if side == "heaven" else (-1 if side == "hell" else 0)
	var d0 := week_start(week)
	var d1 := mini(upto_day, d0 + WEEK_DAYS - 1)
	for d in range(d0, d1 + 1):
		for s in n:
			var diff := sim_push(d, s, "heaven") - sim_push(d, s, "hell") + logged(log, d, s) * sign
			c[s] = clampi(c[s] + diff * CONTROL_PER_SOUL_BP, -CONTROL_MAX_BP, CONTROL_MAX_BP)
	return c


static func standing(c: Array) -> Dictionary:
	var h := 0
	var e := 0
	for v: Variant in c:
		if int(v) > 0:
			h += 1
		elif int(v) < 0:
			e += 1
	return {"heaven": h, "hell": e, "winner": "heaven" if h > e else ("hell" if e > h else "")}


## The week's reward for a player on a side: everyone's share, the winners' bonus, per sector held.
static func reward(won: bool, held: int) -> Dictionary:
	var r: Dictionary = (_d.rewards.all as Dictionary).duplicate(true)
	if won:
		_add(r, _d.rewards.won)
	for i in maxi(0, held):
		_add(r, _d.rewards.held_per_sector)
	return r


static func _add(into: Dictionary, more: Dictionary) -> void:
	for k: Variant in more:
		into[str(k)] = int(into.get(str(k), 0)) + int(more[k])


## The side the player fights against.
static func other_side(side: String) -> String:
	return "hell" if side == "heaven" else ("heaven" if side == "hell" else "")


## This week's enemy Champion for a player on `side` ("" without a side).
static func champion_for(week: int, side: String) -> String:
	var pool: Array = (_C.pools as Dictionary).get(other_side(side), [])
	if pool.is_empty():
		return ""
	return str(pool[posmod(week, pool.size())])


static func champion_level(avg_level: int) -> int:
	return maxi(CHAMP_MIN_LEVEL, avg_level + CHAMP_LEVEL_OVER)


## Her stats before the battle's boss multipliers: StatCalc's at level/stars, HP and ATK scaled.
static func champion_stats(hero_id: String, level: int) -> Dictionary:
	var st: Dictionary = StatCalc.stats(hero_id, level, CHAMP_STARS)
	st.hp = int(st.hp) * CHAMP_HP_BP / 10000
	st.atk = int(st.atk) * CHAMP_ATK_BP / 10000
	return st


## The tier indices reached by `damage` against `hp`.
static func tiers_reached(hp: int, damage: int) -> Array[int]:
	var out: Array[int] = []
	for i in CHAMP_TIERS.size():
		if damage * 100 >= hp * int((CHAMP_TIERS[i] as Dictionary).pct):
			out.append(i)
	return out


## A fresh save block: no side chosen, focus on the middle sector, nothing logged or claimed, no
## champion yet (she is set up on the first look of a week).
static func new_state() -> Dictionary:
	return {"side": "", "focus": sector_count() / 2, "log": {}, "claimed_week": -1000000, "souls_total": 0, "seen_week": -1000000,
		"champ": {"week": -1000000, "hero": "", "level": 0, "hp": 0, "damage": 0, "day": -1000000, "tries": 0, "tiers": []},
		"keepers": {}, "levels": {}, "layout": {}}
