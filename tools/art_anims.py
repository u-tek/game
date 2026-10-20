"""Source of the SHARED HaloRig animations -> assets/art/anim/<name>.anim.json.

    python3 tools/art_anims.py            # rewrite every shared animation
The JSON files are the engine-neutral deliverable (docs/dev/halorig.md section 5); this
script is just a compact way to author them. Per-hero overrides live in
assets/art/heroes/<id>/anim/ (see tools/art_anims_<id>.py).

Conventions (standard skeleton, character faces RIGHT, y down):
  * rotate: degrees, offset from the setup pose, POSITIVE = CLOCKWISE on screen.
    A hanging arm (pointing down) raised forward toward the enemy is NEGATIVE (-90 = level).
  * translate: rig units (canvas px), offset in the parent bone's space.
  * scale: multiplier on the setup scale.
  * _r = character's right = NEAR side (weapon hand), _l = far side.
"""
import json
import os

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "art", "anim")


def K(t, v, e="sine_in_out"):
    return {"t": round(t, 3), "v": v, "e": e}


def T(t, x, y, e="sine_in_out"):
    return {"t": round(t, 3), "x": x, "y": y, "e": e}


def keys(kind, pts, e="sine_in_out"):
    """pts: [(t, v[, ease])] for rotate/bend/fx, [(t, x, y[, ease])] for translate/scale/look."""
    out = []
    for p in pts:
        if kind in ("rotate", "bend", "fx"):
            out.append(K(p[0], p[1], p[2] if len(p) > 2 else e))
        else:
            out.append(T(p[0], p[1], p[2], p[3] if len(p) > 3 else e))
    return out


class Anim:
    def __init__(self, name, duration, loop=False, mix=0.12, mix_out=0.15, hold=False, loop_start=None):
        self.d = {"name": name, "duration": duration, "loop": loop, "mix": mix, "mix_out": mix_out}
        if hold:
            self.d["hold"] = True
        if loop_start is not None:
            self.d["loop_start"] = loop_start
        self.d["bones"] = {}
        self.d["slots"] = {}
        self.d["fx"] = {}
        self.d["events"] = []

    def rot(self, bone, *pts, e="sine_in_out"):
        self.d["bones"].setdefault(bone, {})["rotate"] = keys("rotate", pts, e)
        return self

    def tr(self, bone, *pts, e="sine_in_out"):
        self.d["bones"].setdefault(bone, {})["translate"] = keys("translate", pts, e)
        return self

    def sc(self, bone, *pts, e="sine_in_out"):
        self.d["bones"].setdefault(bone, {})["scale"] = keys("scale", pts, e)
        return self

    def att(self, slot, *pts):
        self.d["slots"].setdefault(slot, {})["attachment"] = [{"t": t, "v": v} for t, v in pts]
        return self

    def eyes(self, *pts):
        self.att("eye_l", *pts)
        self.att("eye_r", *pts)
        self.att("eyes", *pts)       # warp rigs: one overlay slot for both eyes
        return self

    def col(self, slot, *pts):
        self.d["slots"].setdefault(slot, {})["color"] = [{"t": p[0], "c": p[1], "e": p[2] if len(p) > 2 else "linear"} for p in pts]
        return self

    def look(self, *pts, e="sine_in_out"):
        self.d["look"] = keys("look", pts, e)
        return self

    def fx(self, name, *pts, e="sine_in_out"):
        self.d["fx"][name] = keys("fx", pts, e)
        return self

    def lunge(self, *pts, e="sine_in_out"):
        self.d["lunge"] = keys("fx", pts, e)
        return self

    def ev(self, t, name):
        self.d["events"].append({"t": t, "name": name})
        return self

    def save(self, out_dir=OUT):
        os.makedirs(out_dir, exist_ok=True)
        if not self.d["fx"]:
            del self.d["fx"]
        if not self.d["slots"]:
            del self.d["slots"]
        self.d["events"].sort(key=lambda e: e["t"])
        p = os.path.join(out_dir, self.d["name"] + ".anim.json")
        with open(p, "w") as fh:
            json.dump(self.d, fh, indent=1)
            fh.write("\n")
        return p


S = "sine_in_out"


def idle():
    a = Anim("idle", 3.2, loop=True, mix=0.25)
    a.tr("hips", (0, 0, 0), (1.6, 0, 7), (3.2, 0, 0))
    a.rot("torso", (0, 0), (1.7, 0.8), (3.2, 0))
    a.rot("chest", (0, 0), (1.5, -0.7), (3.2, 0))
    a.sc("chest_upper", (0, 1, 1), (1.4, 1.006, 1.016), (3.2, 1, 1))
    a.tr("chest_upper", (0, 0, 0), (1.4, 0, -3), (3.2, 0, 0))
    a.tr("clavicle_r", (0, 0, 0), (1.5, 0, -4), (3.2, 0, 0))
    a.tr("clavicle_l", (0, 0, 0), (1.5, 0, -3), (3.2, 0, 0))
    a.rot("neck", (0, 0), (1.9, 0.8), (3.2, 0))
    a.rot("head", (0, 0), (0.9, -0.8), (2.3, 1.6), (3.2, 0))
    a.rot("arm_upper_r", (0, 0), (1.6, -1.4), (3.2, 0))
    a.rot("arm_lower_r", (0, 0), (1.8, -2.5), (3.2, 0))
    a.rot("hand_r", (0, 0), (2.0, -4), (3.2, 0))
    a.rot("arm_upper_l", (0, 0), (1.6, 1.2), (3.2, 0))
    a.rot("arm_lower_l", (0, 0), (1.8, 2.0), (3.2, 0))
    a.rot("hand_l", (0, 0), (2.0, 3), (3.2, 0))
    a.rot("thigh_l", (0, 0), (1.6, 0.6), (3.2, 0))
    a.tr("weapon", (0, 0, 0), (1.6, 0, -16), (3.2, 0, 0))
    a.rot("weapon", (0, 0), (1.2, 1.5), (2.6, -1.0), (3.2, 0))
    a.look((0, 0, 0), (1.2, 0.06, 0.04), (2.6, -0.04, 0), (3.2, 0, 0))
    return a


def attack_melee():
    a = Anim("attack_melee", 0.8, mix=0.06, mix_out=0.2)
    a.lunge((0, 0, "cubic_in"), (0.16, -0.05, "quint_out"), (0.3, 1.0, S), (0.52, 1.0, "cubic_in_out"), (0.8, 0))
    a.tr("hips", (0, 0, 0), (0.16, 0, 16, "cubic_out"), (0.3, 0, -8, "quint_out"), (0.45, 0, 12), (0.8, 0, 0))
    a.rot("torso", (0, 0), (0.16, -9, "cubic_out"), (0.24, -10, "expo_out"), (0.34, 11), (0.48, 9), (0.8, 0))
    a.rot("chest", (0, 0), (0.16, -6, "cubic_out"), (0.24, -7, "expo_out"), (0.34, 8), (0.8, 0))
    a.rot("head", (0, 0), (0.16, -4), (0.34, 5), (0.8, 0))
    a.rot("arm_upper_r", (0, 0), (0.16, -190, "cubic_out"), (0.25, -205, "expo_out"), (0.34, -42), (0.48, -34), (0.8, 0))
    a.rot("arm_lower_r", (0, 0), (0.16, -32, "cubic_out"), (0.25, -40, "expo_out"), (0.34, -6), (0.48, -12), (0.8, 0))
    a.rot("hand_r", (0, 0), (0.16, -20), (0.25, -24, "expo_out"), (0.34, 16), (0.8, 0))
    a.rot("arm_upper_l", (0, 0), (0.16, -30), (0.34, 22), (0.8, 0))
    a.rot("arm_lower_l", (0, 0), (0.16, -25), (0.34, -5), (0.8, 0))
    a.rot("thigh_r", (0, 0), (0.16, -5), (0.32, -16, "back_out"), (0.5, -13), (0.8, 0))
    a.rot("shin_r", (0, 0), (0.32, 12, "back_out"), (0.8, 0))
    a.rot("thigh_l", (0, 0), (0.32, 12), (0.8, 0))
    a.rot("shin_l", (0, 0), (0.32, 8), (0.8, 0))
    a.look((0, 0, 0), (0.3, 0.3, 0.2), (0.8, 0, 0))
    a.eyes((0, "open"), (0.62, "default"))
    a.att("mouth", (0.24, "open"), (0.5, "default"))
    a.fx("trail", (0.25, 0, "step"), (0.26, 1, "linear"), (0.4, 1, "linear"), (0.46, 0))
    a.ev(0.26, "swing").ev(0.33, "hit").ev(0.3, "step")
    return a


def attack_thrust():
    a = Anim("attack_thrust", 0.8, mix=0.06, mix_out=0.2)
    a.lunge((0, 0), (0.18, -0.08, "cubic_out"), (0.31, 1.0, "expo_out"), (0.52, 1.0, "cubic_in_out"), (0.8, 0))
    a.tr("hips", (0, 0, 0), (0.18, 0, 18), (0.31, 0, 4, "expo_out"), (0.8, 0, 0))
    a.rot("torso", (0, 0), (0.18, -8, "cubic_out"), (0.31, 13, "expo_out"), (0.5, 11), (0.8, 0))
    a.rot("chest", (0, 0), (0.18, -5), (0.31, 6, "expo_out"), (0.8, 0))
    a.rot("arm_upper_r", (0, 0), (0.18, 28, "cubic_out"), (0.31, -78, "expo_out"), (0.5, -74), (0.8, 0))
    a.rot("arm_lower_r", (0, 0), (0.18, -105, "cubic_out"), (0.31, -8, "expo_out"), (0.5, -12), (0.8, 0))
    a.rot("hand_r", (0, 0), (0.18, 10), (0.31, -4), (0.8, 0))
    a.rot("weapon", (0, 0), (0.18, 70, "cubic_out"), (0.31, 88, "expo_out"), (0.5, 86), (0.8, 0))
    a.rot("arm_upper_l", (0, 0), (0.18, -50), (0.31, -70, "expo_out"), (0.8, 0))
    a.rot("arm_lower_l", (0, 0), (0.18, -70), (0.31, -20, "expo_out"), (0.8, 0))
    a.rot("thigh_r", (0, 0), (0.31, -20, "back_out"), (0.8, 0))
    a.rot("shin_r", (0, 0), (0.31, 16, "back_out"), (0.8, 0))
    a.rot("thigh_l", (0, 0), (0.31, 16), (0.8, 0))
    a.look((0, 0, 0), (0.3, 0.35, 0.1), (0.8, 0, 0))
    a.eyes((0, "open"), (0.62, "default"))
    a.att("mouth", (0.26, "open"), (0.5, "default"))
    a.fx("trail", (0.26, 0, "step"), (0.27, 1, "linear"), (0.36, 1, "linear"), (0.42, 0))
    a.ev(0.27, "swing").ev(0.32, "hit")
    return a


def attack_ranged():
    a = Anim("attack_ranged", 0.9, mix=0.08, mix_out=0.2)
    a.tr("hips", (0, 0, 0), (0.25, 0, 10), (0.42, 0, -4, "expo_out"), (0.9, 0, 0))
    a.rot("torso", (0, 0), (0.25, -5), (0.42, 6, "expo_out"), (0.9, 0))
    a.rot("chest", (0, 0), (0.25, -3), (0.42, 4, "expo_out"), (0.9, 0))
    a.rot("head", (0, 0), (0.25, -3), (0.42, 3), (0.9, 0))
    a.rot("arm_upper_l", (0, 0), (0.25, -58, "cubic_out"), (0.42, -82, "expo_out"), (0.6, -76), (0.9, 0))
    a.rot("arm_lower_l", (0, 0), (0.25, -30, "cubic_out"), (0.42, -6, "expo_out"), (0.9, 0))
    a.rot("hand_l", (0, 0), (0.25, -15), (0.42, -25, "expo_out"), (0.9, 0))
    a.rot("arm_upper_r", (0, 0), (0.25, -40, "cubic_out"), (0.42, 15, "expo_out"), (0.9, 0))
    a.rot("arm_lower_r", (0, 0), (0.25, -50), (0.42, -20), (0.9, 0))
    a.tr("weapon", (0, 0, 0), (0.25, -20, -30, "cubic_out"), (0.42, 40, -10, "expo_out"), (0.9, 0, 0))
    a.rot("weapon", (0, 0), (0.25, -12), (0.42, 20, "expo_out"), (0.9, 0))
    a.look((0, 0, 0), (0.25, 0.3, -0.1), (0.42, 0.45, 0.1), (0.9, 0, 0))
    a.eyes((0, "open"), (0.7, "default"))
    a.att("mouth", (0.38, "open"), (0.6, "default"))
    a.fx("glow", (0.05, 0), (0.36, 1.0, "expo_out"), (0.44, 1.3, "cubic_out"), (0.62, 0))
    a.fx("flash", (0.38, 0, "expo_out"), (0.42, 0.25, "cubic_out"), (0.56, 0))
    a.ev(0.4, "release").ev(0.46, "hit")
    return a


def cast():
    a = Anim("cast", 1.0, mix=0.1, mix_out=0.22)
    a.tr("hips", (0, 0, 0), (0.3, 0, 14), (0.55, 0, -24, "back_out"), (1.0, 0, 0))
    a.rot("torso", (0, 0), (0.3, 3), (0.55, -6, "back_out"), (1.0, 0))
    a.rot("chest", (0, 0), (0.3, 3), (0.55, -5, "back_out"), (1.0, 0))
    a.rot("head", (0, 0), (0.3, 6), (0.55, -6), (1.0, 0))
    a.rot("arm_upper_r", (0, 0), (0.3, -40), (0.55, -150, "back_out"), (0.75, -140), (1.0, 0))
    a.rot("arm_lower_r", (0, 0), (0.3, -60), (0.55, -10, "back_out"), (1.0, 0))
    a.rot("hand_r", (0, 0), (0.55, -20), (1.0, 0))
    a.rot("arm_upper_l", (0, 0), (0.3, -35), (0.55, -140, "back_out"), (0.75, -132), (1.0, 0))
    a.rot("arm_lower_l", (0, 0), (0.3, -55), (0.55, -8, "back_out"), (1.0, 0))
    a.tr("weapon", (0, 0, 0), (0.3, 0, 20), (0.55, 20, -90, "back_out"), (1.0, 0, 0))
    a.look((0, 0, 0), (0.3, 0.1, 0.4), (0.55, 0.2, -0.6), (1.0, 0, 0))
    a.eyes((0, "closed"), (0.45, "open"), (0.85, "default"))
    a.att("mouth", (0.45, "open"), (0.8, "default"))
    a.fx("hand_glow", (0.05, 0), (0.45, 1.0, "cubic_in"), (0.6, 1.2), (0.85, 0))
    a.fx("aura", (0, 0), (0.4, 1.0), (0.8, 0.6), (1.0, 0))
    a.fx("glow", (0.2, 0), (0.5, 1.0), (0.7, 0))
    a.fx("flash", (0.5, 0, "expo_out"), (0.55, 0.3, "cubic_out"), (0.75, 0))
    a.ev(0.55, "release").ev(0.6, "hit")
    return a


def support_cast():
    a = Anim("support_cast", 1.0, mix=0.1, mix_out=0.22)
    a.tr("hips", (0, 0, 0), (0.35, 0, 8), (0.6, 0, -12), (1.0, 0, 0))
    a.rot("head", (0, 0), (0.35, 8), (0.6, -3), (1.0, 0))
    a.rot("torso", (0, 0), (0.35, 2), (0.6, -3), (1.0, 0))
    a.rot("arm_upper_r", (0, 0), (0.35, -38), (0.6, -70, "back_out"), (1.0, 0))
    a.rot("arm_lower_r", (0, 0), (0.35, -95), (0.6, -25, "back_out"), (1.0, 0))
    a.rot("arm_upper_l", (0, 0), (0.35, -28), (0.6, -75, "back_out"), (1.0, 0))
    a.rot("arm_lower_l", (0, 0), (0.35, -90), (0.6, -20, "back_out"), (1.0, 0))
    a.rot("hand_r", (0, 0), (0.6, -25), (1.0, 0))
    a.rot("hand_l", (0, 0), (0.6, -25), (1.0, 0))
    a.look((0, 0, 0), (0.35, 0, 0.5), (0.6, 0.15, -0.3), (1.0, 0, 0))
    a.eyes((0, "closed"), (0.5, "open"), (0.85, "default"))
    a.att("mouth", (0.5, "smile"), (0.9, "default"))
    a.fx("hand_glow", (0.1, 0), (0.45, 0.9), (0.62, 1.3), (0.9, 0))
    a.fx("aura", (0, 0), (0.45, 0.8), (1.0, 0))
    a.ev(0.5, "release").ev(0.56, "hit")
    return a


def ultimate():
    a = Anim("ultimate", 1.7, mix=0.08, mix_out=0.25)
    a.lunge((0, 0), (0.8, 0, "cubic_in"), (0.93, 1.0, "expo_out"), (1.3, 1.0, "cubic_in_out"), (1.7, 0))
    a.tr("hips", (0, 0, 0), (0.32, 0, 34, "cubic_out"), (0.65, 0, -60, "back_out"), (0.88, 0, -54), (0.98, 0, 10, "expo_out"), (1.7, 0, 0))
    a.rot("torso", (0, 0), (0.32, 8), (0.65, -8, "back_out"), (0.88, -9), (0.98, 12, "expo_out"), (1.25, 9), (1.7, 0))
    a.rot("chest", (0, 0), (0.32, 6), (0.65, -6, "back_out"), (0.98, 8, "expo_out"), (1.7, 0))
    a.rot("head", (0, 0), (0.32, 10), (0.65, -8), (0.98, 4), (1.7, 0))
    a.rot("arm_upper_r", (0, 0), (0.32, -30), (0.65, -170, "back_out"), (0.88, -176), (0.98, -80, "expo_out"), (1.25, -70), (1.7, 0))
    a.rot("arm_lower_r", (0, 0), (0.32, -90), (0.65, -12, "back_out"), (0.98, -4, "expo_out"), (1.7, 0))
    a.rot("arm_upper_l", (0, 0), (0.32, -25), (0.65, -165, "back_out"), (0.88, -170), (0.98, -70, "expo_out"), (1.7, 0))
    a.rot("arm_lower_l", (0, 0), (0.32, -85), (0.65, -10, "back_out"), (0.98, -2, "expo_out"), (1.7, 0))
    a.rot("thigh_r", (0, 0), (0.32, -10), (0.65, 4), (0.98, -14, "expo_out"), (1.7, 0))
    a.rot("shin_r", (0, 0), (0.32, 18), (0.65, 4), (0.98, 10), (1.7, 0))
    a.rot("thigh_l", (0, 0), (0.32, -6), (0.65, 10), (0.98, 10), (1.7, 0))
    a.rot("shin_l", (0, 0), (0.32, 22), (0.65, 14), (1.7, 0))
    a.tr("weapon", (0, 0, 0), (0.32, 0, 30), (0.65, 0, -140, "back_out"), (0.98, 60, -20, "expo_out"), (1.7, 0, 0))
    a.rot("weapon", (0, 0), (0.65, -10), (0.98, 25, "expo_out"), (1.7, 0))
    a.look((0, 0, 0), (0.32, 0, 0.6), (0.65, -0.2, -0.7), (0.98, 0.45, 0.1), (1.7, 0, 0))
    a.eyes((0, "closed"), (0.6, "open"), (1.45, "default"))
    a.att("mouth", (0.6, "open"), (1.3, "default"))
    a.fx("aura", (0, 0), (0.6, 1.0), (1.1, 1.2), (1.7, 0))
    a.fx("hand_glow", (0.1, 0), (0.6, 1.2), (0.9, 1.4), (1.05, 0))
    a.fx("glow", (0.3, 0), (0.85, 1.4), (1.0, 1.8), (1.3, 0))
    a.fx("flash", (0.9, 0, "expo_out"), (0.96, 0.6, "cubic_out"), (1.25, 0))
    a.fx("trail", (0.9, 0, "step"), (0.91, 1, "linear"), (1.02, 1), (1.08, 0))
    a.ev(0.0, "ult_start").ev(0.65, "ult_pose").ev(0.92, "release").ev(0.98, "hit")
    return a


def hit():
    a = Anim("hit", 0.45, mix=0.03, mix_out=0.16)
    a.tr("root", (0, 0, 0, "expo_out"), (0.06, -46, 0), (0.45, 0, 0, "cubic_in_out"))
    a.tr("hips", (0, 0, 0), (0.06, 0, 10, "expo_out"), (0.45, 0, 0))
    a.rot("torso", (0, 0, "expo_out"), (0.06, -10), (0.2, -6, "back_out"), (0.45, 0))
    a.rot("chest", (0, 0, "expo_out"), (0.06, -6), (0.45, 0))
    a.rot("head", (0, 0, "expo_out"), (0.06, -13), (0.2, -5, "back_out"), (0.45, 0))
    a.rot("arm_upper_r", (0, 0, "expo_out"), (0.06, 14), (0.45, 0))
    a.rot("arm_lower_r", (0, 0, "expo_out"), (0.06, -14), (0.45, 0))
    a.rot("arm_upper_l", (0, 0, "expo_out"), (0.06, 16), (0.45, 0))
    a.rot("arm_lower_l", (0, 0, "expo_out"), (0.06, -10), (0.45, 0))
    a.look((0, 0, 0, "expo_out"), (0.06, -0.3, -0.3), (0.45, 0, 0))
    a.eyes((0, "hurt"), (0.3, "default"))
    a.att("mouth", (0, "hurt"), (0.3, "default"))
    a.fx("flash", (0, 0.85, "cubic_out"), (0.16, 0))
    a.ev(0.0, "impact")
    return a


def death():
    a = Anim("death", 1.6, mix=0.05, hold=True)
    a.tr("root", (0, 0, 0, "expo_out"), (0.08, -50, 0), (0.6, -70, 0), (1.6, -70, 0))
    a.tr("hips", (0, 0, 0, "expo_out"), (0.08, 0, 12), (0.18, 0, 0, "cubic_in"), (0.55, -10, 330, "cubic_in"), (0.62, -10, 318, "quad_out"), (0.9, -20, 420, "cubic_in"), (1.6, -20, 420))
    a.rot("thigh_r", (0, 0), (0.18, 0, "cubic_in"), (0.55, -62), (0.9, -70), (1.6, -70))
    a.rot("shin_r", (0, 0), (0.18, 0, "cubic_in"), (0.55, 105), (0.9, 112), (1.6, 112))
    a.rot("thigh_l", (0, 0), (0.18, 0, "cubic_in"), (0.55, -44), (0.9, -52), (1.6, -52))
    a.rot("shin_l", (0, 0), (0.18, 0, "cubic_in"), (0.55, 98), (0.9, 108), (1.6, 108))
    a.rot("torso", (0, 0, "expo_out"), (0.08, -12), (0.3, -4), (0.62, 14, "cubic_in"), (1.0, 34, "quad_out"), (1.6, 36))
    a.rot("chest", (0, 0, "expo_out"), (0.08, -6), (0.62, 8), (1.0, 16), (1.6, 18))
    a.rot("head", (0, 0, "expo_out"), (0.08, -16), (0.4, -6), (0.8, 22), (1.6, 26))
    a.rot("arm_upper_r", (0, 0, "expo_out"), (0.08, 18), (0.6, 4), (1.0, -12), (1.6, -14))
    a.rot("arm_lower_r", (0, 0), (0.08, -20), (0.6, -6), (1.6, -8))
    a.rot("arm_upper_l", (0, 0, "expo_out"), (0.08, 20), (0.6, 2), (1.0, -10), (1.6, -12))
    a.rot("arm_lower_l", (0, 0), (0.08, -16), (1.6, -4))
    a.tr("weapon", (0, 0, 0), (0.6, 30, 200, "cubic_in"), (1.0, 60, 520, "cubic_in"), (1.6, 60, 520))
    a.rot("weapon", (0, 0), (1.0, 50, "cubic_in"), (1.6, 50))
    a.look((0, 0, 0, "expo_out"), (0.08, -0.4, -0.4), (0.8, 0, 0.8), (1.6, 0, 0.8))
    a.eyes((0, "hurt"), (0.5, "closed"))
    a.att("mouth", (0, "hurt"), (0.6, "default"))
    a.fx("flash", (0, 0.9, "cubic_out"), (0.2, 0), (0.9, 0), (1.3, 0.35))
    a.fx("fade", (0, 0), (0.95, 0, "sine_in"), (1.55, 1.0))
    a.ev(0.0, "impact").ev(0.62, "thud").ev(1.55, "gone")
    return a


def victory():
    a = Anim("victory", 2.8, loop=True, loop_start=1.2, mix=0.15)
    a.tr("root", (0, 0, 0), (0.12, 0, 0, "cubic_out"), (0.3, 0, -70, "cubic_in"), (0.46, 0, 0), (2.8, 0, 0))
    a.tr("hips", (0, 0, 0), (0.12, 0, 22, "cubic_out"), (0.3, 0, -6), (0.5, 0, 16, "back_out"), (0.7, 0, 0), (2.0, 0, 6), (2.8, 0, 0))
    a.rot("torso", (0, 0), (0.12, 4), (0.4, -4), (0.7, -2), (2.0, -3), (2.8, -2))
    a.rot("head", (0, 0), (0.4, -5), (0.8, 3), (2.0, 5), (2.8, 3))
    a.rot("arm_upper_r", (0, 0), (0.12, 10), (0.45, -150, "back_out"), (1.2, -146), (2.0, -152), (2.8, -146))
    a.rot("arm_lower_r", (0, 0), (0.12, -20), (0.45, -30, "back_out"), (1.2, -26), (2.0, -34), (2.8, -26))
    a.rot("hand_r", (0, 0), (0.45, -10), (2.8, -10))
    a.rot("arm_upper_l", (0, 0), (0.45, -16, "back_out"), (2.0, -20), (2.8, -16))
    a.rot("arm_lower_l", (0, 0), (0.45, -30), (2.0, -36), (2.8, -30))
    a.look((0, 0, 0), (0.4, -0.55, -0.1), (1.2, -0.5, -0.1), (2.0, -0.6, 0), (2.8, -0.5, -0.1))
    a.eyes((0.3, "smile"))
    a.att("mouth", (0.3, "smile"))
    a.fx("aura", (0.3, 0), (0.6, 0.7), (1.2, 0.3), (2.0, 0.45), (2.8, 0.3))
    a.ev(0.12, "jump").ev(0.46, "land").ev(0.5, "cheer")
    return a


def stun():
    a = Anim("stun", 1.8, loop=True, mix=0.15)
    a.tr("hips", (0, 0, 10), (0.9, 0, 16), (1.8, 0, 10))
    a.rot("torso", (0, 4), (0.9, 6), (1.8, 4))
    a.rot("head", (0, 12), (0.6, 17), (1.2, 9), (1.8, 12))
    a.rot("neck", (0, 4), (0.9, 6), (1.8, 4))
    a.rot("arm_upper_r", (0, 5), (0.9, 8), (1.8, 5))
    a.rot("arm_lower_r", (0, 4), (0.9, 8), (1.8, 4))
    a.rot("arm_upper_l", (0, 6), (0.9, 9), (1.8, 6))
    a.look((0, 0, 0.5), (0.6, 0.2, 0.6), (1.2, -0.2, 0.5), (1.8, 0, 0.5))
    a.eyes((0, "hurt"))
    a.att("mouth", (0, "hurt"))
    return a


def hop():
    a = Anim("hop", 0.55, mix=0.06, mix_out=0.15)
    a.tr("root", (0, 0, 0), (0.12, 0, 0, "cubic_out"), (0.28, 0, -110, "cubic_in"), (0.44, 0, 0), (0.55, 0, 0))
    a.tr("hips", (0, 0, 0), (0.12, 0, 26, "cubic_out"), (0.28, 0, -8), (0.47, 0, 22, "back_out"), (0.55, 0, 0))
    a.rot("thigh_r", (0, 0), (0.12, -14), (0.28, -6), (0.47, -12), (0.55, 0))
    a.rot("shin_r", (0, 0), (0.12, 20), (0.28, 30), (0.47, 18), (0.55, 0))
    a.rot("thigh_l", (0, 0), (0.12, -10), (0.28, -20), (0.47, -8), (0.55, 0))
    a.rot("shin_l", (0, 0), (0.12, 18), (0.28, 40), (0.47, 16), (0.55, 0))
    a.rot("arm_upper_r", (0, 0), (0.12, 12), (0.28, -20), (0.55, 0))
    a.rot("arm_upper_l", (0, 0), (0.12, 10), (0.28, -24), (0.55, 0))
    a.ev(0.12, "jump").ev(0.44, "land")
    return a


def run():
    a = Anim("run", 0.56, loop=True, mix=0.12)
    a.rot("torso", (0, 8), (0.28, 9), (0.56, 8))
    a.tr("hips", (0, 0, 0, "quad_out"), (0.14, 0, -18, "quad_in"), (0.28, 0, 0, "quad_out"), (0.42, 0, -18, "quad_in"), (0.56, 0, 0))
    a.rot("thigh_r", (0, -34), (0.28, 26), (0.56, -34))
    a.rot("shin_r", (0, 22), (0.14, 70), (0.28, 12), (0.42, 40), (0.56, 22))
    a.rot("thigh_l", (0, 26), (0.28, -34), (0.56, 26))
    a.rot("shin_l", (0, 12), (0.14, 40), (0.28, 22), (0.42, 70), (0.56, 12))
    a.rot("arm_upper_r", (0, 22), (0.28, -26), (0.56, 22))
    a.rot("arm_lower_r", (0, -40), (0.28, -60), (0.56, -40))
    a.rot("arm_upper_l", (0, -22), (0.28, 20), (0.56, -22))
    a.rot("arm_lower_l", (0, -55), (0.28, -40), (0.56, -55))
    a.ev(0.0, "step").ev(0.28, "step")
    return a


# ======================================================================== WARP set
# For painted single-image heroes (warp rigs): whole-body actions built from root/hips/torso/
# chest/head transforms (squash & stretch about the feet, lean, lunge, recoil), breathing,
# wing flaps, weapon-region bob/thrust, overlay swaps, glows, and VFX hook events.
# Events named vfx_<kind> ask the battle screen to spawn an effect (HeroSprite.vfx_requested).
# Amplitude limits for one flat painting: head/neck rotation <= ~7 deg (long hair hangs from the
# head), weapon region <= ~30 px / 10 deg, wings <= ~7 deg, whole-body root tilt <= ~10 deg.
WARP_OUT = os.path.join(OUT, "warp")
WINGS = (("wing_upper_r", 1), ("wing_lower_r", -1), ("wing_upper_l", -1), ("wing_lower_l", 1), ("wing_r", 1), ("wing_l", -1))


def wings_flap(a, pts):
    """pts: [(t, amount)] - positive opens the upper wings."""
    for b, sg in WINGS:
        a.rot(b, *[(p[0], p[1] * sg) + tuple(p[2:]) for p in pts])


def w_idle():
    # Layered breathing (3.2 s) with a slower weight shift and head tilt on other phases, so the
    # loop never looks mechanical; springs (hair, tail, bust, cloth) ride on top of it.
    a = Anim("idle", 3.2, loop=True, mix=0.25)
    a.sc("chest", (0, 1, 1), (1.5, 1.022, 1.038), (3.2, 1, 1))
    a.tr("chest", (0, 0, 0), (1.5, 0, -6), (3.2, 0, 0))
    a.tr("hips", (0, 0, 0), (0.8, 4, 6), (1.6, 0, 10), (2.4, -4, 6), (3.2, 0, 0))
    a.rot("torso", (0, 0), (0.8, 1.0), (1.7, 1.4), (2.6, -0.6), (3.2, 0))
    a.rot("neck", (0, 0), (1.0, 0.8), (2.2, -0.6), (3.2, 0))
    a.rot("head", (0, 0), (0.9, -2.2), (2.1, 2.4), (3.2, 0))
    wings_flap(a, [(0, 0), (1.6, 4.0), (3.2, 0)])
    a.tr("weapon", (0, 0, 0), (1.6, 0, -18), (3.2, 0, 0))
    a.rot("weapon", (0, 0), (1.2, 2.2), (2.6, -1.4), (3.2, 0))
    a.rot("arm_l", (0, 0), (1.6, 2.0), (3.2, 0))
    a.rot("arm_r", (0, 0), (1.6, -2.0), (3.2, 0))
    a.look((0, 0, 0), (0.9, 0.1, 0.05), (2.1, -0.08, -0.02), (3.2, 0, 0))
    return a


def w_attack_melee():
    a = Anim("attack_melee", 0.8, mix=0.06, mix_out=0.2)
    a.lunge((0, 0), (0.15, -0.06, "quint_out"), (0.3, 1.0, S), (0.54, 1.0, "cubic_in_out"), (0.8, 0))
    a.sc("root", (0, 1, 1, "cubic_out"), (0.15, 1.06, 0.93, "expo_out"), (0.28, 0.94, 1.07), (0.38, 1.03, 0.97), (0.6, 1, 1))
    a.rot("root", (0, 0, "cubic_out"), (0.15, -5, "expo_out"), (0.3, 8), (0.45, 6), (0.75, 0))
    a.tr("hips", (0, 0, 0), (0.15, 0, 14, "expo_out"), (0.3, 0, -6), (0.8, 0, 0))
    a.rot("head", (0, 0), (0.15, -4), (0.32, 5), (0.8, 0))
    a.rot("weapon", (0, 0, "cubic_out"), (0.15, -7, "expo_out"), (0.32, 9), (0.5, 5), (0.8, 0))
    a.tr("weapon", (0, 0, 0, "cubic_out"), (0.15, -12, -8, "expo_out"), (0.32, 24, 4), (0.8, 0, 0))
    a.rot("arm_r", (0, 0), (0.15, 10), (0.32, -12), (0.8, 0))
    a.rot("hair_back", (0, 0), (0.3, -3), (0.8, 0))
    a.look((0, 0, 0), (0.3, 0.35, 0.2), (0.8, 0, 0))
    a.eyes((0, "open"), (0.62, "default"))
    a.att("mouth", (0.24, "open"), (0.5, "default"))
    a.fx("flash", (0.28, 0, "expo_out"), (0.31, 0.12, "cubic_out"), (0.45, 0))
    a.ev(0.15, "windup").ev(0.26, "vfx_slash").ev(0.26, "swing").ev(0.32, "hit").ev(0.3, "step")
    return a


def w_attack_thrust():
    a = Anim("attack_thrust", 0.8, mix=0.06, mix_out=0.2)
    a.lunge((0, 0), (0.18, -0.08, "cubic_out"), (0.31, 1.0, "expo_out"), (0.52, 1.0, "cubic_in_out"), (0.8, 0))
    a.sc("root", (0, 1, 1), (0.18, 1.04, 0.95, "expo_out"), (0.31, 1.08, 0.95), (0.45, 1.0, 1.0), (0.8, 1, 1))
    a.rot("root", (0, 0), (0.18, -6, "expo_out"), (0.31, 10), (0.5, 8), (0.8, 0))
    a.tr("weapon", (0, 0, 0), (0.18, -16, 0, "expo_out"), (0.31, 30, 0), (0.5, 26, 0), (0.8, 0, 0))
    a.rot("weapon", (0, 0), (0.18, -6), (0.31, 4), (0.8, 0))
    a.look((0, 0, 0), (0.3, 0.4, 0.1), (0.8, 0, 0))
    a.eyes((0, "open"), (0.62, "default"))
    a.att("mouth", (0.26, "open"), (0.5, "default"))
    a.ev(0.18, "windup").ev(0.27, "vfx_thrust").ev(0.27, "swing").ev(0.32, "hit")
    return a


def w_attack_ranged():
    a = Anim("attack_ranged", 0.9, mix=0.08, mix_out=0.2)
    a.sc("root", (0, 1, 1), (0.28, 1.03, 0.97), (0.42, 0.97, 1.04, "expo_out"), (0.6, 1, 1))
    a.rot("root", (0, 0), (0.28, -3.5), (0.42, 4, "expo_out"), (0.9, 0))
    a.tr("hips", (0, 0, 0), (0.28, 0, 8), (0.42, 0, -4, "expo_out"), (0.9, 0, 0))
    a.rot("head", (0, 0), (0.28, -3), (0.42, 3), (0.9, 0))
    a.rot("arm_l", (0, 0), (0.28, -6), (0.42, -9, "expo_out"), (0.9, 0))
    a.tr("weapon", (0, 0, 0), (0.28, -8, -14, "cubic_out"), (0.42, 22, -4, "expo_out"), (0.9, 0, 0))
    a.rot("weapon", (0, 0), (0.28, -5), (0.42, 8, "expo_out"), (0.9, 0))
    wings_flap(a, [(0, 0), (0.28, 4), (0.42, -2, "expo_out"), (0.9, 0)])
    a.look((0, 0, 0), (0.28, 0.3, -0.1), (0.42, 0.45, 0.1), (0.9, 0, 0))
    a.eyes((0, "open"), (0.72, "default"))
    a.att("mouth", (0.38, "open"), (0.6, "default"))
    a.fx("glow", (0.05, 0), (0.36, 1.0, "expo_out"), (0.44, 1.3, "cubic_out"), (0.62, 0))
    a.fx("flash", (0.38, 0, "expo_out"), (0.42, 0.22, "cubic_out"), (0.56, 0))
    a.ev(0.05, "charge").ev(0.4, "release").ev(0.4, "vfx_bolt").ev(0.48, "hit")
    return a


def w_cast():
    a = Anim("cast", 1.0, mix=0.1, mix_out=0.22)
    a.tr("root", (0, 0, 0), (0.3, 0, 10), (0.55, 0, -42, "back_out"), (0.8, 0, -30), (1.0, 0, 0))
    a.sc("root", (0, 1, 1), (0.3, 1.03, 0.97), (0.55, 0.98, 1.03, "back_out"), (1.0, 1, 1))
    a.rot("head", (0, 0), (0.3, 5), (0.55, -5), (1.0, 0))
    a.sc("chest", (0, 1, 1), (0.55, 1.03, 1.04), (1.0, 1, 1))
    a.rot("arm_l", (0, 0), (0.3, -4), (0.55, -10, "back_out"), (1.0, 0))
    a.tr("weapon", (0, 0, 0), (0.3, 0, 8), (0.55, 8, -30, "back_out"), (1.0, 0, 0))
    wings_flap(a, [(0, 0), (0.3, -3), (0.55, 6, "back_out"), (1.0, 0)])
    a.look((0, 0, 0), (0.3, 0.1, 0.4), (0.55, 0.2, -0.6), (1.0, 0, 0))
    a.eyes((0, "closed"), (0.45, "open"), (0.85, "default"))
    a.att("mouth", (0.45, "open"), (0.8, "default"))
    a.fx("hand_glow", (0.05, 0), (0.45, 1.0, "cubic_in"), (0.6, 1.2), (0.85, 0))
    a.fx("aura", (0, 0), (0.4, 1.0), (0.8, 0.6), (1.0, 0))
    a.fx("glow", (0.2, 0), (0.5, 1.0), (0.7, 0))
    a.fx("flash", (0.5, 0, "expo_out"), (0.55, 0.3, "cubic_out"), (0.75, 0))
    a.ev(0.05, "charge").ev(0.55, "release").ev(0.55, "vfx_burst").ev(0.6, "hit")
    return a


def w_support_cast():
    a = Anim("support_cast", 1.0, mix=0.1, mix_out=0.22)
    a.tr("root", (0, 0, 0), (0.35, 0, 6), (0.6, 0, -24), (1.0, 0, 0))
    a.rot("head", (0, 0), (0.35, 6), (0.6, -3), (1.0, 0))
    a.sc("chest", (0, 1, 1), (0.35, 0.99, 0.98), (0.6, 1.03, 1.04), (1.0, 1, 1))
    wings_flap(a, [(0, 0), (0.35, -2), (0.6, 5), (1.0, 0)])
    a.look((0, 0, 0), (0.35, 0, 0.5), (0.6, 0.15, -0.3), (1.0, 0, 0))
    a.eyes((0, "closed"), (0.5, "open"), (0.85, "default"))
    a.att("mouth", (0.5, "smile"), (0.9, "default"))
    a.fx("hand_glow", (0.1, 0), (0.45, 0.9), (0.62, 1.3), (0.9, 0))
    a.fx("aura", (0, 0), (0.45, 0.8), (1.0, 0))
    a.ev(0.5, "release").ev(0.5, "vfx_sparkle").ev(0.56, "hit")
    return a


def w_ultimate():
    a = Anim("ultimate", 1.7, mix=0.08, mix_out=0.25)
    a.lunge((0, 0), (0.8, 0, "cubic_in"), (0.93, 1.0, "expo_out"), (1.3, 1.0, "cubic_in_out"), (1.7, 0))
    a.tr("root", (0, 0, 0), (0.32, 0, 12, "cubic_out"), (0.65, 0, -86, "back_out"), (0.88, 0, -80), (0.98, 0, 0, "expo_out"), (1.7, 0, 0))
    a.sc("root", (0, 1, 1), (0.32, 1.06, 0.92, "cubic_out"), (0.65, 0.97, 1.05, "back_out"), (0.88, 0.98, 1.04),
         (0.98, 1.06, 0.95, "expo_out"), (1.2, 1, 1))
    a.rot("root", (0, 0), (0.32, 2), (0.65, -3), (0.7, -2.2), (0.75, -3.4), (0.8, -2.4), (0.88, -3), (0.98, 7, "expo_out"), (1.3, 4), (1.7, 0))
    a.rot("head", (0, 0), (0.32, 5), (0.65, -5), (0.98, 3), (1.7, 0))
    a.sc("chest", (0, 1, 1), (0.65, 1.04, 1.05), (1.0, 1, 1))
    a.rot("arm_l", (0, 0), (0.32, 4), (0.65, -12, "back_out"), (0.98, -5, "expo_out"), (1.7, 0))
    a.tr("weapon", (0, 0, 0), (0.32, 0, 10), (0.65, 0, -40, "back_out"), (0.98, 26, -8, "expo_out"), (1.7, 0, 0))
    a.rot("weapon", (0, 0), (0.65, -5), (0.98, 8, "expo_out"), (1.7, 0))
    wings_flap(a, [(0, 0), (0.32, -3), (0.65, 7, "back_out"), (0.88, 6), (0.98, -3, "expo_out"), (1.7, 0)])
    a.look((0, 0, 0), (0.32, 0, 0.6), (0.65, -0.2, -0.7), (0.98, 0.45, 0.1), (1.7, 0, 0))
    a.eyes((0, "closed"), (0.6, "open"), (1.45, "default"))
    a.att("mouth", (0.6, "open"), (1.3, "default"))
    a.fx("aura", (0, 0), (0.6, 1.0), (1.1, 1.2), (1.7, 0))
    a.fx("hand_glow", (0.1, 0), (0.6, 1.2), (0.9, 1.4), (1.05, 0))
    a.fx("glow", (0.3, 0), (0.85, 1.4), (1.0, 1.8), (1.3, 0))
    a.fx("flash", (0.9, 0, "expo_out"), (0.96, 0.6, "cubic_out"), (1.25, 0))
    a.ev(0.0, "ult_start").ev(0.1, "vfx_charge").ev(0.65, "ult_pose").ev(0.92, "release").ev(0.92, "vfx_burst").ev(0.98, "hit")
    return a


def w_hit():
    a = Anim("hit", 0.45, mix=0.03, mix_out=0.16)
    a.tr("root", (0, 0, 0, "expo_out"), (0.06, -46, 0), (0.45, 0, 0, "cubic_in_out"))
    a.rot("root", (0, 0, "expo_out"), (0.06, -6), (0.22, -2, "back_out"), (0.45, 0))
    a.sc("root", (0, 1, 1, "expo_out"), (0.06, 0.96, 1.03), (0.2, 1.02, 0.98), (0.45, 1, 1))
    a.rot("head", (0, 0, "expo_out"), (0.06, -6), (0.2, -2, "back_out"), (0.45, 0))
    wings_flap(a, [(0, 0, "expo_out"), (0.06, 6), (0.45, 0)])
    a.look((0, 0, 0, "expo_out"), (0.06, -0.3, -0.3), (0.45, 0, 0))
    a.eyes((0, "hurt"), (0.3, "default"))
    a.att("mouth", (0, "hurt"), (0.3, "default"))
    a.fx("flash", (0, 0.85, "cubic_out"), (0.16, 0))
    a.ev(0.0, "impact")
    return a


def w_death():
    a = Anim("death", 1.6, mix=0.05, hold=True)
    a.tr("root", (0, 0, 0, "expo_out"), (0.08, -46, 0), (0.6, -54, 12, "cubic_in"), (1.0, -56, 30), (1.6, -56, 30))
    a.rot("root", (0, 0, "expo_out"), (0.08, -5), (0.3, -2), (0.7, -4, "cubic_in"), (1.6, -4.5))
    a.sc("root", (0, 1, 1, "expo_out"), (0.08, 0.96, 1.03), (0.3, 1, 1), (0.9, 1.03, 0.9, "cubic_in"), (1.6, 1.03, 0.88))
    a.rot("head", (0, 0, "expo_out"), (0.08, -6), (0.4, -2), (0.9, 6), (1.6, 7))
    a.rot("neck", (0, 0), (0.9, 2), (1.6, 2))
    wings_flap(a, [(0, 0, "expo_out"), (0.08, 4), (0.9, -6, "cubic_in"), (1.6, -7)])
    a.tr("weapon", (0, 0, 0), (0.6, 4, 16, "cubic_in"), (1.0, 6, 30, "cubic_in"), (1.6, 6, 30))
    a.rot("weapon", (0, 0), (1.0, 6, "cubic_in"), (1.6, 6))
    a.look((0, 0, 0, "expo_out"), (0.08, -0.4, -0.4), (0.8, 0, 0.8), (1.6, 0, 0.8))
    a.eyes((0, "hurt"), (0.5, "closed"))
    a.att("mouth", (0, "hurt"), (0.6, "default"))
    a.fx("flash", (0, 0.9, "cubic_out"), (0.2, 0), (0.9, 0), (1.3, 0.35))
    a.fx("fade", (0, 0), (0.85, 0, "sine_in"), (1.5, 1.0))
    a.ev(0.0, "impact").ev(0.85, "vfx_dissolve").ev(1.5, "gone")
    return a


def w_victory():
    a = Anim("victory", 2.8, loop=True, loop_start=1.2, mix=0.15)
    a.tr("root", (0, 0, 0), (0.12, 0, 0, "cubic_out"), (0.3, 0, -70, "cubic_in"), (0.46, 0, 0), (2.8, 0, 0))
    a.sc("root", (0, 1, 1), (0.12, 1.06, 0.93, "cubic_out"), (0.3, 0.96, 1.05), (0.48, 1.05, 0.95, "back_out"), (0.7, 1, 1))
    a.tr("hips", (0, 0, 0), (1.2, 0, 0), (2.0, 0, 8), (2.8, 0, 0))
    a.rot("head", (0, 0), (0.4, -4), (0.8, 3), (2.0, 5), (2.8, 3))
    a.rot("arm_l", (0, 0), (0.45, -12, "back_out"), (2.0, -14), (2.8, -12))
    wings_flap(a, [(0, 0), (0.3, 6), (0.6, 3, "back_out"), (2.0, 4.5), (2.8, 3)])
    a.look((0, 0, 0), (0.4, -0.5, -0.1), (1.2, -0.45, -0.1), (2.0, -0.55, 0), (2.8, -0.45, -0.1))
    a.eyes((0.3, "smile"))
    a.att("mouth", (0.3, "smile"))
    a.fx("aura", (0.3, 0), (0.6, 0.7), (1.2, 0.3), (2.0, 0.45), (2.8, 0.3))
    a.ev(0.12, "jump").ev(0.46, "land").ev(0.5, "cheer").ev(0.5, "vfx_sparkle")
    return a


def w_stun():
    a = Anim("stun", 1.8, loop=True, mix=0.15)
    a.rot("root", (0, 1.5), (0.9, -1.5), (1.8, 1.5))
    a.tr("hips", (0, 0, 10), (0.9, 0, 16), (1.8, 0, 10))
    a.rot("head", (0, 5), (0.6, 7), (1.2, 4), (1.8, 5))
    wings_flap(a, [(0, -6), (0.9, -8), (1.8, -6)])
    a.look((0, 0, 0.5), (0.6, 0.2, 0.6), (1.2, -0.2, 0.5), (1.8, 0, 0.5))
    a.eyes((0, "hurt"))
    a.att("mouth", (0, "hurt"))
    return a


def w_hop():
    a = Anim("hop", 0.55, mix=0.06, mix_out=0.15)
    a.tr("root", (0, 0, 0), (0.12, 0, 0, "cubic_out"), (0.28, 0, -110, "cubic_in"), (0.44, 0, 0), (0.55, 0, 0))
    a.sc("root", (0, 1, 1), (0.12, 1.07, 0.92, "cubic_out"), (0.28, 0.95, 1.06), (0.47, 1.06, 0.93, "back_out"), (0.55, 1, 1))
    wings_flap(a, [(0, 0), (0.12, -4), (0.28, 7), (0.47, -2), (0.55, 0)])
    a.ev(0.12, "jump").ev(0.44, "land")
    return a


def w_run():
    a = Anim("run", 0.5, loop=True, mix=0.12)
    a.rot("root", (0, 7), (0.25, 8), (0.5, 7))
    a.tr("root", (0, 0, 0, "quad_out"), (0.125, 0, -18, "quad_in"), (0.25, 0, 0, "quad_out"), (0.375, 0, -18, "quad_in"), (0.5, 0, 0))
    a.sc("root", (0, 1.03, 0.97), (0.125, 0.98, 1.02), (0.25, 1.03, 0.97), (0.375, 0.98, 1.02), (0.5, 1.03, 0.97))
    wings_flap(a, [(0, 0), (0.25, 6), (0.5, 0)])
    a.ev(0.0, "step").ev(0.25, "step")
    return a


WARP_ALL = [w_idle, w_attack_melee, w_attack_thrust, w_attack_ranged, w_cast, w_support_cast, w_ultimate, w_hit,
            w_death, w_victory, w_stun, w_hop, w_run]


# Format 2 warp rigs (per-part rigs, docs/dev/halorig.md 11): the idle is procedural
# (RigPlayer._idle_drive: breathing, weight shift, wings, planted legs), so their idle animation
# only keeps the base track looping. Their actions key the per-part skeleton: each wing on its own
# (wing_r1..3 on her right, wing_l1..3 on her left, top to bottom; lower wings follow later and a
# little less), upper arms and forearms, chest and head trailing the hips. Breasts, hair, braids,
# halo and earrings follow through on their springs. Animations missing here come from the warp set.
WARP2_OUT = os.path.join(OUT, "warp2")
WINGS2 = [("wing_r1", 1), ("wing_r2", 1), ("wing_r3", 1), ("wing_l1", -1), ("wing_l2", -1), ("wing_l3", -1),
          ("wing_r", 1), ("wing_l", -1)]


def wings2(a, pts, stagger=0.03, fall=0.15):
    """pts: [(t, lift deg[, ease])]; positive opens every wing (her right wings turn clockwise, her
    left ones counter-clockwise). Wing n starts (n-1)*stagger later and lifts (n-1)*fall less."""
    end = a.d["duration"]
    for name, sg in WINGS2:
        rank = int(name[-1]) - 1 if name[-1].isdigit() else 0
        dt = stagger * rank
        k = 1.0 - fall * rank
        ks = []
        for p in pts:
            t = p[0] if p[0] <= 0 else min(p[0] + dt, end)
            if ks and t <= ks[-1][0]:
                continue
            ks.append((t, round(p[1] * sg * k, 2)) + tuple(p[2:]))
        a.rot(name, *ks)


def w2_idle():
    return Anim("idle", 4.0, loop=True, mix=0.3)


def w2_attack_thrust():
    """Spear strike: she sinks and draws the spear back as all six wings fold in, then drives forward
    off the back foot - hips first, chest, then head and spear arm - the wings flaring open one
    after another; she holds the strike a beat and settles back with a small overshoot."""
    a = Anim("attack_thrust", 0.85, mix=0.06, mix_out=0.22)
    a.lunge((0, 0), (0.2, -0.1, "cubic_out"), (0.31, 1.0, "expo_out"), (0.52, 1.0, "cubic_in_out"), (0.85, 0))
    a.sc("root", (0, 1, 1), (0.2, 1.05, 0.95, "expo_out"), (0.3, 0.95, 1.06, "expo_out"), (0.42, 1.01, 0.99), (0.6, 1, 1))
    a.rot("root", (0, 0), (0.2, -5, "cubic_out"), (0.31, 9, "expo_out"), (0.5, 7), (0.85, 0))
    a.tr("hips", (0, 0, 0), (0.2, -4, 14, "cubic_out"), (0.31, 6, -6, "expo_out"), (0.5, 4, -2), (0.85, 0, 0))
    a.rot("torso", (0, 0), (0.2, -3), (0.32, 4, "expo_out"), (0.6, 1.5), (0.85, 0))
    a.tr("chest", (0, 0, 0), (0.2, -3, 4, "cubic_out"), (0.32, 4, -6, "expo_out"), (0.6, 1, -1), (0.85, 0, 0))
    a.sc("chest", (0, 1, 1), (0.2, 0.99, 0.97), (0.32, 1.02, 1.04, "expo_out"), (0.6, 1, 1))
    a.rot("head", (0, 0), (0.21, -5, "cubic_out"), (0.34, 4, "expo_out"), (0.56, 2), (0.85, 0))
    a.rot("arm_l", (0, 0), (0.2, -8, "cubic_out"), (0.31, 10, "expo_out"), (0.5, 7), (0.85, 0))
    a.rot("forearm_l", (0, 0), (0.21, -6, "cubic_out"), (0.33, 9, "expo_out"), (0.85, 0))
    a.rot("arm_r", (0, 0), (0.2, 5, "cubic_out"), (0.32, -6, "expo_out"), (0.85, 0))
    a.rot("forearm_r", (0, 0), (0.21, 4, "cubic_out"), (0.34, -5, "expo_out"), (0.85, 0))
    a.tr("weapon", (0, 0, 0), (0.2, -16, -8, "cubic_out"), (0.31, 26, 5, "expo_out"), (0.5, 22, 3), (0.85, 0, 0))
    a.rot("weapon", (0, 0), (0.2, -3, "cubic_out"), (0.31, 3, "expo_out"), (0.85, 0))
    wings2(a, [(0, 0), (0.2, -4, "cubic_out"), (0.31, 7, "expo_out"), (0.5, 5), (0.85, 0)], stagger=0.02, fall=0.06)
    a.look((0, 0, 0), (0.3, 0.4, 0.1), (0.85, 0, 0))
    a.eyes((0, "open"), (0.62, "default"))
    a.att("mouth", (0.26, "open"), (0.5, "default"))
    a.fx("flash", (0.28, 0, "expo_out"), (0.31, 0.14, "cubic_out"), (0.46, 0))
    a.ev(0.18, "windup").ev(0.27, "vfx_thrust").ev(0.27, "swing").ev(0.32, "hit")
    return a


def w2_ultimate():
    """She gathers (crouch, wings folded tight), rises on a great wingbeat - all six wings sweeping
    open in a wave from the top pair down - hangs in the air trembling with the charge, then dives
    into the strike, wings snapping back, and lands."""
    a = Anim("ultimate", 1.7, mix=0.08, mix_out=0.25)
    a.lunge((0, 0), (0.8, 0, "cubic_in"), (0.93, 1.0, "expo_out"), (1.3, 1.0, "cubic_in_out"), (1.7, 0))
    a.tr("root", (0, 0, 0), (0.32, 0, 14, "cubic_out"), (0.65, 0, -90, "back_out"), (0.88, 0, -84), (0.98, 0, 0, "expo_out"), (1.7, 0, 0))
    a.sc("root", (0, 1, 1), (0.32, 1.06, 0.92, "cubic_out"), (0.65, 0.97, 1.05, "back_out"), (0.88, 0.98, 1.04),
         (0.98, 1.06, 0.95, "expo_out"), (1.2, 1, 1))
    a.rot("root", (0, 0), (0.32, 2), (0.65, -3), (0.7, -2.2), (0.75, -3.4), (0.8, -2.4), (0.88, -3), (0.98, 7, "expo_out"), (1.3, 4), (1.7, 0))
    a.tr("hips", (0, 0, 0), (0.32, 0, 10, "cubic_out"), (0.65, 0, -4, "back_out"), (0.98, 4, -4, "expo_out"), (1.7, 0, 0))
    a.rot("torso", (0, 0), (0.32, 3), (0.66, -4, "back_out"), (0.99, 4, "expo_out"), (1.7, 0))
    a.sc("chest", (0, 1, 1), (0.32, 0.98, 0.96), (0.66, 1.04, 1.06, "back_out"), (1.0, 1, 1))
    a.rot("head", (0, 0), (0.33, 5), (0.67, -6, "back_out"), (1.0, 4, "expo_out"), (1.7, 0))
    a.rot("arm_l", (0, 0), (0.32, 4), (0.66, -8, "back_out"), (0.98, 6, "expo_out"), (1.7, 0))
    a.rot("forearm_l", (0, 0), (0.33, 3), (0.68, -6, "back_out"), (1.0, 5, "expo_out"), (1.7, 0))
    a.rot("arm_r", (0, 0), (0.32, -4), (0.66, 8, "back_out"), (0.98, -5, "expo_out"), (1.7, 0))
    a.rot("forearm_r", (0, 0), (0.33, -3), (0.68, 6, "back_out"), (1.0, -4, "expo_out"), (1.7, 0))
    a.tr("weapon", (0, 0, 0), (0.32, 0, 10), (0.65, 0, -40, "back_out"), (0.98, 30, -8, "expo_out"), (1.7, 0, 0))
    a.rot("weapon", (0, 0), (0.65, -2), (0.98, 3, "expo_out"), (1.7, 0))
    wings2(a, [(0, 0), (0.32, -5, "cubic_out"), (0.62, 9, "back_out"), (0.7, 7.5), (0.76, 9), (0.82, 8),
               (0.88, 8.5), (0.98, -4, "expo_out"), (1.25, 1.5), (1.7, 0)], stagger=0.03, fall=0.06)
    a.look((0, 0, 0), (0.32, 0, 0.6), (0.65, -0.2, -0.7), (0.98, 0.45, 0.1), (1.7, 0, 0))
    a.eyes((0, "closed"), (0.6, "open"), (1.45, "default"))
    a.att("mouth", (0.6, "open"), (1.3, "default"))
    a.fx("aura", (0, 0), (0.6, 1.0), (1.1, 1.2), (1.7, 0))
    a.fx("hand_glow", (0.1, 0), (0.6, 1.2), (0.9, 1.4), (1.05, 0))
    a.fx("glow", (0.3, 0), (0.85, 1.4), (1.0, 1.8), (1.3, 0))
    a.fx("flash", (0.9, 0, "expo_out"), (0.96, 0.6, "cubic_out"), (1.25, 0))
    a.ev(0.0, "ult_start").ev(0.1, "vfx_charge").ev(0.65, "ult_pose").ev(0.92, "release").ev(0.92, "vfx_burst").ev(0.98, "hit")
    return a


def w2_hit():
    """Knocked back: the body snaps away, head and wings a frame later, everything soft still swinging."""
    a = Anim("hit", 0.5, mix=0.03, mix_out=0.18)
    a.tr("root", (0, 0, 0, "expo_out"), (0.06, -46, 0), (0.5, 0, 0, "cubic_in_out"))
    a.rot("root", (0, 0, "expo_out"), (0.06, -6), (0.22, -2, "back_out"), (0.5, 0))
    a.sc("root", (0, 1, 1, "expo_out"), (0.06, 0.96, 1.03), (0.2, 1.02, 0.98), (0.5, 1, 1))
    a.rot("torso", (0, 0, "expo_out"), (0.08, -3), (0.25, 1, "back_out"), (0.5, 0))
    a.rot("head", (0, 0, "expo_out"), (0.09, -7), (0.24, -2, "back_out"), (0.5, 0))
    a.rot("arm_l", (0, 0, "expo_out"), (0.09, 6), (0.3, -2), (0.5, 0))
    a.rot("arm_r", (0, 0, "expo_out"), (0.09, -6), (0.3, 2), (0.5, 0))
    wings2(a, [(0, 0, "expo_out"), (0.07, 7), (0.25, -2, "back_out"), (0.5, 0)], stagger=0.02)
    a.eyes((0, "closed"), (0.3, "default"))
    a.att("mouth", (0, "open"), (0.3, "default"))
    a.fx("flash", (0, 0.5, "cubic_out"), (0.18, 0))
    a.ev(0.0, "impact")
    return a


WARP2_ALL = [w2_idle, w2_attack_thrust, w2_ultimate, w2_hit]


ALL = [idle, attack_melee, attack_thrust, attack_ranged, cast, support_cast, ultimate, hit, death, victory, stun, hop, run]

if __name__ == "__main__":
    for fn in ALL:
        print("wrote", os.path.relpath(fn().save()))
    for fn in WARP_ALL:
        print("wrote", os.path.relpath(fn().save(WARP_OUT)))
    for fn in WARP2_ALL:
        print("wrote", os.path.relpath(fn().save(WARP2_OUT)))
