"""Cut-paper decorations for real days (the calendar, data/calendar.json): pieces the print shop hangs
on a thread across the Lobby poster on a holiday. Modelled from code (2D outlines with cut holes,
card thickness, a slight curl) and rendered straight down in Cycles, lit like the UI (key light top
left, physical_objects.py KEY_DIR). No floor: the game throws each piece's shadow itself, so it can
swing over the paper.

    blender --background --factory-startup --python tools/blender/holiday_objects.py -- <out_dir> [which] [samples]

which: comma list of piece names, a set (halloween, christmas, newyear, valentine, birthday) or
"all". Writes <out_dir>/<name>.png (512 px, 16-bit, transparent). Then
python tools/blender/finish_holiday.py <out_dir> crops, scales and writes assets/art/ui/holiday/.
  bat_a, bat_b, bat_c          black card stock bats, wings spread, down, raised (Halloween)
  bat_p                        bat_c in pumpkin card (it reads over the Lobby's black type)
  snow_a, snow_b, snow_c       folded-and-cut white paper snowflakes (Christmas Eve, Christmas)
  star_a, star_b               folded gold-foil card stars (New Year's Eve, New Year)
  heart_a, heart_b             pink card hearts (the day's ink), b with a heart cut out (Valentine's Day)
  flag_ink, flag_paper, flag_red   bunting pennants (birthdays), hung by their top edge
"""
import math
import os
import random
import sys

import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
OUT = argv[0]
SETS = {
    "halloween": ["bat_a", "bat_b", "bat_c", "bat_p"],
    "christmas": ["snow_a", "snow_b", "snow_c"],
    "newyear": ["star_a", "star_b"],
    "valentine": ["heart_a", "heart_b"],
    "birthday": ["flag_ink", "flag_paper", "flag_red"],
}
ALL = [n for v in SETS.values() for n in v]
arg = argv[1] if len(argv) > 1 else "all"
WHICH: list = []
for a in arg.split(","):
    WHICH += ALL if a == "all" else SETS.get(a, [a])
SAMPLES = int(argv[2]) if len(argv) > 2 else 160
os.makedirs(OUT, exist_ok=True)

# The UI's key light: top left (plate.gdshader KEY_LIGHT; image up = +Y here).
KEY_DIR = Vector((-0.42, 0.66, 0.62)).normalized()
RES = 512
ORTHO = 1.25


# ------------------------------------------------------------------ scene

def reset() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    prefs = bpy.context.preferences.addons["cycles"].preferences
    prefs.compute_device_type = "OPTIX"
    prefs.get_devices()
    for d in prefs.devices:
        d.use = d.type == "OPTIX"
    sc.cycles.device = "GPU"
    sc.cycles.samples = SAMPLES
    sc.cycles.use_denoising = True
    sc.cycles.denoiser = "OPTIX"
    sc.cycles.use_adaptive_sampling = True
    sc.render.film_transparent = True
    sc.render.resolution_x = RES
    sc.render.resolution_y = RES
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.render.image_settings.color_depth = "16"
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "Medium High Contrast"
    sc.view_settings.exposure = -0.35
    cd = bpy.data.cameras.new("Cam")
    cd.type = "ORTHO"
    cd.ortho_scale = ORTHO
    cam = bpy.data.objects.new("Cam", cd)
    sc.collection.objects.link(cam)
    cam.location = (0.0, 0.0, 20.0)
    sc.camera = cam
    # A soft grey room, the key light top left, a weak fill bottom right, a cool bounce from the paper.
    w = bpy.data.worlds.new("Room")
    sc.world = w
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs["Color"].default_value = (0.5, 0.5, 0.5, 1)
    w.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.35
    area(KEY_DIR * 9.0, 900.0, 4.0)
    area(Vector((6.0, -5.0, 5.0)), 140.0, 6.0)
    area(Vector((0.0, 0.0, -4.0)), 30.0, 8.0)


def area(loc: Vector, energy: float, size: float) -> None:
    bpy.ops.object.light_add(type="AREA", location=loc)
    l = bpy.context.object
    l.data.energy = energy
    l.data.shape = "DISK"
    l.data.size = size
    l.rotation_euler = (Vector((0, 0, 0)) - l.location).to_track_quat("-Z", "Y").to_euler()


# ------------------------------------------------------------------ materials

def paper(name: str, base, rough: float = 0.82, sheen: float = 0.25, metal: float = 0.0, fibre: float = 0.18,
        crinkle: float = 0.0, sss: float = 0.0) -> bpy.types.Material:
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*base, 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    b.inputs["Sheen Weight"].default_value = sheen
    if sss > 0.0:
        b.inputs["Subsurface Weight"].default_value = sss
        b.inputs["Subsurface Radius"].default_value = (0.02, 0.02, 0.02)
    tc = nt.nodes.new("ShaderNodeTexCoord")
    # Paper fibre: fine stretched noise; foil crinkle: larger soft facets.
    mp = nt.nodes.new("ShaderNodeMapping")
    mp.inputs["Scale"].default_value = (90.0, 30.0, 90.0)
    nt.links.new(tc.outputs["Object"], mp.inputs["Vector"])
    nz = nt.nodes.new("ShaderNodeTexNoise")
    nz.inputs["Detail"].default_value = 12.0
    nz.inputs["Roughness"].default_value = 0.65
    nt.links.new(mp.outputs["Vector"], nz.inputs["Vector"])
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = fibre
    bump.inputs["Distance"].default_value = 0.002
    nt.links.new(nz.outputs["Fac"], bump.inputs["Height"])
    normal_out = bump.outputs["Normal"]
    if crinkle > 0.0:
        vor = nt.nodes.new("ShaderNodeTexVoronoi")
        vor.inputs["Scale"].default_value = 22.0
        nt.links.new(tc.outputs["Object"], vor.inputs["Vector"])
        b2 = nt.nodes.new("ShaderNodeBump")
        b2.inputs["Strength"].default_value = crinkle
        b2.inputs["Distance"].default_value = 0.004
        nt.links.new(vor.outputs["Distance"], b2.inputs["Height"])
        nt.links.new(bump.outputs["Normal"], b2.inputs["Normal"])
        normal_out = b2.outputs["Normal"]
    nt.links.new(normal_out, b.inputs["Normal"])
    return m


def mat_for(name: str) -> bpy.types.Material:
    if name == "bat_p":
        # Pumpkin construction card: the Halloween ink (calendar.json ff8a1c) as a dyed matte stock.
        return paper("PumpkinCard", (1.0, 0.25, 0.018), rough=0.78, sheen=0.3, fibre=0.22, sss=0.04)
    if name.startswith("bat") or name == "flag_ink":
        return paper("BlackCard", (0.022, 0.021, 0.024), rough=0.62, sheen=0.55, fibre=0.25)
    if name.startswith("snow") or name == "flag_paper":
        # Opaque white card (a translucent paper went grey on the poster's paper).
        return paper("WhitePaper", (0.95, 0.945, 0.92), rough=0.86, sheen=0.12, fibre=0.14, sss=0.0)
    if name.startswith("star"):
        return paper("GoldFoil", (1.0, 0.79, 0.42), rough=0.18, sheen=0.0, metal=1.0, fibre=0.03, crinkle=0.3)
    if name.startswith("heart"):
        # Valentine's pink (the day's ink, calendar.json ff4f8b) as a dyed card.
        return paper("PinkCard", (1.0, 0.085, 0.26), rough=0.8, sheen=0.25, fibre=0.16, sss=0.04)
    # flag_red: the house signal red as a dyed paper
    return paper("RedPaper", (0.80, 0.075, 0.03), rough=0.8, sheen=0.2, fibre=0.16, sss=0.05)


# ------------------------------------------------------------------ outlines (2D, y up, about 1 unit wide)

def jitter(pts, amount: float, seed: int, closed: bool = True):
    """Hand-cut edges: each point nudged along its normal by a slow random wave (scissors wander)."""
    rnd = random.Random(seed)
    n = len(pts)
    phase = [rnd.uniform(0, math.tau) for _ in range(3)]
    out = []
    for i, (x, y) in enumerate(pts):
        a = pts[(i - 1) % n]
        b = pts[(i + 1) % n]
        tx, ty = b[0] - a[0], b[1] - a[1]
        l = math.hypot(tx, ty) or 1.0
        nx, ny = ty / l, -tx / l
        t = i / n * math.tau
        d = amount * (0.6 * math.sin(t * 7 + phase[0]) + 0.3 * math.sin(t * 19 + phase[1]) + 0.1 * math.sin(t * 41 + phase[2]))
        out.append((x + nx * d, y + ny * d))
    return out


def quad(p0, c, p1, steps: int = 10):
    pts = []
    for i in range(steps):
        t = i / steps
        x = (1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * c[0] + t * t * p1[0]
        y = (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * c[1] + t * t * p1[1]
        pts.append((x, y))
    return pts


def wing(side: int, lift: float, span: float, sweep: float):
    """One wing from the shoulder out and back to the leg, as points (x mirrored by side): an arched
    leading edge to the wrist, a long tip, and a trailing membrane scalloped between four finger tips.
    lift turns the whole wing up (positive) or down about the shoulder; sweep pulls the tip back."""
    sh = (0.055, 0.035)
    ca, sa = math.cos(lift), math.sin(lift)

    def rot(p):
        x, y = p[0] - sh[0], p[1] - sh[1]
        return (sh[0] + x * ca - y * sa, sh[1] + x * sa + y * ca)

    s = span
    wrist = (0.20 * s, 0.11)
    tip = (0.47 * s, 0.02 - sweep)
    fingers = [tip, (0.38 * s, -0.11 - sweep * 0.6), (0.26 * s, -0.15 - sweep * 0.3), (0.15 * s, -0.15)]
    pts = []
    pts += quad(sh, (0.10 * s, 0.13), wrist, 7)
    pts += quad(wrist, (0.36 * s, 0.10 - sweep * 0.4), tip, 7)
    for i in range(3):
        a, b = fingers[i], fingers[i + 1]
        mid = ((a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5 + 0.06)                  # the membrane sags up between fingers
        pts += quad(a, mid, b, 8)
    leg = (0.035, -0.10)
    pts += quad(fingers[3], (0.08, -0.08), leg, 6)
    pts = [rot(p) for p in pts]
    return [(x * side, y) for x, y in pts]


def bat(lift_r: float, lift_l: float, span: float = 1.0, sweep: float = 0.0):
    """A bat mid-flap, seen from the front: a round head with two small rounded ears and a snout, an
    oval body with little feet, each wing at its own angle (so it never reads as an emblem)."""
    head = []
    for i in range(15):                                                           # the crown, right to left
        t = i / 14 * math.pi
        head.append((math.cos(t) * 0.045, 0.085 + math.sin(t) * 0.04))
    ear_r = [(0.038, 0.105), (0.052, 0.148), (0.062, 0.152), (0.058, 0.100)]
    pts = []
    pts += [(0.012, 0.125)] + ear_r
    pts += [(0.05, 0.06)]
    pts += wing(1, lift_r, span, sweep)
    pts += [(0.03, -0.12), (0.022, -0.145), (0.008, -0.135), (0.0, -0.15),         # feet
        (-0.008, -0.135), (-0.022, -0.145), (-0.03, -0.12)]
    lw = wing(-1, lift_l, span * 0.97, sweep * 1.2)
    pts += list(reversed(lw))
    pts += [(-0.05, 0.06)]
    pts += [(-x, y) for x, y in reversed(ear_r)] + [(-0.012, 0.125)]
    return pts


def hole(cx: float, cy: float, r: float = 0.016):
    """A punched hole for the thread."""
    return [(cx + math.cos(t) * r, cy + math.sin(t) * r) for t in [-i / 16 * math.tau for i in range(16)]]


def heart(scale: float = 0.46):
    pts = []
    for i in range(140):
        t = i / 140 * math.tau
        x = 16 * math.sin(t) ** 3
        y = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)
        pts.append((x / 17.0 * scale, y / 17.0 * scale + 0.03))
    return pts


def star(r_out: float = 0.48, r_in: float = 0.2):
    pts = []
    for i in range(10):
        a = math.pi * 0.5 + i * math.pi / 5
        r = r_out if i % 2 == 0 else r_in
        pts.append((math.cos(a) * r, math.sin(a) * r))
    return pts


def pennant(w: float = 0.72, h: float = 0.86):
    # A triangle hanging from its top edge, a small fold-over along the top for the thread.
    return [(-w / 2, h / 2), (w / 2, h / 2), (0.0, -h / 2)]


def snowflake(variant: int):
    """A folded-and-cut paper snowflake: a 12-fold outline (six arms, mirrored) with cut holes in
    each sector."""
    rnd = random.Random(40 + variant)
    # radius profile over one half-sector (0..30 degrees), sharp notches cut by scissors
    prof = {
        0: [(0, 0.48), (4, 0.40), (6, 0.44), (10, 0.30), (13, 0.34), (18, 0.24), (23, 0.27), (30, 0.20)],
        1: [(0, 0.48), (3, 0.36), (5, 0.41), (9, 0.37), (12, 0.28), (16, 0.33), (22, 0.22), (30, 0.25)],
        2: [(0, 0.47), (5, 0.43), (7, 0.33), (11, 0.38), (15, 0.25), (20, 0.30), (25, 0.21), (30, 0.23)],
    }[variant]
    half = [(math.radians(a), r) for a, r in prof]
    outline = []
    for k in range(6):
        base = k * math.pi / 3 + math.pi / 2
        seg = [(base + a, r) for a, r in half] + [(base + math.radians(60) - a, r) for a, r in reversed(half[:-1])]
        outline += [(math.cos(a) * r, math.sin(a) * r) for a, r in seg]
    holes = []
    hole_shapes = {
        0: [("dia", 0.30, 0.0, 0.035), ("tri", 0.16, 0.0, 0.03), ("dot", 0.22, 0.22, 0.016)],
        1: [("tri", 0.30, 0.0, 0.04), ("dia", 0.18, 0.0, 0.028), ("dot", 0.25, 0.3, 0.014)],
        2: [("dia", 0.34, 0.0, 0.03), ("dia", 0.22, 0.0, 0.03), ("tri", 0.14, 0.35, 0.02)],
    }[variant]
    for k in range(6):
        base = k * math.pi / 3 + math.pi / 2
        for kind, r, off, sz in hole_shapes:
            for sgn in ((0,) if off == 0.0 else (-1, 1)):
                a = base + sgn * off
                cx, cy = math.cos(a) * r, math.sin(a) * r
                ux, uy = math.cos(a), math.sin(a)
                vx, vy = -uy, ux
                if kind == "dia":
                    shp = [(1.4, 0), (0, 0.6), (-1.4, 0), (0, -0.6)]
                elif kind == "tri":
                    shp = [(1.1, 0), (-0.7, 0.8), (-0.7, -0.8)]
                else:
                    shp = [(math.cos(t) * 0.9, math.sin(t) * 0.9) for t in [i / 10 * math.tau for i in range(10)]]
                holes.append([(cx + (px * ux + py * vx) * sz, cy + (px * uy + py * vy) * sz) for px, py in shp])
    # a small central hole where the fold met
    holes.append([(math.cos(t) * 0.03, math.sin(t) * 0.03) for t in [i / 12 * math.tau for i in range(12)]])
    return outline, holes


def snow_strips(variant: int, thick: float) -> bpy.types.Object:
    """A paper snowflake built from strips of card: six arms (a spine each, tapering) with pairs of
    branches at 60 degrees, a small hexagon at the heart. Strips overlap as one piece of paper (a
    filled curve would punch holes where they cross)."""
    spec = {
        0: {"len": 0.47, "w": 0.040, "branches": [(0.18, 0.15, 0.030), (0.31, 0.10, 0.024)], "tip": 0.05},
        1: {"len": 0.45, "w": 0.046, "branches": [(0.13, 0.09, 0.028), (0.24, 0.14, 0.030), (0.35, 0.07, 0.022)], "tip": 0.0},
        2: {"len": 0.48, "w": 0.034, "branches": [(0.22, 0.17, 0.026)], "tip": 0.07},
    }[variant]
    parts = []

    def bar(x0, y0, x1, y1, w):
        dx, dy = x1 - x0, y1 - y0
        ln = math.hypot(dx, dy)
        bpy.ops.mesh.primitive_cube_add(size=1, location=((x0 + x1) / 2, (y0 + y1) / 2, 0))
        b = bpy.context.object
        b.scale = (ln + w * 0.6, w, thick)
        b.rotation_euler = (0, 0, math.atan2(dy, dx))
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
        parts.append(b)

    for k in range(6):
        a = math.pi / 2 + k * math.pi / 3
        ux, uy = math.cos(a), math.sin(a)
        bar(0, 0, ux * spec["len"], uy * spec["len"], spec["w"])
        for d, ln, w in spec["branches"]:
            bx, by = ux * d, uy * d
            for sgn in (-1, 1):
                b = a + sgn * math.pi / 3
                bar(bx, by, bx + math.cos(b) * ln, by + math.sin(b) * ln, w)
        if spec["tip"] > 0:
            tx, ty = ux * spec["len"], uy * spec["len"]
            bpy.ops.mesh.primitive_cylinder_add(vertices=6, radius=spec["tip"] * 0.5, depth=thick,
                location=(tx, ty, 0))
            parts.append(bpy.context.object)
    bpy.ops.mesh.primitive_cylinder_add(vertices=6, radius=0.075, depth=thick, location=(0, 0, 0))
    parts.append(bpy.context.object)
    bpy.ops.object.select_all(action="DESELECT")
    for p in parts:
        p.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    ob = bpy.context.object
    ob.name = "Snow%d" % variant
    # Fuse the strips into one solid piece of card (overlapping strips rendered their inner faces as
    # dark patches); the voxel mesh is fine enough to bend smoothly.
    rm = ob.modifiers.new("Fuse", "REMESH")
    rm.mode = "VOXEL"
    rm.voxel_size = 0.0022
    bpy.ops.object.modifier_apply(modifier="Fuse")
    return ob


# ------------------------------------------------------------------ build

def curve_object(name: str, loops, thick: float) -> bpy.types.Object:
    """A flat filled 2D curve from poly loops (inner loops cut holes), extruded to card thickness,
    as a mesh."""
    cu = bpy.data.curves.new(name, "CURVE")
    cu.dimensions = "2D"
    cu.fill_mode = "BOTH"
    cu.extrude = thick * 0.5
    for loop in loops:
        sp = cu.splines.new("POLY")
        sp.points.add(len(loop) - 1)
        for i, (x, y) in enumerate(loop):
            sp.points[i].co = (x, y, 0.0, 1.0)
        sp.use_cyclic_u = True
    ob = bpy.data.objects.new(name, cu)
    bpy.context.scene.collection.objects.link(ob)
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)
    bpy.ops.object.convert(target="MESH")
    ob = bpy.context.object
    # Even out the triangulation so the curl bends smoothly.
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.subdivide(number_cuts=3)
    bpy.ops.object.mode_set(mode="OBJECT")
    return ob


def curl(ob: bpy.types.Object, angle: float, axis: str = "Y") -> None:
    m = ob.modifiers.new("Curl", "SIMPLE_DEFORM")
    m.deform_method = "BEND"
    m.deform_axis = axis
    m.angle = math.radians(angle)


def tilt(ob: bpy.types.Object, rx: float, ry: float) -> None:
    ob.rotation_euler = (math.radians(rx), math.radians(ry), 0.0)


def fold_star(ob_pts, ridge: float = 0.06) -> bpy.types.Object:
    """A folded card star: a raised centre with a crease down each arm (a faceted pyramid)."""
    n = len(ob_pts)
    verts = [(0.0, 0.0, ridge)] + [(x, y, 0.0) for x, y in ob_pts]
    faces = [(0, 1 + i, 1 + (i + 1) % n) for i in range(n)]
    # back face (a thin card)
    base = len(verts)
    verts += [(x, y, -0.006) for x, y in ob_pts]
    faces.append(tuple(base + i for i in reversed(range(n))))
    for i in range(n):
        j = (i + 1) % n
        faces.append((1 + i, base + i, base + j, 1 + j))
    me = bpy.data.meshes.new("Star")
    me.from_pydata(verts, [], faces)
    me.update()
    ob = bpy.data.objects.new("Star", me)
    bpy.context.scene.collection.objects.link(ob)
    bev = ob.modifiers.new("Bevel", "BEVEL")
    bev.width = 0.002
    bev.segments = 2
    return ob


def build(name: str) -> bpy.types.Object:
    seed = sum(ord(c) for c in name)
    thick = 0.012
    thick = 0.008
    if name.startswith("bat"):
        lr, ll, span, sweep, c, rx, ry = {
            "bat_a": (0.42, 0.18, 1.0, 0.02, -22, 6, 4),     # both wings up, the right higher
            "bat_b": (-0.28, 0.10, 0.92, 0.05, -12, -4, 9),  # the right wing down on the stroke
            "bat_c": (0.36, 0.48, 0.88, -0.03, -28, 8, -6),  # wings raised, the left higher
            "bat_p": (0.36, 0.48, 0.88, -0.03, -28, 8, -6),
        }[name]
        ob = curve_object(name, [jitter(bat(lr, ll, span, sweep), 0.0022, seed)], thick)
        curl(ob, c)
        tilt(ob, rx, ry)
    elif name.startswith("snow"):
        ob = snow_strips("abc".index(name[-1]), 0.006)
        curl(ob, -10 if name != "snow_b" else 8)
        tilt(ob, 4, -3)
    elif name.startswith("star"):
        pts = star(0.48, 0.21) if name == "star_a" else star(0.46, 0.18)
        ob = fold_star(pts, 0.07 if name == "star_a" else 0.05)
        tilt(ob, 5, -7 if name == "star_a" else 6)
        ob.rotation_euler[2] = math.radians(0 if name == "star_a" else 8)
    elif name.startswith("heart"):
        loops = [heart(0.46)]
        if name == "heart_b":
            loops.append([(x * 0.38, y * 0.38 + 0.0) for x, y in heart(0.46)])
        ob = curve_object(name, loops, thick)
        curl(ob, -16)
        tilt(ob, 6, 5)
    elif name.startswith("flag"):
        ob = curve_object(name, [jitter(pennant(), 0.002, seed)], 0.008)
        curl(ob, 8, "X")
        tilt(ob, -4, 3 if name == "flag_paper" else -3)
    else:
        raise SystemExit("unknown piece " + name)
    ob.data.materials.append(mat_for(name))
    for p in ob.data.polygons:
        p.use_smooth = False
    return ob


for name in WHICH:
    reset()
    if name.startswith("star"):
        # Gold mirrors the room: a dim grey room turned its shaded facets olive. A bright one.
        bpy.context.scene.world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.95, 0.92, 0.85, 1)
        bpy.context.scene.world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.6
    build(name)
    sc = bpy.context.scene
    sc.render.filepath = os.path.join(OUT, name + ".png")
    bpy.ops.render.render(write_still=True)
    print("RENDERED", sc.render.filepath)
