"""Bakes a growth map next to every rendered growth (the thorns, jelly and moss of
assets/art/ui/physical/ and the rival thorns of assets/art/ui/objects/) for the growth shader
(src/ui/shaders/growth.gdshader, PhysicalKit.come_alive): the piece grows from its root along its
branches when it appears, then sways, twists and breathes a little.

    python tools/blender/growth_maps.py [names...]      # all growths when no names are given

For <name>.png it writes <name>_grow.png (half size, RGBA, data: no colour space) and an entry in
growth.json in the same folder ({"root": [u, v], "len": the longest branch in px}):
  R  growth order: how far along the shape a pixel is from the root (a geodesic distance through the
     piece's body, 0 at the root, 1 at the furthest tip); pixels off the body (soft shadow, fur
     fringes, empty) take the order of the nearest body pixel, so they appear with it
  G  soft: moss and fur, which shimmer a little
  B  glow: LED beads (jelly) and crystal (thorns), which pulse softly
  A  sway weight: the order blurred, so the motion field is smooth between nearby branches
Roots: a corner piece's manifest origin (the poster corner it grows from), the centre of edges and
clumps; the rival thorns grow from the corner bud (thorns_corner) and the top of the stem
(thorns_vine). Needs numpy and Pillow only. Run tools/gd --headless --path . --import afterwards
(the maps' .import files keep fix_alpha_border off: A is data).
"""
import heapq
import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PHYS = os.path.join(ROOT, "assets", "art", "ui", "physical")
OBJS = os.path.join(ROOT, "assets", "art", "ui", "objects")
# Rival thorns (no manifest): where each grows from, as a fraction of the image.
OBJ_ROOTS = {"thorns_corner": "bud", "thorns_vine": "top"}
BODY_A = 0.55
IMPORT = """[remap]

importer="texture"
type="CompressedTexture2D"

[params]

compress/mode=0
compress/high_quality=false
compress/lossy_quality=0.7
compress/uastc_level=0
compress/rdo_quality_loss=0.0
compress/hdr_compression=1
compress/normal_map=0
compress/channel_pack=0
mipmaps/generate=false
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/channel_remap/red=0
process/channel_remap/green=1
process/channel_remap/blue=2
process/channel_remap/alpha=3
process/fix_alpha_border=false
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=0
"""


def growths() -> list:
    out = []
    for f in sorted(os.listdir(PHYS)):
        if f.endswith(".png") and not f.endswith("_grow.png") and (f.startswith("thorn_") or f.startswith("jelly_")):
            out.append((PHYS, f[:-4]))
    for n in OBJ_ROOTS:
        out.append((OBJS, n))
    return out


def blur(a: np.ndarray, sigma: float) -> np.ndarray:
    """Separable Gaussian blur (numpy only), edges clamped."""
    r = max(1, int(math.ceil(sigma * 3)))
    k = np.exp(-0.5 * (np.arange(-r, r + 1) / sigma) ** 2)
    k /= k.sum()
    p = np.pad(a, ((r, r), (0, 0)), mode="edge")
    a = sum(k[i] * p[i:i + a.shape[0]] for i in range(2 * r + 1))
    p = np.pad(a, ((0, 0), (r, r)), mode="edge")
    return sum(k[i] * p[:, i:i + a.shape[1]] for i in range(2 * r + 1))


def geodesic(cost: np.ndarray, start: tuple) -> np.ndarray:
    """Dijkstra over the pixel grid (8 neighbours); cost = per-pixel step multiplier."""
    h, w = cost.shape
    dist = np.full((h, w), np.inf)
    sy, sx = start
    dist[sy, sx] = 0.0
    heap = [(0.0, sy, sx)]
    steps = [(-1, 0, 1.0), (1, 0, 1.0), (0, -1, 1.0), (0, 1, 1.0),
        (-1, -1, 1.4142), (-1, 1, 1.4142), (1, -1, 1.4142), (1, 1, 1.4142)]
    cl = cost.tolist()
    dl = dist.tolist()
    while heap:
        d, y, x = heapq.heappop(heap)
        if d > dl[y][x]:
            continue
        for dy, dx, s in steps:
            ny, nx = y + dy, x + dx
            if 0 <= ny < h and 0 <= nx < w:
                nd = d + s * 0.5 * (cl[y][x] + cl[ny][nx])
                if nd < dl[ny][nx]:
                    dl[ny][nx] = nd
                    heapq.heappush(heap, (nd, ny, nx))
    return np.array(dl)


def fill_from(values: np.ndarray, known: np.ndarray) -> np.ndarray:
    """Every unknown pixel takes the mean of its known neighbours, ring by ring (nearest fill)."""
    v = np.where(known, values, 0.0).astype(np.float64)
    k = known.copy()
    while not k.all():
        s = np.zeros_like(v)
        n = np.zeros_like(v)
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                if dy == 0 and dx == 0:
                    continue
                sv = np.roll(np.roll(v * k, dy, 0), dx, 1)
                sk = np.roll(np.roll(k.astype(np.float64), dy, 0), dx, 1)
                # np.roll wraps: drop what came round the edge.
                if dy == 1:
                    sv[0, :] = 0
                    sk[0, :] = 0
                if dy == -1:
                    sv[-1, :] = 0
                    sk[-1, :] = 0
                if dx == 1:
                    sv[:, 0] = 0
                    sk[:, 0] = 0
                if dx == -1:
                    sv[:, -1] = 0
                    sk[:, -1] = 0
                s += sv
                n += sk
        new = (~k) & (n > 0)
        if not new.any():
            break
        v[new] = s[new] / n[new]
        k = k | new
    return v


def hsv(rgb: np.ndarray):
    mx = rgb.max(axis=2)
    mn = rgb.min(axis=2)
    d = mx - mn
    s = np.where(mx > 1e-4, d / np.maximum(mx, 1e-4), 0.0)
    r, g, b = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]
    hh = np.zeros_like(mx)
    dd = np.maximum(d, 1e-6)
    hh = np.where(mx == r, ((g - b) / dd) % 6.0, hh)
    hh = np.where(mx == g, (b - r) / dd + 2.0, hh)
    hh = np.where(mx == b, (r - g) / dd + 4.0, hh)
    return hh / 6.0, s, mx


def root_px(folder: str, name: str, alpha: np.ndarray, manifest: dict) -> tuple:
    """The root in full-size px (x, y)."""
    h, w = alpha.shape
    body = alpha > BODY_A
    if folder == PHYS:
        o = manifest.get(name, {}).get("origin")
        if o:
            return float(o[0]), float(o[1])
        return w * 0.5, h * 0.5
    how = OBJ_ROOTS.get(name, "bud")
    ys, xs = np.nonzero(body)
    if how == "top":
        i = int(np.argmin(ys))
        return float(xs[i]), float(ys[i])
    # The bud: the thickest part of the body (most body pixels in a disc around it).
    thick = blur(body.astype(np.float64), max(w, h) / 60.0)
    y, x = np.unravel_index(int(np.argmax(thick)), thick.shape)
    return float(x), float(y)


def bake(folder: str, name: str, manifest: dict, meta: dict) -> None:
    src = Image.open(os.path.join(folder, name + ".png")).convert("RGBA")
    full = np.asarray(src, np.float64) / 255.0
    rx, ry = root_px(folder, name, full[:, :, 3], manifest)
    hw, hh = (src.width + 1) // 2, (src.height + 1) // 2
    im = np.asarray(src.resize((hw, hh), Image.BOX), np.float64) / 255.0
    a = im[:, :, 3]
    rgb = im[:, :, :3] / np.maximum(a[:, :, None], 1e-3)
    rgb = np.clip(rgb, 0.0, 1.0)
    body = a > BODY_A
    # Start on the body pixel nearest the root.
    ys, xs = np.nonzero(body)
    j = int(np.argmin((xs - rx * hw / src.width) ** 2 + (ys - ry * hh / src.height) ** 2))
    start = (int(ys[j]), int(xs[j]))
    # Cheap through the body, dearer across fringes, dear across empty paper (small gaps only).
    cost = np.where(body, 1.0, np.where(a > 0.12, 3.0, 12.0))
    g = geodesic(cost, start)
    gmax = float(g[body].max()) if body.any() else 1.0
    order = np.clip(g / max(gmax, 1.0), 0.0, 1.0)
    order = fill_from(order, body)
    order = np.clip(order, 0.0, 1.0)
    weight = np.clip(blur(order, 5.0), 0.0, 1.0)
    hue, sat, val = hsv(rgb)
    # Moss (green) and fur (pale, fuzzy, semi-transparent strands).
    moss = ((hue > 0.17) & (hue < 0.45) & (sat > 0.28) & (a > 0.25)).astype(np.float64)
    # Fur is a pale fuzzy blob: keep where pale strands are dense, not a chrome edge's thin rim.
    pale = ((a > 0.06) & (val > 0.62) & (sat < 0.22)).astype(np.float64)
    fur = np.clip((blur(pale, 2.0) - 0.3) * 3.0, 0.0, 1.0) * (a > 0.04)
    soft = np.clip(blur(np.maximum(moss, fur * 0.8), 0.8), 0.0, 1.0)
    # Glow: saturated bright spots that are not moss (LED beads, crystal).
    lit = ((sat > 0.5) & (val > 0.55) & ~((hue > 0.17) & (hue < 0.45)) & (a > 0.4)).astype(np.float64)
    strength = 1.0 if name.startswith("jelly") else (0.55 if "black" in name else 0.5)
    glow = np.clip(blur(lit, 1.2) * 1.6, 0.0, 1.0) * strength
    out = np.dstack([order, soft, glow, weight])
    Image.fromarray(np.round(out * 255.0).astype(np.uint8), "RGBA").save(os.path.join(folder, name + "_grow.png"), optimize=True)
    imp = os.path.join(folder, name + "_grow.png.import")
    if not os.path.exists(imp):
        with open(imp, "w", newline="\n") as f:
            f.write(IMPORT)
    meta[name] = {"root": [round(rx / src.width, 4), round(ry / src.height, 4)], "len": round(gmax * 2.0, 1)}
    print(name, meta[name], "body px", int(body.sum()))


def main() -> None:
    manifest = json.load(open(os.path.join(PHYS, "physical.json")))
    want = set(sys.argv[1:])
    metas = {}
    for folder, name in growths():
        if want and name not in want:
            continue
        path = os.path.join(folder, "growth.json")
        if folder not in metas:
            metas[folder] = json.load(open(path)) if os.path.exists(path) else {}
        bake(folder, name, manifest, metas[folder])
    for folder, meta in metas.items():
        with open(os.path.join(folder, "growth.json"), "w", newline="\n") as f:
            json.dump(dict(sorted(meta.items())), f, indent=1)
            f.write("\n")


if __name__ == "__main__":
    main()
