class_name StageData
## Campaign: 3 chapters x 10 stages. Enemies are "echoes" of roster heroes. Stages 5 and
## 10 of every chapter are boss stages. Owned by core logic; tuned with
## tests/balance_report.gd (see docs/dev/economy-v1.md).
##
## Stage: {index, id "1-5", chapter (0-based chapter index), name, enemies [{hero_id, level,
##   stars, slot, is_boss}], recommended_power, first_clear_reward, is_boss, background,
##   enemy_faction, hint}
## Chapter: {index, id, name, intro, background, first_stage, stage_count}

const CHAPTERS: Array[Dictionary] = [
	{
		"id": "ch1", "name": "Shattered Sanctum", "background": "chapter-1", "faction": "celestial",
		"intro": "The cathedral of the sky lies broken, and its wardens still patrol the ruins as echoes: hollow light that remembers only its orders. Climb the shattered nave and quiet the choir that will not stop singing.",
	},
	{
		"id": "ch2", "name": "Ember Wastes", "background": "chapter-2", "faction": "infernal",
		"intro": "Beyond the cathedral the land still burns from the last war. Furnace-echoes march under a queen's banner, certain the war never ended. Cross the cinder fields and remind them that it did.",
	},
	{
		"id": "ch3", "name": "Twilight Abyss", "background": "chapter-3", "faction": "fallen",
		"intro": "Between Heaven and Hell lies a dusk that never ends. The Fallen made their home here, and their echoes guard every broken oath. At the bottom waits the reaper who refused her final order.",
	},
]

## Per stage: name, default enemy level and stars, enemies [hero_id, slot, opts...].
## Enemy opts: "boss" marks the boss; {"lv": +n, "st": n} adjust level / stars.
const STAGES: Array[Dictionary] = [
	# ---------------- Chapter 1: Shattered Sanctum (celestial echoes)
	{"name": "Broken Narthex", "lv": 1, "st": 1, "e": [["uriela", 0], ["nuriel", 2]]},
	{"name": "Hall of Fallen Bells", "lv": 2, "st": 1, "e": [["uriela", 0], ["uriela", 1], ["nuriel", 3]]},
	{"name": "Glass Garden", "lv": 3, "st": 1, "e": [["uriela", 0], ["liora", 2], ["nuriel", 3]]},
	{"name": "Pillar Walk", "lv": 5, "st": 1, "e": [["uriela", 0], ["uriela", 1], ["nuriel", 2], ["liora", 3]]},
	{"name": "The Gate Warden", "lv": 6, "st": 1, "boss": true, "e": [["cassiel", 0, "boss"], ["uriela", 1], ["nuriel", 2], ["liora", 3]]},
	{"name": "Ashen Cloister", "lv": 8, "st": 1, "e": [["cassiel", 0], ["uriela", 1], ["nuriel", 2], ["liora", 3], ["ashra", 4]]},
	{"name": "Reliquary Stair", "lv": 9, "st": 2, "e": [["uriela", 0], ["cassiel", 1], ["nuriel", 2], ["kessa", 3], ["liora", 4]]},
	{"name": "Choir Loft", "lv": 10, "st": 2, "e": [["cassiel", 0], ["uriela", 1], ["liora", 2], ["nuriel", 3], ["imra", 4]]},
	{"name": "Bell Tower Ruin", "lv": 12, "st": 2, "e": [["cassiel", 0], ["uriela", 1], ["nuriel", 2], ["liora", 3], ["vesper", 4]]},
	{"name": "The Choir Unsung", "lv": 13, "st": 2, "boss": true, "e": [["cassiel", 0], ["uriela", 1], ["seraphiel", 2, "boss"], ["liora", 3], ["nuriel", 4]]},
	# ---------------- Chapter 2: Ember Wastes (infernal echoes)
	{"name": "Cinder Road", "lv": 15, "st": 2, "e": [["brakka", 0], ["kessa", 1], ["imra", 2], ["vesper", 3], ["kessa", 4]]},
	{"name": "Sulfur Springs", "lv": 16, "st": 2, "e": [["brakka", 0], ["mordessa", 1, {"st": 2}], ["imra", 2], ["kessa", 3], ["vesper", 4]]},
	{"name": "Molten Ford", "lv": 18, "st": 2, "e": [["brakka", 0], ["kessa", 1], ["vesper", 2], ["imra", 3], ["ashra", 4]]},
	{"name": "Chainworks", "lv": 19, "st": 2, "e": [["brakka", 0], ["orrin", 1], ["vesper", 2], ["kessa", 3], ["imra", 4]]},
	{"name": "Brimstone Bulwark", "lv": 21, "st": 2, "boss": true, "e": [["brakka", 0, "boss"], ["kessa", 1], ["vesper", 2], ["imra", 3], ["kessa", 4]]},
	{"name": "Ashfall Market", "lv": 22, "st": 3, "e": [["brakka", 0], ["uriela", 1], ["vesper", 2], ["imra", 3], ["kessa", 4]]},
	{"name": "Lantern Bazaar", "lv": 24, "st": 3, "e": [["brakka", 0], ["kessa", 1], ["imra", 2], ["vesper", 3], ["liora", 4]]},
	{"name": "Obsidian Steps", "lv": 25, "st": 3, "e": [["brakka", 0], ["cassiel", 1], ["vesper", 2], ["kessa", 3], ["imra", 4]]},
	{"name": "Furnace Gate", "lv": 27, "st": 3, "e": [["brakka", 0], ["mordessa", 1], ["vesper", 2], ["imra", 3], ["kessa", 4]]},
	{"name": "Throne of the Ninth Furnace", "lv": 29, "st": 3, "boss": true, "e": [["brakka", 0], ["kessa", 1], ["mordessa", 2, "boss"], ["vesper", 3], ["imra", 4]]},
	# ---------------- Chapter 3: Twilight Abyss (fallen echoes)
	{"name": "Dusk Shore", "lv": 31, "st": 3, "e": [["orrin", 0], ["lucen", 1], ["ashra", 2], ["sable", 3], ["lucen", 4]]},
	{"name": "Chapel of Ghosts", "lv": 33, "st": 3, "e": [["orrin", 0], ["lucen", 1], ["sable", 2], ["ashra", 3], ["noctaire", 4, {"st": 3}]]},
	{"name": "Broken Oath Bridge", "lv": 34, "st": 3, "e": [["orrin", 0], ["brakka", 1], ["ashra", 2], ["sable", 3], ["lucen", 4]]},
	{"name": "Hollow Choir", "lv": 36, "st": 3, "e": [["orrin", 0], ["lucen", 1], ["seraphiel", 2], ["sable", 3], ["ashra", 4]]},
	{"name": "The Chained Gate", "lv": 38, "st": 3, "boss": true, "e": [["orrin", 0, "boss"], ["lucen", 1], ["ashra", 2], ["sable", 3], ["noctaire", 4]]},
	{"name": "Ash Witch's Hollow", "lv": 40, "st": 4, "e": [["orrin", 0], ["lucen", 1], ["ashra", 2], ["ashra", 3], ["sable", 4]]},
	{"name": "Mirror Lake", "lv": 42, "st": 4, "e": [["orrin", 0], ["cassiel", 1], ["lucen", 2], ["sable", 3], ["noctaire", 4]]},
	{"name": "Feather Graveyard", "lv": 44, "st": 4, "e": [["orrin", 0], ["lucen", 1], ["vesper", 2], ["sable", 3], ["noctaire", 4]]},
	{"name": "Eclipse Stair", "lv": 46, "st": 4, "e": [["orrin", 0], ["mordessa", 1], ["ashra", 2], ["sable", 3], ["noctaire", 4]]},
	{"name": "The Last Order", "lv": 48, "st": 4, "boss": true, "e": [["orrin", 0], ["lucen", 1], ["noctaire", 2, "boss"], ["sable", 3], ["ashra", 4]]},
]

const STAGES_PER_CHAPTER := 10
## recommended_power = enemy power (boss multipliers included) * this / 10000.
const RECOMMENDED_BP := 10000

static var _stage_cache: Array[Dictionary] = []
static var _chapter_cache: Array[Dictionary] = []


static func count() -> int:
	return STAGES.size()


static func chapters() -> Array[Dictionary]:
	if _chapter_cache.is_empty():
		for i in CHAPTERS.size():
			var c: Dictionary = CHAPTERS[i].duplicate(true)
			c["index"] = i
			c["first_stage"] = i * STAGES_PER_CHAPTER
			c["stage_count"] = STAGES_PER_CHAPTER
			_chapter_cache.append(c)
	return _chapter_cache


static func stages() -> Array[Dictionary]:
	if _stage_cache.is_empty():
		for i in STAGES.size():
			_stage_cache.append(_build(i))
	return _stage_cache


static func stage(index: int) -> Dictionary:
	if index < 0 or index >= STAGES.size():
		return {}
	return stages()[index]


static func _build(i: int) -> Dictionary:
	var raw: Dictionary = STAGES[i]
	var ch: int = i / STAGES_PER_CHAPTER
	var local: int = i % STAGES_PER_CHAPTER
	var chapter: Dictionary = CHAPTERS[ch]
	var enemies: Array = []
	for e in raw.e:
		var lv: int = int(raw.lv)
		var st: int = int(raw.st)
		var boss := false
		for k in range(2, e.size()):
			var opt: Variant = e[k]
			if opt is String and opt == "boss":
				boss = true
			elif opt is Dictionary:
				lv += int(opt.get("lv", 0))
				st = int(opt.get("st", st))
		var hid: String = e[0]
		var rarity: String = HeroData.get_def(hid).get("rarity", "rare")
		st = maxi(st, int(EconomyData.START_STARS.get(rarity, 1)))
		enemies.append({"hero_id": hid, "level": lv, "stars": st, "slot": int(e[1]), "is_boss": boss})
	var is_boss := bool(raw.get("boss", false))
	var s := {
		"index": i,
		"id": "%d-%d" % [ch + 1, local + 1],
		"chapter": ch,
		"name": raw.name,
		"enemies": enemies,
		"is_boss": is_boss,
		"background": chapter.background,
		"enemy_faction": chapter.faction,
		"first_clear_reward": _first_clear_reward(i, is_boss),
	}
	s["recommended_power"] = recommended_power(enemies)
	s["hint"] = _hint(chapter.faction)
	return s


## Enemy team power the way the player sees it (boss multipliers included).
static func recommended_power(enemies: Array) -> int:
	var counts := {}
	for e in enemies:
		var fac: String = HeroData.get_def(e.hero_id).faction
		counts[fac] = int(counts.get(fac, 0)) + 1
	var fb := 0
	for fac in counts:
		fb = maxi(fb, int(BattleSim.FACTION_BONUS_BP.get(mini(int(counts[fac]), 5), 0)))
	var total := 0
	for e in enemies:
		var st := StatCalc.stats(e.hero_id, int(e.level), int(e.stars))
		st.hp = int(st.hp) * (10000 + fb) / 10000
		st.atk = int(st.atk) * (10000 + fb) / 10000
		if e.is_boss:
			st.hp = int(st.hp) * BattleSim.BOSS_HP_BP / 10000
			st.atk = int(st.atk) * BattleSim.BOSS_ATK_BP / 10000
			st.def = int(st.def) * BattleSim.BOSS_DEF_BP / 10000
		total += StatCalc.power(st)
	return total * RECOMMENDED_BP / 10000


static func _hint(faction: String) -> String:
	var counter := ""
	for f in BattleSim.BEATS:
		if BattleSim.BEATS[f] == faction:
			counter = f
	return "Echoes of the %s host. %s heroes deal +20%% damage here." % [faction.capitalize(), counter.capitalize()]


static func _first_clear_reward(i: int, is_boss: bool) -> Dictionary:
	var local := i % STAGES_PER_CHAPTER
	var r := {
		"gold": 1500 + 450 * i,
		"hero_exp": 900 + 260 * i,
	}
	var tier := EconomyData.gear_tier_for(i)
	if local == 1 or local == 6:
		r["gear_drops"] = [{"slot": EconomyData.GEAR_SLOTS[(i / 2) % 4], "tier": tier}]
	if local == 2:
		r["gems"] = 100
	if local == 4:
		r["gems"] = 200
		r["gear_drops"] = [{"slot": "weapon", "tier": tier}]
	if local == 7:
		r["scrolls"] = 1
	if local == 9:
		r["gems"] = 400
		r["scrolls"] = 2
		r["gear_drops"] = [{"slot": "charm", "tier": mini(tier + 1, 5)}]
	if is_boss:
		r["dust"] = 50 + 25 * (i / STAGES_PER_CHAPTER)
	return r
