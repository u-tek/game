# Character Briefs (art direction v4: Aero Y2K, maximum reveal, female only)

These briefs are the **design source** for all art work. They override `data/art_prompts.json` and
the `look` fields in `data/heroes.json` when they disagree. **Both still hold the v3.3 designs**:
the bible is rewritten in the tag style of whichever checkpoint the owner picks (they are testing
models, 2026-10-17), and the `look` fields once the owner approves these designs. Every hero keeps
her id, faction, role, rarity, stats and kit; only looks (and, for four heroes, title and bio) change.

## v4 direction (owner, 2026-10-17)

"I want the theme of this game to be like Y2K futurism, like Frutiger [Aero] era almost, but like
actually cool, but also like erotic and super, super, super revealing." The four heroes who were
redesigned from men (Nuriel, Brakka, Orrin, Lucen) "don't look good and I don't like their
designs. I want the designs to be more unique." Players can also buy skins ("bikinis and
whatever"): see `docs/dev/skins.md`.

**"Aero Y2K", in one line:** the glossy optimism of 2000s tech (Frutiger Aero skies, glass, water
droplets, chrome, iridescent plastic) worn as high fashion, by angels and demons who dress like
the most dangerous people at the afterparty. Cool, never cute: sleek, glossy, expensive-looking.

**Touchstones:** liquid-chrome and PVC runway fashion; PS2 and Dreamcast era game art; music
videos with chrome bodies and glass rooms; Frutiger Aero desktop art (aqua skies, glass orbs,
bubbles, lens flares); Y2K cyber-fashion (wraparound shield visors, platform boots, rhinestones,
split-dye hair, frosted tips, cyber-sigilism tattoos, hot-rod flame decals, holographic vinyl).

**Materials:** glossy white PVC and pearl plastic, liquid chrome, candy-metallic vinyl, black
latex, holographic and oil-slick iridescent vinyl, smoked acrylic, clear vinyl over opaque
layers, rhinestones, chrome hardware (O-rings, buckles, zips, chains).

### The factions in Aero Y2K

| Faction | Mood | Palette | Signature materials | Halo / horns / wings |
|---|---|---|---|---|
| **Celestial** | Frutiger Aero heaven: sky, glass, water, sunlight | pearl white, aqua and cyan, sky blue, chrome silver, a touch of lime | glossy white PVC, pearl plastic, chrome, clear vinyl over opaque | solid chrome rings with a bright highlight; pearl or frosted wings with aqua tips |
| **Infernal** | Hell's nightclub: chrome, heat, neon, flames | black, candy-apple red, hot pink, liquid chrome | black latex, red metallic vinyl, chrome, rhinestones, flame decals, cyber-sigil tattoos | chrome or glossy black horns; leathery wings with chrome claws |
| **Fallen** | Dial-up dusk: broken tech, glitch, oil-slick shimmer | black, violet, teal, iridescent oil-slick, silver | oil-slick holographic vinyl, smoked acrylic, black latex, cracked chrome, cables | cracked chrome halos with pixel-glitch gaps; black wings with chrome or pixelated tips |

### What we go for

- **Maximum reveal inside the hard lines.** Micro bikinis and micro armor with small opaque cups,
  thong-cut and highleg bottoms, sling straps over opaque cups, underboob, sideboob, center
  plunges to the navel, O-ring and window cutouts, open backs and sides, harnesses and body
  chains, garters, bare midriffs and thighs. More skin than cloth on most of the roster.
- **Glossy everything.** Latex, PVC, chrome and holographic finishes are the look; matte cloth is
  the exception.
- **One Y2K hook per hero** (the "Y2K hook" column below), so 15 heroes never blur into one look.
- **Bodies vary.** Curvy is the default (large to huge breasts, wide hips, thick thighs), but
  builds still range from Brakka's bodybuilder to Nuriel's lean runner and Noctaire's long, slender
  frame.
- **Poses.** Full body, standing, both feet visible, the 3/4 view the rig needs
  (`docs/dev/art-style.md`): hip cocked, hand on hip, visor pushed up, weapon on the shoulder,
  flexing, pointing a weapon at the viewer. Smirks, half-lidded eyes, winks, confident grins.

### Production rules (so the art survives the pipeline)

- **Nothing see-through reaches the background.** The cutout can't separate clear glass or glows
  from the flat backdrop. Wings, halos, capes and drapes are solid: pearl, frosted, chrome or
  glossy, never clear. Clear vinyl could only appear where the body is behind it, and the prompts avoid it for now: `see-through` is a
  forbidden positive tag, so v4 uses opaque glossy materials (pearl, satin, holographic vinyl).
- **No glow effects, particles or bubbles floating around the figure**; the rig draws effects in
  the game. Weapons may have a bright edge painted on the solid blade.
- **Flat backdrop** as today (grey or white per hero), one figure, full body.

### Hard lines (never crossed)

- **Adults only.** Every character is an adult with an apparent age of 20 or older: adult body
  proportions, adult facial structure, adult styling and adult cues in every prompt. Never
  childlike bodies, faces, clothing or behavior. Allure never combines with anything that reads
  young.
- **Y2K without the schoolgirl.** Y2K fashion overlaps with school-coded looks. Never: school
  uniforms, sailor collars, plaid pleated miniskirts, loose socks, `kogal`, randoseru, gym
  uniforms. On the young-end heroes (Liora, Uriela, Imra) also never: butterfly hair clips,
  pigtails or high twin tails with ribbons, heart and star sticker motifs, glitter-kawaii styling,
  small wings or horns, fanged grins, blush with head tilt. They read as glamorous grown women.
  `mesugaki`, `shortstack`, `petite` (and `blue archive` on haloed heroes) stay negated.
- **Suggestive, never explicit.** Never: exposed or visible nipples or areolae, including through
  sheer, clear or wet material, as "covered nipples" outlines, or with nipple-cover-only tops (no
  pasties-only tops, no `slingshot swimsuit`, which exposes them); genitals; the pubic area;
  cameltoe; sexual acts or poses that mimic them (no all fours, kneeling, lying, bent-over or
  spread-leg poses). Bikini cups cover nipples and areolae with margin; every bottom is opaque in
  front. Thong backs are fine. No low-rise or `lowleg` bottoms (they bare the pubic area).
- **Clear and sheer only over opaque.** Clear vinyl, mesh, lace and sheer drapes never sit over
  breasts, nipples or the groin without an opaque layer under them. Wet looks keep the clothing
  opaque (`see-through` and `wet clothes` are negated on light-colored swimwear).
- **Pipeline guardrails stay on.** `tools/comfy/prompts.py` `enforce()` (adult cue tags,
  forbidden terms, required safety negatives) is never removed or weakened, and every hero's
  `negative_extra` upweights covered nipples, nipples, nipple slip, areola slip, cameltoe, no
  panties and pubic hair.
- **Human review decides.** Every image is checked at 1:1 by Claude and the owner against these
  lines and `docs/dev/art-style.md` section 1 before it goes into `assets/` or git. The exposure
  filter is a recorded second opinion (`CLAUDE.md`). An image that crosses a hard line is
  discarded, never patched.
- **Rating target:** App Store 18+. Google Play is stricter about minimally clothed, suggestive
  poses: an Android release needs a "standard" outfit per hero.

### Signature map

| Hero | Build | Signature reveal | Y2K hook | Silhouette and pose |
|---|---|---|---|---|
| Seraphiel | statuesque, huge bust | pearl latex sling leotard plunging to the navel, open sides | chrome mic-sceptre, pop-diva stage glam | six pearl wings, hand raised to the mic |
| Cassiel | athletic, abs, thick thighs | white mecha micro armor, thong-cut plate bottom | PS2-era glossy mecha plates, aqua LED seams | huge pauldrons, frosted riot-glass kite shield |
| Liora | soft and curvy | white string bikini with pearl chains, satin sarong | luxury aqua spa: pearls, chrome, water | glass lyre, hip cocked, wet-look braid |
| Uriela | toned with curves | racing leotard with underboob cutout and navel window | wraparound sport shield visor, race decals | chrome lance over the shoulder |
| Nuriel | lean runner, long legs | zip-front bandeau and thong-back sport briefs | chrome shield visor, bubble-sole platform trainers | jet-fin wings, twin prism daggers |
| Mordessa | voluptuous | red metallic micro bikini under an open vinyl coat | rhinestone crown on chrome horns, fur collar | flame-edged chrome greatsword on the shoulder |
| Brakka | towering bodybuilder | black micro bikini top, black thong, champion belt | hot-rod flames, chrome exhaust gauntlets, frosted tips | double-biceps flex |
| Vesper | hourglass | crimson latex catsuit with heart window, underboob and hip cutouts | red-tinted rimless glasses, holo-ring orb | orb raised, adjusting her glasses |
| Imra | lithe, toned | crimson metallic bandeau bikini, chrome body jewelry | lava-lamp lantern staff, UV sigil body paint | staff raised overhead |
| Kessa | athletic, curvy | black latex catsuit zipped open below the cleavage, hip windows | cat-ear headphones, red cat-eye visor | low hip-cocked stance, twin chrome sickles |
| Noctaire | tall, slender | black latex sling leotard, open sides, oil-slick drape | glitching cracked chrome halo | huge oil-slick scythe, hand in her hair |
| Orrin | tall, scarred, toned | black vinyl monokini with O-ring and side cutouts | smoked-acrylic riot armor, fiber-optic cables | frosted tower riot shield |
| Sable | curvy | latex habit-bodysuit with plunging cutout, thong-cut | holographic veil over an opaque coif, chrome cross | chrome censer orb, head tilt |
| Lucen | slender, long legs | split white/black bodysuit cut diagonally (underboob one side, sideboob the other) | split-dye hair, split wings, everything mirrored | rapier pointed at the viewer, wink |
| Ashra | soft curves | micro underboob tube top, micro shorts under slipping robes | holographic witch hat, chunky headphones | one arm lazily raised, star wand |

## Celestial: Frutiger Aero heaven (pearl white, aqua, sky blue, chrome)

- **Seraphiel**, Legendary Caster, appears mid-20s. *The pop goddess.* Statuesque and voluptuous:
  huge breasts, wide hips, narrow waist. Heaven's headline act. A pearl-white liquid-latex sling
  leotard: two wide glossy straps over opaque cups, joined at a deep plunge to the navel, open at
  the sides, thong-cut at the back; long pearl-vinyl stage drapes from chrome hip rings; chrome body chains; mirror-chrome platform heels. Six wings of pearl plastic with
  aqua tips (two large pairs, a small pair at the head) and a large chrome halo ring. Very long
  platinum hair with an aqua sheen. Her sceptre is a tall chrome tuning-fork microphone stand she
  raises like a torch. Eyes closed, serene, a knowing half-smile.
- **Cassiel**, Epic Guardian, appears mid-20s. *The aero paladin.* Athletic and curvy: toned abs,
  large breasts, wide hips, thick thighs. Glossy white mecha micro armor in the style of a
  2000s console robot: two small sculpted plate cups with aqua LED seams, a gorget, oversized
  white-and-chrome pauldrons, armored gauntlets, a bare midriff, a thong-cut plate bottom, white
  thigh-high mecha greaves. A tall kite shield of frosted aqua riot glass (solid, not clear) with a
  chrome sunburst. Short silver bob, chrome visor tiara, two glossy white wings, chrome halo. Shield
  planted at her side, hand on hip, cocky smirk.
- **Liora**, Epic Support, appears late 20s, clearly adult: adult face with glam makeup and full
  lips, adult figure. *The spa goddess.* Soft and curvy: large breasts, wide hips, thick thighs. A
  luxury aqua-resort look: a white string bikini with small opaque cups, strung with pearl chains;
  a pearl satin sarong tied at the hip; chrome anklets and
  clear-heeled mules. Long rose-gold hair in a wet-look side braid, water droplets on her skin
  (not her clothes). A lyre of frosted aqua glass with chrome strings. Two soft pearl wings, a slim
  chrome halo. Standing with her hip cocked and the lyre at her side, a slow, warm smile (no forward
  lean: in the v4 test it bent her over). Never cutesy (see the hard lines).
- **Uriela**, Rare Striker, appears mid-20s, clearly adult. *The sky racer.* Toned with curves:
  large breasts, wide hips, thick thighs. A glossy azure-and-white racing leotard, highleg and
  thong-cut, with an underboob cutout and a navel window, chrome sponsor-style decals of her
  own sun sigil, racing gloves, white platform racing boots. A chrome wraparound sport shield visor
  pushed up into a high honey-blonde ponytail. Her spear is a chrome aero lance with a frosted aqua
  blade, resting over her shoulder. Swept-back pearl wings, thin chrome halo. Confident grin.
- **Nuriel**, Rare Assassin, appears mid-20s. **Redesigned (v4).** *The lens flare.* Title:
  "the Lens Flare" (was "Dawn Scout"). Bio: "Heaven's fastest courier until she started delivering
  knives. You see the flash on her visor; you never see her." A lean, long-legged runner: defined
  abs, medium-large breasts, toned thighs. An aqua-chrome sport bandeau with a front zip pull, a
  glossy white thong-back sport brief with aqua side stripes, a cropped white vinyl track jacket
  with aqua piping slipping off her shoulders, chrome thigh holster
  straps, fingerless racing gloves, white platform trainers with clear bubble air soles. A mirrored
  chrome wraparound shield visor over her eyes. Platinum pixie cut with aqua tips. Four slim,
  swept-back wings shaped like jet fins, frosted pearl with aqua tips; a thin chrome halo tilted
  like a visor. Twin daggers of faceted crystal with a rainbow edge, one in reverse grip. Pushing
  her visor up with the dagger hand, a cool, unbothered half-smile.

## Infernal: hell's nightclub (black, candy-apple red, hot pink, chrome)

- **Mordessa**, Legendary Striker, appears around 30. *The nightclub empress.* Voluptuous: huge
  breasts, wide hips, thick thighs. Huge curled chrome ram horns with a rhinestone crown between
  them; long wavy black hair with crimson ends. A candy-red metallic micro bikini with small opaque
  cups and chrome O-ring connectors, a chrome chain belt, red latex thigh-high platform boots, and
  over it all a floor-length black vinyl coat worn open off the shoulders with a huge black fur
  collar. Cyber-sigil tattoos curl over her hip and thigh. A chrome greatsword with a painted flame
  edge on her shoulder, the other hand on her hip. Leathery bat wings with chrome claws, spaded
  tail. A commanding smirk.
- **Brakka**, Epic Guardian, appears in her 30s. **Redesigned (v4).** *The champ.* Title stays
  "Brimstone Bulwark". Bio: "Undefeated in the Pit Arena, bouncer at the Brimstone club, and the
  only demon who hugs harder than she hits. Loyal to Mordessa, and to anyone who brings snacks." A
  towering bodybuilder: huge muscles, huge breasts, defined abs, thick thighs, dark red skin. A
  glossy black micro bikini top with small opaque cups and a chrome O-ring at the center (black
  so it reads against her red skin), a black vinyl thong-cut bottom, and a huge chrome-and-gold championship belt around her waist. A
  chest harness of chrome chain. Massive black-and-chrome gauntlets built like hot-rod engines,
  with exhaust pipes on the forearms and glowing magma vents. Black platform boots with hot-rod
  flame decals. Bleached platinum hair with frosted tips, spiked up; big chrome bull horns; small
  tusks; cyber-sigil tattoos over her abs and arms. A thick tail, no wings. Double-biceps flex and
  a huge friendly grin.
- **Vesper**, Epic Caster, appears late 20s. *The hacker succubus.* Hourglass: huge breasts, wide
  hips, narrow waist. Long straight wine-red hair, half-lidded eyes behind red-tinted rimless
  glasses, small glossy black horns. A glossy crimson latex catsuit with a heart-shaped cleavage
  window, an underboob cutout and hip windows, chrome zips, black latex opera gloves, a
  high-collared open black vinyl cape lined in hot pink. A hellfire orb of glossy red glass ringed
  by floating chrome rings (solid, no glow) in her raised hand, the other adjusting her glasses.
  Bat wings, heart-spaded tail.
- **Imra**, Rare Support, **adult woman**, appears mid-20s. *The fire dancer.* Lithe and toned with
  an adult woman's curves (large breasts, wide hips), glam makeup, average height for the roster,
  never drawn small. A crimson metallic bandeau bikini, chrome body jewelry (waist chain, arm cuffs,
  navel ring), cyber-sigil body paint in UV pink and orange, chrome gladiator platform sandals. A
  shoulder-length orange mane, large curved horns, pointed ears. Her lantern staff carries a
  chrome-capped lava lamp with green-orange wax, raised overhead. Bat wings, curly tail. A sultry
  smirk, never a fanged grin. Her review comes first: the imp kit sits next to the young-coded
  `mesugaki` archetype, so nothing about her is small or bratty.
- **Kessa**, Rare Assassin, appears mid-20s. *The chrome cat.* Athletic and curvy: large breasts,
  wide hips, thick thighs. A black latex catsuit zipped open to below the cleavage and held by a
  red chrome-ringed harness, thong-cut, with hip windows; a long red vinyl scarf; black platform
  thigh boots. Chrome cat-ear headphones over short choppy black hair with a red streak, a red
  cat-eye shield visor pushed up, small horns, amber slit-pupil eyes, smug smile. Twin crescent
  sickles of black chrome. A low, hip-cocked fighting stance, chest out. Long cat tail, no wings.

## Fallen: dial-up dusk (black, violet, teal, oil-slick, silver)

- **Noctaire**, Legendary Assassin, appears late 20s. *The glitch reaper.* Tall and slender with
  long legs and large breasts. A black latex sling leotard, open at the sides (sideboob), highleg;
  a long front-and-back drape of oil-slick holographic vinyl from chrome hip buckles; black latex
  opera gloves; heeled thigh boots. Long silver hair, cold violet eyes, a cracked chrome halo
  tilted on her head with square pixel gaps. Tattered black feathered wings whose tips turn to
  pixel blocks. A huge scythe with an oil-slick chrome blade and a painted violet edge; her free
  hand sweeps back her hair. Melancholic allure.
- **Orrin**, Epic Guardian, appears around 30. **Redesigned (v4).** *The firewall.* Title stays
  "the Chained Oath". Bio: "She guarded the gate of a heaven that crashed. The gate is gone; the
  firewall isn't. Now she stands between her friends and everything else." Tall, scarred and
  toned: large breasts, wide hips, thick thighs. A glossy black vinyl monokini, highleg, with a
  chrome O-ring cutout at the sternum and cutouts at both sides of the waist; one heavy chrome
  pauldron; chrome gauntlets; smoked-acrylic thigh-high greaves with violet seams; glowing violet
  fiber-optic cables wrapped around her like her old chains. A tall riot shield of frosted smoked
  acrylic (solid) with a broken loading-ring sigil. Long straight silver hair with a black
  underlayer, a scar through one eye, a cracked chrome halo hanging from her hip like a badge.
  Black wings with chrome-plated feather tips. Shield planted, stoic.
- **Sable**, Epic Support, appears late 20s. *The cyber nun.* Curvy: huge breasts, wide hips,
  thick thighs. A skin-tight black latex habit-bodysuit with a plunging keyhole cutout to the
  navel, corset lacing and chrome trim, thong-cut, under long black vinyl tabard panels open at
  the hips; black latex thighhighs on garter straps; platform heels. An opaque black coif under a
  long veil of holographic vinyl; dark-teal hair; a chrome cross necklace. Her censer is a
  chrome orb on a chain trailing violet smoke. Grey wings with oil-slick sheen, dim cracked halo.
  Gentle, sad, alluring; head tilted. A grown woman's sorrow, never a student nun.
- **Lucen**, Rare Striker, appears mid-20s. **Redesigned (v4).** *The split screen.* Title:
  "Splitwing" (was "Twinfeather Duelist"). Bio: "Half of her fell. She styled the other half to
  match. She swears she hasn't picked a side; her rapier picks for her." Slender and toned with long
  legs: large breasts, wide hips. Everything split down the middle: hair dyed white on one side
  and black on the other; an asymmetric glossy vinyl bodysuit, white on one side and black on the
  other, cut away diagonally across the torso (an underboob cutout on one side, sideboob on the
  other, opaque cups), thong-cut, one long sleeve and one bare arm; one white thigh-high platform
  boot and one bare leg with a black garter ring; tinted oval sunglasses pushed into her hair. One
  white pearl wing, one black chrome wing. No halo. A chrome rapier with a violet painted edge
  pointed at the viewer, hip cocked, a wink and a smile.
- **Ashra**, Rare Caster, appears mid-20s. *The vaporwave witch.* Soft curves: huge breasts, wide
  hips. An oversized witch hat of holographic violet vinyl with chrome star pins; glossy violet
  robes slipping off both shoulders and arms, over a micro black tube top showing underboob and
  black micro shorts; a chrome chain belt; chunky silver headphones around her neck;
  platform ankle boots. Messy grey hair with violet streaks, cracked chrome halo. One arm raised
  lazily overhead, a chrome wand tipped with a glossy star in the other hand. Small grey wings.
  Sleepy half-lidded eyes.

## History

v3 to v3.3 (2026-10-16 and 17): maximum allure in a gothic-fantasy style, the roster made female
only, and cut-backs tuned to the exposure filter (now a second opinion, not a gate). v4
(2026-10-17): Aero Y2K theme for the whole roster, new designs for Nuriel, Brakka, Orrin and
Lucen, more revealing outfits throughout, and the skin line.
