"""HaloRig full-scale body kit: standard landmarks + limb outlines for 7.5-head anime figures.

Canvas 1024 x 2048, feet (soles) at y = 1990, head (crown to chin) ~254 units.
All heroes face screen-right in a 3/4 view. Side names are ANATOMICAL (the character's own):
  _r = her RIGHT = NEAR side = viewer's left  (closer to the camera, drawn in front)
  _l = her LEFT  = FAR side  = viewer's right (toward the enemy, partly behind the body)
Right-handed weapons go in hand_r (the near hand).
See docs/dev/art-style.md section 2 for the proportion chart these numbers come from.
"""
import math
from art_svgkit import smooth, sample, f

H = 254.0  # head height (crown to chin)

# Standard female landmarks (Seraphiel). Male heroes: see MALE_DELTA.
FEMALE = {
    "crown": (526, 108), "chin": (548, 362), "skull_c": (528, 228),
    "eye_r": (494, 250), "eye_l": (577, 248), "nose": (571, 298), "mouth": (559, 330),
    "neck_base": (540, 448), "neck_back": (470, 412),
    "shoulder_r": (418, 488), "shoulder_l": (624, 478),
    "elbow_r": (392, 830), "wrist_r": (412, 1096),
    "elbow_l": (652, 812), "wrist_l": (690, 1078),
    "chest_c": (540, 600), "waist_c": (530, 835), "pelvis_c": (520, 1060),
    "hip_r": (452, 1092), "hip_l": (590, 1110),
    "knee_r": (464, 1545), "ankle_r": (478, 1922),
    "knee_l": (586, 1556), "ankle_l": (614, 1912),
    "toe_r": (552, 1988), "toe_l": (690, 1984),
}

# Typical male deltas: +12% shoulder width, +6% height, narrower hips, thicker limbs.
MALE_DELTA = {"shoulder_spread": 1.18, "hip_spread": 0.9, "limb_width": 1.2, "height": 1.04}


def _norm(dx, dy):
    l = math.hypot(dx, dy) or 1.0
    return dx / l, dy / l


def limb(a, b, prof_left, prof_right, cap_a=0.6, cap_b=0.6, n_cap=3):
    """Closed outline of a limb segment from joint a to joint b.

    prof_left / prof_right: list of (t, half_width) along a->b (t 0..1), for the contour on
    the LEFT of the a->b direction and the RIGHT of it (screen sense when a->b points down:
    left contour = viewer's right... use the returned points, don't think too hard).
    cap_a / cap_b: how far (fraction of the end half-width) the rounded caps extend past the
    joints, so rotated joints overlap without gaps."""
    ax, ay = a
    bx, by = b
    dx, dy = _norm(bx - ax, by - ay)
    nx, ny = -dy, dx  # left normal
    L = math.hypot(bx - ax, by - ay)
    left = []
    right = []
    for t, w in prof_left:
        left.append((ax + dx * L * t + nx * w, ay + dy * L * t + ny * w))
    for t, w in prof_right:
        right.append((ax + dx * L * t - nx * w, ay + dy * L * t - ny * w))
    # caps
    wa = (prof_left[0][1] + prof_right[0][1]) * 0.5
    wb = (prof_left[-1][1] + prof_right[-1][1]) * 0.5
    ca = (ax - dx * wa * cap_a, ay - dy * wa * cap_a)
    cb = (bx + dx * wb * cap_b, by + dy * wb * cap_b)
    pts = [ca] + left + [cb] + right[::-1]
    return pts


def limb_d(*args, **kw):
    return smooth(limb(*args, **kw), True, 1.0)


def along(a, b, t, off=0.0):
    """Point at fraction t from a to b, offset `off` along the left normal."""
    dx, dy = _norm(b[0] - a[0], b[1] - a[1])
    L = math.hypot(b[0] - a[0], b[1] - a[1])
    return (a[0] + dx * L * t - dy * off, a[1] + dy * L * t + dx * off)


def angle(a, b):
    return math.degrees(math.atan2(b[1] - a[1], b[0] - a[0]))
