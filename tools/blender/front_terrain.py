"""Halo & Horn: the War for Souls' relief map (style v4; the terrain-slab reference): the front's
seven sectors as one slab of land seen from above at an angle, Heaven's terraced cliffs at the far
end, Hell's cracked basin at the near end, cratered no-man's-land between. Rendered in Cycles as
white clay; the game paints who holds what onto it live (src/ui/v4/front_relief.gdshader).

    blender --background --factory-startup --python tools/blender/front_terrain.py -- <out_dir> [samples] [gpu|cpu]

Writes, at the same camera:
  <out_dir>/relief.png  the clay slab, lit from the upper left (16-bit RGBA, transparent)
  <out_dir>/data.png    per pixel on the slab's top: R = (sector + 0.5) / 7, G = how far from
                        Heaven's end (0) to Hell's end (1), B = height (0 low .. 1 high); walls and
                        background are 0 (8-bit, Raw view: the numbers as written)
  <out_dir>/normal.png  the slab's surface normal in the camera's frame (R right, G up, B toward the
                        viewer; 0.5 + 0.5 * n), so the game can relight it as the phone tilts
  <out_dir>/points.json the slab's sector centre lines projected to the image (0..1, y down):
                        points[sector][k] at t = k / 10, for the labels and the flags
tools/blender/finish_front.py (system Python) trims and writes assets/art/ui/front/.
Seconds per render on an RTX 3070 (OptiX).
"""
import json
import math
import os
import sys

import bpy
import numpy as np
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
OUT = argv[0]
SAMPLES = int(argv[1]) if len(argv) > 1 else 192
DEV = argv[2] if len(argv) > 2 else "gpu"
os.makedirs(OUT, exist_ok=True)

N_SECT = 7
W = float(N_SECT)          # x: -3.5 .. 3.5, one unit per sector
L = 9.0                    # y: Hell's end at -4.5 (near), Heaven's at +4.5 (far)
BASE = -1.9                # the slab's underside
NX, NY = 7 * 44, 9 * 44
RES = (1300, 1280)

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
sc.render.resolution_x, sc.render.resolution_y = RES
sc.render.resolution_percentage = 100
sc.render.film_transparent = True


# ---------------------------------------------------------------- the height field

rng = np.random.default_rng(4471)


def value_noise(x, y, freq, seed):
    """Smooth value noise on a lattice (numpy), about -1..1."""
    r = np.random.default_rng(seed)
    g = r.uniform(-1, 1, (int(freq * 12) + 4, int(freq * 12) + 4))
    fx, fy = x * freq + 1.0, y * freq + 1.0
    ix, iy = np.floor(fx).astype(int), np.floor(fy).astype(int)
    tx, ty = fx - ix, fy - iy
    sx, sy = tx * tx * (3 - 2 * tx), ty * ty * (3 - 2 * ty)
    a = g[iy % g.shape[0], ix % g.shape[1]]
    b = g[iy % g.shape[0], (ix + 1) % g.shape[1]]
    c = g[(iy + 1) % g.shape[0], ix % g.shape[1]]
    d = g[(iy + 1) % g.shape[0], (ix + 1) % g.shape[1]]
    return (a * (1 - sx) + b * sx) * (1 - sy) + (c * (1 - sx) + d * sx) * sy


def fbm(x, y, base_freq, octaves, seed):
    out = np.zeros_like(x)
    amp, f = 1.0, base_freq
    for o in range(octaves):
        out += amp * value_noise(x, y, f, seed + o * 31)
        amp *= 0.5
        f *= 2.03
    return out


def smoothstep(a, b, v):
    t = np.clip((v - a) / (b - a), 0.0, 1.0)
    return t * t * (3 - 2 * t)


xs = np.linspace(-W / 2, W / 2, NX + 1)
ys = np.linspace(-L / 2, L / 2, NY + 1)
X, Y = np.meshgrid(xs, ys)          # rows: y from Hell (-) to Heaven (+)
t = (L / 2 - Y) / L                 # 0 at Heaven's end, 1 at Hell's

h = 0.3 * fbm(X, Y, 0.45, 5, 11)
# Heaven: the land rises into terraced cliffs (stepped plateaus, softened).
rise = smoothstep(0.46, 0.02, t)
terr = 1.1 * rise + 0.35 * fbm(X, Y, 0.7, 3, 23) * rise
steps = np.floor(np.clip(terr, 0, None) * 5.0) / 5.0
h += 0.95 * (steps * 0.6 + terr * 0.4)
# Hell: the land falls into a basin, split by ridged cracks (lava runs in them).
fall = smoothstep(0.52, 1.0, t)
ridge = 1.0 - np.abs(fbm(X * 1.2, Y * 1.2, 0.7, 4, 47))
cracks = np.clip((ridge - 0.74) / 0.26, 0.0, 1.0)
h -= 0.55 * fall + 0.5 * cracks * smoothstep(0.45, 0.8, t)
# No-man's-land: craters.
mid = smoothstep(0.2, 0.45, t) * smoothstep(0.85, 0.6, t)
for k in range(26):
    cx, cy = rng.uniform(-W / 2 + 0.2, W / 2 - 0.2), rng.uniform(-L * 0.3, L * 0.3)
    r = rng.uniform(0.12, 0.34)
    d = np.sqrt((X - cx) ** 2 + (Y - cy) ** 2) / r
    bowl = np.where(d < 1.0, -(1.0 - d * d), 0.0) + 0.35 * np.exp(-((d - 1.05) / 0.18) ** 2)
    h += 0.6 * r * bowl * mid
# The sector lines: faint furrows between the seven sectors.
for i in range(1, N_SECT):
    bx = -W / 2 + i
    h -= 0.035 * np.exp(-((X - bx) / 0.035) ** 2)
# Fade the very edges slightly so the slab's rim reads as a cut.
h = h * 0.9

# ---------------------------------------------------------------- the slab mesh

verts = []
for j in range(NY + 1):
    for i in range(NX + 1):
        verts.append((float(X[j, i]), float(Y[j, i]), float(h[j, i])))
faces = []
row = NX + 1
for j in range(NY):
    for i in range(NX):
        a = j * row + i
        faces.append((a, a + 1, a + 1 + row, a + row))
top_faces = len(faces)
# The walls: the rim's top vertices down to the underside.
rim = [j * row + 0 for j in range(NY + 1)][::-1] + [0 * row + i for i in range(NX + 1)] \
    + [j * row + NX for j in range(NY + 1)] + [NY * row + i for i in range(NX + 1)][::-1]
# (walk the rim once, counter-clockwise from the near-left corner)
ring = []
for i in range(NX + 1):
    ring.append(0 * row + i)               # near edge (Hell), left to right
for j in range(1, NY + 1):
    ring.append(j * row + NX)              # right edge, near to far
for i in range(NX - 1, -1, -1):
    ring.append(NY * row + i)              # far edge (Heaven), right to left
for j in range(NY - 1, 0, -1):
    ring.append(j * row + 0)               # left edge, far to near
base0 = len(verts)
for vi in ring:
    x, y, _ = verts[vi]
    verts.append((x, y, BASE))
n = len(ring)
for k in range(n):
    a, b = ring[k], ring[(k + 1) % n]
    faces.append((b, a, base0 + k, base0 + (k + 1) % n))
faces.append(tuple(base0 + k for k in range(n))[::-1])

me = bpy.data.meshes.new("slab")
me.from_pydata(verts, [], faces)
me.update()
for p in me.polygons:
    p.use_smooth = True
ob = bpy.data.objects.new("slab", me)
sc.collection.objects.link(ob)
for k, p in enumerate(me.polygons):
    p.material_index = 0 if k < top_faces else 1


def mat_clay():
    m = bpy.data.materials.new("clay")
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (0.86, 0.85, 0.82, 1)
    b.inputs["Roughness"].default_value = 0.85
    return m


def mat_wall():
    """The cut edge: banded strata, paper and ink."""
    m = bpy.data.materials.new("wall")
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    b.inputs["Roughness"].default_value = 0.9
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(tc.outputs["Object"], sep.inputs[0])
    wave = nt.nodes.new("ShaderNodeTexWave")
    wave.wave_type = "BANDS"
    wave.bands_direction = "Z"
    wave.inputs["Scale"].default_value = 3.2
    wave.inputs["Distortion"].default_value = 3.0
    wave.inputs["Detail"].default_value = 3.0
    nt.links.new(tc.outputs["Object"], wave.inputs["Vector"])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = (0.16, 0.16, 0.17, 1)
    ramp.color_ramp.elements[1].color = (0.62, 0.6, 0.57, 1)
    ramp.color_ramp.elements[0].position = 0.35
    ramp.color_ramp.elements[1].position = 0.65
    nt.links.new(wave.outputs["Fac"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], b.inputs["Base Color"])
    return m


def mat_data(hmin, hmax):
    """Emission of (sector, t, height) from the object-space position (exact per pixel)."""
    m = bpy.data.materials.new("data")
    m.use_nodes = True
    nt = m.node_tree
    for nd in list(nt.nodes):
        nt.nodes.remove(nd)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(tc.outputs["Object"], sep.inputs[0])

    def math_node(op, a, b=None):
        nd = nt.nodes.new("ShaderNodeMath")
        nd.operation = op
        for k, v in enumerate([a, b]):
            if v is None:
                continue
            if isinstance(v, (int, float)):
                nd.inputs[k].default_value = v
            else:
                nt.links.new(v, nd.inputs[k])
        return nd.outputs[0]

    sx = math_node("FLOOR", math_node("ADD", sep.outputs["X"], W / 2))
    sx = math_node("MINIMUM", math_node("MAXIMUM", sx, 0.0), N_SECT - 1)
    r = math_node("DIVIDE", math_node("ADD", sx, 0.5), float(N_SECT))
    g = math_node("DIVIDE", math_node("SUBTRACT", L / 2, sep.outputs["Y"]), L)
    bch = math_node("DIVIDE", math_node("SUBTRACT", sep.outputs["Z"], hmin), hmax - hmin)
    comb = nt.nodes.new("ShaderNodeCombineXYZ")
    nt.links.new(r, comb.inputs[0])
    nt.links.new(g, comb.inputs[1])
    nt.links.new(bch, comb.inputs[2])
    nt.links.new(comb.outputs[0], em.inputs["Color"])
    em.inputs["Strength"].default_value = 1.0
    nt.links.new(em.outputs[0], out.inputs["Surface"])
    return m


def mat_normal(cam_obj):
    """Emission of the surface normal in camera space (0.5 + 0.5 * n)."""
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
    # Blender's camera space looks down -Z with +Y up: flip Z so B is toward the viewer.
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(vt.outputs[0], sep.inputs[0])
    negz = nt.nodes.new("ShaderNodeMath")
    negz.operation = "MULTIPLY"
    negz.inputs[1].default_value = -1.0
    nt.links.new(sep.outputs["Z"], negz.inputs[0])
    comb = nt.nodes.new("ShaderNodeCombineXYZ")
    nt.links.new(sep.outputs["X"], comb.inputs[0])
    nt.links.new(sep.outputs["Y"], comb.inputs[1])
    nt.links.new(negz.outputs[0], comb.inputs[2])
    half = nt.nodes.new("ShaderNodeVectorMath")
    half.operation = "MULTIPLY_ADD"
    half.inputs[1].default_value = (0.5, 0.5, 0.5)
    half.inputs[2].default_value = (0.5, 0.5, 0.5)
    nt.links.new(comb.outputs[0], half.inputs[0])
    nt.links.new(half.outputs[0], em.inputs["Color"])
    nt.links.new(em.outputs[0], out.inputs["Surface"])
    return m


def mat_black():
    m = bpy.data.materials.new("black")
    m.use_nodes = True
    nt = m.node_tree
    for nd in list(nt.nodes):
        nt.nodes.remove(nd)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (0, 0, 0, 1)
    nt.links.new(em.outputs[0], out.inputs["Surface"])
    return m


# ---------------------------------------------------------------- camera and light

cam_d = bpy.data.cameras.new("cam")
cam_d.type = "ORTHO"
cam = bpy.data.objects.new("cam", cam_d)
sc.collection.objects.link(cam)
sc.camera = cam
ELEV = math.radians(52.0)
YAW = math.radians(-16.0)
dist = 30.0
direction = Vector((math.sin(YAW) * math.cos(ELEV), -math.cos(YAW) * math.cos(ELEV), math.sin(ELEV)))
aim = Vector((0.0, 0.0, -0.3))
cam.location = direction * dist + aim
look = (aim - cam.location).normalized()
cam.rotation_euler = look.to_track_quat("-Z", "Y").to_euler()
cam_d.ortho_scale = 11.6
cam_d.clip_end = 100.0

sun_d = bpy.data.lights.new("sun", "SUN")
sun_d.energy = 5.5
sun_d.angle = math.radians(2.0)
sun = bpy.data.objects.new("sun", sun_d)
sc.collection.objects.link(sun)
# From the upper left of the picture (far and left of the slab), low: long shadows.
light_from = Vector((-0.75, 0.55, 0.42)).normalized()
sun.rotation_euler = (-light_from).to_track_quat("-Z", "Y").to_euler()

world = bpy.data.worlds.new("w")
sc.world = world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.62, 0.64, 0.68, 1)
world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.32


def render(path, samples, view, depth):
    sc.cycles.samples = samples
    sc.cycles.use_denoising = samples > 4
    if samples > 4:
        sc.cycles.denoiser = "OPTIX" if DEV == "gpu" else "OPENIMAGEDENOISE"
    sc.view_settings.view_transform = view
    try:
        if view == "AgX":
            sc.view_settings.look = "AgX - Medium Contrast"
        else:
            sc.view_settings.look = "None"
    except Exception:
        pass
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.render.image_settings.color_depth = depth
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)


# Beauty: clay and strata.
me.materials.append(mat_clay())
me.materials.append(mat_wall())
render(os.path.join(OUT, "relief.png"), SAMPLES, "AgX", "16")

# Data: exact numbers, no lighting, no filtering between sectors.
hmin, hmax = float(h.min()), float(h.max())
me.materials[0] = mat_data(hmin, hmax)
me.materials[1] = mat_black()
sc.cycles.filter_width = 0.01
sc.world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.0
sun.hide_render = True
render(os.path.join(OUT, "data.png"), 1, "Raw", "8")

# Normals: the surface's facing, for relighting with the tilt (smooth, a few samples).
nm = mat_normal(cam)
me.materials[0] = nm
me.materials[1] = nm
sc.cycles.filter_width = 1.5
render(os.path.join(OUT, "normal.png"), 8, "Raw", "8")

# The sector centre lines in image space.
pts = []
for s in range(N_SECT):
    cx = -W / 2 + s + 0.5
    line = []
    for k in range(11):
        tt = k / 10.0
        yy = L / 2 - tt * L
        jj = int(round((yy + L / 2) / L * NY))
        ii = int(round((cx + W / 2) / W * NX))
        z = float(h[min(max(jj, 0), NY), min(max(ii, 0), NX)])
        v = world_to_camera_view(sc, cam, Vector((cx, yy, z)))
        line.append([round(v.x, 4), round(1.0 - v.y, 4)])
    pts.append(line)
with open(os.path.join(OUT, "points.json"), "w") as f:
    json.dump({"size": list(RES), "sectors": N_SECT, "points": pts}, f)
print("front_terrain: wrote", OUT)
