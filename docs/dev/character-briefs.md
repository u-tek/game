# Character Briefs (art direction v3.3: maximum allure the exposure filter passes, female only)

These briefs are the **design source** for all art work. They override `data/art_prompts.json` and
the `look` fields in `data/heroes.json` when they disagree (the `look` fields mirror these briefs).

## Content direction

The owner's direction: the v2 designs were "a good start but nowhere near as promiscuous as
possible ... skin tight clothing, body suits ... think big". Every design is pushed to the
**maximum allure the App Store 18+ rating allows**, in the style of the most fan-service-heavy
gacha games. The hard lines below are where that maximum ends. They are never traded for allure.

v3.1 keeps the v3 allure and closes the prompt-level risks found in review: youth-coded tag
clusters on the young-end heroes, slits with nothing opaque under them, a sex-mimicking pose,
uneven safety negatives, two converged designs (Vesper and Sable) and tags split across CLIP chunks.

v3.2 (2026-10-17): the owner asked for a **female-only roster**. Nuriel, Brakka, Orrin and Lucen
are now women. They keep their ids, names, factions, roles, stats, weapons and silhouettes; only
the body, outfit and reveal changed. The art is re-rendered with ComfyUI on the owner's PC and
their NoobAI XL checkpoint.

v3.3 (2026-10-17): the ComfyUI pilot on NoobAI-XL-Vpred-v1.0 showed that this model paints far more
skin than the art farm's Animagine. At the old 0.25 thresholds the exposure filter dropped nearly
every candidate of the v3.2 reveals, flagging clothed underboob, cleavage and highleg hips that a
1:1 review found inside the hard lines. The owner then raised both thresholds to 0.5, the
filter's built-in ceiling ("raise it", 2026-10-17): the content standard is "anything that's not
explicit nudity", as in the 18+ gacha games already on the App Store. The hard lines below are
unchanged and still decided at 1:1 by a person. Following the pilot rule below, each hero keeps her
v3.2 reveal where about half of her candidates pass at 0.5; otherwise her reveal is cut back only
as far as it takes, preferring swaps that keep the allure (a closed glossy leotard instead of an
underboob cutout, a pelvic curtain over a highleg line, thighhighs over bare thighs). Every
cut-back is recorded in the hero's paragraph, her row in the signature map and her `brief_gaps` in
the bible, with the pass counts that justified it.

### What we go for

- **Skin-tight and glossy.** Latex and shiny bodysuits, catsuits, highleg leotards, bikini armor
  and micro-armor that leaves more skin than plate.
- **Cutouts and openings.** Underboob, sideboob, a cleavage window or center opening down to the
  navel, navel windows, hip windows (`hip vent`), open backs, partially unzipped suits,
  strapless and bandeau tops, small opaque cups and gem or armor plates as tops.
- **Straps and legwear.** Harnesses, o-rings, garter straps, thighhighs, thigh boots, body
  chains; very high slits and long front-and-back drapes (`pelvic curtain`) over an **opaque**
  leotard, bodysuit, shorts or bikini bottom.
- **Sheer only over opaque.** Sheer sleeves, veils and drapes are fine; sheer never sits over
  breasts, nipples or the groin unless an opaque layer is under it.
- **Bodies.** Curvier, where it fits the character: large to huge breasts, wide hips, thick
  thighs, narrow waists, toned abs. Body types still vary across the roster (statuesque,
  athletic, soft, tall and slender, lithe).
- **Poses and expressions.** Alluring but **full body, standing, both feet visible**, in the
  3/4 view the rig needs (`docs/dev/art-style.md`): hand on hip, hand in hair, leaning toward the
  viewer, an arm raised, arms crossed, a hip-cocked fighting stance, flexing; seductive smiles,
  smirks, half-lidded eyes. A standing S-curve (chest out, hip cocked) gives the arched-back look;
  the `arched back` tag itself is not used, because it drifts toward all-fours and explicit poses.
- **Female only.** Every hero is a woman (owner, 2026-10-17). Builds still vary, from Brakka's
  muscular amazon to Lucen's slender duelist.
- **Character first.** Each hero keeps a distinct silhouette, palette, weapon and personality and
  stays on-faction. The signature map below keeps the reveals from blurring together.

### Hard lines (never crossed)

- **Adults only.** Every character is an adult with an apparent age of 20 or older: adult body
  proportions, adult facial structure, adult styling and adult cues in every prompt. Never
  childlike bodies, faces, clothing (no school uniforms) or behavior, and never "petite
  child-like" framing. Allure never combines with anything that reads young.
- **No youth-coded clusters.** On the young-end heroes (Liora, Uriela, Imra) the design never
  stacks the signals that read young on Danbooru-trained models: high twin tails with ribbons,
  small wings, small horns, short spiky hair with a fanged or sharp-toothed grin, blush and head
  tilt, cutesy framing. Known young-coded archetypes are negated by name: `mesugaki` (the bratty
  girl), `shortstack`, `petite`, and `blue archive` on every hero with a halo (the Danbooru halo
  tag is dominated by that game's school-age cast).
- **Suggestive, never explicit.** Never: exposed or visible nipples or areolae, including
  through sheer or wet fabric, as "covered nipples" outlines on tight fabric, or with
  nipple-cover-only tops (**no pasties-as-the-only-top designs**); genitals; the pubic area;
  cameltoe; sexual acts or poses that mimic them (no all fours, kneeling, lying or bent-over
  poses). Tops and bottoms are **opaque where it matters**: every slit, curtain and cutout sits
  over an opaque layer or bare non-explicit skin. A slit cut to the hip always shows an opaque
  layer under it, named in the brief and tagged (`leotard under clothes`, `shorts under skirt`);
  no low-slung (`lowleg`) skirts on women.
- **Pipeline guardrails stay on.** The adult cue tags and the required safety negatives that
  `tools/comfy/prompts.py` `enforce()` checks are never removed or weakened. On top of them every
  woman's `negative_extra` upweights covered nipples, nipples, nipple slip, areola slip, cameltoe,
  no panties and pubic hair (Imra keeps `nipples` at the global weight only because a pipeline
  test uses her prompt as a fixture; see her brief gaps). Per design it adds: `impossible clothes`
  (fabric drawn clinging to every contour) for the latex and skin-tight suits, downblouse,
  pantyshot and upskirt for Liora's short strapless dress, no bra for Ashra's tube top, all fours
  and kneeling for Kessa, the young-end terms for Liora, Uriela and Imra, and fishnet top for
  Nuriel (fishnet is legwear only).
- **Prompts fit and stay whole.** Every full-body prompt, art-farm overlay included, fits 2 CLIP
  chunks counted with the real CLIP tokenizer, and no multi-word tag straddles the chunk break
  (a split `partially | unzipped` reads as a bare `unzipped`). See `_heroes_doc` in the bible.
- **Human review decides.** Glossy latex and cutouts are where models slip. Every candidate is
  checked at 1:1 against `docs/dev/art-style.md` section 1. An image that crosses a hard line is
  discarded, never cropped or patched into compliance.
- **Pilot before the roster batch.** Render about 4 seeds each for the riskiest reveals first
  (Seraphiel, Uriela, Noctaire, Kessa, Ashra) and read the exposure filter's drop counts in the
  run manifest. The filter (`tools/artgen/config.py`, both thresholds 0.5 since the owner's
  decision of 2026-10-17, never above its `max_threshold`) is never loosened further to keep a
  render; if most of a hero's candidates drop, her reveal is cut back here first.
- **Rating target:** App Store 18+ (frequent/intense mature or suggestive themes). Google Play's
  policy is stricter about minimally clothed, sexually suggestive poses: if the game goes to
  Android, plan a "standard" outfit for every hero alongside this one.

### Signature map

| Hero | Build | Signature reveal | Silhouette and pose |
|---|---|---|---|
| Seraphiel | statuesque, huge bust | center opening to the navel, highleg leotard, long drapes | six wings, raised hand to a floating sceptre |
| Cassiel | athletic, abs, thick thighs | bikini armor, bare midriff | big pauldrons, kite shield, hand on hip |
| Liora | soft and curvy | strapless corset minidress, deep cleavage, garters | long side braid, lyre, leaning forward |
| Uriela | toned with curves | underboob and navel cutouts in a highleg leotard | ponytail, spear over the shoulder |
| Nuriel | lean, athletic, abs | cropped open jacket over a chest wrap, bare midriff, short shorts, fishnet thighhighs | mask, arms crossed with reverse-grip daggers |
| Mordessa | voluptuous | armored dress plunging to the navel, hip slits over a leotard, garters | ram horns, greatsword on the shoulder, hand on hip |
| Brakka | huge muscular amazon | sports bra under a chain harness, plate kilt over shorts | red skin, flexing |
| Vesper | hourglass | glossy crimson latex catsuit, heart-shaped cleavage window | cape and high collar, glasses, raised orb |
| Imra | lithe, toned | bandeau bikini and loincloth, body paint | shaggy orange mane, lantern staff raised |
| Kessa | athletic, curvy | bodysuit unzipped below the cleavage, strap harness, hip windows | cat ears and tail, twin sickles, fighting stance |
| Noctaire | tall, slender, long legs | sideboob corset leotard, long drape | huge scythe, hand in her hair |
| Orrin | tall, scarred, toned | cut-down breastplate over the cleavage, highleg leotard, bare upper thighs | tower shield, torn cape |
| Sable | curvy | skin-tight black habit with cleavage cutout, tabard, garters | veil and cross, censer, head tilt |
| Lucen | slender, long legs | open coat over a strapless bustier, tight leather, thigh boots | rapier, hand on hip |
| Ashra | soft curves | slipping robes, underboob tube top, slit skirt over shorts | huge witch hat, one arm lazily raised |

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
  adult figure. *The tender temptress.* Soft and curvy: large breasts, wide hips, thick thighs. A
  strapless cream corset minidress with gold embroidery that pushes up a deep cleavage, hem high
  enough to show rose-gold garter straps on white thighhighs, white heels. Long rose-gold hair in
  a loose side braid over one shoulder. A pair of soft white wings, flower halo. Golden lyre.
  Leaning toward the viewer with a warm, teasing smile. Never cutesy: no twin tails or ribbons,
  no small wings, no heart motifs, no blush-and-head-tilt, no frilly or puffy styling.
- **Uriela**, Rare Striker, appears early 20s, clearly adult. *The sporty one.* Toned with curves:
  large breasts, wide hips, thick thighs. A glossy azure-and-white highleg battle leotard with an
  underboob cutout and a navel window, gold trim, bare shoulders and back, armored gauntlets and
  boots, a short half-cape. High honey-blonde ponytail, confident grin. Long golden spear with a
  sun blade resting over her shoulder. Swept-back wings, thin halo. *v3.3 pilot:* kept as designed;
  3 of 6 candidates pass the filter at 0.5 (1 of 12 at the old 0.25).
- **Nuriel**, Rare Assassin, appears mid-20s. *The masked kunoichi.* Lean and athletic: defined
  abs, large breasts, wide hips, thick thighs. A cropped sleeveless hooded sky-blue scout jacket
  worn open over a white chest wrap (opaque, firmly in place), a bare toned midriff, tight black
  short shorts with thigh straps, fishnet thighhighs (legwear only, never a fishnet top), short
  boots, wrapped forearms, a white cloth mask over nose and mouth. Messy pale-gold hair in a
  ponytail, half-lidded eyes. Arms crossed under her chest, twin glowing light daggers in reverse
  grip. Sharp white wings, faint halo.

## Infernal (crimson, ember orange, obsidian, gold)

- **Mordessa**, Legendary Striker, appears around 30. *The demon queen.* Voluptuous: huge
  breasts, wide hips, thick thighs. Huge curled black ram horns with a small crown between them;
  long wavy black hair with crimson ends. A black-and-crimson armored dress worn over a glossy
  black highleg leotard: corseted gold-filigree bodice plunging to the navel, one armored
  shoulder, skirt slits cut to the hip on both sides that show the leotard's high-cut line, never
  bare hip; garter straps into thigh-high boots. A greatsword wreathed in flame on her shoulder,
  the other hand on her hip. Leathery bat wings, spaded tail. Commanding smirk.
- **Brakka**, Epic Guardian, appears in her 30s. *The amazon.* An enormous, heavily muscled
  red-skinned demon woman: huge breasts, defined abs, thick arms and thighs. A black sports bra
  under a chain chest harness, an obsidian armor kilt of plates with magma cracks over black
  shorts, huge molten gauntlets, armored boots. Short messy black hair, short thick horns, small
  tusks, friendly grin, thick tail. Flexing both arms.
- **Vesper**, Epic Caster, appears late 20s. *The latex succubus scholar.* Hourglass: huge
  breasts, wide hips, narrow waist. Long straight wine-red hair, half-lidded eyes behind thin
  glasses, small curved horns. A glossy crimson latex catsuit with a heart-shaped cleavage window
  (her one cutout), opera gloves, a high-collared open-front black cape lined in purple. A
  floating hellfire orb in one raised hand, the other adjusting her glasses. Bat wings,
  heart-spaded tail. Crimson suit and hair keep her Infernal and apart from Sable's black habit.
- **Imra**, Rare Support, **adult woman**, appears early 20s. *The wild imp.* Lithe and toned
  with an adult woman's curves (large breasts, wide hips) and an adult face with makeup; average
  height for the roster, never drawn small. A crimson patchwork bandeau bikini, a layered loincloth
  panel over the opaque bikini bottom, tribal body paint, bone and gold jewelry, sandals. A
  shaggy, shoulder-length mane of orange hair, curved horns, pointed ears, a wild sharp-toothed
  grin. Lantern staff with a green-orange flame raised overhead. Bat wings, curly tail. Her
  review comes first: the imp kit (horns, ears, wings, tail, toothy grin) sits next to the
  young-coded "mesugaki" archetype, so nothing about her is small or bratty.
- **Kessa**, Rare Assassin, appears mid-20s. *The cat burglar.* Athletic and curvy: large
  breasts, wide hips, thick thighs. A sleek black bodysuit unzipped to below the cleavage, a red
  strap harness with o-rings over it, hip windows, a long red scarf, black thigh boots. Black cat
  ears plus small horns, short choppy black hair with a red streak, amber slit-pupil eyes, smug
  fanged smile. Twin curved sickles; standing in a low, hip-cocked fighting stance, chest out.
  Long cat tail, no wings.

## Fallen (violet, silver, teal-ash, black)

- **Noctaire**, Legendary Assassin, appears late 20s. *The gothic executioner.* Tall and slender
  with long legs and large breasts. Long silver hair, cold violet eyes, cracked dark halo tilted on
  her head. A black highleg corset leotard open at the sides (sideboob), black lace sleeves, a long
  tattered black front-and-back drape from the hips, silver buckles and chains, heeled thigh boots.
  Tattered black feathered wings with violet tips. A huge crescent scythe with a violet glow; her
  free hand sweeps back her hair. Melancholic allure.
- **Orrin**, Epic Guardian, appears around 30. *The broken knight.* Tall, scarred and toned:
  large breasts, wide hips, thick thighs. Cracked silver armor stripped down to a breastplate cut
  low over her cleavage, one pauldron and gauntlets, broken chains wrapped around her, a black
  highleg leotard under a torn violet cape, armored thigh-high greaves that leave the upper thighs
  bare, her broken halo hanging from a belt at the hip. Long shaggy ash-grey hair, scar over one
  eye. Chain-wrapped tower shield. Ragged grey wings. Stoic.
- **Sable**, Epic Support, appears late 20s. *The fallen nun.* Curvy: huge breasts, wide hips,
  thick thighs. A black and violet veil and a silver cross necklace, long dark-teal hair. A
  skin-tight black habit bodysuit with a cleavage cutout, corset lacing and silver trim; long
  black front-and-back tabard panels over the opaque suit, open at the hips; black thighhighs on
  garter straps, heels. A silver censer trailing violet smoke. Grey wings, dim halo. Gentle, sad,
  alluring; head tilted. A grown woman's sorrow, never a student nun.
- **Lucen**, Rare Striker, appears mid-20s. *The flirt.* Slender and toned with long legs: large
  breasts, wide hips. A violet-and-silver long coat worn open over a strapless black bustier with
  a deep cleavage, a frilled ascot at the throat, tight black leather trousers on a low-slung
  belt, thigh-high boots, a slim rapier, one hand on her hip. Long wavy white hair with black tips,
  half-lidded eyes, flirtatious smile. One white wing, one black wing. No halo.
- **Ashra**, Rare Caster, appears mid-20s. *The sleepy witch.* Soft curves: huge breasts, wide
  hips. An oversized grey witch hat with silver star pins; layered violet robes slipping off both
  shoulders; a strapless cropped tube top showing underboob; a long skirt with high side slits
  over fitted black shorts, sitting on the hips, with a burned hem; ankle boots. Messy grey hair
  with violet streaks, cracked violet halo. One arm raised lazily overhead, a crooked wand with a
  violet flame in the other hand. Small grey wings.
