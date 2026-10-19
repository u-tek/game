"""Finishes the Cycles renders of tools/blender/physical_objects.py into the game's physical UI objects
(style v4, docs/dev/ui-style-v4.md section 2), and makes the paper tiles.

    python tools/blender/finish_physical.py <render_dir> [names...]   # objects -> assets/art/ui/physical/
    python tools/blender/finish_physical.py paper                     # the two paper tiles only

For every <name>.png (16-bit RGBA with its own contact shadow) and its <name>.json (where the world
origin and one world unit land in the render): crops to what is visible, scales to the size the UI
shows it at (about 1.6x, for the phone's pixel density), keeps 8-bit RGBA. Lit LEDs get their glow
baked in (the game never relies on bloom: HDR 2D is off on iOS). The acrylic pieces were rendered over
black and over white: what the slab lets through (T = white - black) and the light it adds (L = black)
become <name>_t.png (rgb T, linear; alpha where the slab is) and <name>_l.png (L, sRGB), which the
acrylic shader combines with what is behind it on screen. The paper tiles (512 px, seamless) are made
here from FFT noise and drawn fibres: paper_felt (grey felt / concrete) and paper_parch (warm
parchment), each a grey detail map (128 = the paper's own colour) and a normal map (+x right, +y up).

Writes assets/art/ui/physical/physical.json: per piece its size, px_per_unit, the world origin's pixel
(the poster corner for the corner pieces) and, for the round hardware, its centre and diameter.
Needs numpy, Pillow and opencv-python (cv2 reads the 16-bit renders).
"""
import json
import math
import os
import sys

import numpy as np
from PIL import Image

try:
    import cv2
except ImportError:  # 8-bit fallback (Pillow drops 16-bit PNGs to 8 bits)
    cv2 = None

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "assets", "art", "ui", "physical")

# Longest side of the finished piece (px), by name prefix (first match wins).
SIZES = [
    ("thorn_chrome_edge", 1024), ("thorn_black_edge", 1024), ("jelly_edge", 1024),
    ("thorn_chrome_clump", 360), ("thorn_black_clump", 360), ("jelly_clump", 380),
    ("thorn_", 720), ("jelly_", 720),
    ("dome_", 240), ("bezel_", 224), ("led_", 56),
    ("acrylic_tab", 300), ("acrylic_card", 640),
]
LED_RGB = {"green": (40, 255, 90), "orange": (255, 100, 20), "red": (255, 40, 24), "cyan": (40, 210, 255)}


def load16(path: str) -> np.ndarray:
    """RGBA as float 0..1 (16-bit precision when cv2 is there)."""
    if cv2 is not None:
        im = cv2.imread(path, cv2.IMREAD_UNCHANGED)
        if im is None:
            raise FileNotFoundError(path)
        scale = 65535.0 if im.dtype == np.uint16 else 255.0
        im = im.astype(np.float32) / scale
        if im.shape[2] == 3:
            im = np.dstack([im, np.ones(im.shape[:2], np.float32)])
        return im[:, :, [2, 1, 0, 3]]
    return np.asarray(Image.open(path).convert("RGBA"), np.float32) / 255.0


def to8(a: np.ndarray) -> np.ndarray:
    return (np.clip(a, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8)


def resize_rgba(a: np.ndarray, w: int, h: int) -> np.ndarray:
    """Premultiplied resize (no dark fringes at soft edges)."""
    pm = a.copy()
    pm[:, :, :3] *= pm[:, :, 3:4]
    if cv2 is not None:
        out = cv2.resize(pm, (w, h), interpolation=cv2.INTER_AREA)
    else:
        out = np.stack([np.asarray(Image.fromarray(pm[:, :, c]).resize((w, h), Image.LANCZOS)) for c in range(4)], axis=2)
    al = np.clip(out[:, :, 3:4], 1e-6, 1.0)
    out[:, :, :3] = np.where(out[:, :, 3:4] > 1e-5, out[:, :, :3] / al, 0.0)
    return out


def bbox(alpha: np.ndarray, thr: float):
    ys, xs = np.where(alpha > thr)
    if len(xs) == 0:
        return 0, 0, alpha.shape[1], alpha.shape[0]
    return int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1


def target(name: str) -> int:
    for pre, s in SIZES:
        if name.startswith(pre):
            return s
    return 512


def blur(a: np.ndarray, sigma: float) -> np.ndarray:
    if cv2 is not None:
        return cv2.GaussianBlur(a, (0, 0), sigma)
    return np.asarray(Image.fromarray(a).filter(__import__("PIL.ImageFilter").ImageFilter.GaussianBlur(sigma)))


def finish(src_dir: str, name: str, manifest: dict) -> None:
    meta = json.load(open(os.path.join(src_dir, name + ".json")))
    im = load16(os.path.join(src_dir, name + ".png"))
    pad_px = 6
    if name.startswith("led_") and name.endswith("_on"):
        # Bake the glow: a soft halo in the LED's colour under it (twice its size).
        h, w = im.shape[:2]
        col = np.array(LED_RGB[name.split("_")[1]], np.float32) / 255.0
        cy, cx = h * 0.5, w * 0.5
        yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
        r = np.hypot(xx - cx, yy - cy) / (w * 0.5)
        halo = np.exp(-(r / 0.42) ** 2) * 0.55 + np.exp(-(r / 0.75) ** 2) * 0.22
        glow = np.dstack([np.broadcast_to(col, (h, w, 3)), halo])
        # The LED over its halo ("over" compositing).
        a = im[:, :, 3:4]
        out_a = a + glow[:, :, 3:4] * (1 - a)
        out_rgb = (im[:, :, :3] * a + glow[:, :, :3] * glow[:, :, 3:4] * (1 - a)) / np.clip(out_a, 1e-6, 1)
        im = np.dstack([out_rgb, out_a])
        pad_px = 2
    x0, y0, x1, y1 = bbox(im[:, :, 3], 0.012)
    x0, y0 = max(0, x0 - pad_px), max(0, y0 - pad_px)
    x1, y1 = min(im.shape[1], x1 + pad_px), min(im.shape[0], y1 + pad_px)
    crop = im[y0:y1, x0:x1]
    t = target(name)
    k = min(1.0, t / max(crop.shape[0], crop.shape[1]))
    w, h = max(1, round(crop.shape[1] * k)), max(1, round(crop.shape[0] * k))
    out = resize_rgba(crop, w, h) if k < 1.0 else crop
    os.makedirs(OUT, exist_ok=True)
    Image.fromarray(to8(out), "RGBA").save(os.path.join(OUT, name + ".png"), optimize=True)
    ox, oy = meta["origin"]
    entry = {"size": [w, h], "px_per_unit": round(meta["px_per_unit"] * k, 3),
        "origin": [round((ox - x0) * k, 1), round((oy - y0) * k, 1)]}
    # Round hardware: centre (the world origin) and diameter, so the UI can seat it exactly.
    dia = {"dome_": 1.32, "bezel_": 1.4, "led_": 0.3}
    for pre, d in dia.items():
        if name.startswith(pre):
            entry["center"] = entry["origin"]
            entry["diameter"] = round(d * meta["px_per_unit"] * k, 1)
    manifest[name] = entry
    print(name, entry)


def finish_acrylic(src_dir: str, name: str, manifest: dict) -> None:
    meta = json.load(open(os.path.join(src_dir, name + "_black.json")))
    b = load16(os.path.join(src_dir, name + "_black.png"))[:, :, :3]
    wv = load16(os.path.join(src_dir, name + "_white.png"))[:, :, :3]
    T = np.clip(wv - b, 0.0, 1.0)
    L = np.clip(b, 0.0, 1.0)
    # Where the slab is: anything it changed (with a little feather).
    cover = np.clip(np.maximum((1.0 - T.min(axis=2)) * 40.0, L.max(axis=2) * 60.0), 0.0, 1.0).astype(np.float32)
    cover = np.clip(blur(cover, 0.8) * 1.3, 0.0, 1.0)
    x0, y0, x1, y1 = bbox(cover, 0.02)
    x0, y0, x1, y1 = max(0, x0 - 3), max(0, y0 - 3), min(cover.shape[1], x1 + 3), min(cover.shape[0], y1 + 3)
    T, L, cover = T[y0:y1, x0:x1], L[y0:y1, x0:x1], cover[y0:y1, x0:x1]
    t = target(name)
    k = min(1.0, t / max(T.shape[0], T.shape[1]))
    w, h = max(1, round(T.shape[1] * k)), max(1, round(T.shape[0] * k))
    if k < 1.0 and cv2 is not None:
        T = cv2.resize(T, (w, h), interpolation=cv2.INTER_AREA)
        L = cv2.resize(L, (w, h), interpolation=cv2.INTER_AREA)
        cover = cv2.resize(cover, (w, h), interpolation=cv2.INTER_AREA)
    # Outside the slab nothing changes: T = 1, L = 0.
    T = T * cover[:, :, None] + (1.0 - cover[:, :, None])
    L = L * cover[:, :, None]
    Image.fromarray(to8(np.dstack([T, cover])), "RGBA").save(os.path.join(OUT, name + "_t.png"), optimize=True)
    l_srgb = np.where(L <= 0.0031308, L * 12.92, 1.055 * np.power(np.clip(L, 0, 1), 1 / 2.4) - 0.055)
    Image.fromarray(to8(l_srgb), "RGB").save(os.path.join(OUT, name + "_l.png"), optimize=True)
    ox, oy = meta["origin"]
    manifest[name] = {"size": [w, h], "px_per_unit": round(meta["px_per_unit"] * k, 3),
        "origin": [round((ox - x0) * k, 1), round((oy - y0) * k, 1)]}
    print(name, manifest[name])


# ------------------------------------------------------------------ paper tiles

N = 512


def fft_noise(rng, beta: float, lo: float = 0.0, hi: float = 1e9) -> np.ndarray:
    """Seamless noise with a 1/f^beta spectrum, band-limited to [lo, hi] cycles per tile, unit std."""
    white = rng.standard_normal((N, N))
    f = np.fft.fft2(white)
    fy = np.fft.fftfreq(N)[:, None] * N
    fx = np.fft.fftfreq(N)[None, :] * N
    r = np.hypot(fx, fy)
    r[0, 0] = 1.0
    amp = r ** (-beta / 2.0)
    amp *= (r >= lo) * (r <= hi)
    amp[0, 0] = 0.0
    out = np.real(np.fft.ifft2(f * amp))
    return (out - out.mean()) / (out.std() + 1e-9)


def fibres(rng, count: int, length=(6, 30), width: float = 0.7, curl: float = 0.25) -> np.ndarray:
    """Short curved fibres drawn with wrap-around (seamless), as a height field 0..1."""
    canvas = np.zeros((N * 3, N * 3), np.float32)
    for _ in range(count):
        x, y = rng.uniform(0, N), rng.uniform(0, N)
        a = rng.uniform(0, math.tau)
        L = rng.uniform(*length)
        pts = []
        for s in range(int(L) + 1):
            pts.append((x + N, y + N))
            a += rng.normal(0, curl)
            x += math.cos(a)
            y += math.sin(a)
        p = np.array(pts, np.int32).reshape(-1, 1, 2)
        if cv2 is not None:
            cv2.polylines(canvas, [p], False, float(rng.uniform(0.5, 1.0)), 1, cv2.LINE_AA)
    tile = np.zeros((N, N), np.float32)
    for i in range(3):
        for j in range(3):
            tile += canvas[i * N:(i + 1) * N, j * N:(j + 1) * N]
    if width > 0.6 and cv2 is not None:
        # Blur with wrap-around: pad from the other side, blur, cut the middle back out.
        pad = 8
        big = np.pad(tile, pad, mode="wrap")
        tile = cv2.GaussianBlur(big, (0, 0), width * 0.6)[pad:-pad, pad:-pad]
    return np.clip(tile, 0.0, 1.0)


def normal_map(height: np.ndarray, strength: float) -> np.ndarray:
    """Seamless normals from a height field (+x right, +y up: OpenGL convention)."""
    dx = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)) * 0.5
    dy = (np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)) * 0.5
    nx = -dx * strength
    ny = dy * strength  # image rows run down; +y up
    nz = np.ones_like(height)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    return np.dstack([nx / ln, ny / ln, nz / ln]) * 0.5 + 0.5


def paper(manifest: dict) -> None:
    os.makedirs(OUT, exist_ok=True)
    rng = np.random.default_rng(2026)
    # Grey felt / concrete (reference 23): a fine felted grain, soft mottling, fibres, tiny pits.
    grain = fft_noise(rng, 0.4, 60, 400)
    fine = fft_noise(rng, 1.0, 20, 256)
    mottle = fft_noise(rng, 2.6, 1, 24)
    fib = fibres(np.random.default_rng(7), 2600, (5, 18), 0.8, 0.35)
    pits = np.clip(fft_noise(rng, 0.2, 80, 400) - 2.2, 0, None)
    h = 0.5 * grain + 0.6 * fine + 0.08 * mottle + 1.6 * fib - 1.2 * pits
    h = (h - h.mean()) / h.std()
    albedo = 0.5 + 0.028 * mottle + 0.03 * grain + 0.035 * fib - 0.05 * pits
    Image.fromarray(to8(albedo), "L").save(os.path.join(OUT, "paper_felt.png"), optimize=True)
    Image.fromarray(to8(normal_map(h, 0.55)), "RGB").save(os.path.join(OUT, "paper_felt_n.png"), optimize=True)
    # Warm parchment (reference 24): soft cockling, a fine tooth, long fibres and faint stains.
    rng = np.random.default_rng(1977)
    cockle = fft_noise(rng, 3.0, 1, 10)
    tooth = fft_noise(rng, 0.8, 40, 300)
    lumps = fft_noise(rng, 1.8, 8, 80)
    fib = fibres(np.random.default_rng(11), 700, (14, 46), 0.9, 0.12)
    stains = fft_noise(rng, 2.8, 2, 30)
    st = np.clip((stains - 0.6) * 0.8, 0, 1)
    h = 0.5 * cockle + 0.6 * tooth + 0.35 * lumps + 0.9 * fib
    h = (h - h.mean()) / h.std()
    albedo = 0.5 + 0.03 * lumps + 0.02 * tooth - 0.06 * st + 0.025 * fib - 0.02 * cockle
    Image.fromarray(to8(albedo), "L").save(os.path.join(OUT, "paper_parch.png"), optimize=True)
    Image.fromarray(to8(normal_map(h, 0.5)), "RGB").save(os.path.join(OUT, "paper_parch_n.png"), optimize=True)
    manifest["paper_felt"] = {"size": [N, N], "tile": True}
    manifest["paper_parch"] = {"size": [N, N], "tile": True}
    print("paper tiles written")


def main() -> None:
    manifest_path = os.path.join(OUT, "physical.json")
    manifest = json.load(open(manifest_path)) if os.path.exists(manifest_path) else {}
    if sys.argv[1] == "paper":
        paper(manifest)
    else:
        src = sys.argv[1]
        names = sys.argv[2:]
        if not names:
            names = sorted({f[:-5] for f in os.listdir(src) if f.endswith(".json")})
        done = set()
        for n in names:
            if n.endswith("_black") or n.endswith("_white"):
                n = n.rsplit("_", 1)[0]
            if n in done:
                continue
            done.add(n)
            if n.startswith("acrylic_"):
                finish_acrylic(src, n, manifest)
            else:
                finish(src, n, manifest)
    os.makedirs(OUT, exist_ok=True)
    with open(manifest_path, "w") as f:
        json.dump(dict(sorted(manifest.items())), f, indent=1)
    print("manifest", manifest_path, len(manifest), "pieces")


if __name__ == "__main__":
    main()
