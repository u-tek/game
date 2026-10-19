"""Turns the Blender renders of the campaign worlds into game assets (style v4).

    python tools/blender/finish_worlds.py <bake_dir> [which] [--preview] [--out <dir>]
    python tools/blender/finish_worlds.py clouds <render_dir> [--out <dir>]

clouds: packs tools/blender/clouds.py's renders into assets/art/worlds/clouds.png (the cumulus
sprites, a 3 x 2 atlas of 320 px cells, each cloud cropped and centred, straight alpha) and
clouds_shadow.png (their top-down silhouettes, blurred, a 3 x 2 atlas of 128 px cells, white = shade).

Planets: tools/blender/planets.py's bakes. which: all | comma list of 1-6. Per world N it writes
into assets/art/worlds/ (or --out):
  w<N>_albedo.jpg  2048 x 1024 sRGB: the world's tint ramp over the baked albedo, with cavity
                   occlusion and steep-slope darkening baked in (the light is added in the game).
  w<N>_normal.jpg  1536 x 768 surface normal in the sphere's own frame (R east, G north, 0.5 =
                   flat; B is 0, the shader rebuilds it), computed from the 2x height bake, so the
                   shader needs no tangents.
  w<N>_height.png  1024 x 512: R height (0..1, 0.5 = the mean radius, for the vertex
                   displacement), G the feature mask (lava, ice cracks, crystal tips ...).
--preview also writes <bake_dir>/w<N>_lit.png: the maps lit on a sphere (numpy, a quick check).
Equirect maps follow Godot's SphereMesh: u = longitude from +Z towards +X, v = 0 at the north pole.
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageFile

# Optimised JPEGs of noisy maps need a bigger encoder buffer.
ImageFile.MAXBLOCK = 1 << 25

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# Per world: the albedo ramp (sRGB low -> high), normal relief (radius units over the 0..1
# height), cavity strength and steep-slope darkening.
WORLDS = {
    1: {"lo": (0.25, 0.245, 0.235), "hi": (0.88, 0.865, 0.83), "relief": 0.075, "cav": 2.4, "slope": 0.55},
    2: {"lo": (0.27, 0.225, 0.205), "hi": (0.84, 0.77, 0.71), "relief": 0.085, "cav": 2.6, "slope": 0.6},
    3: {"lo": (0.17, 0.17, 0.205), "hi": (0.85, 0.845, 0.875), "relief": 0.07, "cav": 2.2, "slope": 0.45},
    4: {"lo": (0.4, 0.455, 0.52), "hi": (0.95, 0.965, 0.985), "relief": 0.06, "cav": 1.8, "slope": 0.35},
    5: {"lo": (0.075, 0.07, 0.075), "hi": (0.5, 0.47, 0.45), "relief": 0.08, "cav": 2.0, "slope": 0.4},
    6: {"lo": (0.2, 0.195, 0.245), "hi": (0.93, 0.925, 0.97), "relief": 0.075, "cav": 2.2, "slope": 0.3},
}


def box_x(a: np.ndarray, r: int) -> np.ndarray:
    """Box blur along x, wrapping (longitude)."""
    if r < 1:
        return a
    p = np.concatenate([a[:, -r - 1:], a, a[:, :r]], axis=1)
    c = np.cumsum(p, axis=1, dtype=np.float64)
    return ((c[:, 2 * r + 1:] - c[:, :-2 * r - 1]) / (2 * r + 1)).astype(np.float32)


def box_y(a: np.ndarray, r: int) -> np.ndarray:
    """Box blur along y, clamped at the poles."""
    if r < 1:
        return a
    p = np.concatenate([np.repeat(a[:1], r + 1, axis=0), a, np.repeat(a[-1:], r, axis=0)], axis=0)
    c = np.cumsum(p, axis=0, dtype=np.float64)
    return ((c[2 * r + 1:] - c[:-2 * r - 1]) / (2 * r + 1)).astype(np.float32)


def blur(a: np.ndarray, r: int) -> np.ndarray:
    """About a Gaussian of radius r: three box passes each way."""
    k = max(1, int(round(r / 1.7)))
    for _ in range(3):
        a = box_y(box_x(a, k), k)
    return a


def down2(a: np.ndarray) -> np.ndarray:
    return a.reshape(a.shape[0] // 2, 2, a.shape[1] // 2, 2, *a.shape[2:]).mean(axis=(1, 3))


def normals(h: np.ndarray, relief: float) -> np.ndarray:
    """Surface normals in the sphere frame (east, north, up) for r = 1 + relief * (h - 0.5)."""
    H, W = h.shape
    th = (np.pi * (np.arange(H) + 0.5) / H)[:, None]
    st = np.sin(th)
    r = 1.0 + relief * (h - 0.5)
    dphi = 2.0 * np.pi / W
    dth = np.pi / H
    r_phi = relief * (np.roll(h, -1, 1) - np.roll(h, 1, 1)) / (2.0 * dphi)
    hp = np.concatenate([h[1:], h[-1:]], axis=0)
    hm = np.concatenate([h[:1], h[:-1]], axis=0)
    r_th = relief * (hp - hm) / (2.0 * dth)
    ne = -r_phi / (r * np.maximum(st, 0.04))
    nn = r_th / r
    # The poles fade to flat (the frame is singular there).
    w = np.clip((st - 0.02) / 0.1, 0.0, 1.0)
    n = np.stack([ne * w, nn * w, np.ones_like(h)], axis=-1)
    return n / np.linalg.norm(n, axis=-1, keepdims=True)


def finish(n: int, bake: str, out: str, preview: bool) -> None:
    cfg = WORLDS[n]
    h = np.load(os.path.join(bake, "w%d_h.npy" % n)).astype(np.float32)
    a = np.load(os.path.join(bake, "w%d_a.npy" % n)).astype(np.float32)
    m = np.load(os.path.join(bake, "w%d_m.npy" % n)).astype(np.float32)
    lo, hi = np.percentile(h, [0.3, 99.7])
    h = np.clip((h - lo) / max(hi - lo, 1e-6), 0.0, 1.0)
    # Centre the mean radius on 0.5 (the displacement keeps the planet's size).
    h = np.clip(h - float(h.mean()) + 0.5, 0.0, 1.0)
    # The normals see the fine relief boosted (an unsharp mask of the height): the grain the
    # displaced reference planet shows, without changing the large shapes.
    hd = h + cfg.get("detail", 2.2) * (h - blur(h, 5))
    nrm2 = normals(hd, cfg["relief"])
    nrm = down2(nrm2)
    nrm /= np.linalg.norm(nrm, axis=-1, keepdims=True)
    h1 = down2(h)
    # Cavity: lower than the neighbourhood at three scales darkens.
    cav = np.zeros_like(h1)
    for rad, k in ((2, 0.9), (7, 0.7), (22, 0.5)):
        cav += np.clip(blur(h1, rad) - h1, 0.0, None) * k
    ao = np.clip(1.0 - cav * cfg["cav"], 0.25, 1.0)
    slope = 1.0 - nrm[..., 2]
    base = np.clip(a, 0.0, 1.0)
    lo_c = np.array(cfg["lo"], dtype=np.float32)
    hi_c = np.array(cfg["hi"], dtype=np.float32)
    col = lo_c + (hi_c - lo_c) * base[..., None]
    col *= (ao * (1.0 - np.clip(slope * cfg["slope"] * 2.0, 0.0, 0.6)))[..., None]
    col = np.clip(col, 0.0, 1.0)
    os.makedirs(out, exist_ok=True)
    Image.fromarray((col * 255.0 + 0.5).astype(np.uint8), "RGB").save(
        os.path.join(out, "w%d_albedo.jpg" % n), quality=86, subsampling=0, optimize=True)
    # B is rebuilt in the shader (and dropped by the RG normal-map import): a flat 0 keeps it cheap.
    enc = np.clip(nrm * 0.5 + 0.5, 0.0, 1.0)
    enc[..., 2] = 0.0
    # Three quarters of the albedo's size (the iPhone's VRAM copy is RG, 1 byte a pixel).
    nim = Image.fromarray((enc * 255.0 + 0.5).astype(np.uint8), "RGB")
    nim = nim.resize((nim.width * 3 // 4, nim.height * 3 // 4), Image.LANCZOS)
    nim.save(os.path.join(out, "w%d_normal.jpg" % n), quality=86, subsampling=0, optimize=True)
    h2 = down2(h1)
    m2 = down2(np.clip(m, 0.0, 1.0)) if m.shape[0] == h1.shape[0] else np.clip(m, 0.0, 1.0)
    if m2.shape != h2.shape:
        m2 = np.asarray(Image.fromarray(m2.astype(np.float32), "F").resize((h2.shape[1], h2.shape[0]), Image.BILINEAR))
    hm = np.stack([h2, m2, np.zeros_like(h2)], axis=-1)
    Image.fromarray((np.clip(hm, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8), "RGB").save(
        os.path.join(out, "w%d_height.png" % n), optimize=True)
    print("w%d  albedo %s  normal %s  height %s" % (n, col.shape[:2], nrm.shape[:2], h2.shape))
    if preview:
        lit = render(col, nrm, m2, n)
        Image.fromarray(lit, "RGB").save(os.path.join(bake, "w%d_lit.png" % n))


def render(col: np.ndarray, nrm: np.ndarray, mask: np.ndarray, n: int, size: int = 900, spin: float = 0.6) -> np.ndarray:
    """An orthographic view of the planet lit from the top left (numpy, nearest samples)."""
    H, W = col.shape[:2]
    ys, xs = np.mgrid[0:size, 0:size]
    x = (xs + 0.5) / size * 2.2 - 1.1
    y = 1.1 - (ys + 0.5) / size * 2.2
    rr = x * x + y * y
    inside = rr < 1.0
    z = np.sqrt(np.clip(1.0 - rr, 0.0, 1.0))
    # Rotate the view about the planet's axis (spin) and tilt it a little.
    tilt = math.radians(-14.0)
    y2 = y * math.cos(tilt) - z * math.sin(tilt)
    z2 = y * math.sin(tilt) + z * math.cos(tilt)
    px = x * math.cos(spin) + z2 * math.sin(spin)
    pz = -x * math.sin(spin) + z2 * math.cos(spin)
    py = y2
    th = np.arccos(np.clip(py, -1.0, 1.0))
    ph = np.arctan2(px, pz) % (2.0 * np.pi)
    ui = np.clip((ph / (2.0 * np.pi) * W).astype(int), 0, W - 1)
    vi = np.clip((th / np.pi * H).astype(int), 0, H - 1)
    c = col[vi, ui]
    nl = nrm[vi, ui]
    up = np.stack([px, py, pz], axis=-1)
    east = np.stack([np.cos(ph), np.zeros_like(ph), -np.sin(ph)], axis=-1)
    north = np.cross(up, east)
    wn = east * nl[..., :1] + north * nl[..., 1:2] + up * nl[..., 2:3]
    # Back to view space (undo the spin and tilt).
    vx = wn[..., 0] * math.cos(spin) - wn[..., 2] * math.sin(spin)
    vz0 = wn[..., 0] * math.sin(spin) + wn[..., 2] * math.cos(spin)
    vy = wn[..., 1] * math.cos(tilt) + vz0 * math.sin(tilt)
    vz = -wn[..., 1] * math.sin(tilt) + vz0 * math.cos(tilt)
    L = np.array([-0.55, 0.6, 0.58])
    L /= np.linalg.norm(L)
    d = np.clip(vx * L[0] + vy * L[1] + vz * L[2], 0.0, 1.0)
    shade = 0.1 + 0.95 * d
    out = c * shade[..., None]
    if n in (5, 2):
        mh, mw = mask.shape
        g = mask[vi * mh // H, ui * mw // W][..., None] * (1.0 if n == 5 else 0.35)
        out = out * (1 - g) + g * np.array([1.0, 0.36, 0.12])
    bg = np.array([0.91, 0.91, 0.89])
    img = np.where(inside[..., None], out, bg)
    return (np.clip(img, 0.0, 1.0) ** (1.0) * 255.0).astype(np.uint8)


def clouds(src: str, out: str, count: int = 6) -> None:
    from PIL import ImageFilter
    cell, scell = 320, 128
    atlas = Image.new("RGBA", (cell * 3, cell * 2), (0, 0, 0, 0))
    shade = Image.new("L", (scell * 3, scell * 2), 0)
    for k in range(count):
        im = Image.open(os.path.join(src, "cloud_%d.png" % (k + 1))).convert("RGBA")
        box = im.getchannel("A").point(lambda a: 255 if a > 3 else 0).getbbox()
        im = im.crop(box)
        s = (cell - 12) / max(im.width, im.height)
        im = im.resize((max(1, round(im.width * s)), max(1, round(im.height * s))), Image.LANCZOS)
        cx, cy = (k % 3) * cell, (k // 3) * cell
        atlas.alpha_composite(im, (cx + (cell - im.width) // 2, cy + (cell - im.height) // 2))
        top = Image.open(os.path.join(src, "cloud_%d_top.png" % (k + 1))).convert("RGBA").getchannel("A")
        tb = top.point(lambda a: 255 if a > 3 else 0).getbbox()
        top = top.crop(tb)
        s2 = (scell - 28) / max(top.width, top.height)
        top = top.resize((max(1, round(top.width * s2)), max(1, round(top.height * s2))), Image.LANCZOS)
        tile = Image.new("L", (scell, scell), 0)
        tile.paste(top, ((scell - top.width) // 2, (scell - top.height) // 2))
        tile = tile.filter(ImageFilter.GaussianBlur(5))
        shade.paste(tile, ((k % 3) * scell, (k // 3) * scell))
    os.makedirs(out, exist_ok=True)
    atlas.save(os.path.join(out, "clouds.png"), optimize=True)
    shade.save(os.path.join(out, "clouds_shadow.png"), optimize=True)
    print("clouds", atlas.size, "shadow", shade.size, "->", out)


if __name__ == "__main__":
    args = [a for a in sys.argv[1:]]
    prev = "--preview" in args
    out = os.path.join(ROOT, "assets", "art", "worlds")
    if "--out" in args:
        out = args[args.index("--out") + 1]
        del args[args.index("--out"):args.index("--out") + 2]
    args = [a for a in args if a != "--preview"]
    if args[0] == "clouds":
        clouds(args[1], out)
        sys.exit(0)
    bake = args[0]
    which = [1, 2, 3, 4, 5, 6] if len(args) < 2 or args[1] == "all" else [int(x) for x in args[1].split(",")]
    for n in which:
        finish(n, bake, out, prev)
