"""Shared pieces of the layered rigs (tools/layered/<hero>_rig.py): the parts of seraphiel_rig.py that every
heroine needs, plus the SAM route that stands in for See-through.

The SAM route (2026-11-04: See-through was removed from the PC to free disk, and reinstalling it needs the
owner's go): every moving part (arms, breasts, the held prop, wings, back hair) is cut from the rig-pose final
with SAM masks (sam_cut.py), and whatever the part covered on the layers behind it is found geometrically
(behind()) and painted in: roughly here (cv2 inpaint from the layer's own pixels), then by the image model
(fill_hidden.py) where it will show.
"""
import os

import cv2
import numpy as np
from PIL import Image
from scipy import ndimage

W, H = 1024, 2048
YY, XX = np.mgrid[0:H, 0:W]


def load_rgba(path):
    return np.asarray(Image.open(path).convert("RGBA")).astype(np.float32)


def load_mask(path, thr=127):
    return np.asarray(Image.open(path).convert("L")) > thr


def save_rgba(path, img):
    Image.fromarray(np.clip(img, 0, 255).astype(np.uint8), "RGBA").save(path)


def save_mask(path, m):
    Image.fromarray((np.clip(m.astype(np.float32), 0, 1) * 255).astype(np.uint8)).save(path)


def bleed(rgba, solid=245):
    """Half-transparent pixels take the colour of the nearest solid pixel: no dark or grey fringes."""
    a = rgba[..., 3]
    sol = a >= solid
    if not sol.any():
        return rgba
    _, (iy, ix) = ndimage.distance_transform_edt(~sol, return_indices=True)
    out = rgba.copy()
    edge = ~sol
    out[edge, :3] = rgba[iy[edge], ix[edge], :3]
    return out


def clean(m, close=4, open_=2, keep_largest=True, smooth=1.5):
    """A SAM mask tidied: holes filled, specks gone, the largest piece, a smooth edge."""
    if close:
        m = ndimage.binary_closing(m, iterations=close)
    m = ndimage.binary_fill_holes(m)
    if open_:
        m = ndimage.binary_opening(m, iterations=open_)
    lab, n = ndimage.label(m)
    if n > 1:
        s = ndimage.sum(m, lab, range(1, n + 1))
        # the largest piece, or (a part something in front splits) every piece but the specks
        m = lab == (int(np.argmax(s)) + 1) if keep_largest else np.isin(lab, [k + 1 for k, v in enumerate(s) if v >= 300])
    if smooth:
        m = ndimage.gaussian_filter(m.astype(np.float32), smooth) > 0.5
    return m


def cut(final, m, soft=0.8):
    """The painting's pixels inside mask m, with a soft edge."""
    a = ndimage.gaussian_filter(m.astype(np.float32), soft) if soft else m.astype(np.float32)
    img = final.copy()
    img[..., 3] = np.minimum(final[..., 3], a * 255)
    return img


def seg_dist(a, b):
    a, b = np.array(a, float), np.array(b, float)
    ab = b - a
    t = np.clip(((XX - a[0]) * ab[0] + (YY - a[1]) * ab[1]) / max(ab @ ab, 1e-6), 0, 1)
    return np.hypot(XX - a[0] - t * ab[0], YY - a[1] - t * ab[1])


def behind(front, rest, reach=28):
    """Pixels of `front` (a part cut out) that had something behind them: where the rest of her
    (everything else, `rest`) closes over the gap the part leaves. A part held clear of her body
    leaves no hole (only backdrop was behind it); an arm across her side or a lance over a wing does."""
    k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * reach + 1, 2 * reach + 1))
    closed = cv2.morphologyEx(rest.astype(np.uint8), cv2.MORPH_CLOSE, k) > 0
    closed = ndimage.binary_fill_holes(closed)
    return front & closed


def rough_fill(layer, hole, radius=9):
    """A layer with `hole` painted roughly from its own solid pixels (cv2 Telea inpaint), alpha 255 there."""
    solid = (layer[..., 3] > 200) & ~hole
    rgb = np.clip(layer[..., :3], 0, 255).astype(np.uint8)
    if solid.any():
        _, (iy, ix) = ndimage.distance_transform_edt(~solid, return_indices=True)
        rgb = rgb.copy()
        rgb[~solid] = rgb[iy[~solid], ix[~solid]]
    inp = cv2.cvtColor(cv2.inpaint(cv2.cvtColor(rgb, cv2.COLOR_RGB2BGR), hole.astype(np.uint8) * 255, radius,
                                   cv2.INPAINT_TELEA), cv2.COLOR_BGR2RGB)
    out = layer.copy()
    out[hole, :3] = inp[hole]
    out[hole, 3] = 255
    return out


def under_band(layer, cover, px=36):
    """The band a back layer (wings, back hair) continues in under the layer in front (`cover`): `px` px
    next to its visible edge, inside `cover`, so a sway or a raised arm never opens a gap at its root."""
    vis = layer[..., 3] > 127
    return ndimage.binary_dilation(vis, iterations=px) & cover & ~vis


def strand_fill(layer, hole, reach=120, warm=None):
    """Hair behind something in front of it, continued along its strands: each hole pixel takes the colour
    of the nearest solid hair pixel straight above it (within `reach` px; else straight below), so hanging
    hair carries on as strands instead of a blurred smear. Pixels with no hair above or below stay clear."""
    # (from the hair's own colour, not its dark outline or a strap's edge: those copied as grey stripes)
    lum = layer[..., :3].mean(axis=2)
    solid = (layer[..., 3] > 200) & ~hole & (lum > np.percentile(lum[layer[..., 3] > 200], 25) if (layer[..., 3] > 200).any() else True)
    if warm is not None:
        # warm hair (blonde, red): a strap or a white edge caught in the mask is not hair
        solid &= (layer[..., 0] - layer[..., 2]) > warm
    out = layer.copy()
    ys, xs = np.nonzero(hole)
    if not len(ys):
        return out
    for x in np.unique(xs):
        col_solid = np.nonzero(solid[:, x])[0]
        if not len(col_solid):
            continue
        hy = ys[xs == x]
        idx = np.searchsorted(col_solid, hy)
        above = np.where(idx > 0, col_solid[np.maximum(idx - 1, 0)], -10 ** 6)
        below = np.where(idx < len(col_solid), col_solid[np.minimum(idx, len(col_solid) - 1)], 10 ** 6)
        use_above = (hy - above) <= reach
        use_below = ~use_above & ((below - hy) <= reach)
        src = np.where(use_above, above, below)
        ok = use_above | use_below
        out[hy[ok], x, :3] = layer[src[ok], x, :3]
        out[hy[ok], x, 3] = 255
    # a hair's breadth of sideways softening, so the copied columns don't band
    sm = cv2.GaussianBlur(out[..., :3], (0, 0), sigmaX=0.9, sigmaY=0.3)
    filled = hole & (out[..., 3] > 0)
    out[filled, :3] = sm[filled]
    return out


def extend_under(layer, cover, px=36):
    """The layer with under_band() filled roughly from its own pixels."""
    band = under_band(layer, cover, px)
    return rough_fill(layer, band, radius=5) if band.any() else layer


def apply_repaint(layer, hole, path, clear_backdrop=True):
    """The image model's repaint (fill_hidden.py; the picked try copied to `path`) wins inside `hole`.
    Where it painted her narrower than the hole it left the flat grey backdrop: cleared."""
    if not os.path.exists(path):
        return layer, False
    rep = load_rgba(path)
    keep = hole.copy()
    if clear_backdrop:
        bgk = (np.abs(rep[..., :3] - 128.0) < 14.0).all(axis=2)
        bgk = ndimage.binary_opening(bgk, iterations=2)
        layer = layer.copy()
        layer[hole & bgk, 3] = 0
        keep &= ~bgk
    out = layer.copy()
    out[keep] = rep[keep]
    return out, True


def split_arm(arm_img, chain, cap_r):
    """An arm layer cut by the nearest bone segment into the upper arm and the forearm with the hand, both
    keeping a disc round the elbow (a cap): bent, the forearm's cap covers the joint like a ball joint.
    chain: shoulder, elbow, wrist, fingertip."""
    dseg = np.stack([seg_dist(chain[k], chain[k + 1]) for k in range(3)])
    nearest = np.argmin(dseg, axis=0)
    cap = np.hypot(XX - chain[1][0], YY - chain[1][1]) <= cap_r
    out = {}
    for piece, want in (("up", nearest == 0), ("fore", nearest >= 1)):
        m = ndimage.gaussian_filter((want | cap).astype(np.float32), 0.8)
        pc = arm_img.copy()
        pc[..., 3] *= m
        out[piece] = pc
    return out


def breast_weights(m, cleave, sign):
    """Grey-level weights for a breast piece: 0 along its top edge (it stays on the chest), full from 70 px
    down, the outer side a little less; and the lower pole's (full over the underside)."""
    ys, xs = np.nonzero(m)
    ytop = np.full(W, H, np.float32)
    np.minimum.at(ytop, xs, ys.astype(np.float32))
    ytop = ndimage.minimum_filter1d(ytop, 9)
    u = np.clip((YY - ytop[None, :]) / 70.0, 0, 1)
    w = u * u * (3 - 2 * u)
    outer = np.clip(((XX - cleave) * sign - 95) / 25.0, 0, 1)
    w *= 1.0 - 0.35 * outer
    u2 = np.clip((YY - ytop[None, :] - 45.0) / 55.0, 0, 1)
    lo = (u2 * u2 * (3 - 2 * u2)) * (1.0 - 0.35 * outer)
    return w * m, lo * m


def torso_fill(body, hole, inside):
    """The torso behind the breasts: each column continues straight up from just under the hole (its
    outfit and skin there), softened sideways, darker the deeper under the breast. Inside her silhouette
    only (`inside`); returns (body, the pixels painted)."""
    known = (body[..., 3] > 200) & ~hole
    fill = np.zeros((H, W, 3), np.float32)
    have = np.zeros((H, W), bool)
    dist_up = np.zeros((H, W), np.float32)
    for x in range(W):
        col = np.nonzero(hole[:, x])[0]
        if not len(col):
            continue
        yb = int(col.max())
        ys_k = np.nonzero(known[yb + 1:yb + 24, x])[0]
        if not len(ys_k):
            continue
        y0 = yb + 1 + int(ys_k[0])
        seg = body[y0 + 3:y0 + 15, x, :3][known[y0 + 3:y0 + 15, x]]
        if not len(seg):
            continue
        fill[col, x] = np.median(seg, axis=0)
        have[col, x] = True
        dist_up[col, x] = yb - col
    put = hole & (have | inside)
    miss = put & ~have
    if miss.any():
        src_ok = known | have
        pool = np.where(have[..., None], fill, body[..., :3])
        _, (iy, ix) = ndimage.distance_transform_edt(~src_ok, return_indices=True)
        fill[miss] = pool[iy[miss], ix[miss]]
        dist_up[miss] = 30.0
    fill = cv2.GaussianBlur(fill, (0, 0), sigmaX=1.6, sigmaY=0.8)
    shade = 1.0 - 0.16 * np.clip(dist_up / 30.0, 0, 1)
    out = body.copy()
    out[put, :3] = fill[put] * shade[put, None]
    out[put, 3] = 255
    return out, put


def eye_whites(body, final, iris_m, lash_m):
    """The white under each iris (the iris is its own piece and darts about): painted from the visible
    sclera, with the lid's shadow along its top."""
    under = ndimage.binary_dilation(iris_m, iterations=3) & ~lash_m
    fin_rgb = final[..., :3]
    bright = (fin_rgb.min(axis=2) > 222) & (fin_rgb.max(axis=2) - fin_rgb.min(axis=2) < 26)
    near_eye = ndimage.binary_dilation(iris_m, iterations=9) & ~iris_m & bright
    sclera = np.median(fin_rgb[near_eye], axis=0) if near_eye.any() else np.array([246.0, 244.0, 248.0])
    lab_e, n_e = ndimage.label(ndimage.binary_dilation(iris_m, iterations=4))
    out = body.copy()
    for k in range(1, n_e + 1):
        sel = under & (lab_e == k)
        if not sel.any():
            continue
        ys_e = np.nonzero(sel)[0]
        t = (YY - ys_e.min()) / max(ys_e.max() - ys_e.min(), 1)
        shade_e = 0.76 + 0.24 * np.clip(t, 0, 1) ** 0.7
        out[sel, :3] = sclera[None, :] * shade_e[sel, None]
        out[sel, 3] = 255
    return out, n_e, sclera


def write_layers(rig_dir, name, imgs, z_order, st_dir):
    """Each layer cropped to its pixels as <name>_<layer>.png; its mask in st/. Returns image rects."""
    rects = {}
    for rl, z in z_order.items():
        img = bleed(np.clip(imgs[rl], 0, 255))
        pil = Image.fromarray(img.astype(np.uint8), "RGBA")
        al = np.asarray(pil)[..., 3]
        ys, xs = np.nonzero(al > 4)
        x0, y0, x1, y1 = int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1
        pil.crop((x0, y0, x1, y1)).save(os.path.join(rig_dir, "%s_%s.png" % (name, rl)))
        rects[rl] = [x0, y0, x1 - x0, y1 - y0]
        save_mask(os.path.join(st_dir, rl + ".png"), al > 127)
        print("layer %-11s z %4d rect %s" % (rl, z, rects[rl]))
    return rects


def diff_rect(path, final, center, half=90, pad=4):
    """The box where a face variant differs from the final, looked for within `half` (px, or (x, y)) of
    `center`: keep the mouth's box off the eyes, or a talking mouth flickers the eyes the model repainted."""
    hx, hy = (half, half) if isinstance(half, (int, float)) else half
    v = load_rgba(path)
    d = np.abs(v[..., :3] - final[..., :3]).max(axis=2) > 18
    d &= (np.abs(np.arange(H) - center[1])[:, None] < hy) & (np.abs(np.arange(W) - center[0])[None, :] < hx)
    ys, xs = np.nonzero(d)
    if not len(xs):
        return None
    return [int(xs.min()) - pad, int(ys.min()) - pad, int(xs.max() - xs.min()) + 2 * pad, int(ys.max() - ys.min()) + 2 * pad]


def union(rs):
    rs = [r for r in rs if r]
    x0 = min(r[0] for r in rs)
    y0 = min(r[1] for r in rs)
    return [x0, y0, max(r[0] + r[2] for r in rs) - x0, max(r[1] + r[3] for r in rs) - y0]
