#!/usr/bin/env python3
"""Collect art farm artifacts and commit them to the orphan branch `art-gen-output`.

    collect.py --incoming DIR --run-dir NAME [--plan-json JSON] [--push] [--branch-dir DIR]

1. every artifact (one per gen job) is re-verified with safety.verify(): only .png/.webp files
   whose path and sha256 have a pass record in that job's filter manifest survive, plus .json;
2. survivors are merged into runs/<run-dir>/ with one combined manifest;
3. contact sheets (sheet.py) are built and must pass the exposure filter like any image; if the
   filter cannot load here, no sheets are made (fail closed) but the verified images still go in;
4. a final verify() of the whole run dir, then runs/<run-dir>/index.json and the branch-wide
   index.json / README.md;
5. --push: commit only those paths on art-gen-output (created as an orphan branch if missing)
   and push, retrying on races with other runs (fetch, reset, re-apply, push).
Token for the push: env GITHUB_TOKEN (contents: write is granted only to this job).
"""
import argparse
import base64
import glob
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import config as C  # noqa: E402
import safety  # noqa: E402
import sheet  # noqa: E402

BRANCH = "art-gen-output"
README = """# art-gen-output

Generated hero art from the art farm (`.github/workflows/art-gen.yml`, docs in
`docs/dev/art-farm.md` on the main branch). Nothing here is used by the game directly: approved
finals are copied into `assets/art/heroes/<id>/`.

- `runs/<run id>-<mode>[-label]/<hero>/`: candidates (`<hero>_s<seed>.webp` + `.json` metadata) or
  finals (`final_s<seed>/`: 1024x2048 canvas, portrait, variants, masks, metadata), `contact_sheet.png`.
- `runs/<run>/index.json`: jobs, timings, filter statistics. `index.json`: all runs.
- Every image passed an automatic exposure filter (NudeNet + anime censor-point detector) on the
  runner before upload; images that failed were deleted and never uploaded (see each run's index).
- Model: cagliostrolab/animagine-xl-4.0 (CreativeML Open RAIL++-M); candidate rounds may use the
  SDXL-Lightning or LCM LoRA (OpenRAIL++). Licences per image are in its metadata.
"""


def log(*a):
    print(time.strftime("%H:%M:%S"), *a, flush=True)


def read_json(p, default=None):
    try:
        with open(p) as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def merge_artifacts(incoming, stage):
    """Verify each artifact and merge it into stage/. Returns (merged manifest, per-job info)."""
    merged = {"files": {}, "dropped": [], "jobs": {}}
    jobs = []
    for art in sorted(os.listdir(incoming)):
        adir = os.path.join(incoming, art)
        if not os.path.isdir(adir):
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


def make_sheets(stage, merged, filt):
    """Contact sheets through the filter; records them in the merged manifest."""
    made = []
    work = tempfile.mkdtemp(prefix="artgen_sheets_")
    try:
        targets = [(h, os.path.join(work, h, "contact_sheet.png")) for h in sheet.heroes_in(stage)]
        for hero, tmp in targets:
            os.makedirs(os.path.dirname(tmp), exist_ok=True)
            if sheet.hero_sheet(stage, hero, tmp):
                made.append(("%s/contact_sheet.png" % hero, tmp))
        tmp = os.path.join(work, "overview.png")
        if sheet.overview(stage, tmp):
            made.append(("overview.png", tmp))
        published = []
        for rel, tmp in made:
            ok, rep = filt.check_file(tmp)
            if not ok:
                log("FILTER DROPPED sheet %s: %s" % (rel, json.dumps(rep.get("flagged") or rep.get("error"))))
                merged["dropped"].append({"rel": rel, "report": rep, "job": "collect"})
                os.remove(tmp)
                continue
            dest = os.path.join(stage, rel)
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            shutil.move(tmp, dest)
            merged["files"][rel] = {"sha256": safety.sha256_file(dest), "passed": True, "scores": rep["scores"],
                                    "views": rep["views"], "job": "collect"}
            published.append(rel)
        return published
    finally:
        shutil.rmtree(work, ignore_errors=True)


def run_index(run_dir, stage, merged, jobs, plan, sheets, sheet_note):
    heroes = {}
    for rel in sorted(merged["files"]):
        parts = rel.split("/")
        if len(parts) >= 2:
            heroes.setdefault(parts[0], {"images": [], "dropped": 0})["images"].append(rel)
    for d in merged["dropped"]:
        hero = d.get("rel", "").split("/")[0]
        heroes.setdefault(hero, {"images": [], "dropped": 0})["dropped"] += 1
    timing = []
    for j in jobs:
        timing.append({"key": j.get("key"), "hero": j.get("hero"), "mode": j.get("mode"), "preset": j.get("preset"),
                       "wall_s": j.get("wall_s"), "timing": j.get("timing"), "filter": j.get("filter"),
                       "cpu": (j.get("env") or {}).get("cpu"), "skipped": j.get("skipped"),
                       "images": [{k: i.get(k) for k in ("what", "seed", "seconds", "s_per_step", "steps_run",
                                                          "rss_peak_gb")} for i in j.get("images", [])]})
    expected = [e["key"] for e in (plan or {}).get("include", [])]
    got = set(merged["jobs"])
    idx = {"run": run_dir, "created": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
           "jobs_expected": expected, "jobs_missing": [k for k in expected if k not in got],
           "heroes": heroes, "sheets": sheets, "sheet_note": sheet_note, "jobs": timing,
           "filter_totals": {"published_images": len(merged["files"]), "dropped": len(merged["dropped"])},
           "model": C.MODEL, "loras": C.LORAS}
    with open(os.path.join(stage, "index.json"), "w") as f:
        json.dump(idx, f, indent=1)
    return idx


def branch_index(branch_dir):
    runs = []
    for p in sorted(glob.glob(os.path.join(branch_dir, "runs", "*", "index.json"))):
        d = read_json(p, {}) or {}
        runs.append({"run": d.get("run") or os.path.basename(os.path.dirname(p)), "created": d.get("created"),
                     "heroes": sorted((d.get("heroes") or {}).keys()),
                     "published_images": (d.get("filter_totals") or {}).get("published_images"),
                     "dropped": (d.get("filter_totals") or {}).get("dropped")})
    with open(os.path.join(branch_dir, "index.json"), "w") as f:
        json.dump({"branch": BRANCH, "runs": runs}, f, indent=1)
    with open(os.path.join(branch_dir, "README.md"), "w") as f:
        f.write(README)


# ------------------------------------------------------------------ git
def sh(args, cwd, check=True, quiet=False):
    r = subprocess.run(args, cwd=cwd, capture_output=True, text=True)
    if not quiet:
        log("$ %s -> %d %s" % (" ".join(args[:4]), r.returncode, (r.stderr or "").strip()[-300:]))
    if check and r.returncode != 0:
        raise RuntimeError("git failed: %s" % " ".join(args))
    return r


def push(stage, run_dir, branch_dir, repo, token, attempts=6):
    os.makedirs(branch_dir, exist_ok=True)
    if not os.path.isdir(os.path.join(branch_dir, ".git")):
        sh(["git", "init", "-q"], branch_dir)
        sh(["git", "remote", "add", "origin", "https://github.com/%s" % repo], branch_dir)
        if token:
            hdr = base64.b64encode(("x-access-token:%s" % token).encode()).decode()
            subprocess.run(["git", "config", "http.https://github.com/.extraheader", "AUTHORIZATION: basic " + hdr],
                           cwd=branch_dir, check=True)
        sh(["git", "config", "user.name", "art-farm[bot]"], branch_dir)
        sh(["git", "config", "user.email", "41898282+github-actions[bot]@users.noreply.github.com"], branch_dir)
    for attempt in range(1, attempts + 1):
        exists = sh(["git", "ls-remote", "--exit-code", "--heads", "origin", BRANCH], branch_dir, check=False).returncode == 0
        if exists:
            sh(["git", "fetch", "-q", "--depth=1", "origin", BRANCH], branch_dir)
            sh(["git", "checkout", "-q", "-f", "-B", BRANCH, "FETCH_HEAD"], branch_dir)
            sh(["git", "clean", "-q", "-fd"], branch_dir)
        else:                                   # first run: a new orphan branch with no history
            sh(["git", "symbolic-ref", "HEAD", "refs/heads/%s" % BRANCH], branch_dir)
        dest = os.path.join(branch_dir, "runs", run_dir)
        if os.path.exists(dest):
            shutil.rmtree(dest)
        shutil.copytree(stage, dest)
        branch_index(branch_dir)
        sh(["git", "add", "--", os.path.join("runs", run_dir), "index.json", "README.md"], branch_dir)
        if sh(["git", "diff", "--cached", "--quiet"], branch_dir, check=False).returncode == 0:
            log("nothing to commit")
            return True
        sh(["git", "commit", "-q", "-m", "art-gen: %s" % run_dir], branch_dir)
        if sh(["git", "push", "-q", "origin", "HEAD:refs/heads/%s" % BRANCH], branch_dir, check=False).returncode == 0:
            log("pushed runs/%s to %s" % (run_dir, BRANCH))
            return True
        log("push rejected (attempt %d), retrying" % attempt)
        time.sleep(5 * attempt)
    return False


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--incoming", required=True)
    ap.add_argument("--run-dir", required=True)
    ap.add_argument("--plan-json", default=os.environ.get("ART_MATRIX", ""))
    ap.add_argument("--stage", default=None)
    ap.add_argument("--push", action="store_true")
    ap.add_argument("--branch-dir", default=None)
    a = ap.parse_args(argv)
    if not __import__("re").fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,120}", a.run_dir):
        log("ERROR: bad run dir name")
        return 2
    plan = json.loads(a.plan_json) if a.plan_json else {}
    stage = a.stage or tempfile.mkdtemp(prefix="artgen_stage_")
    os.makedirs(stage, exist_ok=True)
    if not os.path.isdir(a.incoming):
        os.makedirs(a.incoming, exist_ok=True)
    merged, jobs = merge_artifacts(a.incoming, stage)
    sheets, note = [], ""
    try:
        filt = safety.ExposureFilter(log=log)
        filt.selftest()
        sheets = make_sheets(stage, merged, filt)
        desc = filt.describe()
    except safety.FilterUnavailable as e:
        note = "no contact sheets: exposure filter unavailable in collect (%s)" % e
        log(note)
        desc = None
    write_manifest(stage, merged, desc)
    res = safety.verify(stage, log=log)           # last gate before the commit
    if res["deleted"]:
        log("final verify removed %d file(s)" % res["deleted"])
    idx = run_index(a.run_dir, stage, merged, jobs, plan, sheets, note)
    log("run %s: %d images, %d dropped, jobs missing: %s" % (
        a.run_dir, idx["filter_totals"]["published_images"], idx["filter_totals"]["dropped"], idx["jobs_missing"]))
    summ = os.environ.get("GITHUB_STEP_SUMMARY")
    if summ:
        with open(summ, "a") as f:
            f.write("### Art farm results `%s`\n\n- published images: %d\n- dropped by the filter: %d\n"
                    "- jobs missing: %s\n- branch: `%s` path `runs/%s/`\n" % (
                        a.run_dir, idx["filter_totals"]["published_images"], idx["filter_totals"]["dropped"],
                        ", ".join(idx["jobs_missing"]) or "none", BRANCH, a.run_dir))
    if a.push:
        repo = os.environ.get("GITHUB_REPOSITORY", "")
        if not repo:
            log("ERROR: GITHUB_REPOSITORY not set")
            return 2
        bdir = a.branch_dir or tempfile.mkdtemp(prefix="artgen_branch_")
        if not push(stage, a.run_dir, bdir, repo, os.environ.get("GITHUB_TOKEN", "")):
            log("ERROR: could not push to %s" % BRANCH)
            return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
