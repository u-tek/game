#!/usr/bin/env python3
"""Generates the UI icon set (assets/art/ui/*.svg) for Halo & Horn.

    python3 assets/art/ui/src/make_icons.py      (then: tools/gd --headless --path . --import)

ThorVG-safe: paths/shapes, linear/radial gradients, opacity, transforms. No filters/text.
Icons are drawn on a 64-unit grid and rasterized at 128 px (width/height attributes); the
.import files enable mipmaps so they stay crisp at 28-66 px. New icons need
mipmaps/generate=true in their .import after the first import.
Note: a gradient on a perfectly horizontal/vertical stroke has a zero-size bounding box
and renders nothing in ThorVG; use a solid color there."""
import math, os, sys

OUT_DIR = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OL = "#2a1d3d"  # outline
SW = 3          # outline width in 64-unit space


def f(v):
    s = ("%.2f" % v).rstrip("0").rstrip(".")
    return s if s != "-0" else "0"


def pts(points):
    return " ".join("%s,%s" % (f(x), f(y)) for x, y in points)


def lin(gid, stops, x1=0, y1=0, x2=0, y2=1):
    s = "".join('<stop offset="%s" stop-color="%s"%s/>' % (
        f(o), c, (' stop-opacity="%s"' % f(a)) if a is not None else "") for o, c, a in [(st + (None,))[:3] for st in stops])
    return '<linearGradient id="%s" x1="%s" y1="%s" x2="%s" y2="%s">%s</linearGradient>' % (gid, f(x1), f(y1), f(x2), f(y2), s)


def rad(gid, stops, cx=0.5, cy=0.5, r=0.5, fx=None, fy=None):
    s = "".join('<stop offset="%s" stop-color="%s"%s/>' % (
        f(o), c, (' stop-opacity="%s"' % f(a)) if a is not None else "") for o, c, a in [(st + (None,))[:3] for st in stops])
    extra = ""
    if fx is not None:
        extra = ' fx="%s" fy="%s"' % (f(fx), f(fy))
    return '<radialGradient id="%s" cx="%s" cy="%s" r="%s"%s>%s</radialGradient>' % (gid, f(cx), f(cy), f(r), extra, s)


def svg(body, defs="", w=128, h=128, vw=64, vh=64):
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">'
            '<defs>%s</defs>%s</svg>\n') % (w, h, vw, vh, defs, body)


def star_pts(cx, cy, R, r, n=5, rot=-90):
    out = []
    for i in range(n * 2):
        a = math.radians(rot + i * 180.0 / n)
        rr = R if i % 2 == 0 else r
        out.append((cx + rr * math.cos(a), cy + rr * math.sin(a)))
    return out


def sparkle(cx, cy, R, fill="#fffbe8", outline=True):
    p = star_pts(cx, cy, R, R * 0.28, 4, -90)
    s = ""
    if outline:
        s += '<polygon points="%s" fill="%s" stroke="%s" stroke-width="1.6" stroke-linejoin="round"/>' % (pts(p), fill, OL)
    else:
        s += '<polygon points="%s" fill="%s"/>' % (pts(p), fill)
    return s


def stroke2(d, w_out=13, w_in=8, col="url(#g)", cap="round"):
    """Outlined thick stroke: dark wide stroke under a colored one."""
    return ('<path d="%s" fill="none" stroke="%s" stroke-width="%s" stroke-linecap="%s" stroke-linejoin="round"/>'
            '<path d="%s" fill="none" stroke="%s" stroke-width="%s" stroke-linecap="%s" stroke-linejoin="round"/>') % (
        d, OL, f(w_out), cap, d, col, f(w_in), cap)


def shape(tag, attrs, fill, sw=SW, extra=""):
    return '<%s %s fill="%s" stroke="%s" stroke-width="%s" stroke-linejoin="round"%s/>' % (tag, attrs, fill, OL, f(sw), extra)


GOLD = lin("gold", [(0, "#fff4c0"), (0.45, "#f8cd55"), (1, "#c7841b")])
GOLD_R = lin("goldr", [(0, "#d49524"), (1, "#ffe9a0")])
CREAM = lin("g", [(0, "#ffffff"), (0.55, "#f3ecdf"), (1, "#c4b8e0")])
SILVER = lin("silver", [(0, "#ffffff"), (0.5, "#d9d2ee"), (1, "#8f84b8")])

icons = {}

# ---------------------------------------------------------------- currencies
icons["gold"] = svg(
    shape("circle", 'cx="41" cy="24" r="17"', "url(#gold)") +
    '<circle cx="41" cy="24" r="11.5" fill="none" stroke="#b97a18" stroke-width="2"/>' +
    shape("circle", 'cx="26" cy="39" r="21"', "url(#gold)") +
    shape("circle", 'cx="26" cy="39" r="15"', "url(#goldr)", 2, ' stroke-opacity="0.0"') +
    '<circle cx="26" cy="39" r="15" fill="none" stroke="#b97a18" stroke-width="2"/>' +
    '<polygon points="%s" fill="#fff6cc" stroke="#a86a12" stroke-width="1.6" stroke-linejoin="round"/>' % pts(star_pts(26, 39.5, 8.5, 3.8)) +
    '<path d="M11 34 A16 16 0 0 1 20 22" fill="none" stroke="#ffffff" stroke-width="3" stroke-linecap="round" opacity="0.75"/>' +
    '<path d="M29 18 A12 12 0 0 1 36 10" fill="none" stroke="#ffffff" stroke-width="2.5" stroke-linecap="round" opacity="0.7"/>' +
    sparkle(52, 44, 6),
    GOLD + GOLD_R)

icons["gems"] = svg(
    '<polygon points="10,24 26,24 32,57" fill="#3c9be3"/>'
    '<polygon points="26,24 38,24 32,57" fill="#66c2f2"/>'
    '<polygon points="38,24 54,24 32,57" fill="#2a66c0"/>'
    '<polygon points="10,24 20,10 26,24" fill="#a6e9ff"/>'
    '<polygon points="20,10 44,10 38,24 26,24" fill="#e2f9ff"/>'
    '<polygon points="44,10 54,24 38,24" fill="#74cdf2"/>'
    '<path d="M10 24 H54 M26 24 L32 57 M38 24 L32 57 M20 10 L26 24 M44 10 L38 24" fill="none" stroke="#ffffff" stroke-opacity="0.55" stroke-width="1.2"/>'
    '<polygon points="10,24 20,10 44,10 54,24 32,57" fill="none" stroke="%s" stroke-width="3" stroke-linejoin="round"/>' % OL +
    '<path d="M24 14 L29 14" stroke="#ffffff" stroke-width="2.5" stroke-linecap="round"/>' +
    sparkle(50, 9, 7) + sparkle(13, 44, 4.5))

icons["scrolls"] = svg(
    '<g transform="rotate(-24 32 32)">' +
    shape("rect", 'x="15" y="20" width="34" height="24"', "url(#paper)") +
    '<path d="M19 27 H45 M19 32 H45 M19 37 H40" stroke="#a7834a" stroke-width="1.6" stroke-linecap="round" opacity="0.7"/>' +
    shape("rect", 'x="5" y="16" width="12" height="32" rx="6"', "url(#roll)") +
    shape("rect", 'x="47" y="16" width="12" height="32" rx="6"', "url(#roll)") +
    '<ellipse cx="11" cy="16.5" rx="4" ry="1.6" fill="#7a4a1c"/>' +
    '<ellipse cx="53" cy="16.5" rx="4" ry="1.6" fill="#7a4a1c"/>' +
    shape("rect", 'x="27" y="19" width="10" height="26"', "#8e6ce0", 2.2) +
    shape("circle", 'cx="32" cy="32" r="8.5"', "url(#seal)", 2.5) +
    '<polygon points="%s" fill="#ffe08a"/>' % pts(star_pts(32, 32.5, 5, 2.2)) +
    '</g>' + sparkle(54, 10, 6),
    lin("paper", [(0, "#fff6dc"), (1, "#e2c48e")]) +
    lin("roll", [(0, "#f3dcae"), (0.5, "#d6b077"), (1, "#a67b44")], 0, 0, 1, 0) +
    rad("seal", [(0, "#d7c3ff"), (0.6, "#8e6ce0"), (1, "#5a3ba8")], 0.4, 0.35, 0.7))

icons["hero_exp"] = svg(
    shape("rect", 'x="25" y="3" width="14" height="8" rx="2"', "url(#cork)", 2.5) +
    shape("rect", 'x="27" y="10" width="10" height="13"', "url(#glass)", 2.5) +
    shape("circle", 'cx="32" cy="40" r="19"', "url(#glass)") +
    '<path d="M14.2 40 Q23 34 32 39 Q41 44 49.8 38 A18 18 0 0 1 14.2 40 Z" fill="url(#liq)"/>' +
    '<circle cx="32" cy="40" r="19" fill="none" stroke="%s" stroke-width="3"/>' % OL +
    '<circle cx="26" cy="47" r="2.2" fill="#e9fff4" opacity="0.9"/><circle cx="36" cy="51" r="1.6" fill="#e9fff4" opacity="0.8"/>'
    '<circle cx="39" cy="44" r="1.2" fill="#e9fff4" opacity="0.8"/>'
    '<path d="M19 34 A14 14 0 0 1 27 25" fill="none" stroke="#ffffff" stroke-width="3" stroke-linecap="round" opacity="0.8"/>' +
    sparkle(52, 16, 6, "#d8ffe9"),
    lin("cork", [(0, "#d9a26a"), (1, "#8a5428")]) +
    lin("glass", [(0, "#e9e2ff"), (1, "#8a7fb8")]) +
    lin("liq", [(0, "#c8ffe2"), (0.4, "#5cd6a0"), (1, "#1c8c62")]))

icons["dust"] = svg(
    shape("path", 'd="M5 52 Q9 40 20 37 Q24 26 33 28 Q40 22 46 31 Q56 35 59 52 Z"', "url(#heap)") +
    '<path d="M14 44 Q22 38 30 40" fill="none" stroke="#ffffff" stroke-width="2.4" stroke-linecap="round" opacity="0.6"/>'
    '<circle cx="24" cy="46" r="1.6" fill="#fff"/><circle cx="38" cy="42" r="1.3" fill="#fff"/>'
    '<circle cx="45" cy="47" r="1.6" fill="#fff"/><circle cx="31" cy="34" r="1.2" fill="#fff"/>'
    '<circle cx="17" cy="50" r="1.1" fill="#fff"/>' +
    sparkle(20, 18, 7.5, "#fff4d6") + sparkle(44, 12, 6, "#f3dcff") + sparkle(54, 26, 4, "#fff4d6"),
    lin("heap", [(0, "#f6dcff"), (0.45, "#c08af0"), (1, "#6b3fc2")]))

icons["shard"] = svg(
    shape("polygon", 'points="31,3 45,19 41,50 28,61 19,41 21,17"', "#e0609c") +
    '<polygon points="31,3 21,17 19,41 28,61 32,30" fill="url(#sl)"/>'
    '<polygon points="31,3 45,19 41,50 28,61 32,30" fill="url(#sr)"/>'
    '<path d="M31 3 L32 30 L28 61" fill="none" stroke="#ffffff" stroke-opacity="0.6" stroke-width="1.3"/>'
    '<polygon points="31,3 45,19 41,50 28,61 19,41 21,17" fill="none" stroke="%s" stroke-width="3" stroke-linejoin="round"/>' % OL +
    '<path d="M25 18 L23 34" stroke="#ffffff" stroke-width="2.5" stroke-linecap="round" opacity="0.85"/>' +
    sparkle(50, 9, 6.5) + sparkle(12, 52, 4),
    lin("sl", [(0, "#fff0f7"), (1, "#f2a6c9")]) + lin("sr", [(0, "#f58cbc"), (1, "#a8306c")]))

icons["power"] = svg(
    '<circle cx="32" cy="32" r="29" fill="url(#burst)"/>' +
    shape("polygon", 'points="38,3 13,36 29,36 23,61 51,25 35,25 43,3"', "url(#bolt)") +
    '<path d="M36 9 L21 31" stroke="#ffffff" stroke-width="2.5" stroke-linecap="round" opacity="0.8"/>',
    rad("burst", [(0, "#ffb347", 0.7), (0.6, "#ff7a2e", 0.25), (1, "#ff5a1e", 0.0)]) +
    lin("bolt", [(0, "#fffbd0"), (0.45, "#ffc93a"), (1, "#ef6a17")]))

STAR = star_pts(32, 34, 29, 13.5)
icons["star"] = svg(
    shape("polygon", 'points="%s"' % pts(STAR), "url(#st)", 3.2) +
    '<polygon points="%s" fill="#ffffff" opacity="0.35"/>' % pts(star_pts(28, 29, 10, 4.6)) +
    '<path d="M24 22 L28 16" stroke="#ffffff" stroke-width="2.6" stroke-linecap="round" opacity="0.9"/>',
    lin("st", [(0, "#fff6c4"), (0.5, "#f8c843"), (1, "#d38a17")]))
icons["star_empty"] = svg(
    '<polygon points="%s" fill="#1b1535" stroke="#6b5c9e" stroke-width="3.2" stroke-linejoin="round"/>' % pts(STAR) +
    '<polygon points="%s" fill="none" stroke="#2a1d3d" stroke-width="1.5" stroke-linejoin="round"/>' % pts(star_pts(32, 34, 24, 11)))

# ---------------------------------------------------------------- system glyphs (cream, tintable)
icons["back"] = svg(stroke2("M38 12 L18 32 L38 52", 15, 9), CREAM)
icons["close"] = svg(stroke2("M18 18 L46 46 M46 18 L18 46", 15, 9), CREAM)
icons["chevron_right"] = svg(stroke2("M26 12 L46 32 L26 52", 15, 9), CREAM)
icons["plus"] = svg(stroke2("M32 13 V51 M13 32 H51", 15, 9), CREAM)
icons["check"] = svg(stroke2("M13 34 L26 47 L51 19", 15, 9), CREAM)
icons["info"] = svg(
    '<circle cx="32" cy="32" r="24" fill="none" stroke="%s" stroke-width="11"/>' % OL +
    '<circle cx="32" cy="32" r="24" fill="none" stroke="url(#g)" stroke-width="5.5"/>' +
    stroke2("M32 30 V44", 12, 6.5, "#f3ecdf") + shape("circle", 'cx="32" cy="20.5" r="4.2"', "#f3ecdf", 2.5), CREAM)
icons["speed"] = svg(
    shape("polygon", 'points="8,14 31,32 8,50"', "url(#g)", 3.5) +
    shape("polygon", 'points="31,14 56,32 31,50"', "url(#g)", 3.5), CREAM)
icons["skip"] = svg(
    shape("polygon", 'points="10,13 40,32 10,51"', "url(#g)", 3.5) +
    shape("rect", 'x="43" y="13" width="9" height="38" rx="2.5"', "url(#g)", 3.5), CREAM)


def arc_arrow(cx, cy, r, a0, a1, head=7.0):
    p0 = (cx + r * math.cos(math.radians(a0)), cy + r * math.sin(math.radians(a0)))
    p1 = (cx + r * math.cos(math.radians(a1)), cy + r * math.sin(math.radians(a1)))
    large = 1 if (a1 - a0) % 360 > 180 else 0
    d = "M%s %s A%s %s 0 %d 1 %s %s" % (f(p0[0]), f(p0[1]), f(r), f(r), large, f(p1[0]), f(p1[1]))
    th = math.radians(a1)
    t = (-math.sin(th), math.cos(th))
    n = (math.cos(th), math.sin(th))
    bc = (p1[0] - t[0] * 2.5, p1[1] - t[1] * 2.5)
    tip = (p1[0] + t[0] * head, p1[1] + t[1] * head)
    b1 = (bc[0] + n[0] * head * 0.95, bc[1] + n[1] * head * 0.95)
    b2 = (bc[0] - n[0] * head * 0.95, bc[1] - n[1] * head * 0.95)
    return d, [b1, tip, b2]


d1, h1 = arc_arrow(32, 32, 20, 195, 320)
d2, h2 = arc_arrow(32, 32, 20, 15, 140)
icons["auto"] = svg(
    stroke2(d1, 12, 6.5, "url(#g)", "butt") + shape("polygon", 'points="%s"' % pts(h1), "url(#g)", 2.6) +
    stroke2(d2, 12, 6.5, "url(#g)", "butt") + shape("polygon", 'points="%s"' % pts(h2), "url(#g)", 2.6) +
    shape("polygon", 'points="27,24 40,32 27,40"', "url(#g)", 2.6), CREAM)
d3, h3 = arc_arrow(32, 33, 20, 300, 230)
icons["refresh"] = svg(stroke2(d3, 12, 6.5, "url(#g)", "butt") + shape("polygon", 'points="%s"' % pts(h3), "url(#g)", 2.6), CREAM)

# Settings cog.
def gear_path(cx, cy, R, r, teeth, tw=0.42):
    out = []
    step = 2 * math.pi / teeth
    for i in range(teeth):
        a = i * step
        half = step * tw * 0.5
        bev = step * 0.08
        for ang, rr in [(a - half - bev, r), (a - half, R), (a + half, R), (a + half + bev, r)]:
            out.append((cx + rr * math.cos(ang), cy + rr * math.sin(ang)))
    return out


icons["settings"] = svg(
    shape("polygon", 'points="%s"' % pts(gear_path(32, 32, 29, 21.5, 8)), "url(#silver)") +
    '<circle cx="32" cy="32" r="13.5" fill="none" stroke="#8a7fb4" stroke-width="2.2"/>' +
    shape("circle", 'cx="32" cy="32" r="8"', "#2f2552") +
    '<path d="M16 22 A18 18 0 0 1 26 14" fill="none" stroke="#ffffff" stroke-width="2.6" stroke-linecap="round" opacity="0.9"/>',
    SILVER)

icons["lock"] = svg(
    stroke2("M21 30 V21 A11 11 0 0 1 43 21 V30", 12, 6, "url(#silver)", "butt") +
    shape("rect", 'x="12" y="28" width="40" height="30" rx="7"', "url(#gold)") +
    '<path d="M17 34 H47" stroke="#ffffff" stroke-width="2" stroke-linecap="round" opacity="0.6"/>' +
    '<circle cx="32" cy="41" r="4.5" fill="%s"/>' % OL +
    '<path d="M32 43 V51" stroke="%s" stroke-width="4" stroke-linecap="round"/>' % OL,
    GOLD + SILVER)

# ---------------------------------------------------------------- nav icons
icons["home"] = svg(
    shape("rect", 'x="14" y="30" width="36" height="28" rx="2"', "url(#stone)") +
    shape("rect", 'x="7" y="38" width="10" height="20" rx="1.5"', "url(#stone)") +
    shape("rect", 'x="47" y="38" width="10" height="20" rx="1.5"', "url(#stone)") +
    shape("polygon", 'points="5,40 12,29 19,40"', "url(#gold)", 2.6) +
    shape("polygon", 'points="45,40 52,29 59,40"', "url(#gold)", 2.6) +
    shape("polygon", 'points="10,33 32,10 54,33"', "url(#gold)") +
    shape("path", 'd="M25 58 V46 A7 7 0 0 1 39 46 V58 Z"', "#3a2a66", 2.6) +
    shape("circle", 'cx="32" cy="25" r="4.6"', "url(#win)", 2.2) +
    '<circle cx="32" cy="6.5" r="3.6" fill="none" stroke="%s" stroke-width="4.4"/>' % OL +
    '<circle cx="32" cy="6.5" r="3.6" fill="none" stroke="#ffe08a" stroke-width="2"/>'
    '<path d="M17 18 L26 9" stroke="#fff" stroke-width="0"/>'
    '<path d="M16 31 L30 16" stroke="#ffffff" stroke-width="2.2" stroke-linecap="round" opacity="0.75"/>',
    GOLD + lin("stone", [(0, "#f4ecff"), (1, "#a497c9")]) + rad("win", [(0, "#d9f4ff"), (1, "#3f8fd6")]))

icons["heroes"] = svg(
    # demon (back, right)
    shape("path", 'd="M30 57 C30 44 37 38 46 38 C55 38 62 44 62 57 Z"', "url(#dem)") +
    shape("path", 'd="M38 17 C34 13 33 8 35 3 C37 8 40 10 43 12 Z"', "url(#horn)", 2.2) +
    shape("path", 'd="M54 17 C58 13 59 8 57 3 C55 8 52 10 49 12 Z"', "url(#horn)", 2.2) +
    shape("circle", 'cx="46" cy="25" r="11"', "url(#dem)") +
    # angel (front, left)
    shape("path", 'd="M3 61 C3 46 11 39 22 39 C33 39 41 46 41 61 Z"', "url(#ang)") +
    shape("circle", 'cx="22" cy="27" r="12"', "url(#ang)") +
    '<ellipse cx="22" cy="11" rx="10" ry="3.6" fill="none" stroke="%s" stroke-width="5"/>' % OL +
    '<ellipse cx="22" cy="11" rx="10" ry="3.6" fill="none" stroke="#ffe08a" stroke-width="2.4"/>' +
    '<path d="M14 23 A9 9 0 0 1 20 17" fill="none" stroke="#ffffff" stroke-width="2.6" stroke-linecap="round" opacity="0.9"/>' +
    '<path d="M9 52 C9 47 12 44 16 43" fill="none" stroke="#ffffff" stroke-width="2.6" stroke-linecap="round" opacity="0.8"/>',
    lin("ang", [(0, "#fffbe8"), (0.55, "#f6d784"), (1, "#c98a1e")]) +
    lin("dem", [(0, "#ff8a6a"), (0.5, "#c8321e"), (1, "#6e1408")]) +
    lin("horn", [(0, "#5a4a6a"), (1, "#1e1428")]))

icons["summon"] = svg(
    '<circle cx="32" cy="32" r="30" fill="url(#aura)"/>'
    '<g transform="rotate(-18 32 32)">'
    '<path d="M6 34 A26 9 0 0 1 58 34" fill="none" stroke="%s" stroke-width="7"/>' % OL +
    '<path d="M6 34 A26 9 0 0 1 58 34" fill="none" stroke="#f8cd55" stroke-width="3"/>'
    '</g>' +
    shape("circle", 'cx="32" cy="33" r="18"', "url(#orb)") +
    '<path d="M22 38 C24 28 36 26 40 32 C43 37 37 42 32 39" fill="none" stroke="#e7dcff" stroke-width="2.4" stroke-linecap="round" opacity="0.85"/>'
    '<path d="M21 26 A13 13 0 0 1 30 19" fill="none" stroke="#ffffff" stroke-width="3" stroke-linecap="round" opacity="0.9"/>'
    '<g transform="rotate(-18 32 32)">'
    '<path d="M58 34 A26 9 0 0 1 6 34" fill="none" stroke="%s" stroke-width="7"/>' % OL +
    '<path d="M58 34 A26 9 0 0 1 6 34" fill="none" stroke="url(#gold)" stroke-width="3"/>'
    '</g>' + sparkle(52, 9, 7) + sparkle(10, 50, 5),
    GOLD + rad("orb", [(0, "#f4eeff"), (0.35, "#b79cf5"), (0.75, "#6a45c9"), (1, "#3a2180")], 0.38, 0.3, 0.75) +
    rad("aura", [(0, "#b48cff", 0.55), (0.7, "#8e6ce0", 0.15), (1, "#8e6ce0", 0)]))

icons["quests"] = svg(
    shape("path", 'd="M14 8 H46 A3 3 0 0 1 49 11 V48 L40 57 H14 A3 3 0 0 1 11 54 V11 A3 3 0 0 1 14 8 Z"', "url(#paper)") +
    '<path d="M18 19 H42 M18 27 H42 M18 35 H34" stroke="#9a7440" stroke-width="2.6" stroke-linecap="round"/>' +
    shape("rect", 'x="22" y="4" width="16" height="8" rx="2.5"', "url(#gold)", 2.4) +
    shape("circle", 'cx="45" cy="46" r="13"', "url(#ok)") +
    '<path d="M38.5 46.5 L43.5 51 L51.5 41.5" fill="none" stroke="#ffffff" stroke-width="3.6" stroke-linecap="round" stroke-linejoin="round"/>',
    GOLD + lin("paper", [(0, "#fff7e0"), (1, "#dcc08c")]) + lin("ok", [(0, "#b6ffd8"), (0.5, "#4fcf93"), (1, "#1f8f5f")]))

icons["shop"] = svg(
    shape("path", 'd="M21 21 C7 30 7 58 32 58 C57 58 57 30 43 21 Z"', "url(#bag)") +
    shape("path", 'd="M24 21 L18 8 L28 12 L32 6 L36 12 L46 8 L40 21 Z"', "url(#bag2)", 2.6) +
    shape("rect", 'x="20" y="18" width="24" height="6" rx="3"', "url(#gold)", 2.4) +
    shape("circle", 'cx="32" cy="41" r="10"', "url(#gold)", 2.6) +
    '<polygon points="%s" fill="#fff6cc" stroke="#a86a12" stroke-width="1.3" stroke-linejoin="round"/>' % pts(star_pts(32, 41.5, 6, 2.6)) +
    '<path d="M16 38 C16 32 18 28 22 26" fill="none" stroke="#ffffff" stroke-width="2.6" stroke-linecap="round" opacity="0.6"/>' +
    sparkle(53, 13, 6),
    GOLD + lin("bag", [(0, "#c7a6ff"), (0.5, "#7d56d6"), (1, "#3f2785")]) + lin("bag2", [(0, "#d9c4ff"), (1, "#8e6ce0")]))

icons["chest"] = svg(
    shape("rect", 'x="7" y="30" width="50" height="27" rx="3"', "url(#wood)") +
    shape("path", 'd="M7 31 V24 C7 13 57 13 57 24 V31 Z"', "url(#lid)") +
    shape("rect", 'x="13" y="15" width="7" height="42"', "url(#gold)", 2.2) +
    shape("rect", 'x="44" y="15" width="7" height="42"', "url(#gold)", 2.2) +
    shape("rect", 'x="5" y="28" width="54" height="6" rx="2"', "url(#gold)", 2.4) +
    shape("rect", 'x="26" y="27" width="12" height="14" rx="2.5"', "url(#gold)", 2.4) +
    '<circle cx="32" cy="33" r="2.3" fill="%s"/>' % OL + '<path d="M32 34 V38" stroke="%s" stroke-width="2.2" stroke-linecap="round"/>' % OL +
    '<path d="M24 20 C28 18 36 18 40 20" fill="none" stroke="#ffd9a8" stroke-width="2" stroke-linecap="round" opacity="0.6"/>' +
    sparkle(55, 11, 6.5) + sparkle(8, 12, 4.5),
    GOLD + lin("wood", [(0, "#c47a3c"), (1, "#6b3416")]) + lin("lid", [(0, "#e09650"), (1, "#8f4a1e")]))

# ---------------------------------------------------------------- misc colored
SWORD = ('<g transform="rotate(45 32 32)">' +
         shape("polygon", 'points="28.5,8 32,2 35.5,8 35.5,41 28.5,41"', "url(#blade)", 2.6) +
         '<path d="M32 6 V39" stroke="#ffffff" stroke-width="1.4" opacity="0.8"/>' +
         shape("rect", 'x="21" y="40" width="22" height="6" rx="3"', "url(#gold)", 2.6) +
         shape("rect", 'x="29.5" y="46" width="5" height="11"', "#7a4a2a", 2.4) +
         shape("circle", 'cx="32" cy="59" r="3.4"', "url(#gold)", 2.4) + '</g>')
SWORD_DEFS = GOLD + lin("blade", [(0, "#ffffff"), (0.5, "#dfe6ff"), (1, "#8a92c0")], 0, 0, 1, 0)
icons["sword"] = svg(SWORD + sparkle(13, 13, 5.5), SWORD_DEFS)
icons["stat_atk"] = svg(SWORD, SWORD_DEFS)
icons["gear_weapon"] = svg(SWORD, SWORD_DEFS)

icons["gift"] = svg(
    shape("rect", 'x="11" y="28" width="42" height="29" rx="3"', "url(#box)") +
    shape("rect", 'x="8" y="20" width="48" height="10" rx="3"', "url(#lid)") +
    shape("rect", 'x="28" y="20" width="8" height="37"', "url(#gold)", 2.4) +
    shape("path", 'd="M32 20 C24 8 12 10 16 18 C18 21 26 21 32 20 Z"', "url(#gold)", 2.4) +
    shape("path", 'd="M32 20 C40 8 52 10 48 18 C46 21 38 21 32 20 Z"', "url(#gold)", 2.4),
    GOLD + lin("box", [(0, "#ff8a7a"), (1, "#b52a3a")]) + lin("lid", [(0, "#ffa494"), (1, "#d2424e")]))

icons["arrow_up"] = svg(
    shape("polygon", 'points="32,5 56,30 42,30 42,58 22,58 22,30 8,30"', "url(#up)", 3.2) +
    '<path d="M18 26 L30 13" stroke="#ffffff" stroke-width="2.6" stroke-linecap="round" opacity="0.8"/>',
    lin("up", [(0, "#d2ffe6"), (0.5, "#5cd6a0"), (1, "#1a8a5a")]))

icons["map"] = svg(
    shape("polygon", 'points="6,14 22,8 42,14 58,8 58,50 42,56 22,50 6,56"', "#e8d3a3") +
    '<polygon points="22,8 42,14 42,56 22,50" fill="#d4b67c"/>'
    '<polygon points="6,14 22,8 42,14 58,8 58,50 42,56 22,50 6,56" fill="none" stroke="%s" stroke-width="3" stroke-linejoin="round"/>' % OL +
    '<path d="M22 8 V50 M42 14 V56" stroke="%s" stroke-width="1.6" opacity="0.5"/>' % OL +
    '<path d="M12 46 C18 38 26 44 30 34 C33 27 40 30 44 24" fill="none" stroke="#b5321e" stroke-width="2.4" stroke-dasharray="3 3" stroke-linecap="round"/>' +
    stroke2("M44 17 L52 25 M52 17 L44 25", 6.5, 3.2, "#d9412b"))

icons["crown"] = svg(
    shape("polygon", 'points="7,48 6,18 19,31 32,9 45,31 58,18 57,48"', "url(#gold)") +
    shape("rect", 'x="6" y="45" width="52" height="11" rx="3"', "url(#gold)") +
    shape("circle", 'cx="32" cy="50.5" r="3.6"', "#d9412b", 2) + shape("circle", 'cx="19" cy="50.5" r="2.8"', "#4fa3e0", 2) +
    shape("circle", 'cx="45" cy="50.5" r="2.8"', "#4fa3e0", 2) +
    shape("circle", 'cx="32" cy="9" r="3.4"', "#fff4c0", 2) + shape("circle", 'cx="6" cy="18" r="3"', "#fff4c0", 2) +
    shape("circle", 'cx="58" cy="18" r="3"', "#fff4c0", 2) +
    '<path d="M14 40 L13 27" stroke="#ffffff" stroke-width="2.4" stroke-linecap="round" opacity="0.7"/>', GOLD)

# ---------------------------------------------------------------- stats
HEART = "M32 56 C26 50 7 40 7 23 C7 13 15 8 22 8 C27 8 30 11 32 14 C34 11 37 8 42 8 C49 8 57 13 57 23 C57 40 38 50 32 56 Z"
icons["stat_hp"] = svg(shape("path", 'd="%s"' % HEART, "url(#hp)") +
                       '<path d="M14 22 C14 17 17 14 21 14" fill="none" stroke="#ffffff" stroke-width="3" stroke-linecap="round" opacity="0.85"/>',
                       lin("hp", [(0, "#ff9a8a"), (0.5, "#e2413a"), (1, "#9a1c24")]))
SHIELD = "M32 4 L54 12 C54 34 46 50 32 60 C18 50 10 34 10 12 Z"
icons["stat_def"] = svg(shape("path", 'd="%s"' % SHIELD, "url(#sh)") +
                        shape("path", 'd="M32 11 L47 17 C47 33 41 44 32 51 C23 44 17 33 17 17 Z"', "url(#shin)", 2) +
                        '<path d="M22 20 L24 34" stroke="#ffffff" stroke-width="2.6" stroke-linecap="round" opacity="0.7"/>',
                        lin("sh", [(0, "#f2f6ff"), (1, "#8a94c4")]) + lin("shin", [(0, "#8fd0ff"), (1, "#2c63b8")]))
WING = ("M8 44 C10 26 26 12 52 8 C50 14 46 18 40 21 C47 21 52 20 56 18 C52 26 45 30 37 31 C43 32 48 31 52 30"
        " C46 38 36 42 26 41 C20 44 14 46 8 44 Z")
icons["stat_spd"] = svg(shape("path", 'd="%s"' % WING, "url(#wg)") +
                        '<path d="M14 38 C22 30 32 24 44 18" fill="none" stroke="#6fa9d6" stroke-width="2" stroke-linecap="round"/>'
                        '<path d="M20 40 C28 36 36 33 44 30" fill="none" stroke="#6fa9d6" stroke-width="1.8" stroke-linecap="round"/>',
                        lin("wg", [(0, "#ffffff"), (1, "#9fd2f2")]))
icons["stat_crit"] = svg(shape("polygon", 'points="%s"' % pts(star_pts(32, 32, 29, 12, 8, -90)), "url(#cr)") +
                         shape("circle", 'cx="32" cy="32" r="8"', "#fff6d8", 2.2) +
                         '<circle cx="32" cy="32" r="3" fill="#d9412b"/>',
                         lin("cr", [(0, "#ffe27a"), (0.5, "#ff8a2e"), (1, "#d63a1e")]))

# ---------------------------------------------------------------- gear
icons["gear_armor"] = svg(
    shape("path", 'd="M14 12 L24 8 C26 14 38 14 40 8 L50 12 L58 24 L50 30 L48 56 L16 56 L14 30 L6 24 Z"', "url(#silver)") +
    shape("path", 'd="M24 8 C26 14 38 14 40 8"', "url(#gold)", 2.4) +
    '<path d="M32 18 V52 M18 34 C26 38 38 38 46 34" fill="none" stroke="#8a7fb4" stroke-width="2.2" stroke-linecap="round"/>' +
    shape("circle", 'cx="32" cy="28" r="5"', "url(#gold)", 2.2), SILVER + GOLD)
icons["gear_helm"] = svg(
    shape("path", 'd="M12 44 C12 18 52 18 52 44 L52 56 L41 56 L41 44 L23 44 L23 56 L12 56 Z"', "url(#silver)") +
    shape("path", 'd="M23 44 V34 H41 V44"', "#2f2552", 2.4) +
    shape("path", 'd="M33 4 C24 8 23 18 27 26 H37 C39 18 40 10 33 4 Z"', "url(#plume)", 2.4) +
    '<path d="M18 38 C18 30 22 25 28 23" fill="none" stroke="#ffffff" stroke-width="2.6" stroke-linecap="round" opacity="0.85"/>',
    SILVER + lin("plume", [(0, "#ff8a6a"), (1, "#a61e1e")]))
icons["gear_charm"] = svg(
    '<path d="M16 8 C16 28 48 28 48 8" fill="none" stroke="%s" stroke-width="7" stroke-linecap="round"/>' % OL +
    '<path d="M16 8 C16 28 48 28 48 8" fill="none" stroke="url(#gold)" stroke-width="3" stroke-linecap="round" stroke-dasharray="4 2"/>' +
    shape("circle", 'cx="32" cy="40" r="17"', "url(#gold)") +
    shape("polygon", 'points="32,28 42,40 32,52 22,40"', "url(#gem)", 2.4) +
    '<path d="M27 37 L31 32" stroke="#ffffff" stroke-width="2" stroke-linecap="round"/>',
    GOLD + lin("gem", [(0, "#f0dcff"), (0.5, "#b36bf0"), (1, "#5b2a9a")]))

# ---------------------------------------------------------------- faction emblems
def rays(cx, cy, r0, r1, n, w, rot=0.0):
    out = ""
    for i in range(n):
        a = math.radians(rot + i * 360.0 / n)
        rr = r1 if i % 2 == 0 else r1 * 0.78
        hw = math.radians(w if i % 2 == 0 else w * 0.75)
        p = [(cx + r0 * math.cos(a - hw), cy + r0 * math.sin(a - hw)),
             (cx + rr * math.cos(a), cy + rr * math.sin(a)),
             (cx + r0 * math.cos(a + hw), cy + r0 * math.sin(a + hw))]
        out += shape("polygon", 'points="%s"' % pts(p), "url(#ray)", 2.4)
    return out


icons["faction_celestial"] = svg(
    rays(32, 33, 14, 30, 12, 11, -90) +
    shape("circle", 'cx="32" cy="33" r="15"', "url(#sun)") +
    '<ellipse cx="32" cy="33" rx="9.5" ry="9.5" fill="none" stroke="#fff8dc" stroke-width="2.4"/>' +
    '<polygon points="%s" fill="#ffffff"/>' % pts(star_pts(32, 33, 6, 2.2, 4, -90)),
    lin("ray", [(0, "#fff4c0"), (1, "#e6a22a")]) + rad("sun", [(0, "#fffbe6"), (0.5, "#ffd970"), (1, "#e09a22")], 0.45, 0.4, 0.65))

icons["faction_infernal"] = svg(
    shape("path", 'd="M20 22 C12 20 6 12 7 3 C11 10 17 12 24 13 Z"', "url(#horn)", 2.6) +
    shape("path", 'd="M44 22 C52 20 58 12 57 3 C53 10 47 12 40 13 Z"', "url(#horn)", 2.6) +
    shape("path", 'd="M32 61 C18 61 11 51 13 40 C15 31 22 27 22 18 C27 22 29 27 29 31 C31 24 35 17 33 7 C42 13 49 24 47 33 C50 31 51 28 51 25 C56 32 55 44 50 51 C46 57 40 61 32 61 Z"', "url(#flame)") +
    shape("path", 'd="M32 56 C25 56 21 51 22 45 C23 40 27 38 28 33 C31 36 32 39 32 42 C34 39 36 36 36 32 C41 37 43 43 41 48 C40 53 37 56 32 56 Z"', "url(#core)", 0) +
    '<path d="M19 42 C18 38 19 35 21 32" fill="none" stroke="#ffd2a0" stroke-width="2.4" stroke-linecap="round" opacity="0.8"/>',
    lin("flame", [(0, "#ffb347"), (0.45, "#f0561e"), (1, "#9e1a14")]) +
    lin("core", [(0, "#fff6c8"), (1, "#ffb43a")]) +
    lin("horn", [(0, "#5a4a6a"), (1, "#1e1428")], 0, 0, 1, 1))

icons["faction_fallen"] = svg(
    '<g transform="rotate(-14 32 32)">'
    '<path d="M38.5 13.6 A26 11 0 1 1 22 13.9" fill="none" stroke="%s" stroke-width="9" stroke-linecap="round"/>' % OL +
    '<path d="M38.5 13.6 A26 11 0 1 1 22 13.9" fill="none" stroke="url(#halo)" stroke-width="4.4" stroke-linecap="round"/>'
    '<path d="M22 13.9 L26.5 10.5 M38.5 13.6 L34.5 9.8" stroke="%s" stroke-width="2.4" stroke-linecap="round"/>' % OL +
    '</g>' +
    shape("path", 'd="M47 9 C36 16 26 30 21 46 C19 52 18 56 17 60 C21 56 24 52 28 48 C40 40 50 26 47 9 Z"', "url(#feather)") +
    '<path d="M45 13 C38 24 28 38 19 57" fill="none" stroke="%s" stroke-width="2.2" stroke-linecap="round"/>' % OL +
    '<path d="M38 22 L44 24 M33 30 L40 33 M29 38 L36 41 M41 18 L36 15 M35 26 L30 23 M30 34 L25 32" stroke="#5a44a0" stroke-width="1.6" stroke-linecap="round"/>' +
    sparkle(12, 18, 4.5, "#e6dbff"),
    lin("halo", [(0, "#efe6ff"), (1, "#8e6ce0")]) + lin("feather", [(0, "#e4d8ff"), (0.5, "#9a82e0"), (1, "#4b3590")], 1, 0, 0, 1))

# ---------------------------------------------------------------- role icons (silver-cream, tintable)
ROLE = lin("g", [(0, "#ffffff"), (0.5, "#ece6f8"), (1, "#a99fc4")])
icons["role_guardian"] = svg(
    shape("path", 'd="%s"' % SHIELD, "url(#g)") +
    '<path d="M32 12 V52 M17 24 H47" stroke="#8a7fb4" stroke-width="2.6" stroke-linecap="round"/>', ROLE)
icons["role_striker"] = svg(
    '<g transform="rotate(45 32 32)">' +
    shape("polygon", 'points="27.5,9 32,2 36.5,9 36.5,41 27.5,41"', "url(#g)") +
    shape("rect", 'x="19" y="40" width="26" height="6" rx="3"', "url(#g)", 2.8) +
    shape("rect", 'x="29" y="46" width="6" height="11"', "url(#g)", 2.6) +
    shape("circle", 'cx="32" cy="59" r="3.4"', "url(#g)", 2.4) + '</g>', ROLE)
icons["role_caster"] = svg(
    '<path d="M14 58 L38 24" stroke="%s" stroke-width="9" stroke-linecap="round"/>' % OL +
    '<path d="M14 58 L38 24" stroke="url(#g)" stroke-width="4.5" stroke-linecap="round"/>' +
    shape("polygon", 'points="%s"' % pts(star_pts(43, 17, 15, 5.5, 4, -90)), "url(#g)", 2.8) +
    sparkle(20, 22, 5.5, "#ffffff") + sparkle(52, 40, 4.5, "#ffffff"), ROLE)
icons["role_support"] = svg(
    shape("path", 'd="%s"' % HEART, "url(#g)") +
    '<path d="M32 20 V42 M21 31 H43" stroke="#8a7fb4" stroke-width="5" stroke-linecap="round"/>', ROLE)
DAG = (shape("polygon", 'points="29,10 32,3 35,10 35,40 29,40"', "url(#g)", 2.6) +
       shape("rect", 'x="23" y="39" width="18" height="5" rx="2.5"', "url(#g)", 2.4) +
       shape("rect", 'x="29.5" y="44" width="5" height="10"', "url(#g)", 2.4))
icons["role_assassin"] = svg(
    '<g transform="rotate(35 32 32)">' + DAG + '</g>' + '<g transform="rotate(-35 32 32)">' + DAG + '</g>', ROLE)

# ---------------------------------------------------------------- badges & controls
icons["plus_badge"] = svg(
    shape("circle", 'cx="32" cy="32" r="27"', "url(#pb)") +
    '<path d="M32 18 V46 M18 32 H46" stroke="#0f3a28" stroke-width="10" stroke-linecap="round"/>'
    '<path d="M32 18 V46 M18 32 H46" stroke="#ffffff" stroke-width="5.5" stroke-linecap="round"/>'
    '<path d="M14 26 A19 19 0 0 1 24 13" fill="none" stroke="#ffffff" stroke-width="3" stroke-linecap="round" opacity="0.6"/>',
    lin("pb", [(0, "#a8ffd2"), (0.5, "#3fc985"), (1, "#178a55")]))

icons["sound_on"] = svg(
    shape("path", 'd="M8 24 H18 L31 12 V52 L18 40 H8 Z"', "url(#g)") +
    stroke2("M40 22 C45 27 45 37 40 42", 10, 5) + stroke2("M47 15 C56 24 56 40 47 49", 10, 5), CREAM)
icons["sound_off"] = svg(
    shape("path", 'd="M8 24 H18 L31 12 V52 L18 40 H8 Z"', "url(#g)") +
    stroke2("M40 24 L54 40 M54 24 L40 40", 10, 5), CREAM)

# Music: two beamed eighth notes.
icons["music"] = svg(
    shape("path", 'd="M22 14 L52 7 V17 L22 24 Z"', "url(#g)", 2.6) +
    stroke2("M24 20 V45", 9, 4.5, "#f3ecdf", "butt") + stroke2("M50 13 V39", 9, 4.5, "#f3ecdf", "butt") +
    shape("ellipse", 'cx="17" cy="46" rx="9.5" ry="7.5" transform="rotate(-20 17 46)"', "url(#g)") +
    shape("ellipse", 'cx="43" cy="40" rx="9.5" ry="7.5" transform="rotate(-20 43 40)"', "url(#g)") +
    sparkle(10, 13, 5), CREAM)
# Vibration: a phone with buzz marks on both sides.
icons["vibrate"] = svg(
    shape("rect", 'x="20" y="6" width="24" height="52" rx="5"', "url(#g)") +
    '<rect x="24" y="12" width="16" height="34" rx="2" fill="#3b2f63"/>' +
    '<circle cx="32" cy="52" r="2.6" fill="#3b2f63"/>' +
    stroke2("M12 22 L7 27 L12 32 L7 37 L12 42", 8, 4, "#f2c14e") +
    stroke2("M52 22 L57 27 L52 32 L57 37 L52 42", 8, 4, "#f2c14e"), CREAM)
# Guidance pointer: a gold arrow pointing down at the suggested button.
icons["pointer"] = svg(
    shape("path", 'd="M22 4 H42 V30 H55 L32 60 L9 30 H22 Z"', "url(#gold)") +
    '<path d="M27 9 V31" stroke="#ffffff" stroke-width="3" stroke-linecap="round" opacity="0.8"/>', GOLD)

# Toggle switch for CheckButton (drawn at native size 100x56).
icons["toggle_off"] = svg(
    '<rect x="3" y="7" width="94" height="42" rx="21" fill="#0d0a1c" stroke="#6b5c9e" stroke-width="3"/>'
    '<rect x="8" y="12" width="84" height="32" rx="16" fill="none" stroke="#2a2150" stroke-width="2"/>'
    '<circle cx="28" cy="28" r="18" fill="url(#k)" stroke="%s" stroke-width="3"/>' % OL +
    '<path d="M18 22 A11 11 0 0 1 26 16" fill="none" stroke="#ffffff" stroke-width="2.6" stroke-linecap="round" opacity="0.8"/>',
    lin("k", [(0, "#ffffff"), (1, "#9f95c4")]), 100, 56, 100, 56)
icons["toggle_on"] = svg(
    '<rect x="3" y="7" width="94" height="42" rx="21" fill="url(#on)" stroke="#5c3a0a" stroke-width="3"/>'
    '<path d="M16 16 H70" stroke="#ffffff" stroke-width="2.4" stroke-linecap="round" opacity="0.55"/>'
    '<circle cx="72" cy="28" r="18" fill="url(#k)" stroke="%s" stroke-width="3"/>' % OL +
    '<path d="M62 22 A11 11 0 0 1 70 16" fill="none" stroke="#ffffff" stroke-width="2.6" stroke-linecap="round" opacity="0.9"/>',
    lin("on", [(0, "#ffe9a6"), (0.5, "#f2c14e"), (1, "#c98a1e")]) + lin("k", [(0, "#ffffff"), (1, "#e9e2f8")]),
    100, 56, 100, 56)
icons["knob"] = svg(
    '<circle cx="24" cy="24" r="19" fill="url(#gold)" stroke="%s" stroke-width="3"/>' % OL +
    '<circle cx="24" cy="24" r="7" fill="#fff4c0" stroke="#a86a12" stroke-width="1.5"/>', GOLD, 48, 48, 48, 48)

os.makedirs(OUT_DIR, exist_ok=True)
for name, data in icons.items():
    with open(os.path.join(OUT_DIR, name + ".svg"), "w") as fh:
        fh.write(data)
print("wrote %d icons" % len(icons))
