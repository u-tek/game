class_name StageData
## Campaign: 3 chapters x 10 stages. Enemies are "echoes" of roster heroes. Stages 5 and
## 10 of every chapter are boss stages. Owned by core logic; difficulty is solved by
## tests/tools/calibrate_stages.gd and checked by tests/tools/playthrough.gd (see
## docs/dev/economy-v1.md).
##
## Stage: {index, id "1-5", chapter (0-based chapter index), name, enemies [{hero_id, level,
##   stars, slot, is_boss, echo_bp}], recommended_power, enemy_power, first_clear_reward,
##   is_boss, background, enemy_faction, hint}
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

## Per stage: name, enemy level (lv) and stars (st), echo strength (pw, basis points of the
## ECHO_STAT_BP baseline), recommended power (rec), enemies [hero_id, slot, opts...].
## lv, pw and rec come from tests/tools/calibrate_stages.gd, which follows pacing bots (an
## efficient free player) along a target timeline: chapter 1 on day 1, chapter 2 on days 2-4,
## chapter 3 on days 5-10. See docs/dev/economy-v1.md.
## Enemy opts: "boss" marks the boss; {"lv": +n, "st": n} adjust level / stars.
const STAGES: Array[Dictionary] = [
	# ---------------- Chapter 1: Shattered Sanctum (celestial echoes)
	{"name": "Broken Narthex", "lv": 1, "pw": 14000, "rec": 1322, "st": 1, "e": [["uriela", 0], ["nuriel", 2]]},
	{"name": "Hall of Fallen Bells", "lv": 2, "pw": 10750, "rec": 1322, "st": 1, "e": [["uriela", 0], ["uriela", 1], ["nuriel", 3]]},
	{"name": "Glass Garden", "lv": 3, "pw": 10250, "rec": 1322, "st": 1, "e": [["uriela", 0], ["liora", 2], ["nuriel", 3]]},
	{"name": "Pillar Walk", "lv": 6, "pw": 17250, "rec": 3477, "st": 1, "e": [["uriela", 0], ["uriela", 1], ["nuriel", 2], ["liora", 3]]},
	{"name": "The Gate Warden", "lv": 8, "pw": 11250, "rec": 3837, "st": 1, "boss": true, "e": [["cassiel", 0, "boss"], ["uriela", 1], ["nuriel", 2], ["uriela", 4]]},
	{"name": "Ashen Cloister", "lv": 15, "pw": 14000, "rec": 5309, "st": 1, "e": [["cassiel", 0], ["uriela", 1], ["nuriel", 2], ["liora", 3], ["ashra", 4]]},
	{"name": "Reliquary Stair", "lv": 16, "pw": 12000, "rec": 5385, "st": 2, "e": [["uriela", 0], ["cassiel", 1], ["nuriel", 2], ["kessa", 3], ["liora", 4]]},
	{"name": "Choir Loft", "lv": 18, "pw": 14250, "rec": 6452, "st": 2, "e": [["cassiel", 0], ["uriela", 1], ["liora", 2], ["nuriel", 3], ["imra", 4]]},
	{"name": "Bell Tower Ruin", "lv": 19, "pw": 13500, "rec": 6531, "st": 2, "e": [["cassiel", 0], ["uriela", 1], ["nuriel", 2], ["liora", 3], ["vesper", 4]]},
	{"name": "The Choir Unsung", "lv": 20, "pw": 10000, "rec": 6968, "st": 2, "boss": true, "e": [["cassiel", 0], ["uriela", 1], ["seraphiel", 2, "boss"], ["liora", 3], ["nuriel", 4]]},
	# ---------------- Chapter 2: Ember Wastes (infernal echoes)
	{"name": "Cinder Road", "lv": 24, "pw": 11750, "rec": 8382, "st": 2, "e": [["brakka", 0], ["kessa", 1], ["imra", 2], ["vesper", 3], ["kessa", 4]]},
	{"name": "Sulfur Springs", "lv": 26, "pw": 11500, "rec": 8801, "st": 2, "e": [["brakka", 0], ["mordessa", 1, {"st": 2}], ["imra", 2], ["kessa", 3], ["vesper", 4]]},
	{"name": "Molten Ford", "lv": 28, "pw": 13500, "rec": 9608, "st": 2, "e": [["brakka", 0], ["kessa", 1], ["vesper", 2], ["imra", 3], ["ashra", 4]]},
	{"name": "Chainworks", "lv": 29, "pw": 12750, "rec": 10014, "st": 2, "e": [["brakka", 0], ["orrin", 1], ["vesper", 2], ["kessa", 3], ["imra", 4]]},
	{"name": "Brimstone Bulwark", "lv": 32, "pw": 9500, "rec": 11308, "st": 2, "boss": true, "e": [["brakka", 0, "boss"], ["kessa", 1], ["vesper", 2], ["imra", 3], ["kessa", 4]]},
	{"name": "Ashfall Market", "lv": 34, "pw": 13750, "rec": 11828, "st": 3, "e": [["brakka", 0], ["uriela", 1], ["vesper", 2], ["imra", 3], ["kessa", 4]]},
	{"name": "Lantern Bazaar", "lv": 35, "pw": 12250, "rec": 12230, "st": 3, "e": [["brakka", 0], ["kessa", 1], ["imra", 2], ["vesper", 3], ["liora", 4]]},
	{"name": "Obsidian Steps", "lv": 36, "pw": 12500, "rec": 12568, "st": 3, "e": [["brakka", 0], ["cassiel", 1], ["vesper", 2], ["kessa", 3], ["imra", 4]]},
	{"name": "Furnace Gate", "lv": 39, "pw": 12750, "rec": 13413, "st": 3, "e": [["brakka", 0], ["mordessa", 1], ["vesper", 2], ["imra", 3], ["kessa", 4]]},
	{"name": "Throne of the Ninth Furnace", "lv": 41, "pw": 11500, "rec": 14664, "st": 3, "boss": true, "e": [["brakka", 0], ["kessa", 1], ["mordessa", 2, "boss"], ["vesper", 3], ["imra", 4]]},
	# ---------------- Chapter 3: Twilight Abyss (fallen echoes)
	{"name": "Dusk Shore", "lv": 44, "pw": 13750, "rec": 15963, "st": 3, "e": [["orrin", 0], ["lucen", 1], ["ashra", 2], ["sable", 3], ["lucen", 4]]},
	{"name": "Chapel of Ghosts", "lv": 46, "pw": 12250, "rec": 16745, "st": 3, "e": [["orrin", 0], ["lucen", 1], ["sable", 2], ["ashra", 3], ["noctaire", 4, {"st": 3}]]},
	{"name": "Broken Oath Bridge", "lv": 49, "pw": 14500, "rec": 18267, "st": 3, "e": [["orrin", 0], ["brakka", 1], ["ashra", 2], ["sable", 3], ["lucen", 4]]},
	{"name": "Hollow Choir", "lv": 50, "pw": 14250, "rec": 19115, "st": 3, "e": [["orrin", 0], ["lucen", 1], ["seraphiel", 2], ["sable", 3], ["ashra", 4]]},
	{"name": "The Chained Gate", "lv": 53, "pw": 12500, "rec": 20134, "st": 3, "boss": true, "e": [["orrin", 0, "boss"], ["lucen", 1], ["ashra", 2], ["sable", 3], ["noctaire", 4]]},
	{"name": "Ash Witch's Hollow", "lv": 55, "pw": 13500, "rec": 20911, "st": 4, "e": [["orrin", 0], ["lucen", 1], ["ashra", 2], ["ashra", 3], ["sable", 4]]},
	{"name": "Mirror Lake", "lv": 57, "pw": 13000, "rec": 21358, "st": 4, "e": [["orrin", 0], ["cassiel", 1], ["lucen", 2], ["sable", 3], ["noctaire", 4]]},
	{"name": "Feather Graveyard", "lv": 59, "pw": 13000, "rec": 23095, "st": 4, "e": [["orrin", 0], ["lucen", 1], ["vesper", 2], ["sable", 3], ["noctaire", 4]]},
	{"name": "Eclipse Stair", "lv": 61, "pw": 12500, "rec": 24522, "st": 4, "e": [["orrin", 0], ["mordessa", 1], ["ashra", 2], ["sable", 3], ["noctaire", 4]]},
	{"name": "The Last Order", "lv": 64, "pw": 11750, "rec": 26514, "st": 4, "boss": true, "e": [["orrin", 0], ["lucen", 1], ["noctaire", 2, "boss"], ["sable", 3], ["ashra", 4]]},
]

## Stages 1-1..1-3 are tuned for the three starter Rares at level 1, before any upgrade.
const STARTER_TEAM := {"uriela": 1, "lucen": 1, "kessa": 1}
const STARTER_STAGES := 3

const STAGES_PER_CHAPTER := 10
## First-clear gold / hero EXP: base + step * stage index. Kept well below what the next
## stage's levels cost, so idle income (not the campaign itself) paces progress.
const FIRST_CLEAR_GOLD_BASE := 500
const FIRST_CLEAR_GOLD_STEP := 150
const FIRST_CLEAR_EXP_BASE := 300
const FIRST_CLEAR_EXP_STEP := 90
## Echoes are hollow copies: HP, ATK and DEF at this fraction of a real hero's.
const ECHO_STAT_BP := 7500

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
		enemies.append({"hero_id": hid, "level": lv, "stars": st, "slot": int(e[1]), "is_boss": boss,
			"echo_bp": ECHO_STAT_BP * int(raw.get("pw", 10000)) / 10000})
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
	s["recommended_power"] = recommended_power(i)
	s["enemy_power"] = enemy_power(enemies)
	s["hint"] = _hint(chapter.faction)
	return s


## Stats of an enemy echo (before boss multipliers, which BattleSim applies).
## echo_bp: strength of the echo in basis points (Stage enemy "echo_bp").
static func echo_stats(hero_id: String, level: int, stars: int, echo_bp: int = ECHO_STAT_BP) -> Dictionary:
	var st := StatCalc.stats(hero_id, level, stars)
	for k in ["hp", "atk", "def"]:
		st[k] = maxi(1, int(st[k]) * echo_bp / 10000)
	return st


## Team power (as Game.team_power() shows it, gear included) that wins this stage on the
## intended schedule. Never drops from one stage to the next.
static func recommended_power(index: int) -> int:
	if index < 0 or index >= STAGES.size():
		return 0
	return int(STAGES[index].get("rec", 0))


## Raw enemy team power (faction and boss multipliers included), for reference.
static func enemy_power(enemies: Array) -> int:
	var counts := {}
	for e in enemies:
		var fac: String = HeroData.get_def(e.hero_id).faction
		counts[fac] = int(counts.get(fac, 0)) + 1
	var fb := 0
	for fac in counts:
		fb = maxi(fb, int(BattleSim.FACTION_BONUS_BP.get(mini(int(counts[fac]), 5), 0)))
	var total := 0
	for e in enemies:
		var st := echo_stats(e.hero_id, int(e.level), int(e.stars), int(e.echo_bp))
		st.hp = int(st.hp) * (10000 + fb) / 10000
		st.atk = int(st.atk) * (10000 + fb) / 10000
		if e.is_boss:
			st.hp = int(st.hp) * BattleSim.BOSS_HP_BP / 10000
			st.atk = int(st.atk) * BattleSim.BOSS_ATK_BP / 10000
			st.def = int(st.def) * BattleSim.BOSS_DEF_BP / 10000
		total += StatCalc.power(st)
	return total


static func _hint(faction: String) -> String:
	var counter := ""
	for f in BattleSim.BEATS:
		if BattleSim.BEATS[f] == faction:
			counter = f
	return "Echoes of the %s host. %s heroes deal +20%% damage here." % [faction.capitalize(), counter.capitalize()]


static func _first_clear_reward(i: int, is_boss: bool) -> Dictionary:
	var local := i % STAGES_PER_CHAPTER
	var r := {
		"gold": FIRST_CLEAR_GOLD_BASE + FIRST_CLEAR_GOLD_STEP * i,
		"hero_exp": FIRST_CLEAR_EXP_BASE + FIRST_CLEAR_EXP_STEP * i,
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
