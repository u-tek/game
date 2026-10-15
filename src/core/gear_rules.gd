class_name GearRules
extends RefCounted
## Gear rules: drop tiers, item creation, random drop slots, salvage, comparison score.
## Pure functions on ints; numbers from data/economy.json ("gear") via EconomyData. Every
## random choice uses SeededRng streams derived from the save's rng_seed and gear_seq, so a
## save always produces the same items. Golden fixture: data/fixtures/gear.json.


## Tier that drops from idle / stages after `cleared` stages: 1 + cleared / stages_per_tier,
## clamped to 1..max_tier.
static func tier_for(cleared: int) -> int:
	return clampi(1 + cleared / EconomyData.GEAR_STAGES_PER_TIER, 1, EconomyData.GEAR_MAX_TIER)


## Slot of a random (idle) drop: SeededRng(mix(rng_seed + 31, gear_seq * 13 + 5)).pick(slots).
static func random_slot(rng_seed: int, gear_seq: int) -> String:
	var rng := SeededRng.new(SeededRng.mix(rng_seed + 31, gear_seq * 13 + 5))
	return rng.pick(EconomyData.GEAR_SLOTS)


## The item with sequence number `seq` (uid "g<seq>"): an unknown slot becomes "weapon" and
## the tier is clamped to 1..max_tier. rng = SeededRng(mix(rng_seed, seq)); for each stat of
## the slot (data order): value = max(1, by_tier[tier] * rng.range_int(roll_min, roll_max) / 100);
## then the name noun = rng.pick(item_names[slot]); name = "<tier name> <noun>".
static func make_item(slot: String, tier: int, rng_seed: int, seq: int) -> Dictionary:
	var t := clampi(tier, 1, EconomyData.GEAR_MAX_TIER)
	var s := slot if EconomyData.GEAR_SLOTS.has(slot) else "weapon"
	var rng := SeededRng.new(SeededRng.mix(rng_seed, seq))
	var stats := {}
	for entry in EconomyData.GEAR_STATS[s]:
		var base: int = int(entry.by_tier[t])
		stats[str(entry.stat)] = maxi(1, base * rng.range_int(EconomyData.GEAR_ROLL_MIN_PCT, EconomyData.GEAR_ROLL_MAX_PCT) / 100)
	var noun: String = rng.pick(EconomyData.GEAR_ITEM_NAMES[s])
	return {
		"uid": "g%d" % seq,
		"slot": s,
		"tier": t,
		"name": "%s %s" % [EconomyData.GEAR_TIER_NAMES[t], noun],
		"stats": stats,
		"equipped_by": "",
	}


## Gold and dust for salvaging an item of this tier.
static func salvage_value(tier: int) -> Dictionary:
	return {"gold": EconomyData.SALVAGE_GOLD_PER_TIER * tier, "dust": EconomyData.SALVAGE_DUST_PER_TIER * tier}


## Power-equivalent score of one item (auto-equip comparisons). See StatCalc.gear_score.
static func score(item: Dictionary) -> int:
	return StatCalc.gear_score(item)
