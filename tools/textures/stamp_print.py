"""The EXECUTED rubber stamp, pressed: three frames of its impression as edge fields for the battle's press
layer (src/ui/battle/press_layer.gd, `stamp`).

    python tools/textures/stamp_print.py

A rubber stamp doesn't print a clean shape. The word and its double rule are set at twice the shipped size
(Archivo, condensed black), then inked the way a hand stamp inks: a pressure field (the stamp rocked a
little to one side, so one end bites harder), the rubber's own grain (low spots that take no ink), ink
squeezed out along the edges where the pressure is high (a dark rim and a slight spread), and the paper's
fibre biting the edge. Frame 0 is the first kiss (only the hard-pressed side prints), frame 1 the full
press, frame 2 the same with the ink spread a hair. Each frame is stored as an edge field like the other
hit prints (finish_hit_fx.edge_field: the printed edge at 128), so the shader cuts it crisply at any scale
and lifts it against the paper grain.
Writes assets/art/ui/hit/executed.png: 3 frames of 320x112 in a row.
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tools", "blender"))
DST = os.path.join(ROOT, "assets", "art", "ui", "hit")
FW, FH = 320, 112
W, H = FW * 2, FH * 2


def edge_field(mask):
    m = np.asarray(mask, np.float32) / 255.0
    near = np.asarray(mask.filter(ImageFilter.GaussianBlur(3)), np.float32) / 255.0
    far = np.asarray(mask.filter(ImageFilter.GaussianBlur(10)), np.float32) / 255.0
    f = near * 0.6 + far * 0.4
    f = np.where(m > 0.5, np.maximum(f, 0.5 + 0.5 * far), np.minimum(f, 0.49))
    return Image.fromarray(np.clip(f * 255.0, 0, 255).astype(np.uint8), "L")


def noise(w, h, scale, seed):
    rng = np.random.default_rng(seed)
    small = rng.random((max(h // scale, 2), max(w // scale, 2))).astype(np.float32)
    return np.asarray(Image.fromarray((small * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC), np.float32) / 255.0


def face():
    """The stamp's rubber face: a double rule round EXECUTED in condensed black capitals."""
    im = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(im)
    pad = 10
    d.rectangle([pad, pad, W - pad - 1, H - pad - 1], outline=255, width=9)
    d.rectangle([pad + 17, pad + 17, W - pad - 18, H - pad - 18], outline=255, width=3)
    font = ImageFont.truetype(os.path.join(ROOT, "assets", "fonts", "Archivo-Variable.ttf"), 126)
    try:
        font.set_variation_by_axes([900, 62])         # weight, width: compressed black
    except Exception:
        pass
    word = "EXECUTED"
    box = d.textbbox((0, 0), word, font=font)
    tw, th = box[2] - box[0], box[3] - box[1]
    k = min((W - 96) / tw, (H - 84) / th)
    if k < 1.0:
        font = font.font_variant(size=int(126 * k))
        try:
            font.set_variation_by_axes([900, 62])
        except Exception:
            pass
        box = d.textbbox((0, 0), word, font=font)
        tw, th = box[2] - box[0], box[3] - box[1]
    d.text(((W - tw) // 2 - box[0], (H - th) // 2 - box[1]), word, fill=255, font=font)
    return im


def press(rubber, amount, spread, seed):
    """One impression: the rubber's coverage where pressure and grain let ink through."""
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    rock = 0.62 + 0.38 * (1.0 - xx / W) + 0.06 * (yy / H)               # pressed harder at the left end
    pressure = rock * amount + (noise(W, H, 40, seed) - 0.5) * 0.35
    grain = noise(W, H, 3, seed + 1) * 0.6 + noise(W, H, 9, seed + 2) * 0.4
    r = np.asarray(rubber.filter(ImageFilter.GaussianBlur(1.1)), np.float32) / 255.0
    inked = r * np.clip((pressure - 0.18) * 2.2, 0, 1)
    # the rubber's low spots (grain) take no ink where the pressure is light
    hole = grain > 0.35 + pressure * 0.55
    inked = np.where(hole & (r < 0.98), inked * 0.25, inked)
    m = Image.fromarray(((inked > 0.5 + (noise(W, H, 2, seed + 3) - 0.5) * 0.3) * 255).astype(np.uint8))
    if spread:
        m = m.filter(ImageFilter.MaxFilter(spread))
    return m


def main():
    rubber = face()
    frames = [press(rubber, 0.62, 0, 41), press(rubber, 1.0, 0, 41), press(rubber, 1.04, 3, 41)]
    sheet = Image.new("L", (FW * 3, FH), 0)
    for i, m in enumerate(frames):
        sheet.paste(edge_field(m).resize((FW, FH), Image.LANCZOS), (i * FW, 0))
    out = os.path.join(DST, "executed.png")
    sheet.save(out, optimize=True)
    print(out, sheet.size, os.path.getsize(out))


if __name__ == "__main__":
    main()
