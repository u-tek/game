class_name HeroKits
## Combat kits for the 15 heroes: base stats, one ultimate and two passives each.
## Owned by core logic. Identity (name, faction, role, rarity...) lives in heroes.gd;
## Game.hero_def(id) returns identity merged with the kit.
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

const PASSIVE_STARS: Array[int] = [3, 5]

const KITS := {
	# ---------------------------------------------------------------- CELESTIAL
	"seraphiel": {
		"base_stats": {"hp": 1710, "atk": 112, "def": 42, "spd": 96, "crit": 1200},
		"ultimate": {
			"id": "hymn_of_judgment", "name": "Hymn of Judgment",
			"description": "Sings the sky's final verse: 180% ATK to all enemies and Stuns them for 1.5 s.",
			"effects": [
				{"type": "damage", "target": "enemy_all", "mult_bp": 18000},
				{"type": "status", "target": "enemy_all", "status": "stun", "duration_ms": 1500},
			],
		},
		"passives": [
			{"id": "radiant_aria", "name": "Radiant Aria", "unlock_stars": 3,
				"description": "Basic attacks have a 25% chance to Stun the target for 1 s.",
				"effects": [{"type": "on_hit_status", "status": "stun", "chance_bp": 2500, "duration_ms": 1000}]},
			{"id": "choir_eternal", "name": "Choir Eternal", "unlock_stars": 5,
				"description": "+20% ATK and +10% HP.",
				"effects": [{"type": "stat", "atk_bp": 2000, "hp_bp": 1000}]},
		],
	},
	"cassiel": {
		"base_stats": {"hp": 2810, "atk": 60, "def": 82, "spd": 90, "crit": 500},
		"ultimate": {
			"id": "dawnwall", "name": "Dawnwall",
			"description": "Raises the Gate Wardens' wall: shields all allies for 10% of her max HP and grants them +20% DEF for 5 s.",
			"effects": [
				{"type": "shield", "target": "ally_all", "pct_max_hp_bp": 1000},
				{"type": "status", "target": "ally_all", "status": "def_up", "duration_ms": 5000, "value_bp": 2000},
			],
		},
		"passives": [
			{"id": "unbroken_line", "name": "Unbroken Line", "unlock_stars": 3,
				"description": "+15% HP and +10% DEF.",
				"effects": [{"type": "stat", "hp_bp": 1500, "def_bp": 1000}]},
			{"id": "morning_vigil", "name": "Morning Vigil", "unlock_stars": 5,
				"description": "Battle start: gains a shield equal to 25% of her max HP.",
				"effects": [{"type": "start_shield", "pct_max_hp_bp": 2500}]},
		],
	},
	"liora": {
		"base_stats": {"hp": 1750, "atk": 76, "def": 48, "spd": 102, "crit": 500},
		"ultimate": {
			"id": "lullaby_of_mending", "name": "Lullaby of Mending",
			"description": "A lullaby that closes wounds: heals all allies for 240% ATK and grants Regen (40% ATK per second) for 4 s.",
			"effects": [
				{"type": "heal", "target": "ally_all", "mult_bp": 24000},
				{"type": "status", "target": "ally_all", "status": "regen", "duration_ms": 4000, "dot_mult_bp": 4000},
			],
		},
		"passives": [
			{"id": "soft_refrain", "name": "Soft Refrain", "unlock_stars": 3,
				"description": "Healing done +25%.",
				"effects": [{"type": "heal_bonus", "bp": 2500}]},
			{"id": "hymn_of_plenty", "name": "Hymn of Plenty", "unlock_stars": 5,
				"description": "Battle start: all allies gain +10% max HP.",
				"effects": [{"type": "team_aura", "hp_bp": 1000}]},
		],
	},
	"uriela": {
		"base_stats": {"hp": 1790, "atk": 92, "def": 48, "spd": 104, "crit": 1500},
		"ultimate": {
			"id": "sunlance", "name": "Sunlance",
			"description": "Hurls her blazing spear: 360% ATK to her target and breaks its armor, -40% DEF for 6 s.",
			"effects": [
				{"type": "damage", "target": "enemy_target", "mult_bp": 36000},
				{"type": "status", "target": "enemy_target", "status": "def_down", "duration_ms": 6000, "value_bp": 4000},
			],
		},
		"passives": [
			{"id": "bastion_drills", "name": "Bastion Drills", "unlock_stars": 3,
				"description": "+12% ATK.",
				"effects": [{"type": "stat", "atk_bp": 1200}]},
			{"id": "sunburst_edge", "name": "Sunburst Edge", "unlock_stars": 5,
				"description": "+15% crit chance and +25% crit damage.",
				"effects": [{"type": "stat", "crit_bp": 1500}, {"type": "crit_damage", "bp": 2500}]},
		],
	},
	"nuriel": {
		"base_stats": {"hp": 1500, "atk": 92, "def": 38, "spd": 122, "crit": 2200},
		"ultimate": {
			"id": "daybreak_ambush", "name": "Daybreak Ambush",
			"description": "Dives to the back row: strikes the weakest back-row enemy twice for 170% ATK each and Stuns it for 1 s.",
			"effects": [
				{"type": "damage", "target": "enemy_back_lowest", "mult_bp": 17000, "hits": 2},
				{"type": "status", "target": "enemy_back_lowest", "status": "stun", "duration_ms": 1000},
			],
		},
		"passives": [
			{"id": "light_step", "name": "Light Step", "unlock_stars": 3,
				"description": "+15% SPD.",
				"effects": [{"type": "stat", "spd_bp": 1500}]},
			{"id": "first_light", "name": "First Light", "unlock_stars": 5,
				"description": "Battle start: gains 400 energy.",
				"effects": [{"type": "start_energy", "amount": 400}]},
		],
	},
	# ---------------------------------------------------------------- INFERNAL
	"mordessa": {
		"base_stats": {"hp": 2050, "atk": 106, "def": 54, "spd": 104, "crit": 1800},
		"ultimate": {
			"id": "ninth_furnace", "name": "Ninth Furnace",
			"description": "Brings down the burning greatsword: 320% ATK to her target, 140% ATK to every other enemy, and Burns them all (50% ATK per second) for 4 s.",
			"effects": [
				{"type": "damage", "target": "enemy_target", "mult_bp": 32000},
				{"type": "damage", "target": "enemy_others", "mult_bp": 14000},
				{"type": "status", "target": "enemy_all", "status": "burn", "duration_ms": 4000, "dot_mult_bp": 5000},
			],
		},
		"passives": [
			{"id": "queens_wrath", "name": "Queen's Wrath", "unlock_stars": 3,
				"description": "+15% ATK and +10% crit chance.",
				"effects": [{"type": "stat", "atk_bp": 1500, "crit_bp": 1000}]},
			{"id": "unending_war", "name": "Unending War", "unlock_stars": 5,
				"description": "On kill: restores 20% of her max HP and gains 300 energy.",
				"effects": [{"type": "on_kill", "heal_pct_bp": 2000, "energy": 300}]},
		],
	},
	"brakka": {
		"base_stats": {"hp": 2960, "atk": 62, "def": 76, "spd": 86, "crit": 500},
		"ultimate": {
			"id": "magma_bulwark", "name": "Magma Bulwark",
			"description": "Plants his molten gauntlets: gains a shield of 40% max HP and Taunts all enemies for 5 s.",
			"effects": [
				{"type": "shield", "target": "self", "pct_max_hp_bp": 4000},
				{"type": "status", "target": "self", "status": "taunt", "duration_ms": 5000},
			],
		},
		"passives": [
			{"id": "molten_hide", "name": "Molten Hide", "unlock_stars": 3,
				"description": "Reflects 20% of damage taken back to the attacker.",
				"effects": [{"type": "thorns", "bp": 2000}]},
			{"id": "second_helping", "name": "Second Helping", "unlock_stars": 5,
				"description": "+25% HP.",
				"effects": [{"type": "stat", "hp_bp": 2500}]},
		],
	},
	"vesper": {
		"base_stats": {"hp": 1560, "atk": 106, "def": 38, "spd": 95, "crit": 1100},
		"ultimate": {
			"id": "ember_rain", "name": "Ember Rain",
			"description": "Forecast: fire. 140% ATK to all enemies and Burns them (50% ATK per second) for 6 s.",
			"effects": [
				{"type": "damage", "target": "enemy_all", "mult_bp": 14000},
				{"type": "status", "target": "enemy_all", "status": "burn", "duration_ms": 6000, "dot_mult_bp": 5000},
			],
		},
		"passives": [
			{"id": "ashen_forecast", "name": "Ashen Forecast", "unlock_stars": 3,
				"description": "Basic attacks have a 35% chance to Burn the target (30% ATK per second) for 3 s.",
				"effects": [{"type": "on_hit_status", "status": "burn", "chance_bp": 3500, "duration_ms": 3000, "dot_mult_bp": 3000}]},
			{"id": "inferno_thesis", "name": "Inferno Thesis", "unlock_stars": 5,
				"description": "+18% ATK.",
				"effects": [{"type": "stat", "atk_bp": 1800}]},
		],
	},
	"imra": {
		"base_stats": {"hp": 1600, "atk": 68, "def": 44, "spd": 106, "crit": 500},
		"ultimate": {
			"id": "lantern_pact", "name": "Lantern Pact",
			"description": "Strikes a deal with the whole team: all allies +20% ATK for 5 s, and every other ally gains 100 energy.",
			"effects": [
				{"type": "status", "target": "ally_all", "status": "atk_up", "duration_ms": 5000, "value_bp": 2000},
				{"type": "energy", "target": "ally_others", "amount": 100},
			],
		},
		"passives": [
			{"id": "fair_ish_deal", "name": "Fair-ish Deal", "unlock_stars": 3,
				"description": "Basic attacks have a 50% chance to Weaken the target: -15% ATK for 3 s.",
				"effects": [{"type": "on_hit_status", "status": "atk_down", "chance_bp": 5000, "duration_ms": 3000, "value_bp": 1500}]},
			{"id": "lantern_light", "name": "Lantern Light", "unlock_stars": 5,
				"description": "Battle start: all allies gain 150 energy.",
				"effects": [{"type": "team_start_energy", "amount": 150}]},
		],
	},
	"kessa": {
		"base_stats": {"hp": 1520, "atk": 96, "def": 38, "spd": 118, "crit": 2000},
		"ultimate": {
			"id": "twelfth_contract", "name": "Twelfth Contract",
			"description": "Pounces on the weakest enemy anywhere: 280% ATK, executing it if left below 25% HP (not bosses).",
			"effects": [
				{"type": "damage", "target": "enemy_lowest", "mult_bp": 28000, "execute_bp": 2500},
			],
		},
		"passives": [
			{"id": "hunters_instinct", "name": "Hunter's Instinct", "unlock_stars": 3,
				"description": "+25% damage to enemies below 50% HP.",
				"effects": [{"type": "low_hp_bonus", "bp": 2500}]},
			{"id": "nine_lives", "name": "Nine Lives", "unlock_stars": 5,
				"description": "Heals for 20% of damage dealt.",
				"effects": [{"type": "lifesteal", "bp": 2000}]},
		],
	},
	# ---------------------------------------------------------------- FALLEN
	"noctaire": {
		"base_stats": {"hp": 1750, "atk": 108, "def": 44, "spd": 124, "crit": 2500},
		"ultimate": {
			"id": "eclipse_harvest", "name": "Eclipse Harvest",
			"description": "Dives into the back row with her crescent scythe: 220% ATK to every back-row enemy, executing any left below 30% HP (not bosses).",
			"effects": [
				{"type": "damage", "target": "enemy_back_row", "mult_bp": 22000, "execute_bp": 3000},
			],
		},
		"passives": [
			{"id": "severed_wings", "name": "Severed Wings", "unlock_stars": 3,
				"description": "+15% crit chance and +10% SPD.",
				"effects": [{"type": "stat", "crit_bp": 1500, "spd_bp": 1000}]},
			{"id": "last_order", "name": "Last Order", "unlock_stars": 5,
				"description": "On kill: gains 500 energy.",
				"effects": [{"type": "on_kill", "energy": 500}]},
		],
	},
	"orrin": {
		"base_stats": {"hp": 2900, "atk": 68, "def": 84, "spd": 90, "crit": 500},
		"ultimate": {
			"id": "chains_of_the_oath", "name": "Chains of the Oath",
			"description": "Lashes out with broken chains: 130% ATK to front-row enemies and Stuns them for 2.5 s, then Weakens all enemies (-25% ATK) for 6 s.",
			"effects": [
				{"type": "damage", "target": "enemy_front_row", "mult_bp": 13000},
				{"type": "status", "target": "enemy_front_row", "status": "stun", "duration_ms": 2500},
				{"type": "status", "target": "enemy_all", "status": "atk_down", "duration_ms": 6000, "value_bp": 2500},
			],
		},
		"passives": [
			{"id": "oathbound", "name": "Oathbound", "unlock_stars": 3,
				"description": "Takes 12% less damage.",
				"effects": [{"type": "damage_reduction", "bp": 1200}]},
			{"id": "guarding_chains", "name": "Guarding Chains", "unlock_stars": 5,
				"description": "+20% DEF and +15% HP.",
				"effects": [{"type": "stat", "def_bp": 2000, "hp_bp": 1500}]},
		],
	},
	"sable": {
		"base_stats": {"hp": 1820, "atk": 80, "def": 50, "spd": 100, "crit": 500},
		"ultimate": {
			"id": "dusk_requiem", "name": "Dusk Requiem",
			"description": "Swings the censer for the lost: all enemies -50% DEF for 8 s, and all allies heal for 200% ATK.",
			"effects": [
				{"type": "status", "target": "enemy_all", "status": "def_down", "duration_ms": 8000, "value_bp": 5000},
				{"type": "heal", "target": "ally_all", "mult_bp": 20000},
			],
		},
		"passives": [
			{"id": "censer_smoke", "name": "Censer Smoke", "unlock_stars": 3,
				"description": "Basic attacks Expose the target: -25% DEF for 3 s.",
				"effects": [{"type": "on_hit_status", "status": "def_down", "chance_bp": 10000, "duration_ms": 3000, "value_bp": 2500}]},
			{"id": "vespers", "name": "Vespers", "unlock_stars": 5,
				"description": "Each basic attack also heals the most wounded ally for 70% ATK.",
				"effects": [{"type": "on_attack_heal", "mult_bp": 7000}]},
		],
	},
	"lucen": {
		"base_stats": {"hp": 1710, "atk": 94, "def": 46, "spd": 108, "crit": 1600},
		"ultimate": {
			"id": "twinfeather_flurry", "name": "Twinfeather Flurry",
			"description": "A dazzling flurry: 5 strikes of 85% ATK at random enemies, then +25% SPD for 5 s.",
			"effects": [
				{"type": "damage", "target": "enemy_random", "mult_bp": 8500, "hits": 5},
				{"type": "status", "target": "self", "status": "spd_up", "duration_ms": 5000, "value_bp": 2500},
			],
		},
		"passives": [
			{"id": "neither_side", "name": "Neither Side", "unlock_stars": 3,
				"description": "+10% ATK and +10% HP.",
				"effects": [{"type": "stat", "atk_bp": 1000, "hp_bp": 1000}]},
			{"id": "flourish", "name": "Flourish", "unlock_stars": 5,
				"description": "Basic attacks have a 30% chance to strike twice.",
				"effects": [{"type": "double_strike", "chance_bp": 3000}]},
		],
	},
	"ashra": {
		"base_stats": {"hp": 1560, "atk": 106, "def": 38, "spd": 96, "crit": 1000},
		"ultimate": {
			"id": "accidental_inferno", "name": "Accidental Inferno",
			"description": "Oops. 180% ATK to all enemies, +60% damage to enemies below 50% HP.",
			"effects": [
				{"type": "damage", "target": "enemy_all", "mult_bp": 18000, "low_hp_bonus_bp": 6000},
			],
		},
		"passives": [
			{"id": "careful_study", "name": "Careful Study", "unlock_stars": 3,
				"description": "+15% ATK.",
				"effects": [{"type": "stat", "atk_bp": 1500}]},
			{"id": "ash_cloud", "name": "Ash Cloud", "unlock_stars": 5,
				"description": "Her ultimate also Weakens all enemies: -15% ATK for 4 s.",
				"effects": [{"type": "ult_bonus", "effects": [
					{"type": "status", "target": "enemy_all", "status": "atk_down", "duration_ms": 4000, "value_bp": 1500},
				]}]},
		],
	},
}


static func get_kit(hero_id: String) -> Dictionary:
	return KITS.get(hero_id, {})


## Passives active at this star count.
static func active_passives(hero_id: String, stars: int) -> Array:
	var out: Array = []
	var kit: Dictionary = KITS.get(hero_id, {})
	for p in kit.get("passives", []):
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
