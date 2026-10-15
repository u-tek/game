# Porting Halo & Horn to Unity (plan)

Status: **plan**. The game is built in Godot 4.5 so it can ship to iOS today. It's
structured so a later Unity (C#) version can reuse everything except engine glue and UI, and
can be verified against the Godot version.

## What carries over

| Asset | Godot location | In Unity |
|---|---|---|
| Game content (heroes, skills, stages, economy, banner, quests, offers) | `data/*.json` | Load the same JSON into C# data classes / ScriptableObjects (Newtonsoft JSON) |
| Hero and background art | `assets/art/**/*.svg` (source) + PNG exports | Import the PNGs (or re-export at any size from SVG); Unity's Vector Graphics package can read the SVGs directly |
| UI icons | `assets/art/ui/*.svg` | Same as above |
| Fonts | `assets/fonts/*.ttf` (OFL) | Import as TextMeshPro font assets |
| Save files | `user://save.json` (versioned JSON) | Same format, so players could keep progress |
| Rules spec + golden fixtures | `docs/dev/economy-v1.md`, `data/fixtures/*.json` | The C# port must pass the same fixtures |

## What gets rewritten (1:1 module map)

Rules live in plain classes with integer math and our own RNG, so a C# port is a
mechanical translation, verified by fixtures.

| Godot (GDScript) | Unity (C#) | Notes |
|---|---|---|
| `src/core/rng.gd` | `Core/Rng.cs` | Same algorithm and 32-bit masking, so identical sequences |
| `src/core/battle_sim.gd` | `Core/BattleSim.cs` | Pure class; same tick (100 ms), events, ordering |
| `src/core/*` economy/progression/summon/idle helpers | `Core/*.cs` | Pure classes |
| `src/core/game.gd` (autoload) | `GameService` MonoBehaviour singleton | Thin adapter: time, persistence, events |
| `src/data/*.gd` JSON loaders | `Data/*.cs` loaders | |
| `src/ui/**` | Unity UI (uGUI) screens | Rebuilt; screenshots in `screenshots/` are the reference |
| `src/art/hero_sprite.gd` | `HeroSprite` MonoBehaviour | Animation parameters documented in `docs/dev/art-style.md` |

## Port procedure (when the time comes)

1. Create the Unity project (URP 2D, portrait). Copy `data/`, PNG art exports and fonts.
2. Port `Core` classes one by one; run the fixture tests (NUnit) after each until identical.
3. Port `game.gd` as the service layer; reuse the save format.
4. Rebuild screens in uGUI against the screenshots and `docs/game-design.md`.
5. Swap placeholder vector art for painted art and Spine animation (see `docs/art-plan.md`).

## Alternative

Godot also supports C#. Rewriting `src/core` in C# inside Godot would let the same `.cs`
files drop into Unity almost unchanged. It wasn't done for v1 because Godot's C# iOS export is
still experimental, but it's a reasonable intermediate step before a full port.
