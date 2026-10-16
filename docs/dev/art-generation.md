# AI art generation (ComfyUI pipeline and prompt bible)

Hero art is **AI-rendered on the owner's own ComfyUI** (local GPU behind an HTTPS tunnel, see
`docs/dev/comfyui-setup.md`) with an anime SDXL checkpoint, then cut out, placed on the HaloRig
canvas and given expression variants. Delivery spec and review rubric: `docs/dev/art-style.md`.
Character designs: `docs/dev/character-briefs.md` (the design source; it wins over this file).

| Piece | File |
|---|---|
| Prompt bible (style, negatives, 15 heroes, variants) | `data/art_prompts.json` |
| HTTP client + server discovery | `tools/comfy/comfy.py` |
| Workflow graph builders (core nodes only by default) | `tools/comfy/workflows.py`, schemas in `core_nodes.py` |
| Prompt composer + content-rule enforcement | `tools/comfy/prompts.py` |
| Candidates + contact sheet | `tools/comfy/run_hero.py` |
| Face polish, upscale, cutout, canvas placement | `tools/comfy/finalize.py` (image ops in `post.py`) |
| Eyes closed/open, mouth open, smile, hurt | `tools/comfy/variants.py` |
| Fix hands/props/faces by inpainting | `tools/comfy/fix.py` |
| Copy an approved hero into `assets/` | `tools/comfy/install.py` |
| Tests (no server needed) | `python3 tools/comfy/test_pipeline.py` |
| Outputs (generated sources, ignored by Godot) | `art_src/` (see `art_src/README.md`) |

Python 3 standard library + Pillow + numpy only. Every tool takes `--dry-run`.

## 1. Content rules (hard, enforced in code)

From `docs/dev/character-briefs.md`: alluring fan-service up to the **App Store 18+** limit;
**every character is an adult** (apparent age 20+, adult face, proportions and styling);
**suggestive, never explicit**: no visible nipples, genitals or pubic area (including through sheer
fabric), no sexual acts or poses that mimic them.

How the pipeline enforces it (`data/art_prompts.json` → `content_rules`, `tools/comfy/prompts.py`):
- Every composed prompt goes through `prompts.enforce()` before any workflow is built. It refuses
  to send a prompt unless:
  - the positive has an **adult cue tag** (`adult` plus `mature female` / `mature male`, weighted
    lower for early-20s heroes) and the word "adult" in the natural-language line;
  - the positive has **none of the forbidden terms** (nudity, genitals, sex acts, `see-through`,
    `panties`, `loli`, `child`, `school uniform`, `flat chest`, ...; `topless` for women);
  - the negative carries **every required term**: explicit (`nsfw, explicit, nude, nipples,
    areolae, covered nipples, pussy, cameltoe, penis, bulge, pubic hair, sex, see-through`) and
    childlike (`loli, shota, child, underage, aged down, school uniform`).
- Rating tags: Illustrious/NoobAI/Animagine positives use Danbooru's `sensitive` (sexy, no
  nudity) and negate `nsfw, explicit, questionable`; Pony negates `rating_explicit` and uses no
  positive rating (its `rating_questionable` drifts toward nudity).
- Heroes at the young end (Liora, Uriela early 20s; Imra petite) get extra weighted negatives
  (`(loli:1.3)`, `(child:1.3)`, `(aged down:1.2)`) and their natural-language lines say "clearly
  adult ... adult face and adult proportions".
- Sheer fabric is described as "sheer ... over opaque cloth"; `see-through` stays in the negative.
- Model output is still reviewed by a person: `docs/dev/art-style.md` section 1 checklist on every
  hero, at 1:1 on every sheer panel. A failing image is discarded, never "fixed" into compliance
  by cropping.

## 2. Tonight's runbook

Prerequisite: `COMFYUI_URL` and `COMFYUI_AUTH` set in the environment (`docs/dev/comfyui-setup.md`).
Never print or commit the auth value. Commands run from the repo root.

```bash
# 0. sanity: tests (offline) and server
python3 tools/comfy/test_pipeline.py
python3 tools/comfy/comfy.py ping
python3 tools/comfy/comfy.py discover        # checkpoints, LoRAs, upscalers, custom nodes, chosen model + family
#    -> art_src/_server/discovery.json. Check "recommended checkpoint" and its family; if the family
#       is guessed wrong, add --family illustrious|noobai_vpred|pony|animagine to every command.
#       Pin a model for the night:  export COMFYUI_CKPT='<file name from the list>'

# 1. one hero end to end first (Seraphiel), then the rest
python3 tools/comfy/run_hero.py seraphiel --count 8
#    Read art_src/seraphiel/candidates/contact_sheet.png (full body + face crop per seed).
#    Pick on: content rules (section 1) > face appeal > anatomy/hands > on-brief costume > pose
#    (3/4 view facing right, contrapposto, whole figure inside, air gaps for the rig).
#    Nothing good? Re-run with --seed <new start> or adjust data/art_prompts.json, never the rules.

# 2. optional: fix a hand or prop on the chosen candidate (boxes are candidate pixels)
python3 tools/comfy/fix.py seraphiel 101003 --box 300,980,140,170 --prompt "detailed hand, holding scepter"
python3 tools/comfy/fix.py seraphiel 101003 --apply 101801     # -> candidates/seraphiel_s101003_fixed.png

# 3. finalize: face polish, 2x upscale, background removal, canvas placement, portrait
python3 tools/comfy/finalize.py seraphiel 101003            # or the _fixed.png path; add --flip if she faces left
#    Read art_src/seraphiel/final/seraphiel_check.png (cutout over checker / magenta / dark: no halos,
#    no holes in the figure) and seraphiel_boxes.png (face + portrait boxes). If the face box is off,
#    re-run with --face-box x,y,w,h (candidate pixels, brow/hairline to chin).

# 4. expressions (pixel-aligned with final/seraphiel.png; only the face changes)
python3 tools/comfy/variants.py seraphiel --count 3
#    Read art_src/seraphiel/variants/sheet_<name>.png; promote a better try:
python3 tools/comfy/variants.py seraphiel --pick eyes_open=101502

# 5. into the game, then rig (the rig and assets/ belong to the art owner, see architecture.md)
python3 tools/comfy/install.py seraphiel        # copies <id>.png + variants/*.png, prints warp_src hints
tools/art_warp seraphiel --regen-masks           # docs/dev/halorig.md
```

Order for the roster: the three starters (uriela, kessa, lucen), then legendaries (seraphiel,
mordessa, noctaire), then epics, then the remaining rares. Keep one checkpoint and the same
settings for all 15 (consistency). Budget: about 30-60 s per candidate on a mid-range GPU at
the defaults (768x1344, 28 steps, hires 1.5x).

## 3. Tools

All tools: `--dry-run` (send nothing, write each request's exact `POST /prompt` body to
`art_src/_dryrun/<hero>/<step>_s<seed>.json`, use labelled placeholder images so every later step
still runs), model flags `--ckpt --family --sampler --scheduler --steps --cfg --size WxH
--lora NAME[:STRENGTH] --vae --upscale-model --no-hires --hires-mode latent|model
--hires-denoise --timeout`.

- **`comfy.py`**: `Comfy` client. Env `COMFYUI_URL`, `COMFYUI_AUTH` (sent as `Authorization`;
  `user:pass` becomes Basic), optional `COMFYUI_HEADERS` (JSON, e.g. Cloudflare Access tokens),
  `COMFYUI_CA_BUNDLE`. `discover()` reads `/system_stats`, `/object_info` (checkpoints, LoRAs,
  VAEs, upscalers, ControlNets, samplers, custom nodes) and `/models/*`, ranks checkpoints (anime
  SDXL first; refiners, SD1.5, turbo/lightning, photoreal skipped) and picks the family from the
  file name. `upload_image()` (`POST /upload/image`, subfolder `halo_horn`), `queue()` (validates
  the graph against the server's own schema, then `POST /prompt` with a `client_id`), `wait()`
  (polls `/history/<id>` and `/queue`; running timeout, queue timeout, node error messages),
  `download()` (`/view`). CLI: `ping`, `discover [--object-info FILE]`, `queue GRAPH.json` (re-send
  any saved/dry-run graph and download its images).
- **`run_hero.py <id> [--count N] [--seed S]`**: candidates at seeds `seed_base + i`, each with
  `.json` metadata (prompt, negative, seed, checkpoint, family, every setting) and `.api.json`
  (the graph), plus `contact_sheet.png`. `--ref IMG` adds an IPAdapter reference when the server
  has ComfyUI_IPAdapter_plus; `--controlnet NAME --control-image IMG` adds a core ControlNet.
- **`finalize.py <id> <seed|path>`**: optional `--refine-denoise` img2img, face polish
  (crop-inpaint at 1024 px, denoise 0.35), 2x model upscale (`--upscale auto|on|off`), cutout
  (`--cutout auto|local|server`), placement, `--flip`. Writes `final/<id>.png` (1024x2048 RGBA,
  crown y≈108, soles y=1990, axis x=512), `_portrait.png`, `_check.png`, `_boxes.png`, `<id>.json`
  (transform, face box, portrait rect, `warp_src_hints`).
- **`variants.py <id> [image]`**: the hero's `variant_set` by default (`eyes_closed` or
  `eyes_open` for Seraphiel, `mouth_open`, `smile`; `hurt` on request). Outputs
  `variants/<name>.png` (full canvas; alpha identical to the base; only the eyes/mouth region
  differs), `<name>_patch.png/.json`, tries + `sheet_<name>.png`, `variants.json`
  (`warp_overlay_hints` with eyes/mouth rects) and `masks/eyes.png`, `masks/mouth.png`.
- **`fix.py <id> <image> --box x,y,w,h --prompt "..."`**: crop-inpaint any region; `--apply SEED`.
- **`post.py`**: `cutout`, `place`, `finalize` (local only), `facebox`, `sheet` subcommands.
- **`install.py <id>`**: copy an approved hero to `assets/art/heroes/<id>/` (+ variants).

## 4. Model families and sampler defaults (`families` in the bible)

| Family | Detected from file name | Quality block | Sampler | Notes |
|---|---|---|---|---|
| `illustrious` (default) | illustrious, illu, noob, ilxl, wai, obsession | `masterpiece, best quality, amazing quality, very aesthetic, absurdres, newest` at the end, rating `sensitive` | euler_ancestral / normal, 28 steps, cfg 5.5 | NoobAI epsilon is here too |
| `noobai_vpred` | v-pred / vpred | same | euler / normal, 32 steps, cfg 4.5 | adds `ModelSamplingDiscrete(v_prediction, zsnr)` + `RescaleCFG 0.7` |
| `pony` | pony, pdxl, autismmix | `score_9, score_8_up, score_7_up, score_6_up, source_anime` first | euler_ancestral / normal, 25 steps, cfg 7 | clip skip 2 (`CLIPSetLastLayer -2`), negative `score_6, score_5, score_4, source_pony, ...` |
| `animagine` | animagine | `masterpiece, high score, great score, absurdres` | euler_ancestral, 28, cfg 5 | |
| `sdxl_generic` | (only with `--family`) | `masterpiece, best quality, highly detailed, absurdres` | dpmpp_2m / karras, 30, cfg 6 | |

Base size 768x1344 (SDXL bucket close to the 1:2 canvas), hires fix 1.5x to 1152x2016: latent
upscale + denoise 0.5, or, when an upscale model exists, model upscale + re-encode + denoise 0.4.
A sampler the server lacks falls back to euler_ancestral/euler.

## 5. The prompt bible (`data/art_prompts.json`)

Global blocks:
- **style**: tags `official art, detailed shading` (no `cel shading`: it flattens the rendering), soft lighting, rim lighting, intricate details,
  glint` + a sentence (gacha splash-art rendering, crisp varied-weight lineart, warm key light
  from the upper right, cool rim light on the left, glossy eyes, metal/gem highlights).
- **composition**: `full body, standing, contrapposto, looking at viewer, centered` + "whole
  figure from head to both feet, three-quarter view turned to the right, wings/weapon/hair inside
  the frame, plain flat background with no ground shadow".
- **backgrounds**: flat `grey` (Celestial and Lucen: white/gold designs and white hair), `white`
  (dark Infernal/Fallen designs), `green` (chroma fallback). Picked for contrast so the cutout is
  clean; override with `--background`.
- **negative**: quality, anatomy/hands, framing (crops, extra people, scenery, floor, drop shadow;
  left out for face crops), explicit, childlike, text/watermark/signature/logo, style (chibi, 3d,
  realistic), plus per-gender terms (women: `1boy, topless, bare breasts, flat chest`; men:
  `1girl, breasts, female`) and per-hero extras.
- **factions**: palette tags + palette sentence.
- **regions / variants / face_refine**: expression regions as fractions of the face box, denoise
  per variant, default tags for `smile` and `hurt`.

Per hero: `subject` (count, solo, adult cue), `body`, `hair`, `eyes`, `expression`, `head`
(halo, horns, ears, crown, mask), `wings_tail`, `outfit`, `accessories`, `weapon`, `pose`,
`face` (identity tags for face crops), `natural` (one faithful sentence from the brief, with the
apparent age), `negative_extra`, `seed_base`, `background`, `default_eyes`, `variant_set`,
`variants` (per-hero inpaint prompts: `eyes_closed`, `mouth_open`, ...), `loras`, and
`brief_gaps` (choices the brief does not make, such as eye colours, listed so a reviewer can
veto them).

Composition order: Illustrious-style `subject, body, hair, eyes, expression, head, wings/tail,
outfit, accessories, weapon, composition, pose, palette, background, style, quality, rating.
<natural sentence> Colours: <palette>. <composition sentence> <style sentence>`; Pony puts the
score tags first. Duplicate tags are dropped. Hero names are never put in prompts (they would pull
in unrelated existing characters).

| Hero | Age cue | Background | Seeds | Variants |
|---|---|---|---|---|
| seraphiel | mid-20s, `mature female` | grey | 101000+ | eyes_open (base has closed eyes), mouth_open (singing), smile |
| cassiel | mid-20s | grey | 102000+ | eyes_closed, mouth_open, smile |
| liora | early 20s, clearly adult | grey | 103000+ | eyes_closed, mouth_open, smile |
| uriela | early 20s | grey | 104000+ | eyes_closed, mouth_open, smile |
| nuriel | adult man, mid-20s | grey | 105000+ | eyes_closed, smile (eyes only: mouth is masked) |
| mordessa | around 30 | white | 201000+ | eyes_closed, mouth_open, smile |
| brakka | adult man | white | 202000+ | eyes_closed, mouth_open, smile |
| vesper | late 20s | white | 203000+ | eyes_closed, mouth_open, smile |
| imra | early 20s, petite but clearly adult | white | 204000+ | eyes_closed, mouth_open, smile |
| kessa | mid-20s | white | 205000+ | eyes_closed, mouth_open, smile |
| noctaire | late 20s | white | 301000+ | eyes_closed, mouth_open, smile |
| orrin | adult man, around 30 | white | 302000+ | eyes_closed, mouth_open, smile |
| sable | late 20s | white | 303000+ | eyes_closed, mouth_open, smile |
| lucen | adult man, mid-20s | grey | 304000+ | eyes_closed, mouth_open, smile |
| ashra | mid-20s | white | 305000+ | eyes_closed, mouth_open, smile |

Edit the bible to iterate on looks; the tests (`test_pipeline.py`) re-check every hero against
the content rules for every family.

## 6. Consistency strategy

1. **One model, one style block, one settings set** for the whole roster (`COMFYUI_CKPT`,
   unchanged sampler/cfg/steps, same lighting sentence and background logic).
2. **Fixed seeds**: candidates use `seed_base + i`; each candidate's metadata records seed,
   prompt, negative, model and settings, and its `.api.json` re-renders it exactly
   (`comfy.py queue`). ComfyUI noise is seeded per job, so separate jobs (not a batch) keep each
   candidate reproducible on its own.
3. **Derive, don't re-roll**: once a master is chosen, the face polish, upscale, expression
   variants and fixes are all img2img/inpaint passes on that image at low denoise, with the face
   crop inpainted at 1024 px and pasted back through a feathered mask. Variants keep every pixel
   outside the eyes/mouth region and the exact alpha, so the rig's overlays line up.
4. **New poses/outfits** (e.g. a Google Play "standard" outfit): img2img from the master at
   denoise 0.5-0.6, plus `--ref <master>` for an IPAdapter reference (weight 0.6-0.8) when the
   server has ComfyUI_IPAdapter_plus.
5. **Later**: a character LoRA per hero trained on 15-30 curated images (master, variants,
   reference renders), listed in `heroes.<id>.loras` in the bible.

## 7. Workflows (`tools/comfy/workflows.py`)

Graphs are ComfyUI API format (`{"id": {"class_type", "inputs"}}`, links `["id", output_index]`),
validated before sending against the server's `/object_info` (offline: the embedded core schema).

- **txt2img**: `CheckpointLoaderSimple → [LoraLoader…] → [CLIPSetLastLayer] →
  [ModelSamplingDiscrete → RescaleCFG] → CLIPTextEncode ×2 → EmptyLatentImage → KSampler →
  LatentUpscaleBy 1.5 → KSampler (denoise 0.5) → VAEDecode → SaveImage` (or the model-upscale
  hires path: `VAEDecode → UpscaleModelLoader/ImageUpscaleWithModel → ImageScaleBy → VAEEncode →
  KSampler 0.4`). Optional IPAdapter (schema-filled) and core ControlNet.
- **img2img**: `LoadImage → [upscale] → VAEEncode → KSampler(denoise) → VAEDecode → SaveImage`.
- **inpaint**: `LoadImage + LoadImageMask(red) → GrowMask → VAEEncode → SetLatentNoiseMask →
  KSampler → VAEDecode → ImageCompositeMasked (keeps unmasked pixels) → SaveImage`, or
  `VAEEncodeForInpaint` (denoise 1.0) for replacing an object.
- **upscale**: `LoadImage → UpscaleModelLoader + ImageUpscaleWithModel → ImageScaleBy`, or
  lanczos `ImageScaleBy` without a model.
- **background removal** (only when discovered): the first of InspyrenetRembg, RMBG, BiRefNet,
  BRIA RMBG, essentials, easy-use, WAS rembg; its inputs and model-loader provider are filled from
  the server schema; the MASK is saved via `MaskToImage`. FaceDetailer and ControlNet
  preprocessors are reported by `discover` but not required.

## 8. Cutout and placement (`tools/comfy/post.py`)

Local cutout (when no server node): fit a smooth (quadratic) background colour surface, flood
fill from the borders within a colour tolerance (26), clear enclosed background gaps (flat
regions ≥ 24 px across, each < 6 % of the figure's bounding box, so a white dress on white is kept), unmix
anti-aliased edge pixels against the local background (alpha from the best-explaining foreground
neighbour), feather 0.7 px, despill the background colour, drop specks. Placement: soles at
y=1990, crown at y=108 when the face box is known (else figure top to soles 1900 px), body axis
(centre of the feet) at x=512, everything ≥ 24 px from the edges (scaled down or shifted if not;
notes in the meta). Face box: topmost skin-coloured band near the body axis that persists over
several rows (halo rings, gold crowns and blonde hair are outside the skin window; Brakka uses a
red-skin window), head height from the distance to the feet (~7 heads); always check
`_boxes.png` and pass `--face-box` if needed.

## 9. Troubleshooting

- `HTTP 401/403`: `COMFYUI_AUTH` wrong or missing. A 403 from the local egress proxy means the
  tunnel host is not in the environment's allowed domains (`comfyui-setup.md` step 3).
- "returned HTML, not JSON": the tunnel shows a login/warning page (ngrok browser warning is
  already skipped with a header; check auth).
- `server rejected the workflow`: the message lists node and input; usually a model file name
  (pin one with `--ckpt` from `discover`) or a missing custom node.
- CUDA out of memory: `--size 704x1408`, `--hires-mode latent`, or `--no-hires` then
  `finalize.py --upscale on`.
- Washed-out or burnt images on a v-pred model: `--family noobai_vpred`; then try `--cfg 4`.
- Wrong family guessed: pass `--family` (the guess is printed).
- Background left in holes / figure parts removed: `finalize.py --no-holes` or `--tol 18`; for
  repeated trouble change the hero's `background` in the bible and re-render.
- Ground shadow or tail below the feet: `finalize.py --feet-y <soles y in candidate pixels>`.
