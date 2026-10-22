"""Independent second implementation of the pure rules, written from docs/dev/unity-port.md
(sections 4-8: RNG, stats, battle, summon, idle, progression and awakening (8.6), gear), checked against
data/fixtures/*.json (also 8.5 prints, 9c the Rival and 9d the war). It proves the port document is precise enough, and is a compact
reference for a C# port. GameModel (session.json, save.json) is not covered here.

    python3 -B tests/port_check/check_port.py       # exit 1 if any fixture differs

Not part of tools/check. Data changes need nothing here; a rules change in src/core needs the
same change here (or delete this folder)."""
import json, sys, os
from rng import Rng, mix

ROOT = sys.argv[1] if len(sys.argv) > 1 else os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
def load(name):
    with open(os.path.join(ROOT, "data", name + ".json")) as f:
        return json.load(f)

HEROES = load("heroes")["heroes"]
HERO = {h["id"]: h for h in HEROES}
STAGES = load("stages")
ECO = load("economy")
BANNER_FILE = load("banner")
BANNER = BANNER_FILE["banners"][0]
BANNERS = {b["id"]: b for b in BANNER_FILE["banners"]}
EPOCH = BANNER_FILE.get("epoch_day", 0)
BATTLE = load("battle")
TOWER = load("tower")

def idiv(a, b):
    """C#-style truncating integer division."""
    q = abs(a) // abs(b)
    return q if (a >= 0) == (b > 0) else -q

def imod(a, b):
    return a - idiv(a, b) * b

# ------------------------------------------------------------------ section 6 stats
ST = ECO["stats"]
def active_passives(hid, stars, awaken=0):
    out = [p for p in HERO[hid]["passives"] if stars >= p["unlock_stars"]]
    lg = HERO[hid].get("legend")
    if awaken > 0 and lg:
        if awaken >= lg["passive"].get("unlock_awaken", 1):
            out.append(lg["passive"])
        ub = lg["ult_bonus"]
        if awaken >= ub.get("unlock_awaken", 2):
            out.append({"effects": [{"type": "ult_bonus", "effects": ub["effects"]}]})
    return out

def awaken_bp(a):
    t = ECO["heroes"]["awaken_stat_bp"]
    return 0 if a <= 0 or not t else t[min(a, len(t)) - 1]

def stats(hid, level, stars, gear=(), awaken=0):
    base = HERO[hid]["base_stats"]
    lm = 10000 + (max(level, 1) - 1) * ST["level_growth_bp"]
    sm = 10000 + (max(stars, 1) - 1) * ST["star_growth_bp"]
    g = {k: 0 for k in ("hp", "atk", "def", "spd", "crit")}
    for it in gear:
        for k, v in it.get("stats", {}).items():
            g[k] = g.get(k, 0) + v
    bonus = {k: 0 for k in ("hp_bp", "atk_bp", "def_bp", "spd_bp", "crit_bp")}
    for p in active_passives(hid, stars, awaken):
        for e in p["effects"]:
            if e["type"] == "stat":
                for k in bonus:
                    bonus[k] += e.get(k, 0)
    aw = awaken_bp(awaken)
    out = {}
    for k in ("hp", "atk", "def"):
        v = idiv(idiv(base[k] * lm, 10000) * sm, 10000) + g[k]
        out[k] = idiv(v * (10000 + bonus[k + "_bp"] + aw), 10000)
    out["spd"] = idiv((base["spd"] + (max(stars, 1) - 1) * ST["spd_per_star"] + g["spd"]) * (10000 + bonus["spd_bp"] + aw), 10000)
    out["crit"] = min(idiv((base["crit"] + g["crit"] + bonus["crit_bp"]) * (10000 + aw), 10000), ST["crit_cap_bp"])
    return out

def power(st):
    hp, atk, de, spd, crit = st.get("hp", 0), st.get("atk", 0), st.get("def", 0), st.get("spd", 100), st.get("crit", 0)
    raw = idiv(hp, 2) + atk * 8 + de * 6
    return idiv(idiv(idiv(raw * spd, 100) * (20000 + crit), 20000), 5)

def gear_score(it):
    s = it.get("stats", {})
    return idiv(s.get("hp", 0), 2) + s.get("atk", 0) * 8 + s.get("def", 0) * 6 + s.get("spd", 0) * 15 + idiv(s.get("crit", 0), 6)

def echo_stats(hid, level, stars, echo_bp):
    st = stats(hid, level, stars)
    for k in ("hp", "atk", "def"):
        st[k] = max(1, idiv(st[k] * echo_bp, 10000))
    return st

def start_stars(rarity):
    return ECO["heroes"]["start_stars"].get(rarity, 1)

def built_stages():
    out = []
    for ci, ch in enumerate(STAGES["chapters"]):
        for li, s in enumerate(ch["stages"]):
            echo_bp = idiv(STAGES["echo_stat_bp"] * s["strength_bp"], 10000)
            enemies = []
            for e in s["enemies"]:
                st = max(e.get("stars", s["stars"]), start_stars(HERO[e["hero_id"]]["rarity"]))
                enemies.append({"hero_id": e["hero_id"], "level": s["level"] + e.get("level_bonus", 0), "stars": st,
                                "slot": e["slot"], "is_boss": bool(e.get("boss", False)), "echo_bp": echo_bp})
            out.append({"index": len(out), "id": "%d-%d" % (ci + 1, li + 1), "enemies": enemies,
                        "recommended_power": s["recommended_power"], "first_clear_reward": s["first_clear_reward"]})
    return out

def tower_floor(f):
    """The Spire (docs/dev/unity-port.md 9b): floor f at campaign stage f's difficulty, a seeded team."""
    raws = [s for ch in STAGES["chapters"] for s in ch["stages"]]
    n = len(raws)
    raw = raws[min(f - 1, n - 1)]
    past = max(0, f - n)
    level = raw["level"] + past * TOWER["level_per_floor_past"]
    stars = min(raw["stars"] + idiv(past, TOWER["stars_every_past"]), ECO["heroes"]["max_stars"])
    echo_bp = idiv(STAGES["echo_stat_bp"] * TOWER["strength_bp"], 10000)
    boss = f % TOWER["boss_every"] == 0
    boss_id = TOWER["bosses"][(idiv(f, TOWER["boss_every"]) - 1) % len(TOWER["bosses"])] if boss else ""
    pool = [h["id"] for h in HEROES if h["id"] != boss_id]
    r = Rng(mix(TOWER["seed"], f))
    picks = []
    while len(picks) < (4 if boss else 5):
        i = r.range_int(0, len(pool) - 1)
        picks.append(pool.pop(i))
    fp = ECO["formation"]["front_priority"]
    order = sorted(range(len(picks)), key=lambda i: (-fp.get(HERO[picks[i]]["role"], 0), i))
    slots = [0, 1, 3, 4] if boss else [0, 1, 2, 3, 4]
    def enemy(hid, slot, is_boss):
        return {"hero_id": hid, "level": level, "stars": max(stars, start_stars(HERO[hid]["rarity"])), "slot": slot,
                "is_boss": is_boss, "echo_bp": echo_bp}
    enemies = [enemy(picks[order[k]], slots[k], False) for k in range(len(order))]
    if boss:
        enemies.append(enemy(boss_id, 2, True))
    enemies.sort(key=lambda e: e["slot"])
    rec = idiv(raws[min(f - 1, n - 1)]["recommended_power"] * TOWER["rec_bp"], 10000)
    rec = idiv(rec * (10000 + TOWER["rec_past_bp"] * past), 10000)
    R = TOWER["rewards"]
    gold = R["gold_base"] + R["gold_per_floor"] * f
    reward = {"gold": gold, "hero_exp": idiv(gold * R["hero_exp_bp"], 10000), "dust": R["dust_base"] + idiv(f, R["dust_every"])}
    gems = R["gems"] if f % R["gems_every"] == 0 else 0
    if boss:
        gems += R["boss_gems"]
        reward["scrolls"] = R["boss_scrolls"]
        reward["gear_drops"] = [{"slot": R["gear_slots"][(idiv(f, TOWER["boss_every"]) - 1) % len(R["gear_slots"])],
                                 "tier": max(1, min(1 + idiv(f, R["gear_tier_every"]), G_MAX_TIER))}]
    if gems > 0:
        reward["gems"] = gems
    bgs = TOWER["backgrounds"]
    return {"id": "F%d" % f, "enemies": enemies, "is_boss": boss,
            "background": bgs[idiv(f - 1, TOWER["floors_per_background"]) % len(bgs)],
            "recommended_power": rec, "first_clear_reward": reward}

G_MAX_TIER = ECO["gear"]["max_tier"]

def fb_bp(count):
    arr = BATTLE["faction_bonus_bp"]
    return arr[max(0, min(count, len(arr) - 1))]

def enemy_power(enemies):
    counts = {}
    for e in enemies:
        f = HERO[e["hero_id"]]["faction"]
        counts[f] = counts.get(f, 0) + 1
    fb = max([fb_bp(min(c, 5)) for c in counts.values()] + [0])
    total = 0
    B = BATTLE["boss"]
    for e in enemies:
        st = echo_stats(e["hero_id"], e["level"], e["stars"], e["echo_bp"])
        st["hp"] = idiv(st["hp"] * (10000 + fb), 10000)
        st["atk"] = idiv(st["atk"] * (10000 + fb), 10000)
        if e["is_boss"]:
            st["hp"] = idiv(st["hp"] * B["hp_bp"], 10000)
            st["atk"] = idiv(st["atk"] * B["atk_bp"], 10000)
            st["def"] = idiv(st["def"] * B["def_bp"], 10000)
        total += power(st)
    return total

# ------------------------------------------------------------------ section 8
H = ECO["heroes"]
def level_cost(L):
    c = H["level_cost"]
    e = c["exp_base"] + c["exp_per_level"] * L + c["exp_per_level_squared"] * L * L
    return {"gold": e + idiv(e, c["gold_exp_divisor"]) + c["gold_per_level"] * L, "hero_exp": e}
def level_cap(s):
    return H["level_cap_base"] + H["level_cap_per_star"] * max(1, min(s, H["max_stars"]))
def star_shards(s):
    return 0 if s < 1 or s >= H["max_stars"] else H["star_shards"][s]
def shards_to_max(s):
    return sum(H["star_shards"][k] for k in range(max(s, 1), H["max_stars"]))
def dps(r): return H["dust_per_shard"].get(r, H["dust_per_shard"]["rare"])
def dpe(r): return H["dust_per_excess_shard"].get(r, H["dust_per_excess_shard"]["rare"])
def star_up_cost(s, have, r):
    need = star_shards(s)
    if need <= 0: return {}
    return {"shards": need, "dust": max(0, need - have) * dps(r), "shards_have": have, "shards_used": min(have, need), "dust_per_shard": dps(r)}
def max_awaken(r):
    return len(H["awaken_shards"]) if r in H["awaken_rarities"] else 0
def awaken_left(a, r):
    return sum(H["awaken_shards"][t] for t in range(max(0, min(a, max_awaken(r))), max_awaken(r)))
def add_shards(s, have, n, r, a=0):
    keep = min(n, max(0, shards_to_max(s) + awaken_left(a, r) - have))
    return {"shards": have + keep, "dust": (n - keep) * dpe(r)}
def awaken_cost(s, a, have, r):
    if a < 0 or a >= max_awaken(r): return {}
    need, base = H["awaken_shards"][a], H["awaken_dust"][a]
    return {"tier": a + 1, "shards": need, "dust": base + max(0, need - have) * dps(r), "dust_base": base, "shards_have": have,
            "shards_used": min(have, need), "dust_per_shard": dps(r), "min_stars": H["awaken_min_stars"], "stars_ok": s >= H["awaken_min_stars"]}
def affordable(L, cap, gold, xp):
    n = 0
    while L + n < cap:
        c = level_cost(L + n)
        if gold < c["gold"] or xp < c["hero_exp"]: break
        gold -= c["gold"]; xp -= c["hero_exp"]; n += 1
    return n

I = ECO["idle"]
def per_hour(c):
    c = max(c, 0)
    return {k: v + idiv(I["per_10_stages_per_hour"].get(k, 0) * c, 10) for k, v in I["base_per_hour"].items()}
def elapsed(now, last):
    return 0 if now < last else min(now - last, I["cap_ms"])
def accrue(el, rates, carry, gear_ms):
    reward, nc = {}, {}
    for k, v in rates.items():
        tot = v * el + carry.get(k, 0)
        n = idiv(tot, 3600000); nc[k] = imod(tot, 3600000)
        if n > 0: reward[k] = n
    g = gear_ms + el
    gc = idiv(g, I["gear_every_ms"]); g -= gc * I["gear_every_ms"]
    if gc > 0: reward["gear_count"] = gc
    return {"reward": reward, "carry": nc, "gear_ms": g}
def qcost(u):
    c = I["quick_claim_costs"]
    return c[u] if 0 <= u < len(c) else -1
def quick_reward(rates, gear_ms):
    reward = {}
    for k, v in rates.items():
        n = idiv(v * I["quick_claim_ms"], 3600000)
        if n > 0: reward[k] = n
    g = gear_ms + I["quick_claim_ms"]; cnt = 0
    while g >= I["gear_every_ms"]:
        g -= I["gear_every_ms"]; cnt += 1
    return {"reward": reward, "gear_count": cnt, "gear_ms": g}

G = ECO["gear"]
def tier_for(c): return max(1, min(1 + idiv(c, G["stages_per_tier"]), G["max_tier"]))
def random_slot(seed, seq): return Rng(mix(seed + 31, seq * 13 + 5)).pick(G["slots"])
def make_item(slot, tier, seed, seq):
    t = max(1, min(tier, G["max_tier"]))
    s = slot if slot in G["slots"] else "weapon"
    r = Rng(mix(seed, seq))
    st = {}
    for ent in G["stats"][s]:
        st[ent["stat"]] = max(1, idiv(ent["by_tier"][t] * r.range_int(G["roll_min_pct"], G["roll_max_pct"]), 100))
    noun = r.pick(G["item_names"][s])
    return {"uid": "g%d" % seq, "slot": s, "tier": t, "name": "%s %s" % (G["tier_names"][t], noun), "stats": st, "equipped_by": ""}

def pool_by_rarity(b, faction=""):
    out = {"rare": [], "epic": [], "legendary": []}
    for i in b["pool"]:
        if faction and HERO[i]["faction"] != faction: continue
        out[HERO[i]["rarity"]].append(i)
    return out
def rarity_for_roll(r, b):
    R = b["rates"]
    if r < R["legendary"]: return "legendary"
    if r < R["legendary"] + R["epic"]: return "epic"
    return "rare"
def pull(b, seed, total, pity, count, opts=None):
    """Every banner kind: standard, featured (rate-up 50/50 + guarantee), faction (one faction's
    pool), wish (Legendary = target), envoy (no pity: pity_legendary 0)."""
    opts = opts or {}
    kind = b.get("kind", "standard")
    pool = pool_by_rarity(b, opts.get("faction", "") if kind == "faction" else "")
    feat = opts.get("featured", "") if kind == "featured" else ""
    lost = opts.get("lost", False)
    target = opts.get("target", "") if kind == "wish" else ""
    others = [i for i in pool["legendary"] if i != feat]
    pmax = b.get("pity_legendary", 0)
    rng = Rng(mix(seed, total))
    res, got = [], False
    for i in range(count):
        rar = "legendary" if pmax > 0 and pity >= pmax - 1 else rarity_for_roll(rng.range_int(0, 9999), b)
        if count == 10 and i == 9 and not got and rar == "rare":
            rar = b["ten_pull_guarantee"]
        if rar != "rare": got = True
        if pmax > 0: pity = 0 if rar == "legendary" else pity + 1
        total += 1
        if rar == "legendary" and feat:
            if lost or rng.chance_bp(b.get("featured_bp", 5000)): hid = feat
            elif not others: hid = feat
            else: hid = rng.pick(others)
            lost = hid != feat
        elif rar == "legendary" and target:
            hid = target
        else:
            hid = rng.pick(pool[rar])
        r = {"hero_id": hid, "rarity": rar, "pity": pity}
        if kind == "featured": r["featured"] = hid == feat
        res.append(r)
    out = {"results": res, "pity": pity, "total_pulls": total}
    if kind == "featured": out["lost"] = lost
    return out
def period_index(day, epoch, days):
    return (day - epoch) // max(1, days)      # Python // floors, like the rules
def next_change_day(day, epoch, days):
    return epoch + (period_index(day, epoch, days) + 1) * max(1, days)
def rotation_pick(lst, day, epoch, days):
    return lst[period_index(day, epoch, days) % len(lst)] if lst else ""
def featured_for(b, day, epoch):
    return rotation_pick(b.get("featured_rotation", []), day, epoch, b.get("rotation_days", 7)) if b.get("kind") == "featured" else ""
def faction_for(b, day, epoch):
    return rotation_pick(b.get("faction_rotation", []), day, epoch, b.get("rotation_days", 1)) if b.get("kind") == "faction" else ""
def limit_period(b, day, epoch):
    p = b.get("limit", {}).get("period", "")
    return day if p == "day" else (period_index(day, epoch, 7) if p == "week" else -1)
def limit_resets_day(b, day, epoch):
    p = b.get("limit", {}).get("period", "")
    return day + 1 if p == "day" else (next_change_day(day, epoch, 7) if p == "week" else -1)

# ------------------------------------------------------------------ section 7 battle
B = BATTLE
TICK = 100
EMAX = 1000
EN = B["energy"]

class U: pass

class Sim:
    def __init__(self, setup):
        self.rng = Rng(setup.get("seed", 1))
        self.max_ms = setup.get("max_ms", B["max_ms"])
        self.units, self.by = [], {}
        self.t, self.winner = 0, ""
        self.auto = True
        self.queue, self.full, self.eflags = [], [], []
        self.enc_t, self.enc_n, self.ult_bonus = -1000000000, 0, 0
        self.spot, self.spot_t, self.mark = "", -1000000000, ""
        self.events = []
        self.dmg, self.heal_done = {}, {}
        for s in setup.get("allies", []): self.add(s, "ally")
        for s in setup.get("enemies", []): self.add(s, "enemy")
        self.start()

    def add(self, s, side):
        hid = s["hero_id"]
        if hid not in HERO: return
        aw = s.get("awaken", 0)
        st = s.get("stats") or stats(hid, s.get("level", 1), s.get("stars", 1), (), aw)
        u = U()
        u.hid, u.side, u.slot = hid, side, s.get("slot", 0)
        u.faction, u.role = HERO[hid]["faction"], HERO[hid]["role"]
        hp, atk, de = max(1, st.get("hp", 1)), max(1, st.get("atk", 1)), max(0, st.get("def", 0))
        spd = max(B["min_spd"], st.get("spd", 100))
        u.boss = bool(s.get("is_boss", False))
        if u.boss:
            hp = idiv(hp * B["boss"]["hp_bp"], 10000); atk = idiv(atk * B["boss"]["atk_bp"], 10000); de = idiv(de * B["boss"]["def_bp"], 10000)
        uid = s.get("uid", "")
        if uid == "" or uid in self.by:
            uid = ("a" if side == "ally" else "e") + str(u.slot)
        u.uid = uid
        u.max_hp, u.hp, u.shield, u.energy, u.alive = hp, hp, 0, 0, True
        u.atk, u.de, u.crit = atk, de, st.get("crit", 0)
        u.st_end, u.mods, u.dots, u.dot_src = {}, {}, {}, {}
        u.flag = False
        p = dict(start_energy=0, team_start_energy=0, aura_hp=0, aura_atk=0, start_shield=0, heal_bonus=0, thorns=0, dr=0,
                 on_hit=[], atk_heal=0, low_hp=0, kill_heal=0, kill_energy=0, lifesteal=0, crit_dmg=0, double=0, ult_bonus=[])
        for pas in active_passives(hid, s.get("stars", 1), aw):
            for e in pas["effects"]:
                t = e["type"]
                if t == "start_energy": p["start_energy"] += e["amount"]
                elif t == "team_start_energy": p["team_start_energy"] += e["amount"]
                elif t == "team_aura": p["aura_hp"] += e.get("hp_bp", 0); p["aura_atk"] += e.get("atk_bp", 0)
                elif t == "start_shield": p["start_shield"] += e["pct_max_hp_bp"]
                elif t == "heal_bonus": p["heal_bonus"] += e["bp"]
                elif t == "thorns": p["thorns"] += e["bp"]
                elif t == "damage_reduction": p["dr"] += e["bp"]
                elif t == "on_hit_status": p["on_hit"].append(e)
                elif t == "on_attack_heal": p["atk_heal"] += e["mult_bp"]
                elif t == "low_hp_bonus": p["low_hp"] += e["bp"]
                elif t == "on_kill": p["kill_heal"] += e.get("heal_pct_bp", 0); p["kill_energy"] += e.get("energy", 0)
                elif t == "lifesteal": p["lifesteal"] += e["bp"]
                elif t == "crit_damage": p["crit_dmg"] += e["bp"]
                elif t == "double_strike": p["double"] += e["chance_bp"]
                elif t == "ult_bonus": p["ult_bonus"] += e["effects"]
        u.p = p
        u.ult = HERO[hid]["ultimate"]
        fa = B["first_attack_ms"]
        u.timer = fa["base"] + u.slot * fa["per_slot"] + self.rng.range_int(0, fa["random_max"])
        u.interval = max(B["min_interval_ms"], idiv(B["attack_interval_k"], spd))
        self.units.append(u); self.by[uid] = u
        self.dmg[uid] = 0; self.heal_done[uid] = 0

    def start(self):
        for side in ("ally", "enemy"):
            team = [u for u in self.units if u.side == side]
            counts = {}
            for u in team: counts[u.faction] = counts.get(u.faction, 0) + 1
            bn = 0
            for f in B["factions"]:
                if counts.get(f, 0) > bn: bn = counts[f]
            fb = fb_bp(min(bn, 5))
            ah = fb + sum(u.p["aura_hp"] for u in team)
            aa = fb + sum(u.p["aura_atk"] for u in team)
            te = sum(u.p["team_start_energy"] for u in team)
            for u in team:
                u.max_hp = idiv(u.max_hp * (10000 + ah), 10000); u.hp = u.max_hp
                u.atk = idiv(u.atk * (10000 + aa), 10000)
                if u.p["start_shield"] > 0: u.shield = idiv(u.max_hp * u.p["start_shield"], 10000)
                u.energy = 0
                self.gain(u, u.p["start_energy"] + te)

    # ---------------- helpers
    def emit(self, ev):
        ev["t"] = self.t; self.events.append(ev)
    def setflag(self, u):
        if not u.flag: u.flag = True; self.eflags.append(u)
    def living(self, side): return [u for u in self.units if u.alive and u.side == side]
    def foe(self, side): return "enemy" if side == "ally" else "ally"
    def stunned(self, u): return "stun" in u.st_end

    # stunned or charmed: no ultimate (charm: battle_sim.gd _silenced)
    def silenced(self, u): return "stun" in u.st_end or "charm" in u.st_end
    def lowest(self, lst):
        best, br = None, None
        for u in lst:
            r = idiv(u.hp * 10000, max(1, u.max_hp))
            if br is None or r < br: best, br = u, r
        return best
    def Atk(self, u):
        m = u.mods
        bp = 10000 + m.get("atk_up", 0) - m.get("atk_down", 0) + (B["spotlight"]["atk_bp"] if u.uid == self.spot else 0)
        return max(1, idiv(u.atk * max(bp, B["atk_floor_bp"]), 10000))
    def Def(self, u):
        m = u.mods
        return max(0, idiv(u.de * max(10000 + m.get("def_up", 0) - m.get("def_down", 0), 0), 10000))

    def check_end(self):
        if self.winner: return True
        a, e = self.living("ally"), self.living("enemy")
        if a and e: return False
        self.winner = "enemy" if not a else "ally"
        self.emit({"type": "end", "winner": self.winner})
        return True

    def flush(self):
        evs = self.events
        if self.eflags:
            tail = [{"type": "energy", "unit": u.uid, "energy": u.energy, "t": self.t} for u in self.eflags]
            for u in self.eflags: u.flag = False
            self.eflags = []
            if evs and evs[-1]["type"] == "end":
                end = evs.pop(); evs += tail; evs.append(end)
            else:
                evs += tail
        return evs

    def step(self):
        if self.winner: return []
        self.events = []
        self.t += TICK
        self.status_phase()
        if self.check_end(): return self.flush()
        self.ult_phase()
        if self.check_end(): return self.flush()
        self.attack_phase()
        if not self.check_end() and self.t >= self.max_ms:
            self.winner = "enemy"
            self.emit({"type": "end", "winner": "enemy", "timeout": True})
        return self.flush()

    def set_spotlight(self, uid):
        S = B["spotlight"]; u = self.by.get(uid)
        if self.winner or u is None or uid == self.spot or u.side != "ally" or not u.alive or self.t - self.spot_t < S["switch_ms"]:
            return False
        self.spot, self.spot_t = uid, self.t
        return True

    def set_mark(self, uid):
        u = self.by.get(uid)
        if self.winner or u is None or uid == self.mark or u.side != "enemy" or not u.alive:
            return False
        self.mark = uid
        return True

    def request(self, uid):
        u = self.by.get(uid)
        if self.winner or u is None or u.side != "ally" or not u.alive or u.energy < EMAX or self.silenced(u) or uid in self.queue:
            return False
        self.queue.append(uid); return True

    def outcome(self):
        a = len(self.living("ally")); e = len(self.living("enemy"))
        return {"winner": self.winner, "victory": self.winner == "ally", "duration_ms": self.t, "allies_alive": a,
                "enemies_alive": e, "timeout": self.winner == "enemy" and self.t >= self.max_ms and a > 0 and e > 0,
                "damage_dealt": dict(self.dmg), "healing_done": dict(self.heal_done)}

    # ---------------- phases
    def status_phase(self):
        sec = self.t % 1000 == 0
        for u in self.units:
            if not u.st_end: continue
            if sec:
                if "burn" in u.st_end:
                    src = self.by.get(u.dot_src.get("burn", ""), u)
                    self.apply_damage(src, u, max(1, u.dots.get("burn", 1)), False, False, False, True)
                    if not u.alive: continue
                if "regen" in u.st_end:
                    src = self.by.get(u.dot_src.get("regen", ""), u)
                    self.heal(src, u, u.dots.get("regen", 0))
            for k in list(u.st_end):
                if u.st_end[k] <= self.t:
                    del u.st_end[k]; u.mods.pop(k, None); u.dots.pop(k, None)

    def ult_phase(self):
        q = self.queue; self.queue = []
        for uid in q:
            u = self.by[uid]
            if u.alive and u.energy >= EMAX and not self.silenced(u):
                self.cast(u, True)
                if self.check_end(): return
        for uid in list(self.full):
            u = self.by[uid]
            if not u.alive or u.energy < EMAX or self.silenced(u): continue
            if u.side == "ally" and not self.auto: continue
            self.cast(u, False)
            if self.check_end(): return

    def attack_phase(self):
        for u in self.units:
            if not u.alive or self.stunned(u): continue
            if "spd_up" in u.st_end:
                u.timer -= idiv(TICK * (10000 + u.mods.get("spd_up", 0)), 10000)
            else:
                u.timer -= TICK
            if u.timer > 0: continue
            u.timer += u.interval
            self.basic_attack(u)
            if self.winner or not self.living("ally") or not self.living("enemy"):
                self.check_end(); return

    # ---------------- actions
    def charmed_target(self, u):
        lane = u.slot % 2; first = None
        for m in self.living(u.side):
            if m is u: continue
            if m.slot % 2 == lane: return m
            if first is None: first = m
        return first

    def basic_target(self, u):
        if "charm" in u.st_end:
            turned = self.charmed_target(u)
            if turned is not None: return turned
        foes = self.living(self.foe(u.side))
        if not foes: return None
        for f in foes:
            if "taunt" in f.st_end: return f
        if u.side == "ally" and self.mark and self.by[self.mark].alive:
            return self.by[self.mark]
        if u.role == "assassin":
            back = [f for f in foes if f.slot >= 2]
            return self.lowest(back if back else foes)
        if u.role == "caster":
            return self.rng.pick(foes)
        lane = u.slot % 2
        first_front = None
        for f in foes:
            if f.slot == lane: return f
            if f.slot < 2 and first_front is None: first_front = f
        return first_front if first_front else foes[0]

    def basic_attack(self, u):
        tg = self.basic_target(u)
        if tg is None: return
        self.emit({"type": "attack", "src": u.uid, "target": tg.uid})
        self.gain(u, EN["per_attack"])
        self.strike(u, tg)
        p = u.p
        if p["double"] > 0 and u.alive and tg.alive and self.rng.chance_bp(p["double"]):
            self.emit({"type": "attack", "src": u.uid, "target": tg.uid})
            self.strike(u, tg)
        if p["atk_heal"] > 0 and u.alive:
            low = self.lowest(self.living(u.side))
            if low is not None:
                self.heal(u, low, idiv(idiv(self.Atk(u) * p["atk_heal"], 10000) * (10000 + p["heal_bonus"]), 10000))

    def strike(self, u, tg):
        dealt = self.hit(u, tg, 10000, False, 0)
        if dealt <= 0: return
        if tg.alive:
            for e in u.p["on_hit"]:
                if self.rng.chance_bp(e["chance_bp"]):
                    self.apply_status(u, tg, e["status"], e["duration_ms"], e.get("value_bp", 0), e.get("dot_mult_bp", 0))
        if tg.p["thorns"] > 0 and u.alive:
            self.apply_damage(tg, u, max(1, idiv(dealt * tg.p["thorns"], 10000)), False, False, False, False)

    def hit(self, src, dst, mult, from_ult, lowb):
        if not dst.alive: return 0
        a = self.Atk(src); d = self.Def(dst)
        dmg = idiv(idiv(a * mult, 10000) * a, max(1, a + d))
        adv = B["beats"].get(src.faction, "") == dst.faction
        if adv: dmg = idiv(dmg * (10000 + B["advantage_bp"]), 10000)
        lb = src.p["low_hp"] + lowb
        if lb > 0 and dst.hp * 2 < dst.max_hp: dmg = idiv(dmg * (10000 + lb), 10000)
        r = self.rng.next_u32()
        crit = r % 10000 < src.crit
        if crit: dmg = idiv(dmg * (B["crit_damage_bp"] + src.p["crit_dmg"]), 10000)
        V = B["variance_bp"]
        dmg = idiv(dmg * (10000 - V + (r >> 14) % (2 * V + 1)), 10000)
        if dst.p["dr"] > 0: dmg = idiv(dmg * (10000 - dst.p["dr"]), 10000)
        dmg = max(dmg, 1)
        self.apply_damage(src, dst, dmg, crit, adv, from_ult, False)
        if src.p["lifesteal"] > 0 and src.alive:
            self.heal(src, src, idiv(dmg * src.p["lifesteal"], 10000))
        return dmg

    def apply_damage(self, src, dst, dmg, crit, adv, ult, dot):
        if not dst.alive: return
        ab = min(dst.shield, dmg); dst.shield -= ab
        dst.hp = max(0, dst.hp - (dmg - ab))
        self.dmg[src.uid] += dmg
        ev = {"type": "damage", "src": src.uid, "target": dst.uid, "amount": dmg, "crit": crit, "advantage": adv,
              "from_ultimate": ult, "hp_after": dst.hp, "shield_after": dst.shield}
        if dot: ev["dot"] = True
        self.emit(ev)
        if dst.hp <= 0:
            self.kill(dst, src); return
        if dst.energy < EMAX:
            old = dst.energy
            e = min(EMAX, old + max(EN["hit_min"], min(EN["hit_max"], idiv(dmg * EN["per_full_hp"], dst.max_hp))))
            if e >= EMAX: self.full.append(dst.uid)
            if idiv(e, EN["event_step"]) != idiv(old, EN["event_step"]) or e >= EMAX: self.setflag(dst)
            dst.energy = e

    def execute(self, src, dst):
        rest = dst.hp + dst.shield
        dst.hp = 0; dst.shield = 0
        self.dmg[src.uid] += rest
        self.emit({"type": "damage", "src": src.uid, "target": dst.uid, "amount": rest, "crit": False, "advantage": False,
                   "from_ultimate": True, "hp_after": 0, "shield_after": 0, "execute": True})
        self.kill(dst, src)

    def heal(self, src, dst, n):
        if not dst.alive or n <= 0: return
        h = min(n, dst.max_hp - dst.hp)
        if h <= 0: return
        dst.hp += h; self.heal_done[src.uid] += h
        self.emit({"type": "heal", "src": src.uid, "target": dst.uid, "amount": h, "hp_after": dst.hp})

    def add_shield(self, src, dst, n):
        new = min(idiv(dst.max_hp * B["shield_cap_bp"], 10000), dst.shield + n)
        added = new - dst.shield
        if added <= 0: return
        dst.shield = new
        self.emit({"type": "shield", "src": src.uid, "target": dst.uid, "amount": added, "shield_after": new})

    def gain(self, u, n):
        if not u.alive: return
        if n > 0 and u.uid == self.spot: n = idiv(n * (10000 + B["spotlight"]["energy_bp"]), 10000)
        old = u.energy; e = min(EMAX, old + n)
        if e == old: return
        u.energy = e
        if e >= EMAX: self.full.append(u.uid)
        if idiv(e, EN["event_step"]) != idiv(old, EN["event_step"]) or e >= EMAX: self.setflag(u)

    def kill(self, dst, killer):
        dst.alive = False; dst.hp = 0; dst.shield = 0; dst.energy = 0
        dst.st_end.clear(); dst.mods.clear(); dst.dots.clear()
        if dst.uid in self.full: self.full.remove(dst.uid)
        if dst.uid in self.queue: self.queue.remove(dst.uid)
        self.emit({"type": "death", "unit": dst.uid})
        if killer.alive and killer.side != dst.side:
            if killer.p["kill_heal"] > 0: self.heal(killer, killer, idiv(killer.max_hp * killer.p["kill_heal"], 10000))
            if killer.p["kill_energy"] > 0: self.gain(killer, killer.p["kill_energy"])

    def apply_status(self, src, dst, status, dur, vbp, dot):
        if not dst.alive or dur <= 0: return
        if status in ("stun", "charm") and dst.boss: dur = idiv(dur, B["boss"]["stun_divisor"])
        prev = dst.st_end[status] - self.t if status in dst.st_end else 0
        dst.st_end[status] = max(dst.st_end.get(status, 0), self.t + dur)
        if vbp > 0: dst.mods[status] = max(dst.mods.get(status, 0), vbp)
        if dot > 0:
            amt = max(1, idiv(self.Atk(src) * dot, 10000))
            if status == "regen": amt = idiv(amt * (10000 + src.p["heal_bonus"]), 10000)
            if amt >= dst.dots.get(status, 0):
                dst.dots[status] = amt; dst.dot_src[status] = src.uid
        if prev <= 0 or dur - prev >= B["status_refresh_event_ms"]:
            self.emit({"type": "status", "src": src.uid, "target": dst.uid, "status": status, "duration_ms": dur})

    def resolve(self, u, e, primary):
        foes = self.living(self.foe(u.side)); mates = self.living(u.side)
        t = e.get("target", "enemy_target")
        if t == "enemy_target": return [] if primary is None else [primary]
        if t == "enemy_others": return [f for f in foes if primary is None or f.uid != primary.uid]
        if t == "enemy_all": return foes
        if t == "enemy_front_row":
            fr = [f for f in foes if f.slot < 2]; return fr if fr else [f for f in foes if f.slot >= 2]
        if t == "enemy_back_row":
            br = [f for f in foes if f.slot >= 2]; return br if br else [f for f in foes if f.slot < 2]
        if t == "enemy_back_lowest":
            br = [f for f in foes if f.slot >= 2]; p = self.lowest(br if br else foes); return [] if p is None else [p]
        if t == "enemy_lowest":
            p = self.lowest(foes); return [] if p is None else [p]
        if t == "enemy_random":
            if not foes: return []
            return [self.rng.pick(foes) for _ in range(max(1, e.get("hits", 1)))]
        if t == "ally_all": return mates
        if t == "ally_others": return [m for m in mates if m.uid != u.uid]
        if t == "ally_lowest":
            p = self.lowest(mates); return [] if p is None else [p]
        if t == "self": return [u]
        return []

    def cast(self, u, manual):
        E = B["encore"]
        self.ult_bonus = 0; step = 0
        if u.side == "ally":
            step = min(self.enc_n + 1, E["max_steps"]) if self.t - self.enc_t <= E["window_ms"] else 0
            self.enc_n, self.enc_t = step, self.t
            self.ult_bonus = step * (E["step_bp"] if manual else E["auto_step_bp"])
        effects = list(u.ult["effects"]) + list(u.p["ult_bonus"])
        u.energy = 0
        if u.uid in self.full: self.full.remove(u.uid)
        self.setflag(u)
        primary = self.basic_target(u)
        resolved, ids = [], []
        for e in effects:
            ts = self.resolve(u, e, primary)
            resolved.append(ts)
            for t in ts:
                if t.uid not in ids: ids.append(t.uid)
        ev = {"type": "ultimate", "src": u.uid, "skill_id": u.ult["id"], "skill_name": u.ult["name"], "targets": ids}
        if step > 0: ev["encore"] = step
        self.emit(ev)
        for e, ts in zip(effects, resolved):
            self.apply_effect(u, e, ts)
            if self.winner or not self.living(self.foe(u.side)): break
        self.ult_bonus = 0

    def apply_effect(self, u, e, ts):
        ty = e["type"]
        if ty == "damage":
            mult, lowb, ex = e.get("mult_bp", 10000), e.get("low_hp_bonus_bp", 0), e.get("execute_bp", 0)
            if self.ult_bonus > 0: mult = idiv(mult * (10000 + self.ult_bonus), 10000)
            if e.get("target") == "enemy_random":
                for t in ts:
                    if not t.alive:
                        foes = self.living(self.foe(u.side))
                        if not foes: return
                        t = self.rng.pick(foes)
                    self.hit(u, t, mult, True, lowb)
                return
            for t in ts:
                for _ in range(max(1, e.get("hits", 1))):
                    if not t.alive: break
                    self.hit(u, t, mult, True, lowb)
                if ex > 0 and t.alive and not t.boss and t.hp * 10000 < t.max_hp * ex:
                    self.execute(u, t)
        elif ty == "heal":
            n = idiv(idiv(self.Atk(u) * e["mult_bp"], 10000) * (10000 + u.p["heal_bonus"]), 10000)
            for t in ts:
                if t.alive: self.heal(u, t, n)
        elif ty == "shield":
            n = idiv(u.max_hp * e["pct_max_hp_bp"], 10000)
            for t in ts:
                if t.alive: self.add_shield(u, t, n)
        elif ty == "status":
            for t in ts:
                self.apply_status(u, t, e["status"], e["duration_ms"], e.get("value_bp", 0), e.get("dot_mult_bp", 0))
        elif ty == "energy":
            for t in ts:
                if t.alive: self.gain(t, e["amount"])


# ------------------------------------------------------------------ section 8.5 prints (misprints)
PR = load("prints")
EARLY = PR["early_serial"]

def edition_on(b, day, epoch):
    ed = PR["editions"].get(b, PR["editions"]["standard"])
    days = max(1, ed["days"])
    idx = period_index(day, epoch, days)
    return {"index": idx, "edition": max(1, idx + 1), "open_day": epoch + idx * days, "days": days,
            "run": ed["run"], "per_hour": ed["per_hour"]}

def flaw_for_roll(r):
    acc = 0
    for f in PR["flaws"]:
        acc += f["bp"]
        if r < acc:
            return f["id"]
    return ""

def grade_for_roll(g):
    acc, last = 0, 1
    for row in PR["grades"]:
        acc += row[1]; last = row[0]
        if g < acc:
            return last
    return last

def make_prints(b, ids, day, epoch, hours, ed, seed, seq):
    info = edition_on(b, day, epoch)
    n = ed.get("n", 0) if ed.get("e", -999999) == info["index"] else 0
    run = max(1, info["run"])
    inks = PR["inks"]
    r = Rng(mix(seed, seq))
    out = []
    for hid in ids:
        raw = 1 + max(0, hours) * info["per_hour"] + n
        flaw = flaw_for_roll(r.range_int(0, 9999))
        holo = r.chance_bp(PR["holo_bp"])
        grade = grade_for_roll(r.range_int(0, 9999))
        v = r.range_int(0, 999)
        gap = r.range_int(0, PR["other_takers_max"])
        out.append({"hero": hid, "banner": b, "edition": info["edition"], "printing": idiv(raw - 1, run) + 1,
                    "serial": imod(raw - 1, run) + 1, "run": run, "flaw": flaw,
                    "ink": inks[v % len(inks)] if flaw == "swap" else "", "holo": holo, "grade": grade, "v": v})
        n += 1 + gap
    return {"prints": out, "ed": {"e": info["index"], "n": n}}

def flaw_def(i):
    for f in PR["flaws"]:
        if f["id"] == i and i != "":
            return f
    return None

def notable(p):
    return p.get("flaw", "") != "" or p.get("holo", False) or p.get("grade", 0) >= 9 \
        or p.get("serial", EARLY + 1) <= EARLY or p.get("first", False) or p.get("from", "") != ""

def score(p):
    s = p.get("grade", 0) * 100
    if p.get("holo", False): s += 3000
    f = flaw_def(p.get("flaw", ""))
    if f: s += 2000 + (300 - f["bp"])
    serial = p.get("serial", EARLY + 1)
    if serial <= EARLY: s += 600 + (EARLY - serial)
    if p.get("printing", 1) == 1: s += 50
    return s

def trim(lst, keep=-1):
    keep = PR["keep_plain"] if keep < 0 else keep
    drop = max(0, sum(1 for p in lst if not notable(p)) - keep)
    out = []
    for p in lst:
        if drop > 0 and not notable(p):
            drop -= 1; continue
        out.append(p)
    return out

# ------------------------------------------------------------------ section 9c the Rival
RV = load("rival")
FP = ECO["formation"]["front_priority"]

def r_new_state(seed):
    return {"seed": mix(seed, RV["seed"]), "met": False, "day": -1, "heroes": {}, "pulls": 0, "pity": {}, "lost": False,
            "ed": {}, "print_seq": 0, "prints": [], "feed": [], "feed_seq": 0, "seen": 0, "wins": 0, "losses": 0,
            "fights": 0, "haul_day": -1, "tag_you": False, "tag_her": False, "tag_v": 0}

def banner_on(day, epoch):
    cyc = RV["banner_cycle"]; return cyc[(day - epoch) % len(cyc)]

def counter_faction(main):
    if main == "": return ""
    for f in BATTLE["factions"]:
        if BATTLE["beats"].get(f, "") == main:
            return f
    return ""

def r_stars(hid, dupes, cap):
    s0 = start_stars(HERO[hid]["rarity"])
    top = min(cap + RV["stars_over_you"], H["max_stars"])
    return max(s0, min(s0 + idiv(max(0, dupes), max(1, RV["dupes_per_star"])), top))

def r_level(avg, day, countering):
    wob = RV["level_wobble"]
    lv = avg + wob[day % len(wob)] + (RV["counter_level"] if countering else 0)
    return max(1, lv)

def r_echo_bp():
    return idiv(STAGES["echo_stat_bp"] * RV["strength_bp"], 10000)

def r_team(heroes, cap, level, prefer):
    cands = []
    for i, h in enumerate(HEROES):
        hid = h["id"]
        if hid not in heroes: continue
        st = r_stars(hid, heroes[hid], cap)
        lv = max(1, min(level, level_cap(st)))
        cands.append((1 if prefer and h["faction"] == prefer else 0, power(stats(hid, lv, st)), i, hid, lv, st))
    cands.sort(key=lambda c: (-c[0], -c[1], c[2]))
    picks = cands[:5]
    order = sorted(range(len(picks)), key=lambda k: (-FP.get(HERO[picks[k][3]]["role"], 0), k))
    eb = r_echo_bp()
    return [{"hero_id": picks[k][3], "level": picks[k][4], "stars": picks[k][5], "slot": s, "is_boss": False, "echo_bp": eb,
             "power": power(echo_stats(picks[k][3], picks[k][4], picks[k][5], eb))} for s, k in enumerate(order)]

def r_keeps(p):
    return p["flaw"] != "" or p["holo"] or p["grade"] >= 9 or p["serial"] <= EARLY

def r_sort_prints(lst):
    a = sorted(lst, key=lambda p: (1 if p.get("taken", False) else 0, -score(p), p.get("n", 0)))[:RV["prints_max"]]
    return sorted(a, key=lambda p: (-score(p), p.get("n", 0)))

def r_fill(t, fills):
    for k, v in fills.items():
        t = t.replace("{%s}" % k, str(v))
    return t[:1].upper() + t[1:] if t else t

def r_line(kind, seed, day, salt, fills):
    arr = RV["lines"].get(kind, [])
    if not arr: return ""
    return r_fill(arr[(mix(seed, day) + salt) % len(arr)], fills)

def r_sim_day(rs, day, epoch, owns):
    bid = banner_on(day, epoch)
    b = BANNERS[bid]
    kind = b.get("kind", "standard")
    opts = {}
    if kind == "featured": opts = {"featured": featured_for(b, day, epoch), "lost": rs["lost"]}
    elif kind == "faction": opts = {"faction": faction_for(b, day, epoch)}
    elif kind == "wish":
        ch = pool_by_rarity(b)["legendary"]; opts = {"target": ch[0] if ch else ""}
    roll = pull(b, rs["seed"], rs["pulls"], rs["pity"].get(bid, 0), RV["pulls_per_day"], opts)
    rs["pulls"] = roll["total_pulls"]; rs["pity"][bid] = roll["pity"]
    if "lost" in roll: rs["lost"] = roll["lost"]
    ids, firsts, events = [], [], []
    for r in roll["results"]:
        hid = r["hero_id"]; new = hid not in rs["heroes"]
        rs["heroes"][hid] = 0 if new else rs["heroes"][hid] + 1
        ids.append(hid); firsts.append(new)
        if r["rarity"] == "legendary":
            first = r.get("featured", False) and hid not in owns
            events.append({"type": "featured_first" if first else "legendary", "hero": hid, "flaw": "", "ink": ""})
    info = edition_on(bid, day, epoch)
    hours = (day - info["open_day"]) * 24 + RV["pull_hour"]
    made = make_prints(bid, ids, day, epoch, hours, rs["ed"].get(bid, {}), mix(rs["seed"], PR["seed"]), rs["print_seq"])
    rs["ed"][bid] = made["ed"]
    kept, seq = rs["prints"], rs["print_seq"]
    for k, p in enumerate(made["prints"]):
        n = seq + k + 1
        p.update({"n": n, "uid": "rue-%d" % n, "day": day, "first": firsts[k], "taken": False})
        if p["flaw"] != "": events.append({"type": "misprint", "hero": p["hero"], "flaw": p["flaw"], "ink": p["ink"]})
        if p["holo"]: events.append({"type": "holo", "hero": p["hero"], "flaw": p["flaw"], "ink": p["ink"]})
        if r_keeps(p): kept.append(p)
    rs["print_seq"] = seq + len(ids)
    rs["prints"] = r_sort_prints(kept)
    for k, e in enumerate(events):
        rs["feed_seq"] += 1
        fills = {"hero": HERO[e["hero"]]["name"], "flaw": (flaw_def(e["flaw"]) or {}).get("adj", "")}
        rs["feed"].insert(0, {"n": rs["feed_seq"], "day": day, "type": e["type"], "hero": e["hero"], "flaw": e["flaw"],
                              "ink": e["ink"], "line": r_line(e["type"], rs["seed"], day, k, fills)})
    del rs["feed"][RV["feed_max"]:]
    return events

def r_catch_up(rs, today, epoch, owns):
    if not rs["heroes"]:
        for hid in RV["start_heroes"]: rs["heroes"][hid] = 0
    if rs["day"] < 0: rs["day"] = today - 1
    if today <= rs["day"]: return 0
    frm = max(rs["day"] + 1, today - RV["catch_up_days"] + 1)
    for d in range(frm, today + 1): r_sim_day(rs, d, epoch, owns)
    rs["day"] = today
    return today - frm + 1

def r_best_untaken(rs):
    best = None
    for p in rs["prints"]:
        if p.get("taken", False): continue
        if best is None or score(p) > score(best) or (score(p) == score(best) and p["n"] < best["n"]):
            best = p
    return dict(best) if best else {}

def r_haul(cleared):
    h = RV["haul"]; return {"gems": h["gems"], "gold": h["gold_base"] + h["gold_per_stage"] * cleared, "dust": h["dust"]}

N_STAGES = sum(len(ch["stages"]) for ch in STAGES["chapters"])
def r_cleared_on(c, day):
    lead = RV["stage_lead"]; return max(0, min(c + lead[day % len(lead)], N_STAGES))
def r_tower_on(b, day):
    lead = RV["tower_lead"]; return max(0, min(b + lead[day % len(lead)], TOWER["floors"]))


# ------------------------------------------------------------------ checker
def fx(name):
    with open(os.path.join(ROOT, "data", "fixtures", name + ".json")) as f:
        return json.load(f)

def first_diff(a, b, path=""):
    if type(a) != type(b):
        return "%s: %r vs %r" % (path, a, b)
    if isinstance(a, dict):
        for k in a:
            if k not in b: return "%s/%s missing" % (path, k)
            d = first_diff(a[k], b[k], path + "/" + k)
            if d: return d
        for k in b:
            if k not in a: return "%s/%s unexpected" % (path, k)
        return ""
    if isinstance(a, list):
        for i, (x, y) in enumerate(zip(a, b)):
            d = first_diff(x, y, "%s/%d" % (path, i))
            if d: return d
        return "" if len(a) == len(b) else "%s: len %d vs %d" % (path, len(a), len(b))
    return "" if a == b else "%s: expected %r got %r" % (path, a, b)

results = {}
def check(label, expected, actual):
    d = first_diff(expected, actual)
    results[label] = d
    print("%-28s %s" % (label, "OK" if not d else "DIFF " + d[:300]))

f = fx("rng")
check("rng.sequences", [c["next_u32"] for c in f["sequences"]], [[r.next_u32() for _ in range(12)] for r in [Rng(c["seed"]) for c in f["sequences"]]])
check("rng.mix", [c["out"] for c in f["mix"]], [mix(c["a"], c["b"]) for c in f["mix"]])
def rr(c):
    r = Rng(c["seed"]); v = [r.range_int(c["lo"], c["hi"]) for _ in range(10)]; return [v, r.next_u32()]
check("rng.range_int", [[c["out"], c["next_u32_after"]] for c in f["range_int"]], [rr(c) for c in f["range_int"]])
def cc(c):
    r = Rng(c["seed"]); v = [r.chance_bp(c["bp"]) for _ in range(10)]; return [v, r.next_u32()]
check("rng.chance_bp", [[c["out"], c["next_u32_after"]] for c in f["chance_bp"]], [cc(c) for c in f["chance_bp"]])
def pk(c):
    r = Rng(c["seed"]); a = list(range(c["size"])); return [r.pick(a) for _ in range(10)]
check("rng.pick", [c["out"] for c in f["pick"]], [pk(c) for c in f["pick"]])

f = fx("progression")
check("progression.level_cost", [[c["gold"], c["hero_exp"]] for c in f["level_cost"]], [[level_cost(c["level"])["gold"], level_cost(c["level"])["hero_exp"]] for c in f["level_cost"]])
check("progression.level_cap", [c["cap"] for c in f["level_cap"]], [level_cap(c["stars"]) for c in f["level_cap"]])
check("progression.star_shards", [[c["next"], c["to_max"]] for c in f["star_shards"]], [[star_shards(c["stars"]), shards_to_max(c["stars"])] for c in f["star_shards"]])
check("progression.star_up_cost", [c["out"] for c in f["star_up_cost"]], [star_up_cost(c["stars"], c["shards_have"], c["rarity"]) for c in f["star_up_cost"]])
check("progression.add_shards", [c["out"] for c in f["add_shards"]], [add_shards(c["stars"], c["shards_have"], c["n"], c["rarity"], c.get("awaken", 0)) for c in f["add_shards"]])
check("progression.awaken_cost", [c["out"] for c in f["awaken_cost"]], [awaken_cost(c["stars"], c["awaken"], c["shards_have"], c["rarity"]) for c in f["awaken_cost"]])
check("progression.awaken_stat_bp", [c["out"] for c in f["awaken_stat_bp"]], [awaken_bp(c["awaken"]) for c in f["awaken_stat_bp"]])
check("progression.affordable", [c["out"] for c in f["affordable_levels"]], [affordable(c["level"], c["cap"], c["gold"], c["hero_exp"]) for c in f["affordable_levels"]])

f = fx("idle")
check("idle.per_hour", [c["out"] for c in f["per_hour"]], [per_hour(c["cleared"]) for c in f["per_hour"]])
check("idle.elapsed", [c["out"] for c in f["elapsed"]], [elapsed(c["now_ms"], c["last_claim_at"]) for c in f["elapsed"]])
check("idle.accrue", [c["out"] for c in f["accrue"]], [accrue(c["elapsed_ms"], per_hour(c["cleared"]), c["carry"], c["gear_ms"]) for c in f["accrue"]])
check("idle.quick_claim", [[c["cost"], c["left"]] for c in f["quick_claim"]], [[qcost(c["used"]), max(0, len(I["quick_claim_costs"]) - c["used"])] for c in f["quick_claim"]])
check("idle.quick_reward", [c["out"] for c in f["quick_reward"]], [quick_reward(per_hour(c["cleared"]), c["gear_ms"]) for c in f["quick_reward"]])

f = fx("gear")
check("gear.tier_for", [c["out"] for c in f["tier_for"]], [tier_for(c["cleared"]) for c in f["tier_for"]])
check("gear.random_slot", [c["out"] for c in f["random_slot"]], [random_slot(c["rng_seed"], c["gear_seq"]) for c in f["random_slot"]])
check("gear.make_item", [c["out"] for c in f["make_item"]], [make_item(c["slot"], c["tier"], c["rng_seed"], c["seq"]) for c in f["make_item"]])
check("gear.salvage", [c["out"] for c in f["salvage"]], [{"gold": G["salvage_gold_per_tier"] * c["tier"], "dust": G["salvage_dust_per_tier"] * c["tier"]} for c in f["salvage"]])

f = fx("stats")
check("stats.hero_stats", [[c["out"], c["power"]] for c in f["hero_stats"]], [[stats(c["hero_id"], c["level"], c["stars"], c["gear"], c.get("awaken", 0)), power(stats(c["hero_id"], c["level"], c["stars"], c["gear"], c.get("awaken", 0)))] for c in f["hero_stats"]])
check("stats.gear_score", [c["out"] for c in f["gear_score"]], [gear_score({"stats": c["stats"]}) for c in f["gear_score"]])
bs = built_stages()
exp_st, act_st = [], []
for c in f["stages"]:
    s = bs[c["index"]]
    en = [dict(e, stats=echo_stats(e["hero_id"], e["level"], e["stars"], e["echo_bp"])) for e in s["enemies"]]
    act_st.append({"id": s["id"], "enemies": en, "enemy_power": enemy_power(s["enemies"]), "recommended_power": s["recommended_power"], "first_clear_reward": s["first_clear_reward"]})
    exp_st.append({k: c[k] for k in ("id", "enemies", "enemy_power", "recommended_power", "first_clear_reward")})
check("stats.stages", exp_st, act_st)
exp_tw, act_tw = [], []
for c in f.get("tower", []):
    t = tower_floor(c["floor"])
    en = [dict(e, stats=echo_stats(e["hero_id"], e["level"], e["stars"], e["echo_bp"])) for e in t["enemies"]]
    act_tw.append(dict(t, floor=c["floor"], enemies=en, enemy_power=enemy_power(t["enemies"])))
    exp_tw.append({k: c[k] for k in ("floor", "id", "enemies", "is_boss", "background", "enemy_power", "recommended_power", "first_clear_reward")})
check("stats.tower", exp_tw, act_tw)

f = fx("summon")
check("summon.rarity_for_roll", [c["out"] for c in f["rarity_for_roll"]], [rarity_for_roll(c["roll"], BANNER) for c in f["rarity_for_roll"]])
for c in f["cases"]:
    outs, tot, pity = [], c["total_pulls"], c["pity"]
    for n in c["counts"]:
        r = pull(BANNER, c["seed"], tot, pity, n); outs.append(r); tot, pity = r["total_pulls"], r["pity"]
    check("summon." + c["name"], c["out"], outs)
for c in f.get("banner_cases", []):
    outs, tot, pity, opts = [], c["total_pulls"], c["pity"], dict(c["opts"])
    for n in c["counts"]:
        r = pull(BANNERS[c["banner"]], c["seed"], tot, pity, n, opts); outs.append(r); tot, pity = r["total_pulls"], r["pity"]
        if "lost" in r: opts["lost"] = r["lost"]
    check("summon." + c["name"], c["out"], outs)
if "rotation" in f:
    e, fb, cb, wb, eb = f["epoch_day"], BANNERS["featured"], BANNERS["faction"], BANNERS["wish"], BANNERS["envoy"]
    check("summon.epoch_day", f["epoch_day"], EPOCH)
    check("summon.rotation", [c["out"] for c in f["rotation"]], [{
        "featured": featured_for(fb, d, e), "featured_next_change": next_change_day(d, e, fb["rotation_days"]),
        "faction": faction_for(cb, d, e), "faction_next_change": next_change_day(d, e, cb["rotation_days"]),
        "wish_period": limit_period(wb, d, e), "wish_resets": limit_resets_day(wb, d, e),
        "envoy_period": limit_period(eb, d, e), "envoy_resets": limit_resets_day(eb, d, e)} for d in [c["day"] for c in f["rotation"]]])

f = fx("battles")
for b in f["battles"]:
    sim = Sim(b["setup"]); sim.auto = b["auto_ultimates"]
    evs, reqs, ins, tick = [], [], [], 0
    while not sim.winner:
        tick += 1
        for r in b.get("inputs", []):
            if r["tick"] == tick:
                ok = sim.set_spotlight(r["uid"]) if r["kind"] == "spotlight" else sim.set_mark(r["uid"])
                ins.append({"tick": r["tick"], "kind": r["kind"], "uid": r["uid"], "accepted": ok})
        for r in b["manual_ultimates"]:
            if r["tick"] == tick:
                reqs.append({"tick": r["tick"], "uid": r["uid"], "accepted": sim.request(r["uid"])})
        evs += sim.step()
    units = [{"uid": u.uid, "hp": u.hp, "max_hp": u.max_hp, "shield": u.shield, "energy": u.energy, "alive": u.alive,
              "statuses": {k: v - sim.t for k, v in u.st_end.items()}} for u in sim.units]
    check("battle.%s.events" % b["name"], b["events"], evs)
    check("battle.%s.outcome" % b["name"], b["outcome"], sim.outcome())
    check("battle.%s.final_units" % b["name"], b["final_units"], units)
    if reqs: check("battle.%s.requests" % b["name"], b["manual_ultimates"], reqs)
    if "inputs" in b: check("battle.%s.inputs" % b["name"], b["inputs"], ins)

f = fx("prints")
check("prints.editions", [c["out"] for c in f["editions"]], [edition_on(c["banner"], c["day"], c["epoch_day"]) for c in f["editions"]])
check("prints.flaw_for_roll", f["flaws"], [flaw_for_roll(r) for r in f["flaw_rolls"]])
check("prints.grade_for_roll", f["grades"], [grade_for_roll(r) for r in f["grade_rolls"]])
for c in f["make_prints"]:
    check("prints." + c["name"], c["out"], make_prints(c["banner"], c["hero_ids"], c["day"], c["epoch_day"], c["hours_open"], c["ed"], c["seed"], c["seq"]))
check("prints.notable_score", [[c["notable"], c["score"]] for c in f["samples"]], [[notable(c["print"]), score(c["print"])] for c in f["samples"]])
check("prints.trim", [f["trim"]["out"], f["trim"]["out_default"]], [trim(f["trim"]["list"], f["trim"]["keep_plain"]), trim(f["trim"]["list"])])

f = fx("rival")
e = f["epoch_day"]
check("rival.epoch_day", e, EPOCH)
check("rival.banner_on", f["banners"], [banner_on(d, e) for d in f["banner_days"]])
check("rival.counter_faction", f["counters"], [counter_faction(x) for x in f["factions"]])
check("rival.stars_for", [c["out"] for c in f["stars"]], [r_stars(c["hero_id"], c["dupes"], c["cap"]) for c in f["stars"]])
check("rival.level_on", [c["out"] for c in f["levels"]], [r_level(c["avg"], c["day"], c["countering"]) for c in f["levels"]])
check("rival.team", [c["out"] for c in f["teams"]], [r_team(c["heroes"], c["cap"], c["level"], c["prefer"]) for c in f["teams"]])
for c in f["sims"]:
    rs, outs = r_new_state(c["seed"]), []
    for st in c["steps"]:
        n = r_catch_up(rs, st["today"], e, set(st["owns"]))
        outs.append({"days": n, "state": json.loads(json.dumps(rs)), "best_untaken": r_best_untaken(rs)})
    check("rival.sim." + c["name"], c["out"], outs)
check("rival.haul", f["haul_out"], [r_haul(c) for c in f["hauls"]])
check("rival.leads", f["lead_out"], [[r_cleared_on(c[0], c[2]), r_tower_on(c[1], c[2])] for c in f["leads"]])
check("rival.lines", f["line_out"], [r_line(c[0], c[1], c[2], c[3], c[4]) for c in f["lines"]])

# ---------------- the war (9d)
WAR = load("war")
def w_week_of(day):
    x = day - WAR["epoch_day"]
    return x // WAR["week_days"]
def w_week_start(w): return WAR["epoch_day"] + w * WAR["week_days"]
def w_push(day, sector, side):
    k = 0 if side == "heaven" else 1
    return WAR["sim"]["base"] + Rng(mix(mix(WAR["seed"], day), sector * 2 + k)).range_int(0, WAR["sim"]["spread"])
def w_logged(log, day, sector): return int(log.get(str(day), {}).get(str(sector), 0))
def w_control(week, upto, log, side):
    n = len(WAR["sectors"]); c = [0] * n
    sign = 1 if side == "heaven" else (-1 if side == "hell" else 0)
    d0 = w_week_start(week); d1 = min(upto, d0 + WAR["week_days"] - 1)
    M = WAR["control_max_bp"]
    for d in range(d0, d1 + 1):
        for s in range(n):
            diff = w_push(d, s, "heaven") - w_push(d, s, "hell") + w_logged(log, d, s) * sign
            c[s] = max(-M, min(M, c[s] + diff * WAR["control_per_soul_bp"]))
    return c
def w_standing(c):
    h = sum(1 for v in c if v > 0); e = sum(1 for v in c if v < 0)
    return {"heaven": h, "hell": e, "winner": "heaven" if h > e else ("hell" if e > h else "")}
def w_reward(won, held):
    R = WAR["rewards"]; r = dict(R["all"])
    def add(m):
        for k, v in m.items(): r[k] = r.get(k, 0) + v
    if won: add(R["won"])
    for _ in range(max(0, held)): add(R["held_per_sector"])
    return r

f = fx("war")
check("war.weeks", f["weeks"], [[w_week_of(d), w_week_start(w_week_of(d))] for d in f["days"]])
check("war.pushes", f["pushes"], [[w_push(d, s, "heaven"), w_push(d, s, "hell")] for d in f["push_days"] for s in range(len(WAR["sectors"]))])
check("war.control", f["cases"], [{"week": c["week"], "upto_day": c["upto_day"], "side": c["side"],
    "control": (cc := w_control(c["week"], c["upto_day"], f["log"], c["side"])), "standing": w_standing(cc)} for c in f["cases"]])
check("war.rewards", f["rewards"], [w_reward(r[0], r[1]) for r in f["reward_cases"]])

bad = [k for k, v in results.items() if v]
print("\n%d checks, %d differ" % (len(results), len(bad)))
sys.exit(1 if bad else 0)
