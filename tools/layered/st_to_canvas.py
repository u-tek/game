"""Place See-through's layers (its 1280 px square frame) on the hero's 1024x2048 game canvas.

frame -> input crop: See-through padded the crop to a square ((side - w) // 2 on the short axis) and
resized it to 1280; crop -> canvas: finalize's transform (scale, offset) of the 2x image, which the
crop was cut from at crop_box. Writes <out>/<tag>.png (full canvas RGBA) for every non-empty layer and
reports how well the recombined layers match the final's alpha.
Usage: st_to_canvas.py <st_dir> <final.json> <crop_x0> <crop_y0> <crop_w> <crop_h> <out_dir>"""
import json
import os
import sys

import numpy as np
from PIL import Image

st_dir, fjson, cx0, cy0, cw, ch, out = sys.argv[1], sys.argv[2], *map(int, sys.argv[3:7]), sys.argv[7]
os.makedirs(out, exist_ok=True)
tr = json.load(open(fjson))["transform"]
s, (ox, oy) = tr["scale"], tr["offset"]
side = max(cw, ch)
px, py = (side - cw) // 2, (side - ch) // 2
f = side / 1280.0
# canvas = ((frame * f - pad) + crop0) * s + offset
a = f * s
bx, by = (cx0 - px) * s + ox, (cy0 - py) * s + oy
print("frame -> canvas: x * %.5f + %.2f, y * %.5f + %.2f" % (a, bx, a, by))
W, H = 1024, 2048
final = np.asarray(Image.open(os.path.join(os.path.dirname(fjson), os.path.basename(fjson)[:-5] + ".png")).convert("RGBA"))
union = np.zeros((H, W), np.float32)
skip = {"src_img.png", "src_head.png", "reconstruction.png"}
for fn in sorted(os.listdir(st_dir)):
    if not fn.endswith(".png") or fn.endswith("_depth.png") or fn in skip:
        continue
    im = Image.open(os.path.join(st_dir, fn)).convert("RGBA")
    if np.asarray(im)[..., 3].max() < 16:
        continue
    # affine: canvas pixel (X, Y) samples frame ((X - bx) / a, (Y - by) / a)
    c = im.transform((W, H), Image.AFFINE, (1 / a, 0, -bx / a, 0, 1 / a, -by / a), resample=Image.BICUBIC)
    c.save(os.path.join(out, fn.replace(" ", "_")))
    al = np.asarray(c)[..., 3].astype(np.float32) / 255
    union = np.maximum(union, al)
    print("  %-16s px %7d" % (fn[:-4], int((al > 0.5).sum())))
fa = final[..., 3] > 127
ua = union > 0.5
iou = (fa & ua).sum() / float((fa | ua).sum())
miss = fa & ~(union > 0.2)
print("IoU with the final's alpha: %.3f; final pixels no layer covers: %d" % (iou, int(miss.sum())))
Image.fromarray((miss * 255).astype(np.uint8)).save(os.path.join(out, "_missing.png"))
