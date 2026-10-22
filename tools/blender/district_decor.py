"""Halo & Horn: the district's decor (the props players buy and place on free lots), in the same
white clay and from the same true isometric camera as tools/blender/district_models.py, each on one
reference lot (grid 0, 0) with its shadow (Cycles shadow catcher) and its normals.

    blender --background --factory-startup --python tools/blender/district_decor.py -- <out_dir> [samples] [gpu|cpu]

Writes <out_dir>/decor_<kind>.png (16-bit RGBA, full frame), decor_<kind>_n.png (normals) and
decor.json ({kind: {"foot": [x, y]}} at lot 0, 0, image 0..1, y down). Kinds: tree, cypress, fountain,
statue, lamp, hedge, bench, obelisk. tools/blender/finish_district.py --decor crops them into
assets/art/ui/district/. Seconds per render on an RTX 3070 (OptiX).
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
SAMPLES = int(argv[1]) if len(argv) > 1 else 128
DEV = argv[2] if len(argv) > 2 else "gpu"
os.makedirs(OUT, exist_ok=True)
GRID = 8
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
sc.render.resolution_x, sc.render.resolution_y = RES
sc.render.film_transparent = True
sc.render.image_settings.file_format = "PNG"
sc.render.image_settings.color_mode = "RGBA"


def W(gx, gy, z=0.0):
    return Vector((gy, gx, z))


def clay(name="clay", col=(0.86, 0.85, 0.82)):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*col, 1)
    b.inputs["Roughness"].default_value = 0.8
    return m


CLAY = clay()
DARK = clay("dark", (0.2, 0.2, 0.21))
parts = []


def add(o, mat=None, smooth=True):
    o.data.materials.append(mat or CLAY)
    if smooth:
        for p in o.data.polygons:
            p.use_smooth = True
    parts.append(o)
    return o


def cyl(x, y, z0, r, h, verts=24, r2=None, mat=None):
    if r2 is None:
        bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=h, location=W(x, y, z0 + h / 2))
    else:
        bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r, radius2=r2, depth=h, location=W(x, y, z0 + h / 2))
    return add(bpy.context.object, mat)


def ball(x, y, z, r, sx=1.0, sz=1.0):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=3, radius=r, location=W(x, y, z))
    o = bpy.context.object
    o.scale = (sx, sx, sz)
    return add(o)


def box(x0, y0, z0, sx, sy, sz, mat=None):
    bpy.ops.mesh.primitive_cube_add(size=1, location=W(x0 + sx / 2, y0 + sy / 2, z0 + sz / 2))
    o = bpy.context.object
    o.scale = (sy, sx, sz)
    return add(o, mat, smooth=False)


def torus(x, y, z, R, r):
    bpy.ops.mesh.primitive_torus_add(major_radius=R, minor_radius=r, major_segments=40, minor_segments=10, location=W(x, y, z))
    return add(bpy.context.object)


def build(kind):
    """One prop on lot (0, 0); its centre is (0.5, 0.5)."""
    c = 0.5
    if kind == "tree":
        cyl(c, c, 0.0, 0.05, 0.42, 12, r2=0.035)
        for (dx, dy, dz, r) in [(0, 0, 0.62, 0.28), (0.12, 0.05, 0.5, 0.2), (-0.1, -0.08, 0.52, 0.2), (0.02, -0.12, 0.75, 0.17)]:
            ball(c + dx, c + dy, dz, r)
    elif kind == "cypress":
        cyl(c, c, 0.0, 0.04, 0.12, 10)
        cyl(c, c, 0.1, 0.17, 0.95, 20, r2=0.02)
    elif kind == "fountain":
        cyl(c, c, 0.0, 0.42, 0.1, 40)
        cyl(c, c, 0.08, 0.36, 0.03, 40, mat=DARK)
        cyl(c, c, 0.1, 0.07, 0.36, 16)
        cyl(c, c, 0.44, 0.2, 0.05, 32)
        cyl(c, c, 0.48, 0.04, 0.16, 10)
        ball(c, c, 0.66, 0.06)
    elif kind == "statue":
        box(c - 0.18, c - 0.18, 0.0, 0.36, 0.36, 0.3)
        box(c - 0.14, c - 0.14, 0.3, 0.28, 0.28, 0.05)
        # A robed figure: a tapered body, a head, two folded wings.
        cyl(c, c, 0.35, 0.11, 0.42, 16, r2=0.06)
        ball(c, c, 0.84, 0.065)
        for s in (-1, 1):
            bpy.ops.mesh.primitive_cone_add(vertices=3, radius1=0.16, radius2=0.0, depth=0.04, location=W(c + 0.02, c + s * 0.12, 0.62))
            o = bpy.context.object
            o.rotation_euler = (math.radians(90), math.radians(10 * s), 0)
            o.scale = (1.0, 2.2, 1.0)
            add(o)
    elif kind == "lamp":
        box(c - 0.07, c - 0.07, 0.0, 0.14, 0.14, 0.05)
        cyl(c, c, 0.05, 0.022, 0.8, 10)
        cyl(c, c, 0.85, 0.07, 0.1, 12, r2=0.03)
        ball(c, c, 0.82, 0.05)
    elif kind == "hedge":
        for k in range(3):
            ball(0.18 + k * 0.32, c, 0.16, 0.2, sx=1.0, sz=0.85)
    elif kind == "bench":
        box(0.15, c - 0.1, 0.16, 0.7, 0.2, 0.04)
        box(0.15, c + 0.08, 0.2, 0.7, 0.03, 0.2)
        for x in (0.2, 0.75):
            box(x, c - 0.09, 0.0, 0.05, 0.18, 0.16)
    elif kind == "obelisk":
        box(c - 0.16, c - 0.16, 0.0, 0.32, 0.32, 0.08)
        cyl(c, c, 0.08, 0.11, 1.05, 4, r2=0.06).rotation_euler = (0, 0, math.pi / 4)
        cyl(c, c, 1.13, 0.062, 0.12, 4, r2=0.0).rotation_euler = (0, 0, math.pi / 4)
    return W(c, c, 0.0)


KINDS = ["tree", "cypress", "fountain", "statue", "lamp", "hedge", "bench", "obelisk"]

# The ground (a shadow catcher only) and the camera and light of district_models.py.
bpy.ops.mesh.primitive_cube_add(size=1, location=W(GRID / 2, GRID / 2, -0.18))
ground = bpy.context.object
ground.scale = (GRID, GRID, 0.36)
ground.data.materials.append(CLAY)
ground.is_shadow_catcher = True
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
pic_left = Vector((0.7071, -0.7071, 0.0))
away = Vector((-0.7071, -0.7071, 0.0))
light_from = (pic_left * 0.55 + away * 0.75 + Vector((0, 0, 0.62))).normalized()
sun.rotation_euler = (-light_from).to_track_quat("-Z", "Y").to_euler()
world = bpy.data.worlds.new("w")
sc.world = world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.62, 0.64, 0.68, 1)
world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.4


def normal_mat():
    m = bpy.data.materials.new("normal")
    m.use_nodes = True
    nt = m.node_tree
    for nd in list(nt.nodes):
        nt.nodes.remove(nd)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    vt = nt.nodes.new("ShaderNodeVectorTransform")
    vt.vector_type = "NORMAL"
    vt.convert_from = "WORLD"
    vt.convert_to = "CAMERA"
    nt.links.new(geo.outputs["Normal"], vt.inputs[0])
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(vt.outputs[0], sep.inputs[0])
    neg = nt.nodes.new("ShaderNodeMath")
    neg.operation = "MULTIPLY"
    neg.inputs[1].default_value = -1.0
    nt.links.new(sep.outputs["Z"], neg.inputs[0])
    comb = nt.nodes.new("ShaderNodeCombineXYZ")
    nt.links.new(sep.outputs["X"], comb.inputs[0])
    nt.links.new(sep.outputs["Y"], comb.inputs[1])
    nt.links.new(neg.outputs[0], comb.inputs[2])
    half = nt.nodes.new("ShaderNodeVectorMath")
    half.operation = "MULTIPLY_ADD"
    half.inputs[1].default_value = (0.5, 0.5, 0.5)
    half.inputs[2].default_value = (0.5, 0.5, 0.5)
    nt.links.new(comb.outputs[0], half.inputs[0])
    nt.links.new(half.outputs[0], em.inputs["Color"])
    nt.links.new(em.outputs[0], out.inputs["Surface"])
    return m


NM = normal_mat()
info = {}
for kind in KINDS:
    parts = []
    foot = build(kind)
    v = world_to_camera_view(sc, cam, foot)
    info[kind] = {"foot": [round(v.x, 4), round(1 - v.y, 4)]}
    # Beauty with its shadow.
    sc.cycles.samples = SAMPLES
    sc.cycles.use_denoising = True
    sc.cycles.denoiser = "OPTIX" if DEV == "gpu" else "OPENIMAGEDENOISE"
    sc.view_settings.view_transform = "AgX"
    sc.view_settings.exposure = 0.8
    try:
        sc.view_settings.look = "AgX - Medium Contrast"
    except Exception:
        pass
    sc.render.image_settings.color_depth = "16"
    ground.hide_render = False
    sc.render.filepath = os.path.join(OUT, "decor_%s.png" % kind)
    bpy.ops.render.render(write_still=True)
    # Normals (no ground).
    keep = {o.name: list(o.data.materials) for o in parts}
    for o in parts:
        for k in range(len(o.data.materials)):
            o.data.materials[k] = NM
    ground.hide_render = True
    sc.cycles.samples = 8
    sc.cycles.use_denoising = False
    sc.view_settings.view_transform = "Raw"
    sc.view_settings.exposure = 0.0
    sc.render.image_settings.color_depth = "8"
    sc.render.filepath = os.path.join(OUT, "decor_%s_n.png" % kind)
    bpy.ops.render.render(write_still=True)
    for o in parts:
        bpy.data.objects.remove(o, do_unlink=True)
with open(os.path.join(OUT, "decor.json"), "w") as f:
    json.dump(info, f)
print("district_decor: wrote", OUT)
