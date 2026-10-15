"""HaloRig SVG authoring kit: small helpers for drawing rig-ready hero SVGs in code.

Used by tools/art_hero_<id>.py generators. Everything emitted is ThorVG-safe SVG
(paths, groups, fill/stroke/opacity, linear/radial gradients, clipPath only).
See docs/dev/art-style.md for the recipes these helpers implement.

Coordinates are SVG canvas units (viewBox 0 0 1024 1280, y down).
"""
import math

OUTLINE = "#2a1d3d"   # silhouette line colour (contract)


def f(v):
    """Compact number formatting (1 decimal, no trailing zeros)."""
    s = "%.1f" % v
    if s.endswith(".0"):
        s = s[:-2]
    if s == "-0":
        s = "0"
    return s


# ----------------------------------------------------------------- geometry

def _pt(p):
    return (float(p[0]), float(p[1]))


def _is_corner(p):
    return len(p) > 2 and p[2] in (0, "c", "corner")


def smooth(pts, closed=True, k=1.0):
    """Catmull-Rom spline through points -> SVG path data (cubic beziers).

    A point is (x, y) for a smooth point or (x, y, 'c') for a sharp corner.
    k scales tangents (1 = standard Catmull-Rom, <1 tighter, >1 rounder)."""
    n = len(pts)
    if n < 2:
        return ""
    P = [_pt(p) for p in pts]
    C = [_is_corner(p) for p in pts]
    out = ["M%s %s" % (f(P[0][0]), f(P[0][1]))]
    segs = n if closed else n - 1
    for i in range(segs):
        i0 = (i - 1) % n if closed else max(i - 1, 0)
        i1 = i
        i2 = (i + 1) % n
        i3 = (i + 2) % n if closed else min(i + 2, n - 1)
        p0, p1, p2, p3 = P[i0], P[i1], P[i2], P[i3]
        if C[i1] or (not closed and i1 == 0):
            b1 = (p1[0] + (p2[0] - p1[0]) * 0.3, p1[1] + (p2[1] - p1[1]) * 0.3)
        else:
            b1 = (p1[0] + (p2[0] - p0[0]) * k / 6.0, p1[1] + (p2[1] - p0[1]) * k / 6.0)
        if C[i2] or (not closed and i2 == n - 1):
            b2 = (p2[0] - (p2[0] - p1[0]) * 0.3, p2[1] - (p2[1] - p1[1]) * 0.3)
        else:
            b2 = (p2[0] - (p3[0] - p1[0]) * k / 6.0, p2[1] - (p3[1] - p1[1]) * k / 6.0)
        out.append("C%s %s %s %s %s %s" % (f(b1[0]), f(b1[1]), f(b2[0]), f(b2[1]), f(p2[0]), f(p2[1])))
    if closed:
        out.append("Z")
    return "".join(out)


def sample(pts, closed=False, k=1.0, per_seg=10):
    """Points sampled along the same Catmull-Rom curve smooth() draws."""
    n = len(pts)
    P = [_pt(p) for p in pts]
    C = [_is_corner(p) for p in pts]
    res = []
    segs = n if closed else n - 1
    for i in range(segs):
        i0 = (i - 1) % n if closed else max(i - 1, 0)
        i2 = (i + 1) % n
        i3 = (i + 2) % n if closed else min(i + 2, n - 1)
        p0, p1, p2, p3 = P[i0], P[i], P[i2], P[i3]
        if C[i] or (not closed and i == 0):
            b1 = (p1[0] + (p2[0] - p1[0]) * 0.3, p1[1] + (p2[1] - p1[1]) * 0.3)
        else:
            b1 = (p1[0] + (p2[0] - p0[0]) * k / 6.0, p1[1] + (p2[1] - p0[1]) * k / 6.0)
        if C[i2] or (not closed and i2 == n - 1):
            b2 = (p2[0] - (p2[0] - p1[0]) * 0.3, p2[1] - (p2[1] - p1[1]) * 0.3)
        else:
            b2 = (p2[0] - (p3[0] - p1[0]) * k / 6.0, p2[1] - (p3[1] - p1[1]) * k / 6.0)
        for s in range(per_seg):
            t = s / float(per_seg)
            u = 1 - t
            x = u * u * u * p1[0] + 3 * u * u * t * b1[0] + 3 * u * t * t * b2[0] + t * t * t * p2[0]
            y = u * u * u * p1[1] + 3 * u * u * t * b1[1] + 3 * u * t * t * b2[1] + t * t * t * p2[1]
            res.append((x, y))
    if not closed:
        res.append(P[-1])
    return res


def poly(pts, closed=True):
    s = "M" + " L".join("%s %s" % (f(p[0]), f(p[1])) for p in pts)
    return s + ("Z" if closed else "")


def taper(pts, w, profile="both", k=1.0, per_seg=8, w_min=0.0, power=0.8):
    """Filled, tapered brush stroke along a smooth centerline (varied line weight).

    profile: 'both' thin-thick-thin, 'start' thick->thin, 'end' thin->thick,
    'flat' constant. Returns path data for a filled shape."""
    c = sample(pts, closed=False, k=k, per_seg=per_seg)
    n = len(c)
    if n < 2:
        return ""
    # cumulative length for an even width profile
    L = [0.0]
    for i in range(1, n):
        L.append(L[-1] + math.hypot(c[i][0] - c[i - 1][0], c[i][1] - c[i - 1][1]))
    total = L[-1] or 1.0
    left, right = [], []
    for i in range(n):
        t = L[i] / total
        if profile == "both":
            ww = math.sin(math.pi * t) ** power
        elif profile == "start":
            ww = (1 - t) ** power
        elif profile == "end":
            ww = t ** power
        else:
            ww = 1.0
        hw = max(w_min, w * ww) * 0.5
        a = c[max(i - 1, 0)]
        b = c[min(i + 1, n - 1)]
        dx, dy = b[0] - a[0], b[1] - a[1]
        ln = math.hypot(dx, dy) or 1.0
        nx, ny = -dy / ln, dx / ln
        left.append((c[i][0] + nx * hw, c[i][1] + ny * hw))
        right.append((c[i][0] - nx * hw, c[i][1] - ny * hw))
    ring = left + right[::-1]
    return poly(ring)


def ellipse_pts(cx, cy, rx, ry, n=12, rot=0.0, start=0.0):
    out = []
    cr, sr = math.cos(math.radians(rot)), math.sin(math.radians(rot))
    for i in range(n):
        a = math.radians(start) + 2 * math.pi * i / n
        x, y = rx * math.cos(a), ry * math.sin(a)
        out.append((cx + x * cr - y * sr, cy + x * sr + y * cr))
    return out


def ellipse_d(cx, cy, rx, ry, rot=0.0):
    return smooth(ellipse_pts(cx, cy, rx, ry, 8, rot), True, 1.08)


def mirror(pts, cx=512.0):
    """Mirror points across x = cx (keeps corner flags)."""
    out = []
    for p in pts:
        q = (2 * cx - p[0], p[1]) + tuple(p[2:])
        out.append(q)
    return out


def xf(pts, dx=0.0, dy=0.0, sx=1.0, sy=1.0, rot=0.0, ox=0.0, oy=0.0):
    """Scale/rotate about (ox, oy) then translate. Keeps corner flags."""
    cr, sr = math.cos(math.radians(rot)), math.sin(math.radians(rot))
    out = []
    for p in pts:
        x, y = (p[0] - ox) * sx, (p[1] - oy) * sy
        x, y = x * cr - y * sr, x * sr + y * cr
        out.append((x + ox + dx, y + oy + dy) + tuple(p[2:]))
    return out


def lerp(a, b, t):
    return a + (b - a) * t


def lerp_pt(a, b, t):
    return (lerp(a[0], b[0], t), lerp(a[1], b[1], t))


# ------------------------------------------------------------------ document

class Doc:
    """Collects <defs> (gradients, clip paths) and top-level rig parts."""

    def __init__(self, w=1024, h=1280):
        self.w, self.h = w, h
        self.defs = []
        self.parts = []
        self._n = 0
        self._grad_cache = {}

    def uid(self, prefix):
        self._n += 1
        return "%s%d" % (prefix, self._n)

    def clip(self, d):
        cid = self.uid("c")
        self.defs.append('<clipPath id="%s"><path d="%s"/></clipPath>' % (cid, d))
        return cid

    def _stops(self, stops):
        out = []
        for s in stops:
            off, col = s[0], s[1]
            op = s[2] if len(s) > 2 else 1.0
            extra = ' stop-opacity="%s"' % f(op * 100 / 100.0) if op < 1.0 else ""
            if op < 1.0:
                extra = ' stop-opacity="%.2f"' % op
            out.append('<stop offset="%.3f" stop-color="%s"%s/>' % (off, col, extra))
        return "".join(out)

    def linear(self, stops, x1, y1, x2, y2):
        key = ("L", tuple(tuple(s) for s in stops), round(x1), round(y1), round(x2), round(y2))
        if key in self._grad_cache:
            return "url(#%s)" % self._grad_cache[key]
        gid = self.uid("g")
        self.defs.append('<linearGradient id="%s" gradientUnits="userSpaceOnUse" x1="%s" y1="%s" x2="%s" y2="%s">%s</linearGradient>'
                         % (gid, f(x1), f(y1), f(x2), f(y2), self._stops(stops)))
        self._grad_cache[key] = gid
        return "url(#%s)" % gid

    def radial(self, stops, cx, cy, r, sx=1.0, sy=1.0, rot=0.0):
        key = ("R", tuple(tuple(s) for s in stops), round(cx), round(cy), round(r), sx, sy, rot)
        if key in self._grad_cache:
            return "url(#%s)" % self._grad_cache[key]
        gid = self.uid("g")
        tr = ""
        if sx != 1.0 or sy != 1.0 or rot != 0.0:
            tr = ' gradientTransform="translate(%s %s) rotate(%s) scale(%s %s) translate(%s %s)"' % (
                f(cx), f(cy), f(rot), "%.3f" % sx, "%.3f" % sy, f(-cx), f(-cy))
        self.defs.append('<radialGradient id="%s" gradientUnits="userSpaceOnUse" cx="%s" cy="%s" r="%s"%s>%s</radialGradient>'
                         % (gid, f(cx), f(cy), f(r), tr, self._stops(stops)))
        self._grad_cache[key] = gid
        return "url(#%s)" % gid

    def part(self, pid, body, **meta):
        """Add a top-level rig part. meta keys become data-* attributes
        (underscores -> dashes), e.g. bone='head', parent='neck', pivot=(512,560), z=400."""
        attrs = ['id="%s"' % pid]
        for k, v in meta.items():
            if v is None:
                continue
            if isinstance(v, tuple):
                v = ",".join(f(x) for x in v)
            attrs.append('data-%s="%s"' % (k.replace("_", "-"), v))
        self.parts.append("<g %s>%s</g>" % (" ".join(attrs), body))

    def svg(self, extra_root_attrs=""):
        return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %d %d" width="%d" height="%d"%s>\n<defs>\n%s\n</defs>\n%s\n</svg>\n'
                % (self.w, self.h, self.w, self.h, extra_root_attrs, "\n".join(self.defs), "\n".join(self.parts)))


# ------------------------------------------------------------------ drawing

def path(d, fill="none", stroke=None, sw=None, op=None, cap=None, join="round", extra=""):
    a = ['d="%s"' % d, 'fill="%s"' % fill]
    if stroke:
        a.append('stroke="%s"' % stroke)
        a.append('stroke-width="%s"' % f(sw if sw is not None else 4))
        a.append('stroke-linejoin="%s"' % join)
        if cap:
            a.append('stroke-linecap="%s"' % cap)
    if op is not None and op < 1.0:
        a.append('opacity="%.2f"' % op)
    if extra:
        a.append(extra)
    return "<path %s/>" % " ".join(a)


def group(body, op=None, clip=None, transform=None):
    a = []
    if op is not None and op < 1.0:
        a.append('opacity="%.2f"' % op)
    if clip:
        a.append('clip-path="url(#%s)"' % clip)
    if transform:
        a.append('transform="%s"' % transform)
    return "<g %s>%s</g>" % (" ".join(a), body) if a else body


def shape(doc, d, fill, shades=(), lines=(), outline=OUTLINE, lw=5.0, clip_extra=None):
    """Cel-shaded shape: base fill, then shade/highlight layers clipped to the base,
    then the silhouette outline on top, then interior detail lines (unclipped).

    shades: list of (path_d, fill[, opacity]) drawn inside the shape.
    lines: list of raw SVG strings (e.g. tapered strokes) drawn after the outline."""
    out = [path(d, fill)]
    if shades:
        cid = doc.clip(d)
        inner = "".join(path(s[0], s[1], op=(s[2] if len(s) > 2 else None)) for s in shades)
        out.append(group(inner, clip=cid))
    if lw and outline:
        out.append(path(d, "none", outline, lw))
    out.extend(lines)
    return "".join(out)


def ink(d, color=OUTLINE, op=None):
    """A filled ink mark (use with taper())."""
    return path(d, color, op=op)


def line(d, color=OUTLINE, w=3.0, op=None, cap="round"):
    return path(d, "none", color, w, op=op, cap=cap)
