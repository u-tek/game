class_name StatCalc
## Hero stat and power formulas shared by Game (owned heroes), stage enemies (echoes)
## and tests. Pure functions, ints only.
##
##   stat = (base * level_mult * star_mult + gear) * (1 + passive stat bonus)
##   level_mult = 1 + 7% per level above 1, star_mult = 1 + 12% per star above 1
##   spd and crit do not scale with level; stars add +1 spd each.

const LEVEL_GROWTH_BP := 700
const STAR_GROWTH_BP := 1200
const CRIT_CAP_BP := 7500
const SCALED := ["hp", "atk", "def"]


static func level_mult_bp(level: int) -> int:
	return 10000 + (maxi(level, 1) - 1) * LEVEL_GROWTH_BP


static func star_mult_bp(stars: int) -> int:
	return 10000 + (maxi(stars, 1) - 1) * STAR_GROWTH_BP


## Sum of flat stats from gear items (Array of GearItem dictionaries).
static func gear_totals(items: Array) -> Dictionary:
	var out := {"hp": 0, "atk": 0, "def": 0, "spd": 0, "crit": 0}
	for it in items:
		var st: Dictionary = it.get("stats", {})
		for k in st:
			out[k] = int(out.get(k, 0)) + int(st[k])
	return out


## Final stats {hp, atk, def, spd, crit} for a hero at this level/stars with this gear.
static func stats(hero_id: String, level: int, stars: int, gear: Array = []) -> Dictionary:
	var kit := HeroKits.get_kit(hero_id)
	if kit.is_empty():
		return {"hp": 0, "atk": 0, "def": 0, "spd": 100, "crit": 0}
	var base: Dictionary = kit.base_stats
	var lm := level_mult_bp(level)
	var sm := star_mult_bp(stars)
	var g := gear_totals(gear)
	var bonus := {"hp_bp": 0, "atk_bp": 0, "def_bp": 0, "spd_bp": 0, "crit_bp": 0}
	for e in HeroKits.passive_effects(hero_id, stars, "stat"):
		for k in bonus:
			bonus[k] = int(bonus[k]) + int(e.get(k, 0))
	var out := {}
	for k in SCALED:
		var v: int = int(base[k]) * lm / 10000 * sm / 10000 + int(g[k])
		out[k] = v * (10000 + int(bonus[k + "_bp"])) / 10000
	var spd: int = int(base.spd) + (maxi(stars, 1) - 1) + int(g.spd)
	out["spd"] = spd * (10000 + int(bonus.spd_bp)) / 10000
	out["crit"] = mini(int(base.crit) + int(g.crit) + int(bonus.crit_bp), CRIT_CAP_BP)
	return out


## Combat power shown to the player. Roughly "damage per second times survivability".
static func power(st: Dictionary) -> int:
	var hp: int = int(st.get("hp", 0))
	var atk: int = int(st.get("atk", 0))
	var def: int = int(st.get("def", 0))
	var spd: int = int(st.get("spd", 100))
	var crit: int = int(st.get("crit", 0))
	var raw: int = hp + atk * 7 + def * 5
	return raw * spd / 100 * (20000 + crit) / 20000 / 5


## Power-equivalent score of one gear item (for auto-equip comparisons).
static func gear_score(item: Dictionary) -> int:
	var st: Dictionary = item.get("stats", {})
	return int(st.get("hp", 0)) + int(st.get("atk", 0)) * 7 + int(st.get("def", 0)) * 5 \
		+ int(st.get("spd", 0)) * 12 + int(st.get("crit", 0)) / 8
