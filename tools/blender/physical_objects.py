"""Halo & Horn physical collage objects (style v4 poster look; the owner's "make the game feel physical").
Everything is modelled from code and rendered straight down (orthographic) in Cycles, lit like the UI
(key light top left, docs/dev/ui-style-v4.md), on a shadow-catcher floor so each PNG carries its own
soft contact shadow in the alpha.

    blender --background --factory-startup --python tools/blender/physical_objects.py -- <out_dir> <names|all> [samples] [--cpu] [--preview]

names: a comma list of the JOBS below, a prefix ending in * (thorn_*), or all. Writes <out_dir>/<name>.png
(16-bit RGBA). The acrylic pieces write <name>_black.png and <name>_white.png instead (linear, over a black
and a white backdrop) for tools/blender/finish_physical.py, which splits them into what the slab lets
through and the light it adds, crops everything, bakes the LED halos, makes the paper tiles and writes
assets/art/ui/physical/ plus physical.json (each piece's anchor points).

--cpu renders on the CPU (fewer samples, denoised): use it when another job holds the GPU (check
nvidia-smi first; the overnight ComfyUI art job needs most of the 8 GB). --preview renders at half size.

The pieces:
  thorn_<chrome|black>_<tl|tr|br|bl|edge|clump_a|clump_b>  liquid-chrome thorn growth (fused curves with
      twisted vines, voxel remeshed, smoothed and swelled), knots, thorns, pale fur and grass tufts
      (particle hair); chrome carries blue crystal shards (Celestial), black carries red jelly and a red
      eye (Fallen). The four corners are one composition turned round the poster corner (the light
      stays top left), each with its own seed
  jelly_<tl|tr|br|bl|edge|clump>   wet wine-red jelly / flesh (fused blobs and tubes, subsurface, a glassy
      coat) under fuzzy moss (particle hair on its upper faces) with LED beads sunk into it (Infernal)
  dome_<up|down>             a glossy red ellipsoid push dome
  bezel_<up|down>            a red cap in a knurled silver bezel
  led_<green|orange|red|cyan>_<on|off>   a diffused domed LED in a black grommet
  acrylic_tab                a clear frosted acrylic tab with polished edges and a steel grommet
  acrylic_card               an orange translucent acrylic card with a halftone dot grid and a round cutout
"""
import json
import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector, noise
from mathutils.bvhtree import BVHTree

argv = sys.argv[sys.argv.index("--") + 1:]
OUT = argv[0]
WANT = argv[1] if len(argv) > 1 else "all"
NUMS = [a for a in argv[2:] if a.isdigit()]
SAMPLES = int(NUMS[0]) if NUMS else 192
CPU = "--cpu" in argv
PREVIEW = "--preview" in argv
# Debug: --only-card=<name> keeps just that softbox (and the lights), to see which highlight is which.
ONLY_CARD = next((a.split("=", 1)[1] for a in argv if a.startswith("--only-card=")), "")
os.makedirs(OUT, exist_ok=True)

# Signal red-orange #ff4b1f in linear (Blender colours are linear).
SIGNAL = (1.0, 0.0704, 0.0137)
# The UI's key light comes from the top left (plate.gdshader KEY_LIGHT, screen y down): in world space
# (image up = +Y) that is up and to the left of the object.
KEY_DIR = Vector((-0.42, 0.66, 0.62)).normalized()


# ------------------------------------------------------------------ scene and render

def reset(w: int, h: int, ortho: float, center=(0.0, 0.0), samples: int = SAMPLES, raw: bool = False,
        exposure: float = -0.45, transparent: bool = True) -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    prefs = bpy.context.preferences.addons["cycles"].preferences
    if CPU:
        sc.cycles.device = "CPU"
        sc.cycles.denoiser = "OPENIMAGEDENOISE"
        sc.cycles.samples = max(32, samples // 2)
    else:
        prefs.compute_device_type = "OPTIX"
        prefs.get_devices()
        for d in prefs.devices:
            d.use = d.type == "OPTIX"
        sc.cycles.device = "GPU"
        sc.cycles.denoiser = "OPTIX"
        sc.cycles.samples = samples
    sc.cycles.use_denoising = True
    sc.cycles.use_adaptive_sampling = True
    sc.cycles.max_bounces = 16
    sc.cycles.transmission_bounces = 16
    sc.cycles.glossy_bounces = 8
    sc.cycles.transparent_max_bounces = 16
    sc.cycles.caustics_reflective = False
    sc.cycles.caustics_refractive = False
    sc.cycles.blur_glossy = 0.5
    sc.cycles_curves.shape = "THICK"
    sc.cycles_curves.subdivisions = 2
    sc.render.film_transparent = transparent
    sc.render.resolution_x = w
    sc.render.resolution_y = h
    sc.render.resolution_percentage = 50 if PREVIEW else 100
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.render.image_settings.color_depth = "16"
    if raw:
        sc.view_settings.view_transform = "Raw"
        sc.view_settings.look = "None"
        sc.view_settings.exposure = 0.0
    else:
        sc.view_settings.view_transform = "Standard"
        sc.view_settings.look = "Medium High Contrast"
        # Standard clips highlights: a little under so pale fur and lit glass keep their shape.
        sc.view_settings.exposure = exposure
    cam_data = bpy.data.cameras.new("Cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = ortho
    cam_data.clip_start = 0.1
    cam_data.clip_end = 100.0
    cam = bpy.data.objects.new("Cam", cam_data)
    sc.collection.objects.link(cam)
    cam.location = (center[0], center[1], 30.0)
    cam.rotation_euler = (0.0, 0.0, 0.0)
    sc.camera = cam


def world(strength: float = 0.5, sat: float = 0.0, top: float = 0.01, horizon: float = 0.16, city: float = 0.25) -> None:
    """A dark studio: black overhead (so mirror faces turned to the camera stay dark, the black-chrome
    look), a soft brighter band toward the horizon, and a little of Blender's city light (desaturated)
    for variety in the reflections."""
    sc = bpy.context.scene
    w = bpy.data.worlds.new("Studio")
    sc.world = w
    w.use_nodes = True
    nt = w.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputWorld")
    bg = nt.nodes.new("ShaderNodeBackground")
    env = nt.nodes.new("ShaderNodeTexEnvironment")
    env.image = bpy.data.images.load(os.path.join(bpy.utils.system_resource("DATAFILES", path="studiolights/world"), "city.exr"))
    hs = nt.nodes.new("ShaderNodeHueSaturation")
    hs.inputs["Saturation"].default_value = sat
    mp = nt.nodes.new("ShaderNodeMapping")
    co = nt.nodes.new("ShaderNodeTexCoord")
    mp.inputs["Rotation"].default_value = (0, 0, math.radians(200))
    nt.links.new(co.outputs["Generated"], mp.inputs["Vector"])
    nt.links.new(mp.outputs["Vector"], env.inputs["Vector"])
    nt.links.new(env.outputs["Color"], hs.inputs["Color"])
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(co.outputs["Generated"], sep.inputs["Vector"])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    els = ramp.color_ramp.elements
    els[0].position = 0.0
    els[0].color = (horizon * 0.5, horizon * 0.5, horizon * 0.5, 1)
    els[1].position = 0.75
    els[1].color = (top, top, top, 1)
    e2 = els.new(0.12)
    e2.color = (horizon, horizon, horizon * 1.02, 1)
    nt.links.new(sep.outputs["Z"], ramp.inputs["Fac"])
    add = nt.nodes.new("ShaderNodeMix")
    add.data_type = "RGBA"
    add.blend_type = "ADD"
    add.inputs["Factor"].default_value = city
    nt.links.new(ramp.outputs["Color"], add.inputs[6])
    nt.links.new(hs.outputs["Color"], add.inputs[7])
    nt.links.new(add.outputs[2], bg.inputs["Color"])
    bg.inputs["Strength"].default_value = strength
    nt.links.new(bg.outputs["Background"], out.inputs["Surface"])


def card(name: str, loc, size, strength: float, color=(1.0, 1.0, 1.0), look_at=(0.0, 0.0, 0.0), soft: bool = False) -> bpy.types.Object:
    """An emissive softbox seen only in reflections and refractions (the crisp bands chrome needs).
    soft: its light falls off toward the edges (a diffused box: rounder, photographic highlights)."""
    bpy.ops.mesh.primitive_plane_add(size=1, location=loc)
    p = bpy.context.object
    p.name = name
    p.scale = (size[0], size[1], 1)
    if ONLY_CARD and ONLY_CARD != name:
        strength = 0.0
    d = Vector(look_at) - p.location
    p.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    o = nt.nodes.new("ShaderNodeOutputMaterial")
    e = nt.nodes.new("ShaderNodeEmission")
    e.inputs["Strength"].default_value = strength
    e.inputs["Color"].default_value = (*color, 1)
    if soft:
        tc = nt.nodes.new("ShaderNodeTexCoord")
        mp = nt.nodes.new("ShaderNodeMapping")
        mp.inputs["Location"].default_value = (-1.0, -1.0, 0.0)
        mp.inputs["Scale"].default_value = (2.0, 2.0, 1.0)
        nt.links.new(tc.outputs["Generated"], mp.inputs["Vector"])
        gr = nt.nodes.new("ShaderNodeTexGradient")
        gr.gradient_type = "QUADRATIC_SPHERE"
        nt.links.new(mp.outputs["Vector"], gr.inputs["Vector"])
        # Fades out by turning transparent too, so its edge never cuts a line through the room.
        e.inputs["Strength"].default_value = strength * 1.6
        tr = nt.nodes.new("ShaderNodeBsdfTransparent")
        mx = nt.nodes.new("ShaderNodeMixShader")
        nt.links.new(gr.outputs["Fac"], mx.inputs["Fac"])
        nt.links.new(tr.outputs[0], mx.inputs[1])
        nt.links.new(e.outputs["Emission"], mx.inputs[2])
        nt.links.new(mx.outputs[0], o.inputs["Surface"])
    else:
        nt.links.new(e.outputs["Emission"], o.inputs["Surface"])
    p.data.materials.append(m)
    p.visible_camera = False
    p.visible_shadow = False
    return p


def area(loc, energy: float, size: float, look_at=(0.0, 0.0, 0.0), color=(1.0, 1.0, 1.0), glossy: bool = True) -> bpy.types.Object:
    """An area light (a disc). glossy: False keeps it out of reflections (the softboxes do those)."""
    bpy.ops.object.light_add(type="AREA", location=loc)
    l = bpy.context.object
    l.data.energy = energy
    l.data.shape = "DISK"
    l.data.size = size
    l.data.color = color
    l.visible_glossy = glossy
    l.rotation_euler = (Vector(look_at) - l.location).to_track_quat("-Z", "Y").to_euler()
    return l


def studio(c=(0.0, 0.0), key: float = 1.0, chrome: float = 1.0, world_s: float = 1.0, over: float = 1.0) -> None:
    """Key light top left (the UI's light), a soft fill from the bottom right, and softboxes for the
    reflections: an overhead box offset to the top left, strips on three sides, a low rim card. The
    space straight overhead stays dark (mirror faces turned to the camera read black)."""
    cx, cy = c
    world(world_s)
    k = KEY_DIR * 11.0
    area((cx + k.x, cy + k.y, k.z), 2600.0 * key, 5.0, (cx, cy, 0))
    area((cx + 7.0, cy - 6.0, 6.0), 380.0 * key, 6.0, (cx, cy, 0))
    s = chrome
    card("Over", (cx - 4.2, cy + 5.4, 7.0), (5.0, 1.6), 4.0 * s * over, look_at=(cx, cy, 0))
    card("StripR", (cx + 7.5, cy + 0.5, 2.2), (0.6, 11.0), 16.0 * s, look_at=(cx, cy, 0.4))
    card("StripL", (cx - 7.5, cy - 1.0, 2.0), (0.45, 11.0), 10.0 * s, look_at=(cx, cy, 0.4))
    card("StripT", (cx, cy + 7.5, 2.4), (11.0, 0.55), 14.0 * s, look_at=(cx, cy, 0.4))
    card("RimB", (cx + 1.0, cy - 7.5, 1.4), (9.0, 0.9), 5.0 * s, look_at=(cx, cy, 0.3))


def floor(color=(0.62, 0.62, 0.6)) -> bpy.types.Object:
    """The paper under the object, as a shadow catcher: only the shadow lands in the PNG."""
    bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, 0))
    f = bpy.context.object
    f.name = "Floor"
    f.is_shadow_catcher = True
    m = bpy.data.materials.new("Paper")
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*color, 1)
    b.inputs["Roughness"].default_value = 0.9
    f.data.materials.append(m)
    return f


def render(name: str) -> None:
    """Renders to <OUT>/<name>.png and writes <name>.json (the camera: where the world origin and
    one world unit land in the image) for finish_physical.py."""
    sc = bpy.context.scene
    sc.render.filepath = os.path.join(OUT, name + ".png")
    bpy.ops.render.render(write_still=True)
    k = sc.render.resolution_percentage / 100.0
    w, h = int(sc.render.resolution_x * k), int(sc.render.resolution_y * k)
    cam = sc.camera
    ppu = max(w, h) / cam.data.ortho_scale
    meta = {"size": [w, h], "px_per_unit": ppu,
        "origin": [w * 0.5 - cam.location.x * ppu, h * 0.5 + cam.location.y * ppu]}
    with open(os.path.join(OUT, name + ".json"), "w") as f:
        json.dump(meta, f)
    print("RENDERED", sc.render.filepath)


# ------------------------------------------------------------------ materials

def mat_principled(name, base, metallic=0.0, rough=0.4, coat=0.0, coat_rough=0.03, trans=0.0, ior=1.45, spec=0.5,
        sss=0.0, sss_radius=(1.0, 0.2, 0.1), sss_scale=0.05, emit=None, emit_str=0.0) -> bpy.types.Material:
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*base, 1)
    b.inputs["Metallic"].default_value = metallic
    b.inputs["Roughness"].default_value = rough
    b.inputs["IOR"].default_value = ior
    b.inputs["Specular IOR Level"].default_value = spec
    if coat > 0.0:
        b.inputs["Coat Weight"].default_value = coat
        b.inputs["Coat Roughness"].default_value = coat_rough
    if trans > 0.0:
        b.inputs["Transmission Weight"].default_value = trans
    if sss > 0.0:
        b.inputs["Subsurface Weight"].default_value = sss
        b.inputs["Subsurface Radius"].default_value = sss_radius
        b.inputs["Subsurface Scale"].default_value = sss_scale
    if emit is not None:
        b.inputs["Emission Color"].default_value = (*emit, 1)
        b.inputs["Emission Strength"].default_value = emit_str
    return m


def _node(nt, kind, **inputs):
    n = nt.nodes.new(kind)
    for k, v in inputs.items():
        n.inputs[k].default_value = v
    return n


def mat_chrome(name: str, base, rough=(0.04, 0.16), crust: float = 1.0) -> bpy.types.Material:
    """Liquid chrome: a mirror whose roughness drifts in patches, with a fine bubbly crust (bump)."""
    m = mat_principled(name, base, 1.0, rough[0])
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    tc = nt.nodes.new("ShaderNodeTexCoord")
    nz = _node(nt, "ShaderNodeTexNoise", Scale=7.0, Detail=6.0, Roughness=0.6)
    nt.links.new(tc.outputs["Object"], nz.inputs["Vector"])
    mr = _node(nt, "ShaderNodeMapRange")
    mr.inputs["To Min"].default_value = rough[0]
    mr.inputs["To Max"].default_value = rough[1]
    nt.links.new(nz.outputs["Fac"], mr.inputs["Value"])
    nt.links.new(mr.outputs["Result"], b.inputs["Roughness"])
    # The crust: soft bubbles (smooth voronoi cells) under the mirror finish.
    vo = _node(nt, "ShaderNodeTexVoronoi", Scale=34.0, Randomness=1.0)
    vo.feature = "SMOOTH_F1"
    for inp in vo.inputs:
        if inp.name == "Smoothness":
            inp.default_value = 0.6
    nt.links.new(tc.outputs["Object"], vo.inputs["Vector"])
    bump = _node(nt, "ShaderNodeBump", Strength=0.04 * crust, Distance=0.004)
    nt.links.new(vo.outputs["Distance"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], b.inputs["Normal"])
    return m


def mat_crystal(name: str, color, emit: float = 0.0) -> bpy.types.Material:
    m = mat_principled(name, color, 0.0, 0.02, trans=1.0, ior=1.72, spec=0.8)
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    if emit > 0.0:
        b.inputs["Emission Color"].default_value = (*color, 1)
        b.inputs["Emission Strength"].default_value = emit
    # A deep body colour: absorption inside the shard.
    out = nt.nodes["Material Output"]
    va = _node(nt, "ShaderNodeVolumeAbsorption", Density=6.0)
    va.inputs["Color"].default_value = (*color, 1)
    nt.links.new(va.outputs["Volume"], out.inputs["Volume"])
    return m


def mat_hair(name: str, colors, rough: float = 0.45, root_dark: float = 0.5, principled_hair: bool = False) -> bpy.types.Material:
    """Strands coloured per strand from `colors` (a ramp picked by Hair Info random), darker at the root."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    hi = nt.nodes.new("ShaderNodeHairInfo")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    els = ramp.color_ramp.elements
    els[0].position = 0.0
    els[0].color = (*colors[0], 1)
    els[1].position = 1.0
    els[1].color = (*colors[-1], 1)
    for i, c in enumerate(colors[1:-1]):
        e = els.new((i + 1) / (len(colors) - 1))
        e.color = (*c, 1)
    nt.links.new(hi.outputs["Random"], ramp.inputs["Fac"])
    # Root to tip: darker at the root (self-shadowed), full colour at the tip.
    rt = nt.nodes.new("ShaderNodeMapRange")
    rt.inputs["From Min"].default_value = 0.0
    rt.inputs["From Max"].default_value = 0.6
    rt.inputs["To Min"].default_value = 1.0 - root_dark
    rt.inputs["To Max"].default_value = 1.0
    nt.links.new(hi.outputs["Intercept"], rt.inputs["Value"])
    mul = nt.nodes.new("ShaderNodeMix")
    mul.data_type = "RGBA"
    mul.blend_type = "MULTIPLY"
    mul.inputs["Factor"].default_value = 1.0
    nt.links.new(ramp.outputs["Color"], mul.inputs[6])
    comb = nt.nodes.new("ShaderNodeCombineColor")
    for k in ("Red", "Green", "Blue"):
        nt.links.new(rt.outputs["Result"], comb.inputs[k])
    nt.links.new(comb.outputs["Color"], mul.inputs[7])
    if principled_hair:
        h = nt.nodes.new("ShaderNodeBsdfHairPrincipled")
        h.parametrization = "COLOR"
        h.inputs["Roughness"].default_value = rough
        h.inputs["Radial Roughness"].default_value = 0.6
        h.inputs["Coat"].default_value = 0.05
        nt.links.new(mul.outputs[2], h.inputs["Color"])
        nt.links.new(h.outputs[0], out.inputs["Surface"])
    else:
        b = nt.nodes.new("ShaderNodeBsdfPrincipled")
        b.inputs["Roughness"].default_value = rough
        b.inputs["Specular IOR Level"].default_value = 0.35
        b.inputs["Subsurface Weight"].default_value = 0.0
        nt.links.new(mul.outputs[2], b.inputs["Base Color"])
        nt.links.new(b.outputs[0], out.inputs["Surface"])
    return m


def mat_jelly(name: str = "Jelly", base=(0.095, 0.003, 0.007)) -> bpy.types.Material:
    """Wet dark-red jelly / flesh: subsurface red, a glassy coat, darker veins and paler thin skin."""
    m = mat_principled(name, base, 0.0, 0.3, coat=1.0, coat_rough=0.012, spec=0.5, sss=0.3,
        sss_radius=(1.0, 0.08, 0.05), sss_scale=0.035)
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    b.inputs["Coat IOR"].default_value = 1.48
    tc = nt.nodes.new("ShaderNodeTexCoord")
    nz = _node(nt, "ShaderNodeTexNoise", Scale=4.0, Detail=8.0, Roughness=0.55)
    nt.links.new(tc.outputs["Object"], nz.inputs["Vector"])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    els = ramp.color_ramp.elements
    els[0].position = 0.35
    els[0].color = (base[0] * 0.45, base[1] * 0.4, base[2] * 0.5, 1)
    els[1].position = 0.72
    els[1].color = (min(1.0, base[0] * 1.9), base[1] * 2.2, base[2] * 1.6, 1)
    nt.links.new(nz.outputs["Fac"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], b.inputs["Base Color"])
    # Wrinkles and fine pores under the coat.
    wv = _node(nt, "ShaderNodeTexWave", Scale=9.0, Distortion=6.0, Detail=3.0)
    wv.wave_type = "BANDS"
    nt.links.new(tc.outputs["Object"], wv.inputs["Vector"])
    pores = _node(nt, "ShaderNodeTexNoise", Scale=120.0, Detail=3.0)
    nt.links.new(tc.outputs["Object"], pores.inputs["Vector"])
    add = nt.nodes.new("ShaderNodeMath")
    add.operation = "MULTIPLY_ADD"
    add.inputs[1].default_value = 0.25
    nt.links.new(pores.outputs["Fac"], add.inputs[0])
    nt.links.new(wv.outputs["Fac"], add.inputs[2])
    bump = _node(nt, "ShaderNodeBump", Strength=0.18, Distance=0.006)
    nt.links.new(add.outputs[0], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], b.inputs["Normal"])
    return m


def mat_emit_core(name: str, color, strength: float) -> bpy.types.Material:
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    o = nt.nodes.new("ShaderNodeOutputMaterial")
    e = nt.nodes.new("ShaderNodeEmission")
    e.inputs["Color"].default_value = (*color, 1)
    e.inputs["Strength"].default_value = strength
    nt.links.new(e.outputs["Emission"], o.inputs["Surface"])
    return m


# ------------------------------------------------------------------ geometry helpers

def link(ob: bpy.types.Object) -> bpy.types.Object:
    bpy.context.scene.collection.objects.link(ob)
    return ob


def smoothstep(a: float, b: float, x: float) -> float:
    k = min(max((x - a) / (b - a), 0.0), 1.0)
    return k * k * (3 - 2 * k)


def resample(guide, step: float):
    """Points every `step` along a polyline guide (2D or 3D), as Vectors with z (0 when 2D)."""
    pts = [Vector((p[0], p[1], p[2] if len(p) > 2 else 0.0)) for p in guide]
    seg = [(pts[i + 1] - pts[i]).length for i in range(len(pts) - 1)]
    total = sum(seg)
    n = max(2, int(total / step) + 1)
    out = []
    for k in range(n):
        d = total * k / (n - 1)
        i = 0
        while i < len(seg) - 1 and d > seg[i]:
            d -= seg[i]
            i += 1
        t = d / max(seg[i], 1e-6)
        out.append(pts[i].lerp(pts[i + 1], min(t, 1.0)))
    # Smooth the corners of the guide (two passes of a 1-2-1 filter).
    for _ in range(3):
        out = [out[0]] + [(out[i - 1] + out[i] * 2 + out[i + 1]) / 4 for i in range(1, len(out) - 1)] + [out[-1]]
    return out


def tube(name: str, pts, radii, mat=None, res: int = 6) -> bpy.types.Object:
    """A smooth tube (bezier curve, auto handles) through pts with a radius per point."""
    cu = bpy.data.curves.new(name, "CURVE")
    cu.dimensions = "3D"
    cu.resolution_u = 6
    cu.bevel_depth = 1.0
    cu.bevel_resolution = res
    cu.use_fill_caps = True
    sp = cu.splines.new("BEZIER")
    sp.bezier_points.add(len(pts) - 1)
    for i, (p, r) in enumerate(zip(pts, radii)):
        bp = sp.bezier_points[i]
        bp.co = p
        bp.handle_left_type = "AUTO"
        bp.handle_right_type = "AUTO"
        bp.radius = max(r, 0.0)
    ob = bpy.data.objects.new(name, cu)
    if mat:
        cu.materials.append(mat)
    return link(ob)


def blob(name: str, loc, r: float, squash=(1.0, 1.0, 0.8), seed: int = 0, lump: float = 0.25) -> bpy.types.Object:
    """A lumpy blob (displaced icosphere)."""
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=4, radius=1.0)
    off = Vector((seed * 1.37, seed * 0.71, seed * 2.13))
    for v in bm.verts:
        n = noise.noise(v.co * 1.6 + off) * lump + noise.noise(v.co * 4.0 + off) * lump * 0.35
        v.co = Vector((v.co.x * squash[0], v.co.y * squash[1], v.co.z * squash[2])) * r * (1.0 + n)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    ob.location = loc
    return link(ob)


def fuse(name: str, objs, voxel: float, smooth=(0.6, 6), lumps=(0.18, 0.012), crust=(0.05, 0.004), mat=None,
        apply: bool = True) -> bpy.types.Object:
    """Joins objects into one organic surface: voxel remesh (melts them together), smooth, then
    displace (big lumps, then a fine crust). apply: bake the modifiers into the mesh (needed for hair
    emission and ray casts)."""
    dg = bpy.context.evaluated_depsgraph_get()
    bm = bmesh.new()
    for ob in objs:
        ev = ob.evaluated_get(dg)
        me = bpy.data.meshes.new_from_object(ev)
        me.transform(ob.matrix_world)
        bm.from_mesh(me)
        bpy.data.meshes.remove(me)
    for ob in objs:
        bpy.data.objects.remove(ob, do_unlink=True)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = link(bpy.data.objects.new(name, me))
    rm = ob.modifiers.new("remesh", "REMESH")
    rm.mode = "VOXEL"
    rm.voxel_size = voxel
    rm.adaptivity = 0.0
    sm = ob.modifiers.new("smooth", "SMOOTH")
    sm.factor = smooth[0]
    sm.iterations = smooth[1]
    if lumps[1] > 0.0:
        t = bpy.data.textures.new(name + "_lumps", "CLOUDS")
        t.noise_scale = lumps[0]
        t.noise_depth = 2
        d = ob.modifiers.new("lumps", "DISPLACE")
        d.texture = t
        d.texture_coords = "GLOBAL"
        d.strength = lumps[1]
        d.mid_level = 0.5
    if crust[1] > 0.0:
        t2 = bpy.data.textures.new(name + "_crust", "VORONOI")
        t2.noise_scale = crust[0]
        t2.distance_metric = "DISTANCE"
        t2.weight_1 = 1.0
        t2.weight_2 = 0.0
        d2 = ob.modifiers.new("crust", "DISPLACE")
        d2.texture = t2
        d2.texture_coords = "GLOBAL"
        d2.strength = -crust[1]
        d2.mid_level = 0.5
        sm2 = ob.modifiers.new("soften", "SMOOTH")
        sm2.factor = 0.5
        sm2.iterations = 1
    for p in me.polygons:
        p.use_smooth = True
    if mat:
        me.materials.append(mat)
    if apply:
        dg = bpy.context.evaluated_depsgraph_get()
        ev = ob.evaluated_get(dg)
        baked = bpy.data.meshes.new_from_object(ev)
        ob.modifiers.clear()
        old = ob.data
        ob.data = baked
        bpy.data.meshes.remove(old)
        for p in ob.data.polygons:
            p.use_smooth = True
        if mat and not ob.data.materials:
            ob.data.materials.append(mat)
    return ob


def hair(ob: bpy.types.Object, name: str, mat, count: int, length: float, children: int = 30, radius: float = 0.0025,
        tip: float = 0.0, rough=(0.02, 0.04, 0.0), clump: float = 0.0, normal: float = 1.0, rand: float = 0.3,
        up: float = 0.0, group: str = "", seed: int = 0, child_radius: float = 0.04, kink: str = "NO",
        steps: int = 4, length_rand: float = 0.4) -> None:
    """Particle hair on `ob` (fur, grass, moss). radius: strand root radius (scene units)."""
    mod = ob.modifiers.new(name, "PARTICLE_SYSTEM")
    psys = ob.particle_systems[-1]
    psys.seed = seed
    ps = psys.settings
    ps.name = name
    ps.type = "HAIR"
    ps.use_advanced_hair = True
    ps.count = count
    ps.hair_length = length
    ps.emit_from = "FACE"
    ps.use_emit_random = True
    # Advanced hair: the strand is its emission velocity (normal, random and +Z parts), in scene units.
    ps.normal_factor = normal * length
    ps.factor_random = rand * length
    ps.object_align_factor = (0.0, 0.0, up * length)
    ps.length_random = length_rand
    ps.hair_step = steps
    ps.render_step = 3
    ps.display_step = 2
    ps.child_type = "INTERPOLATED" if children > 0 else "NONE"
    ps.child_percent = min(children, 10)
    ps.rendered_child_count = children
    ps.child_radius = child_radius
    ps.child_roundness = 0.5
    ps.clump_factor = clump
    ps.roughness_1 = rough[0]
    ps.roughness_1_size = 1.0
    ps.roughness_2 = rough[1]
    ps.roughness_2_size = 0.5
    ps.roughness_endpoint = rough[2]
    ps.kink = kink
    if kink == "CURL":
        ps.kink_amplitude = length * 0.25
        ps.kink_frequency = 2.0
    ps.root_radius = 1.0
    ps.tip_radius = tip
    ps.radius_scale = radius
    ps.use_close_tip = True
    ps.render_type = "PATH"
    ob.show_instancer_for_render = len(ob.data.materials) > 0 and ob.get("show_emitter", False)
    if group:
        psys.vertex_group_density = group
    if mat is not None:
        names = [m.name for m in ob.data.materials]
        if mat.name not in names:
            ob.data.materials.append(mat)
            names.append(mat.name)
        ps.material = names.index(mat.name) + 1


def emitter(name: str, loc, r: float, squash=(1.0, 1.0, 0.7)) -> bpy.types.Object:
    """A small hidden emitter (an icosphere the hair grows out of)."""
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=3, radius=r)
    for v in bm.verts:
        v.co = Vector((v.co.x * squash[0], v.co.y * squash[1], v.co.z * squash[2]))
    bm.to_mesh(me)
    bm.free()
    ob = link(bpy.data.objects.new(name, me))
    ob.location = loc
    ob.show_instancer_for_render = False
    return ob


def shard(name: str, base, direction, length: float, r: float, mat, sides: int = 6) -> bpy.types.Object:
    """A crystal: a faceted prism with a pointed tip (and a short point at the base)."""
    me = bpy.data.meshes.new(name)
    verts = [(0.0, 0.0, -r * 0.8)]
    for k in range(sides):
        a = math.tau * k / sides
        verts.append((math.cos(a) * r, math.sin(a) * r, 0.0))
    for k in range(sides):
        a = math.tau * k / sides
        verts.append((math.cos(a) * r * 0.92, math.sin(a) * r * 0.92, length * 0.72))
    verts.append((0.0, 0.0, length))
    faces = []
    for k in range(sides):
        k2 = (k + 1) % sides
        faces.append((0, 1 + k2, 1 + k))
        faces.append((1 + k, 1 + k2, 1 + sides + k2, 1 + sides + k))
        faces.append((1 + sides + k, 1 + sides + k2, 1 + 2 * sides))
    me.from_pydata(verts, [], faces)
    me.update()
    ob = link(bpy.data.objects.new(name, me))
    ob.location = base
    ob.rotation_euler = Vector(direction).normalized().to_track_quat("Z", "Y").to_euler()
    me.materials.append(mat)
    return ob


# ------------------------------------------------------------------ thorn growth

def wobble(pts, amp: float, freq: float, seed: int):
    """Offsets a resampled path sideways (in the paper's plane) by smooth noise."""
    out = []
    n = len(pts)
    for i, p in enumerate(pts):
        a = pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]
        t = Vector((a.x, a.y, 0.0)).normalized() if a.length > 1e-6 else Vector((1, 0, 0))
        side = Vector((-t.y, t.x, 0.0))
        k = i / max(n - 1, 1)
        fade = smoothstep(0.0, 0.08, k)
        w = noise.noise(Vector((i * freq, seed * 3.7, 0.5))) * amp * fade
        out.append(p + side * w)
    return out


CORNER_TURN = {"tl": 0.0, "tr": -90.0, "br": 180.0, "bl": 90.0}


def corner(shape: str):
    """For a corner piece: a function turning the top-left composition's (x, y) into this corner's
    (the poster corner stays at the origin; the light does not turn), and the camera centre."""
    a = math.radians(CORNER_TURN[shape])
    ca, sa = math.cos(a), math.sin(a)

    def P(pts):
        return [(x * ca - y * sa, x * sa + y * ca) for x, y in pts]
    c = P([(1.45, -1.45)])[0]
    return P, c


class Growth:
    """Collects the pieces of one thorn growth (tubes, knots, spikes) before they are fused."""

    def __init__(self, seed: int):
        self.rng = random.Random(seed)
        self.seed = seed
        self.parts = []
        # (point, radius, tangent) samples along every branch: where spikes, fur and accents attach.
        self.samples = []
        self.knots = []

    def branch(self, guide, r0: float, r1: float = 0.0, taper: float = 1.4, step: float = 0.05, wob: float = 0.05,
            lift: float = 0.0, spikes: float = 1.0, spike_len=(2.2, 5.0), z0: float = 0.0, record: bool = True,
            strands: int = 2, twist: float = 3.0, root: float = 0.0):
        """A tapering branch along `guide`: a core with `strands` thinner vines twisted round it (the
        remesh melts them into one sinewy, gappy limb), thorns along it. root: the first fraction of
        its length also tapers (to a point) instead of starting cut off."""
        pts = wobble(resample(guide, step), wob, 0.18, self.rng.randint(0, 999))
        n = len(pts)
        radii = []
        out_pts = []
        for i, p in enumerate(pts):
            k = i / max(n - 1, 1)
            r = r1 + (r0 - r1) * (1.0 - k) ** taper
            r *= 1.0 + 0.22 * noise.noise(Vector((i * 0.3, self.seed * 1.3, 2.0)))
            if root > 0.0:
                r *= 0.08 + 0.92 * smoothstep(0.0, root, k) ** 0.7
            z = r * 0.85 + z0 + lift * math.sin(math.pi * k) + 0.012 * noise.noise(Vector((i * 0.2, 4.0, self.seed)))
            out_pts.append(Vector((p.x, p.y, z)))
            radii.append(r)
        core = [r * (0.62 if strands else 1.0) for r in radii]
        self.parts.append(tube("Branch", out_pts, core))
        total = sum((out_pts[i + 1] - out_pts[i]).length for i in range(n - 1))
        for s in range(strands):
            ph = math.tau * s / strands + self.rng.uniform(-0.5, 0.5)
            spts = []
            srad = []
            for i, p in enumerate(out_pts):
                k = i / max(n - 1, 1)
                a = out_pts[min(i + 1, n - 1)] - out_pts[max(i - 1, 0)]
                t = a.normalized() if a.length > 1e-6 else Vector((1, 0, 0))
                side = Vector((-t.y, t.x, 0.0)).normalized()
                up = t.cross(side).normalized()
                th = ph + k * total * twist / max(r0 * 12.0, 0.3)
                off = radii[i] * (0.52 + 0.18 * noise.noise(Vector((i * 0.4, s * 5.0, self.seed))))
                q = p + (side * math.cos(th) + up * math.sin(th)) * off
                q.z = max(q.z, radii[i] * 0.3)
                spts.append(q)
                srad.append(radii[i] * (0.42 + 0.12 * noise.noise(Vector((i * 0.5, s * 3.0, 9.0)))) * (1.0 - 0.3 * k))
            srad[-1] = 0.0
            self.parts.append(tube("Strand", spts, srad, res=4))
        if record:
            for i, p in enumerate(out_pts):
                a = out_pts[min(i + 1, n - 1)] - out_pts[max(i - 1, 0)]
                self.samples.append((p, radii[i], a.normalized() if a.length > 1e-6 else Vector((1, 0, 0)), i / max(n - 1, 1)))
        if spikes > 0.0:
            self._spikes(out_pts, radii, spikes, spike_len)
        return out_pts, radii

    def _spikes(self, pts, radii, density: float, spike_len) -> None:
        n = len(pts)
        i = self.rng.randint(2, 5)
        side = 1.0 if self.rng.random() < 0.5 else -1.0
        while i < n - 4:
            p, r = pts[i], radii[i]
            if r < 0.012:
                break
            a = pts[i + 1] - pts[i - 1]
            t = Vector((a.x, a.y, 0.0)).normalized()
            ang = math.radians(self.rng.uniform(38, 72)) * side
            d = Matrix.Rotation(ang, 3, "Z") @ t
            d.z = self.rng.uniform(0.05, 0.45)
            d.normalize()
            ln = r * self.rng.uniform(*spike_len)
            self.spike(p + d * r * 0.4, d, ln, r * self.rng.uniform(0.45, 0.62), bend=t * 0.25)
            side = -side if self.rng.random() < 0.8 else side
            i += max(2, int(self.rng.uniform(1.4, 3.6) / density / max(r * 9.0, 0.35)))

    def spike(self, base, d, length: float, r: float, bend=Vector((0, 0, 0))) -> None:
        pts = []
        radii = []
        steps = 6
        for k in range(steps + 1):
            t = k / steps
            dd = (d + bend * t * t).normalized()
            pts.append(base + dd * length * t)
            radii.append(r * (1.0 - t) ** 1.25 + 0.0005)
        radii[-1] = 0.0
        self.parts.append(tube("Spike", pts, radii, res=4))

    def knot(self, loc, r: float, n: int = 8, squash: float = 0.75, coils: int = 3) -> None:
        """A gnarled knot: a cluster of lumpy bulbs of mixed sizes, short vines curling over them and
        stubby thorns."""
        c0 = Vector(loc)
        for k in range(n):
            a = self.rng.uniform(0, math.tau)
            o = Vector((math.cos(a), math.sin(a), 0.0)) * r * self.rng.uniform(0.0, 0.75)
            rr = r * self.rng.uniform(0.3, 0.75)
            c = c0 + o
            c.z = rr * squash * 0.75
            self.parts.append(blob("Knot", c, rr, (1.0, self.rng.uniform(0.7, 1.3), squash), self.rng.randint(0, 99), 0.45))
        for k in range(coils):
            a0 = self.rng.uniform(0, math.tau)
            sweep = self.rng.uniform(1.1, 1.9) * (1 if k % 2 else -1)
            r_in = r * self.rng.uniform(0.35, 0.6)
            r_out = r * self.rng.uniform(0.9, 1.25)
            pts = []
            rad = []
            m = 12
            for i in range(m + 1):
                t = i / m
                a = a0 + sweep * t
                rr = r_in + (r_out - r_in) * t
                pts.append(c0 + Vector((math.cos(a) * rr, math.sin(a) * rr, r * squash * (0.85 + 0.35 * math.sin(math.pi * t)))))
                rad.append(r * 0.18 * (1.0 - t) ** 0.8 + 0.002)
            rad[-1] = 0.0
            self.parts.append(tube("Coil", pts, rad, res=4))
        for k in range(self.rng.randint(4, 7)):
            a = self.rng.uniform(0, math.tau)
            d = Vector((math.cos(a), math.sin(a), self.rng.uniform(0.15, 0.6))).normalized()
            base = c0 + Vector((math.cos(a), math.sin(a), 0)) * r * 0.55
            base.z = r * squash * 0.7
            self.spike(base, d, r * self.rng.uniform(0.6, 1.3), r * 0.16)
        self.knots.append((c0, r))

    def fused(self, mat, voxel: float):
        # Broad, smooth swells (read as liquid metal at UI size), no fine crust (it turns to glitter).
        return fuse("Thorns", self.parts, voxel, smooth=(0.6, 6), lumps=(0.16, 0.032), crust=(0.0, 0.0), mat=mat)

    def pick(self, count: int, min_r: float = 0.0, k_range=(0.0, 1.0)):
        """Random branch samples (point, radius, tangent, k)."""
        pool = [s for s in self.samples if s[1] >= min_r and k_range[0] <= s[3] <= k_range[1]]
        self.rng.shuffle(pool)
        return pool[:count]


def accents(g: Growth, variant: str, fur: int, grass: int, crystals: int, beads: int) -> None:
    """Fur and grass tufts, and the variant's accents (blue crystal shards, or red jelly beads)."""
    rng = g.rng
    if variant == "black":
        fur = max(2, int(fur * 0.6))
        grass = max(2, int(grass * 0.6))
    fur_m = mat_hair("Fur", [(0.42, 0.48, 0.56), (0.6, 0.65, 0.72), (0.76, 0.78, 0.82)], rough=0.32, root_dark=0.45,
        principled_hair=True) if variant == "chrome" else \
        mat_hair("Fur", [(0.16, 0.16, 0.17), (0.28, 0.27, 0.27), (0.42, 0.41, 0.4)], rough=0.38, root_dark=0.45, principled_hair=True)
    grass_m = mat_hair("Grass", [(0.05, 0.12, 0.015), (0.12, 0.26, 0.03), (0.32, 0.36, 0.08), (0.42, 0.34, 0.12)], rough=0.5, root_dark=0.4)
    for i, (p, r, t, k) in enumerate(g.pick(fur, 0.02, (0.03, 0.6))):
        side = Vector((-t.y, t.x, 0.0)) * (1 if rng.random() < 0.5 else -1)
        c = p + side * r * 0.8
        c.z = max(0.015, r * 0.35)
        size = rng.uniform(0.03, 0.055)
        e = emitter("FurEm", c, size, (1.0, 1.0, 0.55))
        hair(e, "Fur", fur_m, 60, size * rng.uniform(0.9, 1.3), children=40, radius=0.0007, rough=(0.006, 0.008, 0.012),
            clump=0.25, normal=1.0, rand=0.5, up=0.25, seed=i, child_radius=0.12, steps=5)
    for i, (p, r, t, k) in enumerate(g.pick(grass, 0.02, (0.05, 0.8))):
        side = Vector((-t.y, t.x, 0.0)) * (1 if rng.random() < 0.5 else -1)
        c = p + side * r * 1.1
        c.z = 0.02
        e = emitter("GrassEm", c, 0.025, (1.0, 1.0, 0.5))
        hair(e, "Grass", grass_m, 8, rng.uniform(0.1, 0.2), children=5, radius=0.0035, rough=(0.0, 0.004, 0.0),
            normal=1.0, rand=0.35, up=0.35, seed=100 + i, child_radius=0.05, steps=5, length_rand=0.6)
    if variant == "chrome":
        blue = mat_crystal("Crystal", (0.035, 0.22, 1.0), 0.6)
        pale = mat_crystal("CrystalPale", (0.35, 0.65, 1.0), 0.25)
        spots = [kn for kn in g.knots] + [(s[0], s[1] * 1.6) for s in g.pick(crystals, 0.03, (0.1, 0.7))]
        for j, (p, r) in enumerate(spots[:crystals]):
            big = j < len(g.knots)
            a0 = rng.uniform(0, math.tau)
            for q in range(rng.randint(6, 9) if big else rng.randint(3, 5)):
                a = a0 + rng.uniform(-1.2, 1.2)
                d = Vector((math.cos(a), math.sin(a), rng.uniform(0.25, 0.8)))
                base = Vector(p) + Vector((math.cos(a), math.sin(a), 0)) * r * rng.uniform(0.3, 0.7)
                base.z = r * 0.45
                shard("Shard", base, d, rng.uniform(0.16, 0.36) * (1.5 if big else 0.95), rng.uniform(0.026, 0.046) * (1.35 if big else 0.95),
                    blue if q % 3 else pale)
    else:
        red = mat_jelly("RedJelly", (0.2, 0.004, 0.009))
        # Wet red jelly pooled where the thorns fork and swelling out of the knots.
        spots = [(kn + Vector((rng.uniform(-0.3, 0.3), rng.uniform(-0.3, 0.3), 0)) * kr, kr * 0.42) for kn, kr in g.knots] +             [(s[0], s[1] * rng.uniform(1.1, 1.5)) for s in g.pick(beads, 0.035, (0.05, 0.6))]
        for j, (p, rr) in enumerate(spots):
            c = Vector(p)
            c.z = rr * 0.55 + 0.02
            b = blob("Bead", c, rr, (1.0, rng.uniform(0.8, 1.15), 0.62), rng.randint(0, 99), 0.22)
            b.data.materials.append(red)
            for poly in b.data.polygons:
                poly.use_smooth = True
            sub = b.modifiers.new("sub", "SUBSURF")
            sub.levels = 1
            sub.render_levels = 2
        # A red eye: a glowing glass bead sunk in the main knot.
        for kn, kr in g.knots[:1]:
            eye = blob("Eye", Vector(kn) + Vector((kr * 0.1, kr * 0.05, kr * 0.62)), kr * 0.2, (1.0, 0.85, 0.7), 7, 0.04)
            eye.data.materials.append(mat_principled("EyeGlass", (0.6, 0.01, 0.005), 0.0, 0.04, coat=1.0,
                emit=(1.0, 0.012, 0.004), emit_str=2.2))
            for poly in eye.data.polygons:
                poly.use_smooth = True
            sub = eye.modifiers.new("sub", "SUBSURF")
            sub.render_levels = 2


def thorns(name: str, variant: str, shape: str) -> None:
    """Thorn growth. Coordinates: the poster's corner at the origin (top-left pieces: the poster lies
    at x > 0, y < 0)."""
    seed = {"tl": 11, "tr": 17, "br": 23, "bl": 29, "edge": 31, "clump_a": 41, "clump_b": 53}[shape]
    g = Growth(seed + (0 if variant == "chrome" else 500))
    if shape in CORNER_TURN:
        # Every corner is the top-left composition turned round its corner (each with its own seed).
        P, cc = corner(shape)
        reset(1024, 1024, 4.2, cc)
        kx, ky = P([(0.12, -0.1)])[0]
        g.knot((kx, ky, 0), 0.3, 10)
        g.branch(P([(-0.7, 0.22), (0.1, -0.08), (0.9, 0.06), (1.8, -0.05), (2.7, 0.08), (3.5, -0.02)]), 0.16, 0.0, 0.9, lift=0.05, root=0.1,
            spike_len=(2.6, 5.5))
        g.branch(P([(0.25, 0.7), (0.05, -0.2), (-0.08, -1.1), (0.08, -2.0), (-0.04, -2.8), (0.06, -3.55)]), 0.155, 0.0, 0.9, lift=0.04, root=0.1,
            spike_len=(2.6, 5.5))
        g.branch(P([(0.15, -0.12), (0.6, -0.5), (1.1, -0.82), (1.55, -1.25)]), 0.065, 0.0, 1.0, lift=0.12, spike_len=(2.0, 3.5))
        g.branch(P([(0.8, 0.03), (1.15, -0.25), (1.35, -0.45)]), 0.04, 0.0, 1.0, lift=0.06, spikes=0.6)
        g.branch(P([(0.02, -1.3), (0.35, -1.55), (0.55, -1.95)]), 0.04, 0.0, 1.0, lift=0.06, spikes=0.6)
        g.branch(P([(0.05, -0.05), (-0.25, -0.25), (-0.6, -0.55)]), 0.06, 0.0, 1.0, spikes=0.5, root=0.3)
        g.branch(P([(0.15, 0.0), (0.3, 0.15), (0.6, 0.45)]), 0.05, 0.0, 1.0, spikes=0.5, root=0.3)
        accents(g, variant, 5, 5, 4, 7)
    elif shape == "edge":
        reset(1024, 256, 6.4, (0.0, 0.0))
        g.knot((-1.1, 0.0, 0), 0.2, 5)
        g.knot((1.6, 0.02, 0), 0.16, 4)
        g.branch([(-3.4, 0.05), (-2.0, -0.08), (-1.1, 0.0), (0.0, 0.08), (1.0, -0.06), (1.6, 0.02), (2.5, 0.07), (3.35, -0.03)], 0.075, 0.03, 0.6, lift=0.03)
        g.branch([(-1.1, 0.0), (-0.6, 0.3), (-0.1, 0.42)], 0.04, 0.0, 1.0, lift=0.08, spikes=0.6)
        g.branch([(1.6, 0.02), (2.0, -0.28), (2.45, -0.4)], 0.035, 0.0, 1.0, lift=0.08, spikes=0.6)
        accents(g, variant, 12, 6, 3, 6)
    else:
        reset(640, 640, 1.9, (0.0, 0.0))
        g.knot((0.0, 0.0, 0), 0.2 if shape == "clump_a" else 0.16, 6)
        n = 5 if shape == "clump_a" else 4
        for k in range(n):
            a = math.tau * k / n + g.rng.uniform(-0.3, 0.3) + (0.4 if shape == "clump_b" else 0.0)
            L = g.rng.uniform(0.5, 0.8)
            mid = Vector((math.cos(a + 0.25), math.sin(a + 0.25), 0)) * L * 0.5
            end = Vector((math.cos(a), math.sin(a), 0)) * L
            g.branch([(0, 0), (mid.x, mid.y), (end.x, end.y)], 0.055, 0.0, 1.0, lift=0.05, spike_len=(1.8, 3.2))
        accents(g, variant, 6, 4, 2, 3)
    chrome = mat_chrome("Chrome", (0.27, 0.28, 0.3), (0.02, 0.09)) if variant == "chrome" else \
        mat_chrome("BlackChrome", (0.055, 0.055, 0.06), (0.03, 0.14))
    g.fused(chrome, 0.0075 if shape not in ("clump_a", "clump_b") else 0.004)
    sc = bpy.context.scene
    studio(tuple(sc.camera.location[:2]), 1.0, 1.0 if variant == "chrome" else 1.25)
    floor()
    render(name)


# ------------------------------------------------------------------ jelly and moss

def mat_led(name: str, color, lit: bool, diffused: bool = False):
    """An LED's epoxy lens (coloured glass, or milky diffused epoxy: diffused) and its die (emissive
    when lit)."""
    if diffused:
        # Milky coloured epoxy under a glassy coat: lit, it glows hottest where it faces you.
        lens = mat_principled(name + "Lens", color if lit else tuple(c * 0.2 for c in color), 0.0, 0.3, coat=1.0, coat_rough=0.02,
            spec=0.5, sss=0.4, sss_radius=(0.3, 0.3, 0.3), sss_scale=0.02)
        if lit:
            nt = lens.node_tree
            b = nt.nodes["Principled BSDF"]
            b.inputs["Emission Color"].default_value = (*color, 1)
            lw = _node(nt, "ShaderNodeLayerWeight", Blend=0.35)
            mr = nt.nodes.new("ShaderNodeMapRange")
            mr.inputs["To Min"].default_value = 2.4
            mr.inputs["To Max"].default_value = 0.45
            nt.links.new(lw.outputs["Facing"], mr.inputs["Value"])
            nt.links.new(mr.outputs["Result"], b.inputs["Emission Strength"])
        die = mat_principled(name + "Die", (0.2, 0.2, 0.2), 1.0, 0.3)
        return lens, die
    lens = mat_principled(name + "Lens", tuple(0.35 + 0.65 * c for c in color), 0.0, 0.06, trans=1.0, ior=1.52, spec=0.7)
    if lit:
        b = lens.node_tree.nodes["Principled BSDF"]
        b.inputs["Emission Color"].default_value = (*color, 1)
        b.inputs["Emission Strength"].default_value = 1.6
    nt = lens.node_tree
    va = _node(nt, "ShaderNodeVolumeAbsorption", Density=3.0 if lit else 9.0)
    va.inputs["Color"].default_value = (*color, 1)
    nt.links.new(va.outputs["Volume"], nt.nodes["Material Output"].inputs["Volume"])
    die = mat_emit_core(name + "Die", color, 3.0) if lit else mat_principled(name + "Die", (0.25, 0.25, 0.26), 1.0, 0.3)
    return lens, die


def led_bead(name: str, loc, r: float, color, lit: bool, sink: float = 0.35):
    """A round LED bead: a glass dome over a glowing die (sunk `sink` of its radius into what it
    sits on)."""
    lens, die = mat_led(name, color, lit)
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=48, v_segments=24, radius=r)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = True
    ob = link(bpy.data.objects.new(name, me))
    ob.location = Vector(loc) + Vector((0, 0, r * (1.0 - sink * 2.0) * 0.5))
    ob.scale = (1.0, 1.0, 0.82)
    me.materials.append(lens)
    me2 = bpy.data.meshes.new(name + "Die")
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=3, radius=r * 0.36)
    bm.to_mesh(me2)
    bm.free()
    d = link(bpy.data.objects.new(name + "Die", me2))
    d.location = ob.location + Vector((0, 0, -r * 0.1))
    me2.materials.append(die)
    return ob


def moss_group(ob: bpy.types.Object, seed: int, cover: float = 0.0, up: float = 0.35, clear=()) -> str:
    """A vertex group for moss: faces turned up, in patches (noise above `cover`), none within
    clear's (x, y, radius) circles."""
    vg = ob.vertex_groups.new(name="moss")
    off = Vector((seed * 1.7, seed * 0.3, 0.0))
    buckets = {}
    me = ob.data
    for v in me.vertices:
        nz = v.normal.z
        patch = noise.noise(v.co * 2.4 + off) + 0.45 * noise.noise(v.co * 7.0 + off)
        w = smoothstep(up, up + 0.4, nz) * smoothstep(cover - 0.12, cover + 0.12, patch)
        for cx, cy, cr in clear:
            w *= smoothstep(cr, cr * 1.6, math.hypot(v.co.x - cx, v.co.y - cy))
        if w > 0.02:
            buckets.setdefault(round(w, 2), []).append(v.index)
    for w, idx in buckets.items():
        vg.add(idx, w, "REPLACE")
    return "moss"


def jelly_mass(rng, parts, guide, r0: float, r1: float, bulge: float = 0.45, blobs: float = 1.0, veins: int = 2, drips: int = 2,
        root: float = 0.0):
    """A run of jelly along `guide`: a swelling tube, blobs bulging off it, raised veins and drips."""
    pts = wobble(resample(guide, 0.05), 0.07, 0.15, rng.randint(0, 999))
    n = len(pts)
    seed = rng.randint(0, 999)
    rad = []
    out = []
    for i, p in enumerate(pts):
        k = i / max(n - 1, 1)
        r = (r0 + (r1 - r0) * k) * (1.0 + bulge * noise.noise(Vector((i * 0.12, seed, 1.0))))
        if root > 0.0:
            r *= 0.15 + 0.85 * smoothstep(0.0, root, k)
        out.append(Vector((p.x, p.y, r * 0.75)))
        rad.append(max(r, 0.004))
    rad[-1] *= 0.35
    parts.append(tube("Mass", out, rad, res=6))
    i = rng.randint(1, 4)
    while i < n - 2 and blobs > 0.0:
        p, r = out[i], rad[i]
        a = out[min(i + 1, n - 1)] - out[max(i - 1, 0)]
        t = Vector((a.x, a.y, 0)).normalized()
        side = Vector((-t.y, t.x, 0))
        c = p + side * r * rng.uniform(-0.8, 0.8)
        rr = r * rng.uniform(0.7, 1.3)
        c.z = rr * 0.6
        parts.append(blob("Lobe", c, rr, (rng.uniform(0.9, 1.4), rng.uniform(0.8, 1.2), 0.7), rng.randint(0, 99), 0.3))
        i += max(2, int(rng.uniform(3, 7) / blobs))
    for v in range(veins):
        ph = rng.uniform(0, math.tau)
        vp = []
        vr = []
        for i, p in enumerate(out):
            k = i / max(n - 1, 1)
            a = out[min(i + 1, n - 1)] - out[max(i - 1, 0)]
            t = Vector((a.x, a.y, 0)).normalized()
            side = Vector((-t.y, t.x, 0))
            w = math.sin(ph + k * rng.uniform(5, 9)) * rad[i] * 0.55
            q = p + side * w
            q.z = rad[i] * 1.32
            vp.append(q)
            vr.append(rad[i] * 0.16)
        vr[0] = vr[-1] = 0.0
        parts.append(tube("Vein", vp, vr, res=4))
    for d in range(drips):
        i = rng.randint(int(n * 0.15), int(n * 0.85))
        p, r = out[i], rad[i]
        a = out[min(i + 1, n - 1)] - out[max(i - 1, 0)]
        t = Vector((a.x, a.y, 0)).normalized()
        side = Vector((-t.y, t.x, 0)) * (1 if rng.random() < 0.5 else -1)
        L = r * rng.uniform(2.0, 4.5)
        q = [p + side * r * 0.6, p + side * (r + L * 0.5) + t * L * 0.15, p + side * (r + L) + t * L * 0.25]
        for qq in q:
            qq.z = 0.02
        q[0].z = r * 0.5
        dr = r * rng.uniform(0.18, 0.28)
        parts.append(tube("Drip", q, [dr * 1.6, dr * 0.7, dr], res=4))
        e = q[-1].copy()
        e.z = dr * 0.8
        parts.append(blob("Drop", e, dr * 1.4, (1.0, 1.0, 0.7), rng.randint(0, 99), 0.1))
    return out, rad


def jelly(name: str, shape: str) -> None:
    """Jelly and moss growth (the Infernal accent): coordinates as thorns()."""
    seed = {"tl": 61, "tr": 67, "br": 73, "bl": 79, "edge": 83, "clump": 97}[shape]
    rng = random.Random(seed)
    parts = []
    leds = []
    if shape in CORNER_TURN:
        P, cc = corner(shape)
        reset(1024, 1024, 4.2, cc)
        for (bx, by), r, sq, sd in (((0.1, -0.08), 0.46, (1.15, 1.0, 0.62), 3), ((0.62, 0.04), 0.3, (1.3, 0.9, 0.6), 5),
                ((-0.02, -0.66), 0.3, (0.9, 1.3, 0.6), 8), ((0.42, -0.42), 0.22, (1.0, 1.0, 0.6), 11)):
            x, y = P([(bx, by)])[0]
            parts.append(blob("Core", (x, y, r * 0.42), r, sq, sd, 0.32))
        jelly_mass(rng, parts, P([(-0.6, 0.15), (0.2, -0.05), (1.1, 0.06), (2.0, -0.04), (2.9, 0.05), (3.5, -0.02)]), 0.24, 0.07,
            bulge=0.5, root=0.06)
        jelly_mass(rng, parts, P([(0.18, 0.55), (0.0, -0.3), (-0.06, -1.2), (0.07, -2.1), (-0.03, -3.0), (0.04, -3.55)]), 0.23, 0.07,
            bulge=0.5, root=0.06)
        jelly_mass(rng, parts, P([(0.3, -0.2), (0.8, -0.5), (1.3, -0.85)]), 0.09, 0.03, blobs=0.6, veins=1, drips=1)
        leds = [(P([(0.36, -0.36)])[0], (1.0, 0.02, 0.01)), (P([(1.6, 0.02)])[0], (1.0, 0.02, 0.01)),
            (P([(0.02, -1.8)])[0], (0.05, 0.75, 1.0))]
    elif shape == "edge":
        reset(1024, 256, 6.4, (0.0, 0.0))
        jelly_mass(rng, parts, [(-3.4, 0.02), (-2.2, -0.06), (-1.0, 0.04), (0.2, -0.05), (1.4, 0.05), (2.5, -0.04), (3.4, 0.02)], 0.15, 0.12,
            bulge=0.5, root=0.06)
        leds = [((-1.6, 0.0), (1.0, 0.02, 0.01)), ((1.1, 0.02), (0.05, 0.75, 1.0)), ((2.6, -0.02), (1.0, 0.02, 0.01))]
    else:
        reset(640, 640, 1.9, (0.0, 0.0))
        parts.append(blob("Core", (0.0, 0.0, 0.15), 0.36, (1.2, 1.0, 0.6), 4, 0.35))
        jelly_mass(rng, parts, [(-0.75, 0.2), (-0.2, 0.05), (0.3, -0.1), (0.75, -0.3)], 0.14, 0.04, veins=1, drips=2, root=0.15)
        leds = [((0.12, 0.05), (1.0, 0.02, 0.01))]
    jm = mat_jelly("Jelly")
    ob = fuse("Jelly", parts, 0.008, smooth=(0.8, 10), lumps=(0.14, 0.03), crust=(0.0, 0.0), mat=jm)
    # It slumps on the paper.
    for v in ob.data.vertices:
        v.co.z = max(v.co.z * 0.78, -0.02)
    ob.data.update()
    ob["show_emitter"] = True
    grp = moss_group(ob, seed, cover=-0.05 if shape != "edge" else 0.05, clear=[(xy[0], xy[1], 0.16) for xy, _c in leds])
    # Moss: short, dense, fuzzy cushions (fuzzy tips), yellower where they catch the light.
    moss_m = mat_hair("Moss", [(0.04, 0.06, 0.006), (0.1, 0.17, 0.016), (0.22, 0.32, 0.035), (0.46, 0.5, 0.09)], rough=0.65, root_dark=0.75)
    area_w = sum(p.area for p in ob.data.polygons) * 0.4
    hair(ob, "Moss", moss_m, int(min(36000, area_w * 11000)), 0.019, children=26, radius=0.0006, rough=(0.007, 0.006, 0.012),
        clump=0.15, normal=1.0, rand=0.5, up=0.55, group=grp, seed=seed, child_radius=0.02, steps=4, length_rand=0.65)
    ob.show_instancer_for_render = True
    # LED beads sunk into the jelly where it is.
    bvh = BVHTree.FromObject(ob, bpy.context.evaluated_depsgraph_get())
    for j, (xy, col) in enumerate(leds):
        hit = bvh.ray_cast(Vector((xy[0], xy[1], 5.0)), Vector((0, 0, -1)))
        z = hit[0].z if hit[0] is not None else 0.1
        led_bead("Bead%d" % j, (xy[0], xy[1], z), 0.085, col, True, 0.4)
    sc = bpy.context.scene
    studio(tuple(sc.camera.location[:2]), 1.0, 0.8)
    floor()
    render(name)


# ------------------------------------------------------------------ hardware

def lathe(name: str, profile, mat, steps: int = 128) -> bpy.types.Object:
    """Revolves a (radius, z) profile around Z (smooth)."""
    me = bpy.data.meshes.new(name)
    me.from_pydata([(r, 0.0, z) for r, z in profile], [(i, i + 1) for i in range(len(profile) - 1)], [])
    ob = link(bpy.data.objects.new(name, me))
    s = ob.modifiers.new("lathe", "SCREW")
    s.axis = "Z"
    s.steps = steps
    s.render_steps = steps
    s.use_smooth_shade = True
    s.use_merge_vertices = True
    me.use_auto_smooth = True
    me.auto_smooth_angle = math.radians(40)
    if mat:
        me.materials.append(mat)
    return ob


def mat_candy(name: str = "Candy", base=(0.15, 0.001, 0.004)) -> bpy.types.Material:
    """Glossy deep-red plastic with depth (subsurface) under a clear coat."""
    return mat_principled(name, base, 0.0, 0.28, coat=1.0, coat_rough=0.02, spec=0.4, sss=0.5, sss_radius=(1.0, 0.06, 0.03),
        sss_scale=0.08)


def mat_knurl(name: str = "Knurl") -> bpy.types.Material:
    """Silver with a diamond knurl (two crossed helical grooves) as bump, polar about the object."""
    m = mat_principled(name, (0.5, 0.51, 0.53), 1.0, 0.32)
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(tc.outputs["Object"], sep.inputs["Vector"])
    ang = nt.nodes.new("ShaderNodeMath")
    ang.operation = "ARCTAN2"
    nt.links.new(sep.outputs["Y"], ang.inputs[0])
    nt.links.new(sep.outputs["X"], ang.inputs[1])
    ln = nt.nodes.new("ShaderNodeVectorMath")
    ln.operation = "LENGTH"
    nt.links.new(tc.outputs["Object"], ln.inputs[0])
    outs = []
    for sgn in (1.0, -1.0):
        a = nt.nodes.new("ShaderNodeMath")
        a.operation = "MULTIPLY"
        a.inputs[1].default_value = 64.0
        nt.links.new(ang.outputs[0], a.inputs[0])
        r = nt.nodes.new("ShaderNodeMath")
        r.operation = "MULTIPLY"
        r.inputs[1].default_value = 260.0 * sgn
        nt.links.new(ln.outputs["Value"], r.inputs[0])
        s = nt.nodes.new("ShaderNodeMath")
        s.operation = "ADD"
        nt.links.new(a.outputs[0], s.inputs[0])
        nt.links.new(r.outputs[0], s.inputs[1])
        sn = nt.nodes.new("ShaderNodeMath")
        sn.operation = "SINE"
        nt.links.new(s.outputs[0], sn.inputs[0])
        ab = nt.nodes.new("ShaderNodeMath")
        ab.operation = "ABSOLUTE"
        nt.links.new(sn.outputs[0], ab.inputs[0])
        outs.append(ab)
    mn = nt.nodes.new("ShaderNodeMath")
    mn.operation = "MINIMUM"
    nt.links.new(outs[0].outputs[0], mn.inputs[0])
    nt.links.new(outs[1].outputs[0], mn.inputs[1])
    bump = _node(nt, "ShaderNodeBump", Strength=0.9, Distance=0.004)
    nt.links.new(mn.outputs[0], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], b.inputs["Normal"])
    return m


def mat_turned(name: str = "Turned", base=(0.8, 0.81, 0.83), rough: float = 0.16) -> bpy.types.Material:
    """Lathe-turned silver: fine concentric rings (bump), anisotropic round the axis."""
    m = mat_principled(name, base, 1.0, rough)
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    b.inputs["Anisotropic"].default_value = 0.7
    tan = nt.nodes.new("ShaderNodeTangent")
    tan.direction_type = "RADIAL"
    tan.axis = "Z"
    nt.links.new(tan.outputs["Tangent"], b.inputs["Tangent"])
    tc = nt.nodes.new("ShaderNodeTexCoord")
    rings = _node(nt, "ShaderNodeTexWave", Scale=60.0, Distortion=0.4, Detail=2.0)
    rings.wave_type = "RINGS"
    nt.links.new(tc.outputs["Object"], rings.inputs["Vector"])
    bump = _node(nt, "ShaderNodeBump", Strength=0.06, Distance=0.003)
    nt.links.new(rings.outputs["Fac"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], b.inputs["Normal"])
    return m


def hardware_studio(c=(0.0, 0.0), crisp: bool = False, horizon: float = 0.2) -> None:
    """The product-shot studio for the hardware: a big diffused overhead box (offset top left) for the
    broad highlight on domes and caps, diffused side boxes for soft rims (crisp: hard strips instead,
    the bright edge lines acrylic needs)."""
    cx, cy = c
    world(1.0, top=0.03, horizon=horizon, city=0.25)
    k = KEY_DIR * 11.0
    area((cx + k.x, cy + k.y, k.z), 1600.0, 4.0, (cx, cy, 0), glossy=False)
    area((cx + 6.0, cy - 6.0, 6.0), 300.0, 6.0, (cx, cy, 0), glossy=False)
    card("Soft", (cx - 2.0, cy + 2.6, 6.0), (4.2, 3.4), 6.0, look_at=(cx, cy, 0), soft=True)
    if crisp:
        card("StripR", (cx + 6.5, cy + 0.5, 2.0), (0.5, 9.0), 14.0, look_at=(cx, cy, 0.3))
        card("StripT", (cx, cy + 6.5, 2.2), (9.0, 0.45), 12.0, look_at=(cx, cy, 0.3))
    else:
        card("SideR", (cx + 6.0, cy + 0.5, 2.4), (3.0, 7.0), 7.0, look_at=(cx, cy, 0.3), soft=True)
        card("SideT", (cx - 0.5, cy + 6.0, 2.6), (7.0, 2.6), 6.0, look_at=(cx, cy, 0.3), soft=True)
    card("RimB", (cx + 0.5, cy - 6.5, 1.2), (8.0, 1.6), 3.0, look_at=(cx, cy, 0.2), soft=True)
    card("RimL", (cx - 6.5, cy - 0.5, 1.2), (1.6, 8.0), 3.0, look_at=(cx, cy, 0.2), soft=True)


def dome(name: str, pressed: bool) -> None:
    """A glossy red ellipsoid push dome on a black rubber seat."""
    reset(560, 480, 1.75, (0.0, 0.0))
    me = bpy.data.meshes.new("Dome")
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=96, v_segments=48, radius=1.0)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = True
    d = link(bpy.data.objects.new("Dome", me))
    h = 0.24 if pressed else 0.36
    d.scale = (0.66, 0.54, h)
    d.location = (0.0, 0.0, -0.02 if pressed else 0.0)
    me.materials.append(mat_candy())
    seat = lathe("Seat", [(0.0, 0.0), (0.62, 0.0), (0.7, 0.012), (0.71, 0.03), (0.64, 0.045), (0.0, 0.045)],
        mat_principled("Rubber", (0.025, 0.025, 0.028), 0.0, 0.55, spec=0.3))
    seat.scale = (1.0, 0.82, 1.0)
    hardware_studio()
    floor()
    render(name)


def bezel(name: str, pressed: bool) -> None:
    """A red cap in a knurled silver bezel (the cap sits lower when pressed)."""
    reset(512, 512, 1.6, (0.0, 0.0))
    knurl = mat_knurl()
    turned = mat_turned()
    # Knurled flank and top ring, a turned chamfer, the well.
    lathe("BezelOut", [(0.0, 0.0), (0.7, 0.0), (0.7, 0.03), (0.64, 0.15), (0.6, 0.16), (0.555, 0.16)], knurl)
    lathe("BezelIn", [(0.555, 0.16), (0.53, 0.158), (0.49, 0.12), (0.475, 0.11), (0.47, 0.03), (0.0, 0.03)], turned)
    top = 0.13 if pressed else 0.21
    cap = lathe("Cap", [(0.0, top), (0.36, top - 0.004), (0.43, top - 0.03), (0.452, top - 0.07), (0.455, 0.03), (0.0, 0.03)], mat_candy())
    cap.data.auto_smooth_angle = math.radians(60)
    hardware_studio()
    floor()
    render(name)


LED_COLORS = {"green": (0.08, 1.0, 0.18), "orange": (1.0, 0.17, 0.006), "red": (1.0, 0.025, 0.012), "cyan": (0.04, 0.78, 1.0)}


def led(name: str, color: str, lit: bool) -> None:
    """A domed LED in a black rubber grommet."""
    reset(192, 192, 0.42, (0.0, 0.0))
    # The grommet's lip rises over the lens's foot (no bright glass wall to catch the room).
    lathe("Grommet", [(0.0, 0.0), (0.142, 0.0), (0.15, 0.015), (0.146, 0.042), (0.128, 0.06), (0.106, 0.058), (0.1, 0.035), (0.0, 0.035)],
        mat_principled("Grommet", (0.02, 0.02, 0.022), 0.0, 0.45, spec=0.35))
    col = LED_COLORS[color]
    lens, die = mat_led("Led", col, lit, True)
    lathe("Lens", [(0.0, 0.0), (0.104, 0.0), (0.103, 0.04), (0.094, 0.066), (0.076, 0.09), (0.048, 0.106), (0.0, 0.114)], lens)
    lathe("Die", [(0.0, 0.03), (0.03, 0.03), (0.03, 0.05), (0.0, 0.05)], die, 32)
    hardware_studio(horizon=0.06)
    floor()
    render(name)


# ------------------------------------------------------------------ acrylic (rendered twice, over black and over white)

def rounded_slab(name: str, w: float, h: float, t: float, r: float, bevel: float, hole=None) -> bpy.types.Object:
    """A rounded-rectangle slab of thickness t (top at z = t), bevelled edges, an optional round hole
    (x, y, radius)."""
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    pts = []
    seg = 16
    for cx, cy, a0 in ((w / 2 - r, h / 2 - r, 0.0), (-w / 2 + r, h / 2 - r, 90.0), (-w / 2 + r, -h / 2 + r, 180.0), (w / 2 - r, -h / 2 + r, 270.0)):
        for k in range(seg + 1):
            a = math.radians(a0 + 90.0 * k / seg)
            pts.append((cx + math.cos(a) * r, cy + math.sin(a) * r))
    bottom = [bm.verts.new((x, y, 0.0)) for x, y in pts]
    top = [bm.verts.new((x, y, t)) for x, y in pts]
    n = len(pts)
    bm.faces.new(list(reversed(bottom)))
    bm.faces.new(top)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((bottom[i], bottom[j], top[j], top[i]))
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    ob = link(bpy.data.objects.new(name, me))
    if hole:
        bpy.ops.mesh.primitive_cylinder_add(vertices=96, radius=hole[2], depth=t * 4, location=(hole[0], hole[1], t * 0.5))
        cut = bpy.context.object
        bo = ob.modifiers.new("hole", "BOOLEAN")
        bo.object = cut
        bo.solver = "EXACT"
        bo.operation = "DIFFERENCE"
        cut.hide_render = True
    bv = ob.modifiers.new("bevel", "BEVEL")
    bv.width = bevel
    bv.segments = 5
    bv.limit_method = "ANGLE"
    bv.angle_limit = math.radians(50)
    me.use_auto_smooth = True
    me.auto_smooth_angle = math.radians(35)
    for p in me.polygons:
        p.use_smooth = True
    return ob


def mat_acrylic(name: str, tint, rough: float, absorb: float):
    """Acrylic: clear (or tinted) transmission, frosted faces and polished edges, a little absorption."""
    m = mat_principled(name, tint, 0.0, rough, trans=1.0, ior=1.49, spec=0.5)
    nt = m.node_tree
    if absorb > 0.0:
        va = _node(nt, "ShaderNodeVolumeAbsorption", Density=absorb)
        va.inputs["Color"].default_value = (*tint, 1)
        nt.links.new(va.outputs["Volume"], nt.nodes["Material Output"].inputs["Volume"])
    b = nt.nodes["Principled BSDF"]
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(geo.outputs["Normal"], sep.inputs["Vector"])
    ab = nt.nodes.new("ShaderNodeMath")
    ab.operation = "ABSOLUTE"
    nt.links.new(sep.outputs["Z"], ab.inputs[0])
    mr = nt.nodes.new("ShaderNodeMapRange")
    mr.inputs["From Min"].default_value = 0.9
    mr.inputs["From Max"].default_value = 0.99
    mr.inputs["To Min"].default_value = 0.02
    mr.inputs["To Max"].default_value = rough
    nt.links.new(ab.outputs[0], mr.inputs["Value"])
    nt.links.new(mr.outputs["Result"], b.inputs["Roughness"])
    return m


def backdrop(level: float) -> None:
    """The emissive backdrop the acrylic is seen against (camera and transmission rays only)."""
    bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, -0.002))
    p = bpy.context.object
    p.name = "Backdrop"
    p.data.materials.append(mat_emit_core("Backdrop", (1.0, 1.0, 1.0), level))
    p.visible_diffuse = False
    p.visible_glossy = False
    p.visible_shadow = False
    p.visible_volume_scatter = False


def acrylic(name: str, kind: str) -> None:
    for level, suffix in ((0.0, "_black"), (1.0, "_white")):
        if kind == "tab":
            reset(320, 720, 2.9, (0.0, 0.0), raw=True, transparent=False)
            slab = rounded_slab("Tab", 1.05, 2.5, 0.09, 0.09, 0.022)
            slab.data.materials.append(mat_acrylic("Clear", (0.93, 0.96, 0.97), 0.32, 0.4))
            # A steel grommet near the foot (it hangs by it).
            ey = lathe("Eyelet", [(0.06, 0.09), (0.1, 0.09), (0.115, 0.1), (0.11, 0.115), (0.085, 0.118), (0.06, 0.105), (0.055, 0.0),
                (0.06, 0.09)], mat_turned("Eyelet", (0.8, 0.8, 0.82), 0.2))
            ey.location = (0.0, -1.02, 0.0)
        else:
            reset(800, 380, 2.72, (0.0, 0.0), raw=True, transparent=False)
            hole = (0.86, 0.2, 0.18)
            slab = rounded_slab("Card", 2.5, 1.12, 0.07, 0.07, 0.016, hole)
            slab.data.materials.append(mat_acrylic("Orange", (1.0, 0.22, 0.012), 0.16, 3.5))
            # The printed halftone dot grid (ink on the top face), growing toward the bottom right.
            ink = mat_principled("Ink", (0.02, 0.012, 0.01), 0.0, 0.55, spec=0.3)
            me = bpy.data.meshes.new("Dots")
            verts, faces = [], []
            step = 0.05
            nx, ny = int(2.3 / step), int(0.98 / step)
            for j in range(ny):
                for i in range(nx):
                    x = -1.15 + (i + 0.5) * step
                    y = -0.49 + (j + 0.5) * step
                    if (x - hole[0]) ** 2 + (y - hole[1]) ** 2 < (hole[2] + 0.03) ** 2:
                        continue
                    k = smoothstep(-0.25, 1.1, x * 0.62 - y * 0.55)
                    rr = step * 0.5 * k * 0.92
                    if rr < 0.004:
                        continue
                    base = len(verts)
                    for q in range(12):
                        a = math.tau * q / 12
                        verts.append((x + math.cos(a) * rr, y + math.sin(a) * rr, 0.0705))
                    faces.append(tuple(range(base, base + 12)))
            me.from_pydata(verts, [], faces)
            me.materials.append(ink)
            link(bpy.data.objects.new("Dots", me))
        hardware_studio(crisp=True)
        backdrop(level)
        render(name + suffix)


# ------------------------------------------------------------------ jobs

JOBS = {}
for _v in ("chrome", "black"):
    for _s in ("tl", "tr", "br", "bl", "edge", "clump_a", "clump_b"):
        JOBS["thorn_%s_%s" % (_v, _s)] = (lambda n, v=_v, s=_s: thorns(n, v, s))
for _s in ("tl", "tr", "br", "bl", "edge", "clump"):
    JOBS["jelly_" + _s] = (lambda n, s=_s: jelly(n, s))
for _p in (False, True):
    JOBS["dome_" + ("down" if _p else "up")] = (lambda n, p=_p: dome(n, p))
    JOBS["bezel_" + ("down" if _p else "up")] = (lambda n, p=_p: bezel(n, p))
for _c in LED_COLORS:
    for _l in (True, False):
        JOBS["led_%s_%s" % (_c, "on" if _l else "off")] = (lambda n, c=_c, l=_l: led(n, c, l))
JOBS["acrylic_tab"] = lambda n: acrylic(n, "tab")
JOBS["acrylic_card"] = lambda n: acrylic(n, "card")


def wanted(name: str) -> bool:
    if WANT == "all":
        return True
    for w in WANT.split(","):
        if w == name or (w.endswith("*") and name.startswith(w[:-1])):
            return True
    return False


for job, fn in JOBS.items():
    if wanted(job):
        fn(job)
