"""Mordessa's own animations for her layered rig (2026-11-04).

Writes assets/art/heroes/mordessa/skins/live/anim/*.anim.json (the art's own set). Conventions as animkit.py. Her
greatsword is planted under her right hand with a grip (like Uriela's lance): "carry" 0 = planted, leaning to
her hand; 1 = carried rigid in the hand, its own rotate key turning it about the grip.
Usage: tools/layered/mordessa_anims.py"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
from animkit import A, Arms, carried, wings, S, CO, BO, QI, QO, CIO  # noqa: E402

OUT = os.path.join(ROOT, "assets", "art", "heroes", "mordessa", "skins", "live", "anim")
ARMS = Arms({"r": ((372, 975), (324, 1122), (265, 1228)), "l": ((640, 975), (700, 1132), (724, 1285))})


def tail(a, keys, lag=0.05):
    for k in range(3):
        a.rot("tail%d" % (k + 1), *[(t + lag * k, v * (1.0 + 0.4 * k), e) for t, v, e in keys])


def coat(a, keys):
    """keys [(t, swing deg, ease)]: both halves of her coat swing out (+ = away from her), the hems further."""
    a.rot("coat_r", *[(t, v, e) for t, v, e in keys])
    a.rot("coat_l", *[(t + 0.02, -v, e) for t, v, e in keys])
    a.rot("coat_r2", *[(t + 0.05, v * 0.7, e) for t, v, e in keys])
    a.rot("coat_l2", *[(t + 0.07, -v * 0.7, e) for t, v, e in keys])


def idle():
    """Her display pose, held under everything: weight on her right hip, chin up, her free hand on her hip."""
    a = A("idle", 4.0, loop=True, mix=0.3, mix_out=0.15)
    a.tr("hips", (0.0, -7, 2), (4.0, -7, 2))
    a.rot("torso", (0.0, 1.5), (4.0, 1.5))
    a.rot("head", (0.0, -3.0), (4.0, -3.0))
    du, df = ARMS.pose("l", (665, 1205))
    a.rot("arm_l", (0.0, du), (4.0, du))
    a.rot("forearm_l", (0.0, df), (4.0, df))
    a.rot("hand_l", (0.0, -18), (4.0, -18))
    tail(a, [(0.0, 6, S), (4.0, 6, S)], lag=0.0)
    return a


def attack():
    """Ember Cleave (1.0 s): she wrenches the greatsword up from the floor onto her shoulder, steps in and brings
    it down in one heavy diagonal cut, the coat flaring; then sets the point back down."""
    a = A("attack_melee", 1.0, mix=0.06, mix_out=0.22)
    a.fx("carry", (0.0, 0.0), (0.12, 0.0), (0.17, 1.0, S), (0.84, 1.0), (0.92, 0.0, S))
    a.fx("trail", (0.0, 0.0), (0.3, 0.0), (0.34, 1.0, QO), (0.5, 0.0, S))
    a.tr("hips", (0.0, 0, 0), (0.18, 6, 8, CO), (0.32, -14, 16, CO), (0.5, -10, 10, S), (0.82, 0, 1, S), (0.95, 0, 0, S))
    a.rot("torso", (0.0, 0), (0.18, 5, CO), (0.33, -8, CO), (0.55, -5, S), (0.88, 0, CIO))
    a.rot("chest", (0.0, 0), (0.18, 3, CO), (0.34, -4, CO), (0.6, -2, S), (0.88, 0, CIO))
    a.rot("head", (0.0, 0), (0.18, -4, CO), (0.33, 6, CO), (0.6, 4, S), (0.9, 0, S))
    tgt = [(0.0, None, S), (0.18, (400, 930), CO), (0.33, (300, 1170), CO), (0.55, (305, 1160), S), (0.84, None, CIO)]
    ak = ARMS.keys(a, "r", tgt)
    hk = [(t, 0, e) for t, _, e in tgt]
    # up onto her shoulder (point behind her), then down and across: the blade ends pointing at the foes, low
    carried(a, "weapon", ak, hk, [(0.0, 0, S), (0.18, 150, CO), (0.33, 60, CO), (0.55, 64, S), (0.84, 0, CIO)])
    ARMS.keys(a, "l", [(0.0, None, S), (0.18, (690, 1150), CO), (0.33, (780, 1010), CO), (0.6, (770, 1020), S), (0.9, None, CIO)])
    coat(a, [(0.0, 0, S), (0.18, 3, CO), (0.34, 9, CO), (0.5, 10, BO), (0.85, 2, S), (1.0, 0, S)])
    wings(a, [(0.0, 0, S), (0.16, -6, CO), (0.33, 14, CO), (0.45, 16, BO), (0.8, 6, S), (1.0, 0, S)])
    tail(a, [(0.0, 0, S), (0.18, -10, CO), (0.34, 18, CO), (0.6, 6, S), (1.0, 0, S)])
    a.eyes((0.0, "open"), (0.15, "half"), (0.32, "open"))
    a.att("mouth", (0.0, "default"), (0.32, "wide"), (0.55, "smile"), (0.75, "default"))
    a.ev(0.05, "charge").ev(0.31, "release").ev(0.34, "hit")
    a.ev(0.18, "jiggle:20,-120").ev(0.34, "jiggle:-40,240").ev(0.84, "jiggle:0,90")
    return a


def cast():
    """Ninth Furnace (2.4 s): she hoists the greatsword high in both hands over her head, wings and coat flaring,
    head back, a laugh; the blade glows, then comes down and is planted again."""
    a = A("cast", 2.4, mix=0.1, mix_out=0.3)
    a.fx("carry", (0.0, 0.0), (0.3, 0.0), (0.38, 1.0, S), (2.0, 1.0), (2.15, 0.0, S))
    a.tr("hips", (0.0, 0, 0), (0.35, 0, 14, CO), (0.8, 0, -8, CO), (1.7, 0, -6, S), (2.1, 0, 3, QI), (2.4, 0, 0, BO))
    a.rot("torso", (0.0, 0), (0.35, -2, CO), (0.82, 2, CO), (2.4, 0, S))
    a.sc("chest", (0.0, 1, 1), (0.55, 1.012, 1.03, S), (0.82, 1.0, 1.0, CO), (2.4, 1, 1, S))
    a.rot("head", (0.0, 0), (0.35, 4, CO), (0.82, -10, CO), (1.0, -11, S), (1.7, -9, S), (2.4, 0, S))
    tgt = [(0.0, None, S), (0.35, (360, 1060), CO), (0.82, (440, 820), CO), (1.0, (438, 812), BO), (1.75, (440, 820), S), (2.15, None, CIO)]
    ak = ARMS.keys(a, "r", tgt, flip=True)
    hk = [(t, 0, e) for t, _, e in tgt]
    carried(a, "weapon", ak, hk, [(0.0, 0, S), (0.35, 60, CO), (0.82, 178, CO), (1.0, 180, BO), (1.75, 178, S), (2.15, 0, CIO)])
    ARMS.keys(a, "l", [(0.0, None, S), (0.35, (700, 1060), CO), (0.82, (580, 820), CO), (1.0, (578, 812), BO), (1.75, (580, 820), S), (2.2, None, CIO)], flip=True)
    coat(a, [(0.0, 0, S), (0.35, -3, CO), (0.8, 12, CO), (0.95, 14, BO), (1.75, 10, S), (2.4, 0, CIO)])
    wings(a, [(0.0, 0, S), (0.35, -10, CO), (0.8, 26, CO), (0.95, 30, BO), (1.75, 22, S), (2.35, 0, CIO)], stagger=0.05)
    tail(a, [(0.0, 0, S), (0.35, -12, CO), (0.82, 20, CO), (1.75, 12, S), (2.4, 0, S)])
    a.eyes((0.0, "open"), (0.3, "closed"), (0.8, "open"))
    a.att("mouth", (0.0, "default"), (0.6, "small"), (0.82, "wide"), (1.6, "open"), (1.8, "smile"), (2.3, "default"))
    a.fx("glow", (0.0, 0), (0.75, 0.1, S), (0.86, 0.5, CO), (1.6, 0.35, S), (2.2, 0, S))
    a.ev(0.82, "release").ev(0.84, "vfx_burst").ev(0.9, "hit")
    a.ev(0.35, "jiggle:0,120").ev(0.82, "jiggle:0,-220").ev(1.2, "jiggle:20,-120").ev(2.1, "jiggle:0,160")
    return a


def touch():
    """A poke (1.2 s): she barely flinches, looks down her nose, a slow smirk and a fan of the wings."""
    a = A("touch", 1.2, mix=0.05, mix_out=0.3)
    a.tr("hips", (0.0, 0, 0), (0.08, 3, -4, CO), (0.3, -2, 2, S), (1.2, 0, 0, S))
    a.tr("chest", (0.0, 0, 0), (0.06, 0, -6, CO), (0.18, 0, 4, QI), (0.32, 0, -2, S), (0.6, 0, 0, S))
    a.rot("head", (0.0, 0), (0.1, 3, CO), (0.35, -7, S), (0.9, -6, S), (1.2, 0, S))
    ARMS.keys(a, "l", [(0.0, None, S), (0.2, (680, 1180), QO), (0.4, (668, 1200), BO), (0.9, (668, 1200), S), (1.2, None, CIO)])
    wings(a, [(0.0, 0, S), (0.15, -6, QO), (0.45, 12, BO), (0.9, 0, S)], stagger=0.04)
    tail(a, [(0.0, 0, S), (0.1, -14, CO), (0.5, 10, S), (1.2, 0, S)])
    a.eyes((0.0, "open"), (0.05, "half"), (0.35, "smile"), (1.15, "open"))
    a.att("mouth", (0.0, "default"), (0.35, "smile"), (1.15, "default"))
    a.ev(0.06, "jiggle:0,-220").ev(0.22, "jiggle:20,140").ev(0.4, "jiggle:0,-90")
    return a


def victory():
    """The empress: she lifts the greatsword onto her shoulder and stands with her hand on her hip, wings up, a
    slow beat of her coat (0.5 s intro, 2.0 s loop)."""
    a = A("victory", 2.5, loop=True, loop_start=0.5, mix=0.15)
    a.fx("carry", (0.0, 0.0), (0.1, 0.0), (0.15, 1.0, S), (2.5, 1.0))
    tgt = [(0.0, None, S), (0.35, (395, 960), BO), (2.5, (395, 960), S)]
    ak = ARMS.keys(a, "r", tgt)
    hk = [(0.0, 0, S), (0.35, 0, BO), (2.5, 0, S)]
    carried(a, "weapon", ak, hk, [(0.0, 0, S), (0.35, 160, BO), (2.5, 160, S)])
    ARMS.keys(a, "l", [(0.0, None, S), (0.35, (665, 1205), BO), (2.5, (665, 1205), S)])
    a.rot("hand_l", (0.0, 0), (0.35, -18, BO), (2.5, -18))
    a.rot("head", (0.0, 0), (0.4, -6, BO), (1.5, -4, S), (2.5, -6, S))
    wings(a, [(0.0, 0, S), (0.4, 16, BO), (1.5, 12, S), (2.5, 16, S)])
    coat(a, [(0.0, 0, S), (0.5, 4, S), (1.5, 1, S), (2.5, 4, S)])
    beats = [(0.0, 0, 0)]
    for k in range(5):
        t = 0.5 + 0.5 * k
        beats += [(t, 0, 10 if k % 4 == 0 else 6, QI), (t + 0.25, 0, -2, QO)]
    a.tr("hips", *beats)
    for k in range(5):
        a.ev(round(0.5 + 0.5 * k + 0.02, 3), "jiggle:0,%d" % (110 if k % 4 == 0 else 80))
    a.eyes((0.0, "open"), (0.2, "half"), (0.45, "smile"))
    a.att("mouth", (0.0, "default"), (0.45, "smile"))
    return a


def idle_preen():
    """Idle gesture: she runs her free hand back through her hair (2.4 s)."""
    a = A("idle_preen", 2.4, mix=0.25, mix_out=0.35)
    ARMS.keys(a, "l", [(0.0, None, S), (0.5, (600, 800), CO), (0.9, (650, 770), S), (1.6, (690, 900), S), (2.2, None, CIO)], flip=True)
    a.rot("hand_l", (0.0, 0), (0.5, -30, CO), (1.6, -10, S), (2.2, 0, S))
    a.rot("head", (0.0, 0), (0.6, 5, S), (1.4, 6, S), (2.2, 0, S))
    a.rot("hair_l1", (0.0, 0), (0.9, -8, S), (1.6, 4, S), (2.4, 0, S))
    a.tr("hips", (0.0, 0, 0), (0.7, 5, 2, S), (1.6, 5, 2, S), (2.4, 0, 0, S))
    a.eyes((0.0, "open"), (0.5, "half"), (1.8, "open"))
    a.att("mouth", (0.0, "default"), (0.7, "smile"), (1.9, "default"))
    a.ev(0.6, "jiggle:20,110").ev(2.0, "jiggle:-20,80")
    return a


def idle_lean():
    """Idle gesture: she leans her weight onto the planted sword, head tilted, tail curling (2.8 s)."""
    a = A("idle_lean", 2.8, mix=0.3, mix_out=0.45)
    a.tr("hips", (0.0, 0, 0), (0.7, -12, 4, S), (2.1, -12, 4, S), (2.8, 0, 0, S))
    a.rot("torso", (0.0, 0), (0.7, 3, S), (2.1, 3, S), (2.8, 0, S))
    a.rot("head", (0.0, 0), (0.7, 6, S), (2.1, 5, S), (2.8, 0, S))
    tail(a, [(0.0, 0, S), (0.8, 16, S), (1.6, 8, S), (2.2, 16, S), (2.8, 0, S)])
    a.eyes((0.0, "open"), (0.6, "half"), (2.3, "open"))
    a.att("mouth", (0.0, "default"), (0.7, "smile"), (2.3, "default"))
    a.ev(0.7, "jiggle:-40,130").ev(2.7, "jiggle:30,100")
    return a


def idle_wings():
    """Idle gesture: a slow, wide spread of the wings with a shake, the coat stirring (2.4 s)."""
    a = A("idle_wings", 2.4, mix=0.25, mix_out=0.4)
    a.tr("chest", (0.0, 0, 0), (0.7, 0, -6, S), (1.4, 0, -5, S), (2.0, 0, 2, QI), (2.4, 0, 0, S))
    shake = [(0.0, 0, S), (0.75, 20, CO)] + [(0.85 + 0.09 * i, 20 + (5 if i % 2 == 0 else -5) * (0.8 ** i), S) for i in range(7)]
    wings(a, shake + [(1.6, 18, S), (2.35, 0, CIO)], stagger=0.06)
    coat(a, [(0.0, 0, S), (0.8, 4, S), (1.6, 2, S), (2.4, 0, S)])
    a.eyes((0.0, "open"), (0.45, "half"), (0.7, "closed"), (1.75, "half"), (1.95, "open"))
    a.ev(1.9, "jiggle:0,160").ev(0.75, "jiggle:0,-110")
    return a


if __name__ == "__main__":
    for f in (idle, attack, cast, touch, victory, idle_preen, idle_lean, idle_wings):
        print(f().save(OUT))
