"""Halo & Horn survey-map clouds (style v4): small volumetric cumulus rendered in Cycles, seen from
the campaign map's camera angle, with a top-down silhouette of each for its shadow on the terrain.

    blender --background --factory-startup --python tools/blender/clouds.py -- <out_dir> [count] [samples] [gpu|cpu]

Writes <out_dir>/cloud_<k>.png (512 px RGBA, transparent) and cloud_<k>_top.png (the silhouette from
straight above, 256 px) for k = 1..count (default 6). tools/blender/finish_worlds.py clouds packs them
into assets/art/worlds/clouds.png (colour atlas) and clouds_shadow.png (shadow atlas).
Each cloud is one volume: a domain cube whose density is a sum of soft blobs (a base row and a few
towers), billowed by noise and cut flat underneath; a low sun from the upper left and a pale sky
light give white tops and grey bases.
"""
import math
import os
import sys

import bpy
import numpy as np
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
OUT = argv[0]
COUNT = int(argv[1]) if len(argv) > 1 else 6
SAMPLES = int(argv[2]) if len(argv) > 2 else 96
DEV = argv[3] if len(argv) > 3 else "gpu"
os.makedirs(OUT, exist_ok=True)

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
sc.render.engine = "CYCLES"
if DEV == "gpu":
    prefs = bpy.context.preferences.addons["cycles"].preferences
    prefs.compute_device_type = "OPTIX"
    prefs.get_devices()
    for d in prefs.devices:
        d.use = d.type == "OPTIX"
    sc.cycles.device = "GPU"
    sc.cycles.denoiser = "OPTIX"
else:
    sc.cycles.device = "CPU"
    sc.cycles.denoiser = "OPENIMAGEDENOISE"
sc.cycles.use_denoising = True
sc.cycles.volume_bounces = 2
sc.cycles.volume_step_rate = 1.0
sc.cycles.max_bounces = 6
sc.render.film_transparent = True
sc.render.image_settings.file_format = "PNG"
sc.render.image_settings.color_mode = "RGBA"
sc.render.image_settings.color_depth = "8"
sc.view_settings.view_transform = "Standard"
sc.view_settings.exposure = 0.0


def link(nt, a, b):
    nt.links.new(a, b)


def math_node(nt, op, a, b=0.0, clamp=False):
    n = nt.nodes.new("ShaderNodeMath")
    n.operation = op
    n.use_clamp = clamp
    for i, v in enumerate((a, b)):
        if isinstance(v, bpy.types.NodeSocket):
            link(nt, v, n.inputs[i])
        else:
            n.inputs[i].default_value = v
    return n.outputs[0]


def smooth(nt, e0, e1, x):
    n = nt.nodes.new("ShaderNodeMapRange")
    n.interpolation_type = "SMOOTHSTEP"
    n.clamp = True
    link(nt, x, n.inputs[0])
    n.inputs[1].default_value = e0
    n.inputs[2].default_value = e1
    n.inputs[3].default_value = 0.0
    n.inputs[4].default_value = 1.0
    return n.outputs[0]


def blobs(k: int):
    """A seeded cumulus layout: (centre, radius) in cloud units (x across, y deep, z up)."""
    rng = np.random.default_rng(1301 + k * 77)
    out = []
    n = int(rng.integers(4, 7))
    width = rng.uniform(1.5, 2.3)
    for i in range(n):
        x = -width * 0.5 + width * (i + 0.5) / n + rng.uniform(-0.1, 0.1)
        r = rng.uniform(0.42, 0.6) * (1.0 - 0.4 * abs(x) / width)
        out.append(((x, rng.uniform(-0.25, 0.25), r * 0.5), r))
    for i in range(int(rng.integers(3, 6))):
        x = rng.uniform(-width * 0.3, width * 0.3)
        r = rng.uniform(0.32, 0.5)
        out.append(((x, rng.uniform(-0.18, 0.18), rng.uniform(0.45, 0.8)), r))
    if rng.uniform() < 0.6:
        out.append(((rng.uniform(-0.25, 0.25), 0.0, rng.uniform(0.95, 1.1)), rng.uniform(0.26, 0.36)))
    return out


def cloud(k: int):
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o)
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.45))
    dom = bpy.context.object
    dom.scale = (3.4, 1.8, 2.1)
    m = bpy.data.materials.new("cloud%d" % k)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    vol = nt.nodes.new("ShaderNodeVolumePrincipled")
    vol.inputs["Color"].default_value = (1.0, 1.0, 1.0, 1.0)
    vol.inputs["Anisotropy"].default_value = 0.35
    link(nt, vol.outputs[0], out.inputs["Volume"])
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    pos = geo.outputs["Position"]
    nz = nt.nodes.new("ShaderNodeTexNoise")
    nz.noise_dimensions = "4D"
    link(nt, pos, nz.inputs["Vector"])
    nz.inputs["Scale"].default_value = 2.2
    nz.inputs["Detail"].default_value = 4.0
    nz.inputs["Roughness"].default_value = 0.55
    nz.inputs[1].default_value = k * 3.7
    off = nt.nodes.new("ShaderNodeVectorMath")
    off.operation = "SUBTRACT"
    link(nt, nz.outputs["Color"], off.inputs[0])
    off.inputs[1].default_value = (0.5, 0.5, 0.5)
    sc_off = nt.nodes.new("ShaderNodeVectorMath")
    sc_off.operation = "SCALE"
    link(nt, off.outputs[0], sc_off.inputs[0])
    sc_off.inputs[3].default_value = 0.42
    pw = nt.nodes.new("ShaderNodeVectorMath")
    pw.operation = "ADD"
    link(nt, pos, pw.inputs[0])
    link(nt, sc_off.outputs[0], pw.inputs[1])
    field = None
    for c, r in blobs(k):
        d = nt.nodes.new("ShaderNodeVectorMath")
        d.operation = "DISTANCE"
        link(nt, pw.outputs[0], d.inputs[0])
        d.inputs[1].default_value = c
        q = math_node(nt, "DIVIDE", d.outputs["Value"], r)
        f = smooth(nt, 1.15, 0.3, q)
        field = f if field is None else math_node(nt, "ADD", field, f)
    fine = nt.nodes.new("ShaderNodeTexNoise")
    link(nt, pos, fine.inputs["Vector"])
    fine.inputs["Scale"].default_value = 6.5
    fine.inputs["Detail"].default_value = 6.0
    fine.inputs["Roughness"].default_value = 0.62
    billow = math_node(nt, "SUBTRACT", field, math_node(nt, "MULTIPLY", math_node(nt, "SUBTRACT", fine.outputs["Fac"], 0.5), 0.9))
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    link(nt, pos, sep.inputs[0])
    bottom = smooth(nt, -0.06, 0.1, sep.outputs["Z"])
    dens = math_node(nt, "MULTIPLY", math_node(nt, "SUBTRACT", billow, 0.36), 9.0, clamp=True)
    dens = math_node(nt, "MULTIPLY", dens, bottom)
    dens = math_node(nt, "MULTIPLY", dens, 26.0)
    link(nt, dens, vol.inputs["Density"])
    dom.data.materials.append(m)
    return dom


def lights():
    w = bpy.data.worlds.new("sky")
    sc.world = w
    w.use_nodes = True
    bg = w.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (0.7, 0.72, 0.77, 1.0)
    bg.inputs["Strength"].default_value = 0.42
    bpy.ops.object.light_add(type="SUN")
    sun = bpy.context.object
    sun.data.energy = 8.0
    sun.data.angle = math.radians(3.0)
    d = Vector((0.8, 0.45, -0.52)).normalized()
    sun.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()


def camera(pitch_deg: float, size: int, top: bool):
    bpy.ops.object.camera_add()
    c = bpy.context.object
    c.data.type = "ORTHO"
    c.data.ortho_scale = 3.0
    if top:
        c.location = (0, 0, 20)
        c.rotation_euler = (0, 0, 0)
    else:
        p = math.radians(pitch_deg)
        c.location = (0, -20 * math.cos(p), 0.45 + 20 * math.sin(p))
        c.rotation_euler = (math.radians(90) - p, 0, 0)
    sc.camera = c
    sc.render.resolution_x = size
    sc.render.resolution_y = size


for k in range(1, COUNT + 1):
    dom = cloud(k)
    lights()
    camera(30.0, 512, False)
    sc.cycles.samples = SAMPLES
    sc.render.filepath = os.path.join(OUT, "cloud_%d.png" % k)
    bpy.ops.render.render(write_still=True)
    for o in list(bpy.data.objects):
        if o.type == "CAMERA":
            bpy.data.objects.remove(o)
    camera(90.0, 256, True)
    sc.cycles.samples = max(8, SAMPLES // 6)
    sc.render.filepath = os.path.join(OUT, "cloud_%d_top.png" % k)
    bpy.ops.render.render(write_still=True)
    print("cloud", k, "done", flush=True)
