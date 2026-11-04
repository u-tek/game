"""Uriela's own animations for her layered rig (2026-11-04).

Writes assets/art/heroes/uriela/skins/live/anim/*.anim.json (the art's own set). Conventions as
seraphiel_anims.py: rotate in degrees, + = clockwise on screen; _r = her right = the viewer's left (the lance
hand); wings: + lifts the r wing (viewer's left), - the l wing; "carry" 0 = the lance planted on its butt and
leaning to her hand, 1 = carried rigid in the hand (its own rotate key turns it about the grip).
Arm poses are solved from the joint chain (arm_pose: a two-bone solve to a wrist target), so the hand lands
where it is meant to.
Usage: tools/layered/uriela_anims.py"""
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools"))
sys.path.insert(0, HERE)
from seraphiel_anims import A, S, CO, BO, QI, QO, CIO  # noqa: E402

OUT = os.path.join(ROOT, "assets", "art", "heroes", "uriela", "skins", "live", "anim")
# rest joints (uriela_rig.py): shoulder, elbow, wrist
ARM = {"r": ((398, 870), (378, 1045), (316, 1124)), "l": ((614, 870), (632, 1050), (690, 1186))}
WINGS_R, WINGS_L = ["wing_r", "wing_r2"], ["wing_l", "wing_l2"]


def arm_pose(side, target, flip=False):
    """(arm, forearm) rotation keys in degrees that put the wrist on `target`, the elbow bent to the same
    side as at rest (flip: the other side, for a hand raised to her face). Unreachable targets are pulled
    into reach."""
    (sx, sy), (ex, ey), (wx, wy) = ARM[side]
    l1, l2 = math.hypot(ex - sx, ey - sy), math.hypot(wx - ex, wy - ey)
    tx, ty = target
    d = max(abs(l1 - l2) + 1.0, min(l1 + l2 - 1.0, math.hypot(tx - sx, ty - sy)))
    a0 = math.atan2(ty - sy, tx - sx)
    alpha = math.acos(max(-1.0, min(1.0, (l1 * l1 + d * d - l2 * l2) / (2 * l1 * d))))
    side_of = lambda px, py, qx, qy: math.copysign(1.0, (qx - sx) * (py - sy) - (qy - sy) * (px - sx))
    rest_side = side_of(ex, ey, wx, wy) * (-1.0 if flip else 1.0)
    for sgn in (1, -1):
        u1 = a0 + sgn * alpha
        elx, ely = sx + l1 * math.cos(u1), sy + l1 * math.sin(u1)
        if side_of(elx, ely, sx + d * math.cos(a0), sy + d * math.sin(a0)) == rest_side:
            break
    tx2, ty2 = sx + d * math.cos(a0), sy + d * math.sin(a0)
    f1 = math.atan2(ty2 - ely, tx2 - elx)
    u0 = math.atan2(ey - sy, ex - sx)
    f0 = math.atan2(wy - ey, wx - ex)
    du = math.degrees(u1 - u0)
    df = math.degrees((f1 - f0) - (u1 - u0))
    norm = lambda a: (a + 180.0) % 360.0 - 180.0
    return round(norm(du), 1), round(norm(df), 1)


def arm(a, side, keys, flip=False):
    """keys [(t, wrist target or None for rest, ease)] -> arm and forearm keys."""
    ak, fk = [], []
    for t, tgt, e in keys:
        du, df = (0.0, 0.0) if tgt is None else arm_pose(side, tgt, flip)
        ak.append((t, du, e))
        fk.append((t, df, e))
    a.rot("arm_" + side, *ak)
    a.rot("forearm_" + side, *fk)
    return ak, fk


def lance(a, arm_keys, hand_keys, tilt_keys):
    """The carried lance's own rotate keys, so it shows `tilt` degrees in the world (+ = the blade to the
    viewer's right) whatever her arm does: the hand's turn (arm + forearm + hand) is taken back out.
    arm_keys: arm()'s (ak, fk); hand_keys, tilt_keys: [(t, deg, ease)] at the same times."""
    ak, fk = arm_keys
    a.rot("weapon", *[(t, round(tilt - u - f - h, 1), e) for (t, u, _), (_, f, _), (_, h, _), (_, tilt, e)
                      in zip(ak, fk, hand_keys, tilt_keys)])


def wings(a, keys, stagger=0.04, tip=0.6):
    """keys [(t, lift deg, ease)]: both wings lift, the tips a beat later and further (they bend)."""
    a.rot("wing_r", *[(t, v, e) for t, v, e in keys])
    a.rot("wing_l", *[(t + 0.02, -v, e) for t, v, e in keys])
    a.rot("wing_r2", *[(t + stagger, v * tip, e) for t, v, e in keys])
    a.rot("wing_l2", *[(t + stagger + 0.02, -v * tip, e) for t, v, e in keys])


def attack():
    """Sky Lance (0.95 s): she sinks and draws the lance down, then drives it up and forward in one jab,
    rising on her toes, the free arm flung back; it comes home and is planted again."""
    a = A("attack_thrust", 0.95, mix=0.06, mix_out=0.2)
    a.fx("carry", (0.0, 0.0), (0.13, 0.0), (0.17, 1.0, S), (0.8, 1.0), (0.88, 0.0, S))
    a.fx("trail", (0.0, 0.0), (0.17, 0.0), (0.2, 1.0, QO), (0.36, 0.0, S))
    a.tr("hips", (0.0, 0, 0), (0.16, -4, 10, CO), (0.27, 7, -12, CO), (0.45, 5, -8, S), (0.78, 0, 1, S), (0.88, 0, 0, S))
    a.rot("torso", (0.0, 0), (0.16, -3, CO), (0.28, 5, CO), (0.5, 3.5, S), (0.82, 0, CIO))
    a.rot("chest", (0.0, 0), (0.17, -2, CO), (0.29, 3, CO), (0.55, 2, S), (0.82, 0, CIO))
    a.sc("chest", (0.0, 1, 1), (0.17, 1.0, 1.02, CO), (0.28, 1.01, 0.985, CO), (0.55, 1, 1, S))
    a.rot("head", (0.0, 0), (0.16, 4, CO), (0.29, -5, CO), (0.55, -4, S), (0.85, 0, S))
    # the lance hand: down and back, then up past her shoulder (the lance rides with it, tipped forward)
    ak = arm(a, "r", [(0.0, None, S), (0.16, (302, 1158), CO), (0.27, (332, 1025), CO), (0.5, (330, 1032), S), (0.8, None, CIO)])
    hk = [(0.0, 0, S), (0.16, 4, CO), (0.27, -6, CO), (0.5, -5, S), (0.8, 0, S)]
    a.rot("hand_r", *hk)
    # tipped out, away from her face (a lance tipped in crosses it)
    lance(a, ak, hk, [(0.0, 0, S), (0.16, 4, CO), (0.27, -20, CO), (0.5, -17, S), (0.8, 0, S)])
    # the free arm: flung back for balance
    a.rot("arm_l", (0.0, 0), (0.16, 6, CO), (0.28, -22, CO), (0.4, -25, BO), (0.75, -12, S), (0.95, 0, S))
    a.rot("forearm_l", (0.0, 0), (0.16, -4, CO), (0.3, 16, CO), (0.45, 20, BO), (0.8, 6, S), (0.95, 0, S))
    wings(a, [(0.0, 0, S), (0.15, -7, CO), (0.28, 14, CO), (0.4, 17, BO), (0.75, 7, S), (0.95, 0, S)])
    a.eyes((0.0, "open"), (0.12, "half"), (0.26, "open"))
    a.att("mouth", (0.0, "default"), (0.24, "wide"), (0.5, "small"), (0.62, "default"))
    a.ev(0.05, "charge").ev(0.24, "release").ev(0.28, "hit")
    a.ev(0.16, "jiggle:0,110").ev(0.28, "jiggle:-30,-230").ev(0.8, "jiggle:0,90")
    return a


def cast():
    """Sunbreak Charge (2.3 s): wings fold, a breath, then she hoists the lance high, wings flared, free arm
    thrown up, head back with a shout; the blade glows; then the lance comes down and is planted."""
    a = A("cast", 2.3, mix=0.1, mix_out=0.3)
    a.fx("carry", (0.0, 0.0), (0.32, 0.0), (0.4, 1.0, S), (1.95, 1.0), (2.1, 0.0, S))
    a.tr("hips", (0.0, 0, 0), (0.35, 0, 12, CO), (0.8, 0, -8, CO), (1.0, 0, -9, S), (1.7, 0, -7, S), (2.05, 0, 3, QI), (2.3, 0, 0, BO))
    a.rot("torso", (0.0, 0), (0.35, -2, CO), (0.82, 2.5, CO), (1.7, 2, S), (2.3, 0, S))
    a.tr("chest", (0.0, 0, 0), (0.35, 0, 4, CO), (0.55, 0, -6, S), (0.82, 0, -3, CO), (1.7, 0, -4, S), (2.3, 0, 0, S))
    a.sc("chest", (0.0, 1, 1), (0.55, 1.012, 1.03, S), (0.82, 1.0, 1.0, CO), (2.3, 1, 1, S))
    a.rot("head", (0.0, 0), (0.35, 5, CO), (0.82, -9, CO), (1.0, -10, S), (1.7, -8, S), (2.3, 0, S))
    a.rot("neck", (0.0, 0), (0.35, 2, CO), (0.82, -4, CO), (2.3, 0, S))
    ak = arm(a, "r", [(0.0, None, S), (0.35, (305, 1150), CO), (0.82, (336, 1000), CO), (1.0, (334, 992), BO), (1.75, (336, 1000), S),
                      (2.1, None, CIO)])
    hk = [(0.0, 0, S), (0.35, 0, CO), (0.82, 0, CO), (1.0, 0, BO), (1.75, 0, S), (2.1, 0, CIO)]
    lance(a, ak, hk, [(0.0, 0, S), (0.35, -3, CO), (0.82, 8, CO), (1.0, 9, BO), (1.75, 7, S), (2.1, 0, CIO)])
    a.rot("arm_l", (0.0, 0), (0.35, 8, CO), (0.84, -98, CO), (1.0, -106, BO), (1.75, -100, S), (2.25, 0, CIO))
    a.rot("forearm_l", (0.0, 0), (0.35, 14, CO), (0.86, -28, CO), (1.05, -36, BO), (1.75, -30, S), (2.25, 0, CIO))
    a.rot("hand_l", (0.0, 0), (0.35, 10, CO), (0.86, -22, CO), (1.1, -30, S), (1.75, -24, S), (2.25, 0, S))
    wings(a, [(0.0, 0, S), (0.35, -10, CO), (0.8, 24, CO), (0.95, 28, BO), (1.75, 22, S), (2.3, 0, CIO)], stagger=0.05)
    a.eyes((0.0, "open"), (0.3, "closed"), (0.8, "open"))
    a.att("mouth", (0.0, "default"), (0.55, "small"), (0.8, "wide"), (1.5, "open"), (1.75, "smile"), (2.25, "default"))
    a.fx("glow", (0.0, 0), (0.75, 0.1, S), (0.86, 0.45, CO), (1.6, 0.3, S), (2.2, 0, S))
    a.ev(0.82, "release").ev(0.84, "vfx_burst").ev(0.9, "hit")
    a.ev(0.35, "jiggle:0,120").ev(0.82, "jiggle:0,-220").ev(1.2, "jiggle:20,-120").ev(2.05, "jiggle:0,160")
    return a


def touch():
    """A poke (1.2 s): a flinch, a laugh, her free hand up to her collar, a bounce."""
    a = A("touch", 1.2, mix=0.05, mix_out=0.3)
    a.tr("hips", (0.0, 0, 0), (0.06, 4, -5, CO), (0.18, -6, 4, S), (0.32, -3, -2, S), (0.5, -1, 1, S), (1.2, 0, 0, S))
    a.rot("torso", (0.0, 0), (0.08, -3, CO), (0.3, 1.5, S), (1.2, 0, S))
    a.tr("chest", (0.0, 0, 0), (0.06, 0, -8, CO), (0.18, 0, 6, QI), (0.3, 0, -3, S), (0.42, 0, 2, S), (0.6, 0, 0, S))
    a.rot("head", (0.0, 0), (0.08, 4, CO), (0.25, -6, S), (0.7, -5, S), (1.2, 0, S))
    arm(a, "l", [(0.0, None, S), (0.13, (650, 1010), QO), (0.32, (604, 908), BO), (0.85, (606, 912), S), (1.2, None, CIO)], flip=True)
    a.rot("hand_l", (0.0, 0), (0.13, -5, QO), (0.32, 10, BO), (0.85, 8, S), (1.2, 0, S))
    wings(a, [(0.0, 0, S), (0.12, -7, QO), (0.4, 6, BO), (0.85, 0, S)], stagger=0.03)
    a.eyes((0.0, "open"), (0.04, "closed"), (0.3, "smile"), (1.15, "open"))
    a.att("mouth", (0.0, "default"), (0.1, "open"), (0.3, "smile"), (1.15, "default"))
    a.ev(0.06, "jiggle:0,-240").ev(0.22, "jiggle:30,150").ev(0.38, "jiggle:0,-100")
    return a


def victory():
    """Hand on her hip, the lance leaned in, wings up, a bounce on every beat (0.5 s intro, 2.0 s loop)."""
    a = A("victory", 2.5, loop=True, loop_start=0.5, mix=0.15)
    arm(a, "l", [(0.0, None, S), (0.35, (640, 1185), BO), (2.5, (640, 1185), S)])
    a.rot("hand_l", (0.0, 0), (0.35, -14, BO), (2.5, -14))
    a.rot("head", (0.0, 0), (0.4, -6, BO), (1.5, -4, S), (2.5, -6, S))
    a.rot("torso", (0.0, 0), (0.4, 2, S), (2.5, 2))
    wings(a, [(0.0, 0, S), (0.4, 14, BO), (1.5, 10, S), (2.5, 14, S)])
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


def idle_twirl():
    """Idle gesture: she rocks the planted lance side to side in her grip, humming, head tilting (2.6 s)."""
    a = A("idle_twirl", 2.6, mix=0.25, mix_out=0.35)
    beat = 0.65
    sway = [(0.0, 0, S)] + [(beat * (k + 0.5), (5 if k % 2 == 0 else -5), S) for k in range(4)] + [(2.6, 0, S)]
    a.rot("hand_r", *sway)
    arm(a, "r", [(0.0, None, S)] + [(beat * (k + 0.5), (296 if k % 2 == 0 else 326, 1124), S) for k in range(4)] + [(2.6, None, S)])
    a.rot("head", (0.0, 0), *[(beat * (k + 0.5), (3 if k % 2 == 0 else -3), S) for k in range(4)], (2.6, 0, S))
    a.tr("hips", (0.0, 0, 0), *[(beat * (k + 0.5), (-6 if k % 2 == 0 else 6), 2, S) for k in range(4)], (2.6, 0, 0, S))
    wings(a, [(0.0, 0, S)] + [(beat * (k + 0.5), (5 if k % 2 == 0 else 2), S) for k in range(4)] + [(2.6, 0, S)])
    a.eyes((0.0, "open"), (0.3, "half"), (2.3, "open"))
    a.att("mouth", (0.0, "default"), (0.4, "small"), (2.2, "default"))
    for k in range(4):
        a.ev(round(beat * (k + 0.5), 3), "jiggle:%d,100" % (-40 if k % 2 == 0 else 40))
    return a


def idle_stretch():
    """Idle gesture: a deep breath, wings stretched wide with a shake, eyes drifting shut (2.4 s)."""
    a = A("idle_stretch", 2.4, mix=0.25, mix_out=0.4)
    a.tr("chest", (0.0, 0, 0), (0.7, 0, -7, S), (1.3, 0, -6, S), (1.9, 0, 2, QI), (2.4, 0, 0, S))
    a.sc("chest", (0.0, 1, 1), (0.7, 1.012, 1.03, S), (1.9, 1, 1, S))
    a.rot("head", (0.0, 0), (0.7, -4, S), (1.4, -5, S), (2.4, 0, S))
    shake = [(0.0, 0, S), (0.75, 22, CO)] + [(0.85 + 0.09 * i, 22 + (6 if i % 2 == 0 else -6) * (0.8 ** i), S) for i in range(7)]
    wings(a, shake + [(1.6, 20, S), (2.35, 0, CIO)], stagger=0.06)
    a.rot("arm_l", (0.0, 0), (0.7, -8, S), (1.8, -6, S), (2.4, 0, S))
    a.eyes((0.0, "open"), (0.45, "half"), (0.7, "closed"), (1.75, "half"), (1.95, "open"))
    a.att("mouth", (0.0, "default"), (0.5, "small"), (1.7, "default"))
    a.ev(1.9, "jiggle:0,170").ev(0.75, "jiggle:0,-120")
    return a


def idle_visor():
    """Idle gesture: she reaches up and tips her visor, a wink and a grin (2.4 s)."""
    a = A("idle_visor", 2.4, mix=0.25, mix_out=0.35)
    arm(a, "l", [(0.0, None, S), (0.45, (600, 760), CO), (0.6, (590, 700), BO), (1.5, (592, 704), S), (2.1, None, CIO)])
    a.rot("hand_l", (0.0, 0), (0.45, -20, CO), (0.6, -35, BO), (1.5, -32, S), (2.1, 0, S))
    a.rot("head", (0.0, 0), (0.5, -3, S), (0.75, 4, BO), (1.5, 3, S), (2.2, 0, S))
    a.tr("hips", (0.0, 0, 0), (0.6, 4, 2, S), (1.6, 4, 2, S), (2.4, 0, 0, S))
    wings(a, [(0.0, 0, S), (0.6, 6, BO), (1.6, 4, S), (2.4, 0, S)])
    a.eyes((0.0, "open"), (0.62, "smile"), (1.6, "open"))
    a.att("mouth", (0.0, "default"), (0.62, "smile"), (1.7, "default"))
    a.ev(0.6, "jiggle:20,120").ev(2.1, "jiggle:-20,90")
    return a


def idle():
    """Her display pose, held under everything (the base track's "idle"; the procedural breath and sway ride on
    it): weight on her left hip, a tilt of the head, her free hand on her hip, the lance leaned a little."""
    a = A("idle", 4.0, loop=True, mix=0.3, mix_out=0.15)
    a.tr("hips", (0.0, 8, 2), (4.0, 8, 2))
    a.rot("torso", (0.0, -1.5), (4.0, -1.5))
    a.rot("chest", (0.0, 1.0), (4.0, 1.0))
    a.rot("head", (0.0, 4.0), (4.0, 4.0))
    du, df = arm_pose("l", (640, 1185))
    a.rot("arm_l", (0.0, du), (4.0, du))
    a.rot("forearm_l", (0.0, df), (4.0, df))
    a.rot("hand_l", (0.0, -14), (4.0, -14))
    return a


if __name__ == "__main__":
    for f in (idle, attack, cast, touch, victory, idle_twirl, idle_stretch, idle_visor):
        print(f().save(OUT))
    for side, tgt in (("r", (338, 985)), ("l", (590, 700)), ("l", (640, 1185))):
        print("arm_pose", side, tgt, arm_pose(side, tgt))
