"""Art farm configuration: model, licences, render presets, styles, limits (pure data, no torch).

Used by plan.py (input validation on the GitHub `plan` job), gen.py (rendering), collect.py, the
tests and the docs. Change a preset here, never inline in the workflow. publish.py (stdlib only, the
job that can write to the repo) keeps its own copies of BRANCH and the upload types; a test keeps
them in sync.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
COMFY_DIR = os.path.join(ROOT, "tools", "comfy")
if COMFY_DIR not in sys.path:          # reuse the prompt bible code and post-processing as they are
    sys.path.insert(0, COMFY_DIR)

FAMILY = "animagine"                   # data/art_prompts.json families.animagine (prompt + sampler profile)
BRANCH = "art-gen-output"              # orphan branch that receives the results

MODEL = {
    "repo": "cagliostrolab/animagine-xl-4.0",
    "license": "CreativeML Open RAIL++-M (commercial use allowed; use restrictions in Attachment A)",
    "license_url": "https://huggingface.co/cagliostrolab/animagine-xl-4.0",
}

# Tools that never ship in the game (pipeline only).
AUX = {
    "cutout": {"name": "rembg isnet-anime", "license": "rembg MIT; IS-Net anime model Apache-2.0 (SkyTNT/anime-segmentation)"},
    "nudenet": {"name": "NudeNet 3.4.2 detector (320n)", "license": "MIT (weights bundled in the pip package)"},
    "anime_censor": {"repo": "deepghs/anime_censor_detection", "model": "censor_detect_v1.0_s",
                     "name": "deepghs anime censor-point detector (YOLOv8)"},
    "anime_face": {"repo": "deepghs/anime_face_detection", "model": "face_detect_v1.4_s",
                   "name": "deepghs anime face detector (YOLOv8)"},
}

# ------------------------------------------------------------------ render presets
# Owner directive (2026-10-16): Animagine XL 4.0's model-card settings for every render, candidates
# included: Euler Ancestral, CFG 5, 28 steps, 832x1216 portrait, quality tags at the END (the bible's
# animagine family has quality_position "end"). No speed LoRAs: Lightning/LCM ran at CFG <= 1.8, washed
# the images out and (at CFG 1) switched the negative prompt off. `draft` is an explicit opt-in only.
SAMPLERS = ("euler_ancestral", "dpmpp_2m_karras")
CFG_MIN, CFG_MAX = 4.0, 7.0            # refused outside this range (plan.py, gen.py and the engine)
NEGATIVES_NEED_CFG_ABOVE = 1.0         # diffusers ignores the negative prompt at guidance_scale <= 1
PRESETS = {
    "standard": {"sampler": "euler_ancestral", "steps": 28, "cfg": 5.0, "width": 832, "height": 1216,
                 "doc": "Animagine XL 4.0 model card: Euler a, 28 steps, CFG 5, 832x1216 (default for candidates "
                        "and finals; about 25-40 min per image on the 4-vCPU runners)"},
    "draft": {"sampler": "dpmpp_2m_karras", "steps": 14, "cfg": 5.0, "width": 832, "height": 1216,
              "doc": "opt-in only: DPM++ 2M Karras 14 steps, CFG 5, 832x1216 (about half the time of standard)"},
}
DEFAULT_PRESET = "standard"
FINAL_PRESET = "standard"              # sampler and CFG of every final-mode pass (hires, face polish, variants)


def cfg_problem(cfg):
    """None when `cfg` is allowed, else the reason. CFG must be > 1 (negatives active) and within CFG_MIN..CFG_MAX."""
    try:
        v = float(cfg)
    except (TypeError, ValueError):
        return "cfg %r is not a number" % (cfg,)
    if not v > NEGATIVES_NEED_CFG_ABOVE:
        return "cfg %.2f leaves the negative prompt inactive (must be > %.0f)" % (v, NEGATIVES_NEED_CFG_ABOVE)
    if not CFG_MIN <= v <= CFG_MAX:
        return "cfg %.2f is outside the allowed %.0f-%.0f" % (v, CFG_MIN, CFG_MAX)
    return None


def preset_problems(p):
    """[] when a preset dict is usable, else the reasons (plan.py and gen.py refuse it)."""
    probs = []
    if not isinstance(p, dict):
        return ["preset is not a dict"]
    c = cfg_problem(p.get("cfg"))
    if c:
        probs.append(c)
    if p.get("lora"):
        probs.append("LoRAs are not used by the farm")
    if p.get("sampler") not in SAMPLERS:
        probs.append("sampler %r not in %s" % (p.get("sampler"), ", ".join(SAMPLERS)))
    steps = p.get("steps")
    if not isinstance(steps, int) or isinstance(steps, bool) or not 8 <= steps <= 60:
        probs.append("steps %r not in 8..60" % (steps,))
    for k in ("width", "height"):
        v = p.get(k)
        if not isinstance(v, int) or isinstance(v, bool) or v % 64 or not 512 <= v <= 1536:
            probs.append("%s %r must be a multiple of 64 in 512..1536" % (k, v))
    return probs


# ------------------------------------------------------------------ dtype
DTYPES = ("fp32", "bf16")
DEFAULT_DTYPE = "fp32"                 # bf16 only for candidates/bench, never in final (plan.py, gen.py, engine)

# ------------------------------------------------------------------ prompt style overlay (style.py)
# Applied in memory on a deep copy of the bible; every composed prompt still goes through
# prompts.lint + prompts.enforce against the real bible (gen.checked). Recorded in every metadata file.
STYLES = {
    "farm": {
        "doc": "farm overlay: dark slate background behind light-palette heroes on grey, face/clarity tags, "
               "3/4 view cue, floating weapons up-weighted, floor/shadow and flat-look negatives, exposure "
               "hardening (weighted explicit negatives first, huge->large breasts, openings->plunging neckline "
               "with filigree panels, rating tag sensitive)",
        "drop_tags": ["cel shading"],
        "style_extra": "game cg, shiny hair",
        "full_body_extra": "(dramatic lighting:0.8), (from side:0.5), (detailed face:1.1)",
        "floating_weight": 1.2,
        "floating_negative": "holding staff, holding weapon",
        "negative_extra": "shadow, floor, reflection, flat color, low contrast, washed out, sketch",
        "face_negative_extra": "flat color, low contrast, washed out, sketch",
        "background": {"key": "slate", "tags": "simple background, dark grey background", "rgb": [70, 72, 80],
                       "style_tags": "rim lighting", "when_background": "grey", "when_palette_has": "white"},
        # Exposure hardening (lead, 2026-10-16, after run 38844272140 dropped both v3-outfit Seraphiel
        # candidates: breast 0.38 / 0.48, nipple_f 0.44). Weighted explicit negatives at the FRONT of every
        # farm negative (full body, face, variants, cover repair; join_tags keeps the first occurrence, so
        # these weights win over the bible's unweighted copies); "topless" only for women (the men are
        # shirtless by design). Tag swaps on the in-memory hero copy: the two tags that combine into slips.
        # "{panels}" = "<gold|silver> filigree panels" (the metal of the hero's outfit/palette, default gold),
        # the opaque-coverage cue.
        "harden_negative": {
            "female": "(nipples:1.5), (areolae:1.5), (nude:1.4), (topless:1.4), (nipple slip:1.4), (nsfw:1.3), "
                      "(covered nipples:1.3)",
            "male": "(nude:1.4), (penis:1.5), (nsfw:1.3), (bulge:1.3), (pubic hair:1.3)",
        },
        "rating_tag": "sensitive",
        "replace_tags": {
            "huge breasts": "large breasts",
            "center opening": "plunging neckline, {panels}",
            "opening to the navel": "plunging neckline, {panels}",
            "open to the navel": "plunging neckline, {panels}",
            "navel opening": "plunging neckline, {panels}",
        },
    },
    "bible": {"doc": "the prompt bible exactly as written"},
}
DEFAULT_STYLE = "farm"

# ------------------------------------------------------------------ cover repair (gen.publish_screened)
# When the exposure filter flags an image, the flagged classes' detector boxes (plus classes at >= near_frac
# of their threshold) are padded, merged and inpainted with the hero's opaque outfit material (style.cover:
# hardened negative, exposure-prone outfit tags removed), then the FULL filter runs again on the new file.
# Only a passing image is published; the unrepaired original never reaches the upload dir. The filter's
# thresholds are never touched here.
REPAIR = {
    "attempts": 2,               # repair passes before the image is dropped as before
    "denoise": 0.6,
    "steps": 14,                 # effective steps (schedule.total_steps_for)
    "px": 768,                   # each crop is inpainted at this size
    "pad": 0.25,                 # every detector box grows by 25% of its size on each side
    "min_side": 48,              # ... and to at least this many px (tiny nipple boxes)
    "context": 2.0,              # crop side = cluster size x this (the model sees the surrounding outfit)
    "crop_min": 320,
    "cluster_max_frac": 0.75,    # regions share one crop while it stays within this x the short image side
    "box_conf_frac": 0.5,        # boxes from anchors scoring >= this x the class threshold
    "near_frac": 0.8,            # unflagged classes at >= this x their threshold are covered too
    "max_regions": 4,            # more separate regions = not a local slip: drop instead
    "max_area_frac": 0.2,        # masks covering more of the image = not a repair: drop instead
    "feather": 3,
    "seed_offset": 700,          # inpaint seed = seed + 700 + 10 x attempt + cluster (same seed family)
    "drop_outfit_terms": ["cutout", "underboob", "sideboob", "opening", "unzipped", "cleavage", "revealing",
                          "plunging", "no shirt", "topless", "backless", "open jacket", "open coat"],
}

# ------------------------------------------------------------------ final mode
# Hires values come from the bible (families.animagine.settings.hires: scale 1.5, denoise_model 0.4,
# steps 20) and face_refine.denoise; `steps` are EFFECTIVE steps (the number actually run, as on
# ComfyUI): diffusers img2img/inpaint run int(num_inference_steps * strength), so the engine asks for
# schedule.total_steps_for(effective, strength). Overridable on the gen.py command line.
FINAL = {
    "face_steps": 16,            # effective steps of the face polish (denoise = bible face_refine.denoise)
    "variant_steps": 14,         # effective steps per expression variant (denoise from the bible's variants)
    "face_px": 1024,             # the face crop is inpainted at this size
    "variant_px": 768,           # expression crops are inpainted at this size
    "face_crop_scale": 1.8,      # face polish crop = face box x this (as finalize.py)
    "variant_crop_scale": 1.9,   # variant crop = face box x this (as variants.py)
    "variant_seed_offset": 500,  # variant seeds = seed_base + 500 + i (as variants.py)
    "ref_s_per_step_mp": 90.0,   # deadline estimates: s/step at 1 MP with CFG (Zen 3 7763 measured 86.8),
    "mp_exponent": 1.2,          #   x MP^1.2; replaced by the measured value after each sampled stage
    "stage_overhead_s": 120.0,   # per-stage encode/decode/load allowance in the estimates
    "untiled_min_avail_gb": 7.0,  # hires decode/encode untiled only with this much MemAvailable (else tiled)
}

# ------------------------------------------------------------------ exposure filter (safety.py)
# Scores are raw per-class detector confidences (max over all anchors and all views), so this is
# stricter than the detectors' own NMS output. Lower = more conservative. Never loosen it to save a
# render: render more candidates instead.
FILTER = {
    "nudenet_threshold": 0.25,
    "anime_threshold": 0.25,
    "nudenet_classes": ["FEMALE_BREAST_EXPOSED", "FEMALE_GENITALIA_EXPOSED", "MALE_GENITALIA_EXPOSED",
                        "ANUS_EXPOSED", "BUTTOCKS_EXPOSED"],
    "anime_classes": ["nipple_f", "penis", "pussy"],
    "max_threshold": 0.5,        # plan.py/gen.py refuse looser settings
    # Sensitivity canary (positive control): an already-public, filter-passed borderline candidate on the
    # art-gen-output branch (measured nudenet 0.2259 / anime censor 0.1053). It is loaded at run time
    # (safety.fetch_canary) and never committed to the code branch. The self-test requires it to PASS
    # and its scores to stay inside these bands, so a detector that silently returns near-zero scores
    # fails closed. If it cannot be fetched, only the canary is skipped (with a warning line).
    "canary": {
        "repo": "u-tek/game",
        "branch": BRANCH,
        "ref": "origin/" + BRANCH,
        "path": "runs/38832421932-candidates-bench-draft/seraphiel/seraphiel_s101000.webp",
        "sha256": "6850479965568fe37d2d1c990c0e0b958cf2ed7bb038261098a7276b44a3fcdc",
        "bands": {"nudenet": {"FEMALE_BREAST_EXPOSED": [0.10, 0.25]},
                  "anime_censor": {"_max": [0.02, 0.25]}},
    },
}

# ------------------------------------------------------------------ limits for workflow inputs (plan.py)
LIMITS = {"count_max": 12, "per_job_max": 12, "jobs_max": 60, "final_jobs_max": 16, "bench_jobs_max": 3,
          "label_max": 40, "final_seeds_max": 4, "max_parallel": 16}

IMAGE_EXTS = (".png", ".webp", ".jpg", ".jpeg", ".gif", ".bmp", ".tif", ".tiff", ".avif", ".heic", ".jxl", ".ico")
UPLOAD_IMAGE_EXTS = (".png", ".webp")      # the only image types the farm writes
UPLOAD_TEXT_EXTS = (".json",)              # everything else is deleted before upload
