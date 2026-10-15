class_name HeroKits
extends RefCounted
## Combat kits (base_stats, ultimate, passives) of the heroes in res://data/heroes.json.
## Identity lives in the same records (see HeroData); Game.hero_def(id) returns both merged.
##
## base_stats: level 1 values at 1 star (the starting-star bonus of Epic/Legendary heroes
##   is applied on top, see StatCalc). hp/atk/def scale with level and stars; spd sets the
##   attack interval (100000 / spd ms); crit is a chance in basis points.
##
## ultimate: {id, name, description, effects: [Effect]}. Fires at 1000 energy.
##   Effect: {type, target, ...}
##     type "damage": mult_bp (of ATK), hits, low_hp_bonus_bp (extra vs targets < 50% HP),
##       execute_bp (non-boss targets left under this HP fraction die)
##     type "heal": mult_bp (of ATK)          type "shield": pct_max_hp_bp (of caster max HP)
##     type "status": status, duration_ms, value_bp (buff/debuff size) or dot_mult_bp
##       (burn/regen per second, of caster ATK)
##     type "energy": amount
##   target: enemy_target (normal target), enemy_others, enemy_all, enemy_front_row,
##     enemy_back_row, enemy_back_lowest, enemy_lowest, enemy_random (one per hit),
##     ally_all, ally_others, ally_lowest, self
##
## passives: [{id, name, description, unlock_stars, effects: [PassiveEffect]}]
##   stat {hp_bp, atk_bp, def_bp, spd_bp, crit_bp}  (applied by StatCalc, shows in hero stats)
##   start_energy {amount}, team_start_energy {amount}, team_aura {hp_bp, atk_bp},
##   start_shield {pct_max_hp_bp}, heal_bonus {bp}, thorns {bp}, damage_reduction {bp},
##   on_hit_status {status, chance_bp, duration_ms, value_bp, dot_mult_bp},
##   on_attack_heal {mult_bp}, low_hp_bonus {bp}, on_kill {heal_pct_bp, energy},
##   lifesteal {bp}, crit_damage {bp}, double_strike {chance_bp}, ult_bonus {effects}
##
## Statuses: stun, burn, regen, taunt, atk_up, atk_down, def_up, def_down, spd_up.

const KIT_KEYS: Array[String] = ["base_stats", "ultimate", "passives"]

static var _kits: Dictionary = {}


static func _ensure() -> void:
	if not _kits.is_empty():
		return
	for rec in GameData.dicts(GameData.heroes().get("heroes", [])):
		var kit := {}
		for k in KIT_KEYS:
			kit[k] = rec.get(k, {} if k != "passives" else [])
		_kits[str(rec.get("id", ""))] = kit


## {base_stats, ultimate, passives} or {} for an unknown hero. Shared: do not modify.
static func get_kit(hero_id: String) -> Dictionary:
	_ensure()
	return _kits.get(hero_id, {})


## Passives active at this star count.
static func active_passives(hero_id: String, stars: int) -> Array:
	var out: Array = []
	for p in get_kit(hero_id).get("passives", []):
		if stars >= int(p.unlock_stars):
			out.append(p)
	return out


## All passive effects of the given type active at this star count.
static func passive_effects(hero_id: String, stars: int, effect_type: String) -> Array:
	var out: Array = []
	for p in active_passives(hero_id, stars):
		for e in p.effects:
			if e.type == effect_type:
				out.append(e)
	return out
