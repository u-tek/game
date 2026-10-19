# Porting Halo & Horn to Unity (C#)

Status: **ready to port.** The game ships from Godot 4.5 (GDScript). All content and tuning is
engine-neutral JSON, the rules are plain classes with integer math and our own RNG, and golden
fixtures record exact outputs. A C# port is a mechanical translation that is *verified*: it is
done when it reproduces every file in `data/fixtures/`.

Contents: 1 file layout · 2 porting rules · 3 data schemas · 4 RNG · 5 seeds and streams ·
6 stats and power · 7 battle simulation · 8 summon, idle, progression, gear · 9 GameModel and
the save format · 10 golden fixtures · 11 port procedure.

## 1. File layout

```
data/                         ENGINE-NEUTRAL CONTENT (single source of truth)
  heroes.json                 15 heroes: identity + kit (base stats, ultimate, passives)
  stages.json                 3 chapters x 10 stages: enemies, difficulty, first-clear rewards
  economy.json                new game, hero progression, stat growth, idle, gear, formation
  banner.json                 summon banner(s): costs, rates, pity, pool
  quests.json                 daily quests
  offers.json                 shop offers and the monthly card
  battle.json                 battle tuning (energy, damage, bosses, factions, timings)
  worlds.json                 the campaign worlds' presentation (no rules; section 3.6d)
  fixtures/*.json             golden fixtures: rule inputs -> exact outputs (section 10)
src/data/                     THIN LOADERS (GDScript; C#: Data/*.cs)
  game_data.gd   GameData     reads and caches data/*.json, turns JSON numbers back into ints
  heroes.gd      HeroData     identity fields of heroes.json
  hero_kits.gd   HeroKits     kit fields of heroes.json (+ active passives by stars)
  stages.gd      StageData    builds Stage/Chapter dictionaries from stages.json
  economy.gd     EconomyData  economy/banner/quests/offers values under their old constant names
src/core/                     RULES (plain classes; no Node, signal, Time, OS, file access)
  rng.gd          SeededRng   xorshift32 + 31-bit seed hash (section 4)
  stat_calc.gd    StatCalc    hero stats, power, gear score (section 6)
  battle_sim.gd   BattleSim   deterministic 5v5 battle (section 7)
  summon_rules.gd SummonRules rarity rolls, pity, 10-pull guarantee (section 8)
  idle_rules.gd   IdleRules   idle income, carry, gear timer, quick claims (section 8)
  progression.gd  Progression level costs/caps, star-ups, shards and dust (section 8)
  gear_rules.gd   GearRules   drop tiers, item creation, salvage (section 8)
  game_model.gd   GameModel   player state + every action (section 9)
  game.gd         (autoload "Game") THIN ADAPTER: clock, JSON save file, signals, polling
tests/
  golden.gd                   fixture inputs + the code that computes their outputs
  unit/test_fixtures.gd       checks data/fixtures/*.json against the rules
  unit/test_rng.gd            RNG reference values (seed 12345)
  tools/make_fixtures.gd      regenerates data/fixtures/*.json
  tools/calibrate_stages.gd   re-solves stage difficulty, writes data/stages.json
  tools/json_pretty.gd        the JSON writer used by the tools
  port_check/check_port.py    independent Python port of sections 4-8, passes the fixtures
```

| Godot | Unity (C#) | Notes |
|---|---|---|
| `data/*.json` | `StreamingAssets/data/*.json` or TextAssets | Load with Newtonsoft (`JObject`, keeps key order) into C# classes. |
| `src/data/*.gd` | `Data/GameData.cs` (+ typed records) | One loader is enough in C#. |
| `src/core/rng.gd`, `stat_calc.gd`, `battle_sim.gd`, `*_rules.gd`, `progression.gd` | `Core/*.cs` | Pure classes in an assembly with no `UnityEngine` reference. |
| `src/core/game_model.gd` | `Core/GameModel.cs` | Same method names (PascalCase is fine), same results. |
| `src/core/game.gd` | `GameService` MonoBehaviour | Clock, save file, C# events instead of signals, app pause/resume. |
| `tests/golden.gd` + `test_fixtures.gd` | `Core.Tests/FixtureTests.cs` (NUnit) | Replays `data/fixtures/*.json`. |
| `src/ui/**` | uGUI screens | Rebuilt; `screenshots/` and `docs/game-design.md` are the reference. |
| `assets/art/**` (painted PNG heroes, SVG icons, rig JSON) | Sprites, HaloRig runtime | See `docs/dev/halorig.md`. |
| `assets/fonts/*.ttf` (OFL) | TextMeshPro font assets | |
| `user://save.json` | `Application.persistentDataPath/save.json` | Same JSON, so a player could keep progress. |

## 2. Porting rules (read first)

- **Integers only, 64-bit.** Every game number is an integer; use `long` everywhere in rules
  (idle math reaches ~10^11, `rate * elapsed_ms`). Percentages are basis points (10000 = 100%).
- **Division truncates toward zero** (`/` on ints, as in C#). Operands are non-negative
  everywhere except `day_of` (section 9), which floors explicitly. `%` is the C# remainder.
- **Evaluate exactly as written, left to right.** `a * b / 10000 * c / d` is
  `((a * b) / 10000 * c) / d`; reordering or merging divisions changes results.
- **Arrays are ordered; object key order never matters for results.** Where order matters the
  data uses arrays (gear stat rolls, banner pool, heroes, stages). JSON objects compare by key.
- **Strings compare ordinally** (`string.CompareOrdinal`), never culture-aware.
- **Sorting:** every sort in the rules has a total order (tie-breaks are spelled out), so
  any sort algorithm gives the same result.
- **JSON numbers:** Godot parses all numbers as doubles and the loader converts whole numbers
  back to ints; in C# read them as `long`.
- **No floats in rules.** The only floats in the Godot project are in the adapter (wall clock),
  the JSON loader (doubles back to ints) and UI animation.

## 3. Data schemas (`data/*.json`)

Every file has `"version": 1` at the top level. Unknown keys must be ignored. Types: `int` =
JSON integer (read as `long`), `bp` = basis points int, `ms` = milliseconds int.

### 3.1 heroes.json

`{version, heroes: [Hero]}`. **Order matters**: lists, summon pools and fixtures follow it.

| Field | Type | Meaning |
|---|---|---|
| `id` | string | Stable id (never changes; save files use it). |
| `name`, `title`, `bio`, `look` | string | Display text; `look` is an art brief. |
| `faction` | `"celestial"` \| `"infernal"` \| `"fallen"` | Counter wheel and faction bonus. |
| `role` | `"guardian"` \| `"striker"` \| `"caster"` \| `"support"` \| `"assassin"` | Targeting and auto-formation. |
| `rarity` | `"rare"` \| `"epic"` \| `"legendary"` | Start stars, dupe shards, dust prices, banner. |
| `base_stats` | `{hp, atk, def, spd, crit}` ints | Level 1, 1 star. `spd` 100 = one attack per second; `crit` in bp. |
| `ultimate` | `{id, name, description, effects: [Effect]}` | Cast at 1000 energy. |
| `passives` | `[{id, name, description, unlock_stars, effects: [PassiveEffect]}]` | Active when stars >= `unlock_stars` (3 and 5). |

**Effect** (ultimates; also `ult_bonus` passives). Common keys: `type`, `target`.

| type | Keys | Behaviour (section 7.7) |
|---|---|---|
| `damage` | `mult_bp`, `hits` (default 1), `low_hp_bonus_bp` (default 0), `execute_bp` (default 0) | `hits` hits per target; `execute_bp`: a non-boss target left below that HP fraction dies. |
| `heal` | `mult_bp` | Heal of caster ATK. |
| `shield` | `pct_max_hp_bp` | Shield of the caster's max HP. |
| `status` | `status`, `duration_ms`, `value_bp` (buffs/debuffs, default 0), `dot_mult_bp` (burn/regen per second, of caster ATK, default 0) | |
| `energy` | `amount` | Energy gain. |

`target`: `enemy_target` (the caster's normal target), `enemy_others`, `enemy_all`,
`enemy_front_row`, `enemy_back_row`, `enemy_back_lowest`, `enemy_lowest`, `enemy_random`
(one random pick per hit), `ally_all`, `ally_others`, `ally_lowest`, `self`.

**PassiveEffect** `type` and keys: `stat {hp_bp?, atk_bp?, def_bp?, spd_bp?, crit_bp?}`,
`start_energy {amount}`, `team_start_energy {amount}`, `team_aura {hp_bp?, atk_bp?}`,
`start_shield {pct_max_hp_bp}`, `heal_bonus {bp}`, `thorns {bp}`, `damage_reduction {bp}`,
`on_hit_status {status, chance_bp, duration_ms, value_bp?, dot_mult_bp?}`,
`on_attack_heal {mult_bp}`, `low_hp_bonus {bp}`, `on_kill {heal_pct_bp?, energy?}`,
`lifesteal {bp}`, `crit_damage {bp}`, `double_strike {chance_bp}`, `ult_bonus {effects: [Effect]}`.

**Statuses:** `stun`, `burn`, `regen`, `taunt`, `atk_up`, `atk_down`, `def_up`, `def_down`, `spd_up`.

### 3.2 stages.json

`{version, echo_stat_bp, calibration, chapters: [Chapter]}`

| Field | Type | Meaning |
|---|---|---|
| `echo_stat_bp` | bp | Echo (enemy) HP/ATK/DEF scale at `strength_bp` 10000 (7500 = 75%). |
| `calibration.starter_team` | `{hero_id: stars}` | Tools only: the team the opening stages are tuned for. |
| `calibration.starter_stages` | int | Tools only: how many opening stages that team must win. |
| Chapter `id`, `name`, `intro`, `hint` | string | Display. |
| Chapter `background` | string | Art key (`HeroArt.background`). |
| Chapter `faction` | string | The enemies' faction (display). |
| Chapter `stages` | `[Stage]` | In order. Global stage index = position in the flattened list. |
| Stage `name` | string | |
| Stage `boss` | bool | Boss stage (one enemy has `boss: true`). |
| Stage `level`, `stars` | int | Default enemy level and stars. |
| Stage `strength_bp` | bp | Echo strength (solved by the calibrator, may exceed 10000). |
| Stage `recommended_power` | int | Team power (as `team_power()`) that wins on schedule. |
| Stage `enemies` | `[{hero_id, slot, boss?, stars?, level_bonus?}]` | `slot` 0-1 front, 2-4 back. |
| Stage `first_clear_reward` | Reward | `{gold?, hero_exp?, gems?, scrolls?, dust?, gear_drops?: [{slot, tier}]}` |

Built stage (what `Game.stage(i)` returns): `id = "<chapter#>-<stage#>"` (1-based),
`chapter` (0-based), `is_boss`, `background`, `enemy_faction`, `hint`, `recommended_power`,
`first_clear_reward`, `enemy_power` (section 6) and `enemies`, each
`{hero_id, slot, is_boss, level = stage.level + level_bonus, stars = max(enemy.stars ?? stage.stars, start_stars(rarity)), echo_bp = echo_stat_bp * strength_bp / 10000}`.

### 3.3 economy.json

| Path | Type | Meaning |
|---|---|---|
| `new_game.player_name` | string | Default player name. |
| `new_game.starter_heroes` | [id] | Owned at the start (level 1, start stars). |
| `new_game.currencies` | `{gold, hero_exp, gems, scrolls, dust}` | Starting currencies. |
| `heroes.start_stars` | `{rarity: int}` | Stars of a newly obtained hero. |
| `heroes.max_stars` | int | 6. |
| `heroes.level_cap_base`, `level_cap_per_star` | int | cap = base + per_star * clamp(stars, 1, max_stars). |
| `heroes.level_cost` | `{exp_base, exp_per_level, exp_per_level_squared, gold_exp_divisor, gold_per_level}` | Section 8.3. |
| `heroes.star_shards` | [int] by current stars | Shards for the next star (index 0 unused). |
| `heroes.dupe_shards` | `{rarity: int}` | Shards from a duplicate. |
| `heroes.dust_per_shard` | `{rarity: int}` | Dust that replaces one missing shard. |
| `heroes.dust_per_excess_shard` | `{rarity: int}` | Dust per shard a maxed hero can't use. |
| `stats.level_growth_bp`, `star_growth_bp` | bp | +7% per level, +12% per star above 1. |
| `stats.spd_per_star` | int | +1 spd per star above 1. |
| `stats.crit_cap_bp` | bp | 7500. |
| `idle.cap_ms` | ms | 12 h. |
| `idle.quick_claim_ms` | ms | 2 h per quick claim. |
| `idle.quick_claim_costs` | [int] | Gem price of the n-th quick claim today (length = claims per day). |
| `idle.base_per_hour`, `per_10_stages_per_hour` | `{currency: int}` | Section 8.2. |
| `idle.gear_every_ms` | ms | One gear drop per 3 h of idle time. |
| `idle.min_claim_for_quest_ms` | ms | A claim counts for the idle quest after this much idle time. |
| `gear.slots` | [string] | `weapon, armor, helm, charm` (order used by auto-equip and random slots). |
| `gear.tier_names` | [string] by tier | Index 0 unused. |
| `gear.item_names` | `{slot: [string]}` | Nouns. |
| `gear.stats` | `{slot: [{stat, by_tier: [int]}]}` | Base stat per tier; **array order = roll order**. |
| `gear.roll_min_pct`, `roll_max_pct` | int | Stat roll range (percent). |
| `gear.stages_per_tier`, `max_tier` | int | tier = clamp(1 + cleared / stages_per_tier, 1, max_tier). |
| `gear.bag_limit` | int | Loose items kept before auto-salvage. |
| `gear.salvage_gold_per_tier`, `salvage_dust_per_tier` | int | Salvage value. |
| `formation.front_priority` | `{role: int}` | Auto-formation front-row preference. |

### 3.4 banner.json

`{version, epoch_day, banners: [Banner]}`. Five banners, in this order: `standard` (the default,
`banners[0]`), `featured`, `faction`, `wish`, `envoy`. `epoch_day` (a day index, days since
1970-01-01 in local time; 20745 = Monday 2026-10-19) starts every rotation and weekly limit.

| Field | Type | Meaning |
|---|---|---|
| `id`, `name`, `short` | string | `short` is the index label ("Featured"). |
| `kind` | `"standard"` \| `"featured"` \| `"faction"` \| `"wish"` \| `"envoy"` | Which rules apply (section 8.1). |
| `cost_one`, `cost_ten` | `{gems, scrolls}` or `{gold}` | Scrolls are used first when the banner takes them and the player has enough. |
| `rates` | `{legendary, epic, rare}` bp | Sum 10000. |
| `pity_legendary` | int | A Legendary is forced when pity >= this - 1. 0 = no pity (the pity counter stays 0). |
| `ten_pull_guarantee` | rarity | The 10th pull of a 10-pull is upgraded to this if all ten would be Rare. |
| `pool` | [hero id] | Pool; grouped by the heroes' rarity **in this order**. |
| `free_daily` | bool | The banner with the free daily pull (standard). |
| `featured_rotation`, `rotation_days`, `featured_bp` | [hero id], int, bp | featured: the rate-up Legendary rotates every `rotation_days`; a Legendary is her with `featured_bp`. |
| `faction_rotation`, `rotation_days` | [faction], int | faction: the pool is cut to that faction, rotating every `rotation_days`. |
| `limit` | `{period: "day" \| "week", pulls}` | Pulls allowed per local day (envoy) or per week from `epoch_day` (wish). |

### 3.5 quests.json

`{version, meta_counter, daily: [{id, title, counter, goal, reward}]}`. A counter bump (section 9)
advances every quest with that `counter`. Claiming a quest bumps `meta_counter`
(`daily_quests_done`) unless the quest's own counter is `meta_counter`.

### 3.6 offers.json

`{version, monthly_card: {offer_id, days, daily_gems}, offers: [Offer]}`. Offer:
`{id, name, tag, description, price_label, reward, limit (0 = unlimited), period ("once" | "day")}`.
Buying the `monthly_card.offer_id` offer extends the pass: `monthly_until_day = max(until, today) + days`,
`monthly_last_day = today`; each later day with `until >= day > last` pays `daily_gems`.

### 3.6b skins.json

`{version, tiers: {tier id: {name, price_gems, description}}, lines: {line id: {name, description}},
skins: [Skin]}`. Skin: `{id, hero, line, tier, name, description, art}`. Cosmetic only (no stats);
the price is the tier's `price_gems`. `art` names the folder `assets/art/heroes/<hero>/skins/<art>/`
(laid out like the base art, files named `<art>.*`). A skin whose rig is not built is "Coming soon"
and cannot be bought (checked in the Game adapter, not the rules). Design: `docs/dev/skins.md`.

### 3.6c tower.json

The Spire, an endless climb beside the campaign. `{version, name, unlock_cleared, floors, seed,
strength_bp, level_per_floor_past, stars_every_past, rec_bp, rec_past_bp, boss_every, bosses [3 hero
ids], backgrounds [kinds], floors_per_background, rewards {gold_base, gold_per_floor, hero_exp_bp,
dust_base, dust_every, gems_every, gems, boss_gems, boss_scrolls, gear_slots, gear_tier_every}}`.
Floors are not stored: section 9b builds them.

### 3.6d worlds.json (presentation only)

The Campaign's worlds: one record per chapter, in chapter order. `{version, about, worlds: [World]}`.
World: `{chapter (the chapter id), world (1-6: the planet art assets/art/worlds/w<world>_albedo.jpg,
_normal.jpg, _height.png), code (the catalogue mark, "S1"), class (terrain, "Terraced highland"),
mass (the MASS tag), readouts [[label, value], ...]}`. No rules read it: the chapter dossier prints
it (`src/ui/v4/survey/world_dossier.gd`) and the survey map takes its surface temperature. A port
only needs it to draw the same dossier. The planet maps are equirectangular in Godot's SphereMesh
layout (u = longitude from +Z towards +X, v = 0 at the north pole); the normal map stores the
normal in the sphere's own frame (R east, G north; B rebuilt), see `planet.gdshader`.
### 3.6d prints.json
Misprints (section 8.5). `{version, seed, editions {banner id: {days, run, per_hour}},
other_takers_max, flaws [{id, name, adj, bp, about}], inks [ids], ink_names {id: name}, holo_bp,
grades [[grade, bp]], grade_names {"10": "Gem Mint", ...}, early_serial, keep_plain, showcase_max}`.
Flaw and grade bp are per 10000 prints; the five flaws total 6%.
### 3.6e rival.json
The Rival (section 9c). `{version, name, title, faction, unlock_cleared, seed, start_heroes [ids],
pulls_per_day, banner_cycle [banner ids], pull_hour, catch_up_days, dupes_per_star, stars_over_you,
level_wobble [7], counter_level, learn_after, strength_bp, stage_lead [5], tower_lead [5],
backgrounds [kinds], haul {gems, gold_base, gold_per_stage, dust}, feed_max, prints_max, lines {kind:
[text]}}`. Line kinds: intro, idle, win (she won), lose (she lost), featured_first, legendary,
misprint, holo, counter.

### 3.7 battle.json

| Field | Value | Meaning |
|---|---|---|
| `max_ms` | 90000 | Time limit; reaching it is a defeat (`end.timeout`). |
| `factions` | [celestial, infernal, fallen] | Tie-break order for the faction bonus. |
| `beats` | `{faction: faction}` | Attacker faction -> the faction it deals +`advantage_bp` to. |
| `advantage_bp` | 2000 | |
| `faction_bonus_bp` | [int] indexed by count (0..5) | HP and ATK bonus for N allies of one faction. |
| `attack_interval_k`, `min_interval_ms` | 100000, 300 | interval = max(min, k / spd). |
| `min_spd` | 20 | spd floor. |
| `first_attack_ms` | `{base, per_slot, random_max}` | First attack after base + slot*per_slot + range_int(0, random_max). |
| `energy` | `{per_attack, per_full_hp, hit_min, hit_max, event_step}` | Section 7.6. |
| `crit_damage_bp` | 15000 | Crit multiplier (+ `crit_damage` passives). |
| `variance_bp` | 500 | Damage roll +/-5%. |
| `atk_floor_bp` | 2000 | ATK debuffs never go below 20%. |
| `shield_cap_bp` | 6000 | Shields cap at 60% of max HP (start shields excepted). |
| `boss` | `{hp_bp, atk_bp, def_bp, stun_divisor}` | Boss multipliers; stuns on bosses last 1/2. |
| `status_refresh_event_ms` | 1000 | A refresh emits a `status` event only if it extends by >= this. |

Algorithm constants (not data): tick = **100 ms**, ultimate at **1000** energy, DoT/HoT every
**1000 ms** of battle time, bp unit 10000.

## 4. RNG (`src/core/rng.gd`)

xorshift32 (Marsaglia 13/17/5) on a 32-bit state, seeded through a 31-bit integer hash. The only
RNG in the rules (never `System.Random`/`UnityEngine.Random`). Reference: `SeededRng(12345)`
first ten `next_u32()` = 1330226942, 157105557, 1930860194, 2576502307, 3667822344, 1167049943,
532296189, 1764891359, 1733563019, 1168441641 (`tests/unit/test_rng.gd`, `data/fixtures/rng.json`).

```csharp
public sealed class SeededRng {
    const ulong Mask = 0xFFFFFFFFUL;
    ulong s;                                    // never 0
    public SeededRng(long seed = 1) {
        s = (ulong)Mix(seed, 0x2545F491);
        if (s == 0) s = 0x6D2B79F5;
        for (int i = 0; i < 3; i++) NextU32();  // warm-up, discarded
    }
    // 31-bit hash of two signed 64-bit ints. a >> 31 is an arithmetic shift.
    public static long Mix(long a, long b) {
        ulong h = (ulong)((a & 0x7FFFFFFF) ^ ((a >> 31) & 0x7FFFFFFF));
        h = (h * 0x9E3779B1UL) & Mask;
        h ^= (ulong)(b & 0x7FFFFFFF);
        h = ((h & 0x7FFFFFFFUL) * 0x85EBCA77UL) & Mask;
        h ^= h >> 15;
        h = ((h & 0x7FFFFFFFUL) * 0xC2B2AE3DUL) & Mask;
        h ^= h >> 13;
        return (long)(h & 0x7FFFFFFFUL);
    }
    public long NextU32() {                     // 1 .. 2^32-1
        ulong x = s;
        x = (x ^ (x << 13)) & Mask;
        x ^= x >> 17;
        x = (x ^ (x << 5)) & Mask;
        s = x;
        return (long)x;
    }
    public long RangeInt(long lo, long hi) => hi <= lo ? lo : lo + NextU32() % (hi - lo + 1);
    public bool ChanceBp(long bp) => bp <= 0 ? false : bp >= 10000 ? true : NextU32() % 10000 < bp;
    public T Pick<T>(IReadOnlyList<T> a) => a[(int)(NextU32() % a.Count)];
}
```

`RangeInt` with `hi <= lo` and `ChanceBp` with `bp <= 0` or `bp >= 10000` **consume no draw**.
Every draw in the rules is listed in sections 7-9; a port must make the same draws in the same order.

## 5. Seeds and random streams

| Stream | Seed | Draws |
|---|---|---|
| New save | `rng_seed = mix(created_at & 0x7FFFFFFF, 104729)`, `summon.seed = mix(created_at & 0x7FFFFFFF, 7919)` | none |
| Stage battle | `mix(rng_seed + stage_index * 7717, battles_started)`; `battles_started` is the counter before this attempt (then +1) | BattleSim (section 7) |
| Spire battle | `mix(rng_seed + 500009 + floor * 7717, battles_started)` (same counter) | BattleSim |
| Spire floor team | `SeededRng(mix(tower.seed, floor))` | section 9b |
| Summon | `SeededRng(mix(summon.seed, total_pulls))`, total_pulls before the summon | section 8.1 |
| Idle drop slot | drop i of a claim: `SeededRng(mix(rng_seed + 31, (gear_seq + i) * 13 + 5)).pick(gear.slots)`, gear_seq before the claim | 1 |
| New gear item | `SeededRng(mix(rng_seed, seq))`, seq = the new `gear_seq` | section 8.4 |

## 6. Stats and power (`src/core/stat_calc.gd`)

For hero `h` at `level`, `stars` with equipped items `gear`:

```
lm = 10000 + (max(level,1) - 1) * level_growth_bp          sm = 10000 + (max(stars,1) - 1) * star_growth_bp
g[k] = sum of item.stats[k] over gear (k in hp, atk, def, spd, crit; missing = 0)
bonus[k_bp] = sum over active passives' "stat" effects (hp_bp, atk_bp, def_bp, spd_bp, crit_bp)
for k in hp, atk, def:  v = base[k] * lm / 10000 * sm / 10000 + g[k];   out[k] = v * (10000 + bonus[k_bp]) / 10000
spd  = (base.spd + (max(stars,1) - 1) * spd_per_star + g.spd) * (10000 + bonus.spd_bp) / 10000
crit = min(base.crit + g.crit + bonus.crit_bp, crit_cap_bp)
power(st)      = (hp/2 + atk*8 + def*6) * spd / 100 * (20000 + crit) / 20000 / 5
gear_score(it) = hp/2 + atk*8 + def*6 + spd*15 + crit/6       (of it.stats)
echo_stats(hero, level, stars, echo_bp) = stats(hero, level, stars) with hp/atk/def = max(1, v * echo_bp / 10000)
```

`enemy_power(stage)`: fb = max over factions of `faction_bonus_bp[min(count,5)]` among the
enemies; for each enemy: st = echo_stats; hp, atk `*= (10000 + fb) / 10000`; bosses then
hp `* boss.hp_bp / 10000`, atk `* boss.atk_bp / 10000`, def `* boss.def_bp / 10000`; sum `power(st)`.
Fixture: `stats.json`.

## 7. Battle simulation (`src/core/battle_sim.gd`)

### 7.1 Setup

`BattleSim(setup)`, `setup = {seed, allies: [Unit], enemies: [Unit], max_ms?}`;
`Unit = {uid, hero_id, side, slot, level, stars, stats {hp, atk, def, spd, crit}, is_boss}`.
`rng = SeededRng(seed)`. Units are added allies first, then enemies, in list order; this
**unit order** is used by every loop below. For each unit (unknown hero ids are skipped):

```
hp = max(1, stats.hp); atk = max(1, stats.atk); def = max(0, stats.def); spd = max(min_spd, stats.spd); crit = stats.crit
if is_boss: hp = hp * boss.hp_bp / 10000; atk = atk * boss.atk_bp / 10000; def = def * boss.def_bp / 10000
uid defaults to "a<slot>" / "e<slot>" when missing or duplicate
passives = active passives of (hero_id, stars), summed by type (section 7.8)
timer    = first_attack.base + slot * first_attack.per_slot + rng.RangeInt(0, first_attack.random_max)   <- one draw per unit
interval = max(min_interval_ms, attack_interval_k / spd)
damage_dealt[uid] = 0; healing_done[uid] = 0
```

Then, for side in (ally, enemy): count factions; the best faction is the first in `factions`
order with a strictly greater count; `fb = faction_bonus_bp[min(count, 5)]`.
`aura_hp = fb + sum(team_aura.hp_bp)`, `aura_atk = fb + sum(team_aura.atk_bp)`,
`team_energy = sum(team_start_energy)` over the side. For each unit of the side in order:
`max_hp = max_hp * (10000 + aura_hp) / 10000; hp = max_hp; atk = atk * (10000 + aura_atk) / 10000;`
if `start_shield > 0`: `shield = max_hp * start_shield / 10000` (not capped);
`energy = 0; GainEnergy(u, start_energy + team_energy)`.

### 7.2 One `step()` (100 ms)

```
if winner != "": return []
events = []; t += 100
1. STATUS PHASE    (7.5)                     -> if CheckEnd(): return Flush()
2. ULTIMATE PHASE  (7.4)                     -> if CheckEnd(): return Flush()
3. ATTACK PHASE    (7.3)
4. if not CheckEnd() and t >= max_ms: winner = "enemy"; emit end {winner, timeout: true}
return Flush()
```

`CheckEnd()`: true if a winner exists. Otherwise if both sides have a living unit, false. Else
`winner = "enemy"` if no ally lives (checked first, so a double KO is a defeat), else `"ally"`;
emit `end {winner}`; true.

`Flush()`: every unit whose "energy changed" flag was set this tick (7.6) gets one event
`energy {unit, energy}` with its current energy, in the order the flags were set, appended
after all other events but before an `end` event. Flags are then cleared. Flags set while the
sim is constructed are flushed by the first step.

`request_ultimate(uid)`: accepted (true) if no winner, the unit is a living ally with energy >=
1000, not stunned, and not already queued; it is appended to the queue. `can_ultimate(uid)` is
the same test minus the queue check. `run_to_end()` steps until a winner (no events are built;
results are identical). `outcome() = {winner, victory, duration_ms: t, allies_alive,
enemies_alive, timeout: winner == "enemy" && t >= max_ms && both sides alive, damage_dealt,
healing_done}`.

### 7.3 Attack phase

For each unit in unit order: skip if dead or stunned (timer frozen). Otherwise
`timer -= 100` (with `spd_up`: `timer -= 100 * (10000 + mods.spd_up) / 10000`). If `timer > 0`,
continue. Else `timer += interval` and **basic attack**; after it, if a winner exists or a side
has no living unit: `CheckEnd()` and end the phase.

**Basic attack** of `u`:
1. `target = BasicTarget(u)`; none -> return.
2. emit `attack {src, target}`; `GainEnergy(u, energy.per_attack)`.
3. `Strike(u, target)`.
4. If `double_strike > 0` and u alive and target alive and `rng.ChanceBp(double_strike)`:
   emit `attack`, `Strike(u, target)` again. (The chance is not drawn when a condition fails.)
5. If `on_attack_heal > 0` and u alive: `low = LowestRatio(living allies of u)`;
   `Heal(u, low, Atk(u) * on_attack_heal / 10000 * (10000 + heal_bonus) / 10000)`.

**Strike(u, target)**: `dealt = Hit(u, target, 10000, false, 0)`; if `dealt <= 0` return.
If target alive: for each `on_hit_status` effect of u (passive order): if `rng.ChanceBp(chance_bp)`:
`ApplyStatus(u, target, status, duration_ms, value_bp, dot_mult_bp)`. Then if target's
`thorns > 0` and u alive: `ApplyDamage(target, u, max(1, dealt * thorns / 10000), crit=false,
adv=false, ult=false, dot=false)` (the target reflects even if this hit killed it).

**BasicTarget(u)**: `foes` = living enemies of u in unit order; empty -> none. The first foe
with `taunt` wins. Else by role: **assassin**: `LowestRatio(back-row foes)` (slot >= 2), or of
all foes if the back row is empty; **caster**: `rng.Pick(foes)`; **others**: the foe whose slot
== `u.slot % 2` if alive, else the first foe with slot < 2, else `foes[0]`.

`LowestRatio(list)`: the first unit with the smallest `hp * 10000 / max(1, max_hp)`.

### 7.4 Ultimate phase

1. Take the manual queue (and clear it). For each uid in request order: if alive, energy >=
   1000 and not stunned: `CastUltimate`; if `CheckEnd()`: end the phase.
2. Snapshot the **full-energy list** (uids in the order they reached 1000; 7.6). For each: skip
   if dead, energy < 1000 or stunned; skip allies when `auto_ultimates` is false; else
   `CastUltimate`; if `CheckEnd()`: end the phase. (Units that fill during this phase cast on a
   later tick.)

**CastUltimate(u)**: `effects = ultimate.effects + ult_bonus effects`; `energy = 0`; remove u
from the full-energy list; set u's energy flag. `primary = BasicTarget(u)` (a caster draws a
pick here). Resolve the targets of **every** effect first, in effect order (7.7), then emit
`ultimate {src, skill_id, skill_name, targets}` (unique uids, first-seen order). Then apply each
effect in order; stop when a winner exists or u's enemies are all dead.

### 7.5 Status phase

Every tick, for each unit in unit order that has statuses:
1. Only when `t % 1000 == 0`: `burn`: `ApplyDamage(src, u, max(1, dots.burn), crit=false,
   adv=false, ult=false, dot=true)`, `src` = the unit that applied the burn (u itself if
   unknown); if u died, go to the next unit. Then `regen`: `Heal(src, u, dots.regen)`.
2. Remove every status of u with `end_t <= t` (and its mod and dot).

DoT/HoT therefore tick **before** expiry on the same tick. `statuses[name]` (remaining ms)
always reads `end_t - t`.

**ApplyStatus(src, dst, status, duration, value_bp, dot_mult_bp)**: return if dst dead or
duration <= 0. Stun on a boss: `duration /= boss.stun_divisor`. `prev` = remaining ms if
active, else 0. `end_t = max(current end_t or 0, t + duration)`. If `value_bp > 0`:
`mods[status] = max(mods[status] ?? 0, value_bp)`. If `dot_mult_bp > 0`: `amount = max(1,
Atk(src) * dot_mult_bp / 10000)`; regen: `amount = amount * (10000 + src.heal_bonus) / 10000`;
if `amount >= dots[status] ?? 0`: `dots[status] = amount`, dot source = src. Emit
`status {src, target, status, duration_ms: duration}` if `prev <= 0` or
`duration - prev >= status_refresh_event_ms`.

Mods: `atk_up`/`atk_down`, `def_up`/`def_down` (bp), `spd_up` (bp of attack speed). `stun`:
no attacks, no ultimates (timer frozen). `taunt`: forced basic target.

### 7.6 Damage, healing, shields, energy, death

```
Atk(u) = max(1, u.atk * max(10000 + mods.atk_up - mods.atk_down, atk_floor_bp) / 10000)
Def(u) = max(0, u.def * max(10000 + mods.def_up - mods.def_down, 0) / 10000)

Hit(src, dst, mult_bp, from_ult, low_hp_bonus_bp):
  if dst dead: return 0
  a = Atk(src); d = Def(dst)
  dmg = a * mult_bp / 10000 * a / max(1, a + d)
  adv = beats[src.faction] == dst.faction;           if adv: dmg = dmg * (10000 + advantage_bp) / 10000
  lb = src.low_hp_bonus + low_hp_bonus_bp;           if lb > 0 and dst.hp * 2 < dst.max_hp: dmg = dmg * (10000 + lb) / 10000
  r = rng.NextU32()                                  <- exactly one draw per hit
  crit = r % 10000 < src.crit;                       if crit: dmg = dmg * (crit_damage_bp + src.crit_damage) / 10000
  dmg = dmg * (10000 - variance_bp + (r >> 14) % (2 * variance_bp + 1)) / 10000
  if dst.damage_reduction > 0: dmg = dmg * (10000 - dst.damage_reduction) / 10000
  dmg = max(dmg, 1)
  ApplyDamage(src, dst, dmg, crit, adv, from_ult, dot=false)
  if src.lifesteal > 0 and src alive: Heal(src, src, dmg * lifesteal / 10000)
  return dmg

ApplyDamage(src, dst, dmg, crit, adv, from_ult, dot):
  if dst dead: return
  absorbed = min(dst.shield, dmg); dst.shield -= absorbed; dst.hp = max(0, dst.hp - (dmg - absorbed))
  damage_dealt[src] += dmg
  emit damage {src, target, amount: dmg, crit, advantage: adv, from_ultimate, hp_after, shield_after} (+ dot: true)
  if dst.hp <= 0: Kill(dst, src); return
  if dst.energy < 1000:
    e = min(1000, energy + clamp(dmg * energy.per_full_hp / dst.max_hp, energy.hit_min, energy.hit_max))
    if e >= 1000: append dst to the full-energy list
    if e / event_step != old / event_step or e >= 1000: set dst's energy flag
    dst.energy = e

Execute(src, dst):     rest = dst.hp + dst.shield; hp = shield = 0; damage_dealt[src] += rest
                       emit damage {amount: rest, crit: false, advantage: false, from_ultimate: true,
                                    hp_after: 0, shield_after: 0, execute: true}; Kill(dst, src)
Heal(src, dst, n):     if dst dead or n <= 0: return; healed = min(n, max_hp - hp); if healed <= 0: return
                       hp += healed; healing_done[src] += healed; emit heal {src, target, amount: healed, hp_after}
AddShield(src, dst, n): new = min(dst.max_hp * shield_cap_bp / 10000, shield + n); added = new - shield
                       if added <= 0: return; shield = new; emit shield {src, target, amount: added, shield_after}
GainEnergy(u, n):      if dead: return; e = min(1000, energy + n); if e == energy: return
                       energy = e; if e >= 1000: append to the full-energy list
                       if e / event_step != old / event_step or e >= 1000: set u's energy flag
Kill(dst, killer):     alive = false; hp = shield = energy = 0; clear statuses, mods, dots;
                       remove from the full-energy list and the manual queue; emit death {unit}
                       if killer alive and on the other side: on_kill.heal_pct_bp > 0 ->
                       Heal(killer, killer, killer.max_hp * heal_pct_bp / 10000); on_kill.energy > 0 ->
                       GainEnergy(killer, energy)
```

Every event also carries `t` (battle ms of the tick).

### 7.7 Ultimate effects

Target resolution (`foes`/`mates` = living units, unit order, taken at resolution time):
`enemy_target` [primary] (none if no primary) · `enemy_others` foes except primary ·
`enemy_all` foes · `enemy_front_row` front-row foes, else back-row · `enemy_back_row`
back-row foes, else front-row · `enemy_back_lowest` [LowestRatio(back row, else all foes)] ·
`enemy_lowest` [LowestRatio(foes)] · `enemy_random` `max(1, hits)` x `rng.Pick(foes)` (with
repeats) · `ally_all` mates incl. self · `ally_others` mates except self · `ally_lowest`
[LowestRatio(mates)] · `self` [u].

Application, per effect type:
- `damage` with `enemy_random`: for each pick, if it died meanwhile, re-pick
  `rng.Pick(living foes)` (stop the effect if none); `Hit(u, t, mult_bp, true, low_hp_bonus_bp)`.
- `damage` otherwise: for each target, up to `max(1, hits)` times while alive:
  `Hit(u, t, mult_bp, true, low_hp_bonus_bp)`; then if `execute_bp > 0`, t alive, not boss and
  `t.hp * 10000 < t.max_hp * execute_bp`: `Execute(u, t)`.
- `heal`: `n = Atk(u) * mult_bp / 10000 * (10000 + u.heal_bonus) / 10000`; `Heal(u, t, n)` for each living t.
- `shield`: `n = u.max_hp * pct_max_hp_bp / 10000`; `AddShield(u, t, n)` for each living t.
- `status`: `ApplyStatus(u, t, status, duration_ms, value_bp, dot_mult_bp)` for each t.
- `energy`: `GainEnergy(t, amount)` for each living t.

### 7.8 Passives in battle

Summed per unit over active passives: `start_energy`, `team_start_energy`, `team_aura`
(hp_bp, atk_bp), `start_shield`, `heal_bonus`, `thorns`, `damage_reduction`, `on_attack_heal`,
`low_hp_bonus`, `on_kill` (heal_pct_bp, energy), `lifesteal`, `crit_damage`, `double_strike`;
`on_hit_status` and `ult_bonus` effects are kept as ordered lists. `stat` effects are already in
the unit's stats (section 6). Fixture: `battles.json` (every event kind, flag, status,
passive type and all 15 ultimates occur at least once).

## 8. Summon, idle, progression, gear

### 8.1 Summon (`summon_rules.gd`)

```
pool = banner.pool grouped by hero rarity (pool order); on a faction banner only heroes of opts.faction
rng = SeededRng(Mix(summon.seed, total_pulls))       total_pulls counts every pull on every banner
for i in 0 .. count-1:
  rarity = pity_legendary > 0 and pity >= pity_legendary - 1 ? "legendary"            (no draw)
         : RarityForRoll(rng.RangeInt(0, 9999))    r < legendary -> legendary; r < legendary + epic -> epic; else rare
  if count == 10 and i == 9 and no epic/legendary so far and rarity == "rare": rarity = ten_pull_guarantee
  if pity_legendary > 0: pity = rarity == "legendary" ? 0 : pity + 1      (else pity stays as it is)
  total_pulls += 1
  hero = featured banner, legendary: lost or rng.ChanceBp(featured_bp) ? featured
                                     : others.Count == 0 ? featured : rng.Pick(others)
                                     (others = pool.legendary without featured); lost = hero != featured
         wish banner, legendary:     opts.target                                       (no draw)
         else:                       rng.Pick(pool[rarity])
```

A featured banner's results also carry `featured` (bool) and the summon returns `lost`. Rotations
(`period_index(day) = floor((day - epoch_day) / days)`, floor also before the epoch): the featured
hero is `featured_rotation[posmod(period_index(day, epoch_day, rotation_days), count)]`, the faction
likewise; `next_change_day = epoch_day + (period_index + 1) * days`. A limit's period is the day
itself ("day") or `period_index(day, epoch_day, 7)` ("week"); it resets on `day + 1` or the next
week's first day.

Paying (GameModel.summon(count, use_free, banner_id)): the free pull (count 1, once per local day,
only on the `free_daily` banner) or scrolls if the banner takes them and `scrolls >= cost.scrolls`,
else the other currency (gems, or gold) if enough, else error ("Not enough gems" / "Not enough
gold"). Checks before paying: a wish needs a target from the banner's Legendaries ("Choose your wish
first"); a limited banner refuses a summon bigger than what is left ("No pulls left today",
"Only 7 pulls left this week"). Each banner but the standard one keeps `summon.banners[id]` = {pity,
pulls, lost (featured), target (wish), period, period_pulls (limit)}; the standard pity stays in
`summon.pity`. Each result goes through `receive_hero` in order (new hero, or duplicate ->
`dupe_shards[rarity]` shards, excess -> dust). Fixture: `summon.json`.

### 8.2 Idle (`idle_rules.gd`)

```
per_hour[k] = base_per_hour[k] + per_10_stages_per_hour[k] * cleared / 10
elapsed = now < last_claim_at ? 0 (timer restarts at now) : min(now - last_claim_at, cap_ms)
accrue:  total = per_hour[k] * elapsed + carry[k]; amount[k] = total / 3600000; carry'[k] = total % 3600000
         g = gear_ms + elapsed; gear_count = g / gear_every_ms; gear_ms' = g - gear_count * gear_every_ms
quick claim n (0-based today): cost = quick_claim_costs[n] (none left when n >= length)
         amount[k] = per_hour[k] * quick_claim_ms / 3600000 (no carry); gear timer += quick_claim_ms,
         one drop per whole gear_every_ms (the timer keeps the rest)
```

Rewards with amount 0 are omitted. Drops: slot per section 5, tier = `tier_for(cleared)`.
Fixture: `idle.json`.

### 8.3 Progression (`progression.gd`)

```
level_cost(L): hero_exp = exp_base + exp_per_level * L + exp_per_level_squared * L * L
               gold     = hero_exp + hero_exp / gold_exp_divisor + gold_per_level * L
level_cap(s) = level_cap_base + level_cap_per_star * clamp(s, 1, max_stars)
star_shards(s) = (s < 1 or s >= max_stars) ? 0 : star_shards[s];  shards_to_max(s) = sum of star_shards[max(s,1) .. max_stars-1]
star_up_cost(s, have, rarity): need = star_shards(s); none if 0; missing = max(0, need - have)
     -> {shards: need, dust: missing * dust_per_shard[rarity], shards_have: have, shards_used: min(have, need), dust_per_shard}
add_shards(s, have, n, rarity): keep = min(n, max(0, shards_to_max(s) - have))
     -> {shards: have + keep, dust: (n - keep) * dust_per_excess_shard[rarity]}
affordable_levels(L, cap, gold, exp): count levels from L while L+n < cap and both costs are affordable (paying as it goes)
```

Unknown rarities price as `rare`. Fixture: `progression.json`.

### 8.4 Gear (`gear_rules.gd`)

`make_item(slot, tier, rng_seed, seq)`: tier clamped to 1..max_tier; unknown slot -> `weapon`;
`rng = SeededRng(Mix(rng_seed, seq))`; for each `{stat, by_tier}` of `gear.stats[slot]` in order:
`value = max(1, by_tier[tier] * rng.RangeInt(roll_min_pct, roll_max_pct) / 100)`; then
`noun = rng.Pick(item_names[slot])`. Item: `{uid: "g<seq>", slot, tier, name: "<tier_names[tier]> <noun>",
stats, equipped_by: ""}`. `salvage_value(tier) = {gold: salvage_gold_per_tier * tier, dust: salvage_dust_per_tier * tier}`.
Fixture: `gear.json`.

### 8.5 Prints: misprints (`print_rules.gd`, data/prints.json)

Cosmetic only: a print never changes a stat and never fades. Every hero a summon gives is a
numbered print of the banner's **edition**:

- `edition_on(banner, day, epoch_day)`: `ed = editions[banner]` (unknown banners use `standard`);
  `days = max(1, ed.days)`; `index = period_index(day, epoch_day, days)` (8.1, a true floor);
  `edition = max(1, index + 1)`; `open_day = epoch_day + index * days`; also `run`, `per_hour`.
- `flaw_for_roll(r)` (r in 0..9999): the first flaw (in file order) whose running `bp` total is
  `> r`, else `""` (a clean print). `grade_for_roll(g)`: the first `[grade, bp]` row of `grades`
  whose running total is `> g`, else the last row's grade.
- `make_prints(banner, hero_ids, day, epoch_day, hours_open, ed, seed, seq)` -> `{prints, ed}`.
  `info = edition_on(...)`; `n = ed.n` if `ed.e == info.index` else 0 (a missing `ed` counts as
  another edition); `run = max(1, info.run)`; `rng = SeededRng(mix(seed, seq))`; for each hero in
  order: `raw = 1 + max(0, hours_open) * per_hour + n`; draws in this order: `flaw =
  flaw_for_roll(range_int(0, 9999))`, `holo = chance_bp(holo_bp)`, `grade =
  grade_for_roll(range_int(0, 9999))`, `v = range_int(0, 999)`, `gap = range_int(0,
  other_takers_max)`; the print is `{hero, banner, edition, printing: (raw - 1) / run + 1, serial:
  (raw - 1) % run + 1, run, flaw, ink: inks[v % inks.size] when flaw == "swap" else "", holo,
  grade, v}`; then `n += 1 + gap`. Returns `ed = {e: info.index, n}`.
- `notable(p)`: a flaw, holo, `grade >= 9`, `serial <= early_serial`, `first` true, or a non-empty
  `from`. `score(p) = grade * 100 (+ 3000 holo) (+ 2000 + (300 - flaw bp) for a flaw) (+ 600 +
  (early_serial - serial) for an early serial) (+ 50 for printing 1)`; missing keys count as grade
  0, no holo, no flaw, serial `early_serial + 1`, printing 1.
- `trim(list, keep_plain = file's keep_plain)`: `drop = max(0, plain count - keep_plain)`; walk the
  list (oldest first) skipping the first `drop` plain prints; order is kept.

Model (`summon`): one `make_prints` per summon on the pulled ids with `day = today`,
`hours_open = (now + tz_bias_ms - open_day * 86400000) / 3600000` (whole hours, at least 0),
`ed = prints.ed[banner]`, `seed = prints.seed`, `seq = prints.seq` (before the summon); then
`prints.ed[banner] = out.ed`, `prints.seq += count`. Print i gets `uid "p<seq + i + 1>"`, `day`,
`first` (= the hero was new) and `from ""`; it is appended to `prints.list` and copied into the
summon result as `print`. Then `total += count`, `list = trim(list)` and the showcase drops uids no
longer in the list. This stream never touches the summon's own (`summon.seed`, `total_pulls`), so
the pulls are the same with or without prints. API: `prints(filter)` newest first (`all`,
`misprint` = a flaw, `holo`, `top` = grade 9+, `rival` = `from == "rival"`, `hero:<id>`),
`print_by_uid`, `print_stats() {total, kept, misprints, holo, top, from_rival, best_grade, best}`
(best = the highest score, the earlier print on ties), `set_showcase(uids)` (errors: more than
`showcase_max`, a repeated uid, an unknown uid), `showcase()`. Fixture: `prints.json`.

## 9. GameModel and the save format

`GameModel` (src/core/game_model.gd) holds `state` and implements every Game API action
(docs/dev/architecture.md section 4) with identical names, arguments and results. Port it method
by method; it is plain dictionary logic over the rules above. Its environment:

- `clock()` returns ms since the Unix epoch; `now = clock() + state.dev_time_offset`.
- `tz_bias_ms`: local offset; `day_of(ms) = floor((ms + tz_bias_ms) / 86400000)` (true floor,
  also for negatives); `today = day_of(now)`.
- `outbox`: notifications in emit order (`level_up`, `star_up`, `quest_ready`, `idle_full`,
  `new_hero`, `monthly_card`); `changed_now` / `changed_later`: the adapter raises "changed"
  after actions (now) or after a daily rollover found by a query (deferred) and schedules a save.

Ordering details that change results:
- **Daily rollover** (`refresh_daily`, called at the start of most actions and queries): new
  day -> reset quests, quick claims and daily shop counts; monthly card pays `daily_gems` once
  per day while active.
- **Counter bumps** (`_bump`): after the rollover, `counters[c] += n`; every quest with that
  counter advances; crossing its goal (unclaimed) queues `quest_ready`.
- **grant(reward)**: currencies in order gold, hero_exp, gems, scrolls, dust; `gear_drops`
  create items (in order) then `gear` uids; `heroes` via `receive_hero`; `shards`; if any gear
  arrived: auto-equip the formation (slot order 0-4), then trim the bag.
- **Auto-equip** (per hero, slots in `gear.slots` order): best `gear_score` among loose items
  and (for a formation hero) items worn by benched heroes; the first item in bag order wins ties;
  the current item is replaced only by a strictly better one.
- **Bag trim**: while more than `bag_limit` loose items: salvage the lowest score first, the
  earlier item in the bag on ties.
- **Formation** (`_arrange`): sort by `front_priority[role] * 1000000 + hp` descending, then id
  ascending; fill slots 0..4. `auto_formation` takes the five strongest owned heroes (power
  descending, then id). A new hero joins only a formation with an empty slot (re-arranged), then
  auto-equips.
- **Idle claim**: compute with the rules, set `last_claim_at = now`, then grant; a claim counts
  for the quest when elapsed >= `min_claim_for_quest_ms`.
- **Stage completion**: a win bumps `battles_won`; a first clear sets `campaign.cleared = i + 1`,
  bumps `stages_cleared` and grants the first-clear reward. A loss bumps `battles_lost`.

**Save format** (`user://save.json`, the `state` dictionary as JSON; numbers are ints):

```
version 1 · created_at ms · player_name · dev_time_offset ms · rng_seed · gear_seq
currencies {gold, hero_exp, gems, scrolls, dust}
heroes {id: {id, level, stars, shards, gear {slot: gear uid}}}
formation [5 hero ids or ""]          campaign {cleared}          tower {best}
idle {last_claim_at, quick_claims_used, quick_claim_day, carry {currency: remainder}, gear_ms, full_notified}
summon {pity (standard banner), total_pulls (all banners), last_free_pull_day, seed,
        banners {featured|faction|wish|envoy: {pity, pulls, lost, target, period, period_pulls}}}
gear [{uid, slot, tier, name, stats {..}, equipped_by}]
quests {day, progress {quest id: n}, claimed [quest id]}
shop {purchases {offer id: n}, daily {offer id: n}, day, monthly_until_day, monthly_last_day}
settings {sound, music, haptics, battle_speed (1|2|4), auto_ultimates, nudity}
skins {owned [skin id], equipped {hero id: skin id}}
prints {seed, seq, ed {banner: {e, n}}, list [print (oldest first)], total, showcase [uid]}   (8.5)
rival {seed, met, day, heroes {id: dupes}, pulls, pity {banner: n}, lost, ed, print_seq, prints,
       feed, feed_seq, seen, wins, losses, fights, haul_day, tag_you, tag_her, tag_v}        (9c)
counters {name: n}   (battles_started, battles_won, battles_lost, stages_cleared, summons, level_ups,
                      star_ups, idle_claims, quick_claims, daily_quests_done, skins_bought, tower_floors)
```

Skins: `buy_skin(id)` pays the tier's gems once (errors "Unknown skin", "Already owned", "Not enough
gems") and bumps `skins_bought`; `equip_skin(hero, id)` needs an owned skin of that hero ("" = base
look). `migrate` keeps known skin ids once each and an equipped skin only if it is owned and belongs
to that hero.

`migrate(loaded)` repairs any older or damaged save: fills missing keys from the default state
(missing currencies are 0), drops unknown heroes and invalid gear, clamps stars/levels/tiers,
fixes gear ownership both ways, restores the starters if no hero survived, cleans the
formation (auto-formation if empty), resets an invalid battle speed and clamps `campaign.cleared`.
Fixtures: `session.json` (a scripted first two days) and `save.json` (migrations).

## 9b. The Spire (`src/data/tower.gd`, GameModel `tower_*`)

Floor `f` (1 .. `floors`), with `n` = campaign stage count and `raw` = stage `min(f - 1, n - 1)`
as stored in stages.json:
- `past = max(0, f - n)`; `level = raw.level + past * level_per_floor_past`;
  `stars = min(raw.stars + past / stars_every_past, max_stars)`, each enemy at least its hero's
  start stars; `echo_bp = echo_stat_bp * strength_bp / 10000`.
- Boss floor when `f % boss_every == 0`: `boss = bosses[(f / boss_every - 1) % 3]`, slot 2,
  `is_boss` true.
- Team: `pool` = roster ids in heroes.json order (minus the boss); `rng = SeededRng(mix(seed, f))`;
  pick `range_int(0, pool.size - 1)` and remove it, until 5 heroes (4 on a boss floor). Order the
  picks by `front_priority[role]` descending, then pick order; they fill slots 0,1,2,3,4 (boss
  floor: 0,1,3,4). Enemies are listed by slot.
- `recommended_power = raw.recommended_power * rec_bp / 10000 * (10000 + rec_past_bp * past) / 10000`
  (two truncating steps, in that order); `enemy_power` as for stages.
- Reward: `gold = gold_base + gold_per_floor * f`, `hero_exp = gold * hero_exp_bp / 10000`,
  `dust = dust_base + f / dust_every`; gems `gems` when `f % gems_every == 0`; a boss floor adds
  `boss_gems`, `scrolls = boss_scrolls` and `gear_drops [{slot: gear_slots[(f / boss_every - 1) %
  4], tier: clamp(1 + f / gear_tier_every, 1, max_tier)}]`; `gems` is present only when > 0.
- `background = backgrounds[((f - 1) / floors_per_background) % 3]`.

Model: open when `campaign.cleared >= unlock_cleared`; `tower.best` = highest floor cleared;
only floor `best + 1` can be fought. `complete_tower(f, outcome)`: errors "Unknown floor", "Floor
locked"; a loss bumps `battles_lost`; a win bumps `battles_won` and `tower_floors`, sets `best = f`
and grants the reward. Save: `tower {best}`; `migrate` clamps `best` to 0 .. floors. Fixture:
`stats.json` `tower` (sample floors, with echo stats and enemy power).

## 9c. The Rival (`src/core/rival_rules.gd`, data/rival.json, GameModel `rival*`)

Rue is another summoner simulated on the phone. She never takes anything from the player.

- `new_state(save_seed)`: `{seed: mix(save_seed, rival.seed), met false, day -1, heroes {}, pulls
  0, pity {}, lost false, ed {}, print_seq 0, prints [], feed [], feed_seq 0, seen 0, wins 0,
  losses 0, fights 0, haul_day -1, tag_you false, tag_her false, tag_v 0}`. The model passes
  `now & 0x7FFFFFFF` of the new game.
- `banner_on(day, epoch_day) = banner_cycle[posmod(day - epoch_day, size)]`.
  `counter_faction(main)`: the faction (battle.json `factions` order) whose `beats` is `main`.
- `stars_for(id, dupes, cap) = max(s0, min(s0 + max(0, dupes) / max(1, dupes_per_star),
  min(cap + stars_over_you, max_stars)))`, `s0` = the rarity's start stars.
  `level_on(avg, day, countering) = max(1, avg + level_wobble[posmod(day, 7)] + (counter_level if
  countering))`. `counters(fights, main) = fights >= learn_after and main != ""`.
  `echo_bp = echo_stat_bp * strength_bp / 10000`.
- `team(heroes, cap, level, prefer)`: for each of her heroes in heroes.json order (index i):
  `stars = stars_for`, `lv = clamp(level, 1, level_cap(stars))`, `power = power(stats(id, lv,
  stars))` (no gear); sort by (`prefer` faction first, power descending, i ascending); take 5;
  order those by `front_priority[role]` descending, then that rank; slot = position (0..4). Entry
  `{hero_id, level, stars, slot, is_boss false, echo_bp, power: power(echo_stats(id, lv, stars,
  echo_bp))}`. `ace` = the entry with the highest power (the first on ties).
- `keeps(p)`: a flaw, holo, grade >= 9 or `serial <= early_serial`.
  `sort_prints(list)`: sort by (taken last, score descending, n ascending), cut to `prints_max`,
  then sort by (score descending, n ascending).
- `sim_day(rs, day, epoch_day, owns)`: `bid = banner_on(day)`, `b` its banner; opts as in 8.1
  (featured: `{featured: featured_for(b, day), lost: rs.lost}`, faction: `{faction:
  faction_for(b, day)}`, wish: `{target: first Legendary of the pool}`); `roll = pull(b, rs.seed,
  rs.pulls, rs.pity[bid] or 0, pulls_per_day, opts)`; `rs.pulls = roll.total_pulls`,
  `rs.pity[bid] = roll.pity`, `rs.lost = roll.lost` when present. For each result in order: a new
  hero joins with 0 dupes, a known one gets `+1`; a Legendary queues `{type: "featured_first"}` if
  it is `featured` and not in `owns`, else `"legendary"` (`hero`, `flaw ""`, `ink ""`). Prints:
  `info = edition_on(bid, day)`, `hours = (day - info.open_day) * 24 + pull_hour`, `made =
  make_prints(bid, ids, day, epoch_day, hours, rs.ed[bid] or {}, mix(rs.seed, prints.seed),
  rs.print_seq)`; `rs.ed[bid] = made.ed`; print k gets `n = print_seq + k + 1`, `uid "rue-<n>"`,
  `day`, `first` (her new hero), `taken false`, queues `"misprint"` if it has a flaw, then `"holo"`
  if holo, and is appended to `rs.prints` when `keeps`; `print_seq += count`; `rs.prints =
  sort_prints(rs.prints)`. Each queued event k (in order): `feed_seq += 1`, push to the front of
  `rs.feed` `{n: feed_seq, day, type, hero, flaw, ink, line: line(type, rs.seed, day, k, {hero:
  the hero's name, flaw: the flaw's adj ("" for none)})}`; cut the feed to `feed_max`.
- `catch_up(rs, today, epoch_day, owns)`: empty `heroes` -> `start_heroes` with 0 dupes; `day < 0`
  -> `day = today - 1`; `today <= day` -> 0; else simulate `max(day + 1, today - catch_up_days +
  1) .. today`, set `day = today` and return the count.
- `best_untaken(rs)`: the untaken print with the highest score (lowest `n` on ties), `{}` if none.
  `haul(cleared) = {gems, gold: gold_base + gold_per_stage * cleared, dust}`.
  `cleared_on(c, day) = clamp(c + stage_lead[posmod(day, 5)], 0, stage count)`,
  `tower_on(b, day) = clamp(b + tower_lead[posmod(day, 5)], 0, floors)`,
  `background(day) = backgrounds[posmod(day, size)]`.
- `line(kind, seed, day, salt, fills)`: `lines[kind][posmod(mix(seed, day) + salt, size)]` ("" when the
  kind has none), then `fill`: replace each `{key}` with its value, upper-case the first letter.

Model: open when `campaign.cleared >= unlock_cleared`. Every rival call first syncs her
(`catch_up` to today, `owns` = the player's heroes; a query that simulated sets `changed_later`).
The player context: the formation's heroes give `avg` (sum of levels / count, 1 with none), `best`
stars (at least 1) and `main` (the most common faction, battle.json order on ties).
`counter = counters(fights, main)`, `prefer = counter_faction(main)` when countering, her team
`team(heroes, best, level_on(avg, today, counter), prefer)`. `rival()` returns the view
(`name, title, unlocked, unlock_cleared, met, team, ace, level, roster [{hero_id, dupes, stars}],
power` (sum of the team's power), `your_power, record {wins, losses, fights}, cleared, tower_best,
pulls, banner, feed, new_feed (feed_seq - seen), prints, tags {you, her, v}, haul, haul_ready
(haul_day != today), haul_print, counter {faction, main}, line, line_kind`); `line_kind` is
`intro` (not met), `win` (tag_you), `lose` (tag_her), `counter`, today's newest feed entry (its
stored line), else `idle`; the line is `line(kind, seed, today, fights, {you: player_name, faction,
main})` (faction names capitalised). `rival_meet()` sets `met` (line `intro`, salt 0);
`rival_seen()` sets `seen = feed_seq`; `rival_alert() = haul_day != today or feed_seq > seen`.
`rival_battle_setup()`: allies as for stages, enemies = her team as echoes, `seed = mix(rng_seed
+ 900001, battles_started)` (then `battles_started += 1`), `background(today)`. `complete_rival(outcome)`:
`fights += 1`, `tag_v = mix(seed, fights) % 1000`; a win bumps `battles_won`, `wins += 1`, `tag_her
= true`, `tag_you = false`, and if `haul_day != today`: `haul_day = today`, grant `haul(cleared)`,
mark `best_untaken` taken and append a copy (without `taken` and `n`, with `from "rival"`, `day`
today, `first false`) to the album (`total += 1`, then trim); line `lose`. A loss bumps
`battles_lost`, `losses += 1`, `tag_you = true`, `tag_her = false`, line `win`; nothing is taken.
Save: `rival {...}` as in `new_state`; `migrate` keeps known heroes (dupes >= 0), known banners'
pity (clamped below their pity limit) and editions, dict prints with a known hero and a uid, at
most `feed_max` dict feed entries, counters >= 0 and `seen <= feed_seq`. Fixture: `rival.json`.
Tuning: `tests/tools/rival_bench.gd` (strength_bp sweep).

## 10. Golden fixtures (`data/fixtures/`)

Each file: `{version, about, regenerate, ...}`. Inputs and expected outputs sit side by side.
**Compare as JSON values**: objects by key set and values (order-free), arrays in order, ints exactly.

| File | Inputs -> outputs |
|---|---|
| `rng.json` | `sequences[]: seed -> next_u32 (12 values)`; `mix[]: a, b -> out`; `range_int[]`, `chance_bp[]`, `pick[]`: seed + args -> 10 successive results (+ `next_u32_after` to check draw counts). |
| `progression.json` | `level_cost[]` for levels 1-139; `level_cap[]`, `star_shards[]` (next, to_max) for stars 0-7; `star_up_cost[]`, `add_shards[]`, `affordable_levels[]` -> out. |
| `idle.json` | `per_hour[]` by cleared; `elapsed[]`; `accrue[]` (elapsed_ms, cleared, carry, gear_ms -> {reward, carry, gear_ms}); `quick_claim[]` (used -> cost, left); `quick_reward[]`. |
| `gear.json` | `tier_for[]`; `random_slot[]` (rng_seed, gear_seq); `make_item[]` (slot, tier, rng_seed, seq -> item); `salvage[]`. |
| `stats.json` | `hero_stats[]` (hero, level, stars, gear items -> stats, power); `gear_score[]`; `stages[]`: every built stage's enemies with echo stats, enemy_power, recommended_power, first_clear_reward. |
| `summon.json` | `rarity_for_roll[]` (rate boundaries); `cases[]` (standard banner): seed, total_pulls, pity, counts -> one `{results [{hero_id, rarity, pity}], pity, total_pulls}` per summon, chained; `banner_cases[]`: the same on `banner` with `opts` (featured + lost, faction, target; on the featured banner `opts.lost` chains from each `out.lost`); `rotation[]`: day -> featured, faction, their next change days, the wish and envoy limit periods and reset days (`epoch_day` stored). |
| `battles.json` | `battles[]`: setup (+ `auto_ultimates`, `manual_ultimates [{tick, uid, accepted}]`) -> `steps`, every event of every step in order, `outcome`, `final_units`, `skip_outcome` (run_to_end on a fresh sim). Manual requests are made before step number `tick` (1 = the first step). |
| `session.json` | GameModel: `start_ms`, `tz_bias_ms`, `steps [{advance_ms, call, args}]` -> `results [{value, notify}]`, `final_state`. Each step advances the clock, then calls the method; `"battle"` = `stage_battle_setup(i)` + `run_to_end` + `complete_stage(i, outcome)`, value `{seed, victory, duration_ms, complete}`. |
| `save.json` | `cases []`: `now_ms`, `input` (a save) -> `out` (`migrate(input)`). |
| `prints.json` | `editions[]` (banner, day, epoch_day -> out); `flaw_rolls` -> `flaws`, `grade_rolls` -> `grades`; `make_prints[]` (inputs -> `out {prints, ed}`, a long run covers every flaw and holo); `samples[]` (print -> notable, score); `trim` (list, keep_plain -> `out`, `out_default`). |
| `rival.json` | `banner_days` -> `banners`; `factions` -> `counters`; `stars[]`, `levels[]`, `teams[]` -> out; `sims[]`: `new_state(seed)` then each step `catch_up(state, today, epoch_day, owns)` -> `{days, state, best_untaken}`; `hauls` -> `haul_out`; `leads` ([cleared, Spire best, day]) -> `lead_out`; `lines` ([kind, seed, day, salt, fills]) -> `line_out`. |

**Checking (NUnit sketch):** load each file with Newtonsoft, run the inputs through your port,
serialize the result to a `JToken`, and assert `JToken.DeepEquals(expected, actual)` (DeepEquals
treats object key order as irrelevant). Report the first differing path to debug.

**Second reference:** `tests/port_check/check_port.py` is an independent Python
implementation of sections 4-8 (RNG, stats, battle, summon, idle, progression, gear), 8.5 (prints),
9b (the Spire's floors) and 9c (the Rival's rules), written
from this document, that passes every fixture except `session`/`save` (GameModel is not
covered). Run `python3 -B tests/port_check/check_port.py`. It is a compact model for the C#
code, and proof that this document is precise enough to port from.

**Regenerate** only after an *intended* change to rules or tuning (battle rules, kits, stage
data, economy numbers, RNG use) or to the fixture inputs in `tests/golden.gd`:

```bash
tools/gd --headless --path . -s tests/tools/make_fixtures.gd          # all files (or name some: battles summon)
tools/gd --headless --path . -s tests/run_tests.gd -- test_fixtures   # must pass
```

A refactor that should not change behaviour must pass `test_fixtures` **without**
regenerating. After `tests/tools/calibrate_stages.gd ... write` the stage-dependent fixtures
(`stats`, `battles`, `session`) change by design: regenerate and review the diff.

## 11. Port procedure

1. Unity project (URP 2D, portrait). Copy `data/` (fixtures go to the test assembly only), PNG
   art exports and fonts.
2. `Core` assembly (no `UnityEngine`): SeededRng -> pass `rng.json`; StatCalc + loaders -> pass
   `stats.json`; Progression, IdleRules, GearRules, SummonRules -> pass their fixtures;
   BattleSim -> pass `battles.json` event for event; GameModel -> pass `save.json` and `session.json`.
3. `GameService` MonoBehaviour: clock (UTC ms + time zone offset), save/load the same JSON
   (atomic write, back up a corrupt file, autosave 1.5 s after a change, save on pause/quit),
   C# events for `changed` / `notify`, poll the daily rollover and idle cap every 2 s.
4. Rebuild screens in uGUI against `screenshots/` and `docs/game-design.md`.

Alternative: Godot also supports C#. Rewriting `src/core` in C# inside Godot would let the same
`.cs` files drop into Unity almost unchanged, verified by the same fixtures. Not done for v1
because Godot's C# iOS export is still experimental.
