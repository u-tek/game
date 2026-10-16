#!/usr/bin/env python3
"""Review sheets for art farm results (uses tools/comfy/post.py contact_sheet).

    sheet.py RUN_DIR                 one contact sheet per hero (+ overview.webp) inside RUN_DIR
    sheet.py RUN_DIR --hero ID       one hero only
    sheet.py RUN_DIR --print         list what would be drawn
    sheet.py RUN_DIR --run-name N    title the sheets with N (default: the folder name)

RUN_DIR is runs/<run>/ on the art-gen-output branch (or a downloaded artifact): <hero>/<hero>_s<seed>.webp
candidates with their .json metadata, and/or <hero>/final_s<seed>/ folders. Labels: seed, render time,
preset, framing flags (CROP / EDGE / FILL / BG? from post.candidate_report, SMALL nn% from
cutout.canvas_fit: the figure would fill only nn% of the canvas spec height). Sheets are WebP. In the workflow every sheet passes the
exposure filter before it is committed (collect.py); locally nothing is filtered or uploaded.
"""
import argparse
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import config as C  # noqa: E402,F401  (sys.path for tools/comfy)
import cutout  # noqa: E402
import post  # noqa: E402
from PIL import Image  # noqa: E402

CAND_RE = re.compile(r"^(?P<hero>[a-z0-9_]+)_s(?P<seed>\d+)\.webp$")


def _read(p):
    try:
        with open(p) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def fit_flag(path):
    """cutout.canvas_fit's SMALL flag for a candidate image, or None (also on any error)."""
    try:
        with Image.open(path) as im:
            cut, _rep = post.candidate_report(im.convert("RGB"))
        return cutout.canvas_fit(cut)["flag"]
    except Exception:       # noqa: BLE001  (review aid only)
        return None


def candidate_entries(hero_dir):
    out = []
    for fn in os.listdir(hero_dir):
        m = CAND_RE.match(fn)
        if not m:
            continue
        meta = _read(os.path.join(hero_dir, fn[:-5] + ".json"))
        framing = meta.get("framing") or {}
        flags = list(framing.get("flags") or [])
        if "canvas_fit" not in framing:     # older runs: measure it now (a half-size colour-flood cutout)
            flag = fit_flag(os.path.join(hero_dir, fn))
            if flag:
                flags.append(flag)
        secs = (meta.get("render") or {}).get("seconds")
        label = "s%s" % m.group("seed")
        if secs:
            label += "  %.1fm" % (secs / 60.0)
        if meta.get("preset"):
            label += "  %s" % meta["preset"]
        if flags:
            label += "  " + " ".join(flags)
        out.append((int(m.group("seed")), os.path.join(hero_dir, fn), label))
    return [(p, lab) for _s, p, lab in sorted(out)]


def final_entries(hero_dir, hero):
    out = []
    for d in sorted(os.listdir(hero_dir)):
        fd = os.path.join(hero_dir, d)
        if not (d.startswith("final_s") and os.path.isdir(fd)):
            continue
        canvas = os.path.join(fd, hero + ".png")
        if os.path.exists(canvas):
            out.append((canvas, "%s canvas" % d))
        por = os.path.join(fd, hero + "_portrait.png")
        if os.path.exists(por):
            out.append((por, "%s portrait" % d))
        vdir = os.path.join(fd, "variants")
        if os.path.isdir(vdir):
            for fn in sorted(os.listdir(vdir)):
                if fn.endswith(".png") and not fn.endswith("_patch.png"):
                    out.append((os.path.join(vdir, fn), "%s %s" % (d, fn[:-4])))
    return out


def _save_webp(png_path, out_path, quality=90):
    if out_path.lower().endswith(".webp"):
        with Image.open(png_path) as im:
            im.load()
            im.save(out_path, format="WEBP", quality=quality, method=6)
        os.remove(png_path)
    return out_path


def _draw(entries, out_path, **kw):
    tmp = out_path[:-5] + ".tmp.png" if out_path.lower().endswith(".webp") else out_path
    post.contact_sheet(entries, tmp, **kw)
    return _save_webp(tmp, out_path) if tmp != out_path else out_path


def run_title(run_dir, run_name=None):
    return run_name or os.path.basename(os.path.normpath(run_dir))


def hero_sheet(run_dir, hero, out_path=None, run_name=None):
    hdir = os.path.join(run_dir, hero)
    entries = candidate_entries(hdir) + final_entries(hdir, hero)
    if not entries:
        return None
    out_path = out_path or os.path.join(hdir, "contact_sheet.webp")
    title = "%s  |  %s  |  %d image(s)" % (hero, run_title(run_dir, run_name), len(entries))
    return _draw(entries, out_path, cols=min(6, max(1, len(entries))), cell_w=300, detail=True, title=title)


def overview(run_dir, out_path=None, cell_w=150, run_name=None):
    entries = []
    for hero in sorted(os.listdir(run_dir)):
        hdir = os.path.join(run_dir, hero)
        if os.path.isdir(hdir) and not hero.startswith("_"):
            entries += [(p, os.path.basename(p)[:-5]) for p, _lab in candidate_entries(hdir)]
    if not entries:
        return None
    out_path = out_path or os.path.join(run_dir, "overview.webp")
    return _draw(entries, out_path, cols=min(10, len(entries)), cell_w=cell_w, detail=False,
                 title="%s: all candidates" % run_title(run_dir, run_name))


def heroes_in(run_dir):
    return sorted(h for h in os.listdir(run_dir) if os.path.isdir(os.path.join(run_dir, h)) and not h.startswith("_"))


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("run_dir")
    ap.add_argument("--hero")
    ap.add_argument("--print", action="store_true")
    ap.add_argument("--run-name", default=None)
    a = ap.parse_args(argv)
    heroes = [a.hero] if a.hero else heroes_in(a.run_dir)
    for h in heroes:
        if a.print:
            hdir = os.path.join(a.run_dir, h)
            for p, lab in candidate_entries(hdir) + final_entries(hdir, h):
                print(h, lab, p)
            continue
        p = hero_sheet(a.run_dir, h, run_name=a.run_name)
        if p:
            print("wrote", p)
    if not a.print and not a.hero:
        p = overview(a.run_dir, run_name=a.run_name)
        if p:
            print("wrote", p)
    return 0


if __name__ == "__main__":
    sys.exit(main())
