"""Seraphiel's layered rig (prototype rigproto2, 2026-10-20/21): the reference for layered rigs (docs/dev/halorig.md 11.4).

What changed from make_rig.py (v1):
- Every layer is weighted only by its own parts ("weights": "own"): in v1 the back hair followed the
  arms, thighs and breasts, and the arms followed the hair.
- The breasts are their own layers (SAM masks, cleaned), weighted top-to-bottom so the top stays on
  the chest and the underside carries the motion; the torso behind them is filled in.
- Each arm is its own layer, with a hand bone at the wrist; the stand is held by the right hand.
- Back hair and drapes are two-bone chains (they wave instead of swinging stiffly).
- Every layer's half-transparent edge takes the colour of its nearest solid pixel (no dark fringes).
Reads st_canvas/*.png (st_to_canvas.py), the v1 rig folder's painting and variants, and the SAM masks
(sam_cut.py: breast_r/l, hand_r/l in SCRATCH/sam). Writes assets/art/heroes/seraphiel/skins/rigproto2/.
Usage: tools/layered/seraphiel_rig.py [sam dir]   (sam_cut.py's masks from seraphiel_sam.json: breast_r/l, hand_r/l;
       default <work>/sam)"""
import json
import os
import shutil
import sys

import cv2
import numpy as np
from PIL import Image, ImageFilter
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
# the work folder (local, never committed): the rig-pose final, See-through's layers on the canvas
# (st_canvas/), the picked expression tries (variants/candidates/) and the repaints (work2/)
SRC = os.path.join(ROOT, "art_src", "_review", "rigproto", "seraphiel")
ST = os.path.join(SRC, "st_canvas")
HEROES = os.path.join(ROOT, "assets", "art", "heroes", "seraphiel", "skins")
V1 = os.path.join(HEROES, "rigproto")
NAME = "rigproto2"
RIG = os.path.join(HEROES, NAME)
SAM = sys.argv[1] if len(sys.argv) > 1 else os.path.join(SRC, "sam")     # sam_cut.py ... seraphiel_sam.json
W, H = 1024, 2048
os.makedirs(os.path.join(RIG, "st"), exist_ok=True)
shutil.copy(os.path.join(V1, "rigproto.png"), os.path.join(RIG, NAME + ".png"))
if not os.path.isdir(os.path.join(RIG, "variants")):
    shutil.copytree(os.path.join(V1, "variants"), os.path.join(RIG, "variants"))
# expression frames made later (variants.py on the rig-pose final; HALO_ART_SRC=art_src/_review/rigproto):
# the picked try of each
PICKS = {"eyes_half": "eyes_half_s101501", "mouth_small": "mouth_small_s101500", "mouth_wide": "mouth_wide_s101501"}
for vname, pick in PICKS.items():
    cands = sorted(f for f in os.listdir(os.path.join(SRC, "variants", "candidates")) if f.startswith(vname + "_s") and f.endswith(".png"))
    f = pick + ".png" if pick else (cands[0] if cands else None)
    if f and os.path.exists(os.path.join(SRC, "variants", "candidates", f)):
        shutil.copy(os.path.join(SRC, "variants", "candidates", f), os.path.join(RIG, "variants", vname + ".png"))
HAS = {v: os.path.exists(os.path.join(RIG, "variants", v + ".png")) for v in PICKS}

final = np.asarray(Image.open(os.path.join(RIG, NAME + ".png")).convert("RGBA")).astype(np.float32)
fa = final[..., 3] > 8
yy, xx = np.mgrid[0:H, 0:W]


def st(tag):
    p = os.path.join(ST, tag.replace(" ", "_") + ".png")
    if not os.path.exists(p):
        return np.zeros((H, W, 4), np.float32)
    return np.asarray(Image.open(p).convert("RGBA")).astype(np.float32)


def save_mask(name, m):
    Image.fromarray((np.clip(m, 0, 1) * 255).astype(np.uint8)).save(os.path.join(RIG, "st", name + ".png"))


def bleed(rgba, solid=245):
    """Half-transparent pixels take the colour of the nearest solid pixel: no dark or grey fringes."""
    a = rgba[..., 3]
    sol = a >= solid
    if not sol.any():
        return rgba
    _, (iy, ix) = ndimage.distance_transform_edt(~sol, return_indices=True)
    out = rgba.copy()
    edge = ~sol
    out[edge, :3] = rgba[iy[edge], ix[edge], :3]
    return out


# ---- See-through layers -> rig layers (as v1), arms split per side
ORDER = [("back hair", -40, "back_hair"), ("wings", -30, "wings"), ("_missing", -25, "extras"),
         ("bottomwear", -15, "drapes"), ("legwear", -10, "legs"), ("footwear", -9, "legs"),
         ("neck", -1, "body"), ("topwear", 0, "body"), ("head", 1, "body"), ("face", 2, "body"),
         ("ears", 3, "body"), ("eyewhite", 4, "body"), ("irides", 5, "irides"), ("eyelash", 6, "lashes"),
         ("eyebrow", 7, "body"), ("nose", 8, "body"), ("mouth", 9, "body"),
         ("objects", 5, "stand"), ("handwear", 10, "arms"), ("front hair", 30, "front_hair")]
ORDER.sort(key=lambda t: t[1])
miss = np.asarray(Image.open(os.path.join(ST, "_missing.png"))) > 127
miss = ndimage.binary_dilation(miss, iterations=2)
headbox = np.zeros((H, W), bool)
headbox[600:905, 320:710] = True
extras = final.copy()
extras[..., 3] *= miss & headbox
L = {tag: (extras if tag == "_missing" else st(tag)) for tag, _, _ in ORDER}
stray = miss & ~headbox & fa
tags = [t for t, _, _ in ORDER if t != "_missing"]
dist = np.stack([ndimage.distance_transform_edt(L[t][..., 3] <= 127) for t in tags])
near = np.argmin(dist, axis=0)
for i, t in enumerate(tags):
    sel = stray & (near == i)
    if sel.any():
        L[t] = L[t].copy()
        L[t][sel] = final[sel]
top = np.full((H, W), "", dtype=object)
for tag, z, rl in ORDER:
    top[L[tag][..., 3] > 127] = rl


def compose(rl):
    out = np.zeros((H, W, 4), np.float32)
    for tag, z, l in ORDER:
        if l != rl:
            continue
        src = L[tag]
        a = src[..., 3:4] / 255.0
        out[..., :3] = src[..., :3] * a + out[..., :3] * (1 - a)
        out[..., 3:4] = 255 * (a + out[..., 3:4] / 255 * (1 - a))
    vis = (top == rl) & fa
    out[vis] = final[vis]
    return out


rl_img = {rl: compose(rl) for rl in ("back_hair", "wings", "extras", "drapes", "legs", "body", "stand", "arms", "front_hair",
                                     "irides", "lashes")}

# the eyes: the irises are their own piece (they dart about) between the face and the lash lines;
# See-through left no eye white, so the white under each iris is painted from the visible sclera
iris_m = L["irides"][..., 3] > 30
under = ndimage.binary_dilation(iris_m, iterations=3) & ~(L["eyelash"][..., 3] > 90)
fin_rgb = final[..., :3]
bright = (fin_rgb.min(axis=2) > 222) & (fin_rgb.max(axis=2) - fin_rgb.min(axis=2) < 26)
near_eye = ndimage.binary_dilation(iris_m, iterations=9) & ~iris_m & bright
sclera = np.median(fin_rgb[near_eye], axis=0) if near_eye.any() else np.array([246.0, 244.0, 248.0])
lab_e, n_e = ndimage.label(ndimage.binary_dilation(iris_m, iterations=4))
eye_body = rl_img["body"]
for k in range(1, n_e + 1):
    sel = under & (lab_e == k)
    if not sel.any():
        continue
    ys_e = np.nonzero(sel)[0]
    t = (yy - ys_e.min()) / max(ys_e.max() - ys_e.min(), 1)       # the lid's shadow on the top of the white
    shade_e = 0.86 + 0.14 * np.clip(t, 0, 1)
    eye_body[sel, :3] = sclera[None, :] * shade_e[sel, None]
    eye_body[sel, 3] = 255
rl_img["body"] = eye_body
print("eyes: %d eye whites painted, sclera %s" % (n_e, sclera.astype(int).tolist()))

# ---- breasts: SAM masks, cleaned (filled, cut at a curve across the upper chest, smoothed)
CLEAVE = 517
breast = {}
for side, sign in (("r", -1), ("l", 1)):
    m = np.asarray(Image.open(os.path.join(SAM, "breast_%s.png" % side))) > 127
    m = ndimage.binary_closing(m, iterations=6)
    m = ndimage.binary_fill_holes(m)
    t = np.clip((xx - CLEAVE) * sign / 115.0, 0, 1)
    m &= yy >= 1012 - 20 * t
    m &= (xx >= CLEAVE) if sign > 0 else (xx < CLEAVE)
    lab, n = ndimage.label(m)
    if n > 1:
        s = ndimage.sum(m, lab, range(1, n + 1))
        m = lab == (int(np.argmax(s)) + 1)
    m = ndimage.binary_opening(m, iterations=3)
    m = ndimage.gaussian_filter(m.astype(np.float32), 3) > 0.5
    # the side of the breast outside the leotard panel, up to the arm: skin that moves with her
    arm_m = rl_img["arms"][..., 3] > 60
    grow = ndimage.binary_dilation(m, iterations=10) & ~arm_m & ((xx - CLEAVE) * sign > 60) & (yy < 1110)
    m |= grow
    m = ndimage.gaussian_filter(m.astype(np.float32), 1.5) > 0.5
    breast[side] = m
    ys, xs = np.nonzero(m)
    print("breast_%s: x %d-%d y %d-%d px %d" % (side, xs.min(), xs.max(), ys.min(), ys.max(), int(m.sum())))

both = breast["r"] | breast["l"]
# breast layers: the painting's pixels, a 1 px soft edge
breast_img = {}
for side in ("r", "l"):
    a = ndimage.gaussian_filter(breast[side].astype(np.float32), 0.8)
    img = final.copy()
    img[..., 3] = np.minimum(final[..., 3], a * 255)
    breast_img[side] = img

# the torso behind them: what shows when a breast lifts or swings is the band under its lower edge,
# so the leotard panels and the skin between them continue straight up from below the breasts (each
# column takes the colour just under the hole), softened sideways, darker the deeper under the
# breast (its shadow). Only inside her silhouette; elsewhere the nearest solid body pixel.
body = rl_img["body"]
hole = ndimage.binary_dilation(both, iterations=2) & fa
known = (body[..., 3] > 200) & ~hole
fill = np.zeros((H, W, 3), np.float32)
have = np.zeros((H, W), bool)
dist_up = np.zeros((H, W), np.float32)
for x in range(W):
    col = np.nonzero(hole[:, x])[0]
    if not len(col):
        continue
    yb = int(col.max())
    ys_k = np.nonzero(known[yb + 1:yb + 24, x])[0]
    if not len(ys_k):
        continue
    y0 = yb + 1 + int(ys_k[0])
    seg = body[y0 + 3:y0 + 15, x, :3][known[y0 + 3:y0 + 15, x]]       # past the outline under the breast
    if not len(seg):
        continue
    c = np.median(seg, axis=0)
    fill[col, x] = c
    have[col, x] = True
    dist_up[col, x] = yb - col
# hole pixels outside her torso (beside it, where the back hair and wings are behind) stay clear: a
# breast swinging out shows the hair behind it, as it would
inside = have | (body[..., 3] > 128)
miss_f = hole & ~have & inside
if miss_f.any():
    src_ok = known | have
    pool = np.where(have[..., None], fill, body[..., :3])
    _, (iy, ix) = ndimage.distance_transform_edt(~src_ok, return_indices=True)
    fill[miss_f] = pool[iy[miss_f], ix[miss_f]]
    dist_up[miss_f] = 30.0
fill = cv2.GaussianBlur(fill, (0, 0), sigmaX=1.6, sigmaY=0.8)
shade = 1.0 - 0.16 * np.clip(dist_up / 30.0, 0, 1)            # deeper under the breast = in its shadow
put = hole & inside
body[put, :3] = fill[put] * shade[put, None]
body[put, 3] = 255
body[hole & ~inside, 3] = 0
# the image model's repaint of the hole (fill_hidden.py, picked try copied to WORK/body_fill.png) wins
WORK = os.path.join(SRC, "work2")
os.makedirs(WORK, exist_ok=True)
Image.fromarray((put * 255).astype(np.uint8)).save(os.path.join(WORK, "body_hole.png"))
Image.fromarray(np.clip(body, 0, 255).astype(np.uint8), "RGBA").save(os.path.join(WORK, "body_rough.png"))
if os.path.exists(os.path.join(WORK, "body_fill.png")):
    rep = np.asarray(Image.open(os.path.join(WORK, "body_fill.png")).convert("RGBA")).astype(np.float32)
    # where the model painted her narrower than the hole, it left the flat grey backdrop: clear, so a
    # lifted breast shows the hair behind her there
    bgk = (np.abs(rep[..., :3] - 128.0) < 14.0).all(axis=2)
    bgk = ndimage.binary_opening(bgk, iterations=2)
    rep[..., 3] = np.where(bgk, 0.0, rep[..., 3])
    rep[..., 3] = np.minimum(rep[..., 3], 255.0 * (1.0 - ndimage.gaussian_filter(bgk.astype(np.float32), 1.0)))
    body[put] = rep[put]
    print("body: hole repainted from work2/body_fill.png (%d backdrop px cleared)" % int((bgk & put).sum()))
rl_img["body"] = body

# the wings behind the stand: See-through left a clamp-shaped hole and the pole's edges in the feathers.
# The strip the stand covered (inside the wings' outline) is rough-filled here and repainted by the
# image model (fill_hidden.py -> WORK/wings_fill.png).
wl = rl_img["wings"]
stand_m = ndimage.binary_dilation(L["objects"][..., 3] > 40, iterations=6)
wing_sil = ndimage.binary_fill_holes(ndimage.binary_closing(wl[..., 3] > 60, iterations=4))
whole = stand_m & wing_sil
Image.fromarray((whole * 255).astype(np.uint8)).save(os.path.join(WORK, "wings_hole.png"))
wsolid = (wl[..., 3] > 200) & ~whole
wrgb = np.clip(wl[..., :3], 0, 255).astype(np.uint8)
_, (iy, ix) = ndimage.distance_transform_edt(~wsolid, return_indices=True)
wrgb[~wsolid] = wrgb[iy[~wsolid], ix[~wsolid]]
winp = cv2.cvtColor(cv2.inpaint(cv2.cvtColor(wrgb, cv2.COLOR_RGB2BGR), whole.astype(np.uint8) * 255, 7, cv2.INPAINT_TELEA), cv2.COLOR_BGR2RGB)
wl[whole, :3] = winp[whole]
wl[whole, 3] = 255
Image.fromarray(np.clip(wl, 0, 255).astype(np.uint8), "RGBA").save(os.path.join(WORK, "wings_rough.png"))
if os.path.exists(os.path.join(WORK, "wings_fill.png")):
    rep = np.asarray(Image.open(os.path.join(WORK, "wings_fill.png")).convert("RGBA")).astype(np.float32)
    wl[whole] = rep[whole]
    print("wings: the stand's strip repainted from work2/wings_fill.png")
rl_img["wings"] = wl

# arms: per side an upper-arm piece and a forearm piece (with the hand), cut by the nearest bone
# segment, both keeping a disc round the elbow (a cap): at rest the two copies coincide, bent the
# forearm's cap covers the joint, so the elbow bends like a ball joint instead of stretching
ARM_CHAIN = {"r": [(418, 965), (403, 1130), (322, 1048), (296, 985)],      # shoulder, elbow, wrist, fingertip
             "l": [(607, 965), (621, 1143), (688, 1288), (706, 1385)]}
ARM_CAP = {"r": 24, "l": 21}


def seg_dist(a, b):
    a, b = np.array(a, float), np.array(b, float)
    ab = b - a
    t = np.clip(((xx - a[0]) * ab[0] + (yy - a[1]) * ab[1]) / max(ab @ ab, 1e-6), 0, 1)
    return np.hypot(xx - a[0] - t * ab[0], yy - a[1] - t * ab[1])


arms = rl_img.pop("arms")
for side, sel in (("r", xx < 512), ("l", xx >= 512)):
    a = arms.copy()
    a[..., 3] *= sel
    ch = ARM_CHAIN[side]
    dseg = np.stack([seg_dist(ch[k], ch[k + 1]) for k in range(3)])
    nearest = np.argmin(dseg, axis=0)
    cap = np.hypot(xx - ch[1][0], yy - ch[1][1]) <= ARM_CAP[side]
    for piece, want in (("up", nearest == 0), ("fore", nearest >= 1)):
        m = ndimage.gaussian_filter((want | cap).astype(np.float32), 0.8)
        pc = a.copy()
        pc[..., 3] *= m
        rl_img["arm_%s_%s" % (side, piece)] = pc
for side in ("r", "l"):
    rl_img["breast_" + side] = breast_img[side]
# the necklace pendant over the top of the cleavage: its own small piece on the chest, above the
# breasts (whose tops are pinned there too), so the two breast pieces never split it
pend = np.zeros((H, W), np.float32)
pend[996:1050, 501:534] = 1.0
pend = ndimage.gaussian_filter(pend, 2.5)
neck_img = final.copy()
neck_img[..., 3] = np.minimum(final[..., 3], pend * 255)
rl_img["pendant"] = neck_img

RIG_Z = {"back_hair": -40, "wings": -30, "extras": -25, "drapes": -15, "legs": -10, "body": 0,
         "irides": 1, "lashes": 2, "breast_r": 4, "breast_l": 5, "pendant": 6, "stand": 7, "arm_l_up": 8, "arm_l_fore": 9, "arm_r_up": 10, "arm_r_fore": 11, "front_hair": 30}
rects = {}
for rl, z in RIG_Z.items():
    img = bleed(np.clip(rl_img[rl], 0, 255))
    pil = Image.fromarray(img.astype(np.uint8), "RGBA")
    al = np.asarray(pil)[..., 3]
    ys, xs = np.nonzero(al > 4)
    x0, y0, x1, y1 = int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1
    pil.crop((x0, y0, x1, y1)).save(os.path.join(RIG, "%s_%s.png" % (NAME, rl)))
    rects[rl] = [x0, y0, x1 - x0, y1 - y0]
    save_mask(rl, al > 127)
    print("layer %-10s z %4d rect %s" % (rl, z, rects[rl]))

head = np.zeros((H, W), bool)
for tag in ("head", "face", "ears", "eyewhite", "irides", "eyelash", "eyebrow", "nose", "mouth"):
    head |= L[tag][..., 3] > 127
save_mask("headgroup", head)
save_mask("neck_st", L["neck"][..., 3] > 127)
for side in ("r", "l"):
    save_mask("hand_" + side, np.asarray(Image.open(os.path.join(SAM, "hand_%s.png" % side))) > 127)

# breast weights: 0 along the top edge (it stays on the chest), full from 70 px down; the outer
# side margin (skin beside the leotard) a little less, so the side follows softly
for side, sign in (("r", -1), ("l", 1)):
    m = breast[side]
    ys, xs = np.nonzero(m)
    ytop = np.full(W, H, np.float32)
    np.minimum.at(ytop, xs, ys.astype(np.float32))
    ytop = ndimage.minimum_filter1d(ytop, 9)
    u = np.clip((yy - ytop[None, :]) / 70.0, 0, 1)
    w = u * u * (3 - 2 * u)
    outer = np.clip(((xx - CLEAVE) * sign - 95) / 25.0, 0, 1)
    w *= 1.0 - 0.35 * outer
    save_mask("breast_%s_w" % side, w * m)
    # the lower pole: a second bone that follows the first with its own lag ("the upper moves first,
    # the lower follows"), 0 above mid-breast, full over the underside
    u2 = np.clip((yy - ytop[None, :] - 45.0) / 55.0, 0, 1)
    save_mask("breast_%s_lo_w" % side, (u2 * u2 * (3 - 2 * u2)) * (1.0 - 0.35 * outer) * m)

# the six wings, split by angle around each side's root (as v1)
wing = L["wings"][..., 3] > 127
wing_bones = []
for side, cx, sign in (("r", 455, -1), ("l", 570, 1)):
    ys, xs = np.nonzero(wing & (xx * sign > cx * sign))
    ang = np.degrees(np.arctan2(-(ys - 1050), (xs - cx) * sign))
    far = np.hypot(xs - cx, ys - 1050) > 160
    hist, edges = np.histogram(ang[far], bins=90, range=(-60, 120))
    sm = np.convolve(hist, np.ones(7) / 7, mode="same")
    peaks = [i for i in range(1, len(sm) - 1) if sm[i] >= sm[i - 1] and sm[i] >= sm[i + 1] and sm[i] > sm.max() * 0.15]
    peaks = sorted(peaks, key=lambda i: -sm[i])[:3]
    centers = sorted((edges[i] + edges[i + 1]) / 2 for i in peaks)[::-1]
    lab = np.argmin(np.abs(ang[:, None] - np.array(centers)[None, :]), axis=1)
    for k, c in enumerate(centers):
        m = np.zeros((H, W), bool)
        m[ys[lab == k], xs[lab == k]] = True
        save_mask("wing_%s%d" % (side, k + 1), m)
        d = np.hypot(xs[lab == k] - cx, ys[lab == k] - 1050)
        nr = d <= np.percentile(d, 4)
        piv = [int(xs[lab == k][nr].mean()), int(ys[lab == k][nr].mean())]
        wing_bones.append(("wing_%s%d" % (side, k + 1), piv, c))


def diff_rect(path, pad=4):
    v = np.asarray(Image.open(path).convert("RGBA")).astype(np.float32)
    d = np.abs(v[..., :3] - final[..., :3]).max(axis=2) > 18
    d &= (np.abs(np.arange(H) - 866)[:, None] < 90) & (np.abs(np.arange(W) - 515)[None, :] < 90)
    ys, xs = np.nonzero(d)
    return [int(xs.min()) - pad, int(ys.min()) - pad, int(xs.max() - xs.min()) + 2 * pad, int(ys.max() - ys.min()) + 2 * pad]


def union(rs):
    x0 = min(r[0] for r in rs)
    y0 = min(r[1] for r in rs)
    return [x0, y0, max(r[0] + r[2] for r in rs) - x0, max(r[1] + r[3] for r in rs) - y0]


# each slot's patch rect covers every one of its frames
er = union([diff_rect(os.path.join(RIG, "variants", v + ".png")) for v in ("eyes_closed", "eyes_half") if v == "eyes_closed" or HAS[v]])
mr = union([diff_rect(os.path.join(RIG, "variants", v + ".png")) for v in ("mouth_open", "mouth_small", "mouth_wide") if v == "mouth_open" or HAS[v]])

M = lambda f, **kw: dict({"type": "mask", "image": "st/%s.png" % f}, **kw)

P = lambda pts, **kw: dict({"type": "polygon", "points": pts}, **kw)

# back hair: per side an outer and an inner lock, each a chain of four segments (waves travel down
# it); pivots at each band's top, on the lock's hair there. Bangs: three locks.
HAIR_BANDS = [1080, 1270, 1460, 1640, 2048]
HAIR_LOCKS = {"r_o": (0, 400), "r_i": (400, 512), "l_i": (512, 624), "l_o": (624, 1024)}
hair_m = L["back hair"][..., 3] > 127
hair_regions, hair_bones = [], []
for lk, (x0, x1) in HAIR_LOCKS.items():
    parent = "hair_back"
    for k in range(4):
        y0, y1 = HAIR_BANDS[k], HAIR_BANDS[k + 1]
        nm = "hair_%s%d" % (lk, k + 1)
        band = hair_m[y0:y0 + 40, x0:x1]
        ys_b, xs_b = np.nonzero(band)
        px = int(xs_b.mean()) + x0 if len(xs_b) else (x0 + x1) // 2
        hair_regions.append({"name": nm, "soft": 22, "rule": M("back_hair", within=P([[x0, y0], [x1, y0], [x1, y1], [x0, y1]]))})
        hair_bones.append({"name": nm, "parent": parent, "pivot": [px, y0],
                           "spring": "hair_long;w=0.06;i=0.62;limit=13;k=%d" % (48 - 5 * k)})
        parent = nm
hair_regions.reverse()           # the lowest segments first (priority), the mass on the head last
BANG_LOCKS = {"hair_front_r": (0, 480, 455), "hair_front": (480, 548, 515), "hair_front_l": (548, 1024, 578)}
regions = [
    # body layer
    {"name": "face", "bone": "face", "rule": {"type": "ellipse", "center": [515, 866], "radius": [62, 64], "feather": 12}},
    {"name": "iris", "rule": M("irides")},
    {"name": "head", "rule": M("headgroup")},
    {"name": "neck", "rule": M("neck_st")},
    {"name": "chest", "rule": P([[420, 930], [600, 930], [650, 1010], [640, 1150], [385, 1150], [380, 1010]], feather=26)},
    {"name": "torso", "rule": P([[400, 1130], [625, 1130], [620, 1245], [405, 1245]], feather=26)},
    {"name": "hips", "rule": P([[360, 1225], [665, 1225], [670, 1360], [355, 1360]], feather=20)},
    # breast layers (grey-level weights; the rest goes to the chest)
    {"name": "breast_r_lo", "rule": M("breast_r_lo_w", levels=True)},
    {"name": "breast_r", "rule": M("breast_r_w", levels=True)},
    {"name": "breast_l_lo", "rule": M("breast_l_lo_w", levels=True)},
    {"name": "breast_l", "rule": M("breast_l_w", levels=True)},
    # extras
] + [{"name": n, "rule": M("front_hair", within=P([[x0, 0], [x1, 0], [x1, 2048], [x0, 2048]]))}
     for n, (x0, x1, _) in BANG_LOCKS.items()] + [
    {"name": "halo", "rule": M("extras", within=P([[400, 640], [640, 640], [640, 790], [400, 790]]))},
    {"name": "head_wing_r", "rule": M("extras", within=P([[330, 780], [478, 780], [478, 900], [330, 900]]))},
    {"name": "head_wing_l", "rule": M("extras", within=P([[548, 780], [700, 780], [700, 900], [548, 900]]))},
    {"name": "weapon", "rule": M("stand")},
    # arms: hand, forearm, upper arm
    {"name": "hand_r", "rule": M("hand_r", within=M("arm_r_fore"))},
    {"name": "forearm_r", "rule": M("arm_r_fore")},
    {"name": "arm_r", "rule": M("arm_r_up")},
    {"name": "hand_l", "rule": M("hand_l", within=M("arm_l_fore"))},
    {"name": "forearm_l", "rule": M("arm_l_fore")},
    {"name": "arm_l", "rule": M("arm_l_up")},
    # legs
    {"name": "foot_r", "rule": M("legs", within=P([[300, 1836], [511, 1836], [511, 2048], [300, 2048]]))},
    {"name": "foot_l", "rule": M("legs", within=P([[511, 1828], [760, 1828], [760, 2048], [511, 2048]]))},
    {"name": "shin_r", "rule": M("legs", within=P([[300, 1560], [511, 1560], [511, 2048], [300, 2048]]))},
    {"name": "thigh_r", "rule": M("legs", within=P([[300, 1180], [511, 1180], [511, 1560], [300, 1560]]))},
    {"name": "shin_l", "rule": M("legs", within=P([[511, 1560], [760, 1560], [760, 2048], [511, 2048]]))},
    {"name": "thigh_l", "rule": M("legs", within=P([[511, 1180], [760, 1180], [760, 1560], [511, 1560]]))},
    # drapes: two-bone chains
    {"name": "drape_r2", "soft": 140, "rule": M("drapes", within=P([[0, 1700], [512, 1700], [512, 2048], [0, 2048]]))},
    {"name": "drape_r", "rule": M("drapes", within=P([[0, 1150], [512, 1150], [512, 2048], [0, 2048]]))},
    {"name": "drape_l2", "soft": 140, "rule": M("drapes", within=P([[512, 1700], [1024, 1700], [1024, 2048], [512, 2048]]))},
    {"name": "drape_l", "rule": M("drapes", within=P([[512, 1150], [1024, 1150], [1024, 2048], [512, 2048]]))},
] + [{"name": n, "rule": M(n)} for n, _, _ in wing_bones] + [
] + hair_regions + [
    {"name": "hair_back", "rule": M("back_hair")},
]

wing_parent = {"1": "chest", "2": "chest", "3": "torso"}
# the lower pole's spring: stiffer, softer-capped, more squash than shift (it rides on the upper one)
JIG_LO = "jiggle;kx=170;ky=230;ky2=560;z=0.3;limit=10;tx=0.3;ty=0.45;rot=0.35;sq=0.6"
bones = [
    # planted ankles: the legs reach them by IK (src "ik"), so the knees flex as the hips move
    {"name": "ik_foot_r", "parent": "root", "pivot": [488, 1830]},
    {"name": "ik_foot_l", "parent": "root", "pivot": [530, 1822]},
    {"name": "hips", "parent": "root", "pivot": [512, 1285]},
    {"name": "torso", "parent": "hips", "pivot": [512, 1195]},
    {"name": "chest", "parent": "torso", "pivot": [512, 1075]},
    {"name": "neck", "parent": "chest", "pivot": [512, 958]},
    {"name": "head", "parent": "neck", "pivot": [512, 935]},
    {"name": "face", "parent": "head", "pivot": [515, 880]},
    {"name": "iris", "parent": "face", "pivot": [515, 856]},
] + [{"name": n, "parent": "head", "pivot": [px, 800], "spring": "bangs"} for n, (_, _, px) in BANG_LOCKS.items()] + [
    {"name": "hair_back", "parent": "head", "pivot": [512, 830], "spring": "hair_mass"},
] + hair_bones + [
    {"name": "halo", "parent": "head", "pivot": [515, 775], "spring": "accessory;limit=5"},
    {"name": "head_wing_r", "parent": "head", "pivot": [470, 830], "spring": "accessory;limit=10"},
    {"name": "head_wing_l", "parent": "head", "pivot": [558, 830], "spring": "accessory;limit=10"},
    {"name": "breast_r", "parent": "chest", "pivot": [458, 1004], "spring": "jiggle"},
    {"name": "breast_r_lo", "parent": "breast_r", "pivot": [458, 1062], "spring": JIG_LO},
    {"name": "breast_l", "parent": "chest", "pivot": [572, 1008], "spring": "jiggle"},
    {"name": "breast_l_lo", "parent": "breast_l", "pivot": [572, 1064], "spring": JIG_LO},
    {"name": "arm_r", "parent": "chest", "pivot": [418, 965]},
    {"name": "forearm_r", "parent": "arm_r", "pivot": [403, 1130]},
    {"name": "hand_r", "parent": "forearm_r", "pivot": [322, 1048]},
    {"name": "arm_l", "parent": "chest", "pivot": [607, 965]},
    {"name": "forearm_l", "parent": "arm_l", "pivot": [621, 1143]},
    {"name": "hand_l", "parent": "forearm_l", "pivot": [688, 1288]},
    {"name": "weapon", "parent": "root", "pivot": [300, 1955], "tip": [300, 765], "grip": {"bone": "hand_r", "at": [300, 1010]}},
    {"name": "thigh_r", "parent": "hips", "pivot": [460, 1300]},
    {"name": "shin_r", "parent": "thigh_r", "pivot": [480, 1560]},
    {"name": "foot_r", "parent": "shin_r", "pivot": [488, 1830]},
    {"name": "thigh_l", "parent": "hips", "pivot": [562, 1300]},
    {"name": "shin_l", "parent": "thigh_l", "pivot": [548, 1560]},
    {"name": "foot_l", "parent": "shin_l", "pivot": [530, 1822]},
    {"name": "drape_r", "parent": "hips", "pivot": [428, 1240], "spring": "cape;w=0.1;g=0.85;limit=12"},
    {"name": "drape_r2", "parent": "root", "pivot": [390, 1700], "spring": "cape;w=0.06;g=0.9;limit=5"},
    {"name": "drape_l", "parent": "hips", "pivot": [602, 1240], "spring": "cape;w=0.1;g=0.85;limit=12"},
    {"name": "drape_l2", "parent": "root", "pivot": [640, 1700], "spring": "cape;w=0.06;g=0.9;limit=5"},
] + [{"name": n, "parent": wing_parent[n[-1]], "pivot": piv, "spring": "wing;w=0.05"} for n, piv, _ in wing_bones]

fmeta = json.load(open(os.path.join(SRC, "final", "seraphiel.json")))
own = {"back_hair": ["hair_back", "hair_r_", "hair_l_"], "wings": ["wing"], "extras": ["halo", "head_wing"], "drapes": ["drape"],
       "legs": ["thigh", "shin", "foot"], "body": ["face", "head", "neck", "chest", "torso", "hips"],
       "breast_r": ["breast_r"], "breast_l": ["breast_l"], "pendant": ["chest"], "irides": ["iris"], "lashes": ["face"], "arm_r_fore": ["hand_r", "forearm_r"],
       "arm_l_fore": ["hand_l", "forearm_l"], "front_hair": ["hair_front"]}
RIGID = {"stand": "weapon", "arm_r_up": "arm_r", "arm_l_up": "arm_l"}      # pieces that move as one
rest = {"breast_r": "chest", "breast_l": "chest"}
CELL = {"breast_r": 6, "breast_l": 6, "arm_r_fore": 8, "arm_l_fore": 8}     # finer grids where shapes bend
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

src = {
    "_doc": "Prototype layered rig v2 (2026-10-20): Seraphiel (MOSS rig pose, seed 101953) split by See-through, "
            "breasts and arms as their own layers, own weights per layer; tools/layered/seraphiel_rig.py. "
            "Not shipped: a local prototype.",
    "version": 2, "cell": 10, "image": NAME + ".png", "origin": fmeta.get("origin", [512, 1990]), "texel_scale": 1.0,
    "portrait": [334, 692, 362], "look_px": [10, 6],
    "meta": {"weapon": "mic stand", "fx_color": "#bff6ff", "art": "moss s101953 rig pose, See-through layers, v2",
             # a livelier idle than the shared default: deeper breath, a hip-to-hip weight shift every
             # 7.2 s, faster drift, and bounce kicks at each breath and each turn of the sway
             "idle_gestures": ["idle_wings", "idle_sway", "idle_lean"],
             "idle": {"breath": 6.0, "noise": 2.2, "head": 1.6, "arms": 2.2, "wings": 1.8, "sway": 9.0,
                      "sway_period": 7.2, "sway_rot": 1.6, "sway_dip": 2.5, "kick_breath": 95.0, "kick_sway": 60.0}},
    "body_bone": "hips", "bones": bones, "regions": regions, "layers": layers,
    "ik": [{"upper": "thigh_r", "lower": "shin_r", "target": "ik_foot_r", "foot": "foot_r", "knee_room": 10},
           {"upper": "thigh_l", "lower": "shin_l", "target": "ik_foot_l", "foot": "foot_l", "knee_room": 10}],
    "overlays": [
        {"slot": "eyes", "bone": "face", "base": "open", "default": "open", "z": 3, "rect": er,
         "variants": {"closed": "variants/eyes_closed.png", "half": "variants/eyes_half.png", "smile": "variants/smile.png"}},
        {"slot": "mouth", "bone": "face", "base": "default", "default": "default", "z": 3, "rect": mr,
         "variants": dict({"open": "variants/mouth_open.png", "smile": "variants/smile.png"},
                          **{k: "variants/mouth_%s.png" % k for k in ("small", "wide") if HAS["mouth_" + k]})},
    ],
}
json.dump(src, open(os.path.join(RIG, NAME + ".warp_src.json"), "w"), indent=1)
print("wrote", NAME, len(bones), "bones", len(regions), "regions", len(layers), "layers")
