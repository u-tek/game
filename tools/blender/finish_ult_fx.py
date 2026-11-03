"""Prints the ultimate effect renders as ink and packs them for the game.

    python tools/blender/finish_ult_fx.py <render_dir>

crown: the 8 frames of tools/blender/ult_fx.py crown become assets/art/ui/ult/ink_crown.png, a 4 x 2
sheet of 512 px frames, white on alpha (modulate colours it: paper on the impact frame, signal on
the field). Each frame is printed: the render's alpha blurred a hair and cut at half (a printed edge,
not a soft one), spread by a pixel (dot gain), and its edge bitten by paper-fibre noise.
"""
import os, sys
import numpy as np
from PIL import Image, ImageFilter

SRC = sys.argv[1]
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DST = os.path.join(ROOT, "assets", "art", "ui", "ult")
os.makedirs(DST, exist_ok=True)

FRAME = 512
rng = np.random.default_rng(1508)
# One fibre field for every frame, so the edge's grain holds still while the splash grows.
fibre = rng.random((FRAME, FRAME)).astype(np.float32)
fibre_img = Image.fromarray((fibre * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.8))
streak = Image.fromarray((rng.random((FRAME // 4, FRAME)) * 255).astype(np.uint8)).resize((FRAME, FRAME), Image.BILINEAR)
fibre = (np.asarray(fibre_img, np.float32) * 0.6 + np.asarray(streak, np.float32) * 0.4) / 255.0

sheet = Image.new("RGBA", (FRAME * 4, FRAME * 2), (255, 255, 255, 0))
for i in range(8):
    im = Image.open(os.path.join(SRC, "crown_%d.png" % i)).convert("RGBA")
    a = im.split()[3].filter(ImageFilter.GaussianBlur(1.2))
    av = np.asarray(a, np.float32) / 255.0
    # The fibre bites the edge only: inside the ink it does nothing, at the rim it moves the cut.
    cut = 0.5 + (fibre - 0.5) * 0.35
    ink = (av > cut).astype(np.uint8) * 255
    m = Image.fromarray(ink).filter(ImageFilter.MaxFilter(3))
    # A half-pixel soft edge after the cut, so the print is crisp but not aliased when scaled.
    m = m.filter(ImageFilter.GaussianBlur(0.6))
    fr = Image.merge("RGBA", (Image.new("L", m.size, 255),) * 3 + (m,))
    sheet.paste(fr, ((i % 4) * FRAME, (i // 4) * FRAME))
out = os.path.join(DST, "ink_crown.png")
sheet.save(out, optimize=True)
print(out, os.path.getsize(out))
