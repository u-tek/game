"""Figure cutout for final mode (PIL + numpy only; built on tools/comfy/post.py helpers).

isnet-anime gives a good soft mask of the character, but it labels background ENCLOSED by the
figure (inside a spiked halo ring, between wings, staff and arm) as figure, and keeps a cast ground
shadow under the feet. post.alpha_from_mask trusts the mask everywhere except a 2 px edge band, so
those would stay as grey patches. artgen_cutout() therefore combines:

  figure = isnet figure
           minus enclosed background: pixels that post.remove_background's colour flood (border fill +
             enclosed holes) calls background AND that are within `hole_tol` of the fitted background
             surface, in regions at least `hole_min` px across;
           minus isnet's unsure haze (mask <= 0.5) that has the background colour (within `bg_tol`),
             while unsure pixels clearly unlike the background (> `solid_dist`) become solid figure when
             isnet leans figure or they sit in a small gap of the figure (closing by `close_px`);
           minus isnet's half-sure zones (mask 0.5-`haze_hi`) of background colour (within `haze_tol`),
             in blobs at least 5 px across only (an opening: the thin seams between two figure parts
             stay); these were the semi-transparent grey patches between a halo and a crown;
           minus pockets: enclosed background too small for the holes (between halo spikes, hair
             strands, wing and arm): flat cores of (2 `pocket_r` + 1)^2 px within `pocket_tol` of the
             fitted background where isnet is not saturated (< `pocket_m`), grown within `hole_tol`
             (opened by 1 px), each under `max_hole_frac` of the figure box; skipped on a near-white
             backdrop (mean luminance >= `pocket_lum`), where white highlights would match it;
           minus the ground shadow: in the bottom `shadow_band` of the figure, smooth pixels with the
             background's chromaticity (wider tolerance where isnet is unsure: anime shadows are
             cooler than the backdrop) and 35-97% of its luminance (darker than the backdrop, so a
             white gown never matches), flood-filled from the background (seeds up to `seed_gap` px
             inside a hard-edged shadow);
  then post.alpha_from_mask for the edge unmixing and despill, and fill_edge_dips for the 1 px holes
  the unmixing makes between a dark outline and a light fill (a beaded edge).

Without an isnet mask (rembg failed to load) the colour-flood cutout is the figure mask.
"""
import numpy as np
from PIL import Image, ImageFilter

import post


def soft_mask(mask, size):
    """isnet output (L / RGB / RGBA image) -> float32 [0, 1] at `size` (w, h), white = figure."""
    if mask.mode == "RGBA" and np.asarray(mask.split()[3]).min() < 250:
        m = np.asarray(mask.split()[3]).astype(np.float32) / 255.0
    else:
        m = np.asarray(mask.convert("L")).astype(np.float32) / 255.0
    if (m.shape[1], m.shape[0]) != tuple(size):
        m = np.asarray(Image.fromarray(np.clip(m * 255 + 0.5, 0, 255).astype(np.uint8)).resize(
            size, Image.BILINEAR)).astype(np.float32) / 255.0
    if m[post._border(m.shape, 4)].mean() > 0.5:      # background came out white: invert
        m = 1.0 - m
    return m


def _lum(a):
    return a[..., 0] * 0.299 + a[..., 1] * 0.587 + a[..., 2] * 0.114


def _chroma(a):
    return a / np.maximum(a.sum(axis=2, keepdims=True), 1.0)


def _grad(lum):
    g = np.zeros_like(lum)
    g[:, 1:] = np.maximum(g[:, 1:], np.abs(lum[:, 1:] - lum[:, :-1]))
    g[:, :-1] = np.maximum(g[:, :-1], np.abs(lum[:, 1:] - lum[:, :-1]))
    g[1:] = np.maximum(g[1:], np.abs(lum[1:] - lum[:-1]))
    g[:-1] = np.maximum(g[:-1], np.abs(lum[1:] - lum[:-1]))
    return g


def ground_shadow(arr, bgc, figure, band=0.15, chroma_tol=0.04, lum_range=(0.35, 0.97), grad_max=8.0,
                  ring_px=2, max_frac=0.8, soft=None, soft_max=0.95, soft_chroma_tol=0.06, seed_gap=3):
    """Boolean mask of the cast shadow under the figure (subset of `figure`), and an info dict.
    A shadow lies flat on the floor: a found region that reaches the top of the bottom band (a dark,
    background-tinted hem or boot rather than a shadow) is left alone. `soft` (isnet's mask, 0-1):
    where it is below `soft_max` the chromaticity tolerance widens to `soft_chroma_tol` (painted
    shadows are bluer than the backdrop; run 38844269897's measured 0.018-0.045). Seeds may sit up
    to `seed_gap` px from the background: the rim of a hard-edged shadow is too steep for `grad_max`."""
    ys, xs = np.nonzero(figure)
    info = {"shadow_px": 0}
    if len(ys) == 0:
        return np.zeros_like(figure), info
    y0, y1 = int(ys.min()), int(ys.max()) + 1
    top = y1 - max(4, int(band * (y1 - y0)))
    rows = np.zeros(figure.shape, dtype=bool)
    rows[top:y1] = True
    lum, blum = _lum(arr), np.maximum(_lum(bgc), 1.0)
    ratio = lum / blum
    cd = np.abs(_chroma(arr) - _chroma(bgc)).max(axis=2)
    tol = chroma_tol if soft is None else np.where(soft < soft_max, soft_chroma_tol, chroma_tol)
    shade = rows & figure & (cd < tol) & (ratio >= lum_range[0]) & (ratio <= lum_range[1])
    cand = shade & (_grad(lum) < grad_max)
    seed = cand & post.dilate(~figure, 1 + seed_gap)
    sh = post.flood(seed, cand)
    if ring_px and sh.any():          # hard-edged shadows: take the (steeper) rim of a found shadow too
        sh |= post.dilate(sh, ring_px) & shade
    kept = np.zeros_like(sh)
    tall = 0
    for comp in post.components(sh, max_count=64):
        cy = np.nonzero(comp.any(axis=1))[0]
        if cy.min() <= top + 2:
            tall += int(comp.sum())
            continue
        kept |= comp
    if tall:
        info["shadow_left_px"] = tall
    band_fig = int((figure & rows).sum())
    if band_fig and kept.sum() > max_frac * band_fig:
        info["shadow_skipped"] = "%d px is more than %.0f%% of the figure's bottom band" % (int(kept.sum()), 100 * max_frac)
        return np.zeros_like(figure), info
    info["shadow_px"] = int(kept.sum())
    return kept, info


def fill_edge_dips(rgba, arr, figure, dist, band_px=2, min_dip=0.25, max_alpha=0.6, solid_dist=40.0):
    """Line art next to the backdrop: the anti-aliased pixel between a dark outline and a light fill
    can have the backdrop's colour, and the edge unmixing then makes it transparent, a 1 px hole inside
    the outline; the outline beyond it is then cut off from the figure and dropped as a speck (run
    38852819142's wings: a beaded edge, dark dots on a dark screen, grey dots on white). In the edge
    band inside the figure mask: pixels clearly unlike the backdrop (> `solid_dist`) that ended up
    transparent come back opaque, then every alpha dip below its 3x3 grey-level closing (by >=
    `min_dip`, alpha < `max_alpha`) takes the closing's alpha; both keep the image's own colour.
    Returns (RGBA Image, filled px)."""
    out = np.asarray(rgba).copy()
    band = figure & post.dilate(figure, band_px) & post.dilate(~figure, band_px)
    lost = band & (out[..., 3] < 8) & (dist > solid_dist)
    out[lost, 3] = 255
    a = out[..., 3]
    closed = np.asarray(Image.fromarray(a, "L").filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.MinFilter(3)))
    dip = band & (closed.astype(np.int32) - a >= int(255 * min_dip)) & (a < int(255 * max_alpha))
    out[dip, 3] = closed[dip]
    fix = lost | dip
    out[fix, :3] = np.clip(arr[fix] + 0.5, 0, 255).astype(np.uint8)
    return Image.fromarray(out, "RGBA"), int(fix.sum())


def _pockets(arr, bgc, m, dist, hole_tol, max_hole_frac, tol, grad, r, m_max, lum_max):
    """Boolean mask of the background pockets (see the module docstring) and how many were too big."""
    none = np.zeros(m.shape, dtype=bool)
    if float(_lum(bgc).mean()) >= lum_max:
        return none, 0
    flat = (m > 0.0) & (m < m_max) & (dist < tol) & (_grad(_lum(arr)) < grad)
    core = post.erode(flat, r)
    if not core.any():
        return none, 0
    grow = (m > 0.0) & (dist < hole_tol)
    found = post.flood(core, post.dilate(post.erode(grow, 1), 1) & grow)
    fy, fx = np.nonzero(m > 0.5)
    box = max(1, int((fy.max() - fy.min() + 1) * (fx.max() - fx.min() + 1))) if len(fx) else 1
    kept, big = none.copy(), 0
    for comp in post.components(found, max_count=400):
        if comp.sum() > max_hole_frac * box:
            big += 1
            continue
        kept |= comp
    return kept, big


def artgen_cutout(img, isnet_mask=None, hole_tol=12.0, hole_min=24, max_hole_frac=0.06, shadow=True,
                  bg_tol=26.0, solid_dist=40.0, close_px=8, band_px=2, feather=0.7, haze_hi=0.9, haze_tol=18.0,
                  pocket_tol=4.0, pocket_grad=4.0, pocket_r=3, pocket_m=0.995, pocket_lum=235.0):
    """(RGBA Image, info). See the module docstring."""
    rgb = img.convert("RGB")
    arr = post._rgb(rgb)
    flood_rgba, flood_info = post.remove_background(rgb, holes=True, hole_tol=hole_tol, hole_min=hole_min,
                                                    max_hole_frac=max_hole_frac, feather=0)
    B = np.asarray(flood_rgba)[..., 3] < 8          # colour flood + enclosed holes = background
    info = {"method": "isnet + holes + shadow" if isnet_mask is not None else "colour flood + shadow",
            "flood": {k: flood_info[k] for k in ("bg_rgb", "hole_px", "holes_kept_as_figure")}}
    if isnet_mask is not None:
        m = soft_mask(isnet_mask, rgb.size)
    else:
        m = (~B).astype(np.float32)
    m0 = m.copy()
    fig = m > 0.5
    bgc = post.fit_bg_surface(arr, ~post.dilate(fig, 4))
    if isnet_mask is not None:
        dist = np.linalg.norm(arr - bgc, axis=2)
        tight = fig & B & (dist < hole_tol)
        r = max(1, hole_min // 2)
        core = post.dilate(post.erode(tight, r), r) & tight
        holes = post.flood(core, tight)
        m = np.where(holes, 0.0, m)
        # isnet's unsure zones: background-coloured haze goes, clearly figure-coloured cloth turns solid
        haze = (m > 0.0) & (m <= 0.5) & (dist < bg_tol)
        near = (m < haze_hi) & (dist < haze_tol)        # half-sure and background-coloured: blobs only
        half = (m > 0.5) & post.dilate(post.erode(near, 2), 2) & near
        haze |= half
        closed = post.erode(post.dilate(m > 0.5, close_px), close_px)      # small gaps inside the figure
        firm = (m < 1.0) & (dist > solid_dist) & ((m > 0.5) | closed)
        m = np.where(haze, 0.0, np.where(firm, 1.0, m))
        info.update({"hole_px": int(holes.sum()), "haze_px": int(haze.sum()), "half_sure_px": int(half.sum()),
                     "firmed_px": int(firm.sum())})
        pockets, big = _pockets(arr, bgc, m, dist, hole_tol, max_hole_frac, pocket_tol, pocket_grad, pocket_r,
                                pocket_m, pocket_lum)
        m = np.where(pockets, 0.0, m)
        info.update({"pocket_px": int(pockets.sum()), "pockets_kept_as_figure": big})
    if shadow:
        sh, sinfo = ground_shadow(arr, bgc, m > 0.02, soft=m0 if isnet_mask is not None else None)
        m = np.where(sh, 0.0, m)
        info.update(sinfo)
    mask = Image.fromarray(np.clip(m * 255 + 0.5, 0, 255).astype(np.uint8), "L")
    rgba, ainfo = post.alpha_from_mask(rgb, mask, band_px=band_px, feather=feather)
    rgba, info["dips_filled_px"] = fill_edge_dips(rgba, arr, m > 0.5, np.linalg.norm(arr - bgc, axis=2), band_px,
                                                  solid_dist=solid_dist)
    info["figure_px"] = ainfo["figure_px"]
    info["bg_rgb"] = [round(float(v), 1) for v in post.estimate_bg(arr)]
    return rgba, info


def canvas_fit(rgba, warn=0.9):
    """How big a cut-out figure (any size, e.g. post.candidate_report's half-size cutout) ends up on
    the 1024x2048 canvas, before any render: post.place_on_canvas scales it to ~FIGURE_H tall unless
    the width (with MARGIN on both sides) or the top margin forces it smaller. A figure whose wings,
    weapon or train make it wider than about half its height lands small: every published 832x1216
    Seraphiel candidate so far fits at 75-77 % (the s101000 final canvas: figure 1445 px, crown at
    y=655, where the spec wants ~1900 px and 108). Returns {"fit": fraction of the full size,
    "figure_px": expected canvas height, "aspect": bbox w/h, "limit": "width" | "top" | None,
    "flag": "SMALL nn%" when fit < warn, else None}."""
    m = post.figure_metrics(rgba)
    x0, top, x1, feet = m["bbox"]
    w, h = max(1, x1 - x0), max(1, feet - top)
    full = post.FIGURE_H / h
    by_w = (post.CANVAS[0] - 2 * post.MARGIN) / w
    by_t = (post.FEET_Y - post.MARGIN) / h
    s = min(full, by_w, by_t)
    fit = s / full
    limit = None if fit >= 0.999 else ("width" if by_w <= by_t else "top")
    return {"fit": round(fit, 3), "figure_px": int(round(h * s)), "aspect": round(w / h, 3), "limit": limit,
            "flag": ("SMALL %d%%" % round(100 * fit)) if fit < warn else None}

