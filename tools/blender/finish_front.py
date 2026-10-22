"""Finishes the War map's relief (tools/blender/front_terrain.py) for the game (system Python, Pillow).

    python tools/blender/finish_front.py <render_dir>

Writes assets/art/ui/front/relief.png (the clay as 8-bit grey + alpha: it is colourless, the game
paints it), data.png (8-bit RGB: sector, depth, height; never resampled but by nearest) and
points.json (copied).
"""
import json
import os
import shutil
import sys

from PIL import Image

src = sys.argv[1]
dst = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "art", "ui", "front")
os.makedirs(dst, exist_ok=True)

relief = Image.open(os.path.join(src, "relief.png"))
if relief.mode.startswith("I") or relief.mode == "RGBA;16":
    relief = relief.convert("RGBA")
relief = relief.convert("RGBA")
grey = relief.convert("L")
la = Image.merge("LA", (grey, relief.getchannel("A")))
la.save(os.path.join(dst, "relief.png"), optimize=True)

data = Image.open(os.path.join(src, "data.png")).convert("RGB")
data.save(os.path.join(dst, "data.png"), optimize=True)

with open(os.path.join(src, "points.json")) as f:
    pts = json.load(f)
with open(os.path.join(dst, "points.json"), "w") as f:
    json.dump(pts, f, separators=(",", ":"))
for n in ("relief.png", "data.png", "points.json"):
    print(n, os.path.getsize(os.path.join(dst, n)))
