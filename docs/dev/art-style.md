# Hero art style guide (painted heroes + HaloRig warp)

Heroes are **painted, full-body anime/gacha illustrations** (raster PNG with transparency,
one image per hero plus face variants), animated by the HaloRig **warp rig**
(`docs/dev/halorig.md` section 8). Briefs: `docs/dev/character-briefs.md` (they override the
`look` text in `src/data/heroes.gd`). Visual direction of the game: "Twilight cathedral"
(`docs/dev/architecture.md` section 7): heroes are shown on a deep indigo `#120e24`.

Vector character art is discontinued. All 15 heroes ship painted art from the art farm
(`docs/dev/art-farm.md`, section "Imported into the game"); Seraphiel's vector stand-in and its
generator were removed when her painted version was installed. To replace a hero's art, swap
`<id>.png` and `variants/*.png`, adjust `<id>.warp_src.json` and rerun `tools/art_warp <id> --regen-masks`.

---------------------------------------------------------------------------------------------

## 1. Content rules: check on EVERY hero review (hard rules, no exceptions)

- [ ] **Adult.** Apparent age 20+ (Seraphiel mid-20s): adult body proportions (7-7.5 heads),
      adult facial structure (defined jaw and cheekbones, mature eyes), adult styling. Never
      childlike bodies, faces, clothing (school uniforms...) or behaviour combined with
      suggestive content. Petite heroes (Imra) still have clearly adult proportions and face.
- [ ] **Suggestive, not explicit.** Allowed: revealing/form-fitting costumes, cleavage, bare
      shoulders, backs, midriffs and thighs, high slits, garters, stockings, corsetry, alluring
      poses and expressions, implied nudity where hair, wings, cloth or light covers.
- [ ] **No** visible nipples, genitals or pubic area, **including through sheer fabric**;
      no sexual acts or poses that mimic them.
- [ ] **Sheer layers only over opaque coverage** (check every sheer panel at 1:1).
- [ ] Each hero keeps a distinct personality, silhouette and role read (allure comes with
      character). Men get the same treatment (open coats, bare chests, toned physiques).
- [ ] Rating target App Store 18+; for Google Play plan a "standard" outfit variant.
- [ ] Original design: no recognizable existing character, logo, costume or brand.

A hero that fails any box is not shipped, whatever its other scores.

## 2. Delivery spec (what the image service must produce)

| Item | Spec |
|---|---|
| Base image | `assets/art/heroes/<id>/<id>.png`, **1024 x 2048**, RGBA, fully transparent background, no shadow on the ground, no text, no watermark, no frame |
| Placement | feet (soles; tiptoes for floaters) at **(512, 1990)**; figure ~1900 px tall; head top ≥ 40 px below the top edge; wings, weapon, hair and halo fully inside with ≥ 24 px margin |
| View | full body, **3/4 view facing screen right**, slight high-angle neutral camera, standing or hovering in a relaxed **contrapposto** (weight on one leg, hips and shoulders counter-tilted, gentle head tilt) |
| Size of the head | crown to chin 250-270 px (7-7.5 heads) |
| Variants | `variants/eyes_open.png` / `eyes_closed.png` (whichever the base is not), `mouth_open.png` (singing/shouting), `smile.png` (eyes + mouth), optional `hurt.png`: **the same image with only the face changed** (inpaint the face; every other pixel identical) |
| Format | 8-bit PNG, sRGB, straight alpha, clean anti-aliased edges, no semi-transparent haze around the figure except intended glows |

### 2.1 Painting for animation (warp-friendly)
- Leave **air gaps** where possible: long hair, capes, ribbons, wings and the weapon should
  read as separate shapes against the background rather than painted over the body. Every
  separate silhouette is a region that can sway.
- Keep arms close to the body or clearly separated; do not cross the weapon over the face.
- Hair falling over the body is fine (it sways as a region), but avoid fine hair strands
  painted across the eyes or mouth (the face overlays would cut them).
- Floating weapons/orbs are great: they bob and thrust as their own region.
- Large soft cloth (trains, sleeves, sheer layers) should hang with clear gravity so the
  spring sway reads naturally.
- Avoid baked motion blur, speed lines and cast shadows on the ground (the game adds them).

## 3. Proportions chart (female standard; male: shoulders +18 %, hips -10 %, limbs +20 % thicker, +4 % height)

Canvas coordinates (1024 x 2048, facing right, 3/4): crown 108, chin 362 (head 254), eyes
y 250 (near eye x 494, far eye x 577), neck pit (540, 448), shoulders near (418, 488) / far
(624, 478), bust line y 600, waist y 835 (narrowest), navel y 880, hips widest y 1050, crotch
y 1150, elbows at the waist (y ~810-830), wrists at the crotch (y ~1060-1100), fingertips
mid-thigh (y ~1230), knees y 1530-1560, ankles y 1900-1920, soles y 1990. Shoulder width
~1.75 head widths (3/4 view: ~230 px between shoulder joints). Hands ~0.7 head long, feet
~0.85 head long. These match `tools/art_body.py` and the rig's standard pivots.

## 4. Look and rendering
- **Quality bar**: premium gacha key-art (Epic Seven / Azur Lane / Idle Angels level): painted
  cel shading with soft gradients, 2-3 tones per material, crisp varied-weight line art
  (thicker outer contours, thin warm interior lines), rim light, glossy eyes, detailed hair with
  strand clumps and highlight bands, ornate costume detail (filigree, gems, embroidery).
- **Lighting**: key light from the **upper right** (the facing side), core shadows on the left
  and under forms; **cool rim light** on the left/back edges; **warm bounce** from the halo or
  weapon glow on hair and shoulders. Same lighting for every hero so the roster matches.
- **Line colour**: dark plum `#2a1d3d` for outer contours; interior lines tinted toward the
  material (warm brown in hair, grey-lilac in white cloth, rose-brown in skin).
- **Faces**: mature anime face, large glossy eyes (two highlights), visible lashes, nose hint,
  defined lips; expressions per brief.

### 4.1 Faction palettes
| Faction | Main | Shadows | Accents | Glow / FX colour |
|---|---|---|---|---|
| **Celestial** | ivory `#fefdff`, gold `#f4c95c`, sky `#8fd2f2` | lilac-white `#e6e1f5`/`#c6bce3`, gold `#de9e38`/`#a6651d` | gems sky `#3a7bc2`, platinum hair `#faefcb` | warm gold `#ffe9a8` |
| **Infernal** | crimson `#c0283a`, ember `#ff7a2e`, obsidian `#1c1420` | wine `#7a1428`, char `#0c080e` | molten gold `#f5b83d`, magma cracks `#ffb347` | ember `#ff8a3d` |
| **Fallen** | violet `#8e6ce0`, silver `#cfd3e6`, teal-ash `#4f8a8b` | dusk `#4b3a7a`, slate `#5a6070` | black feathers `#22202c`, cold glow `#b49cff` | violet `#b48cff` |

Skin (all factions, adjust per hero): base `#fde8dc`, shadow `#f5c6b3`, deep `#e19b8b`,
blush `#f59c9c`. Demons may use red/grey skins from their brief.

## 5. Prompt template for the image service
```
masterpiece, best quality, official gacha game character art, full body, single character,
adult woman, mid-20s, [brief: costume, hair, wings, weapon...], 3/4 view facing right,
contrapposto standing pose, [floating / standing] , cel shading with soft gradients, crisp line
art, rim light from behind left, warm key light from upper right, detailed ornate costume, gold
filigree, glossy eyes, transparent background, centered, entire body visible, feet at the bottom,
no ground shadow
negative: child, loli, young-looking, nsfw, nipples, genitals, see-through over skin, text,
watermark, logo, cropped, cut off, extra limbs, deformed hands, background scenery
```
Then: remove the background (clean alpha), place on the 1024x2048 canvas with the feet at
(512, 1990), and inpaint the face for each variant.

## 6. Rigging a painted hero (summary; spec in halorig.md 8)
1. Copy `seraphiel.warp_src.json`; set pivots (neck top for `head`, between the eyes for
   `face`, hair roots, wing roots, weapon grip, pelvis for `hips`, waist for `chest`).
2. Write region rules (polygons + hair colour ranges), run `tools/art_warp <id>
   --regen-masks`, check the weight overlay (pose test), paint over `masks/*.png` where needed.
3. List the variants under `overlays`; use `rect` to separate eyes and mouth when one variant
   image changes both.
4. Tune springs (long hair from the head: `g` 0.85-0.95), add hero animation overrides in
   `assets/art/heroes/<id>/anim/` only if the shared warp set does not fit.

## 7. Review process and rubric
Each round: `python3 tools/art_review.py <id> rN` (detail ~1100 px, 1:1 face crop, hair
crop, battle ~280 px, card 152 px, portrait 96 px, all on `#120e24`), a pose-test sheet
(`tools/art_preview`, idle / look left-right / attack / cast / ultimate / hit / death /
victory / echo-flipped) and animation sheets + GIFs. Score 1-10, ship at **≥ 8 on every line**
and only with section 1 fully checked:

| # | Criterion | 8+ means |
|---|---|---|
| 1 | Face appeal | mature, attractive, on-brief expression; eyes read at 96 px |
| 2 | Line quality | confident, varied weight, clean edges at 1:1 |
| 3 | Rendering | 2-3 tones per material, form gradients, rim light, metal/gem highlights |
| 4 | Detail density | costume ornament and hair detail at gacha 5-star level, not noisy at 280 px |
| 5 | Anatomy and pose | correct proportions and hands, real contrapposto |
| 6 | Silhouette | instantly readable role and identity at battle size, flipped too |
| 7 | Colour harmony | faction palette, separation from `#120e24` and from other heroes |
| 8 | Rig integrity | no tearing, smearing or visible seams in any pose-test frame; overlays align |
| 9 | Motion feel | idle alive (breath, sway, physics, blinks), actions snappy with clear hit frames |
| 10 | Readability small | battle and portrait sizes read, VFX hooks land on the right spots |
| 11 | Content rules | all of section 1 (pass/fail) |
