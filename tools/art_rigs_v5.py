"""Hand rigs for the 15 heroes' Amanatsu v5 art (2026-10-19): writes
assets/art/heroes/<id>/<id>.warp_src.json from a short spec per hero (skeleton points, spring parts
drawn by eye on a pixel grid of the installed 1024x2048 image), then you build:

    python tools/art_rigs_v5.py [hero ...]              # write warp_src.json (all specced heroes)
    python tools/art_warp_build.py <hero> --regen-masks  # build; then tools/gd --headless --path . --import

Face, head and bang regions come from the face box (face_yolov8m, art_src/_review/skinrig/base_faces.json
on the PC, copied into FACES below); eye/mouth overlays from the install hand-off
(art_src/_handoff/<id>.json, written by tools/comfy/install.py after variants.py) when present.
Weapon/attack meta are kept from the hero's current rig. Grids: art_src/_review/tools/rig_grid.py.
Part tuple: (name, parent, pivot, rule, spring or None[, extra bone fields]). Regions are listed in
priority order (first wins where masks overlap): face, bangs, then the parts as listed, head, chest.
"""
import json
import os
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
HEROES = os.path.join(ROOT, "assets", "art", "heroes")
FX = {"celestial": "#ffe9a8", "infernal": "#ff8a3d", "fallen": "#b48cff"}
FACES = {"seraphiel": [476, 888, 123, 122], "cassiel": [539, 881, 178, 177], "liora": [531, 964, 165, 168],
         "uriela": [446, 821, 138, 137], "nuriel": [521, 849, 148, 146], "mordessa": [494, 782, 159, 159],
         "brakka": [460, 403, 193, 192], "vesper": [441, 552, 168, 166], "imra": [367, 419, 183, 185],
         "kessa": [741, 585, 221, 216], "noctaire": [435, 877, 136, 132], "orrin": [409, 784, 138, 137],
         "sable": [474, 521, 183, 181], "lucen": [565, 656, 170, 173], "ashra": [407, 690, 163, 161]}


def poly(*pts, feather=16):
    return {"type": "polygon", "points": [list(p) for p in pts], "feather": feather}


def ell(cx, cy, rx, ry, feather=24):
    return {"type": "ellipse", "center": [cx, cy], "radius": [rx, ry], "feather": feather}


def minus(a, *bs, feather=20):
    return {"type": "subtract", "rules": [a] + list(bs), "feather": feather}


def union(*rs, feather=16):
    return {"type": "union", "rules": list(rs), "feather": feather}


# Per hero: spine points (hips, torso = waist, chest, neck), the chest polygon, the parts, and the
# seed the art came from (for the _doc).
H = {}

H["kessa"] = dict(
    seed=205602, hips=(340, 1170), torso=(470, 1010), chest=(640, 930), neck=(770, 800),
    head_pivot=(835, 790),
    chest_poly=poly((560, 800), (820, 760), (855, 900), (805, 1085), (600, 1105), (450, 1005), (470, 880), feather=40),
    parts=[
        ("hair_back", "head", (930, 700), poly((915, 690), (985, 690), (1000, 760), (975, 850), (920, 840), (905, 760), feather=14), "hair_long;g=0.85;limit=18"),
        ("weapon", "arm_r", (305, 600), poly((20, 380), (200, 345), (400, 370), (410, 470), (345, 545), (300, 660), (240, 680), (120, 725), (25, 650), feather=10), "weapon", {"tip": [60, 470]}),
        ("arm_r", "chest", (570, 805), poly((290, 535), (370, 530), (440, 640), (610, 770), (600, 860), (500, 870), (380, 715), (295, 650), feather=22), None),
        ("tail", "hips", (310, 880), poly((330, 885), (240, 865), (175, 780), (165, 680), (200, 600), (260, 555), (330, 485), (420, 470), (500, 515), (490, 650), (425, 665), (415, 570), (345, 575), (270, 640), (250, 740), (285, 835), feather=12), "tail;limit=10;g=0.45"),
        ("scarf", "neck", (770, 760), poly((700, 760), (800, 745), (850, 800), (845, 890), (760, 895), (720, 840)), "ribbon;limit=12"),
        ("bust", "chest", (640, 925), ell(685, 990, 130, 100, 30), "bust"),
        ("rear", "hips", (440, 1000), ell(295, 990, 150, 140, 34), "bust;k=70;limit=6"),
    ],
)

H["seraphiel"] = dict(
    seed=101601, hips=(545, 1330), torso=(545, 1250), chest=(545, 1110), neck=(540, 1012),
    chest_poly=poly((440, 1010), (650, 1010), (690, 1110), (660, 1250), (430, 1250), (410, 1110), feather=40),
    parts=[
        ("hair_back", "head", (470, 985), poly((445, 975), (395, 1040), (300, 1120), (220, 1260), (215, 1400), (300, 1460), (390, 1400), (440, 1260), (470, 1080), feather=18), "hair_long;g=0.9;limit=16"),
        ("weapon", "arm_l", (690, 965), poly((640, 735), (725, 735), (735, 900), (712, 1010), (662, 1010), (648, 900), feather=12), "weapon", {"tip": [690, 780]}),
        ("arm_l", "chest", (650, 1060), poly((630, 1040), (690, 950), (770, 950), (770, 1010), (705, 1090), feather=16), None),
        ("wing_r", "chest", (430, 1090), poly((430, 1000), (300, 985), (150, 1100), (45, 1350), (25, 1560), (85, 1800), (185, 1950), (265, 1700), (335, 1450), (415, 1250), (440, 1120), feather=18), "wing"),
        ("wing_l", "chest", (650, 1110), poly((645, 1060), (760, 1030), (880, 1150), (985, 1450), (1003, 1700), (965, 1885), (865, 1650), (800, 1450), (705, 1300), (655, 1200), feather=18), "wing"),
        ("train", "hips", (545, 1390), minus(poly((430, 1380), (650, 1380), (705, 1700), (835, 1965), (145, 1965), (375, 1700)),
                                              poly((455, 1370), (640, 1370), (610, 1900), (570, 1995), (495, 1995), (470, 1700))), "cloth;limit=6;b=0.8"),
        ("bust", "chest", (555, 1060), ell(560, 1128, 125, 80, 26), "bust"),
    ],
)


H["cassiel"] = dict(
    seed=102600, hips=(540, 1400), torso=(560, 1330), chest=(610, 1180), neck=(620, 1060),
    chest_poly=poly((520, 1060), (740, 1060), (780, 1180), (720, 1330), (500, 1350), (470, 1200), feather=40),
    parts=[
        ("weapon", "chest", (810, 1340), poly((740, 1090), (820, 1110), (1000, 1190), (960, 1400), (880, 1600), (760, 1660), (720, 1500), (720, 1200), feather=12), "weapon;limit=4"),
        ("arm_r", "chest", (450, 1120), poly((300, 1100), (450, 1080), (480, 1180), (400, 1360), (310, 1360), (250, 1250), feather=18), None),
        ("wing_r", "chest", (450, 1180), poly((430, 1110), (300, 1080), (150, 1020), (25, 1010), (60, 1080), (110, 1180), (230, 1250), (400, 1270), (480, 1230), feather=18), "wing"),
        ("wing_l", "chest", (720, 1080), poly((700, 1080), (730, 930), (800, 820), (850, 700), (860, 800), (850, 900), (790, 1030), (740, 1090), feather=16), "wing"),
        ("bust", "chest", (630, 1170), ell(640, 1230, 130, 80, 26), "bust"),
    ],
)

H["liora"] = dict(
    seed=103600, hips=(420, 1400), torso=(470, 1310), chest=(580, 1220), neck=(610, 1130),
    chest_poly=poly((500, 1120), (720, 1120), (720, 1300), (600, 1360), (450, 1300), (470, 1180), feather=40),
    parts=[
        ("hair_back", "head", (690, 1080), poly((690, 1050), (800, 1080), (950, 1150), (1000, 1250), (900, 1250), (780, 1230), (700, 1200), feather=16), "hair_long;g=0.85;limit=16"),
        ("braid", "head", (570, 1120), poly((540, 1120), (600, 1120), (600, 1250), (560, 1260), (540, 1200), feather=10), "hair;limit=10"),
        ("weapon", "chest", (650, 1460), poly((650, 1215), (800, 1220), (940, 1310), (930, 1360), (810, 1500), (650, 1490), (640, 1350), feather=10), "weapon;limit=5"),
        ("wing_r", "chest", (490, 1150), poly((500, 1130), (420, 1040), (250, 930), (30, 815), (60, 880), (150, 960), (240, 1060), (330, 1120), (430, 1170), feather=18), "wing"),
        ("wing_l", "chest", (700, 1090), poly((690, 1080), (760, 960), (850, 830), (940, 720), (930, 800), (870, 930), (800, 1040), (740, 1110), feather=16), "wing"),
        ("sarong", "hips", (420, 1300), minus(poly((250, 1250), (420, 1300), (550, 1500), (700, 1560), (900, 1600), (880, 1700), (700, 1780), (500, 1800), (350, 1880), (250, 1700), (200, 1500)),
                                             poly((320, 1450), (440, 1440), (470, 1800), (440, 1990), (400, 1990), (330, 1700)),
                                             poly((520, 1480), (640, 1470), (660, 1700), (700, 1990), (640, 1990), (560, 1750))), "cloth;limit=6;b=0.8"),
        ("bust", "chest", (600, 1220), ell(600, 1290, 110, 90, 26), "bust"),
        ("rear", "hips", (420, 1270), ell(330, 1250, 100, 90, 28), "bust;k=70;limit=6"),
    ],
)

H["uriela"] = dict(
    seed=104601, hips=(500, 1290), torso=(510, 1200), chest=(530, 1060), neck=(515, 960),
    chest_poly=poly((430, 970), (610, 970), (640, 1080), (600, 1220), (440, 1220), (410, 1080), feather=40),
    parts=[
        ("hair_back", "head", (460, 880), poly((440, 860), (380, 870), (300, 920), (310, 990), (380, 990), (450, 950), feather=14), "hair_long;g=0.8;limit=18"),
        ("weapon", "arm_l", (775, 1340), poly((720, 710), (840, 710), (840, 1150), (800, 1400), (790, 1960), (750, 1960), (750, 1400), (720, 1150), feather=10), "weapon;limit=4", {"tip": [780, 720]}),
        ("arm_l", "chest", (600, 1010), poly((590, 1000), (660, 1000), (720, 1150), (800, 1330), (760, 1370), (690, 1250), (610, 1120), feather=16), None),
        ("wing_r", "chest", (360, 1100), poly((330, 1030), (220, 980), (30, 935), (60, 1000), (110, 1090), (220, 1200), (330, 1230), (400, 1150), feather=18), "wing"),
        ("wing_l", "chest", (640, 1110), poly((640, 1050), (760, 1010), (1000, 920), (980, 1000), (900, 1100), (760, 1200), (650, 1200), feather=18), "wing"),
        ("bust", "chest", (535, 1010), ell(540, 1060, 110, 70, 24), "bust"),
    ],
)

H["nuriel"] = dict(
    seed=105601, hips=(520, 1300), torso=(540, 1230), chest=(590, 1110), neck=(600, 1010),
    chest_poly=poly((500, 1020), (700, 1020), (720, 1150), (650, 1260), (500, 1260), (470, 1150), feather=40),
    parts=[
        ("weapon", "chest", (340, 1350), poly((285, 1260), (320, 1260), (400, 1400), (610, 1690), (560, 1700), (360, 1470), (290, 1340), feather=10), "weapon;limit=5"),
        ("dagger_hip", "hips", (680, 1330), poly((650, 1310), (720, 1310), (950, 1640), (900, 1650), (700, 1430), (650, 1360), feather=10), "accessory;limit=6"),
        ("wing_r", "chest", (390, 1030), poly((400, 980), (330, 900), (220, 840), (30, 790), (60, 860), (140, 960), (120, 1060), (190, 1180), (330, 1180), (420, 1100), feather=14), "wing"),
        ("wing_l", "chest", (720, 1000), poly((700, 980), (760, 860), (850, 690), (860, 760), (820, 900), (780, 1000), (730, 1020), feather=12), "wing"),
        ("jacket_r", "chest", (470, 1080), poly((360, 1100), (480, 1080), (500, 1250), (440, 1330), (360, 1320), feather=16), "cloth;limit=8"),
        ("jacket_l", "chest", (690, 1020), poly((650, 1020), (760, 1000), (740, 1330), (700, 1330), (660, 1200), feather=16), "cloth;limit=8"),
        ("bust", "chest", (595, 1060), ell(600, 1110, 90, 60, 22), "bust"),
    ],
)

H["mordessa"] = dict(
    seed=201601, hips=(540, 1290), torso=(560, 1200), chest=(610, 1040), neck=(570, 930),
    chest_poly=poly((500, 940), (780, 940), (800, 1100), (700, 1240), (470, 1260), (470, 1080), feather=40),
    parts=[
        ("weapon", "chest", (820, 810), poly((25, 1030), (300, 960), (720, 760), (770, 720), (1000, 760), (1000, 810), (800, 840), (700, 880), (330, 1010), (40, 1050), feather=10), "weapon;limit=4"),
        ("hair_back", "head", (490, 880), poly((480, 860), (400, 880), (300, 930), (290, 1000), (380, 1060), (470, 1040), (500, 960), feather=16), "hair_long;g=0.85;limit=14"),
        ("wing_r", "chest", (410, 1120), poly((410, 1060), (300, 1080), (160, 1150), (80, 1250), (130, 1330), (260, 1320), (390, 1230), (430, 1150), feather=16), "wing"),
        ("wing_l", "chest", (750, 1120), poly((740, 1110), (850, 1090), (940, 1200), (930, 1380), (860, 1300), (760, 1250), feather=16), "wing"),
        ("tail", "hips", (380, 1300), poly((380, 1300), (330, 1380), (300, 1500), (350, 1600), (470, 1700), (560, 1700), (560, 1760), (470, 1760), (320, 1620), (270, 1480), (290, 1350), (350, 1290), feather=10), "tail;limit=10;g=0.5"),
        ("coat_r", "chest", (420, 1200), minus(poly((360, 1160), (240, 1180), (60, 1350), (30, 1500), (80, 1620), (200, 1600), (330, 1500), (420, 1380), (450, 1250)),
                                              poly((330, 1330), (560, 1330), (470, 1650), (330, 1990), (250, 1990), (300, 1700))), "cape;limit=8"),
        ("coat_l", "chest", (760, 1260), minus(poly((760, 1250), (860, 1300), (990, 1500), (990, 1650), (900, 1660), (800, 1500), (760, 1400)),
                                              poly((600, 1340), (760, 1340), (900, 1800), (960, 1990), (870, 1990), (700, 1700))), "cape;limit=8"),
        ("bust", "chest", (640, 970), ell(650, 1050, 140, 90, 28), "bust"),
    ],
)

H["brakka"] = dict(
    seed=202601, hips=(520, 1050), torso=(560, 900), chest=(570, 740), neck=(560, 590),
    chest_poly=poly((420, 620), (720, 620), (800, 760), (760, 940), (470, 950), (420, 800), feather=40),
    parts=[
        ("arm_r", "chest", (440, 640), poly((195, 600), (230, 420), (320, 350), (430, 390), (450, 480), (380, 500), (320, 560), (310, 690), (240, 700), feather=18), None),
        ("arm_l", "chest", (650, 640), poly((640, 400), (760, 360), (860, 460), (900, 620), (860, 700), (760, 650), (700, 560), (640, 480), feather=18), None),
        ("tail", "hips", (470, 990), union(poly((470, 960), (300, 980), (100, 1050), (60, 1150), (90, 1300), (200, 1370), (250, 1330), (140, 1250), (120, 1130), (250, 1040), (420, 1010)),
                                          poly((720, 1330), (850, 1250), (950, 1100), (980, 1030), (880, 1000), (900, 1080), (820, 1200), (710, 1290)), feather=10), "tail;limit=6;g=0.5"),
        ("bust", "chest", (590, 690), ell(600, 790, 190, 110, 30), "bust"),
    ],
)

H["vesper"] = dict(
    seed=203601, hips=(490, 1090), torso=(500, 980), chest=(520, 820), neck=(530, 710),
    chest_poly=poly((400, 720), (640, 700), (660, 820), (620, 960), (400, 960), (370, 820), feather=40),
    parts=[
        ("wing_r", "chest", (320, 760), poly((320, 730), (250, 720), (150, 820), (60, 1000), (30, 1200), (60, 1300), (130, 1230), (160, 1100), (250, 1150), (290, 1100), (330, 900), feather=16), "wing"),
        ("wing_l", "chest", (700, 750), poly((700, 720), (790, 700), (880, 850), (960, 1050), (1000, 1300), (960, 1400), (900, 1250), (800, 1150), (720, 1150), (700, 900), feather=16), "wing"),
        ("cape_r", "chest", (320, 820), poly((280, 820), (330, 800), (340, 1200), (290, 1210), feather=14), "cape;limit=8"),
        ("cape_l", "chest", (660, 780), poly((640, 760), (720, 740), (740, 1250), (660, 1250), (640, 900), feather=14), "cape;limit=8"),
        ("tail", "hips", (610, 1290), poly((600, 1290), (650, 1300), (700, 1450), (680, 1560), (500, 1580), (300, 1560), (270, 1600), (280, 1700), (200, 1700), (210, 1580), (300, 1530), (480, 1540), (640, 1520), (630, 1400), (590, 1320), feather=10), "tail;limit=10;g=0.5"),
        ("bust", "chest", (500, 760), ell(500, 820, 140, 80, 26), "bust"),
    ],
)

H["imra"] = dict(
    seed=204602, hips=(500, 990), torso=(470, 880), chest=(440, 730), neck=(460, 610),
    chest_poly=poly((330, 600), (600, 600), (620, 760), (560, 870), (330, 880), (260, 760), feather=40),
    parts=[
        ("hair_back", "head", (600, 500), poly((600, 480), (700, 500), (690, 620), (620, 640), (580, 560), feather=14), "hair;limit=14"),
        ("wing_l", "chest", (610, 640), poly((590, 620), (700, 600), (850, 700), (960, 780), (900, 800), (780, 780), (680, 820), (620, 800), (600, 700), feather=14), "wing"),
        ("wing_r", "chest", (300, 800), poly((200, 820), (260, 780), (310, 800), (300, 960), (200, 950), feather=12), "wing"),
        ("tail", "hips", (650, 900), union(poly((620, 880), (700, 860), (830, 950), (900, 1100), (880, 1250), (780, 1350), (700, 1360), (730, 1300), (820, 1220), (850, 1100), (780, 970), (680, 930)),
                                          poly((130, 1220), (260, 1220), (260, 1320), (130, 1320)), feather=10), "tail;limit=6;g=0.5"),
        ("bust", "chest", (420, 690), ell(400, 750, 160, 85, 28), "bust"),
    ],
)

H["noctaire"] = dict(
    seed=301600, hips=(490, 1320), torso=(480, 1230), chest=(490, 1100), neck=(500, 1010),
    chest_poly=poly((390, 1010), (580, 1010), (600, 1120), (560, 1250), (400, 1260), (360, 1120), feather=40),
    parts=[
        ("hair_back", "head", (440, 1010), poly((440, 1000), (380, 1050), (280, 1120), (220, 1250), (240, 1350), (330, 1330), (400, 1230), (440, 1120), feather=16), "hair_long;g=0.9;limit=14"),
        ("weapon", "hips", (500, 1400), minus(union(poly((20, 1000), (60, 1000), (260, 1180), (230, 1210), (30, 1040)),
                                                    poly((680, 1500), (750, 1500), (800, 1560), (760, 1600)),
                                                    poly((720, 1520), (1000, 1560), (1000, 1780), (960, 1880), (320, 1880), (320, 1780), (700, 1700), (740, 1600))),
                                              poly((560, 1420), (680, 1420), (720, 1990), (660, 1990), (580, 1700)),
                                              poly((180, 1400), (450, 1400), (300, 1990), (150, 1990))), "weapon;limit=3"),
        ("wing_r", "chest", (390, 1100), poly((380, 1080), (300, 1150), (200, 1300), (150, 1500), (170, 1700), (250, 1650), (310, 1500), (360, 1350), (400, 1200), feather=16), "wing"),
        ("wing_l", "chest", (610, 1100), poly((600, 1080), (720, 1020), (850, 1100), (950, 1300), (990, 1550), (960, 1720), (900, 1600), (820, 1450), (700, 1350), (620, 1250), feather=16), "wing"),
        ("curtain", "hips", (490, 1380), poly((440, 1380), (540, 1380), (540, 1700), (450, 1700), feather=12), "cloth;limit=10"),
        ("bust", "chest", (470, 1030), ell(470, 1080, 110, 70, 24), "bust"),
    ],
)

H["orrin"] = dict(
    seed=302602, hips=(470, 1250), torso=(470, 1150), chest=(470, 1030), neck=(480, 930),
    chest_poly=poly((380, 930), (590, 930), (610, 1050), (560, 1160), (380, 1170), (340, 1060), feather=40),
    parts=[
        ("hair_back", "head", (410, 950), poly((410, 940), (330, 980), (230, 1050), (150, 1150), (200, 1200), (300, 1150), (380, 1080), (420, 1000), feather=16), "hair_long;g=0.85;limit=14"),
        ("weapon", "chest", (690, 1290), poly((700, 960), (920, 1000), (910, 1250), (870, 1600), (790, 1900), (740, 1960), (700, 1700), feather=12), "weapon;limit=3"),
        ("wing_r", "chest", (330, 950), poly((330, 900), (260, 760), (150, 800), (60, 950), (30, 1200), (60, 1500), (130, 1720), (200, 1650), (230, 1400), (280, 1200), (330, 1050), feather=18), "wing"),
        ("wing_l", "chest", (650, 950), poly((640, 900), (680, 740), (800, 760), (920, 900), (1000, 1150), (990, 1500), (940, 1720), (880, 1650), (900, 1400), (880, 1200), (760, 1000), feather=18), "wing"),
        ("bust", "chest", (460, 950), ell(460, 1010, 110, 70, 24), "bust"),
    ],
)

H["sable"] = dict(
    seed=303601, hips=(560, 1120), torso=(560, 1010), chest=(560, 840), neck=(560, 720),
    chest_poly=poly((420, 720), (720, 720), (740, 880), (680, 1000), (430, 1000), (380, 880), feather=40),
    parts=[
        ("hair_back", "head", (450, 640), poly((430, 620), (500, 640), (520, 800), (480, 930), (420, 900), (410, 750), feather=14), "hair_long;g=0.9;limit=12"),
        ("wing_r", "chest", (340, 760), poly((330, 700), (310, 470), (250, 480), (150, 600), (60, 800), (30, 1100), (110, 1450), (160, 1300), (200, 1100), (260, 950), (340, 850), feather=18), "wing"),
        ("wing_l", "chest", (720, 760), poly((720, 700), (760, 470), (830, 480), (920, 650), (990, 900), (1000, 1200), (920, 1480), (860, 1350), (840, 1100), (780, 900), (720, 850), feather=18), "wing"),
        ("skirt", "hips", (560, 1240), minus(poly((420, 1250), (700, 1230), (760, 1500), (800, 1950), (380, 1950), (420, 1600)),
                                            poly((440, 1200), (700, 1200), (650, 1600), (600, 1960), (490, 1960), (450, 1600))), "cloth;limit=4;b=0.8"),
        ("bust", "chest", (560, 820), ell(560, 900, 160, 90, 30), "bust"),
    ],
)

H["lucen"] = dict(
    seed=304600, hips=(480, 1200), torso=(560, 1100), chest=(620, 940), neck=(650, 830),
    chest_poly=poly((540, 830), (800, 820), (810, 1000), (700, 1120), (520, 1120), (480, 1000), feather=40),
    parts=[
        ("hair_back", "head", (730, 720), poly((720, 700), (800, 780), (840, 1000), (830, 1180), (760, 1170), (730, 1000), (700, 850), feather=16), "hair_long;g=0.85;limit=14"),
        ("weapon", "chest", (650, 1290), poly((610, 1230), (740, 1230), (730, 1360), (670, 1960), (640, 1960), (630, 1360), feather=10), "weapon;limit=4"),
        ("wing_r", "chest", (470, 920), poly((440, 620), (380, 600), (250, 700), (100, 850), (20, 1050), (30, 1250), (100, 1150), (200, 1400), (240, 1300), (260, 1100), (330, 1000), (420, 880), feather=14), "wing"),
        ("wing_l", "chest", (790, 880), poly((790, 820), (900, 730), (980, 800), (1000, 1000), (960, 1250), (860, 1490), (820, 1300), (790, 1100), feather=18), "wing"),
        ("bust", "chest", (650, 920), ell(660, 990, 130, 80, 26), "bust"),
        ("rear", "hips", (460, 1150), ell(380, 1170, 100, 90, 28), "bust;k=70;limit=6"),
    ],
)

H["ashra"] = dict(
    seed=305600, hips=(490, 1200), torso=(480, 1100), chest=(470, 960), neck=(490, 850),
    chest_poly=poly((330, 850), (620, 850), (650, 960), (600, 1080), (360, 1090), (310, 960), feather=40),
    parts=[
        ("hat", "head", (500, 700), poly((290, 600), (400, 560), (600, 540), (710, 600), (750, 750), (650, 750), (500, 700), (380, 720), (300, 700), feather=12), "accessory;limit=6"),
        ("weapon", "hips", (640, 1490), poly((780, 1170), (860, 1190), (840, 1240), (700, 1450), (620, 1520), (610, 1480), (730, 1300), (780, 1230), feather=10), "weapon;limit=6"),
        ("wing_r", "chest", (260, 1000), poly((270, 960), (230, 940), (150, 1000), (60, 1150), (30, 1300), (120, 1270), (200, 1200), (260, 1100), feather=14), "wing"),
        ("wing_l", "chest", (730, 980), poly((720, 950), (780, 940), (900, 1050), (1000, 1220), (980, 1380), (900, 1300), (800, 1200), (720, 1100), feather=14), "wing"),
        ("robe_r", "chest", (300, 900), poly((220, 700), (330, 720), (330, 1100), (310, 1500), (280, 1790), (210, 1600), (220, 1200), feather=16), "cape;limit=6"),
        ("robe_l", "chest", (680, 880), poly((640, 800), (770, 820), (780, 1100), (760, 1720), (680, 1700), (660, 1300), (640, 1000), feather=16), "cape;limit=6"),
        ("bust", "chest", (450, 880), ell(450, 940, 150, 90, 28), "bust"),
    ],
)


def build(hid):
    s = H[hid]
    d = os.path.join(HEROES, hid)
    src_path = os.path.join(d, hid + ".warp_src.json")
    old = json.load(open(src_path)) if os.path.exists(src_path) else {}
    heroes = {h["id"]: h for h in json.load(open(os.path.join(ROOT, "data", "heroes.json")))["heroes"]}
    fx, fy, fw, fh = FACES[hid]
    fcx = fx + fw / 2.0
    r = lambda v: int(round(v))
    head_pivot = s.get("head_pivot", (r(fcx - fw * 0.05), r(fy + fh * 1.02)))
    bones = [
        {"name": "hips", "parent": "root", "pivot": list(s["hips"])},
        {"name": "torso", "parent": "hips", "pivot": list(s["torso"])},
        {"name": "chest", "parent": "torso", "pivot": list(s["chest"])},
        {"name": "neck", "parent": "chest", "pivot": list(s["neck"])},
        {"name": "head", "parent": "neck", "pivot": list(head_pivot)},
        {"name": "face", "parent": "head", "pivot": [r(fcx), r(fy + fh * 0.45)]},
        {"name": "hair_front", "parent": "head", "pivot": [r(fcx), r(fy - fh * 0.15)], "spring": "bangs"},
    ]
    regions = [
        {"name": "face", "bone": "face", "rule": ell(r(fcx), r(fy + fh * 0.55), r(fw * 0.52), r(fh * 0.44), 14)},
        {"name": "hair_front", "rule": ell(r(fcx), r(fy + fh * 0.02), r(fw * 0.62), r(fh * 0.29), 12)},
    ]
    names = {b["name"] for b in bones}
    pending = list(s["parts"])
    # parents first (a part may hang from another part, e.g. weapon from arm)
    while pending:
        for p in list(pending):
            if p[1] in names:
                b = {"name": p[0], "parent": p[1], "pivot": list(p[2])}
                if p[4]:
                    b["spring"] = p[4]
                if len(p) > 5:
                    b.update(p[5])
                bones.append(b)
                names.add(p[0])
                pending.remove(p)
                break
        else:
            raise SystemExit("%s: unknown parent in %s" % (hid, [p[1] for p in pending]))
    for p in s["parts"]:
        regions.append({"name": p[0], "rule": p[3]})
    regions.append({"name": "head", "rule": ell(r(fcx), r(fy + fh * 0.35), r(fw * 1.0), r(fh * 0.95), 22)})
    regions.append({"name": "chest", "rule": s["chest_poly"]})
    ho = os.path.join(ROOT, "art_src", "_handoff", hid + ".json")
    overlays = (json.load(open(ho))["warp_src"].get("overlays") or []) if os.path.exists(ho) else old.get("overlays", [])
    meta = {k: v for k, v in (old.get("meta") or {}).items() if k in ("weapon", "attack")}
    meta.update({"fx_color": FX[heroes[hid]["faction"]], "art": "comfy s%d quick, hand rig v5" % s["seed"]})
    psize = min(r(max(320, fw * 3.0)), 1024)
    pcx = min(max(r(fcx), psize // 2 + 1), 1024 - psize // 2 - 1)
    src = {
        "_doc": "HaloRig warp rig source for %s, drawn by hand on the Amanatsu v5 art (s%d) by tools/art_rigs_v5.py "
                "(2026-10-19): spine, springs for hair/wings/cloth/tail/bust, weapon and arm regions, eye/mouth overlays "
                "from variants.py. Coordinates are image pixels of %s.png (1024x2048, soles at the origin). Regions are "
                "listed in priority order: where masks overlap, the first one wins." % (hid, s["seed"], hid),
        "image": hid + ".png", "origin": [512, 1990], "grid": [28, 56], "texel_scale": 1.0,
        "portrait": [pcx, r(fy + fh * 0.5), psize], "look_px": [12, 7], "meta": meta, "body_bone": "hips",
        "bones": bones, "regions": regions, "overlays": overlays,
    }
    with open(src_path, "w", newline="\n") as f:
        f.write(dumps(src))
    return src_path


def dumps(src):
    lines = ["{"]
    keys = list(src.keys())
    for i, k in enumerate(keys):
        comma = "," if i < len(keys) - 1 else ""
        v = src[k]
        if isinstance(v, list) and v and k in ("bones", "regions", "overlays"):
            lines.append('  "%s": [' % k)
            for j, e in enumerate(v):
                lines.append("    " + json.dumps(e, separators=(", ", ": ")) + ("," if j < len(v) - 1 else ""))
            lines.append("  ]" + comma)
        else:
            lines.append('  "%s": %s%s' % (k, json.dumps(v, separators=(", ", ": ")), comma))
    lines.append("}")
    return "\n".join(lines) + "\n"


if __name__ == "__main__":
    for h in (sys.argv[1:] or list(H)):
        print("wrote", os.path.relpath(build(h), ROOT))
