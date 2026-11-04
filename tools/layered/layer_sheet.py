"""A review sheet of a layered rig's pieces, each on the canvas over a flat grey (helper for tools/layered/).

Usage: layer_sheet.py <rig dir> <out.png> [--scale 0.3]
Reads <rig dir>/<art>.warp_src.json for the layers and their image rects."""
import json
import os
import sys

from PIL import Image, ImageDraw

rig, out = sys.argv[1], sys.argv[2]
sc = float(sys.argv[sys.argv.index("--scale") + 1]) if "--scale" in sys.argv else 0.3
art = os.path.basename(os.path.normpath(rig))
src = json.load(open(os.path.join(rig, art + ".warp_src.json")))
layers = src["layers"]
tw, th = int(1024 * sc), int(2048 * sc)
cols = 6
rows = (len(layers) + cols - 1) // cols
sheet = Image.new("RGB", (tw * cols, (th + 18) * rows), (40, 40, 46))
d = ImageDraw.Draw(sheet)
for i, L in enumerate(layers):
    can = Image.new("RGBA", (1024, 2048), (128, 128, 132, 255))
    im = Image.open(os.path.join(rig, L["image"])).convert("RGBA")
    x, y = L["image_rect"][:2]
    can.alpha_composite(im, (x, y))
    t = can.resize((tw, th), Image.LANCZOS).convert("RGB")
    cx, cy = (i % cols) * tw, (i // cols) * (th + 18)
    sheet.paste(t, (cx, cy + 18))
    d.text((cx + 4, cy + 3), "%s z%d" % (L["name"], L["z"]), fill=(255, 255, 255))
sheet.save(out)
print(out, sheet.size)
