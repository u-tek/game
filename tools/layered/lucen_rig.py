"""Lucen's layered rig (2026-11-04): the SAM route (rigkit.py), modelled on uriela_rig.py.

Reads the rig-pose final (MOSS seed 304000, art_src/_review/rigproto/lucen/final/), the SAM masks (sam_cut.py
with lucen_sam.json -> <work>/sam), the picked expression frames (variants.py) and the image model's repaints of
the hidden parts (fill_hidden.py -> <work>/work2/*_fill.png). Writes assets/art/heroes/lucen/skins/live/ (her
base look once built: HeroArt.LIVE).

Layers, back to front: wings (one white, one black), back hair (the white half and the black half), body (head,
torso, legs), irises, lashes, the upper arms, the two breasts, the rapier (carried in her right hand), the
forearms with the hands.
Usage: tools/layered/lucen_rig.py"""
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
HERO = "lucen"
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
PICKS = {"eyes_closed": "eyes_closed_s304503", "eyes_half": "eyes_half_s304500", "mouth_open": "mouth_open_s304501",
         "mouth_small": "mouth_small_s304500", "mouth_wide": "mouth_wide_s304501", "smile": "smile_s304501"}
# (the blink needed variants.py --denoise 0.85, as Uriela's: the first tries only narrowed her eyes)
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
ARM_CHAIN = {"r": [(400, 840), (335, 1060), (290, 1170), (270, 1240)],     # shoulder, elbow, wrist, fingertip
             "l": [(605, 840), (650, 1060), (665, 1220), (685, 1300)]}
fin3 = final[..., :3]
lum = fin3.mean(axis=2)


def arm_tube(side, radius):
    """Within `radius` px of the arm's bones: SAM's arm masks reached the wing's pearls beside the sleeve and the
    black hair strands beside her bare arm."""
    ch = ARM_CHAIN[side]
    return np.min(np.stack([K.seg_dist(ch[k], ch[k + 1]) for k in range(3)]), axis=0) <= radius


arm_r_raw = sam("arm_r") | sam("hand_r")
arm_l_raw = sam("arm_l") | sam("hand_l")
arm_r = K.clean((sam("arm_r") & arm_tube("r", 36)) | sam("hand_r"), close=3)
arm_l = K.clean((sam("arm_l") & arm_tube("l", 30) & (lum > 80)) | sam("hand_l"), close=3)     # her arm is bare: no black in it
left_over = (arm_r_raw & ~arm_r) | (arm_l_raw & ~arm_l)
rapier = K.clean(sam("rapier") | sam("guard"), close=2, open_=0, keep_largest=False) & ~arm_r     # her fist splits it
breast_r = K.clean(sam("breast_r"), close=6, open_=3) & ~arm_r
breast_l = K.clean(sam("breast_l"), close=6, open_=3) & ~arm_l
CLEAVE = 510
breast_r &= XX < CLEAVE
breast_l &= XX >= CLEAVE
iris = sam("iris_r") | sam("iris_l")
hair_w = K.clean(sam("hair_w"), close=3, open_=1, keep_largest=False) & ~(arm_r | breast_r)
# the black strands beside her bare arm (the arm mask's left-overs) are her hair
hair_b = (K.clean(sam("hair_b"), close=3, open_=1, keep_largest=False) | (left_over & (lum < 80) & (XX >= CLEAVE))) & ~(arm_l | breast_l)
# the hair that falls behind her shoulders (below her jaw) is the back hair; what frames her face stays on her head
back = YY > 770
hair = (hair_w | hair_b) & back
wing_r = K.clean(sam("wing_r") | (left_over & (XX < CLEAVE) & ndimage.binary_dilation(sam("wing_r"), iterations=6)), close=4, open_=2,
                 keep_largest=False) & ~(arm_r | hair)
wing_l = K.clean(sam("wing_l"), close=4, open_=2, keep_largest=False) & ~(arm_l | hair)
wings = wing_r | wing_l


def grow_edge(m, taken):
    """A part keeps the soft anti-aliased rim along its outline (SAM stops inside it)."""
    return m | (ndimage.binary_dilation(m, iterations=3) & (final[..., 3] < 250) & fa & ~taken)


taken = np.zeros((H, W), bool)
for nm_ in ("arm_r", "arm_l", "rapier", "breast_r", "breast_l", "hair", "wings"):
    m_ = grow_edge(globals()[nm_], taken)
    globals()[nm_] = m_
    taken |= m_
front = arm_r | arm_l | rapier | breast_r | breast_l
body_m = fa & ~(front | wings | hair)
lab_b, n_b = ndimage.label(body_m)
if n_b > 1:
    sizes_b = ndimage.sum(body_m, lab_b, range(1, n_b + 1))
    stray = body_m & ~np.isin(lab_b, [k + 1 for k, v in enumerate(sizes_b) if v >= 4000])
    if stray.any():
        owners = {"wings": wings, "rapier": rapier, "hair": hair}
        dist = {k: ndimage.distance_transform_edt(~m) for k, m in owners.items() if m.any()}
        dd = np.stack([dist[k] for k in dist])
        best = np.argmin(dd, axis=0)
        stray &= dd.min(axis=0) <= 30         # specks far from all of them (a strap's end, a fingertip) stay
        for i, k in enumerate(dist):
            globals()[k] = globals()[k] | (stray & (best == i))
        wings, rapier, hair = globals()["wings"], globals()["rapier"], globals()["hair"]
        body_m &= ~stray
        print("body: %d stray px given to the wings, rapier and hair" % int(stray.sum()))
    front = arm_r | arm_l | rapier | breast_r | breast_l
leg_r = K.clean(sam("leg_r"), close=3, keep_largest=False) & body_m
leg_l = K.clean(sam("leg_l") | sam("shoe_l"), close=3, keep_largest=False) & body_m & ~leg_r
glasses = K.clean(sam("glasses"), close=2, open_=0) & body_m
# the lashes: the dark lid lines over each eye (the irises slide under them)
eyebox = ((np.abs(XX - 474) <= 22) & (YY >= 703) & (YY <= 731)) | ((np.abs(XX - 536) <= 22) & (YY >= 696) & (YY <= 724))
lash = ndimage.binary_dilation(eyebox & (lum < 95) & ~ndimage.binary_erosion(iris, iterations=2), iterations=1) & eyebox
for n, m in (("arm_r", arm_r), ("arm_l", arm_l), ("rapier", rapier), ("breast_r", breast_r), ("breast_l", breast_l),
             ("wings", wings), ("hair", hair), ("leg_r", leg_r), ("leg_l", leg_l), ("glasses", glasses), ("lash", lash),
             ("iris", iris)):
    print("%-9s %6d px" % (n, int(m.sum())))

img = {}
# ---- back hair: both halves, continued 16 px under her shoulders and behind her arms, strand by strand
bh = K.cut(final, hair)
hhole = (K.behind(arm_r | arm_l, hair, reach=26) & ~hair) | K.under_band(bh, body_m | arm_r | arm_l, px=16)
wh = K.strand_fill(bh, hhole & (XX < CLEAVE), warm=None)
bk = K.strand_fill(bh, hhole & (XX >= CLEAVE), warm=None)
bh = np.where((XX < CLEAVE)[..., None], wh, bk)
print("back hair: %d px painted in" % int(hhole.sum()))
img["back_hair"] = bh
# ---- wings: what the arms and hair covered of them, and their roots under her, painted in
wl = K.cut(final, wings)
whole = (K.behind(arm_r | arm_l | hair, wings, reach=48) & ~wings) | K.under_band(wl, body_m | hair | arm_r | arm_l, px=40)
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

# ---- body: everything else; the torso behind the breasts and her sides behind the arms are painted in
body = final.copy()
body[~body_m, 3] = 0
both = breast_r | breast_l
bhole = ndimage.binary_dilation(both, iterations=2) & fa
inside = ndimage.binary_fill_holes(ndimage.binary_closing(body_m | both, iterations=8))
body, put_b = K.torso_fill(body, bhole & ~body_m, inside)
# her sides behind the arms: only a 14 px band continuing her body's edge (the repaints of the whole gap behind
# an arm painted a ghost of the sleeve into it; the gap beyond her side is the field, as it would be)
side_hole = ndimage.binary_dilation(body_m, iterations=14) & (arm_r | arm_l) & ~ndimage.binary_dilation(rapier, iterations=2)
blade_hole = K.behind(rapier, body_m, reach=30) & ~body_m & (YY > 1250)
hole = (side_hole | blade_hole) & ~put_b
body = K.rough_fill(body, hole)
K.save_rgba(os.path.join(WORK, "body_rough.png"), body)
areas = {"chest": put_b, "side_r": side_hole & (XX < CLEAVE), "side_l": side_hole & (XX >= CLEAVE), "blade": blade_hole & ~put_b & ~side_hole}
done = []
for an, am in areas.items():
    K.save_mask(os.path.join(WORK, "body_hole_%s.png" % an), am)
    body, rep = K.apply_repaint(body, am, os.path.join(WORK, "body_fill_%s.png" % an))
    if rep:
        done.append(an)
print("body: %d px behind the breasts, %d behind the arms, %d behind the blade; repainted: %s" % (
    int(put_b.sum()), int(side_hole.sum()), int(blade_hole.sum()), ", ".join(done) or "none"))
body, n_e, sclera = K.eye_whites(body, final, iris, lash)
print("eyes: %d eye whites painted, sclera %s" % (n_e, sclera.astype(int).tolist()))
img["body"] = body
img["irides"] = K.cut(final, iris, soft=0.5)
img["lashes"] = K.cut(final, lash, soft=0.5)
img["breast_r"] = K.cut(final, breast_r)
img["breast_l"] = K.cut(final, breast_l)
img["rapier"] = K.cut(final, rapier, soft=0.6)

# ---- arms: upper arm and forearm with the hand, a cap at the elbow; the upper arms sit behind the breasts
ARM_CAP = {"r": 22, "l": 20}
ARM_R = 22
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

RIG_Z = {"wings": -40, "back_hair": -30, "body": 0, "irides": 1, "lashes": 2, "arm_l_up": 3, "arm_r_up": 3, "breast_r": 4,
         "breast_l": 5, "rapier": 8, "arm_l_fore": 9, "arm_r_fore": 11}
rects = K.write_layers(RIG, NAME, img, RIG_Z, ST)

for n, m in (("hair", hair), ("wings_m", wings), ("iris_m", iris), ("glasses", glasses), ("leg_r", leg_r), ("leg_l", leg_l),
             ("hand_r", sam("hand_r")), ("hand_l", sam("hand_l"))):
    K.save_mask(os.path.join(ST, n + ".png"), m)
for side, m, sign in (("r", breast_r, -1), ("l", breast_l, 1)):
    w, lo = K.breast_weights(m, CLEAVE, sign)
    K.save_mask(os.path.join(ST, "breast_%s_w.png" % side), w)
    K.save_mask(os.path.join(ST, "breast_%s_lo_w.png" % side), lo)

M = lambda f, **kw: dict({"type": "mask", "image": "st/%s.png" % f}, **kw)
P = lambda pts, **kw: dict({"type": "polygon", "points": pts}, **kw)
BOX = lambda x0, y0, x1, y1: P([[x0, y0], [x1, y0], [x1, y1], [x0, y1]])

# her hair: the white half (her right) and the black half (her left), each a chain of three segments
HAIR_BANDS = [770, 870, 960, 1070]
hair_regions, hair_bones = [], []
for lk, (x0, x1) in (("w", (0, CLEAVE)), ("b", (CLEAVE, 1024))):
    parent = "hair_back"
    for k in range(3):
        y0, y1 = HAIR_BANDS[k], HAIR_BANDS[k + 1]
        nm = "hair_%s%d" % (lk, k + 1)
        xs_b = np.nonzero(hair[y0:y0 + 30, x0:x1])[1]
        px = int(xs_b.mean()) + x0 if len(xs_b) else (x0 + x1) // 2
        hair_regions.append({"name": nm, "soft": 22, "rule": M("hair", within=BOX(x0, y0, x1, y1 if k < 2 else 2048))})
        hair_bones.append({"name": nm, "parent": parent, "pivot": [px, y0],
                           "spring": "hair_long;w=0.07;i=0.62;g=0.8;limit=13;k=%d" % (46 - 5 * k)})
        parent = nm
hair_regions.reverse()

regions = [
    {"name": "face", "rule": {"type": "ellipse", "center": [505, 730], "radius": [60, 66], "feather": 12}},
    {"name": "iris", "rule": M("iris_m")},
    {"name": "glasses", "soft": 6, "rule": M("glasses")},
    {"name": "earring_r", "soft": 6, "rule": BOX(436, 734, 466, 800)},
    {"name": "earring_l", "soft": 6, "rule": BOX(550, 730, 580, 796)},
    {"name": "hair_front_r", "soft": 16, "rule": P([[410, 640], [470, 640], [468, 700], [446, 780], [410, 790], [396, 720]])},
    {"name": "hair_front_l", "soft": 16, "rule": P([[540, 630], [606, 630], [618, 720], [604, 790], [566, 780], [544, 700]])},
    {"name": "head", "rule": {"type": "ellipse", "center": [508, 690], "radius": [110, 120], "feather": 18}},
    {"name": "neck", "rule": P([[478, 770], [548, 770], [556, 830], [470, 830]], feather=14)},
    {"name": "breast_r_lo", "rule": M("breast_r_lo_w", levels=True)},
    {"name": "breast_r", "rule": M("breast_r_w", levels=True)},
    {"name": "breast_l_lo", "rule": M("breast_l_lo_w", levels=True)},
    {"name": "breast_l", "rule": M("breast_l_w", levels=True)},
    {"name": "chest", "rule": P([[390, 820], [625, 820], [645, 920], [630, 1010], [385, 1010], [370, 920]], feather=26)},
    {"name": "torso", "rule": P([[395, 990], [625, 990], [620, 1130], [400, 1130]], feather=26)},
    {"name": "foot_r", "rule": M("leg_r", within=BOX(0, 1810, 512, 2048))},
    {"name": "shin_r", "rule": M("leg_r", within=BOX(0, 1545, 512, 2048))},
    {"name": "thigh_r", "rule": M("leg_r")},
    {"name": "foot_l", "rule": M("leg_l", within=BOX(512, 1760, 1024, 2048))},
    {"name": "shin_l", "rule": M("leg_l", within=BOX(512, 1510, 1024, 2048))},
    {"name": "thigh_l", "rule": M("leg_l")},
    {"name": "hips", "rule": P([[360, 1110], [650, 1110], [670, 1290], [345, 1290]], feather=22)},
    {"name": "weapon", "rule": M("rapier")},
    {"name": "hand_r", "rule": M("hand_r", within=M("arm_r_fore"))},
    {"name": "forearm_r", "rule": M("arm_r_fore")},
    {"name": "arm_r", "rule": M("arm_r_up")},
    {"name": "hand_l", "rule": M("hand_l", within=M("arm_l_fore"))},
    {"name": "forearm_l", "rule": M("arm_l_fore")},
    {"name": "arm_l", "rule": M("arm_l_up")},
    {"name": "wing_r2", "soft": 60, "rule": M("wings_m", within=BOX(0, 0, 210, 2048))},
    {"name": "wing_r", "rule": M("wings_m", within=BOX(0, 0, CLEAVE, 2048))},
    {"name": "wing_l2", "soft": 60, "rule": M("wings_m", within=BOX(810, 0, 1024, 2048))},
    {"name": "wing_l", "rule": M("wings_m", within=BOX(CLEAVE, 0, 1024, 2048))},
] + hair_regions + [
    {"name": "hair_back", "rule": M("hair")},
]

JIG_LO = "jiggle;kx=170;ky=230;ky2=560;z=0.3;limit=10;tx=0.3;ty=0.45;rot=0.35;sq=0.6;kick=0"
bones = [
    {"name": "ik_foot_r", "parent": "root", "pivot": [476, 1850]},
    {"name": "ik_foot_l", "parent": "root", "pivot": [701, 1787]},
    {"name": "hips", "parent": "root", "pivot": [500, 1180]},
    {"name": "torso", "parent": "hips", "pivot": [503, 1070]},
    {"name": "chest", "parent": "torso", "pivot": [507, 940]},
    {"name": "neck", "parent": "chest", "pivot": [510, 805]},
    {"name": "head", "parent": "neck", "pivot": [510, 780]},
    {"name": "face", "parent": "head", "pivot": [505, 740]},
    {"name": "iris", "parent": "face", "pivot": [505, 714]},
    {"name": "hair_front_r", "parent": "head", "pivot": [440, 660], "spring": "bangs"},
    {"name": "hair_front_l", "parent": "head", "pivot": [574, 650], "spring": "bangs"},
    {"name": "hair_back", "parent": "head", "pivot": [510, 640], "spring": "hair_mass;g=0.85"},
] + hair_bones + [
    {"name": "glasses", "parent": "head", "pivot": [492, 648], "spring": "accessory;limit=4"},
    {"name": "earring_r", "parent": "head", "pivot": [451, 738], "spring": "accessory;limit=12"},
    {"name": "earring_l", "parent": "head", "pivot": [565, 734], "spring": "accessory;limit=12"},
    {"name": "breast_r", "parent": "chest", "pivot": [438, 868], "spring": "jiggle;ky=190"},
    {"name": "breast_r_lo", "parent": "breast_r", "pivot": [438, 930], "spring": JIG_LO},
    {"name": "breast_l", "parent": "chest", "pivot": [582, 868], "spring": "jiggle;ky=190"},
    {"name": "breast_l_lo", "parent": "breast_l", "pivot": [582, 930], "spring": JIG_LO},
    {"name": "arm_r", "parent": "chest", "pivot": [400, 840]},
    {"name": "forearm_r", "parent": "arm_r", "pivot": [335, 1060]},
    {"name": "hand_r", "parent": "forearm_r", "pivot": [290, 1170]},
    {"name": "arm_l", "parent": "chest", "pivot": [605, 840]},
    {"name": "forearm_l", "parent": "arm_l", "pivot": [650, 1060]},
    {"name": "hand_l", "parent": "forearm_l", "pivot": [665, 1220]},
    # the rapier hangs from her fist (carried, not planted): rigid on her hand, turned about the grip
    {"name": "weapon", "parent": "hand_r", "pivot": [282, 1240], "tip": [382, 1962]},
    {"name": "thigh_r", "parent": "hips", "pivot": [430, 1230]},
    {"name": "shin_r", "parent": "thigh_r", "pivot": [445, 1555]},
    {"name": "foot_r", "parent": "shin_r", "pivot": [476, 1850]},
    {"name": "thigh_l", "parent": "hips", "pivot": [582, 1230]},
    {"name": "shin_l", "parent": "thigh_l", "pivot": [626, 1520]},
    {"name": "foot_l", "parent": "shin_l", "pivot": [701, 1787]},
    {"name": "wing_r", "parent": "chest", "pivot": [392, 868], "spring": "wing;w=0.05"},
    {"name": "wing_r2", "parent": "wing_r", "pivot": [210, 830], "spring": "wing;w=0.04;limit=8"},
    {"name": "wing_l", "parent": "chest", "pivot": [640, 862], "spring": "wing;w=0.05"},
    {"name": "wing_l2", "parent": "wing_l", "pivot": [810, 826], "spring": "wing;w=0.04;limit=8"},
]

own = {"back_hair": ["hair_back", "hair_w", "hair_b"], "wings": ["wing"],
       "body": ["face", "head", "neck", "chest", "torso", "hips", "thigh", "shin", "foot", "glasses", "earring", "hair_front"],
       "irides": ["iris"], "lashes": ["face"], "breast_r": ["breast_r"], "breast_l": ["breast_l"],
       "arm_r_fore": ["hand_r", "forearm_r"], "arm_l_fore": ["hand_l", "forearm_l"]}
RIGID = {"rapier": "weapon", "arm_r_up": "arm_r", "arm_l_up": "arm_l"}
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

EYES, MOUTH = (505, 714), (509, 759)
er = K.union([K.diff_rect(os.path.join(RIG, "variants", v + ".png"), final, EYES, half=(64, 20)) for v in ("eyes_closed", "eyes_half", "smile") if HAS.get(v)]) if any(HAS.get(v) for v in ("eyes_closed", "eyes_half", "smile")) else None
mr = K.union([K.diff_rect(os.path.join(RIG, "variants", v + ".png"), final, MOUTH, half=(34, 22)) for v in ("mouth_open", "mouth_small", "mouth_wide", "smile") if HAS.get(v)]) if any(HAS.get(v) for v in ("mouth_open", "mouth_small", "mouth_wide", "smile")) else None
overlays = []
if er:
    overlays.append({"slot": "eyes", "bone": "face", "base": "open", "default": "open", "z": 3, "rect": er,
                     "variants": {k: "variants/%s.png" % v for k, v in (("closed", "eyes_closed"), ("half", "eyes_half"), ("smile", "smile")) if HAS.get(v)}})
if mr:
    overlays.append({"slot": "mouth", "bone": "face", "base": "default", "default": "default", "z": 3, "rect": mr,
                     "variants": {k: "variants/%s.png" % v for k, v in (("open", "mouth_open"), ("small", "mouth_small"), ("wide", "mouth_wide"), ("smile", "smile")) if HAS.get(v)}})

fmeta = json.load(open(os.path.join(SRC, "final", HERO + ".json")))
src = {
    "_doc": "Lucen's layered rig (2026-11-04): MOSS rig pose seed 304000, cut by SAM (tools/layered/lucen_rig.py, rigkit.py), "
            "hidden parts painted in. Her base look (HeroArt.LIVE).",
    "version": 2, "cell": 10, "image": NAME + ".png", "origin": fmeta.get("origin", [512, 1990]), "texel_scale": 1.0,
    "portrait": [380, 560, 260], "look_px": [10, 6],
    "meta": {"weapon": "rapier", "attack": "attack_melee", "fx_color": "#e9e0ff", "art": "moss s304000 rig pose, SAM layers",
             "idle_gestures": ["idle_flourish", "idle_hair", "idle_shades"],
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
