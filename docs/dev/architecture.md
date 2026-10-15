# Halo & Horn: Architecture and Build Contract (v1)

This is the shared contract for everyone (human or agent) building the game. Read it fully
before changing code. **Godot 4.5.1, GDScript, GL Compatibility renderer, portrait.**

## 1. Run, test, screenshot

```bash
godot --headless --path . --import                      # after adding/changing assets or class_names
godot --headless --path . -s tests/run_tests.gd         # unit tests (exit 1 on failure)
godot --headless --path . --quit-after 120              # boot the game headless, watch for SCRIPT ERROR
# Rendered screenshot of a screen (phone-shaped viewport, simulated notch):
xvfb-run -a -s "-screen 0 1600x2000x24" godot --path . --rendering-driver opengl3 \
  --resolution 720x1560 -- --shoot=home --shoot-out=/home/user/game/screenshots/home.png
```

`--shoot` options (implemented in `src/ui/main.gd`): `--shoot=<screen>`,
`--shoot-out=<png path>`, `--shoot-params=<json>`, `--shoot-wait=<seconds, default 1.0>`,
`--fresh` (use a throwaway save with a new game), `--rich` (throwaway save with lots of
heroes/currency, for testing full screens), `--safe-area-sim` (simulate an iPhone notch:
108 px top, 62 px bottom inset). Use Read on the PNG to look at it.

**Always check the console for `SCRIPT ERROR` / `ERROR:` lines.** Godot keeps running after
script errors, so a "successful" run can still be broken.

## 2. Folder ownership

| Path | Owner | Notes |
|---|---|---|
| `src/core/**`, `src/data/**` (except identity fields in `heroes.gd`) | core logic | Rules, state, save, battle sim, data tables |
| `tests/**` | core logic (others may add tests) | `tests/unit/test_*.gd` |
| `src/ui/ui.gd`, `src/ui/main.gd`, `src/main.tscn`, `src/ui/kit.gd`, `src/ui/theme.gd`, `src/ui/components/**`, `assets/art/ui/**` | UI shell | Router, theme, shared widgets, icons |
| `src/ui/screens/home_screen.gd`, `campaign_screen.gd`, `battle_screen.gd`, `src/ui/battle/**` | screens A | Core loop screens |
| `src/ui/screens/heroes_screen.gd`, `hero_detail_screen.gd`, `formation_screen.gd`, `summon_screen.gd`, `quests_screen.gd`, `shop_screen.gd`, `settings_screen.gd` | screens B | Meta screens |
| `src/art/**`, `assets/art/heroes/**`, `assets/art/backgrounds/**`, `icon.svg`, `tools/art_*` | art | Hero/background art and the HeroArt API |
| `project.godot`, `export_presets.cfg`, `docs/dev/**` | lead | Ask in your report instead of editing |

Don't edit files you don't own; if you need a change there, put it in your final report.
Never `git commit`; the lead commits.

## 3. Code conventions

- GDScript with static types (`var x: int`, `-> Dictionary`). Tabs for indentation.
- Data crosses module boundaries as **Dictionaries with snake_case keys** (JSON-friendly).
- All game numbers are **ints** (percentages in basis points: 10000 = 100%).
- UI is built **in code** (Controls created in `_ready`/`setup`), using `src/ui/kit.gd`
  helpers so every screen looks consistent. No hand-written `.tscn` besides `main.tscn`.
- Randomness in rules uses a seeded RNG (`RandomNumberGenerator` with explicit seed, or
  `src/core/rng.gd`), never global `randi()`, so battles replay identically.

## 3b. Portability: the game may be ported to Unity (C#) later

Write code so a later Unity port can reuse the content and reproduce the rules exactly:

- **Content is data, in JSON** under `data/` (heroes, kits, stages, economy, banner, quests,
  offers), loaded by thin GDScript loaders. No game numbers hard-coded in UI code.
- **Rules are engine-agnostic.** Battle, gacha, economy, idle, progression and save logic
  live in plain `RefCounted` classes under `src/core/` that use no Nodes, scenes, signals,
  `Time`, `OS` or other engine services. `game.gd` (the autoload) is a thin adapter that
  passes in the current time and handles persistence/signals.
- **Integer math only** in rules, with explicit rounding (`floor` of integer division). No
  floats, so C# produces identical results.
- **Our own RNG** (`src/core/rng.gd`, a 32-bit PCG or xorshift on masked ints, documented
  algorithm), never Godot's `RandomNumberGenerator`/`randi()`.
- **Golden fixtures**: `data/fixtures/*.json` record inputs (seed, setup) and exact outputs
  (event logs, summon results, cost tables). Unit tests check them; a Unity port must too.
- **Art stays engine-neutral**: SVG sources plus PNG exports; animation described by
  parameters (durations, offsets), not engine-specific animation files.

See `docs/dev/unity-port.md` for the module-by-module port map.

## 4. Game API (autoload `Game`, `src/core/game.gd`)

The full list of method signatures lives in `src/core/game.gd`. Results of actions are
`{"ok": bool, "value": Variant, "error": String}`. `Game.changed` fires after every
change; screens refresh on it (disconnect on exit). `Game.notify(event)` carries one-shot
events like `{"type": "level_up", "hero_id": ...}`.

### Data shapes

**HeroDef** (`Game.hero_def(id)`): `id, name, title, faction ("celestial"|"infernal"|"fallen"),
role ("guardian"|"striker"|"caster"|"support"|"assassin"), rarity ("rare"|"epic"|"legendary"),
bio, look, base_stats {hp, atk, def, spd, crit}, ultimate {id, name, description, ...},
passives [{id, name, description, unlock_stars, ...}]`.

**Counter wheel:** celestial beats infernal, infernal beats fallen, fallen beats celestial
(+20% damage dealt to the beaten faction). **Faction bonus:** 3/4/5 allies of one faction
give +6%/+10%/+15% HP and ATK.

**Reward:** `{gold?, hero_exp?, gems?, scrolls?, dust?, shards?: {hero_id: n}, gear?: [uid], heroes?: [hero_id]}`

**Player state** (`Game.state`, read-only for UI): `version, created_at, player_name,
currencies {gold, hero_exp, gems, scrolls, dust}, heroes {id: {id, level, stars, shards, gear {slot: uid}}},
formation [5 ids or ""], campaign {cleared}, idle {last_claim_at, quick_claims_used, quick_claim_day},
summon {pity, total_pulls, last_free_pull_day}, gear [GearItem], quests {day, progress, claimed},
shop {purchases}, settings {sound, battle_speed (1|2|4), auto_ultimates}, counters {}, dev_time_offset`.

**GearItem:** `{uid, slot ("weapon"|"armor"|"helm"|"charm"), tier (1-5), name, stats {..}, equipped_by}`.

**Stage:** `{index, id ("1-5"), chapter, name, enemies [{hero_id, level, stars, slot, is_boss}],
recommended_power, first_clear_reward, is_boss}`. **Chapter:** `{index, id, name, intro, background}`.

### Battle

`BattleSim` (`src/core/battle_sim.gd`, `class_name BattleSim`, RefCounted):

```gdscript
var sim := BattleSim.new(Game.stage_battle_setup(i))  # setup = {allies: [...], enemies: [...], seed}
sim.units          # Array[Dictionary]: {uid, hero_id, side ("ally"|"enemy"), slot, max_hp, hp,
                   #   shield, energy (0..1000), alive, is_boss, statuses {name: remaining_ms}}
sim.step()         # advance one tick (100 ms of battle time); returns Array of events
sim.request_ultimate(uid) -> bool   # manual ult for an ally with full energy
sim.auto_ultimates = true           # allies fire ults automatically (enemies always do)
sim.is_over() -> bool
sim.outcome() -> Dictionary         # {winner, victory, duration_ms, allies_alive, damage_dealt {uid: n}}
sim.run_to_end() -> Dictionary      # for Skip
```

Unit setup: `{uid, hero_id, side, slot, level, stars, stats {hp, atk, def, spd, crit}, is_boss}`.
Slots 0-1 = front row, 2-4 = back row. Events (all have `t` = battle ms and `type`):
`attack {src, target}`, `damage {src, target, amount, crit, advantage, from_ultimate, hp_after, shield_after}`,
`heal {src, target, amount, hp_after}`, `shield {src, target, amount, shield_after}`,
`status {src, target, status, duration_ms}`, `ultimate {src, skill_id, skill_name, targets}`,
`energy {unit, energy}`, `death {unit}`, `end {winner}`.

The battle screen steps the sim in real time (`TICK_MS = 100`, scaled by battle speed),
animates events, and lets the player tap a portrait to fire a ready ultimate.

## 5. UI contract (autoload `UI`, `src/ui/ui.gd`)

```gdscript
UI.go("hero_detail", {"hero_id": "seraphiel"})   # navigate; screens get setup(params)
UI.back()                                        # previous screen
UI.toast("Not enough gold")
UI.show_reward("Stage cleared!", reward, on_closed)   # modal reward popup
UI.confirm("Spend 300 gems?", on_yes)            # in-game confirm dialog
UI.set_chrome(show_top_bar: bool, show_nav: bool)  # battle/summon hide chrome
UI.safe_top() / UI.safe_bottom() -> float         # insets in viewport px
```

Screens are `Control` scripts in `src/ui/screens/<name>_screen.gd` with
`func setup(params: Dictionary) -> void`. They fill the content area between the top bar
(currencies) and bottom nav (Home, Heroes, Summon, Quests, Shop). `src/ui/kit.gd`
(`class_name Kit`) provides styled builders: buttons (primary/secondary/danger), panels,
labels by role (title/body/number), currency chips, hero cards, rarity frames, progress
bars, faction/role badges, scroll lists. **Use them; don't hand-style.**

Touch targets ≥ 88 px tall (viewport is 720 px wide, so this is about 48 pt on a phone).

## 6. Art contract (`class_name HeroArt`, `src/art/hero_art.gd`)

```gdscript
HeroArt.texture(id) -> Texture2D             # full-body hero art
HeroArt.portrait_region(id) -> Rect2         # face crop inside texture(id)
HeroArt.make_sprite(id) -> Node2D            # animated battle sprite (HeroSprite)
HeroArt.make_portrait(id, size) -> Control   # square face portrait
HeroArt.background(kind) -> Texture2D        # "home", "summon", "chapter-1..3"
HeroArt.faction_color(faction) -> Color
```

HeroSprite methods: `play_idle()`, `play_attack(target_global_pos)`, `play_cast()`,
`play_hit()`, `play_death()`, `set_facing(dir: int)` (1 right/-1 left), `set_echo(bool)`
(enemy "echo" tint), `set_boss(bool)` (bigger + aura). Feet at the node origin.

### Hero SVG rules (Godot rasterizes SVGs with ThorVG at import)

- File: `assets/art/heroes/<id>.svg`, `viewBox="0 0 512 640"`, character centered, feet at
  y≈620, head (incl. hair) roughly inside x 110-402, y 40-330, so the shared portrait crop works.
- Optional wings layer `assets/art/heroes/<id>_wings.svg` (same viewBox, drawn behind body)
  so wings can flap in game.
- **Allowed:** path, circle, ellipse, rect, polygon, g, transform, fill/stroke, opacity,
  linearGradient, radialGradient, clipPath. **Not allowed:** filters (blur/glow), CSS
  `<style>`, text, images, masks, `mix-blend-mode`. Keep each file under ~40 KB.
- Style: chibi anime (head ≈ 40% of height), large expressive eyes with two highlights,
  clean dark outlines (#2a1d3d, not black, 4-6 px), cel shading (one shadow tone) plus soft
  gradient highlights, faction palette. Original designs only.

## 7. Visual direction: "Twilight cathedral"

Deep indigo night sky, gold-leaf filigree, stained-glass color. Dark UI, one look (no light theme).

| Token | Color | Use |
|---|---|---|
| bg | `#120e24` | app background |
| panel | `#1d1738` (90% alpha) | panels, cards |
| panel_hi | `#2a2150` | raised/hover |
| line | `#e8c36a` at 35% | hairline borders |
| ink | `#f3ecdf` | main text |
| ink_dim | `#a99fc4` | secondary text |
| gold | `#f2c14e` | primary accent, primary buttons, Celestial |
| ember | `#d9412b` | Infernal, danger |
| violet | `#8e6ce0` | Fallen |
| sky | `#6fc3e8` | info, Celestial secondary |
| rare / epic / legendary | `#4fa3e0` / `#b36bf0` / `#f5b83d` | rarity frames |
| good | `#5cd6a0` | success, HP |

Fonts (`assets/fonts`): **Marcellus SC** for titles, hero names, screen headers;
**Nunito** (Regular/Bold/ExtraBold/Black) for body, numbers and buttons. Sizes on the 720 px
canvas: 22 small, 26 body, 32 button, 40 header, 56 hero name.

## 8. v1 scope and numbers (starting points; core may tune)

- 15 heroes (see `src/data/heroes.gd`); start with 3 owned (one per faction): **uriela,
  kessa, lucen** (all Rare) plus 1,800 gems (6 pulls), 10 scrolls (one 10-pull) and one free daily pull.
- Campaign: 3 chapters × 10 stages; stages 5 and 10 of each chapter are bosses. Enemies
  are "echoes" of roster heroes.
- Idle: gold, hero EXP and a trickle of dust and gems per hour, scaling with stages cleared;
  12 h cap; 1 free quick claim (2 h) per day, then 50/100/150 gems.
- Summon: 300 gems or 1 scroll per pull; 10-pull 2,700 gems or 10 scrolls. Rates: Legendary
  2%, Epic 18%, Rare 80%; Legendary pity at 60; every 10-pull has an Epic or better.
  Duplicates: 10/20/40 shards (rare/epic/legendary... per tuning); excess to dust.
- Stars: Rare starts 1★, Epic 2★, Legendary 3★; max 6★. Level cap 20 + 20 × stars.
- Daily quests (claim idle, win 3 battles, summon once, level a hero, ...) → gems/scrolls.
- Shop: prototype offers (starter pack, monthly card, gem packs) are **free test purchases**,
  clearly labeled "Test purchase: no charge".
- Settings: sound toggle, battle speed, auto ultimates, reset save, dev tools (+gems,
  skip 8 h).
