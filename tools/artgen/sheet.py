#!/usr/bin/env python3
"""Review sheets for art farm results (uses tools/comfy/post.py contact_sheet).

    sheet.py RUN_DIR                 one contact sheet per hero (+ overview.png) inside RUN_DIR
    sheet.py RUN_DIR --hero ID       one hero only
    sheet.py RUN_DIR --print         list what would be drawn

RUN_DIR is runs/<run>/ on the art-gen-output branch (or a downloaded artifact): <hero>/<hero>_s<seed>.webp
candidates with their .json metadata, and/or <hero>/final_s<seed>/ folders. Labels: seed, render time,
framing flags (CROP / EDGE / FILL from post.candidate_report). In the workflow every sheet passes the
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
import post  # noqa: E402
from PIL import Image  # noqa: E402

CAND_RE = re.compile(r"^(?P<hero>[a-z0-9_]+)_s(?P<seed>\d+)\.webp$")


def _read(p):
    try:
        with open(p) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def candidate_entries(hero_dir):
    out = []
    for fn in os.listdir(hero_dir):
        m = CAND_RE.match(fn)
        if not m:
            continue
        meta = _read(os.path.join(hero_dir, fn[:-5] + ".json"))
        flags = (meta.get("framing") or {}).get("flags") or []
        secs = (meta.get("render") or {}).get("seconds")
        label = "s%s" % m.group("seed")
        if secs:
            label += "  %.1fm" % (secs / 60.0)
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


def hero_sheet(run_dir, hero, out_path=None):
    hdir = os.path.join(run_dir, hero)
    entries = candidate_entries(hdir) + final_entries(hdir, hero)
    if not entries:
        return None
    out_path = out_path or os.path.join(hdir, "contact_sheet.png")
    title = "%s  |  %s  |  %d image(s)" % (hero, os.path.basename(os.path.normpath(run_dir)), len(entries))
    post.contact_sheet(entries, out_path, cols=min(6, max(1, len(entries))), cell_w=300, detail=True, title=title)
    return out_path


def overview(run_dir, out_path=None, cell_w=150):
    entries = []
    for hero in sorted(os.listdir(run_dir)):
        hdir = os.path.join(run_dir, hero)
        if os.path.isdir(hdir) and not hero.startswith("_"):
            entries += [(p, os.path.basename(p)[:-5]) for p, _lab in candidate_entries(hdir)]
    if not entries:
        return None
    out_path = out_path or os.path.join(run_dir, "overview.png")
    post.contact_sheet(entries, out_path, cols=min(10, len(entries)), cell_w=cell_w, detail=False,
                       title="%s: all candidates" % os.path.basename(os.path.normpath(run_dir)))
    return out_path


def heroes_in(run_dir):
    return sorted(h for h in os.listdir(run_dir) if os.path.isdir(os.path.join(run_dir, h)) and not h.startswith("_"))


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("run_dir")
    ap.add_argument("--hero")
    ap.add_argument("--print", action="store_true")
    a = ap.parse_args(argv)
    heroes = [a.hero] if a.hero else heroes_in(a.run_dir)
    for h in heroes:
        if a.print:
            hdir = os.path.join(a.run_dir, h)
            for p, lab in candidate_entries(hdir) + final_entries(hdir, h):
                print(h, lab, p)
            continue
        p = hero_sheet(a.run_dir, h)
        if p:
            print("wrote", p)
    if not a.print and not a.hero:
        p = overview(a.run_dir)
        if p:
            print("wrote", p)
    return 0


if __name__ == "__main__":
    sys.exit(main())
