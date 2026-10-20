#!/usr/bin/env python3
"""Draw OpenPose skeletons (COCO 18 keypoints, the standard colours) for ControlNet pose control.

    python tools/comfy/pose.py rig_stand out.png [--size 896x1152]      # a named pose
    python tools/comfy/pose.py pose.json out.png [--size 896x1152]      # your own keypoints
    python tools/comfy/pose.py rig_stand sheet.png --over art.png       # skeleton over an image, to check

Keypoints are fractions of the canvas (x right, y down), in OpenPose order:
  nose, neck, r_shoulder, r_elbow, r_wrist, l_shoulder, l_elbow, l_wrist, r_hip, r_knee, r_ankle,
  l_hip, l_knee, l_ankle, r_eye, l_eye, r_ear, l_ear      (r_ = HER right = the viewer's left)
A JSON pose is {"name": [x, y] or null, ...} with those names; missing points are left out.
Use the image with run_hero.py --controlnet xinsir_union_sdxl_promax.safetensors --control-type
openpose --control-image <uploaded name>. Rig-ready poses (docs/dev/halorig.md 12): square to the
viewer, arms clear of the body, hands and weapon in the open, legs apart, so every part can be cut out
and the little that hides can be painted in.
"""
import argparse
import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

NAMES = ["nose", "neck", "r_shoulder", "r_elbow", "r_wrist", "l_shoulder", "l_elbow", "l_wrist", "r_hip", "r_knee",
         "r_ankle", "l_hip", "l_knee", "l_ankle", "r_eye", "l_eye", "r_ear", "l_ear"]
LIMBS = [(1, 2), (1, 5), (2, 3), (3, 4), (5, 6), (6, 7), (1, 8), (8, 9), (9, 10), (1, 11), (11, 12), (12, 13), (1, 0),
         (0, 14), (14, 16), (0, 15), (15, 17)]
COLORS = [(255, 0, 0), (255, 85, 0), (255, 170, 0), (255, 255, 0), (170, 255, 0), (85, 255, 0), (0, 255, 0),
          (0, 255, 85), (0, 255, 170), (0, 255, 255), (0, 170, 255), (0, 85, 255), (0, 0, 255), (85, 0, 255),
          (170, 0, 255), (255, 0, 255), (255, 0, 170), (255, 0, 85)]

# Named poses. Heights for a tall heroine about 7.5 heads, head top near y 0.10, soles near 0.93,
# leaving room at the sides for spread wings.
POSES = {
    # standing square to the viewer; her right hand holds a staff or polearm upright at her side, her
    # left arm hangs relaxed a little away from the hip: torso, both arms and both legs in the open
    "rig_stand": {
        "nose": [0.5, 0.155], "neck": [0.5, 0.228], "r_eye": [0.486, 0.143], "l_eye": [0.514, 0.143],
        "r_ear": [0.468, 0.152], "l_ear": [0.532, 0.152],
        "r_shoulder": [0.418, 0.226], "r_elbow": [0.378, 0.37], "r_wrist": [0.352, 0.488],
        "l_shoulder": [0.582, 0.226], "l_elbow": [0.628, 0.366], "l_wrist": [0.652, 0.48],
        "r_hip": [0.452, 0.5], "r_knee": [0.432, 0.69], "r_ankle": [0.418, 0.918],
        "l_hip": [0.548, 0.5], "l_knee": [0.572, 0.69], "l_ankle": [0.59, 0.918]},
    # the same with both arms clear of the body (no weapon in hand)
    "rig_a": {
        "nose": [0.5, 0.155], "neck": [0.5, 0.228], "r_eye": [0.486, 0.143], "l_eye": [0.514, 0.143],
        "r_ear": [0.468, 0.152], "l_ear": [0.532, 0.152],
        "r_shoulder": [0.418, 0.226], "r_elbow": [0.372, 0.366], "r_wrist": [0.348, 0.48],
        "l_shoulder": [0.582, 0.226], "l_elbow": [0.628, 0.366], "l_wrist": [0.652, 0.48],
        "r_hip": [0.452, 0.5], "r_knee": [0.432, 0.69], "r_ankle": [0.418, 0.918],
        "l_hip": [0.548, 0.5], "l_knee": [0.572, 0.69], "l_ankle": [0.59, 0.918]},
}


def load_pose(arg):
    if arg in POSES:
        return POSES[arg]
    if os.path.exists(arg):
        return json.load(open(arg))
    raise SystemExit("pose.py: unknown pose %r (named: %s)" % (arg, ", ".join(POSES)))


def draw(pose, size):
    """The OpenPose picture: limbs as soft ellipses over black, joints as dots (as the preprocessors
    draw them), line width scaled from OpenPose's 4 px at 512."""
    W, H = size
    k = max(W, H) / 512.0
    stick = 4 * k
    pts = [None] * 18
    for i, n in enumerate(NAMES):
        p = pose.get(n)
        if p is not None:
            pts[i] = (p[0] * W, p[1] * H)
    canvas = np.zeros((H, W, 3), np.float32)
    for li, (a, b) in enumerate(LIMBS):
        if pts[a] is None or pts[b] is None:
            continue
        (x0, y0), (x1, y1) = pts[a], pts[b]
        mx, my = (x0 + x1) / 2, (y0 + y1) / 2
        length = math.hypot(x1 - x0, y1 - y0)
        ang = math.atan2(y1 - y0, x1 - x0)
        poly = []
        for t in range(0, 360, 10):
            u = math.radians(t)
            ex, ey = (length / 2) * math.cos(u), stick * math.sin(u)
            poly.append((mx + ex * math.cos(ang) - ey * math.sin(ang), my + ex * math.sin(ang) + ey * math.cos(ang)))
        layer = Image.new("RGB", (W, H))
        ImageDraw.Draw(layer).polygon(poly, fill=COLORS[li])
        lay = np.array(layer).astype(np.float32)
        m = lay.max(axis=2, keepdims=True) > 0
        canvas = np.where(m, canvas * 0.4 + lay * 0.6, canvas)
    img = Image.fromarray(canvas.astype(np.uint8))
    d = ImageDraw.Draw(img)
    r = 4 * k
    for i, p in enumerate(pts):
        if p is not None:
            d.ellipse([p[0] - r, p[1] - r, p[0] + r, p[1] + r], fill=COLORS[i])
    return img


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("pose")
    ap.add_argument("out")
    ap.add_argument("--size", default="896x1152")
    ap.add_argument("--over", help="draw the skeleton over this image instead of black (a check)")
    a = ap.parse_args()
    W, H = (int(v) for v in a.size.lower().split("x"))
    img = draw(load_pose(a.pose), (W, H))
    if a.over:
        base = Image.open(a.over).convert("RGB").resize((W, H))
        m = np.array(img).max(axis=2, keepdims=True) > 0
        img = Image.fromarray(np.where(m, np.array(img), np.array(base)).astype(np.uint8))
    img.save(a.out)
    print("pose.py:", a.out)


if __name__ == "__main__":
    sys.exit(main())
