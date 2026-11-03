"""Bakes each painting's two-tone cut point into assets/art/heroes/cuts.json.

    python tools/art_cuts.py

The two-tone print (an ultimate's impact frame, a blow's impact frame in battle, a fallen echo's
proof) splits her at her own mid-tone: the median luma of her figure from the top of her face down
4.5 face-heights, sampled every 12 px where the painting is opaque, kept within 0.25-0.7. The game used
to scan the texture for it at runtime (UltCutin._cut_point): on the phone that is a GPU readback of the
whole painting, a hitch a beat into every fight. Every rig with a .warp_src.json is baked here, keyed by
its file base under assets/art/heroes/ (RigData.file_base without the folder: "seraphiel/seraphiel",
"seraphiel/skins/<art>/<art>"). Run it after installing new art (tools/check does not).
"""
import glob, json, os
import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HEROES = os.path.join(ROOT, "assets", "art", "heroes")

out = {}
for src in sorted(glob.glob(os.path.join(HEROES, "**", "*.warp_src.json"), recursive=True)):
    base = src[: -len(".warp_src.json")]
    png = base + ".png"
    if not os.path.exists(png):
        continue
    d = json.load(open(src, encoding="utf-8"))
    face = next((r for r in d.get("regions", []) if r.get("name") == "face" and r.get("rule", {}).get("type") == "ellipse"), None)
    im = Image.open(png).convert("RGBA")
    w, h = im.size
    k = w / float((d.get("image_size") or [w])[0])
    if face is None:
        cy, ry = h * 0.22, h * 0.03
    else:
        cy = float(face["rule"]["center"][1]) * k
        ry = float(face["rule"].get("radius", [60, 50])[1]) * k
    top = int(max(cy - ry, 0))
    bot = int(min(cy + ry + 2.0 * ry * 4.5, h - 1))
    a = np.asarray(im, np.float32)[top:bot:12, ::12] / 255.0
    m = a[..., 3] > 0.6
    if m.sum() <= 40:
        continue
    luma = (a[..., 0] * 0.299 + a[..., 1] * 0.587 + a[..., 2] * 0.114)[m]
    key = os.path.relpath(base, HEROES).replace(os.sep, "/")
    out[key] = round(float(np.clip(np.sort(luma)[luma.size // 2], 0.25, 0.7)), 3)

dst = os.path.join(HEROES, "cuts.json")
with open(dst, "w", encoding="utf-8", newline="\n") as f:
    json.dump(out, f, indent=0, sort_keys=True)
    f.write("\n")
print(dst, len(out))
