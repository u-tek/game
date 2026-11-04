"""Helpers for a layered rig's animation scripts (tools/layered/<hero>_anims.py), shared since Lucen (2026-11-04).

Conventions as seraphiel_anims.py: rotate in degrees, + = clockwise on screen; _r = her right = the viewer's left.
    Arms(chains)                one heroine's arm joints (shoulder, elbow, wrist per side, rest pose)
    arms.pose(side, target)     (arm, forearm) degrees that put the wrist on a target, the elbow on its rest side
    arms.keys(a, side, keys)    arm and forearm keys from wrist targets ([(t, (x, y) or None, ease)])
    carried(a, bone, ak, hk, tilt)  a carried prop's own keys so it shows `tilt` degrees in the world
    wings(a, keys)              both wings and their tips (bones wing_r, wing_r2, wing_l, wing_l2)
"""
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, ".."))
from seraphiel_anims import A, S, CO, BO, QI, QO, CIO  # noqa: E402,F401


class Arms:
    def __init__(self, chains):
        self.chains = chains

    def pose(self, side, target, flip=False):
        (sx, sy), (ex, ey), (wx, wy) = self.chains[side]
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
        norm = lambda v: (v + 180.0) % 360.0 - 180.0
        return round(norm(math.degrees(u1 - u0)), 1), round(norm(math.degrees((f1 - f0) - (u1 - u0))), 1)

    def keys(self, a, side, keys, flip=False):
        ak, fk = [], []
        for t, tgt, e in keys:
            du, df = (0.0, 0.0) if tgt is None else self.pose(side, tgt, flip)
            ak.append((t, du, e))
            fk.append((t, df, e))
        a.rot("arm_" + side, *ak)
        a.rot("forearm_" + side, *fk)
        return ak, fk


def carried(a, bone, arm_keys, hand_keys, tilt_keys):
    """A prop riding on her hand: its own rotate keys so it shows `tilt` degrees in the world (the arm's,
    forearm's and hand's turns taken back out). All key lists at the same times."""
    ak, fk = arm_keys
    a.rot(bone, *[(t, round(tilt - u - f - h, 1), e) for (t, u, _), (_, f, _), (_, h, _), (_, tilt, e)
                  in zip(ak, fk, hand_keys, tilt_keys)])


def wings(a, keys, stagger=0.04, tip=0.6):
    """keys [(t, lift deg, ease)]: both wings lift, the tips a beat later and further."""
    a.rot("wing_r", *[(t, v, e) for t, v, e in keys])
    a.rot("wing_l", *[(t + 0.02, -v, e) for t, v, e in keys])
    a.rot("wing_r2", *[(t + stagger, v * tip, e) for t, v, e in keys])
    a.rot("wing_l2", *[(t + stagger + 0.02, -v * tip, e) for t, v, e in keys])
