"""Seraphiel, the Choir Eternal - HaloRig source art generator.

    python3 tools/art_hero_seraphiel.py && tools/art_build seraphiel

Writes assets/art/heroes/seraphiel/seraphiel.svg (the SVG is the rig source; this script is
how it is authored). Full-scale 7.4-head adult figure, 3/4 view facing right, weight on the
far (left) leg, near (right) leg free and revealed by the gown's slit. Design brief:
docs/dev/character-briefs.md. Style rules, recipes and rubric: docs/dev/art-style.md.
"""
import math
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from art_svgkit import (Doc, smooth, sample, taper, path, group, ink, cel, underlay, ellipse_d, poly,
                        f, xf, lerp, lerp_pt, OUTLINE)

d = Doc(1024, 2048)
OUT = OUTLINE

# ------------------------------------------------------------------ palette (Celestial)
SKIN = {"b": "#fde8dc", "s1": "#f4c8b6", "s2": "#dd9a8a", "hi": "#fff8f3", "ln": "#b06358", "rim": "#fff1d2"}
HAIR = {"b": "#faeec9", "s1": "#e8cd95", "s2": "#cba466", "s3": "#a27b46", "hi": "#ffffff", "ln": "#86602f", "rim": "#fff8e2"}
WHITE = {"b": "#fefdff", "s1": "#e4dff4", "s2": "#bfb5de", "s3": "#958ac2", "hi": "#ffffff", "ln": "#6c629e", "rim": "#fff3cc"}
GOLD = {"b": "#f4c95c", "s1": "#de9e38", "s2": "#a6651d", "hi": "#fff3c4", "sp": "#ffffff", "ln": "#5e3510"}
SKY = {"b": "#8fd2f2", "s1": "#5ba8de", "s2": "#3a7bc2", "hi": "#dcf4ff", "ln": "#23508b"}
FEA = {"b": "#fefdff", "s1": "#e6e1f6", "s2": "#c6bce3", "s3": "#9f94c9", "ln": "#8a80b6", "out": "#3e3366",
       "tip": "#f8dc93", "tip2": "#eebf58"}
LW = 4.2          # silhouette outline width (canvas units)
V_BOT = (553, 762)  # bottom of the plunging neckline
SC_X = 846          # sceptre axis


def part(pid, body, **m):
    d.part(pid, body, **m)


def alt(pid, body, **m):
    """Alternate attachment (hidden in the source SVG so it previews like the still)."""
    d.part(pid, body, **m)
    d.parts[-1] = d.parts[-1].replace("<g ", '<g display="none" ', 1)


def opn(pts, k=1.0):
    return smooth(pts, False, k)


# ------------------------------------------------------------------ ornaments
def gem(cx, cy, r, col=SKY, rot=0.0):
    g = d.radial([(0, col["hi"]), (0.45, col["b"]), (1, col["s2"])], cx - r * 0.25, cy - r * 0.3, r * 1.3)
    s = path(ellipse_d(cx, cy, r, r * 0.92, rot), g, GOLD["ln"], max(1.2, r * 0.18))
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


def sparkle(cx, cy, r, col="#ffffff", op=0.95):
    pts = [(cx, cy - r), (cx + r * 0.14, cy - r * 0.14), (cx + r, cy), (cx + r * 0.14, cy + r * 0.14),
           (cx, cy + r), (cx - r * 0.14, cy + r * 0.14), (cx - r, cy), (cx - r * 0.14, cy - r * 0.14)]
    return path(poly(pts), col, op=op)


# ------------------------------------------------------------------ materials
def skin(dd, tones=((22, -8), (8, -3)), lines=(), over=(), lw=LW, hi=None, edge=None):
    t = [(SKIN["s1"], tones[0][0], tones[0][1], 0.92)]
    if len(tones) > 1:
        t.append((SKIN["s2"], tones[1][0], tones[1][1], 0.5))
    if hi is False:
        hi = None
    elif hi is None:
        hi = (SKIN["hi"], -10, 8, 0.75)
    return cel(d, dd, SKIN["b"], tones=t, hi=hi, rim=(SKIN["rim"], 3.5, 0, 0.9),
               over=list(over), lw=lw, outline=OUT, lines=list(lines), edge=edge)


def satin(dd, tones=((26, -10), (10, -4)), lines=(), over=(), lw=LW, edge=None, base=None):
    t = [(WHITE["s1"], tones[0][0], tones[0][1])]
    if len(tones) > 1:
        t.append((WHITE["s2"], tones[1][0], tones[1][1], 0.85))
    return cel(d, dd, base or WHITE["b"], tones=t, hi=(WHITE["hi"], -10, 8), rim=(WHITE["rim"], 4, 0),
               over=list(over), lw=lw, outline=OUT, lines=list(lines), edge=edge)


def fold(pts, w=3.0, op=0.75, col=None):
    return ink(taper(pts, w, "both"), col or WHITE["s2"], op)


def limb(side_a, side_b, cap_a=(), cap_b=(), k=1.0):
    """Limb from two contours (both listed from the top joint to the bottom joint).
    cap_a: points around the top joint (from side_b's top to side_a's top), cap_b around the
    bottom joint (from side_a's bottom to side_b's bottom). Returns (closed, edge) where edge
    strokes only the two sides, so overlapping joint caps stay unlined."""
    ring = list(side_a) + list(cap_b) + list(side_b)[::-1] + list(cap_a)
    return smooth(ring, True, k), opn(side_a, k) + " " + opn(side_b, k)


# ------------------------------------------------------------------ hair
def hgrad(x0, y0, x1, y1, dark=False):
    if dark:
        return d.linear([(0, HAIR["s1"]), (0.6, HAIR["s2"]), (1, HAIR["s3"])], x0, y0, x1, y1)
    return d.linear([(0, "#fffaf0"), (0.5, HAIR["b"]), (1, HAIR["s1"])], x0, y0, x1, y1)


def clumps(cl, grad, tone=(16, -8), tone2=(6, -3), lines=(), shines=(), dark=False, lw=LW, band=None):
    """Hair from overlapping pointed clumps: an underlay outline for the union, each clump with
    its own crescent shading and a thin warm separation line."""
    ds = [smooth(c, True, 1.0) for c in cl]
    s = underlay(ds, lw * 2.0)
    for dd in ds:
        s += cel(d, dd, grad, tones=[(HAIR["s2"] if dark else HAIR["s1"], tone[0], tone[1]),
                                     (HAIR["s3"] if dark else HAIR["s2"], tone2[0], tone2[1], 0.8)],
                 rim=(HAIR["rim"], 4, 0, 0.85), lw=1.8, outline=HAIR["ln"])
    if band:
        s += path(band, "#ffffff", op=0.8)
    for ln in lines:
        s += ink(taper(ln, 2.8, "both"), HAIR["ln"], 0.75)
    for sh in shines:
        s += ink(taper(sh, 4.5, "both"), "#ffffff", 0.85)
    return s


def tress(path_pts, w0, w1):
    """Closed outline of a hair clump along a centerline, width w0 -> w1, pointed tip."""
    c = sample(path_pts, False, 1.0, 6)
    L, R = [], []
    for i, p in enumerate(c):
        t = i / (len(c) - 1)
        w = lerp(w0, w1, t) * (1 - t ** 4)
        a = c[max(i - 1, 0)]
        b = c[min(i + 1, len(c) - 1)]
        dx, dy = b[0] - a[0], b[1] - a[1]
        ln = math.hypot(dx, dy) or 1
        nx, ny = -dy / ln, dx / ln
        L.append((p[0] + nx * w * 0.5, p[1] + ny * w * 0.5))
        R.append((p[0] - nx * w * 0.5, p[1] - ny * w * 0.5))
    tip = c[-1]
    return L[:-1] + [(tip[0], tip[1], "c")] + R[:-1][::-1]


def hair_mass(left, right, tips=(), grad=None, strands=6, tone=(18, -6), tone2=(7, -2), dark=False, top=None,
              shines=(), lw=LW, outline_top=False, line_op=0.6, seed=3, edge_col=OUT):
    """Flowing hair mass between two edge curves (top -> bottom), with pointed tips at the
    bottom (tips: [(extra_len, dx)] left to right) and interpolated strand lines."""
    n = 10
    L = sample(left, False, 1.0, n)
    R = sample(right, False, 1.0, n)
    m = min(len(L), len(R))
    L, R = L[:m], R[:m]
    bl, br = L[-1], R[-1]
    tip_pts = []
    nt = len(tips)
    for i, (extra, dx) in enumerate(tips):
        fa = (i + 0.5) / nt
        base = lerp_pt(bl, br, fa)
        # direction: continue the flow of the mass at the bottom
        flow = (lerp(L[-1][0] - L[-3][0], R[-1][0] - R[-3][0], fa), lerp(L[-1][1] - L[-3][1], R[-1][1] - R[-3][1], fa))
        fl = math.hypot(*flow) or 1
        tip = (base[0] + flow[0] / fl * extra + dx, base[1] + flow[1] / fl * extra)
        if i > 0:
            v = lerp_pt(bl, br, i / nt)
            tip_pts.append((v[0] + flow[0] / fl * extra * 0.12, v[1] + flow[1] / fl * extra * 0.12))
        tip_pts.append((tip[0], tip[1], "c"))
    ring = [p for p in left] + tip_pts + [p for p in right][::-1] + (list(top) if top else [])
    dd = smooth(ring, True, 1.0)
    edge = opn(left + tip_pts + right[::-1]) if not outline_top else None
    g = grad or HAIR["b"]
    over = []
    # strand lines following the flow, interpolated between the edges
    for k in range(1, strands + 1):
        t = k / (strands + 1) + 0.04 * math.sin(k * 2.3 + seed)
        cur = [lerp_pt(L[i], R[i], t) for i in range(m)]
        a = int((0.05 + 0.25 * ((k * 37 + seed) % 7) / 7.0) * m)
        b = m - 1 - int(0.1 * ((k * 53 + seed) % 5) / 5.0 * m)
        if b - a > 3:
            over.append(ink(taper(cur[a:b], 2.6 + (k % 3) * 0.6, "both"), HAIR["ln"], line_op))
    for t0, t1, w in shines:
        cur = [lerp_pt(L[i], R[i], t0) for i in range(m)]
        a, b = int(t1[0] * m), int(t1[1] * m)
        over.append(ink(taper(cur[a:b], w, "both"), "#ffffff", 0.85))
    body = cel(d, dd, g, tones=[(HAIR["s2"] if dark else HAIR["s1"], tone[0], tone[1]),
                                (HAIR["s3"] if dark else HAIR["s2"], tone2[0], tone2[1], 0.75)],
               rim=(HAIR["rim"], 4, 0, 0.9), over=over, lw=lw, outline=edge_col, edge=edge)
    return body


def hair():
    # --- back mass: dome behind the skull + hair falling behind both shoulders (in shadow)
    g = hgrad(500, 80, 500, 740, dark=True)
    dome = smooth([(528, 76), (616, 96), (658, 166), (664, 262), (652, 340), (560, 330), (470, 340), (380, 360),
                   (372, 268), (390, 170), (452, 100)], True)
    s = cel(d, dome, g, tones=[(HAIR["s2"], 24, -8), (HAIR["s3"], 9, -3, 0.75)], lw=LW, outline=OUT)
    s += hair_mass([(392, 260), (374, 380), (366, 520), (378, 640), (392, 730)],
                   [(476, 280), (462, 420), (452, 560), (452, 660), (452, 730)], tips=[(40, 0), (60, 0)],
                   grad=g, dark=True, strands=4, tone=(20, -6))
    s += hair_mass([(604, 260), (616, 400), (628, 540), (640, 660)], [(664, 250), (672, 380), (684, 520), (690, 650)],
                   tips=[(50, 0), (36, 0)], grad=g, dark=True, strands=3, tone=(12, -6))
    part("hair_back", s, parent="head", pivot=(505, 225), z=30, spring="hair_mass")

    # --- near-side cascade to the knees, flowing outward; two segments joined by a gold cuff
    g = hgrad(360, 470, 330, 1220)
    part("hair_back_r_1", hair_mass([(374, 462), (338, 600), (302, 760), (274, 930), (262, 1090), (264, 1214)],
                                    [(472, 492), (452, 640), (430, 800), (408, 960), (394, 1100), (392, 1214)],
                                    grad=g, strands=7, tone=(22, -6), shines=[(0.25, (0.15, 0.5), 6), (0.6, (0.2, 0.45), 4.5)]),
         parent="hair_back", pivot=(410, 520), z=32, spring="hair_long;limit=10;k=55")
    g = hgrad(320, 1180, 300, 1700)
    cuff = gold_band([(258, 1196), (326, 1210), (396, 1198)], 26, 0.8) + gem(326, 1210, 8)
    cuff += scroll(280, 1202, 0.75, -1) + scroll(372, 1204, 0.75, 1)
    part("hair_back_r_2", hair_mass([(262, 1190), (244, 1320), (230, 1440), (222, 1540)],
                                    [(394, 1190), (398, 1310), (388, 1430), (370, 1540)],
                                    tips=[(110, -14), (170, -8), (120, 0), (150, 6), (70, 10)], grad=g, strands=6,
                                    tone=(20, -6), shines=[(0.3, (0.05, 0.35), 5)]) + cuff,
         parent="hair_back_r_1", pivot=(326, 1196), z=34, spring="hair_long;limit=20")

    # --- far tress, between the body and the far arm
    g = hgrad(640, 480, 640, 1150, dark=True)
    part("hair_back_l", hair_mass([(604, 480), (628, 640), (642, 820), (640, 1000)], [(664, 470), (690, 640), (704, 820), (700, 1000)],
                                  tips=[(90, 0), (130, 0), (70, 0)], grad=g, dark=True, strands=4, tone=(14, -6)),
         parent="hair_back", pivot=(632, 520), z=16, spring="hair_long;limit=12")

    # --- bangs: one big sweep to the far side + thin wisps, roots hidden under the crown
    bangs = [
        ("hair_front_1", [(466, 146), (456, 196), (448, 250)], [(488, 146), (478, 200), (448, 250)], [], (476, 156)),
        ("hair_front_2", [(492, 150), (494, 200), (504, 250)], [(508, 150), (512, 200), (504, 250)], [], (500, 158)),
        ("hair_front_3", [(520, 156), (528, 206), (538, 248)], [(534, 154), (542, 204), (538, 248)], [], (527, 162)),
        ("hair_front_4", [(500, 140), (520, 184), (540, 218), (552, 238)], [(566, 128), (600, 158), (620, 196), (628, 230)],
         [(28, -6), (40, -2), (30, 4)], (540, 150)),
        ("hair_front_5", [(618, 150), (628, 210), (634, 262)], [(642, 146), (652, 206), (652, 262)], [(34, 0)], (630, 160)),
    ]
    for i, (pid, le, ri, tips, piv) in enumerate(bangs):
        g = hgrad(piv[0], piv[1] - 10, piv[0], piv[1] + 110)
        part(pid, hair_mass(le, ri, tips=tips, grad=g, strands=1 if not tips else 3, tone=(9, -7), tone2=(4, -3), lw=3.4, line_op=0.6),
             parent="head", pivot=piv, z=111 + i)

    # --- crown over the bangs' roots: dome, scalloped hairline, side part, angel ring
    g = hgrad(530, 80, 530, 200)
    crown = smooth([(444, 236), (428, 176), (444, 118), (496, 84), (560, 80), (614, 102), (640, 150), (640, 204),
                    (626, 180), (612, 166), (596, 172), (578, 152), (560, 160), (540, 146), (520, 158), (500, 148),
                    (482, 162), (466, 160), (456, 190)], True, 1.0)
    band = smooth([(450, 150), (478, 126), (520, 114), (566, 114), (610, 128), (628, 146), (610, 146), (598, 156),
                   (582, 142), (562, 154), (542, 138), (520, 152), (500, 140), (480, 158), (464, 150)], True, 0.8)
    s = cel(d, crown, g, tones=[(HAIR["s1"], 14, -10), (HAIR["s2"], 5, -4, 0.75)], rim=(HAIR["rim"], 4, 0, 0.9),
            over=[path(band, "#ffffff", op=0.85)], lw=LW, outline=OUT,
            edge=opn([(444, 236), (428, 176), (444, 118), (496, 84), (560, 80), (614, 102), (640, 150), (640, 204)]),
            lines=[ink(taper(pp, 2.6, "both"), HAIR["ln"], 0.6) for pp in ([(496, 92), (470, 126), (456, 176)], [(540, 88), (588, 116), (620, 164)], [(518, 92), (526, 128)])])
    part("hair_top", s, parent="head", pivot=(530, 170), z=118)

    # --- near side lock: upper part beside the face (behind the crown), lower part drapes
    #     over the shoulder and chest; the gold cuff hides the joint
    g = hgrad(440, 200, 440, 440, dark=True)
    part("hair_side_r", hair_mass([(440, 200), (430, 262), (424, 330), (424, 430)], [(458, 200), (450, 262), (446, 330), (450, 430)],
                                  grad=g, strands=2, tone=(10, -6), tone2=(4, -2), dark=True),
         parent="head", pivot=(448, 220), z=109, spring="hair;limit=8")
    g = hgrad(460, 410, 480, 900)
    s = hair_mass([(420, 412), (430, 480), (452, 560), (476, 650), (486, 740), (478, 830)],
                  [(456, 412), (470, 476), (494, 552), (514, 640), (522, 730), (512, 820)],
                  tips=[(60, -4), (96, 2)], grad=g, strands=3, tone=(12, -6), tone2=(5, -2),
                  shines=[(0.35, (0.05, 0.4), 5)])
    s += gold_band([(418, 418), (438, 428), (460, 420)], 16) + gem(439, 426, 5.5)
    part("hair_side_r_2", s, parent="hair_side_r", pivot=(438, 420), z=130, spring="hair;limit=14")

    # --- far side lock, falling behind the far shoulder
    g = hgrad(620, 200, 640, 640)
    part("hair_side_l", hair_mass([(608, 196), (616, 270), (626, 360), (636, 460), (640, 540)],
                                  [(634, 196), (644, 270), (654, 360), (664, 460), (668, 540)],
                                  tips=[(60, 0), (40, 0)], grad=g, strands=2, tone=(8, -6), tone2=(3, -2), lw=3.6),
         parent="head", pivot=(618, 230), z=36, spring="hair;limit=12")


def feather_pts(B, ang, L, w, curl=0.0, n=12, round_tip=False):
    left, right, shaft = [], [], []
    cx, cy = B
    for i in range(n + 1):
        t = i / n
        a = math.radians(ang + curl * t * t)
        if i > 0:
            cx += math.cos(a) * L / n
            cy += math.sin(a) * L / n
        shaft.append((cx, cy))
        prof = math.sin(math.pi * min(1.0, 0.15 + t * 0.95)) ** 0.5
        if round_tip:
            prof = math.sqrt(max(0.0, 1 - (max(t - 0.55, 0) / 0.45) ** 2)) * (0.5 + 0.5 * min(1, t * 3))
        hw = w * prof
        nx, ny = -math.sin(a), math.cos(a)
        left.append((cx + nx * hw * 1.1, cy + ny * hw * 1.1))
        right.append((cx - nx * hw * 0.9, cy - ny * hw * 0.9))
    return left + right[::-1], left, right, shaft


def feather(B, ang, L, w, curl=0.0, tip=False, shade=None, round_tip=False, gold_edge=False):
    o, left, right, sh = feather_pts(B, ang, L, w, curl, 12, round_tip)
    dd = poly(o)
    s = path(dd, FEA["b"])
    s += path(poly(right + sh[::-1]), shade or FEA["s1"], op=0.85)
    if tip:
        k = int(len(left) * 0.66)
        s += path(poly(left[k:] + right[k:][::-1]), FEA["tip"], op=0.9)
        k2 = int(len(left) * 0.84)
        s += path(poly(left[k2:] + right[k2:][::-1]), FEA["tip2"], op=0.7)
    if gold_edge:
        s += ink(taper(left[2:], 2.6, "both"), GOLD["b"], 0.9)
    s += path(dd, "none", FEA["ln"], 1.6)
    s += ink(taper(sh[1:-2], 2.0, "start"), FEA["s2"], 0.9)
    return dd, s


def wing(edge, dir_root, dir_tip, L_root, L_tip, n, curl=-14.0, flip=1, rows=2, scale=1.0):
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

    shapes, bodies = [], []
    for i in range(n - 1, -1, -1):
        s = 0.1 + 0.9 * i / (n - 1)
        ang = lerp(dir_root, dir_tip, s ** 1.15) + (3 if i % 2 else -2) * flip
        L = lerp(L_root, L_tip, s ** 0.85) * (1.0 if i % 3 else 0.93)
        dd, body = feather(at(s), ang, L, L * 0.105 * scale, curl * flip, tip=s > 0.45,
                           shade=FEA["s2"] if s < 0.3 else FEA["s1"])
        shapes.append(dd)
        bodies.append(body)
    for row in range(rows):
        m = int(n * (1.3 - 0.2 * row))
        frac = 0.46 - 0.15 * row
        for i in range(m - 1, -1, -1):
            s = 0.03 + 0.92 * i / max(m - 1, 1)
            ang = lerp(dir_root, dir_tip, s ** 1.15) - 8 * flip
            L = lerp(L_root, L_tip, s ** 0.85) * frac
            dd, body = feather(at(s), ang, L, L * 0.2 * scale, curl * 0.4 * flip, round_tip=True,
                               gold_edge=(row == rows - 1 and i % 2 == 0))
            shapes.append(dd)
            bodies.append(body)
    top = sample(edge, False, 1.0, 10)
    lower = []
    for i, p in enumerate(top):
        a = top[max(i - 1, 0)]
        b = top[min(i + 1, len(top) - 1)]
        dx, dy = b[0] - a[0], b[1] - a[1]
        ln = math.hypot(dx, dy) or 1
        t = i / (len(top) - 1)
        ww = L_root * 0.2 * (1 - 0.7 * t) * (1.0 + 0.2 * math.sin(i * 2.1))
        lower.append((p[0] - dy / ln * ww * flip, p[1] + dx / ln * ww * flip))
    lead = poly(top + lower[::-1])
    shapes.append(lead)
    bodies.append(path(lead, FEA["b"]) + ink(taper(top, L_root * 0.06, "both"), "#ffffff", 0.9)
                  + path(lead, "none", FEA["ln"], 1.6))
    return underlay(shapes, 5.6, FEA["out"]) + "".join(bodies)


def wings():
    part("wing_lower_l", wing([(588, 770), (672, 804), (752, 868), (820, 960)], 95, 42, 100, 210, 9, curl=18, flip=-1),
         parent="chest", pivot=(588, 770), z=10)
    part("wing_upper_l", wing([(596, 560), (648, 450), (730, 350), (826, 260), (880, 222)], 74, -18, 128, 290, 11, curl=18, flip=-1),
         parent="chest_upper", pivot=(596, 560), z=12)
    part("wing_lower_r", wing([(470, 776), (380, 812), (280, 890), (184, 1010)], 85, 138, 110, 270, 10, curl=-18),
         parent="chest", pivot=(470, 776), z=22)
    part("wing_upper_r", wing([(462, 566), (410, 452), (324, 340), (228, 240), (160, 196)], 108, 198, 138, 300, 12, curl=-18),
         parent="chest_upper", pivot=(462, 566), z=24)


def head_wings():
    part("wing_head_l", wing([(606, 206), (630, 166), (658, 128), (688, 100)], 30, -36, 50, 96, 6, curl=14, flip=-1, rows=1),
         parent="head", pivot=(606, 206), z=14)
    part("wing_head_r", wing([(444, 214), (418, 166), (388, 116), (350, 78)], 150, 216, 58, 122, 6, curl=-14, rows=1),
         parent="head", pivot=(444, 214), z=98)


# ------------------------------------------------------------------ halo: crown of sunrays
HALO_C = (522, 236)
HALO_RX, HALO_RY, HALO_ROT = 165, 152, 0


def halo_pt(a_deg, r=1.0):
    a = math.radians(a_deg)
    x, y = HALO_RX * r * math.cos(a), HALO_RY * r * math.sin(a)
    rr = math.radians(HALO_ROT)
    return (HALO_C[0] + x * math.cos(rr) - y * math.sin(rr), HALO_C[1] + x * math.sin(rr) + y * math.cos(rr))


def ring_arc(a0, a1, w):
    return gold_band([halo_pt(a0 + (a1 - a0) * i / 24.0) for i in range(25)], w)


def halo():
    """Crown of sunrays: a tilted gold ring behind the head with radiating rays (all behind)."""
    cx, cy = HALO_C
    glow = d.radial([(0, "#fff6d8", 0.75), (0.45, "#ffe39a", 0.3), (1, "#ffd36b", 0.0)], cx, cy, 220)
    s = path(ellipse_d(cx, cy, 220, 220), glow)
    n = 24
    for i in range(n):
        a = math.radians(-90 + 360.0 * i / n)
        if math.sin(a) > 0.55:          # no rays hidden straight down behind the neck
            continue
        r0x, r0y = HALO_RX, HALO_RY
        base = (cx + math.cos(a) * r0x, cy + math.sin(a) * r0y)
        L = 96 if i % 2 == 0 else 52
        if i == 0:
            L = 104
        top_room = (cy + math.sin(a) * r0y) - 8.0
        if math.sin(a) < -0.2:
            L = min(L, top_room / max(-math.sin(a), 0.2))
        tip = (cx + math.cos(a) * (r0x + L), cy + math.sin(a) * (r0y + L))
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
    s += gold_band(ring, 14) + gold_band([(cx + math.cos(math.radians(k * 15)) * (HALO_RX - 18), cy + math.sin(math.radians(k * 15)) * (HALO_RY - 18)) for k in range(25)], 4, hi=False)
    for k in range(8):
        a = math.radians(-90 + k * 45)
        s += gem(cx + math.cos(a) * HALO_RX, cy + math.sin(a) * HALO_RY, 7 if k % 2 == 0 else 5)
    part("halo", s, parent="head", pivot=HALO_C, z=26, spring="accessory;limit=4;g=0")


def sceptre():
    x = SC_X
    glow = d.radial([(0, "#ffffff", 0.9), (0.35, "#bfeaff", 0.45), (1, "#8fd3f2", 0.0)], x, 236, 100)
    s = path(ellipse_d(x, 236, 100, 100), glow)
    g = d.linear([(0, GOLD["s1"]), (0.35, GOLD["b"]), (0.6, GOLD["hi"]), (1, GOLD["s1"])], x - 40, 0, x + 40, 0)
    fd = smooth([(x - 36, 152, "c"), (x - 22, 152, "c"), (x - 22, 326), (x, 350), (x + 22, 326), (x + 22, 152, "c"),
                 (x + 36, 152, "c"), (x + 36, 336), (x + 10, 372), (x - 10, 372), (x - 36, 336)], True, 0.9)
    s += cel(d, fd, g, tones=[(GOLD["s1"], 6, 0)], hi=(GOLD["hi"], -4, 0), lw=3.2, outline=GOLD["ln"])
    for px in (x - 29, x + 29):
        s += path(ellipse_d(px, 146, 11, 11), GOLD["b"], GOLD["ln"], 2.6) + path(ellipse_d(px - 3, 142, 4, 3), "#ffffff", op=0.9)
    for side in (-1, 1):
        for k in range(3):
            dd, body = feather((x + side * 16, 370 - k * 6), 90 - side * (100 - k * 22), 46 - k * 9, 5.5 - k * 0.6, curl=side * 10)
            s += body.replace(FEA["b"], GOLD["hi"]).replace(FEA["s1"], GOLD["b"]).replace(FEA["s2"], GOLD["s1"]).replace(FEA["ln"], GOLD["ln"])
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


def head():
    hd = smooth(HEAD, True, 1.0)
    ear = smooth([(462, 256), (446, 248), (436, 258), (436, 280), (444, 298), (458, 304), (466, 286)], True)
    s = cel(d, ear, SKIN["b"], tones=[(SKIN["s1"], 8, -4)], lw=3.0, outline=SKIN["ln"],
            lines=[ink(taper([(446, 262), (442, 278), (450, 292)], 3, "both"), SKIN["ln"], 0.7)])
    under_bangs = smooth([(440, 180), (470, 216), (500, 212), (528, 240), (560, 220), (592, 236), (616, 214), (616, 150), (440, 150)], True)
    cheek_shadow = smooth([(442, 220), (462, 236), (470, 290), (492, 336), (530, 362), (470, 362), (440, 300)], True)
    eyeshadow = d.radial([(0, "#f0a6a0", 0.45), (1, "#f0a6a0", 0.0)], 494, 244, 36, 1.0, 0.55)
    eyeshadow2 = d.radial([(0, "#f0a6a0", 0.4), (1, "#f0a6a0", 0.0)], 580, 242, 28, 1.0, 0.55)
    face_glow = d.radial([(0, "#fffaf6", 0.9), (0.6, "#fde8dc", 0.0)], 576, 270, 74)
    over = [path(under_bangs, SKIN["s1"], op=0.85), path(cheek_shadow, SKIN["s1"], op=0.55), path(hd, face_glow),
            path(ellipse_d(494, 244, 36, 20), eyeshadow), path(ellipse_d(580, 242, 28, 15), eyeshadow2)]
    s += cel(d, hd, SKIN["b"], tones=[(SKIN["s1"], 16, -6, 0.75), (SKIN["s2"], 6, -2, 0.5)], over=over,
             lw=LW, outline=OUT,
             lines=[
                 ink(taper([(500, 355), (530, 366), (552, 369), (572, 357)], 4.8, "both"), OUT),
                 ink(taper([(561, 266), (565, 282), (571, 296)], 3.0, "end"), SKIN["ln"], 0.8),
                 ink(taper([(562, 302), (569, 305), (575, 300)], 2.8, "both"), SKIN["ln"], 0.95),
                 path(ellipse_d(574, 291, 2.6, 2.0), "#ffffff", op=0.85),
             ])
    part("head", s, parent="neck", pivot=(502, 336), z=100)


def eye_closed(c, w, near):
    """Closed, serene eye: a soft downward lash arc with lashes at the outer corner."""
    cx, cy = c
    sg = -1 if near else 1
    inner = (cx - sg * w * 0.5, cy - 2)
    outer = (cx + sg * w * 0.54, cy - 3)
    arc = [inner, (cx - sg * w * 0.22, cy + 6), (cx + sg * w * 0.06, cy + 8), (cx + sg * w * 0.34, cy + 5), outer]
    s = ink(taper(arc, 7.5, "both", power=0.55), "#35243f")
    s += ink(taper([outer, (outer[0] + sg * 12, outer[1] + 2), (outer[0] + sg * 20, outer[1] - 5)], 4.4, "start"), "#35243f")
    pts = sample(arc, False, 1.0, 10)
    for fx_, ln in ((0.3, 9), (0.48, 12), (0.64, 12), (0.8, 10)):
        p = pts[int(fx_ * (len(pts) - 1))]
        s += ink(taper([p, (p[0] + sg * 3, p[1] + ln * 0.6), (p[0] + sg * 8, p[1] + ln)], 2.6, "start"), "#35243f", 0.9)
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
    s += ink(taper(top + [(outer[0] + sg * 14, outer[1] - 6)], 7.5, "both", power=0.45), "#2f2040")
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
        hurt = ink(taper([(c[0] - sg * w * 0.45, c[1] - 6), (c[0], c[1] + 2), (c[0] + sg * w * 0.45, c[1] - 2)], 6.5, "both"), "#35243f")
        hurt += ink(taper([(c[0] - sg * w * 0.4, c[1] + 8), (c[0] + sg * w * 0.3, c[1] + 6)], 2.4, "both"), SKIN["ln"], 0.7)
        alt("eye_%s_hurt" % side, hurt, slot="eye_" + side, variant="hurt")
        sm = ink(taper([(c[0] - sg * w * 0.48, c[1] + 4), (c[0], c[1] - 7), (c[0] + sg * w * 0.5, c[1] + 2)], 7, "both"), "#35243f")
        sm += ink(taper([(c[0] + sg * w * 0.5, c[1] + 2), (c[0] + sg * w * 0.68, c[1] - 4)], 3.2, "start"), "#35243f")
        alt("eye_%s_smile" % side, sm, slot="eye_" + side, variant="smile")
    part("brow_r", ink(taper([(464, 222), (486, 211), (510, 209), (524, 214)], 5.2, "both", power=0.7), "#b78f56"),
         parent="head", pivot=(494, 214), z=106)
    part("brow_l", ink(taper([(558, 210), (580, 206), (598, 212), (607, 221)], 4.4, "both", power=0.7), "#b78f56"),
         parent="head", pivot=(582, 210), z=107)
    bl = d.radial([(0, "#f59c9c", 0.55), (1, "#f59c9c", 0.0)], 488, 294, 34, 1.0, 0.5)
    bl2 = d.radial([(0, "#f59c9c", 0.5), (1, "#f59c9c", 0.0)], 592, 290, 24, 1.0, 0.5)
    b = path(ellipse_d(488, 294, 34, 17), bl) + path(ellipse_d(592, 290, 24, 12), bl2)
    for k in range(3):
        b += ink(taper([(476 + k * 9, 298), (482 + k * 9, 289)], 1.8, "both"), "#e57f86", 0.55)
    part("blush", b, parent="head", pivot=(540, 292), z=102)
    # mouth: alluring half smile (far corner lifted), defined lips
    lip = "#e58a8c"
    m = path(smooth([(541, 331), (552, 328), (558, 330), (566, 327), (574, 324), (566, 333), (552, 334)]), "#d9787e", op=0.85)
    m += ink(taper([(538, 331), (550, 335), (562, 334), (575, 324)], 3.4, "both"), "#9c4a4a")
    m += ink(taper([(574, 324), (579, 320)], 2.2, "start"), "#9c4a4a", 0.8)
    m += path(smooth([(546, 337), (560, 336), (568, 340), (558, 346), (548, 343)]), lip)
    m += ink(taper([(548, 346), (558, 348), (566, 343)], 1.8, "both"), "#c46b6e", 0.6)
    m += path(ellipse_d(557, 340, 4.5, 1.5, -6), "#ffffff", op=0.8)
    part("mouth", m, parent="head", pivot=(556, 334), z=103)
    om = smooth([(540, 330), (556, 327), (574, 325), (570, 341), (556, 349), (544, 341)])
    o = path(om, "#7a2f3e", "#9c4a4a", 2.4) + path(smooth([(546, 341), (556, 338), (566, 341), (556, 347)]), "#d7737d")
    o += path(smooth([(544, 330.5), (572, 327), (568, 333), (548, 334)]), "#fffafa", op=0.9)
    alt("mouth_open", o, slot="mouth", variant="open")
    sm = ink(taper([(536, 327), (548, 335), (562, 335), (576, 322)], 3.6, "both"), "#9c4a4a")
    sm += path(smooth([(548, 336), (562, 336), (556, 341)]), "#7a2f3e", op=0.85)
    alt("mouth_smile", sm, slot="mouth", variant="smile")
    alt("mouth_hurt", ink(taper([(540, 336), (548, 331), (556, 336), (564, 331), (572, 334)], 3.4, "both"), "#9c4a4a"),
        slot="mouth", variant="hurt")


# ------------------------------------------------------------------ neck, torso, gown
def neck():
    nk = smooth([(476, 296), (504, 332), (548, 362), (562, 356), (566, 400), (574, 440), (600, 460), (520, 474),
                 (446, 462), (466, 436), (472, 380)], True)
    chin_sh = smooth([(474, 300), (520, 352), (550, 369), (568, 358), (566, 394), (540, 398), (500, 378), (474, 340)], True)
    s = skin(nk, ((14, -4), (6, -2)), over=[path(chin_sh, SKIN["s1"], op=0.9), path(chin_sh, SKIN["s2"], op=0.35)],
             edge=opn([(476, 296), (472, 380), (466, 436)]) + " " + opn([(562, 356), (566, 400), (574, 440)]))
    # slim gold choker with a sun charm; fine chains down to the halter rings
    s += gold_band([(470, 404), (520, 418), (568, 404)], 9) + gold_band([(472, 414), (520, 428), (566, 414)], 3, hi=False)
    s += path(smooth([(514, 424), (526, 424), (528, 446, "c"), (520, 456, "c"), (512, 446, "c")]), GOLD["b"], GOLD["ln"], 1.8) + gem(520, 437, 5.5)
    s += chain([(482, 414), (490, 430), (497, 446)], 6) + chain([(558, 412), (562, 428), (564, 444)], 6)
    part("neck", s, parent="chest_upper", pivot=(520, 444), z=81)


def chest_upper():
    pts = [(470, 436), (438, 448), (410, 464), (394, 492), (398, 530), (420, 552), (446, 560), (500, 572), (548, 578),
           (600, 568), (628, 552), (648, 524), (652, 498), (636, 470), (598, 448), (566, 436)]
    sk = smooth(pts, True)
    edge = opn([(470, 436), (438, 448), (410, 464), (394, 492)]) + " " + opn([(566, 436), (598, 448), (636, 470), (652, 498)])
    clav = [ink(taper([(452, 482), (488, 490), (524, 484)], 3.0, "both"), SKIN["ln"], 0.5),
            ink(taper([(566, 482), (596, 478), (620, 486)], 2.6, "both"), SKIN["ln"], 0.45),
            ink(taper([(549, 500), (550, 540), (550, 580)], 2.6, "both"), SKIN["s2"], 0.5)]
    s = skin(sk, ((20, -6), (8, -3)), lines=clav, edge=edge,
             over=[path(smooth([(394, 492), (440, 516), (470, 580), (400, 580)]), SKIN["s1"], op=0.6),
                   path(ellipse_d(618, 494, 22, 12, -15), SKIN["hi"], op=0.7)])
    pn = smooth([(492, 446), (506, 446), (514, 500), (522, 586), (450, 586), (454, 552), (478, 500)], True)
    pf = smooth([(558, 446), (572, 446), (590, 496), (618, 540), (636, 586), (582, 586), (572, 510)], True)
    s += satin(pn, ((16, -4), (6, -2)), lw=3.4, edge=opn([(492, 446), (478, 500), (454, 552), (450, 586)]) + " " + opn([(506, 446), (514, 500), (522, 586)]))
    s += satin(pf, ((12, -4), (5, -2)), lw=3.4, edge=opn([(572, 446), (590, 496), (618, 540), (636, 586)]) + " " + opn([(558, 446), (572, 510), (582, 586)]))
    s += gold_band([(506, 450), (514, 506), (521, 584)], 5) + gold_band([(558, 450), (572, 512), (581, 584)], 5)
    s += gold_band([(519, 578), (550, 588), (581, 578)], 4.5) + gem(550, 588, 4.5)
    s += scroll(526, 580, 0.5, 1) + scroll(574, 580, 0.5, -1)
    s += path(ellipse_d(499, 447, 7, 6), "none", GOLD["ln"], 4.5) + path(ellipse_d(499, 447, 7, 6), "none", GOLD["b"], 2.6)
    s += path(ellipse_d(565, 445, 7, 6), "none", GOLD["ln"], 4.5) + path(ellipse_d(565, 445, 7, 6), "none", GOLD["b"], 2.6)
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
                     path(ellipse_d(502, 600, 28, 17, -15), "#ffffff", op=0.95)],
               lines=[fold([(444, 650), (470, 670), (496, 680), (520, 676), (540, 660)], 2.6, 0.8, WHITE["s3"]),
                      fold([(458, 704), (474, 760)], 2.2, 0.5)],
               edge=opn([(440, 548), (436, 622), (452, 682), (464, 724), (474, 794)]))
    s += satin(cup_f, ((16, -6), (6, -2)),
               over=[path(ub_f, WHITE["s1"], op=0.9), path(smooth([(566, 670), (600, 690), (636, 686), (640, 708), (600, 714), (566, 696)]), WHITE["s2"], op=0.5),
                     path(ellipse_d(626, 598, 19, 13, -25), "#ffffff", op=0.95)],
               lines=[fold([(566, 668), (596, 688), (630, 688), (652, 668)], 2.4, 0.8, WHITE["s3"])],
               edge=opn([(612, 548), (650, 584), (664, 622), (654, 662), (630, 686), (608, 712), (600, 794)]))
    s += gold_band([(518, 550), (528, 610), (542, 684), (552, 760)], 5.5, 0.9)
    s += gold_band([(580, 550), (576, 610), (566, 684), (555, 760)], 5.5, 0.9)
    for y, x0, x1 in ((624, 530, 575), (696, 543, 564)):
        s += gold_band([(x0, y), ((x0 + x1) / 2, y + 7), (x1, y)], 4.5)
        s += scroll(x0 + 6, y + 2, 0.55, 1) + scroll(x1 - 6, y + 2, 0.55, -1)
        s += gem((x0 + x1) / 2, y + 8, 4.5)
    s += path(ellipse_d(553, 764, 12, 10), GOLD["b"], GOLD["ln"], 2.2) + gem(553, 764, 6.5)
    part("chest", s, parent="torso", pivot=(536, 800), z=76)


def torso():
    top = [(466, 762), (510, 772), (552, 778), (580, 774), (602, 764)]
    bot = [(470, 828), (520, 846), (556, 866), (580, 846), (604, 828)]
    band = smooth(top + [(600, 796)] + bot[::-1] + [(468, 796)], True)
    s = satin(band, ((14, -4), (6, -2)), lines=[ink(taper([(x, 776 + abs(x - 552) * -0.05), (x + 1, 836)], 1.8, "both"), WHITE["s2"], 0.6) for x in (494, 516, 590)])
    s += gold_band(top, 6) + gold_band(bot, 6)
    s += path(ellipse_d(556, 818, 12, 11), GOLD["b"], GOLD["ln"], 2.2)
    for k in range(12):
        a = math.radians(k * 30)
        s += ink(taper([(556 + math.cos(a) * 12, 818 + math.sin(a) * 11), (556 + math.cos(a) * 21, 818 + math.sin(a) * 19)], 3.6 if k % 2 == 0 else 2.4, "start"), GOLD["s1"])
    s += gem(556, 818, 7)
    for x, fl in ((482, -1), (594, 1)):
        s += scroll(x, 806, 0.7, fl) + scroll(x, 826, 0.6, fl)
    part("torso", s, parent="hips", pivot=(530, 960), z=80)


def hips():
    # the hips bone carries the gown panels; its own art is the gold hip chains on top
    s = chain([(472, 846), (496, 920), (548, 956), (600, 916), (604, 848)], 9)
    s += chain([(470, 852), (444, 936), (430, 1030), (436, 1100)], 9) + gem(548, 960, 6)
    s += path(smooth([(540, 960), (556, 960), (548, 992, "c")]), GOLD["b"], GOLD["ln"], 1.6)
    part("hips", s, parent="root", pivot=(520, 1066), z=74)


def skirts():
    # sheer outer train (behind everything): luminous white-gold, gold hem
    tr = smooth([(440, 880), (560, 880), (640, 960), (690, 1300), (740, 1700), (770, 1990, "c"), (600, 1975),
                 (420, 1990), (230, 1980), (110, 1990, "c"), (170, 1700), (250, 1400), (330, 1100), (390, 950)], True)
    tg = d.linear([(0, "#fffdf6", 0.9), (0.5, "#fff4dc", 0.7), (1, "#fbefd8", 0.62)], 400, 900, 400, 1990)
    inner = d.radial([(0, "#ffffff", 0.55), (1, "#ffffff", 0.0)], 330, 1500, 320, 0.7, 1.0)
    s = path(tr, tg) + path(tr, inner) + path(tr, "none", "#e9d9a8", 2.4)
    s += gold_band([(150, 1930), (240, 1922), (420, 1930), (600, 1918), (750, 1930)], 4, hi=False)
    for k in range(9):
        x = 170 + k * 66
        s += scroll(x, 1952, 0.9, 1 if k % 2 else -1)
    for pts in ([(380, 1000), (300, 1400), (220, 1800)], [(450, 1000), (420, 1400), (380, 1900)], [(620, 1000), (680, 1500), (720, 1900)]):
        s += ink(taper(pts, 14, "both"), "#ffffff", 0.55) + fold([(p[0] + 10, p[1]) for p in pts], 3, 0.45, "#d8cdee")
    s += gold_band([(112, 1986), (230, 1978), (420, 1986), (600, 1972), (768, 1986)], 7)
    part("skirt_back", s, parent="hips", pivot=(500, 940), z=20, spring="cape;limit=8;k=50", bend="0.6")
    # opaque gown, near-back panel (behind the near leg)
    pts = [(412, 1000), (470, 1010), (480, 1140), (482, 1300), (472, 1520), (454, 1760), (442, 1968), (360, 1984),
           (296, 1974, "c"), (326, 1700), (366, 1420), (394, 1200), (404, 1100)]
    pr = smooth(pts, True)
    s = satin(pr, ((30, -8), (12, -3)), lines=[fold([(400, 1250), (380, 1500), (350, 1800)], 3.2, 0.7),
                                               fold([(440, 1300), (430, 1600), (410, 1900)], 2.6, 0.55)],
              edge=opn([(404, 1100), (394, 1200), (366, 1420), (326, 1700), (296, 1974)]) + " " + opn([(480, 1140), (482, 1300), (472, 1520), (454, 1760), (442, 1968)])
              + " " + opn([(296, 1974), (360, 1984), (442, 1968)]))
    s += gold_band([(300, 1972), (370, 1982), (440, 1966)], 8) + ink(taper([(306, 1956), (436, 1952)], 3, "flat"), SKY["b"])
    s += gold_band([(476, 1134), (480, 1400), (464, 1700), (444, 1964)], 6, 0.9)
    part("skirt_r", s, parent="hips", pivot=(440, 1010), z=58, spring="cloth;limit=6")
    # opaque gown, front panel: from the cincher over the hips, covers the far leg; left edge = slit
    pts = [(466, 820), (604, 820), (626, 900), (646, 980), (654, 1040), (652, 1110), (656, 1400), (680, 1700),
           (708, 1972, "c"), (650, 1986), (602, 1976, "c"), (590, 1720), (564, 1500), (526, 1300), (478, 1142),
           (440, 1126), (410, 1104), (404, 1030), (420, 940), (452, 866)]
    pf = smooth(pts, True)
    hip_sh = smooth([(404, 1030), (420, 940), (452, 866), (470, 900), (450, 1000), (446, 1100), (410, 1104)], True)
    s = satin(pf, ((26, -8), (10, -3)),
              over=[path(hip_sh, WHITE["s1"], op=0.8),
                    path(ellipse_d(600, 990, 30, 70, -8), "#ffffff", op=0.8),
                    path(smooth([(560, 1150), (600, 1400), (640, 1700), (650, 1980), (600, 1976), (580, 1600), (540, 1300)]), WHITE["s1"], op=0.5)],
              lines=[fold([(560, 900), (570, 1000), (580, 1120)], 3, 0.5), fold([(500, 960), (494, 1060), (490, 1120)], 3, 0.45),
                     fold([(600, 1200), (620, 1500), (650, 1800)], 3.2, 0.7), fold([(560, 1250), (590, 1600), (610, 1900)], 2.6, 0.55),
                     fold([(486, 1150), (520, 1180)], 2.4, 0.6), fold([(490, 1160), (540, 1240)], 2.4, 0.5)],
              edge=opn([(452, 866), (420, 940), (404, 1030), (410, 1104), (440, 1126), (478, 1142), (526, 1300), (564, 1500), (590, 1720), (602, 1976)])
              + " " + opn([(604, 820), (626, 900), (646, 980), (654, 1040), (652, 1110), (656, 1400), (680, 1700), (708, 1972)])
              + " " + opn([(602, 1976), (650, 1986), (708, 1972)]))
    s += gold_band([(442, 1128), (478, 1140), (526, 1300), (564, 1500), (591, 1720), (603, 1972)], 7, 0.9)
    s += ink(taper([(490, 1156), (536, 1310), (574, 1500), (600, 1720), (614, 1956)], 3, "flat"), SKY["b"])
    s += gold_band([(602, 1975), (650, 1985), (706, 1971)], 8)
    s += path(smooth([(458, 1118), (482, 1106), (500, 1130), (486, 1158, "c"), (462, 1148)]), GOLD["b"], GOLD["ln"], 2.4)
    s += scroll(486, 1140, 0.8, 1) + scroll(462, 1138, 0.8, -1) + gem(478, 1134, 8)
    s += chain([(474, 1150), (470, 1190), (478, 1230)], 8) + gem(478, 1238, 5)
    part("skirt_l", s, parent="hips", pivot=(540, 840), z=70, spring="cloth;limit=4", bend="0.85")
    # sheer overlay on the front panel (only over the opaque gown)
    so = smooth([(526, 1150), (646, 1120), (676, 1420), (720, 1700), (760, 1972, "c"), (700, 1986), (640, 1980),
                 (612, 1730), (584, 1500), (546, 1300)], True)
    sg = d.linear([(0, "#ffffff", 0.0), (0.4, "#fff8e8", 0.4), (1, "#fff3d6", 0.6)], 0, 1150, 0, 1980)
    s = path(so, sg) + path(so, "none", GOLD["s1"], 1.8, op=0.6)
    s += gold_band([(640, 1980), (700, 1986), (760, 1972)], 5)
    for k in range(4):
        s += scroll(640 + k * 16, 1300 + k * 160, 1.0, 1, 20)
    part("skirt_front", s, parent="hips", pivot=(600, 1150), z=72, spring="cloth;limit=8;w=0.5", bend="0.6")


# ------------------------------------------------------------------ arms + hands
def armlet(pts, w=13):
    c = sample(pts, False, 1.0, 6)
    mid = c[len(c) // 2]
    return gold_band(pts, w) + gem(mid[0], mid[1], 5)


def finger(base, tip, w0, w1, bend=0.0, lw=2.0):
    mid = lerp_pt(base, tip, 0.5)
    dx, dy = tip[0] - base[0], tip[1] - base[1]
    ln = math.hypot(dx, dy) or 1
    nx, ny = -dy / ln, dx / ln
    mid = (mid[0] + nx * bend, mid[1] + ny * bend)
    pts = [(base[0] + nx * w0, base[1] + ny * w0), (mid[0] + nx * (w0 + w1) * 0.5, mid[1] + ny * (w0 + w1) * 0.5),
           (tip[0] + nx * w1, tip[1] + ny * w1), (tip[0] + dx / ln * w1 * 1.1, tip[1] + dy / ln * w1 * 1.1),
           (tip[0] - nx * w1, tip[1] - ny * w1), (mid[0] - nx * (w0 + w1) * 0.5, mid[1] - ny * (w0 + w1) * 0.5),
           (base[0] - nx * w0, base[1] - ny * w0)]
    dd = smooth(pts, True, 0.9)
    s = cel(d, dd, SKIN["b"], tones=[(SKIN["s1"], 5, -3, 0.9)], lw=lw, outline=SKIN["ln"])
    m = lerp_pt(base, tip, 0.5)
    s += ink(taper([m, (m[0] + nx * w0 * 0.6, m[1] + ny * w0 * 0.6)], 1.3, "both"), SKIN["ln"], 0.45)
    s += path(ellipse_d(tip[0] - dx / ln * w1 * 0.3, tip[1] - dy / ln * w1 * 0.3, w1 * 0.55, w1 * 0.8, math.degrees(math.atan2(dy, dx)) + 90), "#ffffff", op=0.5)
    return s


def relaxed_hand(ox, oy, open_=False):
    """Hanging right hand, back toward the viewer, thumb in front. (ox, oy) = wrist."""
    def P(x, y):
        return (x + ox - 404, y + oy - 1072)
    palm = smooth([P(390, 1064), P(420, 1064), P(426, 1100), P(428, 1150), P(416, 1166), P(388, 1160), P(384, 1110)], True)
    h = ""
    if not open_:
        h += finger(P(392, 1150), P(394, 1206), 7, 5.5, 2) + finger(P(402, 1154), P(404, 1226), 8, 6, 3)
        h += finger(P(412, 1156), P(416, 1232), 8, 6, 4)
        h += skin(palm, ((10, -4),), lw=2.4, hi=(SKIN["hi"], -6, 4, 0.6))
        h += finger(P(420, 1150), P(428, 1218), 7.5, 6, 5) + finger(P(420, 1096), P(436, 1166), 8, 6, -4)
    else:
        h += skin(palm, ((10, -4),), lw=2.4)
        for b, t in ((P(390, 1150), P(368, 1214)), (P(400, 1156), P(392, 1238)), (P(412, 1158), P(420, 1240)),
                     (P(422, 1150), P(448, 1212)), (P(420, 1096), P(452, 1138))):
            h += finger(b, t, 7.5, 5.8, 0)
    h += gold_band([P(388, 1074), P(406, 1080), P(424, 1074)], 9) + gem(*P(406, 1080), 4)
    return h


def arms():
    # ---- near arm (her right): relaxed, a little away from the waist so the curve reads
    side_a = [(412, 462), (390, 476), (376, 506), (370, 548), (370, 590), (366, 640), (362, 700), (356, 760), (352, 806)]
    side_b = [(438, 506), (446, 552), (440, 600), (430, 660), (414, 730), (400, 790), (394, 806)]
    au, edge = limb(side_a, side_b, cap_a=[(436, 478), (426, 462)], cap_b=[(358, 832), (384, 834)])
    s = skin(au, ((18, -4), (7, -2)), edge=edge, hi=False,
             lines=[ink(taper([(392, 482), (380, 520)], 2.4, "both"), SKIN["ln"], 0.4),
                    ink(taper([(430, 560), (424, 640), (410, 720)], 7, "both"), SKIN["hi"], 0.8)])
    s += armlet([(366, 626), (394, 636), (428, 626)], 12)
    part("arm_upper_r", s, parent="clavicle_r", pivot=(420, 482), z=120)
    side_a = [(350, 800), (344, 858), (346, 928), (356, 1000), (368, 1058)]
    side_b = [(392, 800), (402, 866), (402, 940), (396, 1010), (394, 1058)]
    al, edge = limb(side_a, side_b, cap_a=[(384, 776), (358, 778)], cap_b=[(374, 1076), (390, 1076)])
    part("arm_lower_r", skin(al, ((14, -4), (6, -2)), edge=edge, hi=False,
                             lines=[ink(taper([(354, 826), (348, 866)], 2.2, "both"), SKIN["ln"], 0.4),
                                    ink(taper([(394, 830), (396, 920), (390, 1010)], 6, "both"), SKIN["hi"], 0.8)]),
         parent="arm_upper_r", pivot=(370, 800), z=122)
    part("hand_r", relaxed_hand(380, 1062), parent="arm_lower_r", pivot=(380, 1062), z=126)
    alt("hand_r_open", relaxed_hand(380, 1062, True), slot="hand_r", variant="open")
    # satin drape hanging behind the near arm from the armlet
    sv = smooth([(366, 622), (410, 636), (392, 760), (384, 900), (394, 1040), (402, 1130, "c"), (344, 1110),
                 (284, 1124, "c"), (304, 980), (328, 820), (346, 700)], True)
    lining = smooth([(284, 1124), (314, 1060), (354, 1080), (402, 1130), (344, 1110)], True)
    s = satin(sv, ((24, -6), (10, -2)), over=[path(lining, SKY["b"]), path(lining, SKY["s1"], op=0.4)],
              lines=[fold([(366, 700), (346, 880), (326, 1060)], 2.8, 0.7), fold([(392, 760), (386, 920), (394, 1060)], 2.4, 0.5)])
    s += gold_band([(284, 1124), (344, 1112), (402, 1130)], 6)
    part("sleeve_r", s, parent="arm_upper_r", pivot=(388, 636), z=119, spring="sleeve;limit=14")

    # ---- far arm (her left): raised, presenting the floating sceptre
    side_a = [(644, 470), (658, 520), (666, 600), (676, 700), (690, 790)]
    side_b = [(610, 540), (618, 600), (632, 680), (648, 760), (660, 804)]
    au, edge = limb(side_a, side_b, cap_a=[(612, 500), (624, 466)], cap_b=[(692, 820), (676, 830)])
    part("arm_upper_l", skin(au, ((12, -4),), edge=edge) + armlet([(624, 634), (650, 642), (674, 634)], 11),
         parent="clavicle_l", pivot=(624, 488), z=40)
    al = smooth([(664, 808), (674, 784), (702, 760), (742, 736), (786, 710), (792, 742), (746, 764), (708, 792), (682, 826)], True)
    edge = opn([(674, 784), (702, 760), (742, 736), (786, 710)]) + " " + opn([(682, 826), (708, 792), (746, 764), (792, 742)])
    part("arm_lower_l", skin(al, ((6, -10), (2, -4)), edge=edge), parent="arm_upper_l", pivot=(674, 800), z=42)
    pl = smooth([(784, 712), (812, 704), (846, 706), (852, 728), (820, 742), (788, 744)], True)
    h = finger((844, 728), (884, 730), 6.5, 5, -2) + finger((848, 722), (896, 720), 7, 5.5, -3)
    h += finger((848, 714), (900, 708), 7, 5.5, -4) + finger((846, 708), (894, 698), 6.5, 5, -4)
    h += skin(pl, ((6, -6),), lw=2.4, hi=(SKIN["hi"], -6, 6, 0.6))
    h += finger((808, 712), (840, 686), 7, 5.5, 3)
    h += gold_band([(786, 708), (790, 726), (788, 744)], 9)
    part("hand_l", h, parent="arm_lower_l", pivot=(788, 724), z=46)
    sv = smooth([(640, 630), (676, 640), (700, 760), (712, 900), (720, 1040, "c"), (676, 1020), (640, 1060, "c"),
                 (640, 900), (636, 760)], True)
    s = satin(sv, ((18, -6), (8, -2)), over=[path(smooth([(640, 1060), (660, 1000), (700, 1010), (720, 1040), (676, 1020)]), SKY["b"])],
              lines=[fold([(660, 700), (676, 860), (684, 1000)], 2.6, 0.6)])
    s += gold_band([(640, 1060), (676, 1020), (720, 1040)], 5)
    part("sleeve_l", s, parent="arm_upper_l", pivot=(652, 640), z=38, spring="sleeve;limit=12")


# ------------------------------------------------------------------ legs
def legs():
    # far (weight) leg: under the gown, painted for the rig only
    part("thigh_l", skin(smooth([(560, 1080), (640, 1080), (646, 1300), (632, 1540), (590, 1560), (572, 1300)], True), ((10, -4),)),
         parent="hips", pivot=(596, 1090), z=50)
    part("shin_l", skin(smooth([(590, 1520), (634, 1520), (632, 1700), (628, 1910), (602, 1914), (592, 1700)], True), ((8, -4),)),
         parent="thigh_l", pivot=(612, 1540), z=52)
    part("foot_l", skin(smooth([(600, 1900), (632, 1900), (680, 1966), (686, 1984), (640, 1978), (606, 1950)], True), ((8, -4),)),
         parent="shin_l", pivot=(618, 1912), z=54)
    # near (free) leg, revealed by the slit. Thigh is drawn over the shin so the kneecap
    # covers the joint; caps are unlined.
    side_a = [(404, 1090), (404, 1200), (412, 1300), (432, 1410), (460, 1490), (478, 1536)]
    side_b = [(500, 1110), (530, 1200), (546, 1300), (550, 1400), (546, 1470), (541, 1512), (546, 1540), (538, 1566)]
    th, edge = limb(side_a, side_b, cap_a=[(470, 1060), (430, 1066)], cap_b=[(488, 1568), (512, 1582)])
    s = skin(th, ((26, -6), (10, -3)), edge=edge, hi=False, over=[path(ellipse_d(522, 1330, 14, 110, -8), SKIN["hi"], op=0.7)],
             lines=[ink(taper([(512, 1536), (528, 1552), (540, 1550)], 2.2, "both"), SKIN["ln"], 0.5)])
    s += gold_band([(406, 1238), (470, 1258), (540, 1244)], 10) + gem(470, 1258, 6)
    s += chain([(420, 1248), (450, 1292), (500, 1290), (532, 1252)], 8)
    part("thigh_r", s, parent="hips", pivot=(452, 1112), z=66)
    side_a = [(480, 1520), (470, 1580), (462, 1650), (461, 1710), (468, 1790), (480, 1870), (486, 1902)]
    side_b = [(536, 1520), (540, 1580), (536, 1660), (528, 1760), (520, 1850), (514, 1902)]
    sh, edge = limb(side_a, side_b, cap_a=[(520, 1496), (490, 1500)], cap_b=[(492, 1922), (510, 1922)])
    s = skin(sh, ((16, -4), (6, -2)), edge=edge, hi=False, over=[path(ellipse_d(526, 1660, 8, 80, -5), SKIN["hi"], op=0.75)])
    part("shin_r", s, parent="thigh_r", pivot=(510, 1528), z=64)
    a = [(514, 1884), (522, 1906), (540, 1934), (562, 1962), (584, 1984), (580, 1992)]
    b = [(580, 1992), (556, 1988), (528, 1974), (502, 1952), (484, 1928), (478, 1904), (484, 1884)]
    ft = smooth(a + b[1:-1] + [(484, 1884), (500, 1878)], True)
    s = skin(ft, ((10, -4),), edge=opn(a) + " " + opn(b),
             lines=[ink(taper([(556, 1988), (568, 1980), (582, 1988)], 1.6, "both"), SKIN["ln"], 0.6),
                    ink(taper([(546, 1984), (556, 1976)], 1.4, "both"), SKIN["ln"], 0.5)])
    s += chain([(480, 1890), (498, 1904), (518, 1892)], 7) + chain([(484, 1898), (498, 1918), (516, 1904)], 6) + gem(498, 1920, 4.5)
    s += gold_band([(552, 1976), (558, 1982), (562, 1976)], 4)
    part("foot_r", s, parent="shin_r", pivot=(498, 1898), z=68)


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
    zs = {}
    for p in d.parts:
        m = re.search(r'data-z="(-?\d+)"', p)
        if m:
            zs[re.search(r'id="([^"]+)"', p).group(1)] = int(m.group(1))

    def zof(p):
        m = re.search(r'data-z="(-?\d+)"', p)
        if m:
            return int(m.group(1))
        m = re.search(r'data-slot="([^"]+)"', p)
        if m:
            for k, v in zs.items():
                if k.startswith(m.group(1)):
                    return v + 0.5
        return -1
    d.parts.sort(key=zof)
    svg = d.svg(' data-hero="seraphiel" data-origin="512,1990" data-texel-scale="0.75" data-portrait="530,330,470"'
                ' data-weapon="sceptre" data-attack="attack_ranged" data-fx-color="#ffe9a8" data-look-px="14,8"')
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "art", "heroes", "seraphiel", "seraphiel.svg")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w") as fh:
        fh.write(svg)
    print("wrote", os.path.normpath(out), "%d KB" % (len(svg) // 1024), len(d.parts), "groups")


if __name__ == "__main__":
    build()
