"""Seraphiel's own animations for the layered rig v2 (prototype, 2026-10-20).

Writes assets/art/heroes/seraphiel/skins/rigproto2/anim/*.anim.json (the art's own set: RigAnim.find
looks there first for this art only). Conventions as tools/art_anims.py: rotate in degrees, + =
clockwise on screen; _r = her right = the viewer's left (the stand hand). Wings: + lifts the r wings
(viewer's left), - lifts the l wings. "carry" (fx) 0 = the stand planted on its base and leaning to
her hand, 1 = carried rigid in the hand (RigPlayer grip). "jiggle:x,y" events kick the breast
springs (rig px/s, + y = down).
Beats from the research notes (art_src/_review/rigproto, rig v2 brief): anticipation, contact,
overshoot, follow-through, settle; joints in order hips -> torso -> chest -> arm -> hand -> stand.
Usage: tools/layered/seraphiel_anims.py"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools"))
from art_anims import Anim  # noqa: E402

OUT = os.path.join(ROOT, "assets", "art", "heroes", "seraphiel", "skins", "rigproto2", "anim")
S, CO, EO, BO, QI, CIO = "sine_in_out", "cubic_out", "expo_out", "back_out", "quad_in", "cubic_in_out"
WINGS_R = ["wing_r1", "wing_r2", "wing_r3"]      # viewer's left, top to bottom
WINGS_L = ["wing_l1", "wing_l2", "wing_l3"]


def wings(a, keys, stagger=0.035, falloff=0.75):
    """keys [(t, lift deg, ease)]: every wing lifts by `lift` (scaled down the stack), top wings first."""
    for k, (wr, wl) in enumerate(zip(WINGS_R, WINGS_L)):
        f = falloff ** k
        a.rot(wr, *[(t + k * stagger, v * f, e) for t, v, e in keys])
        a.rot(wl, *[(t + k * stagger + 0.02, -v * f, e) for t, v, e in keys])


def attack():
    """Feedback Ring (1.0 s): she lifts the stand into a diagonal, mic at her cheek, and belts."""
    a = Anim("attack_ranged", 1.05, mix=0.08, mix_out=0.22)
    # planted through the wind-up (the body's lean would swing a carried stand's foot about 16 px per
    # degree); taken into the hand at the start of the fast swing, set down upright after it
    a.fx("carry", (0.0, 0.0), (0.15, 0.0), (0.21, 1.0, S), (0.83, 1.0), (0.91, 0.0, S))
    # anticipation: sink, chin down, gather; then rise into the belt
    a.tr("hips", (0.0, 0, 0), (0.17, -3, 9, CO), (0.29, 4, -7, EO), (0.5, 2, -4, S), (0.8, 0, 1, S), (1.05, 0, 0, S))
    a.rot("torso", (0.0, 0), (0.17, -2.5, CO), (0.3, 3.5, EO), (0.55, 2.5, S), (1.05, 0, S))
    a.rot("chest", (0.0, 0), (0.19, -1.5, CO), (0.31, 2.5, EO), (0.6, 1.5, S), (1.05, 0, S))
    a.sc("chest", (0.0, 1, 1), (0.19, 1.0, 1.02, CO), (0.3, 1.01, 0.985, EO), (0.6, 1, 1, S))
    a.rot("head", (0.0, 0), (0.17, 3, CO), (0.31, -7, EO), (0.36, -8.5, S), (0.6, -6, S), (1.05, 0, S))
    a.rot("neck", (0.0, 0), (0.17, 1.5, CO), (0.31, -2.5, EO), (1.05, 0, S))
    # the stand hand: lift and tip the stand to her mouth (the stand turns with the hand)
    a.rot("arm_r", (0.0, 0), (0.17, 4, CO), (0.3, -9, EO), (0.36, -10, S), (0.6, -8, S), (0.82, 0, CIO))
    a.rot("forearm_r", (0.0, 0), (0.17, -6, CO), (0.3, 22, EO), (0.36, 25, BO), (0.6, 21, S), (0.82, 0, CIO))
    a.rot("hand_r", (0.0, 0), (0.17, 2, CO), (0.29, 30, EO), (0.36, 36, BO), (0.6, 32, S), (0.82, -2, CIO), (1.05, 0, S))
    a.rot("weapon", (0.0, 0), (0.18, 0, CO), (0.3, 12, EO), (0.36, 15, BO), (0.6, 12, S), (0.82, 0, CIO))
    # the free arm: counterweight back, then flung out on the belt
    a.rot("arm_l", (0.0, 0), (0.17, 6, CO), (0.31, -24, EO), (0.4, -27, BO), (0.75, -18, S), (1.05, 0, S))
    a.rot("forearm_l", (0.0, 0), (0.17, -4, CO), (0.33, 18, EO), (0.45, 22, BO), (0.8, 10, S), (1.05, 0, S))
    a.rot("hand_l", (0.0, 0), (0.33, 16, EO), (0.5, 22, S), (1.05, 0, S))
    wings(a, [(0.0, 0, S), (0.16, -6, CO), (0.29, 12, EO), (0.4, 15, BO), (0.75, 8, S), (1.0, 0, S)])
    a.eyes((0.0, "open"), (0.14, "closed"), (0.31, "open"))
    a.att("mouth", (0.0, "default"), (0.26, "small"), (0.29, "wide"), (0.55, "open"), (0.66, "default"))
    a.fx("glow", (0.0, 0), (0.28, 0, S), (0.32, 0.7, EO), (0.6, 0, S))
    a.ev(0.05, "charge").ev(0.3, "release").ev(0.3, "vfx_bolt").ev(0.38, "hit")
    a.ev(0.17, "jiggle:0,140").ev(0.3, "jiggle:-40,-330").ev(0.84, "jiggle:0,90")
    return a


def cast():
    """Seraphic Aria (2.4 s): wings up and in, a breath, then the belt: wings flare, free arm up and
    out, head back, the note held with vibrato; stand planted."""
    a = Anim("cast", 2.4, mix=0.1, mix_out=0.3)
    a.tr("hips", (0.0, 0, 0), (0.35, 0, 12, CO), (0.8, 0, -5, EO), (1.0, 0, -7, S), (1.75, 0, -6, S), (2.1, 0, 3, QI), (2.4, 0, 0, BO))
    a.rot("torso", (0.0, 0), (0.35, -2, CO), (0.82, 2.5, EO), (1.75, 2, S), (2.4, 0, S))
    a.tr("chest", (0.0, 0, 0), (0.35, 0, 4, CO), (0.55, 0, -6, S), (0.82, 0, -3, EO), (1.75, 0, -4, S), (2.4, 0, 0, S))
    a.sc("chest", (0.0, 1, 1), (0.55, 1.012, 1.03, S), (0.82, 1.0, 1.0, EO), (2.4, 1, 1, S))
    a.rot("head", (0.0, 0), (0.35, 5, CO), (0.6, 6, S), (0.82, -9, EO), (1.0, -10, S), (1.75, -8, S), (2.4, 0, S))
    a.rot("neck", (0.0, 0), (0.35, 2, CO), (0.82, -4, EO), (2.4, 0, S))
    # vibrato on the held note
    vib = [(0.9 + i * 0.085, (-1.2 if i % 2 else 1.2), S) for i in range(10)]
    a.rot("face", (0.0, 0), *vib, (1.85, 0, S))
    # the free arm rises out and up, palm open
    a.rot("arm_l", (0.0, 0), (0.35, 8, CO), (0.84, -98, EO), (1.0, -106, BO), (1.75, -100, S), (2.3, 0, CIO))
    a.rot("forearm_l", (0.0, 0), (0.35, 14, CO), (0.86, -28, EO), (1.05, -36, BO), (1.75, -30, S), (2.3, 0, CIO))
    a.rot("hand_l", (0.0, 0), (0.35, 10, CO), (0.86, -22, EO), (1.1, -30, S), (1.75, -24, S), (2.3, 0, S))
    # the stand hand pulls the mic in a little (stand leans on its base)
    a.rot("arm_r", (0.0, 0), (0.82, -5, EO), (1.75, -4, S), (2.3, 0, S))
    a.rot("forearm_r", (0.0, 0), (0.82, 9, EO), (1.75, 8, S), (2.3, 0, S))
    wings(a, [(0.0, 0, S), (0.35, -10, CO), (0.8, 24, EO), (0.95, 28, BO), (1.75, 22, S), (2.35, 0, CIO)], stagger=0.04)
    a.eyes((0.0, "open"), (0.3, "closed"), (1.8, "open"))
    a.att("mouth", (0.0, "default"), (0.55, "small"), (0.78, "wide"), (1.62, "open"), (1.78, "smile"), (2.3, "default"))
    a.fx("glow", (0.0, 0), (0.75, 0.15, S), (0.84, 0.75, EO), (1.6, 0.45, S), (2.2, 0, S))      # the mic glows
    a.ev(0.82, "release").ev(0.84, "vfx_burst").ev(0.9, "hit")
    a.ev(0.35, "jiggle:0,120").ev(0.82, "jiggle:0,-300").ev(1.2, "jiggle:20,-120").ev(2.1, "jiggle:0,160")
    return a


def touch():
    """A poke on the body (1.2 s): flinch, a giggle bob, a bounce, back to idle with a smile."""
    a = Anim("touch", 1.2, mix=0.05, mix_out=0.3)
    a.tr("hips", (0.0, 0, 0), (0.06, -4, -5, EO), (0.18, 6, 4, S), (0.32, 3, -2, S), (0.5, 1, 1, S), (1.2, 0, 0, S))
    a.rot("torso", (0.0, 0), (0.08, 3, EO), (0.3, -1.5, S), (1.2, 0, S))
    a.tr("chest", (0.0, 0, 0), (0.06, 0, -8, EO), (0.18, 0, 6, QI), (0.3, 0, -3, S), (0.42, 0, 2, S), (0.6, 0, 0, S))
    a.rot("head", (0.0, 0), (0.08, -4, EO), (0.25, 6, S), (0.7, 5, S), (1.2, 0, S))
    a.rot("arm_l", (0.0, 0), (0.08, 9, EO), (0.3, 5, S), (0.9, 4, S), (1.2, 0, S))
    a.rot("forearm_l", (0.0, 0), (0.1, 45, EO), (0.26, 104, BO), (0.85, 98, S), (1.2, 0, CIO))
    a.rot("hand_l", (0.0, 0), (0.26, 18, BO), (0.85, 14, S), (1.2, 0, S))
    wings(a, [(0.0, 0, S), (0.05, -9, EO), (0.3, 6, BO), (0.8, 0, S)], stagger=0.03)
    a.eyes((0.0, "open"), (0.04, "closed"), (0.3, "smile"), (1.15, "open"))
    a.att("mouth", (0.0, "default"), (0.25, "smile"), (1.15, "default"))
    a.ev(0.06, "jiggle:0,-420").ev(0.2, "jiggle:-50,260").ev(0.36, "jiggle:0,-180")
    return a


def victory():
    """Hand on her hip, the stand leaned in, a bounce on every beat (0.5 s intro, 2.0 s loop at 120 BPM)."""
    a = Anim("victory", 2.5, loop=True, loop_start=0.5, mix=0.15)
    # elbow out, wrist on the hip ring at about (655, 1235): arm -38, forearm +90 (worked from the rest
    # pose: shoulder (607, 965), elbow (621, 1143), wrist (688, 1288))
    a.rot("arm_l", (0.0, 0), (0.35, -38, BO), (2.5, -38))
    a.rot("forearm_l", (0.0, 0), (0.35, 90, BO), (2.5, 90))
    a.rot("hand_l", (0.0, 0), (0.35, -12, BO), (2.5, -12))
    a.rot("head", (0.0, 0), (0.4, -6, BO), (1.5, -4, S), (2.5, -6, S))
    a.rot("torso", (0.0, 0), (0.4, 2, S), (2.5, 2))
    wings(a, [(0.0, 0, S), (0.4, 12, BO), (1.5, 9, S), (2.5, 12, S)], stagger=0.04)
    beats = [(0.0, 0, 0)]
    for k in range(5):
        t = 0.5 + 0.5 * k
        beats += [(t, 0, 7 if k % 4 == 0 else 4, QI), (t + 0.25, 0, -1, "quad_out")]
    a.tr("hips", *beats)
    for k in range(5):
        a.ev(round(0.5 + 0.5 * k + 0.02, 3), "jiggle:0,%d" % (190 if k % 4 == 0 else 120))
    a.eyes((0.0, "open"), (0.2, "half"), (0.45, "smile"))
    a.att("mouth", (0.0, "default"), (0.45, "smile"))
    return a


def idle_wings():
    """Idle gesture: a deep breath and a long wing stretch with a shake, eyes drifting shut (2.4 s)."""
    a = Anim("idle_wings", 2.4, mix=0.25, mix_out=0.4)
    a.tr("chest", (0.0, 0, 0), (0.7, 0, -7, S), (1.3, 0, -6, S), (1.9, 0, 2, QI), (2.4, 0, 0, S))
    a.sc("chest", (0.0, 1, 1), (0.7, 1.012, 1.03, S), (1.9, 1, 1, S))
    a.rot("head", (0.0, 0), (0.7, -4, S), (1.4, -5, S), (2.4, 0, S))
    shake = [(0.0, 0, S), (0.75, 20, CO)] + [(0.85 + 0.09 * i, 20 + (5 if i % 2 == 0 else -5) * (0.8 ** i), S) for i in range(7)]
    wings(a, shake + [(1.6, 18, S), (2.35, 0, CIO)], stagger=0.06, falloff=0.8)
    a.rot("arm_l", (0.0, 0), (0.7, -6, S), (1.8, -5, S), (2.4, 0, S))
    a.eyes((0.0, "open"), (0.45, "half"), (0.7, "closed"), (1.75, "half"), (1.95, "open"))
    a.att("mouth", (0.0, "default"), (0.5, "small"), (1.7, "default"))
    a.ev(1.9, "jiggle:0,170").ev(0.75, "jiggle:0,-120")
    return a


def idle_sway():
    """Idle gesture: she sways and nods to a song in her head, humming (2.5 s, two bars at 96 BPM)."""
    a = Anim("idle_sway", 2.5, mix=0.25, mix_out=0.35)
    beat = 0.625
    hx = [(0.0, 0, 0, S)]
    for k in range(4):
        t = beat * (k + 0.5)
        hx.append((t, (10 if k % 2 == 0 else -10), 3, S))
    hx.append((2.5, 0, 0, S))
    a.tr("hips", *hx)
    a.rot("torso", (0.0, 0), *[(beat * (k + 0.5), (-1.5 if k % 2 == 0 else 1.5), S) for k in range(4)], (2.5, 0, S))
    a.rot("head", (0.0, 0), *[(beat * (k + 0.5), (3.5 if k % 2 == 0 else -3.5), S) for k in range(4)], (2.5, 0, S))
    a.rot("arm_l", (0.0, 0), *[(beat * (k + 0.5), (-5 if k % 2 == 0 else 2), S) for k in range(4)], (2.5, 0, S))
    a.rot("forearm_l", (0.0, 0), *[(beat * (k + 0.5), (8 if k % 2 == 0 else 2), S) for k in range(4)], (2.5, 0, S))
    wings(a, [(0.0, 0, S)] + [(beat * (k + 0.5), (6 if k % 2 == 0 else 2), S) for k in range(4)] + [(2.5, 0, S)], stagger=0.05)
    a.eyes((0.0, "open"), (0.25, "half"), (2.2, "open"))
    a.att("mouth", (0.0, "default"), (0.4, "small"), (2.1, "default"))
    for k in range(4):
        a.ev(round(beat * (k + 0.5), 3), "jiggle:%d,110" % (-50 if k % 2 == 0 else 50))
    return a


def idle_lean():
    """Idle gesture: she leans toward the stand, hand to hip, a knowing smile (3.0 s)."""
    a = Anim("idle_lean", 3.0, mix=0.3, mix_out=0.45)
    a.tr("hips", (0.0, 0, 0), (0.6, 8, 3, S), (2.4, 8, 3, S), (3.0, 0, 0, S))
    a.rot("torso", (0.0, 0), (0.6, -3, S), (2.4, -3, S), (3.0, 0, S))
    a.rot("head", (0.0, 0), (0.6, -6, S), (2.4, -5, S), (3.0, 0, S))
    a.rot("arm_l", (0.0, 0), (0.55, -38, BO), (2.45, -38, S), (3.0, 0, CIO))
    a.rot("forearm_l", (0.0, 0), (0.55, 90, BO), (2.45, 90, S), (3.0, 0, CIO))
    a.rot("hand_l", (0.0, 0), (0.55, -12, BO), (2.45, -12, S), (3.0, 0, S))
    a.rot("forearm_r", (0.0, 0), (0.6, 6, S), (2.4, 6, S), (3.0, 0, S))
    wings(a, [(0.0, 0, S), (0.6, 7, BO), (2.4, 6, S), (3.0, 0, S)], stagger=0.05)
    a.eyes((0.0, "open"), (0.5, "half"), (2.5, "open"))
    a.att("mouth", (0.0, "default"), (0.6, "smile"), (2.5, "default"))
    a.ev(0.6, "jiggle:40,140").ev(2.95, "jiggle:-30,110")
    return a


if __name__ == "__main__":
    for f in (attack, cast, touch, victory, idle_wings, idle_sway, idle_lean):
        print(f().save(OUT))
