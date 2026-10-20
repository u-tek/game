"""Paint a rig layer's hidden part with the image model (helper for the layered rigs, e.g. tools/layered/seraphiel_rig.py).

The torso behind a separate breast (or any part cut out of a layer) is first filled roughly, then
repainted here: the layer over the art's flat backdrop, the hole as the mask, a square crop around it
upscaled to 1024 px, a masked repaint (VAEEncode + SetLatentNoiseMask, as variants.py does), pasted
back inside the hole only. Uses the pin's model (MOSS) unless --fallback.

Usage: fill_hidden.py <layer.png> <hole_mask.png> <crop x0,y0,side> <out_dir> --seeds 1,2,3 --denoise 0.6
       [--prompt-file f.txt] [--fallback]
<layer.png> and <hole_mask.png> are canvas-sized (1024x2048). Writes <out_dir>/fill_s<seed>.png (the
layer with its hole repainted) and <out_dir>/fill_sheet.png."""
import argparse
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "comfy"))

import numpy as np  # noqa: E402
from PIL import Image  # noqa: E402

import pipeline as P  # noqa: E402
import prompts  # noqa: E402

ap = argparse.ArgumentParser()
ap.add_argument("layer")
ap.add_argument("mask")
ap.add_argument("crop")
ap.add_argument("out")
ap.add_argument("--seeds", default="1,2,3")
ap.add_argument("--denoise", type=float, default=0.6)
ap.add_argument("--prompt-file")
ap.add_argument("--hero", default="seraphiel")
P.add_common_args(ap)
a = ap.parse_args()
os.makedirs(a.out, exist_ok=True)

bible = prompts.load_bible()
h = prompts.hero_view(bible, a.hero)
client = P.make_client(a)
s, disc, oi = P.resolve_settings(bible, a, client, a.hero)
fam = bible["families"][s["family"]]
desc = open(a.prompt_file).read().strip() if a.prompt_file else (
    "Close-up of the torso of an adult woman in a glossy white latex leotard: two narrow white latex "
    "panels run straight up her chest from her waist, smooth pale skin between them along her sternum, "
    "a soft shadow under her bust.")
if fam.get("prompt_mode") == "sentences":
    positive = "%s, close-up. %s %s" % (prompts._sentence_subject(bible, h, False), fam.get("style_natural", ""), desc)
    negative = prompts._sentence_negative(bible, fam, h)
else:
    positive = "%s, %s" % (prompts._sentence_subject(bible, h, False), desc)
    negative = prompts._sentence_negative(bible, fam, h)
print("model:", s.get("checkpoint"), "| family:", s["family"])

layer = Image.open(a.layer).convert("RGBA")
hole = Image.open(a.mask).convert("L")
x0, y0, side = map(int, a.crop.split(","))
crop = (x0, y0, x0 + side, y0 + side)
bg = bible["backgrounds"]["grey"]["rgb"] if "grey" in bible.get("backgrounds", {}) else [128, 128, 128]
rgb = P.flat_rgb(layer, bg)
tries = []
for seed in [int(v) for v in a.seeds.split(",")]:
    out_rgb, info = P.crop_inpaint(client, s, rgb, crop, hole, positive, negative, seed, a.denoise,
                                   "rigfill_s%d" % seed, os.path.join(a.out, "work"), grow=4, feather=2)
    res = np.asarray(out_rgb).astype(np.float32)
    lay = np.asarray(layer).astype(np.float32).copy()
    m = np.asarray(hole) > 127
    lay[m, :3] = res[m]
    lay[m, 3] = 255
    p = os.path.join(a.out, "fill_s%d.png" % seed)
    Image.fromarray(lay.astype(np.uint8), "RGBA").save(p)
    tries.append((seed, Image.fromarray(lay.astype(np.uint8), "RGBA").crop(crop)))
    print("seed", seed, "->", p)
sheet = Image.new("RGB", (side * (len(tries) + 1), side + 20), (40, 40, 48))
sheet.paste(P.flat_rgb(layer.crop(crop), bg), (0, 20))
for i, (seed, im) in enumerate(tries):
    sheet.paste(P.flat_rgb(im, bg), (side * (i + 1), 20))
sheet.save(os.path.join(a.out, "fill_sheet.png"))
