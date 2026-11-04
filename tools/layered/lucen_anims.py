"""Lucen's own animations for her layered rig (2026-11-04).

Writes assets/art/heroes/lucen/skins/live/anim/*.anim.json (the art's own set). Conventions as animkit.py. Her
rapier rides in her right fist (the weapon bone is a child of hand_r): `animkit.carried` keys it so it shows a
world tilt, 0 = point-down as painted, + = turned clockwise on screen (about +150 points it up and out to the
viewer's left, toward the foes).
Usage: tools/layered/lucen_anims.py"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
from animkit import A, Arms, carried, wings, S, CO, BO, QI, QO, CIO  # noqa: E402

OUT = os.path.join(ROOT, "assets", "art", "heroes", "lucen", "skins", "live", "anim")
ARMS = Arms({"r": ((400, 840), (335, 1060), (290, 1170)), "l": ((605, 840), (650, 1060), (665, 1220))})


def attack():
    """Riposte (0.9 s): en garde (the blade comes up across her), then a lunge: hips drop and drive, the sword arm
    shoots up and out with the point rising toward the foes, the free arm flies up behind her; then back."""
    a = A("attack_melee", 0.9, mix=0.06, mix_out=0.2)
    a.tr("hips", (0.0, 0, 0), (0.15, 6, 6, CO), (0.26, -16, 14, CO), (0.45, -12, 10, S), (0.75, 0, 1, S), (0.86, 0, 0, S))
    a.rot("torso", (0.0, 0), (0.15, 2, CO), (0.26, -6, CO), (0.5, -4, S), (0.8, 0, CIO))
    a.rot("chest", (0.0, 0), (0.15, 1.5, CO), (0.27, -3, CO), (0.55, -2, S), (0.8, 0, CIO))
    a.sc("chest", (0.0, 1, 1), (0.15, 1.0, 1.02, CO), (0.26, 1.01, 0.985, CO), (0.55, 1, 1, S))
    a.rot("head", (0.0, 0), (0.15, -3, CO), (0.27, 5, CO), (0.55, 4, S), (0.85, 0, S))
    # the lunge: her sword arm near full reach, up and out to the viewer's left
    ak = ARMS.keys(a, "r", [(0.0, None, S), (0.15, (360, 1010), CO), (0.26, (215, 770), CO), (0.5, (222, 778), S), (0.78, None, CIO)])
    hk = [(0.0, 0, S), (0.15, -10, CO), (0.26, 8, CO), (0.5, 6, S), (0.78, 0, S)]
    a.rot("hand_r", *hk)
    # a rising thrust: the point up toward the foes' line (a 730 px blade held level ran off the frame)
    carried(a, "weapon", ak, hk, [(0.0, 0, S), (0.15, 90, CO), (0.26, 172, CO), (0.5, 168, S), (0.78, 0, CIO)])
    ARMS.keys(a, "l", [(0.0, None, S), (0.15, (690, 1150), CO), (0.27, (760, 900), CO), (0.45, (755, 905), BO), (0.8, None, CIO)])
    a.rot("hand_l", (0.0, 0), (0.27, -25, CO), (0.5, -20, S), (0.8, 0, S))
    wings(a, [(0.0, 0, S), (0.14, -6, CO), (0.27, 14, CO), (0.4, 16, BO), (0.75, 6, S), (0.9, 0, S)])
    a.eyes((0.0, "open"), (0.12, "half"), (0.25, "open"))
    a.att("mouth", (0.0, "default"), (0.26, "small"), (0.5, "smile"), (0.7, "default"))
    a.ev(0.05, "charge").ev(0.24, "release").ev(0.27, "hit")
    a.ev(0.15, "jiggle:20,110").ev(0.27, "jiggle:-60,-200").ev(0.78, "jiggle:0,90")
    return a


def cast():
    """Twinfeather Flurry (2.3 s): the white and the black wing flare, she draws the blade up high and cuts four
    times, back and forth, faster each time, hair flying; a last cut and the point comes down."""
    a = A("cast", 2.3, mix=0.1, mix_out=0.3)
    a.tr("hips", (0.0, 0, 0), (0.35, 0, 12, CO), (0.75, 0, -6, CO), (1.7, 0, -5, S), (2.05, 0, 3, QI), (2.3, 0, 0, BO))
    a.rot("torso", (0.0, 0), (0.35, 2, CO), (0.75, -3, CO), (1.0, 3, S), (1.25, -3, S), (1.45, 3, S), (1.62, -2, S), (2.3, 0, S))
    a.rot("head", (0.0, 0), (0.35, 4, CO), (0.75, -8, CO), (1.7, -6, S), (2.3, 0, S))
    a.sc("chest", (0.0, 1, 1), (0.5, 1.012, 1.03, S), (0.75, 1.0, 1.0, CO), (2.3, 1, 1, S))
    cuts = [(0.75, (300, 900), 140), (1.0, (230, 1010), 230), (1.25, (310, 900), 120), (1.45, (225, 1000), 240), (1.62, (300, 910), 150)]
    tgt = [(0.0, None, S), (0.35, (360, 1060), CO)] + [(t, p, CO) for t, p, _ in cuts] + [(2.1, None, CIO)]
    ak = ARMS.keys(a, "r", tgt)
    hk = [(t, 0, e) for t, _, e in tgt]
    a.rot("hand_r", *hk)
    carried(a, "weapon", ak, hk, [(0.0, 0, S), (0.35, 60, CO)] + [(t, v, CO) for t, _, v in cuts] + [(2.1, 0, CIO)])
    ARMS.keys(a, "l", [(0.0, None, S), (0.35, (700, 1140), CO), (0.8, (770, 930), CO), (1.7, (765, 935), S), (2.2, None, CIO)])
    wings(a, [(0.0, 0, S), (0.35, -10, CO), (0.75, 26, CO), (0.9, 30, BO), (1.7, 24, S), (2.3, 0, CIO)], stagger=0.05)
    a.eyes((0.0, "open"), (0.3, "closed"), (0.7, "open"))
    a.att("mouth", (0.0, "default"), (0.75, "wide"), (1.0, "small"), (1.45, "wide"), (1.75, "smile"), (2.2, "default"))
    a.fx("glow", (0.0, 0), (0.7, 0.1, S), (0.8, 0.4, CO), (1.6, 0.3, S), (2.2, 0, S))
    a.ev(0.75, "release").ev(0.78, "vfx_burst").ev(0.8, "hit")
    for t, _, _ in cuts:
        a.ev(round(t + 0.01, 3), "jiggle:%d,-120" % (60 if t in (1.0, 1.45) else -60))
    a.ev(2.05, "jiggle:0,160")
    return a


def touch():
    """A poke (1.2 s): a flinch, then a smug look, her free hand to her hip, a bounce."""
    a = A("touch", 1.2, mix=0.05, mix_out=0.3)
    a.tr("hips", (0.0, 0, 0), (0.06, 4, -5, CO), (0.18, -6, 4, S), (0.32, -3, -2, S), (0.5, -1, 1, S), (1.2, 0, 0, S))
    a.rot("torso", (0.0, 0), (0.08, -3, CO), (0.3, 1.5, S), (1.2, 0, S))
    a.tr("chest", (0.0, 0, 0), (0.06, 0, -8, CO), (0.18, 0, 6, QI), (0.3, 0, -3, S), (0.42, 0, 2, S), (0.6, 0, 0, S))
    a.rot("head", (0.0, 0), (0.08, 4, CO), (0.25, -6, S), (0.7, -5, S), (1.2, 0, S))
    ARMS.keys(a, "l", [(0.0, None, S), (0.18, (635, 1150), QO), (0.35, (640, 1140), BO), (0.9, (642, 1142), S), (1.2, None, CIO)])
    a.rot("hand_l", (0.0, 0), (0.35, -14, BO), (0.9, -12, S), (1.2, 0, S))
    wings(a, [(0.0, 0, S), (0.12, -7, QO), (0.4, 6, BO), (0.85, 0, S)], stagger=0.03)
    a.eyes((0.0, "open"), (0.04, "closed"), (0.3, "half"), (1.15, "open"))
    a.att("mouth", (0.0, "default"), (0.1, "open"), (0.3, "smile"), (1.15, "default"))
    a.ev(0.06, "jiggle:0,-240").ev(0.22, "jiggle:30,150").ev(0.38, "jiggle:0,-100")
    return a


def victory():
    """The duelist's finish: a flick of the blade down and out to her side, the point toward the floor, her free
    hand on her hip, a smug tilt of the head, a bounce on every beat (0.5 s intro, 2.0 s loop)."""
    a = A("victory", 2.5, loop=True, loop_start=0.5, mix=0.15)
    tgt = [(0.0, None, S), (0.2, (300, 1080), CO), (0.35, (215, 1120), BO), (2.5, (215, 1120), S)]
    ak = ARMS.keys(a, "r", tgt)
    hk = [(0.0, 0, S), (0.2, -10, CO), (0.35, 6, BO), (2.5, 6, S)]
    a.rot("hand_r", *hk)
    carried(a, "weapon", ak, hk, [(0.0, 0, S), (0.2, -25, CO), (0.35, 38, BO), (2.5, 38, S)])
    ARMS.keys(a, "l", [(0.0, None, S), (0.35, (640, 1145), BO), (2.5, (640, 1145), S)])
    a.rot("hand_l", (0.0, 0), (0.35, -14, BO), (2.5, -14))
    a.rot("head", (0.0, 0), (0.4, 6, BO), (1.5, 4, S), (2.5, 6, S))
    wings(a, [(0.0, 0, S), (0.4, 14, BO), (1.5, 10, S), (2.5, 14, S)])
    beats = [(0.0, 0, 0)]
    for k in range(5):
        t = 0.5 + 0.5 * k
        beats += [(t, 0, 12 if k % 4 == 0 else 8, QI), (t + 0.25, 0, -3, QO)]
    a.tr("hips", *beats)
    for k in range(5):
        a.ev(round(0.5 + 0.5 * k + 0.02, 3), "jiggle:0,%d" % (120 if k % 4 == 0 else 85))
    a.ev(0.35, "jiggle:-30,140")
    a.eyes((0.0, "open"), (0.2, "half"), (0.45, "smile"))
    a.att("mouth", (0.0, "default"), (0.45, "smile"))
    return a


def idle_flourish():
    """Idle gesture: a lazy flourish, the point drawing circles in the air before her, then hanging down (2.6 s)."""
    a = A("idle_flourish", 2.6, mix=0.25, mix_out=0.35)
    tgt = [(0.0, None, S), (0.5, (330, 1090), S), (2.1, (330, 1090), S), (2.6, None, S)]
    ak = ARMS.keys(a, "r", tgt)
    circles = [(0.5 + 0.2 * i, (70 if i % 2 == 0 else 110), S) for i in range(8)]
    hk = [(0.0, 0, S), (0.5, 0, S), (2.1, 0, S), (2.6, 0, S)]
    a.rot("hand_r", *[(t, (8 if i % 2 else -8), S) for i, (t, _, _) in enumerate(circles)])
    a.rot("weapon", (0.0, 0, S), *circles, (2.6, 0, S))
    a.rot("head", (0.0, 0), (0.6, -3, S), (2.0, -2, S), (2.6, 0, S))
    a.tr("hips", (0.0, 0, 0), (0.6, -5, 2, S), (2.0, -5, 2, S), (2.6, 0, 0, S))
    a.eyes((0.0, "open"), (0.4, "half"), (2.2, "open"))
    a.att("mouth", (0.0, "default"), (0.6, "smile"), (2.2, "default"))
    a.ev(0.6, "jiggle:-20,90").ev(2.4, "jiggle:20,80")
    _ = ak, hk
    return a


def idle_hair():
    """Idle gesture: she flicks the black half of her hair back off her shoulder (2.2 s)."""
    a = A("idle_hair", 2.2, mix=0.25, mix_out=0.35)
    ARMS.keys(a, "l", [(0.0, None, S), (0.45, (612, 790), CO), (0.7, (650, 760), BO), (1.4, (648, 764), S), (2.0, None, CIO)], flip=True)
    a.rot("hand_l", (0.0, 0), (0.45, -30, CO), (0.7, -45, BO), (1.4, -40, S), (2.0, 0, S))
    a.rot("head", (0.0, 0), (0.5, -5, S), (0.72, 6, BO), (1.5, 4, S), (2.2, 0, S))
    a.rot("hair_b1", (0.0, 0), (0.6, -6, CO), (0.75, -14, BO), (1.6, -4, S), (2.2, 0, S))
    a.tr("hips", (0.0, 0, 0), (0.6, 4, 2, S), (1.6, 4, 2, S), (2.2, 0, 0, S))
    wings(a, [(0.0, 0, S), (0.7, 6, BO), (1.6, 3, S), (2.2, 0, S)])
    a.eyes((0.0, "open"), (0.55, "half"), (1.6, "open"))
    a.att("mouth", (0.0, "default"), (0.7, "smile"), (1.7, "default"))
    a.ev(0.7, "jiggle:30,130").ev(1.9, "jiggle:-20,90")
    return a


def idle_shades():
    """Idle gesture: she nudges her sunglasses down to look over them, a wink, then pushes them back up (2.4 s)."""
    a = A("idle_shades", 2.4, mix=0.25, mix_out=0.35)
    ARMS.keys(a, "l", [(0.0, None, S), (0.45, (560, 700), CO), (0.6, (545, 660), BO), (1.6, (548, 664), S), (2.1, None, CIO)], flip=True)
    a.rot("hand_l", (0.0, 0), (0.45, -30, CO), (0.6, -50, BO), (1.6, -46, S), (2.1, 0, S))
    a.tr("glasses", (0.0, 0, 0), (0.62, 0, 0, S), (0.8, 0, 16, CO), (1.4, 0, 16, S), (1.6, 0, 0, CO), (2.4, 0, 0, S))
    a.rot("head", (0.0, 0), (0.5, -3, S), (0.8, 4, BO), (1.5, 3, S), (2.3, 0, S))
    wings(a, [(0.0, 0, S), (0.6, 5, BO), (1.6, 3, S), (2.4, 0, S)])
    a.eyes((0.0, "open"), (0.85, "half"), (1.05, "smile"), (1.4, "open"))
    a.att("mouth", (0.0, "default"), (0.85, "smile"), (1.8, "default"))
    a.ev(0.6, "jiggle:20,120").ev(2.1, "jiggle:-20,90")
    return a


def idle():
    """Her display pose, held under everything (the base track's "idle"): hip cocked to her left, head tilted,
    her free hand on her hip, the rapier hanging a little out from her leg."""
    a = A("idle", 4.0, loop=True, mix=0.3, mix_out=0.15)
    a.tr("hips", (0.0, 9, 2), (4.0, 9, 2))
    a.rot("torso", (0.0, -1.5), (4.0, -1.5))
    a.rot("chest", (0.0, 1.0), (4.0, 1.0))
    a.rot("head", (0.0, -4.0), (4.0, -4.0))
    du, df = ARMS.pose("l", (640, 1145))
    a.rot("arm_l", (0.0, du), (4.0, du))
    a.rot("forearm_l", (0.0, df), (4.0, df))
    a.rot("hand_l", (0.0, -14), (4.0, -14))
    a.rot("weapon", (0.0, 6), (4.0, 6))
    return a


if __name__ == "__main__":
    for f in (idle, attack, cast, touch, victory, idle_flourish, idle_hair, idle_shades):
        print(f().save(OUT))
