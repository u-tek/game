"""Halo & Horn ultimate effects, rendered in Cycles on the GPU.

    blender --background --factory-startup --python tools/blender/ult_fx.py -- <out_dir> <which> [samples]

which: crown. Writes <out_dir>/crown_<i>.png (8 frames, 512 px, 16-bit RGBA, transparent).
Then tools/blender/finish_ult_fx.py prints them as ink (threshold, dot gain, fibre edge) and packs the
sheet into assets/art/ui/ult/.

crown: an ink splash struck from above, seen down a camera tilted 20 degrees off the vertical. A
liquid disc (metaballs, so the spikes grow out of it as one body) throws 22 tapered spikes of
random length and 30 droplets; over the 8 frames the spikes run out with an ease-out, the
droplets fly off ballistically and pinch away from the tips, and the disc spreads and thins.
About 2-5 s a frame on an RTX 3070 (OptiX).
"""
import bpy, math, random, sys, os
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
OUT = argv[0]
WHICH = argv[1]
SAMPLES = int(argv[2]) if len(argv) > 2 else 32
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
sc.cycles.use_denoising = False
sc.render.film_transparent = True
sc.render.image_settings.file_format = "PNG"
sc.render.image_settings.color_mode = "RGBA"
sc.render.image_settings.color_depth = "16"
sc.render.resolution_x = 512
sc.render.resolution_y = 512
sc.render.resolution_percentage = 100

FRAMES = 8


def ease_out(k: float) -> float:
    return 1.0 - (1.0 - k) ** 3


def crown() -> None:
    rng = random.Random(1508)
    mb = bpy.data.metaballs.new("Crown")
    mb.resolution = 0.012
    mb.render_resolution = 0.008
    mb.threshold = 0.6
    ob = bpy.data.objects.new("Crown", mb)
    sc.collection.objects.link(ob)
    mat = bpy.data.materials.new("Ink")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (1, 1, 1, 1)
    mb.materials.append(mat)

    # The disc: one flat ellipsoid, and a ring of lobes so its rim is never a clean circle.
    disc = mb.elements.new()
    disc.type = "ELLIPSOID"
    lobes = []
    for i in range(16):
        e = mb.elements.new()
        e.type = "BALL"
        lobes.append((e, math.tau * i / 16 + rng.uniform(-0.12, 0.12), rng.uniform(0.86, 1.0), rng.uniform(0.2, 0.3)))
    # Filler between the disc and its scalloped rim (else a ring of paper shows between them).
    for i in range(10):
        e = mb.elements.new()
        e.type = "BALL"
        lobes.append((e, math.tau * i / 10, 0.55, 0.42))

    # Spikes: chains of shrinking balls along a ray, lifted a little off the floor toward the tip
    # (the crown's wall), each with its own reach and start delay.
    spikes = []
    for i in range(22):
        a = math.tau * i / 22 + rng.uniform(-0.09, 0.09)
        # The blow comes from the left: the splash runs further to the right (the strike's way).
        reach = rng.uniform(1.0, 2.6) * (1.35 if i % 4 == 0 else 1.0) * (1.0 + 0.55 * math.cos(a))
        delay = rng.uniform(0.0, 0.2)
        width = rng.uniform(0.26, 0.38)
        chain = []
        for j in range(18):
            e = mb.elements.new()
            e.type = "BALL"
            chain.append(e)
        spikes.append((a, reach, delay, width, chain))

    # Droplets: some leave the spike tips, some are thrown from the rim at random.
    drops = []
    for i in range(30):
        if i < 14:
            s = spikes[rng.randrange(len(spikes))]
            a = s[0] + rng.uniform(-0.05, 0.05)
            r0 = s[1] * 0.92
        else:
            a = rng.uniform(-1.4, 1.4) if rng.random() < 0.7 else rng.uniform(0, math.tau)
            r0 = rng.uniform(0.9, 1.6)
        v = rng.uniform(1.3, 3.0) * (1.0 + 0.4 * math.cos(a))
        lift = rng.uniform(0.6, 1.8)
        size = rng.uniform(0.06, 0.16)
        t0 = rng.uniform(0.35, 0.7)
        e = mb.elements.new()
        e.type = "BALL"
        drops.append((a, r0, v, lift, size, t0, e))

    cam_d = bpy.data.cameras.new("Cam")
    cam_d.type = "ORTHO"
    cam_d.ortho_scale = 11.0
    cam = bpy.data.objects.new("Cam", cam_d)
    sc.collection.objects.link(cam)
    sc.camera = cam
    tilt = math.radians(20)
    cam.location = Vector((0, -math.sin(tilt) * 20, math.cos(tilt) * 20))
    cam.rotation_euler = (tilt, 0, 0)
    bpy.ops.object.light_add(type="SUN", location=(0, 0, 10))
    bpy.context.object.data.energy = 3.0

    for f in range(FRAMES):
        k = f / (FRAMES - 1)
        spread = 0.75 + 0.9 * ease_out(min(k * 1.3, 1.0))
        thin = 1.0 - 0.45 * k
        disc.co = (0, 0, 0)
        disc.radius = 1.0
        disc.size_x = spread
        disc.size_y = spread
        disc.size_z = 0.22 * thin
        disc.stiffness = 2.0
        for e, a, rr, rad in lobes:
            e.co = (math.cos(a) * rr * spread, math.sin(a) * rr * spread, 0)
            e.radius = rad * spread
            e.stiffness = 2.0
        for a, reach, delay, width, chain in spikes:
            g = ease_out(max(0.0, min((k - delay) / 0.78, 1.0)))
            n = len(chain)
            for j, e in enumerate(chain):
                u = (j + 1) / n
                r = spread * 0.7 + reach * g * u
                lift = 0.35 * g * u * u
                e.co = (math.cos(a) * r, math.sin(a) * r, lift)
                # A wedge: wide where it leaves the disc, a hair at the tip; late, the tip thins
                # further (it has let its drops go).
                e.radius = max(width * (1.0 - u) ** 1.6 * (0.45 + 0.55 * g) * (1.0 - 0.3 * k) + 0.035, 0.0001)
                e.stiffness = 2.0
        for a, r0, v, lift, size, t0, e in drops:
            if k < t0:
                e.co = (math.cos(a) * r0 * 0.5, math.sin(a) * r0 * 0.5, 0)
                e.radius = 0.0001
                continue
            t = (k - t0) / (1.0 - t0)
            r = r0 + v * t * 1.6
            z = lift * t - 1.6 * t * t
            e.co = (math.cos(a) * r, math.sin(a) * r, max(z, 0.0))
            e.radius = size * (1.0 - 0.3 * t)
            e.stiffness = 2.0
        sc.render.filepath = os.path.join(OUT, "crown_%d.png" % f)
        bpy.ops.render.render(write_still=True)


if WHICH == "crown":
    crown()
else:
    raise SystemExit("unknown: " + WHICH)
