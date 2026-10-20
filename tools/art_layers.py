#!/usr/bin/env python3
"""Peel a hero's art into layers for a format 2 rig (docs/dev/halorig.md 11.1 and 12).

    python tools/art_layers.py <rig id> [--dry-run] [--only NAME] [--seed S] [--sheet out.png]

Reads the rig's warp_src.json: its regions (the part masks; SAM masks cut by tools/art_parts.py) and
its "layers" plan, back to front by z:
    {"name": "hair_back", "z": -30, "parts": ["hair_back", "ponytail"],
     "complete": {"grow": 70, "prompt": "black hair, long hair", "denoise": 1.0}}
    {"name": "body", "z": 0, "parts": "rest"}
    {"name": "spear", "z": 5, "parts": ["weapon"], "complete": {"grow": 140, "prompt": "polearm, metal shaft"}}
Every painted pixel gets one part (the first region whose mask covers it, else the nearest part) and
so one layer. A layer with "complete" also gets what the layers in front of it hide, within `grow` px
of its own paint: those pixels are painted by Amanatsu (crop-and-inpaint on the owner's ComfyUI,
same checkpoint and style as the art) from the layer's own paint alone, everything in front taken
out first, so the model continues the hair, wing or shaft rather than redrawing what covered it.
A layer with "fill": N gets small holes filled from its edges instead (OpenCV, no GPU).
Writes <art>_<layer>.png (cropped) next to the art, sets each layer's "image" and "image_rect" in
the warp_src, and a review sheet (each layer alone over a checker, then all of them stacked).
Content rules apply to every prompt (tools/comfy/prompts.py); painted-in skin under clothing stays
at swimwear level and is reviewed like any render.
"""
import argparse
import json
import os
import sys

import cv2
import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
sys.path.insert(0, os.path.join(ROOT, "tools"))
sys.path.insert(0, os.path.join(ROOT, "tools", "comfy"))

import art_warp_build as awb  # noqa: E402


def labels(src, img, alpha):
    """Part index per pixel (region order = priority), unlabelled paint takes the nearest part."""
    H, W = alpha.shape
    regs = src.get("regions", [])
    lab = np.full((H, W), -1, np.int32)
    for k, r in enumerate(regs):
        if "rule" not in r:
            continue
        m = np.array(awb.rule_mask(r["rule"], img)) > 127
        lab[(lab < 0) & m] = k
    opaque = alpha > 0.02
    un = opaque & (lab < 0)
    if un.any() and (lab >= 0).any():
        _, (iy, ix) = ndimage.distance_transform_edt(lab < 0, return_indices=True)
        lab[un] = lab[iy[un], ix[un]]
    return lab, [r.get("bone", r["name"]) for r in regs]


def layer_masks(src, lab, bones, alpha):
    plan = sorted(src.get("layers", []), key=lambda l: l.get("z", 0))
    claimed = [p for l in plan if isinstance(l.get("parts"), list) for p in l["parts"]]
    opaque = alpha > 0.02
    vis = {}
    for l in plan:
        p = l.get("parts", "rest")
        if p == "rest":
            ks = [k for k, b in enumerate(bones) if not b.startswith(tuple(claimed))]
        else:
            ks = [k for k, b in enumerate(bones) if b.startswith(tuple(p))]
        vis[l["name"]] = np.isin(lab, ks) & opaque
    return plan, vis


def straight_prop(rgb, alpha, V):
    """A straight prop (spear, staff, sword, gun barrel) partly hidden behind her: its line from its
    visible pieces, its cross-section where it runs narrow and clean (the shaft), and the hidden
    stretches rebuilt by sliding that cross-section along the line. Returns (rgb, alpha) of the whole
    prop; the visible pieces keep their own paint."""
    ys, xs = np.nonzero(V & (alpha > 0.5))
    P = np.stack([xs, ys], 1).astype(np.float64)
    c = P.mean(0)
    _, _, vt = np.linalg.svd(P - c, full_matrices=False)
    d = vt[0]
    n = np.array([-d[1], d[0]])
    sv = (P - c) @ d
    tv = (P - c) @ n
    s0, s1 = int(np.floor(sv.min())), int(np.ceil(sv.max()))
    # width across the line at each step along it: the shaft is the narrow, steady part
    bins = np.arange(s0, s1 + 1)
    idx = np.clip(np.round(sv).astype(int) - s0, 0, len(bins) - 1)
    width = np.zeros(len(bins))
    lo = np.full(len(bins), 1e9)
    hi = np.full(len(bins), -1e9)
    np.minimum.at(lo, idx, tv)
    np.maximum.at(hi, idx, tv)
    has = hi >= lo
    width[has] = hi[has] - lo[has] + 1
    cand = np.nonzero(has & (width >= 3))[0]
    w_med = np.median(width[cand])
    shaft = cand[width[cand] <= max(w_med, 4)]
    # the longest run of shaft samples, its middle 16 steps
    best, run = (shaft[0], shaft[0]), [shaft[0]]
    for k in shaft[1:]:
        if k == run[-1] + 1:
            run.append(k)
        else:
            run = [k]
        if run[-1] - run[0] > best[1] - best[0]:
            best = (run[0], run[-1])
    mid = (best[0] + best[1]) // 2
    sm = s0 + mid
    T = int(max(12, np.percentile(width[cand], 95)))
    tt = np.arange(-T, T + 1)
    H, W = alpha.shape
    prof = np.zeros((len(tt), 4), np.float64)
    cnt = 0
    for ds in range(-8, 8):
        X = c[0] + d[0] * (sm + ds) + n[0] * tt
        Y = c[1] + d[1] * (sm + ds) + n[1] * tt
        for ch in range(3):
            prof[:, ch] += ndimage.map_coordinates(rgb[..., ch].astype(np.float64), [Y, X], order=1)
        prof[:, 3] += ndimage.map_coordinates((V * alpha).astype(np.float64), [Y, X], order=1)
        cnt += 1
    prof /= cnt
    # every pixel near the line: visible pieces as painted, hidden stretches from the profile
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float64)
    S = (xx - c[0]) * d[0] + (yy - c[1]) * d[1]
    Tn = (xx - c[0]) * n[0] + (yy - c[1]) * n[1]
    near = (S >= s0) & (S <= s1) & (np.abs(Tn) <= T)
    ti = np.clip(np.round(Tn + T).astype(int), 0, len(tt) - 1)
    out_rgb = rgb.copy()
    out_a = alpha * V
    # along the line: is this stretch visible (any of the prop's own paint here)?
    vis_s = np.zeros(len(bins), bool)
    vis_s[idx] = True
    vis_s = ndimage.binary_closing(vis_s, iterations=3)
    si = np.clip(np.round(S).astype(int) - s0, 0, len(bins) - 1)
    hidden = near & ~vis_s[si]
    pa = prof[ti, 3]
    out_rgb[hidden] = np.clip(prof[ti[hidden], :3], 0, 255).astype(np.uint8)
    out_a = np.where(hidden, np.maximum(out_a, pa), out_a)
    return out_rgb, out_a, (c, d, s0, s1, sm)


def checker(size, a=200, b=160, step=24):
    W, H = size
    y, x = np.mgrid[0:H, 0:W]
    c = np.where(((x // step) + (y // step)) % 2 == 0, a, b).astype(np.uint8)
    return Image.fromarray(np.dstack([c, c, c, np.full_like(c, 255)]), "RGBA")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("rig")
    ap.add_argument("--dry-run", action="store_true", help="no GPU: completion areas are filled from their edges")
    ap.add_argument("--only", help="redo this layer only")
    ap.add_argument("--seed", type=int, default=0, help="added to each layer's inpaint seed")
    ap.add_argument("--sheet", help="review sheet path (default: art_src/<hero>/layers_<art>.png)")
    ap.add_argument("--url", default=os.environ.get("COMFYUI_URL", "http://127.0.0.1:8188"))
    a = ap.parse_args()
    hdir, name, hero = awb.rig_dir(a.rig)
    sp = os.path.join(hdir, name + ".warp_src.json")
    src = json.load(open(sp))
    img = Image.open(os.path.join(hdir, src.get("image", name + ".png"))).convert("RGBA")
    awb.set_mask_context(hdir, img)
    rgba = np.array(img)
    H, W = rgba.shape[:2]
    alpha = rgba[..., 3].astype(np.float32) / 255
    lab, bones = labels(src, img, alpha)
    plan, vis = layer_masks(src, lab, bones, alpha)
    if not plan:
        raise SystemExit("art_layers: %s has no \"layers\" plan in its warp_src" % a.rig)
    client = s = bible = None
    out_layers = {}
    for li, l in enumerate(plan):
        nm = l["name"]
        V = vis[nm]
        front = np.zeros_like(V)
        for l2 in plan:
            if l2.get("z", 0) > l.get("z", 0):
                front |= vis[l2["name"]]
        rgb = rgba[..., :3].copy()
        la = alpha * V
        comp = l.get("complete")
        fill = int(l.get("fill", 0))
        if comp and comp.get("mode") == "straight" and (a.only is None or a.only == nm):
            prgb, pa, info = straight_prop(rgba[..., :3], alpha, V)
            rgb = prgb
            la = pa
            print("art_layers: [%s] %s: straight prop, line through %s, length %d px" % (
                a.rig, nm, [round(v) for v in info[0]], info[3] - info[2]))
        elif (comp or fill) and (a.only is None or a.only == nm):
            grow = int((comp or {}).get("grow", fill or 40))
            reach = ndimage.binary_dilation(V, iterations=grow) if V.any() else V
            C = reach & front & ~V
            if C.sum() > 30:
                if comp and not a.dry_run:
                    import comfy  # noqa: F401
                    import pipeline as P
                    import prompts
                    if client is None:
                        bible = prompts.load_bible()
                        os.environ.setdefault("COMFYUI_URL", a.url)
                        cap = argparse.ArgumentParser()
                        P.add_common_args(cap)
                        cargs = cap.parse_args([])
                        client = P.make_client(cargs)
                        s, _, _ = P.resolve_settings(bible, cargs, client, hero)
                    # her own paint over flat grey; what is in front is gone, the hole is repainted
                    ctx = np.full_like(rgb, 128)
                    keep = V & (alpha > 0.5)
                    ctx[keep] = rgb[keep]
                    ctx_img = Image.fromarray(ctx)
                    mask = Image.fromarray((ndimage.binary_dilation(C, iterations=3) * 255).astype(np.uint8))
                    ys, xs = np.nonzero(C)
                    box = [int(xs.min()), int(ys.min()), int(xs.max() - xs.min() + 1), int(ys.max() - ys.min() + 1)]
                    crop = P.square_box(box, ctx_img.size, scale=1.5)
                    pr = prompts.custom(bible, hero, s["family"], comp.get("prompt", ""), comp.get("negative", ""))
                    work = os.path.join(ROOT, "art_src", hero, "work")
                    seed = 4200 + li * 17 + a.seed
                    out, _ = P.crop_inpaint(client, s, ctx_img, crop, mask, pr["positive"], pr["negative"], seed,
                                            float(comp.get("denoise", 1.0)), "%s/layer_%s_%s" % (hero, name, nm), work,
                                            mode="vae_inpaint", grow=6)
                    o = np.array(out)
                    rgb[C] = o[C]
                else:
                    m = (C * 255).astype(np.uint8)
                    src_rgb = rgb.copy()
                    src_rgb[~V] = 128
                    filled = cv2.inpaint(np.ascontiguousarray(src_rgb[..., ::-1]), m, 7, cv2.INPAINT_TELEA)[..., ::-1]
                    rgb[C] = filled[C]
                # the painted-in part fades out toward the edge of its reach, it never ends on a hard cut
                d = ndimage.distance_transform_edt(~V)
                fade = np.clip(1.0 - (d - grow * 0.6) / max(grow * 0.4, 1.0), 0.0, 1.0)
                la = np.maximum(la, C * fade)
        lay = np.dstack([rgb, np.clip(la * 255, 0, 255).astype(np.uint8)]).astype(np.uint8)
        ys, xs = np.nonzero(lay[..., 3] > 0)
        if len(xs) == 0:
            print("art_layers: [%s] layer %s is empty" % (a.rig, nm))
            continue
        x0, y0 = max(0, xs.min() - 2), max(0, ys.min() - 2)
        x1, y1 = min(W, xs.max() + 3), min(H, ys.max() + 3)
        fn = "%s_%s.png" % (name, nm)
        Image.fromarray(lay[y0:y1, x0:x1]).save(os.path.join(hdir, fn), optimize=True)
        awb.write_import(os.path.join(hdir, fn))
        l["image"] = fn
        l["image_rect"] = [int(x0), int(y0), int(x1 - x0), int(y1 - y0)]
        out_layers[nm] = (lay, l.get("z", 0))
        print("art_layers: [%s] %s z=%s: %d px own, %s" % (a.rig, nm, l.get("z", 0), int(V.sum()),
              "completed" if (comp or fill) else "as painted"))
    # the base layer (face overlays sit on it) must come first in the source
    base = src.get("layers_base", "body")
    src["layers"] = sorted(plan, key=lambda l: (l["name"] != base, l.get("z", 0)))
    json.dump(src, open(sp, "w"), indent=2)
    # review sheet: each layer alone, then the stack
    tiles = []
    for nm, (lay, z) in sorted(out_layers.items(), key=lambda kv: kv[1][1]):
        t = checker((W, H))
        t.alpha_composite(Image.fromarray(lay))
        tiles.append((nm, t))
    stack = Image.new("RGBA", (W, H), (60, 56, 72, 255))
    for nm, (lay, z) in sorted(out_layers.items(), key=lambda kv: kv[1][1]):
        stack.alpha_composite(Image.fromarray(lay))
    tiles.append(("stacked", stack))
    tw = 360
    th = int(H * tw / W)
    sheet = Image.new("RGB", (tw * len(tiles), th + 24), (24, 22, 30))
    from PIL import ImageDraw
    d = ImageDraw.Draw(sheet)
    for k, (nm, t) in enumerate(tiles):
        sheet.paste(t.convert("RGB").resize((tw, th)), (k * tw, 24))
        d.text((k * tw + 6, 6), nm, fill=(255, 220, 120))
    out = a.sheet or os.path.join(ROOT, "art_src", hero, "layers_%s.png" % name)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    sheet.save(out)
    print("art_layers: sheet", out)


if __name__ == "__main__":
    main()
