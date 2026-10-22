"""Halo & Horn: the district as an architect's maquette (style v4; the district screen). The eight
buildings of data/district.json in white clay on a paper ground slab, seen from a true isometric
camera, each rendered on its own with its shadow (Cycles shadow catcher) so the game can stack them,
show the unbuilt ones as frosted placeholders and colour the kept ones (src/ui/v4/district_model.gd).

    blender --background --factory-startup --python tools/blender/district_models.py -- <out_dir> [samples] [gpu|cpu]

Writes <out_dir>/ground.png and <out_dir>/<building id>.png (16-bit RGBA, transparent, full frame)
and layout.json (frame size; per building its roof point and its foot point in the image, 0..1, y
down). tools/blender/finish_district.py crops them and writes assets/art/ui/district/.
The grid follows DistrictPlan's: 8 x 8 cells, grid x running down-right, grid y down-left; the spots
are DistrictPlan.SPOTS. Seconds per render on an RTX 3070 (OptiX).
"""
import json
import math
import os
import sys

import bpy
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
OUT = argv[0]
SAMPLES = int(argv[1]) if len(argv) > 1 else 160
DEV = argv[2] if len(argv) > 2 else "gpu"
os.makedirs(OUT, exist_ok=True)

GRID = 8
UNIT = 22.0 / 46.0               # one storey (DistrictPlan.UNIT_H / CELL)
SPOTS = [(3, 6), (0, 5), (5, 5), (0, 1), (6, 1), (2, 0), (5, 0), (7, 0)]
B = [  # id, w (along grid x), d (along grid y), storeys
    ("gate", 2, 1, 3), ("chapel", 1, 2, 4), ("market", 2, 2, 2), ("baths", 2, 1, 2),
    ("forge", 1, 1, 5), ("lounge", 2, 2, 3), ("archive", 1, 2, 4), ("spire", 1, 1, 7),
]
RES = (1304, 1060)

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
sc.render.engine = "CYCLES"
if DEV == "gpu":
    prefs = bpy.context.preferences.addons["cycles"].preferences
    prefs.compute_device_type = "OPTIX"
    prefs.get_devices()
    for dv in prefs.devices:
        dv.use = dv.type == "OPTIX"
    sc.cycles.device = "GPU"
sc.cycles.samples = SAMPLES
sc.cycles.use_denoising = True
sc.cycles.denoiser = "OPTIX" if DEV == "gpu" else "OPENIMAGEDENOISE"
sc.render.resolution_x, sc.render.resolution_y = RES
sc.render.film_transparent = True
sc.render.image_settings.file_format = "PNG"
sc.render.image_settings.color_mode = "RGBA"
sc.render.image_settings.color_depth = "16"
sc.view_settings.view_transform = "AgX"
sc.view_settings.exposure = 0.8
try:
    sc.view_settings.look = "AgX - Medium Contrast"
except Exception:
    pass


def W(gx, gy, z=0.0):
    """Grid (x down-right, y down-left) to Blender world: X = grid y, Y = grid x (camera at +,+,+)."""
    return Vector((gy, gx, z))


# ---------------------------------------------------------------- materials

def clay(name="clay", col=(0.86, 0.85, 0.82)):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*col, 1)
    b.inputs["Roughness"].default_value = 0.8
    return m


CLAY = clay()
DARK = clay("dark", (0.2, 0.2, 0.21))
ROAD = clay("road", (0.7, 0.24, 0.14))


def ground_mat():
    """Paper with the street grid engraved: a darker line at every cell edge."""
    m = bpy.data.materials.new("ground")
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    b.inputs["Roughness"].default_value = 0.85
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(tc.outputs["Object"], sep.inputs[0])

    def line(axis_out):
        fr = nt.nodes.new("ShaderNodeMath")
        fr.operation = "PINGPONG"
        fr.inputs[1].default_value = 0.5
        nt.links.new(axis_out, fr.inputs[0])
        st = nt.nodes.new("ShaderNodeMath")
        st.operation = "LESS_THAN"
        st.inputs[1].default_value = 0.012
        nt.links.new(fr.outputs[0], st.inputs[0])
        return st.outputs[0]

    mx = nt.nodes.new("ShaderNodeMath")
    mx.operation = "MAXIMUM"
    nt.links.new(line(sep.outputs["X"]), mx.inputs[0])
    nt.links.new(line(sep.outputs["Y"]), mx.inputs[1])
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.inputs["A"].default_value = (0.9, 0.89, 0.86, 1)
    mix.inputs["B"].default_value = (0.62, 0.61, 0.58, 1)
    nt.links.new(mx.outputs[0], mix.inputs["Factor"])
    nt.links.new(mix.outputs["Result"], b.inputs["Base Color"])
    return m


def wall_mat():
    m = bpy.data.materials.new("wall")
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    b.inputs["Roughness"].default_value = 0.9
    tc = nt.nodes.new("ShaderNodeTexCoord")
    wave = nt.nodes.new("ShaderNodeTexWave")
    wave.wave_type = "BANDS"
    wave.bands_direction = "Z"
    wave.inputs["Scale"].default_value = 9.0
    wave.inputs["Distortion"].default_value = 1.5
    nt.links.new(tc.outputs["Object"], wave.inputs["Vector"])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = (0.18, 0.18, 0.19, 1)
    ramp.color_ramp.elements[1].color = (0.6, 0.58, 0.55, 1)
    nt.links.new(wave.outputs["Fac"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], b.inputs["Base Color"])
    return m


# ---------------------------------------------------------------- building blocks

parts = []


def box(gx0, gy0, z0, sx, sy, sz, mat=None):
    """A box from grid corner (gx0, gy0, z0) spanning sx (grid x), sy (grid y), sz (up)."""
    c = W(gx0 + sx / 2, gy0 + sy / 2, z0 + sz / 2)
    bpy.ops.mesh.primitive_cube_add(size=1, location=c)
    o = bpy.context.object
    o.scale = (sy, sx, sz)
    o.data.materials.append(mat or CLAY)
    parts.append(o)
    return o


def cyl(gx, gy, z0, r, h, verts=32, r2=None, mat=None):
    if r2 is None:
        bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=h, location=W(gx, gy, z0 + h / 2))
    else:
        bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r, radius2=r2, depth=h, location=W(gx, gy, z0 + h / 2))
    o = bpy.context.object
    o.data.materials.append(mat or CLAY)
    parts.append(o)
    return o


def cone(gx, gy, z0, r, h, verts=4, rot=math.pi / 4):
    bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r, radius2=0.0, depth=h, location=W(gx, gy, z0 + h / 2))
    o = bpy.context.object
    o.rotation_euler = (0, 0, rot)
    o.data.materials.append(CLAY)
    parts.append(o)
    return o


def dome(gx, gy, z0, r):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=40, ring_count=20, radius=r, location=W(gx, gy, z0))
    o = bpy.context.object
    o.scale = (1, 1, 0.92)
    o.data.materials.append(CLAY)
    parts.append(o)
    return o


def torus(gx, gy, z, R, r, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_torus_add(major_radius=R, minor_radius=r, major_segments=48, minor_segments=12, location=W(gx, gy, z))
    o = bpy.context.object
    o.rotation_euler = rot
    o.data.materials.append(CLAY)
    parts.append(o)
    return o


def smooth_all():
    for o in parts:
        for p in o.data.polygons:
            p.use_smooth = len(o.data.polygons) > 30


def build(bid, sx, sy, w, d, h):
    """One building on its lot (grid sx..sx+w, sy..sy+d), h storeys."""
    H = h * UNIT
    m = 0.1
    x0, y0, x1, y1 = sx + m, sy + m, sx + w - m, sy + d - m
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    box(x0 - 0.04, y0 - 0.04, 0, x1 - x0 + 0.08, y1 - y0 + 0.08, 0.06)            # the lot's plinth
    if bid == "gate":
        for px in (x0, x1 - 0.42):
            box(px, y0 + 0.1, 0.06, 0.42, y1 - y0 - 0.2, H - 0.3)
            cone(px + 0.21, cy, H - 0.24, 0.3, 0.42)
        box(x0 + 0.3, y0 + 0.18, H * 0.62, x1 - x0 - 0.6, y1 - y0 - 0.36, 0.2)
        torus(cx, cy, H * 0.38, (x1 - x0) * 0.27, 0.07, rot=(math.pi / 2, 0, math.pi / 2))
        cyl(cx, cy, H * 0.62 + 0.2, 0.09, 0.28)
        torus(cx, cy, H * 0.62 + 0.62, 0.2, 0.035, rot=(math.pi / 2, 0, math.pi / 2))
    elif bid == "chapel":
        box(x0 + 0.1, y0 + 0.55, 0.06, x1 - x0 - 0.2, y1 - y0 - 0.6, H * 0.5)
        # The gable: a triangular prism along the nave (grid y = world X), apex up.
        rr = (x1 - x0 - 0.2) / 1.732
        bpy.ops.mesh.primitive_cylinder_add(vertices=3, radius=rr, depth=y1 - y0 - 0.6,
            location=W(cx, y0 + 0.55 + (y1 - y0 - 0.6) / 2, 0.06 + H * 0.5 + rr * 0.5))
        o = bpy.context.object
        o.rotation_mode = "ZYX"
        o.rotation_euler = (0, math.pi / 2, math.pi)
        o.data.materials.append(CLAY)
        parts.append(o)
        box(cx - 0.22, y0, 0.06, 0.44, 0.48, H * 0.86)
        cone(cx, y0 + 0.24, 0.06 + H * 0.86, 0.32, H * 0.42)
        cyl(cx, y1 - 0.05, H * 0.25, 0.12, 0.02, mat=DARK)
    elif bid == "market":
        box(x0, y0, 0.06, x1 - x0, y1 - y0, 0.05)
        n = 5
        for i in range(n):
            for j in range(n):
                if i in (0, n - 1) or j in (0, n - 1):
                    gx = x0 + 0.1 + (x1 - x0 - 0.2) * i / (n - 1)
                    gy = y0 + 0.1 + (y1 - y0 - 0.2) * j / (n - 1)
                    cyl(gx, gy, 0.11, 0.05, H * 0.62, 16)
        box(x0, y0, 0.11 + H * 0.62, x1 - x0, y1 - y0, 0.1)
        dome(cx, cy, 0.21 + H * 0.62, (x1 - x0) * 0.3)
        cyl(cx, cy, 0.21 + H * 0.62 + (x1 - x0) * 0.27, 0.06, 0.22, 12)
        for i in range(3):
            box(cx - 0.45 + i * 0.32, cy - 0.15, 0.11, 0.22, 0.3, 0.18, DARK)
    elif bid == "baths":
        box(x0, y0, 0.06, x1 - x0, y1 - y0 - 0.25, H * 0.55)
        bpy.ops.mesh.primitive_cylinder_add(vertices=40, radius=(y1 - y0 - 0.25) * 0.5, depth=x1 - x0,
            location=W(cx, y0 + (y1 - y0 - 0.25) / 2, 0.06 + H * 0.55))
        o = bpy.context.object
        o.rotation_euler = (math.pi / 2, 0, 0)
        o.data.materials.append(CLAY)
        parts.append(o)
        box(x0, y1 - 0.25, 0.06, x1 - x0, 0.25, 0.04)
        box(x0 + 0.15, y1 - 0.22, 0.07, x1 - x0 - 0.3, 0.18, 0.04, DARK)       # the pool
        for i in range(6):
            cyl(x0 + 0.12 + (x1 - x0 - 0.24) * i / 5, y1 - 0.27, 0.06, 0.04, H * 0.45, 12)
    elif bid == "forge":
        box(x0, y0, 0.06, x1 - x0, y1 - y0, H * 0.28)
        box(x0 + 0.08, y0 + 0.08, 0.06 + H * 0.28, x1 - x0 - 0.4, y1 - y0 - 0.16, H * 0.1)
        cyl(x1 - 0.2, y0 + 0.2, 0.06, 0.17, H * 0.95, 24, r2=0.11)
        torus(x1 - 0.2, y0 + 0.2, H * 0.6, 0.15, 0.03)
        torus(x1 - 0.2, y0 + 0.2, H * 0.85, 0.13, 0.03)
        box(x0 + 0.1, y1 - 0.3, 0.06 + H * 0.28, 0.25, 0.18, 0.12, DARK)
    elif bid == "lounge":
        box(x0, y0, 0.06, x1 - x0, y1 - y0, H * 0.34)
        box(x0 + 0.15, y0 + 0.1, 0.06 + H * 0.34, x1 - x0 - 0.45, y1 - y0 - 0.4, H * 0.32)
        box(x0 - 0.02, y1 - 0.62, 0.06 + H * 0.34 - 0.03, x1 - x0 + 0.04, 0.3, 0.05)     # a balcony slab
        box(x0 + 0.3, y0 + 0.2, 0.06 + H * 0.66, x1 - x0 - 0.9, y1 - y0 - 0.85, H * 0.3)
        box(x0 + 0.4, y0 + 0.3, 0.06 + H * 0.96, 0.5, 0.35, 0.02, DARK)                  # the roof pool
        box(x0 + 0.1, y1 - 0.35, 0.06 + H * 0.66, 0.9, 0.3, 0.04)
    elif bid == "archive":
        box(x0 + 0.05, y0 + 0.05, 0.06, x1 - x0 - 0.1, y1 - y0 - 0.1, H * 0.82)
        k = 9
        for i in range(k):
            gy = y0 + 0.08 + (y1 - y0 - 0.16) * i / (k - 1)
            box(x1 - 0.06, gy - 0.02, 0.06, 0.08, 0.04, H * 0.82)
        for i in range(4):
            gx = x0 + 0.1 + (x1 - x0 - 0.2) * i / 3
            box(gx - 0.02, y1 - 0.06, 0.06, 0.04, 0.08, H * 0.82)
        dome(cx, y0 + (y1 - y0) * 0.35, 0.06 + H * 0.82, 0.3)
    elif bid == "spire":
        cyl(cx, cy, 0.06, 0.38, H * 0.12, 32)
        cyl(cx, cy, 0.06 + H * 0.12, 0.28, H * 0.78, 32, r2=0.07)
        for f in (0.3, 0.5, 0.68):
            torus(cx, cy, 0.06 + H * f, 0.28 - 0.21 * (f - 0.12) / 0.78 + 0.03, 0.028)
        cyl(cx, cy, 0.06 + H * 0.9, 0.025, H * 0.16, 8)
        torus(cx, cy, 0.06 + H * 0.93, 0.12, 0.018)
    return (W(cx, cy, 0.0), W(cx, cy, H + 0.15))


# ---------------------------------------------------------------- the ground slab

GM = ground_mat()
WM = wall_mat()
bpy.ops.mesh.primitive_cube_add(size=1, location=W(GRID / 2, GRID / 2, -0.18))
ground = bpy.context.object
ground.scale = (GRID, GRID, 0.36)
ground.data.materials.append(GM)
ground.data.materials.append(WM)
for p in ground.data.polygons:
    p.material_index = 0 if p.normal.z > 0.5 else 1
# The souls' road along grid y = 3.5.
bpy.ops.mesh.primitive_cube_add(size=1, location=W(GRID / 2, 3.5, 0.004))
road = bpy.context.object
road.scale = (0.26, GRID, 0.01)
road.data.materials.append(ROAD)

# ---------------------------------------------------------------- camera and light

cam_d = bpy.data.cameras.new("cam")
cam_d.type = "ORTHO"
cam = bpy.data.objects.new("cam", cam_d)
sc.collection.objects.link(cam)
sc.camera = cam
aim = W(GRID / 2, GRID / 2, 0.75)
cam.location = aim + Vector((1, 1, 1)).normalized() * 40.0
cam.rotation_euler = (aim - cam.location).to_track_quat("-Z", "Y").to_euler()
cam_d.ortho_scale = 12.4
cam_d.clip_end = 200.0

sun_d = bpy.data.lights.new("sun", "SUN")
sun_d.energy = 5.0
sun_d.angle = math.radians(2.5)
sun = bpy.data.objects.new("sun", sun_d)
sc.collection.objects.link(sun)
# From the picture's upper left, fairly low (long shadows to the lower right). With the camera at
# (+,+,+) the picture's right is (-1, 1, 0) and "away" on the ground is (-1, -1, 0).
pic_left = Vector((0.7071, -0.7071, 0.0))
away = Vector((-0.7071, -0.7071, 0.0))
light_from = (pic_left * 0.55 + away * 0.75 + Vector((0, 0, 0.62))).normalized()
sun.rotation_euler = (-light_from).to_track_quat("-Z", "Y").to_euler()
world = bpy.data.worlds.new("w")
sc.world = world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.62, 0.64, 0.68, 1)
world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.4

# ---------------------------------------------------------------- the buildings, one by one

groups = {}
layout = {"size": list(RES), "buildings": {}}
for i, (bid, w, d, h) in enumerate(B):
    parts = []
    sx, sy = SPOTS[i]
    foot, roof = build(bid, sx, sy, w, d, h)
    smooth_all()
    groups[bid] = list(parts)
    fv = world_to_camera_view(sc, cam, foot)
    rv = world_to_camera_view(sc, cam, roof)
    layout["buildings"][bid] = {"foot": [round(fv.x, 4), round(1 - fv.y, 4)], "roof": [round(rv.x, 4), round(1 - rv.y, 4)],
        "depth": sx + sy + (w + d) * 0.5}


def show(objs):
    for o in sc.objects:
        if o.type == "MESH":
            o.hide_render = o not in objs


# The ground alone (its own shading, no buildings).
show([ground, road])
ground.is_shadow_catcher = False
sc.render.filepath = os.path.join(OUT, "ground.png")
bpy.ops.render.render(write_still=True)

# Each building with its shadow on the ground (the ground catches the shadow and is otherwise clear).
ground.is_shadow_catcher = True
road.is_shadow_catcher = True
for bid, objs in groups.items():
    show(objs + [ground, road])
    sc.render.filepath = os.path.join(OUT, "%s.png" % bid)
    bpy.ops.render.render(write_still=True)

with open(os.path.join(OUT, "layout.json"), "w") as f:
    json.dump(layout, f)
print("district_models: wrote", OUT)
