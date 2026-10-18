class_name TowerData
extends RefCounted
## The Spire from res://data/tower.json: an endless climb beside the campaign. Floors are built
## from rules, not stored (port spec: docs/dev/unity-port.md section 9b):
##   ref    = min(f - 1, last stage index): floor f fights at the difficulty of campaign stage f
##   past   = max(0, f - stage count): floors beyond the campaign
##   level  = ref stage level + past * level_per_floor_past
##   stars  = min(ref stage stars + past / stars_every_past, max stars), never below a hero's start
##   echo   = echo_stat_bp * strength_bp / 10000 (one fixed strength for every floor)
##   team   = SeededRng(mix(seed, f)) picks distinct roster heroes in roster order; a boss floor
##            (f % boss_every == 0) puts bosses[(f / boss_every - 1) % 3] in slot 2 and four
##            picks around it; picks fill slots by front_priority[role] (higher first, then pick order)
##   rec    = ref stage recommended_power * rec_bp / 10000, past the campaign
##            * (10000 + rec_past_bp * past) / 10000
##
## Built Floor (stage-shaped, so the battle screens read it like a stage): {floor, index (f - 1),
##   id "F12", name, enemies [{hero_id, level, stars, slot, is_boss, echo_bp}], is_boss,
##   background, enemy_faction, recommended_power, enemy_power, first_clear_reward, hint}

static var _d: Dictionary = GameData.tower()
static var UNLOCK_CLEARED: int = int(_d.unlock_cleared)
static var FLOORS: int = int(_d.floors)
static var NAME: String = str(_d.name)
static var _cache: Dictionary = {}


static func get_floor(f: int) -> Dictionary:
	if f < 1 or f > FLOORS:
		return {}
	if not _cache.has(f):
		_cache[f] = _build(f)
	return _cache[f]


static func _build(f: int) -> Dictionary:
	var n := StageData.count()
	var ref := mini(f - 1, n - 1)
	var raw := StageData.raw_stage(ref)
	var past := maxi(0, f - n)
	var level := int(raw.level) + past * int(_d.level_per_floor_past)
	var stars := mini(int(raw.stars) + past / int(_d.stars_every_past), EconomyData.MAX_STARS)
	var echo_bp: int = StageData.ECHO_STAT_BP * int(_d.strength_bp) / 10000
	var is_boss := f % int(_d.boss_every) == 0
	var bosses: Array = _d.bosses
	var boss_id := str(bosses[(f / int(_d.boss_every) - 1) % bosses.size()]) if is_boss else ""
	var pool: Array = []
	for id in HeroData.ids():
		if id != boss_id:
			pool.append(id)
	var rng := SeededRng.new(SeededRng.mix(int(_d.seed), f))
	var picks: Array = []
	while picks.size() < (4 if is_boss else 5):
		var i := rng.range_int(0, pool.size() - 1)
		picks.append(pool[i])
		pool.remove_at(i)
	# Front-liners first: higher front_priority, then pick order (a stable sort by hand).
	var order: Array = []
	for i in picks.size():
		order.append([int(EconomyData.FRONT_PRIORITY.get(str(HeroData.get_def(picks[i]).role), 0)), i])
	order.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0] if a[0] != b[0] else a[1] < b[1])
	var slots: Array = [0, 1, 3, 4] if is_boss else [0, 1, 2, 3, 4]
	var enemies: Array = []
	for k in order.size():
		enemies.append(_enemy(str(picks[int(order[k][1])]), int(slots[k]), level, stars, echo_bp, false))
	if is_boss:
		enemies.append(_enemy(boss_id, 2, level, stars, echo_bp, true))
	enemies.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.slot) < int(b.slot))
	var bgs: Array = _d.backgrounds
	var fl := {
		"floor": f,
		"index": f - 1,
		"id": "F%d" % f,
		"name": "%s, floor %d" % [NAME, f],
		"enemies": enemies,
		"is_boss": is_boss,
		"background": str(bgs[((f - 1) / int(_d.floors_per_background)) % bgs.size()]),
		"recommended_power": recommended_power(f),
		"enemy_power": StageData.enemy_power(enemies),
		"first_clear_reward": reward(f),
		"hint": "",
	}
	fl["enemy_faction"] = _main_faction(enemies)
	return fl


static func _enemy(hid: String, slot: int, level: int, stars: int, echo_bp: int, boss: bool) -> Dictionary:
	var rarity: String = HeroData.get_def(hid).get("rarity", "rare")
	return {"hero_id": hid, "level": level, "stars": maxi(stars, Progression.start_stars(rarity)), "slot": slot,
		"is_boss": boss, "echo_bp": echo_bp}


static func _main_faction(enemies: Array) -> String:
	var counts := {}
	for e in enemies:
		var fac := str(HeroData.get_def(e.hero_id).faction)
		counts[fac] = int(counts.get(fac, 0)) + 1
	var best := ""
	var best_n := 0
	for fac in ["celestial", "infernal", "fallen"]:
		if int(counts.get(fac, 0)) > best_n:
			best_n = int(counts.get(fac, 0))
			best = fac
	return best


static func recommended_power(f: int) -> int:
	var n := StageData.count()
	var past := maxi(0, f - n)
	var rec := StageData.recommended_power(mini(f - 1, n - 1)) * int(_d.rec_bp) / 10000
	return rec * (10000 + int(_d.rec_past_bp) * past) / 10000


## First-clear reward of floor f: gold, hero EXP and dust every floor; gems every gems_every
## floors; a boss floor adds gems, a scroll and one gear item (tier 1 + f / gear_tier_every, max 5).
static func reward(f: int) -> Dictionary:
	var r: Dictionary = _d.rewards
	var gold: int = int(r.gold_base) + int(r.gold_per_floor) * f
	var out := {"gold": gold, "hero_exp": gold * int(r.hero_exp_bp) / 10000,
		"dust": int(r.dust_base) + f / int(r.dust_every)}
	var gems := 0
	if f % int(r.gems_every) == 0:
		gems += int(r.gems)
	if f % int(_d.boss_every) == 0:
		gems += int(r.boss_gems)
		out["scrolls"] = int(r.boss_scrolls)
		var gs: Array = r.gear_slots
		out["gear_drops"] = [{"slot": str(gs[(f / int(_d.boss_every) - 1) % gs.size()]),
			"tier": clampi(1 + f / int(r.gear_tier_every), 1, EconomyData.GEAR_MAX_TIER)}]
	if gems > 0:
		out["gems"] = gems
	return out
