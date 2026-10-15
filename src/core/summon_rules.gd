class_name SummonRules
extends RefCounted
## Gacha rules: rarity rolls, Legendary pity, the 10-pull guarantee and hero picks.
## Pure functions; the banner comes from data/banner.json (EconomyData.BANNER), hero rarities
## from data/heroes.json. Golden fixture: data/fixtures/summon.json.
##
## One summon of `count` pulls (1 or 10) with the save's summon state {seed, total_pulls, pity}:
##   rng = SeededRng(SeededRng.mix(seed, total_pulls))      (total_pulls before this summon)
##   for i in 0..count-1:
##     rarity = "legendary" if pity >= pity_legendary - 1
##              else r = rng.range_int(0, 9999): r < legendary_bp -> legendary,
##                   r < legendary_bp + epic_bp -> epic, else rare
##     if count == 10 and i == 9 and no epic/legendary yet in this summon and rarity == rare: epic
##     pity = 0 if legendary else pity + 1;  total_pulls += 1
##     hero_id = rng.pick(pool_by_rarity[rarity])
## The pity check uses no random draw, so a forced Legendary skips the range_int call.


## Banner pool grouped by rarity, in pool order: {rare: [ids], epic: [ids], legendary: [ids]}.
static func pool_by_rarity(banner: Dictionary) -> Dictionary:
	var out := {"rare": [], "epic": [], "legendary": []}
	for id in banner.get("pool", []):
		var d := HeroData.get_def(str(id))
		if not d.is_empty() and out.has(d.rarity):
			out[d.rarity].append(str(id))
	return out


static func roll_rarity(rng: SeededRng, pity: int, banner: Dictionary) -> String:
	if pity >= int(banner.pity_legendary) - 1:
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


## Rolls `count` pulls. Returns {results: [{hero_id, rarity, pity (after this pull)}],
## pity, total_pulls} (the new summon state).
static func pull(banner: Dictionary, seed_value: int, total_pulls: int, pity: int, count: int) -> Dictionary:
	var pool := pool_by_rarity(banner)
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
		p = 0 if rarity == "legendary" else p + 1
		total += 1
		var hid: String = rng.pick(pool[rarity])
		results.append({"hero_id": hid, "rarity": rarity, "pity": p})
	return {"results": results, "pity": p, "total_pulls": total}
