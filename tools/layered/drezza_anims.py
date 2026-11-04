"""Drezza's own animations for her layered rig (2026-11-04).

Writes assets/art/heroes/drezza/skins/live/anim/*.anim.json (the art's own set). Conventions as animkit.py. Her
red record rides in her right hand (the weapon bone is a child of hand_r); its rotate keys spin it.
Usage: tools/layered/drezza_anims.py"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
from animkit import A, Arms, wings, S, CO, BO, QI, QO, CIO  # noqa: E402

OUT = os.path.join(ROOT, "assets", "art", "heroes", "drezza", "skins", "live", "anim")
ARMS = Arms({"r": ((385, 960), (320, 1112), (268, 1229)), "l": ((632, 960), (703, 1123), (762, 1241))})


def tail(a, keys, lag=0.05):
    for k in range(3):
        a.rot("tail%d" % (k + 1), *[(t + lag * k, v * (1.0 + 0.4 * k), e) for t, v, e in keys])


def coat(a, keys):
    a.rot("coat_r", *[(t, v, e) for t, v, e in keys])
    a.rot("coat_l", *[(t + 0.02, -v, e) for t, v, e in keys])
    a.rot("coat_r2", *[(t + 0.05, v * 0.7, e) for t, v, e in keys])
    a.rot("coat_l2", *[(t + 0.07, -v * 0.7, e) for t, v, e in keys])


def spin(a, t0, t1, turns, ease=S):
    """The record spins `turns` times between t0 and t1 (a key every quarter turn)."""
    n = max(int(turns * 4), 1)
    a.rot("weapon", (t0, 0, "linear"), *[(t0 + (t1 - t0) * (i + 1) / n, -90.0 * (i + 1), "linear") for i in range(n)])


def idle():
    """Her display pose, held under everything: weight on her right hip, head bobbed to one side, her free hand
    resting on the deck at her hip."""
    a = A("idle", 4.0, loop=True, mix=0.3, mix_out=0.15)
    a.tr("hips", (0.0, -7, 2), (4.0, -7, 2))
    a.rot("torso", (0.0, 1.5), (4.0, 1.5))
    a.rot("head", (0.0, -5.0), (4.0, -5.0))
    du, df = ARMS.pose("l", (690, 1215))
    a.rot("arm_l", (0.0, du), (4.0, du))
    a.rot("forearm_l", (0.0, df), (4.0, df))
    a.rot("hand_l", (0.0, -12), (4.0, -12))
    tail(a, [(0.0, 6, S), (4.0, 6, S)], lag=0.0)
    return a


def attack():
    """Spin Toss (0.9 s): she winds the record back, spinning it, and flicks it out toward the foes like a disc;
    the wave flies on (the battle's shot) and the record snaps back to her hand."""
    a = A("attack_ranged", 0.9, mix=0.06, mix_out=0.2)
    a.tr("hips", (0.0, 0, 0), (0.15, 6, 6, CO), (0.28, -10, -6, CO), (0.5, -6, -3, S), (0.8, 0, 1, S), (0.9, 0, 0, S))
    a.rot("torso", (0.0, 0), (0.15, 4, CO), (0.28, -6, CO), (0.55, -3, S), (0.85, 0, CIO))
    a.rot("head", (0.0, 0), (0.15, 4, CO), (0.28, -6, CO), (0.55, -4, S), (0.88, 0, S))
    ARMS.keys(a, "r", [(0.0, None, S), (0.15, (380, 1060), CO), (0.28, (150, 1000), CO), (0.48, (160, 1010), S), (0.8, None, CIO)])
    a.rot("hand_r", (0.0, 0), (0.15, 20, CO), (0.28, -30, CO), (0.5, -24, S), (0.8, 0, S))
    spin(a, 0.0, 0.8, 3)
    ARMS.keys(a, "l", [(0.0, None, S), (0.15, (700, 1180), CO), (0.28, (800, 1050), CO), (0.55, (790, 1060), S), (0.88, None, CIO)])
    coat(a, [(0.0, 0, S), (0.16, 3, CO), (0.3, 8, CO), (0.48, 9, BO), (0.82, 2, S), (0.9, 0, S)])
    wings(a, [(0.0, 0, S), (0.15, -6, CO), (0.28, 12, CO), (0.42, 14, BO), (0.78, 5, S), (0.9, 0, S)])
    tail(a, [(0.0, 0, S), (0.15, -10, CO), (0.3, 16, CO), (0.6, 6, S), (0.9, 0, S)])
    a.eyes((0.0, "open"), (0.12, "half"), (0.28, "open"))
    a.att("mouth", (0.0, "default"), (0.28, "wide"), (0.5, "smile"), (0.72, "default"))
    a.ev(0.05, "charge").ev(0.27, "release").ev(0.28, "vfx_bolt").ev(0.36, "hit")
    a.ev(0.15, "jiggle:20,-110").ev(0.28, "jiggle:-40,200").ev(0.8, "jiggle:0,90")
    return a


def cast(name="cast"):
    """Bass Drop (2.4 s): she presses a headphone cup to her ear and raises the record high, spinning it, wings
    flaring on the build; then the drop: she slams down into a crouch, the coat and wings blasting out. Saved as
    support_cast too: a support's cast plays that one (HeroSprite.play_cast)."""
    a = A(name, 2.4, mix=0.1, mix_out=0.3)
    beat = 0.25
    a.tr("hips", (0.0, 0, 0), *[(0.3 + beat * k, 0, (4 if k % 2 == 0 else 0), S) for k in range(4)],
         (1.3, 0, -6, CO), (1.45, 0, 26, QI), (1.6, 0, 20, S), (2.1, 0, 3, S), (2.4, 0, 0, BO))
    a.rot("head", (0.0, 0), *[(0.3 + beat * k, (4 if k % 2 == 0 else -4), S) for k in range(4)], (1.3, -8, CO), (1.45, 6, QI), (2.4, 0, S))
    ARMS.keys(a, "l", [(0.0, None, S), (0.3, (580, 880), CO), (1.3, (585, 885), S), (1.45, (760, 1050), QI), (2.2, None, CIO)], flip=True)
    ARMS.keys(a, "r", [(0.0, None, S), (0.3, (330, 860), CO), (1.3, (340, 800), CO), (1.45, (200, 1150), QI), (1.9, (210, 1140), S), (2.2, None, CIO)])
    spin(a, 0.3, 1.45, 5)
    coat(a, [(0.0, 0, S), (1.3, -3, CO), (1.48, 16, QI), (1.7, 14, BO), (2.4, 0, CIO)])
    wings(a, [(0.0, 0, S), (0.3, 6, S), (1.3, 20, CO), (1.48, 32, QI), (1.75, 24, S), (2.35, 0, CIO)], stagger=0.05)
    tail(a, [(0.0, 0, S), (1.3, -14, CO), (1.48, 22, QI), (2.0, 8, S), (2.4, 0, S)])
    a.eyes((0.0, "open"), (0.3, "closed"), (1.42, "open"))
    a.att("mouth", (0.0, "default"), (0.3, "small"), (1.3, "default"), (1.45, "wide"), (1.9, "smile"), (2.3, "default"))
    a.fx("glow", (0.0, 0), (0.3, 0.2, S), (1.3, 0.45, S), (1.48, 0.6, CO), (2.2, 0, S))
    a.ev(1.44, "release").ev(1.46, "vfx_burst").ev(1.5, "hit")
    for k in range(4):
        a.ev(round(0.3 + beat * k, 3), "jiggle:%d,90" % (-30 if k % 2 == 0 else 30))
    a.ev(1.46, "jiggle:0,-280").ev(1.7, "jiggle:0,160")
    return a


def touch():
    """A poke (1.2 s): a laugh, a bounce on her heels and a wink, her tail flicking."""
    a = A("touch", 1.2, mix=0.05, mix_out=0.3)
    a.tr("hips", (0.0, 0, 0), (0.06, 0, -16, CO), (0.2, 0, 6, QI), (0.32, 0, -3, S), (0.5, 0, 1, S), (1.2, 0, 0, S))
    a.rot("head", (0.0, 0), (0.08, 4, CO), (0.3, -6, S), (0.8, -5, S), (1.2, 0, S))
    ARMS.keys(a, "l", [(0.0, None, S), (0.18, (640, 1000), QO), (0.35, (600, 920), BO), (0.9, (602, 925), S), (1.2, None, CIO)], flip=True)
    tail(a, [(0.0, 0, S), (0.06, -20, CO), (0.4, 14, S), (0.8, -6, S), (1.2, 0, S)], lag=0.03)
    wings(a, [(0.0, 0, S), (0.12, -7, QO), (0.4, 8, BO), (0.85, 0, S)], stagger=0.03)
    a.eyes((0.0, "open"), (0.04, "closed"), (0.3, "smile"), (1.15, "open"))
    a.att("mouth", (0.0, "default"), (0.1, "wide"), (0.35, "smile"), (1.15, "default"))
    a.ev(0.06, "jiggle:0,-260").ev(0.22, "jiggle:20,170").ev(0.38, "jiggle:0,-100")
    return a


def victory():
    """The headliner: the record raised high and spinning, her free hand on her headphones, bouncing on every beat
    (0.5 s intro, 2.0 s loop)."""
    a = A("victory", 2.5, loop=True, loop_start=0.5, mix=0.15)
    ARMS.keys(a, "r", [(0.0, None, S), (0.35, (330, 840), BO), (2.5, (330, 840), S)])
    ARMS.keys(a, "l", [(0.0, None, S), (0.35, (580, 885), BO), (2.5, (580, 885), S)], flip=True)
    spin(a, 0.3, 2.5, 8)
    a.rot("head", (0.0, 0), (0.4, -5, BO), (1.5, -3, S), (2.5, -5, S))
    wings(a, [(0.0, 0, S), (0.4, 14, BO), (1.5, 10, S), (2.5, 14, S)])
    tail(a, [(0.0, 0, S), (0.5, 12, S), (1.5, -6, S), (2.5, 12, S)])
    beats = [(0.0, 0, 0)]
    for k in range(5):
        t = 0.5 + 0.5 * k
        beats += [(t, 0, 14 if k % 4 == 0 else 10, QI), (t + 0.25, 0, -3, QO)]
    a.tr("hips", *beats)
    for k in range(5):
        a.ev(round(0.5 + 0.5 * k + 0.02, 3), "jiggle:0,%d" % (130 if k % 4 == 0 else 90))
    a.eyes((0.0, "open"), (0.2, "half"), (0.45, "smile"))
    a.att("mouth", (0.0, "default"), (0.45, "smile"))
    return a


def idle_beat():
    """Idle gesture: she presses a headphone cup to her ear and nods to the beat, tail keeping time (2.5 s)."""
    a = A("idle_beat", 2.5, mix=0.25, mix_out=0.35)
    ARMS.keys(a, "l", [(0.0, None, S), (0.45, (580, 885), CO), (2.0, (582, 888), S), (2.5, None, CIO)], flip=True)
    beat = 0.4
    a.rot("head", (0.0, 0), *[(0.5 + beat * k, (5 if k % 2 == 0 else -1), S) for k in range(4)], (2.5, 0, S))
    a.tr("hips", (0.0, 0, 0), *[(0.5 + beat * k, (-6 if k % 2 == 0 else 6), 2, S) for k in range(4)], (2.5, 0, 0, S))
    tail(a, [(0.0, 0, S)] + [(0.5 + beat * k, (12 if k % 2 == 0 else -6), S) for k in range(4)] + [(2.5, 0, S)])
    a.eyes((0.0, "open"), (0.45, "half"), (2.2, "open"))
    a.att("mouth", (0.0, "default"), (0.5, "small"), (2.1, "default"))
    for k in range(4):
        a.ev(round(0.5 + beat * k, 3), "jiggle:%d,100" % (-40 if k % 2 == 0 else 40))
    return a


def idle_scratch():
    """Idle gesture: she scratches the record back and forth in her hand like a deck (2.2 s)."""
    a = A("idle_scratch", 2.2, mix=0.25, mix_out=0.35)
    ARMS.keys(a, "r", [(0.0, None, S), (0.4, (330, 1120), CO), (1.8, (330, 1120), S), (2.2, None, CIO)])
    a.rot("weapon", (0.0, 0, S), *[(0.45 + 0.15 * k, (-40 if k % 2 == 0 else 20), "linear") for k in range(8)], (2.2, 0, S))
    a.rot("head", (0.0, 0), (0.5, -6, S), (1.7, -5, S), (2.2, 0, S))
    a.eyes((0.0, "open"), (0.4, "half"), (1.9, "open"))
    a.att("mouth", (0.0, "default"), (0.5, "smile"), (1.9, "default"))
    return a


def idle_wings():
    """Idle gesture: a wide stretch of the wings with a shake, the coat stirring (2.4 s)."""
    a = A("idle_wings", 2.4, mix=0.25, mix_out=0.4)
    a.tr("chest", (0.0, 0, 0), (0.7, 0, -6, S), (1.4, 0, -5, S), (2.0, 0, 2, QI), (2.4, 0, 0, S))
    shake = [(0.0, 0, S), (0.75, 20, CO)] + [(0.85 + 0.09 * i, 20 + (5 if i % 2 == 0 else -5) * (0.8 ** i), S) for i in range(7)]
    wings(a, shake + [(1.6, 18, S), (2.35, 0, CIO)], stagger=0.06)
    coat(a, [(0.0, 0, S), (0.8, 4, S), (1.6, 2, S), (2.4, 0, S)])
    a.eyes((0.0, "open"), (0.45, "half"), (0.7, "closed"), (1.75, "half"), (1.95, "open"))
    a.ev(1.9, "jiggle:0,160").ev(0.75, "jiggle:0,-110")
    return a


if __name__ == "__main__":
    for f in (idle, attack, cast, touch, victory, idle_beat, idle_scratch, idle_wings):
        print(f().save(OUT))
    print(cast("support_cast").save(OUT))
