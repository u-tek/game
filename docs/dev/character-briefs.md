# Character Briefs (art direction v4: Aero Y2K, maximum reveal, female only)

These briefs are the **design source** for all art work. They override `data/art_prompts.json` and
the `look` fields in `data/heroes.json` when they disagree. **Both still hold the v3.3 designs**:
the bible is rewritten in the tag style of whichever checkpoint the owner picks (they are testing
models, 2026-10-17), and the `look` fields once the owner approves these designs. Every hero keeps
her id, faction, role, rarity, stats and kit; only looks (and, for four heroes, title and bio) change.

**40 heroes at launch (owner, 2026-10-19: "i want 40 characters on launch, each with their own
skins").** 25 heroes were added to the first 15 (Celestial 9, Infernal 8, Fallen 8), marked **New**
in the faction sections. Their bible entries and four skins each are in `data/art_prompts.json` and
`data/skins.json`; their `look` fields in `data/heroes.json` already hold these designs. None has
art yet: the game shows a silhouette until her art is installed.

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
- **One Y2K hook per hero** (the "Y2K hook" column below), so 40 heroes never blur into one look.
- **Bodies vary.** Curvy is the default (large to huge breasts, wide hips, thick thighs), but
  builds still range from Brakka's bodybuilder to Nuriel's lean runner and Noctaire's long, slender
  frame.
- **Poses: as seductive as possible, in character** (owner, 2026-10-17: "there's no need to
  filter out any poses. i want it as erotic as possible without nudity ... but it still needs to
  suit the character cards"). Leaning toward the viewer, arched backs, arms under or hands on the
  chest, hands on thighs and hips, stretching, hair in the wind, bedroom eyes, smirks, winks, lip
  bites. Implied toplessness with hands covering the nipples ("hand bra") is in, best kept for
  skins and illustrations where the hero can put her weapon down. The only limits on base hero art
  are technical: it stands (battle ground line, both feet on the ground, no mid-air), the whole
  figure is in frame, 3/4 or front view for the rig (`docs/dev/art-style.md`). Kneeling, lying and
  all-fours poses fit illustration slots (Bond CGs, skin splash art).

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
- **As erotic as possible, never explicit.** Never: visible nipples or areolae (exposed, through
  sheer, clear or wet material, as "covered nipples" outlines, or peeking past a covering hand,
  pasty or strap); genitals; the pubic area; cameltoe; sexual acts (no partner, no simulated sex).
  Covering is fine when it is complete: hands, hair, props or pasties over the nipples and areolae
  with margin. Bikini cups cover with margin; every bottom is opaque in front; thong backs are
  fine. No low-rise or `lowleg` bottoms (they bare the pubic area). App Store note: implied
  toplessness and pasties risk rejection under Apple's guideline 1.1.4; the sideloaded build
  carries them, an App Store release would need a tamer set.
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
| Argentiel | statuesque, athletic, deep brown skin | liquid-chrome micro armor, thong-cut chrome bottom, bare midriff and back | liquid-mercury chrome body, mirror-chrome lips | glaive across her shoulders, wrists draped over it, four wings |
| Sanariel | soft, voluptuous | white PVC nurse minidress zipped to the navel on a chrome ring, hip-high slits, garters | Y2K cyber-nurse: chrome cap with an aqua plus, chrome stethoscope | giant syringe staff, stethoscope to her lips, wings like a cape |
| Rimelle | long-legged, toned | rhinestone holographic skating leotard, extreme highleg, plunge to the navel, open back | figure-skating glam: rhinestones on holographic vinyl, chrome blade skates | finishing pose on blade skates, scepter swept high |
| Avienne | tall hourglass | plunging white latex bodysuit, underboob cutout, extreme highleg, open cropped jacket | jet-set airline chic: chrome pillbox hat, aqua scarf, livery stripes | aircraft-wing shield planted, pointing to the exits |
| Cirella | lithe gymnast, abs | metallic racerback leotard, extreme highleg, sternum-to-navel diamond, open sides and back | chrome sport-tech: bladed chrome hoops, mirrored arm bands | hoop raised overhead framing her face, on her toes |
| Ferrael | strong, broad, freckled | white PVC apron over a micro bikini, open sides and back | pearl-and-chrome forge-tech: welding goggles, forge gauntlets, halos on a chain | huge hammer at her boot, wiping her brow |
| Verdelle | soft and curvy | lime metallic halter monokini, highleg, plunge to the navel, waist cutouts | Frutiger Aero eco-tech: chrome teardrop watering can, droplet decals, vinyl sun hat | watering can on her hip, pushing back her hat |
| Isobel | tall, toned | open cropped vinyl windbreaker over a metallic micro bikini, thong-cut | Y2K weather-tech: weather-icon decals, chrome anemometer staff | staff raised into the wind, shading her eyes |
| Halcia | athletic, abs, sun-tanned | jumpsuit knotted at the hips, underboob sport micro top, highleg bottom, harness straps | extreme-sports Y2K: chrome altimeter, sponsor patches, parachute harness | low wide stance, twin katars, wings folded flat |
| Mordessa | voluptuous | red metallic micro bikini under an open vinyl coat | rhinestone crown on chrome horns, fur collar | flame-edged chrome greatsword on the shoulder |
| Brakka | towering bodybuilder | black micro bikini top, black thong, champion belt | hot-rod flames, chrome exhaust gauntlets, frosted tips | double-biceps flex |
| Vesper | hourglass | crimson latex catsuit with heart window, underboob and hip cutouts | red-tinted rimless glasses, holo-ring orb | orb raised, adjusting her glasses |
| Imra | lithe, toned | crimson metallic bandeau bikini, chrome body jewelry | lava-lamp lantern staff, UV sigil body paint | staff raised overhead |
| Kessa | athletic, curvy | black latex catsuit zipped open below the cleavage, hip windows | cat-ear headphones, red cat-eye visor | low hip-cocked stance, twin chrome sickles |
| Drezza | tall, lithe, light brown skin | black latex harness micro top, hot-pink PVC thong-cut bottom on O-ring hip straps | cyber-goth rave: hair falls, goggles, face gems, DJ deck | headphone cup to her ear, red record raised high |
| Zecchina | statuesque, huge bust | red latex micro bandeau over an underbust corset, highleg thong, open rhinestone tailcoat | high-roller casino glam: chrome bow-tie collar, chips, razor cards | fanned cards beside her face, hand on hip |
| Torqua | towering glamazon, deep brown skin | candy-red and white PVC race-queen bodysuit, extreme highleg, plunge to the navel, open sides | Y2K race queen: sigil decals, checkered trim, grid parasol | parasol held high like a canopy, hand on cocked hip |
| Sigilla | soft and thick, pale, tattooed collarbone to ankle | red latex micro string bikini, highleg thong, shrug cropped above the breasts | tattoo-parlor hellfire: cyber-sigilism, chrome tattoo machine, piercings | tattoo machine aimed like a pistol, hand on hip |
| Carmesa | dancer's hourglass, olive skin | rhinestone bolero over an underboob bandeau, high-waisted thong-back micro shorts | rhinestone matador glam: capote, estoc, hot-pink latex stockings | cape swept out like a flag, arched back, chin up |
| Thrasha | lean and wiry | safety-pinned black vinyl micro bikini, highleg thong, biker jacket off the shoulders | nu-metal rock star: flying-V guitar-axe, chains, torn fishnets | guitar-axe over her shoulder, throwing the horns |
| Kindra | muscular, abs, tan, soot | red latex micro bandeau under suspenders, highleg thong-cut bottom, turnout boots | firehouse-calendar pin-up: reflective chrome, red-and-chrome helmet | fire axe held low, thumb pulling a suspender, wink |
| Cordia | hourglass, huge bust | black latex waistcoat with nothing under it, plunging to the navel, slit pencil micro skirt | chrome cocktail lounge: shaker, bar spoon, garter flasks | shaker up by her shoulder, hand on hip |
| Noctaire | tall, slender | black latex sling leotard, open sides, oil-slick drape | glitching cracked chrome halo | huge oil-slick scythe, hand in her hair |
| Orrin | tall, scarred, toned | black vinyl monokini with O-ring and side cutouts | smoked-acrylic riot armor, fiber-optic cables | frosted tower riot shield |
| Sable | curvy | latex habit-bodysuit with plunging cutout, thong-cut | holographic veil over an opaque coif, chrome cross | chrome censer orb, head tilt |
| Lucen | slender, long legs | split white/black bodysuit cut diagonally (underboob one side, sideboob the other) | split-dye hair, split wings, everything mirrored | rapier pointed at the viewer, wink |
| Ashra | soft curves | micro underboob tube top, micro shorts under slipping robes | holographic witch hat, chunky headphones | one arm lazily raised, star wand |
| Nadira | tall, long legs, dark skin | space-suit highleg bodysuit zipped to the navel, open sides | oil-slick space-age vinyl, mirrored helmet, dead satellite | wings spread wide, helmet under one arm, satellite staff raised |
| Gantra | tall, broad shoulders, abs | pilot bodysuit unzipped to the navel, highleg, open sides | anime mech-pilot: giant chrome mech arm, cracked headset | mech arm raised like a tower shield, no wings, hand on hip |
| Severine | athletic swordswoman | latex chest wrap, off-shoulder kimono jacket, panels split to the hip | cyber-ronin: holographic obi, glitch sleeves, chrome odachi | drawing the odachi in a low ready stance |
| Benthe | towering, blue-grey skin | keyhole swimsuit from collar to navel, open back, under a diving yoke | retro-future deep sea: chrome corselet, anchor and chain | huge anchor upright like a shield, hand on its fluke |
| Seyra | soft and curvy | halter bodysuit plunging below the navel, bare back, open drape | dead-channel oracle: static crystal ball, third-eye diadem | ball cradled under her chest, head tilt, half-closed eyes |
| Rivette | muscular thighs, abs | laced underboob crop top, highleg micro briefs, garter rings | dead-highway roller derby: platform skates, chrome pads, buzz cut | stop-sign poleaxe planted, arm hooked over it, hip cocked |
| Vandra | lithe, curvy | hoodie cropped to underboob, highleg micro bikini bottom | Y2K street art: chrome spray cans, wildstyle tags, respirator | spray can raised as if tagging the air |
| Ombre | long and lean | micro bandeau and highleg briefs under a harness, coat off the shoulders | 1999 cyber-noir: tiny oval shades, ombre trench, chrome sniper rifle | rifle at low ready, looking over her sunglasses |

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
- **Argentiel**, Legendary Striker, appears early 30s. **New (40-hero roster, 2026-10-19).** *The
  liquid-chrome marshal.* Statuesque and athletic: tall, broad shoulders, defined abs, huge breasts,
  wide hips, thick muscular thighs, deep brown skin. Title "the Sky Marshal". Commander of heaven's
  sky legions and the only angel who has never lost a duel; proud and blunt, warm underneath.
  Liquid-chrome micro armor that looks still molten: two small mirror-chrome cups and a highleg,
  thong-cut chrome bottom joined by chrome rivulets over bare skin; a bare midriff and back; chrome
  thigh-high greaves. She tops the chrome up from a hip flask the way other women reapply lipstick.
  Long black box braids gathered into a high crown with chrome cuffs, mirror-chrome lips. Four
  swept-back pearl wings with aqua tips, a broad chrome halo. A huge double-bladed chrome glaive
  held across her shoulders behind her neck, both wrists draped over it, feet planted wide, chin up:
  a stare that dares you to look away.
- **Sanariel**, Legendary Support, appears early 30s. **New (40-hero roster, 2026-10-19).** *The
  cyber nurse.* Soft and voluptuous: huge breasts, a narrow waist, wide hips, soft thick thighs,
  fair skin. Title "Mercy Ward". Matron of heaven's infirmary, a teasing big sister to every angel
  she patches up, unhurried and unafraid of blood. A skin-tight white PVC nurse minidress zipped
  open to the navel and held by one chrome ring (the dress cups cover with margin), hip-high side
  slits showing white latex garter straps over opaque white highleg briefs, short puffed sleeves;
  white latex opera gloves and thigh-highs. A chrome nurse cap with an aqua plus sign (never a red
  cross, a protected emblem), a chrome stethoscope, mirrored aqua lip gloss. Long wavy mint-aqua
  hair in a loose low bun. Two large pearl wings folded around her like a cape, a slim chrome halo.
  A giant chrome syringe staff, taller than she is, planted beside her; standing hip-cocked (no
  forward lean), lifting the stethoscope to her lips, a patient, teasing smile.
- **Rimelle**, Epic Caster, appears late 20s. **New (40-hero roster, 2026-10-19).** *The rink
  champion.* Long-legged and toned like a champion skater: long thighs, a small waist, large
  breasts, high round hips, an adult face with glam makeup. Title "Triple Axel". Heaven's reigning
  figure-skating champion, cool, perfectionist and secretly very competitive; every battlefield is a
  rink and every enemy a judge she intends to freeze out. A rhinestone-crusted pearl-white
  holographic skating leotard, extreme highleg and thong-cut, with a deep V plunge to the navel, an
  open back down to the hips and one long sleeve; a short pearl-vinyl skating skirt open at the
  front; chrome blade skates. Long straight icy-lavender hair loose to her waist, icy holographic
  eyeshadow. Frosted pearl wings with solid icicle-shaped tips, a thin chrome halo. Standing tall in
  a finishing pose, one arm swept high with a frosted ice-crystal scepter (solid, never clear), the
  other hand on her hip, a cool, cut-glass smile. Never young-coded: a grown champion, not a junior.
- **Avienne**, Epic Guardian, appears early 30s. **New (40-hero roster, 2026-10-19).** *The jet-set
  purser.* Tall hourglass: large breasts, a tiny waist, wide hips, long legs. Title "Cabin Chief".
  Chief purser on heaven's flagship airline, unflappable, polite and quietly terrifying when someone
  ignores the seatbelt sign. A plunging white latex bodysuit with an underboob cutout, extreme
  highleg and thong-cut, under a cropped, fitted aqua PVC flight-attendant jacket worn open; glossy
  white latex thigh-highs, white patent platform pumps. Turn-of-the-millennium jet-set chic: a
  chrome pillbox hat, a knotted aqua silk-look scarf, a chrome flight-wings badge, aircraft livery
  stripes. A chestnut French twist. Two wide white wings with aqua livery stripes, a chrome halo. A
  tall shield cut from a chrome aircraft wing with aqua livery stripes and an upturned winglet tip,
  planted at her side; her free hand raised in a polite safety-demonstration gesture toward the
  exits; a flawless professional smile.
- **Cirella**, Epic Assassin, appears late 20s. **New (40-hero roster, 2026-10-19).** *The bladed
  gymnast.* Lithe and flexible: a gymnast's long lean muscles, defined abs, medium-large breasts,
  firm round hips, an adult face with glam makeup. Title "Perfect Ten". Heaven's gold-medal rhythmic
  gymnast until someone sharpened her hoops; sunny, flirty and ferociously disciplined, she bends
  around blades and comes up behind the enemy's healers. A metallic sky-blue racerback gymnastics
  leotard, extreme highleg and thong-cut, with a diamond cutout from the sternum to the navel and
  both sides cut open from ribs to hips (sideboob), a bare back, a holographic stripe down each
  side; mirrored chrome arm bands; barefoot with chrome ankle cuffs. Cobalt-blue hair in a tight
  high ballet bun. Two slim pearl wings swept up, a thin chrome halo. Two bladed chrome hoops
  (chakram rings): one raised overhead framing her face, the other resting against her hip; up on
  the balls of both feet; a sunny, flirty smile. A grown athlete, never a junior.
- **Ferrael**, Rare Striker, appears late 20s. **New (40-hero roster, 2026-10-19).** *The halo
  smith.* Strong and broad: muscular arms and shoulders, a softly defined belly, huge breasts, wide
  hips, thick thighs, freckled light-tan skin. Title "Halo Smith". She forges every halo in heaven,
  and the dents in the big ones are hers; loud, cheerful and permanently soot-smudged. A heavy white
  PVC blacksmith's apron over a white micro bikini (the bikini always visible), open at the sides
  and back (sideboob, bare hips), bib straps crossed over her shoulders, cut short at mid-thigh;
  white platform work boots. Pearl-and-chrome forge-tech: chrome welding goggles pushed up into a
  short copper-red shag, chrome-plated forge gauntlets, freshly forged halos hanging from a chrome
  chain belt. Soot-smudged pearl wings tucked tight, a heavy chunky chrome halo she forged herself.
  A huge chrome forge hammer resting head-down beside her boot, one hand on the handle, the other
  forearm wiping her brow; a big satisfied grin.
- **Verdelle**, Rare Support, appears late 20s. **New (40-hero roster, 2026-10-19).** *The
  glasshouse gardener.* Soft and curvy: large breasts, a soft waist, wide hips, thick thighs, warm
  light skin, glam makeup. Title "Glasshouse Keeper". She keeps heaven's glasshouse, the sunlit dome
  where every plant in creation grows; warm, chatty and endlessly patient. A lime-green metallic
  halter monokini, highleg and thong-cut, with a plunge to the navel and wide cutouts at both sides
  of the waist; a chrome tool belt slung on her hips; white platform rain boots. Frutiger Aero
  eco-tech: glossy lime-and-white plastic, water-droplet decals, a chrome teardrop-shaped watering
  can, leaf-shaped chrome hair pins, a wide-brim white vinyl sun hat. Long wavy strawberry-blonde
  hair with lime-green tips. Pearl wings with lime-green tips, a chrome halo etched with leaves. Hip
  cocked, the watering can resting on her hip (no pouring water), the other hand pushing back her
  sun hat; a warm, chatty smile.
- **Isobel**, Rare Caster, appears mid-20s. **New (40-hero roster, 2026-10-19).** *The storm
  chaser.* Tall and toned with curves: large breasts, a narrow waist, wide hips, long legs. Title
  "Storm Chaser". She chases storms across heaven for fun and calls them down on enemies for work;
  breathless, reckless and happiest when the sky turns green. A cropped white vinyl storm-chaser
  windbreaker unzipped and blowing open over a sky-blue metallic micro bikini with small opaque
  triangle cups and a highleg, thong-cut bottom; chrome carabiner straps across her hips; white
  platform hiking boots. Y2K weather-tech: Frutiger Aero weather-icon decals (sun, cloud, lightning
  bolt) on the jacket, a tall chrome anemometer staff with spinning cups, a chrome handheld radar on
  her belt. A wind-tossed indigo bob with one white streak. Storm-grey pearl wings with aqua tips, a
  chrome halo. Holding the staff up into the wind, jacket and hair streaming sideways, her other
  hand shading her eyes as she watches the sky; a breathless, thrilled grin.
- **Halcia**, Rare Assassin, appears late 20s. **New (40-hero roster, 2026-10-19).** *The skydiver.*
  Athletic and toned: defined abs, strong thighs, large breasts, firm hips, sun-tanned skin. Title
  "Drop Zone". She jumps out of heaven at forty thousand feet and opens her wings at the last
  possible second, usually on top of an enemy's back line; an adrenaline junkie with a laugh you can
  hear from orbit. A white-and-aqua skydiving jumpsuit stripped off and knotted around her hips by
  the sleeves, over an opaque aqua highleg sport bottom cut high at the hips; an aqua sport micro
  top with an underboob cutout; chrome parachute-harness straps framing her chest and thighs; white
  jump boots. Extreme-sports Y2K: a chrome altimeter on her wrist, sponsor-style patches, a chrome
  jump helmet clipped to her harness at the hip, a pearl parachute pack. A wind-tousled sandy-blonde
  lob. Four narrow pearl wings folded flat against the pack, a thin chrome halo. A wide, low stance
  with knees bent and both feet down, a chrome katar (punch dagger) in each fist, one raised across
  her chest; a fearless grin.

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
- **Drezza**, Legendary Support, appears late 20s. **New (40-hero roster, 2026-10-19).** *The
  headliner.* Title: "the Headliner". Bio: "She has headlined the Brimstone club every night for six
  hundred years and never played the same set twice. When she drops the beat the whole team moves
  faster; when she stops, nobody wants to go home." Tall and lithe: long legs, a tiny waist, large
  breasts, round hips; light brown skin. A black latex micro top under hot-pink criss-cross harness
  straps with chrome O-rings, a hot-pink PVC highleg thong bottom on chrome O-ring hip straps, a
  bare midriff; fluffy black-and-pink faux-fur leg warmers over chunky platform boots. Cyber-goth
  rave: one huge high ponytail of hot-pink and black synthetic hair falls (never twin tails), cyber
  goggles on her forehead, rhinestone face gems. Glossy chrome horns, a spaded tail with a chrome
  tip, no wings. A chrome DJ deck slung on a strap at her hip like a guitar, one hand pressing a
  headphone cup to her ear, the other raised high with a glossy red vinyl record. A mid-beat grin.
- **Zecchina**, Legendary Assassin, appears early 30s. **New (40-hero roster, 2026-10-19).** *The
  high roller.* Title: "House Edge". Bio: "She runs the tables at hell's grand casino and has never
  once let the house lose. She remembers every debt in the underworld, and she always collects."
  Statuesque and voluptuous: tall, huge breasts, a narrow waist, wide hips, long legs. A black latex
  underbust corset with a red latex micro bandeau, a black latex highleg thong bottom, and a
  rhinestone-encrusted black tuxedo tailcoat worn open with long tails; black latex opera gloves,
  fishnet thigh-highs (legwear only) on garters, red patent stilettos. High-roller casino glam: a
  chrome bow-tie collar, gold-chrome casino chips tucked in her garter, a fan of razor-edged chrome
  playing cards. Glossy champagne-blonde Hollywood waves, long straight black horns with gold-chrome
  tips, small black bat wings, a long spaded tail. Fanning her cards beside her face, the other hand
  on her hip pushing the tailcoat back; a half-lidded, knowing smile.
- **Torqua**, Epic Guardian, appears late 20s. **New (40-hero roster, 2026-10-19).** *The race
  queen.* Title: "Grid Queen". Bio: "The face of hell's grand prix, and the reason nobody storms the
  pit lane twice. A thousand photo calls taught her to hold a smile, a parasol and a line." A
  towering glamazon: very tall, very long legs, huge breasts, wide hips, thick thighs; deep brown
  skin. A glossy candy-red and white PVC race-queen bodysuit, extreme highleg and thong-cut, with a
  deep plunge to the navel and both sides cut open; a cropped matching PVC bolero; red latex
  thigh-high platform boots. The Y2K race queen: sponsor-style decals of her own sigil,
  checkered-flag trim, chrome hoop earrings. Long voluminous candy-red blowout curls, swept-back
  chrome horns shaped like hood ornaments, a long tail, no wings. The open chrome-and-red race
  parasol (solid, never clear) held high above her head like a canopy, the other hand on her cocked
  hip, one long leg forward; a dazzling camera smile.
- **Sigilla**, Epic Caster, appears early 30s. **New (40-hero roster, 2026-10-19).** *The tattoo
  witch.* Title: "Burning Ink". Bio: "Hers is the only parlor in hell where demons queue politely,
  because every curse she inks comes true. Her rates are reasonable; her waiting list is not." Soft
  and thick: huge breasts, a soft waist, very wide hips, very thick thighs; pale skin covered
  collarbone to ankle in black and red cyber-sigil tattoos. A red latex micro string bikini (small
  opaque cups, a highleg thong bottom) to show off her tattoos, a black vinyl shrug cropped above
  the breasts, a chrome studded garter belt; black platform creepers. Tattoo-parlor hellfire: an
  oversized chrome rotary tattoo machine on a coiled red cord, flash-sheet decals on her shrug,
  chrome facial piercings. Long black curls over a cherry-red underlayer, one side shaved, small
  curled black horns pierced with chrome rings, black bat wings tattooed with flash art, a spaded
  tail. Aiming the tattoo machine at the viewer like a pistol, the other hand on her hip; a lazy,
  smoldering look.
- **Carmesa**, Epic Assassin, appears late 20s. **New (40-hero roster, 2026-10-19).** *The matador.*
  Title: "Red Veronica". Bio: "Born with a bull's horns and a matador's nerve, she settled the
  argument by becoming both. She bows before every kill, and she has never missed her moment." A
  dancer's hourglass: toned, large breasts, a tiny waist, wide hips, strong legs; olive skin. A
  cropped rhinestone-crusted red-and-chrome matador bolero with epaulettes, open over a black latex
  bandeau cut to show underboob; black latex high-waisted, thong-back micro shorts with rhinestone
  side stripes; hot-pink latex thigh-high stockings, black patent pumps with chrome buckles.
  Rhinestone matador glam: a glossy red vinyl capote (solid) and a chrome estoc. Deep burgundy hair
  in a slick low chignon, glossy black forward-curving bull horns, a long tail, no wings. The capote
  swept out behind her in one hand like a flag, the estoc pointed down at her side, chin up in a
  proud arched-back stance; a cool, theatrical look.
- **Thrasha**, Rare Striker, appears mid-20s. **New (40-hero roster, 2026-10-19).** *The rock star.*
  Title: "Power Chord". Bio: "Her band is banned from every venue in hell, so now she plays the
  battlefield. Loud, reckless and secretly sentimental: she still answers all her fan mail." Lean
  and wiry: tall, a flat toned stomach, large breasts, narrow hips, long legs; adult glam-punk
  makeup (smudged black eyeliner, black lipstick). A black vinyl micro bikini top held together with
  chrome safety pins and chains, a black PVC highleg thong bottom, torn black fishnet thigh-highs
  (legwear only), a cropped studded black vinyl biker jacket slipping off her shoulders; black
  platform combat boots. Nu-metal rock star: a chrome flying-V guitar with flame decals and an
  axe-blade edge, chrome wallet chains, a spiked choker. A choppy hot-pink wolf cut, one horn broken
  off and capped in chrome, tattered bat wings. The guitar-axe held by the neck over her shoulder
  like a battle-axe, the other hand throwing the horns, feet planted wide; a snarling grin, never
  fanged.
- **Kindra**, Rare Guardian, appears early 30s. **New (40-hero roster, 2026-10-19).** *The fire
  marshal.* Title: "Fire Marshal". Bio: "Hell's fire marshal: her job is keeping every fire burning
  exactly where it should. She has carried more demons out of collapsing clubs than anyone, and has
  a terrible pun for each of them." Muscular and athletic: broad shoulders, strong arms, defined
  abs, large breasts, wide hips, thick thighs; tan skin with soot smudges. A red latex micro bandeau
  under red suspenders, a black highleg thong-cut bottom with chrome reflective stripes, black
  thigh-high turnout boots, a cropped turnout jacket slung over her shoulders. Chrome
  firehouse-calendar pin-up: chrome reflective tape, a glossy red-and-chrome fire helmet with holes
  for her horns, a chrome hose nozzle on her belt. Short ash-blonde hair shaved at the sides, stubby
  charred horns through the helmet, a thick tail, no wings. A big chrome fire axe held low in one
  hand, the other thumb hooked in a suspender and pulling it out, chest out; a big confident wink.
  No flames in the art: the rig draws the fire.
- **Cordia**, Rare Support, appears early 30s. **New (40-hero roster, 2026-10-19).** *The
  bartender.* Title: "Last Call". Bio: "She tended bar at the Brimstone club before the club was
  built. She knows what you need before you ask, and she never repeats what you told her."
  Hourglass: huge breasts, a cinched waist, wide hips, thick thighs. A black latex bartender's
  waistcoat with nothing under it, buttoned once at the waist and plunging open to the navel
  (covering with margin), a red latex bow-tie collar on bare skin, red latex cuffs, a black latex
  pencil micro skirt with a slit to the hip over an opaque highleg thong; black patent platform
  heels. Chrome cocktail lounge: a big chrome cocktail shaker and a long chrome bar spoon,
  mirror-chrome nails, a garter holster of tiny chrome flasks (no glassware: it would be
  see-through). Voluminous auburn curls swept to one side, elegant ram horns banded in chrome, a
  spaded tail, small bat wings. Shaking the shaker up beside her shoulder, the other hand on her
  hip; a warm, knowing smirk.

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
- **Nadira**, Legendary Caster, appears early 30s. **New (40-hero roster, 2026-10-19).** *The dead
  satellite.* Title: "Lost Signal". Bio: "Heaven's satellite keeper until the signal died and she
  fell with it, still strapped in. She can still call the dead ones down, and they always answer."
  Tall and long-limbed: very long legs, huge breasts, a narrow waist, wide hips, dark umber skin. A
  glossy black-and-violet space suit cut into a highleg bodysuit, zipped open to the navel and open
  at both sides (sideboob), with oil-slick holographic panels and chrome mission patches bearing a
  broken loading-ring logo; chunky white-and-chrome platform moon boots. A chrome space helmet with
  an opaque mirrored visor tucked under one arm on her hip; the other hand raises a staff topped
  with a small broken chrome satellite. Long silver-white locs tied loosely back. Black wings with
  chrome solar-panel feathers spread wide, a cracked chrome halo tilted like a planet's ring. Calm,
  distant and a little lonely.
- **Gantra**, Legendary Guardian, appears late 20s. **New (40-hero roster, 2026-10-19).** *The last
  pilot.* Title: "Last Pilot". Bio: "She piloted the last mech of heaven's crashed fleet and walked
  out of the wreck carrying its arm. She still talks to it; it is the better listener." Tall and
  athletic with curves: broad strong shoulders, defined abs, huge breasts, wide hips, thick thighs.
  A glossy black-and-teal pilot bodysuit unzipped from the collar to the navel (opaque suit cups),
  cut highleg with open sides; a chrome pilot collar, chrome interface nodes on her hips and spine,
  teal painted seams (no glow); black platform pilot boots. Her mech's giant torn-off chrome forearm
  and hand is strapped over her left arm and raised like a tower shield, fingers spread; a cracked
  chrome halo is bolted to its shoulder. Short choppy teal hair over a shaved undercut, a cracked
  pilot headset. No wings. Free hand on her hip, a tired, cocky half-smile.
- **Severine**, Epic Striker, appears late 20s. **New (40-hero roster, 2026-10-19).** *The
  cyber-ronin.* Title: "Masterless Blade". Bio: "Sworn to an archangel who fell first, she has
  served no one since. She is quietest when she is amused, and that is when you should run."
  Athletic: toned arms and abs, large breasts, wide hips, strong thighs. A black latex chest wrap
  (an opaque band) under a short black latex kimono jacket worn off both shoulders with pixel-glitch
  sleeves; a wide oil-slick holographic obi corset belt; a highleg black latex bottom under long
  black vinyl panels split to the hip on both sides; black latex thigh-highs, black platform
  sandals. Very long straight black hair in a high ponytail bound by a chrome ring. Long tattered
  black wings, a cracked chrome halo with a piece missing. Drawing a long chrome odachi with a
  violet painted edge from the scabbard at her hip, low and ready; a faint, dangerous smile.
- **Benthe**, Epic Guardian, appears early 30s. **New (40-hero roster, 2026-10-19).** *The deep
  diver.* Title: "Crush Depth". Bio: "She fell into the sea, kept falling to the bottom, and decided
  she liked it there. She surfaces only when her friends need a wall, and she is a very good wall."
  Towering and powerful: very tall, broad shoulders, thick strong arms, huge breasts, wide hips,
  very thick thighs, pale blue-grey skin. A black latex high-neck swimsuit with a huge keyhole
  cutout from the collar to the navel and an open back, highleg, under a bolted chrome diving
  corselet that yokes only her shoulders; oil-slick barnacle rivets; a chrome weight belt across her
  hips; chunky chrome diving boots. A huge chrome anchor held upright beside her like a tower
  shield, one hand on its fluke, the heavy chain looped over her shoulder. Long deep-teal wet-look
  waves (the wet look stays on hair and skin). Heavy black wings folded tight with chrome rivet
  tips, a cracked chrome halo. A slow, sleepy smile.
- **Seyra**, Epic Support, appears late 20s. **New (40-hero roster, 2026-10-19).** *The dead-channel
  oracle.* Title: "Static Oracle". Bio: "She reads the future in dead television static and has
  never been wrong, except about her own fall. She already knows what you are about to say." Soft
  and curvy: huge breasts, a soft waist, wide hips, thick thighs; grown-up makeup. A black latex
  halter bodysuit split by a narrow plunge from the collar to below the navel (opaque cups each
  side), highleg, with a bare back; a long violet vinyl priestess drape with CRT scan-line patterns
  hangs from a chrome collar, open at the front and sides; black platform sandals. A cracked
  chrome-framed crystal ball full of TV static (opaque, never clear) cradled beneath her chest. Long
  straight periwinkle hair with blunt bangs, a chrome third-eye diadem with a teal gem. Grey wings
  with oil-slick eye-shaped spots spread low, a cracked chrome halo with a pixel gap. Head tilted as
  if listening, eyes half-closed, a dreamy smile. A grown woman's calm, never girlish.
- **Rivette**, Rare Striker, appears mid-20s, clearly adult. **New (40-hero roster, 2026-10-19).**
  *The roller-derby jammer.* Title: "Hard Stop". Bio: "She skates the broken highways of the Fallen
  wastes, and everything on them stops for her. First to the finish line, first to buy the rounds."
  Athletic and powerful: muscular thighs and glutes, defined abs, large breasts, wide hips; adult
  face with makeup. A black-and-violet vinyl underboob crop top laced up the front, violet PVC
  highleg micro briefs, black latex thigh-highs with chrome garter rings, chrome knee and elbow
  pads, platform roller skates with violet wheels. A bent chrome stop sign welded onto a pole as a
  poleaxe, planted beside her with one arm hooked over it, hip cocked. A platinum buzz cut dyed
  violet at the tips. Clipped black wings with chrome tips, a cracked chrome halo tilted on her
  head. A cocky grin. Never sporty-cute: no gym or school cues.
- **Vandra**, Rare Caster, appears mid-20s, clearly adult. **New (40-hero roster, 2026-10-19).**
  *The street artist.* Title: "Wet Paint". Bio: "She tags the ruins of fallen heaven with spells
  instead of signatures, and whatever she paints starts to burn. Authority is just a wall she hasn't
  got to yet." Lithe and curvy: long legs, a slim waist, large breasts, round hips; adult face with
  makeup. An oversized black vinyl hoodie cropped just under the breasts (underboob, opaque with
  margin), hood down and covered in wildstyle tags; a teal latex highleg micro bikini bottom with
  paint-splattered straps; paint-flecked teal latex thigh-highs; chunky platform sneakers; a
  paint-flecked respirator pulled down around her neck (no paint mist in the air). Oil-slick
  holographic chrome spray cans, one raised at shoulder height as if tagging the air, the other at
  her hip. A messy teal-and-violet shag flecked with paint. Black wings tagged with teal and violet
  graffiti, a cracked chrome halo with a painted drip. A mischievous smile.
- **Ombre**, Rare Assassin, appears late 20s. **New (40-hero roster, 2026-10-19).** *The cyber-noir
  sniper.* Title: "Dead Pixel". Bio: "One shot per battle, and she has never needed a second. She
  reads novels between targets and always finishes the chapter." Long and lean: tall, long legs, a
  narrow waist, large breasts, narrow hips. A black latex micro bandeau and highleg briefs under a
  chrome-buckled tactical chest harness and thigh holsters, black latex arm sleeves, a long
  black-to-silver ombre vinyl trench coat worn open and off the shoulders; knee-high platform combat
  boots. Tiny oval chrome sunglasses slipping down her nose, her eyes visible above them. A long
  chrome sniper rifle with a pixel-crosshair scope held diagonally across her body at low ready; the
  other hand lowers the sunglasses. Very long black hair fading to silver in a low ponytail. Long
  black wings fading to silver at the tips, a cracked chrome halo shaped like a scope reticle. A
  cool, deadpan stare.

## History

v3 to v3.3 (2026-10-16 and 17): maximum allure in a gothic-fantasy style, the roster made female
only, and cut-backs tuned to the exposure filter (now a second opinion, not a gate). v4
(2026-10-17): Aero Y2K theme for the whole roster, new designs for Nuriel, Brakka, Orrin and
Lucen, more revealing outfits throughout, and the skin line. 2026-10-19: the roster grew from 15 to
40 heroes (25 new designs in the same v4 rules), each with all four skin packs.
