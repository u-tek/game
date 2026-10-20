#!/usr/bin/env python3
"""Expression variants (eyes closed / eyes open, mouth open, smile, hurt) by inpainting the face.

    python3 tools/comfy/variants.py <hero_id> [image] [--variants eyes_closed,mouth_open] [--count N]
                                   [--face-box x,y,w,h] [--region eyes=x,y,w,h] [--pick NAME=SEED] [--dry-run]
                                   [--skin SKIN]

`image` defaults to art_src/<id>/final/<id>.png (the canvas the rig uses), so every variant is
pixel-aligned with it: only the masked eyes/mouth area changes, alpha is kept from the base.
(`image` may also be a candidate seed or path; the variants then live in that image's pixels.)
Face box: --face-box, else the one in final/<id>.json, else auto-estimated. Eye and mouth regions
are fractions of the face box (data/art_prompts.json "regions"), or --region NAME=x,y,w,h.

For each variant and seed the face is cropped, upscaled to 1024 px, inpainted (VAEEncode +
SetLatentNoiseMask, denoise ~0.6, the hero's per-variant prompt), scaled back and pasted through a
feathered mask. Outputs in art_src/<id>/variants/:
    <name>.png                 full-size variant (delivery name, docs/dev/art-style.md section 2)
    <name>_patch.png/.json     the changed rect only, feathered, with its position
    candidates/<name>_s<seed>.png, sheet_<name>.png    all tries + a before/after sheet
    variants.json              picks, seeds, prompts, boxes, base_sha (sha256 of the base image)
and region masks in art_src/<id>/masks/<region>.png (white = region), canvas-sized.

Re-runs never overwrite chosen work: new tries take the next unused seeds and are added to the
sheet; variants/<name>.png stays what you picked (change it with --pick NAME=SEED). If the base
image changed since the variants were made (different sha256), the run stops: the old variants no
longer line up with it. --force then archives variants/ and masks/ to history/<timestamp>/ and
starts over; --force also re-renders seeds that already have a try.
--skin <skin id> works on a skin's final instead: art_src/<id>/skins/<art>/final/<art>.png, with
variants/ and masks/ in that folder and tries from the skin's seed_base + 500.
"""
import argparse
import os
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import numpy as np  # noqa: E402
from PIL import Image  # noqa: E402

import comfy  # noqa: E402
import pipeline as P  # noqa: E402
import post  # noqa: E402
import prompts  # noqa: E402
import workflows  # noqa: E402


def resolve_image(target, spec):
    hdir = target["dir"]
    if spec is None:
        p = os.path.join(hdir, "final", target["name"] + ".png")
        if not os.path.exists(p):
            raise P.PipelineError("no %s yet: run finalize.py first (or pass an image)" % P.rel(p))
        return p
    if os.path.exists(spec):
        return os.path.abspath(spec)
    if str(spec).lstrip("s").isdigit():
        p = os.path.join(hdir, "candidates", "%s_s%s.png" % (target["hero"], str(spec).lstrip("s")))
        if os.path.exists(p):
            return p
    raise P.PipelineError("image %r not found" % spec)


def patch_from(variant, base, rect, margin=10):
    """The changed rect of a variant with a feathered border (like tools/art_warp_build.py)."""
    x, y, w, h = rect
    x0, y0 = max(0, x - margin), max(0, y - margin)
    x1, y1 = min(base.width, x + w + margin), min(base.height, y + h + margin)
    pa = np.asarray(variant.crop((x0, y0, x1, y1))).astype(np.float32)
    ph, pw = pa.shape[:2]
    fy = np.minimum(np.arange(ph), np.arange(ph)[::-1])[:, None]
    fx = np.minimum(np.arange(pw), np.arange(pw)[::-1])[None, :]
    pa[..., 3] *= np.clip(np.minimum(fx, fy) / max(1.0, margin * 0.8), 0, 1)
    return Image.fromarray(pa.astype(np.uint8), "RGBA"), [x0, y0, x1 - x0, y1 - y0]


def before_after_sheet(base, tries, crop, out_path, title):
    x0, y0, x1, y1 = crop
    entries = [(base.crop(crop), "base")] + [(im.crop(crop), "s%d" % seed) for seed, im in tries]
    post.contact_sheet(entries, out_path, cols=min(5, len(entries)), cell_w=256, detail=False, title=title)
    return out_path


def promote(vdir, name, seed, base):
    """variants/<name>.png + patch from the try candidates/<name>_s<seed>.png."""
    src = os.path.join(vdir, "candidates", "%s_s%d.png" % (name, seed))
    if not os.path.exists(src):
        raise P.PipelineError("no try %s" % P.rel(src))
    shutil.copyfile(src, os.path.join(vdir, name + ".png"))
    pj = P.read_json(src[:-4] + ".json", {}) or {}
    if pj.get("patch_rect"):
        patch, prect = patch_from(Image.open(src).convert("RGBA"), base, pj["patch_rect"])
        patch.save(os.path.join(vdir, name + "_patch.png"))
        P.write_json(os.path.join(vdir, name + "_patch.json"),
                     {"rect": prect, "seed": int(seed), "region": pj.get("region_name"), "base_sha": pj.get("base_sha")})
    return src


def existing_tries(vcand, name):
    out = set()
    for f in os.listdir(vcand) if os.path.isdir(vcand) else []:
        if f.startswith(name + "_s") and f.endswith(".png") and f[len(name) + 2:-4].isdigit():
            out.add(int(f[len(name) + 2:-4]))
    return out


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("hero")
    ap.add_argument("image", nargs="?", help="default: art_src/<id>/final/<id>.png")
    ap.add_argument("--variants", help="comma list (default: the hero's variant_set)")
    ap.add_argument("--count", type=int, default=3, help="new tries per variant (different seeds)")
    ap.add_argument("--seed", type=int, help="first seed (default: the next unused from seed_base + 500)")
    ap.add_argument("--face-box", help="x,y,w,h in image pixels (brow/hairline to chin)")
    ap.add_argument("--region", action="append", default=[], help="NAME=x,y,w,h override (eyes, mouth, eyes_mouth)")
    ap.add_argument("--denoise", type=float)
    ap.add_argument("--pick", action="append", default=[],
                    help="NAME=SEED: promote an existing try to variants/<NAME>.png without rendering")
    ap.add_argument("--force", action="store_true",
                    help="re-render seeds that already have a try; accept a changed base image (archives the "
                         "old variants/ and masks/ to history/<timestamp>/)")
    ap.add_argument("--skin", help="skin id (bible 'skins'): variants of that skin's final")
    P.add_common_args(ap)
    a = ap.parse_args(argv)
    log = (lambda *x: None) if a.quiet else print
    try:
        bible = prompts.load_bible()
        t = P.art_target(bible, a.hero, a.skin, a.dry_run, adult=a.adult)
        name0, job = t["name"], t["job"]
        h = bible["heroes"][a.hero]
        hdir = t["dir"]
        vdir = os.path.join(hdir, "variants")
        vcand = os.path.join(vdir, "candidates")
        record_path = os.path.join(vdir, "variants.json")
        img_path = resolve_image(t, a.image)
        base = Image.open(img_path).convert("RGBA")
        base_sha = P.sha256_file(img_path)
        record = P.read_json(record_path, None)

        if a.pick:   # offline promotion of an earlier try
            if record is None:
                raise P.PipelineError("no %s yet: render tries first" % P.rel(record_path))
            if record.get("base_sha") != base_sha and not a.force:
                raise P.PipelineError("%s changed since these variants were made; re-render them (--force)"
                                      % P.rel(img_path))
            for spec in a.pick:
                name, _, seed = spec.partition("=")
                if not seed.isdigit():
                    raise P.PipelineError("--pick wants NAME=SEED, got %r" % spec)
                tj = P.read_json(os.path.join(vcand, "%s_s%s.json" % (name, seed)), {}) or {}
                if tj.get("base_sha") not in (None, base_sha) and not a.force:
                    raise P.PipelineError("try %s s%s was made from another base image" % (name, seed))
                promote(vdir, name, int(seed), base)
                record["variants"].setdefault(name, {})["picked_seed"] = int(seed)
                log("picked %s s%s -> %s" % (name, seed, P.rel(os.path.join(vdir, name + ".png"))))
            record["updated"] = P.stamp()
            P.write_json(record_path, record)
            return 0

        stale = record is not None and record.get("base_sha") != base_sha
        if record is None and os.path.isdir(vdir) and any(f.endswith(".png") for f in os.listdir(vdir)):
            stale = True     # variants without a record: origin unknown
        if stale:
            if not a.force:
                raise P.PipelineError(
                    "%s was made from a different base image than %s (sha256 changed: finalize.py re-run or the "
                    "image was edited). Its variants would not line up. Re-run with --force to archive variants/ "
                    "and masks/ to history/ and start over." % (P.rel(record_path), P.rel(img_path)))
            P.archive(hdir, ["variants", "masks"], log=log,
                      reason="variants.py --force: base %s changed to sha %s" % (P.rel(img_path), base_sha[:12]))
            record = None
        if record is None:
            record = {"hero": a.hero, "skin": t["skin"], "adult": bool(a.adult), "variants": {}}
        os.makedirs(vcand, exist_ok=True)

        is_final = os.path.abspath(img_path) == os.path.abspath(os.path.join(hdir, "final", name0 + ".png"))
        fmeta = P.read_json(os.path.join(hdir, "final", name0 + ".json"), {}) if is_final else {}
        names = [v.strip() for v in (a.variants.split(",") if a.variants else h["variant_set"]) if v.strip()]
        client = P.make_client(a)
        src_meta = fmeta if is_final else (P.read_json(img_path[:-4] + ".json", {}) or {})
        P.inherit_model(a, src_meta, "final/%s.json" % name0 if is_final else P.rel(img_path), log)
        s, disc, oi = P.resolve_settings(bible, a, client, a.hero)
        bg_key, bg = prompts.background(bible, a.hero, bible["skins"][t["skin"]].get("background") if t["skin"] else None)

        if a.face_box:
            face_box, conf = post.parse_box(a.face_box), "user"
        elif fmeta.get("face_box"):
            face_box, conf = fmeta["face_box"], "final/%s.json (%s)" % (name0, fmeta.get("face_box_source"))
        else:
            src = base if np.asarray(base.split()[3]).min() < 250 else post.remove_background(base.convert("RGB"))[0]
            face_box, conf = post.estimate_face_box(src, P.skin_profile(bible, a.hero))
        log("%s variants %s on %s, face box %s (%s), checkpoint %s" % (
            t["label"], ",".join(names), P.rel(img_path), ",".join(map(str, face_box)), conf, s["checkpoint"]))
        overrides = {}
        for r in a.region:
            k, _, v = r.partition("=")
            overrides[k] = post.parse_box(v)

        rgb = P.flat_rgb(base, bg["rgb"])
        alpha = base.split()[3]
        crop = P.square_box(face_box, base.size, scale=1.9)
        mdir = os.path.join(hdir, "masks")
        os.makedirs(mdir, exist_ok=True)
        first = t["seed_base"] + 500
        work = os.path.join(hdir, "work")
        count = max(1, a.count)
        for name in names:
            spec = prompts.variant_spec(bible, a.hero, name)
            region = overrides.get(spec["region"]) or post.region_box(face_box, spec["region_frac"])
            mask = P.ellipse_mask(base.size, region, feather=max(3, region[3] // 10))
            mask.save(os.path.join(mdir, "%s.png" % spec["region"]))
            pr = prompts.face(bible, a.hero, s["family"], variant=name, skin=t["skin"], adult=a.adult,
                              pose=src_meta.get("pose"))
            den = a.denoise if a.denoise is not None else spec["denoise"]
            entry = dict(record["variants"].get(name) or {})
            done = set(entry.get("seeds") or []) | existing_tries(vcand, name)
            if a.seed is None and not a.force:          # next unused seeds: re-runs add tries
                seeds, k = [], first
                while len(seeds) < count:
                    if k not in done:
                        seeds.append(k)
                    k += 1
            else:
                start = a.seed if a.seed is not None else first
                seeds = [start + i for i in range(count)]
                if not a.force:
                    kept = [x for x in seeds if x in done]
                    if kept:
                        log("  %s: tries s%s exist, kept (--force to re-render)" % (name, ",".join(map(str, kept))))
                    seeds = [x for x in seeds if x not in done]
            rendered = []
            for seed in seeds:
                out_rgb, info = P.crop_inpaint(client, s, rgb, crop, mask, pr["positive"], pr["negative"], seed, den,
                                               "%s/variant_%s_s%d" % (job, name, seed), work, timeout=a.timeout)
                var = out_rgb.convert("RGBA")
                var.putalpha(alpha)
                # pixels outside the feathered region are bit-identical to the base
                m = np.asarray(mask).astype(np.float32)[..., None] / 255.0
                merged = np.asarray(base).astype(np.float32) * (1 - m) + np.asarray(var).astype(np.float32) * m
                merged[..., 3] = np.asarray(alpha)
                var = Image.fromarray(np.clip(merged + 0.5, 0, 255).astype(np.uint8), "RGBA")
                tp = os.path.join(vcand, "%s_s%d.png" % (name, seed))
                var.save(tp)
                P.write_json(tp[:-4] + ".json", {
                    "hero": a.hero, "skin": t["skin"], "adult": bool(a.adult), "variant": name, "seed": seed,
                    "denoise": den, "base": P.rel(img_path),
                    "base_sha": base_sha, "face_box": face_box, "region": region, "region_name": spec["region"],
                    "patch_rect": region, "crop": info["crop"], "prompt": pr["positive"], "negative": pr["negative"],
                    "settings": P.settings_for_meta(s), "dry_run": a.dry_run, "created": P.stamp()})
                rendered.append(seed)
            all_seeds = sorted(done | set(rendered))
            tries = [(sd, Image.open(os.path.join(vcand, "%s_s%d.png" % (name, sd))).convert("RGBA"))
                     for sd in all_seeds if os.path.exists(os.path.join(vcand, "%s_s%d.png" % (name, sd)))]
            sheet = before_after_sheet(base, tries, crop, os.path.join(vdir, "sheet_%s.png" % name),
                                       "%s %s: base + tries (pick with --pick %s=SEED)" % (t["label"], name, name))
            picked = entry.get("picked_seed")
            out_png = os.path.join(vdir, name + ".png")
            if picked is None or not os.path.exists(out_png):
                picked = rendered[0] if rendered else tries[0][0]
                promote(vdir, name, picked, base)
                note = "using s%d" % picked
            elif picked in rendered:
                promote(vdir, name, picked, base)       # --force re-rendered the picked seed: keep them equal
                note = "re-rendered the picked s%d" % picked
            else:
                note = "kept your pick s%d (promote a new try with --pick %s=SEED)" % (picked, name)
            entry.update({"picked_seed": picked, "seeds": all_seeds, "region": region, "region_name": spec["region"],
                          "denoise": den, "prompt": pr["positive"]})
            record["variants"][name] = entry
            log("  %s: %d new tr%s (%s), sheet %s, %s -> %s" % (
                name, len(rendered), "y" if len(rendered) == 1 else "ies", ",".join("s%d" % x for x in rendered) or "-",
                P.rel(sheet), note, P.rel(out_png)))
        record.update({"base": P.rel(img_path), "base_sha": base_sha, "face_box": face_box, "face_box_source": conf,
                       "updated": P.stamp(), "dry_run": a.dry_run,
                       "warp_overlay_hints": {
                           "_doc": "rects for <id>.warp_src.json overlays (eyes / mouth slots)",
                           "eyes": post.region_box(face_box, bible["regions"]["eyes"]),
                           "mouth": post.region_box(face_box, bible["regions"]["mouth"]),
                           "base_eyes": h.get("default_eyes", "open")}})
        P.write_json(record_path, record)
        if a.dry_run:
            log("dry run: variants are copies of the base; API JSON in %s" % P.rel(os.path.join(comfy.dryrun_dir(), job)))
    except (P.PipelineError, comfy.ComfyError, prompts.ContentRuleError, prompts.PromptError, workflows.WorkflowError,
            KeyError, ValueError) as e:
        print("ERROR: %s" % e, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
