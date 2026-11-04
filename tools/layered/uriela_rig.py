"""Uriela's layered rig (2026-11-04): the first heroine cut by the SAM route (rigkit.py) instead of See-through.

Reads the rig-pose final (MOSS seed 104002, art_src/_review/rigproto/uriela/final/), the SAM masks
(sam_cut.py with uriela_sam.json -> <work>/sam), the picked expression frames (variants.py) and the image
model's repaints of the hidden parts (fill_hidden.py -> <work>/work2/*_fill.png). Writes
assets/art/heroes/uriela/skins/live/ (her base look once built: HeroArt.LIVE).

Layers, back to front: back hair (her ponytail), wings, body (head, torso, legs, coat), irises, lashes, the
two breasts, the lance, then each arm as an upper piece and a forearm with the hand.
Usage: tools/layered/uriela_rig.py"""
import json
import os
import shutil
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rigkit as K  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
HERO = "uriela"
SRC = os.path.join(ROOT, "art_src", "_review", "rigproto", HERO)
SAM = os.path.join(SRC, "sam")
WORK = os.path.join(SRC, "work2")
NAME = "live"
RIG = os.path.join(ROOT, "assets", "art", "heroes", HERO, "skins", NAME)
ST = os.path.join(RIG, "st")
W, H = K.W, K.H
YY, XX = K.YY, K.XX
for d in (RIG, ST, WORK, os.path.join(RIG, "variants")):
    os.makedirs(d, exist_ok=True)
for d in ("st", "variants"):
    open(os.path.join(RIG, d, ".gdignore"), "w").close()
shutil.copy(os.path.join(SRC, "final", HERO + ".png"), os.path.join(RIG, NAME + ".png"))

# the picked try of each expression frame (variants.py candidates; empty = the first try)
PICKS = {"eyes_closed": "eyes_closed_s104503", "eyes_half": "eyes_half_s104502", "mouth_open": "mouth_open_s104501",
         "mouth_small": "mouth_small_s104500", "mouth_wide": "mouth_wide_s104501", "smile": "smile_s104501"}
# (the blink needed variants.py --denoise 0.85: the first two tries only narrowed her eyes)
VC = os.path.join(SRC, "variants", "candidates")
HAS = {}
for vname, pick in PICKS.items():
    cands = sorted(f for f in os.listdir(VC) if f.startswith(vname + "_s") and f.endswith(".png")) if os.path.isdir(VC) else []
    f = pick + ".png" if pick else (cands[0] if cands else None)
    HAS[vname] = bool(f and os.path.exists(os.path.join(VC, f)))
    if HAS[vname]:
        shutil.copy(os.path.join(VC, f), os.path.join(RIG, "variants", vname + ".png"))

final = K.load_rgba(os.path.join(RIG, NAME + ".png"))
fa = final[..., 3] > 8


def sam(n):
    return K.load_mask(os.path.join(SAM, n + ".png")) & fa


# ---- part masks, front to back (a pixel two masks claim goes to the front one)
arm_r = K.clean(sam("arm_r") | sam("hand_r"), close=3)
arm_l = K.clean(sam("arm_l") | sam("hand_l"), close=3)
lance = K.clean(sam("lance") | sam("lance_shaft"), close=2, open_=1, keep_largest=False) & ~arm_r     # her fist splits it
breast_r = K.clean(sam("breast_r"), close=6, open_=3) & ~arm_r
breast_l = K.clean(sam("breast_l"), close=6, open_=3) & ~arm_l
CLEAVE = 504
breast_r &= XX < CLEAVE
breast_l &= XX >= CLEAVE
iris = (sam("iris_r") | sam("iris_l"))
# her ponytail hangs in front of her wings
hair = K.clean(sam("ponytail"), close=3, open_=1, keep_largest=False) & ~arm_l
wing_r = K.clean(sam("wing_r"), close=4, open_=2, keep_largest=False) & ~(arm_r | lance | hair)   # the blade splits it
wing_l = K.clean(sam("wing_l"), close=4, open_=2) & ~(arm_l | hair)
wings = wing_r | wing_l


def grow_edge(m, taken):
    """A part keeps the soft anti-aliased rim along its outline (SAM stops inside it), or the body layer
    under it shows a faint ghost of its outline."""
    return m | (ndimage.binary_dilation(m, iterations=3) & (final[..., 3] < 250) & fa & ~taken)


taken = np.zeros((H, W), bool)
for nm_ in ("arm_r", "arm_l", "lance", "breast_r", "breast_l", "hair", "wings"):
    m_ = grow_edge(globals()[nm_], taken)
    globals()[nm_] = m_
    taken |= m_
front = arm_r | arm_l | lance | breast_r | breast_l
body_m = fa & ~(front | wings | hair)
# specks the masks left between the lance, wings and hair (a blended edge no mask took) would ride on the
# body layer over the wings: each goes to the nearest of them
lab_b, n_b = ndimage.label(body_m)
if n_b > 1:
    sizes_b = ndimage.sum(body_m, lab_b, range(1, n_b + 1))
    stray = body_m & ~np.isin(lab_b, [k + 1 for k, v in enumerate(sizes_b) if v >= 4000])
    if stray.any():
        owners = {"wings": wings, "lance": lance, "hair": hair}
        dist = {k: ndimage.distance_transform_edt(~m) for k, m in owners.items() if m.any()}
        best = np.argmin(np.stack([dist[k] for k in dist]), axis=0)
        for i, k in enumerate(dist):
            sel = stray & (best == i)
            globals()[k] = globals()[k] | sel
        wings, lance, hair = globals()["wings"], globals()["lance"], globals()["hair"]
        body_m &= ~stray
        print("body: %d stray px given to the wings, lance and hair" % int(stray.sum()))
    front = arm_r | arm_l | lance | breast_r | breast_l
coat_r = K.clean(sam("coat_r"), close=3, keep_largest=False) & body_m     # the shaft splits it
coat_l = K.clean(sam("coat_l"), close=3, keep_largest=False) & body_m & ~coat_r
leg_r = K.clean(sam("leg_r"), close=3, keep_largest=False) & body_m     # boot and leg can split & ~(coat_r | coat_l)
leg_l = K.clean(sam("leg_l"), close=3, keep_largest=False) & body_m & ~(coat_r | coat_l | leg_r)
# the halo: the silver ring above her head (SAM took the ponytail's tie): low-saturation pixels in its box
fin3 = final[..., :3]
sat = (fin3.max(axis=2) - fin3.min(axis=2)) / np.maximum(fin3.max(axis=2), 1)
halo = fa & (YY >= 578) & (YY <= 632) & (XX >= 438) & (XX <= 578) & (sat < 0.22)
halo = ndimage.binary_opening(halo, iterations=1)
# the lashes: the dark lid lines over each eye (the irises slide under them)
lum = fin3.mean(axis=2)
eyebox = ((np.abs(XX - 477) <= 22) & (YY >= 731) & (YY <= 756)) | ((np.abs(XX - 534) <= 22) & (YY >= 730) & (YY <= 755))
lash = ndimage.binary_dilation(eyebox & (lum < 95) & ~ndimage.binary_erosion(iris, iterations=2), iterations=1) & eyebox
for n, m in (("arm_r", arm_r), ("arm_l", arm_l), ("lance", lance), ("breast_r", breast_r), ("breast_l", breast_l),
             ("wings", wings), ("hair", hair), ("coat_r", coat_r), ("coat_l", coat_l), ("leg_r", leg_r), ("leg_l", leg_l),
             ("halo", halo), ("lash", lash), ("iris", iris)):
    print("%-9s %6d px" % (n, int(m.sum())))

img = {}
# ---- back hair: her ponytail, continued 16 px in under her shoulders and behind the arm in front of it,
# strand by strand (rigkit.strand_fill: the image model's tries painted a small woman into the strip and a
# blurred fill read as a smear; a picked repaint in hair_fill.png would still win)
bh = K.cut(final, hair)
hhole = (K.behind(arm_l, hair, reach=26) & ~hair) | K.under_band(bh, body_m | arm_l, px=16)
bh = K.strand_fill(bh, hhole, warm=30)      # honey blonde
K.save_mask(os.path.join(WORK, "hair_hole.png"), hhole)
K.save_rgba(os.path.join(WORK, "hair_rough.png"), bh)
bh, rep = K.apply_repaint(bh, hhole, os.path.join(WORK, "hair_fill.png"))
print("back hair: %d px painted in%s" % (int(hhole.sum()), ", repainted" if rep else ""))
img["back_hair"] = bh
# ---- wings: what the lance's blade and the arms covered of them, and their roots under her, painted in
# (each side repainted on its own: wings_r_fill.png, wings_l_fill.png)
wl = K.cut(final, wings)
whole = (K.behind(lance | arm_r | arm_l, wings, reach=64) & ~wings) | K.under_band(wl, body_m | hair | arm_r | arm_l | lance, px=40)
wl = K.rough_fill(wl, whole, radius=5)
K.save_rgba(os.path.join(WORK, "wings_rough.png"), wl)
done = []
for sd, half in (("r", XX < 507), ("l", XX >= 507)):
    K.save_mask(os.path.join(WORK, "wings_%s_hole.png" % sd), whole & half)
    wl, rep = K.apply_repaint(wl, whole & half, os.path.join(WORK, "wings_%s_fill.png" % sd))
    if rep:
        done.append(sd)
print("wings: %d px painted in; repainted: %s" % (int(whole.sum()), ", ".join(done) or "none"))
img["wings"] = wl

# ---- body: everything else; the torso behind the breasts, her sides behind the arms, the coat behind the
# lance's shaft are painted in
body = final.copy()
body[~body_m, 3] = 0
both = breast_r | breast_l
bhole = ndimage.binary_dilation(both, iterations=2) & fa
inside = ndimage.binary_fill_holes(ndimage.binary_closing(body_m | both, iterations=8))
body, put_b = K.torso_fill(body, bhole & ~body_m, inside)
side_hole = K.behind(arm_r | arm_l, body_m, reach=22) & ~body_m
side_hole |= ndimage.binary_dilation(body_m, iterations=14) & (arm_r | arm_l) & ~ndimage.binary_dilation(lance, iterations=2)
shaft_hole = K.behind(lance, body_m, reach=30) & ~body_m & (YY > 1150)
hole = (side_hole | shaft_hole) & ~put_b
body = K.rough_fill(body, hole)
K.save_rgba(os.path.join(WORK, "body_rough.png"), body)
# the image model repaints each hidden area with its own prompt (fill_hidden.py on body_rough.png with
# body_hole_<area>.png; the picked try copied to body_fill_<area>.png): her chest behind the breasts, her
# sides behind each arm, the coat behind the shaft
areas = {"chest": put_b, "side_r": side_hole & (XX < 507) & ~shaft_hole, "side_l": side_hole & (XX >= 507), "shaft": shaft_hole & ~put_b}
done = []
for an, am in areas.items():
    K.save_mask(os.path.join(WORK, "body_hole_%s.png" % an), am)
    body, rep = K.apply_repaint(body, am, os.path.join(WORK, "body_fill_%s.png" % an))
    if rep:
        done.append(an)
print("body: %d px behind the breasts, %d behind the arms, %d behind the shaft; repainted: %s" % (
    int(put_b.sum()), int(side_hole.sum()), int(shaft_hole.sum()), ", ".join(done) or "none"))
body, n_e, sclera = K.eye_whites(body, final, iris, lash)
print("eyes: %d eye whites painted, sclera %s" % (n_e, sclera.astype(int).tolist()))
img["body"] = body
img["irides"] = K.cut(final, iris, soft=0.5)
img["lashes"] = K.cut(final, lash, soft=0.5)
img["breast_r"] = K.cut(final, breast_r)
img["breast_l"] = K.cut(final, breast_l)
# the shaft through her fist: the rows the hand covers copy the shaft's cross-section just below it, so the
# lance can turn in her grip and stay whole
ln = K.cut(final, lance, soft=0.6)
rows = np.nonzero(lance[:, 200:340].any(axis=1))[0]
gap = [y for y in range(1060, 1200) if not lance[y, 200:340].any()]
if gap:
    yb = next(y for y in range(gap[-1] + 1, H) if lance[y, 200:340].any()) + 4
    ya = gap[0] - 1
    cb = np.nonzero(lance[yb, :])[0].mean()
    ca = np.nonzero(lance[ya, :])[0].mean() if lance[ya].any() else cb
    for y in range(ya + 1, yb):
        t = (y - ya) / max(yb - ya, 1)
        dx = int(round((ca * (1 - t) + cb * t) - cb))
        ln[y] = np.roll(ln[yb], dx, axis=0)
        lance[y] = np.roll(lance[yb], dx)
    print("lance: %d rows of shaft painted through her fist" % (yb - ya - 1))
img["lance"] = ln

# ---- arms: upper arm and forearm with the hand, cut by the nearest bone segment, a cap at the elbow
ARM_CHAIN = {"r": [(398, 870), (378, 1045), (316, 1124), (245, 1160)],     # shoulder, elbow, wrist, fingertip
             "l": [(614, 870), (632, 1050), (690, 1186), (768, 1322)]}
ARM_CAP = {"r": 22, "l": 20}
ARM_R = 22          # the upper arm's half width
for side, m in (("r", arm_r), ("l", arm_l)):
    a = K.cut(final, m)
    pieces = K.split_arm(a, ARM_CHAIN[side], ARM_CAP[side])
    # her upper arm runs down behind the outer edge of her breast (it sits behind them): the part the
    # breast hides is painted in (her skin from the arm's own pixels; the image model's repaint wins), so a
    # raised arm is whole; at rest the breast covers it
    up = pieces["up"]
    cap_m = (K.seg_dist(ARM_CHAIN[side][0], ARM_CHAIN[side][1]) <= ARM_R) & (breast_r | breast_l) & ~m
    if cap_m.any():
        up = K.rough_fill(up, cap_m, radius=7)
        K.save_mask(os.path.join(WORK, "arm_%s_up_hole.png" % side), cap_m)
        K.save_rgba(os.path.join(WORK, "arm_%s_up_rough.png" % side), up)
        up, rep = K.apply_repaint(up, cap_m, os.path.join(WORK, "arm_%s_up_fill.png" % side))
        print("arm_%s: %d px of upper arm painted in behind the breast%s" % (side, int(cap_m.sum()), ", repainted" if rep else ""))
    img["arm_%s_up" % side] = up
    img["arm_%s_fore" % side] = pieces["fore"]

RIG_Z = {"wings": -40, "back_hair": -30, "body": 0, "irides": 1, "lashes": 2, "arm_l_up": 3, "arm_r_up": 3, "breast_r": 4,
         "breast_l": 5, "lance": 7, "arm_l_fore": 9, "arm_r_fore": 11}
rects = K.write_layers(RIG, NAME, img, RIG_Z, ST)

# ---- region masks (st/)
for n, m in (("hair", hair), ("wings_m", wings), ("iris_m", iris), ("halo", halo), ("coat_r", coat_r), ("coat_l", coat_l),
             ("leg_r", leg_r), ("leg_l", leg_l), ("hand_r", sam("hand_r")), ("hand_l", sam("hand_l"))):
    K.save_mask(os.path.join(ST, n + ".png"), m)
for side, m, sign in (("r", breast_r, -1), ("l", breast_l, 1)):
    w, lo = K.breast_weights(m, CLEAVE, sign)
    K.save_mask(os.path.join(ST, "breast_%s_w.png" % side), w)
    K.save_mask(os.path.join(ST, "breast_%s_lo_w.png" % side), lo)

M = lambda f, **kw: dict({"type": "mask", "image": "st/%s.png" % f}, **kw)
P = lambda pts, **kw: dict({"type": "polygon", "points": pts}, **kw)
BOX = lambda x0, y0, x1, y1: P([[x0, y0], [x1, y0], [x1, y1], [x0, y1]])

# her ponytail: a chain of four segments down its length (a wave travels down it), the mass on her head first
# (the first segment starts where it leaves her head, right of her face)
HAIR_BANDS = [700, 840, 980, 1110, 1260]
hair_regions, hair_bones, parent = [], [], "hair_back"
for k in range(4):
    y0, y1 = HAIR_BANDS[k], HAIR_BANDS[k + 1]
    nm = "hair_p%d" % (k + 1)
    x_min = 560 if k == 0 else 0
    xs_b = np.nonzero(hair[y0:y0 + 40, x_min:])[1]
    px = int(xs_b.mean()) + x_min if len(xs_b) else 700
    hair_regions.append({"name": nm, "soft": 24, "rule": M("hair", within=BOX(x_min, y0, 1024, y1 if k < 3 else 2048))})
    hair_bones.append({"name": nm, "parent": parent, "pivot": [px, y0],
                       "spring": "hair_long;w=0.07;i=0.62;g=0.8;limit=14;k=%d" % (46 - 5 * k)})
    parent = nm
hair_regions.reverse()           # the lowest segments first (priority), the mass on her head last

regions = [
    # body layer
    {"name": "face", "rule": {"type": "ellipse", "center": [507, 772], "radius": [58, 62], "feather": 12}},
    {"name": "iris", "rule": M("iris_m")},
    {"name": "halo", "rule": M("halo")},
    {"name": "earring_r", "soft": 6, "rule": BOX(442, 796, 474, 866)},
    {"name": "earring_l", "soft": 6, "rule": BOX(540, 796, 574, 866)},
    {"name": "hair_front_r", "soft": 16, "rule": P([[420, 700], [466, 700], [470, 745], [452, 820], [424, 900], [410, 820]])},
    {"name": "hair_front_l", "soft": 16, "rule": P([[548, 700], [594, 700], [604, 820], [590, 900], [562, 820], [544, 745]])},
    {"name": "head", "rule": {"type": "ellipse", "center": [507, 720], "radius": [112, 140], "feather": 18}},
    {"name": "neck", "rule": P([[470, 812], [545, 812], [552, 870], [462, 870]], feather=14)},
    {"name": "breast_r_lo", "rule": M("breast_r_lo_w", levels=True)},
    {"name": "breast_r", "rule": M("breast_r_w", levels=True)},
    {"name": "breast_l_lo", "rule": M("breast_l_lo_w", levels=True)},
    {"name": "breast_l", "rule": M("breast_l_w", levels=True)},
    {"name": "chest", "rule": P([[395, 860], [620, 860], [640, 960], [625, 1060], [390, 1060], [375, 960]], feather=26)},
    {"name": "torso", "rule": P([[395, 1040], [620, 1040], [615, 1170], [400, 1170]], feather=26)},
    # the coat: each side a two-bone chain from the hip, its hem the second
    {"name": "drape_r2", "soft": 120, "rule": M("coat_r", within=BOX(0, 1470, 512, 2048))},
    {"name": "drape_r", "rule": M("coat_r")},
    {"name": "drape_l2", "soft": 120, "rule": M("coat_l", within=BOX(512, 1470, 1024, 2048))},
    {"name": "drape_l", "rule": M("coat_l")},
    # legs
    {"name": "foot_r", "rule": M("leg_r", within=BOX(0, 1745, 512, 2048))},
    {"name": "shin_r", "rule": M("leg_r", within=BOX(0, 1540, 512, 2048))},
    {"name": "thigh_r", "rule": M("leg_r")},
    {"name": "foot_l", "rule": M("leg_l", within=BOX(512, 1745, 1024, 2048))},
    {"name": "shin_l", "rule": M("leg_l", within=BOX(512, 1540, 1024, 2048))},
    {"name": "thigh_l", "rule": M("leg_l")},
    {"name": "hips", "rule": P([[350, 1150], [665, 1150], [690, 1320], [330, 1320]], feather=22)},
    # the lance and arms
    {"name": "weapon", "rule": M("lance")},
    {"name": "hand_r", "rule": M("hand_r", within=M("arm_r_fore"))},
    {"name": "forearm_r", "rule": M("arm_r_fore")},
    {"name": "arm_r", "rule": M("arm_r_up")},
    {"name": "hand_l", "rule": M("hand_l", within=M("arm_l_fore"))},
    {"name": "forearm_l", "rule": M("arm_l_fore")},
    {"name": "arm_l", "rule": M("arm_l_up")},
    # wings: a root and a tip each
    {"name": "wing_r2", "soft": 60, "rule": M("wings_m", within=BOX(0, 0, 232, 2048))},
    {"name": "wing_r", "rule": M("wings_m", within=BOX(0, 0, 507, 2048))},
    {"name": "wing_l2", "soft": 60, "rule": M("wings_m", within=BOX(790, 0, 1024, 2048))},
    {"name": "wing_l", "rule": M("wings_m", within=BOX(507, 0, 1024, 2048))},
] + hair_regions + [
    {"name": "hair_back", "rule": M("hair")},
]

JIG_LO = "jiggle;kx=170;ky=230;ky2=560;z=0.3;limit=10;tx=0.3;ty=0.45;rot=0.35;sq=0.6;kick=0"
bones = [
    # planted ankles: the legs reach them by IK, so the knees flex as the hips move
    {"name": "ik_foot_r", "parent": "root", "pivot": [370, 1755]},
    {"name": "ik_foot_l", "parent": "root", "pivot": [666, 1755]},
    {"name": "hips", "parent": "root", "pivot": [507, 1240]},
    {"name": "torso", "parent": "hips", "pivot": [507, 1130]},
    {"name": "chest", "parent": "torso", "pivot": [507, 1000]},
    {"name": "neck", "parent": "chest", "pivot": [507, 848]},
    {"name": "head", "parent": "neck", "pivot": [507, 825]},
    {"name": "face", "parent": "head", "pivot": [507, 782]},
    {"name": "iris", "parent": "face", "pivot": [506, 748]},
    {"name": "hair_front_r", "parent": "head", "pivot": [444, 705], "spring": "bangs"},
    {"name": "hair_front_l", "parent": "head", "pivot": [570, 705], "spring": "bangs"},
    {"name": "hair_back", "parent": "head", "pivot": [540, 640], "spring": "hair_mass;g=0.85"},
] + hair_bones + [
    {"name": "halo", "parent": "head", "pivot": [507, 606], "spring": "accessory;limit=5"},
    {"name": "earring_r", "parent": "head", "pivot": [458, 800], "spring": "accessory;limit=12"},
    {"name": "earring_l", "parent": "head", "pivot": [556, 800], "spring": "accessory;limit=12"},
    {"name": "breast_r", "parent": "chest", "pivot": [432, 918], "spring": "jiggle;ky=190"},
    {"name": "breast_r_lo", "parent": "breast_r", "pivot": [432, 980], "spring": JIG_LO},
    {"name": "breast_l", "parent": "chest", "pivot": [580, 918], "spring": "jiggle;ky=190"},
    {"name": "breast_l_lo", "parent": "breast_l", "pivot": [580, 980], "spring": JIG_LO},
    {"name": "arm_r", "parent": "chest", "pivot": [398, 870]},
    {"name": "forearm_r", "parent": "arm_r", "pivot": [378, 1045]},
    {"name": "hand_r", "parent": "forearm_r", "pivot": [316, 1124]},
    {"name": "arm_l", "parent": "chest", "pivot": [614, 870]},
    {"name": "forearm_l", "parent": "arm_l", "pivot": [632, 1050]},
    {"name": "hand_l", "parent": "forearm_l", "pivot": [690, 1186]},
    {"name": "weapon", "parent": "root", "pivot": [270, 1972], "tip": [263, 553], "grip": {"bone": "hand_r", "at": [268, 1148]}},
    {"name": "thigh_r", "parent": "hips", "pivot": [440, 1262]},
    {"name": "shin_r", "parent": "thigh_r", "pivot": [405, 1538]},
    {"name": "foot_r", "parent": "shin_r", "pivot": [370, 1755]},
    {"name": "thigh_l", "parent": "hips", "pivot": [578, 1262]},
    {"name": "shin_l", "parent": "thigh_l", "pivot": [603, 1538]},
    {"name": "foot_l", "parent": "shin_l", "pivot": [666, 1755]},
    {"name": "drape_r", "parent": "hips", "pivot": [330, 1190], "spring": "cape;w=0.1;g=0.85;limit=12"},
    {"name": "drape_r2", "parent": "drape_r", "pivot": [262, 1470], "spring": "cape;w=0.06;g=0.9;limit=7"},
    {"name": "drape_l", "parent": "hips", "pivot": [690, 1190], "spring": "cape;w=0.1;g=0.85;limit=12"},
    {"name": "drape_l2", "parent": "drape_l", "pivot": [762, 1470], "spring": "cape;w=0.06;g=0.9;limit=7"},
    {"name": "wing_r", "parent": "chest", "pivot": [405, 905], "spring": "wing;w=0.05"},
    {"name": "wing_r2", "parent": "wing_r", "pivot": [232, 870], "spring": "wing;w=0.04;limit=8"},
    {"name": "wing_l", "parent": "chest", "pivot": [610, 905], "spring": "wing;w=0.05"},
    {"name": "wing_l2", "parent": "wing_l", "pivot": [790, 870], "spring": "wing;w=0.04;limit=8"},
]

own = {"back_hair": ["hair_back", "hair_p"], "wings": ["wing"],
       "body": ["face", "head", "neck", "chest", "torso", "hips", "thigh", "shin", "foot", "drape", "halo", "earring", "hair_front"],
       "irides": ["iris"], "lashes": ["face"], "breast_r": ["breast_r"], "breast_l": ["breast_l"],
       "arm_r_fore": ["hand_r", "forearm_r"], "arm_l_fore": ["hand_l", "forearm_l"]}
RIGID = {"lance": "weapon", "arm_r_up": "arm_r", "arm_l_up": "arm_l"}
rest = {"breast_r": "chest", "breast_l": "chest"}
CELL = {"breast_r": 6, "breast_l": 6, "arm_r_fore": 8, "arm_l_fore": 8}
layers = []
for rl, z in sorted(RIG_Z.items(), key=lambda t: t[1]):
    Ly = {"name": rl, "image": "%s_%s.png" % (NAME, rl), "z": z, "image_rect": rects[rl]}
    if rl in RIGID:
        Ly["bone"] = RIGID[rl]
    else:
        Ly["parts"] = own[rl]
        Ly["weights"] = "own"
        if rl in rest:
            Ly["rest_bone"] = rest[rl]
        if rl in CELL:
            Ly["cell"] = CELL[rl]
    layers.append(Ly)

# the face frames: each slot's patch rect covers every one of its frames
EYES, MOUTH = (506, 746), (509, 789)
er = K.union([K.diff_rect(os.path.join(RIG, "variants", v + ".png"), final, EYES, half=(62, 20)) for v in ("eyes_closed", "eyes_half", "smile") if HAS.get(v)])
mr = K.union([K.diff_rect(os.path.join(RIG, "variants", v + ".png"), final, MOUTH, half=(34, 22)) for v in ("mouth_open", "mouth_small", "mouth_wide", "smile") if HAS.get(v)]) if any(HAS.get(v) for v in ("mouth_open", "mouth_small", "mouth_wide", "smile")) else None
overlays = []
if any(HAS.get(v) for v in ("eyes_closed", "eyes_half", "smile")):
    overlays.append({"slot": "eyes", "bone": "face", "base": "open", "default": "open", "z": 3, "rect": er,
                     "variants": {k: "variants/%s.png" % v for k, v in (("closed", "eyes_closed"), ("half", "eyes_half"), ("smile", "smile")) if HAS.get(v)}})
if mr:
    overlays.append({"slot": "mouth", "bone": "face", "base": "default", "default": "default", "z": 3, "rect": mr,
                     "variants": {k: "variants/%s.png" % v for k, v in (("open", "mouth_open"), ("small", "mouth_small"), ("wide", "mouth_wide"), ("smile", "smile")) if HAS.get(v)}})

fmeta = json.load(open(os.path.join(SRC, "final", HERO + ".json")))
src = {
    "_doc": "Uriela's layered rig (2026-11-04): MOSS rig pose seed 104002, cut by SAM (tools/layered/uriela_rig.py, rigkit.py), "
            "hidden parts painted in. Her base look (HeroArt.LIVE).",
    "version": 2, "cell": 10, "image": NAME + ".png", "origin": fmeta.get("origin", [512, 1990]), "texel_scale": 1.0,
    "portrait": [380, 600, 260], "look_px": [10, 6],
    "meta": {"weapon": "spear", "attack": "attack_thrust", "fx_color": "#9fe8ff", "art": "moss s104002 rig pose, SAM layers",
             "idle_gestures": ["idle_twirl", "idle_stretch", "idle_visor"],
             "idle": {"breath": 6.0, "noise": 2.2, "head": 1.6, "arms": 2.2, "wings": 1.8, "sway": 6.0,
                      "sway_period": 6.4, "sway_rot": 0.8, "sway_dip": 2.5, "kick_breath": 75.0, "kick_sway": 45.0,
                      "iris_x": 1.6, "iris_y": 0.5, "gaze": 0.6}},
    "body_bone": "hips", "bones": bones, "regions": regions, "layers": layers,
    "ik": [{"upper": "thigh_r", "lower": "shin_r", "target": "ik_foot_r", "foot": "foot_r", "knee_room": 10},
           {"upper": "thigh_l", "lower": "shin_l", "target": "ik_foot_l", "foot": "foot_l", "knee_room": 10}],
    "overlays": overlays,
}
json.dump(src, open(os.path.join(RIG, NAME + ".warp_src.json"), "w"), indent=1)
print("wrote", NAME, len(bones), "bones", len(regions), "regions", len(layers), "layers", len(overlays), "overlay slots")
