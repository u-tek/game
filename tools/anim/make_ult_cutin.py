"""Writes the ultimate cut-in's performance for the warp rigs and takes the white wash off the
ultimates.

    python tools/anim/make_ult_cutin.py

assets/art/anim/warp/ult_cutin.anim.json (format 2 rigs fall back to it): what she does in her
close-up (src/ui/battle/ult_cutin.gd), timed to its clock. The keys use only the 8 bones every quick
rig has (root, hips, torso, chest, neck, head, face, hair_front) and the look, so it plays on all of
them: she dips and surges up into her poster (two upward motions stacked), snaps her head to the lens,
holds her pose (shoulders turn, a hip pop, the head tilts, the chest rises), coils, and lunges with
the strike (the 'hit' event at the impact frame). Root rotation stays within 10 degrees and the head
within 8.5 so nothing tears.

It also deletes the 'flash' fx track from every ultimate (the white wash over her art at 0.96 s)
and halves their glow and aura: the cut-in's impact frame is the hit now.
"""
import json, os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ANIM = os.path.join(ROOT, "assets", "art", "anim")

# The cut-in clock's beats (seconds at 1x); ult_cutin.gd's BEATS hold the same numbers.
T_RISE, T_SNAP, T_POSE, T_COIL, T_STRIKE = 0.14, 0.40, 0.80, 0.98, 1.08
DURATION = 1.8


def keys(kind, pts):
    """pts: [(t, value, ease arriving at this key)] -> the file's keys (ease leaves a key)."""
    out = []
    for i, (t, v, _e) in enumerate(pts):
        nxt = pts[i + 1][2] if i + 1 < len(pts) else "sine_in_out"
        k = {"t": round(t, 3), "e": nxt}
        if kind in ("translate", "scale", "look"):
            k["x"], k["y"] = v
        else:
            k["v"] = v
        out.append(k)
    return out


def cutin():
    s = "sine_in_out"
    return {
        "name": "ult_cutin",
        "duration": DURATION,
        "loop": False,
        "mix": 0.05,
        "mix_out": 0.1,
        "bones": {
            "root": {
                "translate": keys("translate", [
                    (0.0, (0, 0), s), (T_RISE, (0, 22), "quad_out"), (T_SNAP, (0, -64), "back_out"),
                    (T_POSE, (12, -62), s), (T_COIL, (0, -46), s), (T_STRIKE, (70, -30), "expo_out"),
                    (1.4, (62, -30), s), (DURATION, (0, 0), s)]),
                "rotate": keys("rotate", [
                    (0.0, 0, s), (T_RISE, 3, "quad_out"), (T_SNAP, -2.5, "back_out"), (T_POSE, -2, s),
                    (T_COIL, -6, s), (T_STRIKE, 10, "expo_out"), (1.4, 8, s), (DURATION, 0, s)]),
                "scale": keys("scale", [
                    (0.0, (1, 1), s), (T_RISE, (1.05, 0.94), "quad_out"), (T_SNAP, (0.98, 1.04), "back_out"),
                    (0.6, (1, 1), s), (T_COIL, (1.04, 0.95), s), (T_STRIKE, (1.07, 0.93), "expo_out"),
                    (1.25, (1, 1), s)]),
            },
            "hips": {
                "translate": keys("translate", [
                    (0.0, (0, 0), s), (0.5, (0, 0), s), (T_POSE, (12, 0), s), (T_COIL, (2, 0), s),
                    (DURATION, (0, 0), s)]),
            },
            "torso": {
                "rotate": keys("rotate", [
                    (0.0, 0, s), (T_SNAP, -5, "back_out"), (T_POSE, 4.5, s), (T_COIL, -4, s),
                    (T_STRIKE, -6, "expo_out"), (1.5, 0, s)]),
            },
            "chest": {
                "scale": keys("scale", [
                    (0.0, (1, 1), s), (T_SNAP, (1.03, 1.05), "back_out"), (T_POSE, (1.04, 1.06), s),
                    (T_COIL, (1.0, 0.99), s), (T_STRIKE, (1.03, 1.04), "expo_out"), (1.5, (1, 1), s)]),
            },
            "head": {
                "rotate": keys("rotate", [
                    (0.0, 0, s), (0.38, -6, s), (0.47, 3, "back_out"), (T_POSE, 6, s),
                    (T_COIL, -3, s), (T_STRIKE, -5, "expo_out"), (1.5, 0, s)]),
            },
        },
        # Into the lens on the snap and held there through the pose; toward the foe on the strike.
        "look": keys("look", [
            (0.0, (0, 0), s), (0.3, (0.3, 0.4), s), (0.47, (0, 0), "back_out"), (T_COIL, (0, 0.1), s),
            (T_STRIKE, (0.45, 0.1), "expo_out"), (DURATION, (0, 0), s)]),
        "events": [{"t": 0.0, "name": "ult_start"}, {"t": T_SNAP, "name": "ult_pose"},
                   {"t": T_STRIKE, "name": "hit"}],
    }


def write(path, d):
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(d, f, indent=1)
        f.write("\n")


write(os.path.join(ANIM, "warp", "ult_cutin.anim.json"), cutin())

ults = [os.path.join(ANIM, "ultimate.anim.json"), os.path.join(ANIM, "warp", "ultimate.anim.json"),
        os.path.join(ANIM, "warp2", "ultimate.anim.json")]
heroes = os.path.join(ROOT, "assets", "art", "heroes")
for h in sorted(os.listdir(heroes)):
    for p in [os.path.join(heroes, h, "anim", "ultimate.anim.json")]:
        if os.path.exists(p):
            ults.append(p)
for p in ults:
    with open(p, encoding="utf-8") as f:
        d = json.load(f)
    fx = d.get("fx", {})
    if "flash" not in fx:
        continue
    del fx["flash"]
    for name in ("glow", "aura"):
        for k in fx.get(name, []):
            k["v"] = round(float(k.get("v", 0)) * 0.5, 3)
    write(p, d)
    print("unwashed", os.path.relpath(p, ROOT))
print("wrote warp/ult_cutin.anim.json")
