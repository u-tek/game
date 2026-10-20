"""Cut part masks from the rig painting with SAM (helper for the layered rigs, e.g. tools/layered/seraphiel_rig.py).

Usage (ComfyUI venv python, it has torch):  sam_cut.py <painting.png> <out_dir> <spec.json>
spec: {"<name>": {"points": [[x, y]...], "neg": [[x, y]...], "box": [x0, y0, x1, y1], "pick": "best"}}
Writes <out_dir>/<name>.png (L, 255 inside) and a preview sheet <out_dir>/_sam_sheet.png."""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools"))
sys.path.insert(0, os.path.join(ROOT, ".pylib"))

import numpy as np  # noqa: E402
from PIL import Image, ImageDraw  # noqa: E402

from art_parts import Sam  # noqa: E402

paint, out, spec = sys.argv[1], sys.argv[2], json.load(open(sys.argv[3]))
os.makedirs(out, exist_ok=True)
img = Image.open(paint).convert("RGBA")
rgba = np.asarray(img).astype(np.float32)
alpha = rgba[..., 3] / 255.0
rgb = (rgba[..., :3] * alpha[..., None] + 128.0 * (1 - alpha[..., None])).astype(np.uint8)
sam = Sam()
sheet = Image.fromarray(rgb).convert("RGBA")
cols = [(255, 60, 60), (60, 200, 255), (90, 255, 90), (255, 200, 40), (220, 90, 255), (255, 140, 200)]
for i, (name, rule) in enumerate(spec.items()):
    m, score = sam.mask(rgb, alpha, rule)
    Image.fromarray((m * 255).astype(np.uint8), "L").save(os.path.join(out, name + ".png"))
    print("%-10s score %.3f px %d" % (name, score, int(m.sum())))
    ov = Image.new("RGBA", sheet.size, cols[i % len(cols)] + (0,))
    ov.putalpha(Image.fromarray((m * 110).astype(np.uint8)))
    sheet.alpha_composite(ov)
    d = ImageDraw.Draw(sheet)
    for p in rule.get("points", []):
        d.ellipse([p[0] - 4, p[1] - 4, p[0] + 4, p[1] + 4], fill=(0, 255, 0, 255))
    for p in rule.get("neg", []):
        d.ellipse([p[0] - 4, p[1] - 4, p[0] + 4, p[1] + 4], fill=(255, 0, 0, 255))
sheet.convert("RGB").save(os.path.join(out, "_sam_sheet.png"))
