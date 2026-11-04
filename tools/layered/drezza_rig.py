"""Drezza's layered rig (2026-11-04): the SAM route (rigkit.py), modelled on mordessa_rig.py.

Reads the rig-pose final (MOSS seed 210001, art_src/_review/rigproto/drezza/final/), the SAM masks (sam_cut.py
with drezza_sam.json -> <work>/sam), the picked expression frames (variants.py) and the image model's repaints
of the hidden parts (fill_hidden.py -> <work>/work2/*_fill.png). Writes assets/art/heroes/drezza/skins/live/
(her base look once built: HeroArt.LIVE).

Layers, back to front: the bat wings, her fur coat (two halves hanging behind her), the ponytail, her tail, body
(head, horns, goggles, headphones, torso, legs, the deck on its strap), irises, lashes, the upper arms in their
sleeves, the two breasts, the record in her right hand, the forearms.
Usage: tools/layered/drezza_rig.py"""
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
HERO = "drezza"
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
PICKS = {"eyes_closed": "eyes_closed_s210502", "eyes_half": "eyes_half_s210501", "mouth_open": "mouth_open_s210501",
         "mouth_small": "mouth_small_s210500", "mouth_wide": "mouth_wide_s210501", "smile": "smile_s210500"}
# (the blink needed variants.py --denoise 0.85; s210503 came out a wink)
EYE_SMILE = True
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
ARM_CHAIN = {"r": [(385, 960), (320, 1112), (268, 1229), (250, 1290)],     # shoulder, elbow, wrist, fingertip
             "l": [(632, 960), (703, 1123), (762, 1241), (785, 1323)]}
fin3 = final[..., :3]
lum = fin3.mean(axis=2)


def arm_tube(side, radius):
    """Within `radius` px of the arm's bones (her fur coat sleeves: SAM could not tell them from the coat)."""
    ch = ARM_CHAIN[side]
    return np.min(np.stack([K.seg_dist(ch[k], ch[k + 1]) for k in range(3)]), axis=0) <= radius


wing_any = sam("wing_r") | sam("wing_l")
record = K.clean(sam("record"), close=2, open_=0)
arm_r = K.clean(((arm_tube("r", 50) & fa) | (sam("arm_r") & arm_tube("r", 54)) | sam("hand_r")) & ~sam("breast_r") & ~wing_any & ~record & (YY > 950), close=3)
arm_l = K.clean(((arm_tube("l", 50) & fa) | (sam("arm_l") & arm_tube("l", 54)) | sam("hand_l")) & ~sam("breast_l") & ~wing_any & ~sam("deck") & (YY > 950), close=3)
sword = record & ~sam("hand_r")
CLEAVE = 508
# (SAM's left breast took her whole chest: the breasts are the bikini cups and below, in their boxes)
breast_r = K.clean(sam("breast_r") & (YY > 972) & (XX > 380), close=6, open_=3) & ~arm_r
breast_l = K.clean(sam("breast_l") & (YY > 972) & (XX < 642) & (YY < 1105), close=6, open_=3) & ~arm_l
breast_r &= XX < CLEAVE
breast_l &= XX >= CLEAVE
iris = sam("iris_r") | sam("iris_l")
hair = K.clean(sam("ponytail"), close=3, open_=1, keep_largest=False) & (YY > 700) & (XX > 540) & ~(arm_l | breast_l)
tail = K.clean(sam("tail"), close=2, open_=0, keep_largest=False) & ~arm_l
wing_r = K.clean(sam("wing_r"), close=4, open_=2, keep_largest=False) & ~(arm_r | hair)
wing_l = K.clean(sam("wing_l"), close=4, open_=2, keep_largest=False) & ~(arm_l | hair)
wings = wing_r | wing_l
coat = (K.clean(sam("coat_r"), close=3, open_=1, keep_largest=False) | K.clean(sam("coat_l"), close=3, open_=1, keep_largest=False)) \
    & ~(arm_r | arm_l | sword | hair | tail | wings | sam("deck") | sam("leg_r") | sam("leg_l")) & (YY > 1080)


def grow_edge(m, taken):
    """A part keeps the soft anti-aliased rim along its outline (SAM stops inside it)."""
    return m | (ndimage.binary_dilation(m, iterations=3) & (final[..., 3] < 250) & fa & ~taken)


taken = np.zeros((H, W), bool)
for nm_ in ("arm_r", "arm_l", "sword", "breast_r", "breast_l", "tail", "hair", "coat", "wings"):
    m_ = grow_edge(globals()[nm_], taken)
    globals()[nm_] = m_
    taken |= m_
# the record's and her right hand's dark outline lies just outside SAM's masks: it stayed on the coat as a ghost
# when she threw the record; both take a 4 px ring of the figure round them
ring = lambda m: ndimage.binary_dilation(m, iterations=4) & fa & ~(breast_r | breast_l | arm_l)
sword = sword | (ring(sword) & ~arm_r)
arm_r = arm_r | (ring(sam("hand_r")) & ~sword)
front = arm_r | arm_l | sword | breast_r | breast_l
coat &= ~front
body_m = fa & ~(front | coat | tail | hair | wings)
lab_b, n_b = ndimage.label(body_m)
if n_b > 1:
    sizes_b = ndimage.sum(body_m, lab_b, range(1, n_b + 1))
    stray = body_m & ~np.isin(lab_b, [k + 1 for k, v in enumerate(sizes_b) if v >= 4000])
    if stray.any():
        owners = {"coat": coat, "tail": tail, "sword": sword, "arm_r": arm_r, "arm_l": arm_l, "hair": hair, "wings": wings}
        dist = {k: ndimage.distance_transform_edt(~m) for k, m in owners.items() if m.any()}
        dd = np.stack([dist[k] for k in dist])
        best = np.argmin(dd, axis=0)
        stray &= dd.min(axis=0) <= 40
        for i, k in enumerate(dist):
            globals()[k] = globals()[k] | (stray & (best == i))
        coat, tail, sword, hair, wings = globals()["coat"], globals()["tail"], globals()["sword"], globals()["hair"], globals()["wings"]
        arm_r, arm_l = globals()["arm_r"], globals()["arm_l"]
        body_m &= ~stray
        print("body: %d stray px given to the coat, tail, record, arms, hair and wings" % int(stray.sum()))
    front = arm_r | arm_l | sword | breast_r | breast_l
leg_r = K.clean(sam("leg_r"), close=3, keep_largest=False) & body_m
leg_l = K.clean(sam("leg_l"), close=3, keep_largest=False) & body_m & ~leg_r
crown = K.clean(sam("goggles"), close=2, open_=0) & body_m
deck = K.clean(sam("deck"), close=2, open_=0) & body_m
phones = K.clean(sam("phones"), close=2, open_=0) & body_m
eyebox = ((np.abs(XX - 470) <= 22) & (YY >= 781) & (YY <= 810)) | ((np.abs(XX - 530) <= 22) & (YY >= 773) & (YY <= 802))
lash = ndimage.binary_dilation(eyebox & (lum < 95) & ~ndimage.binary_erosion(iris, iterations=2), iterations=1) & eyebox
for n, m in (("arm_r", arm_r), ("arm_l", arm_l), ("record", sword), ("breast_r", breast_r), ("breast_l", breast_l),
             ("coat", coat), ("hair", hair), ("tail", tail), ("wings", wings), ("leg_r", leg_r), ("leg_l", leg_l),
             ("goggles", crown), ("deck", deck), ("lash", lash), ("iris", iris)):
    print("%-9s %6d px" % (n, int(m.sum())))

img = {}
# ---- wings: what the arms, hair and coat covered of them, and their roots under her, painted in
wl = K.cut(final, wings)
whole = (K.behind(arm_r | arm_l | hair | coat, wings, reach=48) & ~wings) | K.under_band(wl, body_m | hair | arm_r | arm_l | coat, px=40)
wl = K.rough_fill(wl, whole, radius=5)
K.save_rgba(os.path.join(WORK, "wings_rough.png"), wl)
done = []
for sd, half in (("r", XX < CLEAVE), ("l", XX >= CLEAVE)):
    K.save_mask(os.path.join(WORK, "wings_%s_hole.png" % sd), whole & half)
    wl, rep = K.apply_repaint(wl, whole & half, os.path.join(WORK, "wings_%s_fill.png" % sd))
    if rep:
        done.append(sd)
print("wings: %d px painted in; repainted: %s" % (int(whole.sum()), ", ".join(done) or "none"))
img["wings"] = wl
# ---- the coat: what her legs, the record, the arms, the deck and the tail covered of it
cl = K.cut(final, coat)
chole = (K.behind(body_m | arm_r | arm_l | sword | tail, coat, reach=60) & ~coat) | K.under_band(cl, body_m | arm_r | arm_l, px=30)
# the record is 190 px across: the coat behind it needs a wider reach (its own repaint: coat_rec_fill.png)
rec_hole = K.behind(sword, coat, reach=110) & ~coat & ~chole
chole |= rec_hole
cl = K.rough_fill(cl, chole, radius=5)
K.save_rgba(os.path.join(WORK, "coat_rough.png"), cl)
K.save_mask(os.path.join(WORK, "coat_rec_hole.png"), rec_hole)
done = []
for sd, half in (("r", XX < CLEAVE), ("l", XX >= CLEAVE)):
    K.save_mask(os.path.join(WORK, "coat_%s_hole.png" % sd), chole & half)
    cl, rep = K.apply_repaint(cl, chole & half, os.path.join(WORK, "coat_%s_fill.png" % sd))
    if rep:
        done.append(sd)
cl, rep = K.apply_repaint(cl, rec_hole, os.path.join(WORK, "coat_rec_fill.png"))
if rep:
    done.append("behind the record")
print("coat: %d px painted in (%d behind the record); repainted: %s" % (int(chole.sum()), int(rec_hole.sum()), ", ".join(done) or "none"))
img["coat"] = cl
# ---- the ponytail: continued in behind her shoulder, strand by strand
bh = K.cut(final, hair)
hhole = (K.behind(arm_l, hair, reach=26) & ~hair) | K.under_band(bh, body_m | arm_l, px=16)
img["back_hair"] = K.strand_fill(bh, hhole)
# ---- her tail: continued in behind the coat at its root
tl = K.cut(final, tail)
img["tail"] = K.rough_fill(tl, K.under_band(tl, coat | body_m, px=20), radius=4)

# ---- body: everything else; the torso behind the breasts and her sides behind the arms are painted in
body = final.copy()
body[~body_m, 3] = 0
both = breast_r | breast_l
bhole = ndimage.binary_dilation(both, iterations=2) & fa
inside = ndimage.binary_fill_holes(ndimage.binary_closing(body_m | both, iterations=8))
body, put_b = K.torso_fill(body, bhole & ~body_m, inside)
side_hole = ndimage.binary_dilation(body_m, iterations=14) & (arm_r | arm_l) & ~ndimage.binary_dilation(sword, iterations=2)
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
img["sword"] = K.cut(final, sword, soft=0.6)

# ---- arms: upper arm and forearm with the hand, a cap at the elbow; the upper arms sit behind the breasts
ARM_CAP = {"r": 28, "l": 28}
ARM_R = 28
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

RIG_Z = {"wings": -45, "coat": -40, "back_hair": -35, "tail": -30, "body": 0, "irides": 1, "lashes": 2, "arm_l_up": 3,
         "arm_r_up": 3, "breast_r": 4, "breast_l": 5, "sword": 8, "arm_l_fore": 9, "arm_r_fore": 11}
rects = K.write_layers(RIG, NAME, img, RIG_Z, ST)

for n, m in (("coat_m", coat), ("hair_m", hair), ("tail_m", tail), ("wings_m", wings), ("iris_m", iris), ("crown", crown),
             ("deck", deck), ("phones", phones), ("leg_r", leg_r), ("leg_l", leg_l), ("hand_r", sam("hand_r")), ("hand_l", sam("hand_l"))):
    K.save_mask(os.path.join(ST, n + ".png"), m)
for side, m, sign in (("r", breast_r, -1), ("l", breast_l, 1)):
    w, lo = K.breast_weights(m, CLEAVE, sign)
    K.save_mask(os.path.join(ST, "breast_%s_w.png" % side), w)
    K.save_mask(os.path.join(ST, "breast_%s_lo_w.png" % side), lo)

M = lambda f, **kw: dict({"type": "mask", "image": "st/%s.png" % f}, **kw)
P = lambda pts, **kw: dict({"type": "polygon", "points": pts}, **kw)
BOX = lambda x0, y0, x1, y1: P([[x0, y0], [x1, y0], [x1, y1], [x0, y1]])

# her tail: a chain of three segments from where it comes out of the coat
TAIL_X = [770, 810, 850, 920]
tail_regions, tail_bones, parent = [], [], "hips"
for k in range(3):
    x0, x1 = TAIL_X[k], TAIL_X[k + 1]
    nm = "tail%d" % (k + 1)
    ys_b = np.nonzero(tail[:, x0:x0 + 10])[0]
    py = int(ys_b.mean()) if len(ys_b) else 1460
    tail_regions.append({"name": nm, "soft": 14, "rule": M("tail_m", within=BOX(x0, 0, x1 if k < 2 else 1024, 2048))})
    tail_bones.append({"name": nm, "parent": parent, "pivot": [x0, py],
                       "spring": "hair_long;w=0.09;i=0.6;g=0.4;limit=16;k=%d" % (40 - 6 * k)})
    parent = nm
tail_regions.reverse()
# the ponytail: a three-segment lock from the top of her head
PONY = [(560, 700), (610, 800), (640, 900)]
COAT = [("coat_r", "coat_r2", (330, 1090), (240, 1500), (0, CLEAVE)), ("coat_l", "coat_l2", (690, 1090), (780, 1500), (CLEAVE, 1024))]

regions = [
    {"name": "face", "rule": {"type": "ellipse", "center": [500, 805], "radius": [56, 60], "feather": 12}},
    {"name": "iris", "rule": M("iris_m")},
    {"name": "crown", "soft": 6, "rule": M("crown")},
    {"name": "phones", "soft": 6, "rule": M("phones")},
    {"name": "deck", "soft": 6, "rule": M("deck")},
    {"name": "hair_front_r", "soft": 16, "rule": P([[420, 730], [475, 730], [472, 780], [456, 850], [420, 860], [408, 800]])},
    {"name": "hair_front_l", "soft": 16, "rule": P([[525, 730], [580, 730], [590, 800], [576, 860], [542, 850], [528, 780]])},
    {"name": "head", "rule": P([[390, 610], [620, 610], [615, 880], [395, 880]], feather=18)},
    {"name": "neck", "rule": P([[465, 860], [540, 860], [548, 960], [458, 960]], feather=14)},
    {"name": "breast_r_lo", "rule": M("breast_r_lo_w", levels=True)},
    {"name": "breast_r", "rule": M("breast_r_w", levels=True)},
    {"name": "breast_l_lo", "rule": M("breast_l_lo_w", levels=True)},
    {"name": "breast_l", "rule": M("breast_l_w", levels=True)},
    {"name": "chest", "rule": P([[355, 950], [665, 950], [675, 1050], [650, 1120], [365, 1120], [345, 1050]], feather=26)},
    {"name": "torso", "rule": P([[395, 1100], [620, 1100], [620, 1230], [395, 1230]], feather=26)},
    {"name": "foot_r", "rule": M("leg_r", within=BOX(0, 1860, CLEAVE, 2048))},
    {"name": "shin_r", "rule": M("leg_r", within=BOX(0, 1600, CLEAVE, 2048))},
    {"name": "thigh_r", "rule": M("leg_r")},
    {"name": "foot_l", "rule": M("leg_l", within=BOX(CLEAVE, 1860, 1024, 2048))},
    {"name": "shin_l", "rule": M("leg_l", within=BOX(CLEAVE, 1600, 1024, 2048))},
    {"name": "thigh_l", "rule": M("leg_l")},
    {"name": "hips", "rule": P([[360, 1210], [650, 1210], [660, 1380], [350, 1380]], feather=22)},
    {"name": "weapon", "rule": M("sword")},
    {"name": "hand_r", "rule": M("hand_r", within=M("arm_r_fore"))},
    {"name": "forearm_r", "rule": M("arm_r_fore")},
    {"name": "arm_r", "rule": M("arm_r_up")},
    {"name": "hand_l", "rule": M("hand_l", within=M("arm_l_fore"))},
    {"name": "forearm_l", "rule": M("arm_l_fore")},
    {"name": "arm_l", "rule": M("arm_l_up")},
    {"name": "wing_r2", "soft": 60, "rule": M("wings_m", within=BOX(0, 0, 170, 2048))},
    {"name": "wing_r", "rule": M("wings_m", within=BOX(0, 0, CLEAVE, 2048))},
    {"name": "wing_l2", "soft": 60, "rule": M("wings_m", within=BOX(850, 0, 1024, 2048))},
    {"name": "wing_l", "rule": M("wings_m", within=BOX(CLEAVE, 0, 1024, 2048))},
    {"name": "pony3", "soft": 40, "rule": M("hair_m", within=BOX(0, PONY[2][1], 1024, 2048))},
    {"name": "pony2", "soft": 40, "rule": M("hair_m", within=BOX(0, PONY[1][1], 1024, 2048))},
    {"name": "pony1", "rule": M("hair_m")},
] + [{"name": b2, "soft": 160, "rule": M("coat_m", within=BOX(x0, p2[1], x1, 2048))} for b1, b2, p1, p2, (x0, x1) in COAT] \
  + [{"name": b1, "rule": M("coat_m", within=BOX(x0, 0, x1, 2048))} for b1, b2, p1, p2, (x0, x1) in COAT] + tail_regions

JIG_LO = "jiggle;kx=170;ky=230;ky2=560;z=0.3;limit=10;tx=0.3;ty=0.45;rot=0.35;sq=0.6;kick=0"
bones = [
    {"name": "ik_foot_r", "parent": "root", "pivot": [425, 1890]},
    {"name": "ik_foot_l", "parent": "root", "pivot": [640, 1890]},
    {"name": "hips", "parent": "root", "pivot": [508, 1290]},
    {"name": "torso", "parent": "hips", "pivot": [508, 1170]},
    {"name": "chest", "parent": "torso", "pivot": [508, 1040]},
    {"name": "neck", "parent": "chest", "pivot": [503, 950]},
    {"name": "head", "parent": "neck", "pivot": [500, 900]},
    {"name": "face", "parent": "head", "pivot": [500, 815]},
    {"name": "iris", "parent": "face", "pivot": [500, 791]},
    {"name": "hair_front_r", "parent": "head", "pivot": [445, 740], "spring": "bangs"},
    {"name": "hair_front_l", "parent": "head", "pivot": [555, 740], "spring": "bangs"},
    {"name": "crown", "parent": "head", "pivot": [490, 690], "spring": "accessory;limit=3"},
    {"name": "phones", "parent": "neck", "pivot": [500, 915], "spring": "accessory;limit=5"},
    {"name": "deck", "parent": "hips", "pivot": [660, 1215], "spring": "accessory;limit=9"},
    {"name": "pony1", "parent": "head", "pivot": list(PONY[0]), "spring": "hair_mass;g=0.85"},
    {"name": "pony2", "parent": "pony1", "pivot": list(PONY[1]), "spring": "hair_long;w=0.07;i=0.62;g=0.8;limit=13;k=40"},
    {"name": "pony3", "parent": "pony2", "pivot": list(PONY[2]), "spring": "hair_long;w=0.07;i=0.62;g=0.8;limit=15;k=34"},
    {"name": "breast_r", "parent": "chest", "pivot": [445, 985], "spring": "jiggle;ky=190"},
    {"name": "breast_r_lo", "parent": "breast_r", "pivot": [445, 1050], "spring": JIG_LO},
    {"name": "breast_l", "parent": "chest", "pivot": [570, 985], "spring": "jiggle;ky=190"},
    {"name": "breast_l_lo", "parent": "breast_l", "pivot": [570, 1050], "spring": JIG_LO},
    {"name": "arm_r", "parent": "chest", "pivot": [385, 960]},
    {"name": "forearm_r", "parent": "arm_r", "pivot": [320, 1112]},
    {"name": "hand_r", "parent": "forearm_r", "pivot": [268, 1229]},
    {"name": "arm_l", "parent": "chest", "pivot": [632, 960]},
    {"name": "forearm_l", "parent": "arm_l", "pivot": [703, 1123]},
    {"name": "hand_l", "parent": "forearm_l", "pivot": [762, 1241]},
    # the record rides in her right hand (carried): rigid on her hand, turned about the grip
    {"name": "weapon", "parent": "hand_r", "pivot": [250, 1300], "tip": [256, 1480]},
    {"name": "thigh_r", "parent": "hips", "pivot": [420, 1340]},
    {"name": "shin_r", "parent": "thigh_r", "pivot": [418, 1620]},
    {"name": "foot_r", "parent": "shin_r", "pivot": [425, 1890]},
    {"name": "thigh_l", "parent": "hips", "pivot": [600, 1340]},
    {"name": "shin_l", "parent": "thigh_l", "pivot": [625, 1620]},
    {"name": "foot_l", "parent": "shin_l", "pivot": [640, 1890]},
    {"name": "wing_r", "parent": "chest", "pivot": [345, 1000], "spring": "wing;w=0.05"},
    {"name": "wing_r2", "parent": "wing_r", "pivot": [170, 960], "spring": "wing;w=0.04;limit=8"},
    {"name": "wing_l", "parent": "chest", "pivot": [675, 1000], "spring": "wing;w=0.05"},
    {"name": "wing_l2", "parent": "wing_l", "pivot": [850, 960], "spring": "wing;w=0.04;limit=8"},
] + [b for b1, b2, p1, p2, _ in COAT for b in (
    {"name": b1, "parent": "chest", "pivot": list(p1), "spring": "cape;w=0.1;g=0.85;limit=10"},
    {"name": b2, "parent": b1, "pivot": list(p2), "spring": "cape;w=0.07;g=0.9;limit=8"})] + tail_bones

own = {"coat": ["coat"], "back_hair": ["pony"], "tail": ["tail"], "wings": ["wing"],
       "body": ["face", "head", "neck", "chest", "torso", "hips", "thigh", "shin", "foot", "crown", "phones", "deck", "hair_front"],
       "irides": ["iris"], "lashes": ["face"], "breast_r": ["breast_r"], "breast_l": ["breast_l"],
       "arm_r_fore": ["hand_r", "forearm_r"], "arm_l_fore": ["hand_l", "forearm_l"]}
RIGID = {"sword": "weapon", "arm_r_up": "arm_r", "arm_l_up": "arm_l"}
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

EYES, MOUTH = (500, 791), (510, 830)
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
    "_doc": "Drezza's layered rig (2026-11-04): MOSS rig pose seed 210001, cut by SAM (tools/layered/drezza_rig.py, rigkit.py), "
            "hidden parts painted in. Her base look (HeroArt.LIVE).",
    "version": 2, "cell": 10, "image": NAME + ".png", "origin": fmeta.get("origin", [512, 1990]), "texel_scale": 1.0,
    "portrait": [370, 680, 260], "look_px": [10, 6],
    "meta": {"weapon": "record", "attack": "attack_ranged", "fx_color": "#ff4fb8", "art": "moss s210001 rig pose, SAM layers",
             "idle_gestures": ["idle_beat", "idle_scratch", "idle_wings"],
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
