class_name GameModel
extends RefCounted
## The game's rules applied to the player state: idle, campaign, heroes, formation, gear,
## summon, quests, shop, settings and save migration. Engine-agnostic: no Nodes, signals,
## Time, OS or files. The autoload Game (src/core/game.gd) is a thin adapter around one
## instance: it supplies the clock, saves/loads `state` as JSON and turns `outbox` and the
## change flags into its `notify` / `changed` signals. Method names, arguments and return
## shapes match the Game API (docs/dev/architecture.md section 4); a Unity port turns this
## class into a plain C# class and game.gd into a MonoBehaviour service.
##
## Pure formulas live in Progression, IdleRules, SummonRules, GearRules, StatCalc and
## BattleSim; content and tuning in data/*.json. All numbers are ints.

const SAVE_VERSION := 1
const CURRENCIES: Array[String] = ["gold", "hero_exp", "gems", "scrolls", "dust"]
const DAY_MS := 86400000
const HOUR_MS := 3600000
const BATTLE_SPEEDS: Array[int] = [1, 2, 4]

var state: Dictionary = {}
## Local time zone offset (ms) used for daily resets.
var tz_bias_ms: int = 0
## Returns the current time in ms since the Unix epoch (without dev_time_offset). Set by the
## adapter; the default is a frozen clock at 0.
var clock: Callable = func() -> int: return 0
## One-shot notifications for the UI, in order: level_up {hero_id, level}, star_up {hero_id,
## stars, passive?}, quest_ready {id, title}, idle_full {}, new_hero {hero_id, rarity},
## monthly_card {gems}. The adapter drains it after every call.
var outbox: Array[Dictionary] = []
## Set by actions that changed the state (the adapter emits `changed` and schedules a save).
var changed_now: bool = false
## Set when a query performed the daily rollover (the adapter saves and emits `changed` later).
var changed_later: bool = false

var _def_cache: Dictionary = {}


# ---------------------------------------------------------------- time

## Current time in ms (clock + state.dev_time_offset).
func now_ms() -> int:
	return int(clock.call()) + int(state.get("dev_time_offset", 0))


## Local day number (days since epoch in the player's time zone). Resets at local midnight.
func today() -> int:
	return day_of(now_ms())


## Floor division of (ms + tz_bias_ms) by one day (also correct before 1970).
func day_of(ms: int) -> int:
	var x := ms + tz_bias_ms
	if x >= 0:
		return x / DAY_MS
	return -((-x - 1) / DAY_MS) - 1


## ms until the next local midnight (for "resets in" labels).
func ms_until_reset() -> int:
	return (today() + 1) * DAY_MS - tz_bias_ms - now_ms()


# ---------------------------------------------------------------- new game / save data

func new_game() -> void:
	state = default_state()
	for id in EconomyData.STARTER_HEROES:
		add_hero(id)
	auto_formation()
	refresh_daily()
	_changed()


## The default (brand new) state. Also the template for defaults-merge on load.
func default_state() -> Dictionary:
	var now := now_ms()
	var day := day_of(now)
	return {
		"version": SAVE_VERSION,
		"created_at": now,
		"player_name": EconomyData.START_PLAYER_NAME,
		"currencies": EconomyData.START_CURRENCIES.duplicate(),
		"heroes": {},
		"formation": ["", "", "", "", ""],
		"campaign": {"cleared": 0},
		"tower": {"best": 0},
		"idle": {"last_claim_at": now, "quick_claims_used": 0, "quick_claim_day": day,
			"carry": {}, "gear_ms": 0, "full_notified": false},
		"summon": {"pity": 0, "total_pulls": 0, "last_free_pull_day": -1,
			"seed": SeededRng.mix(now & 0x7FFFFFFF, 7919)},
		"gear": [],
		"gear_seq": 0,
		"quests": {"day": day, "progress": {}, "claimed": []},
		"shop": {"purchases": {}, "daily": {}, "day": day, "monthly_until_day": -1, "monthly_last_day": -1},
		"settings": {"sound": true, "music": true, "haptics": true, "battle_speed": 1, "auto_ultimates": true,
			"nudity": false},
		"skins": {"owned": [], "equipped": {}},
		"counters": {},
		"dev_time_offset": 0,
		"rng_seed": SeededRng.mix(now & 0x7FFFFFFF, 104729),
	}


## Bring a loaded save (numbers already ints) up to date: fill missing keys from defaults,
## drop bad entries. Returns the repaired state (also installed as `state`).
func migrate(loaded: Dictionary) -> Dictionary:
	var defaults := default_state()
	# A currency missing from an old save is 0, not the new-game amount.
	if loaded.get("currencies") is Dictionary:
		for c in CURRENCIES:
			if not loaded.currencies.has(c):
				loaded.currencies[c] = 0
	# Defaults that depend on "now" must not overwrite loaded values; merge fills gaps only.
	_merge_defaults(loaded, defaults)
	var heroes: Dictionary = {}
	for id in loaded.heroes:
		if HeroData.get_def(str(id)).is_empty() or not (loaded.heroes[id] is Dictionary):
			continue
		var h: Dictionary = loaded.heroes[id]
		var rarity: String = HeroData.get_def(str(id)).rarity
		_merge_defaults(h, {"id": str(id), "level": 1, "stars": Progression.start_stars(rarity),
			"shards": 0, "gear": {}})
		h.stars = clampi(int(h.stars), 1, EconomyData.MAX_STARS)
		h.level = clampi(int(h.level), 1, Progression.level_cap(int(h.stars)))
		heroes[str(id)] = h
	loaded.heroes = heroes
	var gear: Array = []
	var gear_uids := {}
	for it in loaded.gear:
		if not (it is Dictionary and it.has("uid") and EconomyData.GEAR_SLOTS.has(str(it.get("slot", "")))):
			continue
		_merge_defaults(it, {"tier": 1, "name": "Relic", "stats": {}, "equipped_by": ""})
		it.uid = str(it.uid)
		it.slot = str(it.slot)
		it.tier = clampi(int(it.tier), 1, EconomyData.GEAR_MAX_TIER)
		it.equipped_by = str(it.equipped_by)
		if gear_uids.has(it.uid):
			continue
		if it.equipped_by != "" and not heroes.has(it.equipped_by):
			it.equipped_by = ""
		gear.append(it)
		gear_uids[it.uid] = it
	loaded.gear = gear
	for id in heroes:
		var hg: Dictionary = heroes[id].gear
		for slot in hg.keys():
			var uid := str(hg[slot])
			if not gear_uids.has(uid) or gear_uids[uid].equipped_by != id or gear_uids[uid].slot != slot:
				hg.erase(slot)
			else:
				hg[slot] = uid
	# Items that claim an owner who does not list them are loose.
	for it in gear:
		if it.equipped_by != "" and str(heroes[it.equipped_by].gear.get(it.slot, "")) != it.uid:
			it.equipped_by = ""
	if heroes.is_empty():
		# Nothing usable survived: give the starters back rather than an empty roster.
		for id in EconomyData.STARTER_HEROES:
			var d := hero_def(id)
			heroes[id] = {"id": id, "level": 1, "stars": int(d.start_stars), "shards": 0, "gear": {}}
	var f: Array = loaded.formation
	var clean: Array = []
	for i in 5:
		var id: String = str(f[i]) if i < f.size() else ""
		clean.append(id if heroes.has(id) and not clean.has(id) else "")
	loaded.formation = clean
	# Skins: known ids only, once each; an equipped skin must be owned and belong to that hero.
	var owned: Array = []
	for sid in loaded.skins.owned:
		var sd := SkinData.get_def(str(sid))
		if not sd.is_empty() and not owned.has(sd.id):
			owned.append(sd.id)
	loaded.skins.owned = owned
	var equipped := {}
	if loaded.skins.equipped is Dictionary:
		for hid in loaded.skins.equipped:
			var sd := SkinData.get_def(str(loaded.skins.equipped[hid]))
			if not sd.is_empty() and owned.has(sd.id) and sd.hero == str(hid):
				equipped[str(hid)] = sd.id
	loaded.skins.equipped = equipped
	if not BATTLE_SPEEDS.has(int(loaded.settings.battle_speed)):
		loaded.settings.battle_speed = 1
	loaded.campaign.cleared = clampi(int(loaded.campaign.cleared), 0, StageData.count())
	loaded.tower.best = clampi(int(loaded.tower.best), 0, TowerData.FLOORS)
	loaded.version = SAVE_VERSION
	state = loaded
	if clean == ["", "", "", "", ""]:
		auto_formation()
	return state


func _merge_defaults(dst: Dictionary, defaults: Dictionary) -> void:
	for k in defaults:
		var dv: Variant = defaults[k]
		if not dst.has(k):
			dst[k] = dv.duplicate(true) if (dv is Dictionary or dv is Array) else dv
			continue
		var cur: Variant = dst[k]
		if dv is Dictionary:
			if cur is Dictionary:
				_merge_defaults(cur, dv)
			else:
				dst[k] = dv.duplicate(true)
		elif dv is Array:
			if not (cur is Array):
				dst[k] = dv.duplicate(true)
		elif dv is int:
			if not (cur is int):
				dst[k] = int(cur) if (cur is float) else dv
		elif dv is bool:
			if not (cur is bool):
				dst[k] = dv
		elif dv is String:
			if not (cur is String):
				dst[k] = dv


func _changed() -> void:
	changed_now = true


func _notify(event: Dictionary) -> void:
	outbox.append(event)


# ---------------------------------------------------------------- definitions

## Hero definition dictionary (identity + kit: base_stats, ultimate, passives, start_stars).
## {} if unknown.
func hero_def(hero_id: String) -> Dictionary:
	if _def_cache.has(hero_id):
		return _def_cache[hero_id]
	var ident := HeroData.get_def(hero_id)
	if ident.is_empty():
		return {}
	var d: Dictionary = ident.duplicate(true)
	var kit := HeroKits.get_kit(hero_id)
	for k in kit:
		d[k] = kit[k].duplicate(true) if kit[k] is Dictionary or kit[k] is Array else kit[k]
	d["start_stars"] = Progression.start_stars(d.rarity)
	_def_cache[hero_id] = d
	return d


func all_hero_defs() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for h in HeroData.all():
		out.append(hero_def(h.id))
	return out


# ---------------------------------------------------------------- currencies & rewards

func currency(id: String) -> int:
	return int(state.get("currencies", {}).get(id, 0))


func _add_currency(id: String, amount: int) -> void:
	state.currencies[id] = maxi(0, int(state.currencies.get(id, 0)) + amount)


func _can_afford(cost: Dictionary) -> bool:
	for k in cost:
		if currency(k) < int(cost[k]):
			return false
	return true


func _pay(cost: Dictionary) -> void:
	for k in cost:
		_add_currency(k, -int(cost[k]))


## Apply a Reward. Creates gear for "gear_drops", adds heroes/shards. Returns what was granted.
func grant(reward: Dictionary) -> Dictionary:
	var out := {}
	for c in CURRENCIES:
		var n: int = int(reward.get(c, 0))
		if n > 0:
			_add_currency(c, n)
			out[c] = n
	var gear_uids: Array = []
	for d in reward.get("gear_drops", []):
		gear_uids.append(create_gear(str(d.slot), int(d.tier)))
	for uid in reward.get("gear", []):
		gear_uids.append(uid)
	if not gear_uids.is_empty():
		out["gear"] = gear_uids
	for hid in reward.get("heroes", []):
		var r := receive_hero(str(hid))
		out["heroes"] = out.get("heroes", []) + [hid]
		if int(r.shards) > 0:
			var sh: Dictionary = out.get("shards", {})
			sh[hid] = int(sh.get(hid, 0)) + int(r.shards)
			out["shards"] = sh
	var shards: Dictionary = reward.get("shards", {})
	for hid in shards:
		if owns(hid):
			var dust := _add_shards(hid, int(shards[hid]))
			var sh2: Dictionary = out.get("shards", {})
			sh2[hid] = int(sh2.get(hid, 0)) + int(shards[hid])
			out["shards"] = sh2
			if dust > 0:
				out["dust"] = int(out.get("dust", 0)) + dust
	if not gear_uids.is_empty():
		_auto_equip_team()
		_trim_gear_bag()
	return out


# ---------------------------------------------------------------- counters & daily rollover

func counter(id: String) -> int:
	return int(state.counters.get(id, 0))


func _bump(counter_id: String, n: int = 1) -> void:
	refresh_daily()
	state.counters[counter_id] = counter(counter_id) + n
	for q in EconomyData.DAILY_QUESTS:
		if q.counter != counter_id:
			continue
		var before: int = int(state.quests.progress.get(q.id, 0))
		var after := before + n
		state.quests.progress[q.id] = after
		if before < int(q.goal) and after >= int(q.goal) and not state.quests.claimed.has(q.id):
			_notify({"type": "quest_ready", "id": q.id, "title": q.title})


## Daily rollover: quests, quick claims, daily shop offers, monthly card payout.
func refresh_daily() -> void:
	if state.is_empty():
		return
	var day := today()
	var did := false
	if int(state.quests.day) != day:
		state.quests = {"day": day, "progress": {}, "claimed": []}
		did = true
	if int(state.idle.quick_claim_day) != day:
		state.idle.quick_claim_day = day
		state.idle.quick_claims_used = 0
		did = true
	if int(state.shop.day) != day:
		state.shop.day = day
		state.shop.daily = {}
		did = true
	if int(state.shop.monthly_until_day) >= day and int(state.shop.monthly_last_day) < day:
		state.shop.monthly_last_day = day
		_add_currency("gems", EconomyData.MONTHLY_CARD_DAILY_GEMS)
		_notify({"type": "monthly_card", "gems": EconomyData.MONTHLY_CARD_DAILY_GEMS})
		did = true
	if did:
		changed_later = true


# ---------------------------------------------------------------- idle rewards

## {elapsed_ms, cap_ms, full: bool, pending: Reward, per_hour: Reward, quick_claims_left: int,
##  quick_claim_cost: int, quick_claim_ms, gear_every_ms}. pending also has gear_count.
func idle_status() -> Dictionary:
	refresh_daily()
	var elapsed := _idle_elapsed()
	var per_hour := IdleRules.per_hour(cleared_count())
	var calc := IdleRules.accrue(elapsed, per_hour, state.idle.get("carry", {}), int(state.idle.get("gear_ms", 0)))
	var used: int = int(state.idle.quick_claims_used)
	return {
		"elapsed_ms": elapsed,
		"cap_ms": EconomyData.IDLE_CAP_MS,
		"full": elapsed >= EconomyData.IDLE_CAP_MS,
		"pending": calc.reward,
		"per_hour": per_hour,
		"quick_claims_left": IdleRules.quick_claims_left(used),
		"quick_claim_cost": IdleRules.quick_claim_cost(used),
		"quick_claim_ms": EconomyData.QUICK_CLAIM_MS,
		"gear_every_ms": EconomyData.IDLE_GEAR_EVERY_MS,
	}


## Grants pending idle rewards; returns the Reward granted.
func claim_idle() -> Dictionary:
	refresh_daily()
	var now := now_ms()
	var elapsed := _idle_elapsed()
	var calc := IdleRules.accrue(elapsed, IdleRules.per_hour(cleared_count()), state.idle.get("carry", {}),
		int(state.idle.get("gear_ms", 0)))
	state.idle.carry = calc.carry
	state.idle.gear_ms = calc.gear_ms
	state.idle.last_claim_at = now
	state.idle.full_notified = false
	var reward: Dictionary = calc.reward.duplicate()
	reward["gear_drops"] = _idle_drops(int(reward.get("gear_count", 0)))
	reward.erase("gear_count")
	var granted := grant(reward)
	if elapsed >= EconomyData.IDLE_MIN_QUEST_CLAIM_MS:
		_bump("idle_claims")
	_changed()
	return granted


## Instantly grants quick_claim_ms of idle rewards. Result {ok, value: Reward, error}.
func quick_claim() -> Dictionary:
	refresh_daily()
	var used: int = int(state.idle.quick_claims_used)
	var cost := IdleRules.quick_claim_cost(used)
	if cost < 0:
		return _err("No quick claims left today")
	if currency("gems") < cost:
		return _err("Not enough gems")
	_add_currency("gems", -cost)
	state.idle.quick_claims_used = used + 1
	var q := IdleRules.quick_reward(IdleRules.per_hour(cleared_count()), int(state.idle.gear_ms))
	var reward: Dictionary = q.reward
	reward["gear_drops"] = _idle_drops(int(q.gear_count))
	state.idle.gear_ms = int(q.gear_ms)
	var granted := grant(reward)
	_bump("quick_claims")
	_changed()
	return _ok(granted)


## Gear drops for idle time: drop i gets GearRules.random_slot(rng_seed, gear_seq + i), so the
## pieces of one claim can differ; tier by progress.
func _idle_drops(count: int) -> Array:
	var drops: Array = []
	for i in count:
		drops.append({"slot": GearRules.random_slot(int(state.rng_seed), int(state.gear_seq) + i),
			"tier": GearRules.tier_for(cleared_count())})
	return drops


func _idle_elapsed() -> int:
	var now := now_ms()
	var last: int = int(state.idle.last_claim_at)
	if now < last:
		# Clock went backwards: restart the timer instead of paying out.
		state.idle.last_claim_at = now
		return 0
	return IdleRules.elapsed(now, last)


## Queues "idle_full" once when the idle timer reaches the cap.
func check_idle_full() -> void:
	if bool(state.idle.get("full_notified", false)):
		return
	if _idle_elapsed() >= EconomyData.IDLE_CAP_MS:
		state.idle.full_notified = true
		_notify({"type": "idle_full"})


# ---------------------------------------------------------------- campaign

func chapters() -> Array[Dictionary]:
	return StageData.chapters()


func stages() -> Array[Dictionary]:
	return StageData.stages()


func stage(stage_index: int) -> Dictionary:
	return StageData.stage(stage_index)


func cleared_count() -> int:
	return int(state.get("campaign", {}).get("cleared", 0))


## "cleared" | "current" | "locked"
func stage_status(stage_index: int) -> String:
	var c := cleared_count()
	if stage_index < c:
		return "cleared"
	if stage_index == c:
		return "current"
	return "locked"


## Next stage to clear, or {} if all cleared.
func current_stage() -> Dictionary:
	return StageData.stage(cleared_count())


## BattleSetup for the player's formation vs this stage. Each call is a new attempt with its
## own seed: mix(rng_seed + stage_index * 7717, battles_started).
func stage_battle_setup(stage_index: int) -> Dictionary:
	var st := StageData.stage(stage_index)
	if st.is_empty():
		return {}
	var allies := _ally_setups()
	var enemies := _enemy_setups(st.enemies)
	var attempt := counter("battles_started")
	state.counters["battles_started"] = attempt + 1
	return {
		"allies": allies,
		"enemies": enemies,
		"seed": SeededRng.mix(int(state.rng_seed) + stage_index * 7717, attempt),
		"stage_index": stage_index,
		"is_boss": bool(st.is_boss),
		"background": st.background,
	}


## UnitSetups for the player's formation (slots 0-4, empty slots skipped).
func _ally_setups() -> Array:
	var allies: Array = []
	var f := formation()
	for slot in 5:
		var id: String = f[slot]
		if id == "":
			continue
		var h: Dictionary = state.heroes[id]
		allies.append({"uid": "a%d" % slot, "hero_id": id, "side": "ally", "slot": slot,
			"level": int(h.level), "stars": int(h.stars), "stats": hero_stats(id), "is_boss": false})
	return allies


## UnitSetups for built stage or floor enemies.
func _enemy_setups(list: Array) -> Array:
	var enemies: Array = []
	for e in list:
		enemies.append({"uid": "e%d" % int(e.slot), "hero_id": e.hero_id, "side": "enemy", "slot": int(e.slot),
			"level": int(e.level), "stars": int(e.stars),
			"stats": StageData.echo_stats(e.hero_id, int(e.level), int(e.stars), int(e.echo_bp)),
			"is_boss": bool(e.is_boss)})
	return enemies


## Call after a stage battle. Result {ok, value: {reward, first_clear: bool, victory}, error}.
func complete_stage(stage_index: int, outcome: Dictionary) -> Dictionary:
	var st := StageData.stage(stage_index)
	if st.is_empty():
		return _err("Unknown stage")
	if stage_index > cleared_count():
		return _err("Stage locked")
	var victory := bool(outcome.get("victory", false))
	if not victory:
		_bump("battles_lost")
		_changed()
		return _ok({"reward": {}, "first_clear": false, "victory": false})
	_bump("battles_won")
	var first := stage_index == cleared_count()
	var reward := {}
	if first:
		state.campaign.cleared = stage_index + 1
		_bump("stages_cleared")
		reward = grant(st.first_clear_reward)
	_changed()
	return _ok({"reward": reward, "first_clear": first, "victory": true})


# ---------------------------------------------------------------- the Spire (tower)

## Open once the campaign has `unlock_cleared` stages cleared (data/tower.json).
func tower_unlocked() -> bool:
	return cleared_count() >= TowerData.UNLOCK_CLEARED


## Highest floor cleared (0 = none).
func tower_best() -> int:
	return int(state.get("tower", {}).get("best", 0))


## The floor to fight next; TowerData.FLOORS + 1 once the top is cleared.
func tower_next() -> int:
	return tower_best() + 1


## BattleSetup for the player's formation vs floor `f` (only the next floor, once unlocked).
func tower_battle_setup(f: int) -> Dictionary:
	var fl := TowerData.get_floor(f)
	if fl.is_empty() or not tower_unlocked() or f != tower_next():
		return {}
	var attempt := counter("battles_started")
	state.counters["battles_started"] = attempt + 1
	return {
		"allies": _ally_setups(),
		"enemies": _enemy_setups(fl.enemies),
		"seed": SeededRng.mix(int(state.rng_seed) + 500009 + f * 7717, attempt),
		"floor": f,
		"is_boss": bool(fl.is_boss),
		"background": fl.background,
	}


## Call after a floor battle. Result {ok, value: {reward, first_clear: true, victory}, error}.
## A win clears the floor (its reward once); a loss changes nothing but the counters.
func complete_tower(f: int, outcome: Dictionary) -> Dictionary:
	var fl := TowerData.get_floor(f)
	if fl.is_empty():
		return _err("Unknown floor")
	if not tower_unlocked() or f != tower_next():
		return _err("Floor locked")
	if not bool(outcome.get("victory", false)):
		_bump("battles_lost")
		_changed()
		return _ok({"reward": {}, "first_clear": false, "victory": false})
	_bump("battles_won")
	_bump("tower_floors")
	state.tower.best = f
	var reward := grant(fl.first_clear_reward)
	_changed()
	return _ok({"reward": reward, "first_clear": true, "victory": true})


# ---------------------------------------------------------------- heroes

## Owned hero entries {id, level, stars, shards, gear}, sorted by power desc, then id.
func owned_heroes() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var powers := {}
	for id in state.get("heroes", {}):
		out.append(state.heroes[id].duplicate(true))
		powers[id] = hero_power(id)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if powers[a.id] != powers[b.id]:
			return powers[a.id] > powers[b.id]
		return str(a.id) < str(b.id))
	return out


func owns(hero_id: String) -> bool:
	return state.get("heroes", {}).has(hero_id)


## Owned hero entry {id, level, stars, shards, gear} (a copy), or {} if not owned.
func hero(hero_id: String) -> Dictionary:
	if not owns(hero_id):
		return {}
	return state.heroes[hero_id].duplicate(true)


## Final stats {hp, atk, def, spd, crit} for an owned hero (level, stars, gear).
## Unowned heroes: level 1 at their starting stars, no gear.
func hero_stats(hero_id: String) -> Dictionary:
	if not owns(hero_id):
		var d := hero_def(hero_id)
		if d.is_empty():
			return {}
		return StatCalc.stats(hero_id, 1, int(d.start_stars))
	var h: Dictionary = state.heroes[hero_id]
	return StatCalc.stats(hero_id, int(h.level), int(h.stars), equipped_items(hero_id))


## Stats preview at another level/stars (keeps current gear). For "next level" displays.
func hero_stats_at(hero_id: String, level: int, stars: int) -> Dictionary:
	return StatCalc.stats(hero_id, level, stars, equipped_items(hero_id))


func hero_power(hero_id: String) -> int:
	var st := hero_stats(hero_id)
	return 0 if st.is_empty() else StatCalc.power(st)


func team_power() -> int:
	var total := 0
	for id in formation():
		if id != "":
			total += hero_power(id)
	return total


func max_level(hero_id: String) -> int:
	if not owns(hero_id):
		var d := hero_def(hero_id)
		return Progression.level_cap(int(d.get("start_stars", 1)))
	return Progression.level_cap(int(state.heroes[hero_id].stars))


## True when passive number `index` (0 or 1) is unlocked at the hero's current stars.
func passive_unlocked(hero_id: String, index: int) -> bool:
	var d := hero_def(hero_id)
	if d.is_empty() or index < 0 or index >= d.passives.size():
		return false
	var stars: int = int(state.heroes[hero_id].stars) if owns(hero_id) else int(d.start_stars)
	return stars >= int(d.passives[index].unlock_stars)


## {gold, hero_exp} or {} when at the level cap.
func level_up_cost(hero_id: String) -> Dictionary:
	if not owns(hero_id):
		return {}
	var lv: int = int(state.heroes[hero_id].level)
	if lv >= max_level(hero_id):
		return {}
	return Progression.level_cost(lv)


func level_up(hero_id: String) -> Dictionary:
	return level_up_many(hero_id, 1)


## Level up to `times` levels (stops at the cap or when out of resources).
## Result {ok, value: {level, levels_gained, cost: {gold, hero_exp}}, error}.
func level_up_many(hero_id: String, times: int) -> Dictionary:
	if not owns(hero_id):
		return _err("Hero not owned")
	var h: Dictionary = state.heroes[hero_id]
	if int(h.level) >= max_level(hero_id):
		return _err("Level cap reached. Star up to raise it")
	var gained := 0
	var spent := {"gold": 0, "hero_exp": 0}
	while gained < times:
		var cost := level_up_cost(hero_id)
		if cost.is_empty() or not _can_afford(cost):
			break
		_pay(cost)
		spent.gold += int(cost.gold)
		spent.hero_exp += int(cost.hero_exp)
		h.level = int(h.level) + 1
		gained += 1
	if gained == 0:
		var cost := level_up_cost(hero_id)
		return _err("Not enough gold" if currency("gold") < int(cost.gold) else "Not enough hero EXP")
	_bump("level_ups", gained)
	_notify({"type": "level_up", "hero_id": hero_id, "level": int(h.level)})
	_changed()
	return _ok({"level": int(h.level), "levels_gained": gained, "cost": spent})


## Most levels affordable right now (for a "level max" button).
func affordable_levels(hero_id: String) -> int:
	if not owns(hero_id):
		return 0
	return Progression.affordable_levels(int(state.heroes[hero_id].level), max_level(hero_id),
		currency("gold"), currency("hero_exp"))


## True when the hero can level up or star up right now (for "upgrade ready" badges).
func upgrade_ready(hero_id: String) -> bool:
	if not owns(hero_id):
		return false
	var c := level_up_cost(hero_id)
	if not c.is_empty() and _can_afford(c):
		return true
	return can_star_up(hero_id)


## {shards, dust, shards_have, shards_used, dust_per_shard} for the next star, or {} at max.
func star_up_cost(hero_id: String) -> Dictionary:
	if not owns(hero_id):
		return {}
	var h: Dictionary = state.heroes[hero_id]
	return Progression.star_up_cost(int(h.stars), int(h.shards), str(hero_def(hero_id).rarity))


func can_star_up(hero_id: String) -> bool:
	var c := star_up_cost(hero_id)
	return not c.is_empty() and currency("dust") >= int(c.dust)


func star_up(hero_id: String) -> Dictionary:
	if not owns(hero_id):
		return _err("Hero not owned")
	var c := star_up_cost(hero_id)
	if c.is_empty():
		return _err("Already at max stars")
	if currency("dust") < int(c.dust):
		return _err("Not enough shards")
	var h: Dictionary = state.heroes[hero_id]
	h.shards = int(h.shards) - int(c.shards_used)
	_add_currency("dust", -int(c.dust))
	h.stars = int(h.stars) + 1
	_bump("star_ups")
	var ev := {"type": "star_up", "hero_id": hero_id, "stars": int(h.stars)}
	for p in hero_def(hero_id).passives:
		if int(p.unlock_stars) == int(h.stars):
			ev["passive"] = p.name
	_notify(ev)
	_changed()
	return _ok({"stars": int(h.stars), "level_cap": max_level(hero_id)})


## Adds a hero at level 1 and its starting stars (no-op if unknown or owned).
func add_hero(hero_id: String) -> void:
	var d := hero_def(hero_id)
	if d.is_empty() or owns(hero_id):
		return
	state.heroes[hero_id] = {"id": hero_id, "level": 1, "stars": int(d.start_stars), "shards": 0, "gear": {}}


## Adds shards; anything a maxed hero can't use becomes dust. Returns dust granted.
func _add_shards(hero_id: String, n: int) -> int:
	var h: Dictionary = state.heroes[hero_id]
	var r := Progression.add_shards(int(h.stars), int(h.shards), n, str(hero_def(hero_id).rarity))
	h.shards = int(r.shards)
	var dust: int = int(r.dust)
	if dust > 0:
		_add_currency("dust", dust)
	return dust


## New hero or duplicate. Returns {hero_id, rarity, is_new, shards, dust}.
func receive_hero(hero_id: String) -> Dictionary:
	var rarity: String = hero_def(hero_id).rarity
	if not owns(hero_id):
		add_hero(hero_id)
		_place_in_formation(hero_id)
		_notify({"type": "new_hero", "hero_id": hero_id, "rarity": rarity})
		return {"hero_id": hero_id, "rarity": rarity, "is_new": true, "shards": 0, "dust": 0}
	var n := Progression.dupe_shards(rarity)
	var dust := _add_shards(hero_id, n)
	return {"hero_id": hero_id, "rarity": rarity, "is_new": false, "shards": n, "dust": dust}


# ---------------------------------------------------------------- formation

## Array of 5 hero ids or "" (index 0-1 front row, 2-4 back row).
func formation() -> Array:
	if state.is_empty():
		return ["", "", "", "", ""]
	return state.formation.duplicate()


func set_formation(slots: Array) -> Dictionary:
	if slots.size() != 5:
		return _err("Formation needs 5 slots")
	var seen := {}
	var clean: Array = []
	for s in slots:
		var id := str(s)
		if id != "":
			if not owns(id):
				return _err("Hero not owned")
			if seen.has(id):
				return _err("A hero can only appear once")
			seen[id] = true
		clean.append(id)
	if seen.is_empty():
		return _err("Place at least one hero")
	state.formation = clean
	_changed()
	return _ok(clean)


## Best 5 owned heroes by power, guardians and strikers in front, then gear them up.
func auto_formation() -> void:
	var ids: Array = []
	for h in owned_heroes():
		ids.append(h.id)
	state.formation = _arrange(ids.slice(0, 5))
	_auto_equip_team()
	_changed()


## Places up to 5 heroes in rows: sorted by front_priority[role] * 1000000 + HP (then id), so
## the two sturdiest front-liners take slots 0-1 and the rest the back row.
func _arrange(ids: Array) -> Array:
	var score := {}
	for id in ids:
		var role: String = hero_def(id).role
		var base: int = int(EconomyData.FRONT_PRIORITY.get(role, 0))
		score[id] = base * 1000000 + int(hero_stats(id).hp)
	var sorted := ids.duplicate()
	sorted.sort_custom(func(a: String, b: String) -> bool:
		if score[a] != score[b]:
			return score[a] > score[b]
		return a < b)
	var f: Array = ["", "", "", "", ""]
	for i in sorted.size():
		f[i] = sorted[i]
	return f


## {faction: String, count: int, bonus_pct: int} for the current formation, or {}.
func faction_bonus() -> Dictionary:
	var counts := {}
	for id in formation():
		if id != "":
			var fac: String = hero_def(id).faction
			counts[fac] = int(counts.get(fac, 0)) + 1
	for fac in counts:
		var n: int = counts[fac]
		var bp := BattleSim.faction_bonus_bp(n)
		if bp > 0:
			return {"faction": fac, "count": n, "bonus_pct": bp / 100}
	return {}


## A new hero joins a formation that still has room (early game): the team is re-arranged
## so a new guardian takes the front row. A full formation is never changed.
func _place_in_formation(hero_id: String) -> void:
	var f: Array = state.formation
	if f.has(hero_id) or not f.has(""):
		return
	var ids: Array = []
	for id in f:
		if id != "":
			ids.append(id)
	ids.append(hero_id)
	state.formation = _arrange(ids)
	_auto_equip_raw(hero_id)


# ---------------------------------------------------------------- gear

func gear_items() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for it in state.get("gear", []):
		out.append(it.duplicate(true))
	return out


func gear_item(gear_uid: String) -> Dictionary:
	var it := _gear(gear_uid)
	return it.duplicate(true) if not it.is_empty() else {}


## Gear score used for comparisons (power-like).
func gear_score(gear_uid: String) -> int:
	return GearRules.score(_gear(gear_uid))


func equip(hero_id: String, gear_uid: String) -> Dictionary:
	if not owns(hero_id):
		return _err("Hero not owned")
	var it := _gear(gear_uid)
	if it.is_empty():
		return _err("Unknown gear")
	_equip_raw(hero_id, it)
	_changed()
	return _ok(gear_uid)


func unequip(hero_id: String, slot: String) -> Dictionary:
	if not owns(hero_id):
		return _err("Hero not owned")
	var hg: Dictionary = state.heroes[hero_id].gear
	if not hg.has(slot):
		return _err("Nothing equipped")
	var it := _gear(hg[slot])
	if not it.is_empty():
		it.equipped_by = ""
	hg.erase(slot)
	_changed()
	return _ok(slot)


func auto_equip(hero_id: String) -> void:
	if _auto_equip_raw(hero_id):
		_changed()


## Turns an unequipped item into gold and dust. Result {ok, value: Reward, error}.
func salvage_gear(gear_uid: String) -> Dictionary:
	var it := _gear(gear_uid)
	if it.is_empty():
		return _err("Unknown gear")
	if str(it.equipped_by) != "":
		return _err("Unequip it first")
	var reward := _salvage_raw(it)
	_changed()
	return _ok(reward)


func _gear(gear_uid: String) -> Dictionary:
	for it in state.get("gear", []):
		if it.uid == gear_uid:
			return it
	return {}


## The GearItems a hero wears (the live dictionaries; do not modify).
func equipped_items(hero_id: String) -> Array:
	var out: Array = []
	if not owns(hero_id):
		return out
	var hg: Dictionary = state.heroes[hero_id].gear
	for slot in hg:
		var it := _gear(hg[slot])
		if not it.is_empty():
			out.append(it)
	return out


func _equip_raw(hero_id: String, it: Dictionary) -> void:
	var prev_owner: String = str(it.equipped_by)
	if prev_owner != "" and owns(prev_owner):
		state.heroes[prev_owner].gear.erase(it.slot)
	var hg: Dictionary = state.heroes[hero_id].gear
	if hg.has(it.slot):
		var old := _gear(hg[it.slot])
		if not old.is_empty():
			old.equipped_by = ""
	hg[it.slot] = it.uid
	it.equipped_by = hero_id


## Best item per slot (highest score, first in bag order on ties) from loose gear and, for a
## hero in the formation, from heroes on the bench (never from another formation hero).
func _auto_equip_raw(hero_id: String) -> bool:
	if not owns(hero_id):
		return false
	var team := formation()
	var may_take := team.has(hero_id)
	var did := false
	var hg: Dictionary = state.heroes[hero_id].gear
	for slot in EconomyData.GEAR_SLOTS:
		var cur := _gear(hg.get(slot, ""))
		var best := cur
		var best_score := GearRules.score(cur) if not cur.is_empty() else -1
		for it in state.gear:
			var owner := str(it.equipped_by)
			if it.slot != slot or owner == hero_id:
				continue
			if owner != "" and (not may_take or team.has(owner)):
				continue
			var sc := GearRules.score(it)
			if sc > best_score:
				best = it
				best_score = sc
		if not best.is_empty() and best != cur:
			_equip_raw(hero_id, best)
			did = true
	return did


func _auto_equip_team() -> void:
	for id in formation():
		if id != "":
			_auto_equip_raw(id)


## Creates the next gear item (gear_seq + 1) in the bag and returns its uid.
func create_gear(slot: String, tier: int) -> String:
	state.gear_seq = int(state.gear_seq) + 1
	var item := GearRules.make_item(slot, tier, int(state.rng_seed), int(state.gear_seq))
	state.gear.append(item)
	return item.uid


func _salvage_raw(it: Dictionary) -> Dictionary:
	var reward := GearRules.salvage_value(int(it.tier))
	state.gear.erase(it)
	_add_currency("gold", int(reward.gold))
	_add_currency("dust", int(reward.dust))
	return reward


## Keeps the bag from growing forever: salvages the weakest unequipped pieces (lowest score
## first; equal scores: the earlier piece in the bag first, so every sort algorithm agrees).
func _trim_gear_bag() -> void:
	var loose: Array = []
	for it in state.gear:
		if str(it.equipped_by) == "":
			loose.append([GearRules.score(it), loose.size(), it])
	if loose.size() <= EconomyData.GEAR_BAG_LIMIT:
		return
	loose.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	for i in loose.size() - EconomyData.GEAR_BAG_LIMIT:
		_salvage_raw(loose[i][2])


# ---------------------------------------------------------------- summon

## BannerDef {id, name, cost_one, cost_ten, scroll_cost_one, scroll_cost_ten, rates: {rare,
## epic, legendary} (basis points), pity_legendary, ten_pull_guarantee, pool, pool_by_rarity}.
func banner() -> Dictionary:
	var b: Dictionary = EconomyData.BANNER
	var pool: Array = []
	for id in b.pool:
		pool.append(str(id))
	return {
		"id": b.id,
		"name": b.name,
		"cost_one": int(b.cost_one.gems),
		"cost_ten": int(b.cost_ten.gems),
		"scroll_cost_one": int(b.cost_one.scrolls),
		"scroll_cost_ten": int(b.cost_ten.scrolls),
		"rates": b.rates.duplicate(),
		"pity_legendary": int(b.pity_legendary),
		"ten_pull_guarantee": b.ten_pull_guarantee,
		"pool": pool,
		"pool_by_rarity": SummonRules.pool_by_rarity(b),
	}


## Pulls since the last Legendary (Legendary guaranteed when this reaches pity_legendary - 1).
func pity_count() -> int:
	return int(state.get("summon", {}).get("pity", 0))


func free_pull_available() -> bool:
	if state.is_empty():
		return false
	refresh_daily()
	return int(state.summon.last_free_pull_day) != today()


## count = 1 or 10. use_free only valid with count 1. Pays with scrolls first, then gems.
## Result {ok, value: Array of {hero_id, rarity, is_new, shards, dust, pity}, error}.
func summon(count: int, use_free: bool = false) -> Dictionary:
	refresh_daily()
	if count != 1 and count != 10:
		return _err("Summon 1 or 10")
	var b: Dictionary = EconomyData.BANNER
	if use_free:
		if count != 1:
			return _err("The free summon is a single pull")
		if not free_pull_available():
			return _err("Free summon already used today")
		state.summon.last_free_pull_day = today()
	else:
		var cost: Dictionary = b.cost_one if count == 1 else b.cost_ten
		if currency("scrolls") >= int(cost.scrolls):
			_add_currency("scrolls", -int(cost.scrolls))
		elif currency("gems") >= int(cost.gems):
			_add_currency("gems", -int(cost.gems))
		else:
			return _err("Not enough gems")
	var roll := SummonRules.pull(b, int(state.summon.seed), int(state.summon.total_pulls), pity_count(), count)
	state.summon.pity = int(roll.pity)
	state.summon.total_pulls = int(roll.total_pulls)
	var results: Array = []
	for p in roll.results:
		var r := receive_hero(str(p.hero_id))
		r["pity"] = int(p.pity)
		results.append(r)
	_bump("summons", count)
	_changed()
	return _ok(results)


# ---------------------------------------------------------------- quests & shop

## Array of {id, title, counter, progress, goal, reward, claimed, ready}. counter names what the
## quest counts ("idle_claims", "battles_won", ...), so the UI can pick an icon and a Go target.
func quests() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if state.is_empty():
		return out
	refresh_daily()
	for q in EconomyData.DAILY_QUESTS:
		var p: int = int(state.quests.progress.get(q.id, 0))
		var claimed: bool = state.quests.claimed.has(q.id)
		out.append({"id": q.id, "title": q.title, "counter": str(q.counter), "progress": mini(p, int(q.goal)), "goal": int(q.goal),
			"reward": q.reward.duplicate(), "claimed": claimed, "ready": p >= int(q.goal) and not claimed})
	return out


func claim_quest(quest_id: String) -> Dictionary:
	refresh_daily()
	var q := {}
	for d in EconomyData.DAILY_QUESTS:
		if d.id == quest_id:
			q = d
	if q.is_empty():
		return _err("Unknown quest")
	if state.quests.claimed.has(quest_id):
		return _err("Already claimed")
	if int(state.quests.progress.get(quest_id, 0)) < int(q.goal):
		return _err("Not finished yet")
	state.quests.claimed.append(quest_id)
	var granted := grant(q.reward)
	if str(q.counter) != EconomyData.META_QUEST_COUNTER:
		_bump(EconomyData.META_QUEST_COUNTER)
	_changed()
	return _ok(granted)


## Number of daily quests ready to claim (for nav badges).
func quests_ready_count() -> int:
	var n := 0
	for q in quests():
		if q.ready:
			n += 1
	return n


## Array of {id, name, description, price_label, reward, limit, purchased, tag, period,
## available, test_purchase} (+ days_left for the monthly card).
func offers() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if state.is_empty():
		return out
	refresh_daily()
	for o in EconomyData.OFFERS:
		var bought := _offer_count(o)
		var limit: int = int(o.limit)
		var entry := {"id": o.id, "name": o.name, "description": o.description,
			"price_label": o.price_label, "reward": o.reward.duplicate(), "limit": limit,
			"purchased": bought, "tag": o.tag, "period": o.period,
			"available": limit == 0 or bought < limit, "test_purchase": o.price_label != "Free"}
		if o.id == EconomyData.MONTHLY_CARD_OFFER:
			entry["days_left"] = monthly_card_days_left()
		out.append(entry)
	return out


## Prototype: purchases are free test purchases. Result {ok, value: Reward, error}.
func buy_offer(offer_id: String) -> Dictionary:
	refresh_daily()
	var o := {}
	for d in EconomyData.OFFERS:
		if d.id == offer_id:
			o = d
	if o.is_empty():
		return _err("Unknown offer")
	var limit: int = int(o.limit)
	if limit > 0 and _offer_count(o) >= limit:
		return _err("Already claimed today" if o.period == "day" else "Purchase limit reached")
	var key: String = "daily" if o.period == "day" else "purchases"
	state.shop[key][offer_id] = int(state.shop[key].get(offer_id, 0)) + 1
	if offer_id == EconomyData.MONTHLY_CARD_OFFER:
		var day := today()
		state.shop.monthly_until_day = maxi(int(state.shop.monthly_until_day), day) + EconomyData.MONTHLY_CARD_DAYS
		state.shop.monthly_last_day = day
	var granted := grant(o.reward)
	_changed()
	return _ok(granted)


## Days of Moonlit Pass payouts left (0 = inactive).
func monthly_card_days_left() -> int:
	return maxi(0, int(state.shop.monthly_until_day) - today())


func _offer_count(o: Dictionary) -> int:
	var key: String = "daily" if o.period == "day" else "purchases"
	return int(state.shop[key].get(o.id, 0))


# ---------------------------------------------------------------- skins (cosmetic)

## The skins of one hero (SkinData records) with "owned" and "equipped" flags added.
func skins_for(hero_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var eq := equipped_skin(hero_id)
	for sd in SkinData.for_hero(hero_id):
		var s := sd.duplicate()
		s["owned"] = owns_skin(sd.id)
		s["equipped"] = sd.id == eq
		out.append(s)
	return out


func owns_skin(skin_id: String) -> bool:
	return (state.skins.owned as Array).has(skin_id)


## The skin a hero wears ("" = her base look).
func equipped_skin(hero_id: String) -> String:
	return str(state.skins.equipped.get(hero_id, ""))


## Buy a skin with gems. Cosmetic only: stats never change. Result {ok, value: skin, error}.
func buy_skin(skin_id: String) -> Dictionary:
	var sd := SkinData.get_def(skin_id)
	if sd.is_empty():
		return _err("Unknown skin")
	if owns_skin(skin_id):
		return _err("Already owned")
	var cost := {"gems": int(sd.price_gems)}
	if not _can_afford(cost):
		return _err("Not enough gems")
	_pay(cost)
	(state.skins.owned as Array).append(skin_id)
	_bump("skins_bought")
	_changed()
	return _ok(sd)


## Put an owned skin on its hero, or skin_id "" to go back to her base look.
func equip_skin(hero_id: String, skin_id: String) -> Dictionary:
	if HeroData.get_def(hero_id).is_empty():
		return _err("Unknown hero")
	if skin_id == "":
		state.skins.equipped.erase(hero_id)
		_changed()
		return _ok("")
	var sd := SkinData.get_def(skin_id)
	if sd.is_empty() or sd.hero != hero_id:
		return _err("That skin is for another hero")
	if not owns_skin(skin_id):
		return _err("You don't own that skin")
	state.skins.equipped[hero_id] = skin_id
	_changed()
	return _ok(skin_id)


# ---------------------------------------------------------------- settings & dev

func setting(key: String) -> Variant:
	return state.get("settings", {}).get(key, null)


func set_setting(key: String, value: Variant) -> void:
	if state.is_empty():
		return
	match key:
		"battle_speed":
			var v := int(value)
			if not BATTLE_SPEEDS.has(v):
				return
			state.settings.battle_speed = v
		"sound", "music", "haptics", "auto_ultimates", "nudity":
			state.settings[key] = bool(value)
		"chapter_intro_seen":
			# Highest chapter index whose story intro the player has seen (campaign screen).
			state.settings[key] = maxi(int(value), int(state.settings.get(key, -1)))
		"player_name":
			state.player_name = str(value).strip_edges().left(16)
		_:
			state.settings[key] = value
	_changed()


## Dev tool: pretend `ms` milliseconds have passed (for idle testing).
func dev_skip_time(ms: int) -> void:
	state.dev_time_offset = int(state.dev_time_offset) + ms
	refresh_daily()
	check_idle_full()
	_changed()


func dev_add(currency_id: String, amount: int) -> void:
	if not CURRENCIES.has(currency_id):
		return
	_add_currency(currency_id, amount)
	_changed()


## Test state for --rich: every hero, lots of currency, mid-campaign progress.
func make_rich_state() -> void:
	new_game()
	var now := now_ms()
	var roster := {
		"seraphiel": [46, 5, 20], "cassiel": [40, 4, 12], "liora": [38, 4, 30],
		"uriela": [44, 4, 25], "nuriel": [30, 3, 5], "mordessa": [42, 4, 10],
		"brakka": [36, 3, 18], "vesper": [35, 3, 0], "imra": [28, 3, 14],
		"kessa": [40, 4, 40], "noctaire": [48, 5, 60], "orrin": [34, 3, 22],
		"sable": [36, 4, 8], "lucen": [42, 4, 30], "ashra": [25, 2, 6],
	}
	for id in roster:
		add_hero(id)
		var h: Dictionary = state.heroes[id]
		h.stars = maxi(int(h.stars), int(roster[id][1]))
		h.level = mini(int(roster[id][0]), Progression.level_cap(int(h.stars)))
		h.shards = int(roster[id][2])
	state.currencies = {"gold": 500000, "hero_exp": 300000, "gems": 50000, "scrolls": 30, "dust": 2000}
	state.campaign.cleared = 12
	auto_formation()
	var slots := ["weapon", "armor", "helm", "charm", "weapon", "armor", "helm", "charm", "weapon", "charm"]
	var tiers := [3, 3, 2, 3, 2, 2, 2, 1, 1, 2]
	for i in slots.size():
		create_gear(slots[i], tiers[i])
	var f := formation()
	_auto_equip_raw(f[0])
	_auto_equip_raw(f[2])
	state.quests.progress = {"dq_idle": 1, "dq_win": 3, "dq_summon": 1, "dq_level": 2}
	state.idle.last_claim_at = now - 5 * HOUR_MS
	state.summon.pity = 37
	state.summon.total_pulls = 120
	state.counters = {"battles_won": 14, "summons": 120, "stages_cleared": 12, "level_ups": 500}
	_changed()


# ---------------------------------------------------------------- helpers

func _ok(value: Variant = null) -> Dictionary:
	return {"ok": true, "value": value, "error": ""}


func _err(msg: String) -> Dictionary:
	return {"ok": false, "value": null, "error": msg}
