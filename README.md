# Halo & Horn

A mobile idle/AFK gacha RPG close to the reference game: collect angels, demons and the fallen
caught between them, build a five-hero team, push through the campaign, and keep earning rewards
while you're away.

**v1 is playable.** It is a **Godot 4.5.1** project (GDScript, Mobile renderer, portrait) that
ships as a native iOS app. Content and rules are kept engine-neutral (JSON data, plain rule
classes, golden fixtures) so a later Unity port can reproduce them exactly.

What's in v1: 40 heroes in three factions, a 60-stage campaign (6 chapters of 10 stages, one
world each, bosses at 5 and 10), the Spire (a 120-floor climb beside the campaign), an auto
battler with manual ultimates and 1x/2x/4x speed, idle rewards with quick claims, summoning with
pity and a free daily pull, levels, stars and gear, skins, the Rival and Misprints, daily quests,
a shop of free test purchases, a profile, settings, and light first-session guidance (a pulsing
ring and arrow on the next suggested tap until chapter 1 is cleared).

## Run the game

Install [Godot 4.5.1](https://godotengine.org/download/archive/4.5.1-stable/) (standard build,
not .NET), then either open the folder in the editor and press Play, or:

```bash
godot --path .                       # play with your normal save (user://save.json)
godot --path . -- --fresh            # throwaway save, brand-new game
godot --path . -- --rich             # throwaway save with every hero and lots of currency
```

The window opens at phone proportions (720x1280 canvas). Settings has dev tools (+gems, +gold,
+EXP, skip 8 hours) and Reset Save.

**On an iPhone:** the **iOS build** GitHub workflow exports the Xcode project, builds an
unsigned IPA and uploads it as an artifact for sideloading. See
[docs/dev/ios-build.md](docs/dev/ios-build.md).

## Tests

```bash
tools/check            # import + unit tests + headless boot (about 20 s); exit 1 on any problem
tools/check tests      # import + unit tests only
tools/check e2e        # everything above plus the screen end-to-end scripts (about 2 min)
```

- Unit tests live in `tests/unit/test_*.gd` (battle, summon, idle, progression, save repair,
  golden fixtures, balance, and `test_playthrough.gd`: a bot plays a fresh game through the
  Game API and checks nobody is hard-stuck in chapter 1). Run one file or test with
  `tools/gd --headless --path . -s tests/run_tests.gd -- test_playthrough`.
- End-to-end scripts drive the real main scene: `tests/tools/battle_screen_e2e.gd`,
  `meta_screens_e2e.gd` and `first_session_e2e.gd` (follows the guide arrows from a fresh save:
  claim, summon, formation, battle 1-1, level up, quests). Run one with
  `tools/gd --headless --path . -s tests/tools/first_session_e2e.gd -- --fresh`.
- Balance tools (`playthrough.gd`, `playthrough_report.gd`, `calibrate_stages.gd`,
  `balance_report.gd`) are described in [docs/dev/economy-v1.md](docs/dev/economy-v1.md).

`tools/gd` runs Godot under a shared lock (several agents may work at once). After adding a
script with a `class_name` or new assets, run `tools/gd --headless --path . --import`.
Godot keeps running after script errors, so always scan output for `SCRIPT ERROR`,
`Parse Error` and `ERROR:`.

## Screenshots

```bash
tools/shoot home                                  # -> screenshots/home.png (720x1560)
tools/shoot campaign --res 720x1280 --fresh --safe-area-sim --shoot-params='{"open_stage":0}'
tools/shoot hero_detail --rich --shoot-params='{"hero_id":"seraphiel"}' --out screenshots/hd.png
```

Screens: `home` (the Lobby), `campaign`, `tower` (the Spire), `battle`, `heroes`, `hero_detail`,
`formation` (Team), `summon`, `gear`, `quests`, `shop`, `settings`, `profile`, `prints`
(Misprints), `rival`, plus the debug-only `lobby_v5` (the approved poster mockup).
Flags: `--fresh` / `--rich` (throwaway saves), `--safe-area-sim` (iPhone notch: 108 px top,
62 px bottom), `--shoot-params=<json>` (screen params, e.g. `{"stage_index":0}` for battle,
`{"pull":10,"skip":true}` or `{"rates":true}` for summon, `{"hero_id":"seraphiel"}` or
`{"show":"weapon"}` for hero_detail, `{"tab":1}` for heroes (Codex) and shop (Gems),
`{"open":"first"}` for gear, `{"sheet":true}` for home (the Sanctum sheet),
`{"open_stage":4,"intro":false}` for campaign, `{"scroll":800}`), `--shoot-wait=<seconds>`.
It needs `xvfb-run` on a headless Linux box. The `screenshots/` folder is git-ignored. The
current UI style (v4 "Signal": the poster look of every screen, the kit, the screen map) is in
[docs/dev/ui-style-v4.md](docs/dev/ui-style-v4.md).

For a step-by-step picture story of the first session, run the first-session walk rendered:

```bash
flock /tmp/halo-godot.lock xvfb-run -a -s "-screen 0 1800x2400x24" godot --path . \
  --rendering-driver opengl3 --resolution 720x1560 -s tests/tools/first_session_e2e.gd \
  -- --fresh --safe-area-sim --shots=$PWD/screenshots/flow
```

## Where things are

| Path | What |
|---|---|
| `src/core/` | Rules and state (`GameModel`, battle sim, RNG, stat formulas); `game.gd` is the `Game` autoload |
| `src/data/`, `data/*.json` | Content and tuning (heroes, kits, stages, economy, banner, quests, offers) |
| `src/ui/` | `UI` autoload (navigation, toasts, popups, sound), `Kit` widgets, theme, screens |
| `src/art/`, `assets/art/` | HeroArt API and the HaloRig animation runtime; painted hero art, skins, chapter backdrops (`assets/art/backgrounds/`; `src/ui/battle/scene_backdrop.gd` paints a fallback in code), UI icons and objects |
| `tests/` | Unit tests, golden fixtures checks, e2e scripts and balance tools |
| `tools/` | `check`, `shoot`, `gd`, art pipeline scripts |

## Developer docs

| Doc | What's in it |
|---|---|
| [Status](docs/dev/status.md) | Start here: where things stand, open owner decisions, known issues, next steps |
| [Architecture](docs/dev/architecture.md) | The build contract: APIs, data shapes, folder ownership, art rules |
| [UI style v4](docs/dev/ui-style-v4.md) | The current look ("Signal", the poster style): the brief, the screen map and the kit |
| [UI style v2](docs/dev/ui-style-v2.md) | Historical: the v2 layouts that v3 and v4 replaced |
| [Economy v1](docs/dev/economy-v1.md) | Formulas, pacing timeline, stage and kit tables, tuning tools |
| [Unity port](docs/dev/unity-port.md) | Module map, JSON fields, RNG, battle tick order, save format, fixtures |
| [HaloRig](docs/dev/halorig.md) | The warp-rig animation system for painted heroes |
| [Art farm](docs/dev/art-farm.md) | How the first 15 heroes' art was made: AI rendering on GitHub Actions, exposure filter, each hero's run and seed |
| [Art generation](docs/dev/art-generation.md), [ComfyUI setup](docs/dev/comfyui-setup.md) | The ComfyUI pipeline on the owner's GPU PC (current settings in [Status](docs/dev/status.md)) and the prompt bible |
| [Skins](docs/dev/skins.md) | The four skin packs for all 40 heroes and how skin art is installed |
| [Art style](docs/dev/art-style.md), [Character briefs](docs/dev/character-briefs.md) | Art direction and per-hero designs |
| [iOS build](docs/dev/ios-build.md) | Building and sideloading the IPA |

## Planning docs

| Doc | What's in it |
|---|---|
| [Vision](docs/vision.md) | Pitch, pillars, target players, and how we differ from the reference game |
| [Game design](docs/game-design.md) | Core loop and every system, tagged Slice / Launch / Later |
| [Tech plan](docs/tech-plan.md) | Historical (written when Unity was the engine): backend, data pipeline, rules that keep the economy safe |
| [Roadmap](docs/roadmap.md) | Historical (written for a Unity team): phases to global launch, exit criteria, team roles |
| [Open questions](docs/open-questions.md) | Decisions made, decisions pending, risks, legal notes |
| [Reference game](docs/reference-idle-angels.md) | How the reference game works, what its players praise and criticize, with sources |
