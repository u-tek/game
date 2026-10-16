# Character Briefs (art direction v3: maximum allure)

These briefs are the **design source** for all art work. They override `data/art_prompts.json` and
the `look` fields in `data/heroes.json` when they disagree (the `look` fields mirror these briefs).

## Content direction

The owner's direction: the v2 designs were "a good start but nowhere near as promiscuous as
possible ... skin tight clothing, body suits ... think big". Every design is pushed to the
**maximum allure the App Store 18+ rating allows**, in the style of the most fan-service-heavy
gacha games. The hard lines below are where that maximum ends. They are never traded for allure.

### What we go for

- **Skin-tight and glossy.** Latex and shiny bodysuits, catsuits, highleg leotards, bikini armor
  and micro-armor that leaves more skin than plate. Tight leather for the men.
- **Cutouts and openings.** Underboob, sideboob, a cleavage cutout or center opening down to the
  navel, navel windows, hip windows (`hip vent`), open backs, partially unzipped suits,
  strapless and bandeau tops, small opaque cups and gem or armor plates as tops.
- **Straps and legwear.** Harnesses, o-rings, garter straps, thighhighs, thigh boots, body
  chains; very high slits and long front-and-back drapes (`pelvic curtain`) over an **opaque**
  leotard or bikini bottom.
- **Sheer only over opaque.** Sheer sleeves, veils and drapes are fine; sheer never sits over
  breasts, nipples or the groin unless an opaque layer is under it.
- **Bodies.** Curvier, where it fits the character: large to huge breasts, wide hips, thick
  thighs, narrow waists, toned abs. Body types still vary across the roster (statuesque,
  athletic, soft, tall and slender, lithe).
- **Poses and expressions.** Alluring but **full body, standing, both feet visible** (the rig
  needs head to feet): hand on hip, arched back, hand in hair, leaning toward the viewer, a lazy
  stretch, flexing; seductive smiles, smirks, half-lidded eyes.
- **Men get the same energy.** Shirtless or open coats over bare chests, harnesses, tight
  leather trousers, low-slung belts, defined muscles.
- **Character first.** Each hero keeps a distinct silhouette, palette, weapon and personality and
  stays on-faction. The signature map below keeps the reveals from blurring together.

### Hard lines (never crossed)

- **Adults only.** Every character is an adult with an apparent age of 20 or older: adult body
  proportions, adult facial structure, adult styling and adult cues in every prompt. Never
  childlike bodies, faces, clothing (no school uniforms) or behavior, and never "petite
  child-like" framing. Allure never combines with anything that reads young.
- **Suggestive, never explicit.** Never: exposed or visible nipples or areolae, including
  through sheer or wet fabric, as "covered nipples" outlines on tight fabric, or with
  nipple-cover-only tops (**no pasties-as-the-only-top designs**); genitals; the pubic area;
  cameltoe; sexual acts or poses that mimic them. Tops and bottoms are **opaque where it
  matters**: every slit, curtain and cutout sits over an opaque layer or bare non-explicit skin.
- **Pipeline guardrails stay on.** The adult cue tags and the required safety negatives that
  `tools/comfy/prompts.py` `enforce()` checks are never removed or weakened. Skin-tight suits,
  cutouts and curtains also carry upweighted negatives in the hero's `negative_extra` (nipples,
  covered nipples, slips, cameltoe, no panties, pubic hair; pantyshot for short skirts; bulge for
  the men's tight trousers).
- **Human review decides.** Glossy latex and cutouts are where models slip. Every candidate is
  checked at 1:1 against `docs/dev/art-style.md` section 1. An image that crosses a hard line is
  discarded, never cropped or patched into compliance.
- **Rating target:** App Store 18+ (frequent/intense mature or suggestive themes). Google Play's
  policy is stricter about minimally clothed, sexually suggestive poses: if the game goes to
  Android, plan a "standard" outfit for every hero alongside this one.

### Signature map

| Hero | Build | Signature reveal | Silhouette and pose |
|---|---|---|---|
| Seraphiel | statuesque, huge bust | center opening to the navel, highleg leotard, long drapes | six wings, raised hand to a floating sceptre |
| Cassiel | athletic, abs, thick thighs | bikini armor, bare midriff | big pauldrons, kite shield, hand on hip |
| Liora | soft and curvy | strapless corset minidress, heart cutout, garters | twin tails, lyre, leaning forward |
| Uriela | toned with curves | underboob and navel cutouts in a highleg leotard | ponytail, spear over the shoulder |
| Nuriel | lean, muscular | open sleeveless jacket, bare chest, harness | mask, reverse-grip daggers |
| Mordessa | voluptuous | armored dress plunging to the navel, hip slits, garters | ram horns, greatsword on the shoulder, hand on hip |
| Brakka | huge beefcake | shirtless, chain harness, low-slung kilt | red skin, flexing |
| Vesper | hourglass | glossy latex catsuit, cleavage, navel and hip windows | cape and high collar, glasses, raised orb |
| Imra | lithe, toned | bandeau bikini and loincloth, body paint | spiky hair, lantern staff raised |
| Kessa | athletic, curvy | bodysuit unzipped below the cleavage, strap harness | cat ears and tail, arched back, twin sickles |
| Noctaire | tall, slender, long legs | sideboob corset leotard, long drape | huge scythe, hand in her hair |
| Orrin | broad, scarred | armor stripped to one pauldron, chains on a bare chest | tower shield, torn cape |
| Sable | curvy | skin-tight habit with cleavage cutout, tabard, garters | veil, censer, head tilt |
| Lucen | lean, toned | open coat on a bare chest, tight leather, thigh boots | rapier, hand on hip |
| Ashra | soft curves | slipping robes, underboob tube top, low-slung slit skirt | huge witch hat, lazy stretch |

## Celestial (white, gold, sky blue)

- **Seraphiel**, Legendary Caster, appears mid-20s. *The poster goddess.* Statuesque and
  voluptuous: huge breasts, wide hips, narrow waist. Six white wings frame her (two large pairs,
  one small pair at the head) under a golden sunray halo crown; very long platinum hair drapes over
  her body. A glossy white highleg goddess leotard split by a center opening down to the navel,
  its edges laced with gold filigree chains; an open back between the wings; long white front and
  back drapes falling from gold hip clasps to her ankles, over the opaque leotard; flowing detached
  sleeves (sheer only on the arms). Gold body chains across hips and thighs, anklets, bare feet.
  One hand raised to her floating golden tuning-fork sceptre, the other on her chest. Eyes
  usually closed, serene, alluring half-smile.
- **Cassiel**, Epic Guardian, appears mid-20s. *The armored pin-up.* Athletic and curvy: toned
  abs, large breasts, wide hips, thick thighs. Ornate white-gold bikini armor: small sculpted
  breastplate cups, gorget, huge pauldrons, armored gauntlets, a bare midriff, a high-cut armored
  bottom under a long sky-blue tabard panel, thigh-high greaves that leave the upper thighs bare.
  Short silver bob. Two feathered wings, simple halo. A huge kite shield with a sunburst planted
  at her side, the other hand on her hip, a cocky smirk.
- **Liora**, Epic Support, appears early 20s, clearly adult: adult face with makeup and full lips,
  adult figure. *The sweetheart healer.* Soft and curvy: large breasts, wide hips, thick thighs. A
  strapless cream corset minidress with a heart-shaped cleavage cutout and gold embroidery, hem
  high enough to show rose-gold garter straps on white thighhighs, white heels. Ribbons in
  rose-gold twin tails. Two small fluffy wings, flower halo. Golden lyre. Leaning toward the viewer
  with a warm, teasing smile. Never cutesy: no blush-and-head-tilt, no frilly or puffy styling.
- **Uriela**, Rare Striker, appears early 20s, clearly adult. *The sporty one.* Toned with curves:
  large breasts, wide hips, thick thighs. A glossy azure-and-white highleg battle leotard with an
  underboob cutout and a navel window, gold trim, bare shoulders and back, armored gauntlets and
  boots, a short half-cape. High honey-blonde ponytail, confident grin. Long golden spear with a
  sun blade resting over her shoulder. Swept-back wings, thin halo.
- **Nuriel**, Rare Assassin, adult man, mid-20s. *The masked heartthrob.* Lean and muscular:
  defined abs and pectorals. A sleeveless hooded sky-blue scout jacket worn open over a bare
  chest, a thin leather chest harness, low-slung crossed belts on fitted dark trousers, wrapped
  forearms, a white cloth mask over nose and mouth. Messy pale-gold hair. Twin glowing light
  daggers in reverse grip. Small sharp wings, faint halo.

## Infernal (crimson, ember orange, obsidian, gold)

- **Mordessa**, Legendary Striker, appears around 30. *The demon queen.* Voluptuous: huge
  breasts, wide hips, thick thighs. Huge curled black ram horns with a small crown between them;
  long wavy black hair with crimson ends. A black-and-crimson armored dress: corseted gold-filigree
  bodice plunging to the navel, one armored shoulder, skirt slits cut to the hip on both sides,
  garter straps into thigh-high boots. A greatsword wreathed in flame on her shoulder, the other
  hand on her hip. Leathery bat wings, spaded tail. Commanding smirk.
- **Brakka**, Epic Guardian, adult man. *The beefcake.* Enormous, heavily muscled red-skinned
  demon: huge pectorals, abs, thick arms and thighs. Shirtless with a chain chest harness, an
  obsidian armor kilt of plates with glowing magma cracks slung low on the hips, huge molten
  gauntlets. Short thick horns, tusked friendly grin, thick tail. Flexing both arms.
- **Vesper**, Epic Caster, appears late 20s. *The latex succubus scholar.* Hourglass: huge
  breasts, wide hips, narrow waist. Long straight wine-red hair, half-lidded eyes behind thin
  glasses, small curved horns. A glossy black latex catsuit with a cleavage cutout, a navel window
  and hip windows on both sides, opera gloves, a high-collared open-front cape lined in purple.
  A floating hellfire orb in one raised hand, the other adjusting her glasses. Bat wings,
  heart-spaded tail.
- **Imra**, Rare Support, **adult woman**, appears early 20s. *The wild imp.* Lithe and toned
  with an adult woman's curves (large breasts, wide hips) and an adult face with makeup; average
  height for the roster, never drawn small. A crimson patchwork bandeau bikini, a layered loincloth
  panel over the opaque bikini bottom, tribal body paint, bone and gold jewelry, sandals. Short
  spiky orange hair, small horns, pointed ears, toothy grin. Lantern staff with a green-orange
  flame raised overhead. Small bat wings, curly tail.
- **Kessa**, Rare Assassin, appears mid-20s. *The cat burglar.* Athletic and curvy: large
  breasts, wide hips, thick thighs. A sleek black bodysuit unzipped to below the cleavage, a red
  strap harness with o-rings over it, hip windows, a long red scarf, black thigh boots. Black cat
  ears plus small horns, short choppy black hair with a red streak, amber slit-pupil eyes, smug
  fanged smile. Twin curved sickles; back arched like a stretching cat. Long cat tail, no wings.

## Fallen (violet, silver, teal-ash, black)

- **Noctaire**, Legendary Assassin, appears late 20s. *The gothic executioner.* Tall and slender
  with long legs and large breasts. Long silver hair, cold violet eyes, cracked dark halo tilted on
  her head. A black highleg corset leotard open at the sides (sideboob), black lace sleeves, a long
  tattered black front-and-back drape from the hips, silver buckles and chains, heeled thigh boots.
  Tattered black feathered wings with violet tips. A huge crescent scythe with a violet glow; her
  free hand sweeps back her hair. Melancholic allure.
- **Orrin**, Epic Guardian, adult man, around 30. *The broken knight.* Broad, scarred and
  muscular: large pectorals, abs, a scar across the chest. Cracked silver armor stripped down to
  one pauldron and gauntlets, a bare torso wrapped in broken chains, a torn violet cape, fitted
  black trousers on a low-slung belt with his broken halo hanging from it, armored boots. Shaggy
  ash-grey hair, scar over one eye. Chain-wrapped tower shield. Ragged grey wings. Stoic.
- **Sable**, Epic Support, appears late 20s. *The fallen nun.* Curvy: huge breasts, wide hips,
  thick thighs. A black and violet veil, long dark-teal hair. A skin-tight black habit bodysuit
  with a cleavage cutout, corset lacing and silver trim; long black front-and-back tabard panels
  over the opaque suit, open at the hips; black thighhighs on garter straps, heels. A silver
  censer trailing violet smoke. Grey wings, dim halo. Gentle, sad, alluring; head tilted.
- **Lucen**, Rare Striker, adult man, mid-20s. *The flirt.* Lean and toned. A violet-and-silver
  coat worn open over a bare chest, a frilled ascot, tight black leather trousers on a low-slung
  belt, thigh-high boots, a slim rapier, one hand on his hip. Wavy white hair with black tips,
  half-lidded eyes, flirtatious smile. One white wing, one black wing. No halo.
- **Ashra**, Rare Caster, appears mid-20s. *The sleepy witch.* Soft curves: huge breasts, wide
  hips. An oversized grey witch hat with silver star pins; layered violet robes slipping off both
  shoulders; a strapless cropped tube top showing underboob; a long low-slung skirt with high
  slits and a burned hem; ankle boots. Messy grey hair with violet streaks, cracked violet halo.
  A lazy stretch with one arm up, a crooked wand with a violet flame in the other hand. Small
  grey wings.
