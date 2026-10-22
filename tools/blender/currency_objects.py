"""Halo & Horn currencies as real objects (owner, 2026-10-23: "return icons to gems and gold, make
icons for summoning scrolls and hero exp. i want it to feel real"), modelled from code and rendered
in Cycles in the gear pieces' studio (tools/blender/gear_objects.py).

    blender --background --factory-startup --python tools/blender/currency_objects.py -- <out_dir> [which] [samples]

which: comma list of gems,gold,scrolls,hero_exp,dust or "all" (the currencies), or "shop" (pouch,
chest, reliquary: the gem packs; gift, crate, moon, satchel: the offers). Writes <out_dir>/<id>.png (512 px,
transparent). tools/blender/finish_currency.py crops them square and writes assets/art/ui/currency/.
  gems      a brilliant-cut sapphire-blue gem with a smaller one behind
  gold      two struck gold coins: a raised rim, a halo and two horns on the face
  scrolls   a rolled summoning scroll of parchment on gold-capped rods, a red wax seal and ribbon
  hero_exp  a glass flask of glowing green essence with a cork and a gold collar
  dust      a little heap of violet star-dust shards that catch the light
"""
import math
import os
import random
import sys

import bpy
from mathutils import Matrix, Vector

argv = sys.argv[sys.argv.index("--") + 1:]
OUT = argv[0]
ALL = ["gems", "gold", "scrolls", "hero_exp", "dust"]
SHOP = ["pouch", "chest", "reliquary", "gift", "crate", "moon", "satchel"]
which = ALL if len(argv) < 2 or argv[1] == "all" else (SHOP if argv[1] == "shop" else argv[1].split(","))
SAMPLES = int(argv[2]) if len(argv) > 2 else 192
os.makedirs(OUT, exist_ok=True)

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
sc.cycles.max_bounces = 16
sc.cycles.transmission_bounces = 16
sc.cycles.glossy_bounces = 8
sc.render.film_transparent = True
sc.render.resolution_x = 512
sc.render.resolution_y = 512
sc.render.image_settings.file_format = "PNG"
sc.render.image_settings.color_mode = "RGBA"
sc.render.image_settings.color_depth = "16"
sc.view_settings.view_transform = "Standard"
try:
    sc.view_settings.look = "Medium High Contrast"
except Exception:
    pass
sc.view_settings.exposure = -0.3

STUDIO = bpy.data.collections.new("Studio")
sc.collection.children.link(STUDIO)
ITEM = bpy.data.collections.new("Item")
sc.collection.children.link(ITEM)


def move_to(ob, coll):
    for c in list(ob.users_collection):
        c.objects.unlink(ob)
    coll.objects.link(ob)


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
    bg.inputs["Strength"].default_value = 0.7
    nt.links.new(bg.outputs["Background"], out.inputs["Surface"])
    card("SoftTop", (0, 1.0, 6.0), (math.radians(-10), 0, 0), (7, 2.6), 6.0)
    card("StripL", (-5.0, -1.5, 1.0), (0, math.radians(-75), 0), (9, 0.6), 12.0)
    card("StripR", (5.0, 0.5, 0.5), (0, math.radians(80), 0), (9, 0.45), 9.0)
    card("Rim", (0, 6.0, 2.0), (math.radians(-80), 0, 0), (8, 0.8), 6.0)
    light((-4, -5, 6), 1400, 4.0)
    light((5, -3, 2), 500, 3.0)


def principled(name, base, metallic=0.0, rough=0.4, coat=0.0, emit=None, emit_str=0.0, trans=0.0, ior=1.45,
        sheen=0.0, noise_bump=0.0, noise_scale=9.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*base, 1)
    b.inputs["Metallic"].default_value = metallic
    b.inputs["Roughness"].default_value = rough
    if coat > 0.0:
        b.inputs["Coat Weight"].default_value = coat
        b.inputs["Coat Roughness"].default_value = 0.04
    if emit is not None:
        b.inputs["Emission Color"].default_value = (*emit, 1)
        b.inputs["Emission Strength"].default_value = emit_str
    if trans > 0.0:
        b.inputs["Transmission Weight"].default_value = trans
        b.inputs["IOR"].default_value = ior
    if sheen > 0.0:
        b.inputs["Sheen Weight"].default_value = sheen
    if noise_bump > 0.0:
        tc = nt.nodes.new("ShaderNodeTexCoord")
        nz = nt.nodes.new("ShaderNodeTexNoise")
        nz.inputs["Scale"].default_value = noise_scale
        nz.inputs["Detail"].default_value = 10.0
        nt.links.new(tc.outputs["Object"], nz.inputs["Vector"])
        bump = nt.nodes.new("ShaderNodeBump")
        bump.inputs["Strength"].default_value = noise_bump
        bump.inputs["Distance"].default_value = 0.01
        nt.links.new(nz.outputs["Fac"], bump.inputs["Height"])
        nt.links.new(bump.outputs["Normal"], b.inputs["Normal"])
    return m


def add(ob, mat, smooth=True):
    ob.data.materials.append(mat)
    if smooth:
        for p in ob.data.polygons:
            p.use_smooth = True
    move_to(ob, ITEM)
    return ob


def bevel(ob, w, seg=3):
    m = ob.modifiers.new("Bevel", "BEVEL")
    m.width = w
    m.segments = seg
    m.limit_method = "ANGLE"
    return ob


def lathe(name, mat, profile, loc=(0, 0, 0), steps=96):
    """A body of revolution about Z from (radius, z) points."""
    verts, faces = [], []
    n = len(profile)
    for i in range(steps):
        a = 2 * math.pi * i / steps
        for r, z in profile:
            verts.append((r * math.cos(a), r * math.sin(a), z))
    for i in range(steps):
        j = (i + 1) % steps
        for k in range(n - 1):
            faces.append((i * n + k, j * n + k, j * n + k + 1, i * n + k + 1))
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.update()
    ob = bpy.data.objects.new(name, me)
    sc.collection.objects.link(ob)
    ob.location = loc
    return add(ob, mat)


# ------------------------------------------------------------------ the objects

def brilliant(name, mat, r, loc, rot):
    """A round brilliant: table, crown facets, girdle, pavilion to a point (16 sides, flat shaded)."""
    n = 16
    table_r, crown_h, girdle_h, pav_h = r * 0.56, r * 0.32, r * 0.04, r * 0.86
    verts = [(0, 0, crown_h + girdle_h)]
    for i in range(n):
        a = 2 * math.pi * (i + 0.5) / n
        verts.append((table_r * math.cos(a), table_r * math.sin(a), crown_h + girdle_h))
    for i in range(n):
        a = 2 * math.pi * i / n
        verts.append((r * math.cos(a), r * math.sin(a), girdle_h))
    for i in range(n):
        a = 2 * math.pi * i / n
        verts.append((r * math.cos(a), r * math.sin(a), 0.0))
    verts.append((0, 0, -pav_h))
    T, G1, G0, P = 1, 1 + n, 1 + 2 * n, 1 + 3 * n
    faces = []
    for i in range(n):
        j = (i + 1) % n
        faces.append((0, T + i, T + j))
        faces.append((T + i, G1 + j, T + j))
        faces.append((T + i, G1 + i, G1 + j))
        faces.append((G1 + i, G0 + i, G0 + j, G1 + j))
        faces.append((G0 + i, P, G0 + j))
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.update()
    ob = bpy.data.objects.new(name, me)
    sc.collection.objects.link(ob)
    ob.location = loc
    ob.rotation_euler = rot
    return add(ob, mat, smooth=False)


def m_gems():
    glass = principled("Sapphire", (0.0, 0.14, 0.8), rough=0.0, trans=1.0, ior=2.1)
    glass.node_tree.nodes["Principled BSDF"].inputs["Emission Color"].default_value = (0.2, 0.55, 1.0, 1)
    glass.node_tree.nodes["Principled BSDF"].inputs["Emission Strength"].default_value = 0.35
    brilliant("GemA", glass, 1.0, (0, 0, 0), (math.radians(64), 0, math.radians(18)))
    small = principled("Aqua", (0.25, 0.85, 1.0), rough=0.0, trans=1.0, ior=2.0)
    small.node_tree.nodes["Principled BSDF"].inputs["Emission Color"].default_value = (0.3, 0.9, 1.0, 1)
    small.node_tree.nodes["Principled BSDF"].inputs["Emission Strength"].default_value = 0.3
    brilliant("GemB", small, 0.5, (0.95, 0.6, -0.55), (math.radians(40), math.radians(-25), math.radians(-30)))


def coin(name, gold, deep, loc, rot, r=1.0):
    t = r * 0.16
    body = lathe(name, gold, [(0.0, -t * 0.5), (r * 0.97, -t * 0.5), (r, -t * 0.38), (r, t * 0.38), (r * 0.97, t * 0.5),
        (r * 0.86, t * 0.5), (r * 0.84, t * 0.36), (0.0, t * 0.36)])
    # The face: a raised halo ring and two horns rising from it, a dot of a pearl between them.
    bpy.ops.mesh.primitive_torus_add(major_radius=r * 0.42, minor_radius=r * 0.06, major_segments=64, minor_segments=12,
        location=(0, 0, t * 0.38))
    halo = add(bpy.context.object, gold)
    parts = [body, halo]
    for s in (-1, 1):
        bpy.ops.mesh.primitive_cone_add(vertices=20, radius1=r * 0.09, radius2=0.0, depth=r * 0.42,
            location=(s * r * 0.3, r * 0.42, t * 0.42))
        h = bpy.context.object
        h.rotation_euler = (math.radians(-90), math.radians(-s * 28), 0)
        h.scale = (1.0, 0.45, 1.0)
        parts.append(add(h, deep))
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r * 0.08, location=(0, 0, t * 0.42))
    p = bpy.context.object
    p.scale = (1, 1, 0.5)
    parts.append(add(p, gold))
    root = bpy.data.objects.new(name + "Root", None)
    sc.collection.objects.link(root)
    move_to(root, ITEM)
    for o in parts:
        o.parent = root
    root.location = loc
    root.rotation_euler = rot
    return root


def m_gold():
    gold = principled("Gold", (1.0, 0.72, 0.28), metallic=1.0, rough=0.22, noise_bump=0.12, noise_scale=40.0)
    deep = principled("GoldDeep", (0.9, 0.55, 0.16), metallic=1.0, rough=0.32)
    coin("CoinBack", gold, deep, (0.55, 0.9, -0.35), (math.radians(68), math.radians(8), math.radians(-24)), 0.9)
    coin("CoinFront", gold, deep, (-0.15, -0.2, 0.0), (math.radians(58), math.radians(-6), math.radians(14)))


def m_scrolls():
    parch = principled("Parchment", (0.5, 0.36, 0.18), rough=0.85, noise_bump=0.5, noise_scale=14.0)
    gold = principled("Gold", (1.0, 0.72, 0.28), metallic=1.0, rough=0.25)
    wax = principled("Wax", (0.62, 0.04, 0.03), rough=0.28, coat=0.4)
    ribbon = principled("Ribbon", (0.75, 0.06, 0.05), rough=0.5, sheen=0.6)
    L = 2.4
    # The rolled body: a cylinder a little thicker at its middle wraps (a gentle spiral edge).
    bpy.ops.mesh.primitive_cylinder_add(vertices=64, radius=0.42, depth=L, location=(0, 0, 0), rotation=(0, math.radians(90), 0))
    body = add(bpy.context.object, parch)
    bevel(body, 0.03)
    for s in (-1, 1):
        # Gold-capped wooden rods with finials.
        bpy.ops.mesh.primitive_cylinder_add(vertices=32, radius=0.47, depth=0.08, location=(s * (L * 0.5 + 0.02), 0, 0), rotation=(0, math.radians(90), 0))
        bevel(add(bpy.context.object, gold), 0.02)
        bpy.ops.mesh.primitive_cylinder_add(vertices=24, radius=0.1, depth=0.28, location=(s * (L * 0.5 + 0.18), 0, 0), rotation=(0, math.radians(90), 0))
        add(bpy.context.object, gold)
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.16, location=(s * (L * 0.5 + 0.36), 0, 0))
        add(bpy.context.object, gold)
    # The ribbon round the middle and the wax seal on it.
    bpy.ops.mesh.primitive_torus_add(major_radius=0.44, minor_radius=0.035, major_segments=64, minor_segments=8,
        location=(0, 0, 0), rotation=(0, math.radians(90), 0))
    r = bpy.context.object
    r.scale = (1, 1, 2.6)
    add(r, ribbon)
    bpy.ops.mesh.primitive_cylinder_add(vertices=40, radius=0.26, depth=0.09, location=(0, -0.44, 0.05), rotation=(math.radians(90), 0, 0))
    seal = add(bpy.context.object, wax)
    bevel(seal, 0.035, 4)
    dp = seal.modifiers.new("Wobble", "DISPLACE")
    tx = bpy.data.textures.new("WaxNoise", "CLOUDS")
    tx.noise_scale = 0.12
    dp.texture = tx
    dp.strength = 0.02
    bpy.ops.mesh.primitive_torus_add(major_radius=0.13, minor_radius=0.02, major_segments=40, minor_segments=8,
        location=(0, -0.5, 0.05), rotation=(math.radians(90), 0, 0))
    add(bpy.context.object, wax)
    for o in ITEM.objects:
        if o.parent is None:
            o.matrix_world = Matrix.Rotation(math.radians(-24), 4, "Z") @ Matrix.Rotation(math.radians(-8), 4, "Y") @ o.matrix_world


def m_hero_exp():
    glass = principled("Glass", (0.95, 1.0, 0.97), rough=0.02, trans=1.0, ior=1.5)
    essence = principled("Essence", (0.05, 0.75, 0.25), rough=0.1, trans=0.3, ior=1.33, emit=(0.1, 0.9, 0.3), emit_str=0.9)
    cork = principled("Cork", (0.55, 0.38, 0.22), rough=0.85, noise_bump=0.5, noise_scale=30.0)
    gold = principled("Gold", (1.0, 0.72, 0.28), metallic=1.0, rough=0.22)
    # A round-bellied flask with a long neck.
    prof = [(0.0, 0.0), (0.45, 0.02), (0.78, 0.25), (0.9, 0.62), (0.82, 1.0), (0.55, 1.28), (0.24, 1.46), (0.2, 1.62),
        (0.2, 2.02), (0.26, 2.08), (0.24, 2.14)]
    lathe("Flask", glass, prof)
    sol = ITEM.objects["Flask"].modifiers.new("Solid", "SOLIDIFY")
    sol.thickness = 0.04
    liq = [(0.0, 0.06), (0.42, 0.08), (0.72, 0.28), (0.83, 0.62), (0.76, 0.95), (0.62, 1.12), (0.0, 1.12)]
    lathe("Essence", essence, liq)
    lathe("Cork", cork, [(0.0, 1.98), (0.17, 1.98), (0.19, 2.12), (0.21, 2.32), (0.0, 2.34)])
    bpy.ops.mesh.primitive_torus_add(major_radius=0.23, minor_radius=0.04, major_segments=48, minor_segments=10, location=(0, 0, 1.72))
    add(bpy.context.object, gold)
    # A few bubbles in the essence.
    rnd = random.Random(7)
    for k in range(9):
        a = rnd.uniform(0, 2 * math.pi)
        rr = rnd.uniform(0.0, 0.55)
        bpy.ops.mesh.primitive_uv_sphere_add(radius=rnd.uniform(0.025, 0.06), location=(rr * math.cos(a), rr * math.sin(a), rnd.uniform(0.3, 1.0)))
        add(bpy.context.object, glass)
    for o in ITEM.objects:
        o.matrix_world = Matrix.Rotation(math.radians(-12), 4, "Y") @ o.matrix_world


def m_dust():
    rnd = random.Random(11)
    mats = [principled("Dust%d" % k, c, rough=0.12, metallic=0.3, emit=c, emit_str=0.25)
        for k, c in enumerate([(0.45, 0.16, 0.9), (0.62, 0.3, 0.95), (0.3, 0.12, 0.7), (0.8, 0.55, 1.0)])]
    # A heap: shards stacked on a mound, smaller and sparser toward its edge.
    for k in range(260):
        a = rnd.uniform(0, 2 * math.pi)
        rr = math.sqrt(rnd.uniform(0, 1)) * 1.05
        z = (1.0 - (rr / 1.05) ** 1.6) * 0.75 + rnd.uniform(-0.04, 0.04)
        s = rnd.uniform(0.05, 0.14) * (1.15 - rr * 0.5)
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=s, location=(rr * math.cos(a), rr * math.sin(a), z))
        o = bpy.context.object
        o.rotation_euler = (rnd.uniform(0, 3), rnd.uniform(0, 3), rnd.uniform(0, 3))
        o.scale = (1.0, rnd.uniform(0.6, 1.0), rnd.uniform(0.8, 1.5))
        add(o, mats[rnd.randrange(len(mats))], smooth=False)


# ------------------------------------------------------------------ shop pieces

def gem_pile(mats, centre, radius, count, seed, top=0.0, scale=1.0):
    """A heap of small cut gems (brilliants) round `centre`, highest in the middle."""
    rnd = random.Random(seed)
    for k in range(count):
        a = rnd.uniform(0, 2 * math.pi)
        rr = math.sqrt(rnd.uniform(0, 1)) * radius
        z = top + (1.0 - (rr / radius) ** 2) * radius * 0.45
        brilliant("G%d" % k, mats[rnd.randrange(len(mats))], rnd.uniform(0.09, 0.16) * scale,
            (centre[0] + rr * math.cos(a), centre[1] + rr * math.sin(a), centre[2] + z),
            (rnd.uniform(0, 3), rnd.uniform(0, 3), rnd.uniform(0, 3)))


def gem_mats():
    out = []
    for k, c in enumerate([(0.0, 0.14, 0.8), (0.0, 0.5, 0.9), (0.35, 0.1, 0.85), (0.0, 0.3, 1.0)]):
        m = principled("PileGem%d" % k, c, rough=0.0, trans=1.0, ior=2.0)
        m.node_tree.nodes["Principled BSDF"].inputs["Emission Color"].default_value = (*c, 1)
        m.node_tree.nodes["Principled BSDF"].inputs["Emission Strength"].default_value = 0.35
        out.append(m)
    return out


def hide_cutter(cut):
    cut.hide_render = True
    move_to(cut, STUDIO)


def m_pouch():
    leather = principled("Leather", (0.075, 0.03, 0.012), rough=0.5, sheen=0.2, noise_bump=0.7, noise_scale=22.0)
    cord = principled("Cord", (0.85, 0.62, 0.25), metallic=0.6, rough=0.35)
    bpy.ops.mesh.primitive_uv_sphere_add(segments=48, ring_count=24, radius=0.9, location=(0, 0, 0.75))
    sack = bpy.context.object
    sack.scale = (1.0, 1.0, 0.85)
    dp = sack.modifiers.new("Folds", "DISPLACE")
    tx = bpy.data.textures.new("Folds", "CLOUDS")
    tx.noise_scale = 0.35
    dp.texture = tx
    dp.strength = 0.16
    add(sack, leather)
    lathe("Neck", leather, [(0.38, 1.38), (0.28, 1.5), (0.3, 1.62), (0.42, 1.78), (0.34, 1.82)])
    bpy.ops.mesh.primitive_torus_add(major_radius=0.3, minor_radius=0.045, location=(0, 0, 1.5))
    add(bpy.context.object, cord)
    gem_pile(gem_mats(), (0.55, -0.75, 0.0), 0.6, 22, 3)


def m_chest():
    wood = principled("Wood", (0.09, 0.035, 0.012), rough=0.55, noise_bump=0.6, noise_scale=6.0)
    gold = principled("Gold", (1.0, 0.72, 0.28), metallic=1.0, rough=0.22)
    W, D, H = 2.0, 1.3, 0.9
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, H / 2))
    box = bpy.context.object
    box.scale = (W, D, H)
    bevel(add(box, wood, smooth=False), 0.03)
    for x in (-W / 2 + 0.06, W / 2 - 0.06):
        bpy.ops.mesh.primitive_cube_add(size=1, location=(x, 0, H / 2))
        b = bpy.context.object
        b.scale = (0.12, D + 0.04, H + 0.04)
        bevel(add(b, gold, smooth=False), 0.02)
    # The lid, opened back on its hinge at the box's back top edge: a slab with gold bands.
    hinge = Vector((0, D / 2, H))
    tilt = Matrix.Rotation(math.radians(-100), 4, "X")
    for (sx, sz, mat, dz) in ((W, 0.14, wood, 0.0), (0.12, 0.16, gold, 0.0)):
        for x in ((0.0,) if mat is wood else (-W / 2 + 0.06, W / 2 - 0.06)):
            bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, 0))
            sl = bpy.context.object
            sl.scale = (sx, D, sz)
            bevel(add(sl, mat, smooth=False), 0.02)
            local = Matrix.Translation(Vector((x, -D / 2, sz / 2 + dz)))
            sl.matrix_world = Matrix.Translation(hinge) @ tilt @ local @ Matrix.Diagonal((sx, D, sz, 1.0))
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, -D / 2 - 0.02, H * 0.72))
    lock = bpy.context.object
    lock.scale = (0.24, 0.06, 0.3)
    bevel(add(lock, gold, smooth=False), 0.02)
    gem_pile(gem_mats(), (0, 0, H - 0.05), 0.8, 46, 5)


def m_reliquary():
    gold = principled("Gold", (1.0, 0.72, 0.28), metallic=1.0, rough=0.2, noise_bump=0.1, noise_scale=40.0)
    velvet = principled("Velvet", (0.45, 0.02, 0.05), rough=0.9, sheen=1.0)
    lathe("Foot", gold, [(0.0, 0.0), (1.1, 0.0), (1.1, 0.12), (0.8, 0.22), (0.7, 0.42), (0.0, 0.42)])
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, 0.95))
    body = bpy.context.object
    body.scale = (1.6, 1.1, 1.05)
    bevel(add(body, gold, smooth=False), 0.06, 4)
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, -0.56, 0.95))
    pane = bpy.context.object
    pane.scale = (1.2, 0.02, 0.7)
    add(pane, velvet, smooth=False)
    lathe("Dome", gold, [(0.0, 1.47), (0.85, 1.47), (0.8, 1.7), (0.55, 1.95), (0.15, 2.08), (0.0, 2.1)])
    bpy.ops.mesh.primitive_torus_add(major_radius=0.32, minor_radius=0.05, major_segments=48, location=(0, 0, 2.5), rotation=(math.radians(90), 0, 0))
    add(bpy.context.object, gold)
    mats = gem_mats()
    for k, x in enumerate((-0.5, 0.0, 0.5)):
        brilliant("Inset%d" % k, mats[k % len(mats)], 0.14, (x, -0.57, 1.0), (math.radians(90), 0, 0))
    gem_pile(mats, (0, -1.0, 0.0), 0.9, 34, 9)


def m_gift():
    paper = principled("GiftPaper", (0.75, 0.05, 0.04), rough=0.35, coat=0.6)
    ribbon = principled("GiftRibbon", (1.0, 0.75, 0.3), metallic=0.8, rough=0.25)
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, 0.6))
    b = bpy.context.object
    b.scale = (1.4, 1.4, 1.2)
    bevel(add(b, paper, smooth=False), 0.04)
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, 1.27))
    l = bpy.context.object
    l.scale = (1.5, 1.5, 0.22)
    bevel(add(l, paper, smooth=False), 0.04)
    for sx, sy in ((0.2, 1.54), (1.54, 0.2)):
        bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, 0.7))
        r = bpy.context.object
        r.scale = (sx, sy, 1.42)
        add(r, ribbon, smooth=False)
    for sgn in (-1, 1):
        bpy.ops.mesh.primitive_torus_add(major_radius=0.3, minor_radius=0.07, major_segments=40, location=(sgn * 0.28, 0, 1.55),
            rotation=(math.radians(90), math.radians(sgn * 35), 0))
        t = bpy.context.object
        t.scale = (1.0, 0.6, 1.0)
        add(t, ribbon)


def m_crate():
    wood = principled("Crate", (0.16, 0.08, 0.03), rough=0.65, noise_bump=0.6, noise_scale=5.0)
    gold = principled("Gold", (1.0, 0.72, 0.28), metallic=1.0, rough=0.22)
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, 0.7))
    b = bpy.context.object
    b.scale = (1.8, 1.4, 1.4)
    bevel(add(b, wood, smooth=False), 0.03)
    for z in (0.18, 1.22):
        bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, z))
        sl = bpy.context.object
        sl.scale = (1.84, 1.44, 0.12)
        bevel(add(sl, wood, smooth=False), 0.02)
    coin("CrateCoin", gold, gold, (0.45, -0.1, 1.62), (math.radians(30), 0, math.radians(20)), 0.42)
    gem_pile(gem_mats(), (-0.3, -0.1, 1.35), 0.55, 18, 13, scale=1.2)


def m_moon():
    silver = principled("Silver", (0.85, 0.87, 0.92), metallic=1.0, rough=0.18)
    glow = principled("MoonGlow", (0.7, 0.75, 1.0), rough=0.3, emit=(0.6, 0.7, 1.0), emit_str=0.8)
    bpy.ops.mesh.primitive_cylinder_add(vertices=96, radius=1.0, depth=0.22, location=(0, 0, 0), rotation=(math.radians(90), 0, 0))
    moon = bpy.context.object
    bpy.ops.mesh.primitive_cylinder_add(vertices=96, radius=0.86, depth=0.5, location=(0.42, 0, 0.22), rotation=(math.radians(90), 0, 0))
    cut = bpy.context.object
    bo = moon.modifiers.new("Crescent", "BOOLEAN")
    bo.object = cut
    bo.operation = "DIFFERENCE"
    bevel(add(moon, silver, smooth=False), 0.05, 4)
    hide_cutter(cut)
    rnd = random.Random(4)
    for k in range(5):
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=rnd.uniform(0.05, 0.1), location=(rnd.uniform(0.2, 1.1), -0.1, rnd.uniform(-0.6, 0.8)))
        add(bpy.context.object, glow)


def m_satchel():
    leather = principled("Satchel", (0.07, 0.025, 0.01), rough=0.5, noise_bump=0.7, noise_scale=20.0)
    gold = principled("Gold", (1.0, 0.72, 0.28), metallic=1.0, rough=0.22)
    parch = principled("Parchment", (0.42, 0.3, 0.14), rough=0.85, noise_bump=0.5, noise_scale=14.0)
    wax = principled("Wax", (0.62, 0.04, 0.03), rough=0.28, coat=0.4)
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, 0.75))
    b = bpy.context.object
    b.scale = (1.8, 0.8, 1.5)
    bevel(add(b, leather, smooth=False), 0.18, 5)
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, -0.42, 1.05))
    f = bpy.context.object
    f.scale = (1.7, 0.08, 0.9)
    bevel(add(f, leather, smooth=False), 0.12, 4)
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, -0.48, 0.8))
    c = bpy.context.object
    c.scale = (0.3, 0.06, 0.24)
    bevel(add(c, gold, smooth=False), 0.03)
    for k, (x, tilt) in enumerate(((-0.5, 12), (0.0, -4), (0.5, -15))):
        bpy.ops.mesh.primitive_cylinder_add(vertices=40, radius=0.2, depth=1.3, location=(x, 0.05, 1.7), rotation=(0, math.radians(tilt), 0))
        add(bpy.context.object, parch)
        bpy.ops.mesh.primitive_cylinder_add(vertices=24, radius=0.23, depth=0.06,
            location=(x + math.sin(math.radians(tilt)) * 0.66, 0.05, 1.7 + math.cos(math.radians(tilt)) * 0.66), rotation=(0, math.radians(tilt), 0))
        add(bpy.context.object, gold)
        bpy.ops.mesh.primitive_cylinder_add(vertices=24, radius=0.11, depth=0.05, location=(x, -0.17, 1.45), rotation=(math.radians(90), 0, 0))
        add(bpy.context.object, wax)


MODELS = {"gems": m_gems, "gold": m_gold, "scrolls": m_scrolls, "hero_exp": m_hero_exp, "dust": m_dust,
    "pouch": m_pouch, "chest": m_chest, "reliquary": m_reliquary, "gift": m_gift, "crate": m_crate, "moon": m_moon,
    "satchel": m_satchel}

# ------------------------------------------------------------------ camera and render

AZ = math.radians(24)
EL = math.radians(22)
VIEW = Vector((math.sin(AZ) * math.cos(EL), -math.cos(AZ) * math.cos(EL), math.sin(EL)))


def frame_camera(cam):
    dg = bpy.context.evaluated_depsgraph_get()
    fwd = -VIEW
    right = fwd.cross(Vector((0, 0, 1))).normalized()
    up = right.cross(fwd).normalized()
    xs, ys, pts = [], [], []
    for ob in ITEM.objects:
        if ob.type not in ("MESH",) or ob.hide_render:
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
    depth = sum((p.dot(VIEW) for p in pts)) / max(len(pts), 1)
    cam.location = right * cx + up * cy + VIEW * depth + VIEW * 12.0
    cam.rotation_euler = fwd.to_track_quat("-Z", "Y").to_euler()
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = max(max(xs) - min(xs), max(ys) - min(ys)) * 1.08


def clear_item():
    for ob in list(ITEM.objects):
        bpy.data.objects.remove(ob, do_unlink=True)


studio()
bpy.ops.object.camera_add()
CAM = bpy.context.object
move_to(CAM, STUDIO)
sc.camera = CAM
for k in which:
    clear_item()
    MODELS[k]()
    bpy.context.view_layer.update()
    frame_camera(CAM)
    sc.render.filepath = os.path.join(OUT, "%s.png" % k)
    bpy.ops.render.render(write_still=True)
    print("RENDERED", sc.render.filepath)
