#!/usr/bin/env python3
"""Art farm renderer: anime SDXL (cagliostrolab/animagine-xl-4.0) on a CPU runner, fp32.

    gen.py candidates --hero ID --seeds 101000,101001 [--preset lightning8] --out DIR --work DIR
    gen.py final      --hero ID --seeds 101001 [--source-run RUN] [--flip] --out DIR --work DIR

Prompts come from the prompt bible through tools/comfy/prompts.py (full_body / face / variant_spec,
family "animagine"); every prompt is re-checked with prompts.enforce() right before it is encoded.
Every image goes through the exposure filter (safety.py) before it reaches --out, the only
directory the workflow uploads. Rendering happens in --work, which is never uploaded.

candidates: one fast render per seed (preset from config.PRESETS, default SDXL-Lightning 8-step),
    saved as a WebP preview + metadata JSON (prompt, negative, seed, model, LoRA, licences,
    settings, timings, framing report, filter scores).
final: per chosen seed
    1. re-render the candidate exactly (prompt/preset/size from its metadata on the art-gen-output
       branch when found, else from the bible), compare with its stored preview;
    2. full-quality img2img at 1.5x (the animagine profile: Euler a, 28 steps, CFG 5, no LoRA,
       denoise 0.45) = hires pass that keeps the chosen composition;
    3. face box (deepghs anime face detector, fallback post.estimate_face_box), face polish
       (crop inpaint at 1024 px, denoise from the bible's face_refine);
    4. cutout with rembg isnet-anime (post.alpha_from_mask edge treatment), placement on the
       1024x2048 canvas with the soles at y=1990 (post.finalize_local: portrait, check, boxes, meta);
    5. expression variants on the canvas (variant_set: eyes_open/eyes_closed, mouth_open, smile):
       crop inpaint of the eyes/mouth region only, alpha and every pixel outside the region
       identical to the base (as tools/comfy/variants.py), patches, masks, variants.json;
    6. a review sheet of the face (base + variants).
"""
import argparse
import gc
import json
import os
import platform
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import config as C  # noqa: E402  (adds tools/comfy to sys.path)
import numpy as np  # noqa: E402
from PIL import Image, ImageFilter  # noqa: E402

import pipeline as P  # noqa: E402  tools/comfy: square_box, ellipse_mask, flat_rgb, skin_profile
import post  # noqa: E402            tools/comfy: cutout edge treatment, placement, sheets
import prompts  # noqa: E402         tools/comfy: prompt bible composer + content rules
import safety  # noqa: E402
import variants as V  # noqa: E402   tools/comfy: patch_from

ROOT = C.ROOT
T_START = time.time()


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


# ------------------------------------------------------------------ prompts
def checked(bible, hero, positive, negative):
    """The single choke point before any text reaches the encoder: syntax + content rules."""
    prompts.lint(positive, negative)
    prompts.enforce(bible, hero, positive, negative)
    return positive, negative


def base_size(bible, hero):
    h = bible["heroes"][hero]
    st = prompts.family_block(bible, C.FAMILY)["settings"]
    w, hh = h.get("size") or [st["width"], st["height"]]
    return int(w), int(hh)


def round8(v):
    return int(round(v / 8.0)) * 8


def quality_settings(bible):
    st = prompts.family_block(bible, C.FAMILY)["settings"]
    return {"sampler": st["sampler"], "steps": int(st["steps"]), "cfg": float(st["cfg"])}


# ------------------------------------------------------------------ real components (runner)
def real_encoders(model_dir, variants):
    import sdxl
    return sdxl.TextEncoders(model_dir, variants, log=log)


def real_engine(model_dir, variants, threads):
    import sdxl
    return sdxl.Engine(model_dir, variants, log=log, threads=threads)


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


# ------------------------------------------------------------------ helpers
def git(*args, binary=False):
    r = subprocess.run(["git", *args], cwd=ROOT, capture_output=True)
    if r.returncode != 0:
        return None
    return r.stdout if binary else r.stdout.decode("utf-8", "replace")


def find_candidate(hero, seed, run=None, ref="origin/art-gen-output"):
    """(meta, preview PIL or None, path) of a published candidate on the output branch, newest run first."""
    listing = git("ls-tree", "-r", "--name-only", ref, "--", "runs")
    if not listing:
        return None, None, None
    want = "/%s/%s_s%d.json" % (hero, hero, seed)
    paths = [p for p in listing.splitlines() if p.endswith(want) and (not run or p.startswith("runs/%s/" % run))]

    def run_key(p):
        head = p.split("/")[1].split("-")[0]
        return int(head) if head.isdigit() else 0

    for p in sorted(paths, key=run_key, reverse=True):
        try:
            meta = json.loads(git("show", "%s:%s" % (ref, p)) or "")
        except ValueError:
            continue
        if meta.get("mode") != "candidates" or meta.get("dropped") or meta.get("hero") != hero:
            continue
        prev = None
        blob = git("show", "%s:%s" % (ref, p[:-5] + ".webp"), binary=True)
        if blob:
            import io
            try:
                prev = Image.open(io.BytesIO(blob)).convert("RGB")
            except Exception:       # noqa: BLE001
                prev = None
        return meta, prev, p
    return None, None, None


def psnr(a, b):
    x = np.asarray(a.convert("RGB")).astype(np.float32)
    y = np.asarray(b.convert("RGB").resize(a.size)).astype(np.float32)
    mse = float(((x - y) ** 2).mean())
    return 99.0 if mse <= 1e-9 else round(10 * np.log10(255.0 ** 2 / mse), 2)


def crop_inpaint(eng, emb, image, crop, mask, denoise, seed, q, target=1024, grow=6, feather=4):
    """Inpaint `mask` (full-size L, white = repaint) of an RGB image on the square `crop` scaled to
    `target` px, pasted back through a feathered mask (same as pipeline.crop_inpaint on ComfyUI)."""
    x0, y0, x1, y1 = crop
    side = x1 - x0
    src = image.crop(crop).resize((target, target), Image.LANCZOS)
    mcrop = mask.crop(crop).resize((target, target), Image.BILINEAR)
    if grow:
        mcrop = mcrop.filter(ImageFilter.MaxFilter(2 * grow + 1))
    res, info = eng.inpaint(emb, src, mcrop, denoise, seed, q["steps"], q["cfg"], q["sampler"])
    back = res.convert("RGB").resize((side, side), Image.LANCZOS)
    m_back = mask.crop(crop)
    if feather:
        m_back = m_back.filter(ImageFilter.GaussianBlur(feather))
    out = image.copy()
    out.paste(back, (x0, y0), m_back)
    info.update({"crop": [x0, y0, side, side], "denoise": denoise, "seed": seed})
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
    for mod in ("torch", "diffusers", "transformers", "peft", "nudenet", "rembg", "onnxruntime"):
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


# ------------------------------------------------------------------ modes
def run_candidates(a, bible, pub, comps, job):
    hero = a.hero
    preset = C.PRESETS[a.preset]
    pr = prompts.full_body(bible, hero, C.FAMILY)
    pos, neg = checked(bible, hero, pr["positive"], pr["negative"])
    w, h = base_size(bible, hero)
    bg_key, bg = prompts.background(bible, hero)
    t0 = time.time()
    enc = comps["encoders"]()
    emb = enc.encode_pair(pos, neg)
    enc.close()
    del enc
    gc.collect()
    job["timing"]["encode_s"] = round(time.time() - t0, 1)
    eng = comps["engine"]()
    job["timing"]["engine_load_s"] = round(getattr(eng, "load_s", 0.0), 1)
    t0 = time.time()
    eng.set_lora(preset["lora"], preset.get("lora_scale", 1.0))
    job["timing"]["lora_s"] = round(time.time() - t0, 1)
    lora = getattr(eng, "lora", None)
    for seed in a.seeds:
        if not a.deadline.allows(job["timing"].get("last_image_s", 0) * 1.3 + 120):
            log("time budget exhausted: skipping seed %d and later" % seed)
            job["skipped"].append(seed)
            continue
        stem = "%s_s%d" % (hero, seed)
        img, info = eng.txt2img(emb, seed, preset["steps"], preset["cfg"], preset["sampler"], w, h)
        job["timing"]["last_image_s"] = info["seconds"]
        job["images"].append(dict(info, seed=seed))
        try:
            _cut, rep = post.candidate_report(img, expected_bg=bg["rgb"])
        except Exception as e:      # noqa: BLE001  (review aid only)
            rep = {"error": str(e)}
        tmp = save_tmp(a.work, img, stem + ".webp", format="WEBP", quality=92, method=6)
        dest = pub.publish(tmp, "%s/%s.webp" % (hero, stem))
        meta = {"hero": hero, "mode": "candidates", "seed": seed, "image": os.path.basename(dest) if dest else None,
                "dropped": dest is None, "width": w, "height": h, "preset": a.preset, "preset_settings": preset,
                "family": C.FAMILY, "prompt": pos, "negative": neg, "prompt_chunks": emb.get("chunks"),
                "background": {"key": bg_key, "rgb": bg["rgb"]},
                "model": {"repo": C.MODEL["repo"], "license": C.MODEL["license"]},
                "lora": lora, "render": info, "framing": rep,
                "filter": pub.manifest["files"].get("%s/%s.webp" % (hero, stem), {}).get("scores")
                if dest else pub.manifest["dropped"][-1]["report"],
                "run": job["run"], "created": stamp()}
        pub.write_json("%s/%s.json" % (hero, stem), meta)
        log("candidate %s: %s in %.0f s (%s)" % (stem, "published" if dest else "DROPPED by the filter",
                                                 info["seconds"], ",".join(rep.get("flags", [])) or "framing ok"))


def run_final(a, bible, pub, comps, job):
    hero = a.hero
    h = bible["heroes"][hero]
    q = quality_settings(bible)
    bg_key, bg = prompts.background(bible, hero)
    names = [v.strip() for v in (a.variants.split(",") if a.variants else h["variant_set"]) if v.strip()]
    if a.no_variants:
        names = []
    plans = []
    for seed in a.seeds:
        meta, preview, src = (None, None, None) if a.no_source else find_candidate(hero, seed, a.source_run)
        if meta:
            pos, neg = checked(bible, hero, meta["prompt"], meta["negative"])
            preset_name = meta.get("preset") if meta.get("preset") in C.PRESETS else a.preset
            w, hh = int(meta.get("width") or base_size(bible, hero)[0]), int(meta.get("height") or base_size(bible, hero)[1])
            log("final %s s%d: candidate metadata from %s (preset %s)" % (hero, seed, src, preset_name))
        else:
            pr = prompts.full_body(bible, hero, C.FAMILY)
            pos, neg = checked(bible, hero, pr["positive"], pr["negative"])
            preset_name = a.preset
            w, hh = base_size(bible, hero)
            log("final %s s%d: no published candidate found, composing from the bible (preset %s)" % (hero, seed, preset_name))
        plans.append({"seed": seed, "pos": pos, "neg": neg, "preset": preset_name, "w": w, "h": hh,
                      "preview": preview, "source": src})
    face_pr = prompts.face(bible, hero, C.FAMILY)
    texts = {"face": checked(bible, hero, face_pr["positive"], face_pr["negative"])}
    for n in names:
        vp = prompts.face(bible, hero, C.FAMILY, variant=n)
        texts["v:" + n] = checked(bible, hero, vp["positive"], vp["negative"])
    for i, p in enumerate(plans):
        texts["base%d" % i] = (p["pos"], p["neg"])
    t0 = time.time()
    enc = comps["encoders"]()
    embs = {k: enc.encode_pair(*v) for k, v in texts.items()}
    enc.close()
    del enc
    gc.collect()
    job["timing"]["encode_s"] = round(time.time() - t0, 1)
    eng = comps["engine"]()
    job["timing"]["engine_load_s"] = round(getattr(eng, "load_s", 0.0), 1)
    cutter = comps["cutter"]()
    finder = comps["faces"]()

    for i, p in enumerate(plans):
        seed = p["seed"]
        tag = "final_s%d" % seed
        wdir = os.path.join(a.work, hero, tag)
        os.makedirs(wdir, exist_ok=True)
        rel = "%s/%s" % (hero, tag)
        steps = []
        preset = C.PRESETS[p["preset"]]
        # 1. the chosen candidate, exactly
        eng.set_lora(preset["lora"], preset.get("lora_scale", 1.0))
        base, info = eng.txt2img(embs["base%d" % i], seed, preset["steps"], preset["cfg"], preset["sampler"], p["w"], p["h"])
        rec = {"step": "base", "preset": p["preset"], "lora": getattr(eng, "lora", None), **info}
        if p["preview"] is not None:
            rec["psnr_vs_published_preview"] = psnr(base, p["preview"])
            log("  re-render vs published preview: PSNR %.1f dB" % rec["psnr_vs_published_preview"])
        steps.append(rec)
        base_tmp = save_tmp(wdir, base, "%s_base.webp" % hero, format="WEBP", quality=92, method=6)
        # 2. full-quality hires pass over it
        eng.set_lora(None)
        W2, H2 = round8(p["w"] * a.hires_scale), round8(p["h"] * a.hires_scale)
        img, info = eng.img2img(embs["base%d" % i], base.resize((W2, H2), Image.LANCZOS), a.refine_denoise,
                                seed + 1, q["steps"], q["cfg"], q["sampler"])
        img = img.convert("RGB")
        steps.append({"step": "hires_img2img", "size": [W2, H2], "denoise": a.refine_denoise, "seed": seed + 1,
                      "settings": q, **info})
        # 3. face box + face polish
        found = finder.find(img) if finder else None
        if found:
            face_box, conf = found
        else:
            quick, _ = post.remove_background(img, holes=False, feather=0)
            face_box, conf = post.estimate_face_box(quick, P.skin_profile(bible, hero))
        log("  face box %s (%s)" % (face_box, conf))
        if not a.no_face_polish:
            fr = bible["regions"]["face"]
            mbox = post.region_box(face_box, fr)
            mask = P.ellipse_mask(img.size, mbox, feather=max(3, face_box[3] // 30))
            crop = P.square_box(face_box, img.size, scale=C.FINAL["face_crop_scale"])
            den = float(bible["face_refine"]["denoise"])
            img, info = crop_inpaint(eng, embs["face"], img, crop, mask, den, seed + 7, q, target=a.inpaint_px)
            steps.append({"step": "face_polish", **info})
        src_tmp = save_tmp(wdir, img, "%s_source.webp" % hero, format="WEBP", quality=95, method=6)
        # 4. cutout + canvas
        t0 = time.time()
        mask_img = cutter.mask(img) if cutter else None
        steps.append({"step": "cutout", "method": getattr(cutter, "name", "post.remove_background"),
                      "seconds": round(time.time() - t0, 1)})
        fdir = os.path.join(wdir, "final")
        meta = post.finalize_local(hero, img, fdir, face_box=face_box, face_source=conf, mask=mask_img,
                                   skin_profile=P.skin_profile(bible, hero), flip=a.flip,
                                   extra_meta={"seed": seed, "mode": "final", "steps": steps,
                                               "model": {"repo": C.MODEL["repo"], "license": C.MODEL["license"]},
                                               "family": C.FAMILY, "prompt": p["pos"], "negative": p["neg"],
                                               "source_candidate": p["source"], "created": stamp()})
        canvas_path = os.path.join(fdir, hero + ".png")
        canvas = Image.open(canvas_path).convert("RGBA")
        fbc = meta["face_box"]
        # 5. variants on the canvas
        vrec = {"hero": hero, "base": "%s.png" % hero, "base_sha": safety.sha256_file(canvas_path), "face_box": fbc,
                "face_box_source": meta.get("face_box_source"), "variants": {}}
        vdir = os.path.join(fdir, "variants")
        mdir = os.path.join(fdir, "masks")
        os.makedirs(vdir, exist_ok=True)
        os.makedirs(mdir, exist_ok=True)
        rgb = P.flat_rgb(canvas, bg["rgb"])
        vcrop = P.square_box(fbc, canvas.size, scale=C.FINAL["variant_crop_scale"])
        first = int(h["seed_base"]) + C.FINAL["variant_seed_offset"]
        var_imgs = []
        for n in names:
            est = (steps[-1].get("seconds") or 600) * 1.5 + 300
            if not a.deadline.allows(est):
                log("  time budget: skipping variant %s" % n)
                vrec["variants"][n] = {"skipped": "time budget"}
                continue
            spec = prompts.variant_spec(bible, hero, n)
            region = post.region_box(fbc, spec["region_frac"])
            vmask = P.ellipse_mask(canvas.size, region, feather=max(3, region[3] // 10))
            vmask.save(os.path.join(mdir, "%s.png" % spec["region"]))
            tries = []
            for k in range(max(1, a.variant_tries)):
                vseed = first + k
                out_rgb, info = crop_inpaint(eng, embs["v:" + n], rgb, vcrop, vmask, spec["denoise"], vseed, q,
                                             target=a.inpaint_px)
                var = merge_variant(canvas, out_rgb, vmask)
                probs = post.variant_alignment(canvas, var, allowed_rect=region, margin=12)
                tp = os.path.join(vdir, "candidates", "%s_s%d.png" % (n, vseed))
                os.makedirs(os.path.dirname(tp), exist_ok=True)
                var.save(tp)
                tries.append({"seed": vseed, "alignment_problems": probs, **info})
                steps.append({"step": "variant_" + n, **info})
            pick = tries[0]["seed"]
            pick_img = Image.open(os.path.join(vdir, "candidates", "%s_s%d.png" % (n, pick))).convert("RGBA")
            pick_img.save(os.path.join(vdir, n + ".png"))
            patch, prect = V.patch_from(pick_img, canvas, region)
            patch.save(os.path.join(vdir, n + "_patch.png"))
            with open(os.path.join(vdir, n + "_patch.json"), "w") as f:
                json.dump({"rect": prect, "seed": pick, "region": spec["region"], "base_sha": vrec["base_sha"]}, f, indent=1)
            vrec["variants"][n] = {"picked_seed": pick, "region": region, "region_name": spec["region"],
                                   "denoise": spec["denoise"], "prompt": texts["v:" + n][0], "tries": tries}
            var_imgs.append((n, pick_img))
        vrec["warp_overlay_hints"] = {"_doc": "rects for <id>.warp_src.json overlays (eyes / mouth slots)",
                                      "eyes": post.region_box(fbc, bible["regions"]["eyes"]),
                                      "mouth": post.region_box(fbc, bible["regions"]["mouth"]),
                                      "base_eyes": h.get("default_eyes", "open")}
        # 6. face review sheet
        sq = P.square_box(fbc, canvas.size, scale=2.4)
        entries = [(canvas.crop(sq), "base")] + [(im.crop(sq), n) for n, im in var_imgs]
        post.contact_sheet(entries, os.path.join(fdir, "variants_sheet.png"), cols=len(entries), cell_w=300,
                           detail=False, title="%s s%d: base + variants" % (hero, seed))
        # publish: every image through the filter, text as JSON
        pub.publish(base_tmp, "%s/%s_base.webp" % (rel, hero))
        pub.publish(src_tmp, "%s/%s_source.webp" % (rel, hero))
        for dp, _dn, fns in os.walk(fdir):
            for fn in sorted(fns):
                full = os.path.join(dp, fn)
                r = "%s/%s" % (rel, os.path.relpath(full, fdir).replace(os.sep, "/"))
                if fn.endswith(".png"):
                    pub.publish(full, r)
                elif fn.endswith(".json"):
                    with open(full) as f:
                        pub.write_json(r, json.load(f))
        meta["steps"] = steps
        pub.write_json("%s/%s.json" % (rel, hero), meta)
        pub.write_json("%s/variants/variants.json" % rel, vrec)
        job["images"] += [s for s in steps if "seconds" in s]
        log("final %s s%d done: canvas, %d variants" % (hero, seed, len(var_imgs)))


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
    ap.add_argument("mode", choices=["candidates", "final"])
    ap.add_argument("--hero", required=True)
    ap.add_argument("--seeds", required=True, help="comma list")
    ap.add_argument("--preset", default=C.DEFAULT_PRESET, choices=sorted(C.PRESETS))
    ap.add_argument("--out", required=True, help="upload dir: only filtered images ever land here")
    ap.add_argument("--work", required=True, help="scratch dir (never uploaded)")
    ap.add_argument("--key", default="local", help="job key (matrix entry)")
    ap.add_argument("--run", default="local", help="run dir name on the output branch")
    ap.add_argument("--model-cache", default=None, help="HF cache dir for the base model")
    ap.add_argument("--threads", type=int, default=None)
    ap.add_argument("--max-minutes", type=float, default=280.0, help="soft budget; later images are skipped")
    ap.add_argument("--source-run", default=None, help="final: run dir of the candidate (default: newest)")
    ap.add_argument("--no-source", action="store_true", help="final: ignore published candidates")
    ap.add_argument("--flip", action="store_true", help="final: mirror (the spec wants a 3/4 view facing right)")
    ap.add_argument("--hires-scale", type=float, default=C.FINAL["hires_scale"])
    ap.add_argument("--refine-denoise", type=float, default=C.FINAL["refine_denoise"])
    ap.add_argument("--inpaint-px", type=int, default=C.FINAL["inpaint_px"])
    ap.add_argument("--variants", default=None, help="final: comma list (default: the hero's variant_set)")
    ap.add_argument("--variant-tries", type=int, default=1)
    ap.add_argument("--no-variants", action="store_true")
    ap.add_argument("--no-face-polish", action="store_true")
    a = ap.parse_args(argv)
    a.seeds = parse_seeds(a.seeds)
    a.deadline = Deadline(a.max_minutes)
    return a


def main(argv=None, components=None):
    a = build_args(argv)
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
           "env": env_info(), "timing": {}, "images": [], "skipped": [], "started": stamp(),
           "licenses": {"model": C.MODEL, "loras": C.LORAS, "aux": C.AUX}}
    pub = safety.Publisher(filt, a.out, log=log, job={"key": a.key, "run": a.run, "hero": a.hero, "mode": a.mode})
    if "encoders" not in comps or "engine" not in comps:
        import sdxl
        model_dir, variants, minfo = sdxl.fetch_model(a.model_cache, log=log)
        job["model"] = {k: v for k, v in minfo.items() if k != "repo_files"}
        job["timing"]["download_s"] = minfo["download_s"]
        comps.setdefault("encoders", lambda: real_encoders(model_dir, variants))
        comps.setdefault("engine", lambda: real_engine(model_dir, variants, a.threads))
    comps.setdefault("cutter", RembgCutter)
    comps.setdefault("faces", AnimeFaceFinder)
    rc = 0
    try:
        if a.mode == "candidates":
            run_candidates(a, bible, pub, comps, job)
        else:
            run_final(a, bible, pub, comps, job)
    except (prompts.ContentRuleError, prompts.PromptError) as e:
        log("ERROR: prompt refused: %s" % e)
        rc = 4
    finally:
        job["filter"] = dict(filt.stats)
        job["finished"] = stamp()
        job["wall_s"] = round(time.time() - T_START, 1)
        imgs = [i for i in job["images"] if i.get("what", "").startswith("txt2img")]
        if imgs:
            job["timing"]["s_per_txt2img"] = round(sum(i["seconds"] for i in imgs) / len(imgs), 1)
        pub.write_json("%s/job_%s.json" % (a.hero, a.key), job)
        log(pub.summary())
        log("job %s finished in %.1f min, timings %s" % (a.key, job["wall_s"] / 60, json.dumps(job["timing"])))
    return rc


if __name__ == "__main__":
    sys.exit(main())
