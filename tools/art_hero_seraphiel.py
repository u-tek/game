"""Seraphiel STAND-IN art (vector), used only as placeholder input for the warp rig until the
painted illustration arrives. Vector character work is discontinued (owner decision): heroes
are painted raster illustrations animated with the HaloRig warp rig (docs/dev/halorig.md).

    python3 tools/art_hero_seraphiel.py && tools/art_warp seraphiel

Writes assets/art/heroes/seraphiel/standin/seraphiel_vector.svg and renders (with Godot's SVG
renderer) assets/art/heroes/seraphiel/seraphiel.png plus variants/eyes_open.png,
variants/mouth_open.png and variants/smile.png - the same files a painted delivery provides. Full-scale 7.4-head adult figure (mid-20s), 3/4 view facing right.
Parts are drawn upright in "neutral" coordinates and then posed by forward kinematics
(POSE below): each part group gets the bone's transform and the rig pivots are written at
their posed positions, so the rig's setup pose IS the poster pose. Design brief:
docs/dev/character-briefs.md. Style rules, recipes and review rubric: docs/dev/art-style.md.
"""
import math
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from art_svgkit import (Doc, smooth, sample, taper, path, group, ink, cel, crescent, underlay, ellipse_d, poly,
                        f, xf, lerp, lerp_pt, tline, matrix_str, rot_about, mat_mul, mat_apply, IDENT, OUTLINE)

d = Doc(1024, 2048)

# ------------------------------------------------------------------ palette + line system
OUT = OUTLINE                      # silhouette ink (#2a1d3d)
SKIN = {"b": "#fde8dc", "s1": "#f5c6b3", "s2": "#e19b8b", "s3": "#c47468", "hi": "#fffaf6", "ln": "#b5685b", "rim": "#e8f4ff"}
HAIR = {"b": "#faefcb", "s1": "#e8d3a2", "s2": "#d2b47e", "s3": "#b09366", "hi": "#ffffff", "ln": "#8c6a40",
        "sil": "#3b2534", "inner": "#7a5a3a", "gloss": "#fffdf2", "rim": "#e4efff"}
HAIR_LAYERS = {   # (root, mid, tip) gradient + shade tone per depth layer (platinum blonde)
    "under": ("#e0cc9e", "#d5bf8e", "#c6ad7c", "#ab9268"),
    "mid": ("#f8eecf", "#f1e3bc", "#e8d4a6", "#d6bd8c"),
    "top": ("#fffbee", "#fcf3da", "#f4e6c4", "#e7d2a4"),
}
WHITE = {"b": "#fefdff", "s1": "#e6e1f5", "s2": "#c6bce3", "s3": "#9f93c9", "hi": "#ffffff", "ln": "#9b90c5", "rim": "#e2f1ff"}
GOLD = {"b": "#f4c95c", "s1": "#df9f39", "s2": "#a8661e", "hi": "#fff4c8", "sp": "#ffffff", "ln": "#5e3510"}
SKY = {"b": "#8fd2f2", "s1": "#5ba8de", "s2": "#3a7bc2", "hi": "#dcf4ff", "ln": "#23508b"}
FEA = {"b": "#fefdff", "s1": "#e7e2f6", "s2": "#c9bfe5", "s3": "#a397cc", "ln": "#9890c2", "sil": "#3e3366",
       "tip": "#f8dc93", "tip2": "#eebf58"}
W_SH, W_SIL, W_LIT, W_IN = 5.4, 4.4, 3.0, 2.0      # shadow-side / normal / lit-side silhouette, interior
V_BOT = (553, 762)    # bottom of the plunging neckline
SC_X = 846            # sceptre axis

# Contrapposto, baked by forward kinematics (degrees, + = clockwise on screen).
# Weight on the far (left) leg: far hip up (pelvis CCW), torso and chest counter-rotate so the
# far shoulder drops, head tilts gently toward it. Hanging things counter-rotate to hang plumb.
POSE = {
    "hips": -4.0, "torso": 3.0, "chest": 3.5, "chest_upper": 1.0, "neck": 0.5, "head": 2.0,
    "thigh_l": 3.0, "shin_l": 1.0, "thigh_r": 5.0, "shin_r": -3.0, "foot_r": -2.0,
    "skirt_l": 4.0, "skirt_r": 4.0, "skirt_back": 4.0, "skirt_front": 4.0,
    "arm_upper_r": -4.0, "arm_lower_r": 2.0, "hand_r": 3.0,
    "arm_upper_l": -2.0,
    "hair_back_r_1": -6.0, "hair_back_l": -5.0, "hair_side_r": -3.0, "hair_side_r_2": -3.0, "hair_side_l": -4.0,
    "sleeve_r": 3.0, "sleeve_l": 2.0, "weapon": -3.0,
}

PARTS = []


def part(pid, body, **m):
    PARTS.append([pid, body, m, False])


def alt(pid, body, **m):
    """Alternate attachment (hidden in the source SVG so it previews like the still)."""
    PARTS.append([pid, body, m, True])


def opn(pts, k=1.0):
    return smooth(pts, False, k)


# ------------------------------------------------------------------ ornaments
def gem(cx, cy, r, col=SKY, rot=0.0):
    g = d.radial([(0, col["hi"]), (0.45, col["b"]), (1, col["s2"])], cx - r * 0.25, cy - r * 0.3, r * 1.3)
    s = path(ellipse_d(cx, cy, r, r * 0.92, rot), g, GOLD["ln"], max(1.1, r * 0.18))
    s += path(ellipse_d(cx - r * 0.3, cy - r * 0.32, r * 0.34, r * 0.2, -30), "#ffffff", op=0.95)
    s += path(ellipse_d(cx + r * 0.35, cy + r * 0.38, r * 0.12, r * 0.12), "#ffffff", op=0.7)
    return s


def gold_band(pts, w, k=1.0, hi=True):
    s = ink(taper(pts, w + 3.0, "flat", k=k), GOLD["ln"])
    s += ink(taper(pts, w, "flat", k=k), GOLD["b"])
    s += ink(taper([(p[0], p[1] + w * 0.22) for p in pts], w * 0.3, "flat", k=k), GOLD["s1"], 0.9)
    if hi:
        s += ink(taper([(p[0], p[1] - w * 0.2) for p in pts], w * 0.32, "both", k=k), GOLD["hi"], 0.95)
    return s


def gold_line(pts, w=3.0):
    """Fine filigree wire: dark edge + gold core, tapered."""
    return tline(pts, w + 2.2, GOLD["ln"]) + tline(pts, w, GOLD["b"]) + tline(pts, w * 0.35, GOLD["hi"], op=0.9)


def chain(pts, link=9.0, k=1.0):
    c = sample(pts, False, k, 30)
    out = []
    acc = 0.0
    last = c[0]
    i = 0
    for p in c[1:]:
        acc += math.hypot(p[0] - last[0], p[1] - last[1])
        if acc >= link:
            acc = 0.0
            a = math.degrees(math.atan2(p[1] - last[1], p[0] - last[0]))
            if i % 2 == 0:
                out.append(path(ellipse_d(p[0], p[1], link * 0.62, link * 0.36, a), GOLD["b"], GOLD["ln"], 1.2))
            else:
                out.append(path(ellipse_d(p[0], p[1], link * 0.5, link * 0.16, a), GOLD["s1"], GOLD["ln"], 1.0))
            i += 1
        last = p
    return "".join(out)


def scroll(cx, cy, s=1.0, flip=1, rot=0.0):
    pts = [(0, 0), (8, -10), (20, -12), (28, -4), (24, 6), (14, 6), (12, -1)]
    pts = [(cx + (x * flip) * s, cy + y * s) for x, y in pts]
    pts = xf(pts, rot=rot, ox=cx, oy=cy)
    return ink(taper(pts, 4.4 * s, "both"), GOLD["ln"]) + ink(taper(pts, 2.6 * s, "both"), GOLD["b"])


def leaf(cx, cy, ang, L, w, col=None, ln=None):
    """Tiny gold feather/leaf motif for embroidery and filigree."""
    a = math.radians(ang)
    ux, uy = math.cos(a), math.sin(a)
    nx, ny = -uy, ux
    pts = [(cx, cy), (cx + ux * L * 0.4 + nx * w, cy + uy * L * 0.4 + ny * w), (cx + ux * L, cy + uy * L, "c"),
           (cx + ux * L * 0.4 - nx * w, cy + uy * L * 0.4 - ny * w)]
    return path(smooth(pts, True, 0.9), col or GOLD["b"], ln or GOLD["ln"], 1.2)


def sunburst(cx, cy, r, n=8, col=None):
    s = ""
    for k in range(n):
        a = math.radians(k * 360.0 / n - 90)
        L = r * (1.0 if k % 2 == 0 else 0.6)
        tip = (cx + math.cos(a) * L, cy + math.sin(a) * L)
        nx, ny = -math.sin(a) * r * 0.16, math.cos(a) * r * 0.16
        s += path(poly([(cx + nx, cy + ny), tip, (cx - nx, cy - ny)]), col or GOLD["b"], GOLD["ln"], 1.0)
    return s + path(ellipse_d(cx, cy, r * 0.32, r * 0.32), GOLD["hi"], GOLD["ln"], 1.0)


def sparkle(cx, cy, r, col="#ffffff", op=0.95):
    pts = [(cx, cy - r), (cx + r * 0.14, cy - r * 0.14), (cx + r, cy), (cx + r * 0.14, cy + r * 0.14),
           (cx, cy + r), (cx - r * 0.14, cy + r * 0.14), (cx - r, cy), (cx - r * 0.14, cy - r * 0.14)]
    return path(poly(pts), col, op=op)


# ------------------------------------------------------------------ materials
def skin(dd, tones=((22, -8), (8, -3)), strokes=(), lines=(), over=(), hi=False, rim=True):
    t = [(SKIN["s1"], tones[0][0], tones[0][1], 0.92)]
    if len(tones) > 1:
        t.append((SKIN["s2"], tones[1][0], tones[1][1], 0.55))
    return cel(d, dd, SKIN["b"], tones=t, hi=(SKIN["hi"], -10, 8, 0.75) if hi else None,
               rim=(SKIN["rim"], 3.5, 0, 0.95) if rim else None, over=list(over), strokes=list(strokes), lines=list(lines))


def satin(dd, tones=((26, -10), (10, -4)), strokes=(), lines=(), over=(), base=None, hi=True):
    t = [(WHITE["s1"], tones[0][0], tones[0][1])]
    if len(tones) > 1:
        t.append((WHITE["s2"], tones[1][0], tones[1][1], 0.85))
    return cel(d, dd, base or WHITE["b"], tones=t, hi=(WHITE["hi"], -10, 8) if hi else None, rim=(WHITE["rim"], 4, 0),
               over=list(over), strokes=list(strokes), lines=list(lines))


def fold(pts, w=10.0, op=0.85, deep=False, light=True):
    """A cloth fold: a tapered shadow lens with a thin crease line and a highlight on its lit side."""
    s = ink(taper(pts, w, "both"), WHITE["s2"] if deep else WHITE["s1"], op)
    s += ink(taper(pts, max(1.4, w * 0.18), "both"), WHITE["s3"], 0.7)
    if light:
        s += ink(taper([(p[0] + w * 0.6, p[1]) for p in pts], w * 0.45, "both"), "#ffffff", 0.9)
    return s


def arc_pts(c, r, a_from, a_to, away, n=6):
    """Points on a circle around c from angle a_from to a_to (radians), sweeping through `away`."""
    def norm(a):
        while a < 0:
            a += 2 * math.pi
        while a >= 2 * math.pi:
            a -= 2 * math.pi
        return a
    a0, a1, aw = norm(a_from), norm(a_to), norm(away)
    ccw = norm(a1 - a0)            # sweep length going positive
    if norm(aw - a0) <= ccw:
        sweep = ccw
    else:
        sweep = ccw - 2 * math.pi
    return [(c[0] + math.cos(a0 + sweep * i / n) * r, c[1] + math.sin(a0 + sweep * i / n) * r) for i in range(1, n)]


def limb(A, B, side_a, side_b, rA=None, rB=None):
    """Limb between joints A (top) and B (bottom) from two contours listed A->B.
    Caps are circular arcs around the joints (radius = half the joint width) so the part can
    rotate about its pivot without opening a gap. Returns the closed outline."""
    def ang(c, p):
        return math.atan2(p[1] - c[1], p[0] - c[0])
    rA = rA or math.hypot(side_a[0][0] - side_b[0][0], side_a[0][1] - side_b[0][1]) * 0.5
    rB = rB or math.hypot(side_a[-1][0] - side_b[-1][0], side_a[-1][1] - side_b[-1][1]) * 0.5
    away_b = math.atan2(B[1] - A[1], B[0] - A[0])
    away_a = away_b + math.pi
    cap_b = arc_pts(B, rB, ang(B, side_a[-1]), ang(B, side_b[-1]), away_b)
    cap_a = arc_pts(A, rA, ang(A, side_b[0]), ang(A, side_a[0]), away_a)
    ring = list(side_a) + cap_b + list(side_b)[::-1] + cap_a
    return smooth(ring, True, 0.9)


# ------------------------------------------------------------------ hair: tapered strand clumps
def _s01(x):
    x = max(0.0, min(1.0, x))
    return x * x * (3 - 2 * x)


def clump_outline(cp, w0, wm, bulge=0.0, tip_frac=0.45):
    """Outline of a hair clump along centerline cp: root width w0 swelling to wm, then
    tapering to a sharp point. bulge > 0 swells the left side, < 0 the right side."""
    c = sample(cp, False, 1.0, 8)
    acc = [0.0]
    for i in range(1, len(c)):
        acc.append(acc[-1] + math.hypot(c[i][0] - c[i - 1][0], c[i][1] - c[i - 1][1]))
    total = acc[-1] or 1.0
    L, R = [], []
    for i, p in enumerate(c):
        t = acc[i] / total
        w = lerp(w0, wm, _s01(t / 0.35))
        w *= (1.0 - _s01((t - tip_frac) / (1.0 - tip_frac))) ** 0.85
        a = c[max(i - 1, 0)]
        b = c[min(i + 1, len(c) - 1)]
        dx, dy = b[0] - a[0], b[1] - a[1]
        ln = math.hypot(dx, dy) or 1
        nx, ny = -dy / ln, dx / ln
        sw = math.sin(math.pi * t) * bulge
        wl, wr = w * 0.5 * (1 + sw), w * 0.5 * (1 - sw)
        L.append((p[0] + nx * wl, p[1] + ny * wl))
        R.append((p[0] - nx * wr, p[1] - ny * wr))
    tip = c[-1]
    ring = L[:-1] + [(tip[0], tip[1], "c")] + R[:-1][::-1]
    return ring, L, R, c, acc, total


def clump(cp, w0, wm, layer="mid", bulge=0.0, gloss=None, light=(10, -6), lines=1, tip_frac=0.45):
    """One hair clump: gradient along its length (root -> tip), a shade crescent on the
    shadow side, tapered edge lines (heavier on the shadow side), optional glossy band."""
    ring, L, R, c, acc, total = clump_outline(cp, w0, wm, bulge, tip_frac)
    dd = poly([p[:2] for p in ring])
    pal = HAIR_LAYERS[layer]
    g = d.linear([(0, pal[0]), (0.55, pal[1]), (1, pal[2])], c[0][0], c[0][1], c[-1][0], c[-1][1])
    inner = [crescent(dd, light[0], light[1], pal[3], 0.85)]
    n = len(c)
    if gloss:
        i0, i1 = int(gloss[0] * n), max(int(gloss[1] * n), int(gloss[0] * n) + 2)
        i1 = min(i1, n - 2)
        top = [L[i0], lerp_pt(L[i0], R[i0], 0.33), lerp_pt(L[min(i0 + 1, n - 1)], R[min(i0 + 1, n - 1)], 0.55), R[i0]]
        bot = [R[i1], lerp_pt(L[max(i1 - 1, 0)], R[max(i1 - 1, 0)], 0.7), lerp_pt(L[i1], R[i1], 0.45), lerp_pt(L[max(i1 - 1, 0)], R[max(i1 - 1, 0)], 0.2), L[i1]]
        band = top + R[i0 + 1:i1] + bot + L[i0 + 1:i1][::-1]
        inner.append(path(poly(band), HAIR["gloss"], op=0.9))
        mid = [lerp_pt(L[i], R[i], 0.6) for i in range(i0, i1 + 1)]
        if len(mid) > 2:
            inner.append(ink(taper(mid, max(2.0, wm * 0.12), "both"), "#ffffff", 0.95))
    # interior strand lines
    for k in range(lines):
        tt = 0.35 + 0.3 * k / max(lines, 1)
        mid = [lerp_pt(L[i], R[i], tt) for i in range(int(n * 0.15), int(n * 0.8))]
        if len(mid) > 3:
            inner.append(ink(taper(mid, 1.8, "both"), HAIR["ln"], 0.45))
    body = path(dd, g) + group("".join(inner), clip=d.clip(dd))
    body += tline(L[int(n * 0.05):], 2.4, HAIR["ln"], "both", 0.35)
    body += tline(R[int(n * 0.1):], 1.4, HAIR["ln"], "both", 0.5, op=0.75)
    return dd, body


def flyaway(pts, w=2.4):
    return tline(pts, w + 1.2, HAIR["s3"], "both", 0.6, op=0.85) + tline(pts, w * 0.5, HAIR["gloss"], "both", 0.6, op=0.8)


def hair_part(specs, extra="", sil=True, sil_w=None, sil_col=None):
    shapes, bodies = [], []
    for sp in specs:
        dd, body = clump(**sp)
        shapes.append(dd)
        bodies.append(body)
    s = underlay(shapes, (sil_w or W_SIL) * 2.0, sil_col or HAIR["sil"]) if sil else ""
    return s + "".join(bodies) + extra


def C(cp, w0, wm, layer="mid", **kw):
    r = {"cp": cp, "w0": w0, "wm": wm, "layer": layer}
    r.update(kw)
    return r


def hair():
    # --- back mass: dome behind the skull + under-layer falling behind both shoulders
    dome = smooth([(528, 76), (616, 96), (658, 166), (664, 262), (652, 340), (560, 330), (470, 340), (380, 360),
                   (372, 268), (390, 170), (452, 100)], True)
    g = d.linear([(0, "#e4d2a6"), (1, "#bea47a")], 520, 80, 520, 360)
    s = path(dome, g, HAIR["sil"], W_SIL)
    s += hair_part([
        C([(404, 250), (384, 360), (370, 480), (374, 600), (390, 720)], 70, 96, "under"),
        C([(456, 280), (444, 400), (434, 540), (440, 660), (452, 740)], 60, 70, "under"),
        C([(618, 250), (636, 360), (650, 480), (662, 600), (660, 700)], 50, 64, "under"),
        C([(596, 290), (608, 420), (620, 540), (628, 660)], 44, 50, "under"),
    ])
    part("hair_back", s, parent="head", pivot=(505, 225), z=30, spring="hair_mass")

    # --- near-side cascade to the knees: three depth layers drifting in an S-curve,
    #     joined by a gold cuff; the ends curl outward
    s = hair_part([
        C([(380, 470), (330, 600), (276, 760), (244, 920), (240, 1080), (258, 1220), (280, 1330)], 56, 86, "under", bulge=0.2),
        C([(440, 490), (410, 640), (372, 800), (346, 960), (340, 1110), (354, 1240), (376, 1330)], 50, 76, "under"),
        C([(372, 480), (320, 630), (268, 800), (240, 970), (244, 1130), (268, 1260), (290, 1336)], 46, 62, "mid", gloss=(0.17, 0.24), lines=2),
        C([(412, 480), (380, 660), (338, 840), (312, 1010), (316, 1170), (338, 1290), (356, 1336)], 50, 66, "mid", lines=2),
        C([(452, 500), (436, 660), (404, 840), (378, 1010), (378, 1160), (394, 1290), (412, 1336)], 44, 58, "mid", gloss=(0.2, 0.26)),
        C([(392, 486), (352, 640), (306, 800), (276, 960), (272, 1110), (290, 1260)], 26, 40, "top", gloss=(0.15, 0.23)),
        C([(430, 492), (404, 656), (366, 830), (342, 990), (342, 1140), (360, 1270)], 24, 36, "top", gloss=(0.18, 0.26)),
    ], extra=flyaway([(276, 760), (240, 860), (220, 980), (214, 1060)]) + flyaway([(410, 880), (420, 990), (404, 1090)], 2.0)
       + flyaway([(250, 1000), (226, 1100), (230, 1180)], 1.8))
    part("hair_back_r_1", s, parent="hair_back", pivot=(410, 520), z=32, spring="hair_long;limit=10;k=55")
    cuff = gold_band([(236, 1198), (316, 1216), (402, 1200)], 26, 0.8) + gem(316, 1216, 8)
    cuff += scroll(262, 1206, 0.75, -1) + scroll(372, 1208, 0.75, 1)
    cuff += leaf(282, 1230, 110, 26, 5) + leaf(352, 1232, 70, 26, 5)
    s = hair_part([
        C([(262, 1190), (236, 1330), (210, 1460), (178, 1570), (150, 1640), (130, 1628)], 62, 66, "under", tip_frac=0.55),
        C([(372, 1190), (370, 1330), (352, 1470), (330, 1590), (318, 1680)], 56, 60, "under", tip_frac=0.5),
        C([(290, 1190), (262, 1340), (232, 1480), (200, 1600), (168, 1680), (148, 1674)], 50, 56, "mid", lines=2, tip_frac=0.55),
        C([(332, 1190), (318, 1350), (296, 1500), (272, 1620), (262, 1712)], 54, 58, "mid", lines=2, tip_frac=0.5),
        C([(380, 1190), (388, 1330), (380, 1470), (366, 1600), (372, 1680), (392, 1692)], 46, 50, "mid", tip_frac=0.55),
        C([(306, 1196), (288, 1330), (266, 1450), (244, 1560)], 30, 34, "top", gloss=(0.1, 0.2)),
        C([(352, 1196), (348, 1336), (334, 1470), (318, 1580)], 28, 30, "top", gloss=(0.12, 0.22)),
    ], extra=cuff + flyaway([(196, 1560), (160, 1620), (128, 1610), (118, 1590)], 2.0) + flyaway([(360, 1580), (386, 1650), (408, 1660)], 2.0)
       + flyaway([(250, 1610), (236, 1700), (222, 1730)], 1.8))
    part("hair_back_r_2", s, parent="hair_back_r_1", pivot=(316, 1202), z=34, spring="hair_long;limit=20")

    # --- far tress, between the body and the far arm
    part("hair_back_l", hair_part([
        C([(612, 480), (640, 640), (660, 820), (664, 1000), (650, 1140)], 50, 62, "under"),
        C([(640, 470), (676, 640), (700, 820), (706, 980), (696, 1110)], 40, 52, "under"),
        C([(626, 476), (656, 640), (676, 820), (680, 980)], 26, 32, "mid"),
    ]), parent="hair_back", pivot=(632, 520), z=16, spring="hair_long;limit=12")

    # --- bangs: separate pointed clumps parting over the forehead (skin shows between them),
    #     roots hidden under the crown
    bangs = [
        ("hair_front_1", [(468, 150), (458, 200), (450, 236), (446, 262)], 28, 30, (468, 158)),
        ("hair_front_2", [(490, 150), (488, 196), (494, 230), (504, 254)], 30, 30, (490, 158)),
        ("hair_front_3", [(508, 154), (514, 192), (522, 224), (530, 244)], 20, 20, (508, 160)),
        ("hair_front_4", [(552, 140), (572, 176), (584, 206), (590, 234)], 34, 36, (556, 148)),
        ("hair_front_5", [(574, 136), (602, 168), (618, 200), (626, 230)], 36, 36, (578, 144)),
        ("hair_front_6", [(612, 150), (630, 204), (638, 250), (636, 290)], 28, 30, (616, 158)),
    ]
    for i, (pid, cp, w0, wm, piv) in enumerate(bangs):
        part(pid, hair_part([C(cp, w0, wm, "top" if i in (1, 3, 4) else "mid", gloss=(0.05, 0.16) if i in (3, 4) else None)],
                            sil_w=2.6, sil_col=HAIR["inner"]),
             parent="head", pivot=piv, z=111 + i)

    # --- crown: clumps flowing from a side part (near side), glossy "angel ring" band
    crown_specs = [
        C([(498, 92), (470, 112), (448, 152), (438, 206)], 56, 60, "mid", lines=2),
        C([(500, 92), (484, 124), (470, 162), (464, 196)], 46, 48, "mid"),
        C([(504, 90), (548, 90), (594, 112), (628, 152), (642, 198)], 64, 70, "mid", lines=2),
        C([(504, 94), (538, 108), (574, 134), (602, 172)], 54, 56, "top"),
        C([(500, 96), (506, 124), (514, 152), (520, 176)], 44, 46, "top"),
        C([(504, 96), (532, 118), (556, 146), (570, 176)], 48, 50, "top"),
        C([(496, 98), (484, 130), (476, 160), (472, 182)], 38, 40, "top"),
    ]
    base = smooth([(444, 236), (428, 176), (444, 118), (496, 84), (560, 80), (614, 102), (640, 150), (640, 204),
                   (600, 170), (520, 162), (470, 176)], True)
    shapes = [base]
    bodies = [path(base, HAIR_LAYERS["mid"][1])]
    for sp in crown_specs:
        dd, body = clump(**sp)
        shapes.append(dd)
        bodies.append(body)
    union = " ".join(shapes)
    band_top = [(440, 150), (470, 128), (510, 114), (556, 112), (600, 124), (630, 146)]
    band_bot = [(630, 160), (612, 150), (598, 162), (584, 146), (566, 158), (548, 142), (528, 156), (510, 144), (490, 160), (470, 150), (452, 168)]
    band = poly(band_top + band_bot)
    glow = d.radial([(0, "#ffe2a0", 0.55), (1, "#ffe2a0", 0.0)], 540, 70, 120, 1.0, 0.6)
    s = underlay(shapes, W_SIL * 2.0, HAIR["sil"]) + "".join(bodies)
    s += group(path(band, HAIR["gloss"], op=0.92) + ink(taper([(456, 150), (510, 124), (560, 122), (620, 146)], 5, "both"), "#ffffff", 0.95)
               + path(ellipse_d(540, 80, 120, 70), glow), clip=d.clip(union))
    part("hair_top", s, parent="head", pivot=(530, 170), z=118)

    # --- near side lock: upper part beside the face (under the crown), lower part drapes over
    #     the shoulder and chest; a gold cuff hides the joint
    part("hair_side_r", hair_part([
        C([(444, 196), (432, 260), (424, 330), (426, 440)], 26, 30, "mid"),
        C([(456, 200), (450, 270), (446, 340), (452, 440)], 18, 22, "top"),
    ], sil_w=3.4), parent="head", pivot=(448, 220), z=109, spring="hair;limit=8")
    s = hair_part([
        C([(432, 414), (440, 490), (462, 570), (486, 660), (496, 750), (488, 840), (466, 910)], 34, 40, "mid", lines=2),
        C([(424, 420), (430, 500), (446, 580), (462, 660), (466, 740), (456, 800)], 16, 18, "mid"),
        C([(446, 416), (458, 494), (480, 574), (502, 664), (510, 754), (500, 846)], 20, 26, "top", gloss=(0.14, 0.24)),
    ], extra=flyaway([(470, 860), (452, 920), (440, 960)], 1.8), sil_w=3.2, sil_col="#5a3e34")
    s += gold_band([(418, 418), (438, 430), (462, 420)], 16) + gem(439, 428, 5.5) + leaf(440, 440, 95, 22, 4)
    part("hair_side_r_2", s, parent="hair_side_r", pivot=(438, 420), z=130, spring="hair;limit=14")
    part("hair_side_l", hair_part([
        C([(626, 200), (640, 290), (656, 400), (668, 500), (670, 580)], 22, 26, "under"),
        C([(612, 200), (622, 280), (634, 380), (646, 480), (652, 560), (646, 630)], 26, 30, "mid"),
    ]), parent="head", pivot=(618, 230), z=36, spring="hair;limit=12")


# ------------------------------------------------------------------ wings: layered feather groups
def _rnd(i, salt=0):
    return ((i * 7919 + salt * 104729) % 1000) / 1000.0


def feather3(B, ang, L, w, curl=0.0, kind="flight", flip=1, salt=0):
    """One feather. kind: 'primary' (gold tip), 'flight', 'covert' (rounded), 'scale'."""
    n = 12
    left, right, shaft = [], [], []
    cx, cy = B
    for i in range(n + 1):
        t = i / n
        a = math.radians(ang + curl * t * t * flip)
        if i > 0:
            cx += math.cos(a) * L / n
            cy += math.sin(a) * L / n
        shaft.append((cx, cy))
        if kind in ("covert", "scale"):
            prof = math.sqrt(max(0.0, 1 - (max(t - 0.5, 0) / 0.5) ** 2)) * (0.45 + 0.55 * min(1, t * 2.5))
        else:
            prof = math.sin(math.pi * min(1.0, 0.12 + t * 0.92)) ** 0.45
        hw = w * prof
        nx, ny = -math.sin(a), math.cos(a)
        left.append((cx + nx * hw * 1.15, cy + ny * hw * 1.15))
        right.append((cx - nx * hw * 0.85, cy - ny * hw * 0.85))
    o = left + right[::-1]
    dd = poly(o)
    tip = shaft[-1]
    if kind == "scale":
        g = d.linear([(0, FEA["s1"]), (1, FEA["b"])], B[0], B[1], tip[0], tip[1])
    else:
        g = d.linear([(0, FEA["s2"]), (0.45, FEA["b"]), (1, "#ffffff")], B[0], B[1], tip[0], tip[1])
    s = path(dd, g)
    s += path(poly(right + shaft[::-1]), FEA["s1"], op=0.7)          # shadowed vane
    if kind == "primary":
        k = int(len(left) * 0.62)
        gt = d.linear([(0, FEA["tip"], 0.0), (0.35, FEA["tip"]), (1, FEA["tip2"])], left[k][0], left[k][1], tip[0], tip[1])
        s += path(poly(left[k:] + right[k:][::-1]), gt)
    s += path(dd, "none", FEA["ln"], 1.3)
    if kind != "scale":
        s += tline(shaft[1:-1], 2.2 if kind != "covert" else 1.6, FEA["s3"], "start", op=0.85)
    return dd, s


def wing3(edge, dir_root, dir_tip, L_root, L_tip, n_prim=8, n_sec=8, curl=-14.0, flip=1, scale=1.0, salt=1):
    e = sample(edge, False, 1.0, 20)
    acc = [0.0]
    for i in range(1, len(e)):
        acc.append(acc[-1] + math.hypot(e[i][0] - e[i - 1][0], e[i][1] - e[i - 1][1]))
    total = acc[-1]

    def at(s):
        tgt = s * total
        for i in range(1, len(e)):
            if acc[i] >= tgt:
                kk = (tgt - acc[i - 1]) / max(acc[i] - acc[i - 1], 1e-6)
                return lerp_pt(e[i - 1], e[i], kk)
        return e[-1]

    def flen(s):
        return lerp(L_root, L_tip, s ** 0.85)

    shapes, bodies = [], []

    def add(res):
        shapes.append(res[0])
        bodies.append(res[1])
    # primaries (outer half, longest, gold tips): outermost first
    for i in range(n_prim - 1, -1, -1):
        s = 0.55 + 0.45 * i / (n_prim - 1)
        jit = 0.92 + 0.14 * _rnd(i, salt)
        ang = lerp(dir_root, dir_tip, s ** 1.1) + (_rnd(i, salt + 3) - 0.5) * 6 * flip
        add(feather3(at(s), ang, flen(s) * jit, flen(s) * 0.1 * scale, curl, "primary", flip))
    # secondaries (inner half)
    for i in range(n_sec - 1, -1, -1):
        s = 0.06 + 0.5 * i / (n_sec - 1)
        jit = 0.9 + 0.12 * _rnd(i, salt + 5)
        ang = lerp(dir_root, dir_tip, s ** 1.1) + (_rnd(i, salt + 7) - 0.5) * 5 * flip
        add(feather3(at(s), ang, flen(s) * 0.82 * jit, flen(s) * 0.1 * scale, curl * 0.7, "flight", flip))
    # greater coverts over the flight feather bases
    m = n_prim + n_sec - 3
    for i in range(m - 1, -1, -1):
        s = 0.04 + 0.92 * i / (m - 1)
        ang = lerp(dir_root, dir_tip, s ** 1.1) - 8 * flip
        add(feather3(at(s), ang, flen(s) * (0.42 + 0.05 * _rnd(i, salt + 9)), flen(s) * 0.12 * scale, curl * 0.4, "covert", flip))
    # lesser coverts: two rows of small scales near the leading edge
    for row, (frac, cnt) in enumerate(((0.24, m + 3), (0.14, m + 6))):
        for i in range(cnt - 1, -1, -1):
            s = 0.02 + 0.9 * i / (cnt - 1)
            ang = lerp(dir_root, dir_tip, s ** 1.1) - 14 * flip
            add(feather3(at(s), ang, flen(s) * frac, flen(s) * frac * 0.42 * scale, 0, "scale", flip))
    # leading edge
    top = sample(edge, False, 1.0, 10)
    lower = []
    for i, p in enumerate(top):
        a = top[max(i - 1, 0)]
        b = top[min(i + 1, len(top) - 1)]
        dx, dy = b[0] - a[0], b[1] - a[1]
        ln = math.hypot(dx, dy) or 1
        t = i / (len(top) - 1)
        ww = L_root * 0.14 * (1 - 0.7 * t) * (1.0 + 0.25 * math.sin(i * 2.1))
        lower.append((p[0] - dy / ln * ww * flip, p[1] + dx / ln * ww * flip))
    lead = poly(top + lower[::-1])
    shapes.append(lead)
    bodies.append(path(lead, FEA["b"]) + tline(top, L_root * 0.05, "#ffffff", op=0.95) + path(lead, "none", FEA["ln"], 1.3))
    return underlay(shapes, 5.6, FEA["sil"]) + "".join(bodies)


def wings():
    part("wing_lower_l", wing3([(588, 770), (672, 804), (752, 868), (820, 960)], 95, 42, 100, 210, 7, 6, curl=18, flip=-1, salt=2),
         parent="chest", pivot=(588, 770), z=10)
    part("wing_upper_l", wing3([(596, 560), (646, 454), (722, 360), (810, 276), (862, 240)], 74, -18, 122, 270, 9, 8, curl=18, flip=-1, salt=3),
         parent="chest_upper", pivot=(596, 560), z=12)
    part("wing_lower_r", wing3([(470, 776), (384, 812), (292, 886), (204, 996)], 85, 138, 106, 250, 8, 7, curl=-18, salt=4),
         parent="chest", pivot=(470, 776), z=22)
    part("wing_upper_r", wing3([(462, 566), (412, 456), (330, 348), (240, 252), (178, 210)], 108, 198, 132, 280, 9, 8, curl=-18, salt=5),
         parent="chest_upper", pivot=(462, 566), z=24)


def head_wings():
    part("wing_head_l", wing3([(606, 206), (630, 166), (658, 128), (688, 100)], 30, -36, 50, 96, 5, 3, curl=14, flip=-1, salt=6),
         parent="head", pivot=(606, 206), z=14)
    part("wing_head_r", wing3([(444, 214), (420, 170), (392, 128), (360, 96)], 150, 216, 54, 104, 5, 3, curl=-14, salt=7),
         parent="head", pivot=(444, 214), z=98)


# ------------------------------------------------------------------ halo: crown of sunrays behind the head
HALO_C = (522, 236)
HALO_RX, HALO_RY = 165, 152


def halo():
    cx, cy = HALO_C
    glow = d.radial([(0, "#fff6d8", 0.75), (0.45, "#ffe39a", 0.3), (1, "#ffd36b", 0.0)], cx, cy, 220)
    s = path(ellipse_d(cx, cy, 220, 220), glow)
    n = 24
    for i in range(n):
        a = math.radians(-90 + 360.0 * i / n)
        if math.sin(a) > 0.55:
            continue
        base = (cx + math.cos(a) * HALO_RX, cy + math.sin(a) * HALO_RY)
        L = 96 if i % 2 == 0 else 52
        if i == 0:
            L = 104
        if math.sin(a) < -0.2:
            L = min(L, (base[1] - 8.0) / max(-math.sin(a), 0.2))
        tip = (cx + math.cos(a) * (HALO_RX + L), cy + math.sin(a) * (HALO_RY + L))
        w = 12 if i % 2 == 0 else 7
        ux, uy = math.cos(a), math.sin(a)
        nx, ny = -uy, ux
        tri = [(base[0] + nx * w, base[1] + ny * w), tip, (base[0] - nx * w, base[1] - ny * w)]
        gg = d.linear([(0, GOLD["s1"]), (0.5, GOLD["b"]), (1, GOLD["hi"])], base[0], base[1], tip[0], tip[1])
        s += path(poly(tri), gg, GOLD["ln"], 2.2)
        s += ink(taper([lerp_pt(base, tip, 0.12), lerp_pt(base, tip, 0.85)], w * 0.45, "start"), GOLD["hi"], 0.9)
        if i % 2 == 0:
            s += path(ellipse_d(tip[0], tip[1], 5, 5), GOLD["hi"], GOLD["ln"], 1.4)
    ring = [(cx + math.cos(math.radians(k * 15)) * HALO_RX, cy + math.sin(math.radians(k * 15)) * HALO_RY) for k in range(25)]
    s += gold_band(ring, 14)
    s += gold_band([(cx + math.cos(math.radians(k * 15)) * (HALO_RX - 18), cy + math.sin(math.radians(k * 15)) * (HALO_RY - 18)) for k in range(25)], 4, hi=False)
    for k in range(8):
        a = math.radians(-90 + k * 45)
        s += gem(cx + math.cos(a) * HALO_RX, cy + math.sin(a) * HALO_RY, 7 if k % 2 == 0 else 5)
    part("halo", s, parent="head", pivot=HALO_C, z=26, spring="accessory;limit=4;g=0")


# ------------------------------------------------------------------ sceptre: floating golden tuning fork
def sceptre():
    x = SC_X
    glow = d.radial([(0, "#ffffff", 0.9), (0.35, "#bfeaff", 0.45), (1, "#8fd3f2", 0.0)], x, 236, 100)
    s = path(ellipse_d(x, 236, 100, 100), glow)
    g = d.linear([(0, GOLD["s1"]), (0.35, GOLD["b"]), (0.6, GOLD["hi"]), (1, GOLD["s1"])], x - 40, 0, x + 40, 0)
    fd = smooth([(x - 36, 152, "c"), (x - 22, 152, "c"), (x - 22, 326), (x, 350), (x + 22, 326), (x + 22, 152, "c"),
                 (x + 36, 152, "c"), (x + 36, 336), (x + 10, 372), (x - 10, 372), (x - 36, 336)], True, 0.9)
    s += cel(d, fd, g, tones=[(GOLD["s1"], 6, 0)], hi=(GOLD["hi"], -4, 0), lw=3.2, outline=GOLD["ln"])
    s += tline([(x - 31, 170), (x - 31, 320)], 3, "#ffffff", op=0.8) + tline([(x + 27, 170), (x + 27, 320)], 2, "#ffffff", op=0.6)
    for px in (x - 29, x + 29):
        s += path(ellipse_d(px, 146, 11, 11), GOLD["b"], GOLD["ln"], 2.6) + path(ellipse_d(px - 3, 142, 4, 3), "#ffffff", op=0.9)
    for side in (-1, 1):
        for k in range(3):
            dd, body = feather3((x + side * 16, 370 - k * 6), 90 - side * (100 - k * 22), 46 - k * 9, 5.5 - k * 0.6, 10, "covert", side)
            s += path(dd, GOLD["b"], GOLD["ln"], 1.6) + crescent(dd, 0, -3, GOLD["s1"]) if False else path(dd, GOLD["b"], GOLD["ln"], 1.6)
    st = smooth([(x - 8, 368), (x + 8, 368), (x + 6, 640), (x - 6, 640)], True, 0.5)
    sg = d.linear([(0, GOLD["s2"]), (0.4, GOLD["b"]), (0.7, GOLD["hi"]), (1, GOLD["s1"])], x - 8, 0, x + 8, 0)
    s += path(st, sg, GOLD["ln"], 2.6)
    for y, r in ((400, 13), (470, 9), (540, 11), (600, 9)):
        s += path(ellipse_d(x, y, r, r * 0.45), GOLD["b"], GOLD["ln"], 2.0) + path(ellipse_d(x - r * 0.3, y - 2, r * 0.4, 1.6), "#ffffff", op=0.8)
    s += gem(x, 438, 9)
    s += path(smooth([(x, 640), (x + 14, 660), (x, 690, "c"), (x - 14, 660)]), GOLD["b"], GOLD["ln"], 2.4) + gem(x, 662, 6)
    s += gem(x, 236, 26)
    s += sparkle(x + 2, 236, 46, "#ffffff", 0.85) + sparkle(x - 34, 196, 12, "#fff6d0", 0.9) + sparkle(x + 40, 290, 9, "#ffffff", 0.8)
    part("weapon", s, parent="hand_l", pivot=(x, 690), z=140, tip=(x, 236))
    rib = [(x - 6, 380), (x - 30, 430), (x - 18, 520), (x - 44, 600), (x - 30, 670)]
    part("ribbon_weapon", cel(d, taper(rib, 24, "start", power=0.5), SKY["b"], tones=[(SKY["s1"], 8, -4)], lw=2.0, outline=SKY["ln"]),
         parent="weapon", pivot=(x - 6, 380), z=139, spring="ribbon;limit=25")


# ------------------------------------------------------------------ head + face
HEAD = [(466, 150), (448, 196), (442, 246), (447, 288), (460, 320), (484, 345), (517, 361), (549, 368, "c"),
        (567, 358), (584, 340), (598, 314), (607, 290), (612, 266), (614, 248), (610, 232), (612, 212),
        (607, 172), (586, 140), (532, 126), (490, 134)]
EYE_R = (494, 254)   # near eye (her right)
EYE_L = (580, 252)   # far eye
BANG_CPS = [([(468, 150), (458, 200), (450, 236), (446, 262)], 28, 30), ([(490, 150), (488, 196), (494, 230), (504, 254)], 30, 30),
            ([(508, 154), (514, 192), (522, 224), (530, 244)], 20, 20), ([(552, 140), (572, 176), (584, 206), (590, 234)], 34, 36),
            ([(574, 136), (602, 168), (618, 200), (626, 230)], 36, 36), ([(612, 150), (630, 204), (638, 250), (636, 290)], 28, 30)]


def head():
    hd = smooth(HEAD, True, 1.0)
    ear = smooth([(462, 256), (446, 248), (436, 258), (436, 280), (444, 298), (458, 304), (466, 286)], True)
    s = cel(d, ear, SKIN["b"], tones=[(SKIN["s1"], 8, -4)], lw=2.6, outline=SKIN["ln"],
            lines=[ink(taper([(446, 262), (442, 278), (450, 292)], 3, "both"), SKIN["ln"], 0.7)])
    # shadows cast by the bangs and hairline on the forehead
    cast = []
    for cp, w0, wm in BANG_CPS:
        ring = clump_outline([(p[0] + 3, p[1] + 10) for p in cp], w0 * 1.1, wm * 1.1)[0]
        cast.append(path(poly([p[:2] for p in ring]), SKIN["s1"], op=0.9))
    cast.append(path(smooth([(440, 150), (470, 186), (520, 176), (560, 166), (610, 188), (620, 150)], True), SKIN["s2"], op=0.6))
    cheek_shadow = smooth([(442, 220), (462, 236), (470, 290), (492, 336), (530, 362), (470, 362), (440, 300)], True)
    eyeshadow = d.radial([(0, "#efa29c", 0.5), (1, "#efa29c", 0.0)], 494, 244, 36, 1.0, 0.55)
    eyeshadow2 = d.radial([(0, "#efa29c", 0.45), (1, "#efa29c", 0.0)], 580, 242, 28, 1.0, 0.55)
    face_glow = d.radial([(0, "#fffaf6", 0.9), (0.6, "#fde8dc", 0.0)], 576, 272, 74)
    nose_sh = smooth([(556, 258), (562, 270), (566, 290), (568, 302), (560, 300), (556, 284), (552, 266)], True)
    over = [path(cheek_shadow, SKIN["s1"], op=0.55), path(hd, face_glow),
            path(ellipse_d(494, 244, 36, 20), eyeshadow), path(ellipse_d(580, 242, 28, 15), eyeshadow2),
            path(nose_sh, SKIN["s1"], op=0.75), path(ellipse_d(568, 309, 9, 3.5, -8), SKIN["s1"], op=0.8),
            path(ellipse_d(556, 352, 16, 5, -6), SKIN["s1"], op=0.5)] + cast
    head_strokes = [
        ([(466, 150), (448, 196), (442, 246), (447, 288), (460, 320), (484, 345), (517, 361), (549, 368)], W_SH, OUT, "end"),
        ([(549, 368), (567, 358), (584, 340), (598, 314), (607, 290), (612, 266), (614, 248), (610, 232), (612, 212), (607, 172)], W_LIT, OUT, "start"),
    ]
    s += cel(d, hd, SKIN["b"], tones=[(SKIN["s1"], 16, -6, 0.75), (SKIN["s2"], 6, -2, 0.5)], rim=(SKIN["rim"], 3, 0, 0.9),
             over=over, strokes=head_strokes,
             lines=[tline([(562, 268), (566, 284), (571, 297)], 2.6, SKIN["ln"], "end", op=0.8),
                    tline([(562, 303), (569, 306), (576, 300)], 2.6, SKIN["ln"], op=0.95),
                    path(ellipse_d(574, 291, 2.6, 2.0), "#ffffff", op=0.9),
                    path(ellipse_d(596, 268, 7, 3, -30), "#ffffff", op=0.5)])
    part("head", s, parent="neck", pivot=(502, 336), z=100)


def eye_closed(c, w, near):
    """Closed, serene eye: thick curved upper lash line with a flick at the outer corner,
    lash strands and a thin lower crease."""
    cx, cy = c
    sg = -1 if near else 1
    inner = (cx - sg * w * 0.5, cy - 2)
    outer = (cx + sg * w * 0.55, cy - 4)
    arc = [inner, (cx - sg * w * 0.22, cy + 6), (cx + sg * w * 0.06, cy + 8.5), (cx + sg * w * 0.34, cy + 5), outer]
    s = ink(taper(arc, 8.5, "both", power=0.5), "#33223e")
    s += ink(taper([outer, (outer[0] + sg * 12, outer[1] + 2), (outer[0] + sg * 21, outer[1] - 6)], 4.8, "start"), "#33223e")
    pts = sample(arc, False, 1.0, 10)
    for fx_, ln in ((0.32, 9), (0.5, 12), (0.66, 13), (0.82, 11)):
        p = pts[int(fx_ * (len(pts) - 1))]
        s += ink(taper([p, (p[0] + sg * 3, p[1] + ln * 0.6), (p[0] + sg * 8, p[1] + ln)], 2.6, "start"), "#33223e", 0.9)
    s += ink(taper([(cx - sg * w * 0.3, cy + 13), (cx + sg * w * 0.05, cy + 15), (cx + sg * w * 0.32, cy + 12)], 1.6, "both"), SKIN["ln"], 0.45)
    s += ink(taper([(cx - sg * w * 0.36, cy - 11), (cx, cy - 14), (cx + sg * w * 0.42, cy - 10)], 2.2, "both"), SKIN["ln"], 0.5)
    return s


def eye_open(c, w, h, near, irx, iry):
    cx, cy = c
    sg = -1 if near else 1
    inner = (cx - sg * w * 0.5, cy + 1)
    outer = (cx + sg * w * 0.52, cy - 4)
    top = [inner, (cx - sg * w * 0.18, cy - h * 0.55), (cx + sg * w * 0.16, cy - h * 0.6), outer]
    bot = [outer, (cx + sg * w * 0.2, cy + h * 0.42), (cx - sg * w * 0.18, cy + h * 0.45), inner]
    white = smooth(top + bot[1:-1], True)
    s = path(white, "#fbfaff")
    ic = (cx + sg * 1.5, cy + 2)
    ig = d.linear([(0, "#5a3416"), (0.35, "#c98a2a"), (0.62, "#f2c75e"), (0.85, "#9fd8f2"), (1, "#5aa6d8")], ic[0], ic[1] - iry, ic[0], ic[1] + iry)
    inn = path(ellipse_d(ic[0], ic[1], irx, iry), ig, "#3a2414", 1.6)
    inn += path(ellipse_d(ic[0], ic[1] + 1, irx * 0.42, iry * 0.55), "#3a1e0c", op=0.9)
    inn += path(ellipse_d(ic[0], ic[1] + iry * 0.45, irx * 0.7, iry * 0.28), "#cdf2ff", op=0.45)
    inn += path(smooth([(cx - w, cy - h), (cx + w, cy - h), (cx + w, cy - h * 0.15), (cx, cy - h * 0.02), (cx - w, cy - h * 0.15)]), "#7d6aa0", op=0.35)
    inn += path(ellipse_d(ic[0] - irx * 0.38, ic[1] - iry * 0.42, irx * 0.36, iry * 0.25, -20), "#ffffff")
    inn += path(ellipse_d(ic[0] + irx * 0.4, ic[1] + iry * 0.3, irx * 0.16, iry * 0.12), "#ffffff", op=0.85)
    s += group(inn, clip=d.clip(white))
    s += ink(taper(top + [(outer[0] + sg * 14, outer[1] - 6)], 8, "both", power=0.45), "#2f2040")
    s += ink(taper([outer, (outer[0] + sg * 9, outer[1] + 3), (outer[0] + sg * 16, outer[1] + 1)], 3.4, "start"), "#2f2040")
    s += ink(taper(bot[1:], 2.4, "both"), SKIN["ln"], 0.8)
    s += ink(taper([(cx - sg * w * 0.34, cy - h * 0.95), (cx, cy - h * 1.05), (cx + sg * w * 0.4, cy - h * 0.86)], 2.2, "both"), SKIN["ln"], 0.55)
    return s


def face():
    for side, c, w, near in (("r", EYE_R, 56, True), ("l", EYE_L, 44, False)):
        z = 104 if side == "r" else 105
        part("eye_%s_closed" % side, eye_closed(c, w, near), slot="eye_" + side, variant="closed", default="1",
             parent="head", pivot=c, z=z)
        alt("eye_%s_open" % side, eye_open(c, w, 30 if near else 28, near, 14 if near else 11, 17 if near else 16),
            slot="eye_" + side, variant="open")
        sg = -1 if near else 1
        hurt = ink(taper([(c[0] - sg * w * 0.45, c[1] - 6), (c[0], c[1] + 2), (c[0] + sg * w * 0.45, c[1] - 2)], 6.5, "both"), "#33223e")
        hurt += ink(taper([(c[0] - sg * w * 0.4, c[1] + 8), (c[0] + sg * w * 0.3, c[1] + 6)], 2.4, "both"), SKIN["ln"], 0.7)
        alt("eye_%s_hurt" % side, hurt, slot="eye_" + side, variant="hurt")
        sm = ink(taper([(c[0] - sg * w * 0.48, c[1] + 4), (c[0], c[1] - 7), (c[0] + sg * w * 0.5, c[1] + 2)], 7, "both"), "#33223e")
        sm += ink(taper([(c[0] + sg * w * 0.5, c[1] + 2), (c[0] + sg * w * 0.68, c[1] - 4)], 3.2, "start"), "#33223e")
        alt("eye_%s_smile" % side, sm, slot="eye_" + side, variant="smile")
    part("brow_r", ink(taper([(464, 222), (486, 211), (510, 209), (524, 214)], 5.2, "both", power=0.7), "#b78f56"),
         parent="head", pivot=(494, 214), z=106)
    part("brow_l", ink(taper([(558, 210), (580, 206), (598, 212), (607, 221)], 4.4, "both", power=0.7), "#b78f56"),
         parent="head", pivot=(582, 210), z=107)
    bl = d.radial([(0, "#f59c9c", 0.55), (1, "#f59c9c", 0.0)], 488, 294, 34, 1.0, 0.5)
    bl2 = d.radial([(0, "#f59c9c", 0.5), (1, "#f59c9c", 0.0)], 592, 290, 24, 1.0, 0.5)
    b = path(ellipse_d(488, 294, 34, 17), bl) + path(ellipse_d(592, 290, 24, 12), bl2)
    for k in range(3):
        b += ink(taper([(476 + k * 9, 298), (482 + k * 9, 289)], 1.8, "both"), "#e57f86", 0.5)
    part("blush", b, parent="head", pivot=(540, 292), z=102)
    # mouth: alluring half smile, upper lip shade, fuller lower lip with gradient + gloss
    lg = d.linear([(0, "#f1a19f"), (1, "#d67479")], 556, 336, 556, 348)
    m = path(smooth([(541, 331), (552, 328), (558, 330), (566, 327), (574, 324), (566, 333), (552, 334)]), "#d27378", op=0.9)
    m += path(smooth([(545, 337), (558, 335), (569, 339), (560, 347), (549, 344)]), lg)
    m += ink(taper([(537, 331), (550, 335), (562, 334), (576, 324)], 3.4, "both"), "#934347")
    m += ink(taper([(576, 324), (581, 319)], 2.2, "start"), "#934347", 0.8)
    m += ink(taper([(548, 347), (558, 349), (567, 344)], 1.8, "both"), "#c46b6e", 0.5)
    m += path(ellipse_d(557, 340, 5, 1.6, -6), "#ffffff", op=0.85) + path(ellipse_d(563, 339.5, 1.6, 1.0), "#ffffff", op=0.7)
    part("mouth", m, parent="head", pivot=(556, 334), z=103)
    om = smooth([(540, 330), (556, 327), (574, 325), (570, 341), (556, 349), (544, 341)])
    o = path(om, "#7a2f3e", "#934347", 2.4) + path(smooth([(546, 341), (556, 338), (566, 341), (556, 347)]), "#d7737d")
    o += path(smooth([(544, 330.5), (572, 327), (568, 333), (548, 334)]), "#fffafa", op=0.9)
    alt("mouth_open", o, slot="mouth", variant="open")
    sm = ink(taper([(536, 327), (548, 335), (562, 335), (576, 322)], 3.6, "both"), "#934347")
    sm += path(smooth([(548, 336), (562, 336), (556, 341)]), "#7a2f3e", op=0.85)
    alt("mouth_smile", sm, slot="mouth", variant="smile")
    alt("mouth_hurt", ink(taper([(540, 336), (548, 331), (556, 336), (564, 331), (572, 334)], 3.4, "both"), "#934347"),
        slot="mouth", variant="hurt")


# ------------------------------------------------------------------ neck, torso
def neck():
    nk = smooth([(476, 296), (504, 332), (548, 362), (562, 356), (566, 400), (574, 440), (600, 460), (520, 474),
                 (446, 462), (466, 436), (472, 380)], True)
    chin_sh = smooth([(474, 300), (520, 352), (550, 369), (568, 358), (566, 396), (540, 400), (500, 380), (474, 342)], True)
    s = skin(nk, ((14, -4), (6, -2)), over=[path(chin_sh, SKIN["s1"], op=0.95), path(chin_sh, SKIN["s2"], op=0.4),
                                             path(smooth([(474, 342), (500, 380), (490, 440), (470, 430)]), SKIN["s1"], op=0.6)],
             strokes=[([(476, 296), (472, 380), (466, 436)], W_SH, OUT, "end"), ([(562, 356), (566, 400), (574, 440)], W_LIT, OUT)])
    s += gold_band([(470, 404), (520, 418), (568, 404)], 9) + gold_band([(472, 414), (520, 428), (566, 414)], 3, hi=False)
    for k in range(5):
        s += leaf(486 + k * 17, 420 + (2 if k in (1, 3) else 0), 90, 12, 3.2)
    s += path(smooth([(514, 424), (526, 424), (528, 446, "c"), (520, 458, "c"), (512, 446, "c")]), GOLD["b"], GOLD["ln"], 1.8) + gem(520, 438, 5.5)
    s += chain([(482, 414), (490, 430), (497, 446)], 6) + chain([(558, 412), (562, 428), (564, 444)], 6)
    part("neck", s, parent="chest_upper", pivot=(520, 444), z=81)


def chest_upper():
    pts = [(470, 436), (438, 448), (410, 464), (394, 492), (398, 530), (420, 552), (446, 560), (500, 572), (548, 578),
           (600, 568), (628, 552), (648, 524), (652, 498), (636, 470), (598, 448), (566, 436)]
    sk = smooth(pts, True)
    warm = d.radial([(0, "#ffd987", 0.35), (1, "#ffd987", 0.0)], 520, 420, 170, 1.0, 0.6)
    s = skin(sk, ((20, -6), (8, -3)),
             strokes=[([(470, 436), (438, 448), (410, 464), (394, 492)], W_SH, OUT, "end"), ([(566, 436), (598, 448), (636, 470), (652, 498)], W_LIT, OUT, "end")],
             over=[path(smooth([(394, 492), (440, 516), (470, 580), (400, 580)]), SKIN["s1"], op=0.6),
                   path(smooth([(452, 488), (488, 496), (524, 490), (520, 500), (486, 506), (454, 500)]), SKIN["s1"], op=0.7),
                   path(smooth([(566, 488), (596, 484), (620, 492), (616, 500), (594, 494), (568, 498)]), SKIN["s1"], op=0.6),
                   path(ellipse_d(618, 494, 22, 12, -15), SKIN["hi"], op=0.7), path(sk, warm)],
             lines=[tline([(452, 482), (488, 490), (524, 484)], 2.6, SKIN["ln"], op=0.55),
                    tline([(566, 482), (596, 478), (620, 486)], 2.2, SKIN["ln"], op=0.5),
                    tline([(549, 500), (550, 540), (550, 580)], 2.4, SKIN["s2"], op=0.5)])
    pn = smooth([(492, 446), (506, 446), (514, 500), (522, 586), (450, 586), (454, 552), (478, 500)], True)
    pf = smooth([(558, 446), (572, 446), (590, 496), (618, 540), (636, 586), (582, 586), (572, 510)], True)
    s += satin(pn, ((16, -4), (6, -2)), strokes=[([(492, 446), (478, 500), (454, 552), (450, 586)], W_SH, OUT), ([(506, 446), (514, 500), (522, 586)], W_IN, WHITE["ln"])])
    s += satin(pf, ((12, -4), (5, -2)), strokes=[([(572, 446), (590, 496), (618, 540), (636, 586)], W_LIT, OUT), ([(558, 446), (572, 510), (582, 586)], W_IN, WHITE["ln"])])
    s += gold_line([(506, 450), (514, 506), (521, 584)], 4) + gold_line([(558, 450), (572, 512), (581, 584)], 4)
    for t in (0.3, 0.65):
        p1 = lerp_pt((506, 450), (521, 584), t)
        p2 = lerp_pt((558, 450), (581, 584), t)
        s += leaf(p1[0] + 2, p1[1], 30, 14, 3.4) + leaf(p2[0] - 2, p2[1], 150, 14, 3.4)
    s += gold_band([(519, 578), (550, 588), (581, 578)], 4.5) + gem(550, 588, 4.5) + scroll(526, 580, 0.5, 1) + scroll(574, 580, 0.5, -1)
    for cx, cy in ((499, 447), (565, 445)):
        s += path(ellipse_d(cx, cy, 7, 6), "none", GOLD["ln"], 4.5) + path(ellipse_d(cx, cy, 7, 6), "none", GOLD["b"], 2.6)
    part("chest_upper", s, parent="chest", pivot=(536, 640), z=82)
    part("clavicle_r", "", parent="chest_upper", pivot=(500, 470))
    part("clavicle_l", "", parent="chest_upper", pivot=(566, 466))


def chest():
    body = smooth([(440, 548), (520, 548), (612, 548), (650, 586), (664, 622), (654, 662), (630, 684), (608, 712),
                   (600, 792), (470, 792), (464, 720), (452, 680), (436, 620)], True)
    vsk = smooth([(514, 546), (584, 546), (578, 610), (566, 690), V_BOT, (540, 690), (526, 610)], True)
    s = path(body, SKIN["b"])
    s += cel(d, vsk, SKIN["b"], tones=[(SKIN["s1"], 12, -4, 0.7)], hi=(SKIN["hi"], -6, 6, 0.6), lw=0,
             over=[path(smooth([(522, 552), (540, 600), (546, 660), (536, 640), (524, 600)]), SKIN["s1"], op=0.85),
                   path(smooth([(578, 552), (566, 600), (560, 650), (570, 620)]), SKIN["s1"], op=0.5),
                   ink(taper([(548, 600), (550, 646), (552, 700)], 4, "both"), SKIN["s2"], 0.6),
                   path(ellipse_d(560, 590, 8, 22, -10), SKIN["hi"], op=0.7)])
    cup_n = smooth([(440, 548), (516, 548), (526, 600), (540, 672), (552, 744), V_BOT, (528, 786), (474, 794),
                    (464, 724), (452, 682), (436, 622)], True)
    cup_f = smooth([(582, 548), (612, 548), (650, 584), (664, 622), (654, 662), (630, 686), (608, 712), (600, 794),
                    (566, 782), V_BOT, (556, 744), (566, 672), (578, 600)], True)
    ub_n = smooth([(436, 628), (462, 664), (496, 680), (528, 672), (546, 650), (552, 730), (500, 726), (448, 710)], True)
    ub_f = smooth([(560, 668), (590, 688), (626, 690), (650, 668), (656, 704), (604, 736), (560, 726)], True)
    s += satin(cup_n, ((24, -6), (9, -2)),
               over=[path(ub_n, WHITE["s1"], op=0.9), path(smooth([(444, 650), (494, 682), (540, 662), (540, 690), (494, 700), (450, 680)]), WHITE["s2"], op=0.55),
                     path(ellipse_d(502, 600, 28, 17, -15), "#ffffff", op=0.95),
                     fold([(470, 720), (476, 760), (478, 790)], 8, 0.7)],
               strokes=[([(440, 548), (436, 622), (452, 682), (464, 724), (474, 794)], W_SH, OUT),
                        ([(444, 650), (470, 670), (496, 680), (520, 676), (540, 660)], W_IN, WHITE["ln"])])
    s += satin(cup_f, ((16, -6), (6, -2)),
               over=[path(ub_f, WHITE["s1"], op=0.9), path(smooth([(566, 670), (600, 690), (636, 686), (640, 708), (600, 714), (566, 696)]), WHITE["s2"], op=0.5),
                     path(ellipse_d(626, 598, 19, 13, -25), "#ffffff", op=0.95)],
               strokes=[([(612, 548), (650, 584), (664, 622), (654, 662), (630, 686), (608, 712), (600, 794)], W_SIL, OUT),
                        ([(566, 668), (596, 688), (630, 688), (652, 668)], W_IN, WHITE["ln"])])
    # neckline filigree: wire edging with feather leaves, bridges with sun clasps
    s += gold_line([(518, 550), (528, 610), (542, 684), (552, 760)], 4.5) + gold_line([(580, 550), (576, 610), (566, 684), (555, 760)], 4.5)
    for t in (0.2, 0.45, 0.7):
        p1 = lerp_pt((518, 550), (552, 760), t)
        p2 = lerp_pt((580, 550), (555, 760), t)
        s += leaf(p1[0] - 2, p1[1], 200, 15, 3.6) + leaf(p2[0] + 2, p2[1], -20, 15, 3.6)
    for y, x0, x1 in ((624, 530, 575), (696, 543, 564)):
        s += gold_line([(x0, y), ((x0 + x1) / 2, y + 7), (x1, y)], 3.4)
        s += scroll(x0 + 6, y + 2, 0.55, 1) + scroll(x1 - 6, y + 2, 0.55, -1)
        s += sunburst((x0 + x1) / 2, y + 8, 8, 8) + gem((x0 + x1) / 2, y + 8, 3.6)
    s += sunburst(553, 764, 16, 12) + gem(553, 764, 6.5)
    part("chest", s, parent="torso", pivot=(536, 800), z=76)


def torso():
    top = [(466, 762), (510, 772), (552, 778), (580, 774), (602, 764)]
    bot = [(470, 828), (520, 846), (556, 866), (580, 846), (604, 828)]
    band = smooth(top + [(600, 796)] + bot[::-1] + [(468, 796)], True)
    s = satin(band, ((14, -4), (6, -2)), strokes=[([(466, 762), (468, 796), (470, 828)], W_SH, OUT), ([(602, 764), (600, 796), (604, 828)], W_LIT, OUT)],
              lines=[tline([(x, 780), (x + 1, 836)], 1.6, WHITE["ln"], op=0.7) for x in (494, 516, 590)])
    s += gold_band(top, 6) + gold_band(bot, 6)
    s += sunburst(556, 818, 22, 12) + gem(556, 818, 7)
    for x, fl in ((482, -1), (594, 1)):
        s += scroll(x, 806, 0.7, fl) + scroll(x, 826, 0.6, fl)
    part("torso", s, parent="hips", pivot=(530, 960), z=80)


def hips():
    # the hips bone carries the gown panels; its own art is the gold hip chains on top
    s = chain([(472, 846), (496, 920), (548, 956), (600, 916), (604, 848)], 9)
    s += chain([(470, 852), (444, 936), (430, 1030), (436, 1100)], 9) + gem(548, 960, 6)
    s += path(smooth([(540, 960), (556, 960), (548, 992, "c")]), GOLD["b"], GOLD["ln"], 1.6)
    part("hips", s, parent="root", pivot=(520, 1066), z=74)


def hem_embroidery(pts, every=46, motif="sun"):
    c = sample(pts, False, 1.0, 20)
    out = []
    acc = 0.0
    k = 0
    for i in range(1, len(c)):
        acc += math.hypot(c[i][0] - c[i - 1][0], c[i][1] - c[i - 1][1])
        if acc >= every:
            acc = 0.0
            x, y = c[i]
            if k % 2 == 0:
                out.append(sunburst(x, y - 18, 10, 8))
            else:
                out.append(leaf(x - 2, y - 10, -110, 20, 4.5) + leaf(x + 2, y - 10, -70, 20, 4.5))
            k += 1
    return "".join(out)


def skirts():
    # sheer outer train (behind everything): luminous, embroidered hem
    tr = smooth([(440, 880), (560, 880), (640, 960), (690, 1300), (740, 1700), (790, 1984, "c"), (600, 1968),
                 (420, 1992), (230, 1978), (90, 1986, "c"), (160, 1700), (250, 1400), (330, 1100), (390, 950)], True)
    tg = d.linear([(0, "#fffdf6", 0.9), (0.5, "#fff4dc", 0.7), (1, "#fbefd8", 0.62)], 400, 900, 400, 1990)
    inner = d.radial([(0, "#ffffff", 0.55), (1, "#ffffff", 0.0)], 330, 1500, 320, 0.7, 1.0)
    s = path(tr, tg) + path(tr, inner)
    for pts in ([(380, 1000), (300, 1400), (210, 1820)], [(450, 1000), (420, 1400), (370, 1900)], [(620, 1000), (680, 1500), (730, 1900)]):
        s += ink(taper(pts, 16, "both"), "#ffffff", 0.55) + ink(taper([(p[0] + 12, p[1]) for p in pts], 3, "both"), "#d8cdee", 0.5)
    s += tline([(160, 1700), (250, 1400), (330, 1100), (390, 950)], 3, "#ffffff", op=0.9)
    s += path(tr, "none", "#d9c38c", 2.0)
    s += gold_band([(96, 1984), (230, 1974), (420, 1988), (600, 1966), (786, 1982)], 7)
    s += gold_line([(140, 1934), (240, 1926), (420, 1934), (600, 1920), (760, 1932)], 2.4)
    s += hem_embroidery([(140, 1956), (240, 1950), (420, 1958), (600, 1944), (760, 1956)])
    part("skirt_back", s, parent="hips", pivot=(500, 940), z=20, spring="cape;limit=8;k=50", bend="0.6")
    # opaque gown, near-back panel (behind the near leg), hem flaring back
    pts = [(412, 1000), (470, 1010), (480, 1140), (482, 1300), (472, 1520), (456, 1760), (446, 1960), (360, 1988),
           (286, 1972, "c"), (316, 1700), (360, 1420), (394, 1200), (404, 1100)]
    pr = smooth(pts, True)
    s = satin(pr, ((30, -8), (12, -3)),
              over=[fold([(400, 1250), (378, 1500), (346, 1800), (330, 1960)], 14, 0.85),
                    fold([(440, 1300), (430, 1600), (414, 1900)], 10, 0.7), fold([(372, 1500), (340, 1760), (310, 1950)], 8, 0.6, deep=True)],
              strokes=[([(404, 1100), (394, 1200), (360, 1420), (316, 1700), (286, 1972)], W_SH, OUT),
                       ([(480, 1140), (482, 1300), (472, 1520), (456, 1760), (446, 1960)], W_IN + 0.6, OUT),
                       ([(286, 1972), (360, 1988), (446, 1960)], W_SIL, OUT)])
    s += path(smooth([(290, 1964), (330, 1950), (372, 1962), (440, 1950), (446, 1960), (360, 1988)], True), SKY["b"], SKY["ln"], 1.4)
    s += gold_band([(288, 1970), (362, 1984), (444, 1960)], 7)
    s += gold_line([(476, 1134), (480, 1400), (464, 1700), (446, 1956)], 4)
    part("skirt_r", s, parent="hips", pivot=(440, 1010), z=58, spring="cloth;limit=6")
    # opaque gown, front panel: from the cincher over the hips, covers the far leg; left edge = slit
    pts = [(466, 820), (604, 820), (626, 900), (646, 980), (654, 1040), (652, 1110), (658, 1400), (686, 1700),
           (724, 1968, "c"), (660, 1990), (600, 1976, "c"), (590, 1720), (564, 1500), (526, 1300), (478, 1142),
           (440, 1126), (410, 1104), (404, 1030), (420, 940), (452, 866)]
    pf = smooth(pts, True)
    hip_sh = smooth([(404, 1030), (420, 940), (452, 866), (470, 900), (450, 1000), (446, 1100), (410, 1104)], True)
    s = satin(pf, ((26, -8), (10, -3)),
              over=[path(hip_sh, WHITE["s1"], op=0.8), path(ellipse_d(604, 990, 30, 74, -8), "#ffffff", op=0.85),
                    fold([(500, 940), (494, 1040), (490, 1120)], 9, 0.6),
                    fold([(566, 900), (574, 1000), (584, 1110)], 8, 0.55),
                    fold([(496, 1150), (530, 1210), (556, 1300)], 10, 0.8), fold([(510, 1146), (560, 1196), (594, 1260)], 8, 0.7),
                    fold([(600, 1190), (622, 1480), (652, 1780), (676, 1960)], 16, 0.85),
                    fold([(566, 1300), (590, 1600), (614, 1940)], 12, 0.75, deep=True),
                    fold([(632, 1350), (662, 1660), (700, 1950)], 8, 0.6)],
              strokes=[([(452, 866), (420, 940), (404, 1030), (410, 1104), (440, 1126)], W_SH, OUT),
                       ([(478, 1142), (526, 1300), (564, 1500), (590, 1720), (600, 1976)], W_SIL, OUT),
                       ([(604, 820), (626, 900), (646, 980), (654, 1040), (652, 1110), (658, 1400), (686, 1700), (724, 1968)], W_LIT, OUT),
                       ([(600, 1976), (660, 1990), (724, 1968)], W_SIL, OUT)])
    s += path(smooth([(604, 1966), (650, 1972), (700, 1958), (722, 1966), (660, 1990)], True), SKY["b"], SKY["ln"], 1.4)
    s += gold_line([(442, 1128), (478, 1140), (526, 1300), (564, 1500), (591, 1720), (603, 1970)], 5)
    s += tline([(490, 1156), (536, 1310), (574, 1500), (600, 1720), (614, 1950)], 3.2, SKY["b"])
    s += gold_band([(602, 1974), (660, 1984), (722, 1966)], 7)
    s += path(smooth([(458, 1118), (482, 1106), (500, 1130), (486, 1158, "c"), (462, 1148)]), GOLD["b"], GOLD["ln"], 2.4)
    s += scroll(486, 1140, 0.8, 1) + scroll(462, 1138, 0.8, -1) + sunburst(478, 1134, 14, 10) + gem(478, 1134, 6)
    s += chain([(474, 1150), (470, 1190), (478, 1230)], 8) + gem(478, 1238, 5)
    part("skirt_l", s, parent="hips", pivot=(540, 840), z=70, spring="cloth;limit=4", bend="0.85")
    # sheer overlay over the front panel only: gradient opacity, its own edge highlight, embroidery
    so = smooth([(530, 1150), (650, 1120), (684, 1420), (726, 1700), (776, 1966, "c"), (712, 1990), (640, 1980),
                 (614, 1730), (586, 1500), (548, 1300)], True)
    sg = d.linear([(0, "#ffffff", 0.0), (0.35, "#fff8e8", 0.35), (1, "#fff3d6", 0.62)], 0, 1150, 0, 1980)
    s = path(so, sg)
    s += tline([(650, 1120), (684, 1420), (726, 1700), (776, 1966)], 3.4, "#ffffff", op=0.95)
    s += tline([(548, 1300), (586, 1500), (614, 1730), (640, 1980)], 2.2, "#ffffff", op=0.8)
    s += tline([(684, 1420), (726, 1700), (770, 1960)], 1.6, GOLD["s1"], op=0.6)
    s += gold_band([(640, 1980), (712, 1990), (776, 1966)], 5)
    s += hem_embroidery([(652, 1960), (712, 1966), (766, 1946)], 38)
    for k in range(3):
        s += leaf(650 + k * 26, 1500 + k * 140, -80, 24, 5)
    part("skirt_front", s, parent="hips", pivot=(600, 1150), z=72, spring="cloth;limit=8;w=0.5", bend="0.6")


# ------------------------------------------------------------------ arms + hands
def armlet(pts, w=12):
    c = sample(pts, False, 1.0, 6)
    mid = c[len(c) // 2]
    s = gold_band(pts, w) + gem(mid[0], mid[1], 5)
    return s + leaf(mid[0] - 10, mid[1] + 6, 120, 18, 4) + leaf(mid[0] + 10, mid[1] + 6, 60, 18, 4)


def finger(base, tip, w0, w1, bend=0.0, nail=True):
    """Slender tapered finger with a knuckle crease and a nail hint."""
    dx, dy = tip[0] - base[0], tip[1] - base[1]
    ln = math.hypot(dx, dy) or 1
    ux, uy = dx / ln, dy / ln
    nx, ny = -uy, ux
    pts = []
    for t, w in ((0.0, w0), (0.35, w0 * 0.96), (0.7, (w0 + w1) * 0.5), (0.92, w1)):
        b = math.sin(math.pi * t) * bend
        pts.append((base[0] + dx * t + nx * (w + b), base[1] + dy * t + ny * (w + b)))
    pts.append((tip[0] + ux * w1 * 0.9 + nx * bend * 0.1, tip[1] + uy * w1 * 0.9 + ny * bend * 0.1))
    for t, w in ((0.92, w1), (0.7, (w0 + w1) * 0.5), (0.35, w0 * 0.96), (0.0, w0)):
        b = math.sin(math.pi * t) * bend
        pts.append((base[0] + dx * t - nx * (w - b), base[1] + dy * t - ny * (w - b)))
    dd = smooth(pts, True, 0.9)
    s = cel(d, dd, SKIN["b"], tones=[(SKIN["s1"], 4, -3, 0.9)], lw=1.8, outline=SKIN["ln"])
    m = lerp_pt(base, tip, 0.5)
    s += tline([(m[0] - nx * w0 * 0.5, m[1] - ny * w0 * 0.5), (m[0] + nx * w0 * 0.6, m[1] + ny * w0 * 0.6)], 1.2, SKIN["ln"], op=0.45)
    if nail:
        nt = lerp_pt(base, tip, 0.88)
        s += path(ellipse_d(nt[0] + nx * bend * 0.1, nt[1] + ny * bend * 0.1, w1 * 0.55, w1 * 0.9, math.degrees(math.atan2(dy, dx)) + 90), "#ffeef0", "#e2a59c", 0.8)
    return s


def relaxed_hand(W, open_=False):
    """Hanging right hand, back of the hand toward the viewer, thumb in front."""
    def P(x, y):
        return (W[0] + x, W[1] + y)
    palm = smooth([P(-14, -4), P(16, -4), P(24, 40), P(22, 86), P(6, 96), P(-16, 90), P(-20, 44)], True)
    h = ""
    if not open_:
        h += finger(P(-12, 86), P(-10, 136), 5.4, 3.9, 3) + finger(P(-2, 92), P(2, 156), 6, 4.3, 4)
        h += finger(P(8, 94), P(14, 166), 6.2, 4.4, 5)
        h += skin(palm, ((10, -4),), strokes=[([P(-14, -4), P(-20, 44), P(-16, 90)], 2.8, OUT), ([P(16, -4), P(24, 40), P(22, 86)], 1.8, SKIN["ln"])],
                  over=[tline([P(-6, 30), P(-4, 70)], 1.4, SKIN["ln"], op=0.35), tline([P(6, 30), P(8, 72)], 1.4, SKIN["ln"], op=0.35)])
        h += finger(P(18, 88), P(28, 156), 6, 4.3, 6) + finger(P(20, 30), P(40, 102), 7, 4.8, -5)
    else:
        h += skin(palm, ((10, -4),), strokes=[([P(-14, -4), P(-20, 44), P(-16, 90)], 2.8, OUT)])
        for b, t in ((P(-12, 86), P(-30, 140)), (P(-2, 92), P(-8, 160)), (P(8, 94), P(18, 166)), (P(18, 88), P(42, 150)), (P(20, 30), P(56, 74))):
            h += finger(b, t, 6, 4.3, 0)
    h += gold_band([P(-16, 8), P(2, 14), P(22, 8)], 8) + gem(*P(2, 14), 4)
    return h


def arms():
    # ---- near arm (her right): relaxed, a little away from the waist so the curve reads
    SH, EL, WR = (420, 482), (370, 800), (380, 1062)
    side_a = [(392, 478), (376, 506), (370, 548), (370, 590), (366, 640), (362, 700), (356, 760), (350, 800)]
    side_b = [(446, 504), (446, 552), (440, 600), (430, 660), (414, 730), (400, 784), (392, 802)]
    au = limb(SH, EL, side_a, side_b, rA=30)
    s = skin(au, ((18, -4), (7, -2)), strokes=[(side_a, W_SH, OUT), (side_b[1:], W_IN + 0.6, OUT)],
             over=[path(smooth([(446, 552), (440, 600), (428, 640), (432, 590)]), SKIN["s1"], op=0.8)],
             lines=[tline([(392, 482), (380, 520)], 2.2, SKIN["ln"], op=0.4),
                    tline([(428, 570), (422, 640), (408, 720)], 7, SKIN["hi"], op=0.8)])
    s += armlet([(366, 626), (394, 636), (428, 626)], 12)
    part("arm_upper_r", s, parent="clavicle_r", pivot=SH, z=120)
    side_a = [(348, 806), (344, 858), (346, 928), (356, 1000), (368, 1058)]
    side_b = [(392, 806), (402, 866), (402, 940), (396, 1010), (394, 1058)]
    al = limb(EL, WR, side_a, side_b, rA=22)
    s = skin(al, ((14, -4), (6, -2)), strokes=[(side_a, W_SH, OUT), (side_b, W_LIT, OUT)],
             lines=[tline([(354, 818), (350, 852)], 2.0, SKIN["ln"], op=0.45),
                    tline([(392, 830), (396, 920), (390, 1010)], 6, SKIN["hi"], op=0.8),
                    path(ellipse_d(368, 812, 8, 5), SKIN["s1"], op=0.7)])
    part("arm_lower_r", s, parent="arm_upper_r", pivot=EL, z=122)
    part("hand_r", relaxed_hand(WR), parent="arm_lower_r", pivot=WR, z=126)
    alt("hand_r_open", relaxed_hand(WR, True), slot="hand_r", variant="open")
    # satin drape hanging behind the near arm from the armlet
    sv = smooth([(366, 622), (410, 636), (392, 760), (384, 900), (394, 1040), (402, 1130, "c"), (344, 1110),
                 (284, 1124, "c"), (304, 980), (328, 820), (346, 700)], True)
    lining = smooth([(284, 1124), (314, 1060), (354, 1080), (402, 1130), (344, 1110)], True)
    s = satin(sv, ((24, -6), (10, -2)), over=[path(lining, SKY["b"]), path(lining, SKY["s1"], op=0.4),
                                              fold([(366, 700), (346, 880), (326, 1060)], 10, 0.8), fold([(392, 760), (386, 920), (394, 1060)], 8, 0.6)],
              strokes=[([(366, 622), (346, 700), (328, 820), (304, 980), (284, 1124)], W_SH, OUT), ([(410, 636), (392, 760), (384, 900), (394, 1040), (402, 1130)], W_IN, OUT)])
    s += gold_band([(284, 1124), (344, 1112), (402, 1130)], 6)
    part("sleeve_r", s, parent="arm_upper_r", pivot=(388, 636), z=119, spring="sleeve;limit=150;g=0.9;k=60")

    # ---- far arm (her left): raised, presenting the floating sceptre
    SH, EL, WR = (624, 488), (674, 800), (788, 724)
    side_a = [(650, 486), (660, 530), (666, 600), (676, 700), (690, 792)]
    side_b = [(606, 520), (618, 600), (632, 680), (648, 760), (656, 802)]
    au = limb(SH, EL, side_a, side_b, rA=24)
    part("arm_upper_l", skin(au, ((12, -4),), strokes=[(side_a, W_LIT, OUT), (side_b, W_SIL, OUT)]) + armlet([(624, 634), (650, 642), (674, 634)], 11),
         parent="clavicle_l", pivot=SH, z=40)
    side_a = [(668, 782), (702, 760), (742, 736), (784, 712)]
    side_b = [(684, 822), (708, 792), (746, 764), (790, 738)]
    al = limb(EL, WR, side_a, side_b, rA=22)
    part("arm_lower_l", skin(al, ((6, -10), (2, -4)), strokes=[(side_a, W_LIT, OUT), (side_b, W_SIL, OUT)],
                             lines=[tline([(700, 772), (740, 750), (776, 730)], 5, SKIN["hi"], op=0.8)]),
         parent="arm_upper_l", pivot=EL, z=42)
    pl = smooth([(784, 712), (814, 704), (848, 708), (856, 728), (822, 744), (790, 746)], True)
    h = finger((846, 732), (886, 734), 5.4, 3.8, -2) + finger((850, 726), (898, 724), 5.8, 4.2, -3)
    h += finger((852, 718), (906, 712), 6, 4.4, -4) + finger((850, 710), (898, 700), 5.6, 4.2, -4)
    h += skin(pl, ((6, -6),), strokes=[([(790, 746), (822, 744), (856, 728)], 2.6, OUT), ([(784, 712), (814, 704), (848, 708)], 1.8, SKIN["ln"])],
              over=[tline([(806, 724), (840, 722)], 1.4, SKIN["ln"], op=0.4)])
    h += finger((810, 712), (842, 688), 6.4, 4.6, 3)
    h += gold_band([(786, 706), (790, 726), (788, 746)], 8)
    part("hand_l", h, parent="arm_lower_l", pivot=WR, z=46)
    sv = smooth([(640, 630), (676, 640), (700, 760), (712, 900), (720, 1040, "c"), (676, 1020), (640, 1060, "c"),
                 (640, 900), (636, 760)], True)
    s = satin(sv, ((18, -6), (8, -2)), over=[path(smooth([(640, 1060), (660, 1000), (700, 1010), (720, 1040), (676, 1020)]), SKY["b"]),
                                             fold([(660, 700), (676, 860), (684, 1000)], 8, 0.7)],
              strokes=[([(640, 630), (636, 760), (640, 900), (640, 1060)], W_SIL, OUT), ([(676, 640), (700, 760), (712, 900), (720, 1040)], W_LIT, OUT)])
    s += gold_band([(640, 1060), (676, 1020), (720, 1040)], 5)
    part("sleeve_l", s, parent="arm_upper_l", pivot=(652, 640), z=38, spring="sleeve;limit=150;g=0.9;k=60")


# ------------------------------------------------------------------ legs
def legs():
    # far (weight) leg: under the gown, painted for the rig only
    part("thigh_l", skin(limb((596, 1090), (612, 1540), [(560, 1090), (572, 1300), (590, 1540)], [(640, 1090), (646, 1300), (634, 1540)])),
         parent="hips", pivot=(596, 1090), z=50)
    part("shin_l", skin(limb((612, 1540), (618, 1912), [(592, 1540), (594, 1700), (604, 1912)], [(634, 1540), (632, 1700), (630, 1912)])),
         parent="thigh_l", pivot=(612, 1540), z=52)
    part("foot_l", skin(smooth([(600, 1900), (632, 1900), (680, 1966), (686, 1984), (640, 1978), (606, 1950)], True)),
         parent="shin_l", pivot=(618, 1912), z=54)
    # near (free) leg, revealed by the slit: thigh over shin so the kneecap covers the joint
    HP, KN, AN = (452, 1112), (510, 1528), (498, 1898)
    side_a = [(404, 1100), (404, 1200), (412, 1300), (432, 1410), (458, 1490), (478, 1530)]
    side_b = [(500, 1110), (530, 1200), (546, 1300), (550, 1400), (546, 1470), (542, 1520)]
    th = limb(HP, KN, side_a, side_b, rB=33)
    s = skin(th, ((26, -6), (10, -3)), strokes=[(side_a, W_SH, OUT, "start"), (side_b[1:], W_LIT, OUT, "start")],
             over=[path(ellipse_d(522, 1330, 14, 110, -8), SKIN["hi"], op=0.75),
                   path(smooth([(470, 1140), (520, 1150), (530, 1200), (490, 1200), (440, 1160)], True), SKIN["s1"], op=0.8),
                   path(smooth([(492, 1544), (512, 1560), (534, 1556), (516, 1580)], True), SKIN["s1"], op=0.7),
                   path(ellipse_d(522, 1528, 10, 7, -20), SKIN["hi"], op=0.85)],
             lines=[tline([(498, 1550), (514, 1562), (532, 1558)], 2.0, SKIN["ln"], op=0.55),
                    tline([(504, 1508), (522, 1500), (538, 1508)], 1.6, SKIN["ln"], op=0.4)])
    s += gold_band([(406, 1238), (470, 1258), (540, 1244)], 10) + gem(470, 1258, 6)
    s += chain([(420, 1248), (450, 1292), (500, 1290), (532, 1252)], 8) + leaf(470, 1270, 90, 20, 4)
    part("thigh_r", s, parent="hips", pivot=HP, z=66)
    side_a = [(478, 1540), (468, 1590), (462, 1650), (461, 1710), (468, 1790), (480, 1870), (486, 1898)]
    side_b = [(540, 1540), (541, 1590), (536, 1660), (528, 1760), (520, 1850), (512, 1898)]
    sh = limb(KN, AN, side_a, side_b, rA=31)
    s = skin(sh, ((16, -4), (6, -2)), strokes=[(side_a[1:], W_SH, OUT), (side_b[1:], W_LIT, OUT)],
             over=[path(ellipse_d(526, 1670, 8, 84, -5), SKIN["hi"], op=0.75),
                   path(smooth([(462, 1650), (470, 1600), (480, 1660), (478, 1760), (468, 1790)], True), SKIN["s1"], op=0.7)],
             lines=[tline([(480, 1620), (476, 1700)], 1.6, SKIN["ln"], op=0.35)])
    part("shin_r", s, parent="thigh_r", pivot=KN, z=64)
    a = [(514, 1884), (522, 1906), (540, 1934), (562, 1962), (584, 1984), (580, 1992)]
    b = [(580, 1992), (556, 1988), (528, 1974), (502, 1952), (484, 1928), (478, 1904), (484, 1884)]
    ft = smooth(a + b[1:-1] + [(484, 1884), (500, 1876)], True)
    s = skin(ft, ((10, -4),), strokes=[(a, W_LIT, OUT), (b, W_SIL, OUT)],
             lines=[tline([(556, 1988), (568, 1980), (582, 1988)], 1.6, SKIN["ln"], op=0.6),
                    tline([(546, 1984), (556, 1976)], 1.4, SKIN["ln"], op=0.5),
                    path(ellipse_d(530, 1940, 10, 4, 40), SKIN["hi"], op=0.7)])
    s += chain([(480, 1890), (498, 1904), (518, 1892)], 7) + chain([(484, 1898), (498, 1918), (516, 1904)], 6) + gem(498, 1920, 4.5)
    s += gold_band([(552, 1976), (558, 1982), (562, 1976)], 4)
    part("foot_r", s, parent="shin_r", pivot=AN, z=68)


# ------------------------------------------------------------------ pose bake + write
def bake_and_write():
    bones = {"root": ("", (512, 1990))}
    for pid, body, m, hid in PARTS:
        bone = m.get("bone") or m.get("slot") or pid
        if "pivot" in m:
            bones[bone] = (m.get("parent", "root"), m["pivot"])
    W = {}

    def get(b):
        if b in W:
            return W[b]
        par, piv = bones[b]
        wp = get(par) if (b != "root" and par in bones) else IDENT
        ang = POSE.get(b, 0.0)
        W[b] = mat_mul(wp, rot_about(ang, piv[0], piv[1])) if ang else wp
        return W[b]

    zs = {}
    for pid, body, m, hid in PARTS:
        if "z" in m:
            zs[m.get("slot", pid)] = m["z"]
    groups = []
    for pid, body, m, hid in PARTS:
        bone = m.get("bone") or m.get("slot") or pid
        wb = get(bone) if bone in bones else IDENT
        attrs = ['id="%s"' % pid]
        if hid:
            attrs.append('display="none"')
        if wb != IDENT:
            attrs.append('transform="%s"' % matrix_str(wb))
        for k, v in m.items():
            if k in ("pivot", "tip"):
                v = mat_apply(wb, v)
            if isinstance(v, tuple):
                v = ",".join(f(x) for x in v)
            attrs.append('data-%s="%s"' % (k.replace("_", "-"), v))
        z = m.get("z", zs.get(m.get("slot", pid), -1) + 0.5)
        groups.append((z, "<g %s>%s</g>" % (" ".join(attrs), body)))
    groups.sort(key=lambda g: g[0])
    d.parts = [g[1] for g in groups]
    svg = d.svg(' data-hero="seraphiel" data-origin="512,1990" data-texel-scale="0.75" data-portrait="534,340,480"'
                ' data-weapon="sceptre" data-attack="attack_ranged" data-fx-color="#ffe9a8" data-look-px="14,8"')
    hero_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "art", "heroes", "seraphiel")
    sdir = os.path.join(hero_dir, "standin")
    os.makedirs(sdir, exist_ok=True)
    os.makedirs(os.path.join(hero_dir, "variants"), exist_ok=True)
    for ig in (os.path.join(sdir, ".gdignore"), os.path.join(hero_dir, "variants", ".gdignore")):
        if not os.path.exists(ig):
            open(ig, "w").close()
    out = os.path.join(sdir, "seraphiel_vector.svg")
    with open(out, "w") as fh:
        fh.write(svg)

    def variant(show, hide):
        v = svg
        for pid in hide:
            v = v.replace('<g id="%s" ' % pid, '<g id="%s" display="none" ' % pid, 1)
        for pid in show:
            v = v.replace('<g id="%s" display="none" ' % pid, '<g id="%s" ' % pid, 1)
        return v
    jobs = [("seraphiel_vector.svg", os.path.join(hero_dir, "seraphiel.png"))]
    for name, show, hide in (("eyes_open", ["eye_r_open", "eye_l_open"], ["eye_r_closed", "eye_l_closed"]),
                             ("mouth_open", ["mouth_open"], ["mouth"]),
                             ("smile", ["eye_r_smile", "eye_l_smile", "mouth_smile"], ["eye_r_closed", "eye_l_closed", "mouth"])):
        fn = "seraphiel_%s.svg" % name
        with open(os.path.join(sdir, fn), "w") as fh:
            fh.write(variant(show, hide))
        jobs.append((fn, os.path.join(hero_dir, "variants", name + ".png")))
    root = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
    args = [os.path.join(root, "tools", "gd"), "--headless", "--path", root, "-s", "tools/art_svg2png.gd", "--"]
    for fn, png in jobs:
        args += [os.path.join(sdir, fn), os.path.normpath(png), "1.0"]
    import subprocess
    r = subprocess.run(args, cwd=root, capture_output=True, text=True)
    print("\n".join(l for l in r.stdout.splitlines() if "->" in l))
    for fn, _png in jobs[1:]:      # variant SVGs are intermediates; the PNGs are the deliverable
        os.remove(os.path.join(sdir, fn))
    print("wrote", os.path.normpath(out), "%d KB" % (len(svg) // 1024), len(d.parts), "groups")


def build():
    wings()
    head_wings()
    halo()
    hair()
    arms()
    legs()
    skirts()
    hips()
    torso()
    chest()
    chest_upper()
    neck()
    head()
    face()
    sceptre()
    bake_and_write()


if __name__ == "__main__":
    build()
