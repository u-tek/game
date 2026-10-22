"""Finishes the district maquette (tools/blender/district_models.py) for the game (system Python,
numpy + Pillow).

    python tools/blender/finish_district.py <render_dir>

Writes assets/art/ui/district/ground.png (the whole frame) and <id>.png per building, cropped to
what it draws, with its cast shadow at about half strength (the shadow catcher's shadows are pitch black, and
its faint ambient veil over the whole ground is dropped),
8-bit RGBA, its normals over the same rect at half size (<id>_n.png), and layout.json: the frame size and per building its crop rect, roof and foot points
(all 0..1 of the frame, y down), its depth (back to front order) and its data spot; and the grid's
image axes (o, x, y: a ground point at lot coordinates (gx, gy) is o + gx * x + gy * y).
"""
import json
import os
import sys

import numpy as np
from PIL import Image

src = sys.argv[1]
dst = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "art", "ui", "district")
os.makedirs(dst, exist_ok=True)
lay = json.load(open(os.path.join(src, "layout.json")))
fw, fh = lay["size"]


def load8(path):
    im = Image.open(path)
    a = np.asarray(im, dtype=np.float64)
    if a.max() > 255.5:
        a = a / 257.0
    return a


g = load8(os.path.join(src, "ground.png"))
Image.fromarray(np.clip(g + 0.5, 0, 255).astype(np.uint8), "RGBA").save(os.path.join(dst, "ground.png"), optimize=True)
out = {"size": [fw, fh], "buildings": {}}
for bid, info in lay["buildings"].items():
    a = load8(os.path.join(src, bid + ".png"))
    shadow = a[..., :3].max(axis=2) < 16.0
    # The catcher also leaves a faint veil of ambient occlusion over the whole ground: drop the
    # weak part (stacked eight times it greys the ground), keep the cast shadow at half strength.
    a[..., 3] = np.where(shadow, np.clip(a[..., 3] - 60.0, 0.0, 255.0) * (0.55 * 255.0 / 195.0), a[..., 3])
    ys, xs = np.nonzero(a[..., 3] > 2.0)
    x0, x1, y0, y1 = max(xs.min() - 2, 0), min(xs.max() + 3, fw), max(ys.min() - 2, 0), min(ys.max() + 3, fh)
    crop = np.clip(a[y0:y1, x0:x1] + 0.5, 0, 255).astype(np.uint8)
    Image.fromarray(crop, "RGBA").save(os.path.join(dst, bid + ".png"), optimize=True)
    # Its normals over the same rect (flat toward the viewer where it has none), half size.
    npath = os.path.join(src, bid + "_n.png")
    if os.path.exists(npath):
        nimg = load8(npath)
        rgb = nimg[y0:y1, x0:x1, :3]
        al = nimg[y0:y1, x0:x1, 3:4] / 255.0
        rgb = rgb * al + np.array([127.5, 127.5, 255.0]) * (1.0 - al)
        nm = Image.fromarray(np.clip(rgb + 0.5, 0, 255).astype(np.uint8), "RGB")
        nm = nm.resize((max(1, nm.width // 2), max(1, nm.height // 2)), Image.LANCZOS)
        nm.save(os.path.join(dst, bid + "_n.png"), optimize=True)
    out["buildings"][bid] = {"rect": [x0 / fw, y0 / fh, (x1 - x0) / fw, (y1 - y0) / fh], "roof": info["roof"],
        "foot": info["foot"], "depth": info["depth"]}
# The ground grid's axes in the image (an orthographic camera: a lot's offset is a fixed image
# offset), fitted from each building's foot point and its lot's centre: image = o + gx * x + gy * y.
data = json.load(open(os.path.join(os.path.dirname(__file__), "..", "..", "data", "district.json"), encoding="utf-8"))
rows, rhs = [], []
for b in data["buildings"]:
    info = lay["buildings"].get(b["id"])
    if not info:
        continue
    cx, cy = b["spot"][0] + b["w"] / 2.0, b["spot"][1] + b["d"] / 2.0
    rows.append([1.0, cx, cy])
    rhs.append(info["foot"])
    out["buildings"][b["id"]]["spot"] = b["spot"]
sol, *_ = np.linalg.lstsq(np.array(rows), np.array(rhs), rcond=None)
out["grid"] = {"o": [round(float(v), 6) for v in sol[0]], "x": [round(float(v), 6) for v in sol[1]],
    "y": [round(float(v), 6) for v in sol[2]]}
with open(os.path.join(dst, "layout.json"), "w") as f:
    json.dump(out, f, separators=(",", ":"))
for n in sorted(os.listdir(dst)):
    print(n, os.path.getsize(os.path.join(dst, n)))
