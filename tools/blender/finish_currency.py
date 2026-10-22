"""Finishes the currency renders (tools/blender/currency_objects.py) for the game (system Python,
numpy + Pillow): each cropped to its object, centred on a transparent square with a little margin,
8-bit RGBA: the currencies 256 px in assets/art/ui/currency/<id>.png (Kit.icon shows them), the shop
pieces 384 px in assets/art/ui/shop/<id>.png (the shop's offers and gem packs).

    python tools/blender/finish_currency.py <render_dir>
"""
import os
import sys

import numpy as np
from PIL import Image

src = sys.argv[1]
root = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "art", "ui")
SETS = {"currency": ["gems", "gold", "scrolls", "hero_exp", "dust"],
    "shop": ["pouch", "chest", "reliquary", "gift", "crate", "moon", "satchel"]}
for k in SETS["currency"] + SETS["shop"]:
    dst = os.path.join(root, "currency" if k in SETS["currency"] else "shop")
    os.makedirs(dst, exist_ok=True)
    p = os.path.join(src, k + ".png")
    if not os.path.exists(p):
        continue
    im = Image.open(p)
    a = np.asarray(im, dtype=np.float64)
    if a.max() > 255.5:
        a = a / 257.0
    ys, xs = np.nonzero(a[..., 3] > 3.0)
    crop = a[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
    h, w = crop.shape[:2]
    side = int(max(h, w) * 1.06)
    sq = np.zeros((side, side, 4))
    oy, ox = (side - h) // 2, (side - w) // 2
    sq[oy:oy + h, ox:ox + w] = crop
    px = 256 if k in SETS["currency"] else 384
    out = Image.fromarray(np.clip(sq + 0.5, 0, 255).astype(np.uint8), "RGBA").resize((px, px), Image.LANCZOS)
    out.save(os.path.join(dst, k + ".png"), optimize=True)
    print(k, os.path.getsize(os.path.join(dst, k + ".png")))
