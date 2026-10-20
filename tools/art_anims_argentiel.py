"""Argentiel's own animations (layered rig: wings / spear / body, docs/dev/halorig.md 11.4)
-> assets/art/heroes/argentiel/anim/<name>.anim.json (RigAnim.find takes a hero's own first).

    python tools/art_anims_argentiel.py

Her spear is its own layer (the whole spear, rebuilt from the painting), pivoting in her raised left
fist and passing behind her body, in front of her wings: it can swing level, thrust and spin, which a
single painting could not. Conventions as tools/art_anims.py (degrees clockwise on screen, rig px).
The spear rests pointing up and to her front (tip up-right, about -59 deg); +45 deg brings it level.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from art_anims import Anim, wings2  # noqa: E402

import math  # noqa: E402

REST_DEG = -58.7      # the spear's line at rest, tip up and to her front


def along(*pts):
    """Translate keys for the spear sliding along its own line: (t, px along the spear, spear rotation
    at that key[, ease]) -> (t, x, y[, ease]) in the fist's space."""
    out = []
    for p in pts:
        ang = math.radians(REST_DEG + p[2])
        out.append((p[0], round(p[1] * math.cos(ang), 1), round(p[1] * math.sin(ang), 1)) + tuple(p[3:]))
    return out


OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "art", "heroes", "argentiel", "anim")


def attack_thrust():
    """She swings the spear down level behind her as she sinks back and her six wings fold, then
    drives it forward off the back foot - hips, chest, head, arm, spear, one after another - while
    the wings flare open; she holds the strike a beat and the spear rides back up to rest."""
    a = Anim("attack_thrust", 0.95, mix=0.06, mix_out=0.22)
    a.lunge((0, 0), (0.22, -0.12, "cubic_out"), (0.33, 1.0, "expo_out"), (0.55, 1.0, "cubic_in_out"), (0.95, 0))
    a.sc("root", (0, 1, 1), (0.22, 1.05, 0.95, "expo_out"), (0.32, 0.95, 1.06, "expo_out"), (0.44, 1.01, 0.99), (0.62, 1, 1))
    a.rot("root", (0, 0), (0.22, -6, "cubic_out"), (0.33, 9, "expo_out"), (0.55, 7), (0.95, 0))
    a.tr("hips", (0, 0, 0), (0.22, -4, 14, "cubic_out"), (0.33, 6, -6, "expo_out"), (0.55, 4, -2), (0.95, 0, 0))
    a.rot("torso", (0, 0), (0.22, -3), (0.34, 4, "expo_out"), (0.65, 1.5), (0.95, 0))
    a.tr("chest", (0, 0, 0), (0.22, -3, 4, "cubic_out"), (0.34, 4, -6, "expo_out"), (0.65, 1, -1), (0.95, 0, 0))
    a.sc("chest", (0, 1, 1), (0.22, 0.99, 0.97), (0.34, 1.02, 1.04, "expo_out"), (0.65, 1, 1))
    a.rot("head", (0, 0), (0.23, -5, "cubic_out"), (0.36, 4, "expo_out"), (0.6, 2), (0.95, 0))
    a.rot("arm_l", (0, 0), (0.22, -6, "cubic_out"), (0.33, 8, "expo_out"), (0.55, 6), (0.95, 0))
    a.rot("forearm_l", (0, 0), (0.23, -5, "cubic_out"), (0.35, 7, "expo_out"), (0.95, 0))
    a.rot("arm_r", (0, 0), (0.22, 5, "cubic_out"), (0.34, -6, "expo_out"), (0.95, 0))
    a.rot("forearm_r", (0, 0), (0.23, 4, "cubic_out"), (0.36, -5, "expo_out"), (0.95, 0))
    # the spear: swung level and drawn back, driven forward along its line, held, ridden back up
    a.rot("weapon", (0, 0), (0.22, 40, "cubic_in_out"), (0.33, 47, "expo_out"), (0.55, 45), (0.95, 0, "back_out"))
    # slid through her fist along its own line (she holds it just under the head): back a little, then
    # forward so the long reach is in front of her (rig px along the levelled spear, about -13 deg)
    a.tr("weapon", (0, 0, 0), *along((0.22, -60, 40), (0.33, 380, 47, "expo_out"), (0.55, 340, 45), (0.95, 0, 0, "back_out")))
    wings2(a, [(0, 0), (0.22, -5, "cubic_out"), (0.33, 10, "expo_out"), (0.55, 7), (0.95, 0)], stagger=0.03, fall=0.1)
    a.look((0, 0, 0), (0.32, 0.4, 0.1), (0.95, 0, 0))
    a.eyes((0, "open"), (0.7, "default"))
    a.att("mouth", (0.28, "open"), (0.55, "default"))
    a.fx("flash", (0.3, 0, "expo_out"), (0.33, 0.14, "cubic_out"), (0.48, 0))
    a.ev(0.2, "windup").ev(0.29, "vfx_thrust").ev(0.29, "swing").ev(0.34, "hit")
    return a


def ultimate():
    """She gathers (crouch, wings folded tight), rises on a great wingbeat with the spear spinning a
    full turn in her fist overhead, hangs in the air with it levelled and charging, then dives into
    the strike and lands, the spear riding back up to rest."""
    a = Anim("ultimate", 1.8, mix=0.08, mix_out=0.25)
    a.lunge((0, 0), (0.85, 0, "cubic_in"), (0.98, 1.0, "expo_out"), (1.35, 1.0, "cubic_in_out"), (1.8, 0))
    a.tr("root", (0, 0, 0), (0.32, 0, 14, "cubic_out"), (0.66, 0, -90, "back_out"), (0.92, 0, -84), (1.02, 0, 0, "expo_out"), (1.8, 0, 0))
    a.sc("root", (0, 1, 1), (0.32, 1.06, 0.92, "cubic_out"), (0.66, 0.97, 1.05, "back_out"), (0.92, 0.98, 1.04),
         (1.02, 1.06, 0.95, "expo_out"), (1.25, 1, 1))
    a.rot("root", (0, 0), (0.32, 2), (0.66, -3), (0.72, -2.2), (0.78, -3.4), (0.84, -2.4), (0.92, -3), (1.02, 7, "expo_out"), (1.35, 4), (1.8, 0))
    a.tr("hips", (0, 0, 0), (0.32, 0, 10, "cubic_out"), (0.66, 0, -4, "back_out"), (1.02, 4, -4, "expo_out"), (1.8, 0, 0))
    a.rot("torso", (0, 0), (0.32, 3), (0.67, -4, "back_out"), (1.03, 4, "expo_out"), (1.8, 0))
    a.sc("chest", (0, 1, 1), (0.32, 0.98, 0.96), (0.67, 1.04, 1.06, "back_out"), (1.05, 1, 1))
    a.rot("head", (0, 0), (0.33, 5), (0.68, -6, "back_out"), (1.04, 4, "expo_out"), (1.8, 0))
    a.rot("arm_l", (0, 0), (0.32, 4), (0.66, -8, "back_out"), (1.02, 6, "expo_out"), (1.8, 0))
    a.rot("forearm_l", (0, 0), (0.33, 3), (0.68, -6, "back_out"), (1.04, 5, "expo_out"), (1.8, 0))
    a.rot("arm_r", (0, 0), (0.32, -4), (0.66, 8, "back_out"), (1.02, -5, "expo_out"), (1.8, 0))
    a.rot("forearm_r", (0, 0), (0.33, -3), (0.68, 6, "back_out"), (1.04, -4, "expo_out"), (1.8, 0))
    # the spear: one full turn in her fist on the rise (the step key swaps 348 for the same angle -12),
    # levelled while she hangs, driven forward on the dive, ridden back up to rest
    a.rot("weapon", (0, 0), (0.32, -12, "cubic_out"), (0.64, 348, "step"), (0.6401, -12, "cubic_out"),
          (0.9, 40, "back_out"), (1.02, 46, "expo_out"), (1.4, 38), (1.8, 0, "cubic_in_out"))
    a.tr("weapon", (0, 0, 0), (0.32, 0, 10), (0.66, 0, -20, "back_out"),
         *along((0.9, 120, 40), (1.02, 400, 46, "expo_out"), (1.4, 330, 38), (1.8, 0, 0, "cubic_in_out")))
    wings2(a, [(0, 0), (0.32, -6, "cubic_out"), (0.62, 12, "back_out"), (0.7, 10), (0.76, 12), (0.82, 10.5),
               (0.9, 11.5), (1.02, -5, "expo_out"), (1.3, 1.5), (1.8, 0)], stagger=0.035, fall=0.1)
    a.look((0, 0, 0), (0.32, 0, 0.6), (0.66, -0.2, -0.7), (1.02, 0.45, 0.1), (1.8, 0, 0))
    a.eyes((0, "closed"), (0.6, "open"), (1.5, "default"))
    a.att("mouth", (0.6, "open"), (1.35, "default"))
    a.fx("aura", (0, 0), (0.6, 1.0), (1.15, 1.2), (1.8, 0))
    a.fx("glow", (0.66, 0), (0.9, 1.4), (1.02, 1.8), (1.35, 0))
    a.fx("flash", (0.95, 0, "expo_out"), (1.0, 0.6, "cubic_out"), (1.3, 0))
    a.ev(0.0, "ult_start").ev(0.1, "vfx_charge").ev(0.66, "ult_pose").ev(0.96, "release").ev(0.96, "vfx_burst").ev(1.02, "hit")
    return a


ALL = [attack_thrust, ultimate]

if __name__ == "__main__":
    for fn in ALL:
        print("wrote", os.path.relpath(fn().save(OUT)))
