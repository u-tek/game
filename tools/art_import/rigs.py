"""Write assets/art/heroes/<id>/<id>.warp_src.json for the painted farm heroes.

Coordinates are canvas pixels (1024x2048, soles at y=1990). Each hero spec gives the skeleton key
points (neck, chest, waist, hips), the hair/halo/wing/weapon/cloth polygons and the meta; the face,
head and overlay rects come from the farm's face box and the variant diffs.
"""
import json
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
# The farm output branch checked out somewhere: git worktree add <dir> origin/art-gen-output
ARTGEN_OUT = os.environ.get("ARTGEN_OUT", os.path.join(REPO, "artgen-out"))


def load_picks():
    """tools/art_import/finals_picks.json with each canvas path resolved under ARTGEN_OUT."""
    picks = json.load(open(os.path.join(HERE, "finals_picks.json")))
    for p in picks.values():
        p["canvas"] = os.path.join(ARTGEN_OUT, p["canvas"])
    return picks


ROOT = os.environ.get("HALO_ASSETS_HEROES", os.path.join(REPO, "assets", "art", "heroes"))
FARM = load_picks()
FX = {"celestial": "#ffe9a8", "infernal": "#ff8a3d", "fallen": "#b48cff"}
FACTION = {h: f for f, hs in {"celestial": ["seraphiel", "cassiel", "liora", "uriela", "nuriel"],
                               "infernal": ["mordessa", "brakka", "vesper", "imra", "kessa"],
                               "fallen": ["noctaire", "orrin", "sable", "lucen", "ashra"]}.items() for h in hs}


def P(*pts):
    return [list(p) for p in pts]


# Per hero: k = key points; hair = [(bone, parent, pivot, poly, spring)]; extra regions; meta.
# Region tuples: (name, bone, parent, pivot, rule-dict, spring or None, extra bone fields)
H = {}

H["seraphiel"] = dict(
    neck=(505, 850), chest=(500, 985), waist=(500, 1120), hips=(500, 1230), shoulder=190,
    head_extra=None,
    halo=((505, 650), P((240, 515), (790, 515), (800, 800), (640, 800), (600, 700), (420, 700), (380, 800), (230, 800))),
    hair=[("hair_back", "head", (390, 840), P((330, 800), (430, 800), (440, 1000), (420, 1250), (400, 1530), (260, 1530), (170, 1350), (230, 1050)), "hair_long;limit=14;g=0.9"),
          ("hair_side_l", "head", (620, 830), P((590, 800), (690, 800), (760, 1000), (840, 1350), (840, 1720), (700, 1720), (650, 1400), (610, 1100)), "hair_long;limit=12;g=0.9")],
    wings=[("wing_r", (360, 900), P((360, 800), (220, 800), (90, 980), (10, 1300), (10, 1410), (140, 1390), (290, 1230), (330, 1060), (390, 960))),
           ("wing_l", (650, 900), P((640, 790), (790, 800), (930, 960), (1015, 1290), (1015, 1400), (880, 1360), (740, 1210), (690, 1010)))],
    weapon=dict(pivot=(770, 1160), tip=(872, 860), parent="hips",
                rule={"type": "union", "rules": [
                    {"type": "polygon", "points": P((770, 770), (975, 770), (975, 975), (880, 1010), (820, 1010), (770, 970))},
                    {"type": "polygon", "points": P((815, 985), (870, 985), (660, 1575), (590, 1575))},
                    {"type": "polygon", "points": P((730, 1110), (810, 1110), (810, 1200), (730, 1200))}]}),
    cloth=[("skirt", "hips", (500, 1240), {"type": "subtract", "rules": [
        {"type": "polygon", "points": P((300, 1230), (700, 1230), (780, 1520), (990, 1990), (40, 1990), (230, 1520))},
        {"type": "polygon", "points": P((330, 1250), (640, 1250), (600, 1500), (575, 1995), (425, 1995), (380, 1500))}], "feather": 26},
            "cloth;limit=5;b=0.9")],
    meta={"weapon": "sceptre", "attack": "attack_ranged"},
)

H["cassiel"] = dict(
    neck=(470, 780), chest=(470, 905), waist=(470, 1040), hips=(470, 1130), shoulder=175,
    halo=((450, 525), P((300, 480), (600, 480), (600, 570), (300, 570))),
    hair=[("hair_side", "head", (420, 700), P((360, 660), (420, 660), (420, 770), (360, 770)), "hair;limit=8")],
    wings=[("wing_r", (350, 760), P((370, 690), (300, 590), (120, 580), (10, 620), (10, 900), (200, 900), (320, 860), (370, 820))),
           ("wing_l", (600, 760), P((590, 700), (680, 590), (880, 600), (1015, 640), (1015, 900), (820, 900), (660, 860), (610, 820)))],
    weapon=dict(pivot=(700, 1000), tip=(760, 860), parent="chest",
                rule={"type": "polygon", "points": P((600, 860), (720, 845), (905, 870), (910, 1120), (820, 1335), (730, 1340), (620, 1160))}),
    cloth=[("skirt", "hips", (465, 1135), {"type": "polygon", "points": P((350, 1120), (590, 1120), (595, 1300), (575, 1890), (380, 1890), (355, 1300)), "feather": 18},
            "cloth;limit=5;b=0.8")],
    meta={"weapon": "shield"},
)

H["liora"] = dict(
    neck=(585, 900), chest=(560, 1010), waist=(520, 1130), hips=(480, 1230), shoulder=170,
    halo=((560, 610), P((400, 540), (720, 540), (720, 690), (560, 700), (400, 690))),
    hair=[("hair_side", "head", (650, 850), P((600, 840), (690, 840), (720, 960), (700, 1030), (610, 1030), (590, 930)), "hair;limit=10;g=0.8"),
          ("hair_back", "head", (500, 860), P((450, 820), (530, 830), (520, 960), (430, 960)), "hair_long;limit=10;g=0.9")],
    wings=[("wing_r", (420, 920), P((430, 880), (300, 760), (120, 790), (10, 940), (10, 1460), (90, 1600), (200, 1500), (300, 1200), (380, 1040))),
           ("wing_l", (690, 900), P((680, 860), (790, 820), (900, 900), (1015, 1180), (1015, 1500), (920, 1520), (800, 1250), (720, 1050)))],
    weapon=dict(pivot=(820, 1095), tip=(860, 1050), parent="chest",
                rule={"type": "polygon", "points": P((565, 1030), (700, 1010), (890, 1040), (890, 1130), (760, 1210), (720, 1320), (590, 1320), (565, 1200))}),
    cloth=[("cape", "hips", (420, 1180), {"type": "subtract", "rules": [
        {"type": "polygon", "points": P((300, 1120), (250, 1300), (60, 1700), (60, 1870), (280, 1820), (330, 1700), (420, 1400), (560, 1300), (650, 1660), (660, 1300), (600, 1120))},
        {"type": "polygon", "points": P((310, 1180), (530, 1200), (560, 1420), (500, 1990), (380, 1990), (330, 1500))}], "feather": 24},
            "cape;limit=6;b=0.7")],
    meta={"weapon": "lyre"},
)

H["uriela"] = dict(
    neck=(525, 830), chest=(520, 950), waist=(520, 1080), hips=(540, 1180), shoulder=170,
    halo=((520, 560), P((380, 500), (660, 500), (660, 630), (580, 630), (560, 590), (470, 590), (450, 630), (380, 630))),
    hair=[("hair_back", "head", (520, 640), P((470, 580), (590, 580), (600, 700), (470, 700)), "hair;limit=6")],
    wings=[("wing_r", (380, 880), P((390, 820), (300, 780), (150, 830), (10, 1000), (10, 1300), (90, 1300), (240, 1150), (330, 1000), (400, 930))),
           ("wing_l", (640, 860), P((620, 790), (700, 760), (860, 840), (1015, 1050), (1015, 1290), (920, 1290), (800, 1100), (680, 950)))],
    weapon=dict(pivot=(700, 805), tip=(885, 540), parent="chest",
                rule={"type": "polygon", "points": P((640, 760), (870, 495), (930, 515), (780, 720), (780, 860), (650, 870))}),
    cloth=[],
    meta={"weapon": "spear"},
)

H["nuriel"] = dict(
    neck=(540, 760), chest=(535, 880), waist=(530, 1020), hips=(520, 1130), shoulder=190,
    halo=((535, 540), P((340, 460), (730, 460), (730, 640), (630, 640), (600, 580), (470, 580), (440, 640), (340, 640))),
    hair=[],
    wings=[("wing_r", (420, 760), P((430, 700), (330, 660), (140, 650), (110, 720), (230, 850), (400, 880), (440, 820))),
           ("wing_l", (650, 750), P((640, 700), (760, 640), (1000, 600), (1000, 700), (900, 860), (700, 880), (640, 820)))],
    weapon=dict(pivot=(470, 960), tip=(600, 905), parent="chest", rule=None),
    cloth=[("coat_r", "chest", (340, 1000), {"type": "polygon", "points": P((300, 980), (380, 980), (390, 1300), (370, 1470), (290, 1470), (270, 1200)), "feather": 18}, "cloth;limit=8;b=0.7"),
           ("coat_l", "chest", (720, 1000), {"type": "polygon", "points": P((680, 980), (770, 960), (840, 1150), (860, 1360), (780, 1360), (700, 1200)), "feather": 18}, "cloth;limit=8;b=0.7")],
    meta={"weapon": "dagger"},
)

H["mordessa"] = dict(
    neck=(480, 900), chest=(480, 1000), waist=(470, 1110), hips=(480, 1200), shoulder=170,
    halo=None,
    hair=[("hair_back", "head", (360, 930), P((300, 900), (380, 900), (400, 1100), (380, 1360), (180, 1370), (170, 1200), (230, 1000)), "hair_long;limit=10;g=0.9"),
          ("hair_side_l", "head", (640, 930), P((600, 900), (690, 920), (780, 1050), (790, 1250), (660, 1250), (620, 1050)), "hair_long;limit=10;g=0.9")],
    wings=[("wing_r", (320, 880), P((330, 840), (200, 780), (40, 790), (40, 840), (180, 960), (330, 950)))],
    weapon=dict(pivot=(620, 930), tip=(990, 770), parent="chest",
                rule={"type": "polygon", "points": P((570, 880), (700, 850), (1015, 740), (1015, 800), (700, 950), (590, 990))}),
    cloth=[("skirt", "hips", (480, 1210), {"type": "subtract", "rules": [
        {"type": "polygon", "points": P((330, 1180), (640, 1180), (800, 1500), (930, 1820), (900, 1900), (100, 1900), (80, 1750), (250, 1450))},
        {"type": "polygon", "points": P((380, 1200), (600, 1200), (590, 1500), (590, 1995), (330, 1995), (370, 1500))}], "feather": 26},
            "cloth;limit=6;b=0.8"),
           ("tail", "hips", (220, 1360), {"type": "polygon", "points": P((230, 1330), (90, 1330), (80, 1620), (200, 1620), (250, 1400)), "feather": 14}, "tail;limit=16")],
    meta={"weapon": "greatsword"},
)

H["brakka"] = dict(
    neck=(500, 680), chest=(500, 820), waist=(500, 990), hips=(500, 1100), shoulder=260,
    halo=None,
    hair=[],
    wings=[],
    weapon=dict(pivot=(760, 560), tip=(760, 520), parent="chest", rule=None),
    cloth=[("tail", "hips", (420, 1150), {"type": "polygon", "points": P((440, 1120), (330, 1150), (150, 1240), (40, 1380), (60, 1560), (200, 1720), (330, 1880), (390, 1860), (300, 1700), (200, 1560), (150, 1420), (260, 1290), (420, 1220)), "feather": 16},
            "tail;limit=10;g=0.6"),
           ("ribbon", "hips", (515, 1240), {"type": "polygon", "points": P((485, 1235), (550, 1235), (565, 1560), (495, 1560)), "feather": 10}, "ribbon;limit=14")],
    meta={"weapon": "fists"},
)

H["vesper"] = dict(
    neck=(560, 760), chest=(560, 880), waist=(580, 1040), hips=(600, 1140), shoulder=190,
    halo=None,
    hair=[("hair_back", "head", (420, 780), P((400, 740), (450, 760), (420, 900), (380, 1100), (230, 1110), (110, 1000), (150, 850), (300, 770)), "hair_long;limit=12;g=0.9"),
          ("hair_side_l", "head", (700, 830), P((680, 800), (760, 830), (900, 900), (1000, 1000), (990, 1110), (900, 1100), (800, 1000), (720, 950)), "hair_long;limit=12;g=0.9")],
    wings=[("wing_r", (310, 700), P((320, 650), (180, 600), (30, 570), (40, 640), (180, 760), (310, 760)))],
    weapon=dict(pivot=(840, 565), tip=(840, 565), parent="chest",
                rule={"type": "ellipse", "center": [840, 562], "radius": [112, 112], "feather": 6}),
    cloth=[("cape", "chest", (380, 820), {"type": "subtract", "rules": [
        {"type": "polygon", "points": P((380, 760), (300, 900), (200, 1150), (40, 1500), (50, 1700), (250, 1710), (330, 1550), (400, 1300))},
        {"type": "polygon", "points": P((400, 1250), (520, 1250), (520, 1990), (300, 1990))}], "feather": 26},
            "cape;limit=6;b=0.7"),
           ("tail", "hips", (360, 1150), {"type": "polygon", "points": P((380, 1050), (200, 1050), (30, 1150), (40, 1300), (200, 1360), (380, 1330)), "feather": 14}, "tail;limit=12")],
    meta={"weapon": "orb"},
)

H["imra"] = dict(
    neck=(590, 700), chest=(580, 800), waist=(580, 960), hips=(590, 1060), shoulder=160,
    halo=None,
    head_extra=P((330, 470), (500, 460), (500, 680), (330, 680)),
    hair=[],
    wings=[],
    weapon=dict(pivot=(190, 1160), tip=(500, 330), parent="hips",
                rule={"type": "polygon", "points": P((450, 280), (560, 300), (470, 520), (420, 700), (270, 1000), (240, 1200), (80, 1660), (20, 1650), (130, 1230), (230, 950), (380, 650))}),
    cloth=[("lantern", "chest", (905, 470), {"type": "polygon", "points": P((850, 470), (970, 470), (980, 820), (840, 820)), "feather": 10}, "accessory;limit=8;g=0.6"),
           ("tail", "hips", (700, 1000), {"type": "polygon", "points": P((690, 840), (860, 860), (1000, 950), (1000, 1140), (880, 1200), (760, 1180), (700, 1100)), "feather": 14}, "tail;limit=10"),
           ("skirt", "hips", (580, 1080), {"type": "subtract", "rules": [
               {"type": "polygon", "points": P((400, 1070), (800, 1070), (830, 1330), (700, 1400), (690, 1960), (500, 1960), (480, 1300), (380, 1300))},
               {"type": "polygon", "points": P((380, 1150), (480, 1160), (480, 1990), (300, 1990))}], "feather": 22},
            "cloth;limit=5;b=0.8")],
    meta={"weapon": "staff"},
)

H["kessa"] = dict(
    neck=(520, 850), chest=(520, 960), waist=(520, 1100), hips=(500, 1200), shoulder=180,
    halo=None,
    hair=[],
    wings=[],
    weapon=dict(pivot=(825, 1210), tip=(975, 1060), parent="hips",
                rule={"type": "polygon", "points": P((740, 1150), (900, 1000), (1015, 1000), (1015, 1420), (860, 1420), (740, 1310))}),
    cloth=[("ribbon", "chest", (470, 810), {"type": "polygon", "points": P((470, 770), (330, 780), (150, 760), (150, 840), (330, 860), (480, 870)), "feather": 12}, "ribbon;limit=12"),
           ("tail", "hips", (380, 1390), {"type": "polygon", "points": P((400, 1360), (200, 1380), (40, 1430), (30, 1650), (130, 1650), (130, 1470), (300, 1440), (400, 1430)), "feather": 14}, "tail;limit=14")],
    meta={"weapon": "sickle"},
)

H["noctaire"] = dict(
    neck=(495, 830), chest=(495, 940), waist=(500, 1070), hips=(500, 1160), shoulder=170,
    halo=((470, 575), P((370, 525), (570, 525), (570, 630), (370, 630))),
    hair=[("hair_back", "head", (390, 820), P((370, 780), (420, 800), (400, 1000), (360, 1250), (330, 1400), (160, 1400), (180, 1100), (280, 880)), "hair_long;limit=10;g=0.9"),
          ("hair_side_l", "head", (600, 820), P((570, 780), (640, 800), (760, 1000), (880, 1300), (850, 1430), (700, 1430), (640, 1100), (600, 950)), "hair_long;limit=10;g=0.9")],
    wings=[("wing_r", (390, 800), P((390, 760), (300, 520), (120, 560), (20, 900), (20, 1500), (60, 1720), (180, 1500), (260, 1150), (360, 900))),
           ("wing_l", (610, 800), P((610, 760), (690, 520), (900, 560), (1015, 900), (1015, 1800), (900, 1700), (820, 1400), (720, 1050), (640, 900)))],
    weapon=dict(pivot=(355, 1270), tip=(60, 1650), parent="hips",
                rule={"type": "polygon", "points": P((320, 1220), (390, 1230), (330, 1460), (480, 1880), (490, 1950), (330, 1950), (20, 1700), (40, 1500), (250, 1460))}),
    cloth=[("skirt", "hips", (500, 1180), {"type": "subtract", "rules": [
        {"type": "polygon", "points": P((380, 1250), (640, 1250), (760, 1550), (1000, 1990), (300, 1990), (340, 1600))},
        {"type": "polygon", "points": P((400, 1270), (600, 1270), (590, 1995), (420, 1995))}], "feather": 24},
            "cloth;limit=5;b=0.8")],
    meta={"weapon": "scythe"},
)

H["orrin"] = dict(
    neck=(490, 740), chest=(490, 870), waist=(490, 1030), hips=(490, 1120), shoulder=210,
    halo=None,
    hair=[("hair_side", "head", (420, 690), P((380, 660), (440, 660), (440, 780), (370, 780)), "hair;limit=8"),
          ("hair_side_l", "head", (580, 690), P((560, 650), (620, 660), (640, 790), (560, 790)), "hair;limit=8")],
    wings=[],
    weapon=dict(pivot=(720, 1000), tip=(820, 900), parent="chest",
                rule={"type": "polygon", "points": P((680, 760), (900, 740), (980, 900), (970, 1240), (900, 1370), (770, 1370), (680, 1150))}),
    cloth=[("cape", "chest", (330, 760), {"type": "subtract", "rules": [
        {"type": "polygon", "points": P((330, 700), (250, 740), (150, 1000), (20, 1500), (20, 1900), (180, 1900), (240, 1600), (300, 1300))},
        {"type": "polygon", "points": P((250, 1150), (330, 1150), (330, 1990), (240, 1990))}], "feather": 26},
            "cape;limit=6;b=0.7"),
           ("cape_l", "hips", (720, 1260), {"type": "polygon", "points": P((700, 1340), (900, 1360), (1015, 1880), (860, 1900), (760, 1700), (700, 1500)), "feather": 22}, "cape;limit=6;b=0.7")],
    meta={"weapon": "shield"},
)

H["sable"] = dict(
    neck=(520, 830), chest=(520, 960), waist=(520, 1090), hips=(520, 1180), shoulder=180,
    halo=((540, 600), P((390, 560), (690, 560), (690, 660), (390, 660))),
    hair=[("hair_long", "head", (700, 1160), P((690, 1150), (770, 1150), (880, 1350), (880, 1620), (780, 1620), (700, 1400)), "hair_long;limit=14;g=0.9")],
    wings=[("wing_r", (340, 900), P((350, 860), (200, 840), (60, 1000), (10, 1300), (40, 1720), (160, 1720), (260, 1400), (330, 1100))),
           ("wing_l", (690, 880), P((680, 840), (790, 820), (930, 900), (1015, 1200), (1015, 1680), (900, 1660), (800, 1350), (720, 1100)))],
    weapon=dict(pivot=(800, 950), tip=(790, 1240), parent="chest",
                rule={"type": "polygon", "points": P((740, 900), (840, 900), (840, 1260), (760, 1260))}),
    cloth=[("skirt", "hips", (560, 1190), {"type": "subtract", "rules": [
        {"type": "polygon", "points": P((580, 1150), (700, 1150), (850, 1500), (980, 1960), (600, 1960))},
        {"type": "polygon", "points": P((560, 1200), (640, 1200), (620, 1995), (540, 1995))}], "feather": 24},
            "cloth;limit=5;b=0.8")],
    meta={"weapon": "chain"},
)

H["lucen"] = dict(
    neck=(530, 820), chest=(530, 940), waist=(530, 1080), hips=(530, 1180), shoulder=180,
    halo=None,
    hair=[("hair_side", "head", (460, 760), P((420, 720), (470, 720), (470, 840), (420, 840)), "hair;limit=8"),
          ("hair_side_l", "head", (610, 760), P((590, 720), (650, 720), (650, 840), (590, 840)), "hair;limit=8")],
    wings=[("wing_r", (420, 820), P((430, 760), (300, 650), (150, 700), (20, 1100), (30, 1640), (160, 1560), (300, 1200), (400, 950))),
           ("wing_l", (630, 820), P((620, 760), (700, 690), (860, 760), (1015, 1100), (1015, 1600), (900, 1560), (770, 1200), (660, 950)))],
    weapon=dict(pivot=(325, 1230), tip=(440, 1915), parent="hips",
                rule={"type": "polygon", "points": P((250, 1160), (400, 1160), (400, 1300), (470, 1930), (420, 1935), (330, 1320), (250, 1300))}),
    cloth=[("coat_r", "hips", (330, 1200), {"type": "subtract", "rules": [
        {"type": "polygon", "points": P((330, 1150), (420, 1150), (380, 1500), (300, 1890), (60, 1890), (100, 1700), (250, 1450))},
        {"type": "polygon", "points": P((240, 1150), (420, 1150), (480, 1950), (400, 1950))}], "feather": 24},
            "cloth;limit=6;b=0.8"),
           ("coat_l", "hips", (680, 1200), {"type": "polygon", "points": P((640, 1150), (720, 1150), (800, 1450), (960, 1700), (960, 1890), (700, 1890), (660, 1500)), "feather": 24}, "cloth;limit=6;b=0.8")],
    meta={"weapon": "rapier"},
)

H["ashra"] = dict(
    neck=(450, 760), chest=(450, 880), waist=(460, 1020), hips=(470, 1100), shoulder=180,
    halo=None,
    head_extra=P((90, 470), (420, 430), (600, 420), (820, 700), (820, 740), (560, 760), (300, 700), (100, 620)),
    hair=[("hair_back", "head", (250, 760), P((220, 720), (300, 720), (280, 1000), (200, 1150), (110, 1150), (150, 950)), "hair_long;limit=10;g=0.9"),
          ("hair_side_l", "head", (640, 790), P((610, 760), (700, 760), (700, 1000), (620, 1100), (580, 950)), "hair_long;limit=10;g=0.9")],
    wings=[("wing_r", (260, 960), P((270, 900), (150, 900), (40, 980), (60, 1080), (200, 1060), (280, 1020))),
           ("wing_l", (670, 950), P((650, 880), (780, 880), (880, 980), (860, 1010), (720, 1010), (650, 1000)))],
    weapon=dict(pivot=(690, 1260), tip=(900, 1330), parent="hips",
                rule={"type": "polygon", "points": P((650, 1220), (880, 1250), (1000, 1300), (1000, 1420), (860, 1420), (650, 1310))}),
    cloth=[("skirt", "hips", (500, 1100), {"type": "subtract", "rules": [
        {"type": "polygon", "points": P((360, 1050), (650, 1050), (760, 1400), (860, 1880), (430, 1860), (380, 1500))},
        {"type": "polygon", "points": P((300, 1180), (420, 1180), (420, 1990), (250, 1990))}], "feather": 24},
            "cloth;limit=5;b=0.8"),
           ("cape", "chest", (230, 780), {"type": "polygon", "points": P((240, 740), (300, 760), (300, 1200), (230, 1340), (170, 1300), (180, 900)), "feather": 18}, "cape;limit=6;b=0.7")],
    meta={"weapon": "wand"},
)


def diff_bbox(base, vpath, rect=None):
    v = np.array(Image.open(vpath).convert("RGBA")).astype(int)
    d = np.abs(v - base).max(axis=2)
    if rect:
        m = np.zeros_like(d)
        x0, y0, x1, y1 = rect
        m[y0:y1, x0:x1] = 1
        d = d * m
    yy, xx = np.nonzero(d > 24)
    if not len(xx):
        return None
    return [int(xx.min()), int(yy.min()), int(xx.max()) + 1, int(yy.max()) + 1]


def build(hid, winks=()):
    s = H[hid]
    farm = json.load(open(os.path.join(os.path.dirname(FARM[hid]["canvas"]), hid + ".json")))
    fx, fy, fw, fh = farm["face_box"]
    fcx, fcy = fx + fw / 2.0, fy + fh * 0.55
    hdir = os.path.join(ROOT, hid)
    base = np.array(Image.open(os.path.join(hdir, hid + ".png")).convert("RGBA")).astype(int)
    nx, ny = s["neck"]
    bones = [
        {"name": "hips", "parent": "root", "pivot": list(s["hips"])},
        {"name": "torso", "parent": "hips", "pivot": list(s["waist"])},
        {"name": "chest", "parent": "torso", "pivot": list(s["chest"])},
        {"name": "neck", "parent": "chest", "pivot": [nx, ny]},
        {"name": "head", "parent": "neck", "pivot": [round(fcx - fw * 0.05), round(fy + fh * 1.02)]},
        {"name": "face", "parent": "head", "pivot": [round(fcx), round(fy + fh * 0.45)]},
        {"name": "hair_front", "parent": "head", "pivot": [round(fcx), round(fy - fh * 0.15)]},
    ]
    regions = [
        {"name": "face", "bone": "face", "rule": {"type": "ellipse", "center": [round(fcx), round(fcy)],
                                                  "radius": [round(fw * 0.52), round(fh * 0.44)], "feather": 14}},
        {"name": "hair_front", "rule": {"type": "ellipse", "center": [round(fcx), round(fy + fh * 0.02)],
                                        "radius": [round(fw * 0.62), round(fh * 0.3)], "feather": 12}},
    ]
    w = s.get("weapon")
    if w:
        b = {"name": "weapon", "parent": w.get("parent", "hips"), "pivot": list(w["pivot"]), "tip": list(w["tip"])}
        if w.get("rule"):
            b["spring"] = "weapon"
            r = dict(w["rule"])
            r.setdefault("feather", 8)
            regions.append({"name": "weapon", "rule": r})
        bones.append(b)
    if s.get("halo"):
        piv, poly = s["halo"]
        bones.append({"name": "halo", "parent": "head", "pivot": list(piv)})
        regions.append({"name": "halo", "rule": {"type": "polygon", "points": poly, "feather": 10}})
    for name, parent, piv, poly, spring in s.get("hair", []):
        bones.append({"name": name, "parent": parent, "pivot": list(piv), "spring": spring})
        regions.append({"name": name, "rule": {"type": "polygon", "points": poly, "feather": 16}})
    # head: an ellipse around the face box (hair top, ears, horns) plus any extra polygon (hat, horns)
    head_rule = {"type": "ellipse", "center": [round(fcx), round(fy + fh * 0.35)], "radius": [round(fw * 1.0), round(fh * 0.95)]}
    if s.get("head_extra"):
        head_rule = {"type": "union", "rules": [head_rule, {"type": "polygon", "points": s["head_extra"]}]}
    head_rule = dict(head_rule, feather=22)
    regions.append({"name": "head", "rule": head_rule})
    for name, piv, poly in s.get("wings", []):
        bones.append({"name": name, "parent": "chest", "pivot": list(piv)})
        regions.append({"name": name, "rule": {"type": "polygon", "points": poly, "feather": 16}})
    cx, cy = s["chest"]
    sw = s["shoulder"]
    wx, wy = s["waist"]
    regions.append({"name": "chest", "rule": {"type": "polygon", "points": P(
        (nx - sw * 0.55, ny - 10), (nx + sw * 0.55, ny - 10), (cx + sw, cy - 60), (cx + sw * 0.95, wy - 20),
        (wx + sw * 0.7, wy + 10), (wx - sw * 0.7, wy + 10), (cx - sw * 0.95, wy - 20), (cx - sw, cy - 60)), "feather": 40}})
    for name, parent, piv, rule, spring in s.get("cloth", []):
        b = {"name": name, "parent": parent, "pivot": list(piv)}
        if spring:
            b["spring"] = spring
        bones.append(b)
        regions.append({"name": name, "rule": rule})
    # overlays
    vdir = os.path.join(hdir, "variants")
    has = lambda v: os.path.exists(os.path.join(vdir, v + ".png"))
    base_eyes = "closed" if hid == "seraphiel" else "open"
    eyes_v = "eyes_open" if base_eyes == "closed" else "eyes_closed"
    pad = 8
    eb = diff_bbox(base, os.path.join(vdir, eyes_v + ".png")) if has(eyes_v) else None
    mb = diff_bbox(base, os.path.join(vdir, "mouth_open.png")) if has("mouth_open") else None
    if eb is None:
        eb = [fx + 4, int(fy + fh * 0.22), fx + fw - 4, int(fy + fh * 0.6)]
    if mb is None:
        mb = [int(fx + fw * 0.25), int(fy + fh * 0.62), int(fx + fw * 0.75), int(fy + fh * 0.95)]
    split = (eb[3] + mb[1]) // 2 if eb[3] > mb[1] else None
    er = [eb[0] - pad, eb[1] - pad, eb[2] + pad, (split if split else eb[3] + pad)]
    mr = [mb[0] - pad, (split if split else mb[1] - pad), mb[2] + pad, mb[3] + pad]
    to_rect = lambda r: [int(r[0]), int(r[1]), int(r[2] - r[0]), int(r[3] - r[1])]
    overlays = []
    ev = {}
    if has(eyes_v) and hid not in winks:
        ev["open" if base_eyes == "closed" else "closed"] = "variants/%s.png" % eyes_v
    if has("smile"):
        ev["smile"] = "variants/smile.png"
    if ev:
        overlays.append({"slot": "eyes", "bone": "face", "base": base_eyes, "default": base_eyes, "rect": to_rect(er), "z": 10, "variants": ev})
    mv = {}
    if has("mouth_open"):
        mv["open"] = "variants/mouth_open.png"
    if has("smile") and hid != "nuriel":
        mv["smile"] = "variants/smile.png"
    if mv:
        overlays.append({"slot": "mouth", "bone": "face", "base": "default", "default": "default", "rect": to_rect(mr), "z": 11, "variants": mv})
    pr = farm["warp_src_hints"]["portrait"]
    meta = dict(s.get("meta", {}))
    meta["fx_color"] = FX[FACTION[hid]]
    meta["art"] = "farm %s %s" % (FARM[hid]["run"].split("-")[0], FARM[hid]["label"].split()[0])
    src = {
        "_doc": "HaloRig warp rig source for %s (docs/dev/halorig.md section 8). Painted by the art farm (docs/dev/art-farm.md): "
                "run %s, seed %s. Coordinates are image pixels of %s.png (1024x2048, soles at the origin). Regions are listed in "
                "priority order: where masks overlap, the first one wins." % (hid, FARM[hid]["run"], FARM[hid]["label"].split()[0], hid),
        "image": hid + ".png", "origin": [512, 1990], "grid": [24, 48], "texel_scale": 1.0,
        "portrait": pr, "look_px": [14, 8], "meta": meta, "body_bone": "hips",
        "bones": bones, "regions": regions, "overlays": overlays,
    }
    with open(os.path.join(hdir, hid + ".warp_src.json"), "w") as f:
        f.write(dumps(src))
    return src


def dumps(src):
    """Readable JSON: one bone / region / overlay per line."""
    lines = ["{"]
    keys = list(src.keys())
    for i, k in enumerate(keys):
        comma = "," if i < len(keys) - 1 else ""
        v = src[k]
        if isinstance(v, list) and k in ("bones", "regions", "overlays"):
            lines.append('  "%s": [' % k)
            for j, e in enumerate(v):
                lines.append("    " + json.dumps(e, separators=(", ", ": ")) + ("," if j < len(v) - 1 else ""))
            lines.append("  ]" + comma)
        else:
            lines.append('  "%s": %s%s' % (k, json.dumps(v, separators=(", ", ": ")), comma))
    lines.append("}")
    return "\n".join(lines) + "\n"


if __name__ == "__main__":
    WINKS = ("cassiel", "brakka", "vesper")
    ids = sys.argv[1:] or list(H)
    for h in ids:
        build(h, WINKS)
        print("wrote", h)
