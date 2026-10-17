# Art farm: AI hero art on GitHub Actions CPU runners

Painted, full-body anime hero art rendered on free GitHub-hosted runners (the repo is public), for
when the owner's ComfyUI PC (`docs/dev/comfyui-setup.md`) is unreachable. One parallel job per hero
(or per chunk of seeds, or per final seed), results merged into the orphan branch
**`art-gen-output`**, which a session without GPU or Hugging Face access can `git fetch`.

| Piece | File |
|---|---|
| Workflow (plan → gen matrix → sheets → publish) | `.github/workflows/art-gen.yml` |
| Input validation + job matrix | `tools/artgen/plan.py` |
| Renderer (candidates / final / bench) | `tools/artgen/gen.py` |
| SDXL on CPU (diffusers, ComfyUI-compatible prompt weights) | `tools/artgen/sdxl.py`, `sdxl_chunks.py` |
| Prompt style overlay (in memory, through `enforce()`) | `tools/artgen/style.py` |
| Effective steps, time estimates / per-stage memory | `tools/artgen/schedule.py` / `memstat.py` |
| Final-mode cutout (isnet + holes + ground shadow) | `tools/artgen/cutout.py` |
| Exposure filter (fail closed, canary) + upload gate | `tools/artgen/safety.py` |
| Contact sheets (WebP) | `tools/artgen/sheet.py` |
| Sheets job: verify artifacts, filtered sheets, bundle | `tools/artgen/collect.py` |
| Publish job: stdlib-only merge + push to `art-gen-output` | `tools/artgen/publish.py` |
| Model, licences, presets, styles, limits | `tools/artgen/config.py` |
| Offline tests (fakes, no torch, no network) | `python3 tools/artgen/test_artgen.py` |

Prompts are **not** duplicated: `gen.py` imports `tools/comfy/prompts.py` (`full_body`, `face`,
`variant_spec`, `enforce`, family `animagine` from `data/art_prompts.json`) and `tools/comfy/post.py`
(edge treatment, canvas placement with the soles at y=1990, portrait, contact sheets), plus small
helpers from `pipeline.py` and `variants.py`. Nothing in `tools/comfy/` or the bible is changed by
the farm; the style overlay works on an in-memory copy.

## 1. Run it

GitHub → Actions → **Art farm** → Run workflow (branch `claude/game-planning`), or the GitHub API /
MCP `actions_run_trigger` with `workflow_id: art-gen.yml`:

| Input | Meaning |
|---|---|
| `mode` | `candidates` (previews to pick from), `final` (chosen seeds: hires, face polish, cutout, variants) or `bench` (s/step only, no images) |
| `heroes` | `seraphiel,cassiel` or `all` (final: optional filter on the `seeds` keys; bench: the hero whose prompt is timed) |
| `count` | candidates per hero, 1-12 (seeds `seed_base + i`, or from `seeds` `{"hero": first_seed}`); bench: jobs, 1-3 |
| `seeds` | final: `{"seraphiel": {"seeds": [101000], "run": "<candidate run dir>", "flip": false}}` (the run is **required**) |
| `preset` | `standard` (default, Animagine XL 4.0 model card) or `draft` (opt-in) |
| `style` | `farm` (default overlay, section 2) or `bible` (the bible as written). **Every production run used `bible`**: the farm overlay raised the exposure scores (section 6), so pass `style=bible` |
| `dtype` | `fp32` (default) or `bf16` (candidates and bench only; final refuses it) |
| `per_job` | candidates per job (0 = one job per hero; default 1 = one image per job, the most parallel) |
| `label` | folder label (`[a-z0-9-]`, 40 chars) |

Fetch the results here:

```bash
git fetch origin art-gen-output
git worktree prune
git worktree add <scratchpad>/artgen-out origin/art-gen-output     # later: git -C <scratchpad>/artgen-out checkout --detach origin/art-gen-output
ls <scratchpad>/artgen-out/runs/                                    # <run id>-<mode>[-label]/<hero>/...
python3 tools/artgen/sheet.py <scratchpad>/artgen-out/runs/<run>    # re-draw sheets locally if needed
```

A run folder holds `index.json` (jobs, CPU, exit codes, timings, per-stage memory, filter
statistics, missing jobs), `filter_manifest.json`, `overview.webp` and per hero
`contact_sheet.webp` plus:
- candidates: `<hero>_s<seed>.webp` (preview, WebP q95) + `<hero>_s<seed>.json` (prompt, negative,
  style, seed, model, preset settings, dtype, render timing, framing flags (`canvas_fit`: `SMALL nn%`
  when the composition would fill under 90 % of the canvas spec height), filter scores, and
  `repair` + `cover_prompt` when the image was published after a cover repair, section 3);
- finals: `final_s<seed>/` with `<hero>_hires.webp` (after the hires pass), `<hero>_source.webp`
  (after the face polish, before the cutout), `<hero>.png` (1024x2048 RGBA canvas, soles at
  512,1990), `_portrait.png`, `_check.webp` (cutout over checker/magenta/dark), `_boxes.webp`,
  `<hero>.json` (live status, source candidate + sha256, transform, face box, `spec` report,
  `warp_src_hints`, every stage with timing and memory), `variants/<name>.png` + `_patch.png/.json`
  + `variants.json` (`warp_overlay_hints`), `masks/<region>.png`, `variants_sheet.webp`;
- `job_<key>.json` per job: CPU model, library versions, engine dtype/threads/VAE config,
  download/load/encode times, per-stage seconds, steps, s/step, VmHWM, errors, exit code.

Picking: content rules (`docs/dev/art-style.md` section 1) > face > anatomy/hands > costume
fidelity to `character-briefs.md` > pose (3/4 facing right, contrapposto, whole figure, air gaps).
A candidate facing left gets `"flip": true` in the final seeds.

Exit codes of `gen.py`: 0 ok, 2 bad arguments (including a refused preset), 3 exposure filter
unavailable (nothing rendered), 4 prompt refused by the content rules (nothing rendered), 5 a
seed/stage failed or was skipped for time (finished stages are still uploaded), 6 final source
candidate missing or invalid (nothing rendered).

## 2. How it renders

- **Model**: `cagliostrolab/animagine-xl-4.0` diffusers folders (fp16 files upcast on load, about
  7 GB, cached with `actions/cache` as `artgen-hf-animagine-xl-4.0-v1`, 6.38 GB, saved by run
  38831256710; with the pip caches about 7 of the repo's 10 GB cache). No LoRA. Prompts are
  encoded first with both CLIP encoders, then the encoders are freed before the UNet loads (16 GB
  runners). Prompt weights and chunking follow ComfyUI (75-token chunks, words kept whole,
  `(tag:w)` as `z_empty + (z - z_empty) * w`, positive/negative aligned by repetition), so the
  bible's prompts mean the same here as on ComfyUI.
- **Settings** (after the owner's "make sure you're using the correct cfg"; the values below are
  Claude's choice from the model card, and the owner never asked for 832x1216): Animagine XL 4.0's
  model-card settings for every render, candidates included: Euler Ancestral, CFG 5, 28 steps,
  832x1216 portrait, quality tags at the end (the bible's animagine family). Accepted cost: about
  25-40 min per candidate on these CPUs.

| Preset | What | UNet passes per image |
|---|---|---|
| `standard` (default, candidates and every final pass) | Euler a, 28 steps, CFG 5, 832x1216 | 56 |
| `draft` (explicit opt-in only) | DPM++ 2M Karras, 14 steps, CFG 5, 832x1216 | 28 |

  The Lightning/LCM presets are gone: on animagine 4.0 they washed the images out and at CFG 1
  switched the negative prompt off (section 3). CFG outside 4-7 is refused in `plan.py`, `gen.py`
  and the engine.
- **dtype**: an explicit run-level input, `fp32` by default, so every job of a run renders the
  same way regardless of its CPU. `bf16` (UNet only; the VAE always encodes/decodes in fp32 through
  our own path) is for candidates and bench only; img2img/inpaint and `mode=final` refuse it.
  Benchmark it with `mode=bench` before using it.
- **Style overlay** (`style=farm`, default; `style.py`, recorded in every metadata file):
  - a dark slate background (`dark grey background`, rgb 70,72,80) for heroes whose bible
    background is grey and whose palette has white (Seraphiel, Liora, Uriela, Nuriel; Lucen keeps
    grey): white hair, wings and gowns melt into a light grey otherwise (the draft candidate's
    background measured 150,157,167);
  - `game cg, shiny hair` in the style slot; `(dramatic lighting:0.8), (from side:0.5),
    (detailed face:1.1)` on the full body (`from side` at 0.5 with `looking at viewer` is the 3/4
    view cue); `cel shading` is dropped if a bible ever has it again;
  - weapon tags starting with `floating ` weighted 1.2, and `holding staff, holding weapon` in the
    negative for a floating weapon nothing holds (Seraphiel's sceptre was held across the body);
  - negatives `shadow, floor, reflection, flat color, low contrast, washed out, sketch`;
  - **exposure hardening** (added after run 38844272140, where the exposure filter dropped both
    v3-outfit Seraphiel candidates: NudeNet breast 0.38 and 0.48, anime `nipple_f` 0.44), for every
    hero, on the in-memory copy only (`data/art_prompts.json` and the briefs are not edited):
    - weighted explicit negatives at the **front** of every farm negative (full body, face polish,
      variants, cover repair); `join_tags` keeps the first copy of a tag, so these weights replace
      the bible's unweighted ones. Women: `(nipples:1.5), (areolae:1.5), (nude:1.4), (topless:1.4),
      (nipple slip:1.4), (nsfw:1.3), (covered nipples:1.3)`. Men: `(nude:1.4), (penis:1.5),
      (nsfw:1.3), (bulge:1.3), (pubic hair:1.3)` (no `topless`: the men are shirtless by design);
    - the rating tag `sensitive` is added if a prompt lacks it (the bible's family already has it);
    - tag swaps for the two tags that combine into slips: `huge breasts` -> `large breasts`;
      `center opening` / `opening to the navel` / `open to the navel` / `navel opening` ->
      `plunging neckline, gold filigree panels` (the metal of the hero's outfit or palette,
      silver for silver heroes): the panels are the opaque-coverage cue;
    - final mode applies the same swaps and negatives to the candidate prompt it reuses (farm
      candidates only).
  Every composed text still goes through `gen.checked()` (`lint` + `enforce` against the real
  bible). `style=bible` renders the bible exactly. Positives stay at 2 CLIP chunks (144-146 of 150 tokens with
  the current bible; the tests allow 3 if an outfit rewrite grows them).
- **Final** per chosen seed, starting from the **published candidate preview** (downloaded from
  `raw.githubusercontent.com/<repo>/art-gen-output/runs/<run>/<hero>/<hero>_s<seed>.webp/.json`
  plus the run's filter manifest; the sha256 must match the filter record, the candidate must be a
  passed `candidates` image of that hero/seed/size). Missing or invalid: exit 6, nothing rendered.
  `--no-source` (local and tests only) renders the base from the bible instead. The candidate's own
  positive is reused; its negative is joined with today's. Each stage is published through the
  filter as soon as it is done, with the live `<hero>.json` (`status`):
  1. **hires**: Lanczos x1.5 to 1248x1824 (bible `hires.scale`), img2img Euler a / CFG 5 at
     denoise 0.4 for **20 effective steps** (bible `hires.denoise_model` / `steps`). Memory: the
     UNet is released, the upscaled image is VAE-encoded untiled, the UNet loads, samples, is
     released again, and the result is decoded **untiled** (no tile seams); tiled only when
     MemAvailable is below 7 GB. → `_hires.webp`.
  2. **face polish**: face box from the deepghs anime face detector, accepted only when plausible
     for a standing full-body figure (centre in the top 30 % of the figure, height 2.5-20 % of it,
     inside the figure: `gen.face_problem`); crop inpaint at 1024 px, bible `face_refine.denoise`
     (0.35), **16 effective steps**. → `_source.webp`. The skin heuristic
     (`post.estimate_face_box`) is NOT used for inpainting: on the real s101000 hires it landed
     inside the halo above the head (and on other art on the chest), where a "face" polish would
     paint a second face. No usable detector box = no face polish and no variants; the canvas is
     placed by proportions (head top unknown in `spec`), the seed is marked `done with errors`
     and the job exits 5.
  3. **cutout + canvas**: `cutout.artgen_cutout` = rembg `isnet-anime` mask, minus enclosed
     background (halo ring, wing gaps: `post.remove_background`'s colour flood + holes, within 12 of
     the fitted background), minus isnet's background-coloured haze (mask ≤ 0.5, and half-sure
     0.5-0.9 zones within 18 of the background in blobs ≥ 5 px across, never thin seams), minus
     **pockets** (enclosed background too small for the holes: between halo spikes and the crown,
     hair strands, wing and arm; flat 7x7 cores within 4 of the fitted background where isnet is
     not saturated, grown within 12, not on a near-white backdrop where white highlights would
     match), plus **detached props** isnet drops entirely (a floating orb: solid blobs the colour
     flood calls figure, > 80 off the backdrop, isnet < 0.05 throughout, within 10 % of the figure
     height from it, off the image border, not starting in the bottom 12 % of the figure, at least
     0.15 % of the image, at most 3 of them (more = a busy backdrop, none kept)), minus the ground
     shadow (bottom 15% of the figure, background chromaticity, 0.06
     tolerance where isnet is unsure because painted shadows are cooler than the backdrop, at
     35-97% of its luminance, flat on the floor, seeds up to 3 px inside a hard edge), then
     `post.alpha_from_mask` edge unmixing/despill and `cutout.fill_edge_dips` (the anti-aliased
     pixel between dark line art and a light fill can have the backdrop's colour; unmixing made it
     a hole and the outline beyond it a dropped speck: beaded edges; then stray specks without a
     solid core go, loose hair strands with >= 24 opaque px stay); `post.finalize_local` places
     it. Before rendering, `cutout.canvas_fit` measures how much of the spec height the source's
     composition can fill (`source_fit`, a `::warning::` under 90 %). On run
     38844269897's s101000 source the first version left semi-transparent grey patches between the
     halo and the crown, opaque grey gaps between hair strands and the whole cool-grey floor shadow
     (16 of ~11 000 px found); see section 6. An automatic
     `spec` report checks 1024x2048 RGBA, soles at 1990, head top ≥ 40, margins ≥ 24.
     → canvas, `_portrait.png`, `_check.webp`, `_boxes.webp`.
  4. **variants** (the hero's `variant_set`): crop inpaint of the eyes/mouth region at 768 px,
     **14 effective steps**, bible per-variant denoise, over the canvas flattened on the
     *measured* background; alpha and every pixel outside the feathered region identical to the
     base (`variant_alignment` in `variants.json`). Each variant is isolated: an error is logged,
     recorded and the next one runs (exit 5). `variants/candidates/` only with `--variant-tries > 1`.
  5. `variants_sheet.webp`.
  Deadline checks (time estimates from the measured s/step, refined after every stage) come
  before the hires, the face polish and each variant; `--max-minutes 270` inside the 300-min job.
- **Effective steps**: diffusers img2img/inpaint run `int(num_inference_steps * strength)`
  steps; ComfyUI's `steps` is the number actually run. The engine therefore asks for
  `schedule.total_steps_for(effective, strength)` (20 at 0.4 → 50 scheduled, 20 run) and records
  `steps_effective`, `num_inference_steps` and `steps_run`.
- **Memory per stage**: `memstat.reset()` (writes 5 to `/proc/self/clear_refs`) before each
  sampled stage, so `vmhwm_gb` is that stage's own peak (sampling + decode); `ru_maxrss` only
  ever showed the 14 GB load transient. `job_<key>.json` `stage_mem` lists them.
- **Bench** (`mode=bench`, 1-3 jobs): fp32 at 4 then 2 threads, 3 steps each at 832x1216 with the
  preset's sampler and CFG, no decode, no images; then bf16 at the faster thread count on CPUs
  with avx512_bf16/AMX. Only `job_<key>.json` (`bench`) is written.

## 3. Safety (hard rule: the repo is public)

Content rules from `docs/dev/character-briefs.md`: alluring up to App Store 18+, every character
clearly an adult, never explicit.
- **Prompts**: composed only by `prompts.full_body` / `prompts.face` (through the style overlay),
  and `gen.checked()` runs `prompts.lint` + `prompts.enforce` again on every prompt right before it
  is encoded (including prompts read back from candidate metadata). Adult cues, forbidden terms and
  the required explicit/childlike negatives are enforced.
- **Negatives are always active**: CFG must be > 1 for diffusers to use the negative prompt at
  all, so CFG is held to 4-7 at three places (`plan.py`, `gen.py` argument check, and the engine's
  `_common`, which also refuses to sample without negative embeddings and always passes them). The
  exposure filter cannot judge apparent age; adult-only rests on `enforce()`'s positive cues and
  childlike negatives (active only because of this guard) plus the human review.
- **Exposure filter** (`safety.py`) on the runner, before anything is uploaded: NudeNet 3.4.2
  (pip, MIT) **and** the deepghs anime censor-point detector (YOLOv8 trained on anime art), each
  on the whole image plus overlapping tiles at two scales; the raw per-class maximum over every
  anchor (no NMS/argmax) must stay below 0.25 for exposed breast, genitalia, anus and buttocks
  (NudeNet) and nipples/genitals (anime detector). A detector error, unreadable image or
  non-finite score drops the image; a detector that cannot load stops the job before rendering.
  Dropped images are deleted immediately; only their name, scores and reason are logged. Never
  loosen the threshold to save a render: render more candidates.
- **Cover repair** (`gen.publish_screened`, `repair.py`, `config.REPAIR`; candidates and the
  final's hires, source and canvas stages; the RGBA canvas is inpainted flattened on its measured
  background and keeps its own alpha outside the repaired regions; inside them (grown 12 px) it is
  cut out again from the repaired image (`gen.recut_regions`, same isnet + `artgen_cutout`), because
  the inpaint can paint backdrop where the figure was (run 38864019250: an opaque grey patch where
  a forearm had been) or figure where the backdrop was; its portrait and review images are drawn
  again from the repaired canvas): when the filter flags an image, the boxes of the flagged
  classes (plus any watched class at >= 80 % of its threshold) are taken from every view of the
  check (`ExposureFilter.flag_boxes`: anchors at >= half the threshold, NMS per class, mapped back
  to image pixels; NudeNet's padded-square input and the anime detector's stretched input are both
  handled). Each box grows by 25 % of its size on every side (at least 48 px), overlapping boxes
  merge, and only those rectangles are inpainted, in square crops of 2x their size (at least
  320 px) at 768 px, denoise 0.6, **14 effective steps**, Euler a / CFG 5, seed = image seed + 700
  + 10 x pass + crop, with `style.cover`: the hero's identity and outfit without its exposure-prone
  tags (cutouts, openings, `cleavage`, `topless`...) plus the outfit's opaque material (`white
  glossy fabric, gold filigree panels, clothed` for Seraphiel) and the hardened negative. The
  repaired file then goes through the **full** filter again (same thresholds, every view); only a
  passing file is published, with `repair` in its pass record and in the metadata (original
  scores, every pass's boxes, regions, crops, seeds, timings and scores). At most 2 passes; more
  than 4 separate regions, regions over 20 % of the image, a detector that cannot localise, a
  filter error, the time budget or `--no-repair` / a bf16 run (inpaint is fp32 only) mean the image
  is dropped as before. The unrepaired original is deleted by the filter in the work dir and never
  reaches the upload dir. In final mode a hires or source image that is still flagged stops the
  seed (exit 5): the canvas would be cut from it. Cost: about 10 min per crop on the runners (one
  crop covers both breasts), at most 2 passes.
- **Self-test** (every gen job, and the sheets job): a flat grey image must pass, a forced
  detector error must drop, and the **sensitivity canary** must pass with scores inside fixed
  bands (NudeNet FEMALE_BREAST_EXPOSED 0.10-0.25, anime detector max 0.02-0.25). The canary is the
  already-public, filter-passed borderline candidate
  `runs/38832421932-candidates-bench-draft/seraphiel/seraphiel_s101000.webp` (measured 0.2259 /
  0.1053; reproduced exactly by NudeNet on another CPU). It is **not** committed to the code branch:
  `safety.fetch_canary` loads it at run time (env `ARTGEN_CANARY_FILE`, else
  `git show origin/art-gen-output:<path>`, else the raw URL) and checks its sha256. A detector that
  silently returns near-zero scores fails the self-test (closed). If the canary cannot be fetched,
  only the canary is skipped, with a `::warning::` line; the rest of the self-test still applies.
- **Upload gate**: renders happen in a work dir outside the checkout, which is never uploaded.
  Only `artgen_out/` is uploaded, after `safety.py verify` deleted any file without a pass record
  (path + sha256), any non-.png/.webp image and anything that is not .json.
- **Sheets job** (`contents: read`, no token; pip packages allowed): re-verifies every artifact's
  files against that job's manifest (sha256; the images are not re-scored, they passed on the gen
  runner), re-runs the detectors only on the contact sheets it draws (no filter = no sheets), runs
  a last `verify` and uploads one `farm-bundle` artifact.
- **Publish job** (the only job with `contents: write`): no setup-python, no pip, no cache; the
  runner's system `python3` runs `publish.py`, which imports only the standard library (a test
  enforces it). It re-checks every image's sha256 against a passing manifest record plus the
  PNG/WebP magic bytes, deletes anything else, makes a partial sparse clone of `art-gen-output`,
  **merges** (adds/replaces files, merges `filter_manifest.json` and `index.json`, never deletes
  published files, so a re-run or a re-run after the 3-day artifact expiry cannot remove images),
  runs a final gate over the whole run folder (any image without a matching record → nothing is
  pushed) and pushes (fetch/reset/re-apply on a race, 6 attempts). The token reaches git only
  through `GIT_CONFIG_*` environment variables of the git processes.
- **Workflow hygiene**: `workflow_dispatch` only (people with write access); inputs reach scripts
  through env vars and are validated by `plan.py` (hero ids from the bible, bounded integers, JSON
  seeds, final seeds must name a `<run id>-candidates...` run, label reduced to `[a-z0-9-]`);
  `permissions: {}` at the top; `persist-credentials: false` on every checkout; every action pinned
  to a commit SHA; `overwrite: true` on uploads (a re-run replaces its artifact instead of failing
  with 409); no `${{ }}` inside `run:` (tests check all of this).
- A person still reviews every image against `docs/dev/art-style.md` section 1 before it ships.
  The filter is an automatic net, not the review.

## 4. Licences

| Item | Licence | Where recorded |
|---|---|---|
| animagine-xl-4.0 | CreativeML Open RAIL++-M (commercial use allowed, use restrictions) | every image's JSON (`model`) |
| LoRAs | none used (Lightning/LCM presets removed; DMD2 never: non-commercial) | |
| rembg / isnet-anime | MIT / Apache-2.0 | pipeline only |
| NudeNet, deepghs detectors | MIT / see their model cards | pipeline only |

## 5. Limits

- **Concurrency**: one run per mode at a time (`concurrency: art-farm-<mode>`, queued, never
  cancelled), so a candidate round and a final round can overlap; `max-parallel: 16` keeps about
  4 of the account's 20 concurrent jobs free for CI and `ios.yml`. Limits: 60 candidate jobs,
  16 final jobs, 3 bench jobs, 4 final seeds per hero.
- Jobs time out at 300 min; `gen.py --max-minutes 270` skips later seeds/stages and still uploads
  what is done (exit 5, `::warning::` in the log).
- This is heavy use of free Actions minutes for the repo's own assets: keep rounds bounded.

## 6. Measurements

Runner CPUs vary per job (AMD EPYC 7763 Zen 3, 9V74 Zen 4, 9V45 Zen 5), all 4 vCPU on 2 physical
cores, 15.6 GB RAM + 2 GB swap. Measured at 832x1216, fp32, 4 threads (job setup adds about 2-3
min: install, model cache restore or 25-60 s download, loads):

| Run | Settings | CPU | s/step | Decode | Image |
|---|---|---|---|---|---|
| 38831256710 smoke | Lightning 8 steps, CFG 1 (1 UNet pass/step) | Zen 4 9V74 | 39 | 71 s | 384 s |
| 38832424485 bench-l8cfg | Lightning 8 steps, CFG 1.8 | Zen 3 7763 | 86.8 | 85 s | 779 s |
| 38832421932 bench-draft | DPM++ 2M Karras 14 steps, CFG 5 | Zen 5 9V45 | 60.0 | 34 s | 874 s |

With CFG (2 UNet passes per step) a step costs about 60 s (Zen 5) to 87 s (Zen 3); Euler a costs
the same per step as DPM++. Filter outcomes so far: Lightning 2 of 3 dropped (breast 0.276 and
0.366), draft 0 of 1 (0.226); one overview sheet dropped as a false positive (anime censor
0.273). Cleavage-heavy designs score near the 0.25 threshold, so render more candidates.

**Standard preset, v3 outfits (before the exposure hardening), same seeds 101000/101001:**
- 38844272140 `style=farm`: both dropped (NudeNet breast 0.384 / 0.481, anime `nipple_f` 0.444);
  75.9 s/step (Zen 4 9V74, 2176 s per image) and 84.7 s/step (Zen 3 7763, 2431 s); VmHWM 14.0-14.2 GB
  (the 832x1216 decode, untiled).
- 38844281818 `style=bible`: both passed (0.198 / 0.213; `nipple_f` 0.165 / 0.068); 77.0 s/step
  (9V74) and 56.2 s/step (Zen 5 9V45, 1599 s). Same seeds and outfit: the farm overlay (dark
  background, dramatic/rim lighting) raised the exposure scores, hence the hardening above.

**First final (38844269897, s101000 of 38832421932, Zen 4 9V74, fp32, code before the cover
repair):** text encode 21 s; UNet load 25 s (load peak 14.2 GB); hires 1248x1824, 20 of 50 steps,
**188.7 s/step, 3977 s** (66 min), VAE encode untiled (VmHWM 9.1 GB), decode untiled 116 s with 7.4
GB available, stage VmHWM **13.98 GB**; face detector box 0.86 (plausible); face polish 1024 px,
16 of 46 steps, **82.0 s/step, 1387 s**, VmHWM **14.46 GB** (UNet reload 18 s); isnet download 2 s +
cutout 10 s. The canvas was then **dropped** (NudeNet breast 0.2598 in a 1024 tile: the 0.2259
canary image, rescaled by 0.83 and flattened on grey) and with it the variants, so the job ended at
91 min, exit 5; `_check.webp` / `_boxes.webp` were dropped as anime-detector false positives
(`penis` 0.41 / 0.73 on the review sheets). The canvas cover repair was added after this run.
`spec`: the s101000 composition is too wide (wings + diagonal sceptre), scaled 0.83 to fit 1024
px, figure 1445 px tall instead of ~1900, crown at y=655 instead of 108.

**Second final (38852819142, same source, code 56c30c8 with the canvas cover repair):** hires
144.2 s/step (48 min sampling, VmHWM 13.06 GB), face polish 60.6 s/step (16 min, 14.03 GB),
cutout 8 s; the canvas scored NudeNet breast 0.2591 (1024 tile), so the cover repair ran on it:
pass 1 (one 492 px crop over the chest, 509 s) raised it to 0.2862, pass 2 (507 s) passed at 0.2408;
then three variants at 32.6-33.9 s/step (469-489 s each, 13.85 GB). Job about 110 min, exit 0.
Checked here (`git fetch`, composites on #120e24 and white):
- variants: alpha identical to the canvas, RGB changed only inside the eyes / mouth / eyes+mouth
  regions (2155 / 745 / 3430 px), `variant_alignment` clean; expressions match the base;
- soles at y=1990, figure centred (bbox centre x 512.5), portrait 512 px head-and-shoulders;
- the repair changed the design where it painted: a gold gorget with a gem replaced the bare
  sternum and the hand resting on the chest became a gold vambrace (that hand is gone). It works
  as designed, but it rewrites art: pick sources whose filter scores are well under 0.25 (this
  source is the 0.2259 canary itself), so the canvas, which the detectors see at a new scale, does
  not need it;
- cutout defects, reproduced locally on the same source and fixed in `cutout.py` afterwards:
  semi-transparent grey patches between the halo and the crown, opaque grey gaps between hair
  strands and between a wing and the hair, the cool floor shadow under the feet (2 px removed), and
  beaded white wing edges (see section 2, step 3);
- filter drops: `_check.webp` (NudeNet 0.2588 on the checker composite, anime `penis` 0.42),
  `_boxes.webp` (`penis` 0.73), `mouth_open_patch.png` (NudeNet 0.41 on a 52x39 crop) and
  `smile_patch.png` (anime `pussy` 0.37): false positives on review images and tiny crops; the
  import uses `variants/<name>.png`, which all passed;
**Third final (38864019250, code 3938fb2: the cutout fixes):** hires 187.1 s/step (62 min), face
polish 80.6 s/step (23 min), variants 43.9 s/step (11 min each), job about 135 min, exit 0. The
canvas needed one repair pass (0.2575 before); halo, hair gaps and feet clean (shadow 11 356 px
removed, background-coloured edge pixels 2.3 % instead of 4.3 %), variants aligned as before. The
repair again removed the hand on the chest and painted backdrop where the forearm had been, which
the old alpha kept as a 464 px opaque grey patch: hence `recut_regions` (checked locally on this
canvas with isnet: the patch goes, 865 px cleared, 54 px added) and the speck pass.
- `spec` still fails on the composition (figure 1445 px, right margin 22 px after the width fit).
  `cutout.canvas_fit` now predicts this before any render: every published 832x1216 Seraphiel
  candidate fills only 75-77 % of the spec height, so candidates get a `SMALL nn%` sheet flag and
  a final logs a warning.

**Production finals (38881543229 `final-round1-v3`, code 105e7a4, the 15 round1-v3 picks, style
bible):** 13 canvases with variants, 2 dropped. Jobs 83-143 min (hires 122-214 s/step, face
polish 52-98, variants 27-53, cover repair 46-55; the spread is the runner CPU), VmHWM 13.8-14.65
GB. Canvases: 1024x2048 RGBA, soles at 1989-1991, every figure width-limited at 70-89 % of the
spec height (margins 22-24 px). Cover repairs: canvas for seraphiel, liora, brakka, ashra (2
passes each), hires for cassiel. Dropped: orrin's canvas (anime `pussy` 0.319 on the bare sternum
under the chest chain, a false positive; the two repair passes raised it to 0.49) and sable's
source (anime `pussy` 0.2515, then NudeNet breast 0.34 / 0.29 after the repairs). The renders are
deterministic across runner CPUs (two runs of the same hires differ by 0.14 mean / 13 max), so a
plain re-run repeats a drop. Findings checked here: the repair recoloured brakka's chest (red to
orange) and replaced liora's visible lace bottom under the hem with skin shading; vesper's floating
hellfire orb was lost because isnet-anime scores detached props 0.00 (`cutout.detached_props`
now rescues them: solid, off-border, not in the floor band, isnet ~0; checked on all 13 sources
(only the orb added) and the 41 round1-v3 candidates (adds a dropped tabard and a coat tail; floor
lines, cast shadows, a sunburst frame, a white glow disc and lyre strings stay out));
`eyes_closed` is a one-eyed wink on cassiel, brakka and vesper; the portrait was dropped by the filter for liora and nuriel (the canvas passed); cosmetic alpha
defects remain: grey pockets inside seraphiel's halo windows, a notch in nuriel's white wing
(feather fill = backdrop colour, taken as an enclosed hole), white rims inside dark hair on white
backdrops (mordessa, kessa), a soft floor shadow under noctaire.
Follow-ups: run 38902617668 (`round1-v3-retry`, alternates) dropped sable s303000 again at the
same 0.2515 and delivered orrin s302000 (clean, no chest chain), orrin s302001 (chest chain added
by the repair, tower shield cut flat at the bottom, purple floor splash) and sable s303001
(chains instead of the censer; a semi-transparent patch on the inner thigh where a pale highlight
matches the white backdrop). Run 38913405511 (code 4405f7e) re-rendered vesper s203000 with the
orb; NudeNet then called the orb `BUTTOCKS_EXPOSED` 0.64 and one repair pass repainted the orb's
interior (still an orb, the hand intact).

**Estimates for the `standard` preset** (28 steps with CFG):
- one candidate: 28-41 min of sampling + about 1 min decode; with `per_job=1` a hero's
  candidates run in parallel, so a round of N candidates per hero for 15 heroes is
  ceil(15 x N / 16) waves of about 35-45 min (2 per hero: 2 waves, about 1.5 h wall);
- one final seed: hires 20 steps at 2.28 MP (about 160-240 s/step: 55-80 min), face polish
  16 steps at 1 MP (17-25 min), 3 variants at 768 px x 14 steps (22-34 min), loads, cutout and
  filter about 10 min: about 1.7-2.5 h, inside the 270-min budget; finals run in parallel.

The final-mode numbers above were estimates made before the first final. Measured: the
production finals (38881543229) took 83-143 min per job with VmHWM up to 14.65 GB; each final's
`<hero>.json` and `job_<key>.json` record the measured s/step, VmHWM per stage and the decode
mode.

**Checked locally (torch 2.8.0, diffusers 0.35.2, no model download):**
- `tools/artgen/test_sdxl_tiny.py` drives the real `sdxl.Engine` with a tiny random SDXL-shaped
  UNet and VAE: txt2img (Euler a and DPM++ 2M Karras), the lazy UNet, the hires path (VAE encode
  with the UNet released, latent img2img, 5 effective steps = 13 scheduled, release, untiled
  decode), inpaint with a UNet reload, the CFG / negative-embeds / sampler / dtype guards, bench,
  bf16 txt2img with hires/inpaint refused, and a cover repair through a real crop inpaint
  (`gen.publish_screened`: the flagged square is repainted, pixels outside the crop unchanged, the
  repaired file is the one published).
- Real NudeNet localisation (`NudeNetScorer.class_boxes`) on the canary image puts the
  FEMALE_BREAST_EXPOSED boxes on the two breasts (0.2259 in the 832 px tile view, the same maximum
  as the check), so the view offsets and NudeNet's padded-square scaling map correctly. Run it with
  `PYTHONPATH=<dir with torch+diffusers> python3 tools/artgen/test_sdxl_tiny.py` (skipped without
  torch).
- CPU attention memory at the hires size: `F.scaled_dot_product_attention` uses the flash kernel
  on CPU in fp32 and never builds the attention matrix. The SDXL UNet's 8892-token attention
  (1248x1824, 10 heads, CFG batch 2) peaked at +0.05 GB and the VAE's 35568-token mid-block
  attention at +0.07 GB, where a materialized matrix would be 6.3 GB and 5.1 GB. The hires pass is
  therefore bounded by weights (10.3 GB UNet) plus convolution activations, not by attention.
- The final path end to end on the real published s101000 preview (real download and sha256
  check, local isnet-anime, fake model): the canvas lands with the soles at 1990, but the figure
  is too wide for 1024 px (wings plus the diagonal sceptre), so it is scaled to fit the width and
  `spec` reports it; the skin heuristic face box landed inside the halo, hence the detector-only
  rule above.

## 7. Imported into the game

All 15 finals are installed in `assets/art/heroes/<id>/` (`<id>.png`, `variants/*.png`) with a
`<id>.warp_src.json` rig (bones, region rules and overlay rects; the source run and seed are in its
`_doc` and `meta.art`). Masks, overlays, portraits and `<id>.warp.json` are built by
`tools/art_warp <id> --regen-masks`. Candidate, review and hires images stay on `art-gen-output`.

| Hero | Run | Seed | Notes |
|---|---|---|---|
| seraphiel | 38881543229 | s101000 | collar from the cover repair; grey pockets in the halo windows cleared at import (1.5k px, base and variants) |
| cassiel | 38881543229 | s102000 | `eyes_closed` is a wink: not used for blinking |
| liora | 38881543229 | s103000 | cover repair removed the lace bottom under the hem (skirt covers, nothing drawn); bead speck on the stocking top |
| uriela | 38881543229 | s104001 | smile is a wink |
| nuriel | 38881543229 | s105001 | masked: eyes slot only; notch in the screen-right wing |
| mordessa | 38881543229 | s201001 | smallest figure (70 % fit); white rims in the hair |
| brakka | 38881543229 | s202001 | chest recoloured by the repair; `eyes_closed` is a wink: not used |
| vesper | 38913405511 | s203000 | orb kept (detached props); `eyes_closed` is a wink: not used |
| imra | 38881543229 | s204000 | lantern on its own accessory spring |
| kessa | 38881543229 | s205000 | scarf on a ribbon spring; white rims in the hair |
| noctaire | 38881543229 | s301000 | soft floor shadow under the feet |
| orrin | 38902617668 | s302000 | alternate seed (s302002's canvas was dropped in its only final run, 38881543229; renders are deterministic, so a re-run would drop it again); no chest chain |
| sable | 38902617668 | s303001 | alternate seed (s303000 dropped twice); chains instead of the censer; thigh haze |
| lucen | 38881543229 | s304000 | |
| ashra | 38881543229 | s305001 | chest re-shaded by the repair |

Four picks were also cover-repaired at the candidate stage (the `repair` record in
`runs/38859902166-candidates-round1-v3/<hero>/<hero>_s<seed>.json`), and finals start from that
repaired preview, so those repairs are in the shipped art: orrin s302000 (chest), sable s303001
(hips and upper thighs), liora s103000 (chest and hem) and vesper s203000 (hip).

Rig conventions used for all 15: `face` ellipse and `hair_front` from the farm's face box, `head`
ellipse (plus hat/horn polygons where needed), a `halo` bone for haloed heroes, hair masses as
`hair_back` / `hair_side_l` / `hair_long` polygons with `g` 0.9 springs, `wing_r` / `wing_l`
polygons pivoting at the shoulder blades, `weapon` = the held or floating item with the gripping
hand (heroes with sheathed or no weapons get a weapon bone without a region, for the VFX tip),
cloth (`skirt`, `cape`, `coat_*`), `tail`, `ribbon` and accessory regions with their spring
presets. Overlay rects come from the variant diffs. Winks are left out of the `eyes` slot, so
those heroes do not blink. The in-game figure height comes from the rig bounds, so the 70-89 %
fit only shows in battle, where heroes use the fixed battle scale.
