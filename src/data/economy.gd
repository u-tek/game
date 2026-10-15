class_name EconomyData
## Economy tuning (v1). Every number the rules use lives here; formulas and pacing are
## documented in docs/dev/economy-v1.md. Owned by core logic.

# ---------------------------------------------------------------- new game
const STARTER_HEROES: Array[String] = ["uriela", "lucen", "kessa"]
const START_CURRENCIES := {"gold": 4000, "hero_exp": 2400, "gems": 1800, "scrolls": 10, "dust": 0}

# ---------------------------------------------------------------- heroes
const START_STARS := {"rare": 1, "epic": 2, "legendary": 3}
const MAX_STARS := 6
const LEVEL_CAP_BASE := 20
const LEVEL_CAP_PER_STAR := 20

## Shards to go from N stars to N+1 (index = current stars).
const STAR_SHARDS: Array[int] = [0, 10, 20, 40, 60, 100]
## Shards granted by a duplicate summon.
const DUPE_SHARDS := {"rare": 10, "epic": 20, "legendary": 40}
## Dust needed to replace one missing shard when starring up, by the hero's rarity. A worse
## rate than duplicates: dust smooths out bad luck but never replaces summoning.
const DUST_PER_SHARD := {"rare": 10, "epic": 25, "legendary": 60}
## Dust granted per shard a maxed hero cannot use (40% of the price above).
const DUST_PER_EXCESS_SHARD := {"rare": 4, "epic": 10, "legendary": 24}

# ---------------------------------------------------------------- idle
const IDLE_CAP_MS := 12 * 3600 * 1000
const QUICK_CLAIM_MS := 2 * 3600 * 1000
## Quick-claim prices by use index within the day (0 = the free one).
const QUICK_CLAIM_COSTS: Array[int] = [0, 50, 100, 150]
## Per-hour idle income: base + per_10_stages * stages cleared / 10 (rounded down).
const IDLE_BASE := {"gold": 600, "hero_exp": 400, "dust": 3, "gems": 3}
const IDLE_PER_10_STAGES := {"gold": 1100, "hero_exp": 750, "dust": 5, "gems": 2}
## One gear drop per this much idle time.
const IDLE_GEAR_EVERY_MS := 3 * 3600 * 1000

# ---------------------------------------------------------------- summon
const BANNER := {
	"id": "standard",
	"name": "Choir of the Fallen Sky",
	"cost_one": {"gems": 300, "scrolls": 1},
	"cost_ten": {"gems": 2700, "scrolls": 10},
	"rates": {"legendary": 200, "epic": 1800, "rare": 8000},
	"pity_legendary": 60,
	"ten_pull_guarantee": "epic",
}

# ---------------------------------------------------------------- gear
const GEAR_SLOTS: Array[String] = ["weapon", "armor", "helm", "charm"]
const GEAR_TIER_NAMES: Array[String] = ["", "Worn", "Tempered", "Gilded", "Hallowed", "Eclipse"]
const GEAR_ITEM_NAMES := {
	"weapon": ["Blade", "Spear", "Sceptre", "Glaive"],
	"armor": ["Cuirass", "Vestments", "Mail"],
	"helm": ["Circlet", "Helm", "Crown"],
	"charm": ["Rosary", "Locket", "Reliquary"],
}
## Flat stats per slot at each tier (index = tier).
const GEAR_STATS := {
	"weapon": {"atk": [0, 16, 32, 56, 90, 140]},
	"armor": {"hp": [0, 270, 530, 910, 1440, 2190], "def": [0, 8, 16, 28, 44, 66]},
	"helm": {"hp": [0, 210, 420, 720, 1140, 1710], "def": [0, 6, 12, 20, 32, 48]},
	"charm": {"crit": [0, 300, 500, 800, 1100, 1500], "spd": [0, 3, 5, 8, 11, 15], "atk": [0, 6, 12, 22, 34, 52]},
}
## Unequipped gear kept before the weakest pieces are salvaged automatically.
const GEAR_BAG_LIMIT := 40
const SALVAGE_GOLD_PER_TIER := 400
const SALVAGE_DUST_PER_TIER := 3

# ---------------------------------------------------------------- quests (daily)
## counter: which Game counter drives the quest.
const DAILY_QUESTS: Array[Dictionary] = [
	{"id": "dq_idle", "title": "Collect idle rewards twice", "counter": "idle_claims", "goal": 2,
		"reward": {"gems": 40, "gold": 3000}},
	{"id": "dq_win", "title": "Win 3 battles", "counter": "battles_won", "goal": 3,
		"reward": {"gems": 60, "hero_exp": 1500}},
	{"id": "dq_summon", "title": "Summon a hero", "counter": "summons", "goal": 1,
		"reward": {"gems": 50}},
	{"id": "dq_level", "title": "Level up heroes 5 times", "counter": "level_ups", "goal": 5,
		"reward": {"gold": 5000, "hero_exp": 2000}},
	{"id": "dq_quick", "title": "Use a Quick Claim", "counter": "quick_claims", "goal": 1,
		"reward": {"gems": 40}},
	{"id": "dq_all", "title": "Complete 5 daily quests", "counter": "daily_quests_done", "goal": 5,
		"reward": {"gems": 100, "scrolls": 1}},
]

# ---------------------------------------------------------------- shop
## limit: max purchases (0 = no limit). period: "once" (lifetime) or "day".
const OFFERS: Array[Dictionary] = [
	{"id": "daily_gift", "name": "Daily Blessing", "tag": "free",
		"description": "A small gift from the Choir, every day.",
		"price_label": "Free", "reward": {"gems": 30, "gold": 2000}, "limit": 1, "period": "day"},
	{"id": "starter_pack", "name": "Envoy's Starter Pack", "tag": "best value",
		"description": "Everything a new envoy needs: gems, scrolls and supplies. Once per account.",
		"price_label": "$0.99", "reward": {"gems": 1200, "scrolls": 10, "gold": 50000, "hero_exp": 30000},
		"limit": 1, "period": "once"},
	{"id": "monthly_card", "name": "Moonlit Pass", "tag": "monthly",
		"description": "300 gems now, then 100 more on each day you log in, for 30 days.",
		"price_label": "$4.99", "reward": {"gems": 300}, "limit": 0, "period": "once"},
	{"id": "scroll_bundle", "name": "Summoner's Satchel", "tag": "limited",
		"description": "10 summon scrolls and 300 dust. Limit 3.",
		"price_label": "$9.99", "reward": {"scrolls": 10, "dust": 300}, "limit": 3, "period": "once"},
	{"id": "gems_s", "name": "Pouch of Gems", "tag": "",
		"description": "330 gems.",
		"price_label": "$4.99", "reward": {"gems": 330}, "limit": 0, "period": "once"},
	{"id": "gems_m", "name": "Chest of Gems", "tag": "popular",
		"description": "1,100 gems.",
		"price_label": "$14.99", "reward": {"gems": 1100}, "limit": 0, "period": "once"},
	{"id": "gems_l", "name": "Reliquary of Gems", "tag": "",
		"description": "3,880 gems.",
		"price_label": "$49.99", "reward": {"gems": 3880}, "limit": 0, "period": "once"},
]
const MONTHLY_CARD_DAYS := 30
const MONTHLY_CARD_DAILY_GEMS := 100


# ---------------------------------------------------------------- formulas

## Cost of going from `level` to `level + 1`.
static func level_cost(level: int) -> Dictionary:
	var exp_cost := 20 + 10 * level + level * level
	var gold_cost := exp_cost + exp_cost / 4 + 10 * level
	return {"gold": gold_cost, "hero_exp": exp_cost}


static func level_cap(stars: int) -> int:
	return LEVEL_CAP_BASE + LEVEL_CAP_PER_STAR * clampi(stars, 1, MAX_STARS)


## Shards needed for the next star, 0 at max.
static func star_shards(stars: int) -> int:
	if stars < 1 or stars >= MAX_STARS:
		return 0
	return STAR_SHARDS[stars]


## Total shards a hero at `stars` can still use until max stars.
static func shards_to_max(stars: int) -> int:
	var total := 0
	for s in range(maxi(stars, 1), MAX_STARS):
		total += STAR_SHARDS[s]
	return total


## Idle income per hour for this many cleared stages.
static func idle_per_hour(cleared: int) -> Dictionary:
	var out := {}
	var c := maxi(cleared, 0)
	for k in IDLE_BASE:
		out[k] = int(IDLE_BASE[k]) + int(IDLE_PER_10_STAGES[k]) * c / 10
	return out


## Dust that replaces one missing shard of a hero of this rarity.
static func dust_per_shard(rarity: String) -> int:
	return int(DUST_PER_SHARD.get(rarity, DUST_PER_SHARD.rare))


## Dust granted for one shard a maxed hero of this rarity cannot use.
static func dust_per_excess_shard(rarity: String) -> int:
	return int(DUST_PER_EXCESS_SHARD.get(rarity, DUST_PER_EXCESS_SHARD.rare))


## Gear tier that drops from idle / stages at this progress.
static func gear_tier_for(cleared: int) -> int:
	return clampi(1 + cleared / 7, 1, 5)
