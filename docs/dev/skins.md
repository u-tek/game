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
repaint, three face variants, a 1:1 review, install, rig. The launch set is 30 jobs. The model
and settings come from the owner's checkpoint tests; the GPU time per skin is quoted once they
are chosen, and long runs wait for the owner's go-ahead.

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
- Not yet: skin art (the art jobs above), the equipped skin on portrait cards and the summon
  reveal, and skin bundles for real money.
