class_name BattleSim
extends RefCounted
## Deterministic, logic-only 5v5 battle (see docs/dev/architecture.md section 4).
##
##   var sim := BattleSim.new(setup)   # setup = {allies: [UnitSetup], enemies: [UnitSetup], seed}
##   while not sim.is_over(): events = sim.step()   # one 100 ms tick
##   sim.run_to_end()                                # skip: same rules and RNG, no events built
## Deterministic: integer math only and our own SeededRng, so a seed replays exactly.
##
## Rules in short:
## - Attack interval = 100000 / spd ms (spd 100 = 1.0 s). Stunned units do nothing.
## - Targeting: Taunt first; assassins hit the weakest back-row enemy; casters hit any enemy
##   (ranged, random); everyone else hits the front row first (same lane when possible).
##   Charmed units (the Infernal signature) hit their own side instead (a teammate in their lane,
##   else the first one) and can't cast their ultimate; alone, they fight on as usual.
## - Damage = ATK * mult * ATK / (ATK + DEF), +20% vs the faction you beat, crits x1.5,
##   +/-5% variance. Shields absorb first.
## - Energy: +100 per basic attack, + up to 500 for losing a full health bar (min 15 per
##   hit). Ultimate at 1000. Enemies always cast automatically; allies when
##   auto_ultimates is true or when request_ultimate() is called.
## - Faction bonus (3/4/5 of one faction: +6/10/15% HP and ATK) and boss multipliers are
##   applied when the sim is built. 90 s limit: a timeout is a defeat.
## Every tunable number comes from data/battle.json (and hero kits from data/heroes.json).
## The exact tick order, for ports, is in docs/dev/unity-port.md; golden fixtures in
## data/fixtures/battles.json.

## Algorithm constants (part of the API contract, not tuning): one tick is 100 ms of battle
## time; an ultimate fires at 1000 energy.
const TICK_MS := 100
const ENERGY_MAX := 1000
const NO_EXPIRY := 1 << 40
const STATUSES: Array[String] = ["stun", "burn", "regen", "taunt", "atk_up", "atk_down", "def_up", "def_down", "spd_up", "charm"]

static var _B: Dictionary = GameData.battle()
static var MAX_MS: int = int(_B.max_ms)
static var FACTIONS: Array[String] = GameData.strings(_B.factions)
## Counter wheel: attacker faction -> the faction it deals +advantage_bp damage to.
static var BEATS: Dictionary = _B.beats
static var ADVANTAGE_BP: int = int(_B.advantage_bp)
## {count: bp} for 3/4/5 allies of one faction (from the faction_bonus_bp array by count).
static var FACTION_BONUS_BP: Dictionary = _faction_bonus_table()
static var INTERVAL_K: int = int(_B.attack_interval_k)
static var MIN_INTERVAL_MS: int = int(_B.min_interval_ms)
static var MIN_SPD: int = int(_B.min_spd)
static var FIRST_ATTACK_BASE_MS: int = int(_B.first_attack_ms.base)
static var FIRST_ATTACK_PER_SLOT_MS: int = int(_B.first_attack_ms.per_slot)
static var FIRST_ATTACK_RANDOM_MS: int = int(_B.first_attack_ms.random_max)
static var ENERGY_PER_ATTACK: int = int(_B.energy.per_attack)
static var ENERGY_PER_FULL_HP: int = int(_B.energy.per_full_hp)
static var ENERGY_HIT_MIN: int = int(_B.energy.hit_min)
static var ENERGY_HIT_MAX: int = int(_B.energy.hit_max)
static var ENERGY_EVENT_STEP: int = int(_B.energy.event_step)
static var CRIT_DAMAGE_BP: int = int(_B.crit_damage_bp)
static var VARIANCE_BP: int = int(_B.variance_bp)
static var ATK_FLOOR_BP: int = int(_B.atk_floor_bp)
static var SHIELD_CAP_BP: int = int(_B.shield_cap_bp)
static var BOSS_HP_BP: int = int(_B.boss.hp_bp)
static var BOSS_ATK_BP: int = int(_B.boss.atk_bp)
static var BOSS_DEF_BP: int = int(_B.boss.def_bp)
static var BOSS_STUN_DIVISOR: int = int(_B.boss.stun_divisor)
static var STATUS_REFRESH_EVENT_MS: int = int(_B.status_refresh_event_ms)

## Runtime units. Contract keys: uid, hero_id, side, slot, max_hp, hp, shield, energy,
## alive, is_boss, statuses {name: remaining_ms}. Extra keys are internal.
var units: Array[Dictionary] = []
## Allies fire ultimates on their own when full (enemies always do).
var auto_ultimates: bool = true
## Battle time in ms.
var t_ms: int = 0
var max_ms: int = MAX_MS
var winner: String = ""
var rng: SeededRng

## False while run_to_end() skips ahead: rules run identically, but no event dictionaries
## are built (they are most of the cost of a long battle).
var _rec: bool = true

var _by_uid: Dictionary = {}
var _queued: Array[String] = []
var _events: Array = []
var _damage: Dictionary = {}
var _healing: Dictionary = {}
var _faction_bonus: Dictionary = {"ally": {}, "enemy": {}}
## Hot-path caches.
var _alive_cache: Dictionary = {}
var _alive_count: Dictionary = {"ally": 0, "enemy": 0}
var _energy_dirty: Array = []
var _full_energy: Array = []
var _timers := PackedInt32Array()
var _intervals := PackedInt32Array()
## Per unit: bit 0 stunned, bit 1 spd_up, bit 2 dead (mirrors statuses for the hot loop).
var _aflags := PackedByteArray()
## Earliest status expiry of any unit (skips the status pass on most ticks).
var _min_exp: int = NO_EXPIRY
const _F_STUN := 1
const _F_SPD := 2
const _F_DEAD := 4


static func _faction_bonus_table() -> Dictionary:
	var out := {}
	var arr: Array = _B.faction_bonus_bp
	for n in arr.size():
		if int(arr[n]) > 0:
			out[n] = int(arr[n])
	return out


## Faction bonus (basis points of HP and ATK) for `count` allies of one faction.
static func faction_bonus_bp(count: int) -> int:
	var arr: Array = _B.faction_bonus_bp
	return int(arr[clampi(count, 0, arr.size() - 1)])


func _init(setup: Dictionary = {}) -> void:
	rng = SeededRng.new(int(setup.get("seed", 1)))
	max_ms = int(setup.get("max_ms", MAX_MS))
	var i := 0
	for s in setup.get("allies", []):
		_add_unit(s, "ally", i)
		i += 1
	i = 0
	for s in setup.get("enemies", []):
		_add_unit(s, "enemy", i)
		i += 1
	_start_of_battle()


# ---------------------------------------------------------------- public API

## Advance one 100 ms tick. Returns this tick's events.
func step() -> Array:
	if winner != "":
		return []
	_events = []
	t_ms += TICK_MS
	_tick_statuses()
	if _check_end():
		return _flush()
	_tick_ultimates()
	if _check_end():
		return _flush()
	_tick_attacks()
	if not _check_end() and t_ms >= max_ms:
		winner = "enemy"
		_emit({"type": "end", "winner": winner, "timeout": true})
	return _flush()


## Queue a manual ultimate for an ally with full energy. It fires on the next step().
func request_ultimate(uid: String) -> bool:
	if not can_ultimate(uid) or _queued.has(uid):
		return false
	_queued.append(uid)
	return true


## True when this ally could cast its ultimate right now.
func can_ultimate(uid: String) -> bool:
	if winner != "" or not _by_uid.has(uid):
		return false
	var u: Dictionary = _by_uid[uid]
	return u.side == "ally" and u.alive and int(u.energy) >= ENERGY_MAX and not _silenced(u)


func is_over() -> bool:
	return winner != ""


func outcome() -> Dictionary:
	var allies_alive := 0
	var enemies_alive := 0
	for u in units:
		if u.alive:
			if u.side == "ally":
				allies_alive += 1
			else:
				enemies_alive += 1
	return {
		"winner": winner,
		"victory": winner == "ally",
		"duration_ms": t_ms,
		"allies_alive": allies_alive,
		"enemies_alive": enemies_alive,
		"timeout": winner == "enemy" and t_ms >= max_ms and enemies_alive > 0 and allies_alive > 0,
		"damage_dealt": _damage.duplicate(),
		"healing_done": _healing.duplicate(),
	}


## Simulate to the end (Skip). Returns outcome().
func run_to_end() -> Dictionary:
	var guard := max_ms / TICK_MS + 5
	_rec = false
	for u in _energy_dirty:
		u._ed = false
	_energy_dirty.clear()
	while winner == "" and guard > 0:
		step()
		guard -= 1
	_rec = true
	_refresh_remaining()
	return outcome()


func unit(uid: String) -> Dictionary:
	return _by_uid.get(uid, {})


## Faction bonus applied to a side: {faction, count, bonus_bp} or {}.
func faction_bonus(side: String) -> Dictionary:
	return _faction_bonus.get(side, {})


# ---------------------------------------------------------------- setup

func _add_unit(s: Dictionary, side: String, index: int) -> void:
	var hid: String = str(s.get("hero_id", ""))
	var ident := HeroData.get_def(hid)
	var kit := HeroKits.get_kit(hid)
	if ident.is_empty() or kit.is_empty():
		push_warning("BattleSim: unknown hero '%s'" % hid)
		return
	# awaken (optional, default 0): a Legendary's awakening tier, which adds her legend passive and
	# empowered ultimate to her passives (HeroKits.active_passives); the effects work as any passive's.
	var awaken: int = int(s.get("awaken", 0))
	var st: Dictionary = s.get("stats", {})
	if st.is_empty():
		st = StatCalc.stats(hid, int(s.get("level", 1)), int(s.get("stars", 1)), [], awaken)
	var boss := bool(s.get("is_boss", false))
	var hp: int = maxi(1, int(st.get("hp", 1)))
	var atk: int = maxi(1, int(st.get("atk", 1)))
	var def: int = maxi(0, int(st.get("def", 0)))
	var spd: int = maxi(MIN_SPD, int(st.get("spd", 100)))
	if boss:
		hp = hp * BOSS_HP_BP / 10000
		atk = atk * BOSS_ATK_BP / 10000
		def = def * BOSS_DEF_BP / 10000
	var stars: int = int(s.get("stars", 1))
	var slot: int = int(s.get("slot", index))
	var uid: String = str(s.get("uid", ""))
	if uid == "" or _by_uid.has(uid):
		uid = "%s%d" % ["a" if side == "ally" else "e", slot]
	var u := {
		"uid": uid, "hero_id": hid, "side": side, "slot": slot,
		"level": int(s.get("level", 1)), "stars": stars,
		"faction": ident.faction, "role": ident.role,
		"max_hp": hp, "hp": hp, "shield": 0, "energy": 0, "alive": true,
		"is_boss": boss, "statuses": {},
		"atk": atk, "def": def, "spd": spd, "crit": int(st.get("crit", 0)),
		"idx": units.size(),
		"beats": BEATS.get(ident.faction, ""),
		"mods": {}, "dots": {}, "dot_src": {}, "exp": {}, "next_exp": NO_EXPIRY,
		"pas": _collect_passives(hid, stars, awaken),
		"ult": kit.ultimate,
		"_ed": false,
	}
	_timers.append(FIRST_ATTACK_BASE_MS + slot * FIRST_ATTACK_PER_SLOT_MS + rng.range_int(0, FIRST_ATTACK_RANDOM_MS))
	_intervals.append(maxi(MIN_INTERVAL_MS, INTERVAL_K / spd))
	_aflags.append(0)
	units.append(u)
	_by_uid[uid] = u
	_alive_count[side] = int(_alive_count[side]) + 1
	_damage[uid] = 0
	_healing[uid] = 0


func _collect_passives(hid: String, stars: int, awaken: int = 0) -> Dictionary:
	var p := {
		"start_energy": 0, "team_start_energy": 0, "aura_hp": 0, "aura_atk": 0,
		"start_shield": 0, "heal_bonus": 0, "thorns": 0, "dr": 0, "on_hit": [],
		"atk_heal": 0, "low_hp": 0, "kill_heal": 0, "kill_energy": 0, "lifesteal": 0,
		"crit_dmg": 0, "double": 0, "ult_bonus": [],
	}
	for pas in HeroKits.active_passives(hid, stars, awaken):
		for e in pas.effects:
			match str(e.type):
				"start_energy": p.start_energy += int(e.amount)
				"team_start_energy": p.team_start_energy += int(e.amount)
				"team_aura":
					p.aura_hp += int(e.get("hp_bp", 0))
					p.aura_atk += int(e.get("atk_bp", 0))
				"start_shield": p.start_shield += int(e.pct_max_hp_bp)
				"heal_bonus": p.heal_bonus += int(e.bp)
				"thorns": p.thorns += int(e.bp)
				"damage_reduction": p.dr += int(e.bp)
				"on_hit_status": p.on_hit.append(e)
				"on_attack_heal": p.atk_heal += int(e.mult_bp)
				"low_hp_bonus": p.low_hp += int(e.bp)
				"on_kill":
					p.kill_heal += int(e.get("heal_pct_bp", 0))
					p.kill_energy += int(e.get("energy", 0))
				"lifesteal": p.lifesteal += int(e.bp)
				"crit_damage": p.crit_dmg += int(e.bp)
				"double_strike": p.double += int(e.chance_bp)
				"ult_bonus": p.ult_bonus.append_array(e.effects)
	return p


func _start_of_battle() -> void:
	for side in ["ally", "enemy"]:
		var team := _side_units(side)
		# Faction bonus: 3/4/5 of one faction -> HP and ATK for the whole side.
		var counts := {}
		for u in team:
			counts[u.faction] = int(counts.get(u.faction, 0)) + 1
		var best_f := ""
		var best_n := 0
		for f in FACTIONS:
			if int(counts.get(f, 0)) > best_n:
				best_n = int(counts.get(f, 0))
				best_f = f
		var fb: int = faction_bonus_bp(best_n)
		if fb > 0:
			_faction_bonus[side] = {"faction": best_f, "count": best_n, "bonus_bp": fb}
		var aura_hp := fb
		var aura_atk := fb
		var team_energy := 0
		for u in team:
			aura_hp += int(u.pas.aura_hp)
			aura_atk += int(u.pas.aura_atk)
			team_energy += int(u.pas.team_start_energy)
		for u in team:
			u.max_hp = int(u.max_hp) * (10000 + aura_hp) / 10000
			u.hp = u.max_hp
			u.atk = int(u.atk) * (10000 + aura_atk) / 10000
			if int(u.pas.start_shield) > 0:
				u.shield = int(u.max_hp) * int(u.pas.start_shield) / 10000
			u.energy = 0
			_gain_energy(u, int(u.pas.start_energy) + team_energy)


# ---------------------------------------------------------------- tick phases

## Once a second: burn and regen ticks. Every tick: expiries, and (while events are
## recorded, i.e. someone is watching) the remaining time of every status.
func _tick_statuses() -> void:
	var second := t_ms % 1000 == 0
	if second or t_ms >= _min_exp:
		for u in units:
			var sts: Dictionary = u.statuses
			if sts.is_empty():
				continue
			if second:
				if sts.has("burn"):
					var src: Dictionary = _by_uid.get(u.dot_src.get("burn", ""), u)
					_apply_damage(src, u, maxi(1, int(u.dots.get("burn", 1))), false, false, false, true)
					if not u.alive:
						continue
				if sts.has("regen"):
					var hsrc: Dictionary = _by_uid.get(u.dot_src.get("regen", ""), u)
					_heal(hsrc, u, int(u.dots.get("regen", 0)))
			if t_ms >= int(u.next_exp):
				_expire_statuses(u)
		var m := NO_EXPIRY
		for u in units:
			m = mini(m, int(u.next_exp))
		_min_exp = m
	if _rec:
		_refresh_remaining()


## statuses {name: remaining_ms} from the absolute expiry times.
func _refresh_remaining() -> void:
	for u in units:
		var sts: Dictionary = u.statuses
		if sts.is_empty():
			continue
		var ex: Dictionary = u.exp
		for k in sts:
			sts[k] = int(ex[k]) - t_ms


## Drops finished statuses and refreshes remaining times.
func _expire_statuses(u: Dictionary) -> void:
	var sts: Dictionary = u.statuses
	var ex: Dictionary = u.exp
	var next := NO_EXPIRY
	for k in ex.keys():
		var end_t: int = ex[k]
		if end_t <= t_ms:
			ex.erase(k)
			sts.erase(k)
			u.mods.erase(k)
			u.dots.erase(k)
			if k == "stun":
				_aflags[int(u.idx)] &= ~_F_STUN
			elif k == "spd_up":
				_aflags[int(u.idx)] &= ~_F_SPD
		else:
			sts[k] = end_t - t_ms
			next = mini(next, end_t)
	u.next_exp = next


func _tick_ultimates() -> void:
	if _queued.is_empty() and _full_energy.is_empty():
		return
	var queue := _queued.duplicate()
	_queued.clear()
	for uid in queue:
		var u: Dictionary = _by_uid[uid]
		if u.alive and int(u.energy) >= ENERGY_MAX and not _silenced(u):
			_cast_ultimate(u)
			if _check_end():
				return
	if _full_energy.is_empty():
		return
	var ready := _full_energy.duplicate()
	for ruid in ready:
		var u: Dictionary = _by_uid[ruid]
		if not u.alive or int(u.energy) < ENERGY_MAX or _silenced(u):
			continue
		if u.side == "ally" and not auto_ultimates:
			continue
		_cast_ultimate(u)
		if _check_end():
			return


func _tick_attacks() -> void:
	for i in units.size():
		var f: int = _aflags[i]
		var timer: int = _timers[i]
		if f == 0:
			timer -= TICK_MS
		elif f & (_F_STUN | _F_DEAD):
			continue
		else:
			timer -= TICK_MS * (10000 + int(units[i].mods.get("spd_up", 0))) / 10000
		if timer > 0:
			_timers[i] = timer
			continue
		_timers[i] = timer + _intervals[i]
		_basic_attack(units[i])
		if winner != "" or int(_alive_count.ally) <= 0 or int(_alive_count.enemy) <= 0:
			_check_end()
			return


# ---------------------------------------------------------------- actions

func _basic_attack(u: Dictionary) -> void:
	var target := _basic_target(u)
	if target.is_empty():
		return
	if _rec:
		_events.append({"type": "attack", "src": u.uid, "target": target.uid, "t": t_ms})
	_gain_energy(u, ENERGY_PER_ATTACK)
	_strike(u, target)
	var p: Dictionary = u.pas
	if int(p.double) > 0 and u.alive and target.alive and rng.chance_bp(int(p.double)):
		if _rec:
			_emit({"type": "attack", "src": u.uid, "target": target.uid})
		_strike(u, target)
	if int(p.atk_heal) > 0 and u.alive:
		var low := _lowest_ratio(_alive_of(u.side))
		if not low.is_empty():
			_heal(u, low, _atk(u) * int(p.atk_heal) / 10000 * (10000 + int(p.heal_bonus)) / 10000)


## One basic hit plus its on-hit effects (thorns, lifesteal, on-hit statuses).
func _strike(u: Dictionary, target: Dictionary) -> void:
	var dealt := _hit(u, target, 10000, false, 0)
	if dealt <= 0:
		return
	var on_hit: Array = u.pas.on_hit
	if not on_hit.is_empty() and target.alive:
		for e in on_hit:
			if rng.chance_bp(int(e.chance_bp)):
				_apply_status(u, target, str(e.status), int(e.duration_ms), int(e.get("value_bp", 0)), int(e.get("dot_mult_bp", 0)))
	var thorns: int = int(target.pas.thorns)
	if thorns > 0 and u.alive:
		_apply_damage(target, u, maxi(1, dealt * thorns / 10000), false, false, false, false)


func _cast_ultimate(u: Dictionary) -> void:
	var ult: Dictionary = u.ult
	var effects: Array = []
	effects.append_array(ult.effects)
	effects.append_array(u.pas.ult_bonus)
	u.energy = 0
	_full_energy.erase(u.uid)
	if _rec and not u._ed:
		u._ed = true
		_energy_dirty.append(u)
	var primary := _basic_target(u)
	var resolved: Array = []
	var seen := {}
	var target_ids: Array = []
	for e in effects:
		var ts := _resolve_targets(u, e, primary)
		resolved.append(ts)
		for t in ts:
			if not seen.has(t.uid):
				seen[t.uid] = true
				target_ids.append(t.uid)
	_emit({"type": "ultimate", "src": u.uid, "skill_id": ult.id, "skill_name": ult.name, "targets": target_ids})
	for i in effects.size():
		_apply_effect(u, effects[i], resolved[i])
		if winner != "" or _all_dead(_enemy_side(u.side)):
			return


func _apply_effect(u: Dictionary, e: Dictionary, targets: Array) -> void:
	match str(e.type):
		"damage":
			var mult: int = int(e.get("mult_bp", 10000))
			var low_bonus: int = int(e.get("low_hp_bonus_bp", 0))
			var execute: int = int(e.get("execute_bp", 0))
			if str(e.target) == "enemy_random":
				for t in targets:
					var tt: Dictionary = t
					if not tt.alive:
						var foes := _alive_of(_enemy_side(u.side))
						if foes.is_empty():
							return
						tt = rng.pick(foes)
					_hit(u, tt, mult, true, low_bonus)
				return
			var hits: int = maxi(1, int(e.get("hits", 1)))
			for t in targets:
				for h in hits:
					if not t.alive:
						break
					_hit(u, t, mult, true, low_bonus)
				if execute > 0 and t.alive and not t.is_boss and int(t.hp) * 10000 < int(t.max_hp) * execute:
					_emit_execute(u, t)
		"heal":
			var amount: int = _atk(u) * int(e.mult_bp) / 10000 * (10000 + int(u.pas.heal_bonus)) / 10000
			for t in targets:
				if t.alive:
					_heal(u, t, amount)
		"shield":
			var amt: int = int(u.max_hp) * int(e.pct_max_hp_bp) / 10000
			for t in targets:
				if t.alive:
					_add_shield(u, t, amt)
		"status":
			for t in targets:
				_apply_status(u, t, str(e.status), int(e.duration_ms), int(e.get("value_bp", 0)), int(e.get("dot_mult_bp", 0)))
		"energy":
			for t in targets:
				if t.alive:
					_gain_energy(t, int(e.amount))


# ---------------------------------------------------------------- targeting

func _enemy_side(side: String) -> String:
	return "enemy" if side == "ally" else "ally"


func _side_units(side: String) -> Array:
	var out: Array = []
	for u in units:
		if u.side == side:
			out.append(u)
	return out


## Alive units of a side (cached; rebuilt after a death). Callers must not modify it.
func _alive_of(side: String) -> Array:
	if _alive_cache.has(side):
		return _alive_cache[side]
	var out: Array = []
	for u in units:
		if u.alive and u.side == side:
			out.append(u)
	_alive_cache[side] = out
	return out


func _all_dead(side: String) -> bool:
	return int(_alive_count[side]) <= 0


func _lowest_ratio(list: Array) -> Dictionary:
	var best: Dictionary = {}
	var best_r := 1 << 40
	for u in list:
		var r: int = int(u.hp) * 10000 / maxi(1, int(u.max_hp))
		if r < best_r:
			best_r = r
			best = u
	return best


func _row(list: Array, back: bool) -> Array:
	var out: Array = []
	for u in list:
		if (int(u.slot) >= 2) == back:
			out.append(u)
	return out


func _basic_target(u: Dictionary) -> Dictionary:
	if not u.statuses.is_empty() and u.statuses.has("charm"):
		var turned := _charmed_target(u)
		if not turned.is_empty():
			return turned
	var foes := _alive_of(_enemy_side(u.side))
	if foes.is_empty():
		return {}
	for f in foes:
		if not f.statuses.is_empty() and f.statuses.has("taunt"):
			return f
	var role: String = u.role
	if role == "assassin":
		var back := _row(foes, true)
		return _lowest_ratio(back if not back.is_empty() else foes)
	if role == "caster":
		return rng.pick(foes)
	var lane: int = int(u.slot) % 2
	var first_front: Dictionary = {}
	for f in foes:
		var fs: int = f.slot
		if fs == lane:
			return f
		if fs < 2 and first_front.is_empty():
			first_front = f
	return first_front if not first_front.is_empty() else foes[0]


## A charmed unit's mark: the living teammate in its lane, else the first living teammate
## ({} when it is the last one standing).
func _charmed_target(u: Dictionary) -> Dictionary:
	var lane: int = int(u.slot) % 2
	var first: Dictionary = {}
	for m in _alive_of(u.side):
		if m.uid == u.uid:
			continue
		if int(m.slot) % 2 == lane:
			return m
		if first.is_empty():
			first = m
	return first


## Stunned or charmed: no ultimate.
func _silenced(u: Dictionary) -> bool:
	return not u.statuses.is_empty() and (u.statuses.has("stun") or u.statuses.has("charm"))


func _resolve_targets(u: Dictionary, e: Dictionary, primary: Dictionary) -> Array:
	var foe_side := _enemy_side(u.side)
	match str(e.get("target", "enemy_target")):
		"enemy_target":
			return [] if primary.is_empty() else [primary]
		"enemy_others":
			var others: Array = []
			for f in _alive_of(foe_side):
				if primary.is_empty() or f.uid != primary.uid:
					others.append(f)
			return others
		"enemy_all":
			return _alive_of(foe_side)
		"enemy_front_row":
			var foes := _alive_of(foe_side)
			var fr := _row(foes, false)
			return fr if not fr.is_empty() else _row(foes, true)
		"enemy_back_row":
			var foes2 := _alive_of(foe_side)
			var br := _row(foes2, true)
			return br if not br.is_empty() else _row(foes2, false)
		"enemy_back_lowest":
			var foes3 := _alive_of(foe_side)
			var b := _row(foes3, true)
			var pick := _lowest_ratio(b if not b.is_empty() else foes3)
			return [] if pick.is_empty() else [pick]
		"enemy_lowest":
			var low := _lowest_ratio(_alive_of(foe_side))
			return [] if low.is_empty() else [low]
		"enemy_random":
			var foes4 := _alive_of(foe_side)
			var out: Array = []
			if foes4.is_empty():
				return out
			for i in maxi(1, int(e.get("hits", 1))):
				out.append(rng.pick(foes4))
			return out
		"ally_all":
			return _alive_of(u.side)
		"ally_others":
			var mates: Array = []
			for a in _alive_of(u.side):
				if a.uid != u.uid:
					mates.append(a)
			return mates
		"ally_lowest":
			var l := _lowest_ratio(_alive_of(u.side))
			return [] if l.is_empty() else [l]
		"self":
			return [u]
	return []


# ---------------------------------------------------------------- effects

func _atk(u: Dictionary) -> int:
	var m: Dictionary = u.mods
	var bp: int = 10000 + int(m.get("atk_up", 0)) - int(m.get("atk_down", 0))
	return maxi(1, int(u.atk) * maxi(bp, ATK_FLOOR_BP) / 10000)


func _def(u: Dictionary) -> int:
	var m: Dictionary = u.mods
	var bp: int = 10000 + int(m.get("def_up", 0)) - int(m.get("def_down", 0))
	return maxi(0, int(u.def) * maxi(bp, 0) / 10000)


## Computes and applies one hit. Returns damage dealt. (Hot path: stat math inlined.)
func _hit(src: Dictionary, dst: Dictionary, mult_bp: int, from_ult: bool, low_hp_bonus_bp: int) -> int:
	if not dst.alive:
		return 0
	var atk: int = src.atk
	var sm: Dictionary = src.mods
	if not sm.is_empty():
		atk = maxi(1, atk * maxi(10000 + int(sm.get("atk_up", 0)) - int(sm.get("atk_down", 0)), ATK_FLOOR_BP) / 10000)
	var def: int = dst.def
	var dm: Dictionary = dst.mods
	if not dm.is_empty():
		def = maxi(0, def * maxi(10000 + int(dm.get("def_up", 0)) - int(dm.get("def_down", 0)), 0) / 10000)
	var dmg: int = atk * mult_bp / 10000 * atk / maxi(1, atk + def)
	var adv: bool = src.beats == dst.faction
	if adv:
		dmg = dmg * (10000 + ADVANTAGE_BP) / 10000
	var sp: Dictionary = src.pas
	var lb: int = int(sp.low_hp) + low_hp_bonus_bp
	if lb > 0 and int(dst.hp) * 2 < int(dst.max_hp):
		dmg = dmg * (10000 + lb) / 10000
	# One draw: low bits decide the crit, high bits the +/-5% variance.
	var r: int = rng.next_u32()
	var crit: bool = r % 10000 < int(src.crit)
	if crit:
		dmg = dmg * (CRIT_DAMAGE_BP + int(sp.crit_dmg)) / 10000
	dmg = dmg * (10000 - VARIANCE_BP + (r >> 14) % (2 * VARIANCE_BP + 1)) / 10000
	var dr: int = dst.pas.dr
	if dr > 0:
		dmg = dmg * (10000 - dr) / 10000
	if dmg < 1:
		dmg = 1
	_apply_damage(src, dst, dmg, crit, adv, from_ult, false)
	var ls: int = sp.lifesteal
	if ls > 0 and src.alive:
		_heal(src, src, dmg * ls / 10000)
	return dmg


func _apply_damage(src: Dictionary, dst: Dictionary, dmg: int, crit: bool, adv: bool, from_ult: bool, dot: bool) -> void:
	if not dst.alive:
		return
	var absorbed: int = mini(int(dst.shield), dmg)
	dst.shield = int(dst.shield) - absorbed
	var to_hp: int = dmg - absorbed
	dst.hp = maxi(0, int(dst.hp) - to_hp)
	_damage[src.uid] = int(_damage[src.uid]) + dmg
	if _rec:
		var ev := {"type": "damage", "src": src.uid, "target": dst.uid, "amount": dmg, "crit": crit,
			"advantage": adv, "from_ultimate": from_ult, "hp_after": dst.hp, "shield_after": dst.shield, "t": t_ms}
		if dot:
			ev["dot"] = true
		_events.append(ev)
	if int(dst.hp) <= 0:
		_kill(dst, src)
		return
	var before: int = dst.energy
	if before < ENERGY_MAX:
		var e: int = mini(ENERGY_MAX, before + clampi(dmg * ENERGY_PER_FULL_HP / int(dst.max_hp), ENERGY_HIT_MIN, ENERGY_HIT_MAX))
		dst.energy = e
		if e >= ENERGY_MAX:
			_full_energy.append(dst.uid)
		if _rec and not dst._ed and (e / ENERGY_EVENT_STEP != before / ENERGY_EVENT_STEP or e >= ENERGY_MAX):
			dst._ed = true
			_energy_dirty.append(dst)


func _emit_execute(src: Dictionary, dst: Dictionary) -> void:
	var rest: int = int(dst.hp) + int(dst.shield)
	dst.shield = 0
	dst.hp = 0
	_damage[src.uid] = int(_damage.get(src.uid, 0)) + rest
	_emit({"type": "damage", "src": src.uid, "target": dst.uid, "amount": rest, "crit": false,
		"advantage": false, "from_ultimate": true, "hp_after": 0, "shield_after": 0, "execute": true})
	_kill(dst, src)


func _kill(dst: Dictionary, killer: Dictionary) -> void:
	dst.alive = false
	_aflags[int(dst.idx)] = _F_DEAD
	_alive_count[dst.side] = int(_alive_count[dst.side]) - 1
	_alive_cache.erase(dst.side)
	_full_energy.erase(dst.uid)
	dst.hp = 0
	dst.shield = 0
	dst.energy = 0
	dst.statuses.clear()
	dst.exp.clear()
	dst.next_exp = NO_EXPIRY
	dst.mods.clear()
	dst.dots.clear()
	_queued.erase(dst.uid)
	_emit({"type": "death", "unit": dst.uid})
	if killer.alive and killer.side != dst.side:
		var p: Dictionary = killer.pas
		if int(p.kill_heal) > 0:
			_heal(killer, killer, int(killer.max_hp) * int(p.kill_heal) / 10000)
		if int(p.kill_energy) > 0:
			_gain_energy(killer, int(p.kill_energy))


func _heal(src: Dictionary, dst: Dictionary, amount: int) -> void:
	if not dst.alive or amount <= 0:
		return
	var healed: int = mini(amount, int(dst.max_hp) - int(dst.hp))
	if healed <= 0:
		return
	dst.hp = int(dst.hp) + healed
	_healing[src.uid] = int(_healing[src.uid]) + healed
	if _rec:
		_emit({"type": "heal", "src": src.uid, "target": dst.uid, "amount": healed, "hp_after": dst.hp})


func _add_shield(src: Dictionary, dst: Dictionary, amount: int) -> void:
	var cap: int = int(dst.max_hp) * SHIELD_CAP_BP / 10000
	var new_shield: int = mini(cap, int(dst.shield) + amount)
	var added: int = new_shield - int(dst.shield)
	if added <= 0:
		return
	dst.shield = new_shield
	if _rec:
		_emit({"type": "shield", "src": src.uid, "target": dst.uid, "amount": added, "shield_after": new_shield})


func _apply_status(src: Dictionary, dst: Dictionary, status: String, duration_ms: int, value_bp: int, dot_mult_bp: int) -> void:
	if not dst.alive or duration_ms <= 0:
		return
	if (status == "stun" or status == "charm") and dst.is_boss:
		duration_ms /= BOSS_STUN_DIVISOR
	var sts: Dictionary = dst.statuses
	var prev: int = int(sts.get(status, 0))
	var end_t: int = maxi(int(dst.exp.get(status, 0)), t_ms + duration_ms)
	dst.exp[status] = end_t
	sts[status] = end_t - t_ms
	dst.next_exp = mini(int(dst.next_exp), end_t)
	_min_exp = mini(_min_exp, end_t)
	if status == "stun":
		_aflags[int(dst.idx)] |= _F_STUN
	elif status == "spd_up":
		_aflags[int(dst.idx)] |= _F_SPD
	if value_bp > 0:
		dst.mods[status] = maxi(int(dst.mods.get(status, 0)), value_bp)
	if dot_mult_bp > 0:
		var amount: int = maxi(1, _atk(src) * dot_mult_bp / 10000)
		if status == "regen":
			amount = amount * (10000 + int(src.pas.heal_bonus)) / 10000
		if amount >= int(dst.dots.get(status, 0)):
			dst.dots[status] = amount
			dst.dot_src[status] = src.uid
	# Refreshing a status that is still running (by less than a second) is silent.
	if _rec and (prev <= 0 or duration_ms - prev >= STATUS_REFRESH_EVENT_MS):
		_emit({"type": "status", "src": src.uid, "target": dst.uid, "status": status, "duration_ms": duration_ms})


func _gain_energy(u: Dictionary, amount: int) -> void:
	if not u.alive:
		return
	var before: int = u.energy
	var e: int = mini(ENERGY_MAX, before + amount)
	if e == before:
		return
	u.energy = e
	if e >= ENERGY_MAX:
		_full_energy.append(u.uid)
	# Energy events only when the bar moves a visible step (50) or fills up.
	if _rec and not u._ed and (e / ENERGY_EVENT_STEP != before / ENERGY_EVENT_STEP or e >= ENERGY_MAX):
		u._ed = true
		_energy_dirty.append(u)


# ---------------------------------------------------------------- bookkeeping

func _emit(ev: Dictionary) -> void:
	if not _rec:
		return
	ev["t"] = t_ms
	_events.append(ev)


func _check_end() -> bool:
	if winner != "":
		return true
	if int(_alive_count.ally) > 0 and int(_alive_count.enemy) > 0:
		return false
	if _all_dead("ally"):
		winner = "enemy"
	elif _all_dead("enemy"):
		winner = "ally"
	else:
		return false
	_emit({"type": "end", "winner": winner})
	return true


func _flush() -> Array:
	if _energy_dirty.is_empty():
		return _events
	var tail: Array = []
	for u in _energy_dirty:
		u._ed = false
		tail.append({"type": "energy", "unit": u.uid, "energy": u.energy, "t": t_ms})
	_energy_dirty.clear()
	# Keep "end" as the very last event.
	if not _events.is_empty() and _events.back().type == "end":
		var end_ev: Dictionary = _events.pop_back()
		_events.append_array(tail)
		_events.append(end_ev)
	else:
		_events.append_array(tail)
	return _events
