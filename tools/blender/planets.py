"""Halo & Horn campaign worlds (style v4): one procedural planet per chapter, modelled in Blender and
baked to equirectangular maps that src/ui/v4/survey/planet.gdshader shades in real time.

    blender --background --factory-startup --python tools/blender/planets.py -- bake <out_dir> <which> [res] [gpu|cpu]
    blender --background --factory-startup --python tools/blender/planets.py -- beauty <maps_dir> <out_dir> <which> [gpu|cpu]

bake: for each world (which = all | comma list of 1-6) the terrain is a node graph of the surface
direction (noise, ridges, Voronoi craters, cracks and shards), baked as emission onto a UV sphere
whose UVs follow Godot's SphereMesh (u = longitude from +Z towards +X, v = 0 at the north pole), so
no resampling is needed. Writes <out_dir>/w<N>_h.npy (height, 2 x res wide), w<N>_a.npy (albedo base,
0..1) and w<N>_m.npy (feature mask: lava, ice cracks, crystal tips ...), float32, top row first.
tools/blender/finish_worlds.py (system Python, numpy + Pillow) turns them into the game's maps.

beauty: renders each finished world as a truly displaced sphere in a grey studio (a check of the
maps, 1024 px, transparent) from <maps_dir>/w<N>_albedo.jpg and w<N>_height.png.

GPU (OptiX) by default; pass cpu when the GPU is busy (the bake is emission only and fast either way).
"""
import math
import os
import sys
import time

import bpy
import numpy as np

argv = sys.argv[sys.argv.index("--") + 1:]
MODE = argv[0]


def setup(device: str, samples: int) -> bpy.types.Scene:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    if device == "gpu":
        prefs = bpy.context.preferences.addons["cycles"].preferences
        prefs.compute_device_type = "OPTIX"
        prefs.get_devices()
        for d in prefs.devices:
            d.use = d.type == "OPTIX"
        sc.cycles.device = "GPU"
    else:
        sc.cycles.device = "CPU"
    sc.cycles.samples = samples
    return sc


# ------------------------------------------------------------------ the bake sphere

def godot_dir(u: np.ndarray, v: np.ndarray) -> np.ndarray:
    """Godot SphereMesh direction for UV (u, v), as Blender coordinates (x, -z, y)."""
    ph = u * math.tau
    th = v * math.pi
    gx = np.sin(ph) * np.sin(th)
    gy = np.cos(th)
    gz = np.cos(ph) * np.sin(th)
    return np.stack([gx, -gz, gy], axis=-1)


def uv_sphere(seg: int, rings: int) -> bpy.types.Object:
    us = np.arange(seg + 1) / seg
    vs = np.arange(rings + 1) / rings
    uu, vv = np.meshgrid(us, vs)
    pts = godot_dir(uu, vv).reshape(-1, 3)
    faces = []
    row = seg + 1
    for j in range(rings):
        for i in range(seg):
            a = j * row + i
            faces.append((a, a + row, a + row + 1, a + 1))
    me = bpy.data.meshes.new("world")
    me.from_pydata([tuple(p) for p in pts], [], faces)
    me.update()
    # Outward faces (the first one is checked: its normal must point away from the centre).
    f0 = me.polygons[seg * (rings // 2)]
    if f0.normal.dot(f0.center) < 0.0:
        me.flip_normals()
    uvl = me.uv_layers.new(name="UV")
    vi = np.empty(len(me.loops), dtype=np.int32)
    me.loops.foreach_get("vertex_index", vi)
    uv = np.stack([uu.ravel(), 1.0 - vv.ravel()], axis=-1).astype(np.float32)
    uvl.data.foreach_set("uv", uv[vi].ravel())
    ob = bpy.data.objects.new("world", me)
    bpy.context.scene.collection.objects.link(ob)
    for p in me.polygons:
        p.use_smooth = True
    return ob


# ------------------------------------------------------------------ a small node language

class NG:
    """Builds a shader node graph from expressions: every method returns an output socket."""

    def __init__(self, nt: bpy.types.NodeTree) -> None:
        self.nt = nt

    def _set(self, sock, v) -> None:
        if isinstance(v, bpy.types.NodeSocket):
            self.nt.links.new(v, sock)
        else:
            sock.default_value = v

    def math(self, op: str, a, b=0.0, c=0.0, clamp: bool = False):
        n = self.nt.nodes.new("ShaderNodeMath")
        n.operation = op
        n.use_clamp = clamp
        self._set(n.inputs[0], a)
        self._set(n.inputs[1], b)
        self._set(n.inputs[2], c)
        return n.outputs[0]

    def add(self, a, b): return self.math("ADD", a, b)
    def sub(self, a, b): return self.math("SUBTRACT", a, b)
    def mul(self, a, b): return self.math("MULTIPLY", a, b)
    def div(self, a, b): return self.math("DIVIDE", a, b)
    def pw(self, a, b): return self.math("POWER", a, b)
    def mn(self, a, b): return self.math("MINIMUM", a, b)
    def mx(self, a, b): return self.math("MAXIMUM", a, b)
    def ab(self, a): return self.math("ABSOLUTE", a)
    def fl(self, a): return self.math("FLOOR", a)
    def fr(self, a): return self.math("FRACT", a)
    def lt(self, a, b): return self.math("LESS_THAN", a, b)
    def gt(self, a, b): return self.math("GREATER_THAN", a, b)
    def ma(self, a, b, c): return self.math("MULTIPLY_ADD", a, b, c)
    def ex(self, a): return self.math("EXPONENT", a)
    def sat(self, a): return self.math("ADD", a, 0.0, clamp=True)

    def lerp(self, a, b, t):
        return self.add(a, self.mul(self.sub(b, a), t))

    def remap(self, x, a: float, b: float, c: float = 0.0, d: float = 1.0, smooth: bool = False, clamp: bool = True):
        n = self.nt.nodes.new("ShaderNodeMapRange")
        n.interpolation_type = "SMOOTHSTEP" if smooth else "LINEAR"
        n.clamp = clamp
        self._set(n.inputs[0], x)
        self._set(n.inputs[1], a)
        self._set(n.inputs[2], b)
        self._set(n.inputs[3], c)
        self._set(n.inputs[4], d)
        return n.outputs[0]

    def smooth(self, e0: float, e1: float, x):
        return self.remap(x, e0, e1, 0.0, 1.0, smooth=True)

    def gauss(self, x, w: float):
        """exp(-(x / w)^2)"""
        q = self.div(x, w)
        return self.ex(self.mul(self.mul(q, q), -1.0))

    def noise(self, vec, scale: float, detail: float = 2.0, rough: float = 0.5, dist: float = 0.0, lac: float = 2.0, color: bool = False):
        n = self.nt.nodes.new("ShaderNodeTexNoise")
        n.noise_dimensions = "3D"
        self._set(n.inputs["Vector"], vec)
        self._set(n.inputs["Scale"], scale)
        self._set(n.inputs["Detail"], detail)
        self._set(n.inputs["Roughness"], rough)
        self._set(n.inputs["Lacunarity"], lac)
        self._set(n.inputs["Distortion"], dist)
        return n.outputs["Color"] if color else n.outputs["Fac"]

    def ridge(self, vec, scale: float, detail: float = 4.0, rough: float = 0.5, sharp: float = 2.0):
        """Ridged noise in 0..1, 1 on the crests."""
        f = self.noise(vec, scale, detail, rough)
        r = self.sub(1.0, self.ab(self.sub(self.mul(f, 2.0), 1.0)))
        return self.pw(self.sat(r), sharp)

    def voronoi(self, vec, scale: float, feature: str = "F1", metric: str = "EUCLIDEAN", rand: float = 1.0):
        n = self.nt.nodes.new("ShaderNodeTexVoronoi")
        n.voronoi_dimensions = "3D"
        n.feature = feature
        n.distance = metric
        self._set(n.inputs["Vector"], vec)
        self._set(n.inputs["Scale"], scale)
        self._set(n.inputs["Randomness"], rand)
        return n

    def sep(self, col):
        n = self.nt.nodes.new("ShaderNodeSeparateColor")
        self._set(n.inputs[0], col)
        return n.outputs[0], n.outputs[1], n.outputs[2]

    def vmath(self, op: str, a, b=None, scale: float = 1.0):
        n = self.nt.nodes.new("ShaderNodeVectorMath")
        n.operation = op
        self._set(n.inputs[0], a)
        if b is not None:
            self._set(n.inputs[1], b)
        if op == "SCALE":
            self._set(n.inputs[3], scale)
        return n.outputs["Value"] if op in ("LENGTH", "DOT_PRODUCT", "DISTANCE") else n.outputs["Vector"]

    def warp(self, p, scale: float, amount: float, detail: float = 2.0):
        c = self.noise(p, scale, detail, 0.5, color=True)
        off = self.vmath("SUBTRACT", c, (0.5, 0.5, 0.5))
        return self.vmath("ADD", p, self.vmath("SCALE", off, scale=amount * 2.0))

    def craters(self, p, scale: float, density: float, depth: float, r0: float = 0.16, r1: float = 0.38, rim: float = 0.35):
        """A field of bowl craters with raised rims (Voronoi cells; some cells hold a crater)."""
        v = self.voronoi(p, scale, "F1")
        d = v.outputs["Distance"]
        ra, rb, _ = self.sep(v.outputs["Color"])
        rad = self.add(r0, self.mul(rb, r1 - r0))
        x = self.div(d, rad)
        bowl = self.mul(self.sub(self.mul(x, x), 1.0), self.lt(x, 1.0))
        ridge = self.mul(self.gauss(self.sub(x, 1.0), 0.32), rim)
        on = self.gt(ra, 1.0 - density)
        return self.mul(self.mul(self.add(bowl, ridge), on), depth), self.mul(self.mul(self.lt(x, 1.0), on), self.sub(1.0, x))


# ------------------------------------------------------------------ the six worlds
# Each recipe returns (height, albedo 0..1, mask 0..1) sockets for the surface direction p.

def w_highland(g: NG, p):
    """Shattered Sanctum: broken terraced highlands, smooth dark lowland basins, old craters."""
    w = g.warp(p, 1.1, 0.22)
    cont = g.noise(w, 1.45, 7.0, 0.56)
    base = g.remap(cont, 0.40, 0.64)
    t = g.mul(base, 5.0)
    terr = g.div(g.add(g.fl(t), g.smooth(0.58, 0.94, g.fr(t))), 5.0)
    rid = g.ridge(g.warp(p, 3.0, 0.08), 4.2, 6.0, 0.55, 3.0)
    grain = g.noise(p, 52.0, 5.0, 0.62)
    fine = g.noise(p, 140.0, 3.0, 0.6)
    cr, crm = g.craters(g.warp(p, 6.0, 0.03), 7.0, 0.42, 0.10)
    cr2, _ = g.craters(p, 19.0, 0.35, 0.035)
    h = g.add(g.mul(terr, 0.62), g.mul(g.mul(rid, base), 0.26))
    h = g.add(h, g.mul(g.sub(grain, 0.5), 0.10))
    h = g.add(h, g.mul(g.sub(fine, 0.5), 0.035))
    h = g.add(g.add(h, cr), cr2)
    alb = g.add(0.28, g.mul(terr, 0.5))
    alb = g.add(alb, g.mul(g.mul(rid, base), 0.18))
    alb = g.add(alb, g.mul(g.sub(g.noise(p, 9.0, 4.0, 0.6), 0.5), 0.22))
    alb = g.add(alb, g.mul(crm, 0.12))
    mask = g.sub(1.0, g.smooth(0.0, 0.25, base))
    return h, alb, mask


def w_canyons(g: NG, p):
    """Ember Wastes: wind-cut mesas in strata, a braided canyon network, ember-lit canyon floors."""
    w = g.warp(p, 1.6, 0.26, 3.0)
    mesa = g.remap(g.noise(w, 2.0, 6.0, 0.5), 0.40, 0.62)
    mesa = g.smooth(0.25, 0.75, mesa)
    # Meandering canyons: the zero crossings of warped noise, a main network and side gullies.
    n1 = g.noise(g.warp(p, 2.4, 0.3, 4.0), 2.3, 3.0, 0.45)
    can = g.sub(1.0, g.smooth(0.0, 0.05, g.ab(g.sub(n1, 0.5))))
    n2 = g.noise(g.warp(p, 6.0, 0.12, 3.0), 6.5, 3.0, 0.5)
    can2 = g.mul(g.sub(1.0, g.smooth(0.0, 0.035, g.ab(g.sub(n2, 0.5)))), g.smooth(0.3, 0.7, mesa))
    rid = g.ridge(w, 6.0, 5.0, 0.55, 2.0)
    h = g.add(g.mul(mesa, 0.55), g.mul(rid, 0.16))
    h = g.sub(h, g.mul(can, 0.42))
    h = g.sub(h, g.mul(can2, 0.14))
    # Strata: soft steps over the height.
    s = g.mul(h, 16.0)
    h = g.lerp(h, g.div(g.add(g.fl(s), g.smooth(0.7, 1.0, g.fr(s))), 16.0), 0.55)
    h = g.add(h, g.mul(g.sub(g.noise(p, 60.0, 4.0, 0.6), 0.5), 0.06))
    band = g.math("SINE", g.mul(h, 70.0))
    alb = g.add(0.42, g.mul(band, 0.07))
    alb = g.add(alb, g.mul(mesa, 0.12))
    alb = g.sub(alb, g.mul(can, 0.18))
    alb = g.add(alb, g.mul(g.sub(g.noise(p, 14.0, 3.0, 0.6), 0.5), 0.14))
    mask = g.mx(can, g.mul(can2, 0.5))
    return h, alb, mask


def w_craters(g: NG, p):
    """Twilight Abyss: dark smooth maria, bright cratered uplands, fresh craters with ejecta."""
    w = g.warp(p, 1.0, 0.25)
    s = g.noise(w, 1.25, 5.0, 0.5)
    sea = g.smooth(0.52, 0.46, s)
    up = g.noise(p, 6.0, 7.0, 0.58)
    h = g.mul(g.sub(1.0, sea), g.add(0.55, g.mul(up, 0.35)))
    h = g.add(h, g.mul(sea, g.add(0.18, g.mul(g.noise(p, 20.0, 3.0, 0.5), 0.04))))
    c1, m1 = g.craters(g.warp(p, 4.0, 0.04), 3.2, 0.5, 0.22, 0.18, 0.42, 0.45)
    c2, m2 = g.craters(g.warp(p, 8.0, 0.02), 8.0, 0.55, 0.10)
    c3, m3 = g.craters(p, 19.0, 0.55, 0.045)
    c4, _ = g.craters(p, 42.0, 0.5, 0.018)
    h = g.add(g.add(g.add(g.add(h, c1), c2), c3), c4)
    h = g.add(h, g.mul(g.sub(g.noise(p, 90.0, 3.0, 0.6), 0.5), 0.025))
    alb = g.lerp(g.add(0.6, g.mul(up, 0.12)), 0.24, sea)
    # Fresh ejecta: bright haloes around some craters.
    ej = g.mul(g.mx(g.mx(m2, m3), g.mul(m1, 0.6)), g.gt(g.noise(p, 3.0, 2.0, 0.5), 0.52))
    alb = g.add(alb, g.mul(ej, 0.22))
    alb = g.add(alb, g.mul(g.sub(g.noise(p, 30.0, 4.0, 0.6), 0.5), 0.1))
    return h, alb, sea


def w_ice(g: NG, p):
    """Halo Skyline: a frozen moon; bright ice crossed by long double-ridged lineae, patches of
    jumbled chaos terrain and polar caps."""
    w = g.warp(p, 1.4, 0.2)
    swell = g.noise(w, 1.8, 5.0, 0.5)
    lines = None
    grooves = None
    # Lineae: long, thin arcs of great circles in some thirty directions, each present only along part of its
    # length, slightly wavy; a groove between two raised ridges.
    pw = g.warp(p, 2.2, 0.025, 1.0)
    rng = np.random.default_rng(404)
    for i in range(34):
        ax = rng.normal(size=3)
        ax /= np.linalg.norm(ax)
        d = g.ab(g.vmath("DOT_PRODUCT", pw, tuple(float(x) for x in ax)))
        off = tuple(float(x) for x in rng.uniform(-9.0, 9.0, 3))
        seg = g.smooth(0.44, 0.56, g.noise(g.vmath("ADD", p, off), 1.3, 1.0, 0.5))
        wd = 0.0042 + 0.0026 * (i % 3)
        amt = g.mul(seg, 1.0 if i < 10 else 0.6)
        ln = g.mul(g.sub(1.0, g.smooth(0.0, wd, d)), amt)
        rg = g.mul(g.sub(g.gauss(g.sub(d, wd * 1.7), wd), g.mul(g.gauss(d, wd * 0.6), 0.9)), amt)
        lines = ln if lines is None else g.mx(lines, ln)
        grooves = rg if grooves is None else g.add(grooves, rg)
    chaos = g.mul(g.smooth(0.55, 0.64, g.noise(g.warp(p, 2.0, 0.2), 2.6, 3.0, 0.5)), g.noise(p, 34.0, 4.0, 0.7))
    lat = g.ab(g.math("ARCSINE", g.vmath("DOT_PRODUCT", p, (0.0, 0.0, 1.0))))
    cap = g.smooth(0.95, 1.2, g.add(lat, g.mul(g.sub(swell, 0.5), 0.8)))
    h = g.add(g.mul(swell, 0.4), g.mul(grooves, 0.045))
    h = g.add(h, g.mul(chaos, 0.12))
    h = g.add(h, g.mul(cap, 0.1))
    h = g.add(h, g.mul(g.sub(g.noise(p, 70.0, 4.0, 0.55), 0.5), 0.03))
    alb = g.add(0.74, g.mul(g.sub(swell, 0.5), 0.2))
    alb = g.sub(alb, g.mul(lines, 0.24))
    alb = g.sub(alb, g.mul(chaos, 0.3))
    alb = g.add(alb, g.mul(cap, 0.14))
    alb = g.add(alb, g.mul(g.sub(g.noise(p, 24.0, 3.0, 0.6), 0.5), 0.08))
    return h, alb, g.sat(lines)


def w_lava(g: NG, p):
    """Neon Inferno: black basalt crust over molten seams, lava channels, a few calderas."""
    w = g.warp(p, 1.5, 0.22)
    base = g.noise(w, 2.2, 6.0, 0.55)
    vol = g.voronoi(g.warp(p, 2.0, 0.08), 2.6, "F1")
    vd = vol.outputs["Distance"]
    vr = g.sep(vol.outputs["Color"])[0]
    on = g.gt(vr, 0.55)
    cone = g.mul(g.pw(g.sat(g.sub(1.0, g.div(vd, 0.42))), 1.6), on)
    cald = g.mul(g.sat(g.sub(1.0, g.div(vd, 0.09))), on)
    e = g.voronoi(g.warp(p, 6.0, 0.06), 9.0, "DISTANCE_TO_EDGE").outputs["Distance"]
    seam = g.sub(1.0, g.smooth(0.0, 0.05, e))
    e2 = g.voronoi(g.warp(p, 14.0, 0.03), 24.0, "DISTANCE_TO_EDGE").outputs["Distance"]
    seam2 = g.sub(1.0, g.smooth(0.0, 0.06, e2))
    chan = g.ridge(g.warp(p, 2.5, 0.2), 3.0, 3.0, 0.5, 6.0)
    low = g.sub(1.0, g.smooth(0.35, 0.55, base))
    h = g.add(g.mul(base, 0.4), g.mul(cone, 0.55))
    h = g.sub(h, g.mul(cald, 0.25))
    h = g.sub(h, g.mul(seam, 0.05))
    h = g.sub(h, g.mul(g.mul(chan, low), 0.12))
    h = g.add(h, g.mul(g.sub(g.noise(p, 80.0, 4.0, 0.6), 0.5), 0.05))
    alb = g.add(0.14, g.mul(g.noise(p, 12.0, 4.0, 0.6), 0.12))
    alb = g.add(alb, g.mul(cone, 0.1))
    lava = g.mx(g.mul(seam, g.add(0.35, g.mul(low, 0.65))), g.mul(g.mul(chan, low), 0.9))
    lava = g.mx(lava, cald)
    lava = g.mx(lava, g.mul(g.mul(seam2, low), 0.45))
    return h, alb, g.sat(lava)


def w_crystal(g: NG, p):
    """Starfall Requiem: plains of dust broken by fields of faceted crystal shards."""
    w = g.warp(p, 1.3, 0.2)
    field = g.smooth(0.42, 0.53, g.noise(w, 1.6, 5.0, 0.55))
    plain = g.noise(p, 4.0, 6.0, 0.55)
    # Crystal fields: a mosaic of flat facets at random heights (two sizes of Voronoi cells, each
    # cell its own height and sheen), broken by four-pointed star shards.
    v1 = g.voronoi(g.warp(p, 4.0, 0.02), 7.0, "F1")
    c1r, c1g, _ = g.sep(v1.outputs["Color"])
    v2 = g.voronoi(g.warp(p, 9.0, 0.01), 17.0, "F1")
    c2r, c2g, _ = g.sep(v2.outputs["Color"])
    facet = g.add(g.mul(c1r, 0.6), g.mul(c2r, 0.4))
    sheen = g.add(g.mul(c1g, 0.5), g.mul(c2g, 0.5))
    v3 = g.voronoi(g.warp(p, 6.0, 0.03), 11.0, "F1", "MINKOWSKI", 1.0)
    g._set(v3.inputs["Exponent"], 0.6)
    hr = g.sep(v3.outputs["Color"])[1]
    spike = g.mul(g.pw(g.sat(g.sub(1.0, g.mul(v3.outputs["Distance"], 0.85))), 1.6), g.mul(g.add(0.3, hr), 0.38))
    h = g.add(g.mul(plain, 0.2), g.mul(field, g.add(g.mul(facet, 0.3), spike)))
    h = g.add(h, g.mul(g.sub(g.noise(p, 110.0, 3.0, 0.6), 0.5), 0.02))
    alb = g.add(0.2, g.mul(plain, 0.08))
    alb = g.add(alb, g.mul(field, g.add(0.3, g.add(g.mul(sheen, 0.42), g.mul(spike, 0.5)))))
    alb = g.add(alb, g.mul(g.sub(g.noise(p, 16.0, 3.0, 0.6), 0.5), 0.08))
    glint = g.mul(field, g.mx(g.smooth(0.82, 0.95, c2g), g.smooth(0.5, 0.9, g.div(spike, 0.4))))
    return h, alb, glint


RECIPES = {1: w_highland, 2: w_canyons, 3: w_craters, 4: w_ice, 5: w_lava, 6: w_crystal}


def bake_world(n: int, out: str, res: int) -> None:
    t0 = time.time()
    ob = bpy.data.objects.get("world")
    m = bpy.data.materials.new("w%d" % n)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    g = NG(nt)
    tc = nt.nodes.new("ShaderNodeTexCoord")
    p = g.vmath("NORMALIZE", tc.outputs["Object"])
    h, a, k = RECIPES[n](g, p)
    em = nt.nodes.new("ShaderNodeEmission")
    o = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(em.outputs[0], o.inputs["Surface"])
    tex = nt.nodes.new("ShaderNodeTexImage")
    ob.data.materials.clear()
    ob.data.materials.append(m)
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)
    for tag, sock, w in (("h", h, res * 2), ("a", a, res), ("m", k, res)):
        hh = w // 2
        img = bpy.data.images.new("w%d_%s" % (n, tag), w, hh, alpha=False, float_buffer=True, is_data=True)
        img.colorspace_settings.name = "Non-Color"
        tex.image = img
        nt.nodes.active = tex
        nt.links.new(sock, em.inputs["Color"])
        bpy.ops.object.bake(type="EMIT", margin=2, use_clear=True)
        buf = np.empty(w * hh * 4, dtype=np.float32)
        img.pixels.foreach_get(buf)
        arr = buf.reshape(hh, w, 4)[::-1, :, 0].copy()
        np.save(os.path.join(out, "w%d_%s.npy" % (n, tag)), arr)
        print("w%d %s %dx%d  min %.3f max %.3f  (%.1fs)" % (n, tag, w, hh, float(arr.min()), float(arr.max()), time.time() - t0), flush=True)
        bpy.data.images.remove(img)


def beauty_world(n: int, maps: str, out: str) -> None:
    """The finished maps on a truly displaced sphere, lit like the dossier (a check, not shipped)."""
    sc = bpy.context.scene
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o)
    ob = uv_sphere(1024, 512)
    img = bpy.data.images.load(os.path.join(maps, "w%d_albedo.jpg" % n))
    himg = bpy.data.images.load(os.path.join(maps, "w%d_height.png" % n))
    himg.colorspace_settings.name = "Non-Color"
    tx = bpy.data.textures.new("h", "IMAGE")
    tx.image = himg
    tx.extension = "REPEAT"
    md = ob.modifiers.new("disp", "DISPLACE")
    md.texture = tx
    md.texture_coords = "UV"
    md.uv_layer = "UV"
    md.strength = 0.06
    md.mid_level = 0.5
    m = bpy.data.materials.new("b%d" % n)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    t = m.node_tree.nodes.new("ShaderNodeTexImage")
    t.image = img
    m.node_tree.links.new(t.outputs["Color"], b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = 0.85
    ob.data.materials.append(m)
    bpy.ops.object.light_add(type="SUN", location=(0, 0, 5))
    sun = bpy.context.object
    sun.data.energy = 3.2
    sun.data.angle = math.radians(6)
    sun.rotation_euler = (math.radians(55), 0, math.radians(-125))
    w = bpy.data.worlds.new("w")
    sc.world = w
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.35
    bpy.ops.object.camera_add(location=(0, -10, 0), rotation=(math.radians(90), 0, 0))
    cam = bpy.context.object
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = 2.3
    sc.camera = cam
    sc.render.resolution_x = 1024
    sc.render.resolution_y = 1024
    sc.render.film_transparent = True
    sc.cycles.use_denoising = True
    sc.view_settings.view_transform = "Standard"
    sc.render.filepath = os.path.join(out, "w%d_beauty.png" % n)
    bpy.ops.render.render(write_still=True)


if MODE == "bake":
    OUT = argv[1]
    which = [1, 2, 3, 4, 5, 6] if len(argv) < 3 or argv[2] == "all" else [int(x) for x in argv[2].split(",")]
    RES = int(argv[3]) if len(argv) > 3 else 2048
    DEV = argv[4] if len(argv) > 4 else "gpu"
    os.makedirs(OUT, exist_ok=True)
    setup(DEV, 2)
    uv_sphere(1024, 512)
    for n in which:
        bake_world(n, OUT, RES)
elif MODE == "beauty":
    MAPS, OUT = argv[1], argv[2]
    which = [1, 2, 3, 4, 5, 6] if len(argv) < 4 or argv[3] == "all" else [int(x) for x in argv[3].split(",")]
    DEV = argv[4] if len(argv) > 4 else "gpu"
    os.makedirs(OUT, exist_ok=True)
    setup(DEV, 64)
    for n in which:
        beauty_world(n, MAPS, OUT)
else:
    print("unknown mode", MODE)
