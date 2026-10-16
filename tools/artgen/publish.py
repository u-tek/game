#!/usr/bin/env python3
"""Publish job of the art farm: merge a verified bundle into art-gen-output and push. STDLIB ONLY.

    publish.py --bundle DIR --run-dir NAME [--repo OWNER/NAME] [--remote-url URL] [--work DIR] [--no-push]

This is the only code that runs with `contents: write`. It runs on the runner's system python3 with
no pip installs (a test parses this file and allows standard-library imports only), so no third-party
package ever runs next to the token. The token comes from env GITHUB_TOKEN and reaches git only
through GIT_CONFIG_* environment variables of the git processes (never written to .git/config).

1. verify_bundle: no symlinks; only .png/.webp/.json; every image needs a passing record in the
   bundle's filter_manifest.json with a matching sha256 and the PNG/WebP magic bytes; JSON must
   parse. Anything else is deleted. (The detectors ran on the gen runners and in the sheets job;
   this re-checks integrity and file type, not content.)
2. partial, sparse clone of art-gen-output (only runs/<run>/, index.json, README.md are checked out).
3. MERGE, never delete: bundle files are copied over (same name = replaced), filter_manifest.json
   and the run's index.json are merged (files/jobs by key, dropped de-duplicated), the branch-wide
   index.json entry for this run is updated. A re-run, or a re-run after the artifacts expired, can
   add or replace files but never removes published ones.
4. final_gate: every image under runs/<run>/ must have a passing manifest record with a matching
   sha256 (and magic bytes); otherwise nothing is pushed (fail closed).
5. commit and push; on a rejected push: fetch, reset, re-apply the merge, retry (6 attempts).
"""
import argparse
import base64
import datetime
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

# kept in sync with tools/artgen/config.py and safety.py by test_artgen.py
BRANCH = "art-gen-output"
UPLOAD_IMAGE_EXTS = (".png", ".webp")
UPLOAD_TEXT_EXTS = (".json",)
MANIFEST = "filter_manifest.json"
RUN_DIR_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,120}$")
REPO_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9-]{0,38}/[A-Za-z0-9._-]{1,100}$")
PNG_MAGIC = b"\x89PNG\r\n\x1a\n"

README = """# art-gen-output

Generated hero art from the art farm (`.github/workflows/art-gen.yml`, docs in
`docs/dev/art-farm.md` on the main branch). Nothing here is used by the game directly: approved
finals are copied into `assets/art/heroes/<id>/`.

- `runs/<run id>-<mode>[-label]/<hero>/`: candidates (`<hero>_s<seed>.webp` + `.json` metadata) or
  finals (`final_s<seed>/`: `_hires.webp`, `_source.webp`, the 1024x2048 canvas `<hero>.png`, portrait,
  `_check.webp`, `_boxes.webp`, variants, masks, `variants_sheet.webp`, metadata), `contact_sheet.webp`.
- `runs/<run>/index.json`: jobs, timings, memory, filter statistics. `index.json`: all runs.
- Every image passed an automatic exposure filter (NudeNet + anime censor-point detector) on the
  runner before upload; images that failed were deleted and never uploaded (see each run's index).
- Model: cagliostrolab/animagine-xl-4.0 (CreativeML Open RAIL++-M), no LoRA. Settings per image are
  in its metadata.
"""


def log(*a):
    print(time.strftime("%H:%M:%S"), *a, flush=True)


def now():
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def read_json(p, default=None):
    try:
        with open(p) as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def write_json(p, obj):
    with open(p, "w") as f:
        json.dump(obj, f, indent=1)


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def magic_ok(path):
    with open(path, "rb") as f:
        head = f.read(16)
    low = path.lower()
    if low.endswith(".png"):
        return head.startswith(PNG_MAGIC)
    if low.endswith(".webp"):
        return head[:4] == b"RIFF" and head[8:12] == b"WEBP"
    return False


# ------------------------------------------------------------------ 1. bundle verification
def verify_bundle(bundle):
    """Delete anything in the bundle that is not a verified image or valid JSON.
    Returns ({"kept", "deleted", "reasons"}, manifest)."""
    res = {"kept": 0, "deleted": 0, "reasons": []}
    man = read_json(os.path.join(bundle, MANIFEST), None)
    if not isinstance(man, dict) or not isinstance(man.get("files"), dict):
        res["reasons"].append("no readable manifest: every image is deleted")
        man = {"files": {}, "dropped": [], "jobs": {}}
    files = man["files"]

    def drop(p, why):
        if os.path.islink(p) or os.path.isfile(p):
            os.remove(p)
        else:
            shutil.rmtree(p, ignore_errors=True)
        res["deleted"] += 1
        res["reasons"].append("%s: %s" % (os.path.relpath(p, bundle), why))

    for dirpath, dirnames, filenames in os.walk(bundle):
        for d in list(dirnames):
            if os.path.islink(os.path.join(dirpath, d)):
                drop(os.path.join(dirpath, d), "symlinked directory")
                dirnames.remove(d)
        for fn in filenames:
            p = os.path.join(dirpath, fn)
            rel = os.path.relpath(p, bundle).replace(os.sep, "/")
            low = fn.lower()
            if os.path.islink(p):
                drop(p, "symlink")
            elif low.endswith(UPLOAD_IMAGE_EXTS):
                rec = files.get(rel)
                if not isinstance(rec, dict) or rec.get("passed") is not True:
                    drop(p, "image without a filter pass record")
                elif rec.get("sha256") != sha256_file(p):
                    drop(p, "image changed after the filter (sha256)")
                elif not magic_ok(p):
                    drop(p, "not a PNG/WebP file")
                else:
                    res["kept"] += 1
            elif low.endswith(UPLOAD_TEXT_EXTS):
                try:
                    with open(p) as f:
                        json.load(f)
                    res["kept"] += 1
                except (OSError, ValueError):
                    drop(p, "not valid JSON")
            else:
                drop(p, "file type not allowed")
    for r in res["reasons"]:
        log("verify_bundle: " + r)
    log("verify_bundle: kept %d, deleted %d" % (res["kept"], res["deleted"]))
    return res, man


# ------------------------------------------------------------------ 3. merge
def merge_manifest(old, new):
    old = old if isinstance(old, dict) else {}
    out = {"files": dict(old.get("files") or {}), "dropped": [], "jobs": dict(old.get("jobs") or {})}
    out["files"].update(new.get("files") or {})
    out["jobs"].update(new.get("jobs") or {})
    seen = set()
    for d in list(old.get("dropped") or []) + list(new.get("dropped") or []):
        k = (d.get("rel"), d.get("job"))
        if k in seen:
            continue
        seen.add(k)
        out["dropped"].append(d)
    if new.get("filter") or old.get("filter"):
        out["filter"] = new.get("filter") or old.get("filter")
    return out


def heroes_from(files, dropped):
    heroes = {}
    for rel in sorted(files):
        parts = rel.split("/")
        if len(parts) >= 2:
            heroes.setdefault(parts[0], {"images": [], "dropped": 0})["images"].append(rel)
    for d in dropped:
        rel = d.get("rel", "") or ""
        if "/" in rel:
            heroes.setdefault(rel.split("/")[0], {"images": [], "dropped": 0})["dropped"] += 1
    return heroes


def merge_index(old, new, man, run_dir):
    old = old if isinstance(old, dict) else {}
    new = new if isinstance(new, dict) else {}
    jobs = {}
    for j in list(old.get("jobs") or []) + list(new.get("jobs") or []):
        if isinstance(j, dict) and j.get("key"):
            jobs[j["key"]] = j
    expected = list(dict.fromkeys(list(old.get("jobs_expected") or []) + list(new.get("jobs_expected") or [])))
    got = set(man.get("jobs") or {})
    idx = dict(old)
    idx.update(new)
    idx.update({"run": run_dir, "created": old.get("created") or new.get("created") or now(), "updated": now(),
                "jobs": [jobs[k] for k in sorted(jobs)], "jobs_expected": expected,
                "jobs_missing": [k for k in expected if k not in got],
                "heroes": heroes_from(man["files"], man["dropped"]),
                "sheets": sorted(set(old.get("sheets") or []) | set(new.get("sheets") or [])),
                "filter_totals": {"published_images": len(man["files"]), "dropped": len(man["dropped"])}})
    return idx


def apply_bundle(bundle, branch_dir, run_dir):
    """Copy the bundle into runs/<run_dir>/ (replace same names, never delete) and merge the JSON
    indexes. Returns the merged run index."""
    dest = os.path.join(branch_dir, "runs", run_dir)
    os.makedirs(dest, exist_ok=True)
    new_man = read_json(os.path.join(bundle, MANIFEST), {}) or {}
    new_idx = read_json(os.path.join(bundle, "index.json"), {}) or {}
    old_man = read_json(os.path.join(dest, MANIFEST), {}) or {}
    old_idx = read_json(os.path.join(dest, "index.json"), {}) or {}
    for dirpath, _dirnames, filenames in os.walk(bundle):
        for fn in filenames:
            src = os.path.join(dirpath, fn)
            rel = os.path.relpath(src, bundle).replace(os.sep, "/")
            if rel in (MANIFEST, "index.json"):
                continue
            out = os.path.join(dest, rel)
            os.makedirs(os.path.dirname(out), exist_ok=True)
            if os.path.islink(out):
                os.remove(out)
            shutil.copyfile(src, out)
    man = merge_manifest(old_man, new_man)
    write_json(os.path.join(dest, MANIFEST), man)
    idx = merge_index(old_idx, new_idx, man, run_dir)
    write_json(os.path.join(dest, "index.json"), idx)
    update_branch_index(branch_dir, run_dir, idx)
    return idx


def update_branch_index(branch_dir, run_dir, idx):
    p = os.path.join(branch_dir, "index.json")
    cur = read_json(p, {}) or {}
    runs = [r for r in (cur.get("runs") or []) if isinstance(r, dict) and r.get("run") != run_dir]
    runs.append({"run": run_dir, "created": idx.get("created"), "updated": idx.get("updated"),
                 "heroes": sorted((idx.get("heroes") or {}).keys()),
                 "published_images": (idx.get("filter_totals") or {}).get("published_images"),
                 "dropped": (idx.get("filter_totals") or {}).get("dropped"),
                 "jobs_missing": idx.get("jobs_missing")})
    runs.sort(key=lambda r: str(r.get("run")))
    write_json(p, {"branch": BRANCH, "runs": runs})
    with open(os.path.join(branch_dir, "README.md"), "w") as f:
        f.write(README)


# ------------------------------------------------------------------ 4. gate
def final_gate(run_path):
    """[] when every image under run_path has a passing record with a matching sha256 in the run's
    merged manifest, and nothing else but JSON is there; else the problems (nothing is pushed)."""
    man = read_json(os.path.join(run_path, MANIFEST), None)
    if not isinstance(man, dict):
        return ["no readable merged manifest"]
    files = man.get("files") or {}
    probs = []
    for dirpath, dirnames, filenames in os.walk(run_path):
        for d in dirnames:
            if os.path.islink(os.path.join(dirpath, d)):
                probs.append("symlinked directory %s" % d)
        for fn in filenames:
            p = os.path.join(dirpath, fn)
            rel = os.path.relpath(p, run_path).replace(os.sep, "/")
            if os.path.islink(p):
                probs.append("%s: symlink" % rel)
            elif fn.lower().endswith(UPLOAD_IMAGE_EXTS):
                rec = files.get(rel)
                if not isinstance(rec, dict) or rec.get("passed") is not True:
                    probs.append("%s: no filter pass record" % rel)
                elif rec.get("sha256") != sha256_file(p):
                    probs.append("%s: sha256 does not match its record" % rel)
                elif not magic_ok(p):
                    probs.append("%s: not a PNG/WebP file" % rel)
            elif not fn.lower().endswith(UPLOAD_TEXT_EXTS):
                probs.append("%s: file type not allowed" % rel)
    return probs


# ------------------------------------------------------------------ 2./5. git
def git_env(token):
    env = dict(os.environ)
    env.update({"GIT_TERMINAL_PROMPT": "0", "GIT_AUTHOR_NAME": "art-farm[bot]", "GIT_COMMITTER_NAME": "art-farm[bot]",
                "GIT_AUTHOR_EMAIL": "41898282+github-actions[bot]@users.noreply.github.com",
                "GIT_COMMITTER_EMAIL": "41898282+github-actions[bot]@users.noreply.github.com"})
    if token:
        hdr = base64.b64encode(("x-access-token:%s" % token).encode()).decode()
        env.update({"GIT_CONFIG_COUNT": "1", "GIT_CONFIG_KEY_0": "http.https://github.com/.extraheader",
                    "GIT_CONFIG_VALUE_0": "AUTHORIZATION: basic " + hdr})
    return env


def sh(args, cwd, env, check=True):
    r = subprocess.run(args, cwd=cwd, env=env, capture_output=True, text=True)
    log("$ %s -> %d %s" % (" ".join(args[:5]), r.returncode, (r.stderr or "").strip()[-300:]))
    if check and r.returncode != 0:
        raise RuntimeError("git failed: %s" % " ".join(args[:5]))
    return r


def checkout(remote, work, run_dir, env):
    """Partial, sparse clone of the output branch (or a new orphan branch). Returns True if it existed."""
    if os.path.exists(work):
        shutil.rmtree(work)
    ls = sh(["git", "ls-remote", "--exit-code", "--heads", remote, BRANCH], None, env, check=False)
    if ls.returncode == 0:
        sh(["git", "clone", "-q", "--depth=1", "--filter=blob:none", "--sparse", "--single-branch", "--branch", BRANCH,
            remote, work], None, env)
        sh(["git", "sparse-checkout", "set", "--no-cone", "/runs/%s/" % run_dir, "/index.json", "/README.md"], work, env)
        return True
    if ls.returncode != 2:
        raise RuntimeError("cannot reach %s (git ls-remote exit %d)" % (remote, ls.returncode))
    os.makedirs(work)
    sh(["git", "init", "-q"], work, env)
    sh(["git", "remote", "add", "origin", remote], work, env)
    sh(["git", "symbolic-ref", "HEAD", "refs/heads/%s" % BRANCH], work, env)
    return False


def publish(bundle, run_dir, remote, work, token="", attempts=6, push=True):
    env = git_env(token)
    existed = checkout(remote, work, run_dir, env)
    for attempt in range(1, attempts + 1):
        idx = apply_bundle(bundle, work, run_dir)
        probs = final_gate(os.path.join(work, "runs", run_dir))
        if probs:
            for p in probs:
                log("final_gate: " + p)
            log("ERROR: final gate failed: nothing pushed")
            return False
        sh(["git", "add", "--", "runs/%s" % run_dir, "index.json", "README.md"], work, env)
        if sh(["git", "diff", "--cached", "--quiet"], work, env, check=False).returncode == 0:
            log("nothing to commit")
            return True
        sh(["git", "commit", "-q", "-m", "art-gen: %s (%d images, %d dropped)" % (
            run_dir, idx["filter_totals"]["published_images"], idx["filter_totals"]["dropped"])], work, env)
        if not push:
            log("--no-push: committed locally in %s" % work)
            return True
        if sh(["git", "push", "-q", "origin", "HEAD:refs/heads/%s" % BRANCH], work, env, check=False).returncode == 0:
            log("pushed runs/%s to %s" % (run_dir, BRANCH))
            return True
        log("push rejected (attempt %d), re-applying on the new tip" % attempt)
        time.sleep(5 * attempt)
        if existed or sh(["git", "ls-remote", "--exit-code", "--heads", "origin", BRANCH], work, env,
                         check=False).returncode == 0:
            sh(["git", "fetch", "-q", "--depth=1", "origin", BRANCH], work, env)
            sh(["git", "reset", "-q", "--hard", "FETCH_HEAD"], work, env)
            existed = True
    return False


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--bundle", required=True)
    ap.add_argument("--run-dir", required=True)
    ap.add_argument("--repo", default=os.environ.get("GITHUB_REPOSITORY", ""))
    ap.add_argument("--remote-url", default=None, help="default https://github.com/<repo> (tests: a local bare repo)")
    ap.add_argument("--work", default=None)
    ap.add_argument("--no-push", action="store_true")
    a = ap.parse_args(argv)
    if not RUN_DIR_RE.match(a.run_dir):
        log("ERROR: bad run dir name")
        return 2
    if not a.remote_url and not REPO_RE.match(a.repo or ""):
        log("ERROR: bad or missing --repo / GITHUB_REPOSITORY")
        return 2
    if not os.path.isdir(a.bundle):
        log("ERROR: no bundle at %s" % a.bundle)
        return 2
    res, _man = verify_bundle(a.bundle)
    if res["kept"] == 0:
        log("ERROR: empty bundle after verification: nothing to publish")
        return 1
    remote = a.remote_url or "https://github.com/%s" % a.repo
    work = a.work or tempfile.mkdtemp(prefix="artgen_branch_")
    ok = publish(a.bundle, a.run_dir, remote, work, os.environ.get("GITHUB_TOKEN", ""), push=not a.no_push)
    summ = os.environ.get("GITHUB_STEP_SUMMARY")
    if summ and ok:
        idx = read_json(os.path.join(work, "runs", a.run_dir, "index.json"), {}) or {}
        with open(summ, "a") as f:
            f.write("### Published `runs/%s/` on `%s`\n\n- images in the run folder: %s\n- dropped: %s\n"
                    "- jobs missing: %s\n" % (a.run_dir, BRANCH, idx.get("filter_totals", {}).get("published_images"),
                                              idx.get("filter_totals", {}).get("dropped"),
                                              ", ".join(idx.get("jobs_missing") or []) or "none"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
