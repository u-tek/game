"""Kessa's layered rig (2026-11-04): the SAM route (rigkit.py), modelled on lucen_rig.py.

Reads the rig-pose final (MOSS seed 205013, art_src/_review/rigproto/kessa/final/), the SAM masks (sam_cut.py
with kessa_sam.json -> <work>/sam), the picked expression frames (variants.py) and the image model's repaints of
the hidden parts (fill_hidden.py -> <work>/work2/*_fill.png). Writes assets/art/heroes/kessa/skins/live/ (her
base look once built: HeroArt.LIVE).

Layers, back to front: the scarf's long tails (a cape behind her, two halves), her tail, body (head, torso,
legs), irises, lashes, the upper arms, the two breasts, a sickle carried in each hand, the forearms with the
hands.
Usage: tools/layered/kessa_rig.py"""
import json
import os
import shutil
import sys

import numpy as np
from scipy import ndimage

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rigkit as K  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
HERO = "kessa"
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
PICKS = {"eyes_closed": "eyes_closed_s205503", "eyes_half": "eyes_half_s205500", "mouth_open": "mouth_open_s205501",
         "mouth_small": "mouth_small_s205500", "mouth_wide": "mouth_wide_s205501", "smile": "smile_s205500"}
# (the blink needed variants.py --denoise 0.85; both smile tries turned her amber eyes red, so her smile is a
# mouth frame only: the eyes slot has no smile)
EYE_SMILE = False
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
ARM_CHAIN = {"r": [(368, 625), (318, 860), (262, 1075), (240, 1125)],     # shoulder, elbow, wrist, fingertip
             "l": [(650, 625), (700, 860), (752, 1075), (778, 1125)]}
fin3 = final[..., :3]
lum = fin3.mean(axis=2)


def arm_tube(side, radius):
    """Within `radius` px of the arm's bones (SAM's left arm took a strip of the red cape beside it)."""
    ch = ARM_CHAIN[side]
    return np.min(np.stack([K.seg_dist(ch[k], ch[k + 1]) for k in range(3)]), axis=0) <= radius


redish = (fin3[..., 0] - fin3[..., 1] > 60) & (fin3[..., 0] - fin3[..., 2] > 40) & (YY < 1000)   # the cape's red, not her gloves' trim


def shoulder(side):
    """Her bare shoulder above the glove (SAM cut the glove only): her skin along the upper arm's bone."""
    ch = ARM_CHAIN[side]
    return (K.seg_dist(ch[0], ch[1]) <= 34) & (YY < 800) & fa & ~redish


arm_r = K.clean(((sam("arm_r") & arm_tube("r", 64) & ~redish) | shoulder("r") | sam("hand_r")) & ~sam("breast_r"), close=3)
arm_l = K.clean(((sam("arm_l") & arm_tube("l", 64) & ~redish) | shoulder("l") | sam("hand_l")) & ~sam("breast_l"), close=3)
sickle_r = K.clean(sam("sickle_r"), close=2, open_=0, keep_largest=False) & ~arm_r
sickle_l = K.clean(sam("sickle_l"), close=2, open_=0, keep_largest=False) & ~arm_l
breast_r = K.clean(sam("breast_r"), close=6, open_=3) & ~arm_r
breast_l = K.clean(sam("breast_l"), close=6, open_=3) & ~arm_l
CLEAVE = 512
breast_r &= XX < CLEAVE
breast_l &= XX >= CLEAVE
iris = sam("iris_r") | sam("iris_l")
# the scarf's tails hang behind her as a cape (the wrap round her neck stays on the body)
cape = (K.clean(sam("cape_r"), close=3, open_=1, keep_largest=False) | K.clean(sam("cape_l"), close=3, open_=1, keep_largest=False)
        | (sam("arm_l") & redish)) & ~(arm_r | arm_l | sickle_r | sickle_l)
tail = K.clean(sam("tail"), close=3, open_=1, keep_largest=False) & ~(cape | sickle_l)


def grow_edge(m, taken):
    """A part keeps the soft anti-aliased rim along its outline (SAM stops inside it)."""
    return m | (ndimage.binary_dilation(m, iterations=3) & (final[..., 3] < 250) & fa & ~taken)


taken = np.zeros((H, W), bool)
for nm_ in ("arm_r", "arm_l", "sickle_r", "sickle_l", "breast_r", "breast_l", "tail", "cape"):
    m_ = grow_edge(globals()[nm_], taken)
    globals()[nm_] = m_
    taken |= m_
sickles = sickle_r | sickle_l
front = arm_r | arm_l | sickles | breast_r | breast_l
body_m = fa & ~(front | cape | tail)
lab_b, n_b = ndimage.label(body_m)
if n_b > 1:
    sizes_b = ndimage.sum(body_m, lab_b, range(1, n_b + 1))
    stray = body_m & ~np.isin(lab_b, [k + 1 for k, v in enumerate(sizes_b) if v >= 4000])
    if stray.any():
        owners = {"cape": cape, "tail": tail, "sickle_r": sickle_r, "sickle_l": sickle_l, "arm_r": arm_r, "arm_l": arm_l}
        dist = {k: ndimage.distance_transform_edt(~m) for k, m in owners.items() if m.any()}
        dd = np.stack([dist[k] for k in dist])
        best = np.argmin(dd, axis=0)
        stray &= dd.min(axis=0) <= 40
        for i, k in enumerate(dist):
            globals()[k] = globals()[k] | (stray & (best == i))
        cape, tail, sickle_r, sickle_l = globals()["cape"], globals()["tail"], globals()["sickle_r"], globals()["sickle_l"]
        arm_r, arm_l = globals()["arm_r"], globals()["arm_l"]
        sickles = sickle_r | sickle_l
        body_m &= ~stray
        print("body: %d stray px given to the cape, tail, sickles and arms" % int(stray.sum()))
    front = arm_r | arm_l | sickles | breast_r | breast_l
leg_r = K.clean(sam("leg_r"), close=3, keep_largest=False) & body_m
leg_l = K.clean(sam("leg_l"), close=3, keep_largest=False) & body_m & ~leg_r
phones = K.clean(sam("headphones"), close=2, open_=0) & body_m
visor = K.clean(sam("visor"), close=2, open_=0) & body_m
eyebox = ((np.abs(XX - 468) <= 22) & (YY >= 455) & (YY <= 484)) | ((np.abs(XX - 540) <= 22) & (YY >= 442) & (YY <= 471))
lash = ndimage.binary_dilation(eyebox & (lum < 95) & ~ndimage.binary_erosion(iris, iterations=2), iterations=1) & eyebox
for n, m in (("arm_r", arm_r), ("arm_l", arm_l), ("sickles", sickles), ("breast_r", breast_r), ("breast_l", breast_l),
             ("cape", cape), ("tail", tail), ("leg_r", leg_r), ("leg_l", leg_l), ("phones", phones), ("visor", visor),
             ("lash", lash), ("iris", iris)):
    print("%-9s %6d px" % (n, int(m.sum())))

img = {}
# ---- the cape (the scarf's tails): what her body, arms and legs covered of it, and its top under her shoulders
cl = K.cut(final, cape)
chole = (K.behind(body_m | arm_r | arm_l | tail, cape, reach=40) & ~cape) | K.under_band(cl, body_m | arm_r | arm_l, px=30)
cl = K.rough_fill(cl, chole, radius=5)
K.save_rgba(os.path.join(WORK, "cape_rough.png"), cl)
done = []
for sd, half in (("r", XX < CLEAVE), ("l", XX >= CLEAVE)):
    K.save_mask(os.path.join(WORK, "cape_%s_hole.png" % sd), chole & half)
    cl, rep = K.apply_repaint(cl, chole & half, os.path.join(WORK, "cape_%s_fill.png" % sd))
    if rep:
        done.append(sd)
print("cape: %d px painted in; repainted: %s" % (int(chole.sum()), ", ".join(done) or "none"))
img["cape"] = cl
# ---- her tail: continued 24 px in behind her leg at its root
tl = K.cut(final, tail)
thole = K.under_band(tl, body_m, px=24)
tl = K.rough_fill(tl, thole, radius=5)
img["tail"] = tl

# ---- body: everything else; the torso behind the breasts and her sides behind the arms are painted in
body = final.copy()
body[~body_m, 3] = 0
both = breast_r | breast_l
bhole = ndimage.binary_dilation(both, iterations=2) & fa
inside = ndimage.binary_fill_holes(ndimage.binary_closing(body_m | both, iterations=8))
body, put_b = K.torso_fill(body, bhole & ~body_m, inside)
# her sides behind the arms: a 14 px band continuing her body's edge
side_hole = ndimage.binary_dilation(body_m, iterations=14) & (arm_r | arm_l) & ~ndimage.binary_dilation(sickles, iterations=2)
hole = side_hole & ~put_b
body = K.rough_fill(body, hole)
K.save_rgba(os.path.join(WORK, "body_rough.png"), body)
areas = {"chest": put_b, "side_r": side_hole & (XX < CLEAVE), "side_l": side_hole & (XX >= CLEAVE)}
done = []
for an, am in areas.items():
    K.save_mask(os.path.join(WORK, "body_hole_%s.png" % an), am)
    body, rep = K.apply_repaint(body, am, os.path.join(WORK, "body_fill_%s.png" % an))
    if rep:
        done.append(an)
print("body: %d px behind the breasts, %d behind the arms; repainted: %s" % (int(put_b.sum()), int(side_hole.sum()), ", ".join(done) or "none"))
body, n_e, sclera = K.eye_whites(body, final, iris, lash)
print("eyes: %d eye whites painted, sclera %s" % (n_e, sclera.astype(int).tolist()))
img["body"] = body
img["irides"] = K.cut(final, iris, soft=0.5)
img["lashes"] = K.cut(final, lash, soft=0.5)
img["breast_r"] = K.cut(final, breast_r)
img["breast_l"] = K.cut(final, breast_l)
img["sickle_r"] = K.cut(final, sickle_r, soft=0.6)
img["sickle_l"] = K.cut(final, sickle_l, soft=0.6)

# ---- arms: upper arm and forearm with the hand, a cap at the elbow; the upper arms sit behind the breasts
ARM_CAP = {"r": 22, "l": 22}
ARM_R = 24
for side, m in (("r", arm_r), ("l", arm_l)):
    a = K.cut(final, m)
    pieces = K.split_arm(a, ARM_CHAIN[side], ARM_CAP[side])
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

RIG_Z = {"cape": -40, "tail": -30, "body": 0, "irides": 1, "lashes": 2, "arm_l_up": 3, "arm_r_up": 3, "breast_r": 4,
         "breast_l": 5, "sickle_r": 8, "sickle_l": 8, "arm_l_fore": 9, "arm_r_fore": 11}
rects = K.write_layers(RIG, NAME, img, RIG_Z, ST)

for n, m in (("cape_m", cape), ("tail_m", tail), ("iris_m", iris), ("phones", phones), ("visor", visor), ("leg_r", leg_r),
             ("leg_l", leg_l), ("hand_r", sam("hand_r")), ("hand_l", sam("hand_l"))):
    K.save_mask(os.path.join(ST, n + ".png"), m)
for side, m, sign in (("r", breast_r, -1), ("l", breast_l, 1)):
    w, lo = K.breast_weights(m, CLEAVE, sign)
    K.save_mask(os.path.join(ST, "breast_%s_w.png" % side), w)
    K.save_mask(os.path.join(ST, "breast_%s_lo_w.png" % side), lo)

M = lambda f, **kw: dict({"type": "mask", "image": "st/%s.png" % f}, **kw)
P = lambda pts, **kw: dict({"type": "polygon", "points": pts}, **kw)
BOX = lambda x0, y0, x1, y1: P([[x0, y0], [x1, y0], [x1, y1], [x0, y1]])

# her tail: a chain of four segments from its root at her hip
TAIL_BANDS = [1330, 1400, 1470, 1540, 1660]
tail_regions, tail_bones, parent = [], [], "hips"
for k in range(4):
    y0, y1 = TAIL_BANDS[k], TAIL_BANDS[k + 1]
    nm = "tail%d" % (k + 1)
    xs_b = np.nonzero(tail[y0:y0 + 20, :])[1]
    px = int(xs_b.mean()) if len(xs_b) else 720
    tail_regions.append({"name": nm, "soft": 18, "rule": M("tail_m", within=BOX(0, y0, 1024, y1 if k < 3 else 2048))})
    tail_bones.append({"name": nm, "parent": parent, "pivot": [px, y0],
                       "spring": "hair_long;w=0.09;i=0.6;g=0.6;limit=16;k=%d" % (40 - 5 * k)})
    parent = nm
tail_regions.reverse()
# the cape: each tail of the scarf a two-bone chain from her shoulders
CAPE = [("cape_r", "cape_r2", (330, 870), (290, 1250)), ("cape_l", "cape_l2", (720, 660), (750, 1250))]

regions = [
    {"name": "face", "rule": {"type": "ellipse", "center": [504, 478], "radius": [58, 62], "feather": 12}},
    {"name": "iris", "rule": M("iris_m")},
    {"name": "phones", "soft": 6, "rule": M("phones")},
    {"name": "visor", "soft": 6, "rule": M("visor")},
    {"name": "hair_front_r", "soft": 16, "rule": P([[400, 410], [460, 410], [458, 470], [440, 540], [404, 548], [392, 470]])},
    {"name": "hair_front_l", "soft": 16, "rule": P([[550, 400], [610, 400], [620, 480], [604, 545], [566, 540], [550, 470]])},
    {"name": "head", "rule": {"type": "ellipse", "center": [506, 450], "radius": [112, 116], "feather": 18}},
    {"name": "neck", "rule": P([[470, 530], [545, 530], [552, 600], [462, 600]], feather=14)},
    {"name": "breast_r_lo", "rule": M("breast_r_lo_w", levels=True)},
    {"name": "breast_r", "rule": M("breast_r_w", levels=True)},
    {"name": "breast_l_lo", "rule": M("breast_l_lo_w", levels=True)},
    {"name": "breast_l", "rule": M("breast_l_w", levels=True)},
    {"name": "chest", "rule": P([[360, 590], [660, 590], [680, 700], [665, 830], [355, 830], [340, 700]], feather=26)},
    {"name": "torso", "rule": P([[380, 810], [640, 810], [640, 960], [380, 960]], feather=26)},
    {"name": "foot_r", "rule": M("leg_r", within=BOX(0, 1820, 512, 2048))},
    {"name": "shin_r", "rule": M("leg_r", within=BOX(0, 1560, 512, 2048))},
    {"name": "thigh_r", "rule": M("leg_r")},
    {"name": "foot_l", "rule": M("leg_l", within=BOX(512, 1820, 1024, 2048))},
    {"name": "shin_l", "rule": M("leg_l", within=BOX(512, 1560, 1024, 2048))},
    {"name": "thigh_l", "rule": M("leg_l")},
    {"name": "hips", "rule": P([[320, 940], [700, 940], [720, 1160], [300, 1160]], feather=22)},
    {"name": "weapon", "rule": M("sickle_r")},
    {"name": "weapon_l", "rule": M("sickle_l")},
    {"name": "hand_r", "rule": M("hand_r", within=M("arm_r_fore"))},
    {"name": "forearm_r", "rule": M("arm_r_fore")},
    {"name": "arm_r", "rule": M("arm_r_up")},
    {"name": "hand_l", "rule": M("hand_l", within=M("arm_l_fore"))},
    {"name": "forearm_l", "rule": M("arm_l_fore")},
    {"name": "arm_l", "rule": M("arm_l_up")},
] + [{"name": b2, "soft": 120, "rule": M("cape_m", within=BOX(0 if b2.endswith("r2") else CLEAVE, p2[1], CLEAVE if b2.endswith("r2") else 1024, 2048))}
     for _, b2, _, p2 in CAPE] + [{"name": b1, "rule": M("cape_m", within=BOX(0 if b1.endswith("_r") else CLEAVE, 0, CLEAVE if b1.endswith("_r") else 1024, 2048))}
                                 for b1, _, _, _ in CAPE] + tail_regions

JIG_LO = "jiggle;kx=170;ky=230;ky2=560;z=0.3;limit=10;tx=0.3;ty=0.45;rot=0.35;sq=0.6;kick=0"
bones = [
    {"name": "ik_foot_r", "parent": "root", "pivot": [440, 1860]},
    {"name": "ik_foot_l", "parent": "root", "pivot": [700, 1860]},
    {"name": "hips", "parent": "root", "pivot": [510, 1050]},
    {"name": "torso", "parent": "hips", "pivot": [510, 920]},
    {"name": "chest", "parent": "torso", "pivot": [510, 720]},
    {"name": "neck", "parent": "chest", "pivot": [508, 575]},
    {"name": "head", "parent": "neck", "pivot": [506, 545]},
    {"name": "face", "parent": "head", "pivot": [504, 490]},
    {"name": "iris", "parent": "face", "pivot": [504, 464]},
    {"name": "hair_front_r", "parent": "head", "pivot": [430, 420], "spring": "bangs"},
    {"name": "hair_front_l", "parent": "head", "pivot": [580, 410], "spring": "bangs"},
    {"name": "phones", "parent": "head", "pivot": [600, 445], "spring": "accessory;limit=3"},
    {"name": "visor", "parent": "head", "pivot": [492, 405], "spring": "accessory;limit=3"},
    {"name": "breast_r", "parent": "chest", "pivot": [430, 640], "spring": "jiggle;ky=190"},
    {"name": "breast_r_lo", "parent": "breast_r", "pivot": [430, 715], "spring": JIG_LO},
    {"name": "breast_l", "parent": "chest", "pivot": [592, 640], "spring": "jiggle;ky=190"},
    {"name": "breast_l_lo", "parent": "breast_l", "pivot": [592, 715], "spring": JIG_LO},
    {"name": "arm_r", "parent": "chest", "pivot": [368, 625]},
    {"name": "forearm_r", "parent": "arm_r", "pivot": [318, 860]},
    {"name": "hand_r", "parent": "forearm_r", "pivot": [262, 1075]},
    {"name": "arm_l", "parent": "chest", "pivot": [650, 625]},
    {"name": "forearm_l", "parent": "arm_l", "pivot": [700, 860]},
    {"name": "hand_l", "parent": "forearm_l", "pivot": [752, 1075]},
    # a sickle in each fist (carried): rigid on her hand, turned about the grip
    {"name": "weapon", "parent": "hand_r", "pivot": [240, 1110], "tip": [70, 1270]},
    {"name": "weapon_l", "parent": "hand_l", "pivot": [775, 1110], "tip": [950, 1270]},
    {"name": "thigh_r", "parent": "hips", "pivot": [410, 1100]},
    {"name": "shin_r", "parent": "thigh_r", "pivot": [415, 1480]},
    {"name": "foot_r", "parent": "shin_r", "pivot": [440, 1860]},
    {"name": "thigh_l", "parent": "hips", "pivot": [612, 1100]},
    {"name": "shin_l", "parent": "thigh_l", "pivot": [640, 1480]},
    {"name": "foot_l", "parent": "shin_l", "pivot": [700, 1860]},
] + [b for c1, c2, p1, p2 in CAPE for b in (
    {"name": c1, "parent": "chest", "pivot": list(p1), "spring": "cape;w=0.12;g=0.85;limit=12"},
    {"name": c2, "parent": c1, "pivot": list(p2), "spring": "cape;w=0.08;g=0.9;limit=9"})] + tail_bones

own = {"cape": ["cape"], "tail": ["tail"],
       "body": ["face", "head", "neck", "chest", "torso", "hips", "thigh", "shin", "foot", "phones", "visor", "hair_front"],
       "irides": ["iris"], "lashes": ["face"], "breast_r": ["breast_r"], "breast_l": ["breast_l"],
       "arm_r_fore": ["hand_r", "forearm_r"], "arm_l_fore": ["hand_l", "forearm_l"]}
RIGID = {"sickle_r": "weapon", "sickle_l": "weapon_l", "arm_r_up": "arm_r", "arm_l_up": "arm_l"}
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

EYES, MOUTH = (504, 464), (505, 507)
EYE_FRAMES = ("eyes_closed", "eyes_half") + (("smile",) if EYE_SMILE else ())
er = K.union([K.diff_rect(os.path.join(RIG, "variants", v + ".png"), final, EYES, half=(64, 20)) for v in EYE_FRAMES if HAS.get(v)]) if any(HAS.get(v) for v in ("eyes_closed", "eyes_half", "smile")) else None
mr = K.union([K.diff_rect(os.path.join(RIG, "variants", v + ".png"), final, MOUTH, half=(34, 22)) for v in ("mouth_open", "mouth_small", "mouth_wide", "smile") if HAS.get(v)]) if any(HAS.get(v) for v in ("mouth_open", "mouth_small", "mouth_wide", "smile")) else None
overlays = []
if er:
    overlays.append({"slot": "eyes", "bone": "face", "base": "open", "default": "open", "z": 3, "rect": er,
                     "variants": {k: "variants/%s.png" % v for k, v in (("closed", "eyes_closed"), ("half", "eyes_half"), ("smile", "smile")) if HAS.get(v) and v in EYE_FRAMES}})
if mr:
    overlays.append({"slot": "mouth", "bone": "face", "base": "default", "default": "default", "z": 3, "rect": mr,
                     "variants": {k: "variants/%s.png" % v for k, v in (("open", "mouth_open"), ("small", "mouth_small"), ("wide", "mouth_wide"), ("smile", "smile")) if HAS.get(v)}})

fmeta = json.load(open(os.path.join(SRC, "final", HERO + ".json")))
src = {
    "_doc": "Kessa's layered rig (2026-11-04): MOSS rig pose seed 205013, cut by SAM (tools/layered/kessa_rig.py, rigkit.py), "
            "hidden parts painted in. Her base look (HeroArt.LIVE).",
    "version": 2, "cell": 10, "image": NAME + ".png", "origin": fmeta.get("origin", [512, 1990]), "texel_scale": 1.0,
    "portrait": [376, 330, 260], "look_px": [10, 6],
    "meta": {"weapon": "sickle", "attack": "attack_melee", "fx_color": "#ff5a6a", "art": "moss s205013 rig pose, SAM layers",
             "idle_gestures": ["idle_spin", "idle_stretch", "idle_ears"],
             "idle": {"breath": 6.0, "noise": 2.2, "head": 1.6, "arms": 2.2, "wings": 1.8, "sway": 6.0,
                      "sway_period": 6.8, "sway_rot": 0.8, "sway_dip": 2.5, "kick_breath": 75.0, "kick_sway": 45.0,
                      "iris_x": 1.6, "iris_y": 0.5, "gaze": 0.6}},
    "body_bone": "hips", "bones": bones, "regions": regions, "layers": layers,
    "ik": [{"upper": "thigh_r", "lower": "shin_r", "target": "ik_foot_r", "foot": "foot_r", "knee_room": 10},
           {"upper": "thigh_l", "lower": "shin_l", "target": "ik_foot_l", "foot": "foot_l", "knee_room": 10}],
    "overlays": overlays,
}
json.dump(src, open(os.path.join(RIG, NAME + ".warp_src.json"), "w"), indent=1)
print("wrote", NAME, len(bones), "bones", len(regions), "regions", len(layers), "layers", len(overlays), "overlay slots")
