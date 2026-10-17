#!/usr/bin/env python3
"""Whole-roster helpers for the art pipeline.

    python3 tools/comfy/roster.py status [--dry-run] [--json]
        one line per hero: background, candidates (and how many carry check flags), chosen master,
        variants done / needed, installed in assets/ (same / differs), rig hand-off written
    python3 tools/comfy/roster.py candidates [--count N] [--heroes a,b,...] [--seed-offset N] [--dry-run] [run_hero flags]
        run_hero.py for each hero in roster order (starters, legendaries, epics, rares). Existing
        seeds are skipped, so re-running only fills gaps; one hero failing does not stop the rest.
        --seed-offset N starts each hero at its seed_base + N, for a new round beside the old seeds.

Roster order: uriela, kessa, lucen (starters), seraphiel, mordessa, noctaire (legendaries), cassiel,
liora, brakka, vesper, orrin, sable (epics), nuriel, imra, ashra (rares).
"""
import argparse
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import comfy  # noqa: E402
import install  # noqa: E402
import pipeline as P  # noqa: E402
import prompts  # noqa: E402

ORDER = ["uriela", "kessa", "lucen", "seraphiel", "mordessa", "noctaire", "cassiel", "liora", "brakka", "vesper",
         "orrin", "sable", "nuriel", "imra", "ashra"]


def roster(bible):
    return [h for h in ORDER if h in bible["heroes"]] + [h for h in bible["heroes"] if h not in ORDER]


def hero_status(bible, hero_id, dry_run=False):
    import run_hero
    h = bible["heroes"][hero_id]
    hdir = P.hero_dir(hero_id, dry_run)
    cands = run_hero.candidate_paths(os.path.join(hdir, "candidates"), hero_id)
    flagged = sum(1 for _, p in cands if ((P.read_json(p[:-4] + ".json", {}) or {}).get("check") or {}).get("flags"))
    fm = P.read_json(os.path.join(hdir, "final", hero_id + ".json"), {}) or {}
    rec = P.read_json(os.path.join(hdir, "variants", "variants.json"), {}) or {}
    need = list(h["variant_set"])
    have = [v for v in need if os.path.exists(os.path.join(hdir, "variants", v + ".png"))]
    stale = bool(rec) and bool(fm.get("sha256")) and rec.get("base_sha") != fm.get("sha256")
    dst = os.path.join(install.heroes_root(), hero_id, hero_id + ".png")
    final = os.path.join(hdir, "final", hero_id + ".png")
    if not os.path.exists(dst):
        inst = "-"
    elif os.path.exists(final) and P.sha256_file(dst) == P.sha256_file(final):
        inst = "same"
    else:
        inst = "differs"
    return {"hero": hero_id, "background": prompts.background(bible, hero_id)[0], "candidates": len(cands),
            "flagged": flagged, "master_seed": fm.get("candidate_seed"), "final": os.path.exists(final),
            "variants": "%d/%d%s" % (len(have), len(need), " STALE" if stale else ""),
            "installed": inst, "handoff": os.path.exists(install.handoff_path(hero_id))}


def cmd_status(a):
    bible = prompts.load_bible()
    rows = [hero_status(bible, hid, a.dry_run) for hid in roster(bible)]
    if a.json:
        print(json.dumps(rows, indent=1))
        return 0
    print("%-10s %-6s %-16s %-8s %-11s %-9s %s" % ("hero", "bg", "candidates", "master", "variants", "assets", "hand-off"))
    for r in rows:
        print("%-10s %-6s %-16s %-8s %-11s %-9s %s" % (
            r["hero"], r["background"], "%d (%d flagged)" % (r["candidates"], r["flagged"]) if r["candidates"] else "-",
            "s%s" % r["master_seed"] if r["final"] else "-", r["variants"], r["installed"], "yes" if r["handoff"] else "-"))
    done = sum(1 for r in rows if r["handoff"])
    print("%d/%d heroes handed to the rig build%s" % (done, len(rows), " (dry run folder)" if a.dry_run else ""))
    return 0


def cmd_candidates(a, rest):
    import run_hero
    bible = prompts.load_bible()
    heroes = [x.strip() for x in a.heroes.split(",")] if a.heroes else roster(bible)
    failed = []
    for hid in heroes:
        print("== %s" % hid, flush=True)
        argv = [hid, "--count", str(a.count)] + (["--dry-run"] if a.dry_run else []) + rest
        if a.seed_offset is not None:
            argv += ["--seed", str(int(bible["heroes"][hid]["seed_base"]) + a.seed_offset)]
        if run_hero.main(argv) != 0:
            failed.append(hid)
    if failed:
        print("FAILED: %s" % ", ".join(failed), file=sys.stderr)
        return 1
    print("contact sheets: art_src/%s<id>/candidates/contact_sheet.png" % ("_dryrun/" if a.dry_run else ""))
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    st = sub.add_parser("status")
    st.add_argument("--dry-run", action="store_true", help="report on art_src/_dryrun/ instead")
    st.add_argument("--json", action="store_true")
    ca = sub.add_parser("candidates", help="run_hero.py for many heroes; unknown flags pass through")
    ca.add_argument("--count", type=int, default=8)
    ca.add_argument("--heroes", help="comma list (default: all, roster order)")
    ca.add_argument("--dry-run", action="store_true")
    ca.add_argument("--seed-offset", type=int,
                    help="first seed = each hero's seed_base + N (a new round that can't collide with earlier seeds)")
    a, rest = ap.parse_known_args(argv)
    if a.cmd == "candidates" and a.seed_offset is not None and "--seed" in rest:
        ap.error("--seed-offset and --seed together")
    if a.cmd == "status":
        if rest:
            ap.error("unknown arguments: %s" % " ".join(rest))
        return cmd_status(a)
    return cmd_candidates(a, rest)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (comfy.ComfyError, P.PipelineError) as e:
        print("ERROR: %s" % e, file=sys.stderr)
        sys.exit(1)
