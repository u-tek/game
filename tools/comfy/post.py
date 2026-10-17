#!/usr/bin/env python3
"""Post-processing for generated hero art (PIL + numpy only).

    remove_background(img)        flat-background cutout: flood fill from the borders with colour
                                  tolerance (against a fitted background surface, so gentle gradients
                                  and vignettes are fine), enclosed background holes, foreground/background
                                  unmixing for anti-aliased edges, alpha feathering, colour despill
    alpha_from_mask(img, mask)    same edge treatment for a mask from a ComfyUI background-removal node
    place_on_canvas(rgba)         trim, scale and place on the 1024x2048 canvas, feet at y=1990, body
                                  axis centred at x=512 (shifted only if the figure would leave the canvas)
    estimate_face_box(rgba)       heuristic face box (skin colour + body proportions)
    portrait(canvas, face_box)    square head-and-shoulders crop
    contact_sheet(entries, out)   labelled grid of candidates (full body + face detail) for review

CLI:
    post.py cutout IN.png OUT.png [--bg R,G,B] [--tol 26] [--no-holes]
    post.py place IN_RGBA.png OUT.png
    post.py finalize HERO IN.png [--face-box x,y,w,h] [--out-dir DIR]    local cutout+place+portrait (no server)
    post.py facebox IN.png [--out debug.png]                             show the estimated face box
    post.py sheet OUT.png IMG [IMG ...] [--cols 4]
"""
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

# Delivery spec: docs/dev/art-style.md section 2-3 (crown y=108, soles y=1990, >= 24 px margins).
CANVAS = (1024, 2048)
FEET_Y = 1990
CROWN_Y = 108
FIGURE_H = 1900          # used only when the crown is unknown (bbox top includes halo/wings)
MARGIN = 24
HEAD_TOP_MIN = 40


# ------------------------------------------------------------------ small morphology helpers
def _box_sum(m, r):
    """Sum of m over a (2r+1)^2 window (zero padding), via an integral image."""
    m = m.astype(np.int32)
    h, w = m.shape
    p = np.pad(m, ((r + 1, r), (r + 1, r)))
    c = p.cumsum(0).cumsum(1)
    k = 2 * r + 1
    return c[k:k + h, k:k + w] - c[0:h, k:k + w] - c[k:k + h, 0:w] + c[0:h, 0:w]


def dilate(mask, r):
    return mask.copy() if r <= 0 else _box_sum(mask, r) > 0


def erode(mask, r):
    return mask.copy() if r <= 0 else _box_sum(mask, r) >= (2 * r + 1) ** 2


def _run_fill(seed, cand):
    """Within each row, every run of `cand` pixels that touches a seed becomes seeded."""
    h, w = cand.shape
    starts = cand.copy()
    starts[:, 1:] &= ~cand[:, :-1]
    run_id = np.cumsum(starts.ravel()).reshape(h, w) * cand
    hit = np.zeros(int(run_id.max()) + 1, dtype=bool)
    hit[run_id[seed & cand]] = True
    hit[0] = False
    return hit[run_id]


def flood(seed, cand, max_iter=2000):
    """Pixels of `cand` 4-connected to `seed` (binary reconstruction by alternating row/column runs)."""
    cur = seed & cand
    for _ in range(max_iter):
        nxt = _run_fill(cur, cand)
        nxt = _run_fill(nxt.T, cand.T).T
        if np.array_equal(nxt, cur):
            return nxt
        cur = nxt
    return cur


def _border(shape, width=1):
    b = np.zeros(shape, dtype=bool)
    b[:width, :] = b[-width:, :] = True
    b[:, :width] = b[:, -width:] = True
    return b


def _rgb(img):
    if isinstance(img, np.ndarray):
        return img[..., :3].astype(np.float32)
    if img.mode == "RGBA":
        bg = Image.new("RGB", img.size, (128, 128, 128))
        bg.paste(img, mask=img.split()[3])
        img = bg
    return np.asarray(img.convert("RGB")).astype(np.float32)


def estimate_bg(arr, width=6):
    """Median colour of the image border."""
    b = _border(arr.shape[:2], width)
    return np.median(arr[b], axis=0)


def fit_bg_surface(arr, bgmask, samples=40000):
    """Quadratic colour surface fitted to known background pixels (handles gradients/vignettes)."""
    h, w = bgmask.shape
    ys, xs = np.nonzero(bgmask)
    if len(xs) < 50:
        return np.broadcast_to(estimate_bg(arr), arr.shape).astype(np.float32)
    if len(xs) > samples:
        idx = np.random.default_rng(0).choice(len(xs), samples, replace=False)
        ys, xs = ys[idx], xs[idx]
    u, v = xs / max(1, w - 1) - 0.5, ys / max(1, h - 1) - 0.5
    A = np.stack([np.ones_like(u), u, v, u * u, v * v, u * v], 1)
    coef, *_ = np.linalg.lstsq(A, arr[ys, xs], rcond=None)
    coef = coef.astype(np.float32)
    U = np.linspace(-0.5, 0.5, w, dtype=np.float32)[None, :, None]
    V = np.linspace(-0.5, 0.5, h, dtype=np.float32)[:, None, None]
    out = coef[0] + coef[1] * U + coef[2] * V + coef[3] * U * U + coef[4] * V * V + coef[5] * U * V
    return np.clip(out, 0, 255).astype(np.float32)


def _offsets(r):
    return [(dy, dx) for dy in range(-r, r + 1) for dx in range(-r, r + 1)]


def _unmix_band(arr, figure, band, bgc, r=3, lo=10.0, hi=40.0):
    """Alpha for edge-band pixels by foreground/background unmixing.
    Background colour = mean of nearby background pixels (fallback: fitted surface). Foreground
    candidates = 'solid' figure pixels in the (2r+1)^2 window (the pixel itself included); the one
    that best explains the pixel as a mix (smallest residual off the bg->fg line, nearer preferred)
    gives alpha = projection onto that line. Returns ys, xs, alpha, local background colours."""
    h, w = figure.shape
    ys, xs = np.nonzero(band)
    obs = arr[ys, xs]
    dist_full = np.linalg.norm(arr - bgc, axis=2)
    solid = figure & (dist_full > hi)
    bsum = np.zeros_like(obs)
    bcnt = np.zeros(len(ys), dtype=np.float32)
    for dy, dx in _offsets(r + 1):
        yy, xx = np.clip(ys + dy, 0, h - 1), np.clip(xs + dx, 0, w - 1)
        isbg = ~figure[yy, xx]
        bsum[isbg] += arr[yy[isbg], xx[isbg]]
        bcnt[isbg] += 1
    bg_local = np.where(bcnt[:, None] > 0, bsum / np.maximum(bcnt, 1)[:, None], bgc[ys, xs])
    v = obs - bg_local
    best = np.full(len(ys), np.inf, dtype=np.float32)
    alpha = np.zeros(len(ys), dtype=np.float32)
    found = np.zeros(len(ys), dtype=bool)
    for dy, dx in _offsets(r):
        yy, xx = np.clip(ys + dy, 0, h - 1), np.clip(xs + dx, 0, w - 1)
        ok = solid[yy, xx]
        if not ok.any():
            continue
        c = arr[yy, xx] - bg_local
        denom = np.maximum((c * c).sum(1), 1e-3)
        proj = np.clip((v * c).sum(1) / denom, 0, 1)
        perp = np.linalg.norm(v - proj[:, None] * c, axis=1)
        score = perp + 0.75 * (abs(dy) + abs(dx))
        better = ok & (score < best) & (denom > 25.0 ** 2)
        best = np.where(better, score, best)
        alpha = np.where(better, proj, alpha)
        found |= better
    d_local = np.linalg.norm(v, axis=1)
    smooth = np.clip((d_local - lo) / (hi - lo), 0, 1)
    alpha = np.where(found, alpha, smooth)
    alpha *= np.clip((d_local - lo) / lo, 0, 1)      # noise floor: background grain stays transparent
    return ys, xs, alpha, bg_local


def _finish_alpha(arr, bgc, figure, band_px=2, feather=0.7, soft=(10.0, 40.0), despill=True):
    """Alpha + colours from a hard figure mask: unmix anti-aliased edge pixels against the local
    background, feather, despill the background colour, drop specks. Returns an RGBA uint8 array."""
    band = dilate(figure, band_px) & dilate(~figure, band_px)
    alpha = figure.astype(np.float32)
    bys = bxs = bg_local = None
    if band.any():
        bys, bxs, a_band, bg_local = _unmix_band(arr, figure, band, bgc, r=band_px + 1, lo=soft[0], hi=soft[1])
        alpha[bys, bxs] = a_band
    if feather and feather > 0:
        blurred = np.asarray(Image.fromarray((alpha * 255).astype(np.uint8)).filter(
            ImageFilter.GaussianBlur(feather))).astype(np.float32) / 255.0
        # feather only softens: never raise alpha of background pixels, never cut solid figure pixels
        alpha = np.where(band, np.minimum(alpha, np.maximum(blurred, alpha * 0.85)), alpha)
    # remove specks: keep only alpha connected to a solid 5x5 core
    core = erode(alpha > 0.5, 2)
    keep = flood(core, alpha > 0.02)
    alpha = np.where(keep, alpha, 0.0)
    rgb = arr.copy()
    if despill and bys is not None:
        a = alpha[bys, bxs][:, None]
        part = ((a[:, 0] > 0.02) & (a[:, 0] < 0.999))
        un = (arr[bys, bxs] - (1.0 - a) * bg_local) / np.maximum(a, 1e-3)
        cur = rgb[bys, bxs]
        cur[part] = np.clip(un[part], 0, 255)
        rgb[bys, bxs] = cur
    rgb[alpha <= 0.0] = 0
    out = np.dstack([rgb, alpha * 255.0])
    return np.clip(out + 0.5, 0, 255).astype(np.uint8)


def components(mask, max_count=200):
    """Yield boolean masks of the 4-connected components of `mask` (largest count capped)."""
    rest = mask.copy()
    for _ in range(max_count):
        ys, xs = np.nonzero(rest)
        if len(xs) == 0:
            return
        seed = np.zeros_like(rest)
        seed[ys[0], xs[0]] = True
        comp = flood(seed, rest)
        rest &= ~comp
        yield comp


def remove_background(img, bg=None, tol=26.0, holes=True, hole_tol=12.0, hole_min=24, max_hole_frac=0.06,
                      band_px=2, feather=0.7, despill=True):
    """Cut a figure out of a flat background. Returns (RGBA Image, info dict).
    Background = pixels within `tol` of the fitted background colour that are connected to the image
    border, plus enclosed "holes" (gaps between arm and body, legs, feathers): flat regions within
    `hole_tol`, at least `hole_min` px across, each smaller than `max_hole_frac` of the figure's
    bounding box (so a large white dress on a white background is not taken for a hole)."""
    arr = _rgb(img)
    h, w = arr.shape[:2]
    bg0 = np.array(bg, dtype=np.float32) if bg is not None else estimate_bg(arr)
    border = _border((h, w))
    # pass 1: flood fill against a flat colour, then fit a smooth background surface and refill
    cand = np.linalg.norm(arr - bg0, axis=2) < tol
    B = flood(border & cand, cand)
    bgc = fit_bg_surface(arr, B) if bg is None else np.broadcast_to(bg0, arr.shape).astype(np.float32)
    dist = np.linalg.norm(arr - bgc, axis=2)
    cand = dist < tol
    B = flood(border & cand, cand)
    n_holes = 0
    skipped = []
    if holes:
        hole_px, n_holes, skipped = enclosed_holes(dist, cand, B, hole_tol, hole_min, max_hole_frac)
        B |= hole_px
    figure = ~B
    rgba = _finish_alpha(arr, bgc, figure, band_px=band_px, feather=feather, despill=despill)
    info = {"method": "flood_fill", "bg_rgb": [round(float(x), 1) for x in bg0], "tol": tol,
            "hole_px": n_holes, "holes_kept_as_figure": skipped, "figure_px": int((rgba[..., 3] > 127).sum())}
    return Image.fromarray(rgba, "RGBA"), info


def enclosed_holes(dist, cand, B, hole_tol=12.0, hole_min=24, max_hole_frac=0.06):
    """Background seen through the figure (gaps between arm and body, cut-outs in a weapon): flat
    regions within `hole_tol` of the background, at least `hole_min` px across, grown inside `cand`,
    each smaller than `max_hole_frac` of the figure's bounding box (so a large white dress on a white
    background is not taken for a hole). B: pixels already known to be background.
    Returns (hole mask, hole px, [[x, y, area] of regions kept as figure])."""
    holes = np.zeros(B.shape, bool)
    n, skipped = 0, []
    tight = (dist < hole_tol) & ~B
    r = max(1, hole_min // 2)
    opened = dilate(erode(tight, r), r) & tight
    if opened.any():
        fy, fx = np.nonzero(~B)
        fig_area = max(1, int((fy.max() - fy.min() + 1) * (fx.max() - fx.min() + 1))) if len(fx) else 1
        for comp in components(opened):
            hole = flood(comp, cand & ~B)
            area = int(hole.sum())
            if area > max_hole_frac * fig_area:
                ys, xs = np.nonzero(comp)
                skipped.append([int(xs.mean()), int(ys.mean()), area])
                continue
            n += area
            holes |= hole
    return holes, n, skipped


def alpha_from_mask(img, mask, bg=None, band_px=2, feather=0.7, holes=True, tol=26.0):
    """Combine an image with a mask from a server-side background-removal node. The mask may be
    an L/RGB image (white = figure) or an RGBA image (alpha). Polarity is auto-detected.
    holes: also clear enclosed flat background regions the node kept as figure (BiRefNet keeps the
    background seen through a scythe blade or between a wing and the body), by the same rules as
    remove_background's holes."""
    arr = _rgb(img)
    if mask.mode == "RGBA" and np.asarray(mask.split()[3]).min() < 250:
        m = np.asarray(mask.split()[3]).astype(np.float32) / 255.0
    else:
        m = np.asarray(mask.convert("L")).astype(np.float32) / 255.0
    if m.shape != arr.shape[:2]:
        m = np.asarray(Image.fromarray((m * 255).astype(np.uint8)).resize(
            (arr.shape[1], arr.shape[0]), Image.BILINEAR)).astype(np.float32) / 255.0
    border = _border(m.shape, 4)
    if m[border].mean() > 0.5:   # background came out white: invert
        m = 1.0 - m
    figure = m > 0.5
    bg0 = np.array(bg, dtype=np.float32) if bg is not None else estimate_bg(arr)
    bgc = fit_bg_surface(arr, ~dilate(figure, 4)) if bg is None else np.broadcast_to(bg0, arr.shape).astype(np.float32)
    n_holes, skipped = 0, []
    if holes:
        dist = np.linalg.norm(arr - bgc, axis=2)
        hole_px, n_holes, skipped = enclosed_holes(dist, dist < tol, ~figure)
        figure &= ~hole_px
        m = np.where(hole_px, 0.0, m)
    rgba = _finish_alpha(arr, bgc, figure, band_px=band_px, feather=feather)
    # trust the node's soft mask where it is confident, our unmixing only on the edge band
    a = rgba[..., 3].astype(np.float32) / 255.0
    edge = dilate(figure, band_px) & dilate(~figure, band_px)
    a = np.where(edge, a, m)
    rgba[..., 3] = np.clip(a * 255 + 0.5, 0, 255).astype(np.uint8)
    return Image.fromarray(rgba, "RGBA"), {"method": "server_mask", "figure_px": int((a > 0.5).sum()),
                                           "hole_px": n_holes, "holes_kept_as_figure": skipped}


# ------------------------------------------------------------------ geometry
def alpha_bbox(rgba, thresh=8):
    a = np.asarray(rgba.split()[3])
    ys, xs = np.nonzero(a > thresh)
    if len(xs) == 0:
        return None
    return int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1


def trim(rgba, thresh=8, pad=0):
    bb = alpha_bbox(rgba, thresh)
    if bb is None:
        return rgba, (0, 0, rgba.width, rgba.height)
    x0, y0, x1, y1 = bb
    x0, y0 = max(0, x0 - pad), max(0, y0 - pad)
    x1, y1 = min(rgba.width, x1 + pad), min(rgba.height, y1 + pad)
    return rgba.crop((x0, y0, x1, y1)), (x0, y0, x1, y1)


def figure_metrics(rgba):
    """top, feet (lowest solid row), bbox and body axis x (alpha-weighted centre of the lowest 12%)."""
    a = np.asarray(rgba.split()[3]).astype(np.float32) / 255.0
    solid = a > 0.5
    rows = np.nonzero(solid.sum(1) >= 3)[0]
    if len(rows) == 0:
        raise ValueError("image has no opaque figure")
    top, feet = int(rows.min()), int(rows.max()) + 1
    cols = np.nonzero(solid.any(0))[0]
    band0 = feet - max(4, int(0.12 * (feet - top)))
    sub = a[band0:feet]
    xs = np.arange(a.shape[1], dtype=np.float32)
    wsum = sub.sum()
    axis = float((sub.sum(0) * xs).sum() / wsum) if wsum > 0 else float(cols.mean())
    return {"top": top, "feet": feet, "bbox": [int(cols.min()), top, int(cols.max()) + 1, feet], "axis_x": axis}


def crown_from_face_box(face_box):
    """Head crown y from a face box (box spans brow/hairline to chin; crown ~0.4 box heights above)."""
    return face_box[1] - 0.4 * face_box[3]


def place_on_canvas(rgba, canvas=CANVAS, feet_y=FEET_Y, figure_h=FIGURE_H, margin=MARGIN, feet_src=None,
                    axis_src=None, crown_src=None, crown_y=CROWN_Y):
    """Scale and place the figure: crown at crown_y and soles at feet_y when the crown is known
    (from the face box), else top-of-figure to feet = figure_h; smaller if anything (wings, halo,
    weapon) would come closer than `margin` to an edge. Body axis at the canvas centre (shifted only
    as needed to fit). Returns (canvas RGBA, transform) with canvas_xy = src_xy * scale + offset."""
    m = figure_metrics(rgba)
    feet = feet_src if feet_src is not None else m["feet"]
    axis = axis_src if axis_src is not None else m["axis_x"]
    x0, top, x1, _ = m["bbox"]
    h = max(1, feet - top)
    W, H = canvas
    notes = []
    if crown_src is not None and feet - crown_src > 0.5 * h:
        scale = (feet_y - crown_y) / (feet - crown_src)
    else:
        scale = figure_h / h
        if crown_src is not None:
            notes.append("crown estimate ignored (implausible)")
    if (x1 - x0) * scale > W - 2 * margin:
        scale = (W - 2 * margin) / (x1 - x0)
        notes.append("figure too wide for the canvas: scaled down to fit the width")
    if feet_y - (feet - top) * scale < margin:
        scale = (feet_y - margin) / h
        notes.append("figure too tall (halo/wings): scaled down to keep a %d px top margin" % margin)
    ox = W / 2 - axis * scale
    # keep the whole bbox on the canvas, moving the axis off-centre only as much as needed
    if x0 * scale + ox < margin:
        ox = margin - x0 * scale
        notes.append("shifted right to fit")
    if x1 * scale + ox > W - margin:
        ox = W - margin - x1 * scale
        notes.append("shifted left to fit")
    oy = feet_y - feet * scale
    nw, nh = max(1, round(rgba.width * scale)), max(1, round(rgba.height * scale))
    scaled = rgba.convert("RGBa").resize((nw, nh), Image.LANCZOS).convert("RGBA")
    out = Image.new("RGBA", canvas, (0, 0, 0, 0))
    out.alpha_composite(scaled, (int(round(ox)), int(round(oy))))
    tr = {"scale": round(scale, 6), "offset": [int(round(ox)), int(round(oy))], "canvas": list(canvas),
          "feet_y": feet_y, "figure_h": round(h * scale, 1), "notes": notes}
    if crown_src is not None:
        tr["crown_y"] = round(crown_src * scale + oy, 1)
        if tr["crown_y"] < HEAD_TOP_MIN:
            notes.append("head top at y=%.0f, spec wants >= %d" % (tr["crown_y"], HEAD_TOP_MIN))
    return out, tr


def map_box(box, tr):
    """(x, y, w, h) in source pixels -> canvas pixels."""
    s, (ox, oy) = tr["scale"], tr["offset"]
    x, y, w, h = box
    return [round(x * s + ox), round(y * s + oy), round(w * s), round(h * s)]


# Skin colour windows in PIL HSV (0-255 each). "light": peach/pale anime skin (excludes blonde/gold
# hair and halos, which sit at higher hues, and saturated red/orange hair). "red": red-skinned demons.
SKIN_PROFILES = {"light": {"hue": (0, 25), "hue_wrap": 248, "sat": (12, 130), "val": 110},
                 "red": {"hue": (0, 14), "hue_wrap": 240, "sat": (90, 235), "val": 70}}


def skin_mask(rgba, profile="light"):
    p = SKIN_PROFILES[profile]
    hsv = np.asarray(rgba.convert("RGB").convert("HSV")).astype(np.int32)
    h, s, v = hsv[..., 0], hsv[..., 1], hsv[..., 2]
    a = np.asarray(rgba.split()[3]) > 127
    return (((h >= p["hue"][0]) & (h <= p["hue"][1])) | (h >= p["hue_wrap"])) & \
        (s >= p["sat"][0]) & (s <= p["sat"][1]) & (v >= p["val"]) & a


def estimate_face_box(rgba, skin_profile="light"):
    """Heuristic face box (x, y, w, h) spanning brow/hairline to chin, plus a confidence string.
    Finds the topmost band of skin-coloured pixels near the body axis that persists for several
    rows (so halo rings and hair highlights don't count); head height from the distance to the
    feet (~7 heads). Always check it (finalize's _boxes.png) and pass --face-box if it is off."""
    m = figure_metrics(rgba)
    skin = skin_mask(rgba, skin_profile)
    fig_h = m["feet"] - m["top"]
    axis = m["axis_x"]
    y_lo, y_hi = m["top"], m["top"] + int(0.42 * fig_h)
    x_lo, x_hi = int(max(0, axis - 0.2 * fig_h)), int(min(skin.shape[1], axis + 0.2 * fig_h))
    region = skin[y_lo:y_hi, x_lo:x_hi]
    counts = region.sum(1)
    thr = max(4, int(0.012 * fig_h))
    ok = (counts >= thr).astype(np.float32)
    k = max(5, int(0.035 * fig_h))
    run = np.convolve(ok, np.ones(k, np.float32), "valid") / k if len(ok) >= k else np.zeros(0)
    rows = np.nonzero(run >= 0.8)[0]
    if len(rows):
        skin_top = y_lo + int(rows[0]) + int(np.argmax(ok[rows[0]:rows[0] + k] > 0))
        hh = (m["feet"] - skin_top) / 7.0
        band = skin[skin_top:skin_top + int(0.5 * hh), x_lo:x_hi]
        ys, xs = np.nonzero(band)
        cx = x_lo + float(np.median(xs)) if len(xs) else axis
        conf = "skin"
        y0 = skin_top - 0.08 * hh
    else:
        hh = fig_h / 7.6
        cx = axis
        conf = "proportions-only (low)"
        y0 = m["top"] + 0.35 * hh
    fw, fh = 0.70 * hh, 0.68 * hh
    return [int(round(cx - fw / 2)), int(round(y0)), int(round(fw)), int(round(fh))], conf


def region_box(face_box, frac):
    """Sub-box of a face box from fractions [x0, y0, x1, y1] -> (x, y, w, h)."""
    x, y, w, h = face_box
    return [int(round(x + frac[0] * w)), int(round(y + frac[1] * h)),
            int(round((frac[2] - frac[0]) * w)), int(round((frac[3] - frac[1]) * h))]


def portrait_rect(face_box, canvas_size, scale=2.7):
    """Square head-and-shoulders rect [x, y, size, size] around a face box, clamped to the canvas."""
    x, y, w, h = face_box
    size = int(round(max(w, h) * scale))
    size = min(size, canvas_size[0], canvas_size[1])
    cx, cy = x + w / 2, y + 0.55 * h
    px = int(round(min(max(cx - size / 2, 0), canvas_size[0] - size)))
    py = int(round(min(max(cy - size / 2, 0), canvas_size[1] - size)))
    return [px, py, size, size]


def portrait(canvas_img, face_box, out_px=512):
    r = portrait_rect(face_box, canvas_img.size)
    crop = canvas_img.crop((r[0], r[1], r[0] + r[2], r[1] + r[3]))
    return crop.resize((out_px, out_px), Image.LANCZOS), r


# ------------------------------------------------------------------ review images
def _font(size):
    try:
        return ImageFont.load_default(size=size)
    except TypeError:
        return ImageFont.load_default()


def checker(size, cell=16, c1=(200, 200, 200), c2=(150, 150, 150)):
    w, h = size
    yy, xx = np.mgrid[0:h, 0:w]
    m = ((xx // cell + yy // cell) % 2).astype(bool)
    arr = np.where(m[..., None], np.array(c1, np.uint8), np.array(c2, np.uint8))
    return Image.fromarray(arr.astype(np.uint8), "RGB")


def cutout_preview(rgba, height=1000):
    """Side-by-side preview of a cutout over a checkerboard, magenta and near-black, to spot halos."""
    s = height / rgba.height
    im = rgba.convert("RGBa").resize((max(1, int(rgba.width * s)), height), Image.LANCZOS).convert("RGBA")
    tiles = [checker(im.size), Image.new("RGB", im.size, (255, 0, 255)), Image.new("RGB", im.size, (20, 18, 36))]
    out = Image.new("RGB", (im.width * 3, height))
    for i, t in enumerate(tiles):
        t.paste(im, (0, 0), im)
        out.paste(t, (i * im.width, 0))
    return out


def draw_boxes(img, boxes, width=3):
    """Debug overlay: boxes = [(x, y, w, h, colour, label)]."""
    out = img.convert("RGB").copy()
    d = ImageDraw.Draw(out)
    f = _font(max(14, img.height // 80))
    for x, y, w, h, col, label in boxes:
        d.rectangle([x, y, x + w, y + h], outline=col, width=width)
        if label:
            d.text((x + 3, y - f.size - 4 if hasattr(f, "size") else y - 14), label, fill=col, font=f)
    return out


def _fit(im, box):
    w, h = box
    s = min(w / im.width, h / im.height)
    return im.resize((max(1, int(im.width * s)), max(1, int(im.height * s))), Image.LANCZOS)


def detail_crop(img):
    """Face/upper-body crop for review sheets (works on flat-background candidates and RGBA)."""
    small = img.convert("RGBA") if img.mode == "RGBA" else img.convert("RGB")
    f = 0.5 if small.height > 1200 else 1.0
    sm = small.resize((int(small.width * f), int(small.height * f)), Image.BILINEAR)
    try:
        rgba = sm if sm.mode == "RGBA" else remove_background(sm, holes=False, feather=0)[0]
        fb, _ = estimate_face_box(rgba)
        x, y, w, h = [v / f for v in fb]
        size = max(w, h) * 3.0
        cx, cy = x + w / 2, y + h * 0.9
        box = (int(cx - size / 2), int(cy - size / 2), int(cx + size / 2), int(cy + size / 2))
    except ValueError:
        box = (0, 0, img.width, img.width)
    crop = img.crop(box)
    if crop.mode == "RGBA":
        bg = checker(crop.size)
        bg.paste(crop, (0, 0), crop)
        crop = bg
    return crop


def contact_sheet(entries, out_path, cols=4, cell_w=300, detail=True, title=None):
    """Grid of candidates. entries: [(path or Image, label)]. Each cell shows the full image and,
    below it, a face/upper-body detail crop, with the label (seed) on top. Returns the path."""
    cell_h = int(cell_w * 1.75)
    det_h = cell_w if detail else 0
    lab_h = 30
    rows = (len(entries) + cols - 1) // cols
    head = 44 if title else 0
    W = cols * cell_w + (cols + 1) * 8
    H = head + rows * (lab_h + cell_h + det_h + 12) + 8
    sheet = Image.new("RGB", (W, H), (27, 25, 38))
    d = ImageDraw.Draw(sheet)
    if title:
        d.text((10, 10), title, fill=(243, 236, 223), font=_font(24))
    for i, (src, label) in enumerate(entries):
        im = Image.open(src) if isinstance(src, str) else src
        im.load()
        r, c = divmod(i, cols)
        x = 8 + c * (cell_w + 8)
        y = head + 8 + r * (lab_h + cell_h + det_h + 12)
        d.text((x + 2, y + 2), label, fill=(242, 193, 78), font=_font(20))
        y += lab_h
        view = im
        if im.mode == "RGBA":
            view = checker(im.size)
            view.paste(im, (0, 0), im)
        t = _fit(view.convert("RGB"), (cell_w, cell_h))
        sheet.paste(t, (x + (cell_w - t.width) // 2, y))
        if detail:
            dc = _fit(detail_crop(im).convert("RGB"), (cell_w, det_h))
            sheet.paste(dc, (x + (cell_w - dc.width) // 2, y + cell_h + 4))
    os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)
    sheet.save(out_path)
    return out_path


# ------------------------------------------------------------------ automatic checks
def candidate_report(img, expected_bg=None, tol=26.0, scale=0.5):
    """Quick cutout + framing check of a flat-background candidate (on a half-size copy).
    Returns (rgba cutout at check size, report):
      touches        image edges the figure reaches (cropped head, feet, wings or weapon)
      edge_low       fraction of the figure's outline (1-3 px inside the edge) whose colour is within
                     2*tol of the background: hair, wings or armour that melt into it
      bg_rgb, bg_off the border colour found and its distance from the expected flat colour
      figure_frac    figure area / image area (very high = a scene was painted, not a flat background)
      flags          short labels for contact sheets ([] = looks fine)"""
    im = img.convert("RGB")
    if scale != 1.0:
        im = im.resize((max(8, int(im.width * scale)), max(8, int(im.height * scale))), Image.BILINEAR)
    rgba, info = remove_background(im, tol=tol)
    arr = _rgb(im)
    a = np.asarray(rgba)[..., 3] > 127
    m = 2
    touches = [n for n, e in (("top", a[:m].any()), ("bottom", a[-m:].any()),
                              ("left", a[:, :m].any()), ("right", a[:, -m:].any())) if e]
    bg = np.array(info["bg_rgb"], np.float32)
    inner = a & dilate(~a, 3) & ~dilate(~a, 1)
    edge_low = float((np.linalg.norm(arr[inner] - bg, axis=1) < 2 * tol).mean()) if inner.any() else 0.0
    bg_off = float(np.linalg.norm(bg - np.array(expected_bg, np.float32))) if expected_bg is not None else 0.0
    frac = float(a.mean())
    flags = []
    if touches:
        flags.append("CROP:" + ",".join(touches))
    if edge_low > 0.2:      # advisory; calibrate on the first live candidates
        flags.append("EDGE %d%%" % round(100 * edge_low))
    if bg_off > 40:
        flags.append("BG?")
    if frac > 0.55:
        flags.append("FILL %d%%" % round(100 * frac))
    rep = {"touches": touches, "edge_low": round(edge_low, 3), "bg_rgb": info["bg_rgb"], "bg_off": round(bg_off, 1),
           "figure_frac": round(frac, 3), "holes_kept_as_figure": len(info["holes_kept_as_figure"]), "flags": flags}
    return rgba, rep


def variant_alignment(base, variant, allowed_rect=None, margin=12, tol=2):
    """Check that `variant` is `base` with only a local change: same size, identical alpha, and every
    pixel that differs (RGB beyond `tol`) inside `allowed_rect` (x, y, w, h) grown by `margin`.
    Returns a list of problems ([] = aligned)."""
    if base.size != variant.size:
        return ["size %s differs from the base %s" % (variant.size, base.size)]
    b = np.asarray(base.convert("RGBA")).astype(np.int16)
    v = np.asarray(variant.convert("RGBA")).astype(np.int16)
    probs = []
    if not np.array_equal(b[..., 3], v[..., 3]):
        probs.append("alpha differs from the base (%d px)" % int((b[..., 3] != v[..., 3]).sum()))
    diff = (np.abs(b[..., :3] - v[..., :3]).max(2) > tol) & (b[..., 3] > 0)
    if allowed_rect is not None and diff.any():
        x, y, w, h = allowed_rect
        inside = np.zeros_like(diff)
        inside[max(0, y - margin):y + h + margin, max(0, x - margin):x + w + margin] = True
        out = diff & ~inside
        if out.sum() > 0:
            ys, xs = np.nonzero(out)
            probs.append("%d px changed outside the expression region (e.g. at %d,%d): not made from this base"
                         % (int(out.sum()), int(xs[0]), int(ys[0])))
    return probs


# ------------------------------------------------------------------ finalize (local part)
def parse_box(s):
    if s is None:
        return None
    v = [int(round(float(t))) for t in str(s).replace(" ", "").split(",")]
    if len(v) != 4:
        raise ValueError("box must be x,y,w,h")
    return v


def finalize_local(hero_id, image, out_dir, face_box=None, bg=None, mask=None, feet_y_src=None, extra_meta=None,
                   tol=26.0, holes=True, flip=False, face_source="user", skin_profile="light"):
    """Cutout (or server mask) + canvas placement + portrait + review preview + meta JSON.
    `face_box` is in the source image's pixels (before any flip). flip mirrors the result (the spec
    wants a 3/4 view facing screen right). Returns the meta dict."""
    img = Image.open(image) if isinstance(image, str) else image
    img.load()
    if flip:
        img = img.transpose(Image.FLIP_LEFT_RIGHT)
        if mask is not None:
            mask = mask.transpose(Image.FLIP_LEFT_RIGHT)
        if face_box is not None:
            face_box = [img.width - face_box[0] - face_box[2], face_box[1], face_box[2], face_box[3]]
    if img.mode == "RGBA" and np.asarray(img.split()[3]).min() < 250:
        rgba, cut = img, {"method": "source_alpha"}
    elif mask is not None:
        rgba, cut = alpha_from_mask(img, mask, bg=bg, holes=holes, tol=tol)
    else:
        rgba, cut = remove_background(img, bg=bg, tol=tol, holes=holes)
    if face_box is None:
        fb_src, conf = estimate_face_box(rgba, skin_profile)
    else:
        fb_src, conf = list(face_box), face_source
    crown = crown_from_face_box(fb_src) if conf != "proportions-only (low)" else None
    canvas, tr = place_on_canvas(rgba, feet_src=feet_y_src, crown_src=crown)
    fb = map_box(fb_src, tr)
    por, prect = portrait(canvas, fb)
    os.makedirs(out_dir, exist_ok=True)
    base = os.path.join(out_dir, hero_id)
    canvas.save(base + ".png")
    por.save(base + "_portrait.png")
    cutout_preview(canvas, 1000).save(base + "_check.png")
    draw_boxes(cutout_preview(canvas, 2048).crop((0, 0, canvas.width, canvas.height)),
               [(*fb, (0, 220, 255), "face"), (*prect, (242, 193, 78), "portrait")]).save(base + "_boxes.png")
    meta = {
        "hero": hero_id, "image": os.path.basename(base + ".png"), "canvas": list(CANVAS),
        "origin": [CANVAS[0] // 2, FEET_Y], "transform": tr, "cutout": cut,
        "face_box": fb, "face_box_source": conf, "face_box_src_pixels": fb_src, "flipped": bool(flip),
        "head_px_estimate": round(fb[3] / 0.68),
        "portrait_rect": prect,
        "warp_src_hints": {
            "_doc": "Suggested values for assets/art/heroes/<id>/<id>.warp_src.json (HaloRig warp rig).",
            "origin": [CANVAS[0] // 2, FEET_Y],
            "portrait": [prect[0] + prect[2] // 2, prect[1] + prect[3] // 2, prect[2]],
        },
    }
    meta.update(extra_meta or {})
    with open(base + ".json", "w") as f:
        json.dump(meta, f, indent=1)
    return meta


# ------------------------------------------------------------------ CLI
def _rgb_arg(s):
    return [int(t) for t in s.split(",")] if s else None


def main(argv=None):
    import argparse
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("cutout")
    c.add_argument("inp")
    c.add_argument("out")
    c.add_argument("--bg", help="background colour R,G,B (default: sampled from the border)")
    c.add_argument("--tol", type=float, default=26.0)
    c.add_argument("--no-holes", action="store_true")
    p = sub.add_parser("place")
    p.add_argument("inp")
    p.add_argument("out")
    f = sub.add_parser("finalize")
    f.add_argument("hero")
    f.add_argument("inp")
    f.add_argument("--face-box")
    f.add_argument("--bg")
    f.add_argument("--out-dir")
    f.add_argument("--flip", action="store_true", help="mirror (the spec wants the figure facing right)")
    fb = sub.add_parser("facebox")
    fb.add_argument("inp")
    fb.add_argument("--out")
    fb.add_argument("--skin", choices=sorted(SKIN_PROFILES), default="light")
    s = sub.add_parser("sheet")
    s.add_argument("out")
    s.add_argument("images", nargs="+")
    s.add_argument("--cols", type=int, default=4)
    a = ap.parse_args(argv)
    if a.cmd == "cutout":
        rgba, info = remove_background(Image.open(a.inp), bg=_rgb_arg(a.bg), tol=a.tol, holes=not a.no_holes)
        rgba.save(a.out)
        print(json.dumps(info))
    elif a.cmd == "place":
        out, tr = place_on_canvas(Image.open(a.inp).convert("RGBA"))
        out.save(a.out)
        print(json.dumps(tr))
    elif a.cmd == "finalize":
        root = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
        out_dir = a.out_dir or os.path.join(os.environ.get("HALO_ART_SRC") or os.path.join(root, "art_src"),
                                            a.hero, "final")
        meta = finalize_local(a.hero, a.inp, out_dir, face_box=parse_box(a.face_box), bg=_rgb_arg(a.bg), flip=a.flip)
        print(json.dumps({k: meta[k] for k in ("face_box", "face_box_source", "portrait_rect", "transform")}, indent=1))
        print("wrote", os.path.join(out_dir, a.hero + ".png"))
    elif a.cmd == "facebox":
        im = Image.open(a.inp)
        rgba = im if im.mode == "RGBA" else remove_background(im)[0]
        box, conf = estimate_face_box(rgba, a.skin)
        print("face box x,y,w,h = %s  (%s)" % (",".join(map(str, box)), conf))
        if a.out:
            draw_boxes(im, [(*box, (0, 220, 255), "face (%s)" % conf)]).save(a.out)
            print("wrote", a.out)
    elif a.cmd == "sheet":
        contact_sheet([(p, os.path.basename(p)) for p in a.images], a.out, cols=a.cols)
        print("wrote", a.out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
