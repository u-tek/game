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
           minus the ground shadow: in the bottom `shadow_band` of the figure, smooth pixels with the
             background's chromaticity and 35-97% of its luminance (darker than the backdrop, so a
             white gown never matches), flood-filled from the background;
  then post.alpha_from_mask for the edge unmixing and despill.

Without an isnet mask (rembg failed to load) the colour-flood cutout is the figure mask.
"""
import numpy as np
from PIL import Image

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
                  ring_px=2, max_frac=0.8):
    """Boolean mask of the cast shadow under the figure (subset of `figure`), and an info dict.
    A shadow lies flat on the floor: a found region that reaches the top of the bottom band (a dark,
    background-tinted hem or boot rather than a shadow) is left alone."""
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
    shade = rows & figure & (cd < chroma_tol) & (ratio >= lum_range[0]) & (ratio <= lum_range[1])
    cand = shade & (_grad(lum) < grad_max)
    seed = cand & post.dilate(~figure, 1)
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


def artgen_cutout(img, isnet_mask=None, hole_tol=12.0, hole_min=24, max_hole_frac=0.06, shadow=True,
                  bg_tol=26.0, solid_dist=40.0, close_px=8, band_px=2, feather=0.7):
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
        closed = post.erode(post.dilate(m > 0.5, close_px), close_px)      # small gaps inside the figure
        firm = (m < 1.0) & (dist > solid_dist) & ((m > 0.5) | closed)
        m = np.where(haze, 0.0, np.where(firm, 1.0, m))
        info.update({"hole_px": int(holes.sum()), "haze_px": int(haze.sum()), "firmed_px": int(firm.sum())})
    if shadow:
        sh, sinfo = ground_shadow(arr, bgc, m > 0.02)
        m = np.where(sh, 0.0, m)
        info.update(sinfo)
    mask = Image.fromarray(np.clip(m * 255 + 0.5, 0, 255).astype(np.uint8), "L")
    rgba, ainfo = post.alpha_from_mask(rgb, mask, band_px=band_px, feather=feather)
    info["figure_px"] = ainfo["figure_px"]
    info["bg_rgb"] = [round(float(v), 1) for v in post.estimate_bg(arr)]
    return rgba, info
