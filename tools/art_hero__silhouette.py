"""Fallback rig for heroes without art: a hooded, cloaked full-scale figure in GREYSCALE.

The runtime gradient-maps luminance to faction colours (rig shader map_* uniforms), and the
build writes faction-tinted stills/portraits (data-tint-variants). It uses the standard
skeleton with standard female landmarks, so it is also the reference/template rig.

    python3 tools/art_hero__silhouette.py && tools/art_build _silhouette
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from art_svgkit import Doc, smooth, taper, shape, path, line, ellipse_d, ink, f
from art_body import FEMALE as L, limb, limb_d, along

OUT = "#151515"
C0, C1, C2, C3 = "#2c2c2c", "#1f1f1f", "#141414", "#3c3c3c"   # cloak base / shade / deep / lit
RIM = "#e6e6e6"
GLOW = "#ffffff"

d = Doc(1024, 2048)


def rim(pts, w=7):
    return ink(taper(pts, w, "both"), RIM, op=0.85)


def P(pid, body, **m):
    d.part(pid, body, **m)


# ---- wings: none. Hair: none (hood). Cape/cloak back panel
cape = [(470, 430), (360, 520), (300, 900), (250, 1400), (230, 1900, "c"), (420, 1940), (560, 1930), (700, 1945, "c"), (690, 1500), (640, 1000), (600, 480)]
P("cape", shape(d, smooth(cape), C1, [(smooth([(230, 1900), (330, 1200), (380, 700), (420, 1960)]), C2)], [], OUT, 6)
  + rim([(330, 560), (275, 1000), (245, 1500), (238, 1890)], 9),
  parent="chest_upper", pivot=(520, 470), z=40, spring="cape;limit=10")

# far arm (behind body)
au_l = limb(L["shoulder_l"], L["elbow_l"], [(0, 44), (0.5, 40), (1, 32)], [(0, 40), (0.5, 36), (1, 30)])
P("arm_upper_l", shape(d, smooth(au_l), C1, [], [], OUT, 5), parent="clavicle_l", pivot=L["shoulder_l"], z=200)
al_l = limb(L["elbow_l"], L["wrist_l"], [(0, 32), (1, 26)], [(0, 32), (1, 26)])
P("arm_lower_l", shape(d, smooth(al_l), C1, [], [], OUT, 5), parent="arm_upper_l", pivot=L["elbow_l"], z=210)
hr = [(672, 1074), (708, 1074), (716, 1136), (700, 1192), (676, 1192), (666, 1136)]
P("hand_l", shape(d, smooth(hr), C3, [], [], OUT, 4), parent="arm_lower_l", pivot=L["wrist_l"], z=220)

# legs (boots under the robe)
for side, z0 in (("l", 250), ("r", 300)):
    hip, knee, ank, toe = L["hip_" + side], L["knee_" + side], L["ankle_" + side], L["toe_" + side]
    th = limb(hip, knee, [(0, 80), (0.5, 66), (1, 46)], [(0, 76), (0.5, 60), (1, 44)])
    P("thigh_" + side, shape(d, smooth(th), C2, [], [], OUT, 5), parent="hips", pivot=hip, z=z0)
    sh = limb(knee, ank, [(0, 46), (0.3, 50), (1, 26)], [(0, 44), (0.3, 42), (1, 24)])
    P("shin_" + side, shape(d, smooth(sh), C1, [], [], OUT, 5) + rim([along(knee, ank, 0.1, -40), along(knee, ank, 0.9, -24)], 6),
      parent="thigh_" + side, pivot=knee, z=z0 + 5)
    ft = [(ank[0] - 30, ank[1] - 20), (ank[0] + 26, ank[1] - 18), (toe[0], toe[1] - 14, "c"), (toe[0] - 6, toe[1] + 2), (ank[0] - 34, ank[1] + 62)]
    P("foot_" + side, shape(d, smooth(ft), C1, [], [], OUT, 5), parent="shin_" + side, pivot=ank, z=z0 + 10)

# robe: hips/skirt, torso, chest
skirt = [(440, 1000), (610, 1000), (690, 1500), (730, 1880, "c"), (600, 1900), (470, 1885), (330, 1895, "c"), (380, 1400)]
P("skirt_back", shape(d, smooth(skirt), C0, [(smooth([(380, 1400), (440, 1100), (470, 1890), (330, 1895)]), C1)], [], OUT, 6)
  + rim([(390, 1150), (360, 1500), (338, 1880)], 8),
  parent="hips", pivot=(525, 1040), z=350)
hips = [(436, 960), (612, 960), (640, 1080), (520, 1120), (400, 1080)]
P("hips", shape(d, smooth(hips), C0, [], [], OUT, 5), parent="root", pivot=L["pelvis_c"], z=360)
front = [(500, 1060), (560, 1060), (600, 1500), (610, 1860, "c"), (540, 1880), (480, 1860, "c"), (470, 1500)]
P("skirt_front", shape(d, smooth(front), C3, [(smooth([(470, 1500), (500, 1070), (520, 1870), (480, 1860)]), C0)], [], OUT, 5),
  parent="hips", pivot=(530, 1060), z=370)
torso = [(452, 780), (612, 780), (604, 900), (630, 1010), (420, 1010), (448, 900)]
P("torso", shape(d, smooth(torso), C0, [], [], OUT, 5), parent="hips", pivot=(528, 960), z=400)
chest = [(430, 560), (640, 560), (620, 700), (608, 820), (452, 820), (438, 700)]
P("chest", shape(d, smooth(chest), C0, [(smooth([(430, 560), (470, 600), (470, 820), (452, 820), (438, 700)]), C1)], [], OUT, 5),
  parent="torso", pivot=(532, 800), z=410)
cu = [(400, 480), (470, 445), (590, 440), (650, 480), (660, 560), (620, 650), (440, 650), (396, 560)]
P("chest_upper", shape(d, smooth(cu), C0, [], [], OUT, 6) + rim([(410, 500), (398, 560), (420, 620)], 7),
  parent="chest", pivot=(536, 640), z=420)
P("clavicle_r", "", parent="chest_upper", pivot=(520, 455))
P("clavicle_l", "", parent="chest_upper", pivot=(545, 452))
P("neck", shape(d, smooth([(482, 340), (560, 340), (566, 450), (474, 450)]), C2, [], [], OUT, 4), parent="chest_upper", pivot=(520, 445), z=390)

# head = hood with shadowed face
hood = [(526, 60), (630, 110), (668, 230), (640, 380), (600, 470), (470, 470), (410, 380), (392, 220), (430, 110)]
face = [(470, 200), (600, 196), (615, 260), (596, 330), (552, 366), (490, 340), (466, 270)]
P("head", shape(d, smooth(hood), C0, [(smooth([(392, 220), (440, 120), (470, 300), (470, 470), (410, 380)]), C1)], [], OUT, 6)
  + path(smooth(face), C2) + rim([(420, 140), (396, 240), (410, 360)], 9)
  + ink(taper([(470, 196), (530, 170), (606, 192)], 10, "both"), C3),
  parent="neck", pivot=(505, 330), z=500)
for side, (ex, ey), w in (("r", L["eye_r"], 30), ("l", L["eye_l"], 24)):
    P("eye_%s_open" % side, ink(taper([(ex - w * 0.5, ey + 2), (ex, ey - 6), (ex + w * 0.5, ey + 1)], 12, "both"), GLOW),
      slot="eye_" + side, variant="open", default="1", parent="head", pivot=(ex, ey), z=520 if side == "r" else 521)
    P("eye_%s_closed" % side, ink(taper([(ex - w * 0.5, ey), (ex, ey + 4), (ex + w * 0.5, ey)], 5, "both"), GLOW),
      slot="eye_" + side, variant="closed")
hood_front = [(526, 70), (626, 112), (664, 228), (650, 190), (600, 150), (526, 140), (450, 160), (412, 220), (430, 110)]
P("hair_top", shape(d, smooth(hood_front), C3, [], [], OUT, 5), parent="head", pivot=(526, 150), z=550)

# near arm (front)
au_r = limb(L["shoulder_r"], L["elbow_r"], [(0, 48), (0.5, 44), (1, 36)], [(0, 46), (0.5, 42), (1, 34)])
P("arm_upper_r", shape(d, smooth(au_r), C0, [], [], OUT, 5) + rim([along(L["shoulder_r"], L["elbow_r"], 0.1, -44), along(L["shoulder_r"], L["elbow_r"], 0.9, -34)], 7),
  parent="clavicle_r", pivot=L["shoulder_r"], z=620)
al_r = limb(L["elbow_r"], L["wrist_r"], [(0, 36), (0.6, 46), (1, 50)], [(0, 34), (0.6, 44), (1, 48)])
P("arm_lower_r", shape(d, smooth(al_r), C0, [], [], OUT, 5), parent="arm_upper_r", pivot=L["elbow_r"], z=630)
hl = [(392, 1096), (436, 1096), (446, 1160), (430, 1220), (404, 1222), (392, 1160)]
P("hand_r", shape(d, smooth(hl), C3, [], [], OUT, 4), parent="arm_lower_r", pivot=L["wrist_r"], z=650)

svg = d.svg(' data-hero="_silhouette" data-origin="512,1990" data-texel-scale="0.5" data-portrait="530,330,460"'
            ' data-tint-variants="celestial=f2c14e,infernal=d9412b,fallen=8e6ce0"')
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "art", "heroes", "_silhouette", "_silhouette.svg")
os.makedirs(os.path.dirname(out), exist_ok=True)
open(out, "w").write(svg)
print("wrote", os.path.normpath(out), len(svg), "bytes")
