"""Noctaire's layered rig (2026-11-04): the SAM route (rigkit.py), modelled on mordessa_rig.py.

Reads the rig-pose final (MOSS seed 301001, art_src/_review/rigproto/noctaire/final/), the SAM masks (sam_cut.py
with noctaire_sam.json -> <work>/sam), the picked expression frames (variants.py) and the image model's repaints
of the hidden parts (fill_hidden.py -> <work>/work2/*_fill.png). Writes assets/art/heroes/noctaire/skins/live/
(her base look once built: HeroArt.LIVE).

Layers, back to front: the glitch wings, her long hair, the two holographic drapes, body (head, halo, torso,
legs), irises, lashes, the upper arms, the two breasts, the scythe planted under her right hand, the forearms.
Usage: tools/layered/noctaire_rig.py"""
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
HERO = "noctaire"
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
PICKS = {"eyes_closed": "eyes_closed_s301502", "eyes_half": "eyes_half_s301500", "mouth_open": "mouth_open_s301501",
         "mouth_small": "mouth_small_s301500", "mouth_wide": "mouth_wide_s301501", "smile": "smile_s301500"}
# (the blink needed variants.py --denoise 0.85)
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
ARM_CHAIN = {"r": [(405, 880), (355, 1050), (318, 905), (305, 850)],     # shoulder, elbow, wrist, fingertip
             "l": [(608, 880), (665, 1075), (705, 1260), (712, 1310)]}
fin3 = final[..., :3]
lum = fin3.mean(axis=2)


def arm_tube(side, radius):
    ch = ARM_CHAIN[side]
    return np.min(np.stack([K.seg_dist(ch[k], ch[k + 1]) for k in range(3)]), axis=0) <= radius


def glove(side, radius=36):
    """Her black glove's fingers round the hand (SAM's hand masks left fingertips on the body, which stayed
    behind when the arm moved): dark pixels near the wrist-to-fingertip segment."""
    ch = ARM_CHAIN[side]
    return (K.seg_dist(ch[2], ch[3]) <= radius) & (lum < 90) & fa


arm_r = K.clean((sam("arm_r") & arm_tube("r", 44)) | sam("hand_r") | glove("r", 26), close=3)
arm_l = K.clean((sam("arm_l") & arm_tube("l", 44)) | sam("hand_l") | glove("l"), close=3)
# (the halo's glitch blocks sit under the blade: SAM's scythe mask took them; they stay on her head)
scythe = K.clean(sam("scythe_shaft") | sam("scythe_head"), close=2, open_=0, keep_largest=False) & ~arm_r & ~ndimage.binary_dilation(sam("halo"), iterations=2)
CLEAVE = 513
# (SAM's right breast took her shoulder: the breasts start below the collarbones)
breast_r = K.clean(sam("breast_r") & (YY > 905), close=6, open_=3) & ~arm_r
breast_l = K.clean(sam("breast_l") & (YY > 905), close=6, open_=3) & ~arm_l
breast_r &= XX < CLEAVE
breast_l &= XX >= CLEAVE
iris = sam("iris_r") | sam("iris_l")
# her long hair: what hangs below her shoulders sways; above, it stays on her head
# (the drapes first: SAM's hair masks spread over the holographic drapes beside it)
drapes_m = K.clean(sam("drape_r"), close=3, open_=1, keep_largest=False) | K.clean(sam("drape_l"), close=3, open_=1, keep_largest=False)
hair = (K.clean(sam("hair_r"), close=3, open_=1, keep_largest=False) | K.clean(sam("hair_l"), close=3, open_=1, keep_largest=False)) \
    & (YY > 900) & ~(arm_r | arm_l | breast_r | breast_l | scythe | (drapes_m & (YY > 1190)))
wing_r = K.clean(sam("wing_r"), close=4, open_=2, keep_largest=False) & ~(arm_r | hair | scythe)
wing_l = K.clean(sam("wing_l"), close=4, open_=2, keep_largest=False) & ~(arm_l | hair)
wings = wing_r | wing_l
# the two holographic drapes from her hip buckles
coat = drapes_m & ~(arm_r | arm_l | scythe | wings) & (YY > 1190)
tail = np.zeros((H, W), bool)


def grow_edge(m, taken):
    """A part keeps the soft anti-aliased rim along its outline (SAM stops inside it)."""
    return m | (ndimage.binary_dilation(m, iterations=3) & (final[..., 3] < 250) & fa & ~taken)


taken = np.zeros((H, W), bool)
for nm_ in ("arm_r", "arm_l", "scythe", "breast_r", "breast_l", "hair", "coat", "wings"):
    m_ = grow_edge(globals()[nm_], taken)
    globals()[nm_] = m_
    taken |= m_
sword = scythe
front = arm_r | arm_l | sword | breast_r | breast_l
body_m = fa & ~(front | coat | hair | wings)
lab_b, n_b = ndimage.label(body_m)
if n_b > 1:
    sizes_b = ndimage.sum(body_m, lab_b, range(1, n_b + 1))
    stray = body_m & ~np.isin(lab_b, [k + 1 for k, v in enumerate(sizes_b) if v >= 4000])
    if stray.any():
        owners = {"coat": coat, "sword": sword, "arm_r": arm_r, "arm_l": arm_l, "hair": hair, "wings": wings}
        dist = {k: ndimage.distance_transform_edt(~m) for k, m in owners.items() if m.any()}
        dd = np.stack([dist[k] for k in dist])
        best = np.argmin(dd, axis=0)
        stray &= dd.min(axis=0) <= 40
        for i, k in enumerate(dist):
            globals()[k] = globals()[k] | (stray & (best == i))
        coat, sword, hair, wings = globals()["coat"], globals()["sword"], globals()["hair"], globals()["wings"]
        arm_r, arm_l = globals()["arm_r"], globals()["arm_l"]
        body_m &= ~stray
        print("body: %d stray px given to the drapes, scythe, arms, hair and wings" % int(stray.sum()))
    front = arm_r | arm_l | sword | breast_r | breast_l
leg_r = K.clean(sam("leg_r"), close=3, keep_largest=False) & body_m
leg_l = K.clean(sam("leg_l"), close=3, keep_largest=False) & body_m & ~leg_r
crown = K.clean(sam("halo"), close=2, open_=0, keep_largest=False) & body_m
eyebox = ((np.abs(XX - 488) <= 22) & (YY >= 736) & (YY <= 766)) | ((np.abs(XX - 543) <= 22) & (YY >= 734) & (YY <= 764))
lash = ndimage.binary_dilation(eyebox & (lum < 95) & ~ndimage.binary_erosion(iris, iterations=2), iterations=1) & eyebox
for n, m in (("arm_r", arm_r), ("arm_l", arm_l), ("scythe", sword), ("breast_r", breast_r), ("breast_l", breast_l),
             ("drapes", coat), ("hair", hair), ("wings", wings), ("leg_r", leg_r), ("leg_l", leg_l),
             ("halo", crown), ("lash", lash), ("iris", iris)):
    print("%-9s %6d px" % (n, int(m.sum())))

img = {}
# ---- wings: what the hair, arms and scythe covered of them, and their roots under her, painted in
wl = K.cut(final, wings)
whole = (K.behind(arm_r | arm_l | hair | sword, wings, reach=48) & ~wings) | K.under_band(wl, body_m | hair | arm_r | arm_l, px=40)
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
# ---- the drapes: what her legs and the scythe covered, and their tops under the hip buckles
cl = K.cut(final, coat)
chole = (K.behind(body_m | arm_l | sword | hair, coat, reach=40) & ~coat) | K.under_band(cl, body_m, px=20)
cl = K.rough_fill(cl, chole, radius=5)
K.save_rgba(os.path.join(WORK, "coat_rough.png"), cl)
done = []
for sd, half in (("r", XX < CLEAVE), ("l", XX >= CLEAVE)):
    K.save_mask(os.path.join(WORK, "coat_%s_hole.png" % sd), chole & half)
    cl, rep = K.apply_repaint(cl, chole & half, os.path.join(WORK, "coat_%s_fill.png" % sd))
    if rep:
        done.append(sd)
print("drapes: %d px painted in; repainted: %s" % (int(chole.sum()), ", ".join(done) or "none"))
img["coat"] = cl
# ---- her long hair: continued in behind her arms and body, strand by strand
bh = K.cut(final, hair)
hhole = (K.behind(arm_r | arm_l | sword, hair, reach=26) & ~hair) | K.under_band(bh, body_m | arm_r | arm_l | coat, px=16)
img["back_hair"] = K.strand_fill(bh, hhole)

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
ARM_CAP = {"r": 24, "l": 24}
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

RIG_Z = {"wings": -45, "back_hair": -40, "coat": -35, "body": 0, "irides": 1, "lashes": 2, "arm_l_up": 3,
         "arm_r_up": 3, "breast_r": 4, "breast_l": 5, "sword": 8, "arm_l_fore": 9, "arm_r_fore": 11}
rects = K.write_layers(RIG, NAME, img, RIG_Z, ST)

for n, m in (("coat_m", coat), ("hair_m", hair), ("wings_m", wings), ("iris_m", iris), ("crown", crown),
             ("leg_r", leg_r), ("leg_l", leg_l), ("hand_r", sam("hand_r")), ("hand_l", sam("hand_l"))):
    K.save_mask(os.path.join(ST, n + ".png"), m)
for side, m, sign in (("r", breast_r, -1), ("l", breast_l, 1)):
    w, lo = K.breast_weights(m, CLEAVE, sign)
    K.save_mask(os.path.join(ST, "breast_%s_w.png" % side), w)
    K.save_mask(os.path.join(ST, "breast_%s_lo_w.png" % side), lo)

M = lambda f, **kw: dict({"type": "mask", "image": "st/%s.png" % f}, **kw)
P = lambda pts, **kw: dict({"type": "polygon", "points": pts}, **kw)
BOX = lambda x0, y0, x1, y1: P([[x0, y0], [x1, y0], [x1, y1], [x0, y1]])

# her long hair: each side a three-segment lock from her shoulders
HAIR_BANDS = [900, 1150, 1400, 1750]
hair_regions, hair_bones = [], []
for lk, (x0, x1) in (("r", (0, CLEAVE)), ("l", (CLEAVE, 1024))):
    parent = "chest"
    for k in range(3):
        y0, y1 = HAIR_BANDS[k], HAIR_BANDS[k + 1]
        nm = "hair_%s%d" % (lk, k + 1)
        xs_b = np.nonzero(hair[y0:y0 + 30, x0:x1])[1]
        px = int(xs_b.mean()) + x0 if len(xs_b) else (x0 + x1) // 2
        hair_regions.append({"name": nm, "soft": 30, "rule": M("hair_m", within=BOX(x0, y0, x1, y1 if k < 2 else 2048))})
        hair_bones.append({"name": nm, "parent": parent, "pivot": [px, y0],
                           "spring": "hair_long;w=0.07;i=0.62;g=0.8;limit=12;k=%d" % (44 - 5 * k)})
        parent = nm
hair_regions.reverse()
# the drapes: each a two-bone chain from its hip buckle
COAT = [("drape_r", "drape_r2", (385, 1205), (365, 1560), (0, CLEAVE)), ("drape_l", "drape_l2", (640, 1205), (660, 1560), (CLEAVE, 1024))]

regions = [
    {"name": "face", "rule": {"type": "ellipse", "center": [515, 765], "radius": [56, 60], "feather": 12}},
    {"name": "iris", "rule": M("iris_m")},
    {"name": "halo", "soft": 8, "rule": M("crown")},
    {"name": "hair_front_r", "soft": 16, "rule": P([[440, 690], [495, 690], [492, 740], [474, 800], [440, 820], [428, 760]])},
    {"name": "hair_front_l", "soft": 16, "rule": P([[535, 690], [590, 690], [600, 760], [588, 820], [554, 800], [538, 740]])},
    {"name": "head", "rule": P([[400, 640], [630, 640], [625, 840], [405, 840]], feather=18)},
    {"name": "neck", "rule": P([[480, 815], [550, 815], [556, 870], [474, 870]], feather=14)},
    {"name": "breast_r_lo", "rule": M("breast_r_lo_w", levels=True)},
    {"name": "breast_r", "rule": M("breast_r_w", levels=True)},
    {"name": "breast_l_lo", "rule": M("breast_l_lo_w", levels=True)},
    {"name": "breast_l", "rule": M("breast_l_w", levels=True)},
    {"name": "chest", "rule": P([[370, 860], [655, 860], [665, 960], [650, 1060], [375, 1060], [360, 960]], feather=26)},
    {"name": "torso", "rule": P([[400, 1040], [625, 1040], [625, 1170], [400, 1170]], feather=26)},
    {"name": "foot_r", "rule": M("leg_r", within=BOX(0, 1850, CLEAVE, 2048))},
    {"name": "shin_r", "rule": M("leg_r", within=BOX(0, 1590, CLEAVE, 2048))},
    {"name": "thigh_r", "rule": M("leg_r")},
    {"name": "foot_l", "rule": M("leg_l", within=BOX(CLEAVE, 1850, 1024, 2048))},
    {"name": "shin_l", "rule": M("leg_l", within=BOX(CLEAVE, 1590, 1024, 2048))},
    {"name": "thigh_l", "rule": M("leg_l")},
    {"name": "hips", "rule": P([[380, 1150], [640, 1150], [650, 1320], [370, 1320]], feather=22)},
    {"name": "weapon", "rule": M("sword")},
    {"name": "hand_r", "rule": M("hand_r", within=M("arm_r_fore"))},
    {"name": "forearm_r", "rule": M("arm_r_fore")},
    {"name": "arm_r", "rule": M("arm_r_up")},
    {"name": "hand_l", "rule": M("hand_l", within=M("arm_l_fore"))},
    {"name": "forearm_l", "rule": M("arm_l_fore")},
    {"name": "arm_l", "rule": M("arm_l_up")},
    {"name": "wing_r2", "soft": 60, "rule": M("wings_m", within=BOX(0, 0, 160, 2048))},
    {"name": "wing_r", "rule": M("wings_m", within=BOX(0, 0, CLEAVE, 2048))},
    {"name": "wing_l2", "soft": 60, "rule": M("wings_m", within=BOX(860, 0, 1024, 2048))},
    {"name": "wing_l", "rule": M("wings_m", within=BOX(CLEAVE, 0, 1024, 2048))},
] + [{"name": b2, "soft": 160, "rule": M("coat_m", within=BOX(x0, p2[1], x1, 2048))} for b1, b2, p1, p2, (x0, x1) in COAT] \
  + [{"name": b1, "rule": M("coat_m", within=BOX(x0, 0, x1, 2048))} for b1, b2, p1, p2, (x0, x1) in COAT] + hair_regions

JIG_LO = "jiggle;kx=170;ky=230;ky2=560;z=0.3;limit=10;tx=0.3;ty=0.45;rot=0.35;sq=0.6;kick=0"
bones = [
    {"name": "ik_foot_r", "parent": "root", "pivot": [468, 1880]},
    {"name": "ik_foot_l", "parent": "root", "pivot": [525, 1880]},
    {"name": "hips", "parent": "root", "pivot": [513, 1230]},
    {"name": "torso", "parent": "hips", "pivot": [513, 1110]},
    {"name": "chest", "parent": "torso", "pivot": [513, 960]},
    {"name": "neck", "parent": "chest", "pivot": [515, 850]},
    {"name": "head", "parent": "neck", "pivot": [515, 820]},
    {"name": "face", "parent": "head", "pivot": [515, 775]},
    {"name": "iris", "parent": "face", "pivot": [515, 750]},
    {"name": "hair_front_r", "parent": "head", "pivot": [460, 700], "spring": "bangs"},
    {"name": "hair_front_l", "parent": "head", "pivot": [570, 700], "spring": "bangs"},
    {"name": "halo", "parent": "head", "pivot": [515, 660], "spring": "accessory;limit=6"},
    {"name": "breast_r", "parent": "chest", "pivot": [448, 915], "spring": "jiggle;ky=190"},
    {"name": "breast_r_lo", "parent": "breast_r", "pivot": [448, 990], "spring": JIG_LO},
    {"name": "breast_l", "parent": "chest", "pivot": [580, 915], "spring": "jiggle;ky=190"},
    {"name": "breast_l_lo", "parent": "breast_l", "pivot": [580, 990], "spring": JIG_LO},
    {"name": "arm_r", "parent": "chest", "pivot": [405, 880]},
    {"name": "forearm_r", "parent": "arm_r", "pivot": [355, 1050]},
    {"name": "hand_r", "parent": "forearm_r", "pivot": [318, 905]},
    {"name": "arm_l", "parent": "chest", "pivot": [608, 880]},
    {"name": "forearm_l", "parent": "arm_l", "pivot": [665, 1075]},
    {"name": "hand_l", "parent": "forearm_l", "pivot": [705, 1260]},
    # the scythe is planted on its butt with her right hand round the shaft at shoulder height (a grip)
    {"name": "weapon", "parent": "root", "pivot": [318, 1955], "tip": [300, 640], "grip": {"bone": "hand_r", "at": [312, 870]}},
    {"name": "thigh_r", "parent": "hips", "pivot": [455, 1290]},
    {"name": "shin_r", "parent": "thigh_r", "pivot": [460, 1590]},
    {"name": "foot_r", "parent": "shin_r", "pivot": [468, 1880]},
    {"name": "thigh_l", "parent": "hips", "pivot": [568, 1290]},
    {"name": "shin_l", "parent": "thigh_l", "pivot": [552, 1590]},
    {"name": "foot_l", "parent": "shin_l", "pivot": [525, 1880]},
    {"name": "wing_r", "parent": "chest", "pivot": [370, 920], "spring": "wing;w=0.05"},
    {"name": "wing_r2", "parent": "wing_r", "pivot": [160, 930], "spring": "wing;w=0.04;limit=8"},
    {"name": "wing_l", "parent": "chest", "pivot": [660, 920], "spring": "wing;w=0.05"},
    {"name": "wing_l2", "parent": "wing_l", "pivot": [860, 930], "spring": "wing;w=0.04;limit=8"},
] + [b for b1, b2, p1, p2, _ in COAT for b in (
    {"name": b1, "parent": "hips", "pivot": list(p1), "spring": "cape;w=0.1;g=0.85;limit=12"},
    {"name": b2, "parent": b1, "pivot": list(p2), "spring": "cape;w=0.07;g=0.9;limit=8"})] + hair_bones

own = {"coat": ["drape"], "back_hair": ["hair_r", "hair_l"], "wings": ["wing"],
       "body": ["face", "head", "neck", "chest", "torso", "hips", "thigh", "shin", "foot", "halo", "hair_front"],
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

EYES, MOUTH = (515, 750), (515, 787)
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
    "_doc": "Noctaire's layered rig (2026-11-04): MOSS rig pose seed 301001, cut by SAM (tools/layered/noctaire_rig.py, rigkit.py), "
            "hidden parts painted in. Her base look (HeroArt.LIVE).",
    "version": 2, "cell": 10, "image": NAME + ".png", "origin": fmeta.get("origin", [512, 1990]), "texel_scale": 1.0,
    "portrait": [385, 640, 260], "look_px": [10, 6],
    "meta": {"weapon": "scythe", "attack": "attack_melee", "fx_color": "#b48cff", "art": "moss s301001 rig pose, SAM layers",
             "idle_gestures": ["idle_hair", "idle_glitch", "idle_wings"],
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
