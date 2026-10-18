"""HaloRig WARP build: one painted illustration -> <id>.warp.json (grid mesh + bone skin
weights from region masks + overlay patches), portrait, imports.  Spec: docs/dev/halorig.md.

    python3 tools/art_warp_build.py seraphiel [--regen-masks] [--check]
    tools/art_warp seraphiel            # same, then Godot import (use this one)
    tools/art_warp imra@lucky_ember     # a skin: assets/art/heroes/imra/skins/lucky_ember/, files named
                                        # lucky_ember.* (the folder RigData.load_rig(hero, art) reads)

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
    Common keys: "grow": px dilation, "feather": px blur radius."""
    size = img.size
    t = rule.get("type", "polygon")
    if t == "polygon":
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


# ------------------------------------------------------------------ build
def rig_dir(rig_id):
    """(folder, file name, hero id) of a rig id: <id> (base art) or <id>@<art> (a skin)."""
    hero_id, _, art = rig_id.partition("@")
    if art:
        return os.path.join(HEROES, hero_id, "skins", art), art, hero_id
    return os.path.join(HEROES, hero_id), hero_id, hero_id


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
        if "rule" in r and (regen or not os.path.exists(mp)):
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
        regions.append({"name": rname, "bone": bone, "arr": arr, "raw": np.array(m).astype(np.float32) / 255.0})

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
            # feather the patch border so it blends into the base
            pa = np.array(patch).astype(np.float32)
            ph, pw = pa.shape[:2]
            fy = np.minimum(np.arange(ph), np.arange(ph)[::-1])[:, None]
            fx = np.minimum(np.arange(pw), np.arange(pw)[::-1])[None, :]
            ramp = np.clip(np.minimum(fx, fy) / max(1.0, m * 0.8), 0, 1)
            pa[..., 3] *= ramp
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
    out = {"format": "halowarp", "version": FORMAT_VERSION, "id": hero_id,
           "image": os.path.basename(img_path) if texel == 1.0 else "%s_warp.png" % name,
           "image_size": [W, H], "canvas": [W, H], "origin": [ox, oy], "texel_scale": texel,
           "look_px": src.get("look_px", [14, 8]), "still": os.path.basename(img_path), "portrait": "%s_portrait.png" % name,
           "portrait_rect": prect, "bounds": [r1(bx0 - ox), r1(by0 - oy), r1(bx1 - bx0), r1(by1 - by0)],
           "meta": meta, "body_bone": body, "max_influences": MAX_INFLUENCES,
           "bones": bones_json, "slots": slots,
           "mesh": {"grid": [cols, rows], "vertices": verts, "uvs": uvs, "triangles": tris, "skin": skin}}
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
            sk = os.path.join(HEROES, d, "skins")
            for art in sorted(os.listdir(sk)) if os.path.isdir(sk) else []:
                if os.path.exists(os.path.join(sk, art, art + ".warp_src.json")):
                    ids.append("%s@%s" % (d, art))
    for h in ids:
        build(h, regen, check)
    print("art_warp_build: %d hero(es), %d error(s), %d warning(s)" % (len(ids), errors, warnings))
    sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()
