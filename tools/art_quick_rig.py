"""Quick HaloRig source for a skin (or hero) image: body bones and regions from the face box and the
silhouette, no hand-drawn hair, wing, weapon or cloth polygons and no face overlays.

    python tools/art_quick_rig.py imra@lucky_ember --face 452,640,120,128 [--seed 207000]
    python tools/art_quick_rig.py --faces faces.json      # {"<hero>@<art>": {"face": [x,y,w,h], "seed": n}, ...}
    python tools/art_warp_build.py imra@lucky_ember --regen-masks      # then the Godot import

Writes assets/art/heroes/<hero>/skins/<art>/<art>.warp_src.json (or <hero>/<hero>.warp_src.json without
"@<art>"). The face box is in pixels of the installed 1024x2048 image (brow to chin, cheek to cheek).
The rig breathes, sways and turns its head; blinks, talking and spring parts (hair, wings, tails)
need variants and a hand-made rig (docs/dev/halorig.md section 8, docs/dev/skins.md Production).
"""
import argparse
import json
import os
import sys

import numpy as np
from PIL import Image

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
HEROES = os.path.join(ROOT, "assets", "art", "heroes")
FX = {"celestial": "#ffe9a8", "infernal": "#ff8a3d", "fallen": "#b48cff"}
SOLES = (512, 1990)


def paths(rig_id):
    hero, _, art = rig_id.partition("@")
    d = os.path.join(HEROES, hero, "skins", art) if art else os.path.join(HEROES, hero)
    name = art or hero
    return hero, art, d, os.path.join(d, name + ".png"), os.path.join(d, name + ".warp_src.json")


def body_x(alpha, y, guess, max_w):
    """Midpoint of the opaque run at row y nearest to guess, if it is body-sized; else guess."""
    row = alpha[int(y)] > 40
    if not row.any():
        return guess
    edges = np.flatnonzero(np.diff(np.concatenate([[0], row.astype(np.int8), [0]])))
    runs = list(zip(edges[::2], edges[1::2]))
    best = min(runs, key=lambda r: 0 if r[0] <= guess < r[1] else min(abs(r[0] - guess), abs(r[1] - guess)))
    if best[1] - best[0] > max_w:
        return guess
    return (best[0] + best[1]) / 2.0


def build(rig_id, face, seed=None):
    hero, art, d, img, out = paths(rig_id)
    if not os.path.exists(img):
        raise SystemExit("no image %s" % os.path.relpath(img, ROOT))
    heroes = {h["id"]: h for h in json.load(open(os.path.join(ROOT, "data", "heroes.json")))["heroes"]}
    alpha = np.array(Image.open(img).convert("RGBA"))[:, :, 3]
    fx, fy, fw, fh = face
    fcx, chin = fx + fw / 2.0, fy + fh
    L = SOLES[1] - chin                                 # chin to soles
    ys = {"neck": chin + 0.03 * L, "chest": chin + 0.13 * L, "waist": chin + 0.24 * L, "hips": chin + 0.33 * L}
    feet = alpha[SOLES[1] - 60:SOLES[1] + 1] > 40
    cols = np.flatnonzero(feet.any(axis=0))
    feet_x = float(cols.mean()) if len(cols) else SOLES[0]
    pts = {}
    for k, y in ys.items():
        t = (y - chin) / L
        guess = fcx + (feet_x - fcx) * t
        pts[k] = (round(body_x(alpha, y, guess, fw * 2.6)), round(y))
    nx, ny = pts["neck"]
    cx, cy = pts["chest"]
    wx, wy = pts["waist"]
    sw = fw * 1.15                                       # half shoulder width
    r = lambda v: int(round(v))
    bones = [
        {"name": "hips", "parent": "root", "pivot": list(pts["hips"])},
        {"name": "torso", "parent": "hips", "pivot": [wx, wy]},
        {"name": "chest", "parent": "torso", "pivot": [cx, cy]},
        {"name": "neck", "parent": "chest", "pivot": [nx, ny]},
        {"name": "head", "parent": "neck", "pivot": [r(fcx - fw * 0.05), r(fy + fh * 1.02)]},
        {"name": "face", "parent": "head", "pivot": [r(fcx), r(fy + fh * 0.45)]},
        {"name": "hair_front", "parent": "head", "pivot": [r(fcx), r(fy - fh * 0.15)]},
    ]
    regions = [
        {"name": "face", "bone": "face", "rule": {"type": "ellipse", "center": [r(fcx), r(fy + fh * 0.55)],
                                                  "radius": [r(fw * 0.52), r(fh * 0.44)], "feather": 14}},
        {"name": "hair_front", "rule": {"type": "ellipse", "center": [r(fcx), r(fy + fh * 0.02)],
                                        "radius": [r(fw * 0.62), r(fh * 0.3)], "feather": 12}},
        {"name": "head", "rule": {"type": "ellipse", "center": [r(fcx), r(fy + fh * 0.35)],
                                  "radius": [r(fw * 1.0), r(fh * 0.95)], "feather": 22}},
        {"name": "chest", "rule": {"type": "polygon", "points": [[r(p[0]), r(p[1])] for p in (
            (nx - sw * 0.55, ny - 10), (nx + sw * 0.55, ny - 10), (cx + sw, cy - 60), (cx + sw * 0.95, wy - 20),
            (wx + sw * 0.7, wy + 10), (wx - sw * 0.7, wy + 10), (cx - sw * 0.95, wy - 20), (cx - sw, cy - 60))],
            "feather": 40}},
    ]
    # portrait: a square around the face, kept inside the image (a face near an edge shifts it)
    H_img, W_img = alpha.shape
    psize = min(r(max(300, fw * 2.7)), W_img, H_img)
    pcx = min(max(r(fcx), psize // 2 + 1), W_img - psize // 2 - 1)
    pcy = min(max(r(fy + fh * 0.5), psize // 2 + 1), H_img - psize // 2 - 1)
    h = heroes.get(hero, {})
    label = "%s %s" % (hero, art) if art else hero
    # weapon / attack style come from the hero's own rig (hero_sprite.attack_anim reads them);
    # read before writing, since rebuilding the base look overwrites that same file
    base_src = os.path.join(HEROES, hero, hero + ".warp_src.json")
    base_meta = (json.load(open(base_src)).get("meta") or {}) if os.path.exists(base_src) else {}
    meta = {k: base_meta[k] for k in ("weapon", "attack") if k in base_meta}
    meta.update({"fx_color": FX.get(h.get("faction"), "#ffe9a8"), "art": "comfy s%s quick" % seed})
    src = {
        "_doc": "HaloRig warp rig source for %s, written by tools/art_quick_rig.py (body bones from the face box and "
                "the silhouette; no spring parts or face overlays yet). ComfyUI candidate s%s, cut out without the face "
                "pass or the tiled 2x repaint. Coordinates are image pixels (1024x2048, soles at the origin)."
                % (label, seed if seed is not None else "?"),
        "image": os.path.basename(img), "origin": list(SOLES), "grid": [24, 48], "texel_scale": 1.0,
        "portrait": [pcx, pcy, psize], "look_px": [8, 5],
        "meta": meta,
        "body_bone": "hips", "bones": bones, "regions": regions, "overlays": [],
    }
    with open(out, "w", newline="\n") as f:
        f.write(dumps(src))
    return out


def dumps(src):
    """Readable JSON: one bone / region per line (same layout as tools/art_import/rigs.py)."""
    lines = ["{"]
    keys = list(src.keys())
    for i, k in enumerate(keys):
        comma = "," if i < len(keys) - 1 else ""
        v = src[k]
        if isinstance(v, list) and v and k in ("bones", "regions", "overlays"):
            lines.append('  "%s": [' % k)
            for j, e in enumerate(v):
                lines.append("    " + json.dumps(e, separators=(", ", ": ")) + ("," if j < len(v) - 1 else ""))
            lines.append("  ]" + comma)
        else:
            lines.append('  "%s": %s%s' % (k, json.dumps(v, separators=(", ", ": ")), comma))
    lines.append("}")
    return "\n".join(lines) + "\n"


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("rig_id", nargs="?", help="<hero>@<art> or <hero>")
    ap.add_argument("--face", help="x,y,w,h in image pixels")
    ap.add_argument("--seed", type=int)
    ap.add_argument("--faces", help="JSON {rig_id: {face: [x,y,w,h], seed: n}}")
    a = ap.parse_args(argv)
    jobs = {}
    if a.faces:
        jobs.update(json.load(open(a.faces)))
    if a.rig_id:
        if not a.face:
            ap.error("--face x,y,w,h is required with a rig id")
        jobs[a.rig_id] = {"face": [int(v) for v in a.face.split(",")], "seed": a.seed}
    if not jobs:
        ap.error("give a rig id and --face, or --faces")
    for rid, j in jobs.items():
        if rid.startswith("_"):
            continue
        print("wrote", os.path.relpath(build(rid, j["face"], j.get("seed")), ROOT))
    return 0


if __name__ == "__main__":
    sys.exit(main())
