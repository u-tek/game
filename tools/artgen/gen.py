#!/usr/bin/env python3
"""Art farm renderer: anime SDXL (cagliostrolab/animagine-xl-4.0) on a CPU runner.

    gen.py candidates --hero ID --seeds 101000,101001 [--preset standard] [--style farm] [--dtype fp32] --out DIR --work DIR
    gen.py final      --hero ID --seeds 101000 --source-run RUN [--repo OWNER/NAME] [--flip] --out DIR --work DIR
    gen.py final      --hero ID --seeds 101000 --no-source [--preset standard]     (local/tests: render the base)
    gen.py bench      --hero ID --out DIR --work DIR                              (s/step only, no images)

Prompts come from the prompt bible through tools/comfy/prompts.py (full_body / face / variant_spec,
family "animagine"), with the in-memory style overlay of style.py; every prompt is re-checked with
prompts.lint + prompts.enforce (gen.checked) right before it is encoded. Every image goes through the
exposure filter (safety.py) before it reaches --out, the only directory the workflow uploads.
Rendering happens in --work, which is never uploaded. CFG is always within config.CFG_MIN..CFG_MAX
(> 1, so the negative prompt is always active); presets are refused otherwise.

candidates: one render per seed (preset from config.PRESETS, default "standard" = the Animagine XL
    4.0 model card: Euler a, 28 steps, CFG 5, 832x1216), saved as a WebP preview (q95) + metadata JSON
    (prompt, negative, style, seed, model, licences, settings, timings, framing report, filter scores).
final: per chosen seed, starting from the PUBLISHED candidate preview (downloaded from the
    art-gen-output branch: runs/<run>/<hero>/<hero>_s<seed>.json/.webp; a final always names its
    candidate run; missing/invalid -> exit 6, nothing rendered). Each stage is published through the
    filter as soon as it is done, with the live <hero>.json:
    1. hires: Lanczos x1.5 (bible hires.scale), img2img Euler a / CFG 5, denoise 0.4 for 20 EFFECTIVE
       steps (bible hires.denoise_model / steps) -> <hero>_hires.webp;
    2. face box (deepghs anime face detector, fallback post.estimate_face_box) and face polish (crop
       inpaint at 1024 px, bible face_refine.denoise, 16 effective steps) -> <hero>_source.webp;
    3. cutout (cutout.artgen_cutout: rembg isnet-anime + enclosed holes + ground shadow), placement on
       the 1024x2048 canvas with the soles at y=1990 (post.finalize_local) -> <hero>.png,
       _portrait.png, _check.webp, _boxes.webp, plus an automatic spec report;
    4. expression variants (the hero's variant_set) on the canvas: crop inpaint of the eyes/mouth
       region at 768 px, 14 effective steps, alpha and every pixel outside the region identical to the
       base (as tools/comfy/variants.py) -> variants/<n>.png, _patch.png/.json, masks/, variants.json;
       each variant is isolated (an error is logged and the next one runs);
    5. variants_sheet.webp.
    Deadline checks (estimates from the measured s/step) come before the hires, the face polish and
    each variant. Exit 5 when a seed or variant failed (finished stages are still uploaded).
bench: fp32 at 4 and 2 threads (then bf16 on CPUs with native bf16), a few txt2img steps without
    decoding: only job_<key>.json with s/step is written.

Cover repair (publish_screened, config.REPAIR): when the exposure filter flags an image (a candidate,
    the final's hires or source stage), the flagged classes' detector boxes are padded and merged, only
    those regions are inpainted with the hero's opaque outfit material (style.cover, hardened negative;
    denoise 0.6, 14 effective steps, same seed family), and the FULL filter runs again on the new file.
    Only a passing image is published (at most 2 passes, else dropped as before); the unrepaired
    original never reaches --out. The metadata records the boxes, regions, crops, seeds and scores.
    fp32 only (the engine's inpaint refuses bf16); --no-repair turns it off.

Exit codes: 0 ok, 2 bad arguments, 3 exposure filter unavailable, 4 prompt refused by the content
rules, 5 a seed/stage failed (partial outputs), 6 final source candidate missing or invalid.
"""
import argparse
import gc
import hashlib
import io
import json
import os
import platform
import re
import sys
import time
import traceback

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import config as C  # noqa: E402  (adds tools/comfy to sys.path)
import numpy as np  # noqa: E402
from PIL import Image, ImageFilter  # noqa: E402

import cutout  # noqa: E402
import memstat  # noqa: E402
import pipeline as P  # noqa: E402  tools/comfy: square_box, ellipse_mask, flat_rgb, skin_profile
import post  # noqa: E402            tools/comfy: cutout edge treatment, placement, sheets
import prompts  # noqa: E402         tools/comfy: prompt bible composer + content rules
import repair  # noqa: E402
import safety  # noqa: E402
import schedule  # noqa: E402
import style  # noqa: E402
import variants as V  # noqa: E402   tools/comfy: patch_from

ROOT = C.ROOT
T_START = time.time()
HERO_RE = re.compile(r"^[a-z][a-z0-9_]{1,30}$")
RUN_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,80}$")
REPO_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9-]{0,38}/[A-Za-z0-9._-]{1,100}$")
RAW_URL = "https://raw.githubusercontent.com/%s/%s/runs/%s/%s"


def log(*a):
    print(time.strftime("%H:%M:%S"), *a, flush=True)


def stamp():
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


class Deadline:
    def __init__(self, minutes):
        self.end = T_START + minutes * 60.0

    def left(self):
        return self.end - time.time()

    def allows(self, seconds):
        return self.left() > seconds


class SourceError(RuntimeError):
    """The final's source candidate is missing or does not match: nothing is rendered (exit 6)."""


# ------------------------------------------------------------------ prompts and settings
def checked(bible, hero, positive, negative):
    """The single choke point before any text reaches the encoder: syntax + content rules."""
    prompts.lint(positive, negative)
    prompts.enforce(bible, hero, positive, negative)
    return positive, negative


def preset_settings(name_or_dict):
    """A validated copy of a preset (by name, or a recorded preset_settings dict). Raises ValueError."""
    p = C.PRESETS.get(name_or_dict) if isinstance(name_or_dict, str) else name_or_dict
    if p is None:
        raise ValueError("unknown preset %r (known: %s)" % (name_or_dict, ", ".join(sorted(C.PRESETS))))
    probs = C.preset_problems(p)
    if probs:
        raise ValueError("preset refused: %s" % "; ".join(probs))
    return dict(p)


def final_settings(bible, a):
    """Sampler/CFG of the final preset + the bible's hires and face_refine values (CLI overrides)."""
    p = preset_settings(C.FINAL_PRESET)
    hires = prompts.family_block(bible, C.FAMILY)["settings"].get("hires") or {}
    s = {"sampler": p["sampler"], "cfg": p["cfg"], "preset": C.FINAL_PRESET,
         "hires_scale": float(a.hires_scale or hires.get("scale", 1.5)),
         "hires_denoise": float(a.hires_denoise or hires.get("denoise_model", 0.4)),
         "hires_steps": int(a.hires_steps or hires.get("steps", 20)),
         "face_denoise": float(bible["face_refine"]["denoise"]),
         "face_steps": int(a.face_steps), "face_px": int(a.face_px),
         "variant_steps": int(a.variant_steps), "variant_px": int(a.variant_px)}
    for k in ("hires_denoise", "face_denoise"):
        if not 0.05 <= s[k] <= 1.0:
            raise ValueError("%s %.2f out of range" % (k, s[k]))
    if not 1.0 <= s["hires_scale"] <= 2.0:
        raise ValueError("hires scale %.2f out of range 1..2" % s["hires_scale"])
    return s


def round8(v):
    return int(round(v / 8.0)) * 8


# ------------------------------------------------------------------ real components (runner)
def real_encoders(model_dir, variants):
    import sdxl
    return sdxl.TextEncoders(model_dir, variants, log=log)


def real_engine(model_dir, variants, threads=None, dtype=C.DEFAULT_DTYPE, lazy_unet=False):
    import sdxl
    return sdxl.Engine(model_dir, variants, log=log, threads=threads, dtype=dtype, lazy_unet=lazy_unet)


class RembgCutter:
    name = "rembg isnet-anime"

    def __init__(self):
        from rembg import new_session
        t0 = time.time()
        self._s = new_session("isnet-anime")
        log("rembg isnet-anime ready in %.0f s" % (time.time() - t0))

    def mask(self, img):
        from rembg import remove
        m = remove(img.convert("RGB"), session=self._s, only_mask=True)
        return m.convert("L")


class AnimeFaceFinder:
    name = "deepghs anime face detector"

    def __init__(self):
        a = C.AUX["anime_face"]
        self._y = safety.YoloOnnx(a["repo"], a["model"])

    def find(self, img):
        """(x, y, w, h) of the most confident face in the upper half (searched on square crops so
        the detector's stretch-to-square input keeps the aspect), or None."""
        W, H = img.size
        best = None
        side = min(W, H)
        for y0 in sorted({0, max(0, min(H - side, side // 3))}):
            crop = img.crop((0, y0, side, y0 + side)) if W <= H else img
            for x0, y0b, x1, y1, _lab, sc in self._y.boxes(crop, conf=0.3):
                cy = (y0b + y1) / 2 + y0
                if cy > 0.55 * H:
                    continue
                if best is None or sc > best[4]:
                    best = (x0, y0b + y0, x1 - x0, y1 - y0b, sc)
        if not best:
            return None
        x, y, w, h, sc = best
        return [int(round(x)), int(round(y)), int(round(w)), int(round(h))], "anime face detector %.2f" % sc


class Lazy:
    """Optional helper models (face detector, isnet): built on first use; a failure is logged once
    and the caller falls back (heuristic face box / colour-flood cutout)."""

    def __init__(self, factory, what, job):
        self.factory, self.what, self.job = factory, what, job
        self.obj, self.tried = None, False

    def get(self):
        if not self.tried:
            self.tried = True
            try:
                self.obj = self.factory()
            except Exception as e:      # noqa: BLE001
                log("WARNING: %s unavailable, using the fallback: %s: %s" % (self.what, type(e).__name__, e))
                self.job.setdefault("warnings", []).append("%s unavailable: %s" % (self.what, e))
        return self.obj


# ------------------------------------------------------------------ final source (published candidate)
def _http_get(url, limit, tries=3, timeout=60):
    import urllib.error
    import urllib.request
    last = None
    for i in range(tries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "art-farm"})
            with urllib.request.urlopen(req, timeout=timeout) as r:
                data = r.read(limit + 1)
            if len(data) > limit:
                raise SourceError("%s is larger than %d bytes" % (url, limit))
            return data
        except urllib.error.HTTPError as e:
            if e.code == 404:
                raise SourceError("not found: %s" % url)
            last = e
        except (urllib.error.URLError, OSError) as e:
            last = e
        time.sleep(3 * (i + 1))
    raise SourceError("could not download %s: %s" % (url, last))


def fetch_candidate(repo, run, hero, seed, get=_http_get):
    """(meta, RGB preview, source record) of a published candidate on the art-gen-output branch.
    Downloads only runs/<run>/<hero>/<hero>_s<seed>.json/.webp and the run's filter manifest. Raises
    SourceError when anything is missing or does not match (mode, hero, seed, size, filter record)."""
    if not (isinstance(repo, str) and REPO_RE.match(repo)):
        raise SourceError("bad repo %r" % (repo,))
    if not (isinstance(run, str) and RUN_RE.match(run)):
        raise SourceError("bad run name %r" % (run,))
    if not HERO_RE.match(hero) or not 0 <= int(seed) < 2 ** 32:
        raise SourceError("bad hero/seed")
    stem = "%s_s%d" % (hero, int(seed))
    try:
        meta = json.loads(get(RAW_URL % (repo, C.BRANCH, run, "%s/%s.json" % (hero, stem)), 4 << 20).decode("utf-8"))
        man = json.loads(get(RAW_URL % (repo, C.BRANCH, run, safety.MANIFEST), 32 << 20).decode("utf-8"))
    except (ValueError, UnicodeDecodeError) as e:
        raise SourceError("candidate metadata is not valid JSON: %s" % e)
    if not isinstance(meta, dict) or meta.get("mode") != "candidates":
        raise SourceError("%s is not a candidate" % stem)
    if meta.get("dropped") or not meta.get("image"):
        raise SourceError("%s was dropped by the filter" % stem)
    if meta.get("hero") != hero or meta.get("seed") != int(seed):
        raise SourceError("%s metadata names %r seed %r" % (stem, meta.get("hero"), meta.get("seed")))
    rel = "%s/%s.webp" % (hero, stem)
    rec = (man.get("files") or {}).get(rel) if isinstance(man, dict) else None
    if not rec or not rec.get("passed") or not rec.get("sha256"):
        raise SourceError("%s has no filter pass record in the run's manifest" % rel)
    blob = get(RAW_URL % (repo, C.BRANCH, run, rel), 32 << 20)
    sha = hashlib.sha256(blob).hexdigest()
    if sha != rec["sha256"]:
        raise SourceError("%s sha256 %s does not match its filter record %s" % (rel, sha[:12], rec["sha256"][:12]))
    try:
        img = Image.open(io.BytesIO(blob))
        img.load()
        img = img.convert("RGB")
    except Exception as e:      # noqa: BLE001
        raise SourceError("%s is not a readable image: %s" % (rel, e))
    if [img.width, img.height] != [meta.get("width"), meta.get("height")]:
        raise SourceError("%s is %dx%d, metadata says %sx%s" % (rel, img.width, img.height, meta.get("width"),
                                                                meta.get("height")))
    for k in ("prompt", "negative"):
        if not isinstance(meta.get(k), str) or not meta[k]:
            raise SourceError("%s metadata has no %s" % (stem, k))
    src = {"repo": repo, "run": run, "path": "runs/%s/%s" % (run, rel), "sha256": sha,
           "preset": meta.get("preset"), "preset_settings": meta.get("preset_settings"),
           "style": (meta.get("style") or {}).get("name", "bible")}
    return meta, img, src


# ------------------------------------------------------------------ image helpers
def crop_inpaint(eng, emb, image, crop, mask, denoise, seed, fs, steps, target, grow=6, feather=4):
    """Inpaint `mask` (full-size L, white = repaint) of an RGB image on the square `crop` scaled to
    `target` px for `steps` effective steps, pasted back through a feathered mask (as
    pipeline.crop_inpaint on ComfyUI)."""
    x0, y0, x1, y1 = crop
    side = x1 - x0
    src = image.crop(crop).resize((target, target), Image.LANCZOS)
    mcrop = mask.crop(crop).resize((target, target), Image.BILINEAR)
    if grow:
        mcrop = mcrop.filter(ImageFilter.MaxFilter(2 * grow + 1))
    res, info = eng.inpaint(emb, src, mcrop, denoise, seed, steps, fs["cfg"], fs["sampler"])
    back = res.convert("RGB").resize((side, side), Image.LANCZOS)
    m_back = mask.crop(crop)
    if feather:
        m_back = m_back.filter(ImageFilter.GaussianBlur(feather))
    out = image.copy()
    out.paste(back, (x0, y0), m_back)
    info.update({"crop": [x0, y0, side, side], "denoise": denoise, "seed": seed, "px": target})
    return out, info


def merge_variant(base, out_rgb, mask):
    """Variant canvas: inpainted RGB inside the feathered region, the base everywhere else, base alpha."""
    alpha = base.split()[3]
    var = out_rgb.convert("RGBA")
    var.putalpha(alpha)
    m = np.asarray(mask).astype(np.float32)[..., None] / 255.0
    merged = np.asarray(base).astype(np.float32) * (1 - m) + np.asarray(var).astype(np.float32) * m
    merged[..., 3] = np.asarray(alpha)
    return Image.fromarray(np.clip(merged + 0.5, 0, 255).astype(np.uint8), "RGBA")


def spec_report(canvas, fmeta):
    """Automatic check of a canvas against docs/dev/art-style.md section 2 (1024x2048 RGBA, soles at
    y=1990, head top >= 40, >= 24 px margins left/right/top, no scale-down notes)."""
    probs = []
    if canvas.size != tuple(post.CANVAS) or canvas.mode != "RGBA":
        probs.append("canvas %s %s, spec %dx%d RGBA" % (canvas.size, canvas.mode, post.CANVAS[0], post.CANVAS[1]))
    try:
        feet = post.figure_metrics(canvas)["feet"]
    except ValueError:
        return {"ok": False, "problems": probs + ["no opaque figure"]}
    if abs(feet - post.FEET_Y) > 2:
        probs.append("soles at y=%d, spec %d" % (feet, post.FEET_Y))
    tr = fmeta.get("transform") or {}
    crown = tr.get("crown_y")
    if crown is None:
        probs.append("head top unknown (face box from proportions only)")
    elif crown < post.HEAD_TOP_MIN:
        probs.append("head top at y=%.0f, spec >= %d" % (crown, post.HEAD_TOP_MIN))
    bb = post.alpha_bbox(canvas)
    W, H = canvas.size
    margins = {"left": bb[0], "right": W - bb[2], "top": bb[1], "bottom": H - bb[3]} if bb else {}
    for k in ("left", "right", "top"):
        if bb and margins[k] < post.MARGIN - 1:
            probs.append("%s margin %d px, spec >= %d" % (k, margins[k], post.MARGIN))
    probs += [n for n in tr.get("notes", []) if "too wide" in n or "too tall" in n]
    return {"ok": not probs, "problems": probs, "margins": margins, "feet_row": feet, "crown_y": crown}


def face_problem(box, fm):
    """None when `box` (x, y, w, h) looks like the head of a standing full-body figure with metrics
    `fm` (post.figure_metrics), else the reason."""
    x, y, w, h = box
    fig_h = max(1.0, float(fm["feet"] - fm["top"]))
    frac = (y + h / 2.0 - fm["top"]) / fig_h
    if not 0.0 <= frac <= 0.3:
        return "face centre at %.0f%% of the figure height (expected the top 30%%)" % (100 * frac)
    if not 0.025 <= h / fig_h <= 0.2:
        return "face height is %.1f%% of the figure (expected 2.5-20%%)" % (100 * h / fig_h)
    x0, _y0, x1, _y1 = fm["bbox"]
    if x + w / 2.0 < x0 or x + w / 2.0 > x1:
        return "face centre outside the figure"
    return None


def proportional_face_box(fm):
    """A face box from body proportions only (no inpainting is done with it; placement then ignores
    the crown, as post.place_on_canvas does for 'proportions-only (low)')."""
    hh = (fm["feet"] - fm["top"]) / 7.6
    return [int(round(fm["axis_x"] - 0.35 * hh)), int(round(fm["top"] + 0.35 * hh)), int(round(0.7 * hh)),
            int(round(0.68 * hh))]


def env_info():
    info = {"python": platform.python_version(), "machine": platform.machine(), "cpus": os.cpu_count()}
    try:
        with open("/proc/cpuinfo") as f:
            for line in f:
                if line.startswith("model name"):
                    info["cpu"] = line.split(":", 1)[1].strip()
                    break
        with open("/proc/meminfo") as f:
            info["mem_gb"] = round(int(f.readline().split()[1]) / 1024 / 1024, 1)
    except OSError:
        pass
    for mod in ("torch", "diffusers", "transformers", "nudenet", "rembg", "onnxruntime"):
        try:
            info[mod] = __import__(mod).__version__
        except Exception:       # noqa: BLE001
            pass
    return info


def save_tmp(work, img, name, **kw):
    p = os.path.join(work, name)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    img.save(p, **kw)
    return p


def to_webp(path, quality=90):
    """Re-save a review PNG as WebP next to it (deletes the PNG). Returns the new path."""
    out = os.path.splitext(path)[0] + ".webp"
    with Image.open(path) as im:
        im.load()
        im.save(out, format="WEBP", quality=quality, method=6)
    os.remove(path)
    return out


def encode_all(comps, texts, job):
    t0 = time.time()
    enc = comps["encoders"]()
    embs = {k: enc.encode_pair(*v) for k, v in texts.items()}
    enc.close()
    del enc
    gc.collect()
    job["timing"]["encode_s"] = round(time.time() - t0, 1)
    return embs


# ------------------------------------------------------------------ filter + cover repair
WEBP_KW = {"format": "WEBP", "quality": 95, "method": 6}


def publish_screened(a, pub, eng, cover_emb, img, tmp, rel, seed, est, job, save_kw=None):
    """Publish `img` (already saved at `tmp`, in the work dir) through the exposure filter. When it is
    flagged: cover-repair the flagged regions (config.REPAIR) and publish the repaired image only if it
    passes the full filter again; else record the drop. The unrepaired original is deleted by the filter
    and never reaches the upload dir.
    Returns (dest or None, the published image or None, repair record or None, last filter report)."""
    save_kw = save_kw or WEBP_KW
    dest = pub.publish(tmp, rel, defer_drop=True)
    first = pub.last_report or {}
    if dest:
        return dest, img, None, first
    R = C.REPAIR
    rec = {"original": {k: first[k] for k in ("scores", "flagged", "error") if k in first},
           "settings": {k: R[k] for k in ("denoise", "steps", "px", "pad", "context", "box_conf_frac", "near_frac")},
           "attempts": [], "result": None}

    def give_up(why):
        last = pub.last_report or first
        rec["result"] = "dropped: " + why
        pub.record_drop(rel, dict(last, repair=rec))
        log("  cover repair of %s: %s -> dropped" % (rel, why))
        return None, None, rec, last

    if first.get("error") or not first.get("flagged"):
        return give_up("filter error (no repair)")
    if cover_emb is None:
        return give_up("repair off (%s)" % ("--no-repair" if a.no_repair else "bf16 run: inpaint is fp32 only"))
    fs = preset_settings(C.FINAL_PRESET)
    cur, last = img.convert("RGB"), first
    for k in range(R["attempts"]):
        classes = pub.filt.cover_classes(last, R["near_frac"])
        try:
            boxes = pub.filt.flag_boxes(cur, classes, R["box_conf_frac"])
        except Exception as e:      # noqa: BLE001  (cannot localise: drop as before)
            return give_up("detector boxes unavailable: %s: %s" % (type(e).__name__, e))
        pl = repair.plan(boxes, cur.size, R)
        att = {"attempt": k + 1, "classes": classes, "boxes": sorted(boxes, key=lambda b: -b["score"])[:40],
               "regions": pl["regions"], "area_frac": pl["area_frac"], "crops": [c["crop"] for c in pl["clusters"]],
               "seeds": [], "inpaints": []}
        rec["attempts"].append(att)
        if not pl["ok"]:
            return give_up(pl["why"])
        need = len(pl["clusters"]) * est.seconds(R["px"], R["px"], R["steps"]) + 60
        if not a.deadline.allows(need):
            return give_up("time budget (%.0f min left, the repair needs about %.0f)" % (a.deadline.left() / 60,
                                                                                        need / 60))
        log("  cover repair of %s, pass %d: %s -> %d region(s) %s in %d crop(s)" % (
            rel, k + 1, json.dumps(classes), len(pl["regions"]), pl["regions"], len(pl["clusters"])))
        t0 = time.time()
        try:
            for ci, cl in enumerate(pl["clusters"]):
                s = seed + R["seed_offset"] + 10 * k + ci
                cur, info = crop_inpaint(eng, cover_emb, cur, tuple(cl["crop"]), repair.mask(cur.size, cl["regions"]),
                                         R["denoise"], s, fs, R["steps"], R["px"], grow=4, feather=R["feather"])
                est.learn(info, R["px"], R["px"])
                att["seeds"].append(s)
                att["inpaints"].append({k2: info.get(k2) for k2 in ("seconds", "s_per_step", "steps_run", "steps_effective",
                                                                    "num_inference_steps", "vmhwm_gb", "crop", "px")})
                job["images"].append(dict({k2: v for k2, v in info.items() if k2 != "step_s"}, seed=s,
                                          step="cover_repair", rel=rel))
        except Exception as e:      # noqa: BLE001
            log("ERROR in the cover repair of %s: %s\n%s" % (rel, e, traceback.format_exc()))
            return give_up("repair inpaint failed: %s: %s" % (type(e).__name__, e))
        att["seconds"] = round(time.time() - t0, 1)
        cur = cur.convert("RGB")
        tmp2 = save_tmp(os.path.dirname(tmp), cur, os.path.basename(tmp), **save_kw)
        summary = {"repair": {"passes": k + 1, "regions": pl["regions"], "classes": classes,
                              "original_scores": first.get("scores")}}
        dest = pub.publish(tmp2, rel, defer_drop=True, extra=summary)
        last = pub.last_report or {}
        att["after"] = {k2: last[k2] for k2 in ("scores", "flagged", "error") if k2 in last}
        if dest:
            pub.count_repaired()
            rec["result"] = "published after %d repair pass(es)" % (k + 1)
            log("  cover repair of %s: passed the full filter after pass %d (%.0f s)" % (rel, k + 1, att["seconds"]))
            return dest, cur, rec, last
        if last.get("error"):
            return give_up("filter error on the repaired image")
    return give_up("still flagged after %d repair pass(es)" % R["attempts"])


def cover_text(a, bible, hero, sname):
    """The cover-repair prompt pair (checked), or None when the repair is off for this run."""
    if a.no_repair or a.dtype != "fp32":
        return None
    c = style.cover(bible, hero, sname)
    return checked(bible, hero, c["positive"], c["negative"])


# ------------------------------------------------------------------ candidates
def run_candidates(a, bible, pub, comps, job):
    hero = a.hero
    p = preset_settings(a.preset)
    sty = style.full_body(bible, hero, a.style)
    pos, neg = checked(bible, hero, sty["positive"], sty["negative"])
    w, h = p["width"], p["height"]
    texts = {"base": (pos, neg)}
    cover = cover_text(a, bible, hero, a.style)
    if cover:
        texts["cover"] = cover
    embs = encode_all(comps, texts, job)
    emb = embs["base"]
    eng = comps["engine"](dtype=a.dtype, lazy_unet=False)
    job["engine"] = dict(getattr(eng, "info", {}) or {})
    job["timing"]["engine_load_s"] = round(getattr(eng, "load_s", 0.0), 1)
    est = _Est()
    rc = 0
    for seed in a.seeds:
        if not a.deadline.allows(job["timing"].get("last_image_s", 0) * 1.3 + 120):
            log("time budget exhausted: skipping seed %d and later" % seed)
            job["skipped"].append(seed)
            continue
        stem = "%s_s%d" % (hero, seed)
        try:
            img, info = eng.txt2img(emb, seed, p["steps"], p["cfg"], p["sampler"], w, h)
        except Exception as e:      # noqa: BLE001  (next seed; the job still uploads what it has)
            log("ERROR rendering %s: %s\n%s" % (stem, e, traceback.format_exc()))
            job["errors"].append({"seed": seed, "stage": "txt2img", "error": "%s: %s" % (type(e).__name__, e)})
            rc = 5
            continue
        job["timing"]["last_image_s"] = info["seconds"]
        job["images"].append(dict(info, seed=seed))
        est.learn(info, w, h)
        try:
            _cut, rep = post.candidate_report(img, expected_bg=sty["bg_rgb"])
        except Exception as e:      # noqa: BLE001  (review aid only)
            rep = {"error": str(e)}
        tmp = save_tmp(a.work, img, stem + ".webp", **WEBP_KW)
        rel = "%s/%s.webp" % (hero, stem)
        dest, _pimg, rrec, frep = publish_screened(a, pub, eng, embs.get("cover"), img, tmp, rel, seed, est, job)
        del img, _pimg
        meta = {"hero": hero, "mode": "candidates", "seed": seed, "image": os.path.basename(dest) if dest else None,
                "dropped": dest is None, "width": w, "height": h, "preset": a.preset, "preset_settings": p,
                "dtype": a.dtype, "family": C.FAMILY, "style": sty["style"], "prompt": pos, "negative": neg,
                "prompt_chunks": emb.get("chunks"), "background": {"key": sty["background_key"], "rgb": sty["bg_rgb"]},
                "model": {"repo": C.MODEL["repo"], "license": C.MODEL["license"]}, "lora": None,
                "render": info, "framing": rep,
                "filter": frep.get("scores") if dest else frep,
                "repair": rrec, "cover_prompt": {"positive": cover[0], "negative": cover[1]} if (rrec and cover) else None,
                "run": job["run"], "created": stamp()}
        pub.write_json("%s/%s.json" % (hero, stem), meta)
        log("candidate %s: %s in %.0f s (%s)" % (
            stem, ("published after a cover repair" if rrec else "published") if dest else "DROPPED by the filter",
            info["seconds"], ",".join(rep.get("flags", [])) or "framing ok"))
    return rc


# ------------------------------------------------------------------ final
class _Est:
    """Stage time estimates, refined from the measured s/step after every sampled stage."""

    def __init__(self):
        self.ref = float(C.FINAL["ref_s_per_step_mp"])

    def seconds(self, w, h, steps):
        return schedule.estimate_s(self.ref, w, h, steps, C.FINAL["stage_overhead_s"], C.FINAL["mp_exponent"])

    def learn(self, info, w, h):
        sps = info.get("s_per_step")
        if sps:
            self.ref = schedule.ref_from_measure(sps, w, h, C.FINAL["mp_exponent"])


def run_final(a, bible, pub, comps, job):
    hero = a.hero
    h = bible["heroes"][hero]
    fs = final_settings(bible, a)
    names = [v.strip() for v in (a.variants.split(",") if a.variants else h["variant_set"]) if v.strip()]
    if a.no_variants:
        names = []
    # 0. every source and every text first: a missing candidate or a refused prompt stops the job
    #    before anything heavy is loaded
    plans = []
    for seed in a.seeds:
        if a.no_source:
            p = preset_settings(a.preset)
            sty = style.full_body(bible, hero, a.style)
            pos, neg = checked(bible, hero, sty["positive"], sty["negative"])
            plans.append({"seed": seed, "pos": pos, "neg": neg, "style": a.style, "base_settings": p,
                          "w": p["width"], "h": p["height"], "preview": None, "source": None})
            continue
        try:
            meta, preview, src = comps["fetch"](a.repo, a.source_run, hero, seed)
        except SourceError as e:
            log("ERROR: final source for %s s%d: %s (nothing rendered; pass --no-source to render a base)" % (
                hero, seed, e))
            job["errors"].append({"seed": seed, "stage": "source", "error": str(e)})
            return 6
        sname = src["style"] if src["style"] in C.STYLES else "bible"
        # the candidate's own positive (it describes this image) + its negative joined with today's
        # (new model-card or content-rule negatives apply to the passes that are still to come); a farm
        # candidate also gets today's exposure hardening (weighted negatives first, tag swaps)
        pos = style.harden_positive(bible, hero, sname, meta["prompt"])
        neg = style.harden_negative(bible, hero, sname, prompts.join_tags(
            meta["negative"], style.full_body(bible, hero, sname)["negative"]))
        pos, neg = checked(bible, hero, pos, neg)
        plans.append({"seed": seed, "pos": pos, "neg": neg, "style": sname, "base_settings": src["preset_settings"],
                      "w": preview.width, "h": preview.height, "preview": preview, "source": src})
        log("final %s s%d: source %s (sha256 %s, preset %s, style %s)" % (hero, seed, src["path"], src["sha256"][:12],
                                                                          src["preset"], sname))
    texts = {}
    for i, p in enumerate(plans):
        texts["base%d" % i] = (p["pos"], p["neg"])
        sname = p["style"]
        if "face:" + sname not in texts:
            f = style.face(bible, hero, sname)
            texts["face:" + sname] = checked(bible, hero, f["positive"], f["negative"])
            cov = cover_text(a, bible, hero, sname)
            if cov:
                texts["cover:" + sname] = cov
            for n in names:
                vp = style.face(bible, hero, sname, variant=n)
                texts["v:%s:%s" % (sname, n)] = checked(bible, hero, vp["positive"], vp["negative"])
    embs = encode_all(comps, texts, job)
    eng = comps["engine"](dtype="fp32", lazy_unet=True)
    job["engine"] = dict(getattr(eng, "info", {}) or {})
    finder = Lazy(comps["faces"], "anime face detector", job)
    cutter = Lazy(comps["cutter"], "rembg isnet-anime", job)
    est = _Est()
    rc = 0
    for i, p in enumerate(plans):
        ctx = {}
        try:
            res = _final_one(a, bible, pub, job, eng, embs, texts, i, p, fs, names, finder, cutter, est, ctx)
        except Exception as e:      # noqa: BLE001  (the next seed still runs; finished stages are uploaded)
            log("ERROR in final %s s%d: %s\n%s" % (hero, p["seed"], e, traceback.format_exc()))
            job["errors"].append({"seed": p["seed"], "stage": "final", "error": "%s: %s" % (type(e).__name__, e)})
            if "save" in ctx:
                ctx["meta"]["errors"].append("%s: %s" % (type(e).__name__, e))
                ctx["save"]("failed after %s" % ctx["meta"]["status"])
            res = 5
        rc = rc or res
    return rc


def _final_one(a, bible, pub, job, eng, embs, texts, i, p, fs, names, finder, cutter, est, ctx):
    hero = a.hero
    h = bible["heroes"][hero]
    seed = p["seed"]
    tag = "final_s%d" % seed
    wdir = os.path.join(a.work, hero, tag)
    fdir = os.path.join(wdir, "final")
    os.makedirs(fdir, exist_ok=True)
    rel = "%s/%s" % (hero, tag)
    steps = []
    meta = {"hero": hero, "mode": "final", "seed": seed, "status": "started", "source_candidate": p["source"],
            "style": style.record(p["style"]), "settings": fs, "base_settings": p["base_settings"],
            "family": C.FAMILY, "prompt": p["pos"], "negative": p["neg"],
            "model": {"repo": C.MODEL["repo"], "license": C.MODEL["license"]}, "lora": None,
            "steps": steps, "errors": [], "skipped": [], "outputs": [], "run": job["run"], "created": stamp()}

    def save(status):
        meta["status"] = status
        meta["updated"] = stamp()
        pub.write_json("%s/%s.json" % (rel, hero), meta)

    ctx.update(save=save, meta=meta)

    def publish(path, name):
        dest = pub.publish(path, "%s/%s" % (rel, name))
        if dest:
            meta["outputs"].append(name)
        else:
            meta.setdefault("dropped", []).append(name)
        return dest

    def screened(name, image):
        """Publish a stage image through the filter with the cover repair; the image to continue with
        (the repaired one when a repair was needed) or None when it was dropped."""
        tmp = save_tmp(wdir, image, name, **WEBP_KW)
        dest, out, rrec, _rep = publish_screened(a, pub, eng, embs.get("cover:" + p["style"]), image, tmp,
                                                 "%s/%s" % (rel, name), seed, est, job)
        if rrec:
            meta.setdefault("repairs", {})[name] = rrec
        if dest:
            meta["outputs"].append(name)
            return out
        meta.setdefault("dropped", []).append(name)
        return None

    def stage_done(rec):
        steps.append(rec)
        job["images"].append(dict(rec, seed=seed))
        job["stage_mem"].append({"seed": seed, "step": rec["step"], "vmhwm_gb": rec.get("vmhwm_gb"),
                                 "mem": rec.get("mem_stage") or memstat.snapshot()})

    # 0. base: the published preview (already on the branch), or a fresh render with --no-source
    if p["preview"] is not None:
        base = p["preview"]
        steps.append({"step": "base", "from": p["source"]["path"], "sha256": p["source"]["sha256"]})
    else:
        bs = p["base_settings"]
        if not a.deadline.allows(est.seconds(p["w"], p["h"], bs["steps"])):
            meta["skipped"].append("base: time budget")
            save("skipped: time budget")
            return 5
        base, info = eng.txt2img(embs["base%d" % i], seed, bs["steps"], bs["cfg"], bs["sampler"], p["w"], p["h"])
        est.learn(info, p["w"], p["h"])
        stage_done({"step": "base", **info})
        publish(save_tmp(wdir, base, "%s_base.webp" % hero, format="WEBP", quality=95, method=6), "%s_base.webp" % hero)
    save("base")

    # 1. hires
    W2, H2 = round8(p["w"] * fs["hires_scale"]), round8(p["h"] * fs["hires_scale"])
    need = est.seconds(W2, H2, fs["hires_steps"]) + 300
    if not a.deadline.allows(need):
        log("  time budget: %.0f min left, hires needs about %.0f: no hires, no canvas" % (a.deadline.left() / 60, need / 60))
        meta["skipped"].append("hires: time budget")
        save("skipped: time budget")
        return 5
    img, info = eng.hires(embs["base%d" % i], base, (W2, H2), fs["hires_denoise"], seed + 1, fs["hires_steps"],
                          fs["cfg"], fs["sampler"])
    img = img.convert("RGB")
    est.learn(info, W2, H2)
    stage_done({"step": "hires_img2img", "seed": seed + 1, **info})
    img = screened("%s_hires.webp" % hero, img)
    if img is None:
        log("  the hires image was dropped by the filter (after the cover repair): no face polish, no canvas")
        meta["errors"].append("hires image dropped by the exposure filter")
        save("hires dropped")
        return 5
    save("hires")

    # 2. face box + face polish. Only a plausible detector box is used for inpainting: the skin
    #    heuristic can land on the chest or inside a halo, and a "face" painted there is worse than none.
    face_box, conf = None, None
    quick, _ = post.remove_background(img, holes=False, feather=0)
    fm = post.figure_metrics(quick)
    fd = finder.get()
    if fd is not None:
        try:
            found = fd.find(img)
            if found:
                why = face_problem(found[0], fm)
                if why:
                    log("WARNING: detector face box %s rejected: %s" % (found[0], why))
                    meta["errors"].append("face box %s rejected: %s" % (found[0], why))
                else:
                    face_box, conf = found
        except Exception as e:      # noqa: BLE001
            log("WARNING: face detector failed: %s" % e)
            meta["errors"].append("face detector failed: %s" % e)
    face_ok = face_box is not None
    if not face_ok:
        face_box, conf = proportional_face_box(fm), "proportions-only (low)"
        meta["skipped"] += ["face polish: no face box", "variants: no face box"]
        meta["errors"].append("no usable face box (detector unavailable or implausible)")
        log("  no usable face box: no face polish, no variants; canvas placed by proportions")
    log("  face box %s (%s)" % (face_box, conf))
    if a.no_face_polish:
        meta["skipped"].append("face polish: --no-face-polish")
    elif face_ok:
        crop = P.square_box(face_box, img.size, scale=C.FINAL["face_crop_scale"])
        need = est.seconds(fs["face_px"], fs["face_px"], fs["face_steps"]) + 300
        if not a.deadline.allows(need):
            log("  time budget: skipping the face polish")
            meta["skipped"].append("face polish: time budget")
        else:
            fr = bible["regions"]["face"]
            mask = P.ellipse_mask(img.size, post.region_box(face_box, fr), feather=max(3, face_box[3] // 30))
            img, info = crop_inpaint(eng, embs["face:" + p["style"]], img, crop, mask, fs["face_denoise"], seed + 7, fs,
                                     fs["face_steps"], fs["face_px"])
            est.learn(info, fs["face_px"], fs["face_px"])
            stage_done({"step": "face_polish", **info})
    img = screened("%s_source.webp" % hero, img)
    if img is None:
        log("  the source image was dropped by the filter (after the cover repair): no canvas")
        meta["errors"].append("source image dropped by the exposure filter")
        save("source dropped")
        return 5
    save("face")

    # 3. cutout + canvas
    t0 = time.time()
    isnet = None
    ct = cutter.get()
    if ct is not None:
        try:
            isnet = ct.mask(img)
        except Exception as e:      # noqa: BLE001
            log("WARNING: isnet mask failed, colour-flood cutout instead: %s" % e)
    rgba, cinfo = cutout.artgen_cutout(img, isnet)
    stage_done({"step": "cutout", "method": cinfo["method"], "seconds": round(time.time() - t0, 1), "detail": cinfo})
    bg_meas = [int(round(v)) for v in post.estimate_bg(post._rgb(img))]
    fmeta = post.finalize_local(hero, rgba, fdir, face_box=face_box, face_source=conf,
                                skin_profile=P.skin_profile(bible, hero), flip=a.flip)
    canvas_path = os.path.join(fdir, hero + ".png")
    canvas = Image.open(canvas_path).convert("RGBA")
    spec = spec_report(canvas, fmeta)
    log("  canvas spec: %s" % ("ok" if spec["ok"] else "; ".join(spec["problems"])))
    fmeta.pop("hero", None)
    meta.update({k: v for k, v in fmeta.items() if k not in ("steps",)})
    meta.update({"image": hero + ".png", "spec": spec, "bg_measured": bg_meas, "cutout_detail": cinfo})
    canvas_dest = publish(canvas_path, hero + ".png")
    publish(os.path.join(fdir, hero + "_portrait.png"), hero + "_portrait.png")
    for kind in ("check", "boxes"):
        publish(to_webp(os.path.join(fdir, "%s_%s.png" % (hero, kind))), "%s_%s.webp" % (hero, kind))
    save("canvas")
    if not canvas_dest:
        log("  the canvas was dropped by the filter: no variants for this seed")
        meta["errors"].append("canvas dropped by the exposure filter")
        save("canvas dropped")
        return 5

    # 4. expression variants on the canvas, each isolated
    rc = 0
    if not face_ok:
        names = []
        rc = 5
    fbc = meta["face_box"]
    vrec = {"hero": hero, "base": "%s.png" % hero, "base_sha": safety.sha256_file(canvas_dest), "face_box": fbc,
            "face_box_source": meta.get("face_box_source"), "bg_rgb": bg_meas, "variants": {},
            "warp_overlay_hints": {"_doc": "rects for <id>.warp_src.json overlays (eyes / mouth slots)",
                                   "eyes": post.region_box(fbc, bible["regions"]["eyes"]),
                                   "mouth": post.region_box(fbc, bible["regions"]["mouth"]),
                                   "base_eyes": h.get("default_eyes", "open")}}
    vdir = os.path.join(wdir, "variants")
    os.makedirs(os.path.join(vdir, "candidates"), exist_ok=True)
    os.makedirs(os.path.join(wdir, "masks"), exist_ok=True)
    rgb = P.flat_rgb(canvas, bg_meas)
    vcrop = P.square_box(fbc, canvas.size, scale=C.FINAL["variant_crop_scale"])
    first = int(h["seed_base"]) + C.FINAL["variant_seed_offset"]
    var_imgs = []
    for n in names:
        need = est.seconds(fs["variant_px"], fs["variant_px"], fs["variant_steps"]) * max(1, a.variant_tries) + 60
        if not a.deadline.allows(need):
            log("  time budget: skipping variant %s" % n)
            vrec["variants"][n] = {"skipped": "time budget"}
            meta["skipped"].append("variant %s: time budget" % n)
            job["skipped"].append("%s s%d variant %s" % (hero, seed, n))
            continue
        try:
            spec_v = prompts.variant_spec(bible, hero, n)
            region = post.region_box(fbc, spec_v["region_frac"])
            feather = max(3, region[3] // 10)
            vmask = P.ellipse_mask(canvas.size, region, feather=feather)
            mpath = os.path.join(wdir, "masks", "%s.png" % spec_v["region"])
            if not os.path.exists(mpath):
                vmask.save(mpath)
                publish(mpath, "masks/%s.png" % spec_v["region"])
            tries = []
            for k in range(max(1, a.variant_tries)):
                vseed = first + k
                out_rgb, info = crop_inpaint(eng, embs["v:%s:%s" % (p["style"], n)], rgb, vcrop, vmask, spec_v["denoise"],
                                             vseed, fs, fs["variant_steps"], fs["variant_px"])
                est.learn(info, fs["variant_px"], fs["variant_px"])
                var = merge_variant(canvas, out_rgb, vmask)
                probs = post.variant_alignment(canvas, var, allowed_rect=region, margin=3 * feather + 2)
                tries.append({"seed": vseed, "alignment_problems": probs, "image": var,
                              **{k2: v2 for k2, v2 in info.items() if k2 != "step_s"}})
                stage_done({"step": "variant_" + n, **info})
            pick = tries[0]
            vpath = os.path.join(vdir, n + ".png")
            pick["image"].save(vpath)
            patch, prect = V.patch_from(pick["image"], canvas, region)
            ppath = os.path.join(vdir, n + "_patch.png")
            patch.save(ppath)
            vdest = publish(vpath, "variants/%s.png" % n)
            publish(ppath, "variants/%s_patch.png" % n)
            pub.write_json("%s/variants/%s_patch.json" % (rel, n), {"rect": prect, "seed": pick["seed"],
                                                                    "region": spec_v["region"], "base_sha": vrec["base_sha"]})
            if a.variant_tries > 1:
                for t in tries:
                    cp = os.path.join(vdir, "candidates", "%s_s%d.png" % (n, t["seed"]))
                    t["image"].save(cp)
                    publish(cp, "variants/candidates/%s_s%d.png" % (n, t["seed"]))
            vrec["variants"][n] = {"picked_seed": pick["seed"], "published": bool(vdest), "region": region,
                                   "region_name": spec_v["region"], "denoise": spec_v["denoise"],
                                   "prompt": texts["v:%s:%s" % (p["style"], n)][0],
                                   "tries": [{k2: v2 for k2, v2 in t.items() if k2 != "image"} for t in tries]}
            if vdest:
                var_imgs.append((n, pick["image"]))
        except Exception as e:      # noqa: BLE001  (isolate: the next variant still runs)
            log("ERROR in variant %s of %s s%d: %s\n%s" % (n, hero, seed, e, traceback.format_exc()))
            vrec["variants"][n] = {"error": "%s: %s" % (type(e).__name__, e)}
            meta["errors"].append("variant %s: %s: %s" % (n, type(e).__name__, e))
            rc = 5
        pub.write_json("%s/variants/variants.json" % rel, vrec)
        save("variant " + n)

    # 5. face review sheet
    try:
        sq = P.square_box(fbc, canvas.size, scale=2.4)
        entries = [(canvas.crop(sq), "base")] + [(im.crop(sq), n) for n, im in var_imgs]
        sp = post.contact_sheet(entries, os.path.join(wdir, "variants_sheet.png"), cols=len(entries), cell_w=300,
                                detail=False, title="%s s%d: base + variants" % (hero, seed))
        publish(to_webp(sp), "variants_sheet.webp")
    except Exception as e:      # noqa: BLE001
        log("WARNING: variants sheet failed: %s" % e)
        meta["errors"].append("variants sheet: %s" % e)
    pub.write_json("%s/variants/variants.json" % rel, vrec)
    save("done" if not meta["errors"] else "done with errors")
    log("final %s s%d done: canvas, %d variant(s), spec %s" % (hero, seed, len(var_imgs), "ok" if spec["ok"] else "NOT ok"))
    return rc


# ------------------------------------------------------------------ bench
def run_bench(a, bible, pub, comps, job):
    """s/step at 4 and 2 threads in fp32 (then bf16 at the faster count on native-bf16 CPUs); no images."""
    p = preset_settings(a.preset)
    sty = style.full_body(bible, a.hero, a.style)
    emb = encode_all(comps, {"base": checked(bible, a.hero, sty["positive"], sty["negative"])}, job)["base"]
    res = []
    eng = comps["engine"](dtype="fp32", lazy_unet=False)
    native = bool((getattr(eng, "info", {}) or {}).get("bf16_native"))
    for th in (4, 2):
        eng.set_threads(th)
        _none, info = eng.bench(emb, a.bench_steps, p["cfg"], p["sampler"], p["width"], p["height"])
        res.append({"dtype": "fp32", "threads": th, **info})
    best = min(res, key=lambda r: r.get("s_per_step_steady") or 1e9)["threads"]
    if native:
        eng.close()
        del eng
        gc.collect()
        eng = comps["engine"](dtype="bf16", threads=best, lazy_unet=False)
        _none, info = eng.bench(emb, a.bench_steps, p["cfg"], p["sampler"], p["width"], p["height"])
        res.append({"dtype": "bf16", "threads": best, **info})
    job["bench"] = {"preset": a.preset, "size": [p["width"], p["height"]], "steps": a.bench_steps,
                    "bf16_native": native, "results": res}
    log("bench: %s" % json.dumps([{k: r.get(k) for k in ("dtype", "threads", "s_per_step_steady")} for r in res]))
    return 0


# ------------------------------------------------------------------ main
def parse_seeds(s):
    out = []
    for t in str(s or "").replace(" ", "").split(","):
        if t:
            if not t.isdigit() or int(t) >= 2 ** 32:
                raise ValueError("bad seed %r" % t)
            out.append(int(t))
    if not out:
        raise ValueError("no seeds")
    return out


def build_args(argv):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("mode", choices=["candidates", "final", "bench"])
    ap.add_argument("--hero", required=True)
    ap.add_argument("--seeds", default="1", help="comma list (bench ignores it)")
    ap.add_argument("--preset", default=C.DEFAULT_PRESET, choices=sorted(C.PRESETS))
    ap.add_argument("--style", default=C.DEFAULT_STYLE, choices=sorted(C.STYLES))
    ap.add_argument("--dtype", default=C.DEFAULT_DTYPE, choices=list(C.DTYPES))
    ap.add_argument("--out", required=True, help="upload dir: only filtered images ever land here")
    ap.add_argument("--work", required=True, help="scratch dir (never uploaded)")
    ap.add_argument("--key", default="local", help="job key (matrix entry)")
    ap.add_argument("--run", default="local", help="run dir name on the output branch")
    ap.add_argument("--model-cache", default=None, help="HF cache dir for the base model")
    ap.add_argument("--threads", type=int, default=None)
    ap.add_argument("--max-minutes", type=float, default=280.0, help="soft budget; later stages are skipped")
    ap.add_argument("--repo", default=os.environ.get("GITHUB_REPOSITORY") or "u-tek/game",
                    help="final: repository whose art-gen-output branch holds the candidate")
    ap.add_argument("--source-run", default=None, help="final: run dir of the chosen candidate (required)")
    ap.add_argument("--no-source", action="store_true", help="final: render the base from the bible (local/tests)")
    ap.add_argument("--flip", action="store_true", help="final: mirror (the spec wants a 3/4 view facing right)")
    ap.add_argument("--hires-scale", type=float, default=None, help="default: bible hires.scale")
    ap.add_argument("--hires-denoise", type=float, default=None, help="default: bible hires.denoise_model")
    ap.add_argument("--hires-steps", type=int, default=None, help="effective steps (default: bible hires.steps)")
    ap.add_argument("--face-steps", type=int, default=C.FINAL["face_steps"], help="effective steps")
    ap.add_argument("--face-px", type=int, default=C.FINAL["face_px"])
    ap.add_argument("--variant-steps", type=int, default=C.FINAL["variant_steps"], help="effective steps")
    ap.add_argument("--variant-px", type=int, default=C.FINAL["variant_px"])
    ap.add_argument("--variants", default=None, help="final: comma list (default: the hero's variant_set)")
    ap.add_argument("--variant-tries", type=int, default=1)
    ap.add_argument("--no-variants", action="store_true")
    ap.add_argument("--no-face-polish", action="store_true")
    ap.add_argument("--no-repair", action="store_true", help="no cover repair: a flagged image is dropped at once")
    ap.add_argument("--bench-steps", type=int, default=3)
    a = ap.parse_args(argv)
    a.seeds = parse_seeds(a.seeds)
    a.deadline = Deadline(a.max_minutes)
    probs = C.preset_problems(C.PRESETS[a.preset])
    if probs:
        ap.error("preset %s refused: %s" % (a.preset, "; ".join(probs)))
    if a.mode == "final" and a.dtype != "fp32":
        ap.error("final mode runs in fp32 only")
    if a.mode == "final" and not a.no_source and not a.source_run:
        ap.error("final mode needs --source-run (the candidate's run dir) or --no-source")
    if a.source_run and not RUN_RE.match(a.source_run):
        ap.error("bad --source-run")
    if not 1 <= a.variant_tries <= 4 or not 1 <= a.bench_steps <= 8:
        ap.error("--variant-tries 1..4, --bench-steps 1..8")
    for k in ("face_px", "variant_px"):
        if getattr(a, k) % 64 or not 512 <= getattr(a, k) <= 1024:
            ap.error("--%s must be a multiple of 64 in 512..1024" % k.replace("_", "-"))
    return a


def main(argv=None, components=None):
    try:
        a = build_args(argv)
    except SystemExit as e:
        return e.code if isinstance(e.code, int) else 2
    bible = prompts.load_bible()
    if a.hero not in bible["heroes"]:
        log("ERROR: unknown hero %r" % a.hero)
        return 2
    os.makedirs(a.work, exist_ok=True)
    comps = dict(components or {})
    # The filter comes first: without it nothing may be published, so do not spend hours rendering.
    try:
        filt = comps["filter"]() if "filter" in comps else safety.ExposureFilter(log=log)
        filt.selftest()
    except safety.FilterUnavailable as e:
        log("ERROR: exposure filter unavailable, refusing to render (fail closed): %s" % e)
        return 3
    job = {"key": a.key, "run": a.run, "hero": a.hero, "mode": a.mode, "seeds": a.seeds, "preset": a.preset,
           "preset_settings": C.PRESETS[a.preset], "style": a.style, "dtype": a.dtype if a.mode != "final" else "fp32",
           "env": env_info(), "timing": {}, "images": [], "stage_mem": [], "skipped": [], "errors": [],
           "started": stamp(), "licenses": {"model": C.MODEL, "aux": C.AUX}}
    pub = safety.Publisher(filt, a.out, log=log, job={"key": a.key, "run": a.run, "hero": a.hero, "mode": a.mode})
    if "encoders" not in comps or "engine" not in comps:
        import sdxl
        model_dir, variants, minfo = sdxl.fetch_model(a.model_cache, log=log)
        job["model"] = {k: v for k, v in minfo.items() if k != "repo_files"}
        job["timing"]["download_s"] = minfo["download_s"]
        comps.setdefault("encoders", lambda: real_encoders(model_dir, variants))
        comps.setdefault("engine", lambda **kw: real_engine(model_dir, variants, **dict({"threads": a.threads}, **kw)))
    comps.setdefault("cutter", RembgCutter)
    comps.setdefault("faces", AnimeFaceFinder)
    comps.setdefault("fetch", fetch_candidate)
    rc = 0
    try:
        if a.mode == "candidates":
            rc = run_candidates(a, bible, pub, comps, job)
        elif a.mode == "final":
            rc = run_final(a, bible, pub, comps, job)
        else:
            rc = run_bench(a, bible, pub, comps, job)
    except (prompts.ContentRuleError, prompts.PromptError) as e:
        log("ERROR: prompt refused: %s" % e)
        rc = 4
    except Exception as e:      # noqa: BLE001  (the job record and the finished outputs still upload)
        log("ERROR: %s: %s\n%s" % (type(e).__name__, e, traceback.format_exc()))
        job["errors"].append({"stage": "job", "error": "%s: %s" % (type(e).__name__, e)})
        rc = 5
    finally:
        job["filter"] = dict(filt.stats)
        job["finished"] = stamp()
        job["wall_s"] = round(time.time() - T_START, 1)
        job["exit_code"] = rc
        imgs = [i for i in job["images"] if str(i.get("what", "")).startswith("txt2img")]
        if imgs:
            job["timing"]["s_per_txt2img"] = round(sum(i["seconds"] for i in imgs) / len(imgs), 1)
        pub.write_json("%s/job_%s.json" % (a.hero, a.key), job)
        log(pub.summary())
        if job["skipped"]:
            print("::warning::art-gen %s skipped (time budget): %s" % (a.key, ", ".join(map(str, job["skipped"]))))
        log("job %s finished in %.1f min (exit %d), timings %s" % (a.key, job["wall_s"] / 60, rc, json.dumps(job["timing"])))
    return rc


if __name__ == "__main__":
    sys.exit(main())
