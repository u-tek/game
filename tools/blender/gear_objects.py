"""Halo & Horn gear pieces (style v4 studio objects), modelled from code and rendered in Cycles.

    blender --background --factory-startup --python tools/blender/gear_objects.py -- <out_dir> [kinds] [tiers] [samples]

kinds: comma list of item nouns (Blade,Spear,Sceptre,Glaive,Cuirass,Vestments,Mail,Circlet,Helm,Crown,
Rosary,Locket,Reliquary) or "all"; tiers: comma list of 1-5 (Worn, Tempered, Gilded, Hallowed, Eclipse)
or "all". Writes <out_dir>/<noun>_<tier>.png (512 px, transparent). tools/blender/finish_objects.py
gear <out_dir> crops them, bakes the paper shadow and writes assets/art/ui/gear/.
Every piece shares one studio (Blender's bundled city.exr, desaturated, plus emissive cards) and one
three-quarter orthographic camera that frames the piece automatically.
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

argv = sys.argv[sys.argv.index("--") + 1:]
OUT = argv[0]
KINDS = ["Blade", "Spear", "Sceptre", "Glaive", "Cuirass", "Vestments", "Mail", "Circlet", "Helm", "Crown",
    "Rosary", "Locket", "Reliquary"]
kinds = KINDS if len(argv) < 2 or argv[1] == "all" else argv[1].split(",")
tiers = [1, 2, 3, 4, 5] if len(argv) < 3 or argv[2] == "all" else [int(t) for t in argv[2].split(",")]
SAMPLES = int(argv[3]) if len(argv) > 3 else 128
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
sc.render.film_transparent = True
sc.render.resolution_x = 512
sc.render.resolution_y = 512
sc.render.image_settings.file_format = "PNG"
sc.render.image_settings.color_mode = "RGBA"
sc.render.image_settings.color_depth = "16"
try:
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "Medium High Contrast"
    # Standard clips highlights: a little under so white ceramic and lit stones keep their shape.
    sc.view_settings.exposure = -0.45
except Exception:
    sc.view_settings.view_transform = "Filmic"

STUDIO = bpy.data.collections.new("Studio")
sc.collection.children.link(STUDIO)
ITEM = bpy.data.collections.new("Item")
sc.collection.children.link(ITEM)


# ------------------------------------------------------------------ studio

def studio() -> None:
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
    card("SoftTop", (0, 1.0, 6.0), (math.radians(-10), 0, 0), (7, 2.6), 6.0)
    card("StripL", (-5.0, -1.5, 1.0), (0, math.radians(-75), 0), (9, 0.6), 12.0)
    card("StripR", (5.0, 0.5, 0.5), (0, math.radians(80), 0), (9, 0.45), 9.0)
    card("Rim", (0, 6.0, 2.0), (math.radians(-80), 0, 0), (8, 0.8), 6.0)
    light((-4, -5, 6), 1400, 4.0)
    light((5, -3, 2), 500, 3.0)


def card(name, loc, rot, size, strength) -> None:
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


def light(loc, energy, size) -> None:
    bpy.ops.object.light_add(type="AREA", location=loc)
    l = bpy.context.object
    l.data.energy = energy
    l.data.size = size
    l.rotation_euler = (Vector((0, 0, 0)) - l.location).to_track_quat("-Z", "Y").to_euler()
    move_to(l, STUDIO)


def move_to(ob, coll) -> None:
    for c in list(ob.users_collection):
        c.objects.unlink(ob)
    coll.objects.link(ob)


# ------------------------------------------------------------------ materials

def principled(name, base, metallic=0.0, rough=0.4, coat=0.0, emit=None, emit_str=0.0, trans=0.0, ior=1.45,
        aniso=0.0, sheen=0.0, noise_rough=0.0, spec=None):
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
    if aniso > 0.0:
        b.inputs["Anisotropic"].default_value = aniso
    if sheen > 0.0:
        b.inputs["Sheen Weight"].default_value = sheen
    if spec is not None:
        b.inputs["Specular IOR Level"].default_value = spec
    if noise_rough > 0.0:
        # Worn metal: rough patches and pitting.
        tc = nt.nodes.new("ShaderNodeTexCoord")
        nz = nt.nodes.new("ShaderNodeTexNoise")
        nz.inputs["Scale"].default_value = 9.0
        nz.inputs["Detail"].default_value = 8.0
        nt.links.new(tc.outputs["Object"], nz.inputs["Vector"])
        mr = nt.nodes.new("ShaderNodeMapRange")
        mr.inputs["To Min"].default_value = rough - noise_rough
        mr.inputs["To Max"].default_value = rough + noise_rough
        nt.links.new(nz.outputs["Fac"], mr.inputs["Value"])
        nt.links.new(mr.outputs["Result"], b.inputs["Roughness"])
        bump = nt.nodes.new("ShaderNodeBump")
        bump.inputs["Strength"].default_value = 0.25
        bump.inputs["Distance"].default_value = 0.004
        nt.links.new(nz.outputs["Fac"], bump.inputs["Height"])
        nt.links.new(bump.outputs["Normal"], b.inputs["Normal"])
    return m


def mail_material(base, rough):
    """Chainmail: a fine ring pattern as bump on metal."""
    m = principled("Mail", base, 1.0, rough)
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    tc = nt.nodes.new("ShaderNodeTexCoord")
    vo = nt.nodes.new("ShaderNodeTexVoronoi")
    vo.feature = "DISTANCE_TO_EDGE"
    vo.inputs["Scale"].default_value = 70.0
    nt.links.new(tc.outputs["Object"], vo.inputs["Vector"])
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.9
    bump.inputs["Distance"].default_value = 0.01
    bump.invert = True
    nt.links.new(vo.outputs["Distance"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], b.inputs["Normal"])
    return m


# Signal red-orange #ff4b1f in linear (Blender colours are linear).
SIGNAL = (1.0, 0.0704, 0.0137)


def tier_set(t: int) -> dict:
    """primary metal, accent, gem, cloth, trim for a tier."""
    if t == 1:  # Worn: pitted iron, leather, a dull amber stone, undyed linen
        return {"metal": principled("Iron", (0.2, 0.19, 0.18), 1.0, 0.68, noise_rough=0.25),
            "accent": principled("Leather", (0.11, 0.07, 0.05), 0.0, 0.62, sheen=0.3),
            "gem": principled("Amber", (0.55, 0.28, 0.06), 0.0, 0.25, trans=0.6, ior=1.55),
            "cloth": principled("Linen", (0.36, 0.30, 0.22), 0.0, 0.85, sheen=0.3, spec=0.15),
            "trim": principled("Bronze", (0.36, 0.22, 0.11), 1.0, 0.55, noise_rough=0.2),
            "mail": mail_material((0.22, 0.21, 0.2), 0.62)}
    if t == 2:  # Tempered: bright steel, blued steel, sapphire, navy
        return {"metal": principled("Steel", (0.80, 0.82, 0.86), 1.0, 0.2, aniso=0.4),
            "accent": principled("Blued", (0.10, 0.14, 0.26), 1.0, 0.28),
            "gem": principled("Sapphire", (0.10, 0.30, 0.95), 0.0, 0.05, trans=0.9, ior=1.77),
            "cloth": principled("Navy", (0.04, 0.06, 0.16), 0.0, 0.8, sheen=0.2, spec=0.15),
            "trim": principled("Steel2", (0.80, 0.82, 0.86), 1.0, 0.22),
            "mail": mail_material((0.78, 0.8, 0.84), 0.25)}
    if t == 3:  # Gilded: gold, red enamel, ruby, crimson
        return {"metal": principled("Gold", (1.0, 0.72, 0.30), 1.0, 0.16),
            "accent": principled("Enamel", (0.32, 0.01, 0.02), 0.0, 0.3, coat=0.6),
            "gem": principled("Ruby", (0.95, 0.04, 0.08), 0.0, 0.03, trans=0.9, ior=1.76),
            "cloth": principled("Crimson", (0.32, 0.01, 0.025), 0.0, 0.7, sheen=0.1, spec=0.12),
            "trim": principled("Gold2", (1.0, 0.72, 0.30), 1.0, 0.18),
            "mail": mail_material((1.0, 0.72, 0.30), 0.2)}
    if t == 4:  # Hallowed: pearl-white ceramic, gold, a softly lit aqua stone, white silk
        return {"metal": principled("Pearl", (0.5, 0.48, 0.45), 0.0, 0.3, coat=0.8, spec=0.4),
            "accent": principled("Gold", (1.0, 0.76, 0.36), 1.0, 0.15),
            "gem": principled("Halo", (0.2, 0.8, 1.0), 0.0, 0.05, emit=(0.2, 0.8, 1.0), emit_str=1.1, trans=0.4),
            "cloth": principled("Silk", (0.62, 0.6, 0.56), 0.0, 0.5, sheen=0.4, spec=0.3),
            "trim": principled("Gold2", (1.0, 0.76, 0.36), 1.0, 0.15),
            "mail": mail_material((0.86, 0.85, 0.82), 0.25)}
    # Eclipse: black chrome, signal-red light, a burning stone, black satin
    return {"metal": principled("BlackChrome", (0.035, 0.035, 0.04), 1.0, 0.1),
        "accent": principled("Signal", SIGNAL, 0.0, 0.3, emit=SIGNAL, emit_str=1.25),
        "gem": principled("Core", SIGNAL, 0.0, 0.1, emit=SIGNAL, emit_str=1.6),
        "cloth": principled("Satin", (0.02, 0.02, 0.025), 0.0, 0.35, sheen=0.2, spec=0.4),
        "trim": principled("Signal2", SIGNAL, 0.0, 0.3, emit=SIGNAL, emit_str=1.25),
        "mail": mail_material((0.05, 0.05, 0.06), 0.15)}


# ------------------------------------------------------------------ geometry helpers

def obj_from(me, name, mat, smooth=True, auto=40):
    for p in me.polygons:
        p.use_smooth = smooth
    me.use_auto_smooth = True
    me.auto_smooth_angle = math.radians(auto)
    ob = bpy.data.objects.new(name, me)
    ITEM.objects.link(ob)
    if mat:
        me.materials.append(mat)
    return ob


def prim(op, mat, smooth=True, auto=40, **kw):
    getattr(bpy.ops.mesh, op)(**kw)
    ob = bpy.context.object
    move_to(ob, ITEM)
    for p in ob.data.polygons:
        p.use_smooth = smooth
    ob.data.use_auto_smooth = True
    ob.data.auto_smooth_angle = math.radians(auto)
    if mat:
        ob.data.materials.append(mat)
    return ob


def bevel(ob, w, seg=3, angle=35):
    m = ob.modifiers.new("bevel", "BEVEL")
    m.width = w
    m.segments = seg
    m.limit_method = "ANGLE"
    m.angle_limit = math.radians(angle)
    m.harden_normals = True
    return m


def subsurf(ob, lv=2):
    m = ob.modifiers.new("sub", "SUBSURF")
    m.levels = lv
    m.render_levels = lv
    return m


def solidify(ob, t, offset=-1.0):
    m = ob.modifiers.new("solid", "SOLIDIFY")
    m.thickness = t
    m.offset = offset
    return m


def blade(name, mat, length, width, thick, profile, base=(0, 0, 0), n=48, path=None):
    """A diamond-section blade along +Z (or along path(t) -> (x, z, angle)): width(t) and
    thickness(t) from profile(t) in 0..1, flat faces with crisp ridges."""
    verts = []
    faces = []
    for i in range(n + 1):
        t = i / n
        k = profile(t)
        w = width * k
        th = thick * max(k, 0.0) ** 0.8
        if path:
            x, z, a = path(t)
            nx, nz = math.cos(a), -math.sin(a)
        else:
            x, z, nx, nz = 0.0, t * length, 1.0, 0.0
        cx, cz = base[0] + x, base[2] + z
        verts += [(cx - nx * w, base[1], cz - nz * w), (cx, base[1] - th, cz), (cx + nx * w, base[1], cz + nz * w),
            (cx, base[1] + th, cz)]
    for i in range(n):
        a = i * 4
        b = a + 4
        for k in range(4):
            faces.append((a + k, a + (k + 1) % 4, b + (k + 1) % 4, b + k))
    faces.append((3, 2, 1, 0))
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0005)
    bm.to_mesh(me)
    bm.free()
    return obj_from(me, name, mat, smooth=False)


def lathe(name, mat, profile, loc=(0, 0, 0), steps=96, smooth=True):
    """Revolve a (radius, z) profile around Z."""
    me = bpy.data.meshes.new(name)
    me.from_pydata([(r, 0.0, z) for r, z in profile], [(i, i + 1) for i in range(len(profile) - 1)], [])
    ob = obj_from(me, name, mat, smooth)
    ob.location = loc
    s = ob.modifiers.new("lathe", "SCREW")
    s.axis = "Z"
    s.steps = steps
    s.render_steps = steps
    s.use_smooth_shade = smooth
    s.use_merge_vertices = True
    return ob


def ring_of(n, radius, z, make, start=0.0):
    obs = []
    for i in range(n):
        a = start + math.tau * i / n
        obs.append(make(Vector((math.cos(a) * radius, math.sin(a) * radius, z)), a))
    return obs


def shell(name, mat, sx, sy, sz, keep, thick=0.05, sub=2):
    """A smooth shell: part of an ellipsoid (keep(v) decides which vertices stay), thickened."""
    bpy.ops.mesh.primitive_uv_sphere_add(segments=48, ring_count=32, radius=1.0)
    ob = bpy.context.object
    move_to(ob, ITEM)
    ob.name = name
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    for v in bm.verts:
        v.co = Vector((v.co.x * sx, v.co.y * sy, v.co.z * sz))
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not keep(v.co)], context="VERTS")
    bm.to_mesh(ob.data)
    bm.free()
    for p in ob.data.polygons:
        p.use_smooth = True
    ob.data.materials.append(mat)
    solidify(ob, thick, 1.0)
    subsurf(ob, sub)
    return ob


def chain(n, start, step, r=0.035, mat=None):
    obs = []
    for i in range(n):
        p = Vector(start) + Vector(step) * i
        rot = (math.radians(90), 0, 0) if i % 2 else (math.radians(90), math.radians(90), 0)
        obs.append(prim("primitive_torus_add", mat, major_radius=r, minor_radius=r * 0.28, major_segments=32,
            minor_segments=12, location=p, rotation=rot))
    return obs


def gem(mat, loc, r, flat=0.7):
    g = prim("primitive_ico_sphere_add", mat, smooth=False, subdivisions=1, radius=r, location=loc)
    g.scale = (1.0, flat, 1.0)
    return g


def interp(pts, x):
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        if x <= x1:
            k = (x - x0) / max(x1 - x0, 1e-6)
            k = min(max(k, 0.0), 1.0)
            k = k * k * (3 - 2 * k)
            return y0 + (y1 - y0) * k
    return pts[-1][1]


def smoothstep(a, b, x):
    k = min(max((x - a) / (b - a), 0.0), 1.0)
    return k * k * (3 - 2 * k)


def tube(name, mat, pts, r, closed=False):
    """A round rim or cord through points (a bevelled poly curve)."""
    cu = bpy.data.curves.new(name, "CURVE")
    cu.dimensions = "3D"
    cu.bevel_depth = r
    cu.bevel_resolution = 6
    cu.use_fill_caps = True
    sp = cu.splines.new("POLY")
    sp.points.add(len(pts) - 1)
    for i, q in enumerate(pts):
        sp.points[i].co = (q[0], q[1], q[2], 1.0)
    sp.use_cyclic_u = closed
    ob = bpy.data.objects.new(name, cu)
    ITEM.objects.link(ob)
    cu.materials.append(mat)
    return ob


TORSO_W = [(-1.1, 0.6), (-0.45, 0.54), (0.3, 0.72), (0.78, 0.8), (1.0, 0.74)]
TORSO_D = [(-1.1, 0.33), (-0.45, 0.3), (0.25, 0.43), (0.8, 0.34), (1.0, 0.28)]


def torso(name, mat, sleeves=False, thick=0.05, ridge=0.035):
    """A front torso surface (breastplate or shirt): neck scoop, armholes (or shoulders), a centre
    ridge, pointed at the waist front. Returns (object, top edge points, bottom edge points)."""
    nu, nv = 56, 44
    verts, faces = [], []
    top, bot = [], []
    for j in range(nv + 1):
        v = j / nv
        for i in range(nu + 1):
            u = -1.0 + 2.0 * i / nu
            ztop = 0.94 - 0.3 * math.exp(-(u / 0.27) ** 2) - (0.0 if sleeves else 0.34 * smoothstep(0.62, 0.97, abs(u)))
            zbot = -0.95 - 0.13 * math.cos(u * math.pi * 0.5) ** 2
            z = zbot + (ztop - zbot) * v
            a = u * math.radians(104)
            x = math.sin(a) * interp(TORSO_W, z)
            y = -math.cos(a) * interp(TORSO_D, z) - ridge * math.exp(-(x / 0.07) ** 2) * (1.0 if z > -0.55 else 0.35)
            verts.append((x, y, z))
            if j == nv:
                top.append((x, y - 0.012, z))
            if j == 0:
                bot.append((x, y - 0.012, z))
    for j in range(nv):
        for i in range(nu):
            a = j * (nu + 1) + i
            faces.append((a, a + 1, a + nu + 2, a + nu + 1))
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    ob = obj_from(me, name, mat, smooth=True)
    solidify(ob, thick, -1.0)
    subsurf(ob, 2)
    return ob, top, bot


def surface_ring(z, out=0.015, n=60):
    pts = []
    for i in range(n + 1):
        u = -1.0 + 2.0 * i / n
        a = u * math.radians(104)
        x = math.sin(a) * (interp(TORSO_W, z) + out)
        y = -math.cos(a) * (interp(TORSO_D, z) + out) - 0.035 * math.exp(-(x / 0.07) ** 2)
        pts.append((x, y, z))
    return pts


# ------------------------------------------------------------------ the pieces

def m_blade(M):
    blade("Blade", M["metal"], 1.55, 0.115, 0.035, lambda t: (1.0 - 0.18 * t) * min(1.0, (1.0 - t) * 5.0), base=(0, 0, 0.0))
    g = prim("primitive_cube_add", M["trim"], size=1.0, location=(0, 0, -0.02))
    g.scale = (0.56, 0.1, 0.08)
    bevel(g, 0.025, 3)
    for sx in (-1, 1):
        prim("primitive_uv_sphere_add", M["trim"], radius=0.06, location=(sx * 0.3, 0, -0.02))
    gem(M["gem"], (0, -0.05, -0.02), 0.05)
    grip = lathe("Grip", M["accent"], [(0.0, -0.06), (0.042, -0.06), (0.042, -0.42), (0.0, -0.42)])
    for i in range(6):
        prim("primitive_torus_add", M["trim"], major_radius=0.044, minor_radius=0.009, location=(0, 0, -0.1 - i * 0.055))
    gem(M["gem"], (0, 0, -0.5), 0.075, 1.0)
    p = lathe("Pommel", M["trim"], [(0.0, -0.44), (0.07, -0.45), (0.05, -0.5), (0.0, -0.52)])


def m_spear(M):
    lathe("Shaft", M["accent"], [(0.0, -1.4), (0.032, -1.4), (0.032, 0.32), (0.0, 0.32)])
    for z in (0.18, 0.26, -0.3, -1.33):
        prim("primitive_torus_add", M["trim"], major_radius=0.038, minor_radius=0.012, location=(0, 0, z))
    lathe("Socket", M["metal"], [(0.0, 0.3), (0.045, 0.3), (0.03, 0.42), (0.0, 0.43)])
    blade("Head", M["metal"], 0.62, 0.13, 0.04, lambda t: math.sin(math.pi * min(1.0, (t * 1.0 + 0.04)) ** 0.75) * (1.0 - t ** 4),
        base=(0, 0, 0.42))
    lathe("Butt", M["metal"], [(0.0, -1.4), (0.034, -1.4), (0.0, -1.52)])


def m_sceptre(M):
    lathe("Shaft", M["metal"], [(0.0, -1.1), (0.04, -1.1), (0.035, 0.0), (0.05, 0.05), (0.04, 0.2), (0.0, 0.2)])
    for z in (-0.2, -0.28, -0.36, -0.95):
        prim("primitive_torus_add", M["accent"], major_radius=0.042, minor_radius=0.011, location=(0, 0, z))
    gem(M["gem"], (0, 0, 0.42), 0.15, 1.0)
    lathe("Cup", M["trim"], [(0.0, 0.18), (0.06, 0.2), (0.13, 0.32), (0.12, 0.34), (0.05, 0.25), (0.0, 0.24)])
    halo = prim("primitive_torus_add", M["trim"], major_radius=0.3, minor_radius=0.022, major_segments=96, minor_segments=16,
        location=(0, 0.02, 0.44), rotation=(math.radians(90), 0, 0))
    for a in (45, 135, 225, 315):
        r = math.radians(a)
        c = prim("primitive_cone_add", M["trim"], vertices=24, radius1=0.03, radius2=0.0, depth=0.14,
            location=(math.cos(r) * 0.37, 0.02, 0.44 + math.sin(r) * 0.37), rotation=(0, math.radians(90) - r, 0))
    lathe("Finial", M["trim"], [(0.0, -1.1), (0.05, -1.12), (0.0, -1.2)])


def m_glaive(M):
    lathe("Shaft", M["accent"], [(0.0, -1.35), (0.032, -1.35), (0.032, 0.25), (0.0, 0.25)])
    for z in (0.15, 0.22, -0.4, -1.3):
        prim("primitive_torus_add", M["trim"], major_radius=0.038, minor_radius=0.012, location=(0, 0, z))
    lathe("Socket", M["metal"], [(0.0, 0.22), (0.05, 0.22), (0.04, 0.36), (0.0, 0.37)])
    # A curved single-edged blade sweeping back from the socket.
    def path(t):
        a = math.radians(-8 + 70 * t ** 1.3)
        r = 0.9
        return (r * (1 - math.cos(a)) * 0.55 - 0.02, 0.34 + r * math.sin(a) * 1.05, a * 0.9)
    blade("Head", M["metal"], 0.8, 0.15, 0.035, lambda t: (0.75 + 0.45 * math.sin(math.pi * t)) * (1.0 - t ** 3), base=(0, 0, 0), path=path)
    gem(M["gem"], (0.02, -0.05, 0.42), 0.045)
    lathe("Butt", M["metal"], [(0.0, -1.35), (0.034, -1.35), (0.0, -1.45)])


def torso_keep(front=True):
    return lambda c: c.y <= 0.08 and c.z < 0.82 and c.z > -0.86


def m_cuirass(M):
    plate, top, bot = torso("Plate", M["metal"])
    tube("RimTop", M["trim"], top, 0.028)
    tube("RimBot", M["trim"], bot, 0.028)
    tube("Belt", M["accent"], surface_ring(-0.5, 0.03), 0.045)
    gem(M["gem"], (0, -0.38, -0.5), 0.07)
    for sx in (-1, 1):
        p = shell("Pauldron", M["metal"], 0.36, 0.34, 0.24, lambda c: c.z > -0.04, 0.04, 2)
        p.location = (sx * 0.7, -0.02, 0.58)
        p.rotation_euler = (0, sx * math.radians(32), 0)
        r = prim("primitive_torus_add", M["trim"], major_radius=0.35, minor_radius=0.022, major_segments=64, minor_segments=12,
            location=(sx * 0.7, -0.02, 0.58), rotation=(0, sx * math.radians(32), 0))
        r.scale = (1.0, 0.94, 1.0)


def m_mail(M):
    shirt, top, bot = torso("Mail", M["mail"], sleeves=True, thick=0.04, ridge=0.0)
    for sx in (-1, 1):
        th = math.radians(38)
        s = lathe("Sleeve", M["mail"], [(0.0, 0.0), (0.22, 0.0), (0.19, -0.46), (0.0, -0.46)])
        s.location = (sx * 0.7, 0.0, 0.74)
        s.rotation_euler = (0, -sx * th, 0)
        s.scale = (1.0, 0.72, 1.0)
        cuff = prim("primitive_torus_add", M["accent"], major_radius=0.19, minor_radius=0.03, major_segments=48, minor_segments=12)
        cuff.location = (sx * (0.7 + 0.46 * math.sin(th)), 0.0, 0.74 - 0.46 * math.cos(th))
        cuff.rotation_euler = (0, -sx * th, 0)
        cuff.scale = (1.0, 0.72, 1.0)
    neck = [q for q in top if abs(q[0]) < 0.3]
    tube("Collar", M["accent"], neck, 0.05)
    tube("Hem", M["trim"], bot, 0.03)
    tube("Belt", M["accent"], surface_ring(-0.45, 0.04), 0.05)
    gem(M["gem"], (0, -0.39, -0.45), 0.07)


def m_vestments(M):
    # A tabard: a long front panel with folds, gold-trimmed edges, a collar and an emblem.
    nu, nv = 48, 80

    def at(u, t):
        width = 0.62 + 0.18 * (1.0 - t) - 0.1 * math.exp(-((t - 0.72) ** 2) / 0.02)
        x = (u - 0.5) * width * 2.0
        fold = 0.045 * math.sin(u * math.tau * 3.0 + t * 1.5) * (1.0 - t) ** 0.7 + 0.25 * (x ** 2)
        z = (t - 0.5) * 2.0 - (0.18 * math.exp(-((u - 0.5) / 0.16) ** 2) if t > 0.999 else 0.0)
        return (x, -fold - 0.05, z)
    verts, faces = [], []
    for j in range(nv + 1):
        for i in range(nu + 1):
            verts.append(at(i / nu, j / nv))
    for j in range(nv):
        for i in range(nu):
            a = j * (nu + 1) + i
            faces.append((a, a + 1, a + nu + 2, a + nu + 1))
    me = bpy.data.meshes.new("Tabard")
    me.from_pydata(verts, [], faces)
    p = obj_from(me, "Tabard", M["cloth"], smooth=True)
    solidify(p, 0.025, 0.0)
    subsurf(p, 1)
    edge = [at(0.0, j / 40) for j in range(41)]
    tube("TrimL", M["trim"], [(x - 0.004, y - 0.02, z) for x, y, z in edge], 0.022)
    tube("TrimR", M["trim"], [(-x + 0.004, y - 0.02, z) for x, y, z in edge], 0.022)
    tube("Hem", M["trim"], [(x, y - 0.02, z + 0.004) for x, y, z in [at(i / 48, 0.0) for i in range(49)]], 0.025)
    # The collar: a gold torus round the neck opening, and shoulder clasps.
    col = prim("primitive_torus_add", M["trim"], major_radius=0.3, minor_radius=0.045, major_segments=64, minor_segments=12,
        location=(0, 0.05, 0.95))
    col.scale = (1.0, 0.7, 1.0)
    for sx in (-1, 1):
        prim("primitive_uv_sphere_add", M["trim"], radius=0.06, location=(sx * 0.42, -0.1, 0.95))
        gem(M["gem"], (sx * 0.42, -0.15, 0.95), 0.035)
    emb = prim("primitive_torus_add", M["trim"], major_radius=0.13, minor_radius=0.018, major_segments=64, minor_segments=12,
        location=(0, -0.1, 0.2), rotation=(math.radians(90), 0, 0))
    gem(M["gem"], (0, -0.12, 0.2), 0.07)
    star = prim("primitive_cone_add", M["trim"], vertices=4, radius1=0.08, radius2=0.0, depth=0.42, location=(0, -0.1, -0.12),
        rotation=(math.radians(180), 0, 0))
    star.scale = (1.0, 0.25, 1.0)


def m_circlet(M):
    band = prim("primitive_torus_add", M["metal"], major_radius=0.62, minor_radius=0.045, major_segments=128, minor_segments=16)
    band.scale = (1.0, 0.92, 1.0)
    fy = -0.62 * 0.92
    blade("Peak", M["trim"], 0.72, 0.17, 0.04, lambda t: (1.0 - t) ** 0.8 * min(1.0, t * 6.0 + 0.4), base=(0, fy - 0.01, -0.02), n=28)
    gem(M["gem"], (0, fy - 0.06, 0.16), 0.1)
    for sx in (-1, 1):
        for k, (deg, ln) in enumerate(((24, 0.5), (48, 0.34))):
            a0 = math.radians(-90 + sx * deg)
            bx, by = math.cos(a0) * 0.62, math.sin(a0) * 0.62 * 0.92
            blade("Leaf", M["trim"], ln, 0.1 - 0.02 * k, 0.025, lambda t: math.sin(math.pi * t) ** 0.6, base=(bx, by, 0.0), n=20,
                path=lambda t, s=sx, L=ln: (s * 0.25 * L * t, L * t, s * math.radians(-18)))
            gem(M["gem"], (bx, by - 0.04, 0.0), 0.04 - 0.01 * k)


def m_helm(M):
    sx_, sy_, sz_ = 0.58, 0.63, 0.7
    dome = shell("Dome", M["metal"], sx_, sy_, sz_, lambda c: c.z > -0.58, 0.05, 2)
    face = shell("Face", M["metal"], sx_ + 0.04, sy_ + 0.04, sz_ + 0.02, lambda c: c.y < -0.3 and c.z < 0.2 and c.z > -0.62, 0.04, 2)
    slit = prim("primitive_cube_add", None, size=1.0, location=(0, -0.6, 0.04))
    slit.scale = (0.62, 0.5, 0.055)
    slit.hide_render = True
    for ob in (dome, face):
        b = ob.modifiers.new("slit", "BOOLEAN")
        b.object = slit
        b.solver = "EXACT"
        b.operation = "DIFFERENCE"
    # A rolled rim round the base, following the shell.
    z = -0.56
    k = math.sqrt(max(0.0, 1.0 - (z / sz_) ** 2))
    tube("Rim", M["trim"], [(math.cos(a) * (sx_ * k + 0.03), math.sin(a) * (sy_ * k + 0.03), z)
        for a in [math.tau * i / 96 for i in range(96)]], 0.03, closed=True)
    R = 0.74

    def path(t):
        th = math.radians(-58 + 132 * t)
        return (R * math.sin(th) * 0.86, R * math.cos(th) - 0.02, th - math.pi * 0.5)
    crest = blade("Crest", M["accent"], 1.0, 0.13, 0.045, lambda t: math.sin(math.pi * min(1.0, t * 1.05)) ** 0.45, n=56, path=path)
    crest.rotation_euler = (0, 0, math.radians(90))
    for sxx in (-1, 1):
        for kk in range(3):
            prim("primitive_uv_sphere_add", M["trim"], radius=0.022, location=(sxx * (0.12 + 0.06 * kk), -0.66, -0.2))
    gem(M["gem"], (0, -0.7, 0.3), 0.065)


def m_crown(M):
    lathe("Band", M["metal"], [(0.48, -0.16), (0.52, -0.16), (0.53, 0.0), (0.5, 0.16), (0.46, 0.16), (0.47, 0.0), (0.45, -0.14),
        (0.48, -0.16)], smooth=True)

    def spike(pos, a):
        front = abs(math.sin(a) + 1.0) < 0.05
        h = 0.46 if front else 0.32
        c = prim("primitive_cone_add", M["metal"], vertices=4, radius1=0.085, radius2=0.0, depth=h,
            location=(pos.x, pos.y, 0.16 + h * 0.5), rotation=(0, 0, a + math.radians(45)))
        c.scale = (1.0, 0.42, 1.0)
        bevel(c, 0.008, 2)
        prim("primitive_uv_sphere_add", M["trim"], radius=0.034, location=(pos.x, pos.y, 0.18 + h))
        return c
    ring_of(8, 0.5, 0.0, spike, start=-math.pi * 0.5)
    ring_of(8, 0.535, 0.0, lambda pos, a: gem(M["gem"], (pos.x, pos.y, 0.0), 0.05), start=-math.pi * 0.5 + math.tau / 16)
    cap = shell("Cap", M["cloth"], 0.46, 0.46, 0.26, lambda c: c.z > 0.0, 0.02, 2)
    cap.location = (0, 0, 0.12)


def m_rosary(M):
    n = 22
    for i in range(n):
        a = math.tau * i / n
        r = 0.05 if i % 5 else 0.07
        prim("primitive_uv_sphere_add", M["gem"] if i % 5 == 0 else M["accent"], segments=24, ring_count=12, radius=r,
            location=(math.sin(a) * 0.5, 0, 0.22 + math.cos(a) * 0.62))
    for i in range(4):
        prim("primitive_uv_sphere_add", M["accent"], segments=24, ring_count=12, radius=0.045, location=(0, 0, -0.44 - i * 0.1))
    v = prim("primitive_cube_add", M["metal"], size=1.0, location=(0, 0, -0.98))
    v.scale = (0.06, 0.04, 0.44)
    bevel(v, 0.015, 3)
    h = prim("primitive_cube_add", M["metal"], size=1.0, location=(0, 0, -0.88))
    h.scale = (0.3, 0.04, 0.06)
    bevel(h, 0.015, 3)
    gem(M["gem"], (0, -0.04, -0.88), 0.05)
    halo = prim("primitive_torus_add", M["trim"], major_radius=0.13, minor_radius=0.014, major_segments=64, minor_segments=12,
        location=(0, 0.01, -0.88), rotation=(math.radians(90), 0, 0))


def m_locket(M):
    body = lathe("Locket", M["metal"], [(0.0, -0.07), (0.38, -0.07), (0.42, -0.04), (0.43, 0.0), (0.42, 0.04), (0.38, 0.07),
        (0.0, 0.08)])
    body.rotation_euler = (math.radians(90), 0, 0)
    body.scale = (0.82, 1.0, 1.0)
    rim = prim("primitive_torus_add", M["trim"], major_radius=0.36, minor_radius=0.022, major_segments=96, minor_segments=12,
        location=(0, -0.075, 0), rotation=(math.radians(90), 0, 0))
    rim.scale = (0.82, 1.0, 1.0)
    gem(M["gem"], (0, -0.1, 0.0), 0.14)
    for a in range(0, 360, 45):
        r = math.radians(a)
        prim("primitive_uv_sphere_add", M["trim"], radius=0.025, location=(math.cos(r) * 0.26 * 0.82, -0.09, math.sin(r) * 0.26))
    prim("primitive_torus_add", M["trim"], major_radius=0.07, minor_radius=0.018, location=(0, 0, 0.42),
        rotation=(0, math.radians(90), 0))
    chain(7, (0, 0, 0.52), (0, 0, 0.09), 0.04, M["trim"])


def m_reliquary(M):
    lathe("Glass", principled("Glass", (0.95, 0.97, 1.0), 0.0, 0.02, trans=1.0, ior=1.5),
        [(0.0, -0.3), (0.2, -0.3), (0.2, 0.3), (0.0, 0.3)])
    prim("primitive_uv_sphere_add", M["gem"], radius=0.1, location=(0, 0, 0))
    for z, s in ((-0.36, -1), (0.36, 1)):
        lathe("Cap", M["metal"], [(0.0, z), (0.25, z), (0.27, z + 0.04 * s), (0.25, z + 0.09 * s), (0.12, z + 0.16 * s),
            (0.0, z + 0.18 * s)])
        prim("primitive_torus_add", M["trim"], major_radius=0.24, minor_radius=0.015, location=(0, 0, z - 0.04 * s))
    for a in (0, 90, 180, 270):
        r = math.radians(a + 45)
        c = prim("primitive_cylinder_add", M["metal"], vertices=16, radius=0.018, depth=0.64,
            location=(math.cos(r) * 0.215, math.sin(r) * 0.215, 0))
    prim("primitive_torus_add", M["trim"], major_radius=0.08, minor_radius=0.02, location=(0, 0, 0.62),
        rotation=(0, math.radians(90), 0))
    spike = prim("primitive_cone_add", M["trim"], vertices=24, radius1=0.04, radius2=0.0, depth=0.2, location=(0, 0, -0.64),
        rotation=(math.radians(180), 0, 0))


MODELS = {"Blade": m_blade, "Spear": m_spear, "Sceptre": m_sceptre, "Glaive": m_glaive, "Cuirass": m_cuirass,
    "Vestments": m_vestments, "Mail": m_mail, "Circlet": m_circlet, "Helm": m_helm, "Crown": m_crown,
    "Rosary": m_rosary, "Locket": m_locket, "Reliquary": m_reliquary}
# Long pieces lie diagonally across the frame.
TILT = {"Blade": -42, "Spear": -42, "Sceptre": -30, "Glaive": -38}
# Rings tipped toward the camera so the front ornament reads.
PRE_X = {"Circlet": 30, "Crown": 10}


# ------------------------------------------------------------------ camera and render

AZ = math.radians(28)
EL = math.radians(16)
VIEW = Vector((math.sin(AZ) * math.cos(EL), -math.cos(AZ) * math.cos(EL), math.sin(EL)))


def frame_camera(cam) -> None:
    """Point the orthographic camera down VIEW and fit the visible item."""
    dg = bpy.context.evaluated_depsgraph_get()
    fwd = -VIEW
    right = fwd.cross(Vector((0, 0, 1))).normalized()
    up = right.cross(fwd).normalized()
    xs, ys, pts = [], [], []
    for ob in ITEM.objects:
        if ob.hide_render or ob.type not in ("MESH", "CURVE"):
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
    center = right * cx + up * cy + VIEW * depth
    cam.location = center + VIEW * 12.0
    cam.rotation_euler = fwd.to_track_quat("-Z", "Y").to_euler()
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = max(max(xs) - min(xs), max(ys) - min(ys)) * 1.1


def clear_item() -> None:
    for ob in list(ITEM.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    for me in list(bpy.data.meshes):
        if me.users == 0:
            bpy.data.meshes.remove(me)


studio()
bpy.ops.object.camera_add()
CAM = bpy.context.object
move_to(CAM, STUDIO)
sc.camera = CAM
for kind in kinds:
    for t in tiers:
        clear_item()
        MODELS[kind](tier_set(t))
        if kind in PRE_X:
            rx = Matrix.Rotation(math.radians(PRE_X[kind]), 4, "X")
            for ob in ITEM.objects:
                if ob.parent is None:
                    ob.matrix_world = rx @ ob.matrix_world
        if kind in TILT:
            # Lay long pieces diagonally in the picture plane (a rotation about the view axis).
            rot = Matrix.Rotation(math.radians(TILT[kind]), 4, VIEW)
            for ob in ITEM.objects:
                if ob.parent is None:
                    ob.matrix_world = rot @ ob.matrix_world
        bpy.context.view_layer.update()
        frame_camera(CAM)
        sc.render.filepath = os.path.join(OUT, "%s_%d.png" % (kind.lower(), t))
        bpy.ops.render.render(write_still=True)
        print("RENDERED", sc.render.filepath)
