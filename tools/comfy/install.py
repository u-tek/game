#!/usr/bin/env python3
"""Copy a finished, reviewed hero from art_src/ into the game's asset folder for the HaloRig warp build.

    python3 tools/comfy/install.py <hero_id> [--skin SKIN] [--dry-run] [--force] [--partial]

Copies art_src/<id>/final/<id>.png -> assets/art/heroes/<id>/<id>.png and
art_src/<id>/variants/<name>.png -> assets/art/heroes/<id>/variants/<name>.png (delivery names only:
eyes_open, eyes_closed, mouth_open, smile, hurt). Never touches <id>.warp_src.json, masks/ or anything
else in assets/; writes the rig hand-off art_src/_handoff/<id>.json (origin, portrait, overlay slots
with rects and variant files, fx colour) for whoever builds the warp rig.

Refuses (nothing copied) unless:
  1. final/<id>.json exists and is not a dry run (placeholders are never installed);
  2. final/<id>.png still has the sha256 finalize.py recorded (not edited since);
  3. variants.json was made from that exact image (base_sha), and every variant has the final's alpha
     and differs from it only inside its eyes/mouth region (pixel check, so the rig overlays line up);
  4. every variant in the hero's variant_set exists (--partial installs what is there);
  5. an existing assets/.../<id>.png or variant with DIFFERENT content is replaced only with --force
     (e.g. Seraphiel's vector stand-in). Anything replaced or removed is first copied to
     art_src/<id>/history/installed_<timestamp>/.
Then: write/update assets/art/heroes/<id>/<id>.warp_src.json from the hand-off, and
      tools/art_warp <id> --regen-masks   (docs/dev/halorig.md sections 1 and 8)

--skin <skin id> installs a skin instead: art_src/<id>/skins/<art>/final/<art>.png and its variants ->
assets/art/heroes/<id>/skins/<art>/<art>.png and variants/ (the folder RigData.load_rig(hero, art) reads),
hand-off art_src/_handoff/<id>@<art>.json, rig source <art>.warp_src.json in that folder, rig build
tools/art_warp <id>@<art> --regen-masks. The skin must be in data/skins.json with the same "art".

Only run this once the hero passed review (docs/dev/art-style.md sections 1 and 7).
Env HALO_ASSETS_HEROES overrides the destination root (tests).
"""
import argparse
import json
import os
import shutil
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

from PIL import Image  # noqa: E402

import comfy  # noqa: E402
import pipeline as P  # noqa: E402
import post  # noqa: E402
import prompts  # noqa: E402

DELIVERY_VARIANTS = ("eyes_open", "eyes_closed", "mouth_open", "smile", "hurt")
FX_COLOR = {"celestial": "#ffe9a8", "infernal": "#ff8a3d", "fallen": "#b48cff"}   # art-style.md 4.1
SLOT_KEYS = {"eyes_open": "open", "eyes_closed": "closed", "mouth_open": "open", "smile": "smile", "hurt": "hurt"}


class InstallError(RuntimeError):
    pass


def heroes_root():
    return os.path.abspath(os.environ.get("HALO_ASSETS_HEROES") or os.path.join(comfy.ROOT, "assets", "art", "heroes"))


def handoff_path(hero_id, art="", adult=False):
    name = hero_id + ("@" + art if art else "") + ("@adult" if adult else "")
    return os.path.join(comfy.art_src(), "_handoff", name + ".json")


def game_skin(target):
    """The data/skins.json entry of a skin target; its "art" must match the bible's (the game loads that folder)."""
    path = os.path.join(comfy.ROOT, "data", "skins.json")
    entry = next((sk for sk in (P.read_json(path, {}) or {}).get("skins", []) if sk.get("id") == target["skin"]), None)
    if entry is None:
        raise InstallError("skin %s is not in data/skins.json: the game would never show it" % target["skin"])
    if entry.get("hero") != target["hero"] or entry.get("art") != target["art"]:
        raise InstallError("data/skins.json has %s as %s/%s, the bible as %s/%s: make them agree first" % (
            target["skin"], entry.get("hero"), entry.get("art"), target["hero"], target["art"]))
    return entry


def dest_dir(target):
    d = os.path.join(heroes_root(), target["hero"])
    if target["art"]:
        d = os.path.join(d, "skins", target["art"])
    if target.get("adult"):       # the EroLabs nude set: assets/.../skins/<art>/adult/
        d = os.path.join(d, "adult")
    return d


def rig_id(target):
    """The id tools/art_warp builds: <id> or <id>@<art>."""
    return target["hero"] + ("@" + target["art"] if target["art"] else "")


def _cli(target):
    return target["hero"] + (" --skin " + target["skin"] if target["skin"] else "")


def verify(target, bible, partial=False):
    """Checks 1-4. Returns (final_png, final_meta, record, [(name, src_png, region_name)]) or raises."""
    hero_id, src = target["hero"], target["dir"]
    final = os.path.join(src, "final", target["name"] + ".png")
    fmeta = P.read_json(final[:-4] + ".json")
    if not os.path.exists(final) or fmeta is None:
        raise InstallError("%s or its .json is missing: run finalize.py first" % P.rel(final))
    if fmeta.get("dry_run", True):
        raise InstallError("%s comes from a dry run (placeholder art); render it live" % P.rel(final))
    sha = P.sha256_file(final)
    if fmeta.get("sha256") and fmeta["sha256"] != sha:
        raise InstallError("%s changed after finalize.py (sha256 %s, recorded %s). Re-run finalize.py --force "
                           "instead of editing the final by hand" % (P.rel(final), sha[:12], fmeta["sha256"][:12]))
    record = P.read_json(os.path.join(src, "variants", "variants.json"), {}) or {}
    if record and record.get("base_sha") != sha:
        raise InstallError("variants/variants.json was made from another base image than %s: re-run "
                           "variants.py %s --force" % (P.rel(final), _cli(target)))
    base = Image.open(final).convert("RGBA")
    wanted = list(bible["heroes"][hero_id]["variant_set"])
    found, missing, problems = [], [], []
    for v in DELIVERY_VARIANTS:
        p = os.path.join(src, "variants", v + ".png")
        if not os.path.exists(p):
            if v in wanted:
                missing.append(v)
            continue
        ent = (record.get("variants") or {}).get(v) or {}
        tj = P.read_json(os.path.join(src, "variants", "candidates", "%s_s%s.json" % (v, ent.get("picked_seed"))), {})
        rect = (tj or {}).get("patch_rect") or ent.get("region")
        # variants.py feathers its ellipse mask with a Gaussian of radius max(3, h // 10): allow 4 sigma
        margin = 4 * max(3, int(rect[3]) // 10) + 6 if rect else 12
        for pr in post.variant_alignment(base, Image.open(p), rect, margin=margin):
            problems.append("%s: %s" % (v, pr))
        found.append((v, p, ent.get("region_name") or prompts.variant_spec(bible, hero_id, v)["region"]))
    if problems:
        raise InstallError("variants do not line up with %s:\n  %s\nRe-run variants.py %s --force"
                           % (P.rel(final), "\n  ".join(problems), _cli(target)))
    if missing and not partial:
        raise InstallError("variants missing: %s (variants.py %s), or install without them with --partial"
                           % (", ".join(missing), _cli(target)))
    return final, dict(fmeta, sha256=sha), record, found


def plan_copies(target, final, found):
    dst = dest_dir(target)
    pairs = [(final, os.path.join(dst, target["name"] + ".png"))]
    pairs += [(p, os.path.join(dst, "variants", v + ".png")) for v, p, _ in found]
    names = {v for v, _, _ in found}
    stale = [os.path.join(dst, "variants", v + ".png") for v in DELIVERY_VARIANTS
             if v not in names and os.path.exists(os.path.join(dst, "variants", v + ".png"))]
    return dst, pairs, stale


def handoff(target, bible, fmeta, record, found, dst):
    hero_id, name = target["hero"], target["name"]
    h = bible["heroes"][hero_id]
    hints = dict(fmeta.get("warp_src_hints") or {})
    hints.pop("_doc", None)
    ov = (record or {}).get("warp_overlay_hints") or {}
    base_eyes = "closed" if h.get("default_eyes") == "closed" else "open"
    slots = {"eyes": {"slot": "eyes", "bone": "face", "base": base_eyes, "default": base_eyes, "z": 10,
                      "rect": ov.get("eyes"), "variants": {}},
             "mouth": {"slot": "mouth", "bone": "face", "base": "default", "default": "default", "z": 11,
                       "rect": ov.get("mouth"), "variants": {}}}
    files = {}
    for v, p, region in found:
        rel_path = "variants/%s.png" % v
        files[v] = {"path": comfy.rel(os.path.join(dst, rel_path)), "sha256": P.sha256_file(p),
                    "region": region}
        for slot in (("eyes", "mouth") if region == "eyes_mouth" else (region,)):
            if slot in slots:
                slots[slot]["variants"][SLOT_KEYS[v]] = rel_path
    return {
        "_doc": "Hand-off from tools/comfy/install.py to the HaloRig warp build (docs/dev/halorig.md 8): use these "
                "values in %s, then tools/art_warp %s --regen-masks. Coordinates are pixels of the installed "
                "1024x2048 image." % (comfy.rel(os.path.join(dst, name + ".warp_src.json")), rig_id(target)),
        "hero": hero_id, "skin": target["skin"], "art": target["art"] or None,
        "name": h["name"], "faction": h["faction"], "role": h["role"],
        "installed": time.strftime("%Y-%m-%dT%H:%M:%S"),
        "image": {"path": comfy.rel(os.path.join(dst, name + ".png")), "sha256": fmeta["sha256"]},
        "variants": files,
        "warp_src": {"image": name + ".png", "origin": hints.get("origin", [512, 1990]),
                     "portrait": hints.get("portrait"), "meta": {"fx_color": FX_COLOR.get(h["faction"])},
                     "overlays": [sl for sl in slots.values() if sl["variants"]]},
        "face_box": fmeta.get("face_box"), "flipped": fmeta.get("flipped"),
        "source": {"candidate": fmeta.get("source_candidate"), "seed": fmeta.get("candidate_seed"),
                   "checkpoint": (fmeta.get("settings") or {}).get("checkpoint"),
                   "family": (fmeta.get("settings") or {}).get("family")},
        "brief_gaps": h.get("brief_gaps", []),
    }


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("hero")
    ap.add_argument("--dry-run", action="store_true", help="run every check and list what would be copied")
    ap.add_argument("--force", action="store_true",
                    help="replace existing assets whose content differs (backed up to art_src/<id>/history/ first)")
    ap.add_argument("--partial", action="store_true", help="install even if some variants of variant_set are missing")
    ap.add_argument("--skin", help="skin id (bible 'skins'): install that skin's final into assets/.../skins/<art>/")
    ap.add_argument("--adult", action="store_true",
                    help="install the EroLabs nude variant into assets/.../skins/<art>/adult/ (or "
                         "assets/.../<id>/adult/ for the base look): the tame build's Godot import "
                         "ignores it via .gdignore, and the EroLabs build swaps it over the tame art")
    a = ap.parse_args(argv)
    try:
        bible = prompts.load_bible()
        if a.hero not in bible["heroes"]:
            raise InstallError("unknown hero %r" % a.hero)
        t = P.art_target(bible, a.hero, a.skin, adult=a.adult)
        if t["skin"]:
            game_skin(t)
        final, fmeta, record, found = verify(t, bible, a.partial)
        dst, pairs, stale = plan_copies(t, final, found)
        changed = [d for s, d in pairs if os.path.exists(d) and P.sha256_file(d) != P.sha256_file(s)]
        if (changed or stale) and not a.force:
            raise InstallError("assets already hold different art for %s:\n  %s\nRe-run with --force to replace "
                               "them (they are backed up to %s/history/installed_<timestamp>/ first)" % (
                                   t["label"], "\n  ".join([P.rel(d) + " (differs)" for d in changed] +
                                                           [P.rel(d) + " (not in this delivery)" for d in stale]),
                                   P.rel(t["dir"])))
        verb = "would copy" if a.dry_run else "copy"
        for s, d in pairs:
            same = os.path.exists(d) and P.sha256_file(d) == P.sha256_file(s)
            print("%s %s -> %s%s" % (verb, P.rel(s), P.rel(d), " (identical, skipped)" if same else ""))
        for d in stale:
            print("%s %s (stale variant)" % ("would remove" if a.dry_run else "remove", P.rel(d)))
        if a.dry_run:
            print("dry run: all checks passed; nothing written")
            return 0
        if changed or stale:
            bdir = os.path.join(t["dir"], "history", "installed_" + time.strftime("%Y%m%d-%H%M%S"))
            for d in changed + stale:
                b = os.path.join(bdir, os.path.relpath(d, dst))
                os.makedirs(os.path.dirname(b), exist_ok=True)
                shutil.copy2(d, b)
            print("backed up %d replaced file(s) to %s" % (len(changed) + len(stale), P.rel(bdir)))
        for s, d in pairs:
            if not (os.path.exists(d) and P.sha256_file(d) == P.sha256_file(s)):
                os.makedirs(os.path.dirname(d), exist_ok=True)
                shutil.copyfile(s, d)
        for d in stale:
            os.remove(d)
        vd = os.path.join(dst, "variants")
        if os.path.isdir(vd) and not os.path.exists(os.path.join(vd, ".gdignore")):
            open(os.path.join(vd, ".gdignore"), "w").close()
        if t.get("adult") and not os.path.exists(os.path.join(dst, ".gdignore")):
            open(os.path.join(dst, ".gdignore"), "w").close()     # the tame build ignores the nude set
        ho = handoff(t, bible, fmeta, record, found, dst)
        P.write_json(handoff_path(a.hero, t["art"], adult=bool(a.adult)), ho)
        print("hand-off: %s" % P.rel(handoff_path(a.hero, t["art"], adult=bool(a.adult))))
        print("warp_src hints: %s" % json.dumps(ho["warp_src"]))
        print("next: update %s (start from %s if it is new), then tools/art_warp %s --regen-masks" % (
            P.rel(os.path.join(dst, t["name"] + ".warp_src.json")),
            "%s.warp_src.json" % a.hero if t["art"] else "seraphiel.warp_src.json", rig_id(t)))
    except (InstallError, P.PipelineError, KeyError, OSError) as e:
        print("ERROR: %s" % e, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
