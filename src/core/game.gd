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

## Emitted after any state change (UI refreshes on this).
signal changed
## Emitted for one-shot feedback the UI may toast, e.g. {"type": "quest_ready", "id": ...}
signal notify(event: Dictionary)

const SAVE_VERSION := 1

var state: Dictionary = {}
## Tests: fixed clock in ms. -1 = use real time.
var now_override_ms: int = -1
## Where the save lives. Empty string = don't persist (tests).
var save_path: String = "user://save.json"


func _ready() -> void:
	load_or_create()


# ---------------------------------------------------------------- time / save

## Current time in ms (real clock + state.dev_time_offset, or now_override_ms).
func now_ms() -> int:
	return 0 # TODO core


func load_or_create() -> void:
	pass # TODO core: load save_path or call new_game()


func new_game() -> void:
	pass # TODO core: fresh state (starter heroes, starting gems), emit changed


func save() -> void:
	pass # TODO core


func reset_save() -> void:
	pass # TODO core: delete save and start a new game


# ---------------------------------------------------------------- definitions

## Hero definition dictionary (see HeroData + stats/skills). {} if unknown.
func hero_def(hero_id: String) -> Dictionary:
	return HeroData.get_def(hero_id)


func all_hero_defs() -> Array[Dictionary]:
	return HeroData.all()


# ---------------------------------------------------------------- currencies

## Amount of a currency: "gold", "hero_exp", "gems", "scrolls", "dust".
func currency(id: String) -> int:
	return 0 # TODO core


# ---------------------------------------------------------------- idle rewards

## {elapsed_ms, cap_ms, full: bool, pending: Reward, per_hour: Reward,
##  quick_claims_left: int, quick_claim_cost: int}
func idle_status() -> Dictionary:
	return {} # TODO core


## Grants pending idle rewards; returns the Reward granted.
func claim_idle() -> Dictionary:
	return {} # TODO core


## Instantly grants 2h of idle rewards. Result {ok, value: Reward, error}.
func quick_claim() -> Dictionary:
	return {"ok": false, "error": "TODO"} # TODO core


# ---------------------------------------------------------------- campaign

func chapters() -> Array[Dictionary]:
	return [] # TODO core


func stages() -> Array[Dictionary]:
	return [] # TODO core


## Next stage to clear, or {} if all cleared.
func current_stage() -> Dictionary:
	return {} # TODO core


## BattleSetup for the player's formation vs this stage.
func stage_battle_setup(stage_index: int) -> Dictionary:
	return {} # TODO core


## Call after a stage battle. Result {ok, value: {reward, first_clear: bool}, error}.
func complete_stage(stage_index: int, outcome: Dictionary) -> Dictionary:
	return {"ok": false, "error": "TODO"} # TODO core


# ---------------------------------------------------------------- heroes

## Owned hero entries {id, level, stars, shards, gear}, sorted by power desc.
func owned_heroes() -> Array[Dictionary]:
	return [] # TODO core


func owns(hero_id: String) -> bool:
	return false # TODO core


## Final stats {hp, atk, def, spd, crit} for an owned hero (level, stars, gear).
func hero_stats(hero_id: String) -> Dictionary:
	return {} # TODO core


func hero_power(hero_id: String) -> int:
	return 0 # TODO core


func team_power() -> int:
	return 0 # TODO core


func max_level(hero_id: String) -> int:
	return 0 # TODO core


## {gold, hero_exp} or {} when at the level cap.
func level_up_cost(hero_id: String) -> Dictionary:
	return {} # TODO core


func level_up(hero_id: String) -> Dictionary:
	return {"ok": false, "error": "TODO"} # TODO core


## {shards, dust} needed for the next star, or {} at max stars.
func star_up_cost(hero_id: String) -> Dictionary:
	return {} # TODO core


func star_up(hero_id: String) -> Dictionary:
	return {"ok": false, "error": "TODO"} # TODO core


## Array of 5 hero ids or "" (index 0-1 front row, 2-4 back row).
func formation() -> Array:
	return ["", "", "", "", ""] # TODO core


func set_formation(slots: Array) -> Dictionary:
	return {"ok": false, "error": "TODO"} # TODO core


func auto_formation() -> void:
	pass # TODO core


## {faction: String, count: int, bonus_pct: int} for the current formation, or {}.
func faction_bonus() -> Dictionary:
	return {} # TODO core


# ---------------------------------------------------------------- gear

func gear_items() -> Array[Dictionary]:
	return [] # TODO core


func equip(hero_id: String, gear_uid: String) -> Dictionary:
	return {"ok": false, "error": "TODO"} # TODO core


func auto_equip(hero_id: String) -> void:
	pass # TODO core


# ---------------------------------------------------------------- summon

## BannerDef {id, name, cost_one, cost_ten, rates: {rare, epic, legendary} (basis points),
## pity_legendary, pool: [...]}
func banner() -> Dictionary:
	return {} # TODO core


func pity_count() -> int:
	return 0 # TODO core


func free_pull_available() -> bool:
	return false # TODO core


## count = 1 or 10. use_free only valid with count 1. Pays with scrolls first, then gems.
## Result {ok, value: Array of {hero_id, rarity, is_new, shards, pity}, error}.
func summon(count: int, use_free: bool = false) -> Dictionary:
	return {"ok": false, "error": "TODO"} # TODO core


# ---------------------------------------------------------------- quests & shop

## Array of {id, title, progress, goal, reward, claimed}
func quests() -> Array[Dictionary]:
	return [] # TODO core


func claim_quest(quest_id: String) -> Dictionary:
	return {"ok": false, "error": "TODO"} # TODO core


## Array of {id, name, description, price_label, reward, limit, purchased, tag}
func offers() -> Array[Dictionary]:
	return [] # TODO core


## Prototype: purchases are free test purchases. Result {ok, value: Reward, error}.
func buy_offer(offer_id: String) -> Dictionary:
	return {"ok": false, "error": "TODO"} # TODO core


# ---------------------------------------------------------------- settings & dev

func setting(key: String) -> Variant:
	return null # TODO core


func set_setting(key: String, value: Variant) -> void:
	pass # TODO core


## Dev tool: pretend `ms` milliseconds have passed (for idle testing).
func dev_skip_time(ms: int) -> void:
	pass # TODO core


func dev_add(currency_id: String, amount: int) -> void:
	pass # TODO core
