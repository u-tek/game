# Halo & Horn: Economy and Balance v1

Owner: core logic. Every number below lives in the JSON data under `data/` (loaded read-only
by thin GDScript loaders); this page explains the formulas and the intended pacing. Source of
truth:

| What | File |
|---|---|
| Currencies, costs, idle, gear, stats growth | `data/economy.json` (`EconomyData`) |
| Summon banner (cost, rates, pity, pool) | `data/banner.json` |
| Daily quests | `data/quests.json` |
| Shop offers | `data/offers.json` |
| Hero identity, base stats, ultimates, passives | `data/heroes.json` (`HeroData`, `HeroKits`) |
| Battle tuning (timer, counters, faction bonus, boss) | `data/battle.json` (`BattleSim`) |
| Campaign, enemy echoes, first-clear rewards | `data/stages.json` (`StageData`) |
| Stat and power formulas | `src/core/stat_calc.gd` (`StatCalc`) |
| Battle rules | `src/core/battle_sim.gd` (`BattleSim`) |
| Pacing model (the "free player" the curve is tuned for) | `tests/tools/pacing_bot.gd` |
| "Never hard-stuck" guard (a reasonable new player) | `tests/unit/test_playthrough.gd` |

All numbers are ints; percentages are basis points (10000 = 100%).

## 1. Intended pacing

The campaign is tuned against an **efficient free player**: four short sessions a day (9:00,
13:00, 19:00, 23:00), claims idle and quests, uses the free quick claim, free pull and daily
gift, summons with every scroll and with gems in 10-pulls, keeps the best five heroes in an
auto-arranged formation, stars up from duplicates and levels the team evenly
(`tests/tools/pacing_bot.gd`). Stage difficulty is solved so that this player clears each stage
at its **target hour** (hours of play since the first session):

| When | Target | What it feels like |
|---|---|---|
| First session (minutes) | 1-1..1-5 | The three starter Rares win 1-1..1-3 at level 1 with no upgrades. 1-4 is the first wall: summon (10 scrolls, 1,800 gems = 6 pulls, the free pull) and level up. The 1-5 boss (Cassiel echo) closes the session. |
| Rest of day 1 | 1-6..1-10 | Idle EXP between check-ins pays for ~2 stages per session. 1-10 (Seraphiel echo) at the last session of the day. |
| Days 2-4 | Chapter 2 | Two to three stages a day. First star-ups beyond 3 stars, tier 2-3 gear. |
| Days 5-10 | Chapter 3 | One or two stages a day; levels 44-64, 4-star heroes, tier 4-5 gear. Real investment. |

Measured with `tests/tools/playthrough.gd` (four bots with different summon luck, playing
freely): 5-7 stages after the first session, **8-12 after day 1**, 18-21 after day 3, 22-28
after day 5, campaign finished on days 6-8. A player with fewer sessions, or who spends less
well, takes longer; the 12 h idle cap means two check-ins a day lose little.

Why it is gated: first-clear EXP and gold are small (section 5) and level costs grow with
the square of the level, so **idle income is what buys the levels** the next stages need. The
first version paid ~140k EXP in first-clear rewards, which let a player run through all 30
stages in an afternoon; this version pays ~48k in total.

## 2. Currencies: sources and sinks

| Currency | Start | Sources | Sinks |
|---|---|---|---|
| gold | 4,000 | idle, first clears, quests, daily gift, gear salvage | hero levels |
| hero_exp | 2,400 | idle, first clears, quests | hero levels |
| gems | 1,800 | idle trickle, first clears (stage x-3 and bosses), quests, daily gift, shop (test purchases) | summons (300 / 2,700), paid quick claims (50/100/150) |
| scrolls | 10 | first clears (x-8, x-10), "complete 5 quests", shop | summons (1 / 10), always used before gems |
| dust | 0 | idle trickle, boss first clears, duplicates of maxed heroes, gear salvage, shop | stands in for missing shards when starring up (price by rarity) |
| shards (per hero) | 0 | duplicate summons | star-ups |

## 3. Heroes

**Stats** (`StatCalc.stats`):

    stat(hp/atk/def) = (base * (1 + 7% * (level - 1)) * (1 + 12% * (stars - 1)) + gear) * (1 + passive %)
    spd  = base_spd + (stars - 1) + gear spd, then * (1 + passive %)
    crit = base_crit + gear crit + passive crit   (cap 75%)

`base_stats` in `data/heroes.json` are level 1, 1-star values. Epics start at 2 stars and
Legendaries at 3 stars (with their first passive) with higher base numbers.

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
5->6: 100. A duplicate gives 10 / 20 / 40 shards (Rare / Epic / Legendary). Passives unlock at
3 and 5 stars.

Missing shards can be paid with **dust, priced by rarity** (`EconomyData.dust_per_shard`):
10 / 25 / 60 dust per Rare / Epic / Legendary shard. `star_up_cost` returns the shards the star
needs, the dust that covers the shortfall and `dust_per_shard`. Shards a hero can no longer use
(beyond 6 stars) become dust at 40% of that price: 4 / 10 / 24 per shard.

| Rarity | Start | Shards to 6 stars | Duplicates to 6 stars | All in dust |
|---|---|---|---|---|
| Rare | 1 star | 230 | 23 | 2,300 |
| Epic | 2 stars | 220 | 11 | 5,500 |
| Legendary | 3 stars | 200 | 5 | 12,000 |

Idle dust is 3 + c/2 per hour (c = stages cleared), so dust tops up a star or two on a Rare
quickly but replaces a Legendary duplicate only after weeks. It smooths bad luck; it never
makes summoning pointless (the first version priced every shard at 10 dust, which let a
Legendary reach 6 stars from idle dust in about three days).

### Kits

Every hero has one ultimate (fires at 1,000 energy) and two passives (3 and 5 stars). Effect
types are documented at the top of `src/data/hero_kits.gd` and in `docs/dev/unity-port.md`
section 3.1; the kits themselves are in `data/heroes.json`. `BattleSim` implements all of them.

| Hero | Rarity | Role | Ultimate | 3-star passive | 5-star passive |
|---|---|---|---|---|---|
| Seraphiel | legendary | caster | **Hymn of Judgment**: Sings the sky's final verse: 180% ATK to all enemies and Stuns them for 1.5 s. | **Radiant Aria**: Basic attacks have a 25% chance to Stun the target for 1 s. | **Choir Eternal**: +20% ATK and +10% HP. |
| Cassiel | epic | guardian | **Dawnwall**: Raises the Gate Wardens' wall: shields all allies for 10% of her max HP and grants them +20% DEF for 5 s. | **Unbroken Line**: +15% HP and +10% DEF. | **Morning Vigil**: Battle start: gains a shield equal to 25% of her max HP. |
| Liora | epic | support | **Lullaby of Mending**: A lullaby that closes wounds: heals all allies for 240% ATK and grants Regen (40% ATK per second) for 4 s. | **Soft Refrain**: Healing done +25%. | **Hymn of Plenty**: Battle start: all allies gain +10% max HP. |
| Uriela | rare | striker | **Sunlance**: Hurls her blazing spear: 360% ATK to her target and breaks its armor, -40% DEF for 6 s. | **Bastion Drills**: +12% ATK. | **Sunburst Edge**: +15% crit chance and +25% crit damage. |
| Nuriel | rare | assassin | **Daybreak Ambush**: Dives to the back row: strikes the weakest back-row enemy twice for 170% ATK each and Stuns it for 1 s. | **Light Step**: +15% SPD. | **First Light**: Battle start: gains 400 energy. |
| Mordessa | legendary | striker | **Ninth Furnace**: Brings down the burning greatsword: 320% ATK to her target, 140% ATK to every other enemy, and Burns them all (50% ATK per second) for 4 s. | **Queen's Wrath**: +15% ATK and +10% crit chance. | **Unending War**: On kill: restores 20% of her max HP and gains 300 energy. |
| Brakka | epic | guardian | **Magma Bulwark**: Plants his molten gauntlets: gains a shield of 40% max HP and Taunts all enemies for 5 s. | **Molten Hide**: Reflects 20% of damage taken back to the attacker. | **Second Helping**: +25% HP. |
| Vesper | epic | caster | **Ember Rain**: Forecast: fire. 140% ATK to all enemies and Burns them (50% ATK per second) for 6 s. | **Ashen Forecast**: Basic attacks have a 35% chance to Burn the target (30% ATK per second) for 3 s. | **Inferno Thesis**: +18% ATK. |
| Imra | rare | support | **Lantern Pact**: Strikes a deal with the whole team: all allies +20% ATK for 5 s, and every other ally gains 100 energy. | **Fair-ish Deal**: Basic attacks have a 50% chance to Weaken the target: -15% ATK for 3 s. | **Lantern Light**: Battle start: all allies gain 150 energy. |
| Kessa | rare | assassin | **Twelfth Contract**: Pounces on the weakest enemy anywhere: 280% ATK, executing it if left below 25% HP (not bosses). | **Hunter's Instinct**: +25% damage to enemies below 50% HP. | **Nine Lives**: Heals for 20% of damage dealt. |
| Noctaire | legendary | assassin | **Eclipse Harvest**: Dives into the back row with her crescent scythe: 220% ATK to every back-row enemy, executing any left below 30% HP (not bosses). | **Severed Wings**: +15% crit chance and +10% SPD. | **Last Order**: On kill: gains 500 energy. |
| Orrin | epic | guardian | **Chains of the Oath**: Lashes out with broken chains: 130% ATK to front-row enemies and Stuns them for 2.5 s, then Weakens all enemies (-25% ATK) for 6 s. | **Oathbound**: Takes 12% less damage. | **Guarding Chains**: +20% DEF and +15% HP. |
| Sable | epic | support | **Dusk Requiem**: Swings the censer for the lost: all enemies -50% DEF for 8 s, and all allies heal for 200% ATK. | **Censer Smoke**: Basic attacks Expose the target: -25% DEF for 3 s. | **Vespers**: Each basic attack also heals the most wounded ally for 70% ATK. |
| Lucen | rare | striker | **Twinfeather Flurry**: A dazzling flurry: 5 strikes of 85% ATK at random enemies, then +25% SPD for 5 s. | **Neither Side**: +10% ATK and +10% HP. | **Flourish**: Basic attacks have a 30% chance to strike twice. |
| Ashra | rare | caster | **Accidental Inferno**: Oops. 180% ATK to all enemies, +60% damage to enemies below 50% HP. | **Careful Study**: +15% ATK. | **Ash Cloud**: Her ultimate also Weakens all enemies: -15% ATK for 4 s. |

Kits were balanced by swapping each hero into a fixed team of the same level and stars and
measuring the level it needs across five stages (lower is better): Legendaries need about 10%
fewer levels than Epics and Rares; within a role, Epics and Rares land within a few levels of
each other (Rares stay useful, Epics are not mandatory). Damage scales with ATK^2 / (ATK + DEF),
so ATK buffs are worth roughly double their number and DEF breaks about half; kit numbers
account for that (e.g. Sable's -50% DEF, Imra's +20% ATK).

## 4. Battle rules that drive balance

- 100 ms ticks, 90 s limit (a timeout is a loss). Attack interval = 100000 / spd ms.
- Targeting: taunt first; assassins hit the weakest back-row enemy; casters hit a random
  enemy; everyone else hits the front row first (their own lane when possible).
- Damage = `ATK * mult * ATK / (ATK + DEF)`, +20% vs the faction you beat
  (celestial > infernal > fallen > celestial), crits x1.5 (+ passives), +/-5% variance.
- Energy: +100 per basic attack, + up to 500 for losing a full health bar per hit (min 15,
  max 200 per hit). Ultimate at 1000, so most heroes cast every 7-10 s.
- Faction bonus: 3/4/5 heroes of one faction give the whole team +6/10/15% HP and ATK.
- Bosses: HP x2.5, ATK x1.15, DEF x1.1, stuns on them last half as long, no executes.
- Shields cap at 60% of max HP.

Battles at the intended power last 20-55 s at 1x (the calibration rejects slower wins);
stronger teams finish much faster. Simulation cost (`tests/tools/bench_sim.gd`, dev VM): ~5 ms for a typical
campaign battle; ~25 ms for a pathological 90 s all-tank mirror with `run_to_end()` (Skip
builds no event dictionaries); stepping with events costs ~45 us per 100 ms tick.

## 5. Campaign

Enemies are **echoes**: roster heroes at the stage's level and stars, with HP/ATK/DEF at 75% x
the stage's `pw` (echo strength). Each chapter's echoes come from one faction (chapter 1
Celestial, 2 Infernal, 3 Fallen) with a few guests, so counter-picking pays (+20%); each stage's
`hint` says which faction to bring.

`lv`, `pw` and `rec` per stage (the `level`, `strength_bp` and `recommended_power` fields in
`data/stages.json`) are produced by `tests/tools/calibrate_stages.gd`:

1. Four pacing bots with different summon luck replay the target timeline (`TIMELINE_H`),
   clearing each stage at its hour; just before that, each bot's formation is recorded.
2. Enemy level `lv` = the bots' level at that hour (never lower than the previous stage), so
   "Lv 41 enemies" really meet a level 41 team.
3. `pw` = the largest echo strength at which at least 3 of the 4 recorded teams win >= 75% of
   seeded battles with wins averaging <= 55 s (so nobody at the threshold loses to the 90 s
   timer while winning), then -5% so a less efficient player is not stuck for long.
4. `rec` (recommended power, as `Game.team_power()` shows it, gear included) = the second
   weakest bot's power at that hour; it never drops.
5. Stages 1-1..1-3 instead: the three starter Rares at level 1 win >= 90% of seeds in <= 30 s.
6. The other first-session stages use every bot's team at a lower level (1-4 at L6, 1-5 at L8:
   a new player may not spend all the starting EXP), and all four teams must win, so the
   first wall never depends on summon luck. The 1-5 boss is a long fight more than a hard one
   (the 55 s rule caps its strength).

| Stage | Name | Boss | Enemy lv / stars | pw | Target hour | Recommended power | First clear gold / EXP | Extra first-clear rewards |
|---|---|---|---|---|---|---|---|---|
| 1-1 | Broken Narthex | - | 1 / 1 | 14000 | 0 | 1,322 | 500 / 300 | - |
| 1-2 | Hall of Fallen Bells | - | 2 / 1 | 10750 | 0 | 1,322 | 650 / 390 | T1 weapon |
| 1-3 | Glass Garden | - | 3 / 1 | 10250 | 0 | 1,322 | 800 / 480 | 100 gems |
| 1-4 | Pillar Walk | - | 6 / 1 | 17250 | 0 | 3,477 | 950 / 570 | - |
| 1-5 | The Gate Warden | Cassiel | 8 / 2 | 11250 | 0 | 3,837 | 1,100 / 660 | 200 gems, 50 dust, T1 weapon |
| 1-6 | Ashen Cloister | - | 15 / 2 | 14000 | 4 | 5,309 | 1,250 / 750 | - |
| 1-7 | Reliquary Stair | - | 16 / 2 | 12000 | 4 | 5,385 | 1,400 / 840 | T1 charm |
| 1-8 | Choir Loft | - | 18 / 2 | 14250 | 10 | 6,452 | 1,550 / 930 | 1 scroll |
| 1-9 | Bell Tower Ruin | - | 19 / 2 | 13500 | 10 | 6,531 | 1,700 / 1,020 | - |
| 1-10 | The Choir Unsung | Seraphiel | 20 / 2 | 10000 | 14 | 6,968 | 1,850 / 1,110 | 400 gems, 2 scrolls, 50 dust, T3 charm |
| 2-1 | Cinder Road | - | 24 / 2 | 11750 | 24 | 8,382 | 2,000 / 1,200 | - |
| 2-2 | Sulfur Springs | - | 26 / 2 | 11500 | 28 | 8,801 | 2,150 / 1,290 | T2 armor |
| 2-3 | Molten Ford | - | 28 / 2 | 13500 | 34 | 9,608 | 2,300 / 1,380 | 100 gems |
| 2-4 | Chainworks | - | 29 / 2 | 12750 | 38 | 10,014 | 2,450 / 1,470 | - |
| 2-5 | Brimstone Bulwark | Brakka | 32 / 2 | 9500 | 48 | 11,308 | 2,600 / 1,560 | 200 gems, 75 dust, T3 weapon |
| 2-6 | Ashfall Market | - | 34 / 3 | 13750 | 52 | 11,828 | 2,750 / 1,650 | - |
| 2-7 | Lantern Bazaar | - | 35 / 3 | 12250 | 58 | 12,230 | 2,900 / 1,740 | T3 weapon |
| 2-8 | Obsidian Steps | - | 36 / 3 | 12500 | 62 | 12,568 | 3,050 / 1,830 | 1 scroll |
| 2-9 | Furnace Gate | - | 39 / 3 | 12750 | 72 | 13,413 | 3,200 / 1,920 | - |
| 2-10 | Throne of the Ninth Furnace | Mordessa | 41 / 3 | 11500 | 82 | 14,664 | 3,350 / 2,010 | 400 gems, 2 scrolls, 75 dust, T4 charm |
| 3-1 | Dusk Shore | - | 44 / 3 | 13750 | 96 | 15,963 | 3,500 / 2,100 | - |
| 3-2 | Chapel of Ghosts | - | 46 / 3 | 12250 | 106 | 16,745 | 3,650 / 2,190 | T4 helm |
| 3-3 | Broken Oath Bridge | - | 49 / 3 | 14500 | 120 | 18,267 | 3,800 / 2,280 | 100 gems |
| 3-4 | Hollow Choir | - | 50 / 3 | 14250 | 130 | 19,115 | 3,950 / 2,370 | - |
| 3-5 | The Chained Gate | Orrin | 53 / 3 | 12500 | 144 | 20,134 | 4,100 / 2,460 | 200 gems, 100 dust, T4 weapon |
| 3-6 | Ash Witch's Hollow | - | 55 / 4 | 13500 | 158 | 20,911 | 4,250 / 2,550 | - |
| 3-7 | Mirror Lake | - | 57 / 4 | 13000 | 168 | 21,358 | 4,400 / 2,640 | T4 armor |
| 3-8 | Feather Graveyard | - | 59 / 4 | 13000 | 182 | 23,095 | 4,550 / 2,730 | 1 scroll |
| 3-9 | Eclipse Stair | - | 61 / 4 | 12500 | 196 | 24,522 | 4,700 / 2,820 | - |
| 3-10 | The Last Order | Noctaire | 64 / 4 | 11750 | 216 | 26,514 | 4,850 / 2,910 | 400 gems, 2 scrolls, 100 dust, T5 charm |

First-clear gold = 500 + 150 x index, EXP = 300 + 90 x index (index 0-29). Gems on every x-3
(100) and boss (200 / 400), scrolls on x-8 and x-10, dust on bosses, gear on x-2, x-5, x-7, x-10
(tier = `1 + cleared / 7`, the x-10 charm one tier higher). Replays pay nothing (they still
count for "Win 3 battles"), so the campaign cannot be farmed; idle is the steady income.

## 6. Idle rewards

Per hour, with `c` = stages cleared (`EconomyData.idle_per_hour`, base + per-10-stages x c / 10):

| Currency | Per hour | c = 0 | c = 10 | c = 20 | c = 30 |
|---|---|---|---|---|---|
| gold | 600 + 110c | 600 | 1,700 | 2,800 | 3,900 |
| hero_exp | 400 + 75c | 400 | 1,150 | 1,900 | 2,650 |
| dust | 3 + c/2 | 3 | 8 | 13 | 18 |
| gems | 3 + c/5 | 3 | 5 | 7 | 9 |
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
does not reroll a summon. New heroes join a formation that still has empty slots (the team is
re-arranged so a new guardian takes the front row); a full formation is never changed.

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

`Game.offers()` marks paid offers `test_purchase: true`; the shop labels them "Test purchase:
no charge". The starter pack's 30k EXP is about a day of chapter-2 idle EXP.

## 10. Free-player income

Per day around chapter 2 (c = 15): quests 290 gems + 1 scroll, daily gift 30 gems, idle gems
~6/h x 24 h = 144 -> about **460 gems + 1 scroll = ~2.5 pulls a day**, ~75 pulls a month (plus
700 gems and 3 scrolls per chapter from first clears). That is ~2 Legendaries a month. The
pacing bots own 9 heroes after the first session and 12 by day 4. The monthly card adds ~3,300
gems (11 pulls) a month.

## 11. Save, launch flags

- JSON at `Game.save_path` (`user://save.json`), written atomically (temp file + rename) about
  1.5 s after a change, and on app pause / focus out / close / exit. `version` plus a
  defaults-merge fills keys missing from older saves; bad values are repaired (unknown heroes
  and gear dropped, ids coerced to strings, battle speed and progress clamped, an empty
  roster gets the starters back). A save that is not valid JSON is copied to
  `save.corrupt-<ms>.json` and replaced by a new game.
- `--fresh`: brand-new game in `user://test_save.json` (deleted first). `--rich`: same test
  path, every hero at varied levels/stars, 50,000 gems, 500,000 gold, 300,000 EXP, 30 scrolls,
  2,000 dust, 12 stages cleared, 10 gear items (some equipped), quest progress, idle last
  claimed 5 h ago. Neither touches the real save.

## 12. Tuning tools

    tools/gd --headless --path . -s tests/tools/calibrate_stages.gd [-- stages=3-29 seeds=12]
    tools/gd --headless --path . -s tests/tools/playthrough.gd [-- days=10 bots=4]
    tools/gd --headless --path . -s tests/tools/playthrough_report.gd [-- stages=10]
    tools/gd --headless --path . -s tests/tools/balance_report.gd [-- seeds=8 stages=0-29]
    tools/gd --headless --path . -s tests/tools/inspect_battle.gd -- stage=9 plv=16 seed=1
    tools/gd --headless --path . -s tests/tools/bench_sim.gd

- **calibrate_stages**: re-solves `lv`, `pw` and `rec` after changing kits, enemy teams,
  battle rules or the economy. Run it with `write` to update `data/stages.json`, then
  regenerate the golden fixtures with `tests/tools/make_fixtures.gd` (keep 1-1 gentle).
- **playthrough**: checks the result against the timeline with freely playing bots.
- **playthrough_report**: what the new-player bot of `test_playthrough.gd` does per summon
  luck (tries and sessions per stage, hours to clear chapter 1).
- **balance_report**: for every stage, the lowest uniform level at which several fixed team
  profiles (no gear) win 70%.
- **inspect_battle**: per-unit damage, healing, ultimates and deaths for one battle.

Unit tests (`tests/unit/test_balance.gd`) guard the key promises: L1 starters win 1-1..1-3
(>= 18/20 seeds) and lose 1-4, unupgraded starters lose 1-10, the `--rich` state wins 1-10,
three starters at L12 lose 1-6, enemy levels and recommended power never drop, and a pacing
bot clears about chapter 1 on day 1 without finishing chapter 2 on day 2.
`tests/unit/test_playthrough.gd` plays a fresh game through the Game API like a reasonable new
player (summons with what it has, Auto-fill, levels up, retries, waits when stuck) and checks
that the starters win 1-1, 1-1..1-3 fall at the first try, the first session clears at least
1-4 but not the whole chapter, no chapter 1 stage blocks for more than three check-ins, and
chapter 1 is done within two days (three for a player who never spends gems on summons).

Idle gear: each idle gear drop rolls its own slot, so a long claim brings mixed pieces.
