"""Halo & Horn UI collage objects (style v4, the poster look), rendered in Cycles on the GPU.

    blender --background --factory-startup --python tools/blender/ui_objects.py -- <out_dir> <which> [samples]

which: coil_chrome | coil_ink | disc | printer | clip. Writes <out_dir>/<which>.png (16-bit RGBA, transparent;
the printer also <which>.json, where its slit is in the render). Then
tools/blender/finish_objects.py crops, adds the paper shadow and writes assets/art/ui/objects/.
Uses only Blender's bundled studio light (city.exr, desaturated) and emissive cards, so it runs on
any Blender 4.0 install. Takes 4-10 s per object on an RTX 3070 (OptiX).
"""
import bpy, math, sys, os
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
OUT = argv[0]
WHICH = argv[1]
SAMPLES = int(argv[2]) if len(argv) > 2 else 256
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
sc.render.image_settings.file_format = "PNG"
sc.render.image_settings.color_mode = "RGBA"
sc.render.image_settings.color_depth = "16"
try:
    sc.view_settings.view_transform = "AgX"
    sc.view_settings.look = "AgX - Medium High Contrast"
except Exception:
    sc.view_settings.view_transform = "Filmic"


def world():
    w = bpy.data.worlds.new("Studio")
    sc.world = w
    w.use_nodes = True
    nt = w.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputWorld")
    bg = nt.nodes.new("ShaderNodeBackground")
    env = nt.nodes.new("ShaderNodeTexEnvironment")
    path = os.path.join(bpy.utils.system_resource("DATAFILES", path="studiolights/world"), "city.exr")
    env.image = bpy.data.images.load(path)
    mapping = nt.nodes.new("ShaderNodeMapping")
    coord = nt.nodes.new("ShaderNodeTexCoord")
    mapping.inputs["Rotation"].default_value = (0, 0, math.radians(140))
    nt.links.new(coord.outputs["Generated"], mapping.inputs["Vector"])
    nt.links.new(mapping.outputs["Vector"], env.inputs["Vector"])
    hs = nt.nodes.new("ShaderNodeHueSaturation")
    hs.inputs["Saturation"].default_value = 0.0
    nt.links.new(env.outputs["Color"], hs.inputs["Color"])
    nt.links.new(hs.outputs["Color"], bg.inputs["Color"])
    bg.inputs["Strength"].default_value = 0.55
    nt.links.new(bg.outputs["Background"], out.inputs["Surface"])


def softbox(name, loc, rot, size, strength):
    """An emissive card seen only in reflections (the crisp bands chrome needs)."""
    bpy.ops.mesh.primitive_plane_add(size=1, location=loc, rotation=rot)
    p = bpy.context.object
    p.name = name
    p.scale = (size[0], size[1], 1)
    m = bpy.data.materials.new(name + "_m")
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
    return p


def key_light(loc, energy, size=3.0):
    bpy.ops.object.light_add(type="AREA", location=loc)
    l = bpy.context.object
    l.data.energy = energy
    l.data.size = size
    d = Vector((0, 0, 0)) - l.location
    l.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    return l


def camera(loc, target, lens=50.0, ortho=0.0):
    bpy.ops.object.camera_add(location=loc)
    c = bpy.context.object
    d = Vector(target) - c.location
    c.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    if ortho > 0.0:
        c.data.type = "ORTHO"
        c.data.ortho_scale = ortho
    else:
        c.data.lens = lens
    sc.camera = c
    return c


def principled(name, base, metallic, rough, coat=0.0, aniso=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*base, 1)
    b.inputs["Metallic"].default_value = metallic
    b.inputs["Roughness"].default_value = rough
    if coat > 0.0:
        b.inputs["Coat Weight"].default_value = coat
        b.inputs["Coat Roughness"].default_value = 0.03
    if aniso > 0.0:
        b.inputs["Anisotropic"].default_value = aniso
    return m


def coil(ink: bool):
    sc.render.resolution_x = 640
    sc.render.resolution_y = 1400
    # A steel spring along -Z, seen from just past its top end: the rings shrink into the distance.
    turns, r, pitch = 11, 1.0, 0.55
    cu = bpy.data.curves.new("coil", "CURVE")
    cu.dimensions = "3D"
    cu.resolution_u = 32
    cu.bevel_depth = 0.085
    cu.bevel_resolution = 10
    cu.use_fill_caps = True
    sp = cu.splines.new("NURBS")
    n = turns * 24
    sp.points.add(n - 1)
    for i in range(n):
        a = i / 24 * math.tau
        k = i / (n - 1)
        rr = r * (1.0 - 0.72 * k ** 0.85)
        sp.points[i].co = (math.cos(a) * rr, math.sin(a) * rr, -i / 24 * pitch, 1)
    sp.use_endpoint_u = True
    sp.order_u = 4
    ob = bpy.data.objects.new("Coil", cu)
    sc.collection.objects.link(ob)
    if ink:
        mat = principled("Ink", (0.012, 0.013, 0.015), 0.0, 0.32, coat=1.0)
    else:
        mat = principled("Chrome", (0.94, 0.95, 0.97), 1.0, 0.045)
    cu.materials.append(mat)
    camera((0.0, -4.4, 3.4), (0.0, 0.0, -2.4), lens=33.0)
    world()
    softbox("SoftTop", (0, 0.4, 4.0), (0, 0, 0), (6, 2.2), 7.0)
    softbox("StripL", (-3.2, -0.5, -1.5), (0, math.radians(-90), 0), (9, 0.5), 14.0)
    softbox("StripR", (3.0, 1.0, -2.5), (0, math.radians(90), 0), (9, 0.35), 10.0)
    key_light((-3, -3, 3), 900)
    key_light((3, -1, -4), 300, 2.0)


def disc():
    sc.render.resolution_x = 512
    sc.render.resolution_y = 512
    # The face (to 0.86 R) carries the stamp's ink; a raised, rounded rim around it.
    prof = [(0.0, 0.07), (0.84, 0.07), (0.86, 0.088), (0.885, 0.122), (0.945, 0.128), (0.982, 0.108),
        (1.0, 0.08), (1.0, -0.09), (0.98, -0.12), (0.0, -0.12)]
    me = bpy.data.meshes.new("prof")
    verts = [(x, 0.0, z) for x, z in prof]
    edges = [(i, i + 1) for i in range(len(verts) - 1)]
    me.from_pydata(verts, edges, [])
    d = bpy.data.objects.new("Disc", me)
    sc.collection.objects.link(d)
    scr = d.modifiers.new("lathe", "SCREW")
    scr.axis = "Z"
    scr.steps = 256
    scr.render_steps = 256
    scr.use_smooth_shade = True
    scr.use_merge_vertices = True
    me.use_auto_smooth = True
    me.auto_smooth_angle = math.radians(35)
    m = principled("Silver", (0.8, 0.81, 0.83), 1.0, 0.24, aniso=0.9)
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    tan = nt.nodes.new("ShaderNodeTangent")
    tan.direction_type = "RADIAL"
    tan.axis = "Z"
    nt.links.new(tan.outputs["Tangent"], b.inputs["Tangent"])
    coord = nt.nodes.new("ShaderNodeTexCoord")
    rings = nt.nodes.new("ShaderNodeTexWave")
    rings.wave_type = "RINGS"
    rings.inputs["Scale"].default_value = 90.0
    rings.inputs["Distortion"].default_value = 0.3
    rings.inputs["Detail"].default_value = 2.0
    nt.links.new(coord.outputs["Object"], rings.inputs["Vector"])
    grad = nt.nodes.new("ShaderNodeTexGradient")
    grad.gradient_type = "RADIAL"
    nt.links.new(coord.outputs["Object"], grad.inputs["Vector"])
    mul = nt.nodes.new("ShaderNodeMath")
    mul.operation = "MULTIPLY"
    mul.inputs[1].default_value = 220.0
    nt.links.new(grad.outputs["Fac"], mul.inputs[0])
    frac = nt.nodes.new("ShaderNodeMath")
    frac.operation = "PINGPONG"
    frac.inputs[1].default_value = 0.5
    nt.links.new(mul.outputs[0], frac.inputs[0])
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(coord.outputs["Object"], sep.inputs["Vector"])
    az = nt.nodes.new("ShaderNodeMath")
    az.operation = "ABSOLUTE"
    nt.links.new(sep.outputs["Z"], az.inputs[0])
    side = nt.nodes.new("ShaderNodeMath")
    side.operation = "LESS_THAN"
    side.inputs[1].default_value = 0.085
    nt.links.new(az.outputs[0], side.inputs[0])
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "FLOAT"
    nt.links.new(side.outputs[0], mix.inputs["Factor"])
    nt.links.new(rings.outputs["Fac"], mix.inputs["A"])
    nt.links.new(frac.outputs[0], mix.inputs["B"])
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.08
    bump.inputs["Distance"].default_value = 0.01
    nt.links.new(mix.outputs["Result"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], b.inputs["Normal"])
    me.materials.append(m)
    camera((0.0, -0.001, 6.0), (0, 0, 0), ortho=2.08)
    world()
    softbox("SoftTop", (-1.8, 1.2, 4.0), (math.radians(-25), math.radians(-30), 0), (3.5, 1.0), 5.0)
    softbox("Strip", (2.4, -1.6, 2.4), (math.radians(30), math.radians(55), 0), (5, 0.35), 14.0)
    softbox("Fill", (0.0, 3.0, 2.0), (math.radians(-60), 0, 0), (4, 0.6), 3.0)
    key_light((-3, -2, 5), 300)


def printer():
    """The reward receipt's thermal printer, seen from the front and above: a satin black slab with
    rounded edges, the slit the receipt feeds out of along its top, a red LED and its etched name."""
    import json
    from bpy_extras.object_utils import world_to_camera_view
    sc.render.resolution_x = 1500
    sc.render.resolution_y = 380
    W, D, H = 6.4, 1.0, 0.55
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, 0))
    body = bpy.context.object
    body.name = "Printer"
    body.scale = (W, D, H)
    bpy.ops.object.transform_apply(scale=True)
    # The slit: cut through the top, a little forward of the middle.
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, -0.1, H * 0.5))
    cut = bpy.context.object
    cut.scale = (W - 0.5, 0.075, 0.62)
    bpy.ops.object.transform_apply(scale=True)
    bo = body.modifiers.new("slit", "BOOLEAN")
    bo.operation = "DIFFERENCE"
    bo.object = cut
    cut.hide_render = True
    cut.hide_viewport = True
    bv = body.modifiers.new("round", "BEVEL")
    bv.width = 0.11
    bv.segments = 6
    bv.limit_method = "ANGLE"
    bpy.ops.object.shade_smooth()
    body.data.use_auto_smooth = True
    body.data.auto_smooth_angle = math.radians(40)
    body.data.materials.append(principled("Satin", (0.016, 0.016, 0.018), 0.0, 0.38, coat=0.35))
    # The slit's throat: a black card down inside it, so the slot reads deep.
    bpy.ops.mesh.primitive_plane_add(size=1, location=(0, -0.1, H * 0.5 - 0.2), rotation=(0, 0, 0))
    throat = bpy.context.object
    throat.scale = (W - 0.52, 0.07, 1)
    m = principled("Throat", (0.0, 0.0, 0.0), 0.0, 1.0)
    throat.data.materials.append(m)
    # The LED on the front face, right, in a small bezel.
    bpy.ops.mesh.primitive_cylinder_add(radius=0.075, depth=0.04, location=(W * 0.5 - 0.42, -D * 0.5 - 0.005, -0.02),
        rotation=(math.radians(90), 0, 0))
    bez = bpy.context.object
    bez.data.materials.append(principled("Bezel", (0.5, 0.5, 0.52), 1.0, 0.3))
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.05, location=(W * 0.5 - 0.42, -D * 0.5 - 0.02, -0.02))
    led = bpy.context.object
    lm = bpy.data.materials.new("Led")
    lm.use_nodes = True
    nt = lm.node_tree
    nt.nodes.clear()
    o = nt.nodes.new("ShaderNodeOutputMaterial")
    e = nt.nodes.new("ShaderNodeEmission")
    e.inputs["Color"].default_value = (1.0, 0.07, 0.015, 1)
    e.inputs["Strength"].default_value = 3.2
    nt.links.new(e.outputs["Emission"], o.inputs["Surface"])
    led.data.materials.append(lm)
    # Its name, etched into the front face (a slightly lighter, rougher print).
    bpy.ops.object.text_add(location=(-W * 0.5 + 0.34, -D * 0.5 - 0.004, -0.09), rotation=(math.radians(90), 0, 0))
    tx = bpy.context.object
    tx.data.body = "HH  ·  THERMAL RECEIPT  ·  58MM"
    tx.data.size = 0.12
    tx.data.extrude = 0.004
    tx.data.space_character = 1.25
    tx.data.materials.append(principled("Etch", (0.09, 0.09, 0.1), 0.0, 0.75))
    cam = camera((0.0, -7.2, 5.0), (0.0, 0.0, 0.05), ortho=W + 0.5)
    world()
    softbox("TopBand", (0.0, 1.5, 4.5), (math.radians(-25), 0, 0), (9.0, 0.8), 6.0)
    softbox("Front", (0.0, -4.0, 1.2), (math.radians(75), 0, 0), (9.0, 0.5), 2.5)
    key_light((-4, -3, 6), 400, 4.0)
    bpy.context.view_layer.update()
    # Where the paper leaves the slit (its centre line at the top face), in the render's pixels.
    v = world_to_camera_view(sc, cam, Vector((0.0, -0.1, H * 0.5)))
    vl = world_to_camera_view(sc, cam, Vector((-(W - 0.5) * 0.5, -0.1, H * 0.5)))
    vr = world_to_camera_view(sc, cam, Vector(((W - 0.5) * 0.5, -0.1, H * 0.5)))
    info = {"slit_y": (1.0 - v.y) * sc.render.resolution_y, "slit_x0": vl.x * sc.render.resolution_x,
        "slit_x1": vr.x * sc.render.resolution_x, "size": [sc.render.resolution_x, sc.render.resolution_y]}
    with open(os.path.join(OUT, WHICH + ".json"), "w") as f:
        json.dump(info, f)


def clip():
    """A steel paperclip (the gem shape: three U bends), seen from above, for clipping a photo to the
    intake form."""
    sc.render.resolution_x = 360
    sc.render.resolution_y = 1000
    pts = []

    def line(a, b, n=6):
        for i in range(n):
            t = i / n
            pts.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))

    def arc(c, r, a0, a1, n=24):
        for i in range(n):
            t = a0 + (a1 - a0) * i / n
            pts.append((c[0] + r * math.cos(t), c[1] + r * math.sin(t)))

    line((-0.18, 2.35), (-0.18, 0.55))
    arc((0.0, 0.55), 0.18, math.pi, 2 * math.pi)
    line((0.18, 0.55), (0.18, 2.75))
    arc((-0.14, 2.75), 0.32, 0.0, math.pi)
    line((-0.46, 2.75), (-0.46, 0.42))
    arc((0.0, 0.42), 0.46, math.pi, 2 * math.pi)
    line((0.46, 0.42), (0.46, 2.45))
    pts.append((0.46, 2.45))
    cu = bpy.data.curves.new("clip", "CURVE")
    cu.dimensions = "3D"
    cu.bevel_depth = 0.034
    cu.bevel_resolution = 8
    cu.use_fill_caps = True
    sp = cu.splines.new("POLY")
    sp.points.add(len(pts) - 1)
    for i, (x, y) in enumerate(pts):
        sp.points[i].co = (x, y - 1.55, 0.0, 1.0)
    ob = bpy.data.objects.new("Clip", cu)
    sc.collection.objects.link(ob)
    ob.data.materials.append(principled("Steel", (0.78, 0.79, 0.81), 1.0, 0.16, aniso=0.5))
    camera((0.0, -0.001, 6.0), (0, 0, 0), ortho=3.4)
    world()
    softbox("SoftTop", (-1.8, 1.2, 4.0), (math.radians(-25), math.radians(-30), 0), (3.5, 1.0), 6.0)
    softbox("Strip", (2.4, -1.6, 2.4), (math.radians(30), math.radians(55), 0), (5, 0.35), 16.0)
    softbox("Fill", (0.0, 3.0, 2.0), (math.radians(-60), 0, 0), (4, 0.6), 3.0)
    key_light((-3, -2, 5), 300)


if WHICH == "clip":
    clip()
elif WHICH == "printer":
    printer()
elif WHICH == "coil_chrome":
    coil(False)
elif WHICH == "coil_ink":
    coil(True)
else:
    disc()
sc.render.filepath = os.path.join(OUT, WHICH + ".png")
bpy.ops.render.render(write_still=True)
print("RENDERED", sc.render.filepath)
