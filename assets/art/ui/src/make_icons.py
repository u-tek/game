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
icons["close"] = svg(stroke("M16 16 L48 48 M48 16 L16 48", 6.5))
icons["check"] = svg(stroke("M12 33 L26 47 L53 18", 7.5))
icons["plus"] = svg(stroke("M32 12 V52 M12 32 H52", 7.5, cap="butt"))
icons["info"] = svg(path(circle_d(32, 32, 26) + " " + circle_d(32, 32, 21.5)) + circ(32, 20, 3.6) + rect(28.6, 27, 6.8, 21, 1.5))
icons["lock"] = svg(stroke("M21 30 V22 A11 11 0 0 1 43 22 V30", 6, cap="butt")
                    + path(rrect_d(13, 28, 38, 28, 4) + " " + circle_d(32, 39, 4.2) + " " + poly_d([(30, 41), (34, 41), (35, 50), (29, 50)])))
icons["refresh"] = svg(stroke("M50 30 A18 18 0 1 1 42 16", 6, cap="butt") + poly([(36, 6), (52, 14), (38, 26)]))
icons["settings"] = svg(path(gear_d(32, 32, 27, 20, 8) + " " + circle_d(32, 32, 8.5)))
icons["mail"] = svg(path(rrect_d(6, 13, 52, 38, 4) + " " + poly_d([(9, 15), (32, 32), (55, 15), (57, 19.5), (32, 38), (7, 19.5)])))
icons["bell"] = svg(path("M32 7 C42 7 47 15 47 25 V36 L53 45 H11 L17 36 V25 C17 15 22 7 32 7 Z") + path(circle_d(32, 51, 6)))
icons["quests"] = svg(path(rrect_d(11, 10, 42, 48, 4) + " " + rrect_d(16, 18, 32, 35, 1.5))
                      + rect(23, 5, 18, 10, 2.5) + stroke("M21 35 L28 42 L43 26", 5.2) )
icons["avatar"] = svg(circ(32, 24, 12) + path("M8 60 C8 45 19 38 32 38 C45 38 56 45 56 60 Z"))
icons["filter"] = svg(path(poly_d([(8, 10), (56, 10), (38, 32), (38, 52), (26, 58), (26, 32)])))
icons["eye_off"] = svg(stroke("M6 32 C14 20 22 15 32 15 C42 15 50 20 58 32 C50 44 42 49 32 49 C22 49 14 44 6 32 Z", 4.5) + circ(32, 32, 8) + stroke("M12 54 L52 10", 5))
icons["home"] = svg(path(poly_d([(32, 6), (58, 30), (51, 30), (51, 56), (38, 56), (38, 40), (26, 40), (26, 56), (13, 56), (13, 30), (6, 30)])))
icons["pointer"] = svg(poly([(32, 60), (8, 32), (22, 32), (22, 6), (42, 6), (42, 32), (56, 32)], W)
                       + poly([(32, 53), (15, 35), (26, 35), (26, 10), (38, 10), (38, 35), (49, 35)], ORANGE))

# Bottom nav (Heroes, Team, Lobby, Gear, Summon). Original glyphs, consistent weight.
# Heroes: one figure under a halo with a single swept wing behind the shoulder (our angel
# motif), one tone. Deliberately not a group of busts.
icons["nav_heroes"] = svg(stroke("M15 9 A11 3.8 0 1 0 37 9 A11 3.8 0 1 0 15 9", 3.4)
                          + circ(26, 22, 8.2)
                          + path("M10 58 C10 43 17 35 26 35 C35 35 42 43 42 58 Z")
                          + path("M39 37 C46 34 50 28 53 18 C55 11 58 7 62 5 C62 14 60 21 57 26 C59 25.5 61 24.5 63 23 "
                                 "C62 30 58 35 53 37.5 C55.5 37.8 58 37.5 60 37 C56 44 50 47.5 43 48 Z"))
icons["heroes"] = icons["nav_heroes"]
# Team: formation board, two front slots and three back slots, as rounded hexes.
_team = ""
for (x, y) in [(22, 18), (42, 18), (12, 44), (32, 44), (52, 44)]:
    _team += poly(hex_pts(x, y, 10.5))
icons["nav_team"] = svg(_team)
icons["team"] = icons["nav_team"]
# Lobby: halo over a horned crest (the game's two sides), inside a hex frame.
icons["nav_lobby"] = svg(path("M8 58 V30 L32 10 L56 30 V58 Z M24 58 V44 C24 38 27 34 32 31 C37 34 40 38 40 44 V58 Z")
                         + path(circle_d(32, 6, 5) + " " + circle_d(32, 6, 2.6)) + rect(4, 55, 56, 5, 1.5))
# Gear: shield with a sword through it.
icons["nav_gear"] = svg(path(poly_d([(44, 6), (58, 6), (58, 20), (50, 28), (36, 14)])) + path(poly_d([(6, 50), (14, 42), (22, 50), (14, 58)])) + rect(4, 41, 22, 5, 2, W, ' transform="rotate(45 15 43.5)"')
                        + path("M32 12 L52 19 V33 C52 45 43 53 32 58 C21 53 12 45 12 33 V19 Z " + poly_d([(20, 28), (32, 36), (44, 28), (44, 34), (32, 42), (20, 34)])))
icons["gear"] = icons["nav_gear"]
# Summon: a portal ring with a four-point star rising out of it.
icons["nav_summon"] = svg(path("M8 46 C8 39 19 35 32 35 C45 35 56 39 56 46 C56 53 45 57 32 57 C19 57 8 53 8 46 Z M15 46 C15 49 22 51 32 51 C42 51 49 49 49 46 C49 43 42 41 32 41 C22 41 15 43 15 46 Z")
                          + poly(star_pts(32, 22, 18, 5, 4, -90)) + circ(48, 10, 3) + circ(14, 16, 2.4))
icons["summon"] = icons["nav_summon"]

# Objective flag: a pole and a notched pennant (the lobby objective strip).
icons["flag"] = svg(rect(12, 6, 6, 52, 2) + path(poly_d([(18, 8), (54, 8), (44, 21), (54, 34), (18, 34)])) + rect(6, 54, 18, 5, 2))

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
icons["equip"] = icons["nav_gear"]
icons["upgrade"] = svg(path(poly_d([(32, 6), (54, 28), (42, 28), (42, 40), (22, 40), (22, 28), (10, 28)])) + rect(22, 45, 20, 5, 1) + rect(22, 53, 20, 5, 1))

# Battle / settings controls.
icons["speed"] = svg(path(poly_d([(6, 12), (32, 32), (6, 52)])) + path(poly_d([(30, 12), (58, 32), (30, 52)])))
icons["skip"] = svg(path(poly_d([(8, 12), (36, 32), (8, 52)])) + rect(42, 12, 9, 40, 1.5))
icons["auto"] = svg(stroke("M50 30 A18 18 0 1 0 46 44", 6, cap="butt") + poly([(56, 22), (54, 38), (40, 28)])
                    + path("M25 41 L31 22 H35 L41 41 H36.5 L35 36 H31 L29.5 41 Z M32 32 H34 L33 28 Z"))
icons["sound_on"] = svg(path(poly_d([(6, 24), (18, 24), (32, 10), (32, 54), (18, 40), (6, 40)])) + stroke("M40 22 A13 13 0 0 1 40 42", 4.5) + stroke("M46 14 A23 23 0 0 1 46 50", 4.5))
icons["music"] = svg(rect(24, 10, 5, 36) + rect(48, 6, 5, 36) + path(poly_d([(24, 10), (53, 4), (53, 14), (24, 20)]))
                     + circ(19, 46, 8) + circ(43, 42, 8))
icons["vibrate"] = svg(path(rrect_d(20, 6, 24, 52, 4) + " " + rrect_d(24, 12, 16, 36, 1)) + stroke("M12 20 V44 M6 25 V39 M52 20 V44 M58 25 V39", 3.5))

# Stats (white glyphs).
icons["stat_hp"] = svg(path("M32 56 C16 44 6 35 6 23 C6 14 13 8 21 8 C26 8 30 11 32 15 C34 11 38 8 43 8 C51 8 58 14 58 23 C58 35 48 44 32 56 Z"))
icons["stat_atk"] = icons["sword"]
icons["stat_def"] = svg(path("M32 6 L54 14 V30 C54 44 44 53 32 58 C20 53 10 44 10 30 V14 Z"))
icons["stat_spd"] = svg(path(poly_d([(36, 4), (12, 36), (28, 36), (24, 60), (52, 24), (34, 24)])))
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
icons["crown"] = svg(poly([(6, 18), (20, 30), (32, 10), (44, 30), (58, 18), (52, 50), (12, 50)], AMBER) + rect(12, 50, 40, 7, 1.5, ORANGE_DK)
                     + circ(32, 10, 4, W) + circ(6, 18, 3.5, AMBER) + circ(58, 18, 3.5, AMBER) + poly([(32, 30), (37, 38), (32, 46), (27, 38)], ORANGE_DK))

# Factions: flat marks in the faction color with a white core.
icons["faction_celestial"] = svg(path(circle_d(32, 13, 10) + " " + circle_d(32, 13, 6), "#f5c242")
                                 + path("M30 50 C24 36 16 30 4 27 C7 33 9 36 13 38 C9 38 7 39 5 41 C11 45 17 46 23 45 C20 47 18 49 17 52 C22 53 27 52 30 50 Z", "#f5c242")
                                 + path("M34 50 C40 36 48 30 60 27 C57 33 55 36 51 38 C55 38 57 39 59 41 C53 45 47 46 41 45 C44 47 46 49 47 52 C42 53 37 52 34 50 Z", "#f5c242")
                                 + poly([(32, 28), (36, 42), (32, 60), (28, 42)], W))
icons["faction_infernal"] = svg(path("M14 8 C8 22 12 34 24 40 L26 32 C20 28 17 20 14 8 Z", "#e8452c") + path("M50 8 C56 22 52 34 40 40 L38 32 C44 28 47 20 50 8 Z", "#e8452c")
                                + path("M32 22 C40 30 44 38 44 46 C44 54 38 60 32 60 C26 60 20 54 20 46 C20 38 24 30 32 22 Z", "#e8452c")
                                + path("M32 38 C36 42 38 46 38 50 C38 54 35 56 32 56 C29 56 26 54 26 50 C26 46 28 42 32 38 Z", "#ffd2b0"))
icons["faction_fallen"] = svg(stroke("M10 20 A22 9 0 0 1 30 11.2", 5, "#9a6cf5", "butt") + stroke("M38 11.3 A22 9 0 0 1 54 20 A22 9 0 0 1 44 27.5", 5, "#9a6cf5", "butt")
                              + path("M22 60 C20 50 24 38 34 30 C40 26 46 25 50 26 C50 32 46 40 40 46 C34 52 28 56 22 60 Z", "#9a6cf5")
                              + stroke("M24 57 C30 48 37 38 47 29", 2.6, W))

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
