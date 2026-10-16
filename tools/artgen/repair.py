"""Cover repair planning (torch-free): from the exposure detectors' boxes to inpaint crops and masks.

gen.publish_screened() calls this when the exposure filter flags an image. Only the flagged regions are
repainted (with the hero's opaque outfit material, style.cover), and the repaired image must pass the
full filter again before it can be published; the unrepaired original never reaches the upload dir.

    boxes (safety.ExposureFilter.flag_boxes, image px)
      -> each box padded by config REPAIR pad on every side and to at least min_side px
      -> overlapping regions merged
      -> refused when there are more than max_regions or they cover more than max_area_frac of the image
         (not a local slip: the image is dropped as before)
      -> regions grouped into square crops (context x the group size, at least crop_min px, at most
         cluster_max_frac x the short image side), one inpaint per crop
"""
from PIL import Image, ImageDraw

import config as C


def _grow(box, pad, min_side, size):
    x0, y0, x1, y1 = box
    w, h = max(1.0, x1 - x0), max(1.0, y1 - y0)
    cx, cy = (x0 + x1) / 2.0, (y0 + y1) / 2.0
    w2, h2 = max(min_side, w * (1 + 2 * pad)), max(min_side, h * (1 + 2 * pad))
    W, H = size
    return [max(0, int(cx - w2 / 2)), max(0, int(cy - h2 / 2)), min(W, int(round(cx + w2 / 2))),
            min(H, int(round(cy + h2 / 2)))]


def _overlap(a, b):
    return a[0] < b[2] and b[0] < a[2] and a[1] < b[3] and b[1] < a[3]


def _union(a, b):
    return [min(a[0], b[0]), min(a[1], b[1]), max(a[2], b[2]), max(a[3], b[3])]


def merge(rects):
    """Merge overlapping [x0, y0, x1, y1] rects until none overlap."""
    rects = [list(r) for r in rects]
    changed = True
    while changed:
        changed = False
        out = []
        for r in rects:
            for o in out:
                if _overlap(r, o):
                    o[:] = _union(o, r)
                    changed = True
                    break
            else:
                out.append(list(r))
        rects = out
    return sorted(rects, key=lambda r: (r[1], r[0]))


def _square(rect, size, context, crop_min):
    """Square crop (x0, y0, x1, y1) around rect: side = context x its longer side, >= crop_min, clamped."""
    W, H = size
    x0, y0, x1, y1 = rect
    side = int(round(max(x1 - x0, y1 - y0) * context))
    side = min(max(side, crop_min), W, H)
    cx, cy = (x0 + x1) / 2.0, (y0 + y1) / 2.0
    cx0 = int(round(min(max(cx - side / 2.0, 0), W - side)))
    cy0 = int(round(min(max(cy - side / 2.0, 0), H - side)))
    return [cx0, cy0, cx0 + side, cy0 + side]


def _contains(crop, rect):
    return crop[0] <= rect[0] and crop[1] <= rect[1] and crop[2] >= rect[2] and crop[3] >= rect[3]


def plan(boxes, size, cfg=None):
    """{"ok", "why", "regions": [[x0, y0, x1, y1]], "area_frac", "clusters": [{"crop", "regions"}]}."""
    cfg = cfg or C.REPAIR
    W, H = size
    if not boxes:
        return {"ok": False, "why": "the detectors returned no boxes to cover", "regions": [], "clusters": [],
                "area_frac": 0.0}
    rects = merge(_grow(b["box"] if isinstance(b, dict) else b, cfg["pad"], cfg["min_side"], size) for b in boxes)
    area = sum((r[2] - r[0]) * (r[3] - r[1]) for r in rects) / float(W * H)
    res = {"ok": False, "why": None, "regions": rects, "clusters": [], "area_frac": round(area, 4)}
    if len(rects) > cfg["max_regions"]:
        res["why"] = "%d separate regions (max %d): not a local slip" % (len(rects), cfg["max_regions"])
        return res
    if area > cfg["max_area_frac"]:
        res["why"] = "regions cover %.0f%% of the image (max %.0f%%): not a local slip" % (
            100 * area, 100 * cfg["max_area_frac"])
        return res
    limit = cfg["cluster_max_frac"] * min(W, H)
    groups = []
    for r in rects:
        for g in groups:
            u = _union(g["bbox"], r)
            if max(u[2] - u[0], u[3] - u[1]) * cfg["context"] <= limit:
                g["bbox"], g["regions"] = u, g["regions"] + [r]
                break
        else:
            groups.append({"bbox": list(r), "regions": [r]})
    for g in groups:
        crop = _square(g["bbox"], size, cfg["context"], cfg["crop_min"])
        if not all(_contains(crop, r) for r in g["regions"]):
            # a region larger than the image's short side cannot be inpainted in one square crop
            res["why"] = "region %s does not fit a square crop" % (g["bbox"],)
            return res
        res["clusters"].append({"crop": crop, "regions": g["regions"]})
    res["ok"] = True
    return res


def mask(size, regions):
    """Full-size L mask, white rectangles = repaint (crop_inpaint grows and feathers it)."""
    m = Image.new("L", size, 0)
    d = ImageDraw.Draw(m)
    for x0, y0, x1, y1 in regions:
        d.rectangle([x0, y0, x1 - 1, y1 - 1], fill=255)
    return m
