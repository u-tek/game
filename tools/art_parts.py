"""SAM part masks for HaloRig warp rigs (docs/dev/halorig.md, section 11).

A warp source region can cut its mask with Segment Anything instead of a hand-drawn shape:
    {"name": "breast_l", "bone": "breast_l", "rule": {"type": "sam", "points": [[x, y], ...],
     "neg": [[x, y], ...], "box": [x0, y0, x1, y1], "pick": "best", "clip": true, "feather": 3}}
(image pixels; `points` inside the part, `neg` on neighbours it must not take, `box` around it;
`pick`: best | small | large | 0 | 1 | 2 of SAM's three proposals; `clip`: keep only what lies in
the box). "sam" rules also work inside union/subtract. This tool runs SAM for every sam rule of the
given rigs and caches each result as a 1-bit PNG in masks/_sam/<key>.png (key = rule + image
hash); tools/art_warp_build.py reads the cache and fails when a mask is missing or stale.

    <python with torch> tools/art_parts.py argentiel imra@lucky_ember [--sheet out.png] [--cpu]
    <python with torch> tools/art_parts.py argentiel --grid out.png      # the art with a coordinate grid

On the owner's PC the ComfyUI venv has torch: /d/comfyui/.venv/Scripts/python.exe. segment-anything
lives in <repo>/.pylib (gitignored; `python -m pip install --target .pylib segment-anything --no-deps`)
or HALO_PYLIB. Checkpoint: SAM_CHECKPOINT, default D:/comfyui/models/sams/sam_vit_b_01ec64.pth
(Apache-2.0). Each prompt runs on a crop around its box and points, so thin parts keep their edges.
--sheet writes a review image: every region's final mask in colour, outlined and labelled, bone
pivots as dots, a 100 px grid.
"""
import argparse
import colorsys
import json
import os
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
sys.path.insert(0, os.path.join(ROOT, "tools"))
sys.path.insert(0, os.environ.get("HALO_PYLIB", os.path.join(ROOT, ".pylib")))

import numpy as np  # noqa: E402
from PIL import Image, ImageDraw, ImageFont  # noqa: E402

import art_warp_build as awb  # noqa: E402

MIN_CROP = 448       # px: SAM sees at least this much context round a part
CROP_PAD = 0.45      # share of the prompt extent added on each side


def sam_rules(rule):
    if not isinstance(rule, dict):
        return
    if rule.get("type") == "sam":
        yield rule
    for r in rule.get("rules", []):
        yield from sam_rules(r)
    if "within" in rule:
        yield from sam_rules(rule["within"])


class Sam:
    def __init__(self, cpu=False):
        import torch
        from segment_anything import SamPredictor, sam_model_registry
        ck = os.environ.get("SAM_CHECKPOINT", "D:/comfyui/models/sams/sam_vit_b_01ec64.pth")
        kind = "vit_h" if "vit_h" in ck else "vit_l" if "vit_l" in ck else "vit_b"
        self.dev = "cuda" if torch.cuda.is_available() and not cpu else "cpu"
        model = sam_model_registry[kind](checkpoint=ck)
        model.to(self.dev)
        self.pred = SamPredictor(model)
        self.torch = torch

    def mask(self, rgb, alpha, rule):
        H, W = alpha.shape
        pts = [list(map(float, p)) for p in rule.get("points", [])]
        neg = [list(map(float, p)) for p in rule.get("neg", [])]
        box = [float(v) for v in rule["box"]] if "box" in rule else None
        if not pts and box is None:
            raise ValueError("sam rule needs points or a box")
        xs = [p[0] for p in pts] + ([box[0], box[2]] if box else [])
        ys = [p[1] for p in pts] + ([box[1], box[3]] if box else [])
        x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
        pw, ph = max(x1 - x0, 1.0), max(y1 - y0, 1.0)
        side_w = max(pw * (1 + 2 * CROP_PAD), MIN_CROP)
        side_h = max(ph * (1 + 2 * CROP_PAD), MIN_CROP)
        cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
        c0x = int(max(0, min(W - side_w, cx - side_w / 2)))
        c0y = int(max(0, min(H - side_h, cy - side_h / 2)))
        c1x, c1y = int(min(W, c0x + side_w)), int(min(H, c0y + side_h))
        self.pred.set_image(np.ascontiguousarray(rgb[c0y:c1y, c0x:c1x]))
        coords = np.array([[p[0] - c0x, p[1] - c0y] for p in pts + neg], np.float32) if pts or neg else None
        labels = np.array([1] * len(pts) + [0] * len(neg), np.int32) if coords is not None else None
        b = np.array([box[0] - c0x, box[1] - c0y, box[2] - c0x, box[3] - c0y], np.float32) if box else None
        with self.torch.no_grad():
            masks, scores, _ = self.pred.predict(point_coords=coords, point_labels=labels, box=b, multimask_output=True)
        areas = masks.reshape(masks.shape[0], -1).sum(1)
        pick = rule.get("pick", "best")
        if pick == "best":
            i = int(np.argmax(scores))
        elif pick == "small":
            i = int(np.argmin(areas))
        elif pick == "large":
            i = int(np.argmax(areas))
        else:
            i = int(pick)
        m = np.zeros((H, W), bool)
        m[c0y:c1y, c0x:c1x] = masks[i]
        if rule.get("clip") and box:
            keep = np.zeros_like(m)
            keep[int(max(0, box[1])):int(min(H, box[3])) + 1, int(max(0, box[0])):int(min(W, box[2])) + 1] = True
            m &= keep
        m &= alpha > 0.1
        return m, float(scores[i])


def load_src(rig):
    hdir, name, _ = awb.rig_dir(rig)
    src_path = os.path.join(hdir, name + ".warp_src.json")
    src = json.load(open(src_path))
    img = Image.open(os.path.join(hdir, src.get("image", name + ".png"))).convert("RGBA")
    return hdir, name, src, img


def run(rig, sam, force=False):
    hdir, name, src, img = load_src(rig)
    awb.set_mask_context(hdir, img)
    alpha = np.array(img.split()[3]).astype(np.float32) / 255.0
    rgba = np.array(img).astype(np.float32)
    grey = np.full(rgba.shape[:2] + (3,), 128.0, np.float32)
    rgb = (rgba[..., :3] * alpha[..., None] + grey * (1 - alpha[..., None])).astype(np.uint8)
    os.makedirs(awb.sam_dir(), exist_ok=True)
    gi = os.path.join(hdir, "masks", ".gdignore")
    if not os.path.exists(gi):
        open(gi, "w").close()
    made = kept = 0
    want = set()
    for reg in src.get("regions", []):
        for r in sam_rules(reg.get("rule", {})):
            path = awb.sam_path(r)
            want.add(os.path.basename(path))
            if os.path.exists(path) and not force:
                kept += 1
                continue
            m, score = sam.mask(rgb, alpha, r)
            Image.fromarray((m * 255).astype(np.uint8), "L").convert("1").save(path, optimize=True)
            made += 1
            if score < 0.8 or m.sum() < 50:
                print("art_parts: [%s] %s: weak mask (score %.2f, %d px)" % (rig, reg["name"], score, int(m.sum())))
    # drop cached masks no rule uses any more
    for f in os.listdir(awb.sam_dir()):
        if f.endswith(".png") and f not in want:
            os.remove(os.path.join(awb.sam_dir(), f))
    print("art_parts: [%s] %d sam masks made, %d cached" % (rig, made, kept))


def colour(i):
    r, g, b = colorsys.hsv_to_rgb((i * 0.61803) % 1.0, 0.85, 1.0)
    return int(r * 255), int(g * 255), int(b * 255)


def grid_image(img, step=100):
    W, H = img.size
    bg = Image.new("RGBA", img.size, (60, 56, 72, 255))
    bg.alpha_composite(img)
    d = ImageDraw.Draw(bg)
    font = ImageFont.load_default()
    for x in range(0, W, step):
        d.line([(x, 0), (x, H)], fill=(255, 255, 255, 70) if x % 500 else (255, 255, 0, 120), width=1)
        for y in range(0, H, 400):
            d.text((x + 2, y + 2), str(x), fill=(255, 255, 0, 255), font=font)
    for y in range(0, H, step):
        d.line([(0, y), (W, y)], fill=(255, 255, 255, 70) if y % 500 else (255, 255, 0, 120), width=1)
        for x in range(0, W, 400):
            d.text((x + 2, y + 2), str(y), fill=(0, 255, 255, 255), font=font)
    return bg


def sheet(rig, out, scale=0.5):
    hdir, name, src, img = load_src(rig)
    awb.set_mask_context(hdir, img)
    W, H = img.size
    base = grid_image(img)
    over = np.zeros((H, W, 4), np.float32)
    labels = []
    for i, reg in enumerate(src.get("regions", [])):
        m = np.array(awb.rule_mask(reg["rule"], img)).astype(np.float32) / 255.0 if "rule" in reg else \
            np.array(Image.open(os.path.join(hdir, reg.get("mask", "masks/%s.png" % reg["name"]))).convert("L")).astype(np.float32) / 255.0
        c = colour(i)
        a = m * 0.45
        over[..., :3] = over[..., :3] * (1 - a[..., None]) + np.array(c, np.float32) * a[..., None]
        over[..., 3] = np.maximum(over[..., 3], a * 255)
        edge = (m > 0.5) ^ (np.roll(m > 0.5, 1, 0) | np.roll(m > 0.5, 1, 1)) & (m > 0.5)
        over[edge] = [*c, 255]
        ys, xs = np.nonzero(m > 0.5)
        if len(xs):
            labels.append((int(xs.mean()), int(ys.mean()), reg["name"], c))
    lay = Image.fromarray(over.astype(np.uint8), "RGBA")
    base.alpha_composite(lay)
    d = ImageDraw.Draw(base)
    font = ImageFont.load_default()
    for b in src.get("bones", []):
        if "pivot" in b:
            x, y = b["pivot"]
            d.ellipse([x - 6, y - 6, x + 6, y + 6], fill=(255, 255, 255, 255), outline=(0, 0, 0, 255), width=2)
    for x, y, n, c in labels:
        d.rectangle([x - 2, y - 2, x + 7 * len(n) + 2, y + 12], fill=(0, 0, 0, 200))
        d.text((x, y), n, fill=c + (255,), font=font)
    if scale != 1.0:
        base = base.resize((int(W * scale), int(H * scale)), Image.LANCZOS)
    base.convert("RGB").save(out)
    print("art_parts: sheet", out)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("rigs", nargs="+")
    ap.add_argument("--sheet", help="review image path (one rig) or folder (several)")
    ap.add_argument("--sheet-scale", type=float, default=0.5)
    ap.add_argument("--grid", help="write the art with a coordinate grid here and stop")
    ap.add_argument("--cpu", action="store_true")
    ap.add_argument("--force", action="store_true", help="re-run SAM even for cached masks")
    a = ap.parse_args()
    if a.grid:
        _, _, _, img = load_src(a.rigs[0])
        grid_image(img).convert("RGB").save(a.grid)
        print("art_parts: grid", a.grid)
        return
    sam = None
    for rig in a.rigs:
        _, _, src, _ = load_src(rig)
        if any(True for reg in src.get("regions", []) for _ in sam_rules(reg.get("rule", {}))):
            sam = sam or Sam(a.cpu)
            run(rig, sam, a.force)
        if a.sheet:
            out = a.sheet if len(a.rigs) == 1 else os.path.join(a.sheet, rig.replace("@", "__") + "_parts.png")
            sheet(rig, out, a.sheet_scale)


if __name__ == "__main__":
    main()
