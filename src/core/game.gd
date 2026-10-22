extends Node
## Autoload "Game": the single API the UI talks to.
##
## CONTRACT (see docs/dev/architecture.md): method names, arguments and return shapes
## below are used by the UI. Add methods freely; do not rename or remove these. The UI never
## edits `state` directly. It calls methods and listens to `changed`.
##
## This node is a thin adapter (portability, architecture.md section 3b). Every rule lives in
## `model` (GameModel, src/core/game_model.gd, a plain RefCounted with no engine services) and
## the pure rule classes it uses. This script only:
##   - supplies the clock (real time, or now_override_ms in tests) and the time zone,
##   - saves and loads `state` as JSON (atomic write, corrupt-save backup, autosave),
##   - turns the model's outbox / change flags into the `notify` and `changed` signals,
##   - polls daily resets and the idle cap while the app runs.
##
## The script also works when instantiated directly (tests do
## `preload("res://src/core/game.gd").new()`), so it must not rely on being in the tree
## for logic. Set `now_override_ms` and `save_path` in tests.
##
## Content and tuning: data/*.json. Formulas: docs/dev/economy-v1.md. Port notes:
## docs/dev/unity-port.md.

## Emitted after any state change (UI refreshes on this).
signal changed
## Emitted for one-shot feedback the UI may toast, e.g. {"type": "quest_ready", "id": ...}
## Types: level_up {hero_id, level}, star_up {hero_id, stars, passive?}, awaken {hero_id, awaken,
## unlock}, quest_ready {id, title}, idle_full {}, new_hero {hero_id, rarity}, monthly_card {gems}.
signal notify(event: Dictionary)

const SAVE_VERSION := GameModel.SAVE_VERSION
const TEST_SAVE_PATH := "user://test_save.json"
const CURRENCIES: Array[String] = GameModel.CURRENCIES
const AUTOSAVE_DELAY_MS := 1500
const DAY_MS := GameModel.DAY_MS
const HOUR_MS := GameModel.HOUR_MS

## The rules and state. Tests and tools may call it directly (e.g. model.add_hero(id)).
var model := GameModel.new()
## The player state (lives in the model). Read-only for the UI.
var state: Dictionary:
	get:
		return model.state
	set(value):
		model.state = value
## Tests: fixed clock in ms. -1 = use real time.
var now_override_ms: int = -1
## Where the save lives. Empty string = don't persist (tests).
var save_path: String = "user://save.json"
## Local time zone offset used for daily resets (tests set 0).
var tz_bias_ms: int:
	get:
		return model.tz_bias_ms
	set(value):
		model.tz_bias_ms = value

var _dirty: bool = false
var _dirty_at: int = 0
var _poll_accum: float = 0.0


func _init() -> void:
	model.clock = _clock_ms
	var tz: Dictionary = Time.get_time_zone_from_system()
	model.tz_bias_ms = int(tz.get("bias", 0)) * 60000


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
		if args.has("--skins"):       # screenshots/testing: every owned hero wears her first installed skin
			_dress_owned_heroes()
		if args.has("--nudity"):      # screenshots/testing: the throwaway save with nudity on
			set_setting("nudity", true)
		if args.has("--rival-tag"):   # screenshots/testing: Rue won the last fight (her tag on the Lobby)
			dev_rival_tag(true)
		for a in args:
			# screenshots/testing: --date=MM-DD moves the clock to that day this year (the calendar).
			if a.begins_with("--date="):
				dev_date(a.substr("--date=".length()))
			# --born=MM-DD: the player's birthday, as if given on the intake form.
			if a.begins_with("--born="):
				model.state.player_birthday = CalendarRules.clean_md(a.substr("--born=".length()))
		for a in args:
			# screenshots/testing: --war=heaven|hell picks the side and logs a few days of souls in two
			# sectors (and last week's, so a claim waits).
			if a.begins_with("--war="):
				dev_war(a.substr("--war=".length()))
		for a in args:
			# screenshots/testing: --awaken=seraphiel:3,noctaire:1 sets Legendaries to max stars at
			# those awakening tiers (tier 0: ready to awaken, shards and dust for the next one).
			if a.begins_with("--awaken="):
				for part in a.substr("--awaken=".length()).split(",", false):
					var kv := part.split(":")
					var tier := int(kv[1]) if kv.size() > 1 else 0
					model.dev_set_awaken(kv[0], tier, 96 if tier < 3 else 40)
				model.state.currencies.dust = maxi(int(model.state.currencies.dust), 12000)
		save()
		# Screenshots/testing: --away=<hours> pretends the player was away that long; --notice=tz:3,
		# late:3, early:6 or visits:10 queues what she notices.
		for a in args:
			if a.begins_with("--away="):
				last_away_ms = int(float(a.substr("--away=".length())) * 3600000.0)
			if a.begins_with("--notice="):
				var kv := a.substr("--notice=".length()).split(":")
				notices[kv[0]] = int(kv[1]) if kv.size() > 1 else 1
	else:
		load_or_create()
		_measure_away()


func _process(delta: float) -> void:
	if _dirty and Time.get_ticks_msec() - _dirty_at >= AUTOSAVE_DELAY_MS:
		save()
	_poll_accum += delta
	if _poll_accum >= 2.0:
		_poll_accum = 0.0
		if not state.is_empty():
			model.refresh_daily()
			model.check_idle_full()
			_flush()


func _exit_tree() -> void:
	if _dirty and not state.is_empty():
		save()


## How long the player was away before this session (or this resume), in ms (0 when unknown).
## The Lobby's heroine notices long absences once (away_noticed).
var last_away_ms := 0
var away_noticed := false
## What else she may notice about this visit, each said once (take_notice): "tz" (the clock moved
## across time zones: hours, + = ahead), "late" (opened 01:00-04:59: the hour), "early" (05:00-06:59),
## "visits" (the tenth visit today).
var notices: Dictionary = {}


## Notes when the player leaves (kept in the settings: an adapter detail, not a rule).
func _mark_seen() -> void:
	if not state.is_empty() and state.get("settings") is Dictionary:
		state.settings["last_seen_ms"] = _clock_ms()


## How long since the player was last seen (and resets the "noticed" flag for a long absence).
func _measure_away() -> void:
	if state.is_empty() or not (state.get("settings") is Dictionary):
		return
	var seen := int((state.settings as Dictionary).get("last_seen_ms", 0))
	var away := maxi(0, _clock_ms() - seen) if seen > 0 else -1
	if away >= 3600000:
		last_away_ms = away
		away_noticed = false
	_notice_visit(away)
	_mark_seen()


## A visit (launch or return after 5 min or more): the time zone, the hour, the count today.
func _notice_visit(away: int) -> void:
	var st: Dictionary = state.settings
	var tz := int(Time.get_time_zone_from_system().get("bias", 0))
	# The day follows the device's zone even after travelling while the app was in the background.
	model.tz_bias_ms = tz * 60000
	if st.has("tz_bias") and int(st.tz_bias) != tz and absi(tz - int(st.tz_bias)) >= 60:
		notices["tz"] = (tz - int(st.tz_bias)) / 60
	st["tz_bias"] = tz
	if away >= 0 and away < 300000:
		return
	var hour := int(Time.get_datetime_dict_from_system().hour)
	var day := today()
	if hour >= 1 and hour < 5 and int(st.get("late_seen_day", -1)) != day:
		notices["late"] = hour
	elif hour >= 5 and hour < 7 and int(st.get("early_seen_day", -1)) != day:
		notices["early"] = hour
	if int(st.get("visits_day", -1)) != day:
		st["visits_day"] = day
		st["visits_n"] = 0
	st["visits_n"] = int(st.get("visits_n", 0)) + 1
	if int(st.visits_n) == 10:
		notices["visits"] = 10


## Takes one notice (null when there is none) and marks it said.
func take_notice(key: String) -> Variant:
	if not notices.has(key):
		return null
	var v: Variant = notices[key]
	notices.erase(key)
	if key == "late" or key == "early":
		state.settings[key + "_seen_day"] = today()
	return v


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_CLOSE_REQUEST:
			if not state.is_empty():
				_mark_seen()
				save()
		NOTIFICATION_APPLICATION_RESUMED, NOTIFICATION_APPLICATION_FOCUS_IN:
			if not state.is_empty():
				_measure_away()
				model.refresh_daily()
				model.check_idle_full()
				_flush()
				changed.emit()


# ---------------------------------------------------------------- adapter plumbing

## Wall clock in ms since the Unix epoch (or the test override). The model adds dev_time_offset.
func _clock_ms() -> int:
	if now_override_ms >= 0:
		return now_override_ms
	return int(Time.get_unix_time_from_system() * 1000.0)


## Emits what the last model call produced: queued notifications first, then `changed`
## (immediately after actions; deferred after a daily rollover found by a query, so a screen
## reading Game during its own refresh never re-enters itself).
func _flush() -> void:
	# Art follows the nudity setting (skins show their adult art when it is on and installed).
	HeroArt.nudity = model.setting("nudity") == true
	if not model.outbox.is_empty():
		var events := model.outbox.duplicate()
		model.outbox.clear()
		for e in events:
			notify.emit(e)
	if model.changed_now:
		model.changed_now = false
		model.changed_later = false
		_mark_dirty()
		changed.emit()
	elif model.changed_later:
		model.changed_later = false
		_mark_dirty()
		if is_inside_tree():
			changed.emit.call_deferred()


func _mark_dirty() -> void:
	if not _dirty:
		_dirty_at = Time.get_ticks_msec()
	_dirty = true


# ---------------------------------------------------------------- time / save

# ---------------------------------------------------------------- the calendar

## Today's real days (holidays, owned heroines' birthdays), each with "claimed".
func calendar_today() -> Array:
	return model.calendar_today()


func claim_calendar(key: String) -> Dictionary:
	var r := model.claim_calendar(key)
	_flush()
	return r


## Screenshots/testing: shifts the clock (dev_time_offset) so today is MM-DD this year.
func dev_date(mmdd: String) -> void:
	var parts := mmdd.split("-")
	if parts.size() != 2:
		return
	var y := int(CalendarRules.civil(today())[0])
	var target := CalendarRules.day_number(y, int(parts[0]), int(parts[1]))
	model.state.dev_time_offset = int(model.state.dev_time_offset) + (target - today()) * GameModel.DAY_MS


## Current time in ms (real clock + state.dev_time_offset, or now_override_ms).
func now_ms() -> int:
	return model.now_ms()


## Local day number (days since epoch in the player's time zone). Resets at local midnight.
func today() -> int:
	return model.today()


func day_of(ms: int) -> int:
	return model.day_of(ms)


## ms until the next local midnight (for "resets in" labels).
func ms_until_reset() -> int:
	return model.ms_until_reset()


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
	model.migrate(intify(data))
	model.refresh_daily()
	model.changed_now = true
	_flush()


func new_game() -> void:
	model.new_game()
	_flush()


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
	return model.default_state()


## Convert JSON floats back to ints (all game numbers are ints).
static func intify(v: Variant) -> Variant:
	return GameData.intify(v)


## Bring a loaded save up to date: fill missing keys from defaults, drop bad entries.
func migrate(loaded: Dictionary) -> Dictionary:
	var out := model.migrate(loaded)
	_flush()
	return out


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


# ---------------------------------------------------------------- definitions

## Hero definition dictionary (identity + kit: base_stats, ultimate, passives). {} if unknown.
func hero_def(hero_id: String) -> Dictionary:
	return model.hero_def(hero_id)


func all_hero_defs() -> Array[Dictionary]:
	return model.all_hero_defs()


# ---------------------------------------------------------------- currencies & counters

## Amount of a currency: "gold", "hero_exp", "gems", "scrolls", "dust".
func currency(id: String) -> int:
	return model.currency(id)


func counter(id: String) -> int:
	return model.counter(id)


# ---------------------------------------------------------------- idle rewards

## {elapsed_ms, cap_ms, full: bool, pending: Reward, per_hour: Reward,
##  quick_claims_left: int, quick_claim_cost: int, quick_claim_ms, gear_every_ms}
## pending also has gear_count (gear pieces that will drop on claim).
func idle_status() -> Dictionary:
	var r := model.idle_status()
	_flush()
	return r


## Grants pending idle rewards; returns the Reward granted.
func claim_idle() -> Dictionary:
	var r := model.claim_idle()
	_flush()
	return r


## Instantly grants 2h of idle rewards. Result {ok, value: Reward, error}.
func quick_claim() -> Dictionary:
	var r := model.quick_claim()
	_flush()
	return r


# ---------------------------------------------------------------- campaign

func chapters() -> Array[Dictionary]:
	return model.chapters()


func stages() -> Array[Dictionary]:
	return model.stages()


func stage(stage_index: int) -> Dictionary:
	return model.stage(stage_index)


func cleared_count() -> int:
	return model.cleared_count()


## "cleared" | "current" | "locked"
func stage_status(stage_index: int) -> String:
	return model.stage_status(stage_index)


## Next stage to clear, or {} if all cleared.
func current_stage() -> Dictionary:
	return model.current_stage()


## BattleSetup for the player's formation vs this stage.
func stage_battle_setup(stage_index: int) -> Dictionary:
	var r := model.stage_battle_setup(stage_index)
	_flush()
	return r


## Call after a stage battle. Result {ok, value: {reward, first_clear: bool, victory}, error}.
func complete_stage(stage_index: int, outcome: Dictionary) -> Dictionary:
	var r := model.complete_stage(stage_index, outcome)
	_flush()
	return r


# ---------------------------------------------------------------- the Spire (tower)

func tower_unlocked() -> bool:
	return model.tower_unlocked()


## Highest floor cleared (0 = none).
func tower_best() -> int:
	return model.tower_best()


## The next floor to fight (TowerData.FLOORS + 1 when the top is cleared).
func tower_next() -> int:
	return model.tower_next()


func tower_floors() -> int:
	return TowerData.FLOORS


## Built floor f (stage-shaped: enemies, recommended_power, first_clear_reward...), or {}.
func tower_floor(f: int) -> Dictionary:
	return TowerData.get_floor(f)


func tower_battle_setup(f: int) -> Dictionary:
	var r := model.tower_battle_setup(f)
	_flush()
	return r


## Call after a floor battle. Result {ok, value: {reward, first_clear, victory}, error}.
func complete_tower(f: int, outcome: Dictionary) -> Dictionary:
	var r := model.complete_tower(f, outcome)
	_flush()
	return r


# ---------------------------------------------------------------- heroes

## Owned hero entries {id, level, stars, shards, gear, awaken}, sorted by power desc.
func owned_heroes() -> Array[Dictionary]:
	return model.owned_heroes()


func owns(hero_id: String) -> bool:
	return model.owns(hero_id)


## Owned hero entry {id, level, stars, shards, gear, awaken} (a copy), or {} if not owned.
func hero(hero_id: String) -> Dictionary:
	return model.hero(hero_id)


## Final stats {hp, atk, def, spd, crit} for an owned hero (level, stars, gear).
## Unowned heroes: level 1 at their starting stars, no gear.
func hero_stats(hero_id: String) -> Dictionary:
	return model.hero_stats(hero_id)


## Stats preview at another level/stars (keeps current gear). For "next level" displays.
## awaken: the awakening tier to preview (-1 = her current one).
func hero_stats_at(hero_id: String, level: int, stars: int, awaken: int = -1) -> Dictionary:
	return model.hero_stats_at(hero_id, level, stars, awaken)


func hero_power(hero_id: String) -> int:
	return model.hero_power(hero_id)


func team_power() -> int:
	return model.team_power()


func max_level(hero_id: String) -> int:
	return model.max_level(hero_id)


## True when passive number `index` (0 or 1) is unlocked at the hero's current stars.
func passive_unlocked(hero_id: String, index: int) -> bool:
	return model.passive_unlocked(hero_id, index)


## {gold, hero_exp} or {} when at the level cap.
func level_up_cost(hero_id: String) -> Dictionary:
	return model.level_up_cost(hero_id)


func level_up(hero_id: String) -> Dictionary:
	var r := model.level_up(hero_id)
	_flush()
	return r


## Level up to `times` levels (stops at the cap or when out of resources).
## Result {ok, value: {level, levels_gained, cost: {gold, hero_exp}}, error}.
func level_up_many(hero_id: String, times: int) -> Dictionary:
	var r := model.level_up_many(hero_id, times)
	_flush()
	return r


## Most levels affordable right now (for a "level max" button).
func affordable_levels(hero_id: String) -> int:
	return model.affordable_levels(hero_id)


## True when the hero can level up, star up or awaken right now (for "upgrade ready" badges).
func upgrade_ready(hero_id: String) -> bool:
	return model.upgrade_ready(hero_id)


## {shards, dust} needed for the next star, or {} at max stars.
## shards = total shards the star needs; dust = dust needed to cover missing shards
## (dust_per_shard each, by rarity). Also: shards_have, shards_used, dust_per_shard.
func star_up_cost(hero_id: String) -> Dictionary:
	return model.star_up_cost(hero_id)


func can_star_up(hero_id: String) -> bool:
	return model.can_star_up(hero_id)


func star_up(hero_id: String) -> Dictionary:
	var r := model.star_up(hero_id)
	_flush()
	return r


## A Legendary's awakening tier, 0-3 (0 for every other hero). A1 unlocks her legend passive, A2
## her empowered ultimate, A3 her Ascended title; every tier raises all stats (data/economy.json
## heroes.awaken_*). Her legend block (title, passive, ult_bonus, lore) is hero_def(id).legend.
func awaken_tier(hero_id: String) -> int:
	return model.awaken_tier(hero_id)


## The next awakening's cost, or {} (not owned, not a Legendary, fully awakened):
## {tier, shards, dust, dust_base, shards_have, shards_used, dust_per_shard, min_stars, stars_ok}.
## dust = dust_base + dust_per_shard for each missing shard; stars_ok is false below min_stars.
func awaken_cost(hero_id: String) -> Dictionary:
	return model.awaken_cost(hero_id)


func can_awaken(hero_id: String) -> bool:
	return model.can_awaken(hero_id)


## Result {ok, value: {awaken, unlock: "legend_passive" | "ult_bonus" | "ascended"}, error}.
func awaken(hero_id: String) -> Dictionary:
	var r := model.awaken(hero_id)
	_flush()
	return r


# ---------------------------------------------------------------- formation

## Array of 5 hero ids or "" (index 0-1 front row, 2-4 back row).
func formation() -> Array:
	return model.formation()


func set_formation(slots: Array) -> Dictionary:
	var r := model.set_formation(slots)
	_flush()
	return r


## Best 5 owned heroes by power, guardians and strikers in front, then gear them up.
func auto_formation() -> void:
	model.auto_formation()
	_flush()


## {faction: String, count: int, bonus_pct: int} for the current formation, or {}.
func faction_bonus() -> Dictionary:
	return model.faction_bonus()


# ---------------------------------------------------------------- gear

func gear_items() -> Array[Dictionary]:
	return model.gear_items()


func gear_item(gear_uid: String) -> Dictionary:
	return model.gear_item(gear_uid)


## Gear score used for comparisons (power-like).
func gear_score(gear_uid: String) -> int:
	return model.gear_score(gear_uid)


func equip(hero_id: String, gear_uid: String) -> Dictionary:
	var r := model.equip(hero_id, gear_uid)
	_flush()
	return r


func unequip(hero_id: String, slot: String) -> Dictionary:
	var r := model.unequip(hero_id, slot)
	_flush()
	return r


func auto_equip(hero_id: String) -> void:
	model.auto_equip(hero_id)
	_flush()


## Turns an unequipped item into gold and dust. Result {ok, value: Reward, error}.
func salvage_gear(gear_uid: String) -> Dictionary:
	var r := model.salvage_gear(gear_uid)
	_flush()
	return r


# ---------------------------------------------------------------- summon

## BannerDef for banner_id (default the standard banner) as it stands today: {id, kind
## ("standard" | "featured" | "faction" | "wish" | "envoy"), name, short, cost_one, cost_ten
## (prices in `currency`: "gems", or "gold" on the envoy banner), scroll_cost_one,
## scroll_cost_ten (0 = scrolls not taken), rates: {rare, epic, legendary} (basis points),
## pity_legendary (0 = none), ten_pull_guarantee, pool, pool_by_rarity, free_daily, pity, and per
## kind: featured, featured_bp, lost / faction / target, choices; rotation_days, next_change_day,
## ms_until_change; limit_period, limit_max, limit_left (-1 = none), ms_until_limit_reset}.
## See GameModel.banner.
func banner(banner_id: String = "standard") -> Dictionary:
	return model.banner(banner_id)


## Every banner's BannerDef in banner.json order (the standard one first).
func banners() -> Array[Dictionary]:
	return model.banners()


## Pulls since the banner's last Legendary (Legendary guaranteed when this reaches
## pity_legendary - 1).
func pity_count(banner_id: String = "standard") -> int:
	return model.pity_count(banner_id)


## Pulls left in the banner's limit period (envoy: today, wish: this week); -1 = no limit.
func summon_left(banner_id: String) -> int:
	return model.summon_left(banner_id)


## The wish banner's chosen Legendary ("" until picked).
func wish_target(banner_id: String = "wish") -> String:
	return model.wish_target(banner_id)


## Result {ok, value: hero id, error}.
func set_wish_target(hero_id: String, banner_id: String = "wish") -> Dictionary:
	var r := model.set_wish_target(hero_id, banner_id)
	_flush()
	return r


func free_pull_available() -> bool:
	var r := model.free_pull_available()
	_flush()
	return r


## count = 1 or 10 on banner_id (standard by default). use_free: the standard banner's free
## daily pull, count 1 only. Pays with scrolls first, then gems (gold on the envoy banner).
## Result {ok, value: Array of {hero_id, rarity, is_new, shards, dust, pity (+ featured)}, error}.
func summon(count: int, use_free: bool = false, banner_id: String = "standard") -> Dictionary:
	var r := model.summon(count, use_free, banner_id)
	_flush()
	return r


# ---------------------------------------------------------------- quests & shop

## Array of {id, title, counter, progress, goal, reward, claimed, ready}
func quests() -> Array[Dictionary]:
	var r := model.quests()
	_flush()
	return r


func claim_quest(quest_id: String) -> Dictionary:
	var r := model.claim_quest(quest_id)
	_flush()
	return r


## Number of daily quests ready to claim (for nav badges).
func quests_ready_count() -> int:
	var r := model.quests_ready_count()
	_flush()
	return r


## Array of {id, name, description, price_label, reward, limit, purchased, tag}
## (+ period "once"|"day", available: bool, test_purchase: true, days_left for the monthly card).
## limit 0 = unlimited; purchased counts lifetime ("once") or today ("day").
func offers() -> Array[Dictionary]:
	var r := model.offers()
	_flush()
	return r


## Prototype: purchases are free test purchases. Result {ok, value: Reward, error}.
func buy_offer(offer_id: String) -> Dictionary:
	var r := model.buy_offer(offer_id)
	_flush()
	return r


## Days of Moonlit Pass payouts left (0 = inactive).
func monthly_card_days_left() -> int:
	return model.monthly_card_days_left()


# ---------------------------------------------------------------- skins (cosmetic)

## A hero's skins with "owned", "equipped" and "installed" (its art is in the build) flags.
func skins_for(hero_id: String) -> Array[Dictionary]:
	var out := model.skins_for(hero_id)
	for s in out:
		s["installed"] = HeroArt.has_skin_art(s.hero, s.id)
	return out


func owns_skin(skin_id: String) -> bool:
	return model.owns_skin(skin_id)


## The equipped skin ("" = base look).
func equipped_skin(hero_id: String) -> String:
	return model.equipped_skin(hero_id)


## Buy a skin with gems. Skins whose art is not in the build yet are "Coming soon".
func buy_skin(skin_id: String) -> Dictionary:
	var sd := SkinData.get_def(skin_id)
	if not sd.is_empty() and not HeroArt.has_skin_art(sd.hero, skin_id):
		return {"ok": false, "value": null, "error": "Coming soon"}
	var r := model.buy_skin(skin_id)
	_flush()
	return r


func equip_skin(hero_id: String, skin_id: String) -> Dictionary:
	var r := model.equip_skin(hero_id, skin_id)
	_flush()
	return r


## Throwaway saves only (--skins): give every owned hero her first installed skin and equip it.
func _dress_owned_heroes() -> void:
	for h in owned_heroes():
		var hid := str(h.id)
		for s in skins_for(hid):
			if bool(s.installed):
				if not owns_skin(str(s.id)):
					(state.skins.owned as Array).append(str(s.id))
				model.equip_skin(hid, str(s.id))
				break
	model.changed_now = true
	_flush()


# ---------------------------------------------------------------- prints (cosmetic)

## The album, newest first: [{uid, hero, banner, edition, printing, serial, run, flaw, ink, holo,
## grade, v, day, first, from}]. filter: "all" | "misprint" | "holo" | "top" | "rival" | "hero:<id>".
func prints(filter: String = "all") -> Array[Dictionary]:
	return model.prints(filter)


## One album print by uid, {} if not there.
func print_by_uid(uid: String) -> Dictionary:
	return model.print_by_uid(uid)


## {total, kept, misprints, holo, top, from_rival, best_grade, best}.
func print_stats() -> Dictionary:
	return model.print_stats()


## Prints shown on the profile (up to 3 uids). Result {ok, value: uids, error}.
func set_showcase(uids: Array) -> Dictionary:
	var r := model.set_showcase(uids)
	_flush()
	return r


func showcase() -> Array[Dictionary]:
	return model.showcase()


# ---------------------------------------------------------------- the Rival (Rue)

func war_unlocked() -> bool:
	return model.war_unlocked()


## The front (GameModel.war): side, focus, sectors with control, standing, week, souls, claim.
func war() -> Dictionary:
	return model.war()


func war_choose_side(side: String) -> Dictionary:
	var r := model.war_choose_side(side)
	_flush()
	return r


func war_set_focus(sector: int) -> Dictionary:
	var r := model.war_set_focus(sector)
	_flush()
	return r


func war_claim() -> Dictionary:
	var r := model.war_claim()
	_flush()
	return r


## The intake form (the onboarding): done? the signature strokes; finishing it; replaying it.
func onboarded() -> bool:
	return model.onboarded()


func signature() -> Array:
	return model.signature()


func complete_intake(player_name: String, strokes: Array, born: String = "") -> Dictionary:
	var r := model.complete_intake(player_name, strokes, born)
	_flush()
	return r


func reset_intake() -> void:
	model.reset_intake()
	_flush()


## Raises an open building one level for gold (GameModel.district_upgrade).
func district_upgrade(building: int) -> Dictionary:
	var r := model.district_upgrade(building)
	_flush()
	return r


## The player's district (GameModel.district): buildings, keepers, the idle bonus.
func district() -> Dictionary:
	return model.district()


func district_set_keeper(building: int, hero_id: String) -> Dictionary:
	var r := model.district_set_keeper(building, hero_id)
	_flush()
	return r


## The Champion fight's BattleSetup ({} without a side or with no tries left today).
func war_champion_setup() -> Dictionary:
	var r := model.war_champion_setup()
	_flush()
	return r


## Call after a Champion fight. Result {ok, value: {damage, total, pct, reward, tiers}, error}.
func complete_champion(outcome: Dictionary) -> Dictionary:
	var r := model.complete_champion(outcome)
	_flush()
	return r


## Debug (throwaway saves): the player fights for `side` with souls logged over this week and last.
func dev_war(side: String) -> void:
	var ws: Dictionary = model.state.war
	ws.side = side
	ws.focus = 3
	var today := model.today()
	var w0 := WarRules.week_start(WarRules.week_of(today))
	for d in range(w0 - 7, today + 1):
		ws.log[str(d)] = {"3": 600 + (d % 3) * 200, "1": 240}
		ws.souls_total = int(ws.souls_total) + 840 + (d % 3) * 200
	# Two keepers: one of the side's faction (doubled), one not.
	var want := "celestial" if side == "heaven" else "infernal"
	var mine := ""
	var other := ""
	for h: Dictionary in model.owned_heroes():
		var f := str(hero_def(str(h.id)).get("faction", ""))
		if f == want and mine == "":
			mine = str(h.id)
		elif f != want and f != "fallen" and other == "":
			other = str(h.id)
	if mine != "":
		ws.keepers["0"] = mine
	if other != "":
		ws.keepers["2"] = other
	# Two raised buildings (the levels).
	ws["levels"] = {"0": 3, "2": 2}
	_flush()


func rival_unlocked() -> bool:
	return model.rival_unlocked()


## The Rival view (GameModel.rival): name, team, ace, record, feed, prints, tags, haul, line ...
func rival() -> Dictionary:
	var r := model.rival()
	_flush()
	return r


## True when a haul is waiting or her feed has news (the Lobby's RIVAL light).
func rival_alert() -> bool:
	var r := model.rival_alert()
	_flush()
	return r


## The first visit: she introduces herself. Result {ok, value: {line}, error}.
func rival_meet() -> Dictionary:
	var r := model.rival_meet()
	_flush()
	return r


## The player has read her feed.
func rival_seen() -> void:
	model.rival_seen()
	_flush()


func rival_battle_setup() -> Dictionary:
	var r := model.rival_battle_setup()
	_flush()
	return r


## Call after a fight with her. Result {ok, value: {victory, reward, print, haul, line, record}, error}.
func complete_rival(outcome: Dictionary) -> Dictionary:
	var r := model.complete_rival(outcome)
	_flush()
	return r


## Debug (throwaway saves): the next summon's prints take these looks, one per pull, e.g.
## [{"flaw": "shift"}, {"holo": true}].
func dev_print_looks(looks: Array) -> void:
	if not (OS.is_debug_build() and save_path == TEST_SAVE_PATH) and save_path != "":
		return
	model.dev_print_looks = looks.duplicate(true)


## Debug (throwaway saves): set her tags as if she had just won (you: true) or lost.
func dev_rival_tag(you: bool) -> void:
	var rs: Dictionary = state.get("rival", {})
	if rs.is_empty():
		return
	rs.tag_you = you
	rs.tag_her = not you
	model.changed_now = true
	_flush()


# ---------------------------------------------------------------- settings & dev

func setting(key: String) -> Variant:
	return model.setting(key)


func set_setting(key: String, value: Variant) -> void:
	model.set_setting(key, value)
	_flush()


## Dev tool: pretend `ms` milliseconds have passed (for idle testing).
func dev_skip_time(ms: int) -> void:
	model.dev_skip_time(ms)
	_flush()


func dev_add(currency_id: String, amount: int) -> void:
	model.dev_add(currency_id, amount)
	_flush()


## Test state for --rich: every hero, lots of currency, mid-campaign progress.
func make_rich_state() -> void:
	model.make_rich_state()
	_flush()
