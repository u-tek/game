class_name SummonRules
extends RefCounted
## Gacha rules: rarity rolls, Legendary pity, the 10-pull guarantee, hero picks and the banner
## rotations. Pure functions; banners come from data/banner.json (EconomyData.BANNERS), hero
## rarities and factions from data/heroes.json. The day index is passed in (GameModel.today()),
## never read from the clock here. Golden fixture: data/fixtures/summon.json.
##
## Banner kinds (banner.kind):
##   standard  the whole pool.
##   featured  rate-up: a Legendary is the featured hero (opts.featured) with featured_bp chance;
##             after a Legendary that was not the featured one (opts.lost), the next Legendary is
##             the featured one for sure. The featured hero rotates every rotation_days days.
##   faction   the pool is cut to one faction (opts.faction), rotating every rotation_days days.
##   wish      every Legendary is the player's chosen target (opts.target).
##   envoy     no Legendary rate and no pity (pity_legendary 0): Rare and Epic only.
##
## One summon of `count` pulls (1 or 10) with the save's summon state {seed, total_pulls} and
## the banner's own pity (total_pulls counts every pull on every banner, so no two pulls share
## a random stream):
##   rng = SeededRng(SeededRng.mix(seed, total_pulls))      (total_pulls before this summon)
##   pool = pool_by_rarity(banner, faction if kind == "faction" else "")
##   for i in 0..count-1:
##     rarity = "legendary" if pity_legendary > 0 and pity >= pity_legendary - 1
##              else r = rng.range_int(0, 9999): r < legendary_bp -> legendary,
##                   r < legendary_bp + epic_bp -> epic, else rare
##     if count == 10 and i == 9 and no epic/legendary yet in this summon and rarity == rare:
##       rarity = ten_pull_guarantee
##     if pity_legendary > 0: pity = 0 if legendary else pity + 1   (else pity stays as it is)
##     total_pulls += 1
##     hero_id = featured legendary: featured if lost or rng.chance_bp(featured_bp), else
##                 rng.pick(the other legendaries) (featured when there are none); lost = hero != featured
##               wish legendary: target (no draw)
##               else rng.pick(pool[rarity])
## The pity check uses no random draw, so a forced Legendary skips the range_int call.

const KINDS: Array[String] = ["standard", "featured", "faction", "wish", "envoy"]


## Banner pool grouped by rarity, in pool order: {rare: [ids], epic: [ids], legendary: [ids]}.
## faction: keep only that faction's heroes ("" = all).
static func pool_by_rarity(banner: Dictionary, faction: String = "") -> Dictionary:
	var out := {"rare": [], "epic": [], "legendary": []}
	for id in banner.get("pool", []):
		var d := HeroData.get_def(str(id))
		if d.is_empty() or not out.has(d.rarity):
			continue
		if faction != "" and str(d.faction) != faction:
			continue
		out[d.rarity].append(str(id))
	return out


static func roll_rarity(rng: SeededRng, pity: int, banner: Dictionary) -> String:
	var pity_max := int(banner.get("pity_legendary", 0))
	if pity_max > 0 and pity >= pity_max - 1:
		return "legendary"
	return rarity_for_roll(rng.range_int(0, 9999), banner)


## Rarity of a roll r in 0..9999: r < legendary_bp -> legendary; r < legendary_bp + epic_bp
## -> epic; else rare.
static func rarity_for_roll(r: int, banner: Dictionary) -> String:
	var rates: Dictionary = banner.rates
	if r < int(rates.legendary):
		return "legendary"
	if r < int(rates.legendary) + int(rates.epic):
		return "epic"
	return "rare"


# ---------------------------------------------------------------- rotations

## Which rotation period `day` falls in: floor((day - epoch_day) / days) (floor also before the
## epoch). days < 1 counts as 1.
static func period_index(day: int, epoch_day: int, days: int) -> int:
	var x := day - epoch_day
	var p := maxi(1, days)
	if x >= 0:
		return x / p
	return -((-x - 1) / p) - 1


## The first day of the next period (the day the current pick changes).
static func next_change_day(day: int, epoch_day: int, days: int) -> int:
	return epoch_day + (period_index(day, epoch_day, days) + 1) * maxi(1, days)


## Entry posmod(period_index, size) of `list` ("" if empty).
static func rotation_pick(list: Array, day: int, epoch_day: int, days: int) -> String:
	if list.is_empty():
		return ""
	return str(list[posmod(period_index(day, epoch_day, days), list.size())])


## The featured Legendary of a featured banner on `day` ("" for other kinds).
static func featured_for(banner: Dictionary, day: int, epoch_day: int) -> String:
	if str(banner.get("kind", "")) != "featured":
		return ""
	return rotation_pick(banner.get("featured_rotation", []), day, epoch_day, int(banner.get("rotation_days", 7)))


## The faction of a faction banner on `day` ("" for other kinds).
static func faction_for(banner: Dictionary, day: int, epoch_day: int) -> String:
	if str(banner.get("kind", "")) != "faction":
		return ""
	return rotation_pick(banner.get("faction_rotation", []), day, epoch_day, int(banner.get("rotation_days", 1)))


## The period a banner's pull limit counts in on `day`: the day itself for "day", the week
## index from the epoch for "week", -1 when the banner has no limit.
static func limit_period(banner: Dictionary, day: int, epoch_day: int) -> int:
	var lim: Dictionary = banner.get("limit", {})
	match str(lim.get("period", "")):
		"day":
			return day
		"week":
			return period_index(day, epoch_day, 7)
	return -1


## The day the banner's current limit period ends (the first day of the next one), -1 if none.
static func limit_resets_day(banner: Dictionary, day: int, epoch_day: int) -> int:
	var lim: Dictionary = banner.get("limit", {})
	match str(lim.get("period", "")):
		"day":
			return day + 1
		"week":
			return next_change_day(day, epoch_day, 7)
	return -1


# ---------------------------------------------------------------- pulls

## Rolls `count` pulls. opts: featured (hero id), lost (bool) for a featured banner; faction for
## a faction banner; target (a Legendary id) for a wish banner. Returns {results: [{hero_id,
## rarity, pity (after this pull)}], pity, total_pulls} (the new summon state); a featured banner
## also returns lost and marks each result featured (bool).
static func pull(banner: Dictionary, seed_value: int, total_pulls: int, pity: int, count: int, opts: Dictionary = {}) -> Dictionary:
	var kind := str(banner.get("kind", "standard"))
	var pool := pool_by_rarity(banner, str(opts.get("faction", "")) if kind == "faction" else "")
	var featured := str(opts.get("featured", "")) if kind == "featured" else ""
	var lost := bool(opts.get("lost", false))
	var target := str(opts.get("target", "")) if kind == "wish" else ""
	var others: Array = []
	for id: Variant in pool.legendary:
		if str(id) != featured:
			others.append(str(id))
	var has_pity := int(banner.get("pity_legendary", 0)) > 0
	var rng := SeededRng.new(SeededRng.mix(seed_value, total_pulls))
	var results: Array = []
	var got_epic := false
	var p := pity
	var total := total_pulls
	for i in count:
		var rarity := roll_rarity(rng, p, banner)
		if count == 10 and i == 9 and not got_epic and rarity == "rare":
			rarity = str(banner.get("ten_pull_guarantee", "epic"))
		if rarity != "rare":
			got_epic = true
		if has_pity:
			p = 0 if rarity == "legendary" else p + 1
		total += 1
		var hid := ""
		if rarity == "legendary" and featured != "":
			if lost or rng.chance_bp(int(banner.get("featured_bp", 5000))):
				hid = featured
			elif others.is_empty():
				hid = featured
			else:
				hid = str(rng.pick(others))
			lost = hid != featured
		elif rarity == "legendary" and target != "":
			hid = target
		else:
			hid = str(rng.pick(pool[rarity]))
		var r := {"hero_id": hid, "rarity": rarity, "pity": p}
		if kind == "featured":
			r["featured"] = hid == featured
		results.append(r)
	var out := {"results": results, "pity": p, "total_pulls": total}
	if kind == "featured":
		out["lost"] = lost
	return out


## The Legendaries a wish banner lets the player choose from (pool order).
static func wish_choices(banner: Dictionary) -> Array:
	return pool_by_rarity(banner).legendary
