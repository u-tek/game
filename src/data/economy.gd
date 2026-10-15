class_name EconomyData
extends RefCounted
## Economy tuning, loaded from res://data/economy.json, banner.json, quests.json and
## offers.json (the source of truth; schemas in docs/dev/unity-port.md, pacing and formulas
## in docs/dev/economy-v1.md). The names below are the ones the code used when these were
## GDScript constants. Treat them as read-only. The formulas themselves live in the rule
## classes under src/core/ (Progression, IdleRules, GearRules); the functions here forward
## to them so existing callers keep working.

static var _eco: Dictionary = GameData.economy()

# ---------------------------------------------------------------- new game
static var STARTER_HEROES: Array[String] = GameData.strings(_eco.new_game.starter_heroes)
static var START_CURRENCIES: Dictionary = _eco.new_game.currencies
static var START_PLAYER_NAME: String = str(_eco.new_game.player_name)

# ---------------------------------------------------------------- heroes
static var START_STARS: Dictionary = _eco.heroes.start_stars
static var MAX_STARS: int = int(_eco.heroes.max_stars)
static var LEVEL_CAP_BASE: int = int(_eco.heroes.level_cap_base)
static var LEVEL_CAP_PER_STAR: int = int(_eco.heroes.level_cap_per_star)
## Level cost coefficients: see Progression.level_cost.
static var LEVEL_COST: Dictionary = _eco.heroes.level_cost
## Shards to go from N stars to N+1 (index = current stars).
static var STAR_SHARDS: Array[int] = GameData.ints(_eco.heroes.star_shards)
## Shards granted by a duplicate summon.
static var DUPE_SHARDS: Dictionary = _eco.heroes.dupe_shards
## Dust needed to replace one missing shard when starring up, by the hero's rarity.
static var DUST_PER_SHARD: Dictionary = _eco.heroes.dust_per_shard
## Dust granted per shard a maxed hero cannot use.
static var DUST_PER_EXCESS_SHARD: Dictionary = _eco.heroes.dust_per_excess_shard
## Stat growth: {level_growth_bp, star_growth_bp, spd_per_star, crit_cap_bp} (StatCalc).
static var STATS: Dictionary = _eco.stats

# ---------------------------------------------------------------- idle
static var IDLE_CAP_MS: int = int(_eco.idle.cap_ms)
static var QUICK_CLAIM_MS: int = int(_eco.idle.quick_claim_ms)
## Quick-claim prices by use index within the day (0 = the free one).
static var QUICK_CLAIM_COSTS: Array[int] = GameData.ints(_eco.idle.quick_claim_costs)
## Per-hour idle income: base + per_10_stages * stages cleared / 10 (rounded down).
static var IDLE_BASE: Dictionary = _eco.idle.base_per_hour
static var IDLE_PER_10_STAGES: Dictionary = _eco.idle.per_10_stages_per_hour
## One gear drop per this much idle time.
static var IDLE_GEAR_EVERY_MS: int = int(_eco.idle.gear_every_ms)
## A claim after at least this much idle time counts for the "collect idle rewards" quest.
static var IDLE_MIN_QUEST_CLAIM_MS: int = int(_eco.idle.min_claim_for_quest_ms)

# ---------------------------------------------------------------- summon
## The standard banner (first entry of banner.json).
static var BANNER: Dictionary = GameData.banner().banners[0]

# ---------------------------------------------------------------- gear
static var GEAR_SLOTS: Array[String] = GameData.strings(_eco.gear.slots)
static var GEAR_TIER_NAMES: Array[String] = GameData.strings(_eco.gear.tier_names)
static var GEAR_ITEM_NAMES: Dictionary = _eco.gear.item_names
## Per slot: [{stat, by_tier: [value at tier 0..5]}] (order matters: one roll per entry).
static var GEAR_STATS: Dictionary = _eco.gear.stats
static var GEAR_ROLL_MIN_PCT: int = int(_eco.gear.roll_min_pct)
static var GEAR_ROLL_MAX_PCT: int = int(_eco.gear.roll_max_pct)
static var GEAR_STAGES_PER_TIER: int = int(_eco.gear.stages_per_tier)
static var GEAR_MAX_TIER: int = int(_eco.gear.max_tier)
## Unequipped gear kept before the weakest pieces are salvaged automatically.
static var GEAR_BAG_LIMIT: int = int(_eco.gear.bag_limit)
static var SALVAGE_GOLD_PER_TIER: int = int(_eco.gear.salvage_gold_per_tier)
static var SALVAGE_DUST_PER_TIER: int = int(_eco.gear.salvage_dust_per_tier)

# ---------------------------------------------------------------- formation
## Auto-formation front-row preference by role (higher = more likely in front).
static var FRONT_PRIORITY: Dictionary = _eco.formation.front_priority

# ---------------------------------------------------------------- quests (daily)
## {id, title, counter, goal, reward}; counter: which Game counter drives the quest.
static var DAILY_QUESTS: Array[Dictionary] = GameData.dicts(GameData.quests().daily)
## Counter bumped when a daily quest is claimed (the meta quest's own claim doesn't count).
static var META_QUEST_COUNTER: String = str(GameData.quests().meta_counter)

# ---------------------------------------------------------------- shop
## limit: max purchases (0 = no limit). period: "once" (lifetime) or "day".
static var OFFERS: Array[Dictionary] = GameData.dicts(GameData.offers().offers)
static var MONTHLY_CARD_OFFER: String = str(GameData.offers().monthly_card.offer_id)
static var MONTHLY_CARD_DAYS: int = int(GameData.offers().monthly_card.days)
static var MONTHLY_CARD_DAILY_GEMS: int = int(GameData.offers().monthly_card.daily_gems)


# ---------------------------------------------------------------- formulas (forwarders)

## Cost of going from `level` to `level + 1`: {gold, hero_exp}.
static func level_cost(level: int) -> Dictionary:
	return Progression.level_cost(level)


static func level_cap(stars: int) -> int:
	return Progression.level_cap(stars)


## Shards needed for the next star, 0 at max.
static func star_shards(stars: int) -> int:
	return Progression.star_shards(stars)


## Total shards a hero at `stars` can still use until max stars.
static func shards_to_max(stars: int) -> int:
	return Progression.shards_to_max(stars)


## Idle income per hour for this many cleared stages.
static func idle_per_hour(cleared: int) -> Dictionary:
	return IdleRules.per_hour(cleared)


## Dust that replaces one missing shard of a hero of this rarity.
static func dust_per_shard(rarity: String) -> int:
	return Progression.dust_per_shard(rarity)


## Dust granted for one shard a maxed hero of this rarity cannot use.
static func dust_per_excess_shard(rarity: String) -> int:
	return Progression.dust_per_excess_shard(rarity)


## Gear tier that drops from idle / stages at this progress.
static func gear_tier_for(cleared: int) -> int:
	return GearRules.tier_for(cleared)
