extends Node
## Autoload "Game": the single API the UI talks to. Owns player state, save/load and
## all rules (idle, campaign, summon, progression, quests, shop).
##
## CONTRACT (see docs/dev/architecture.md): method names, arguments and return shapes
## below are used by the UI. Add methods freely; do not rename or remove these.
## All rules live here or in res://src/core/*.gd helpers. The UI never edits `state`
## directly. It calls methods and listens to `changed`.
##
## The script also works when instantiated directly (tests do
## `preload("res://src/core/game.gd").new()`), so it must not rely on being in the tree
## for logic. Set `now_override_ms` and `save_path` in tests.
##
## Numbers and formulas: src/data/economy.gd, documented in docs/dev/economy-v1.md.

## Emitted after any state change (UI refreshes on this).
signal changed
## Emitted for one-shot feedback the UI may toast, e.g. {"type": "quest_ready", "id": ...}
## Types: level_up {hero_id, level}, star_up {hero_id, stars, passive?}, quest_ready {id, title},
## idle_full {}, new_hero {hero_id, rarity}, monthly_card {gems}.
signal notify(event: Dictionary)

const SAVE_VERSION := 1
const TEST_SAVE_PATH := "user://test_save.json"
const CURRENCIES: Array[String] = ["gold", "hero_exp", "gems", "scrolls", "dust"]
const AUTOSAVE_DELAY_MS := 1500
const DAY_MS := 86400000
const HOUR_MS := 3600000

var state: Dictionary = {}
## Tests: fixed clock in ms. -1 = use real time.
var now_override_ms: int = -1
## Where the save lives. Empty string = don't persist (tests).
var save_path: String = "user://save.json"
## Local time zone offset used for daily resets (tests set 0).
var tz_bias_ms: int = 0

var _def_cache: Dictionary = {}
var _dirty: bool = false
var _dirty_at: int = 0
var _poll_accum: float = 0.0


func _init() -> void:
	var tz: Dictionary = Time.get_time_zone_from_system()
	tz_bias_ms = int(tz.get("bias", 0)) * 60000


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--fresh") or args.has("--rich"):
		# Throwaway save: never touch the real one.
		save_path = TEST_SAVE_PATH
		_delete_save_file()
		if args.has("--rich"):
			make_rich_state()
		else:
			new_game()
		save()
	else:
		load_or_create()


func _process(delta: float) -> void:
	if _dirty and Time.get_ticks_msec() - _dirty_at >= AUTOSAVE_DELAY_MS:
		save()
	_poll_accum += delta
	if _poll_accum >= 2.0:
		_poll_accum = 0.0
		if not state.is_empty():
			_refresh_daily()
			_check_idle_full()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_CLOSE_REQUEST:
			if not state.is_empty():
				save()
		NOTIFICATION_APPLICATION_RESUMED, NOTIFICATION_APPLICATION_FOCUS_IN:
			if not state.is_empty():
				_refresh_daily()
				_check_idle_full()
				changed.emit()


# ---------------------------------------------------------------- time / save

## Current time in ms (real clock + state.dev_time_offset, or now_override_ms).
func now_ms() -> int:
	var offset: int = int(state.get("dev_time_offset", 0))
	if now_override_ms >= 0:
		return now_override_ms + offset
	return int(Time.get_unix_time_from_system() * 1000.0) + offset


## Local day number (days since epoch in the player's time zone). Resets at local midnight.
func today() -> int:
	return day_of(now_ms())


func day_of(ms: int) -> int:
	var x := ms + tz_bias_ms
	if x >= 0:
		return x / DAY_MS
	return -((-x - 1) / DAY_MS) - 1


## ms until the next local midnight (for "resets in" labels).
func ms_until_reset() -> int:
	return (today() + 1) * DAY_MS - tz_bias_ms - now_ms()


func load_or_create() -> void:
	if save_path == "" or not FileAccess.file_exists(save_path):
		new_game()
		save()
		return
	var text := FileAccess.get_file_as_string(save_path)
	var json := JSON.new()
	var err := json.parse(text)
	var data: Variant = json.data if err == OK else null
	if not (data is Dictionary) or not (data as Dictionary).has("version"):
		_backup_corrupt(text)
		new_game()
		save()
		return
	state = migrate(intify(data))
	_refresh_daily()
	changed.emit()


func new_game() -> void:
	state = default_state()
	for id in EconomyData.STARTER_HEROES:
		_add_hero(id)
	auto_formation()
	_refresh_daily()
	_changed()


func save() -> void:
	_dirty = false
	if save_path == "" or state.is_empty():
		return
	var tmp := save_path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("Game.save: cannot write %s" % tmp)
		return
	f.store_string(JSON.stringify(state))
	f.close()
	var err := DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(save_path))
	if err != OK:
		# Fallback: write in place.
		var f2 := FileAccess.open(save_path, FileAccess.WRITE)
		if f2:
			f2.store_string(JSON.stringify(state))
			f2.close()


func reset_save() -> void:
	_delete_save_file()
	new_game()
	save()


## The default (brand new) state. Also the template for defaults-merge on load.
func default_state() -> Dictionary:
	var now := now_ms()
	var day := day_of(now)
	return {
		"version": SAVE_VERSION,
		"created_at": now,
		"player_name": "Envoy",
		"currencies": EconomyData.START_CURRENCIES.duplicate(),
		"heroes": {},
		"formation": ["", "", "", "", ""],
		"campaign": {"cleared": 0},
		"idle": {"last_claim_at": now, "quick_claims_used": 0, "quick_claim_day": day,
			"carry": {}, "gear_ms": 0, "full_notified": false},
		"summon": {"pity": 0, "total_pulls": 0, "last_free_pull_day": -1,
			"seed": SeededRng.mix(now & 0x7FFFFFFF, 7919)},
		"gear": [],
		"gear_seq": 0,
		"quests": {"day": day, "progress": {}, "claimed": []},
		"shop": {"purchases": {}, "daily": {}, "day": day, "monthly_until_day": -1, "monthly_last_day": -1},
		"settings": {"sound": true, "music": true, "haptics": true, "battle_speed": 1, "auto_ultimates": true},
		"counters": {},
		"dev_time_offset": 0,
		"rng_seed": SeededRng.mix(now & 0x7FFFFFFF, 104729),
	}


## Convert JSON floats back to ints (all game numbers are ints).
static func intify(v: Variant) -> Variant:
	if v is float:
		var f: float = v
		if is_finite(f) and f == floorf(f) and absf(f) < 9.0e15:
			return int(f)
		return f
	if v is Dictionary:
		var d := {}
		for k in v:
			d[k] = intify(v[k])
		return d
	if v is Array:
		var a: Array = []
		for x in v:
			a.append(intify(x))
		return a
	return v


## Bring a loaded save up to date: fill missing keys from defaults, drop bad entries.
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
		_merge_defaults(h, {"id": str(id), "level": 1, "stars": int(EconomyData.START_STARS[rarity]),
			"shards": 0, "gear": {}})
		h.stars = clampi(int(h.stars), 1, EconomyData.MAX_STARS)
		h.level = clampi(int(h.level), 1, EconomyData.level_cap(int(h.stars)))
		heroes[str(id)] = h
	loaded.heroes = heroes
	var gear: Array = []
	var gear_uids := {}
	for it in loaded.gear:
		if it is Dictionary and it.has("uid") and it.has("slot"):
			_merge_defaults(it, {"tier": 1, "name": "Relic", "stats": {}, "equipped_by": ""})
			if it.equipped_by != "" and not heroes.has(it.equipped_by):
				it.equipped_by = ""
			gear.append(it)
			gear_uids[it.uid] = it
	loaded.gear = gear
	for id in heroes:
		var hg: Dictionary = heroes[id].gear
		for slot in hg.keys():
			if not gear_uids.has(hg[slot]) or gear_uids[hg[slot]].equipped_by != id:
				hg.erase(slot)
	var f: Array = loaded.formation
	var clean: Array = []
	for i in 5:
		var id: String = str(f[i]) if i < f.size() else ""
		clean.append(id if heroes.has(id) and not clean.has(id) else "")
	loaded.formation = clean
	loaded.version = SAVE_VERSION
	return loaded


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


func _backup_corrupt(text: String) -> void:
	if save_path == "":
		return
	var backup := "%s.corrupt-%d.json" % [save_path.get_basename(), now_ms()]
	var f := FileAccess.open(backup, FileAccess.WRITE)
	if f:
		f.store_string(text)
		f.close()
	push_warning("Game: save was corrupted; backed up to %s and started a new game" % backup)


func _delete_save_file() -> void:
	if save_path != "" and FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))


func _changed() -> void:
	if not _dirty:
		_dirty_at = Time.get_ticks_msec()
	_dirty = true
	changed.emit()


# ---------------------------------------------------------------- definitions

## Hero definition dictionary (identity + kit: base_stats, ultimate, passives). {} if unknown.
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
	d["start_stars"] = int(EconomyData.START_STARS.get(d.rarity, 1))
	_def_cache[hero_id] = d
	return d


func all_hero_defs() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for h in HeroData.all():
		out.append(hero_def(h.id))
	return out


# ---------------------------------------------------------------- currencies

## Amount of a currency: "gold", "hero_exp", "gems", "scrolls", "dust".
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
func _grant(reward: Dictionary) -> Dictionary:
	var out := {}
	for c in CURRENCIES:
		var n: int = int(reward.get(c, 0))
		if n > 0:
			_add_currency(c, n)
			out[c] = n
	var gear_uids: Array = []
	for d in reward.get("gear_drops", []):
		gear_uids.append(_create_gear(str(d.slot), int(d.tier)))
	for uid in reward.get("gear", []):
		gear_uids.append(uid)
	if not gear_uids.is_empty():
		out["gear"] = gear_uids
	for hid in reward.get("heroes", []):
		var r := _receive_hero(str(hid))
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


# ---------------------------------------------------------------- counters & quests

func counter(id: String) -> int:
	return int(state.counters.get(id, 0))


func _bump(counter_id: String, n: int = 1) -> void:
	_refresh_daily()
	state.counters[counter_id] = counter(counter_id) + n
	for q in EconomyData.DAILY_QUESTS:
		if q.counter != counter_id:
			continue
		var before: int = int(state.quests.progress.get(q.id, 0))
		var after := before + n
		state.quests.progress[q.id] = after
		if before < int(q.goal) and after >= int(q.goal) and not state.quests.claimed.has(q.id):
			notify.emit({"type": "quest_ready", "id": q.id, "title": q.title})


## Daily rollover: quests, quick claims, daily shop offers, monthly card payout.
func _refresh_daily() -> void:
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
		notify.emit({"type": "monthly_card", "gems": EconomyData.MONTHLY_CARD_DAILY_GEMS})
		did = true
	if did:
		if not _dirty:
			_dirty_at = Time.get_ticks_msec()
		_dirty = true
		if is_inside_tree():
			changed.emit.call_deferred()


# ---------------------------------------------------------------- idle rewards

## {elapsed_ms, cap_ms, full: bool, pending: Reward, per_hour: Reward,
##  quick_claims_left: int, quick_claim_cost: int}
## pending also has gear_count (gear pieces that will drop on claim).
func idle_status() -> Dictionary:
	_refresh_daily()
	var elapsed := _idle_elapsed()
	var per_hour := EconomyData.idle_per_hour(cleared_count())
	var calc := _idle_calc(elapsed, per_hour)
	var used: int = int(state.idle.quick_claims_used)
	var costs := EconomyData.QUICK_CLAIM_COSTS
	return {
		"elapsed_ms": elapsed,
		"cap_ms": EconomyData.IDLE_CAP_MS,
		"full": elapsed >= EconomyData.IDLE_CAP_MS,
		"pending": calc.reward,
		"per_hour": per_hour,
		"quick_claims_left": maxi(0, costs.size() - used),
		"quick_claim_cost": costs[used] if used < costs.size() else -1,
		"quick_claim_ms": EconomyData.QUICK_CLAIM_MS,
		"gear_every_ms": EconomyData.IDLE_GEAR_EVERY_MS,
	}


## Grants pending idle rewards; returns the Reward granted.
func claim_idle() -> Dictionary:
	_refresh_daily()
	var now := now_ms()
	var elapsed := _idle_elapsed()
	var calc := _idle_calc(elapsed, EconomyData.idle_per_hour(cleared_count()))
	state.idle.carry = calc.carry
	state.idle.gear_ms = calc.gear_ms
	state.idle.last_claim_at = now
	state.idle.full_notified = false
	var reward: Dictionary = calc.reward.duplicate()
	var drops: Array = []
	for i in int(reward.get("gear_count", 0)):
		drops.append({"slot": _random_gear_slot(), "tier": EconomyData.gear_tier_for(cleared_count())})
	reward.erase("gear_count")
	reward["gear_drops"] = drops
	var granted := _grant(reward)
	if elapsed >= 60000:
		_bump("idle_claims")
	_changed()
	return granted


## Instantly grants 2h of idle rewards. Result {ok, value: Reward, error}.
func quick_claim() -> Dictionary:
	_refresh_daily()
	var used: int = int(state.idle.quick_claims_used)
	var costs := EconomyData.QUICK_CLAIM_COSTS
	if used >= costs.size():
		return _err("No quick claims left today")
	var cost: int = costs[used]
	if currency("gems") < cost:
		return _err("Not enough gems")
	_add_currency("gems", -cost)
	state.idle.quick_claims_used = used + 1
	var per_hour := EconomyData.idle_per_hour(cleared_count())
	var reward := {}
	for k in per_hour:
		var n: int = int(per_hour[k]) * EconomyData.QUICK_CLAIM_MS / HOUR_MS
		if n > 0:
			reward[k] = n
	var gear_ms: int = int(state.idle.gear_ms) + EconomyData.QUICK_CLAIM_MS
	var drops: Array = []
	while gear_ms >= EconomyData.IDLE_GEAR_EVERY_MS:
		gear_ms -= EconomyData.IDLE_GEAR_EVERY_MS
		drops.append({"slot": _random_gear_slot(), "tier": EconomyData.gear_tier_for(cleared_count())})
	state.idle.gear_ms = gear_ms
	reward["gear_drops"] = drops
	var granted := _grant(reward)
	_bump("quick_claims")
	_changed()
	return _ok(granted)


func _idle_elapsed() -> int:
	var now := now_ms()
	var last: int = int(state.idle.last_claim_at)
	if now < last:
		# Clock went backwards: restart the timer instead of paying out.
		state.idle.last_claim_at = now
		return 0
	return mini(now - last, EconomyData.IDLE_CAP_MS)


## Pending amounts for `elapsed` ms, using sub-unit carry so frequent claims lose nothing.
func _idle_calc(elapsed: int, per_hour: Dictionary) -> Dictionary:
	var carry: Dictionary = state.idle.get("carry", {})
	var new_carry := {}
	var reward := {}
	for k in per_hour:
		var total: int = int(per_hour[k]) * elapsed + int(carry.get(k, 0))
		var n: int = total / HOUR_MS
		new_carry[k] = total % HOUR_MS
		if n > 0:
			reward[k] = n
	var gear_ms: int = int(state.idle.get("gear_ms", 0)) + elapsed
	var gear_count: int = gear_ms / EconomyData.IDLE_GEAR_EVERY_MS
	gear_ms -= gear_count * EconomyData.IDLE_GEAR_EVERY_MS
	if gear_count > 0:
		reward["gear_count"] = gear_count
	return {"reward": reward, "carry": new_carry, "gear_ms": gear_ms}


func _check_idle_full() -> void:
	if bool(state.idle.get("full_notified", false)):
		return
	if _idle_elapsed() >= EconomyData.IDLE_CAP_MS:
		state.idle.full_notified = true
		notify.emit({"type": "idle_full"})


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


## BattleSetup for the player's formation vs this stage.
func stage_battle_setup(stage_index: int) -> Dictionary:
	var st := StageData.stage(stage_index)
	if st.is_empty():
		return {}
	var allies: Array = []
	var f := formation()
	for slot in 5:
		var id: String = f[slot]
		if id == "":
			continue
		var h: Dictionary = state.heroes[id]
		allies.append({"uid": "a%d" % slot, "hero_id": id, "side": "ally", "slot": slot,
			"level": int(h.level), "stars": int(h.stars), "stats": hero_stats(id), "is_boss": false})
	var enemies: Array = []
	for e in st.enemies:
		enemies.append({"uid": "e%d" % int(e.slot), "hero_id": e.hero_id, "side": "enemy", "slot": int(e.slot),
			"level": int(e.level), "stars": int(e.stars),
			"stats": StageData.echo_stats(e.hero_id, int(e.level), int(e.stars), int(e.echo_bp)),
			"is_boss": bool(e.is_boss)})
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
		reward = _grant(st.first_clear_reward)
	_changed()
	return _ok({"reward": reward, "first_clear": first, "victory": true})


# ---------------------------------------------------------------- heroes

## Owned hero entries {id, level, stars, shards, gear}, sorted by power desc.
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
	return StatCalc.stats(hero_id, int(h.level), int(h.stars), _equipped_items(hero_id))


## Stats preview at another level/stars (keeps current gear). For "next level" displays.
func hero_stats_at(hero_id: String, level: int, stars: int) -> Dictionary:
	return StatCalc.stats(hero_id, level, stars, _equipped_items(hero_id))


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
		return EconomyData.level_cap(int(d.get("start_stars", 1)))
	return EconomyData.level_cap(int(state.heroes[hero_id].stars))


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
	return EconomyData.level_cost(lv)


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
	notify.emit({"type": "level_up", "hero_id": hero_id, "level": int(h.level)})
	_changed()
	return _ok({"level": int(h.level), "levels_gained": gained, "cost": spent})


## Most levels affordable right now (for a "level max" button).
func affordable_levels(hero_id: String) -> int:
	if not owns(hero_id):
		return 0
	var lv: int = int(state.heroes[hero_id].level)
	var cap := max_level(hero_id)
	var gold := currency("gold")
	var xp := currency("hero_exp")
	var n := 0
	while lv + n < cap:
		var c := EconomyData.level_cost(lv + n)
		if gold < int(c.gold) or xp < int(c.hero_exp):
			break
		gold -= int(c.gold)
		xp -= int(c.hero_exp)
		n += 1
	return n


## {shards, dust} needed for the next star, or {} at max stars.
## shards = total shards the star needs; dust = dust needed to cover missing shards
## (DUST_PER_SHARD each). Also: shards_have, shards_used, dust_per_shard.
func star_up_cost(hero_id: String) -> Dictionary:
	if not owns(hero_id):
		return {}
	var h: Dictionary = state.heroes[hero_id]
	var need := EconomyData.star_shards(int(h.stars))
	if need <= 0:
		return {}
	var have: int = int(h.shards)
	var missing := maxi(0, need - have)
	return {"shards": need, "dust": missing * EconomyData.DUST_PER_SHARD, "shards_have": have,
		"shards_used": mini(have, need), "dust_per_shard": EconomyData.DUST_PER_SHARD}


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
	notify.emit(ev)
	_changed()
	return _ok({"stars": int(h.stars), "level_cap": max_level(hero_id)})


func _add_hero(hero_id: String) -> void:
	var d := hero_def(hero_id)
	if d.is_empty() or owns(hero_id):
		return
	state.heroes[hero_id] = {"id": hero_id, "level": 1, "stars": int(d.start_stars), "shards": 0, "gear": {}}


## Adds shards; anything a maxed hero can't use becomes dust. Returns dust granted.
func _add_shards(hero_id: String, n: int) -> int:
	var h: Dictionary = state.heroes[hero_id]
	var usable := maxi(0, EconomyData.shards_to_max(int(h.stars)) - int(h.shards))
	var keep := mini(n, usable)
	h.shards = int(h.shards) + keep
	var dust := (n - keep) * EconomyData.DUST_PER_EXCESS_SHARD
	if dust > 0:
		_add_currency("dust", dust)
	return dust


## New hero or duplicate. Returns {hero_id, rarity, is_new, shards, dust}.
func _receive_hero(hero_id: String) -> Dictionary:
	var rarity: String = hero_def(hero_id).rarity
	if not owns(hero_id):
		_add_hero(hero_id)
		_place_in_formation(hero_id)
		notify.emit({"type": "new_hero", "hero_id": hero_id, "rarity": rarity})
		return {"hero_id": hero_id, "rarity": rarity, "is_new": true, "shards": 0, "dust": 0}
	var n: int = int(EconomyData.DUPE_SHARDS[rarity])
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


func auto_formation() -> void:
	var ids: Array = []
	for h in owned_heroes():
		ids.append(h.id)
	ids = ids.slice(0, 5)
	var front_score := func(id: String) -> int:
		var role: String = hero_def(id).role
		var base: int = {"guardian": 3, "striker": 2, "support": 0, "caster": 0, "assassin": -1}.get(role, 0)
		return base * 1000000 + int(hero_stats(id).hp)
	ids.sort_custom(func(a: String, b: String) -> bool: return front_score.call(a) > front_score.call(b))
	var f: Array = ["", "", "", "", ""]
	var front: Array = ids.slice(0, mini(2, ids.size()))
	var back: Array = ids.slice(front.size())
	for i in front.size():
		f[i] = front[i]
	for i in back.size():
		f[2 + i] = back[i]
	state.formation = f
	_changed()


## {faction: String, count: int, bonus_pct: int} for the current formation, or {}.
func faction_bonus() -> Dictionary:
	var counts := {}
	for id in formation():
		if id != "":
			var fac: String = hero_def(id).faction
			counts[fac] = int(counts.get(fac, 0)) + 1
	for fac in counts:
		var n: int = counts[fac]
		if n >= 3:
			var bp: int = int(BattleSim.FACTION_BONUS_BP.get(mini(n, 5), 0))
			return {"faction": fac, "count": n, "bonus_pct": bp / 100}
	return {}


func _place_in_formation(hero_id: String) -> void:
	var f: Array = state.formation
	if f.has(hero_id):
		return
	var role: String = hero_def(hero_id).role
	var order: Array = [0, 1, 2, 3, 4] if role == "guardian" or role == "striker" else [2, 3, 4, 0, 1]
	for i in order:
		if f[i] == "":
			f[i] = hero_id
			return


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
	return StatCalc.gear_score(_gear(gear_uid))


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


func _equipped_items(hero_id: String) -> Array:
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


func _auto_equip_raw(hero_id: String) -> bool:
	if not owns(hero_id):
		return false
	var did := false
	var hg: Dictionary = state.heroes[hero_id].gear
	for slot in EconomyData.GEAR_SLOTS:
		var cur := _gear(hg.get(slot, ""))
		var best := cur
		var best_score := StatCalc.gear_score(cur) if not cur.is_empty() else -1
		for it in state.gear:
			if it.slot != slot or str(it.equipped_by) != "":
				continue
			var sc := StatCalc.gear_score(it)
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


func _random_gear_slot() -> String:
	var rng := SeededRng.new(SeededRng.mix(int(state.rng_seed) + 31, int(state.gear_seq) * 13 + 5))
	return rng.pick(EconomyData.GEAR_SLOTS)


func _create_gear(slot: String, tier: int) -> String:
	tier = clampi(tier, 1, 5)
	if not EconomyData.GEAR_SLOTS.has(slot):
		slot = "weapon"
	state.gear_seq = int(state.gear_seq) + 1
	var rng := SeededRng.new(SeededRng.mix(int(state.rng_seed), int(state.gear_seq)))
	var stats := {}
	var table: Dictionary = EconomyData.GEAR_STATS[slot]
	for k in table:
		var base: int = int(table[k][tier])
		stats[k] = maxi(1, base * rng.range_int(90, 110) / 100)
	var noun: String = rng.pick(EconomyData.GEAR_ITEM_NAMES[slot])
	var item := {
		"uid": "g%d" % int(state.gear_seq),
		"slot": slot,
		"tier": tier,
		"name": "%s %s" % [EconomyData.GEAR_TIER_NAMES[tier], noun],
		"stats": stats,
		"equipped_by": "",
	}
	state.gear.append(item)
	return item.uid


func _salvage_raw(it: Dictionary) -> Dictionary:
	var tier: int = int(it.tier)
	var reward := {"gold": EconomyData.SALVAGE_GOLD_PER_TIER * tier, "dust": EconomyData.SALVAGE_DUST_PER_TIER * tier}
	state.gear.erase(it)
	_add_currency("gold", int(reward.gold))
	_add_currency("dust", int(reward.dust))
	return reward


## Keeps the bag from growing forever: salvages the weakest unequipped pieces.
func _trim_gear_bag() -> void:
	var loose: Array = []
	for it in state.gear:
		if str(it.equipped_by) == "":
			loose.append(it)
	if loose.size() <= EconomyData.GEAR_BAG_LIMIT:
		return
	loose.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return StatCalc.gear_score(a) < StatCalc.gear_score(b))
	for i in loose.size() - EconomyData.GEAR_BAG_LIMIT:
		_salvage_raw(loose[i])


# ---------------------------------------------------------------- summon

## BannerDef {id, name, cost_one, cost_ten, rates: {rare, epic, legendary} (basis points),
## pity_legendary, pool: [...]}
## cost_one / cost_ten are gem prices; scroll_cost_one / scroll_cost_ten the scroll prices.
func banner() -> Dictionary:
	var b: Dictionary = EconomyData.BANNER
	var pool: Array = []
	var by_rarity := {"rare": [], "epic": [], "legendary": []}
	for h in HeroData.all():
		pool.append(h.id)
		by_rarity[h.rarity].append(h.id)
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
		"pool_by_rarity": by_rarity,
	}


## Pulls since the last Legendary (Legendary guaranteed when this reaches pity_legendary - 1).
func pity_count() -> int:
	return int(state.get("summon", {}).get("pity", 0))


func free_pull_available() -> bool:
	if state.is_empty():
		return false
	_refresh_daily()
	return int(state.summon.last_free_pull_day) != today()


## count = 1 or 10. use_free only valid with count 1. Pays with scrolls first, then gems.
## Result {ok, value: Array of {hero_id, rarity, is_new, shards, pity}, error}.
func summon(count: int, use_free: bool = false) -> Dictionary:
	_refresh_daily()
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
	var pool := {"rare": [], "epic": [], "legendary": []}
	for h in HeroData.all():
		pool[h.rarity].append(h.id)
	var rng := SeededRng.new(SeededRng.mix(int(state.summon.seed), int(state.summon.total_pulls)))
	var results: Array = []
	var got_epic := false
	for i in count:
		var rarity := _roll_rarity(rng)
		if count == 10 and i == 9 and not got_epic and rarity == "rare":
			rarity = "epic"
		if rarity != "rare":
			got_epic = true
		state.summon.pity = 0 if rarity == "legendary" else pity_count() + 1
		state.summon.total_pulls = int(state.summon.total_pulls) + 1
		var hid: String = rng.pick(pool[rarity])
		var r := _receive_hero(hid)
		r["pity"] = pity_count()
		results.append(r)
	_bump("summons", count)
	_changed()
	return _ok(results)


func _roll_rarity(rng: SeededRng) -> String:
	var rates: Dictionary = EconomyData.BANNER.rates
	if pity_count() >= int(EconomyData.BANNER.pity_legendary) - 1:
		return "legendary"
	var r := rng.range_int(0, 9999)
	if r < int(rates.legendary):
		return "legendary"
	if r < int(rates.legendary) + int(rates.epic):
		return "epic"
	return "rare"


# ---------------------------------------------------------------- quests & shop

## Array of {id, title, progress, goal, reward, claimed} (+ ready: bool)
func quests() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if state.is_empty():
		return out
	_refresh_daily()
	for q in EconomyData.DAILY_QUESTS:
		var p: int = int(state.quests.progress.get(q.id, 0))
		var claimed: bool = state.quests.claimed.has(q.id)
		out.append({"id": q.id, "title": q.title, "progress": mini(p, int(q.goal)), "goal": int(q.goal),
			"reward": q.reward.duplicate(), "claimed": claimed, "ready": p >= int(q.goal) and not claimed})
	return out


func claim_quest(quest_id: String) -> Dictionary:
	_refresh_daily()
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
	var granted := _grant(q.reward)
	if quest_id != "dq_all":
		_bump("daily_quests_done")
	_changed()
	return _ok(granted)


## Number of daily quests ready to claim (for nav badges).
func quests_ready_count() -> int:
	var n := 0
	for q in quests():
		if q.ready:
			n += 1
	return n


## Array of {id, name, description, price_label, reward, limit, purchased, tag}
## (+ period "once"|"day", available: bool, test_purchase: true, days_left for the monthly card).
## limit 0 = unlimited; purchased counts lifetime ("once") or today ("day").
func offers() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if state.is_empty():
		return out
	_refresh_daily()
	for o in EconomyData.OFFERS:
		var bought := _offer_count(o)
		var limit: int = int(o.limit)
		var entry := {"id": o.id, "name": o.name, "description": o.description,
			"price_label": o.price_label, "reward": o.reward.duplicate(), "limit": limit,
			"purchased": bought, "tag": o.tag, "period": o.period,
			"available": limit == 0 or bought < limit, "test_purchase": o.price_label != "Free"}
		if o.id == "monthly_card":
			entry["days_left"] = monthly_card_days_left()
		out.append(entry)
	return out


## Prototype: purchases are free test purchases. Result {ok, value: Reward, error}.
func buy_offer(offer_id: String) -> Dictionary:
	_refresh_daily()
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
	if offer_id == "monthly_card":
		var day := today()
		state.shop.monthly_until_day = maxi(int(state.shop.monthly_until_day), day) + EconomyData.MONTHLY_CARD_DAYS
		state.shop.monthly_last_day = day
	var granted := _grant(o.reward)
	_changed()
	return _ok(granted)


## Days of Moonlit Pass payouts left (0 = inactive).
func monthly_card_days_left() -> int:
	return maxi(0, int(state.shop.monthly_until_day) - today())


func _offer_count(o: Dictionary) -> int:
	var key: String = "daily" if o.period == "day" else "purchases"
	return int(state.shop[key].get(o.id, 0))


# ---------------------------------------------------------------- settings & dev

func setting(key: String) -> Variant:
	return state.get("settings", {}).get(key, null)


func set_setting(key: String, value: Variant) -> void:
	if state.is_empty():
		return
	match key:
		"battle_speed":
			var v := int(value)
			if not [1, 2, 4].has(v):
				return
			state.settings.battle_speed = v
		"sound", "music", "haptics", "auto_ultimates":
			state.settings[key] = bool(value)
		"player_name":
			state.player_name = str(value).strip_edges().left(16)
		_:
			state.settings[key] = value
	_changed()


## Dev tool: pretend `ms` milliseconds have passed (for idle testing).
func dev_skip_time(ms: int) -> void:
	state.dev_time_offset = int(state.dev_time_offset) + ms
	_refresh_daily()
	_check_idle_full()
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
		_add_hero(id)
		var h: Dictionary = state.heroes[id]
		h.stars = maxi(int(h.stars), int(roster[id][1]))
		h.level = mini(int(roster[id][0]), EconomyData.level_cap(int(h.stars)))
		h.shards = int(roster[id][2])
	state.currencies = {"gold": 500000, "hero_exp": 300000, "gems": 50000, "scrolls": 30, "dust": 2000}
	state.campaign.cleared = 12
	var slots := ["weapon", "armor", "helm", "charm", "weapon", "armor", "helm", "charm", "weapon", "charm"]
	var tiers := [3, 3, 2, 3, 2, 2, 2, 1, 1, 2]
	for i in slots.size():
		_create_gear(slots[i], tiers[i])
	auto_formation()
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
