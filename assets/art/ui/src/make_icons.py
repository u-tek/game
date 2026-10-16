#!/usr/bin/env python3
"""Generates the UI icon set (assets/art/ui/*.svg) for Halo & Horn, style v2
(docs/dev/ui-style-v2.md, "Icons").

    python3 assets/art/ui/src/make_icons.py      (then: tools/gd --headless --path . --import)

Grammar (all original drawings, no traced or copied shapes):
  * 64-unit grid, rendered at 128 px. Live area 6..58 (glyphs) so tinted icons line up.
  * UI glyphs are SOLID WHITE (#fff) flat shapes with cut-outs and 4-unit strokes, square
    joins softened to round, no outlines, no gradients. Code tints them with modulate
    (white on dark chrome, near-black on light panels, grey when inactive).
  * Colored icons only where color carries meaning: currencies, stars, power, crown, the
    three faction marks, toggles. Those use flat 2-3 tone fills (light face, base, shade)
    and one small white glint. No black outlines anywhere.
ThorVG-safe: paths, polygons, rects, circles, strokes, fill-rule evenodd, opacity.
New icons need mipmaps/generate=true in their .import (this script writes the .import
for any icon that has none)."""
import math, os, sys

OUT_DIR = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
W = "#ffffff"

ACCENT = "#12a8f4"
ACCENT_LT = "#7fdcff"
ACCENT_DK = "#0a6fd6"
AMBER = "#ffc23a"
ORANGE = "#ff8a1e"
ORANGE_DK = "#d8620c"


def f(v):
    s = ("%.2f" % v).rstrip("0").rstrip(".")
    return s if s != "-0" else "0"


def pts(points):
    return " ".join("%s,%s" % (f(x), f(y)) for x, y in points)


def svg(body, w=128, h=128, vw=64, vh=64):
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">%s</svg>\n'
            % (w, h, vw, vh, body))


def path(d, fill=W, extra=""):
    return '<path d="%s" fill="%s" fill-rule="evenodd"%s/>' % (d, fill, extra)


def stroke(d, w=4.0, col=W, cap="round", join="round", extra=""):
    return ('<path d="%s" fill="none" stroke="%s" stroke-width="%s" stroke-linecap="%s" stroke-linejoin="%s"%s/>'
            % (d, col, f(w), cap, join, extra))


def poly(points, fill=W, extra=""):
    return '<polygon points="%s" fill="%s"%s/>' % (pts(points), fill, extra)


def circ(cx, cy, r, fill=W, extra=""):
    return '<circle cx="%s" cy="%s" r="%s" fill="%s"%s/>' % (f(cx), f(cy), f(r), fill, extra)


def ring(cx, cy, r, w=4.0, col=W, extra=""):
    return '<circle cx="%s" cy="%s" r="%s" fill="none" stroke="%s" stroke-width="%s"%s/>' % (f(cx), f(cy), f(r), col, f(w), extra)


def rect(x, y, w, h, rx=0, fill=W, extra=""):
    return '<rect x="%s" y="%s" width="%s" height="%s" rx="%s" fill="%s"%s/>' % (f(x), f(y), f(w), f(h), f(rx), fill, extra)


def rrect_d(x, y, w, h, r):
    """Rounded rect as a path (for evenodd cut-outs)."""
    return ("M%s %s H%s A%s %s 0 0 1 %s %s V%s A%s %s 0 0 1 %s %s H%s A%s %s 0 0 1 %s %s V%s A%s %s 0 0 1 %s %s Z" % (
        f(x + r), f(y), f(x + w - r), f(r), f(r), f(x + w), f(y + r), f(y + h - r), f(r), f(r), f(x + w - r), f(y + h),
        f(x + r), f(r), f(r), f(x), f(y + h - r), f(y + r), f(r), f(r), f(x + r), f(y)))


def circle_d(cx, cy, r):
    return "M%s %s A%s %s 0 1 0 %s %s A%s %s 0 1 0 %s %s Z" % (
        f(cx - r), f(cy), f(r), f(r), f(cx + r), f(cy), f(r), f(r), f(cx - r), f(cy))


def poly_d(points):
    return "M" + " L".join("%s %s" % (f(x), f(y)) for x, y in points) + " Z"


def hex_pts(cx, cy, r, flat=False):
    off = 0 if flat else 30
    return [(cx + r * math.cos(math.radians(off + 60 * i)), cy + r * math.sin(math.radians(off + 60 * i))) for i in range(6)]


def star_pts(cx, cy, R, r, n=5, rot=-90):
    out = []
    for i in range(n * 2):
        a = math.radians(rot + i * 180.0 / n)
        rr = R if i % 2 == 0 else r
        out.append((cx + rr * math.cos(a), cy + rr * math.sin(a)))
    return out


def gear_d(cx, cy, R, r, teeth, tw=0.45):
    p = []
    for i in range(teeth):
        a0 = 2 * math.pi * i / teeth
        da = 2 * math.pi / teeth
        for a, rr in ((a0 - da * tw * 0.5, r), (a0 - da * tw * 0.35, R), (a0 + da * tw * 0.35, R), (a0 + da * tw * 0.5, r)):
            p.append((cx + rr * math.cos(a), cy + rr * math.sin(a)))
    return poly_d(p)


def glint(x, y, s=3.0):
    return poly(star_pts(x, y, s, s * 0.3, 4, -90), W, ' opacity="0.9"')


icons = {}

# ------------------------------------------------------------------ navigation & chrome glyphs

# Back: chunky left arrow.
icons["back"] = svg(stroke("M38 14 L20 32 L38 50", 7) + stroke("M22 32 H50", 7))
icons["chevron_right"] = svg(stroke("M24 14 L42 32 L24 50", 7))
icons["arrow_right"] = svg(path(poly_d([(10, 26), (34, 26), (34, 14), (54, 32), (34, 50), (34, 38), (10, 38)])))
icons["arrow_up"] = svg(path(poly_d([(32, 8), (54, 30), (40, 30), (40, 56), (24, 56), (24, 30), (10, 30)])))
icons["close"] = svg(stroke("M16 16 L48 48 M48 16 L16 48", 6.5))
icons["check"] = svg(stroke("M12 33 L26 47 L53 18", 7.5))
icons["plus"] = svg(stroke("M32 12 V52 M12 32 H52", 7.5, cap="butt"))
icons["plus_badge"] = svg(stroke("M32 14 V50 M14 32 H50", 9, cap="butt"))
icons["info"] = svg(path(circle_d(32, 32, 26) + " " + circle_d(32, 32, 21.5)) + circ(32, 20, 3.6) + rect(28.6, 27, 6.8, 21, 1.5))
icons["lock"] = svg(stroke("M21 30 V22 A11 11 0 0 1 43 22 V30", 6, cap="butt")
                    + path(rrect_d(13, 28, 38, 28, 4) + " " + circle_d(32, 39, 4.2) + " " + poly_d([(30, 41), (34, 41), (35, 50), (29, 50)])))
icons["refresh"] = svg(stroke("M50 30 A18 18 0 1 1 42 16", 6, cap="butt") + poly([(36, 6), (52, 14), (38, 26)]))
icons["settings"] = svg(path(gear_d(32, 32, 27, 20, 8) + " " + circle_d(32, 32, 8.5)))
icons["menu"] = svg(rect(9, 9, 20, 20, 3) + rect(35, 9, 20, 20, 3) + rect(9, 35, 20, 20, 3) + rect(35, 35, 20, 20, 3))
icons["mail"] = svg(path(rrect_d(6, 13, 52, 38, 4) + " " + poly_d([(9, 15), (32, 32), (55, 15), (57, 19.5), (32, 38), (7, 19.5)])))
icons["bell"] = svg(path("M32 7 C42 7 47 15 47 25 V36 L53 45 H11 L17 36 V25 C17 15 22 7 32 7 Z") + path(circle_d(32, 51, 6)))
icons["chat"] = svg(path(rrect_d(6, 10, 52, 36, 8) + " " + circle_d(20, 28, 3.6) + " " + circle_d(32, 28, 3.6) + " " + circle_d(44, 28, 3.6)) + poly([(16, 44), (28, 44), (14, 56)]))
icons["quests"] = svg(path(rrect_d(11, 10, 42, 48, 4) + " " + rrect_d(16, 18, 32, 35, 1.5))
                      + rect(23, 5, 18, 10, 2.5) + stroke("M21 35 L28 42 L43 26", 5.2) )
icons["calendar"] = svg(path(rrect_d(8, 12, 48, 44, 4) + " " + rrect_d(13, 25, 38, 26, 1.5)) + rect(17, 6, 6, 12, 2) + rect(41, 6, 6, 12, 2)
                        + rect(18, 30, 8, 7, 1) + rect(28, 30, 8, 7, 1) + rect(38, 30, 8, 7, 1) + rect(18, 40, 8, 7, 1) + rect(28, 40, 8, 7, 1))
icons["friend"] = svg(circ(32, 22, 11) + path("M10 56 C10 42 20 36 32 36 C44 36 54 42 54 56 Z"))
icons["avatar"] = svg(circ(32, 24, 12) + path("M8 60 C8 45 19 38 32 38 C45 38 56 45 56 60 Z"))
icons["trophy"] = svg(path("M18 8 H46 V26 C46 35 40 41 32 41 C24 41 18 35 18 26 Z") + stroke("M18 14 H10 V20 C10 27 15 30 19 30 M46 14 H54 V20 C54 27 49 30 45 30", 4)
                      + rect(29, 40, 6, 9) + rect(19, 49, 26, 7, 2))
icons["filter"] = svg(path(poly_d([(8, 10), (56, 10), (38, 32), (38, 52), (26, 58), (26, 32)])))
icons["sort"] = svg(path(poly_d([(18, 6), (30, 22), (22, 22), (22, 58), (14, 58), (14, 22), (6, 22)]))
                    + path(poly_d([(46, 58), (34, 42), (42, 42), (42, 6), (50, 6), (50, 42), (58, 42)])))
icons["eye_off"] = svg(stroke("M6 32 C14 20 22 15 32 15 C42 15 50 20 58 32 C50 44 42 49 32 49 C22 49 14 44 6 32 Z", 4.5) + circ(32, 32, 8) + stroke("M12 54 L52 10", 5))
icons["home"] = svg(path(poly_d([(32, 6), (58, 30), (51, 30), (51, 56), (38, 56), (38, 40), (26, 40), (26, 56), (13, 56), (13, 30), (6, 30)])))
icons["exit"] = svg(path(poly_d([(8, 8), (40, 8), (40, 22), (34, 22), (34, 14), (14, 14), (14, 50), (34, 50), (34, 42), (40, 42), (40, 56), (8, 56)]))
                    + path(poly_d([(22, 29), (44, 29), (44, 20), (58, 32), (44, 44), (44, 35), (22, 35)])))
icons["pointer"] = svg(poly([(32, 60), (8, 32), (22, 32), (22, 6), (42, 6), (42, 32), (56, 32)], W)
                       + poly([(32, 53), (15, 35), (26, 35), (26, 10), (38, 10), (38, 35), (49, 35)], ACCENT))
icons["hex"] = svg(poly(hex_pts(32, 32, 29)))
icons["hex_outline"] = svg(path(poly_d(hex_pts(32, 32, 29)) + " " + poly_d(hex_pts(32, 32, 24))))

# Bottom nav (Heroes, Team, Lobby, Gear, Summon). Original glyphs, consistent weight.
# Heroes: a centered bust with two smaller busts behind, cut by a chevron at the base.
icons["nav_heroes"] = svg(circ(32, 16, 8.5) + path("M18 46 C18 33 24 28 32 28 C40 28 46 33 46 46 L32 58 Z")
                          + circ(12, 22, 6) + path("M2 44 C2 35 6 31 12 31 C16 31 19 33 20 37 L16 48 Z", W, ' opacity="0.8"')
                          + circ(52, 22, 6) + path("M62 44 C62 35 58 31 52 31 C48 31 45 33 44 37 L48 48 Z", W, ' opacity="0.8"'))
icons["heroes"] = icons["nav_heroes"]
# Team: formation board, two front slots and three back slots, as rounded hexes.
_team = ""
for (x, y) in [(22, 18), (42, 18), (12, 44), (32, 44), (52, 44)]:
    _team += poly(hex_pts(x, y, 10.5))
icons["nav_team"] = svg(_team + stroke("M22 18 L32 44 L42 18", 2.5, extra=' opacity="0.7"'))
icons["team"] = icons["nav_team"]
# Lobby: halo over a horned crest (the game's two sides), inside a hex frame.
icons["nav_lobby"] = svg(path(poly_d(hex_pts(32, 33, 28)) + " " + poly_d(hex_pts(32, 33, 23.5)))
                         + path("M32 22 C39 22 44 26 44 32 C44 41 37 47 32 52 C27 47 20 41 20 32 C20 26 25 22 32 22 Z")
                         + path("M20 28 C16 22 15 16 17 10 C20 17 24 20 27 23 Z") + path("M44 28 C48 22 49 16 47 10 C44 17 40 20 37 23 Z")
                         + path(circle_d(32, 13, 8) + " " + circle_d(32, 13, 5.2)) )
icons["lobby"] = icons["nav_lobby"]
# Gear: shield with a sword through it.
icons["nav_gear"] = svg(path("M32 8 L52 15 V31 C52 43 43 52 32 57 C21 52 12 43 12 31 V15 Z M32 14 L18 19 V31 C18 40 24 46 32 50 Z")
                        + rect(42, 4, 5, 42, 1, W, ' transform="rotate(35 44 25)"') + rect(34, 40, 18, 5, 2, W, ' transform="rotate(35 43 42)"'))
icons["gear"] = icons["nav_gear"]
# Summon: a portal ring with a four-point star rising out of it.
icons["nav_summon"] = svg(path("M8 46 C8 39 19 35 32 35 C45 35 56 39 56 46 C56 53 45 57 32 57 C19 57 8 53 8 46 Z M15 46 C15 49 22 51 32 51 C42 51 49 49 49 46 C49 43 42 41 32 41 C22 41 15 43 15 46 Z")
                          + poly(star_pts(32, 22, 18, 5, 4, -90)) + circ(48, 10, 3) + circ(14, 16, 2.4))
icons["summon"] = icons["nav_summon"]

# Lobby side buttons & shortcuts.
icons["sanctum"] = svg(path("M8 54 V34 C8 20 19 10 32 10 C45 10 56 20 56 34 V54 H44 V36 C44 29 39 24 32 24 C25 24 20 29 20 36 V54 Z")
                       + rect(4, 54, 56, 5, 1.5) + poly(star_pts(32, 40, 8, 2.6, 4, -90)))
icons["campaign"] = svg(path(poly_d([(10, 8), (14, 8), (14, 58), (10, 58)])) + path(poly_d([(14, 10), (52, 10), (44, 22), (52, 34), (14, 34)])))
icons["map"] = svg(path(poly_d([(6, 14), (22, 8), (42, 14), (58, 8), (58, 50), (42, 56), (22, 50), (6, 56)]) + " "
                        + poly_d([(24, 14.5), (40, 19.5), (40, 49.5), (24, 44.5)])))
icons["shop"] = svg(path(poly_d([(8, 22), (56, 22), (52, 58), (12, 58)]) + " " + circle_d(24, 31, 2.8) + " " + circle_d(40, 31, 2.8))
                    + stroke("M24 31 V18 A8 8 0 0 1 40 18 V31", 4.2, cap="butt"))
icons["gift"] = svg(rect(8, 22, 48, 11, 2) + rect(12, 35, 40, 22, 2)
                    + path("M32 22 C26 10 14 10 16 18 C17 22 26 22 32 22 Z M32 22 C38 10 50 10 48 18 C47 22 38 22 32 22 Z"))
icons["chest"] = svg(path("M6 26 C6 16 13 10 22 10 H42 C51 10 58 16 58 26 V30 H6 Z") + path(rrect_d(6, 33, 52, 23, 3) + " " + poly_d([(27, 33), (37, 33), (37, 44), (32, 47), (27, 44)])))
icons["sword"] = svg(path(poly_d([(50, 6), (58, 6), (58, 14), (28, 44), (20, 36)])) + rect(8, 34, 26, 6, 2, W, ' transform="rotate(45 21 37)"')
                     + path(poly_d([(14, 44), (20, 50), (11, 59), (5, 53)])))
icons["crossed"] = svg(path(poly_d([(46, 4), (56, 4), (56, 14), (24, 46), (14, 36)])) + path(poly_d([(18, 4), (8, 4), (8, 14), (40, 46), (50, 36)]))
                       + rect(6, 44, 18, 5, 2, W, ' transform="rotate(45 15 46)"') + rect(40, 44, 18, 5, 2, W, ' transform="rotate(-45 49 46)"'))
icons["skill"] = svg(path(poly_d([(36, 4), (14, 36), (30, 36), (26, 60), (50, 26), (34, 26)])))
icons["equip"] = icons["nav_gear"]
icons["upgrade"] = svg(path(poly_d([(32, 6), (54, 28), (42, 28), (42, 40), (22, 40), (22, 28), (10, 28)])) + rect(22, 45, 20, 5, 1) + rect(22, 53, 20, 5, 1))
icons["timer"] = svg(path(circle_d(32, 36, 24) + " " + circle_d(32, 36, 19)) + rect(26, 4, 12, 6, 2) + stroke("M32 22 V36 L41 42", 4.5))

# Battle / settings controls.
icons["speed"] = svg(path(poly_d([(6, 12), (32, 32), (6, 52)])) + path(poly_d([(30, 12), (58, 32), (30, 52)])))
icons["skip"] = svg(path(poly_d([(8, 12), (36, 32), (8, 52)])) + rect(42, 12, 9, 40, 1.5))
icons["auto"] = svg(stroke("M50 30 A18 18 0 1 0 46 44", 6, cap="butt") + poly([(56, 22), (54, 38), (40, 28)])
                    + path("M25 41 L31 22 H35 L41 41 H36.5 L35 36 H31 L29.5 41 Z M32 32 H34 L33 28 Z"))
icons["sound_on"] = svg(path(poly_d([(6, 24), (18, 24), (32, 10), (32, 54), (18, 40), (6, 40)])) + stroke("M40 22 A13 13 0 0 1 40 42", 4.5) + stroke("M46 14 A23 23 0 0 1 46 50", 4.5))
icons["sound_off"] = svg(path(poly_d([(6, 24), (18, 24), (32, 10), (32, 54), (18, 40), (6, 40)])) + stroke("M40 24 L56 40 M56 24 L40 40", 5))
icons["music"] = svg(rect(24, 10, 5, 36) + rect(48, 6, 5, 36) + path(poly_d([(24, 10), (53, 4), (53, 14), (24, 20)]))
                     + circ(19, 46, 8) + circ(43, 42, 8))
icons["vibrate"] = svg(path(rrect_d(20, 6, 24, 52, 4) + " " + rrect_d(24, 12, 16, 36, 1)) + stroke("M12 20 V44 M6 25 V39 M52 20 V44 M58 25 V39", 3.5))

# Stats (white glyphs).
icons["stat_hp"] = svg(path("M32 56 C16 44 6 35 6 23 C6 14 13 8 21 8 C26 8 30 11 32 15 C34 11 38 8 43 8 C51 8 58 14 58 23 C58 35 48 44 32 56 Z"))
icons["stat_atk"] = icons["sword"]
icons["stat_def"] = svg(path("M32 6 L54 14 V30 C54 44 44 53 32 58 C20 53 10 44 10 30 V14 Z"))
icons["stat_spd"] = svg(path(poly_d([(36, 4), (12, 36), (28, 36), (24, 60), (52, 24), (34, 24)])))
icons["stat_crit"] = svg(path(circle_d(32, 32, 24) + " " + circle_d(32, 32, 18.5)) + circ(32, 32, 6) + rect(29.5, 2, 5, 16) + rect(29.5, 46, 5, 16) + rect(2, 29.5, 16, 5) + rect(46, 29.5, 16, 5))
icons["power"] = svg(poly([(38, 3), (12, 36), (29, 36), (24, 61), (52, 25), (35, 25)], ORANGE)
                     + poly([(38, 3), (12, 36), (29, 36), (35, 25)], AMBER))

# Gear slots (white glyphs).
icons["gear_weapon"] = icons["sword"]
icons["gear_armor"] = svg(path("M20 6 L26 6 C27 10 29 12 32 12 C35 12 37 10 38 6 L44 6 L58 14 L52 28 L46 25 V58 H18 V25 L12 28 L6 14 Z M24 30 V36 H40 V30 Z M24 41 V47 H40 V41 Z"))
icons["gear_helm"] = svg(path("M8 40 C8 20 18 8 32 8 C46 8 56 20 56 40 V54 H40 V42 H24 V54 H8 Z M14 32 H50 V36 H14 Z"))
icons["gear_charm"] = svg(path(poly_d([(32, 4), (52, 26), (32, 60), (12, 26)]) + " " + poly_d([(32, 14), (44, 27), (32, 48), (20, 27)])) + poly([(32, 20), (38, 27), (32, 38), (26, 27)]))

# Roles (white glyphs; shown on hex badges).
icons["role_guardian"] = svg(path("M32 6 L54 14 V30 C54 44 44 53 32 58 C20 53 10 44 10 30 V14 Z M32 14 V50 C40 46 47 39 47 30 V19 Z"))
icons["role_striker"] = svg(path(poly_d([(46, 4), (60, 4), (60, 18), (28, 50), (14, 36)])) + rect(4, 40, 26, 7, 2, W, ' transform="rotate(45 17 43)"') + path(poly_d([(8, 50), (14, 56), (8, 62), (2, 56)])))
icons["role_caster"] = svg(rect(29, 22, 6, 38, 2) + poly(star_pts(32, 16, 14, 5, 4, -90)))
icons["role_support"] = svg(path(poly_d([(24, 6), (40, 6), (40, 24), (58, 24), (58, 40), (40, 40), (40, 58), (24, 58), (24, 40), (6, 40), (6, 24), (24, 24)])))
icons["role_assassin"] = svg(path(poly_d([(32, 2), (40, 32), (32, 44), (24, 32)])) + rect(16, 42, 32, 5, 2) + rect(29, 46, 6, 14, 2))

# ------------------------------------------------------------------ colored icons

def coin_gold():
    hx = hex_pts(32, 32, 27, flat=False)
    hx2 = hex_pts(32, 32, 20, flat=False)
    return (poly([(p[0], p[1] + 2.5) for p in hx], ORANGE_DK) + poly(hx, "#f5b31f") + poly(hx2, "#ffd766")
            + path(circle_d(32, 32, 10) + " " + circle_d(32, 32, 6.5), "#c8790d") + poly([(32, 24), (36, 32), (32, 40), (28, 32)], "#c8790d")
            + poly([hx[3], hx[4], hx[5], (32, 32)], W, ' opacity="0.22"') + glint(19, 18, 3.4))


def gem_crystal():
    top, bot = (32, 3), (32, 61)
    l, r = (12, 22), (52, 22)
    l2, r2 = (12, 42), (52, 42)
    c1, c2 = (32, 28), (32, 46)
    return (poly([top, r, c1, l], "#c6f3ff") + poly([l, c1, c2, l2], "#3ec3f7") + poly([c1, r, r2, c2], "#139ee8")
            + poly([l2, c2, bot], "#0a7bd6") + poly([c2, r2, bot], "#0761b8") + poly([top, (22, 18), (32, 23)], W, ' opacity="0.75"')
            + glint(22, 30, 3.2))


def ticket():
    body = ("M8 14 H56 V26 C52 26 50 29 50 32 C50 35 52 38 56 38 V50 H8 V38 C12 38 14 35 14 32 C14 29 12 26 8 26 Z")
    return (path(body.replace("M8 14", "M8 16.5").replace("H56 V26", "H56 V28.5"), "#5b3fc4") + path(body, "#9a7cf6")
            + path("M14 18 H50 V24 C46 26 45 29 45 32 C45 35 46 38 50 40 V46 H14 V40 C18 38 19 35 19 32 C19 29 18 26 14 24 Z", "#e7e0ff")
            + poly(star_pts(32, 32, 9.5, 3.4, 4, -90), "#7a5ae8") + glint(20, 21, 2.6))


def exp_chip():
    return (rect(9, 11, 46, 46, 8, "#138a55") + rect(9, 8, 46, 46, 8, "#3fd58c") + rect(14, 13, 36, 36, 5, "#7ef0b4")
            + path(poly_d([(32, 15), (46, 30), (38, 30), (38, 45), (26, 45), (26, 30), (18, 30)]), "#0f8a52") + glint(18, 17, 2.8))


def dust_pile():
    return (path("M6 54 C10 44 20 40 32 40 C44 40 54 44 58 54 Z", "#7b45d6") + path("M12 52 C16 46 23 44 32 44 C41 44 48 46 52 52 Z", "#a877f2")
            + poly(star_pts(22, 24, 12, 3.2, 4, -90), "#d9c2ff") + poly(star_pts(44, 16, 8, 2.4, 4, -90), "#c3a2ff")
            + poly(star_pts(46, 36, 6, 2, 4, -90), W))


def shard_icon():
    return (poly([(34, 2), (52, 22), (40, 62), (14, 40), (20, 14)], "#8a2fb8") + poly([(34, 2), (52, 22), (36, 30), (20, 14)], "#f6b8ff")
            + poly([(20, 14), (36, 30), (40, 62), (14, 40)], "#c955e6") + poly([(36, 30), (52, 22), (40, 62)], "#a03dd0") + glint(28, 16, 3))


icons["gold"] = svg(coin_gold())
icons["gems"] = svg(gem_crystal())
icons["scrolls"] = svg(ticket())
icons["hero_exp"] = svg(exp_chip())
icons["dust"] = svg(dust_pile())
icons["shard"] = svg(shard_icon())

icons["star"] = svg(poly(star_pts(32, 34, 28, 12.5), ORANGE_DK) + poly(star_pts(32, 32, 28, 12.5), AMBER)
                    + poly([star_pts(32, 32, 28, 12.5)[i] for i in (9, 0, 1)] + [(32, 32)], "#ffe39a") + glint(22, 22, 3))
icons["star_empty"] = svg(path(poly_d(star_pts(32, 32, 28, 12.5)) + " " + poly_d(star_pts(32, 32.5, 21, 9.3)), "#9aa1ab")
                          + poly(star_pts(32, 32.5, 21, 9.3), "#9aa1ab", ' opacity="0.25"'))
icons["crown"] = svg(poly([(6, 18), (20, 30), (32, 10), (44, 30), (58, 18), (52, 50), (12, 50)], AMBER) + rect(12, 50, 40, 7, 1.5, ORANGE_DK)
                     + circ(32, 10, 4, W) + circ(6, 18, 3.5, AMBER) + circ(58, 18, 3.5, AMBER) + poly([(32, 30), (37, 38), (32, 46), (27, 38)], ORANGE_DK))

# Factions: flat marks in the faction color with a white core.
icons["faction_celestial"] = svg(path(circle_d(32, 16, 12) + " " + circle_d(32, 16, 7.5), "#f5c242")
                                 + path("M32 30 C26 36 18 38 6 36 C10 46 20 52 30 52 Z", "#f5c242") + path("M32 30 C38 36 46 38 58 36 C54 46 44 52 34 52 Z", "#f5c242")
                                 + poly([(32, 30), (36, 44), (32 , 60), (28, 44)], W))
icons["faction_infernal"] = svg(path("M14 8 C8 22 12 34 24 40 L26 32 C20 28 17 20 14 8 Z", "#e8452c") + path("M50 8 C56 22 52 34 40 40 L38 32 C44 28 47 20 50 8 Z", "#e8452c")
                                + path("M32 22 C40 30 44 38 44 46 C44 54 38 60 32 60 C26 60 20 54 20 46 C20 38 24 30 32 22 Z", "#e8452c")
                                + path("M32 38 C36 42 38 46 38 50 C38 54 35 56 32 56 C29 56 26 54 26 50 C26 46 28 42 32 38 Z", "#ffd2b0"))
icons["faction_fallen"] = svg(path("M10 18 A22 9 0 0 1 40 10.5 L37 16 A16 5.5 0 0 0 16 19 Z", "#9a6cf5") + path("M46 12 A22 9 0 0 1 54 22 L48 22 A16 5.5 0 0 0 44 17 Z", "#9a6cf5")
                              + path("M36 26 C46 32 50 44 44 58 C42 48 36 42 26 40 C30 36 34 32 36 26 Z", "#9a6cf5") + path("M34 32 C38 38 39 44 38 50 C35 46 32 44 28 42 C31 39 33 36 34 32 Z", W))

# Toggles and slider knob.
icons["toggle_on"] = svg(rect(2, 16, 60, 32, 16, ACCENT) + circ(46, 32, 12, W), 128, 128)
icons["toggle_off"] = svg(rect(2, 16, 60, 32, 16, "#aeb5bf") + circ(18, 32, 12, W), 128, 128)
icons["knob"] = svg(circ(32, 32, 22, W) + ring(32, 32, 19, 5, ACCENT))


def write_import(name):
    imp = os.path.join(OUT_DIR, name + ".svg.import")
    if os.path.exists(imp):
        return
    with open(imp, "w") as fh:
        fh.write('[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n\n[deps]\n\nsource_file="res://assets/art/ui/%s.svg"\n\n'
                 '[params]\n\ncompress/mode=0\nmipmaps/generate=true\nmipmaps/limit=-1\nprocess/fix_alpha_border=true\n'
                 'svg/scale=1.0\n' % name)


for name, data in icons.items():
    with open(os.path.join(OUT_DIR, name + ".svg"), "w") as fh:
        fh.write(data)
    write_import(name)
print("wrote %d icons to %s" % (len(icons), OUT_DIR))
