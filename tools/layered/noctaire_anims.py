"""Noctaire's own animations for her layered rig (2026-11-04).

Writes assets/art/heroes/noctaire/skins/live/anim/*.anim.json (the art's own set). Conventions as animkit.py. Her
scythe is planted on its butt under her right hand with a grip: "carry" 0 = planted, leaning to her hand; 1 =
carried rigid in the hand, its own rotate key turning it about the grip.
Usage: tools/layered/noctaire_anims.py"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
from animkit import A, Arms, carried, wings, S, CO, BO, QI, QO, CIO  # noqa: E402

OUT = os.path.join(ROOT, "assets", "art", "heroes", "noctaire", "skins", "live", "anim")
ARMS = Arms({"r": ((405, 880), (355, 1050), (318, 905)), "l": ((608, 880), (665, 1075), (705, 1260))})


def drapes(a, keys):
    """keys [(t, swing deg, ease)]: both drapes swing out (+ = away from her), the hems further."""
    a.rot("drape_r", *[(t, v, e) for t, v, e in keys])
    a.rot("drape_l", *[(t + 0.02, -v, e) for t, v, e in keys])
    a.rot("drape_r2", *[(t + 0.05, v * 0.7, e) for t, v, e in keys])
    a.rot("drape_l2", *[(t + 0.07, -v * 0.7, e) for t, v, e in keys])


def idle():
    """Her display pose, held under everything: weight on her left hip, head tilted toward the scythe, her free
    hand resting on her hip."""
    a = A("idle", 4.0, loop=True, mix=0.3, mix_out=0.15)
    a.tr("hips", (0.0, 7, 2), (4.0, 7, 2))
    a.rot("torso", (0.0, -1.5), (4.0, -1.5))
    a.rot("head", (0.0, 5.0), (4.0, 5.0))
    du, df = ARMS.pose("l", (650, 1200))
    a.rot("arm_l", (0.0, du), (4.0, du))
    a.rot("forearm_l", (0.0, df), (4.0, df))
    a.rot("hand_l", (0.0, -16), (4.0, -16))
    return a


def attack():
    """Glitch Reap (0.95 s): she lifts the scythe off the floor, the blade swings round behind her, and she reaps
    down and across in one long arc, the drapes flaring; then plants it again."""
    a = A("attack_melee", 0.95, mix=0.06, mix_out=0.22)
    a.fx("carry", (0.0, 0.0), (0.1, 0.0), (0.15, 1.0, S), (0.8, 1.0), (0.88, 0.0, S))
    a.fx("trail", (0.0, 0.0), (0.26, 0.0), (0.3, 1.0, QO), (0.48, 0.0, S))
    a.tr("hips", (0.0, 0, 0), (0.16, 8, 6, CO), (0.3, -16, 14, CO), (0.5, -10, 8, S), (0.8, 0, 1, S), (0.9, 0, 0, S))
    a.rot("torso", (0.0, 0), (0.16, 5, CO), (0.3, -8, CO), (0.52, -5, S), (0.85, 0, CIO))
    a.rot("chest", (0.0, 0), (0.16, 3, CO), (0.31, -4, CO), (0.55, -2, S), (0.85, 0, CIO))
    a.rot("head", (0.0, 0), (0.16, -4, CO), (0.3, 6, CO), (0.55, 4, S), (0.88, 0, S))
    tgt = [(0.0, None, S), (0.16, (380, 880), CO), (0.3, (260, 1110), CO), (0.52, (265, 1100), S), (0.82, None, CIO)]
    ak = ARMS.keys(a, "r", tgt)
    hk = [(t, 0, e) for t, _, e in tgt]
    # the blade swings back over her head, then reaps down and across toward the foes
    carried(a, "weapon", ak, hk, [(0.0, 0, S), (0.16, 40, CO), (0.3, -70, CO), (0.52, -64, S), (0.82, 0, CIO)])
    ARMS.keys(a, "l", [(0.0, None, S), (0.16, (690, 1180), CO), (0.3, (790, 1020), CO), (0.55, (780, 1030), S), (0.88, None, CIO)])
    drapes(a, [(0.0, 0, S), (0.16, 3, CO), (0.32, 11, CO), (0.48, 12, BO), (0.82, 2, S), (0.95, 0, S)])
    wings(a, [(0.0, 0, S), (0.15, -6, CO), (0.3, 14, CO), (0.42, 16, BO), (0.78, 6, S), (0.95, 0, S)])
    a.eyes((0.0, "open"), (0.14, "half"), (0.3, "open"))
    a.att("mouth", (0.0, "default"), (0.3, "small"), (0.55, "smile"), (0.75, "default"))
    a.ev(0.05, "charge").ev(0.28, "release").ev(0.31, "hit")
    a.ev(0.16, "jiggle:20,-120").ev(0.31, "jiggle:-40,230").ev(0.82, "jiggle:0,90")
    return a


def cast():
    """Eclipse Harvest (2.4 s): she raises the scythe high overhead in both hands, wings flared, head back, eyes
    shut, the blade glowing; then sweeps it down in a full circle and plants it."""
    a = A("cast", 2.4, mix=0.1, mix_out=0.3)
    a.fx("carry", (0.0, 0.0), (0.3, 0.0), (0.38, 1.0, S), (2.0, 1.0), (2.15, 0.0, S))
    a.tr("hips", (0.0, 0, 0), (0.35, 0, 14, CO), (0.8, 0, -8, CO), (1.7, 0, -6, S), (2.1, 0, 3, QI), (2.4, 0, 0, BO))
    a.rot("torso", (0.0, 0), (0.35, -2, CO), (0.82, 2, CO), (2.4, 0, S))
    a.sc("chest", (0.0, 1, 1), (0.55, 1.012, 1.03, S), (0.82, 1.0, 1.0, CO), (2.4, 1, 1, S))
    a.rot("head", (0.0, 0), (0.35, 4, CO), (0.82, -10, CO), (1.0, -11, S), (1.7, -9, S), (2.4, 0, S))
    tgt = [(0.0, None, S), (0.35, (360, 1000), CO), (0.82, (440, 720), CO), (1.0, (438, 712), BO), (1.4, (300, 880), CO),
           (1.75, (300, 1100), CO), (2.15, None, CIO)]
    ak = ARMS.keys(a, "r", tgt, flip=True)
    hk = [(t, 0, e) for t, _, e in tgt]
    carried(a, "weapon", ak, hk, [(0.0, 0, S), (0.35, 20, CO), (0.82, 4, CO), (1.0, 6, BO), (1.4, -120, CO), (1.75, -240, CO), (2.15, -360, CIO)])
    ARMS.keys(a, "l", [(0.0, None, S), (0.35, (700, 1100), CO), (0.82, (580, 720), CO), (1.0, (578, 712), BO), (1.75, (760, 1000), S), (2.2, None, CIO)], flip=True)
    drapes(a, [(0.0, 0, S), (0.35, -3, CO), (0.8, 10, CO), (1.4, 16, S), (1.75, 14, BO), (2.4, 0, CIO)])
    wings(a, [(0.0, 0, S), (0.35, -10, CO), (0.8, 26, CO), (0.95, 30, BO), (1.75, 22, S), (2.35, 0, CIO)], stagger=0.05)
    a.eyes((0.0, "open"), (0.3, "closed"), (1.3, "open"))
    a.att("mouth", (0.0, "default"), (0.6, "small"), (0.82, "open"), (1.4, "wide"), (1.8, "smile"), (2.3, "default"))
    a.fx("glow", (0.0, 0), (0.75, 0.1, S), (0.86, 0.5, CO), (1.6, 0.35, S), (2.2, 0, S))
    a.ev(0.82, "release").ev(0.84, "vfx_burst").ev(1.45, "hit")
    a.ev(0.35, "jiggle:0,120").ev(0.82, "jiggle:0,-220").ev(1.45, "jiggle:-40,180").ev(2.1, "jiggle:0,160")
    return a


def touch():
    """A poke (1.2 s): a startled blink, then a slow, melancholy half-smile and her hand to her chest."""
    a = A("touch", 1.2, mix=0.05, mix_out=0.3)
    a.tr("hips", (0.0, 0, 0), (0.08, -3, -4, CO), (0.3, 2, 2, S), (1.2, 0, 0, S))
    a.tr("chest", (0.0, 0, 0), (0.06, 0, -7, CO), (0.18, 0, 5, QI), (0.32, 0, -2, S), (0.6, 0, 0, S))
    a.rot("head", (0.0, 0), (0.1, -4, CO), (0.35, 6, S), (0.9, 5, S), (1.2, 0, S))
    ARMS.keys(a, "l", [(0.0, None, S), (0.2, (650, 1020), QO), (0.4, (590, 930), BO), (0.9, (592, 934), S), (1.2, None, CIO)], flip=True)
    a.rot("hand_l", (0.0, 0), (0.4, 12, BO), (0.9, 10, S), (1.2, 0, S))
    wings(a, [(0.0, 0, S), (0.12, -7, QO), (0.4, 6, BO), (0.85, 0, S)], stagger=0.03)
    a.eyes((0.0, "open"), (0.04, "closed"), (0.3, "half"), (1.15, "open"))
    a.att("mouth", (0.0, "default"), (0.35, "smile"), (1.15, "default"))
    a.ev(0.06, "jiggle:0,-230").ev(0.22, "jiggle:-20,150").ev(0.4, "jiggle:0,-90")
    return a


def victory():
    """The reaper's rest: the scythe on her shoulder, the blade curving over her head, her free hand on her hip,
    wings up (0.5 s intro, 2.0 s loop)."""
    a = A("victory", 2.5, loop=True, loop_start=0.5, mix=0.15)
    a.fx("carry", (0.0, 0.0), (0.1, 0.0), (0.15, 1.0, S), (2.5, 1.0))
    tgt = [(0.0, None, S), (0.35, (400, 940), BO), (2.5, (400, 940), S)]
    ak = ARMS.keys(a, "r", tgt)
    hk = [(0.0, 0, S), (0.35, 0, BO), (2.5, 0, S)]
    carried(a, "weapon", ak, hk, [(0.0, 0, S), (0.35, 26, BO), (2.5, 26, S)])
    ARMS.keys(a, "l", [(0.0, None, S), (0.35, (650, 1200), BO), (2.5, (650, 1200), S)])
    a.rot("hand_l", (0.0, 0), (0.35, -16, BO), (2.5, -16))
    a.rot("head", (0.0, 0), (0.4, 6, BO), (1.5, 4, S), (2.5, 6, S))
    wings(a, [(0.0, 0, S), (0.4, 16, BO), (1.5, 12, S), (2.5, 16, S)])
    drapes(a, [(0.0, 0, S), (0.5, 4, S), (1.5, 1, S), (2.5, 4, S)])
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


def idle_hair():
    """Idle gesture: she sweeps her silver hair back off her shoulder (2.4 s)."""
    a = A("idle_hair", 2.4, mix=0.25, mix_out=0.35)
    ARMS.keys(a, "l", [(0.0, None, S), (0.5, (610, 780), CO), (0.9, (660, 760), S), (1.6, (700, 900), S), (2.2, None, CIO)], flip=True)
    a.rot("hand_l", (0.0, 0), (0.5, -30, CO), (1.6, -10, S), (2.2, 0, S))
    a.rot("head", (0.0, 0), (0.6, -5, S), (1.4, -6, S), (2.2, 0, S))
    a.rot("hair_l1", (0.0, 0), (0.9, -10, S), (1.6, 4, S), (2.4, 0, S))
    a.tr("hips", (0.0, 0, 0), (0.7, 5, 2, S), (1.6, 5, 2, S), (2.4, 0, 0, S))
    a.eyes((0.0, "open"), (0.5, "half"), (1.8, "open"))
    a.att("mouth", (0.0, "default"), (0.7, "smile"), (1.9, "default"))
    a.ev(0.6, "jiggle:20,110").ev(2.0, "jiggle:-20,80")
    return a


def idle_glitch():
    """Idle gesture: she glitches: a few hard, stepped jerks of her head and wings, like a dropped frame (1.6 s)."""
    a = A("idle_glitch", 1.6, mix=0.1, mix_out=0.3)
    st = "step"
    a.rot("head", (0.0, 0, st), (0.3, 6, st), (0.38, -4, st), (0.44, 3, st), (0.52, 0, st), (1.0, 0, st), (1.06, -5, st), (1.14, 0, S), (1.6, 0, S))
    a.tr("chest", (0.0, 0, 0, st), (0.3, 6, 0, st), (0.38, -5, 0, st), (0.46, 0, 0, st), (1.6, 0, 0, S))
    wings(a, [(0.0, 0, st), (0.3, 10, st), (0.38, -6, st), (0.46, 0, st), (1.6, 0, S)], stagger=0.0)
    a.eyes((0.0, "open"), (0.3, "closed"), (0.38, "open"), (1.0, "half"), (1.1, "open"))
    a.ev(0.31, "jiggle:60,-120").ev(0.39, "jiggle:-60,100")
    return a


def idle_wings():
    """Idle gesture: a slow, wide spread of the wings with a shake, the drapes stirring (2.4 s)."""
    a = A("idle_wings", 2.4, mix=0.25, mix_out=0.4)
    a.tr("chest", (0.0, 0, 0), (0.7, 0, -6, S), (1.4, 0, -5, S), (2.0, 0, 2, QI), (2.4, 0, 0, S))
    shake = [(0.0, 0, S), (0.75, 20, CO)] + [(0.85 + 0.09 * i, 20 + (5 if i % 2 == 0 else -5) * (0.8 ** i), S) for i in range(7)]
    wings(a, shake + [(1.6, 18, S), (2.35, 0, CIO)], stagger=0.06)
    drapes(a, [(0.0, 0, S), (0.8, 4, S), (1.6, 2, S), (2.4, 0, S)])
    a.eyes((0.0, "open"), (0.45, "half"), (0.7, "closed"), (1.75, "half"), (1.95, "open"))
    a.ev(1.9, "jiggle:0,160").ev(0.75, "jiggle:0,-110")
    return a


if __name__ == "__main__":
    for f in (idle, attack, cast, touch, victory, idle_hair, idle_glitch, idle_wings):
        print(f().save(OUT))
