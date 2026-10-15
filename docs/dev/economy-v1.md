# Halo & Horn: Economy and Balance v1

Owner: core logic. Every number below lives in code; this page explains the formulas and
the intended pacing. Source of truth:

| What | File |
|---|---|
| Currencies, costs, idle, summon, gear, quests, shop | `src/data/economy.gd` (`EconomyData`) |
| Hero base stats, ultimates, passives | `src/data/hero_kits.gd` (`HeroKits`) |
| Stat and power formulas | `src/core/stat_calc.gd` (`StatCalc`) |
| Battle rules | `src/core/battle_sim.gd` (`BattleSim`) |
| Campaign, enemy echoes, first-clear rewards | `src/data/stages.gd` (`StageData`) |

All numbers are ints; percentages are basis points (10000 = 100%).

## 1. Intended pacing

| When | Player does | Team |
|---|---|---|
| Session 1, minutes 0-5 | Clears 1-1..1-3 with the three starter Rares (Uriela, Lucen, Kessa). Summons with the 10 starting scrolls, the free daily pull and the 1,800 starting gems (6 pulls): about 17 heroes, at least 1 Epic guaranteed by the 10-pull. | 3 Rares at L1-5 |
| Session 1, minutes 5-40 | Fields 5 heroes, levels them with starting and first-clear EXP. 1-4..1-9. The starters alone stall around 1-6/1-7 (they would need L16-22). | L7-13, 2-3 Epics |
| End of day 1 | 1-10 boss (Seraphiel echo) needs about L16 on a reference team; a free quick claim plus idle EXP covers it. | ~L16-20 |
| Days 2-3 | Chapter 2 (Ember Wastes). Two 12 h idle claims a day carry the leveling; first star-ups from duplicates. | L18-37 |
| Days 4-8 | Chapter 3 (Twilight Abyss). Needs L39-62: Rares must star up (1-star cap is L40, 2-star L60), gear tier 4-5, ideally a Legendary. Real investment. | L40-62, 3-4 stars |

Day 1 summons for a free player: ~17 at start + chapter 1 first clears (700 gems, 3 scrolls)
+ daily quests (290 gems, 1 scroll) + daily gift (30 gems) = about 25 pulls.

## 2. Currencies: sources and sinks

| Currency | Start | Sources | Sinks |
|---|---|---|---|
| gold | 4,000 | idle, first clears, quests, daily gift, gear salvage | hero levels |
| hero_exp | 2,400 | idle, first clears, quests | hero levels |
| gems | 1,800 | idle trickle, boss/stage first clears, quests, daily gift, shop (test purchases) | summons (300 / 2,700), paid quick claims (50/100/150) |
| scrolls | 10 | first clears (1-8, 1-10 style milestones), quests, shop | summons (1 / 10), used before gems |
| dust | 0 | idle trickle, boss first clears, maxed-hero duplicates, gear salvage | stands in for missing shards when starring up |
| shards (per hero) | 0 | duplicate summons | star-ups |

## 3. Heroes

**Stats** (`StatCalc.stats`):

    stat(hp/atk/def) = (base * (1 + 7% * (level - 1)) * (1 + 12% * (stars - 1)) + gear) * (1 + passive %)
    spd  = base_spd + (stars - 1) + gear spd, then * (1 + passive %)
    crit = base_crit + gear crit + passive crit   (cap 75%)

`base_stats` in `hero_kits.gd` are level 1, 1-star values. Epics start at 2 stars (+12%) and
Legendaries at 3 stars (+24%) with slightly higher base numbers, so a fresh Legendary is about
1.5x a fresh Rare, but a starred-up Rare stays useful (6-star Rare = 1.6x its 1-star self).

**Power** (`StatCalc.power`, shown in the UI): `(hp/2 + 8*atk + 6*def) * spd/100 * (1 + crit/2) / 5`.

**Level cap:** 20 + 20 x stars (40 at 1 star ... 140 at 6 stars).

**Level cost** from level L to L+1: `hero_exp = 20 + 10L + L^2`, `gold = exp * 1.25 + 10L`.

| Levels | Total EXP | Total gold |
|---|---|---|
| 1 -> 10 | 915 | 1,590 |
| 1 -> 20 | 4,750 | 7,830 |
| 1 -> 30 | 13,485 | 21,195 |
| 1 -> 40 | 29,120 | 44,185 |
| 1 -> 60 | 89,090 | 129,040 |
| 1 -> 80 | 200,660 | 282,395 |
| 1 -> 140 | 1,004,970 | 1,353,460 |

**Stars:** shards for the next star by current stars: 1->2: 10, 2->3: 20, 3->4: 40, 4->5: 60,
5->6: 100. A duplicate gives 10 / 20 / 40 shards (Rare / Epic / Legendary). Missing shards can
be paid with **10 dust each** (`star_up_cost` returns the shards needed and the dust that
would cover the shortfall). Shards a 6-star hero can no longer use become 4 dust each.
Passives unlock at 3 and 5 stars (Legendaries start with the first one).

| Rarity | Start | Shards to 6 stars | Duplicates to 6 stars |
|---|---|---|---|
| Rare | 1 star | 230 | 23 |
| Epic | 2 stars | 220 | 11 |
| Legendary | 3 stars | 200 | 5 |

## 4. Battle rules that drive balance

- 100 ms ticks, 90 s limit (a timeout is a loss). Attack interval = 100000 / spd ms.
- Damage = `ATK * mult * ATK / (ATK + DEF)`, +20% vs the faction you beat
  (celestial > infernal > fallen > celestial), crits x1.5 (+ passives), +/-5% variance.
- Energy: +100 per basic attack, + up to 500 for losing a full health bar per hit (min 15,
  max 200 per hit). Ultimate at 1000, so most heroes cast every 7-10 s.
- Faction bonus: 3/4/5 heroes of one faction give the whole team +6/10/15% HP and ATK.
- Bosses: HP x2.5, ATK x1.15, DEF x1.1, stuns on them last half as long, no executes.
- Shields cap at 60% of max HP.

Typical battles last 20-45 s at 1x; even matches run 45-75 s. Simulation cost: 5-15 ms per
battle, about 37 ms for a pathological 90 s all-tank mirror on the dev VM.

## 5. Campaign difficulty

Enemies are **echoes**: roster heroes at the stage's level and stars with HP/ATK/DEF at 75% x
the stage's `pw` (echo strength). Displayed enemy levels rise steadily; `pw` absorbs the
difference between compositions (Cassiel shields, healers and guardian bosses fight much longer
than a squad of strikers). `pw` is solved by `tests/tools/calibrate_stages.gd` so that a
**reference team** needs the "calibrated level" below to win:

- 1-1..1-3: the three starter Rares, >= 90% of seeds.
- Later: 3 starter Rares + Brakka (Epic) + Liora (Epic), no gear, 1-2 stars, >= 70% of seeds.

`recommended_power` is that reference team's power at the calibrated level, so it reflects the
real difficulty and never drops from one stage to the next. Better heroes, stars, gear,
counter-picking the chapter's faction and the faction bonus all let a player beat a stage
below that level (a 3-star team needs ~10 fewer levels in chapter 3).

| Stage | Name | Enemy lv | Enemy stars | pw | Boss | Calibrated level | Recommended power | First clear gold / EXP | Extra first-clear rewards |
|---|---|---|---|---|---|---|---|---|---|
| 1-1 | Broken Narthex | 1 | 1 | 14000 | - | L1 | 1322 | 1500 / 900 | - |
| 1-2 | Hall of Fallen Bells | 2 | 1 | 11000 | - | L2 | 1410 | 1950 / 1160 | T1 weapon |
| 1-3 | Glass Garden | 3 | 1 | 11500 | - | L4 | 1595 | 2400 / 1420 | 100 gems |
| 1-4 | Pillar Walk | 4 | 1 | 13000 | - | L3 | 2526 | 2850 / 1680 | - |
| 1-5 | The Gate Warden | 5 | 1 | 10250 | Cassiel | L5 | 2838 | 3300 / 1940 | 200 gems, 50 dust, T1 weapon |
| 1-6 | Ashen Cloister | 7 | 1 | 11750 | - | L7 | 3150 | 3750 / 2200 | - |
| 1-7 | Reliquary Stair | 8 | 2 | 11500 | - | L9 | 3460 | 4200 / 2460 | T1 charm |
| 1-8 | Choir Loft | 10 | 2 | 12500 | - | L11 | 3775 | 4650 / 2720 | 1 scrolls |
| 1-9 | Bell Tower Ruin | 11 | 2 | 11500 | - | L13 | 4084 | 5100 / 2980 | - |
| 1-10 | The Choir Unsung | 13 | 2 | 9500 | Seraphiel | L16 | 4553 | 5550 / 3240 | 400 gems, 2 scrolls, 50 dust, T3 charm |
| 2-1 | Cinder Road | 15 | 2 | 10750 | - | L18 | 4867 | 6000 / 3500 | - |
| 2-2 | Sulfur Springs | 17 | 2 | 10000 | - | L20 | 5181 | 6450 / 3760 | T2 armor |
| 2-3 | Molten Ford | 19 | 2 | 12250 | - | L22 | 5493 | 6900 / 4020 | 100 gems |
| 2-4 | Chainworks | 21 | 2 | 10500 | - | L24 | 5806 | 7350 / 4280 | - |
| 2-5 | Brimstone Bulwark | 23 | 2 | 7750 | Brakka | L27 | 6272 | 7800 / 4540 | 200 gems, 75 dust, T3 weapon |
| 2-6 | Ashfall Market | 24 | 3 | 9250 | - | L28 | 6424 | 8250 / 4800 | - |
| 2-7 | Lantern Bazaar | 26 | 3 | 11000 | - | L30 | 6737 | 8700 / 5060 | T3 weapon |
| 2-8 | Obsidian Steps | 28 | 3 | 9000 | - | L32 | 7049 | 9150 / 5320 | 1 scrolls |
| 2-9 | Furnace Gate | 30 | 3 | 8500 | - | L34 | 7362 | 9600 / 5580 | - |
| 2-10 | Throne of the Ninth Furnace | 32 | 3 | 9250 | Mordessa | L37 | 7830 | 10050 / 5840 | 400 gems, 2 scrolls, 75 dust, T4 charm |
| 3-1 | Dusk Shore | 34 | 3 | 11500 | - | L39 | 8146 | 10500 / 6100 | - |
| 3-2 | Chapel of Ghosts | 36 | 3 | 10000 | - | L41 | 8453 | 10950 / 6360 | T4 helm |
| 3-3 | Broken Oath Bridge | 38 | 3 | 11750 | - | L43 | 8769 | 11400 / 6620 | 100 gems |
| 3-4 | Hollow Choir | 40 | 3 | 11000 | - | L45 | 9080 | 11850 / 6880 | - |
| 3-5 | The Chained Gate | 42 | 3 | 8250 | Orrin | L48 | 9547 | 12300 / 7140 | 200 gems, 100 dust, T4 weapon |
| 3-6 | Ash Witch's Hollow | 44 | 4 | 11250 | - | L50 | 9858 | 12750 / 7400 | - |
| 3-7 | Mirror Lake | 46 | 4 | 8000 | - | L52 | 10171 | 13200 / 7660 | T4 armor |
| 3-8 | Feather Graveyard | 48 | 4 | 8500 | - | L55 | 10638 | 13650 / 7920 | 1 scrolls |
| 3-9 | Eclipse Stair | 50 | 4 | 8250 | - | L58 | 11111 | 14100 / 8180 | - |
| 3-10 | The Last Order | 53 | 4 | 8250 | Noctaire | L62 | 11731 | 14550 / 8440 | 400 gems, 2 scrolls, 100 dust, T5 charm |

First-clear gold = 1,500 + 450 x index, EXP = 900 + 260 x index (index 0-29). Bosses also give
dust. Replays pay nothing (they still count for "Win 3 battles"), so the campaign cannot be
farmed for currency; idle is the steady income.

Chapter themes set the counter-pick: chapter 1 echoes are Celestial (bring Fallen), chapter 2
Infernal (bring Celestial), chapter 3 Fallen (bring Infernal). Each stage's `hint` says so.

## 6. Idle rewards

Per hour, with `c` = stages cleared:

| Currency | Per hour | c = 0 | c = 10 | c = 20 | c = 30 |
|---|---|---|---|---|---|
| gold | 600 + 110c | 600 | 1,700 | 2,800 | 3,900 |
| hero_exp | 400 + 75c | 400 | 1,150 | 1,900 | 2,650 |
| dust | 4 + c | 4 | 14 | 24 | 34 |
| gems | 3 + floor(c / 5) | 3 | 5 | 7 | 9 |
| gear | 1 piece per 3 h | | | | |

- Cap: 12 h. Sub-unit remainders carry over between claims, so frequent claimers lose nothing.
- Gear tier from idle and first clears: `1 + cleared / 7` (T1 at the start, T5 from 28 cleared).
- Quick claim: 2 h of rewards instantly, 4 per day: free, then 50 / 100 / 150 gems. Resets at
  local midnight. It does not reset the idle timer.
- New gear is auto-equipped onto the formation when it is an upgrade. More than 40 loose
  pieces: the weakest are salvaged (400 gold + 3 dust per tier).
- The idle rate always uses the current progress, so clearing a stage raises pending rewards.

## 7. Summoning

| | |
|---|---|
| Single | 1 scroll, else 300 gems |
| Ten | 10 scrolls, else 2,700 gems (10% off) |
| Rates | Legendary 2%, Epic 18%, Rare 80% (uniform within a rarity; all 15 heroes) |
| Pity | the 60th pull without a Legendary is a Legendary; counter shown via `pity_count()` |
| Ten-pull | always has an Epic or better (the 10th result is upgraded if needed) |
| Free | one free single pull per local day |

Effective Legendary rate with pity is ~2.85% (one per ~35 pulls on average, never more than 60).
Results come from an RNG seeded by the save (`summon.seed + total_pulls`), so reloading a save
does not reroll a summon.

## 8. Daily quests (reset at local midnight)

| Quest | Goal | Reward |
|---|---|---|
| Collect idle rewards twice | 2 | 40 gems, 3,000 gold |
| Win 3 battles | 3 | 60 gems, 1,500 EXP |
| Summon a hero | 1 | 50 gems |
| Level up heroes 5 times | 5 | 5,000 gold, 2,000 EXP |
| Use a Quick Claim | 1 | 40 gems |
| Complete 5 daily quests | 5 | 100 gems, 1 scroll |

All of them fit in 10 minutes and match the core loop (claim, fight, summon, level). Progress
is driven by `state.counters` bumps (`idle_claims`, `battles_won`, `summons`, `level_ups`,
`quick_claims`, `daily_quests_done`).

## 9. Shop (prototype: every purchase is a free test purchase)

| Offer | Price label | Reward | Limit |
|---|---|---|---|
| Daily Blessing | Free | 30 gems, 2,000 gold | 1 per day |
| Envoy's Starter Pack | $0.99 | 1,200 gems, 10 scrolls, 50,000 gold, 30,000 EXP | 1 |
| Moonlit Pass (monthly card) | $4.99 | 300 gems now, then 100 gems on each day you log in for 30 days | repeatable (extends) |
| Summoner's Satchel | $9.99 | 10 scrolls, 300 dust | 3 |
| Pouch / Chest / Reliquary of Gems | $4.99 / $14.99 / $49.99 | 330 / 1,100 / 3,880 gems | none |

## 10. Free-player income

Per day around chapter 2 (c = 15): quests 290 gems + 1 scroll, daily gift 30 gems, idle gems
~6/h x 24 h = 144 -> about **460 gems + 1 scroll = ~2.5 pulls a day**, ~75 pulls a month (plus
700 gems and 3 scrolls per chapter from first clears). That is ~2 Legendaries a month; maxing a
specific Legendary (5 duplicates) takes months, softened by dust (10 per missing shard, ~24
dust/h late game). The monthly card adds ~3,300 gems (11 pulls) a month.

## 11. Tuning tools

    tools/gd --headless --path . -s tests/tools/balance_report.gd [-- seeds=8 stages=0-29]
    tools/gd --headless --path . -s tests/tools/calibrate_stages.gd [-- stages=0-9]
    tools/gd --headless --path . -s tests/tools/inspect_battle.gd -- stage=9 plv=16 seed=1
    tools/gd --headless --path . -s tests/tools/bench_sim.gd

- **balance_report**: for every stage, the lowest uniform level at which several team
  profiles (starters, reference, day-1 mix, 3-star, late) win 70%, next to the level the
  economy can afford at that point of the intended pacing.
- **calibrate_stages**: re-solves `pw` after changing kits, enemy teams or battle rules. Paste
  its output into `StageData.STAGES`.
- **inspect_battle**: per-unit damage, healing, ultimates and deaths for one battle.

Unit tests (`tests/unit/test_balance.gd`) guard the key promises: starters win 1-1 (>= 18/20
seeds), unupgraded starters lose 1-10, the `--rich` state wins 1-10, three starters at L12 lose
1-6, enemy levels and recommended power never drop.
