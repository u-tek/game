#!/usr/bin/env python3
"""Repair a region (hands, a prop, a face) of a candidate or final image by crop-and-inpaint.

    python3 tools/comfy/fix.py <hero_id> <image|seed> --box x,y,w,h --prompt "tags" [--mask m.png]
                              [--denoise 0.5] [--count 3] [--seed S] [--mode noise_mask|vae_inpaint] [--dry-run]
                              [--skin SKIN]

The prompt is the hero's identity tags (hair, outfit, weapon, style) plus --prompt, checked against
the content rules, rendered with the checkpoint that made the candidate (from its .json). --box is
the area to repaint (an ellipse inside it, unless --mask is given: white = repaint, same size as the
image). Fix the CANDIDATE, then finalize the _fixed.png: fixes on final/<id>.png are refused (its
variants and the rig are aligned to it pixel for pixel). On any other RGBA input the original alpha
is kept outside the repainted area and only re-cut inside it.

Tries go to art_src/<id>/work/fix_<stem>_s<seed>.png with a before/after sheet; --apply SEED copies
a try over a new file <image stem>_fixed.png (never overwrites the input). --skin works on a skin's
candidates and folders (art_src/<id>/skins/<art>/) with that skin's outfit in the prompt.
"""
import argparse
import os
import shutil
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

from PIL import Image  # noqa: E402

import comfy  # noqa: E402
import pipeline as P  # noqa: E402
import post  # noqa: E402
import prompts  # noqa: E402
import workflows  # noqa: E402
from finalize import find_candidate  # noqa: E402


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("hero")
    ap.add_argument("image", help="candidate seed or image path")
    ap.add_argument("--box", help="x,y,w,h area to repaint, in image pixels")
    ap.add_argument("--mask", help="mask PNG (white = repaint), same size as the image")
    ap.add_argument("--prompt", default="", help="what the area should show, e.g. 'holding scepter, detailed hand'")
    ap.add_argument("--negative", default="")
    ap.add_argument("--denoise", type=float, default=0.5)
    ap.add_argument("--mode", choices=["noise_mask", "vae_inpaint"], default="noise_mask")
    ap.add_argument("--count", type=int, default=3)
    ap.add_argument("--seed", type=int)
    ap.add_argument("--apply", type=int, metavar="SEED", help="write the try with this seed as <stem>_fixed.png")
    ap.add_argument("--skin", help="skin id (bible 'skins'): a skin's candidate, with the skin's outfit in the prompt")
    P.add_common_args(ap)
    a = ap.parse_args(argv)
    log = (lambda *x: None) if a.quiet else print
    try:
        bible = prompts.load_bible()
        t = P.art_target(bible, a.hero, a.skin, a.dry_run)
        path = find_candidate(t, a.image)
        stem = os.path.splitext(os.path.basename(path))[0]
        hdir = t["dir"]
        work = os.path.join(hdir, "work")
        if os.path.abspath(path).startswith(os.path.abspath(os.path.join(hdir, "final")) + os.sep):
            fm = P.read_json(os.path.join(hdir, "final", t["name"] + ".json"), {}) or {}
            raise P.PipelineError(
                "refusing to fix %s: the variants and the rig are aligned to it. Fix the candidate instead (%s), "
                "then finalize.py %s <path to the _fixed.png> --force%s" % (
                    P.rel(path), fm.get("source_candidate", "candidates/<id>_s<seed>.png"), a.hero,
                    " --skin " + t["skin"] if t["skin"] else ""))
        if a.apply is not None:
            src = os.path.join(work, "fix_%s_s%d.png" % (stem, a.apply))
            if not os.path.exists(src):
                raise P.PipelineError("no try %s" % P.rel(src))
            dst = os.path.join(os.path.dirname(path), stem + "_fixed.png")
            shutil.copyfile(src, dst)
            meta = P.read_json(path[:-4] + ".json")
            if meta is not None:   # keep seed/checkpoint/background so finalize.py polishes consistently
                meta.update({"image": os.path.basename(dst), "fixed_from": P.rel(path), "fix_seed": a.apply})
                P.write_json(dst[:-4] + ".json", meta)
            log("wrote %s (use it as the candidate for finalize.py)" % P.rel(dst))
            return 0
        if not a.box and not a.mask:
            raise P.PipelineError("give --box x,y,w,h or --mask")
        img = Image.open(path)
        rgba_in = img.mode == "RGBA"
        _, bg = prompts.background(bible, a.hero, (P.read_json(path[:-4] + ".json", {}) or {}).get("background", {}).get("key"))
        rgb = P.flat_rgb(img, bg["rgb"]) if rgba_in else img.convert("RGB")
        if a.mask:
            mask = Image.open(a.mask).convert("L")
            if mask.size != rgb.size:
                raise P.PipelineError("mask size %s differs from the image %s" % (mask.size, rgb.size))
            bb = mask.getbbox()
            if not bb:
                raise P.PipelineError("mask is empty")
            box = [bb[0], bb[1], bb[2] - bb[0], bb[3] - bb[1]]
        else:
            box = post.parse_box(a.box)
            mask = P.ellipse_mask(rgb.size, box, feather=max(3, min(box[2:]) // 12))
        client = P.make_client(a)
        P.inherit_model(a, P.read_json(path[:-4] + ".json", {}) or {}, P.rel(path[:-4] + ".json"), log)
        s, _, _ = P.resolve_settings(bible, a, client, a.hero)
        pr = prompts.custom(bible, a.hero, s["family"], a.prompt, a.negative, skin=t["skin"])
        crop = P.square_box(box, rgb.size, scale=1.6)
        first = a.seed if a.seed is not None else t["seed_base"] + 800
        tries = []
        for i in range(max(1, a.count)):
            seed = first + i
            out, _ = P.crop_inpaint(client, s, rgb, crop, mask, pr["positive"], pr["negative"], seed, a.denoise,
                                    "%s/fix_%s_s%d" % (t["job"], stem, seed), work, mode=a.mode, timeout=a.timeout)
            if rgba_in:   # re-cut only inside the (dilated) fix area; keep the original alpha elsewhere
                recut, _ = post.remove_background(out, bg=bg["rgb"])
                m = post.dilate(np.asarray(mask) > 8, 6)[..., None]
                orig = np.asarray(img.convert("RGBA"))
                out = Image.fromarray(np.where(m, np.asarray(recut), orig).astype(np.uint8), "RGBA")
            tp = os.path.join(work, "fix_%s_s%d.png" % (stem, seed))
            out.save(tp)
            tries.append((seed, out))
        entries = [(img.crop(crop), "before")] + [(t.crop(crop), "s%d" % sd) for sd, t in tries]
        sheet = os.path.join(work, "fix_%s_sheet.png" % stem)
        post.contact_sheet(entries, sheet, cols=min(4, len(entries)), cell_w=320, detail=False,
                           title="%s fix: pick with --apply SEED" % stem)
        log("tries in %s, sheet %s" % (P.rel(work), P.rel(sheet)))
        log("apply: python3 tools/comfy/fix.py %s %s --apply <seed>%s%s" % (
            a.hero, a.image, " --skin " + t["skin"] if t["skin"] else "", " --dry-run" if a.dry_run else ""))
    except (P.PipelineError, comfy.ComfyError, prompts.ContentRuleError, workflows.WorkflowError, ValueError) as e:
        print("ERROR: %s" % e, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
