"""Kessa's own animations for her layered rig (2026-11-04).

Writes assets/art/heroes/kessa/skins/live/anim/*.anim.json (the art's own set). Conventions as animkit.py. A
sickle rides in each fist (weapon on hand_r, weapon_l on hand_l): `animkit.carried` keys each so it shows a
world tilt, 0 = hanging as painted.
Usage: tools/layered/kessa_anims.py"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
from animkit import A, Arms, carried, S, CO, BO, QI, QO, CIO  # noqa: E402

OUT = os.path.join(ROOT, "assets", "art", "heroes", "kessa", "skins", "live", "anim")
ARMS = Arms({"r": ((368, 625), (318, 860), (262, 1075)), "l": ((650, 625), (700, 860), (752, 1075))})


def tail(a, keys, lag=0.05):
    """keys [(t, swing deg, ease)]: her tail swings, each segment a beat after the one before and further."""
    for k in range(4):
        a.rot("tail%d" % (k + 1), *[(t + lag * k, v * (1.0 + 0.35 * k), e) for t, v, e in keys])


def both(a, r_keys, l_keys, r_tilt, l_tilt):
    """Both arms from wrist targets and both sickles at world tilts (all key lists at the same times)."""
    ak = ARMS.keys(a, "r", r_keys)
    al = ARMS.keys(a, "l", l_keys)
    hr = [(t, 0, e) for t, _, e in r_keys]
    hl = [(t, 0, e) for t, _, e in l_keys]
    carried(a, "weapon", ak, hr, r_tilt)
    carried(a, "weapon_l", al, hl, l_tilt)


def idle():
    """Her display pose, held under everything: weight on her right hip, head tilted, the sickles a little out."""
    a = A("idle", 4.0, loop=True, mix=0.3, mix_out=0.15)
    a.tr("hips", (0.0, -8, 2), (4.0, -8, 2))
    a.rot("torso", (0.0, 1.5), (4.0, 1.5))
    a.rot("chest", (0.0, -1.0), (4.0, -1.0))
    a.rot("head", (0.0, -5.0), (4.0, -5.0))
    a.rot("weapon", (0.0, -6), (4.0, -6))
    a.rot("weapon_l", (0.0, 6), (4.0, 6))
    tail(a, [(0.0, 6, S), (4.0, 6, S)], lag=0.0)
    return a


def attack():
    """Ashen Claw (0.85 s): she drops into a crouch with both sickles drawn back, then pounces, slashing both
    across in an X, her tail lashing out behind; then back up into her stance."""
    a = A("attack_melee", 0.85, mix=0.05, mix_out=0.2)
    a.tr("hips", (0.0, 0, 0), (0.14, 0, 24, CO), (0.24, -18, -14, CO), (0.42, -12, -8, S), (0.7, 0, 1, S), (0.82, 0, 0, S))
    a.rot("torso", (0.0, 0), (0.14, 4, CO), (0.24, -7, CO), (0.48, -4, S), (0.78, 0, CIO))
    a.rot("chest", (0.0, 0), (0.14, 3, CO), (0.25, -4, CO), (0.5, -2, S), (0.78, 0, CIO))
    a.sc("chest", (0.0, 1, 1), (0.14, 1.01, 0.98, CO), (0.24, 1.0, 1.02, CO), (0.5, 1, 1, S))
    a.rot("head", (0.0, 0), (0.14, 6, CO), (0.25, -4, CO), (0.5, -3, S), (0.8, 0, S))
    t = [0.0, 0.14, 0.24, 0.44, 0.75]
    both(a,
         [(t[0], None, S), (t[1], (300, 980), CO), (t[2], (470, 860), CO), (t[3], (480, 870), S), (t[4], None, CIO)],
         [(t[0], None, S), (t[1], (720, 980), CO), (t[2], (550, 860), CO), (t[3], (540, 870), S), (t[4], None, CIO)],
         [(t[0], 0, S), (t[1], -40, CO), (t[2], 70, CO), (t[3], 66, S), (t[4], 0, CIO)],
         [(t[0], 0, S), (t[1], 40, CO), (t[2], -70, CO), (t[3], -66, S), (t[4], 0, CIO)])
    tail(a, [(0.0, 0, S), (0.14, -12, CO), (0.26, 22, CO), (0.5, 8, S), (0.85, 0, S)])
    a.eyes((0.0, "open"), (0.1, "half"), (0.24, "open"))
    a.att("mouth", (0.0, "default"), (0.24, "wide"), (0.45, "smile"), (0.65, "default"))
    a.ev(0.05, "charge").ev(0.22, "release").ev(0.25, "hit")
    a.ev(0.14, "jiggle:0,160").ev(0.25, "jiggle:0,-240").ev(0.75, "jiggle:0,100")
    return a


def cast():
    """Twelfth Contract (2.3 s): she crosses the sickles before her face, a breath, then throws them wide and spins
    them, a flurry of three cuts low to high, ending with both blades raised; tail whipping."""
    a = A("cast", 2.3, mix=0.1, mix_out=0.3)
    a.tr("hips", (0.0, 0, 0), (0.35, 0, 16, CO), (0.75, 0, -6, CO), (1.0, 8, -4, S), (1.25, -8, -6, S), (1.5, 0, -10, CO), (2.0, 0, 3, QI), (2.3, 0, 0, BO))
    a.rot("torso", (0.0, 0), (0.35, 3, CO), (0.75, -3, CO), (1.0, 4, S), (1.25, -4, S), (1.5, 0, S), (2.3, 0, S))
    a.rot("head", (0.0, 0), (0.35, 5, CO), (0.75, -6, CO), (1.5, -8, S), (2.3, 0, S))
    t = [0.0, 0.35, 0.75, 1.0, 1.25, 1.5, 1.8, 2.15]
    both(a,
         [(t[0], None, S), (t[1], (470, 640), CO), (t[2], (220, 900), CO), (t[3], (380, 1000), CO), (t[4], (230, 780), CO),
          (t[5], (300, 560), CO), (t[6], (305, 570), S), (t[7], None, CIO)],
         [(t[0], None, S), (t[1], (550, 640), CO), (t[2], (800, 900), CO), (t[3], (640, 1000), CO), (t[4], (790, 780), CO),
          (t[5], (720, 560), CO), (t[6], (715, 570), S), (t[7], None, CIO)],
         [(t[0], 0, S), (t[1], 110, CO), (t[2], -60, CO), (t[3], 40, CO), (t[4], -90, CO), (t[5], 150, CO), (t[6], 148, S), (t[7], 0, CIO)],
         [(t[0], 0, S), (t[1], -110, CO), (t[2], 60, CO), (t[3], -40, CO), (t[4], 90, CO), (t[5], -150, CO), (t[6], -148, S), (t[7], 0, CIO)])
    tail(a, [(0.0, 0, S), (0.35, -10, CO), (0.75, 18, CO), (1.0, -16, S), (1.25, 18, S), (1.5, -10, S), (2.3, 0, S)])
    a.eyes((0.0, "open"), (0.3, "closed"), (0.72, "open"))
    a.att("mouth", (0.0, "default"), (0.75, "wide"), (1.0, "small"), (1.5, "wide"), (1.8, "smile"), (2.2, "default"))
    a.fx("glow", (0.0, 0), (0.7, 0.1, S), (0.8, 0.4, CO), (1.6, 0.3, S), (2.2, 0, S))
    a.ev(0.75, "release").ev(0.78, "vfx_burst").ev(0.8, "hit")
    for tt in (1.0, 1.25, 1.5):
        a.ev(round(tt + 0.01, 3), "jiggle:0,-160")
    a.ev(2.0, "jiggle:0,160")
    return a


def touch():
    """A poke (1.2 s): a startled hop with her tail puffed straight up, then a smug look and a lick of her fang."""
    a = A("touch", 1.2, mix=0.05, mix_out=0.3)
    a.tr("hips", (0.0, 0, 0), (0.06, 0, -18, CO), (0.2, 0, 6, QI), (0.32, 0, -3, S), (0.5, 0, 1, S), (1.2, 0, 0, S))
    a.rot("torso", (0.0, 0), (0.08, -3, CO), (0.3, 1.5, S), (1.2, 0, S))
    a.rot("head", (0.0, 0), (0.08, -4, CO), (0.25, 6, S), (0.7, 5, S), (1.2, 0, S))
    tail(a, [(0.0, 0, S), (0.06, -28, CO), (0.4, -24, S), (0.8, 4, S), (1.2, 0, S)], lag=0.03)
    a.rot("weapon", (0.0, 0), (0.08, -14, CO), (0.5, -6, S), (1.2, 0, S))
    a.rot("weapon_l", (0.0, 0), (0.08, 14, CO), (0.5, 6, S), (1.2, 0, S))
    a.eyes((0.0, "open"), (0.04, "closed"), (0.3, "half"), (1.15, "open"))
    a.att("mouth", (0.0, "default"), (0.1, "open"), (0.35, "smile"), (1.15, "default"))
    a.ev(0.06, "jiggle:0,-260").ev(0.22, "jiggle:20,170").ev(0.38, "jiggle:0,-100")
    return a


def victory():
    """She twirls a sickle on one finger and leans on her hip, tail curling, a bounce on every beat (0.5 s intro,
    2.0 s loop)."""
    a = A("victory", 2.5, loop=True, loop_start=0.5, mix=0.15)
    ak = ARMS.keys(a, "r", [(0.0, None, S), (0.35, (330, 760), BO), (2.5, (330, 760), S)])
    spin = [(0.5 + 0.125 * i, -90.0 * (i + 1), "linear") for i in range(16)]
    a.rot("weapon", (0.0, 0, S), (0.35, -30, BO), *spin)
    ARMS.keys(a, "l", [(0.0, None, S), (0.35, (680, 1010), BO), (2.5, (680, 1010), S)])
    a.rot("weapon_l", (0.0, 0), (0.35, 20, BO), (2.5, 20))
    a.rot("head", (0.0, 0), (0.4, -6, BO), (1.5, -4, S), (2.5, -6, S))
    tail(a, [(0.0, 0, S), (0.4, 14, BO), (1.5, 8, S), (2.5, 14, S)])
    beats = [(0.0, 0, 0)]
    for k in range(5):
        t = 0.5 + 0.5 * k
        beats += [(t, 0, 12 if k % 4 == 0 else 8, QI), (t + 0.25, 0, -3, QO)]
    a.tr("hips", *beats)
    for k in range(5):
        a.ev(round(0.5 + 0.5 * k + 0.02, 3), "jiggle:0,%d" % (120 if k % 4 == 0 else 85))
    a.eyes((0.0, "open"), (0.2, "half"), (0.45, "smile"))
    a.att("mouth", (0.0, "default"), (0.45, "smile"))
    _ = ak
    return a


def idle_spin():
    """Idle gesture: she spins the right sickle round her finger twice and catches it (2.4 s)."""
    a = A("idle_spin", 2.4, mix=0.25, mix_out=0.35)
    ARMS.keys(a, "r", [(0.0, None, S), (0.4, (320, 900), CO), (1.9, (320, 900), S), (2.4, None, CIO)])
    spin = [(0.5 + 0.1 * i, -90.0 * (i + 1), "linear") for i in range(8)]
    a.rot("weapon", (0.0, 0, S), (0.4, -20, CO), *spin, (1.5, -740, BO), (1.9, -720, S), (2.4, -720, S))
    a.rot("head", (0.0, 0), (0.5, -3, S), (1.5, -5, S), (2.4, 0, S))
    tail(a, [(0.0, 0, S), (0.6, 10, S), (1.2, -6, S), (1.8, 8, S), (2.4, 0, S)])
    a.eyes((0.0, "open"), (0.4, "half"), (1.5, "smile"), (2.1, "open"))
    a.att("mouth", (0.0, "default"), (1.5, "smile"), (2.2, "default"))
    a.ev(1.5, "jiggle:-20,110")
    return a


def idle_stretch():
    """Idle gesture: a cat's stretch, both arms up with the sickles, back arched, a yawn (2.6 s)."""
    a = A("idle_stretch", 2.6, mix=0.25, mix_out=0.4)
    t = [0.0, 0.6, 1.6, 2.2]
    both(a,
         [(t[0], None, S), (t[1], (400, 470), S), (t[2], (410, 480), S), (t[3], None, CIO)],
         [(t[0], None, S), (t[1], (620, 470), S), (t[2], (610, 480), S), (t[3], None, CIO)],
         [(t[0], 0, S), (t[1], 160, S), (t[2], 158, S), (t[3], 0, CIO)],
         [(t[0], 0, S), (t[1], -160, S), (t[2], -158, S), (t[3], 0, CIO)])
    a.tr("chest", (0.0, 0, 0), (0.6, 0, -10, S), (1.6, 0, -9, S), (2.2, 0, 2, QI), (2.6, 0, 0, S))
    a.sc("chest", (0.0, 1, 1), (0.6, 1.01, 1.03, S), (2.2, 1, 1, S))
    a.rot("head", (0.0, 0), (0.6, 6, S), (1.6, 7, S), (2.4, 0, S))
    tail(a, [(0.0, 0, S), (0.6, -18, S), (1.6, -14, S), (2.4, 0, S)])
    a.eyes((0.0, "open"), (0.5, "closed"), (1.7, "half"), (2.1, "open"))
    a.att("mouth", (0.0, "default"), (0.7, "wide"), (1.4, "small"), (1.8, "default"))
    a.ev(2.2, "jiggle:0,180").ev(0.6, "jiggle:0,-130")
    return a


def idle_ears():
    """Idle gesture: she taps her headphones to the beat, nodding, tail keeping time (2.5 s)."""
    a = A("idle_ears", 2.5, mix=0.25, mix_out=0.35)
    ARMS.keys(a, "l", [(0.0, None, S), (0.45, (610, 470), CO), (2.0, (612, 474), S), (2.5, None, CIO)], flip=True)
    a.rot("weapon_l", (0.0, 0), (0.45, -40, CO), (2.0, -38, S), (2.5, 0, S))
    beat = 0.4
    a.rot("head", (0.0, 0), *[(0.5 + beat * k, (4 if k % 2 == 0 else -1), S) for k in range(4)], (2.5, 0, S))
    a.tr("hips", (0.0, 0, 0), *[(0.5 + beat * k, (-6 if k % 2 == 0 else 6), 2, S) for k in range(4)], (2.5, 0, 0, S))
    tail(a, [(0.0, 0, S)] + [(0.5 + beat * k, (12 if k % 2 == 0 else -6), S) for k in range(4)] + [(2.5, 0, S)])
    a.eyes((0.0, "open"), (0.45, "half"), (2.2, "open"))
    a.att("mouth", (0.0, "default"), (0.5, "small"), (2.1, "default"))
    for k in range(4):
        a.ev(round(0.5 + beat * k, 3), "jiggle:%d,100" % (-40 if k % 2 == 0 else 40))
    return a


if __name__ == "__main__":
    for f in (idle, attack, cast, touch, victory, idle_spin, idle_stretch, idle_ears):
        print(f().save(OUT))
