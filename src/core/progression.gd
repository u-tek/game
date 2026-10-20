class_name Progression
extends RefCounted
## Hero progression rules: level costs and caps, star-up costs, shards and dust.
## Pure functions on ints (no engine services, no state); numbers from data/economy.json
## ("heroes" section) via EconomyData. Golden fixture: data/fixtures/progression.json.


## Cost of going from `level` to `level + 1`:
##   hero_exp = exp_base + exp_per_level * L + exp_per_level_squared * L * L
##   gold     = hero_exp + hero_exp / gold_exp_divisor + gold_per_level * L   (integer division)
static func level_cost(level: int) -> Dictionary:
	var c: Dictionary = EconomyData.LEVEL_COST
	var lv := level
	var exp_cost: int = int(c.exp_base) + int(c.exp_per_level) * lv + int(c.exp_per_level_squared) * lv * lv
	var gold_cost: int = exp_cost + exp_cost / int(c.gold_exp_divisor) + int(c.gold_per_level) * lv
	return {"gold": gold_cost, "hero_exp": exp_cost}


## Level cap at this many stars: level_cap_base + level_cap_per_star * stars (stars clamped 1..max).
static func level_cap(stars: int) -> int:
	return EconomyData.LEVEL_CAP_BASE + EconomyData.LEVEL_CAP_PER_STAR * clampi(stars, 1, EconomyData.MAX_STARS)


## Stars a newly obtained hero of this rarity starts with.
static func start_stars(rarity: String) -> int:
	return int(EconomyData.START_STARS.get(rarity, 1))


## Shards needed for the next star, 0 at max (or below 1 star).
static func star_shards(stars: int) -> int:
	if stars < 1 or stars >= EconomyData.MAX_STARS:
		return 0
	return EconomyData.STAR_SHARDS[stars]


## Total shards a hero at `stars` can still use until max stars.
static func shards_to_max(stars: int) -> int:
	var total := 0
	for s in range(maxi(stars, 1), EconomyData.MAX_STARS):
		total += EconomyData.STAR_SHARDS[s]
	return total


## Dust that replaces one missing shard of a hero of this rarity (unknown rarity: as rare).
static func dust_per_shard(rarity: String) -> int:
	return int(EconomyData.DUST_PER_SHARD.get(rarity, EconomyData.DUST_PER_SHARD.rare))


## Dust granted for one shard a maxed hero of this rarity cannot use.
static func dust_per_excess_shard(rarity: String) -> int:
	return int(EconomyData.DUST_PER_EXCESS_SHARD.get(rarity, EconomyData.DUST_PER_EXCESS_SHARD.rare))


## Shards a duplicate of this rarity grants.
static func dupe_shards(rarity: String) -> int:
	return int(EconomyData.DUPE_SHARDS.get(rarity, EconomyData.DUPE_SHARDS.rare))


## Next star's cost for a hero at `stars` holding `shards_have` shards, or {} at max stars:
## {shards (needed in total), dust (covers the missing shards), shards_have, shards_used,
##  dust_per_shard}.
static func star_up_cost(stars: int, shards_have: int, rarity: String) -> Dictionary:
	var need := star_shards(stars)
	if need <= 0:
		return {}
	var missing := maxi(0, need - shards_have)
	var per := dust_per_shard(rarity)
	return {"shards": need, "dust": missing * per, "shards_have": shards_have,
		"shards_used": mini(shards_have, need), "dust_per_shard": per}


## Adding `n` shards to a hero at `stars` (and awakening tier `awaken`) holding `shards_have`:
## shards beyond what the hero can still use (star-ups, then a Legendary's awakenings) become dust.
## Returns {shards (new total), dust (granted)}.
static func add_shards(stars: int, shards_have: int, n: int, rarity: String, awaken: int = 0) -> Dictionary:
	var usable := maxi(0, shards_usable(stars, awaken, rarity) - shards_have)
	var keep := mini(n, usable)
	return {"shards": shards_have + keep, "dust": (n - keep) * dust_per_excess_shard(rarity)}


# ---------------------------------------------------------------- awakening (Legendaries)
## After max stars a Legendary can awaken AWAKEN_SHARDS.size() times (A1-A3). Each tier costs her
## own shards plus dust (missing shards are covered by dust at dust_per_shard, like star-ups) and
## gives every stat a bonus (StatCalc); A1 unlocks her legend passive, A2 her empowered ultimate
## (HeroKits.active_passives), A3 her Ascended title (cosmetic).

## True when heroes of this rarity can awaken.
static func can_awaken_rarity(rarity: String) -> bool:
	return EconomyData.AWAKEN_RARITIES.has(rarity)


## Highest awakening tier for this rarity (0 = cannot awaken).
static func max_awaken(rarity: String) -> int:
	return EconomyData.AWAKEN_SHARDS.size() if can_awaken_rarity(rarity) else 0


## Shards a hero at awakening tier `awaken` can still use for awakenings.
static func awaken_shards_left(awaken: int, rarity: String) -> int:
	var total := 0
	for t in range(clampi(awaken, 0, max_awaken(rarity)), max_awaken(rarity)):
		total += EconomyData.AWAKEN_SHARDS[t]
	return total


## Every shard a hero can still use: star-ups to max stars, then awakenings.
static func shards_usable(stars: int, awaken: int, rarity: String) -> int:
	return shards_to_max(stars) + awaken_shards_left(awaken, rarity)


## The next awakening for a hero at `stars` and tier `awaken` holding `shards_have`, or {} when her
## rarity cannot awaken or she is fully awakened: {tier (the one it reaches), shards (needed),
## dust (base + missing shards * dust_per_shard), dust_base, shards_have, shards_used,
## dust_per_shard, min_stars, stars_ok}.
static func awaken_cost(stars: int, awaken: int, shards_have: int, rarity: String) -> Dictionary:
	if awaken < 0 or awaken >= max_awaken(rarity):
		return {}
	var need: int = EconomyData.AWAKEN_SHARDS[awaken]
	var base: int = EconomyData.AWAKEN_DUST[awaken]
	var per := dust_per_shard(rarity)
	var missing := maxi(0, need - shards_have)
	return {"tier": awaken + 1, "shards": need, "dust": base + missing * per, "dust_base": base,
		"shards_have": shards_have, "shards_used": mini(shards_have, need), "dust_per_shard": per,
		"min_stars": EconomyData.AWAKEN_MIN_STARS, "stars_ok": stars >= EconomyData.AWAKEN_MIN_STARS}


## Total stat bonus (basis points, on every stat) at awakening tier `awaken` (0 below A1).
static func awaken_stat_bp(awaken: int) -> int:
	if awaken <= 0 or EconomyData.AWAKEN_STAT_BP.is_empty():
		return 0
	return EconomyData.AWAKEN_STAT_BP[mini(awaken, EconomyData.AWAKEN_STAT_BP.size()) - 1]


## Most levels affordable from `level` (stopping at `cap`) with this gold and hero EXP.
static func affordable_levels(level: int, cap: int, gold: int, hero_exp: int) -> int:
	var n := 0
	var g := gold
	var x := hero_exp
	while level + n < cap:
		var c := level_cost(level + n)
		if g < int(c.gold) or x < int(c.hero_exp):
			break
		g -= int(c.gold)
		x -= int(c.hero_exp)
		n += 1
	return n
