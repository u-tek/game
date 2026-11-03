"""Halo & Horn battle hit effects, rendered in Cycles on the GPU.

    blender --background --factory-startup --python tools/blender/hit_fx.py -- <out_dir> <which> [variant]

which: slash (variants 0, 1), thrust, splat, droplet, blot. Writes <out_dir>/<which><variant>_<i>.png
(white on transparent, at twice the shipped size). Then tools/blender/finish_hit_fx.py prints them as
ink and packs them as soft-edged L8 sheets into assets/art/ui/hit/ (src/ui/battle/press_layer.gd).

slash (striker, assassin): one dry-brush ink stroke, the blow's path. A ribbon mesh along a shallow
arc, as wide as the brush's press (a hard press at the entry, a fat belly, a long lifting taper); its
ink is noise stretched along the stroke (the bristles), cut harder toward the tail and the edges, so
the end breaks into dry streaks. Over 6 frames the head runs out with a ragged front, flecks fly off
the belly along the swing, and the stroke dries out. Variant 1 is a flatter, heavier sweep.
thrust (guardian): a straight jab of the same brush that thickens as it pushes in, and a short crown
of spikes and droplets bursting off its tip.
splat (a ranged shot landing): the ultimate's ink crown (ult_fx.py) at lower energy, face-on, its
spikes and droplets running on along the shot (+x).
droplet (the shot in flight): a teardrop of ink with two satellite drops, 4 looping frames.
blot (what a fallen echo leaves on the street): a spread pool with short drips, foreshortened.
Each takes about 1-3 s a frame on an RTX 3070 (OptiX).
"""
import bpy, bmesh, math, random, sys, os

argv = sys.argv[sys.argv.index("--") + 1:]
OUT = os.path.abspath(argv[0])
WHICH = argv[1]
VAR = int(argv[2]) if len(argv) > 2 else 0
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
sc.cycles.samples = 8
sc.cycles.use_denoising = False
sc.cycles.transparent_max_bounces = 8
sc.render.film_transparent = True
sc.render.image_settings.file_format = "PNG"
sc.render.image_settings.color_mode = "RGBA"
sc.render.resolution_x = 512
sc.render.resolution_y = 512
sc.render.resolution_percentage = 100
sc.view_settings.view_transform = "Standard"


def size(w: int, h: int) -> None:
    sc.render.resolution_x = w
    sc.render.resolution_y = h


def ortho_camera(scale: float, at=(0.0, 0.0)) -> None:
    cam_d = bpy.data.cameras.new("Cam")
    cam_d.type = "ORTHO"
    cam_d.ortho_scale = scale
    cam = bpy.data.objects.new("Cam", cam_d)
    sc.collection.objects.link(cam)
    sc.camera = cam
    cam.location = (at[0], at[1], 20)


def ribbon(path, width, n: int):
    """A strip along path(u) -> (x, y, normal angle), width(u) wide, UV u along it and v across."""
    me = bpy.data.meshes.new("Ribbon")
    ob = bpy.data.objects.new("Ribbon", me)
    sc.collection.objects.link(ob)
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new()
    rows = []
    for i in range(n):
        u = i / (n - 1)
        x, y, a = path(u)
        nx, ny = math.cos(a), math.sin(a)
        w = width(u) * 0.5
        rows.append((bm.verts.new((x + nx * w, y + ny * w, 0)), bm.verts.new((x - nx * w, y - ny * w, 0)), u))
    for i in range(n - 1):
        a0, b0, u0 = rows[i]
        a1, b1, u1 = rows[i + 1]
        f = bm.faces.new((a0, b0, b1, a1))
        for loop, (uu, vv) in zip(f.loops, ((u0, 1), (u0, 0), (u1, 0), (u1, 1))):
            loop[uv].uv = (uu, vv)
    bm.to_mesh(me)
    bm.free()
    return me


def brush_material(seed: float, dry_tail: float, dry_edge: float, base: float, bristle: float = 26.0):
    """Ink where stretched noise beats a threshold that rises toward the tail and the edges; shown up
    to a ragged head. Returns (material, head value node, dry value node)."""
    mat = bpy.data.materials.new("Ink")
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    new, link = nt.nodes.new, nt.links.new

    def m(op, a=None, b=None, va=None, vb=None):
        n = new("ShaderNodeMath")
        n.operation = op
        if a is not None:
            link(a, n.inputs[0])
        elif va is not None:
            n.inputs[0].default_value = va
        if b is not None:
            link(b, n.inputs[1])
        elif vb is not None:
            n.inputs[1].default_value = vb
        return n.outputs[0]

    out = new("ShaderNodeOutputMaterial")
    mix = new("ShaderNodeMixShader")
    tr = new("ShaderNodeBsdfTransparent")
    em = new("ShaderNodeEmission")
    link(tr.outputs[0], mix.inputs[1])
    link(em.outputs[0], mix.inputs[2])
    link(mix.outputs[0], out.inputs[0])
    tc = new("ShaderNodeTexCoord")
    sep = new("ShaderNodeSeparateXYZ")
    link(tc.outputs["UV"], sep.inputs[0])
    U, V = sep.outputs[0], sep.outputs[1]
    comb = new("ShaderNodeCombineXYZ")
    link(m("MULTIPLY", U, vb=2.2), comb.inputs[0])
    link(m("MULTIPLY", V, vb=bristle), comb.inputs[1])
    comb.inputs[2].default_value = seed
    noise = new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 1.7
    noise.inputs["Detail"].default_value = 7.0
    noise.inputs["Roughness"].default_value = 0.62
    link(comb.outputs[0], noise.inputs["Vector"])
    edge = m("MULTIPLY", m("ABSOLUTE", m("SUBTRACT", V, vb=0.5)), vb=dry_edge)
    dry = new("ShaderNodeValue")
    tail = m("MULTIPLY", m("POWER", U, vb=2.0), vb=dry_tail)
    thr = m("ADD", m("ADD", edge, tail), m("ADD", dry.outputs[0], vb=base))
    ink = m("GREATER_THAN", noise.outputs["Fac"], thr)
    head = new("ShaderNodeValue")
    n2 = new("ShaderNodeTexNoise")
    n2.inputs["Scale"].default_value = 9.0
    link(comb.outputs[0], n2.inputs["Vector"])
    front = m("ADD", head.outputs[0], m("MULTIPLY", m("SUBTRACT", n2.outputs["Fac"], vb=0.5), vb=0.06))
    link(m("MULTIPLY", m("LESS_THAN", U, front), ink), mix.inputs[0])
    return mat, head, dry


def flat_material():
    mat = bpy.data.materials.new("Flat")
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    o = nt.nodes.new("ShaderNodeOutputMaterial")
    e = nt.nodes.new("ShaderNodeEmission")
    nt.links.new(e.outputs[0], o.inputs[0])
    return mat


def disc(x: float, y: float, r: float, mat, rng):
    bpy.ops.mesh.primitive_circle_add(vertices=12, radius=r, fill_type="NGON", location=(x, y, 0))
    o = bpy.context.object
    o.data.materials.append(mat)
    for v in o.data.vertices:
        v.co.x *= rng.uniform(0.75, 1.25)
        v.co.y *= rng.uniform(0.75, 1.25)
    return o


def ease_out(k: float) -> float:
    return 1.0 - (1.0 - k) ** 3


def render(name: str) -> None:
    sc.render.filepath = os.path.join(OUT, name)
    bpy.ops.render.render(write_still=True)


def slash() -> None:
    rng = random.Random(40 + VAR)
    # A shallow arc across the frame (2:1), upper left to the right; variant 1 flatter and heavier.
    a0, span, rad, press, cy = [(152, 124, 4.0, 1.6, -1.25), (144, 108, 4.6, 1.8, -1.7)][VAR]

    def path(u):
        a = math.radians(a0 - span * u)
        r = rad * (1.0 - 0.1 * u)
        return math.cos(a) * r, math.sin(a) * r + cy, a

    def width(u):
        return 0.1 + 0.95 * press * math.sin(math.pi * min(u * 1.7, 1.0)) ** 0.55 * (1 - u) ** 0.6

    size(768, 384)
    me = ribbon(path, width, 220)
    # Coarse bristles: their gaps must survive the impression's size on a phone (3+ px).
    mat, head, dry = brush_material(VAR * 3.7 + 1.0, 0.7, 0.75, 0.16, 9.0)
    me.materials.append(mat)
    fm = flat_material()
    # Flecks: shaken off the loaded belly as the brush passes, flying on along the swing and outward.
    flecks = []
    for _ in range(13):
        u = rng.uniform(0.3, 0.8)
        x, y, a = path(u)
        tang = a - math.pi / 2
        # Thrown off the outer edge (the arc's normal) and carried on a little along the swing.
        out_v, on_v = rng.uniform(0.9, 2.6), rng.uniform(0.4, 1.6)
        vx = math.cos(a) * out_v + math.cos(tang) * on_v
        vy = math.sin(a) * out_v + math.sin(tang) * on_v
        flecks.append((u, x, y, vx, vy, disc(x, y, rng.uniform(0.03, 0.1), fm, rng)))
    ortho_camera(8.0, (0, 1.95))
    for f in range(6):
        k = f / 5.0
        h = min(1.08, 0.2 + k * 1.7)
        head.outputs[0].default_value = h
        dry.outputs[0].default_value = max(0.0, k - 0.45) * 0.75
        for u, x, y, vx, vy, o in flecks:
            # It leaves when the head passes, then flies on (t: frames since it left).
            t = (h - u) / 1.7 * 5.0
            o.hide_render = t <= 0.0 or k > 0.95
            tt = max(t, 0.0) * 0.18
            o.location = (x + vx * tt, y + vy * tt, 0)
            o.scale = (1.0 + tt * 1.2, max(1.0 - tt * 0.6, 0.35), 1.0)
            o.rotation_euler = (0, 0, math.atan2(vy, vx))
        render("slash%d_%d.png" % (VAR, f))


def thrust() -> None:
    rng = random.Random(77)

    def path(u):
        return -3.0 + 5.6 * u, 0.06 * math.sin(u * 5.0), math.pi / 2

    def width(u):
        # A jab: thin where it leaves, swelling as it pushes in, blunt at the tip.
        return 0.14 + 1.05 * u ** 0.7 * (1.0 - max(0.0, u - 0.92) / 0.08 * 0.55)

    size(640, 256)
    me = ribbon(path, width, 160)
    mat, head, dry = brush_material(11.0, 0.25, 0.7, 0.16, 8.0)
    me.materials.append(mat)
    # The tip's burst: metaball spikes off the blunt end, and droplets thrown forward.
    mb = bpy.data.metaballs.new("Tip")
    mb.resolution = 0.02
    mb.render_resolution = 0.012
    mb.threshold = 0.6
    ob = bpy.data.objects.new("Tip", mb)
    sc.collection.objects.link(ob)
    fm = flat_material()
    mb.materials.append(fm)
    tip = (2.55, 0.0)
    spikes = []
    for i in range(11):
        a = rng.uniform(-1.4, 1.4)
        reach = rng.uniform(0.6, 1.4) * (1.0 + 0.5 * math.cos(a))
        spikes.append((a, reach, rng.uniform(0.22, 0.32), [mb.elements.new() for _ in range(12)]))
    drops = []
    for _ in range(10):
        a = rng.uniform(-1.3, 1.3)
        drops.append((a, rng.uniform(1.4, 3.2), rng.uniform(0.0, 0.25), disc(tip[0], tip[1], rng.uniform(0.035, 0.08), fm, rng)))
    ortho_camera(8.0, (0.2, 0.0))
    for f in range(6):
        k = f / 5.0
        head.outputs[0].default_value = [0.4, 0.8, 1.05, 1.05, 1.05, 1.05][f]
        dry.outputs[0].default_value = max(0.0, k - 0.55) * 0.9
        g = [0.0, 0.0, 0.5, 1.0, 1.0, 0.85][f]
        thin = [1.0, 1.0, 1.0, 1.0, 0.7, 0.45][f]
        for a, reach, wd, chain in spikes:
            for j, e in enumerate(chain):
                u = (j + 1) / len(chain)
                r = reach * g * u
                e.co = (tip[0] + math.cos(a) * r, tip[1] + math.sin(a) * r, 0)
                e.radius = max(wd * (1.0 - u) ** 1.5 * thin * (0.4 + 0.6 * g) + 0.02, 0.0001) if g > 0 else 0.0001
                e.stiffness = 2.0
        for a, v, t0, o in drops:
            t = max(0.0, (k - 0.5 - t0) / 0.5)
            o.hide_render = t <= 0.0
            o.location = (tip[0] + math.cos(a) * v * t, tip[1] + math.sin(a) * v * t, 0)
            o.scale = (1.0 + t, max(1.0 - 0.5 * t, 0.4), 1.0)
            o.rotation_euler = (0, 0, a)
        render("thrust0_%d.png" % f)


def crown_body(rng, n_lobes: int, n_spikes: int, n_drops: int, bias: float):
    """The ult_fx.py crown's parts: a disc, scalloped lobes, spike chains and droplets."""
    mb = bpy.data.metaballs.new("Crown")
    mb.resolution = 0.012
    mb.render_resolution = 0.008
    mb.threshold = 0.6
    ob = bpy.data.objects.new("Crown", mb)
    sc.collection.objects.link(ob)
    mb.materials.append(flat_material())
    disc_e = mb.elements.new()
    disc_e.type = "ELLIPSOID"
    lobes = []
    for i in range(n_lobes):
        lobes.append((mb.elements.new(), math.tau * i / n_lobes + rng.uniform(-0.12, 0.12), rng.uniform(0.86, 1.0), rng.uniform(0.2, 0.3)))
    for i in range(8):
        lobes.append((mb.elements.new(), math.tau * i / 8, 0.55, 0.42))
    spikes = []
    for i in range(n_spikes):
        a = math.tau * i / n_spikes + rng.uniform(-0.1, 0.1)
        reach = rng.uniform(0.9, 2.2) * (1.3 if i % 4 == 0 else 1.0) * (1.0 + bias * math.cos(a))
        spikes.append([a, reach, rng.uniform(0.0, 0.2), rng.uniform(0.24, 0.36), [mb.elements.new() for _ in range(16)]])
    drops = []
    for i in range(n_drops):
        if i < n_drops // 2:
            sp = spikes[rng.randrange(len(spikes))]
            a, r0 = sp[0] + rng.uniform(-0.05, 0.05), sp[1] * 0.9
        else:
            a, r0 = rng.uniform(-1.3, 1.3), rng.uniform(0.9, 1.5)
        drops.append((a, r0, rng.uniform(1.2, 2.8) * (1.0 + 0.4 * math.cos(a)), rng.uniform(0.06, 0.14), rng.uniform(0.35, 0.7), mb.elements.new()))
    return disc_e, lobes, spikes, drops


def crown_pose(parts, k: float, spread_k: float = 1.0) -> None:
    disc_e, lobes, spikes, drops = parts
    spread = (0.75 + 0.9 * ease_out(min(k * 1.3, 1.0))) * spread_k
    disc_e.co = (0, 0, 0)
    disc_e.radius = 1.0
    disc_e.size_x = spread
    disc_e.size_y = spread
    disc_e.size_z = 0.22 * (1.0 - 0.45 * k)
    disc_e.stiffness = 2.0
    for e, a, rr, rad in lobes:
        e.co = (math.cos(a) * rr * spread, math.sin(a) * rr * spread, 0)
        e.radius = rad * spread
        e.stiffness = 2.0
    for a, reach, delay, width, chain in spikes:
        g = ease_out(max(0.0, min((k - delay) / 0.78, 1.0)))
        for j, e in enumerate(chain):
            u = (j + 1) / len(chain)
            r = spread * 0.7 + reach * g * u
            e.co = (math.cos(a) * r, math.sin(a) * r, 0.0)
            e.radius = max(width * (1.0 - u) ** 1.6 * (0.45 + 0.55 * g) * (1.0 - 0.3 * k) + 0.035, 0.0001)
            e.stiffness = 2.0
    for a, r0, v, sz, t0, e in drops:
        if k < t0:
            e.co = (math.cos(a) * r0 * 0.5, math.sin(a) * r0 * 0.5, 0)
            e.radius = 0.0001
            continue
        t = (k - t0) / (1.0 - t0)
        e.co = (math.cos(a) * (r0 + v * t * 1.6), math.sin(a) * (r0 + v * t * 1.6), 0.0)
        e.radius = sz * (1.0 - 0.3 * t)
        e.stiffness = 2.0


def splat() -> None:
    size(512, 512)
    parts = crown_body(random.Random(2208), 12, 14, 18, 0.8)
    ortho_camera(10.0, (0.9, 0.0))
    for f in range(6):
        crown_pose(parts, f / 5.0)
        render("splat0_%d.png" % f)


def droplet() -> None:
    size(256, 128)
    mb = bpy.data.metaballs.new("Drop")
    mb.resolution = 0.01
    mb.render_resolution = 0.006
    mb.threshold = 0.6
    ob = bpy.data.objects.new("Drop", mb)
    sc.collection.objects.link(ob)
    mb.materials.append(flat_material())
    head = mb.elements.new()
    tail = [mb.elements.new() for _ in range(9)]
    sats = [mb.elements.new() for _ in range(2)]
    ortho_camera(4.0, (-0.6, 0.0))
    for f in range(4):
        st = [1.0, 1.35, 1.1, 1.45][f]
        head.co = (0.5, 0, 0)
        head.radius = 0.34
        head.stiffness = 2.0
        for j, e in enumerate(tail):
            u = (j + 1) / len(tail)
            e.co = (0.5 - u * 0.95 * st, 0.02 * math.sin(f + j), 0)
            e.radius = 0.3 * (1.0 - u) ** 0.9 + 0.06
            e.stiffness = 2.0
        for i, e in enumerate(sats):
            e.co = (-1.0 * st - 0.45 * i - 0.1 * math.sin(f * 1.7 + i), 0.12 * (1 if i else -1) * math.cos(f + i), 0)
            e.radius = 0.09 - 0.025 * i
            e.stiffness = 3.0
        render("droplet0_%d.png" % f)


def blot() -> None:
    size(768, 256)
    rng = random.Random(912)
    parts = crown_body(rng, 30, 9, 0, 0.0)
    # A pool, not a cloud: many small uneven lobes hugging the rim, and drips run out of it.
    disc_e, lobes, spikes, _drops = parts
    for i, (e, a, _rr, _rad) in enumerate(lobes):
        if i < 30:
            lobes[i] = (e, a, rng.uniform(0.86, 1.12), rng.uniform(0.05, 0.13))
        else:
            lobes[i] = (e, a, 0.5, 0.34)
    for sp in spikes:
        sp[1] = rng.uniform(0.45, 1.3)
        sp[2] = 0.0
        sp[3] *= 0.8
    cam_d = bpy.data.cameras.new("Cam")
    cam_d.type = "ORTHO"
    cam_d.ortho_scale = 7.6
    cam = bpy.data.objects.new("Cam", cam_d)
    sc.collection.objects.link(cam)
    sc.camera = cam
    tilt = math.radians(70)
    cam.location = (0, -math.sin(tilt) * 20, math.cos(tilt) * 20)
    cam.rotation_euler = (tilt, 0, 0)
    crown_pose(parts, 1.0, 1.25)
    render("blot0_0.png")


JOBS = {"slash": slash, "thrust": thrust, "splat": splat, "droplet": droplet, "blot": blot}
if WHICH not in JOBS:
    raise SystemExit("unknown: " + WHICH)
JOBS[WHICH]()
