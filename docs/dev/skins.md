# Skins (v1 design, 2026-10-17)

The owner: "I want you to make a bunch of skins as well that the players can purchase, like
bikinis and whatever." This is the design. Nothing is built yet (see "Game work" at the end).

## What a skin is

- An alternate look for one hero: a new painted full-body image with its own face variants
  (blink, talk, smile) and its own HaloRig. It shows everywhere the hero shows: Lobby, hero
  detail, team, battle, summon reveal.
- **Cosmetic only.** No stats. That keeps the game fair and keeps skins out of App Store
  pay-to-win complaints.
- Same hard lines as the base designs (`docs/dev/character-briefs.md`): adults only, no visible
  nipples or areolae, no genitals or pubic area, no sex poses, clear or sheer only over opaque,
  full body standing. Swimwear does not change that: cups cover with margin, bottoms are opaque in
  front, wet looks keep the clothing opaque. No school-coded looks (no school swimsuits).
- Same Aero Y2K style: glossy, chrome, holographic, cool, never cute.

## Skin lines (collections)

| Line | Look | When |
|---|---|---|
| **Aqua Resort** | Swimwear in Frutiger Aero water: micro bikinis, high-cut plunging one-pieces, chrome shades, wet-look hair, pearl and chrome jewelry | Launch line: one per hero |
| **Bunny Lounge** | Hell's casino: glossy latex or holographic vinyl bunny leotards (highleg, opaque), fishnet tights (legwear only), cuffs, collar, ears | Launch, rotating |
| **Club Chrome** | Night out: latex micro dresses over opaque shorts, mesh over opaque, rhinestone body chains, platform heels | Rotating |
| **After Hours** | Opaque satin and latex lingerie sets, garters, robes slipping off the shoulders | Rotating, premium |
| **Pop Idol** | Y2K stage and race-queen outfits: metallic crop tops, micro shorts, headset mics, holographic boots | Rotating |
| **Events** | Valentine (red latex), Halloween (angels dressed as demons and the reverse), Winter (fur-trimmed red micro bikini), Summer (more Aqua Resort) | Limited time |

## Packs (v2, 2026-10-17: 60 skins, four packs x all 15 heroes)

The owner: "come up with different skin packs for all the characters that's consistent ... a bikini one, like a
pool one for all of them. And then make another one that's even more, like, erotic." Every pack covers every
hero, so a pack reads as one collection. The catalogue (names, descriptions, tiers) is `data/skins.json`; the art
prompts are the `skins` block of `data/art_prompts.json` (Aqua Resort and After Dark so far).

| Pack | Look | Tier |
|---|---|---|
| **Aqua Resort** | Pool and bikini: micro bikinis and plunging one-pieces, wet skin, chrome shades | Standard (Legendaries Deluxe) |
| **Bunny Lounge** | Hell's casino: glossy latex and holographic bunny leotards, fishnets | Standard (Legendaries Deluxe) |
| **Club Chrome** | A night out: latex micro dresses over opaque layers, rhinestones, platforms | Standard (Legendaries Deluxe) |
| **After Dark** | The most daring: topless, covered by hands, hair or an arm; opaque bottoms; never visible nipples | Deluxe |

After Dark is for the sideloaded build (Apple guideline 1.1.4 makes it an App Store rejection risk). There is no
nude set: Claude declined it (2026-10-17). Every skin follows the hard lines in `docs/dev/character-briefs.md`.

## Adult set (EroLabs, 2026-10-18)

The owner asked for a fully nude version of the skins for an EroLabs build ("a version of this game
for erolabs to monetise and catch a different audience"; allowed in CLAUDE.md, "Allowed if
explicitly stated"). It is an opt-in mode of the ComfyUI pipeline, not a guardrail bypass:

- `data/art_prompts.json` `content_rules_adult` gates the `--adult` mode: nudity terms are allowed
  in the positive and no longer required in the negative; sex acts (nude pinups, no porn) and every
  childlike term stay forbidden and required-negative. Adult cues relaxed on the owner's word
  (2026-10-18, "the adult cues are making them all look 30+ and slightly fat"): the subject line is
  `1girl, solo, adult`, the gendered `mature female` cue is gone, the family rating tag is `nsfw`.
- All 60 skins have an `adult` block: nude outfit + the pack's kept items (bunny ears, cuffs,
  collars, gloves, veils, belts, footwear; hero identity, pose and props unchanged).
- Same flow as tame art, same settings: `run_hero.py --skin <id> --adult` (work in
  `art_src/<id>/skins/<art>/adult/`, seeds +5000), then `finalize.py --adult`, `variants.py --adult`,
  `fix.py --adult`, `install.py --adult` (into `assets/art/heroes/<id>/skins/<art>/adult/`).
- **In the game: a toggle, one build (owner, 2026-10-19: "implement these skins into the game now
  with a toggle. in the settings you should be able to press 'toggle nudity'").** Settings >
  Adult content > "Toggle nudity" (off by default; turning it on asks "I'm 18+") sets the
  `nudity` setting; Game syncs it to `HeroArt.nudity`, and every skin with adult art then shows
  `skins/<art>/adult/<art>.*` (sprite, portraits, thumbnails, try-on); skins without it keep
  their normal art. Rig ids `<hero>@<art>@adult` (`art_warp_build.py`, `art_quick_rig.py`),
  RigData art `<art>/adult`. `--nudity` with `--rich`/`--fresh` turns it on in the throwaway save
  (screenshots). The separate EroLabs build swap and the `.gdignore` are gone.
- **Game work, 2026-10-19 (owner: "when I change the skins, the character card doesn't change in
  the heroes section"; "I expect every character in the game now becomes nude ... it should be
  obvious that that's happened"):**
  - Every place that shows one of the player's heroes wears her equipped skin: Heroes cards, Team,
    Gear, reward tiles, the top-bar avatar, Lobby hero and banners, hero detail, battle portraits,
    sprites and the ultimate cut-in, battle results, the shop wardrobe. `Kit.hero_card`,
    `portrait_card`, `avatar` and `banner_card` default to `Kit.hero_look(id)` (the equipped skin);
    enemies (campaign and Spire echoes, chapter bosses) pass `skin: ""` and keep the base look.
  - `Kit.art_crop(id, aspect, zoom, skin)` caches by `HeroArt.art_key(id, skin)` (hero + the art
    actually shown), so a new skin or the nudity toggle gives a new crop at once; the avatar, Lobby
    and hero detail sprite rebuild when that key changes (screens refresh on `Game.changed`).
  - Nude base looks: `assets/art/heroes/<id>/adult/<id>.*` (what `install.py --adult` writes for a
    base look), RigData art `"/adult"`, rig id `<id>@@adult` (`docs/dev/halorig.md` 8.1). With
    nudity on every look, enemies included, shows its nude art where it is built and its normal art
    otherwise. None is rendered yet, so base looks fall back to the normal art.
  - Splash cards (`SplashCard`): with nudity on each file is read from
    `assets/art/splash/<name>/adult/` when it is there (same names, its own `layout.json`
    optional), else from the card's folder. There is no boot or loading screen with hero art yet.
  - Settings: turning nudity on (after "I'm 18+") or off shows a big notice over everything, "NUDITY
    MODE ENABLED" / "NUDITY MODE DISABLED", and the row shows the state and how much nude art the
    build has (skins with adult art, base looks with adult art).
- Installed 2026-10-19: all 60. OpenCode's finals run (`art_src/_review/adult_finals.log`, picks
  by framing flags in `art_src/_review/adult_picks.json`) finished 44 with the face pass and tiled
  2x; ComfyUI went down for the last 14, which Claude cut out quick (no face pass or 2x). Two
  cropped picks were swapped for full-body seeds: seraphiel_diva_night s110001, kessa_cat_nap
  s212000. Claude reviewed all 60 (adult women, standing pinups, no sex acts, clean cutouts).
  Quick rigs (face boxes from face_yolov8m), no blinks or springs.
- The repo is public, so the nude art is too (the owner's call, 2026-10-19: "just make it public
  i'll be fine", after being told GitHub's rules do not allow sexually explicit content and a
  takedown would also stop the free iOS builds).

## Pricing (proposal for the owner)

For scale: 330 gems cost $4.99 in the shop and one summon costs 300 gems.

| Tier | What | Price |
|---|---|---|
| Standard | New art, face variants, rig | 980 gems (about $15) |
| Deluxe | Standard + its own idle animation, ultimate effect color and Lobby lines | 1,480 gems (about $22) |
| Bundles | A whole line for one faction, or a hero's skin with summon scrolls | direct purchase, $9.99 to $29.99 |

Real-money items go through App Store in-app purchase once the game is signed; until then the
shop's test purchases cover them.

## Production

Each skin is one art job, the same as a hero: candidates, a pick, a final with the tiled
repaint, three face variants, a 1:1 review, install, rig. Same model and settings as the base art
(`docs/dev/status.md`); long runs wait for the owner's go-ahead. Every ComfyUI tool takes
`--skin <skin id>` (the full id like `kessa_card_shark`, or the short `card_shark`):

```bash
python tools/comfy/run_hero.py kessa --skin card_shark --count 3 --size 896x1152   # candidates
python tools/comfy/finalize.py kessa 208001 --skin card_shark    # face pass + tiled 2x repaint + cutout
python tools/comfy/variants.py kessa --skin card_shark           # blink, talk, smile
python tools/comfy/install.py kessa --skin card_shark            # after the 1:1 review
python tools/art_warp_build.py kessa@card_shark --regen-masks    # rig (tools/art_warp on Linux)
```

Work files live in `art_src/<hero>/skins/<art>/` (`candidates/`, `final/<art>.png`, `variants/`,
`masks/`); `install.py` checks the skin against `data/skins.json` and copies into
`assets/art/heroes/<hero>/skins/<art>/` with the hand-off in `art_src/_handoff/<hero>@<art>.json`.
The rig source `<art>.warp_src.json` in that folder is written by hand like a hero's (a new pose
needs its own pivots and region polygons; start from the hero's). Once `<art>.warp.json` exists the
game shows the skin instead of "Coming soon". `finalize.py` refuses a skin candidate without
`--skin` (and the reverse), and `run_hero.py --force` never re-renders a skin final's master seed.

### Quick install (no upscale), how the 60 skins went in on 2026-10-18

For a skin that should be in the game before its finishing passes (the owner: "put a pin in the
upscaling ... just put them into the game"):

```bash
python tools/comfy/finalize.py kessa 208000 --skin card_shark --no-face-refine --upscale off   # cutout only
python tools/comfy/install.py kessa --skin card_shark --partial          # no face variants yet
python tools/art_quick_rig.py kessa@card_shark --face x,y,w,h --seed 208000   # or --faces faces.json
python tools/art_warp_build.py kessa@card_shark --regen-masks
tools/gd --headless --path . --import
```

The face box is in pixels of the installed 1024x2048 image (`finalize.py`'s own estimate often lands on
a halo or hat; the 60 were placed with the `face_yolov8m.pt` detector from the ComfyUI models folder).
The quick rig moves the body, chest and head; it has no blinks, talking or spring parts. The later
upscale pass re-runs `finalize.py --force` with the defaults, then `variants.py`, `install.py --force`
and a hand-made rig.

## Game work (built 2026-10-17)

- `data/skins.json` (all 30 launch skins; tiers and lines) and `src/data/skins.gd` (`SkinData`).
  Tiers as built: the six skins of the three Legendaries (Seraphiel, Mordessa, Noctaire) are Deluxe,
  the rest Standard.
- Save data `skins {owned, equipped}`; `GameModel.buy_skin` / `equip_skin` / `skins_for`, cleaned
  by `migrate` (`docs/dev/unity-port.md` section 9).
- Art: `assets/art/heroes/<hero>/skins/<art>/` laid out like the base art (`<art>.warp.json`,
  `<art>.png`, `<art>_portrait.png`, `overlays/`). `HeroArt` takes an optional skin id and falls
  back to the base look until the skin's rig is built; `RigData.load_rig(hero, art)`.
- Shop: a "Wardrobe" tab (one card per hero: Buy for gems with a confirm, Wear, Equipped, or
  Coming soon while the art is not built). Hero page: a "Skins" side tab (base look plus her
  skins). The Lobby sprite, the hero page and the player's units in battle wear the equipped
  skin; enemies (campaign echoes) keep the base look.
- Tests: `tests/unit/test_skins.gd` (data, buy, equip, save round trip, migrate, art fallback).
- Installed art (2026-10-18): all 60, quick install (above). Wardrobe rows and the hero Skins tab show
  each skin's portrait; the hero page has "Try on" (`params.preview` opens it trying one on).
- Not yet: the upscale pass and face variants, the equipped skin on portrait cards and the summon
  reveal, and skin bundles for real money.
