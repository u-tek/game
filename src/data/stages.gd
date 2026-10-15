class_name StageData
extends RefCounted
## Campaign from res://data/stages.json: chapters, each with its stages in order. Enemies are
## "echoes" of roster heroes; the 5th and 10th stage of a chapter are bosses. Difficulty
## values (level, strength_bp, recommended_power) are solved by tests/tools/calibrate_stages.gd
## (which writes them back into the JSON) and checked by tests/tools/playthrough.gd; see
## docs/dev/economy-v1.md.
##
## Built Stage: {index, id "1-5", chapter (0-based chapter index), name, enemies [{hero_id,
##   level, stars, slot, is_boss, echo_bp}], recommended_power, enemy_power, first_clear_reward,
##   is_boss, background, enemy_faction, hint}
## Chapter: {index, id, name, intro, background, faction, hint, first_stage, stage_count}

## Echoes are hollow copies: HP, ATK and DEF at this fraction of a real hero's (basis points).
static var ECHO_STAT_BP: int = int(GameData.stages().echo_stat_bp)
## Calibration only: the starter team (hero id -> stars) and how many opening stages it must win.
static var STARTER_TEAM: Dictionary = GameData.stages().calibration.starter_team
static var STARTER_STAGES: int = int(GameData.stages().calibration.starter_stages)

static var _raw: Array[Dictionary] = []
static var _raw_chapter: Array[int] = []
static var _raw_local: Array[int] = []
static var _stage_cache: Array[Dictionary] = []
static var _chapter_cache: Array[Dictionary] = []


static func _ensure() -> void:
	if not _chapter_cache.is_empty():
		return
	var chs := GameData.dicts(GameData.stages().get("chapters", []))
	for ci in chs.size():
		var c: Dictionary = chs[ci]
		var list := GameData.dicts(c.get("stages", []))
		var out := {}
		for k in c:
			if k != "stages":
				out[k] = c[k]
		out["index"] = ci
		out["first_stage"] = _raw.size()
		out["stage_count"] = list.size()
		_chapter_cache.append(out)
		for li in list.size():
			_raw.append(list[li])
			_raw_chapter.append(ci)
			_raw_local.append(li)


static func count() -> int:
	_ensure()
	return _raw.size()


static func chapters() -> Array[Dictionary]:
	_ensure()
	return _chapter_cache


static func stages() -> Array[Dictionary]:
	_ensure()
	if _stage_cache.is_empty():
		for i in _raw.size():
			_stage_cache.append(_build(i))
	return _stage_cache


static func stage(index: int) -> Dictionary:
	if index < 0 or index >= count():
		return {}
	return stages()[index]


## The stage record exactly as stored in stages.json (tools: the calibrator rewrites it).
static func raw_stage(index: int) -> Dictionary:
	_ensure()
	return _raw[index] if index >= 0 and index < _raw.size() else {}


## Enemy setup from a stage record: level = stage level + level_bonus, stars = enemy stars or
## the stage's, but never below the hero's starting stars; echo_bp = echo_stat_bp *
## strength_bp / 10000.
static func _build(i: int) -> Dictionary:
	var raw: Dictionary = _raw[i]
	var ch: int = _raw_chapter[i]
	var chapter: Dictionary = _chapter_cache[ch]
	var echo_bp: int = ECHO_STAT_BP * int(raw.get("strength_bp", 10000)) / 10000
	var enemies: Array = []
	for e in raw.get("enemies", []):
		var hid: String = str(e.hero_id)
		var rarity: String = HeroData.get_def(hid).get("rarity", "rare")
		var st: int = maxi(int(e.get("stars", raw.stars)), Progression.start_stars(rarity))
		enemies.append({"hero_id": hid, "level": int(raw.level) + int(e.get("level_bonus", 0)), "stars": st,
			"slot": int(e.slot), "is_boss": bool(e.get("boss", false)), "echo_bp": echo_bp})
	var s := {
		"index": i,
		"id": "%d-%d" % [ch + 1, _raw_local[i] + 1],
		"chapter": ch,
		"name": str(raw.name),
		"enemies": enemies,
		"is_boss": bool(raw.get("boss", false)),
		"background": str(chapter.background),
		"enemy_faction": str(chapter.faction),
		"first_clear_reward": raw.get("first_clear_reward", {}),
	}
	s["recommended_power"] = recommended_power(i)
	s["enemy_power"] = enemy_power(enemies)
	s["hint"] = str(chapter.get("hint", ""))
	return s


## Stats of an enemy echo (before boss multipliers, which BattleSim applies).
## echo_bp: strength of the echo in basis points (Stage enemy "echo_bp").
static func echo_stats(hero_id: String, level: int, stars: int, echo_bp: int = -1) -> Dictionary:
	var bp := ECHO_STAT_BP if echo_bp < 0 else echo_bp
	var st := StatCalc.stats(hero_id, level, stars)
	for k in ["hp", "atk", "def"]:
		st[k] = maxi(1, int(st[k]) * bp / 10000)
	return st


## Team power (as Game.team_power() shows it, gear included) that wins this stage on the
## intended schedule. Never drops from one stage to the next.
static func recommended_power(index: int) -> int:
	return int(raw_stage(index).get("recommended_power", 0))


## Raw enemy team power (faction and boss multipliers included), for reference.
static func enemy_power(enemies: Array) -> int:
	var counts := {}
	for e in enemies:
		var fac: String = HeroData.get_def(e.hero_id).faction
		counts[fac] = int(counts.get(fac, 0)) + 1
	var fb := 0
	for fac in counts:
		fb = maxi(fb, BattleSim.faction_bonus_bp(int(counts[fac])))
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
