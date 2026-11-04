"""Prints the battle hit renders as ink and packs them for the game.

    python tools/blender/finish_hit_fx.py <render_dir>

Reads tools/blender/hit_fx.py's frames (rendered at twice the shipped size) and writes
assets/art/ui/hit/ (src/ui/battle/press_layer.gd draws them through ink_print.gdshader):
  slash0-2.png            6 frames of 384x192 in 3 x 2 (2: the hooked flick)
  thrust.png              6 frames of 320x128 in 3 x 2
  splat.png               6 frames of 256x256 in 3 x 2
  droplet.png             4 frames of 128x64 in 4 x 1
  blot.png                1 frame of 384x128: the splat's last frame lying on the street
  press_grain.png         a seamless 256 px paper-fibre tile
Each frame is printed like the ultimate's crown (finish_ult_fx.py): the render's alpha blurred a hair
and cut at half against paper-fibre noise (a printed edge, bitten by the fibre), spread a pixel (dot
gain). Then it is stored as an edge field, not a hard mask: 8-bit grey where the printed edge sits at
128, rising inside the ink with distance from the edge, so the shader cuts it crisply at any scale,
and the ink lifts (the cut rises) from the thin bristles and the edges first.
"""
import os, sys
import numpy as np
from PIL import Image, ImageFilter

SRC = sys.argv[1]
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DST = os.path.join(ROOT, "assets", "art", "ui", "hit")
os.makedirs(DST, exist_ok=True)


def fibre_field(w: int, h: int, seed: int = 1508) -> np.ndarray:
    rng = np.random.default_rng(seed)
    a = Image.fromarray((rng.random((h, w)) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.8))
    st = Image.fromarray((rng.random((max(h // 4, 1), w)) * 255).astype(np.uint8)).resize((w, h), Image.BILINEAR)
    return (np.asarray(a, np.float32) * 0.6 + np.asarray(st, np.float32) * 0.4) / 255.0


def printed(alpha: Image.Image, fibre: np.ndarray, soft: float, gain: bool) -> Image.Image:
    """The render's coverage as a printed binary mask: blurred, cut against the fibre, dot gain
    (not on brush strokes: it would fill the dry bristles' gaps)."""
    av = np.asarray(alpha.filter(ImageFilter.GaussianBlur(soft)), np.float32) / 255.0
    cut = 0.5 + (fibre - 0.5) * 0.35
    m = Image.fromarray(((av > cut) * 255).astype(np.uint8))
    return m.filter(ImageFilter.MaxFilter(3)) if gain else m


def edge_field(mask: Image.Image) -> Image.Image:
    """Two blurs of the mask, averaged: 0.5 on a straight edge, near 1 deep inside, lower in thin
    strokes (they lift first)."""
    m = np.asarray(mask, np.float32) / 255.0
    near = np.asarray(Image.fromarray((m * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(3)), np.float32) / 255.0
    far = np.asarray(Image.fromarray((m * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(10)), np.float32) / 255.0
    f = near * 0.6 + far * 0.4
    # Keep the edge where the print put it: outside the mask the field stays below half.
    f = np.where(m > 0.5, np.maximum(f, 0.5 + 0.5 * far), np.minimum(f, 0.49))
    return Image.fromarray(np.clip(f * 255.0, 0, 255).astype(np.uint8), "L")


def frame(path: str, out_size, squash: float = 1.0, soft: float = 1.6, gain: bool = True) -> Image.Image:
    im = Image.open(path).convert("RGBA")
    a = im.split()[3]
    if squash != 1.0:
        # Lying on the street: the splash cropped to its ink, foreshortened, filling 90% of the frame.
        a = a.crop(a.getbbox())
        w, h = a.size
        sq = a.resize((w, max(int(h * squash), 1)), Image.LANCZOS)
        box = (int(out_size[0] * 2 * 0.9), int(out_size[1] * 2 * 0.9))
        k = min(box[0] / sq.size[0], box[1] / sq.size[1])
        sq = sq.resize((max(int(sq.size[0] * k), 1), max(int(sq.size[1] * k), 1)), Image.LANCZOS)
        a = Image.new("L", (out_size[0] * 2, out_size[1] * 2), 0)
        a.paste(sq, ((a.size[0] - sq.size[0]) // 2, (a.size[1] - sq.size[1]) // 2))
    fib = fibre_field(a.size[0], a.size[1])
    f = edge_field(printed(a, fib, soft, gain))
    return f.resize(out_size, Image.LANCZOS)


def sheet(name: str, frames, cols: int, rows: int, fw: int, fh: int) -> None:
    sh = Image.new("L", (fw * cols, fh * rows), 0)
    for i, fr in enumerate(frames):
        sh.paste(fr, ((i % cols) * fw, (i // cols) * fh))
    out = os.path.join(DST, name + ".png")
    sh.save(out, optimize=True)
    print(out, sh.size, os.path.getsize(out))


for v in (0, 1, 2):
    if not os.path.exists(os.path.join(SRC, "slash%d_0.png" % v)):
        continue
    sheet("slash%d" % v, [frame(os.path.join(SRC, "slash%d_%d.png" % (v, i)), (384, 192), soft=0.8, gain=False) for i in range(6)], 3, 2, 384, 192)
sheet("thrust", [frame(os.path.join(SRC, "thrust0_%d.png" % i), (320, 128), soft=0.8, gain=False) for i in range(6)], 3, 2, 320, 128)
sheet("splat", [frame(os.path.join(SRC, "splat0_%d.png" % i), (256, 256)) for i in range(6)], 3, 2, 256, 256)
sheet("droplet", [frame(os.path.join(SRC, "droplet0_%d.png" % i), (128, 64)) for i in range(4)], 4, 1, 128, 64)
sheet("blot", [frame(os.path.join(SRC, "splat0_5.png"), (384, 128), 0.3)], 1, 1, 384, 128)

# Paper fibre as a seamless tile: the field built three times over and the middle kept.
rng = np.random.default_rng(1508)
base = (rng.random((256, 256)) * 255).astype(np.uint8)
big = Image.fromarray(np.tile(base, (3, 3))).filter(ImageFilter.GaussianBlur(0.9))
streak = Image.fromarray(np.tile((rng.random((64, 256)) * 255).astype(np.uint8), (3, 3))).resize((768, 768), Image.BILINEAR)
g = np.asarray(big, np.float32) * 0.6 + np.asarray(streak, np.float32) * 0.4
tile = Image.fromarray(np.clip(g, 0, 255).astype(np.uint8)[256:512, 256:512], "L")
tile.save(os.path.join(DST, "press_grain.png"), optimize=True)
print(os.path.join(DST, "press_grain.png"), os.path.getsize(os.path.join(DST, "press_grain.png")))
