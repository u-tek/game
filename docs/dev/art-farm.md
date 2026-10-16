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
| `style` | `farm` (default overlay, section 2) or `bible` (the bible as written) |
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
  style, seed, model, preset settings, dtype, render timing, framing flags, filter scores);
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
- **Settings (owner directive)**: Animagine XL 4.0's model-card settings for every render,
  candidates included: Euler Ancestral, CFG 5, 28 steps, 832x1216 portrait, quality tags at the
  end (the bible's animagine family). Accepted cost: about 25-40 min per candidate on these CPUs.

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
  - negatives `shadow, floor, reflection, flat color, low contrast, washed out, sketch`.
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
  2. **face polish**: face box from the deepghs anime face detector (fallback
     `post.estimate_face_box`), crop inpaint at 1024 px, bible `face_refine.denoise` (0.35),
     **16 effective steps**. → `_source.webp`.
  3. **cutout + canvas**: `cutout.artgen_cutout` = rembg `isnet-anime` mask, minus enclosed
     background (halo ring, wing gaps: `post.remove_background`'s colour flood + holes, within 12 of
     the fitted background), minus isnet's background-coloured haze, minus the ground shadow (bottom
     15% of the figure, background chromaticity at 35-97% of its luminance, flat on the floor), then
     `post.alpha_from_mask` edge unmixing/despill; `post.finalize_local` places it. An automatic
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

**Estimates for the `standard` preset** (28 steps with CFG):
- one candidate: 28-41 min of sampling + about 1 min decode; with `per_job=1` a hero's
  candidates run in parallel, so a round of N candidates per hero for 15 heroes is
  ceil(15 x N / 16) waves of about 35-45 min (2 per hero: 2 waves, about 1.5 h wall);
- one final seed: hires 20 steps at 2.28 MP (about 160-240 s/step: 55-80 min), face polish
  16 steps at 1 MP (17-25 min), 3 variants at 768 px x 14 steps (22-34 min), loads, cutout and
  filter about 10 min: about 1.7-2.5 h, inside the 270-min budget; finals run in parallel.

The final-mode numbers above are estimates until the first final smoke; each final's
`<hero>.json` and `job_<key>.json` record the measured s/step, VmHWM per stage and the decode
mode, and this section is updated from them.
