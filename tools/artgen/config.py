"""Art farm configuration: models, licenses, render presets, limits (pure data, no torch).

Used by plan.py (input validation on the GitHub `plan` job), gen.py (rendering) and the docs.
Change a preset here, never inline in the workflow.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
COMFY_DIR = os.path.join(ROOT, "tools", "comfy")
if COMFY_DIR not in sys.path:          # reuse the prompt bible code and post-processing as they are
    sys.path.insert(0, COMFY_DIR)

FAMILY = "animagine"                   # data/art_prompts.json families.animagine (prompt + sampler profile)

MODEL = {
    "repo": "cagliostrolab/animagine-xl-4.0",
    "license": "CreativeML Open RAIL++-M (commercial use allowed; use restrictions in Attachment A)",
    "license_url": "https://huggingface.co/cagliostrolab/animagine-xl-4.0",
}

# Fast-sampling LoRAs for candidate rounds. DMD2 is NOT allowed (non-commercial licence).
LORAS = {
    "lightning8": {"repo": "ByteDance/SDXL-Lightning", "file": "sdxl_lightning_8step_lora.safetensors",
                   "license": "OpenRAIL++ (CreativeML Open RAIL++-M)",
                   "license_url": "https://huggingface.co/ByteDance/SDXL-Lightning"},
    "lcm": {"repo": "latent-consistency/lcm-lora-sdxl", "file": "pytorch_lora_weights.safetensors",
            "license": "OpenRAIL++ (CreativeML Open RAIL++-M)",
            "license_url": "https://huggingface.co/latent-consistency/lcm-lora-sdxl"},
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

# Candidate presets: speed vs quality. "quality" is the bible's animagine profile itself.
# sampler names: euler_ancestral | euler_trailing | dpmpp_2m_karras | lcm   (all with trailing timesteps)
PRESETS = {
    "lightning8": {"lora": "lightning8", "lora_scale": 1.0, "sampler": "euler_trailing", "steps": 8, "cfg": 1.0,
                   "doc": "SDXL-Lightning 8-step LoRA, no CFG (1 UNet pass per step; negatives unused)"},
    "lightning8_cfg": {"lora": "lightning8", "lora_scale": 1.0, "sampler": "euler_trailing", "steps": 8, "cfg": 1.8,
                       "doc": "SDXL-Lightning 8-step LoRA with light CFG (negatives active; 2 passes per step)"},
    "lcm8": {"lora": "lcm", "lora_scale": 1.0, "sampler": "lcm", "steps": 8, "cfg": 1.5,
             "doc": "LCM-LoRA 8 steps, light CFG"},
    "draft": {"lora": None, "sampler": "dpmpp_2m_karras", "steps": 14, "cfg": 5.0,
              "doc": "no LoRA, DPM++ 2M Karras 14 steps (deterministic; the same seed at more steps keeps the composition)"},
    "quality": {"lora": None, "sampler": "euler_ancestral", "steps": 28, "cfg": 5.0,
                "doc": "the bible's animagine profile: Euler a, 28 steps, CFG 5 (slow on CPU)"},
}
DEFAULT_PRESET = "lightning8"

# Final-mode defaults (overridable on the gen.py command line)
FINAL = {
    "hires_scale": 1.5,          # base size -> hires size (768x1344 -> 1152x2016)
    "refine_denoise": 0.45,      # full-quality img2img at the hires size over the chosen candidate
    "face_crop_scale": 1.8,      # face polish crop = face box x this (as finalize.py)
    "variant_crop_scale": 1.9,   # variant crop = face box x this (as variants.py)
    "inpaint_px": 1024,          # crops are inpainted at this size (SDXL-native detail)
    "variant_seed_offset": 500,  # variant seeds = seed_base + 500 + i (as variants.py)
}

# Exposure filter (safety.py). Scores are raw per-class detector confidences (max over all anchors and
# all views), so this is stricter than the detectors' own NMS output. Lower = more conservative.
FILTER = {
    "nudenet_threshold": 0.25,
    "anime_threshold": 0.25,
    "nudenet_classes": ["FEMALE_BREAST_EXPOSED", "FEMALE_GENITALIA_EXPOSED", "MALE_GENITALIA_EXPOSED",
                        "ANUS_EXPOSED", "BUTTOCKS_EXPOSED"],
    "anime_classes": ["nipple_f", "penis", "pussy"],
    "max_threshold": 0.5,        # plan.py/gen.py refuse looser settings
}

# Limits for workflow inputs (plan.py)
LIMITS = {"count_max": 12, "per_job_max": 12, "jobs_max": 60, "label_max": 40, "final_seeds_max": 4}

IMAGE_EXTS = (".png", ".webp", ".jpg", ".jpeg", ".gif", ".bmp", ".tif", ".tiff", ".avif", ".heic", ".jxl", ".ico")
UPLOAD_IMAGE_EXTS = (".png", ".webp")      # the only image types the farm writes
UPLOAD_TEXT_EXTS = (".json", ".txt")       # everything else is deleted before upload
