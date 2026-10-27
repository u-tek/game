"""Finishes the Cycles renders of tools/blender/holiday_objects.py into the Lobby's holiday decorations
(assets/art/ui/holiday/).

    python tools/blender/finish_holiday.py <render_dir> [names...]

For every <name>.png (16-bit RGBA, no floor): crops to what is visible, scales so the longer side is
PX (about 1.6x the size the Lobby shows it at, for the phone's pixel density) and writes
<name>.png, plus <name>_shadow.png: the piece's alpha blurred, as a black shadow with PAD px of room on
each side (the game throws it onto the paper and moves it as the piece swings). holiday.json lists each
piece's size and where it hangs from: the topmost point near its centre (a bat's head, a star's top
point), or for a pennant ("edge") its two top corners.
Needs numpy, Pillow and opencv-python (cv2 reads the 16-bit renders).
"""
import json
import os
import sys

import cv2
import numpy as np
from PIL import Image, ImageFilter

PX = {"bat": 150, "snow": 120, "star": 112, "heart": 104, "flag": 96}
PAD = 14
BLUR = 4.0
DST = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "assets", "art", "ui", "holiday")


def finish(src: str, name: str) -> dict:
    im = cv2.imread(os.path.join(src, name + ".png"), cv2.IMREAD_UNCHANGED)
    if im is None:
        raise SystemExit("missing render " + name)
    rgba = im[..., [2, 1, 0, 3]].astype(np.float64) / 65535.0 * 255.0
    a = rgba[..., 3]
    ys, xs = np.nonzero(a > 2.0)
    y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
    crop = rgba[y0:y1, x0:x1]
    h, w = crop.shape[:2]
    px = PX[name.split("_")[0]]
    k = px / max(h, w)
    nw, nh = max(1, round(w * k)), max(1, round(h * k))
    # Premultiply before scaling so the edge pixels don't pick up the transparent black.
    pre = crop.copy()
    pre[..., :3] *= pre[..., 3:4] / 255.0
    img = Image.fromarray(np.clip(pre + 0.5, 0, 255).astype(np.uint8), "RGBA").resize((nw, nh), Image.LANCZOS)
    arr = np.asarray(img).astype(np.float64)
    al = arr[..., 3:4]
    arr[..., :3] = np.where(al > 0, arr[..., :3] * 255.0 / np.maximum(al, 1), 0)
    out = Image.fromarray(np.clip(arr + 0.5, 0, 255).astype(np.uint8), "RGBA")
    out.save(os.path.join(DST, name + ".png"), optimize=True)
    # The shadow: the alpha, blurred, on a canvas PAD px larger on every side.
    sa = Image.new("L", (nw + PAD * 2, nh + PAD * 2), 0)
    sa.paste(out.getchannel("A"), (PAD, PAD))
    sa = sa.filter(ImageFilter.GaussianBlur(BLUR))
    sh = Image.merge("RGBA", (Image.new("L", sa.size, 18), Image.new("L", sa.size, 16), Image.new("L", sa.size, 14), sa))
    sh.save(os.path.join(DST, name + "_shadow.png"), optimize=True)
    # Where it hangs from.
    oa = np.asarray(out.getchannel("A"))
    if name.startswith("flag"):
        rows = np.nonzero(oa.max(axis=1) > 128)[0]
        top = int(rows.min())
        cols = np.nonzero(oa[top + 2] > 128)[0]
        hang = {"edge": [[int(cols.min()), top + 2], [int(cols.max()), top + 2]]}
    else:
        # Straight above the model's origin (the render's centre): a bat's crown between its ears,
        # a star's top point, a heart's cleft.
        ox = int(round((im.shape[1] * 0.5 - x0) * k))
        band = oa[:, max(0, ox - 2):ox + 3]
        rows = np.nonzero(band.max(axis=1) > 128)[0]
        hang = {"point": [ox, int(rows.min()) + 1]}
    print(name, nw, nh, hang)
    return {"size": [nw, nh], **hang}


def main() -> None:
    src = sys.argv[1]
    names = sys.argv[2:] or sorted(f[:-4] for f in os.listdir(src) if f.endswith(".png") and "_" in f
        and f.split("_")[0] in PX and not f.endswith("_shadow.png"))
    os.makedirs(DST, exist_ok=True)
    man_path = os.path.join(DST, "holiday.json")
    man = {"pad": PAD, "pieces": {}}
    if os.path.exists(man_path):
        with open(man_path, encoding="utf-8") as f:
            man["pieces"] = json.load(f).get("pieces", {})
    for n in names:
        man["pieces"][n] = finish(src, n)
    with open(man_path, "w", encoding="utf-8") as f:
        json.dump(man, f, indent=1, sort_keys=True)
        f.write("\n")


if __name__ == "__main__":
    main()
