"""Halo & Horn collage objects for the Rival's poster and the print album (style v4, the poster look
with the physical pieces of the owner's 2026-10-19 references, rebuilt from code, never traced).

    blender --background --factory-startup --python tools/blender/rival_objects.py -- <out_dir> <which> [samples] [gpu|cpu]

which: comma list or "all" of
  thorns_corner  black chrome thorn growth (lumpy melted metal, spikes, blue crystal, white fur tufts
                 and a few grass blades) spreading from a corner along two edges
  thorns_vine    the same growth as a long vine along one edge
  dome           a glossy red ellipsoid dome (a gem stuck on the poster)
  button         a red push button in a knurled silver bezel
  acrylic        an orange translucent acrylic card with a printed halftone dot grid and a round cut-out
                 (unused: the record card is the acrylic.gdshader version, which can carry live type)
  seal           a seal of glossy dark-red jelly, dripping, overgrown with moss, a red and a cyan LED in it
Every object sits on a shadow catcher (its contact shadow is in the alpha), lit by the shared studio
(Blender's bundled city.exr, desaturated, plus emissive cards), Standard view at exposure -0.45 and
an orthographic camera looking down at the poster. Writes <out_dir>/<which>.png (16-bit RGBA).
tools/blender/finish_objects.py rival <out_dir> crops them into assets/art/ui/objects/.
cpu: renders on the CPU (fewer samples, OpenImageDenoise) so a GPU job running beside it never
runs out of memory.
"""
import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

argv = sys.argv[sys.argv.index("--") + 1:]
OUT = argv[0]
ALL = ["thorns_corner", "thorns_vine", "dome", "button", "seal"]
WHICH = ALL if len(argv) < 2 or argv[1] == "all" else argv[1].split(",")
SAMPLES = int(argv[2]) if len(argv) > 2 else 160
DEVICE = argv[3] if len(argv) > 3 else "gpu"
os.makedirs(OUT, exist_ok=True)

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
sc.render.engine = "CYCLES"
if DEVICE == "gpu":
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
sc.cycles.samples = SAMPLES
sc.cycles.use_denoising = True
sc.cycles.max_bounces = 10
sc.cycles.transmission_bounces = 10
sc.render.film_transparent = True
sc.cycles.film_transparent_glass = True
sc.render.image_settings.file_format = "PNG"
sc.render.image_settings.color_mode = "RGBA"
sc.render.image_settings.color_depth = "16"
sc.view_settings.view_transform = "Standard"
sc.view_settings.look = "Medium High Contrast"
sc.view_settings.exposure = -0.45

STUDIO = bpy.data.collections.new("Studio")
sc.collection.children.link(STUDIO)
ITEM = bpy.data.collections.new("Item")
sc.collection.children.link(ITEM)

# Signal red-orange #ff4b1f in linear (Blender colours are linear).
SIGNAL = (1.0, 0.0704, 0.0137)


def move_to(ob, coll):
    for c in list(ob.users_collection):
        c.objects.unlink(ob)
    coll.objects.link(ob)


def studio():
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
    hs.inputs["Saturation"].default_value = 0.0
    mp = nt.nodes.new("ShaderNodeMapping")
    co = nt.nodes.new("ShaderNodeTexCoord")
    mp.inputs["Rotation"].default_value = (0, 0, math.radians(140))
    nt.links.new(co.outputs["Generated"], mp.inputs["Vector"])
    nt.links.new(mp.outputs["Vector"], env.inputs["Vector"])
    nt.links.new(env.outputs["Color"], hs.inputs["Color"])
    nt.links.new(hs.outputs["Color"], bg.inputs["Color"])
    bg.inputs["Strength"].default_value = 0.6
    nt.links.new(bg.outputs["Background"], out.inputs["Surface"])
    card("SoftTop", (0, 1.5, 7.0), (math.radians(-12), 0, 0), (8, 3), 6.0)
    card("StripL", (-6.0, -1.5, 2.0), (0, math.radians(-70), 0), (10, 0.7), 12.0)
    card("StripR", (6.0, 0.5, 1.5), (0, math.radians(75), 0), (10, 0.5), 9.0)
    card("Rim", (0, 7.0, 2.5), (math.radians(-78), 0, 0), (9, 0.8), 6.0)
    light((-4, -4, 7), 1500, 4.0)
    light((5, -3, 3), 450, 3.0)


def card(name, loc, rot, size, strength):
    bpy.ops.mesh.primitive_plane_add(size=1, location=loc, rotation=rot)
    p = bpy.context.object
    p.name = name
    p.scale = (size[0], size[1], 1)
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    o = nt.nodes.new("ShaderNodeOutputMaterial")
    e = nt.nodes.new("ShaderNodeEmission")
    e.inputs["Strength"].default_value = strength
    nt.links.new(e.outputs["Emission"], o.inputs["Surface"])
    p.data.materials.append(m)
    p.visible_camera = False
    p.visible_shadow = False
    move_to(p, STUDIO)


def light(loc, energy, size):
    bpy.ops.object.light_add(type="AREA", location=loc)
    l = bpy.context.object
    l.data.energy = energy
    l.data.size = size
    l.rotation_euler = (Vector((0, 0, 0)) - l.location).to_track_quat("-Z", "Y").to_euler()
    move_to(l, STUDIO)


def smooth(ob, angle=40):
    for p in ob.data.polygons:
        p.use_smooth = True
    ob.data.use_auto_smooth = True
    ob.data.auto_smooth_angle = math.radians(angle)


def shadow_catcher(size=30.0):
    bpy.ops.mesh.primitive_plane_add(size=size, location=(0, 0, 0))
    p = bpy.context.object
    p.name = "Catcher"
    p.is_shadow_catcher = True
    move_to(p, ITEM)
    return p


# ------------------------------------------------------------------ materials

def principled(name, base, metallic=0.0, rough=0.4, coat=0.0, trans=0.0, ior=1.45, emit=None, emit_str=0.0,
               bump=0.0, bump_scale=30.0, alpha=1.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*base, 1)
    b.inputs["Metallic"].default_value = metallic
    b.inputs["Roughness"].default_value = rough
    if coat > 0.0:
        b.inputs["Coat Weight"].default_value = coat
        b.inputs["Coat Roughness"].default_value = 0.03
    if trans > 0.0:
        b.inputs["Transmission Weight"].default_value = trans
        b.inputs["IOR"].default_value = ior
    if emit is not None:
        b.inputs["Emission Color"].default_value = (*emit, 1)
        b.inputs["Emission Strength"].default_value = emit_str
    if alpha < 1.0:
        b.inputs["Alpha"].default_value = alpha
    if bump > 0.0:
        tc = nt.nodes.new("ShaderNodeTexCoord")
        nz = nt.nodes.new("ShaderNodeTexNoise")
        nz.inputs["Scale"].default_value = bump_scale
        nz.inputs["Detail"].default_value = 10.0
        nz.inputs["Roughness"].default_value = 0.6
        nt.links.new(tc.outputs["Object"], nz.inputs["Vector"])
        bp = nt.nodes.new("ShaderNodeBump")
        bp.inputs["Strength"].default_value = bump
        bp.inputs["Distance"].default_value = 0.02
        nt.links.new(nz.outputs["Fac"], bp.inputs["Height"])
        nt.links.new(bp.outputs["Normal"], b.inputs["Normal"])
    return m


def hair_material(name, color, melanin=0.0, rough=0.35):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    o = nt.nodes.new("ShaderNodeOutputMaterial")
    h = nt.nodes.new("ShaderNodeBsdfHairPrincipled")
    h.parametrization = "COLOR"
    h.inputs["Color"].default_value = (*color, 1)
    h.inputs["Roughness"].default_value = rough
    h.inputs["Radial Roughness"].default_value = 0.6
    nt.links.new(h.outputs["BSDF"], o.inputs["Surface"])
    return m


# ------------------------------------------------------------------ thorn growth

def tube(name, pts, radii, mat, res=6):
    cu = bpy.data.curves.new(name, "CURVE")
    cu.dimensions = "3D"
    cu.bevel_depth = 1.0
    cu.bevel_resolution = 3
    cu.use_fill_caps = True
    sp = cu.splines.new("NURBS")
    sp.points.add(len(pts) - 1)
    for i, (p, r) in enumerate(zip(pts, radii)):
        sp.points[i].co = (p.x, p.y, p.z, 1.0)
        sp.points[i].radius = r
    sp.order_u = 4
    sp.use_endpoint_u = True
    sp.resolution_u = res
    ob = bpy.data.objects.new(name, cu)
    ITEM.objects.link(ob)
    cu.materials.append(mat)
    return ob


def cone(loc, direction, length, radius, mat, bend=0.0):
    """A thorn: a cone pointing along `direction` (a curved one when bend > 0)."""
    bm = bmesh.new()
    seg = 8
    rings = 5
    d = direction.normalized()
    side = d.cross(Vector((0, 0, 1)))
    if side.length < 1e-4:
        side = Vector((1, 0, 0))
    side.normalize()
    up = side.cross(d).normalized()
    verts = []
    for k in range(rings):
        t = k / (rings - 1)
        c = loc + d * length * t + up * bend * length * t * t
        r = radius * (1.0 - t) ** 1.2 + 0.0008
        ring = []
        for i in range(seg):
            a = 2 * math.pi * i / seg
            ring.append(bm.verts.new(c + side * math.cos(a) * r + up * math.sin(a) * r))
        verts.append(ring)
    for k in range(rings - 1):
        for i in range(seg):
            bm.faces.new((verts[k][i], verts[k][(i + 1) % seg], verts[k + 1][(i + 1) % seg], verts[k + 1][i]))
    me = bpy.data.meshes.new("thorn")
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = True
    ob = bpy.data.objects.new("thorn", me)
    ITEM.objects.link(ob)
    me.materials.append(mat)
    return ob


def crystal_cluster(loc, rng, mat, scale=0.06):
    for _ in range(rng.randint(3, 6)):
        h = scale * rng.uniform(1.2, 2.6)
        r = scale * rng.uniform(0.18, 0.32)
        bpy.ops.mesh.primitive_cylinder_add(vertices=6, radius=r, depth=h, location=loc)
        ob = bpy.context.object
        move_to(ob, ITEM)
        # Point the tip: scale the top ring in.
        me = ob.data
        for v in me.vertices:
            if v.co.z > 0:
                v.co.x *= 0.15
                v.co.y *= 0.15
                v.co.z += r * 0.8
        ob.rotation_euler = (rng.uniform(0.3, 1.1), rng.uniform(-0.6, 0.6), rng.uniform(0, math.tau))
        ob.location = loc + Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), 0.2)) * scale * 0.6
        me.materials.append(mat)


def fur_tuft(loc, rng, fur_mat, grass_mat, r=0.04):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=r, location=loc)
    ob = bpy.context.object
    move_to(ob, ITEM)
    # A flat tuft clinging to the stem, not a ball.
    ob.scale = (rng.uniform(1.4, 2.2), rng.uniform(0.7, 1.0), 0.35)
    ob.rotation_euler = (0, 0, rng.uniform(0, math.tau))
    ob.data.materials.append(fur_mat)
    ob.data.materials.append(grass_mat)
    for slot, (count, length, mat_i, kink) in enumerate([(420, r * 1.5, 1, 0.0), (26, r * 4.2, 2, 0.0)]):
        mod = ob.modifiers.new("hair%d" % slot, "PARTICLE_SYSTEM")
        ps = mod.particle_system.settings
        ps.type = "HAIR"
        ps.count = count
        ps.hair_length = length
        ps.material = mat_i
        ps.use_advanced_hair = True
        ps.child_type = "INTERPOLATED"
        for k, v in {"child_percent": 6, "child_nbr": 6, "rendered_child_count": 10 if slot == 0 else 3,
                "roughness_1": 0.06 if slot == 0 else 0.02, "roughness_2": 0.08 if slot == 0 else 0.03,
                "roughness_endpoint": 0.05, "root_radius": 1.0, "tip_radius": 0.0,
                "radius_scale": 0.004 if slot == 0 else 0.006,
                "seed": rng.randint(0, 9999), "display_step": 4, "render_step": 5, "use_render_emitter": False}.items():
            if hasattr(ps, k):
                setattr(ps, k, v)
        # Length last: Blender keeps hair length in the emit velocity settings.
        ps.hair_length = length
    return ob


def growth(seed, kind):
    rng = random.Random(seed)
    chrome = principled("BlackChrome", (0.03, 0.03, 0.035), 1.0, 0.13, bump=0.35, bump_scale=18.0)
    crystal = principled("BlueCrystal", (0.08, 0.32, 1.0), 0.0, 0.04, trans=1.0, ior=1.55, emit=(0.05, 0.25, 1.0), emit_str=0.6)
    fur = hair_material("Fur", (0.42, 0.48, 0.56), rough=0.45)
    grass = hair_material("Grass", (0.08, 0.3, 0.02), rough=0.3)
    nodes = []
    spikes_n = [0]

    def branch(start, d, length, radius, depth):
        step = 0.05
        n = max(3, int(length / step))
        pts = [start.copy()]
        radii = [radius]
        p = start.copy()
        head = d.copy()
        for i in range(n):
            d = (d + Vector((rng.uniform(-0.3, 0.3), rng.uniform(-0.3, 0.3), 0.0)) + head * (0.35 if depth == 0 else 0.12)).normalized()
            p = p + d * step
            p.z = 0.6 * radius + rng.uniform(-0.004, 0.012)
            t = (i + 1) / n
            r = radius * (1.0 - t) ** 0.7 + 0.004
            # Lumps: the stem swells and pinches like melted metal.
            r *= rng.uniform(0.8, 1.35) if i % 3 == 0 else 1.0
            pts.append(p.copy())
            radii.append(r)
            nodes.append((p.copy(), r))
            if depth < 2 and rng.random() < (0.1 if depth == 0 else 0.06):
                ang = rng.choice([-1, 1]) * rng.uniform(0.6, 1.2)
                nd = Matrix.Rotation(ang, 3, "Z") @ d
                branch(p.copy(), nd, length * rng.uniform(0.25, 0.5), r * 0.85, depth + 1)
            if rng.random() < 0.42:
                ang = rng.choice([-1, 1]) * rng.uniform(0.7, 1.4)
                sd = Matrix.Rotation(ang, 3, "Z") @ d
                sd.z = rng.uniform(0.1, 0.6)
                cone(p + Vector((0, 0, r * 0.3)), sd, r * rng.uniform(3.5, 7.5), r * rng.uniform(0.6, 0.95), chrome, rng.uniform(-0.25, 0.25))
                spikes_n[0] += 1
        tube("stem", pts, radii, chrome)

    if kind == "corner":
        # From the corner (0, 0) along +x and -y (the poster's top and left edges), a bud in the middle.
        branch(Vector((0.0, 0.0, 0.0)), Vector((1.0, -0.15, 0)).normalized(), 2.6, 0.075, 0)
        branch(Vector((0.0, 0.0, 0.0)), Vector((0.12, -1.0, 0)).normalized(), 2.4, 0.07, 0)
        branch(Vector((0.05, -0.05, 0.0)), Vector((1.0, -1.0, 0)).normalized(), 0.6, 0.055, 1)
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.12, location=(0.02, -0.02, 0.07))
        bud = bpy.context.object
        bud.scale = (1.0, 1.0, 0.6)
        move_to(bud, ITEM)
        bud.data.materials.append(chrome)
        mod = bud.modifiers.new("lumps", "DISPLACE")
        tx = bpy.data.textures.new("lumps", "CLOUDS")
        tx.noise_scale = 0.08
        mod.texture = tx
        mod.strength = 0.05
        smooth(bud, 80)
    else:
        branch(Vector((0.0, 0.0, 0.0)), Vector((0.05, -1.0, 0)).normalized(), 4.4, 0.07, 0)
        branch(Vector((0.04, -1.8, 0.0)), Vector((1.0, -0.6, 0)).normalized(), 0.9, 0.05, 1)
    # Crystals and tufts along the growth.
    rng.shuffle(nodes)
    for p, r in nodes[: 7 if kind == "corner" else 6]:
        crystal_cluster(p + Vector((0, 0, r)), rng, crystal, scale=0.09 + r * 0.9)
    for p, r in nodes[7: 7 + (12 if kind == "corner" else 10)]:
        if os.environ.get("RIVAL_NOFUR"):
            break
        fur_tuft(p + Vector((0, 0, r * 0.8)), rng, fur, grass, r=0.03 + r * 0.25)


# ------------------------------------------------------------------ dome, button, acrylic

def dome():
    bpy.ops.mesh.primitive_uv_sphere_add(segments=96, ring_count=48, radius=1.0, location=(0, 0, 0))
    ob = bpy.context.object
    move_to(ob, ITEM)
    ob.scale = (1.0, 0.72, 0.5)
    smooth(ob, 80)
    m = principled("RedGloss", (0.16, 0.003, 0.006), 0.0, 0.05, coat=1.0)
    # Deep glossy red: a little subsurface-like glow at the rim via a fresnel-mixed emission.
    ob.data.materials.append(m)


def knurl_material():
    m = principled("Knurl", (0.36, 0.37, 0.4), 1.0, 0.3)
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(tc.outputs["Object"], sep.inputs["Vector"])
    # Angle round the axis and height: two diagonal groove sets (a knurled ring).
    at = nt.nodes.new("ShaderNodeMath")
    at.operation = "ARCTAN2"
    nt.links.new(sep.outputs["Y"], at.inputs[0])
    nt.links.new(sep.outputs["X"], at.inputs[1])
    outs = []
    for sgn in (1.0, -1.0):
        mz = nt.nodes.new("ShaderNodeMath")
        mz.operation = "MULTIPLY"
        mz.inputs[1].default_value = 22.0 * sgn
        nt.links.new(sep.outputs["Z"], mz.inputs[0])
        ma = nt.nodes.new("ShaderNodeMath")
        ma.operation = "MULTIPLY"
        ma.inputs[1].default_value = 9.0
        nt.links.new(at.outputs[0], ma.inputs[0])
        ad = nt.nodes.new("ShaderNodeMath")
        ad.operation = "ADD"
        nt.links.new(mz.outputs[0], ad.inputs[0])
        nt.links.new(ma.outputs[0], ad.inputs[1])
        sn = nt.nodes.new("ShaderNodeMath")
        sn.operation = "SINE"
        nt.links.new(ad.outputs[0], sn.inputs[0])
        ab = nt.nodes.new("ShaderNodeMath")
        ab.operation = "ABSOLUTE"
        nt.links.new(sn.outputs[0], ab.inputs[0])
        outs.append(ab)
    mn = nt.nodes.new("ShaderNodeMath")
    mn.operation = "MINIMUM"
    nt.links.new(outs[0].outputs[0], mn.inputs[0])
    nt.links.new(outs[1].outputs[0], mn.inputs[1])
    bp = nt.nodes.new("ShaderNodeBump")
    bp.inputs["Strength"].default_value = 1.0
    bp.inputs["Distance"].default_value = 0.05
    nt.links.new(mn.outputs[0], bp.inputs["Height"])
    nt.links.new(bp.outputs["Normal"], b.inputs["Normal"])
    return m


def button():
    silver = principled("Silver", (0.42, 0.43, 0.46), 1.0, 0.16)
    knurl = knurl_material()
    # The bezel: a ring with a knurled outer wall and a polished chamfered top.
    bpy.ops.mesh.primitive_cylinder_add(vertices=128, radius=1.0, depth=0.42, location=(0, 0, 0.21))
    ring = bpy.context.object
    move_to(ring, ITEM)
    ring.data.materials.append(knurl)
    bpy.ops.mesh.primitive_cylinder_add(vertices=128, radius=0.76, depth=1.0, location=(0, 0, 0.3))
    hole = bpy.context.object
    move_to(hole, ITEM)
    mod = ring.modifiers.new("hole", "BOOLEAN")
    mod.object = hole
    mod.operation = "DIFFERENCE"
    bpy.context.view_layer.objects.active = ring
    bpy.ops.object.modifier_apply(modifier="hole")
    bpy.data.objects.remove(hole, do_unlink=True)
    bev = ring.modifiers.new("bevel", "BEVEL")
    bev.width = 0.03
    bev.segments = 3
    bev.limit_method = "ANGLE"
    smooth(ring)
    # A polished lip on top of the bezel.
    bpy.ops.mesh.primitive_torus_add(major_radius=0.88, minor_radius=0.07, major_segments=128, minor_segments=24, location=(0, 0, 0.42))
    lip = bpy.context.object
    move_to(lip, ITEM)
    lip.scale = (1, 1, 0.5)
    lip.data.materials.append(silver)
    smooth(lip, 80)
    # The red cap, domed, a little proud of the bezel.
    bpy.ops.mesh.primitive_uv_sphere_add(segments=96, ring_count=48, radius=0.72, location=(0, 0, 0.3))
    cap = bpy.context.object
    move_to(cap, ITEM)
    cap.scale = (1, 1, 0.42)
    smooth(cap, 80)
    cap.data.materials.append(principled("RedCap", (0.2, 0.004, 0.008), 0.0, 0.25, coat=0.9))
    bpy.ops.mesh.primitive_cylinder_add(vertices=96, radius=0.72, depth=0.3, location=(0, 0, 0.15))
    skirt = bpy.context.object
    move_to(skirt, ITEM)
    skirt.data.materials.append(principled("RedSkirt", (0.14, 0.003, 0.006), 0.0, 0.3))


def acrylic():
    # A rounded slab of orange acrylic with a printed halftone grid and a round cut-out.
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.04))
    ob = bpy.context.object
    move_to(ob, ITEM)
    ob.scale = (3.2, 2.0, 0.08)
    bpy.ops.object.transform_apply(scale=True)
    bpy.ops.mesh.primitive_cylinder_add(vertices=96, radius=0.42, depth=1.0, location=(-1.0, 0.25, 0.0))
    hole = bpy.context.object
    move_to(hole, ITEM)
    mod = ob.modifiers.new("hole", "BOOLEAN")
    mod.object = hole
    mod.operation = "DIFFERENCE"
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.modifier_apply(modifier="hole")
    bpy.data.objects.remove(hole, do_unlink=True)
    bev = ob.modifiers.new("bevel", "BEVEL")
    bev.width = 0.025
    bev.segments = 4
    bev.limit_method = "ANGLE"
    smooth(ob)
    m = bpy.data.materials.new("Acrylic")
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (1.0, 0.16, 0.02, 1)
    b.inputs["Roughness"].default_value = 0.16
    b.inputs["Transmission Weight"].default_value = 0.88
    b.inputs["IOR"].default_value = 1.49
    # The printed dot grid: a darker orange print on the top face.
    tc = nt.nodes.new("ShaderNodeTexCoord")
    mp = nt.nodes.new("ShaderNodeMapping")
    mp.inputs["Scale"].default_value = (26.0, 26.0, 1.0)
    nt.links.new(tc.outputs["Object"], mp.inputs["Vector"])
    fr = nt.nodes.new("ShaderNodeVectorMath")
    fr.operation = "FRACTION"
    nt.links.new(mp.outputs["Vector"], fr.inputs[0])
    sub = nt.nodes.new("ShaderNodeVectorMath")
    sub.operation = "SUBTRACT"
    sub.inputs[1].default_value = (0.5, 0.5, 0.0)
    nt.links.new(fr.outputs[0], sub.inputs[0])
    sxy = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(sub.outputs[0], sxy.inputs[0])
    cxy = nt.nodes.new("ShaderNodeCombineXYZ")
    nt.links.new(sxy.outputs["X"], cxy.inputs["X"])
    nt.links.new(sxy.outputs["Y"], cxy.inputs["Y"])
    ln = nt.nodes.new("ShaderNodeVectorMath")
    ln.operation = "LENGTH"
    nt.links.new(cxy.outputs[0], ln.inputs[0])
    lt = nt.nodes.new("ShaderNodeMath")
    lt.operation = "LESS_THAN"
    lt.inputs[1].default_value = 0.26
    nt.links.new(ln.outputs["Value"], lt.inputs[0])
    mix = nt.nodes.new("ShaderNodeMixRGB")
    mix.inputs["Color1"].default_value = (1.0, 0.16, 0.02, 1)
    mix.inputs["Color2"].default_value = (0.32, 0.03, 0.005, 1)
    nt.links.new(lt.outputs[0], mix.inputs["Fac"])
    nt.links.new(mix.outputs["Color"], b.inputs["Base Color"])
    rmix = nt.nodes.new("ShaderNodeMath")
    rmix.operation = "MULTIPLY_ADD"
    rmix.inputs[1].default_value = -0.6
    rmix.inputs[2].default_value = 0.88
    nt.links.new(lt.outputs[0], rmix.inputs[0])
    nt.links.new(rmix.outputs[0], b.inputs["Transmission Weight"])
    ob.data.materials.append(m)


def seal():
    """A seal of glossy dark-red jelly (the parchment poster reference's frame material), dripping a
    little, overgrown with moss on top, a red and a cyan LED set into it."""
    rng = random.Random(7)
    mb = bpy.data.metaballs.new("Jelly")
    mb.resolution = 0.04
    mb.render_resolution = 0.025
    ob = bpy.data.objects.new("Jelly", mb)
    ITEM.objects.link(ob)
    # A flattened blob with lobes and a few drips running off one side.
    for _ in range(9):
        e = mb.elements.new()
        e.co = (rng.uniform(-0.55, 0.55), rng.uniform(-0.4, 0.4), rng.uniform(0.0, 0.12))
        e.radius = rng.uniform(0.38, 0.55)
    for k in range(3):
        x = -0.3 + k * 0.32
        for j in range(5):
            e = mb.elements.new()
            e.co = (x + rng.uniform(-0.03, 0.03), -0.42 - j * 0.1, 0.02)
            e.radius = 0.24 - j * 0.03
    ob.scale = (1.0, 1.0, 0.42)
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)
    bpy.ops.object.convert(target="MESH")
    jelly = bpy.context.object
    move_to(jelly, ITEM)
    smooth(jelly, 80)
    disp = jelly.modifiers.new("lumps", "DISPLACE")
    tx = bpy.data.textures.new("lumps", "CLOUDS")
    tx.noise_scale = 0.18
    disp.texture = tx
    disp.strength = 0.05
    m = principled("Jelly", (0.07, 0.0008, 0.003), 0.0, 0.06, coat=1.0)
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Subsurface Weight"].default_value = 0.15
    b.inputs["Subsurface Radius"].default_value = (0.6, 0.05, 0.05)
    b.inputs["Subsurface Scale"].default_value = 0.02
    jelly.data.materials.append(m)
    # Moss on the top: hair on the upward faces, density from a noisy vertex group.
    moss_mat = hair_material("Moss", (0.035, 0.085, 0.012), rough=0.55)
    jelly.data.materials.append(moss_mat)
    vg = jelly.vertex_groups.new(name="moss")
    for v in jelly.data.vertices:
        n = v.normal
        # Patchy: a few soft clumps (hashed blobs), only on the upward faces of the top half.
        clump = 0.0
        for cx, cy, cr in ((-0.35, 0.25, 0.32), (0.15, 0.32, 0.26), (0.45, 0.0, 0.2), (-0.05, -0.05, 0.16)):
            dd = math.hypot(v.co.x - cx, v.co.y - cy)
            clump = max(clump, 1.0 - dd / cr)
        wgt = max(0.0, n.z) * clump
        if wgt > 0.05:
            vg.add([v.index], min(1.0, wgt * 1.6), "REPLACE")
    mod = jelly.modifiers.new("moss", "PARTICLE_SYSTEM")
    ps = mod.particle_system.settings
    ps.type = "HAIR"
    ps.count = 2600
    ps.material = 2
    ps.use_advanced_hair = True
    ps.child_type = "INTERPOLATED"
    for k, v in {"rendered_child_count": 8, "roughness_1": 0.04, "roughness_2": 0.05, "root_radius": 1.0, "tip_radius": 0.1,
            "radius_scale": 0.006, "render_step": 4, "display_step": 3}.items():
        if hasattr(ps, k):
            setattr(ps, k, v)
    ps.hair_length = 0.05
    mod.particle_system.vertex_group_density = "moss"
    mod.particle_system.vertex_group_length = "moss"
    # Two LEDs set into the jelly.
    for loc, col in (((0.32, -0.12, 0.2), SIGNAL), ((-0.28, 0.05, 0.21), (0.05, 0.6, 1.0))):
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.07, location=loc)
        led = bpy.context.object
        move_to(led, ITEM)
        smooth(led, 80)
        led.data.materials.append(principled("Led", col, 0.0, 0.1, emit=col, emit_str=4.0, coat=1.0))


# ------------------------------------------------------------------ camera and render

def frame_camera(cam, el_deg, az_deg, pad=1.08):
    az = math.radians(az_deg)
    el = math.radians(el_deg)
    view = Vector((math.sin(az) * math.cos(el), -math.cos(az) * math.cos(el), math.sin(el)))
    dg = bpy.context.evaluated_depsgraph_get()
    fwd = -view
    right = fwd.cross(Vector((0, 0, 1))).normalized()
    up = right.cross(fwd).normalized()
    xs, ys, pts = [], [], []
    for ob in ITEM.objects:
        if ob.hide_render or ob.type not in ("MESH", "CURVE") or ob.name.startswith("Catcher"):
            continue
        ev = ob.evaluated_get(dg)
        me = ev.to_mesh()
        mw = ob.matrix_world
        for v in me.vertices:
            p = mw @ v.co
            xs.append(p.dot(right))
            ys.append(p.dot(up))
            pts.append(p)
        ev.to_mesh_clear()
    cx = (min(xs) + max(xs)) * 0.5
    cy = (min(ys) + max(ys)) * 0.5
    depth = sum((p.dot(view) for p in pts)) / max(len(pts), 1)
    center = right * cx + up * cy + view * depth
    cam.location = center + view * 20.0
    cam.rotation_euler = fwd.to_track_quat("-Z", "Y").to_euler()
    cam.data.type = "ORTHO"
    w = max(xs) - min(xs)
    h = max(ys) - min(ys)
    cam.data.ortho_scale = max(w, h) * pad
    return w, h


def clear_item():
    for ob in list(ITEM.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    for me in list(bpy.data.meshes):
        if me.users == 0:
            bpy.data.meshes.remove(me)
    for cu in list(bpy.data.curves):
        if cu.users == 0:
            bpy.data.curves.remove(cu)


# which: (builder, elevation, azimuth, render width px)
JOBS = {
    "thorns_corner": (lambda: growth(23, "corner"), 72, 18, 1024),
    "thorns_vine": (lambda: growth(41, "vine"), 72, 18, 1024),
    "dome": (dome, 58, 20, 512),
    "button": (button, 40, 18, 512),
    "acrylic": (acrylic, 64, 14, 1024),
    "seal": (seal, 62, 16, 512),
}

studio()
bpy.ops.object.camera_add()
CAM = bpy.context.object
move_to(CAM, STUDIO)
sc.camera = CAM
for which in WHICH:
    if which not in JOBS:
        print("UNKNOWN", which)
        continue
    clear_item()
    build, el, az, px = JOBS[which]
    build()
    bpy.context.view_layer.update()
    w, h = frame_camera(CAM, el, az)
    shadow_catcher()
    aspect = w / max(h, 1e-4)
    if aspect >= 1.0:
        sc.render.resolution_x = px
        sc.render.resolution_y = max(64, int(px / aspect * 1.0))
    else:
        sc.render.resolution_y = px
        sc.render.resolution_x = max(64, int(px * aspect))
    CAM.data.sensor_fit = "AUTO"
    sc.render.filepath = os.path.join(OUT, which + ".png")
    bpy.ops.render.render(write_still=True)
    print("RENDERED", sc.render.filepath, sc.render.resolution_x, sc.render.resolution_y)
