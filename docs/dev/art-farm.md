# Art farm: AI hero art on GitHub Actions CPU runners

Painted, full-body anime hero art rendered on free GitHub-hosted runners (the repo is public), for
when the owner's ComfyUI PC (`docs/dev/comfyui-setup.md`) is unreachable. One parallel job per hero
(or per chunk of seeds), results committed to the orphan branch **`art-gen-output`**, which a
session without GPU or Hugging Face access can `git fetch`.

| Piece | File |
|---|---|
| Workflow (plan → gen matrix → collect) | `.github/workflows/art-gen.yml` |
| Input validation + job matrix | `tools/artgen/plan.py` |
| Renderer (candidates / final) | `tools/artgen/gen.py` |
| SDXL on CPU (diffusers, ComfyUI-compatible prompt weights) | `tools/artgen/sdxl.py`, `sdxl_chunks.py` |
| Exposure filter (fail closed) + upload gate | `tools/artgen/safety.py` |
| Contact sheets | `tools/artgen/sheet.py` |
| Verify + commit to `art-gen-output` | `tools/artgen/collect.py` |
| Models, licences, presets, limits | `tools/artgen/config.py` |
| Offline tests (fakes, no torch) | `python3 tools/artgen/test_artgen.py` |

Prompts are **not** duplicated: `gen.py` imports `tools/comfy/prompts.py` (`full_body`, `face`,
`variant_spec`, `enforce`, family `animagine` from `data/art_prompts.json`) and `tools/comfy/post.py`
(cutout edge treatment, canvas placement with the soles at y=1990, portrait, contact sheets), plus
small helpers from `pipeline.py` and `variants.py`. Nothing in `tools/comfy/` was changed.

## 1. Run it

GitHub → Actions → **Art farm** → Run workflow (branch `claude/game-planning`), or the GitHub API /
MCP `actions_run_trigger` with `workflow_id: art-gen.yml`:

| Input | Meaning |
|---|---|
| `mode` | `candidates` (fast previews to pick from) or `final` (chosen seeds at full quality) |
| `heroes` | `seraphiel,cassiel` or `all` (final: optional filter on the `seeds` keys) |
| `count` | candidates per hero, 1-12 (seeds `seed_base + i`, or from `seeds` `{"hero": first_seed}`) |
| `seeds` | final: `{"seraphiel": [101001]}` or `{"seraphiel": {"seeds": [101001], "run": "<run dir>", "flip": true}}` |
| `preset` | candidate preset (below); final re-uses the preset recorded with the candidate |
| `per_job` | candidates per job (0 = one job per hero); e.g. 15 heroes x 6 with `per_job=3` = 30 jobs, 20 at a time |
| `label` | folder label (`[a-z0-9-]`, 40 chars) |

Fetch the results here:

```bash
git fetch origin art-gen-output
git worktree add /tmp/claude-0/artgen-out origin/art-gen-output     # or: git -C /tmp/claude-0/artgen-out pull
ls /tmp/claude-0/artgen-out/runs/                                    # <run id>-<mode>[-label]/<hero>/...
python3 tools/artgen/sheet.py /tmp/claude-0/artgen-out/runs/<run>    # re-draw sheets locally if needed
```

A run folder holds `index.json` (jobs, timings, filter statistics, missing jobs), `overview.png`,
and per hero `contact_sheet.png` plus:
- candidates: `<hero>_s<seed>.webp` (preview, quality 92) + `<hero>_s<seed>.json` (prompt, negative,
  seed, model, LoRA, licences, preset settings, render timing, framing flags, filter scores);
- finals: `final_s<seed>/` with `<hero>.png` (1024x2048 RGBA canvas, soles at 512,1990),
  `_portrait.png`, `_check.png` (cutout over checker/magenta/dark), `_boxes.png`, `<hero>.json`
  (transform, face box, `warp_src_hints`, every step with timing), `<hero>_base.webp` (the
  re-rendered candidate), `<hero>_source.webp` (hires + face polish, before the cutout),
  `variants/<name>.png` + `_patch.png/.json` + `variants.json` (`warp_overlay_hints`),
  `masks/<region>.png`, `variants_sheet.png`;
- `job_<key>.json` per job: CPU model, library versions, download/load/encode times, per-image
  seconds and seconds per step, peak memory, filter counts.

Picking: content rules (`docs/dev/art-style.md` section 1) > face > anatomy/hands > costume
fidelity to `character-briefs.md` > pose (3/4 facing right, contrapposto, whole figure, air gaps).
A candidate facing left gets `"flip": true` in the final seeds.

## 2. How it renders

- **Model**: `cagliostrolab/animagine-xl-4.0` diffusers folders (fp16 weights upcast to fp32, about
  7 GB, cached with `actions/cache`), on CPU in fp32. Prompts are encoded first with both CLIP
  encoders, then the encoders are freed before the UNet loads (16 GB runners). VAE tiling,
  channels-last UNet. Prompt weights and chunking follow ComfyUI (75-token chunks, words kept
  whole, `(tag:w)` as `z_empty + (z - z_empty) * w`, positive/negative aligned by repetition), so
  the bible's prompts mean the same thing here as on ComfyUI.
- **Candidate presets** (`config.PRESETS`):

| Preset | What | UNet passes per image |
|---|---|---|
| `lightning8` (default) | SDXL-Lightning 8-step LoRA, Euler trailing, CFG 1 (negatives unused) | 8 |
| `lightning8_cfg` | same with CFG 1.8 (negatives active) | 16 |
| `lcm8` | LCM-LoRA, 8 steps, CFG 1.5 | 16 |
| `draft` | no LoRA, DPM++ 2M Karras 14 steps, CFG 5 | 28 |
| `quality` | the bible's animagine profile: Euler a 28 steps, CFG 5 | 56 |

- **Final** per chosen seed: (1) re-render the candidate exactly from its published metadata
  (PSNR against the published preview is logged); (2) full-quality img2img at 1.5x (Euler a 28
  steps, CFG 5, no LoRA, denoise 0.45): the hires pass keeps the chosen composition and adds the
  negatives and detail; (3) face box from the deepghs anime face detector (fallback: the skin
  heuristic in `post.estimate_face_box`), face polish (crop inpaint at 1024 px, bible
  `face_refine.denoise`); (4) cutout with rembg `isnet-anime`, edge unmixing and despill by
  `post.alpha_from_mask`, placement by `post.finalize_local`; (5) the hero's `variant_set`
  (e.g. Seraphiel: eyes_open, mouth_open, smile) inpainted on the canvas inside the eyes/mouth
  region only: alpha and every pixel outside the feathered region identical to the base, as
  `tools/comfy/variants.py` does (`variant_alignment` result in `variants.json`).

## 3. Safety (hard rule: the repo is public)

Content rules from `docs/dev/character-briefs.md`: alluring up to App Store 18+, every character
clearly an adult, never explicit.
- **Prompts**: composed only by `prompts.full_body` / `prompts.face`, and `gen.checked()` runs
  `prompts.lint` + `prompts.enforce` again on every prompt right before it is encoded (including
  prompts read back from candidate metadata). Adult cues, forbidden terms and the required
  explicit/childlike negatives are enforced. Note: at CFG 1 (`lightning8`) the negative prompt has
  no effect, so the image filter below carries the safety for candidates; finals always run
  their quality passes with CFG 5 and the full negative.
- **Exposure filter** (`safety.py`) on the runner, before anything is uploaded:
  NudeNet 3.4.2 (pip, MIT) **and** the deepghs anime censor-point detector (YOLOv8 trained on anime
  art), each on the whole image plus overlapping tiles at two scales; the raw per-class maximum
  over every anchor (no NMS/argmax) must stay below 0.25 for exposed breast, genitalia, anus and
  buttocks (NudeNet) and nipples/genitals (anime detector). A detector error, unreadable image or
  non-finite score drops the image; a detector that cannot load stops the job before rendering;
  every job starts with a self-test that proves a forced detector error drops the image.
  Dropped images are deleted immediately; only their name, scores and reason are logged
  (`filter_manifest.json`, `job_<key>.json`, run `index.json`).
- **Upload gate**: renders happen in a work dir outside the checkout, which is never uploaded. Only `artgen_out/` is
  uploaded, after `safety.py verify` deleted any file without a pass record (path + sha256), any
  non-.png/.webp image and anything that is not .json. `collect.py` verifies every artifact
  again, filters the contact sheets it draws (no filter in collect = no sheets), runs a last
  `verify` over the run folder and only then commits.
- **Workflow hygiene**: `workflow_dispatch` only (people with write access); inputs reach scripts
  through env vars and are validated by `plan.py` (hero ids from the bible, bounded integers,
  JSON seeds, label reduced to `[a-z0-9-]`); `permissions: {}` at the top, `contents: read` for
  plan and gen, `contents: write` only for collect; artifacts kept 3 days.
- A person still reviews every image against `docs/dev/art-style.md` section 1 before it ships.
  The filter is an automatic net, not the review.

## 4. Licences

| Item | Licence | Where recorded |
|---|---|---|
| animagine-xl-4.0 | CreativeML Open RAIL++-M (commercial use allowed, use restrictions) | every image's JSON (`model`) |
| SDXL-Lightning LoRA (ByteDance) | OpenRAIL++ | candidate/final JSON (`lora`) |
| LCM-LoRA SDXL | OpenRAIL++ | same |
| DMD2 | non-commercial: **not used** | |
| rembg / isnet-anime | MIT / Apache-2.0 | pipeline only |
| NudeNet, deepghs detectors | MIT / see their model cards | pipeline only |

## 5. Limits and measurements

CPU generation is slow; runs are bounded (counts, 300-minute job timeout, `--max-minutes 270`
soft budget inside `gen.py`: later seeds/variants are skipped and what is done is still uploaded).
This is heavy use of free Actions minutes for the repo's own assets, so keep rounds small.
Measured numbers: section 6 (filled from the smoke runs).

## 6. Smoke results

(see below; updated after each measured run)
