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

## Launch set (30 skins: an Aqua Resort skin plus one more per hero)

| Hero | Aqua Resort | Second skin |
|---|---|---|
| Seraphiel | **Tidal Diva**: pearl micro bikini with chrome ring links, chrome body chains, mirrored shades pushed into wet platinum hair, chrome mic | **Encore Bunny** (Bunny Lounge): pearl latex bunny leotard, chrome cuffs and collar, white fishnets, aqua bow tie |
| Cassiel | **Lifeguard Unit**: white-and-aqua sport micro bikini with mecha plate accents, chrome whistle, frosted rescue-board shield | **Off Duty** (After Hours): white satin lingerie and garters, one pauldron hanging from her hip |
| Liora | **Pearl Lagoon**: high-cut aqua one-piece plunging to the navel, pearl straps, wet-look braid | **Lounge Singer** (Club Chrome): cream sequin micro dress slit to the hip over opaque shorts, long satin gloves, chrome mic |
| Uriela | **Surf Racer**: azure racing micro bikini with sun-sigil decals, shield visor, lance as a surf spear | **Podium Queen** (Pop Idol): glossy white vinyl race-queen crop top and micro skirt over opaque shorts, thigh boots, chrome parasol |
| Nuriel | **Jet Stream**: aqua chrome micro bikini, clear-vinyl rash jacket off the shoulders, shield visor | **Courier Bunny** (Bunny Lounge): white vinyl bunny leotard with aqua racing stripes, bunny-ear visor |
| Mordessa | **Lava Lounge**: black latex micro bikini, red chrome shades, fur-trimmed robe worn open, rhinestone crown | **High Roller** (Bunny Lounge): red latex bunny leotard, black fishnets, rhinestone crown between her horns |
| Brakka | **Pool Champ**: black-and-chrome micro bikini (it has to read against her red skin), championship belt, towel over her shoulders, chrome shades | **Velvet Rope** (Club Chrome): black latex bodysuit with SECURITY in chrome letters, chain harness |
| Vesper | **Red Tide**: crimson latex micro bikini with chrome heart rings, tinted glasses, open beach robe | **Late Session** (After Hours): black latex lingerie and garters, red-tinted glasses |
| Imra | **Fire Lagoon**: orange metallic bandeau bikini, chrome jewelry, a tiki-torch version of her staff | **Headliner** (Pop Idol): metallic red crop top, high-cut shorts, chrome headset mic, platform boots |
| Kessa | **Black Cat Beach**: black latex micro bikini with red O-rings, cat-ear sun visor | **Purr** (After Hours): red satin lingerie, chrome collar, cat-ear headphones |
| Noctaire | **Midnight Swim**: black micro bikini with an oil-slick wrap, cracked chrome halo | **Void Bunny** (Bunny Lounge): black latex bunny leotard, oil-slick ears, glitch-pattern fishnets |
| Orrin | **Riot Beach**: black-and-violet sport micro bikini, smoked shades, riot shield as a surfboard | **Off the Clock** (After Hours): black satin lingerie, her fiber-optic cables loose, armor jacket over the shoulders |
| Sable | **Holy Water**: black one-piece with a plunging keyhole, clear holographic veil, chrome cross | **Choir Night** (Club Chrome): violet latex micro dress over opaque shorts, holographic veil |
| Lucen | **Split Tide**: mismatched white and black micro bikini, half-and-half shades | **Two-Faced Bunny** (Bunny Lounge): split white/black latex bunny leotard, one white ear, one black |
| Ashra | **Lazy River**: violet micro bikini, holographic sun hat, a sleepy standing stretch | **Night Owl** (After Hours): oversized off-shoulder sweater over a tube top and opaque micro shorts, headphones |

Young-end heroes (Liora, Uriela, Imra) get the glam skins (resort, lounge singer, race queen,
headliner) and none of the lingerie line, as an extra margin on the "never reads young" rule.

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
