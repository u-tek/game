"""HaloRig WARP build: one painted illustration -> <id>.warp.json (grid mesh + bone skin
weights from region masks + overlay patches), portrait, imports.  Spec: docs/dev/halorig.md.

    python3 tools/art_warp_build.py seraphiel [--regen-masks] [--check]
    tools/art_warp seraphiel            # same, then Godot import (use this one)
    tools/art_warp imra@lucky_ember     # a skin: assets/art/heroes/imra/skins/lucky_ember/, files named
                                        # lucky_ember.* (the folder RigData.load_rig(hero, art) reads)
    tools/art_warp imra@lucky_ember@adult   # the skin's nude art: skins/lucky_ember/adult/lucky_ember.*
    tools/art_warp imra@@adult          # the base look's nude art: assets/art/heroes/imra/adult/imra.*
    (with no id it builds every base look and skin, plus every adult/ folder that has a warp_src)

Inputs in assets/art/heroes/<id>/:
    <id>.warp_src.json      rig setup: bones (pivots), regions (+ mask rules), overlays, grid
    <id>.png                the painted full-body image (transparent background, ~1024x2048)
    masks/<region>.png      grayscale weight masks (white = moves with the region's bone);
                            generated from "rule" entries when missing (or with --regen-masks)
    variants/<name>.png     full-size variants of the same image (eyes open, mouth open...)
Outputs: <id>.warp.json, overlays/<slot>_<variant>.png, <id>_portrait.png (+ .import files).
Needs Python 3 with Pillow and numpy.
"""
import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
HEROES = os.path.join(ROOT, "assets", "art", "heroes")
FORMAT_VERSION = 1
PORTRAIT_PX = 384
MAX_INFLUENCES = 3
PRESETS = {k: v for k, v in json.load(open(os.path.join(ROOT, "tools", "art_spring_presets.json"))).items() if not k.startswith("_")}

# Default spring preset by bone name (same rules as the cutout build) and head-turn factors.
DEFAULT_SPRING = [("hair_front", "bangs"), ("hair_back", "hair_long"), ("hair_side", "hair"), ("hair", "hair"),
                  ("ahoge", "hair"), ("ponytail", "hair_long"), ("skirt", "cloth"), ("coat", "cloth"), ("cape", "cape"),
                  ("ribbon", "ribbon"), ("sleeve", "sleeve"), ("wing", "wing"), ("tail", "tail")]
LOOK_DEFAULTS = [("face", (1.0, 1.0)), ("eye", (1.0, 1.0)), ("mouth", (0.95, 0.9)), ("hair_front", (0.7, 0.55)),
                 ("hair_side", (0.25, 0.15)), ("hair_back", (-0.35, -0.2)), ("halo", (-0.1, -0.15)),
                 ("horn", (-0.15, -0.1)), ("ear", (-0.45, 0.2)), ("wing_head", (-0.3, -0.1))]

errors = 0
warnings = 0


def err(hero, msg):
    global errors
    errors += 1
    print("ERROR: [%s] %s" % (hero, msg))


def warn(hero, msg):
    global warnings
    warnings += 1
    print("WARNING: [%s] %s" % (hero, msg))


# ------------------------------------------------------------------ masks from rules
# ---- SAM masks (tools/art_parts.py cuts them; the build only reads the cache)
_MASK_CTX = {"dir": "", "key": ""}


def set_mask_context(hdir, img):
    """The rig folder and image whose cached SAM masks rule_mask reads (masks/_sam/<key>.png)."""
    import hashlib
    _MASK_CTX["dir"] = hdir
    _MASK_CTX["key"] = hashlib.sha1(np.array(img).tobytes()).hexdigest()[:12]


def sam_dir():
    return os.path.join(_MASK_CTX["dir"], "masks", "_sam")


def sam_path(rule):
    """Cache file of a "sam" rule: its prompt and the image both name it, so a new prompt or a
    repainted image needs a new run of tools/art_parts.py."""
    import hashlib
    k = {key: rule[key] for key in ("points", "neg", "box", "pick", "clip") if key in rule}
    h = hashlib.sha1((json.dumps(k, sort_keys=True) + _MASK_CTX["key"]).encode()).hexdigest()[:16]
    return os.path.join(sam_dir(), h + ".png")


def _poly_mask(size, pts):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).polygon([tuple(p) for p in pts], fill=255)
    return m


def rule_mask(rule, img):
    """Rasterize a mask rule. Rule types (all coordinates in image pixels):
      {"type": "polygon", "points": [[x, y], ...]}
      {"type": "ellipse", "center": [x, y], "radius": [rx, ry]}
      {"type": "color", "within": <rule>, "hsv_min": [h, s, v], "hsv_max": [h, s, v]}   (0-255 HSV)
      {"type": "alpha", "within": <rule>}         opaque pixels of the image inside <rule>
      {"type": "union"|"subtract", "rules": [...]} (subtract: first minus the rest)
      {"type": "sam", "points", "neg", "box", "pick", "clip"}   Segment Anything (tools/art_parts.py)
      {"type": "mask", "image": "<file>", "threshold": 128, "within": <rule>}  a mask image (alpha or L)
                                                  in the art's pixels, relative to the rig folder;
                                                  "levels": true keeps its grey levels as weights
    Common keys: "grow": px dilation, "feather": px blur radius."""
    size = img.size
    t = rule.get("type", "polygon")
    if t == "sam":
        path = sam_path(rule)
        if not os.path.exists(path):
            raise ValueError("SAM mask not cut yet (%s): run tools/art_parts.py on this rig" % os.path.basename(path))
        m = Image.open(path).convert("L")
    elif t == "polygon":
        m = _poly_mask(size, rule["points"])
    elif t == "ellipse":
        cx, cy = rule["center"]
        rx, ry = rule["radius"]
        m = Image.new("L", size, 0)
        ImageDraw.Draw(m).ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=255)
    elif t in ("color", "alpha"):
        within = rule_mask(rule["within"], img) if "within" in rule else Image.new("L", size, 255)
        a = np.array(img.split()[3])
        sel = a > 24
        if t == "color":
            hsv = np.array(img.convert("RGB").convert("HSV")).astype(np.int32)
            lo = np.array(rule.get("hsv_min", [0, 0, 0]))
            hi = np.array(rule.get("hsv_max", [255, 255, 255]))
            h = hsv[..., 0]
            if lo[0] <= hi[0]:
                hok = (h >= lo[0]) & (h <= hi[0])
            else:   # hue range wrapping around red
                hok = (h >= lo[0]) | (h <= hi[0])
            sel &= hok & (hsv[..., 1] >= lo[1]) & (hsv[..., 1] <= hi[1]) & (hsv[..., 2] >= lo[2]) & (hsv[..., 2] <= hi[2])
        m = Image.fromarray(((sel & (np.array(within) > 127)) * 255).astype(np.uint8), "L")
    elif t == "mask":
        # a mask image in the art's pixels, relative to the rig folder (e.g. a See-through layer's alpha
        # placed on the canvas): white or opaque = the part
        path = os.path.join(_MASK_CTX["dir"], rule["image"])
        src = Image.open(path)
        src = src.split()[3] if src.mode == "RGBA" else src.convert("L")
        if src.size != size:
            raise ValueError("mask %s is %dx%d, the art is %dx%d" % (rule["image"], src.size[0], src.size[1], *size))
        if rule.get("levels"):
            m = src                     # grey levels are weights (a breast fading into the chest)
        else:
            cut = int(rule.get("threshold", 128))
            m = src.point(lambda v: 255 if v >= cut else 0)
        if "within" in rule:
            m = ImageChops.multiply(m, rule_mask(rule["within"], img))
    elif t == "union":
        m = Image.new("L", size, 0)
        for r in rule["rules"]:
            m = ImageChops.lighter(m, rule_mask(r, img))
    elif t == "subtract":
        rs = rule["rules"]
        m = rule_mask(rs[0], img)
        for r in rs[1:]:
            m = ImageChops.subtract(m, rule_mask(r, img))
    else:
        raise ValueError("unknown mask rule type %s" % t)
    g = int(rule.get("grow", 0))
    if g > 0:
        m = m.filter(ImageFilter.MaxFilter(g * 2 + 1 if g * 2 + 1 <= 51 else 51))
    fe = float(rule.get("feather", 0))
    if fe > 0:
        m = m.filter(ImageFilter.GaussianBlur(fe))
    return m


# ------------------------------------------------------------------ helpers
def bilinear(arr, x, y):
    h, w = arr.shape
    x = min(max(x, 0.0), w - 1.001)
    y = min(max(y, 0.0), h - 1.001)
    x0, y0 = int(x), int(y)
    fx, fy = x - x0, y - y0
    a = arr[y0, x0] * (1 - fx) + arr[y0, x0 + 1] * fx
    b = arr[y0 + 1, x0] * (1 - fx) + arr[y0 + 1, x0 + 1] * fx
    return a * (1 - fy) + b * fy


def write_import(path):
    ip = path + ".import"
    if os.path.exists(ip):
        t = open(ip).read()
        if "mipmaps/generate=true" in t:
            return
        open(ip, "w").write(t.replace("mipmaps/generate=false", "mipmaps/generate=true"))
        return
    res = "res://" + os.path.relpath(path, ROOT).replace(os.sep, "/")
    open(ip, "w").write(
        '[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n\n[deps]\n\nsource_file="%s"\n\n[params]\n\n'
        "compress/mode=0\ncompress/high_quality=false\ncompress/lossy_quality=0.7\ncompress/uastc_level=0\n"
        "compress/rdo_quality_loss=0.0\ncompress/hdr_compression=1\ncompress/normal_map=0\ncompress/channel_pack=0\n"
        "mipmaps/generate=true\nmipmaps/limit=-1\nroughness/mode=0\nroughness/src_normal=\"\"\n"
        "process/channel_remap/red=0\nprocess/channel_remap/green=1\nprocess/channel_remap/blue=2\n"
        "process/channel_remap/alpha=3\nprocess/fix_alpha_border=true\nprocess/premult_alpha=false\n"
        "process/normal_map_invert_y=false\nprocess/hdr_as_srgb=false\nprocess/hdr_clamp_exposure=false\n"
        "process/size_limit=0\ndetect_3d/compress_to=0\n" % res)


def default_spring(name):
    for pre, preset in DEFAULT_SPRING:
        if name.startswith(pre):
            return preset
    return ""


def spring_for(hero, name, spec):
    if spec is None:
        spec = default_spring(name)
    if spec in ("", "none"):
        return None
    bits = spec.split(";")
    preset = bits[0].strip()
    if preset not in PRESETS:
        err(hero, "bone %s: unknown spring preset %s" % (name, preset))
        return None
    s = dict(PRESETS[preset])
    for b in bits[1:]:
        if "=" in b:
            k, v = b.split("=", 1)
            s[k.strip()] = float(v)
    s["preset"] = preset
    return s


def look_for(name):
    for pre, f in LOOK_DEFAULTS:
        if name.startswith(pre):
            return list(f)
    return [0.0, 0.0]


def r1(v):
    return round(float(v), 1)


def tone_match(vimg, img, alpha, rect=None, pad=48):
    """A face variant (eyes closed, smile ...) from img2img drifts in skin tone: measure the drift
    where it barely differs from the base (not the lids or mouth it was made for), smooth it, and
    take it out everywhere, so swapping in its patch changes the features, not the face's colour."""
    from scipy import ndimage
    W, H = img.size
    if rect:
        x0, y0, w0, h0 = rect
        bx0, by0 = max(0, int(x0) - pad), max(0, int(y0) - pad)
        bx1, by1 = min(W, int(x0 + w0) + pad), min(H, int(y0 + h0) + pad)
    else:
        bx0, by0, bx1, by1 = 0, 0, W, H
    va = np.array(vimg).astype(np.float32)
    ba = np.array(img).astype(np.float32)
    v = va[by0:by1, bx0:bx1, :3]
    b = ba[by0:by1, bx0:bx1, :3]
    d = v - b
    calm = ((np.abs(d).max(axis=2) < 40) & (alpha[by0:by1, bx0:bx1] > 0.5)).astype(np.float32)
    den = ndimage.gaussian_filter(calm, 10.0) + 1e-3
    tone = np.stack([ndimage.gaussian_filter(d[..., c] * calm, 10.0) / den for c in range(3)], axis=2)
    tone *= np.clip(den[..., None] * 4.0, 0, 1)          # no estimate far from any calm pixel
    va[by0:by1, bx0:bx1, :3] = np.clip(v - tone, 0, 255)
    return Image.fromarray(va.astype(np.uint8), "RGBA")


# ------------------------------------------------------------------ format 2 mesh
# Blend width (px) at a part's edge by bone name: soft flesh blends wide, hair, wings and props
# stay crisp against what is behind them. A region's "soft" key overrides it.
SOFT_DEFAULT = [("face", 10), ("hair", 6), ("braid", 6), ("ponytail", 6), ("ahoge", 6), ("lock", 6), ("wing", 6),
                ("tail", 8), ("weapon", 4), ("prop", 4), ("halo", 4), ("horn", 4), ("ear", 6), ("breast", 14),
                ("thigh", 10), ("shin", 10), ("foot", 8), ("arm", 10), ("forearm", 10), ("hand", 8), ("skirt", 8),
                ("cape", 8), ("ribbon", 6), ("chest", 16), ("torso", 16), ("hips", 16), ("belly", 16),
                ("neck", 12), ("head", 12)]
# Parts a full-screen view may cut (the "core" rect leaves them out; RigData.core_rect).
CROPPABLE = ("wing", "tail", "weapon", "cape", "ribbon")
MAP_SCALE = 2          # weight maps at half resolution
# Depth for turns (RigPlayer head_turn / body_turn, docs/dev/halorig.md 11.5): per bone name,
# (base, bulge): a part sits at `base` (+ toward the viewer) and swells by `bulge` toward its middle
# (a pillow from its mask), so a turn slides the bangs over the face, the face over the skull and
# the back hair the other way. First match wins.
DEPTH_DEFAULT = [("iris", (0.9, 0.0)), ("face", (0.55, 0.45)), ("hair_front", (1.1, 0.1)), ("bangs", (1.1, 0.1)), ("hair_side", (0.45, 0.2)),
                 ("hair_back", (-0.6, 0.1)), ("hair_long", (-0.6, 0.1)), ("ponytail", (-0.5, 0.1)),
                 ("braid", (-0.3, 0.1)), ("ahoge", (0.3, 0.0)), ("ear", (-0.2, 0.1)), ("halo", (-0.45, 0.0)),
                 ("horn", (-0.1, 0.1)), ("head", (0.15, 0.5)), ("neck", (0.0, 0.2)), ("breast", (0.6, 0.5)),
                 ("chest", (0.3, 0.3)), ("torso", (0.25, 0.3)), ("belly", (0.3, 0.3)), ("hips", (0.2, 0.3)),
                 ("forearm", (0.15, 0.2)), ("arm", (0.1, 0.2)), ("hand", (0.15, 0.1)), ("thigh", (0.15, 0.25)),
                 ("shin", (0.1, 0.2)), ("foot", (0.1, 0.1)), ("wing", (-0.9, 0.1)), ("tail", (-0.6, 0.1)),
                 ("cape", (-0.7, 0.1)), ("skirt", (0.2, 0.2)), ("weapon", (0.0, 0.0)), ("earring", (-0.1, 0.0))]


def soft_for(bone, reg):
    if "soft" in reg:
        return float(reg["soft"])
    for p, v in SOFT_DEFAULT:
        if bone.startswith(p):
            return float(v)
    return 8.0


def compose_weights(regions, index, body, alpha):
    """Hard weight maps at half resolution: the region masks as drawn, composed in priority order
    (the first region takes its weight, later ones the rest, the body bone what is left). When a
    region claims the body bone itself (a "hips" mask), every painted pixel no mask covers takes the
    weights of the nearest claimed pixel instead: anti-aliased edges and stray feathers follow
    their part, not the hips. Returns (stack (K, h, w), keys = bone indices, blend width per bone,
    alpha at half resolution)."""
    from scipy import ndimage
    H, W = alpha.shape
    S = MAP_SCALE
    h2, w2 = H // S, W // S
    a2 = alpha[:h2 * S, :w2 * S].reshape(h2, S, w2, S).mean(axis=(1, 3))
    wmap = {}
    soft_of = {}
    rem = np.ones((h2, w2), np.float32)
    for reg in regions:
        m = reg["raw"][:h2 * S, :w2 * S].reshape(h2, S, w2, S).mean(axis=(1, 3))
        w = np.clip(m, 0.0, 1.0) * rem
        rem = rem - w
        b = index[reg["bone"]]
        wmap[b] = wmap.get(b, 0.0) + w
        soft_of[b] = max(soft_of.get(b, 0.0), soft_for(reg["bone"], reg.get("src", {})))
    bi = index[body]
    full = bi in wmap
    wmap[bi] = wmap.get(bi, 0.0) + rem
    soft_of.setdefault(bi, 16.0)
    keys = sorted(wmap)
    stack = np.stack([np.asarray(wmap[k], np.float32) * np.ones((h2, w2), np.float32) for k in keys])
    if full:
        un = (rem > 0.5) & (a2 > 0.05)
        if un.any() and not un.all():
            _, (iy, ix) = ndimage.distance_transform_edt(rem > 0.5, return_indices=True)
            stack[:, un] = stack[:, iy[un], ix[un]]
    return stack, keys, soft_of, a2


def own_stack(regions, keys, index, a2, parts, rest=None):
    """A layer's own weights (layer "weights": "own"): only the regions of its own parts (bone name
    prefixes), in priority order, so no other layer's part reaches into it (hair behind an arm stays
    on the hair). What none of them covers takes the weights of the nearest covered pixel, or goes
    to the `rest` bone. Same keys as the shared stack (the turn maps line up). Returns the stack."""
    from scipy import ndimage
    S = MAP_SCALE
    h2, w2 = a2.shape
    st = np.zeros((len(keys), h2, w2), np.float32)
    rem = np.ones((h2, w2), np.float32)
    for reg in regions:
        if not reg["bone"].startswith(tuple(parts)) or index[reg["bone"]] not in keys:
            continue
        m = reg["raw"][:h2 * S, :w2 * S].reshape(h2, S, w2, S).mean(axis=(1, 3))
        w = np.clip(m, 0.0, 1.0) * rem
        rem = rem - w
        st[keys.index(index[reg["bone"]])] += w
    if rest is not None:
        st[keys.index(index[rest])] += rem
    else:
        cov = rem < 0.5
        if cov.any() and not cov.all():
            _, (iy, ix) = ndimage.distance_transform_edt(~cov, return_indices=True)
            st[:, ~cov] = st[:, iy[~cov], ix[~cov]]
    st /= np.maximum(st.sum(axis=0, keepdims=True), 1e-6)
    return st


def core_rect(stack, keys, a2, index, ox, oy):
    """Her body without the croppable parts (the largest connected piece), rig space."""
    from scipy import ndimage
    S = MAP_SCALE
    names = {v: k for k, v in index.items()}
    crop = [i for i, k in enumerate(keys) if names[k].startswith(CROPPABLE)]
    cropw = stack[crop].sum(axis=0) if crop else np.zeros_like(a2)
    bodyish = ndimage.binary_opening((a2 > 0.5) & (cropw < 0.5), iterations=2)
    lab, nlab = ndimage.label(bodyish)
    if nlab:
        sizes = ndimage.sum(bodyish, lab, range(1, nlab + 1))
        bodyish = lab == (int(np.argmax(sizes)) + 1)
    cy, cx = np.nonzero(bodyish)
    if len(cx) == 0:
        cy, cx = np.nonzero(a2 > 0.5)
    qx0, qx1 = np.percentile(cx, [0.1, 99.9]) * S
    qy0, qy1 = np.percentile(cy, [0.1, 99.9]) * S
    return [r1(qx0 - ox), r1(qy0 - oy), r1(qx1 - qx0 + S), r1(qy1 - qy0 + S)]


def depth_for(bone):
    for p, v in DEPTH_DEFAULT:
        if bone.startswith(p):
            return v
    return (0.0, 0.2)


def turn_maps(stack, keys, index, bones_parent, a2):
    """Per bone at half resolution: its depth map (base + bulge * sqrt(distance into its own mask /
    the mask's deepest point)) and whether it turns with the head (the head bone and every bone
    below it) or with the body (the rest; legs fade out from the hips down, planted shins not at
    all). Returns (depth stack, head flag per key, body flag per key)."""
    from scipy import ndimage
    names = {v: k for k, v in index.items()}

    def under(n, top):
        while n:
            if n == top:
                return True
            n = bones_parent.get(n, "")
        return False
    dep = np.zeros_like(stack)
    head_k = np.zeros(len(keys), np.float32)
    body_k = np.zeros(len(keys), np.float32)
    for k, b in enumerate(keys):
        nm = names[b]
        base, bulge = depth_for(nm)
        m = stack[k] > 0.5
        if m.any():
            dist = ndimage.distance_transform_edt(m)
            mx = max(float(dist.max()), 1.0)
            dep[k] = base + bulge * np.sqrt(np.clip(dist / mx, 0, 1))
        else:
            dep[k] = base
        if under(nm, "head"):
            head_k[k] = 1.0
        elif nm != "root" and not (bones_parent.get(nm, "") == "root" and nm != "hips"):
            body_k[k] = 1.0              # planted bones (on root: shins, feet) stay out of turns
    return dep, head_k, body_k


def layer_mesh(hero, src, stack, keys, soft_of, index, body, lay_alpha, image_rect, ox, oy, name, image, z,
               native=None, rigid=None, turn=None):
    """One format 2 layer: a `cell` px grid (default 12) over the layer's paint, four influences per
    grid point. The layer's own painted pixels (`native`: painted in the original, not filled in)
    keep their weights; everything else in the layer (transparent margins, painted-in hidden parts
    such as wing roots behind the body) takes the weights of the nearest native pixel, so an outline
    moves with its part and a hidden root moves with its wing. Then parts blend where they meet,
    each by its blend width, and each grid point takes the weights of the paint around it.
    `rigid`: every point follows that one bone (a prop). Returns (layer json, grid rect, n, tris)."""
    import base64
    import zlib
    from scipy import ndimage
    H, W = lay_alpha.shape
    S = MAP_SCALE
    h2, w2 = H // S, W // S
    cell = int(src.get("cell", 12))
    la2 = lay_alpha[:h2 * S, :w2 * S].reshape(h2, S, w2, S).mean(axis=(1, 3))
    st = stack.copy()
    if rigid is None:
        own = la2 > 0.35
        if native is not None:
            own &= native
        if own.any() and not own.all():
            iy, ix = ndimage.distance_transform_edt(~own, return_distances=False, return_indices=True)
            st = st[:, iy, ix]
        for k, b in enumerate(keys):
            sg = soft_of.get(b, 8.0) / S * 0.5
            if sg > 0.3:
                st[k] = ndimage.gaussian_filter(st[k], sg)
        st /= np.maximum(st.sum(axis=0, keepdims=True), 1e-6)
        sig = cell / S * 0.6
        den = ndimage.gaussian_filter(la2, sig)
        held = den > 0.02
        for k in range(len(keys)):
            sm = ndimage.gaussian_filter(st[k] * la2, sig) / np.maximum(den, 1e-4)
            st[k] = np.where(held, sm, st[k])
    ys, xs = np.nonzero(lay_alpha > 0.0)
    if len(xs) == 0:
        err(hero, "layer %s is empty" % name)
        return None, (0, 0, 0, 0), 0, 0
    x0 = max(0, int(xs.min()) - cell)
    y0 = max(0, int(ys.min()) - cell)
    cols = int(math.ceil((min(W, int(xs.max()) + 1 + cell) - x0) / cell))
    rows = int(math.ceil((min(H, int(ys.max()) + 1 + cell) - y0) / cell))
    pad = np.zeros((rows * cell, cols * cell), np.float32)
    sub = lay_alpha[y0:y0 + rows * cell, x0:x0 + cols * cell]
    pad[:sub.shape[0], :sub.shape[1]] = sub
    keep = pad.reshape(rows, cell, cols, cell).max(axis=(1, 3)) > 0.0
    used = np.zeros((rows + 1, cols + 1), bool)
    used[:-1, :-1] |= keep
    used[:-1, 1:] |= keep
    used[1:, :-1] |= keep
    used[1:, 1:] |= keep
    jj, ii = np.nonzero(used)                       # row by row, as RigData._load_layer numbers them
    px = x0 + ii * cell
    py = y0 + jj * cell
    nv = len(px)
    bi = index[body]
    skin = np.zeros((nv, 8), np.uint8)
    if rigid is not None:
        skin[:, 0] = index[rigid]
        skin[:, 1] = 255
        for k in range(1, 4):
            skin[:, k * 2] = bi
    else:
        coords = np.array([np.clip(py / S - 0.5, 0, h2 - 1), np.clip(px / S - 0.5, 0, w2 - 1)])
        wv = np.stack([ndimage.map_coordinates(st[k], coords, order=1, mode="nearest") for k in range(len(keys))], axis=1)
        kb = np.array(keys)
        body_col = keys.index(bi)
        wv_nb = wv.copy()
        wv_nb[:, body_col] = -1.0                    # the body bone takes the remainder
        top = np.argsort(-wv_nb, axis=1)[:, :4]
        for k in range(min(4, top.shape[1])):
            col = top[:, k]
            w = np.clip(wv[np.arange(nv), col], 0.0, 1.0)
            w = np.where(col == body_col, 0.0, w)
            skin[:, k * 2] = np.where(w > 0.0, kb[col], bi).astype(np.uint8)
            skin[:, k * 2 + 1] = np.round(w * 255).astype(np.uint8)
        for k in range(top.shape[1], 4):
            skin[:, k * 2] = bi
        tot = skin[:, 1::2].astype(np.int32).sum(axis=1)
        over = tot > 255
        if over.any():
            f = 255.0 / tot[over]
            for k in range(4):
                skin[over, k * 2 + 1] = np.floor(skin[over, k * 2 + 1] * f).astype(np.uint8)
        if max(keys) > 255:
            err(hero, "more than 255 bones")
    lj = {"name": name, "image": image, "z": int(z),
          "mesh": {"cell": cell, "rect": [x0, y0, cols, rows], "n": int(nv),
                   "cells": base64.b64encode(zlib.compress(keep.astype(np.uint8).tobytes(), 9)).decode(),
                   "skin": base64.b64encode(zlib.compress(skin.tobytes(), 9)).decode()}}
    if turn is not None:
        # per grid point: depth (byte = depth * 100 + 128), share of the head turn, of the body turn
        dep, head_k, body_k = turn[:3]
        coords = np.array([np.clip(py / S - 0.5, 0, h2 - 1), np.clip(px / S - 0.5, 0, w2 - 1)])
        if rigid is not None:
            ki = keys.index(index[rigid])
            dv = ndimage.map_coordinates(dep[ki], coords, order=1, mode="nearest")
            th = np.full(nv, head_k[ki])
            tb = np.full(nv, body_k[ki])
        else:
            wsum = np.maximum(wv.sum(axis=1), 1e-6)
            dmap = np.stack([ndimage.map_coordinates(dep[k], coords, order=1, mode="nearest") for k in range(len(keys))], axis=1)
            dv = (wv * dmap).sum(axis=1) / wsum
            th = (wv * head_k[None, :]).sum(axis=1) / wsum
            tb = (wv * body_k[None, :]).sum(axis=1) / wsum
        # the body turn fades out down the legs (hips full, knees none)
        hy = turn[3] if len(turn) > 3 else None
        if hy is not None:
            fade = np.clip(1.0 - (py - hy[0]) / max(hy[1] - hy[0], 1.0), 0.0, 1.0)
            tb = tb * fade
        tbytes = np.zeros((nv, 4), np.uint8)
        tbytes[:, 0] = np.clip(np.round(dv * 100 + 128), 0, 255).astype(np.uint8)
        tbytes[:, 1] = np.clip(np.round(th * 255), 0, 255).astype(np.uint8)
        tbytes[:, 2] = np.clip(np.round(tb * 255), 0, 255).astype(np.uint8)
        lj["mesh"]["turn"] = base64.b64encode(zlib.compress(tbytes.tobytes(), 9)).decode()
    if image_rect is not None:
        lj["image_rect"] = [int(v) for v in image_rect]
    return lj, (x0, y0, min(W, x0 + cols * cell), min(H, y0 + rows * cell)), int(nv), int(keep.sum()) * 2


def mesh_v2(hero, src, img, alpha, regions, index, body, ox, oy, image_name, hdir):
    """Format 2 layers (docs/dev/halorig.md 11). Without "layers" in the source: one layer, the
    painting. With them (tools/art_layers.py peels the art apart): each layer's image (cropped to
    `image_rect` on the canvas), its own mesh; `parts` (bone name prefixes, or "rest") says which of
    the painting's parts the layer holds, `bone` makes it a rigid prop. Returns (layers json, core
    rect, grid bounds in image px, vertices, triangles)."""
    from scipy import ndimage
    stack, keys, soft_of, a2 = compose_weights(regions, index, body, alpha)
    core = core_rect(stack, keys, a2, index, ox, oy)
    parents = {b["name"]: b.get("parent", "root") for b in src.get("bones", [])}
    parents["root"] = ""
    dep, head_k, body_k = turn_maps(stack, keys, index, parents, a2)
    # where the body turn fades on the legs: from the hips' pivot down to the knees (shin pivots)
    piv = {b["name"]: b["pivot"] for b in src.get("bones", []) if "pivot" in b}
    hy0 = float(piv.get("hips", [0, oy - 700])[1])
    knees = [float(v[1]) for k, v in piv.items() if k.startswith("shin")]
    hy1 = min(knees) if knees else hy0 + 300.0
    turn = (dep, head_k, body_k, (hy0, max(hy1, hy0 + 50.0)))
    names = {v: k for k, v in index.items()}
    dom = np.array(keys)[np.argmax(stack, axis=0)]
    specs = src.get("layers") or [{"name": "base", "image": image_name, "z": 0}]
    claimed = []
    for ls in specs:
        p = ls.get("parts")
        if isinstance(p, list):
            claimed += p
    out, nv_all, nt_all = [], 0, 0
    bx0 = by0 = 10 ** 9
    bx1 = by1 = 0
    H, W = alpha.shape
    for ls in specs:
        lp = os.path.join(hdir, ls["image"])
        if not os.path.exists(lp):
            err(hero, "layer %s: missing %s (tools/art_layers.py makes it)" % (ls["name"], ls["image"]))
            return None, None, (0, 0, 0, 0), 0, 0
        limg = Image.open(lp).convert("RGBA")
        ir = ls.get("image_rect")
        lay_alpha = np.zeros((H, W), np.float32)
        la = np.array(limg.split()[3]).astype(np.float32) / 255.0
        if ir:
            x, y = int(ir[0]), int(ir[1])
            lay_alpha[y:y + la.shape[0], x:x + la.shape[1]] = la[:H - y, :W - x]
        else:
            lay_alpha[:la.shape[0], :la.shape[1]] = la
        native = None
        p = ls.get("parts")
        lstack = stack
        if ls.get("weights") == "own" and isinstance(p, list):
            # only this layer's own parts weight it (see own_stack); every painted pixel is its own
            rest = ls.get("rest_bone")
            if rest is not None and (rest not in index or index[rest] not in keys):
                err(hero, "layer %s: rest_bone %s has no region" % (ls["name"], rest))
                return None, None, (0, 0, 0, 0), 0, 0
            lstack = own_stack(regions, keys, index, a2, p, rest)
        elif p is not None:
            if p == "rest":
                native = ~np.isin(dom, [k for k in keys if names[k].startswith(tuple(claimed))])
            else:
                native = np.isin(dom, [k for k in keys if names[k].startswith(tuple(p))])
            native &= a2 > 0.35
        lsrc = dict(src, cell=int(ls["cell"])) if "cell" in ls else src     # a layer may use a finer grid
        lj, (x0, y0, x1, y1), nv, nt = layer_mesh(hero, lsrc, lstack, keys, soft_of, index, body, lay_alpha,
                                                  ir, ox, oy, ls["name"], ls["image"], ls.get("z", 0),
                                                  native=native, rigid=ls.get("bone"), turn=turn)
        if lj is None:
            return None, None, (0, 0, 0, 0), 0, 0
        out.append(lj)
        nv_all += nv
        nt_all += nt
        bx0, by0, bx1, by1 = min(bx0, x0), min(by0, y0), max(bx1, x1), max(by1, y1)
    _ = ndimage
    return out, core, (bx0, by0, bx1, by1), nv_all, nt_all


# ------------------------------------------------------------------ build
def rig_dir(rig_id):
    """(folder, file name, hero id) of a rig id: <id> (base art), <id>@<art> (a skin),
    <id>@<art>@adult (the skin's nude art in skins/<art>/adult/, files still named <art>.*) or
    <id>@@adult (the base look's nude art in <id>/adult/, files still named <id>.*).
    The game's RigData art strings for the same folders: "", "<art>", "<art>/adult", "/adult"."""
    hero_id, _, art = rig_id.partition("@")
    art, _, variant = art.partition("@")
    d = os.path.join(HEROES, hero_id, "skins", art) if art else os.path.join(HEROES, hero_id)
    return (os.path.join(d, variant) if variant else d), art or hero_id, hero_id


def build(hero, regen=False, check=False):
    hdir, name, hero_id = rig_dir(hero)      # `hero` stays the label in messages (<id> or <id>@<art>)
    src_path = os.path.join(hdir, name + ".warp_src.json")
    if not os.path.exists(src_path):
        err(hero, "missing " + src_path)
        return
    src = json.load(open(src_path))
    img_path = os.path.join(hdir, src.get("image", name + ".png"))
    if not os.path.exists(img_path):
        err(hero, "missing image " + img_path)
        return
    img = Image.open(img_path).convert("RGBA")
    W, H = img.size
    alpha = np.array(img.split()[3]).astype(np.float32) / 255.0
    ox, oy = src.get("origin", [W / 2, H - 58])
    cols, rows = src.get("grid", [24, 48])
    texel = float(src.get("texel_scale", 1.0))

    # ---- bones
    bones = [{"name": "root", "parent": "", "pivot": [ox, oy]}] + [b for b in src.get("bones", []) if b["name"] != "root"]
    index = {}
    for i, b in enumerate(bones):
        if b["name"] in index:
            err(hero, "duplicate bone %s" % b["name"])
        index[b["name"]] = i
    for b in bones[1:]:
        if b.get("parent", "root") not in index:
            err(hero, "bone %s: unknown parent %s" % (b["name"], b.get("parent")))
        if "pivot" not in b:
            err(hero, "bone %s: missing pivot" % b["name"])
    order = []
    seen = set()

    def visit(n, stack=()):
        if n in seen:
            return
        if n in stack:
            err(hero, "bone cycle at %s" % n)
            return
        b = bones[index[n]]
        p = b.get("parent", "root") if n != "root" else ""
        if p and p in index:
            visit(p, stack + (n,))
        seen.add(n)
        order.append(n)
    for b in bones:
        visit(b["name"])
    bones = [bones[index[n]] for n in order]
    index = {b["name"]: i for i, b in enumerate(bones)}
    body = src.get("body_bone", "hips" if "hips" in index else "root")
    if body not in index:
        err(hero, "body_bone %s is not a bone" % body)
        body = "root"

    # ---- region masks (priority order: first listed wins where masks overlap)
    os.makedirs(os.path.join(hdir, "masks"), exist_ok=True)
    set_mask_context(hdir, img)
    gi = os.path.join(hdir, "masks", ".gdignore")
    if not os.path.exists(gi):
        open(gi, "w").close()
    regions = []
    for r in src.get("regions", []):
        rname = r["name"]       # not `name`: that is the rig's file name, used for the outputs below
        bone = r.get("bone", rname)
        if bone not in index:
            err(hero, "region %s: unknown bone %s" % (rname, bone))
            continue
        mp = os.path.join(hdir, r.get("mask", "masks/%s.png" % rname))
        # format 2: masks always come from the rules (SAM masks are cached by tools/art_parts.py)
        if "rule" in r and (regen or int(src.get("version", 1)) >= 2 or not os.path.exists(mp)):
            m = rule_mask(r["rule"], img)
            if not check:
                m.save(mp)
        elif os.path.exists(mp):
            m = Image.open(mp).convert("L")
            if m.size != img.size:
                err(hero, "mask %s is %s, image is %s" % (mp, m.size, img.size))
                continue
        else:
            err(hero, "region %s: no mask file and no rule" % rname)
            continue
        cell = max(W / cols, H / rows)
        arr = np.array(m.filter(ImageFilter.GaussianBlur(cell * 0.25))).astype(np.float32) / 255.0
        if arr.max() <= 0.01:
            warn(hero, "region %s mask is empty" % rname)
        regions.append({"name": rname, "bone": bone, "arr": arr, "raw": np.array(m).astype(np.float32) / 255.0, "src": r})

    version = int(src.get("version", 1))
    if version >= 2 and not check:
        # masks of regions this source no longer has (an older rig's) would only mislead
        want = {os.path.basename(r.get("mask", "masks/%s.png" % r["name"])) for r in src.get("regions", [])}
        for f in os.listdir(os.path.join(hdir, "masks")):
            if f.endswith(".png") and f not in want:
                os.remove(os.path.join(hdir, "masks", f))
    if version >= 2:
        # format 2 (docs/dev/halorig.md section 11): a fine grid, weights from the part masks
        layers_json, core, (bx0, by0, bx1, by1), nv, nt = mesh_v2(hero, src, img, alpha, regions, index, body, ox, oy, os.path.basename(img_path), hdir)
        if layers_json is None:
            return
    else:
        # ---- grid over the alpha bounds (+ margin), culling fully transparent cells
        ys, xs = np.nonzero(alpha > 0.02)
        if len(xs) == 0:
            err(hero, "image is fully transparent")
            return
        pad = 24
        bx0, by0 = max(0, xs.min() - pad), max(0, ys.min() - pad)
        bx1, by1 = min(W, xs.max() + pad), min(H, ys.max() + pad)
        gx = np.linspace(bx0, bx1, cols + 1)
        gy = np.linspace(by0, by1, rows + 1)
        keep_cell = np.zeros((rows, cols), bool)
        for j in range(rows):
            for i in range(cols):
                x0, x1 = int(gx[i]), int(math.ceil(gx[i + 1]))
                y0, y1 = int(gy[j]), int(math.ceil(gy[j + 1]))
                if alpha[y0:y1 + 1, x0:x1 + 1].max() > 0.0:
                    keep_cell[j, i] = True
        vid = -np.ones((rows + 1, cols + 1), int)
        verts, uvs, skin = [], [], []
        for j in range(rows + 1):
            for i in range(cols + 1):
                used = any(keep_cell[jj, ii] for jj in (j - 1, j) for ii in (i - 1, i) if 0 <= jj < rows and 0 <= ii < cols)
                if not used:
                    continue
                vid[j, i] = len(verts) // 2
                x, y = gx[i], gy[j]
                verts += [r1((x - ox) / 1.0), r1((y - oy) / 1.0)]
                uvs += [round(x / W, 5), round(y / H, 5)]
                # skin weights: priority composition, keep the strongest MAX_INFLUENCES
                remaining = 1.0
                infl = []
                for reg in regions:
                    w = bilinear(reg["arr"], x, y) * remaining
                    if w > 0.004:
                        infl.append((index[reg["bone"]], w))
                        remaining -= w
                infl.sort(key=lambda t: -t[1])
                infl = infl[:MAX_INFLUENCES]
                tot = sum(w for _, w in infl)
                if tot > 1.0:
                    infl = [(b, w / tot) for b, w in infl]
                while len(infl) < MAX_INFLUENCES:
                    infl.append((index[body], 0.0))
                for b, w in infl:
                    skin += [b, round(w, 4)]
        tris = []
        for j in range(rows):
            for i in range(cols):
                if keep_cell[j, i]:
                    a, b2, c, d = vid[j, i], vid[j, i + 1], vid[j + 1, i + 1], vid[j + 1, i]
                    tris += [int(a), int(b2), int(c), int(a), int(c), int(d)]

    # ---- bones json (pivots in rig units; axis/length from the region masks for springs)
    bones_json = []
    for b in bones:
        n = b["name"]
        piv = b["pivot"] if n != "root" else [ox, oy]
        par = b.get("parent", "root") if n != "root" else ""
        ppiv = bones[index[par]]["pivot"] if par else [ox, oy]
        if par == "root":
            ppiv = [ox, oy]
        bj = {"name": n, "parent": par, "x": r1(piv[0] - ox), "y": r1(piv[1] - oy),
              "lx": r1(piv[0] - ppiv[0]), "ly": r1(piv[1] - ppiv[1])}
        axis, length = [0.0, 1.0], 0.0
        regs = [r for r in regions if r["bone"] == n]
        if regs:
            m = np.zeros_like(alpha)
            for r in regs:
                m = np.maximum(m, r["raw"])
            m = m * (alpha > 0.1)
            yy, xx = np.nonzero(m[::4, ::4] > 0.5)
            if len(xx):
                xx = xx * 4 - piv[0]
                yy = yy * 4 - piv[1]
                cx, cy = xx.mean(), yy.mean()
                ln = math.hypot(cx, cy)
                if ln > 1:
                    axis = [cx / ln, cy / ln]
                length = float(max((xx * axis[0] + yy * axis[1]).max(), 0))
        if "axis" in b:
            a = b["axis"]
            ln = math.hypot(a[0], a[1]) or 1
            axis = [a[0] / ln, a[1] / ln]
        if "length" in b:
            length = float(b["length"])
        bj["axis"] = [round(axis[0], 3), round(axis[1], 3)]
        bj["length"] = r1(length)
        sp = spring_for(hero, n, b.get("spring")) if n != "root" else None
        if sp:
            if length < 8:
                warn(hero, "bone %s has a spring but no region to measure; set length" % n)
            bj["spring"] = sp
        if "bend" in b:
            bj["bend"] = float(b["bend"])
        lk = b.get("look", look_for(n))
        if lk[0] or lk[1]:
            bj["look"] = lk
        if "tip" in b:
            bj["tip"] = [r1(b["tip"][0] - piv[0]), r1(b["tip"][1] - piv[1])]
        if "grip" in b:
            # a held prop: RigPlayer keeps the point `at` (image px) in the hand bone's grip
            g = b["grip"]
            if g.get("bone") not in index:
                err(hero, "bone %s: grip bone %s is not a bone" % (n, g.get("bone")))
            else:
                bj["grip"] = {"bone": g["bone"], "at": [r1(g["at"][0] - ox), r1(g["at"][1] - oy)]}
        bones_json.append(bj)

    # ---- overlays: variant images -> feathered patches where they differ from the base
    slots = []
    if not check:
        os.makedirs(os.path.join(hdir, "overlays"), exist_ok=True)
    for ov in src.get("overlays", []):
        slot = ov["slot"]
        bone = ov.get("bone", "head")
        if bone not in index:
            err(hero, "overlay %s: unknown bone %s" % (slot, bone))
            continue
        base_v = ov.get("base", "default")
        atts = {base_v: {}}
        for vname, vpath in ov.get("variants", {}).items():
            vp = os.path.join(hdir, vpath)
            if not os.path.exists(vp):
                err(hero, "overlay %s/%s: missing %s" % (slot, vname, vp))
                continue
            vimg = Image.open(vp).convert("RGBA")
            if vimg.size != img.size:
                err(hero, "overlay %s/%s: size %s differs from the image %s" % (slot, vname, vimg.size, img.size))
                continue
            vimg = tone_match(vimg, img, alpha, ov.get("rect"))
            diff = np.abs(np.array(vimg).astype(np.int32) - np.array(img).astype(np.int32)).max(axis=2)
            if "rect" in ov:
                x0, y0, w0, h0 = ov["rect"]
                region = np.zeros_like(diff)
                region[int(y0):int(y0 + h0), int(x0):int(x0 + w0)] = 1
                diff = diff * region
            yy, xx = np.nonzero(diff > int(ov.get("threshold", 24)))
            if len(xx) == 0:
                warn(hero, "overlay %s/%s: identical to the base image" % (slot, vname))
                continue
            m = int(ov.get("margin", 10))
            x0, y0 = max(0, xx.min() - m), max(0, yy.min() - m)
            x1, y1 = min(W, xx.max() + m + 1), min(H, yy.max() + m + 1)
            patch = vimg.crop((x0, y0, x1, y1))
            # only where the variant really differs (the lids, the mouth), feathered, and faded out
            # toward the patch border: a blink fades the lids, not a rectangle of skin
            pa = np.array(patch).astype(np.float32)
            ph, pw = pa.shape[:2]
            from scipy import ndimage
            dz = diff[y0:y1, x0:x1] > int(ov.get("threshold", 24))
            dz = ndimage.binary_dilation(dz, iterations=4)
            soft = np.clip(ndimage.gaussian_filter(dz.astype(np.float32), 3.0) * 1.6, 0, 1)
            fy = np.minimum(np.arange(ph), np.arange(ph)[::-1])[:, None]
            fx = np.minimum(np.arange(pw), np.arange(pw)[::-1])[None, :]
            ramp = np.clip(np.minimum(fx, fy) / max(1.0, m * 0.8), 0, 1)
            pa[..., 3] *= ramp * soft
            fname = "overlays/%s_%s.png" % (slot, vname)
            if not check:
                Image.fromarray(pa.astype(np.uint8), "RGBA").save(os.path.join(hdir, fname))
                write_import(os.path.join(hdir, fname))
            atts[vname] = {"texture": fname, "x": r1(x0 - ox), "y": r1(y0 - oy), "w": int(x1 - x0), "h": int(y1 - y0)}
        slots.append({"name": slot, "bone": bone, "z": int(ov.get("z", 10 + len(slots))), "default": ov.get("default", base_v),
                      "attachments": atts})

    slots.sort(key=lambda sl: sl["z"])
    # ---- portrait + json
    pc = src.get("portrait", [ox, oy - 1700, 480])
    prect = [pc[0] - pc[2] / 2, pc[1] - pc[2] / 2, pc[2], pc[2]]
    meta = dict(src.get("meta", {}))
    out = {"format": "halowarp", "version": FORMAT_VERSION if version < 2 else 2, "id": hero_id,
           "image": os.path.basename(img_path) if texel == 1.0 else "%s_warp.png" % name,
           "image_size": [W, H], "canvas": [W, H], "origin": [ox, oy], "texel_scale": texel,
           "look_px": src.get("look_px", [14, 8]), "still": os.path.basename(img_path), "portrait": "%s_portrait.png" % name,
           "portrait_rect": prect, "bounds": [r1(bx0 - ox), r1(by0 - oy), r1(bx1 - bx0), r1(by1 - by0)],
           "meta": meta, "body_bone": body, "max_influences": MAX_INFLUENCES,
           "bones": bones_json, "slots": slots}
    ik = []
    for c in src.get("ik", []):
        # two-bone IK (RigPlayer): upper and lower reach for the target bone's pivot (an ankle)
        names_ok = all(c.get(k) in index for k in ("upper", "lower", "target"))
        if not names_ok or index[c["target"]] > index[c["upper"]]:
            err(hero, "ik %s: needs known bones, the target solved before the upper bone" % c)
            continue
        ik.append({"upper": c["upper"], "lower": c["lower"], "target": c["target"],
                   "knee_room": float(c.get("knee_room", 12.0))})
        if c.get("foot") in index:
            ik[-1]["foot"] = c["foot"]          # held at the target's angle (flat on the floor)
    if ik:
        out["ik"] = ik
    if version >= 2:
        out["max_influences"] = 4
        out["core"] = core
        out["layers"] = layers_json
    else:
        out["mesh"] = {"grid": [cols, rows], "vertices": verts, "uvs": uvs, "triangles": tris, "skin": skin}
        nv, nt = len(verts) // 2, len(tris) // 3
    if check:
        print("art_warp_build: [%s] check ok: %d bones, %d regions, %d vertices, %d triangles" % (hero, len(bones_json), len(regions), nv, nt))
        return
    if texel != 1.0:
        img.resize((int(W * texel), int(H * texel)), Image.LANCZOS).save(os.path.join(hdir, out["image"]))
        write_import(os.path.join(hdir, out["image"]))
    write_import(img_path)
    sc = PORTRAIT_PX / pc[2]
    por = img.crop((int(prect[0]), int(prect[1]), int(prect[0] + prect[2]), int(prect[1] + prect[3])))
    por.resize((PORTRAIT_PX, PORTRAIT_PX), Image.LANCZOS).save(os.path.join(hdir, out["portrait"]))
    write_import(os.path.join(hdir, out["portrait"]))
    for sub in ("variants",):
        p = os.path.join(hdir, sub)
        if os.path.isdir(p) and not os.path.exists(os.path.join(p, ".gdignore")):
            open(os.path.join(p, ".gdignore"), "w").close()
    json.dump(out, open(os.path.join(hdir, name + ".warp.json"), "w"), separators=(",", ":"))
    print("art_warp_build: [%s] %d bones, %d regions, %d overlay slots, %d vertices, %d triangles" % (
        hero, len(bones_json), len(regions), len(slots), nv, nt))
    _ = sc


def main():
    args = sys.argv[1:]
    regen = "--regen-masks" in args
    check = "--check" in args
    ids = [a for a in args if not a.startswith("--")]
    if not ids:
        for d in sorted(os.listdir(HEROES)):
            if os.path.exists(os.path.join(HEROES, d, d + ".warp_src.json")):
                ids.append(d)
            if os.path.exists(os.path.join(HEROES, d, "adult", d + ".warp_src.json")):
                ids.append("%s@@adult" % d)
            sk = os.path.join(HEROES, d, "skins")
            for art in sorted(os.listdir(sk)) if os.path.isdir(sk) else []:
                if os.path.exists(os.path.join(sk, art, art + ".warp_src.json")):
                    ids.append("%s@%s" % (d, art))
                if os.path.exists(os.path.join(sk, art, "adult", art + ".warp_src.json")):
                    ids.append("%s@%s@adult" % (d, art))
    for h in ids:
        build(h, regen, check)
    print("art_warp_build: %d hero(es), %d error(s), %d warning(s)" % (len(ids), errors, warnings))
    sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()
