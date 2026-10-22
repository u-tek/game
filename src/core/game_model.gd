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
## stars, passive?}, awaken {hero_id, awaken, unlock}, quest_ready {id, title}, idle_full {},
## new_hero {hero_id, rarity}, monthly_card {gems}. The adapter drains it after every call.
var outbox: Array[Dictionary] = []
## Set by actions that changed the state (the adapter emits `changed` and schedules a save).
var changed_now: bool = false
## Set when a query performed the daily rollover (the adapter saves and emits `changed` later).
var changed_later: bool = false

var _def_cache: Dictionary = {}
## Debug only (never saved): the next summon's prints take these looks, one per pull in order,
## e.g. [{"flaw": "shift"}, {"holo": true}] (Game sets it for screenshots on throwaway saves).
var dev_print_looks: Array = []


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
			"seed": SeededRng.mix(now & 0x7FFFFFFF, 7919), "banners": _banner_states_default()},
		"gear": [],
		"gear_seq": 0,
		"quests": {"day": day, "progress": {}, "claimed": []},
		"shop": {"purchases": {}, "daily": {}, "day": day, "monthly_until_day": -1, "monthly_last_day": -1},
		"settings": {"sound": true, "music": true, "haptics": true, "battle_speed": 1, "auto_ultimates": true,
			"nudity": false},
		"skins": {"owned": [], "equipped": {}},
		"prints": {"seed": SeededRng.mix(now & 0x7FFFFFFF, PrintRules.SEED), "seq": 0, "ed": {}, "list": [], "total": 0,
			"showcase": []},
		"rival": RivalRules.new_state(now & 0x7FFFFFFF),
		"war": WarRules.new_state(),
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
			"shards": 0, "gear": {}, "awaken": 0})
		h.stars = clampi(int(h.stars), 1, EconomyData.MAX_STARS)
		h.level = clampi(int(h.level), 1, Progression.level_cap(int(h.stars)))
		# Awakening (Legendaries at max stars only; older saves have none).
		h.awaken = clampi(int(h.awaken), 0, Progression.max_awaken(rarity)) if int(h.stars) >= EconomyData.AWAKEN_MIN_STARS else 0
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
			heroes[id] = {"id": id, "level": 1, "stars": int(d.start_stars), "shards": 0, "gear": {}, "awaken": 0}
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
	_migrate_summon(loaded.summon)
	_migrate_prints(loaded.prints)
	_migrate_rival(loaded.rival)
	_migrate_war(loaded.war)
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
		var a := {"uid": "a%d" % slot, "hero_id": id, "side": "ally", "slot": slot,
			"level": int(h.level), "stars": int(h.stars), "stats": hero_stats(id), "is_boss": false}
		# A Legendary's awakening tier brings her legend passive and empowered ultimate (BattleSim).
		if int(h.get("awaken", 0)) > 0:
			a["awaken"] = int(h.awaken)
		allies.append(a)
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
	var souls := _war_add_souls(WarRules.SOULS_PER_WIN)
	_changed()
	return _ok({"reward": reward, "first_clear": first, "victory": true, "souls": souls})


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
	var souls := _war_add_souls(WarRules.SOULS_PER_WIN)
	_changed()
	return _ok({"reward": reward, "first_clear": true, "victory": true, "souls": souls})


# ---------------------------------------------------------------- heroes

## Owned hero entries {id, level, stars, shards, gear, awaken}, sorted by power desc, then id.
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


## Owned hero entry {id, level, stars, shards, gear, awaken} (a copy), or {} if not owned.
func hero(hero_id: String) -> Dictionary:
	if not owns(hero_id):
		return {}
	return state.heroes[hero_id].duplicate(true)


## Final stats {hp, atk, def, spd, crit} for an owned hero (level, stars, gear, awakening).
## Unowned heroes: level 1 at their starting stars, no gear.
func hero_stats(hero_id: String) -> Dictionary:
	if not owns(hero_id):
		var d := hero_def(hero_id)
		if d.is_empty():
			return {}
		return StatCalc.stats(hero_id, 1, int(d.start_stars))
	var h: Dictionary = state.heroes[hero_id]
	return StatCalc.stats(hero_id, int(h.level), int(h.stars), equipped_items(hero_id), int(h.get("awaken", 0)))


## Stats preview at another level/stars (keeps current gear). For "next level" displays.
## awaken: the awakening tier to preview, -1 = her current one.
func hero_stats_at(hero_id: String, level: int, stars: int, awaken: int = -1) -> Dictionary:
	var aw := awaken
	if aw < 0:
		aw = awaken_tier(hero_id)
	return StatCalc.stats(hero_id, level, stars, equipped_items(hero_id), aw)


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


## True when the hero can level up, star up or awaken right now (for "upgrade ready" badges).
func upgrade_ready(hero_id: String) -> bool:
	if not owns(hero_id):
		return false
	var c := level_up_cost(hero_id)
	if not c.is_empty() and _can_afford(c):
		return true
	return can_star_up(hero_id) or can_awaken(hero_id)


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


## A Legendary's awakening tier (0-3; 0 for everyone else and unowned heroes).
func awaken_tier(hero_id: String) -> int:
	return int(state.heroes[hero_id].get("awaken", 0)) if owns(hero_id) else 0


## The next awakening's cost, or {} when she can't awaken (not owned, not a Legendary, fully
## awakened): {tier, shards, dust, dust_base, shards_have, shards_used, dust_per_shard, min_stars,
## stars_ok} (Progression.awaken_cost). dust covers the base price plus any missing shards.
func awaken_cost(hero_id: String) -> Dictionary:
	if not owns(hero_id):
		return {}
	var h: Dictionary = state.heroes[hero_id]
	return Progression.awaken_cost(int(h.stars), int(h.get("awaken", 0)), int(h.shards), str(hero_def(hero_id).rarity))


func can_awaken(hero_id: String) -> bool:
	var c := awaken_cost(hero_id)
	return not c.is_empty() and bool(c.stars_ok) and currency("dust") >= int(c.dust)


## Awaken a Legendary at max stars one tier (A1 legend passive, A2 empowered ultimate, A3 Ascended).
## Result {ok, value: {awaken, unlock: "legend_passive" | "ult_bonus" | "ascended"}, error}.
func awaken(hero_id: String) -> Dictionary:
	if not owns(hero_id):
		return _err("Hero not owned")
	if not Progression.can_awaken_rarity(str(hero_def(hero_id).rarity)):
		return _err("Only Legendary heroes can awaken")
	var c := awaken_cost(hero_id)
	if c.is_empty():
		return _err("Already fully awakened")
	if not bool(c.stars_ok):
		return _err("Awakening needs %d stars" % int(c.min_stars))
	if currency("dust") < int(c.dust):
		return _err("Not enough shards or dust")
	var h: Dictionary = state.heroes[hero_id]
	h.shards = int(h.shards) - int(c.shards_used)
	_add_currency("dust", -int(c.dust))
	h.awaken = int(c.tier)
	_bump("awakenings")
	var unlock: String = ["legend_passive", "ult_bonus", "ascended"][clampi(int(h.awaken) - 1, 0, 2)]
	_notify({"type": "awaken", "hero_id": hero_id, "awaken": int(h.awaken), "unlock": unlock})
	_changed()
	return _ok({"awaken": int(h.awaken), "unlock": unlock})


## Adds a hero at level 1 and its starting stars (no-op if unknown or owned).
func add_hero(hero_id: String) -> void:
	var d := hero_def(hero_id)
	if d.is_empty() or owns(hero_id):
		return
	state.heroes[hero_id] = {"id": hero_id, "level": 1, "stars": int(d.start_stars), "shards": 0, "gear": {}, "awaken": 0}


## Adds shards; anything a maxed hero can't use becomes dust (a Legendary keeps what her
## awakenings can still use). Returns dust granted.
func _add_shards(hero_id: String, n: int) -> int:
	var h: Dictionary = state.heroes[hero_id]
	var r := Progression.add_shards(int(h.stars), int(h.shards), n, str(hero_def(hero_id).rarity), int(h.get("awaken", 0)))
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


## Best 5 owned heroes by power, guardians and strikers in front, then gear them up. The team
## always fields a guardian when one is owned: if the best 5 have none, the strongest owned
## guardian takes the place of the weakest of them.
func auto_formation() -> void:
	var ids: Array = []
	for h in owned_heroes():
		ids.append(h.id)
	var team := ids.slice(0, 5)
	var has_guardian := false
	for id in team:
		if str(hero_def(id).role) == "guardian":
			has_guardian = true
	if team.size() == 5 and not has_guardian:
		for id in ids.slice(5):
			if str(hero_def(id).role) == "guardian":
				team[4] = id
				break
	state.formation = _arrange(team)
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
#
# Five banners (data/banner.json): standard, featured, faction, wish, envoy. Each has its own
# pity. state.summon keeps {seed, total_pulls (every pull on every banner: the random stream),
# last_free_pull_day, pity (the standard banner's: the original key, so old saves carry it over),
# banners {id: {pity, pulls, lost, target, period, period_pulls}} for the other banners}.

## BannerDef for banner_id ("standard" by default) as it stands today: {id, kind, name, short,
## cost_one, cost_ten (price in `currency`), scroll_cost_one, scroll_cost_ten (0 = no scrolls),
## currency ("gems" | "gold"), rates: {rare, epic, legendary} (basis points), pity_legendary
## (0 = no pity), ten_pull_guarantee, pool (today's pool), pool_by_rarity, free_daily, pity (the
## banner's counter now), featured (hero id) + featured_bp + lost (featured banner), faction
## (faction banner), target + choices (wish banner), rotation_days, next_change_day,
## ms_until_change (featured / faction), limit_period ("day" | "week" | ""), limit_max,
## limit_left (-1 = no limit), ms_until_limit_reset}. {} if unknown.
func banner(banner_id: String = "standard") -> Dictionary:
	var b := EconomyData.banner_def(banner_id)
	if b.is_empty():
		return {}
	var day := today()
	var epoch := EconomyData.BANNER_EPOCH_DAY
	var kind := str(b.get("kind", "standard"))
	var faction := SummonRules.faction_for(b, day, epoch)
	var pool: Array = []
	for id in b.pool:
		if faction == "" or str(hero_def(str(id)).get("faction", "")) == faction:
			pool.append(str(id))
	var c1: Dictionary = b.cost_one
	var c10: Dictionary = b.cost_ten
	var cur := "gold" if c1.has("gold") else "gems"
	var out := {
		"id": b.id,
		"kind": kind,
		"name": b.name,
		"short": str(b.get("short", b.name)),
		"cost_one": int(c1.get(cur, 0)),
		"cost_ten": int(c10.get(cur, 0)),
		"scroll_cost_one": int(c1.get("scrolls", 0)),
		"scroll_cost_ten": int(c10.get("scrolls", 0)),
		"currency": cur,
		"rates": b.rates.duplicate(),
		"pity_legendary": int(b.get("pity_legendary", 0)),
		"ten_pull_guarantee": b.ten_pull_guarantee,
		"pool": pool,
		"pool_by_rarity": SummonRules.pool_by_rarity(b, faction),
		"free_daily": bool(b.get("free_daily", false)),
		"pity": pity_count(banner_id),
	}
	if kind == "featured":
		out["featured"] = SummonRules.featured_for(b, day, epoch)
		out["featured_bp"] = int(b.get("featured_bp", 5000))
		out["lost"] = bool(_bstate(banner_id).lost) if not state.is_empty() else false
	if kind == "faction":
		out["faction"] = faction
	if kind == "wish":
		out["choices"] = SummonRules.wish_choices(b)
		out["target"] = wish_target(banner_id)
	if kind == "featured" or kind == "faction":
		var days := int(b.get("rotation_days", 7 if kind == "featured" else 1))
		var next := SummonRules.next_change_day(day, epoch, days)
		out["rotation_days"] = days
		out["next_change_day"] = next
		out["ms_until_change"] = _ms_until_day(next)
	var lim: Dictionary = b.get("limit", {})
	out["limit_period"] = str(lim.get("period", ""))
	out["limit_max"] = int(lim.get("pulls", 0))
	out["limit_left"] = summon_left(banner_id)
	var reset := SummonRules.limit_resets_day(b, day, epoch)
	out["ms_until_limit_reset"] = _ms_until_day(reset) if reset >= 0 else -1
	return out


## Every banner's BannerDef, in banner.json order (the standard one first).
func banners() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for b in EconomyData.BANNERS:
		out.append(banner(str(b.id)))
	return out


## Pulls on this banner since its last Legendary (a Legendary is guaranteed when this reaches
## pity_legendary - 1). Always 0 on a banner without pity.
func pity_count(banner_id: String = "standard") -> int:
	if state.is_empty():
		return 0
	if banner_id == "standard":
		return int(state.get("summon", {}).get("pity", 0))
	if EconomyData.banner_def(banner_id).is_empty():
		return 0
	return int(_bstate(banner_id).pity)


## Pulls left in the banner's current limit period (envoy: today, wish: this week), -1 when the
## banner has no limit.
func summon_left(banner_id: String) -> int:
	var b := EconomyData.banner_def(banner_id)
	var lim: Dictionary = b.get("limit", {})
	if b.is_empty() or int(lim.get("pulls", 0)) <= 0:
		return -1
	if state.is_empty():
		return int(lim.pulls)
	var bs := _bstate(banner_id)
	var period := SummonRules.limit_period(b, today(), EconomyData.BANNER_EPOCH_DAY)
	var used := int(bs.period_pulls) if int(bs.period) == period else 0
	return maxi(0, int(lim.pulls) - used)


## The wish banner's chosen Legendary ("" until the player picks one).
func wish_target(banner_id: String = "wish") -> String:
	if state.is_empty() or EconomyData.banner_def(banner_id).is_empty():
		return ""
	return str(_bstate(banner_id).target)


## Picks the Legendary every Legendary from the wish banner will be. It can change at any time;
## the pity carries over. Result {ok, value: hero id, error}.
func set_wish_target(hero_id: String, banner_id: String = "wish") -> Dictionary:
	var b := EconomyData.banner_def(banner_id)
	if b.is_empty() or str(b.get("kind", "")) != "wish":
		return _err("Not a wish banner")
	if not SummonRules.wish_choices(b).has(hero_id):
		return _err("That hero can't be wished for")
	_bstate(banner_id).target = hero_id
	_changed()
	return _ok(hero_id)


func free_pull_available() -> bool:
	if state.is_empty():
		return false
	refresh_daily()
	return int(state.summon.last_free_pull_day) != today()


## count = 1 or 10 on banner_id (standard by default). use_free: the standard banner's daily
## free pull (count 1). Pays with scrolls first when the banner takes them, then gems (gold on
## the envoy banner). A wish needs a target; envoy and wish have pull limits.
## Result {ok, value: Array of {hero_id, rarity, is_new, shards, dust, pity (+ featured on the
## featured banner)}, error}.
func summon(count: int, use_free: bool = false, banner_id: String = "standard") -> Dictionary:
	refresh_daily()
	if count != 1 and count != 10:
		return _err("Summon 1 or 10")
	var b := EconomyData.banner_def(banner_id)
	if b.is_empty():
		return _err("Unknown banner")
	var kind := str(b.get("kind", "standard"))
	var day := today()
	var epoch := EconomyData.BANNER_EPOCH_DAY
	var opts := {}
	match kind:
		"featured":
			opts = {"featured": SummonRules.featured_for(b, day, epoch), "lost": bool(_bstate(banner_id).lost)}
		"faction":
			opts = {"faction": SummonRules.faction_for(b, day, epoch)}
		"wish":
			var tgt := wish_target(banner_id)
			if tgt == "" or not SummonRules.wish_choices(b).has(tgt):
				return _err("Choose your wish first")
			opts = {"target": tgt}
	var left := summon_left(banner_id)
	if left >= 0 and count > left:
		var per := "today" if str(b.limit.period) == "day" else "this week"
		return _err("No pulls left %s" % per if left == 0 else "Only %d pull%s left %s" % [left, "" if left == 1 else "s", per])
	if use_free:
		if not bool(b.get("free_daily", false)):
			return _err("No free summon on this banner")
		if count != 1:
			return _err("The free summon is a single pull")
		if not free_pull_available():
			return _err("Free summon already used today")
		state.summon.last_free_pull_day = today()
	else:
		var cost: Dictionary = b.cost_one if count == 1 else b.cost_ten
		var sc := int(cost.get("scrolls", 0))
		var cur := "gold" if cost.has("gold") else "gems"
		if sc > 0 and currency("scrolls") >= sc:
			_add_currency("scrolls", -sc)
		elif currency(cur) >= int(cost.get(cur, 0)):
			_add_currency(cur, -int(cost.get(cur, 0)))
		else:
			return _err("Not enough %s" % cur)
	var roll := SummonRules.pull(b, int(state.summon.seed), int(state.summon.total_pulls), pity_count(banner_id), count, opts)
	state.summon.total_pulls = int(roll.total_pulls)
	if banner_id == "standard":
		state.summon.pity = int(roll.pity)
	else:
		var bs := _bstate(banner_id)
		bs.pity = int(roll.pity)
		bs.pulls = int(bs.pulls) + count
		if roll.has("lost"):
			bs.lost = bool(roll.lost)
		if left >= 0:
			var period := SummonRules.limit_period(b, day, epoch)
			if int(bs.period) != period:
				bs.period = period
				bs.period_pulls = 0
			bs.period_pulls = int(bs.period_pulls) + count
	# Every hero comes as a numbered print of the banner's edition (cosmetic; its own random stream,
	# so the pulls above are the same with or without prints).
	var ps: Dictionary = state.prints
	var ids: Array = []
	for p in roll.results:
		ids.append(str(p.hero_id))
	var eds: Dictionary = ps.ed
	var seq0 := int(ps.seq)
	var made := PrintRules.make_prints(banner_id, ids, day, epoch, _hours_open(banner_id, day), eds.get(banner_id, {}),
		int(ps.seed), seq0)
	eds[banner_id] = made.ed
	ps.seq = seq0 + ids.size()
	var results: Array = []
	for i in roll.results.size():
		var p: Dictionary = roll.results[i]
		var r := receive_hero(str(p.hero_id))
		r["pity"] = int(p.pity)
		if p.has("featured"):
			r["featured"] = bool(p.featured)
		var pr: Dictionary = made.prints[i]
		pr["uid"] = "p%d" % (seq0 + i + 1)
		pr["day"] = day
		pr["first"] = bool(r.is_new)
		pr["from"] = ""
		_dev_print(pr, i)
		(ps.list as Array).append(pr)
		r["print"] = pr.duplicate()
		results.append(r)
	dev_print_looks.clear()
	ps.total = int(ps.total) + ids.size()
	_trim_prints()
	_bump("summons", count)
	_changed()
	return _ok(results)


## A banner's saved state (not the standard one's), created when missing.
func _bstate(banner_id: String) -> Dictionary:
	var s: Dictionary = state.summon
	if not (s.get("banners") is Dictionary):
		s["banners"] = {}
	var all: Dictionary = s.banners
	if not (all.get(banner_id) is Dictionary):
		all[banner_id] = _banner_state_default()
	return all[banner_id]


static func _banner_state_default() -> Dictionary:
	return {"pity": 0, "pulls": 0, "lost": false, "target": "", "period": -1, "period_pulls": 0}


## {banner id: state} for every banner but the standard one (its pity is summon.pity).
static func _banner_states_default() -> Dictionary:
	var out := {}
	for b in EconomyData.BANNERS:
		if str(b.id) != "standard":
			out[str(b.id)] = _banner_state_default()
	return out


## Save repair for the summon block (after the defaults merge): pity inside 0..pity_legendary - 1
## (0 without pity), counts >= 0, a wish target that is still a choice, known banners only.
func _migrate_summon(s: Dictionary) -> void:
	s.pity = clampi(int(s.pity), 0, maxi(0, int(EconomyData.BANNER.get("pity_legendary", 0)) - 1))
	s.total_pulls = maxi(0, int(s.total_pulls))
	var clean := {}
	for b in EconomyData.BANNERS:
		var id := str(b.id)
		if id == "standard":
			continue
		var bs: Dictionary = s.banners.get(id) if s.banners.get(id) is Dictionary else _banner_state_default()
		_merge_defaults(bs, _banner_state_default())
		bs.pity = clampi(int(bs.pity), 0, maxi(0, int(b.get("pity_legendary", 0)) - 1))
		bs.pulls = maxi(0, int(bs.pulls))
		bs.period_pulls = maxi(0, int(bs.period_pulls))
		if bs.target != "" and (str(b.get("kind", "")) != "wish" or not SummonRules.wish_choices(b).has(bs.target)):
			bs.target = ""
		clean[id] = bs
	s.banners = clean


## ms from now until the local midnight that starts `day`.
func _ms_until_day(day: int) -> int:
	return maxi(0, day * DAY_MS - tz_bias_ms - now_ms())


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


# ---------------------------------------------------------------- prints (cosmetic)

## Whole hours since the banner's current edition opened (local midnight of its first day).
func _hours_open(banner_id: String, day: int) -> int:
	var info := PrintRules.edition_on(banner_id, day, EconomyData.BANNER_EPOCH_DAY)
	return maxi(0, (now_ms() + tz_bias_ms - int(info.open_day) * DAY_MS) / HOUR_MS)


## Debug: gives print i of this summon the look queued in dev_print_looks (summon() clears the
## queue afterwards).
func _dev_print(pr: Dictionary, i: int) -> void:
	if i >= dev_print_looks.size() or not (dev_print_looks[i] is Dictionary):
		return
	var look: Dictionary = dev_print_looks[i]
	if look.has("flaw"):
		pr.flaw = str(look.flaw)
		pr.ink = str(PrintRules.inks()[int(pr.v) % PrintRules.inks().size()]) if pr.flaw == "swap" else ""
		if look.has("ink") and pr.flaw == "swap":
			pr.ink = str(look.ink)
	if look.has("holo"):
		pr.holo = bool(look.holo)
	if look.has("grade"):
		pr.grade = clampi(int(look.grade), 1, 10)


## Keeps the album to every notable print plus the newest plain ones (PrintRules.trim); the
## showcase only lists prints still in the album.
func _trim_prints() -> void:
	var ps: Dictionary = state.prints
	ps.list = PrintRules.trim(ps.list)
	var have := {}
	for p: Dictionary in ps.list:
		have[str(p.uid)] = true
	var sc: Array = []
	for u: Variant in ps.showcase:
		if have.has(str(u)) and not sc.has(str(u)):
			sc.append(str(u))
	ps.showcase = sc


## The album, newest first (copies). filter: "all" | "misprint" (a flaw) | "holo" | "top" (grade
## 9 or 10) | "rival" (won from the Rival) | "hero:<id>".
func prints(filter: String = "all") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if state.is_empty():
		return out
	var list: Array = state.prints.list
	for i in range(list.size() - 1, -1, -1):
		var p: Dictionary = list[i]
		var keep := true
		match filter:
			"misprint":
				keep = str(p.get("flaw", "")) != ""
			"holo":
				keep = bool(p.get("holo", false))
			"top":
				keep = int(p.get("grade", 0)) >= 9
			"rival":
				keep = str(p.get("from", "")) == "rival"
			_:
				if filter.begins_with("hero:"):
					keep = str(p.get("hero", "")) == filter.substr(5)
		if keep:
			out.append(p.duplicate())
	return out


## One album print by uid (a copy), {} if not there.
func print_by_uid(uid: String) -> Dictionary:
	for p: Dictionary in state.get("prints", {}).get("list", []):
		if str(p.get("uid", "")) == uid:
			return p.duplicate()
	return {}


## {total (every print ever received), kept (in the album), misprints, holo, top (grade 9+),
## from_rival, best_grade, best (the rarest print by PrintRules.score, {} when none)}.
func print_stats() -> Dictionary:
	var out := {"total": 0, "kept": 0, "misprints": 0, "holo": 0, "top": 0, "from_rival": 0, "best_grade": 0, "best": {}}
	if state.is_empty():
		return out
	var ps: Dictionary = state.prints
	out.total = int(ps.total)
	var best := {}
	for p: Dictionary in ps.list:
		out.kept = int(out.kept) + 1
		if str(p.get("flaw", "")) != "":
			out.misprints = int(out.misprints) + 1
		if bool(p.get("holo", false)):
			out.holo = int(out.holo) + 1
		if int(p.get("grade", 0)) >= 9:
			out.top = int(out.top) + 1
		if str(p.get("from", "")) == "rival":
			out.from_rival = int(out.from_rival) + 1
		out.best_grade = maxi(int(out.best_grade), int(p.get("grade", 0)))
		if best.is_empty() or PrintRules.score(p) > PrintRules.score(best):
			best = p
	out.best = best.duplicate()
	return out


## Prints shown on the profile: up to showcase_max album uids, in order. Unknown or repeated uids
## are refused. Result {ok, value: the showcase uids, error}.
func set_showcase(uids: Array) -> Dictionary:
	if uids.size() > PrintRules.SHOWCASE_MAX:
		return _err("Only %d prints fit the showcase" % PrintRules.SHOWCASE_MAX)
	var clean: Array = []
	for u: Variant in uids:
		var s := str(u)
		if clean.has(s):
			return _err("That print is already in the showcase")
		if print_by_uid(s).is_empty():
			return _err("Unknown print")
		clean.append(s)
	state.prints.showcase = clean
	_changed()
	return _ok(clean.duplicate())


## The showcased prints (copies), in showcase order.
func showcase() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if state.is_empty():
		return out
	for u: Variant in state.prints.showcase:
		var p := print_by_uid(str(u))
		if not p.is_empty():
			out.append(p)
	return out


## Save repair for the prints block (after the defaults merge): known heroes only, sane numbers,
## unique uids, a showcase of album uids.
func _migrate_prints(ps: Dictionary) -> void:
	ps.seq = maxi(0, int(ps.seq))
	ps.total = maxi(0, int(ps.total))
	var eds := {}
	for bid: Variant in ps.ed:
		var e: Variant = ps.ed[bid]
		if e is Dictionary and not EconomyData.banner_def(str(bid)).is_empty():
			eds[str(bid)] = {"e": int(e.get("e", 0)), "n": maxi(0, int(e.get("n", 0)))}
	ps.ed = eds
	var list: Array = []
	var seen := {}
	for p: Variant in ps.list:
		if not (p is Dictionary) or HeroData.get_def(str(p.get("hero", ""))).is_empty():
			continue
		var d: Dictionary = p
		var uid := str(d.get("uid", ""))
		if uid == "" or seen.has(uid):
			continue
		seen[uid] = true
		_merge_defaults(d, {"banner": "standard", "edition": 1, "printing": 1, "serial": 1, "run": 1, "flaw": "", "ink": "",
			"holo": false, "grade": 5, "v": 0, "day": 0, "first": false, "from": ""})
		d.uid = uid
		if str(d.flaw) != "" and PrintRules.flaw_def(str(d.flaw)).is_empty():
			d.flaw = ""
		d.grade = clampi(int(d.grade), 1, 10)
		list.append(d)
	ps.list = list
	ps.total = maxi(int(ps.total), list.size())
	_merge_defaults(ps, {"showcase": []})
	var sc: Array = []
	for u: Variant in ps.showcase:
		if seen.has(str(u)) and not sc.has(str(u)) and sc.size() < PrintRules.SHOWCASE_MAX:
			sc.append(str(u))
	ps.showcase = sc


# ---------------------------------------------------------------- the Rival (Rue)

## She shows up once the campaign has `unlock_cleared` stages cleared (data/rival.json).
func rival_unlocked() -> bool:
	return cleared_count() >= RivalRules.UNLOCK_CLEARED


## What she reads off the player's team: {avg (formation average level), best (best stars),
## main (the faction most of the formation belongs to, "" with none)}.
func _rival_ctx() -> Dictionary:
	var lv := 0
	var n := 0
	var best := 1
	var counts := {}
	for id in formation():
		if id == "" or not owns(id):
			continue
		var h: Dictionary = state.heroes[id]
		lv += int(h.level)
		n += 1
		best = maxi(best, int(h.stars))
		var fac := str(hero_def(id).faction)
		counts[fac] = int(counts.get(fac, 0)) + 1
	var main := ""
	var top := 0
	for f in BattleSim.FACTIONS:
		if int(counts.get(f, 0)) > top:
			top = int(counts.get(f, 0))
			main = f
	return {"avg": lv / n if n > 0 else 1, "best": best, "main": main}


## Simulates her days up to today (once she is unlocked). A query may do it, like the daily
## rollover: the adapter saves and emits `changed` later.
func _rival_sync() -> void:
	if state.is_empty() or not rival_unlocked():
		return
	var owned := {}
	for id in state.heroes:
		owned[str(id)] = true
	var rs: Dictionary = state.rival
	var before := int(rs.day)
	var was_empty := (rs.heroes as Dictionary).is_empty()
	RivalRules.catch_up(rs, today(), EconomyData.BANNER_EPOCH_DAY, owned)
	if int(rs.day) != before or was_empty:
		changed_later = true


## Her team today: {team (enemy entries in slot order), level, countering, prefer, main}.
func _rival_team() -> Dictionary:
	var rs: Dictionary = state.rival
	var ctx := _rival_ctx()
	var day := today()
	var countering := RivalRules.counters(int(rs.fights), str(ctx.main))
	var prefer := RivalRules.counter_faction(str(ctx.main)) if countering else ""
	var lv := RivalRules.level_on(int(ctx.avg), day, countering)
	return {"team": RivalRules.team(rs.heroes, int(ctx.best), lv, prefer), "level": lv, "countering": countering,
		"prefer": prefer, "main": str(ctx.main)}


## The Rival as the UI shows her: {name, title, unlocked, unlock_cleared, met, team [{hero_id,
## level, stars, slot, power, ...}], ace (her strongest hero), level, roster [{hero_id, stars,
## dupes}], power (her team as echoes), your_power, record {wins, losses, fights}, cleared,
## tower_best, pulls, banner (today's), feed (newest first: {n, day, type, hero, flaw, ink, line}),
## new_feed (entries since rival_seen), prints (her kept prints, best first), tags {you, her, v},
## haul (a first win today pays it: {gems, gold, dust}), haul_ready, haul_print (the print it
## would bring, {} when none), counter {faction, main} ("" when she isn't counter-picking), line,
## line_kind}.
func rival() -> Dictionary:
	var out := {"name": RivalRules.NAME, "title": RivalRules.TITLE, "unlocked": rival_unlocked(),
		"unlock_cleared": RivalRules.UNLOCK_CLEARED}
	if state.is_empty() or not rival_unlocked():
		return out
	_rival_sync()
	var rs: Dictionary = state.rival
	var day := today()
	var tm := _rival_team()
	var team: Array = tm.team
	var power := 0
	for e: Dictionary in team:
		power += int(e.power)
	var roster: Array = []
	var best := int(_rival_ctx().best)
	for id in HeroData.ids():
		if (rs.heroes as Dictionary).has(id):
			roster.append({"hero_id": id, "dupes": int(rs.heroes[id]), "stars": RivalRules.stars_for(id, int(rs.heroes[id]), best)})
	var countering := bool(tm.countering)
	var fills := {"you": str(state.get("player_name", "you")), "faction": str(tm.prefer).capitalize(),
		"main": str(tm.main).capitalize()}
	var kind := "idle"
	var ln := ""
	var feed: Array = rs.feed
	if not bool(rs.met):
		kind = "intro"
	elif bool(rs.tag_you):
		kind = "win"
	elif bool(rs.tag_her):
		kind = "lose"
	elif countering:
		kind = "counter"
	elif not feed.is_empty() and int((feed[0] as Dictionary).day) == day:
		kind = str(feed[0].type)
		ln = str(feed[0].line)
	if ln == "":
		ln = RivalRules.line(kind, int(rs.seed), day, int(rs.fights), fills)
	out.merge({
		"met": bool(rs.met),
		"team": team,
		"ace": RivalRules.ace(team),
		"level": int(tm.level),
		"roster": roster,
		"power": power,
		"your_power": team_power(),
		"record": {"wins": int(rs.wins), "losses": int(rs.losses), "fights": int(rs.fights)},
		"cleared": RivalRules.cleared_on(cleared_count(), day),
		"tower_best": RivalRules.tower_on(tower_best(), day),
		"pulls": int(rs.pulls),
		"banner": RivalRules.banner_on(day, EconomyData.BANNER_EPOCH_DAY),
		"feed": feed.duplicate(true),
		"new_feed": maxi(0, int(rs.feed_seq) - int(rs.seen)),
		"prints": (rs.prints as Array).duplicate(true),
		"tags": {"you": bool(rs.tag_you), "her": bool(rs.tag_her), "v": int(rs.tag_v)},
		"haul": RivalRules.haul(cleared_count()),
		"haul_ready": int(rs.haul_day) != day,
		"haul_print": RivalRules.best_untaken(rs).duplicate(),
		"counter": {"faction": str(tm.prefer), "main": str(tm.main)} if countering else {"faction": "", "main": ""},
		"line": ln,
		"line_kind": kind,
	}, true)
	return out


## True when the Lobby should light her label: a haul is waiting or her feed has news.
func rival_alert() -> bool:
	if state.is_empty() or not rival_unlocked():
		return false
	_rival_sync()
	var rs: Dictionary = state.rival
	return int(rs.haul_day) != today() or int(rs.feed_seq) > int(rs.seen)


## The first visit: she introduces herself. Result {ok, value: {line}, error}.
func rival_meet() -> Dictionary:
	if not rival_unlocked():
		return _err("Clear stage %d first" % RivalRules.UNLOCK_CLEARED)
	_rival_sync()
	var rs: Dictionary = state.rival
	var ln := RivalRules.line("intro", int(rs.seed), today(), 0, {"you": str(state.get("player_name", "you"))})
	rs.met = true
	_changed()
	return _ok({"line": ln})


## The player has read her feed (the Lobby light goes out until something new happens).
func rival_seen() -> void:
	if state.is_empty() or not rival_unlocked():
		return
	_rival_sync()
	var rs: Dictionary = state.rival
	if int(rs.seen) != int(rs.feed_seq):
		rs.seen = int(rs.feed_seq)
		_changed()


## BattleSetup for the player's formation vs her team (echoes at strength_bp). Each call is a
## new attempt with its own seed: mix(rng_seed + 900001, battles_started). {} while locked.
func rival_battle_setup() -> Dictionary:
	if not rival_unlocked():
		return {}
	_rival_sync()
	var tm := _rival_team()
	var attempt := counter("battles_started")
	state.counters["battles_started"] = attempt + 1
	return {
		"allies": _ally_setups(),
		"enemies": _enemy_setups(tm.team),
		"seed": SeededRng.mix(int(state.rng_seed) + 900001, attempt),
		"rival": true,
		"is_boss": false,
		"background": RivalRules.background(today()),
	}


## Call after a fight with her. A win records it, tags her poster, clears her tag on yours, and the
## first win of a day pays her haul plus the best print you have not taken from her (copied into
## the album with from "rival"). A loss records it and lets her tag your Lobby poster; it costs
## nothing. Result {ok, value: {victory, reward, print ({} when none), haul (bool), line, record}, error}.
func complete_rival(outcome: Dictionary) -> Dictionary:
	if not rival_unlocked():
		return _err("Clear stage %d first" % RivalRules.UNLOCK_CLEARED)
	_rival_sync()
	var rs: Dictionary = state.rival
	var day := today()
	var victory := bool(outcome.get("victory", false))
	rs.fights = int(rs.fights) + 1
	rs.tag_v = SeededRng.mix(int(rs.seed), int(rs.fights)) % 1000
	var reward := {}
	var won_print := {}
	var paid := false
	var fills := {"you": str(state.get("player_name", "you"))}
	var ln := ""
	if victory:
		_bump("battles_won")
		rs.wins = int(rs.wins) + 1
		rs.tag_her = true
		rs.tag_you = false
		if int(rs.haul_day) != day:
			rs.haul_day = day
			paid = true
			reward = grant(RivalRules.haul(cleared_count()))
			var best := RivalRules.best_untaken(rs)
			if not best.is_empty():
				best.taken = true
				won_print = best.duplicate()
				won_print.erase("taken")
				won_print.erase("n")
				won_print["from"] = "rival"
				won_print["day"] = day
				won_print["first"] = false
				var ps: Dictionary = state.prints
				(ps.list as Array).append(won_print.duplicate())
				ps.total = int(ps.total) + 1
				_trim_prints()
		ln = RivalRules.line("lose", int(rs.seed), day, int(rs.fights), fills)
	else:
		_bump("battles_lost")
		rs.losses = int(rs.losses) + 1
		rs.tag_you = true
		rs.tag_her = false
		ln = RivalRules.line("win", int(rs.seed), day, int(rs.fights), fills)
	_changed()
	return _ok({"victory": victory, "reward": reward, "print": won_print, "haul": paid, "line": ln,
		"record": {"wins": int(rs.wins), "losses": int(rs.losses), "fights": int(rs.fights)}})


## Save repair for the rival block (after the defaults merge): known heroes only, sane numbers,
## lists of the right shape.
# ---------------------------------------------------------------- the War for Souls (the front)

## Open once the campaign has `unlock_cleared` stages cleared (data/war.json).
func war_unlocked() -> bool:
	return cleared_count() >= WarRules.UNLOCK_CLEARED


## Picks the player's side ("heaven" | "hell"). Allowed once; afterwards only at a week's start
## (no souls logged this week yet), so a side can't be switched mid-week.
func war_choose_side(side: String) -> Dictionary:
	if not WarRules.SIDES.has(side):
		return _err("Unknown side")
	if not war_unlocked():
		return _err("The front opens later in the campaign")
	var ws: Dictionary = state.war
	if str(ws.side) == side:
		return _ok({"side": side})
	if str(ws.side) != "" and _war_week_souls() > 0:
		return _err("You can change sides when the next week starts")
	ws.side = side
	_changed()
	return _ok({"side": side})


## The sector the player's souls go to.
func war_set_focus(sector: int) -> Dictionary:
	if sector < 0 or sector >= WarRules.sector_count():
		return _err("Unknown sector")
	state.war.focus = sector
	_changed()
	return _ok({"focus": sector})


## Souls into the focused sector today (only with a side chosen). Returns the souls sent (0 = none).
func _war_add_souls(n: int) -> int:
	var ws: Dictionary = state.war
	if str(ws.side) == "" or n <= 0 or not war_unlocked():
		return 0
	var day := today()
	var dk := str(day)
	if not (ws.log as Dictionary).has(dk):
		ws.log[dk] = {}
	var sk := str(int(ws.focus))
	ws.log[dk][sk] = int((ws.log[dk] as Dictionary).get(sk, 0)) + n
	ws.souls_total = int(ws.souls_total) + n
	# Keep only the days a claim can still read (this week and the last).
	var keep_from := day - WarRules.LOG_DAYS
	for k: Variant in (ws.log as Dictionary).keys():
		if int(str(k)) < keep_from:
			ws.log.erase(k)
	return n


## Souls the player sent this week.
func _war_week_souls() -> int:
	var ws: Dictionary = state.war
	var d0 := WarRules.week_start(WarRules.week_of(today()))
	var n := 0
	for k: Variant in (ws.log as Dictionary).keys():
		if int(str(k)) >= d0:
			for s: Variant in (ws.log[k] as Dictionary).values():
				n += int(s)
	return n


## The front view: {unlocked, name, side, side_name, focus, sectors [{id, name, control}], standing,
## week, day_in_week (1-7), days_left, souls_today, souls_week, souls_total, souls_per_win,
## claim: {week, won, held, reward} or {} (last week's result, unclaimed)}.
func war() -> Dictionary:
	var ws: Dictionary = state.war
	var day := today()
	var week := WarRules.week_of(day)
	var side := str(ws.side)
	var c := WarRules.control(week, day, ws.log, side)
	var sectors: Array = []
	for i in WarRules.sector_count():
		var sd: Dictionary = WarRules.SECTORS[i]
		sectors.append({"id": str(sd.id), "name": str(sd.name), "control": c[i]})
	var today_souls := 0
	for s: Variant in (ws.log.get(str(day), {}) as Dictionary).values():
		today_souls += int(s)
	return {"unlocked": war_unlocked(), "name": WarRules.NAME, "side": side, "side_name": WarRules.side_name(side),
		"focus": int(ws.focus), "sectors": sectors, "standing": WarRules.standing(c), "week": week,
		"day_in_week": day - WarRules.week_start(week) + 1, "days_left": WarRules.week_start(week) + WarRules.WEEK_DAYS - day,
		"souls_today": today_souls, "souls_week": _war_week_souls(), "souls_total": int(ws.souls_total),
		"souls_per_win": WarRules.SOULS_PER_WIN, "claim": _war_claimable(), "champion": _champ_view()}


## This week's Champion for the player's side: set up on the first look of a week (her level from
## the formation then, so it holds all week); the day's tries reset at midnight.
func _champ_sync() -> Dictionary:
	var ws: Dictionary = state.war
	var side := str(ws.side)
	var c: Dictionary = ws.champ
	if side == "":
		return c
	var day := today()
	var week := WarRules.week_of(day)
	var hero := WarRules.champion_for(week, side)
	if int(c.week) != week or str(c.hero) != hero:
		var lv := WarRules.champion_level(int(_rival_ctx().avg))
		c.week = week
		c.hero = hero
		c.level = lv
		# Her max HP as the battle builds her (passives included): a sim with her alone.
		c.hp = int(BattleSim.new({"allies": [], "enemies": [_champ_enemy(hero, lv)], "seed": 1}).unit("e0").max_hp)
		c.damage = 0
		c.tiers = []
		c.day = day
		c.tries = 0
	if int(c.day) != day:
		c.day = day
		c.tries = 0
	return c


## The Champion's UnitSetup: alone in slot 0 as a boss, StatCalc's stats with HP and ATK scaled.
func _champ_enemy(hero: String, level: int) -> Dictionary:
	return {"uid": "e0", "hero_id": hero, "side": "enemy", "slot": 0, "level": level,
		"stars": WarRules.CHAMP_STARS, "stats": WarRules.champion_stats(hero, level), "is_boss": true}


## {hero, name, title, level, hp, damage, pct (0-100), tries_left, tiers [{pct, reward, done}]} or {}.
func _champ_view() -> Dictionary:
	if str(state.war.side) == "":
		return {}
	var c := _champ_sync()
	var tiers: Array = []
	for i in WarRules.CHAMP_TIERS.size():
		var t: Dictionary = WarRules.CHAMP_TIERS[i]
		tiers.append({"pct": int(t.pct), "reward": t.reward, "done": (c.tiers as Array).has(i)})
	var d := hero_def(str(c.hero))
	return {"hero": str(c.hero), "name": str(d.get("name", c.hero)), "title": str(d.get("title", "")), "level": int(c.level),
		"hp": int(c.hp), "damage": int(c.damage), "pct": mini(100, int(c.damage) * 100 / maxi(1, int(c.hp))),
		"tries_left": maxi(0, WarRules.CHAMP_TRIES - int(c.tries)), "tiers": tiers}


## BattleSetup against the Champion ({} without a side or tries left today): the formation vs her
## alone as a boss, her HP and ATK scaled, max_ms the champion's.
func war_champion_setup() -> Dictionary:
	if str(state.war.side) == "" or not war_unlocked():
		return {}
	var c := _champ_sync()
	if int(c.tries) >= WarRules.CHAMP_TRIES:
		return {}
	var attempt := counter("battles_started")
	state.counters["battles_started"] = attempt + 1
	var hero := str(c.hero)
	return {
		"allies": _ally_setups(),
		"enemies": [_champ_enemy(hero, int(c.level))],
		"seed": SeededRng.mix(int(state.rng_seed) + 700001, attempt),
		"max_ms": WarRules.CHAMP_MAX_MS,
		"champion": true,
		"is_boss": true,
		"background": "chapter-5",
	}


## After a Champion fight: one try used, the damage the team dealt is added to the week's total and
## every tier newly reached pays at once. Result {ok, value: {damage, total, pct, reward, tiers}, error}.
func complete_champion(outcome: Dictionary) -> Dictionary:
	if str(state.war.side) == "":
		return _err("Pick a side first")
	var c := _champ_sync()
	if int(c.tries) >= WarRules.CHAMP_TRIES:
		return _err("No tries left today")
	c.tries = int(c.tries) + 1
	var dmg := 0
	var dd: Variant = outcome.get("damage_dealt", {})
	if dd is Dictionary:
		for uid: Variant in dd:
			if str(uid).begins_with("a"):
				dmg += maxi(0, int(dd[uid]))
	c.damage = int(c.damage) + dmg
	var got := {}
	var reached: Array[int] = []
	for i in WarRules.tiers_reached(int(c.hp), int(c.damage)):
		if not (c.tiers as Array).has(i):
			(c.tiers as Array).append(i)
			reached.append(i)
			var r := grant((WarRules.CHAMP_TIERS[i] as Dictionary).reward)
			for k: Variant in r:
				got[k] = int(got.get(k, 0)) + int(r[k])
	_bump("champion_fights")
	_changed()
	return _ok({"damage": dmg, "total": int(c.damage), "pct": mini(100, int(c.damage) * 100 / maxi(1, int(c.hp))),
		"reward": got, "tiers": reached})


## Last week's result for the player, when they fought in it and haven't claimed it.
func _war_claimable() -> Dictionary:
	var ws: Dictionary = state.war
	var side := str(ws.side)
	if side == "":
		return {}
	var last := WarRules.week_of(today()) - 1
	if int(ws.claimed_week) >= last:
		return {}
	var d0 := WarRules.week_start(last)
	var fought := false
	for k: Variant in (ws.log as Dictionary).keys():
		var d := int(str(k))
		if d >= d0 and d < d0 + WarRules.WEEK_DAYS:
			fought = true
	if not fought:
		return {}
	var c := WarRules.control(last, d0 + WarRules.WEEK_DAYS - 1, ws.log, side)
	var st := WarRules.standing(c)
	var won := str(st.winner) == side
	var held := int(st[side])
	return {"week": last, "won": won, "held": held, "winner": str(st.winner), "reward": WarRules.reward(won, held)}


## Claims last week's war reward. Result {ok, value: {reward, won, held}, error}.
func war_claim() -> Dictionary:
	var cl := _war_claimable()
	if cl.is_empty():
		return _err("Nothing to claim")
	state.war.claimed_week = int(cl.week)
	var got := grant(cl.reward)
	_changed()
	return _ok({"reward": got, "won": cl.won, "held": cl.held, "winner": cl.winner})


func _migrate_war(ws: Dictionary) -> void:
	if not WarRules.SIDES.has(str(ws.side)):
		ws.side = ""
	ws.focus = clampi(int(ws.focus), 0, WarRules.sector_count() - 1)
	var log := {}
	if ws.log is Dictionary:
		for k: Variant in ws.log:
			if str(k).is_valid_int() and ws.log[k] is Dictionary:
				var dl := {}
				for s: Variant in ws.log[k]:
					var si := int(str(s))
					if str(s).is_valid_int() and si >= 0 and si < WarRules.sector_count():
						dl[str(si)] = maxi(0, int(ws.log[k][s]))
				log[str(int(str(k)))] = dl
	ws.log = log
	ws.claimed_week = int(ws.claimed_week)
	ws.souls_total = maxi(0, int(ws.souls_total))
	ws.seen_week = int(ws.seen_week)
	var c: Dictionary = ws.champ
	if HeroData.get_def(str(c.hero)).is_empty():
		c.hero = ""
		c.week = -1000000
	for k: String in ["level", "hp", "damage", "tries"]:
		c[k] = maxi(0, int(c[k]))
	var tiers: Array = []
	if c.tiers is Array:
		for v: Variant in c.tiers:
			var i := int(v)
			if i >= 0 and i < WarRules.CHAMP_TIERS.size() and not tiers.has(i):
				tiers.append(i)
	c.tiers = tiers


func _migrate_rival(rs: Dictionary) -> void:
	var heroes := {}
	for id: Variant in rs.heroes:
		if not HeroData.get_def(str(id)).is_empty():
			heroes[str(id)] = maxi(0, int(rs.heroes[id]))
	rs.heroes = heroes
	for k: String in ["pulls", "print_seq", "feed_seq", "seen", "wins", "losses", "fights"]:
		rs[k] = maxi(0, int(rs[k]))
	rs.seen = mini(int(rs.seen), int(rs.feed_seq))
	var pity := {}
	for bid: Variant in rs.pity:
		if not EconomyData.banner_def(str(bid)).is_empty():
			pity[str(bid)] = clampi(int(rs.pity[bid]), 0, maxi(0, int(EconomyData.banner_def(str(bid)).get("pity_legendary", 0)) - 1))
	rs.pity = pity
	var eds := {}
	for bid: Variant in rs.ed:
		var e: Variant = rs.ed[bid]
		if e is Dictionary and not EconomyData.banner_def(str(bid)).is_empty():
			eds[str(bid)] = {"e": int(e.get("e", 0)), "n": maxi(0, int(e.get("n", 0)))}
	rs.ed = eds
	var prints: Array = []
	for p: Variant in rs.prints:
		if p is Dictionary and not HeroData.get_def(str(p.get("hero", ""))).is_empty() and str(p.get("uid", "")) != "":
			prints.append(p)
	rs.prints = prints
	var feed: Array = []
	for e: Variant in rs.feed:
		if e is Dictionary and feed.size() < RivalRules.FEED_MAX:
			feed.append(e)
	rs.feed = feed


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


## Debug (throwaway saves; Game checks): a Legendary at max stars and awakening tier `tier` (0-3),
## holding `shards` shards when >= 0 (screenshots of the awakening).
func dev_set_awaken(hero_id: String, tier: int, shards: int = -1) -> void:
	var rarity := str(hero_def(hero_id).get("rarity", ""))
	if not Progression.can_awaken_rarity(rarity):
		return
	add_hero(hero_id)
	var h: Dictionary = state.heroes[hero_id]
	h.stars = EconomyData.MAX_STARS
	h.awaken = clampi(tier, 0, Progression.max_awaken(rarity))
	if shards >= 0:
		h.shards = shards
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
		"argentiel": [38, 4, 16], "sanariel": [34, 4, 9], "rimelle": [30, 3, 12], "avienne": [32, 3, 20],
		"cirella": [28, 3, 7], "ferrael": [36, 4, 24], "verdelle": [22, 2, 11], "isobel": [26, 3, 15],
		"halcia": [30, 3, 4], "drezza": [36, 4, 6], "zecchina": [32, 3, 14], "torqua": [30, 3, 18],
		"sigilla": [28, 3, 10], "carmesa": [34, 4, 5], "thrasha": [24, 2, 26], "kindra": [20, 2, 12],
		"cordia": [27, 3, 8], "nadira": [40, 4, 12], "gantra": [33, 3, 3], "severine": [35, 4, 20],
		"benthe": [29, 3, 9], "seyra": [31, 3, 16], "rivette": [26, 2, 22], "vandra": [23, 2, 7],
		"ombre": [37, 4, 28],
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
	# The other banners mid-way too: a lost 50/50 (the next Legendary is the featured one), a wish
	# picked with 10 of the week's pulls used, 3 envoy draws today.
	var fb := _bstate("featured")
	fb.merge({"pity": 41, "pulls": 40, "lost": true}, true)
	_bstate("faction").merge({"pity": 12, "pulls": 12}, true)
	var wb := _bstate("wish")
	wb.merge({"pity": 18, "pulls": 18, "target": "noctaire", "period_pulls": 10,
		"period": SummonRules.limit_period(EconomyData.banner_def("wish"), today(), EconomyData.BANNER_EPOCH_DAY)}, true)
	_bstate("envoy").merge({"pulls": 10, "period": today(), "period_pulls": 3}, true)
	state.counters = {"battles_won": 14, "summons": 120, "stages_cleared": 12, "level_ups": 500}
	_make_rich_prints()
	# Rue: met, a week of her pulls to catch up on, three fights (so she counter-picks), you won last.
	var rs: Dictionary = state.rival
	rs.merge({"met": true, "day": today() - RivalRules.CATCH_UP_DAYS, "wins": 2, "losses": 1, "fights": 3,
		"tag_her": true, "tag_v": 417}, true)
	_changed()


## --rich album: 120 pulls' worth of prints (the summon counters above), every flaw and a holo or
## two among them so the album and the profile have something to show.
func _make_rich_prints() -> void:
	var ps: Dictionary = state.prints
	var ids: Array = []
	for id in HeroData.ids():
		ids.append(id)
	var day := today()
	var banners := ["standard", "featured", "faction", "standard", "wish", "envoy"]
	var list: Array = []
	var n := 0
	for k in 12:
		var bid: String = banners[k % banners.size()]
		var pull: Array = []
		for j in 10:
			pull.append(ids[(k * 7 + j * 3) % ids.size()])
		var made := PrintRules.make_prints(bid, pull, day - 30 + k * 2, EconomyData.BANNER_EPOCH_DAY, 6 + k * 13,
			(ps.ed as Dictionary).get(bid, {}), int(ps.seed), n)
		ps.ed[bid] = made.ed
		for p: Dictionary in made.prints:
			n += 1
			p["uid"] = "p%d" % n
			p["day"] = day - 30 + k * 2
			p["first"] = n <= ids.size()
			p["from"] = ""
			list.append(p)
	var looks := [[7, {"flaw": "shift"}], [19, {"flaw": "swap", "ink": "cyan", "holo": true}], [33, {"flaw": "ghost"}],
		[48, {"flaw": "double", "grade": 10}], [61, {"flaw": "flood"}], [77, {"holo": true, "grade": 10}],
		[90, {"flaw": "swap", "ink": "gold"}], [104, {"flaw": "shift", "holo": true}], [115, {"grade": 10}]]
	for lk: Array in looks:
		var p: Dictionary = list[int(lk[0])]
		var look: Dictionary = lk[1]
		if look.has("flaw"):
			p.flaw = str(look.flaw)
			p.ink = str(look.get("ink", "")) if p.flaw == "swap" else ""
		if look.has("holo"):
			p.holo = bool(look.holo)
		if look.has("grade"):
			p.grade = int(look.grade)
	ps.list = list
	ps.seq = n
	ps.total = n
	_trim_prints()
	ps.showcase = [str(list[48].uid), str(list[19].uid), str(list[77].uid)]


# ---------------------------------------------------------------- helpers

func _ok(value: Variant = null) -> Dictionary:
	return {"ok": true, "value": value, "error": ""}


func _err(msg: String) -> Dictionary:
	return {"ok": false, "value": null, "error": msg}
