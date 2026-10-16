#!/usr/bin/env python3
"""Sheets job of the art farm: verify the gen artifacts, draw the contact sheets, build one bundle.

    collect.py --incoming DIR --run-dir NAME --out BUNDLE [--plan-json JSON]

Runs in the workflow's `sheets` job, which has `contents: read` only and no token (pip packages and
detector models are allowed here). It never pushes: the separate `publish` job (contents: write,
no pip, stdlib-only tools/artgen/publish.py) merges the bundle into art-gen-output.

1. every artifact (one per gen job) is re-verified with safety.verify(): only .png/.webp files
   whose path and sha256 have a pass record in that job's filter manifest survive, plus .json
   (the images themselves are not re-scored: they passed the filter on the gen runner);
2. survivors are merged into BUNDLE with one combined filter_manifest.json;
3. contact sheets (sheet.py, WebP, titled with the run name) are drawn and run through the exposure
   filter like any image; if the filter cannot load here, no sheets are made (fail closed) but the
   verified images still go in;
4. a final verify() of the bundle, then BUNDLE/index.json (jobs, timings, filter totals, missing jobs)
   and the step summary.
"""
import argparse
import json
import os
import re
import shutil
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import config as C  # noqa: E402
import safety  # noqa: E402
import sheet  # noqa: E402

BRANCH = C.BRANCH
RUN_DIR_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,120}$")


def log(*a):
    print(time.strftime("%H:%M:%S"), *a, flush=True)


def read_json(p, default=None):
    try:
        with open(p) as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def merge_artifacts(incoming, stage):
    """Verify each artifact and merge it into stage/. Returns (merged manifest, per-job records)."""
    merged = {"files": {}, "dropped": [], "jobs": {}}
    jobs = []
    for art in sorted(os.listdir(incoming)):
        adir = os.path.join(incoming, art)
        if not os.path.isdir(adir) or os.path.islink(adir):
            continue
        res = safety.verify(adir, log=log)
        man = read_json(os.path.join(adir, safety.MANIFEST), {}) or {}
        key = (man.get("job") or {}).get("key") or art
        merged["jobs"][key] = {"artifact": art, "verify": {"kept": res["kept"], "deleted": res["deleted"]},
                               "stats": man.get("stats"), "filter": man.get("filter")}
        merged["dropped"] += [dict(d, job=key) for d in man.get("dropped", [])]
        for dp, _dn, fns in os.walk(adir):
            for fn in fns:
                src = os.path.join(dp, fn)
                rel = os.path.relpath(src, adir).replace(os.sep, "/")
                if rel == safety.MANIFEST:
                    continue
                dest = os.path.join(stage, rel)
                if os.path.exists(dest):
                    log("collision on %s from %s: kept the first copy" % (rel, art))
                    continue
                os.makedirs(os.path.dirname(dest), exist_ok=True)
                shutil.copyfile(src, dest)
                if rel in man.get("files", {}):
                    merged["files"][rel] = dict(man["files"][rel], job=key)
                if fn.startswith("job_") and fn.endswith(".json"):
                    jobs.append(read_json(dest, {}))
    return merged, jobs


def write_manifest(stage, merged, filt_desc=None):
    out = {"files": merged["files"], "dropped": merged["dropped"], "jobs": merged["jobs"]}
    if filt_desc:
        out["filter"] = filt_desc
    with open(os.path.join(stage, safety.MANIFEST), "w") as f:
        json.dump(out, f, indent=1)


def make_sheets(stage, merged, filt, run_name=None):
    """Contact sheets (WebP) through the filter; records them in the merged manifest."""
    made = []
    work = tempfile.mkdtemp(prefix="artgen_sheets_")
    try:
        for hero in sheet.heroes_in(stage):
            tmp = os.path.join(work, hero, "contact_sheet.webp")
            os.makedirs(os.path.dirname(tmp), exist_ok=True)
            if sheet.hero_sheet(stage, hero, tmp, run_name=run_name):
                made.append(("%s/contact_sheet.webp" % hero, tmp))
        tmp = os.path.join(work, "overview.webp")
        if sheet.overview(stage, tmp, run_name=run_name):
            made.append(("overview.webp", tmp))
        published = []
        for rel, tmp in made:
            ok, rep = filt.check_file(tmp)
            if not ok:
                log("FILTER DROPPED sheet %s: %s" % (rel, json.dumps(rep.get("flagged") or rep.get("error"))))
                merged["dropped"].append({"rel": rel, "report": rep, "job": "sheets"})
                os.remove(tmp)
                continue
            dest = os.path.join(stage, rel)
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            shutil.move(tmp, dest)
            merged["files"][rel] = {"sha256": safety.sha256_file(dest), "passed": True, "scores": rep["scores"],
                                    "views": rep["views"], "job": "sheets"}
            published.append(rel)
        return published
    finally:
        shutil.rmtree(work, ignore_errors=True)


IMAGE_KEYS = ("what", "step", "seed", "seconds", "s_per_step", "steps_run", "steps_effective", "num_inference_steps",
              "decode", "decode_s", "vmhwm_gb", "rss_peak_gb")


def job_summary(j):
    return {"key": j.get("key"), "hero": j.get("hero"), "mode": j.get("mode"), "preset": j.get("preset"),
            "style": j.get("style"), "dtype": j.get("dtype"), "exit_code": j.get("exit_code"),
            "wall_s": j.get("wall_s"), "timing": j.get("timing"), "filter": j.get("filter"),
            "cpu": (j.get("env") or {}).get("cpu"), "skipped": j.get("skipped"), "errors": j.get("errors"),
            "engine": j.get("engine"), "bench": j.get("bench"),
            "images": [{k: i.get(k) for k in IMAGE_KEYS if k in i} for i in j.get("images", [])]}


def heroes_from(files, dropped):
    heroes = {}
    for rel in sorted(files):
        parts = rel.split("/")
        if len(parts) >= 2:
            heroes.setdefault(parts[0], {"images": [], "dropped": 0})["images"].append(rel)
    for d in dropped:
        rel = d.get("rel", "")
        if "/" in rel:
            heroes.setdefault(rel.split("/")[0], {"images": [], "dropped": 0})["dropped"] += 1
    return heroes


def run_index(run_dir, stage, merged, jobs, plan, sheets, sheet_note):
    expected = [e["key"] for e in (plan or {}).get("include", [])]
    got = set(merged["jobs"])
    idx = {"run": run_dir, "created": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
           "jobs_expected": expected, "jobs_missing": [k for k in expected if k not in got],
           "heroes": heroes_from(merged["files"], merged["dropped"]), "sheets": sheets, "sheet_note": sheet_note,
           "jobs": [job_summary(j) for j in jobs],
           "filter_totals": {"published_images": len(merged["files"]), "dropped": len(merged["dropped"])},
           "model": C.MODEL}
    with open(os.path.join(stage, "index.json"), "w") as f:
        json.dump(idx, f, indent=1)
    return idx


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--incoming", required=True)
    ap.add_argument("--run-dir", required=True)
    ap.add_argument("--out", required=True, help="bundle dir (the run folder's content)")
    ap.add_argument("--plan-json", default=os.environ.get("ART_MATRIX", ""))
    a = ap.parse_args(argv)
    if not RUN_DIR_RE.fullmatch(a.run_dir):
        log("ERROR: bad run dir name")
        return 2
    plan = json.loads(a.plan_json) if a.plan_json else {}
    if os.path.exists(a.out):
        shutil.rmtree(a.out)
    os.makedirs(a.out)
    os.makedirs(a.incoming, exist_ok=True)
    merged, jobs = merge_artifacts(a.incoming, a.out)
    sheets, note = [], ""
    try:
        filt = safety.ExposureFilter(log=log)
        filt.selftest()
        sheets = make_sheets(a.out, merged, filt, run_name=a.run_dir)
        desc = filt.describe()
    except safety.FilterUnavailable as e:
        note = "no contact sheets: exposure filter unavailable in the sheets job (%s)" % e
        log(note)
        desc = None
    write_manifest(a.out, merged, desc)
    res = safety.verify(a.out, log=log)           # last gate before the bundle is uploaded
    if res["deleted"]:
        log("final verify removed %d file(s)" % res["deleted"])
    idx = run_index(a.run_dir, a.out, merged, jobs, plan, sheets, note)
    log("run %s: %d images, %d dropped, jobs missing: %s" % (
        a.run_dir, idx["filter_totals"]["published_images"], idx["filter_totals"]["dropped"], idx["jobs_missing"]))
    summ = os.environ.get("GITHUB_STEP_SUMMARY")
    if summ:
        with open(summ, "a") as f:
            f.write("### Art farm results `%s`\n\n- images in this attempt: %d\n- dropped by the filter: %d\n"
                    "- jobs missing: %s\n- branch: `%s` path `runs/%s/` (merged by the publish job)\n\n"
                    "| job | cpu | exit | wall min | images |\n|---|---|---|---|---|\n" % (
                        a.run_dir, idx["filter_totals"]["published_images"], idx["filter_totals"]["dropped"],
                        ", ".join(idx["jobs_missing"]) or "none", BRANCH, a.run_dir))
            for j in idx["jobs"]:
                f.write("| %s | %s | %s | %.0f | %s |\n" % (
                    j["key"], j.get("cpu") or "?", j.get("exit_code"), (j.get("wall_s") or 0) / 60.0,
                    ", ".join("%s %.0fs %s s/step" % (i.get("what") or i.get("step"), i.get("seconds") or 0,
                                                      i.get("s_per_step")) for i in j["images"] if i.get("seconds"))))
    return 0


if __name__ == "__main__":
    sys.exit(main())
