#!/usr/bin/env python3
"""Plan an art farm run: validate the workflow_dispatch inputs and build the job matrix.

Inputs arrive ONLY as environment variables (never interpolated into shell by the workflow):
    ART_HEROES   "seraphiel,cassiel" or "all"           (candidates; final uses the keys of ART_SEEDS)
    ART_MODE     candidates | final
    ART_COUNT    candidates per hero, 1..12
    ART_SEEDS    JSON. candidates: optional {"hero": first_seed}. final: {"hero": [seed, ...]} or
                 {"hero": {"seeds": [...], "run": "<run dir>", "flip": true}}
    ART_LABEL    free text, reduced to [a-z0-9-], max 40 chars
    ART_PRESET   a config.PRESETS name
    ART_PER_JOB  candidates per job (0 = one job per hero); splits a hero over parallel jobs
    GITHUB_RUN_ID
Writes `matrix=<json>`, `run_dir=<name>`, `jobs=<n>` lines for $GITHUB_OUTPUT on stdout and a
Markdown summary to $GITHUB_STEP_SUMMARY when set. Exit 2 on invalid input.
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import config as C  # noqa: E402
import prompts  # noqa: E402

HERO_RE = re.compile(r"^[a-z][a-z0-9_]{1,30}$")
RUN_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,80}$")


class PlanError(ValueError):
    pass


def _int(name, raw, lo, hi, default):
    raw = (raw or "").strip()
    if raw == "":
        return default
    if not re.fullmatch(r"\d{1,6}", raw):
        raise PlanError("%s must be an integer, got %r" % (name, raw[:40]))
    v = int(raw)
    if not lo <= v <= hi:
        raise PlanError("%s must be in %d..%d, got %d" % (name, lo, hi, v))
    return v


def _seed(v):
    if isinstance(v, bool) or not isinstance(v, int) or not 0 <= v < 2 ** 32:
        raise PlanError("seeds must be integers in 0..2^32-1, got %r" % (v,))
    return v


def clean_label(raw):
    s = re.sub(r"[^a-z0-9]+", "-", (raw or "").lower()).strip("-")
    return s[:C.LIMITS["label_max"]].strip("-")


def parse_seeds(raw):
    raw = (raw or "").strip() or "{}"
    try:
        d = json.loads(raw)
    except ValueError as e:
        raise PlanError("seeds is not valid JSON: %s" % e)
    if not isinstance(d, dict):
        raise PlanError("seeds must be a JSON object {\"hero\": ...}")
    return d


def build(env, bible):
    mode = (env.get("ART_MODE") or "candidates").strip()
    if mode not in ("candidates", "final"):
        raise PlanError("mode must be candidates or final")
    preset = (env.get("ART_PRESET") or C.DEFAULT_PRESET).strip()
    if preset not in C.PRESETS:
        raise PlanError("preset must be one of %s" % ", ".join(sorted(C.PRESETS)))
    count = _int("count", env.get("ART_COUNT"), 1, C.LIMITS["count_max"], 6)
    per_job = _int("per_job", env.get("ART_PER_JOB"), 0, C.LIMITS["per_job_max"], 0)
    seeds = parse_seeds(env.get("ART_SEEDS"))
    run_id = (env.get("GITHUB_RUN_ID") or "local").strip()
    if not re.fullmatch(r"[0-9]{1,20}|local", run_id):
        raise PlanError("bad GITHUB_RUN_ID")
    label = clean_label(env.get("ART_LABEL"))
    known = list(bible["heroes"])

    def hero_ok(hid):
        if not isinstance(hid, str) or not HERO_RE.match(hid) or hid not in bible["heroes"]:
            raise PlanError("unknown hero %r (known: %s)" % (str(hid)[:40], ", ".join(known)))
        return hid

    for k in seeds:
        hero_ok(k)
    include = []
    if mode == "candidates":
        raw = (env.get("ART_HEROES") or "").strip().lower()
        heroes = known if raw in ("all", "*") else [hero_ok(x) for x in re.split(r"[\s,]+", raw) if x]
        if not heroes:
            raise PlanError("no heroes given")
        heroes = list(dict.fromkeys(heroes))
        for hid in heroes:
            start = seeds.get(hid, bible["heroes"][hid]["seed_base"])
            start = _seed(start)
            if start + count >= 2 ** 32:
                raise PlanError("seed range overflows")
            all_seeds = [start + i for i in range(count)]
            size = per_job or count
            for ci in range(0, count, size):
                chunk = all_seeds[ci:ci + size]
                include.append({"key": "%s-c%d" % (hid, ci // size), "hero": hid,
                                "seeds": ",".join(map(str, chunk)), "flip": "0", "source_run": ""})
    else:
        if not seeds:
            raise PlanError('final mode needs seeds, e.g. {"seraphiel": [101001]}')
        only = (env.get("ART_HEROES") or "").strip().lower()
        narrow = None if only in ("", "all", "*") else {hero_ok(x) for x in re.split(r"[\s,]+", only) if x}
        for hid, spec in seeds.items():
            if narrow is not None and hid not in narrow:
                continue
            flip, run = False, ""
            if isinstance(spec, dict):
                flip = spec.get("flip", False)
                run = spec.get("run", "") or ""
                spec = spec.get("seeds")
            if isinstance(spec, int) and not isinstance(spec, bool):
                spec = [spec]
            if not isinstance(spec, list) or not spec:
                raise PlanError("final seeds for %s must be a non-empty list" % hid)
            if len(spec) > C.LIMITS["final_seeds_max"]:
                raise PlanError("at most %d final seeds per hero" % C.LIMITS["final_seeds_max"])
            if not isinstance(flip, bool):
                raise PlanError("flip must be true/false")
            if run and (not isinstance(run, str) or not RUN_RE.match(run)):
                raise PlanError("bad run name for %s" % hid)
            for s in spec:
                include.append({"key": "%s-f%d" % (hid, _seed(s)), "hero": hid, "seeds": str(_seed(s)),
                                "flip": "1" if flip else "0", "source_run": run})
        if not include:
            raise PlanError("no final jobs after filtering by heroes")
    keys = [e["key"] for e in include]
    if len(set(keys)) != len(keys):
        raise PlanError("duplicate jobs (same hero and seed twice)")
    if len(include) > C.LIMITS["jobs_max"]:
        raise PlanError("%d jobs is more than the limit %d" % (len(include), C.LIMITS["jobs_max"]))
    run_dir = "%s-%s%s" % (run_id, mode, "-" + label if label else "")
    return {"matrix": {"include": include}, "run_dir": run_dir, "jobs": len(include), "mode": mode,
            "preset": preset, "label": label, "count": count}


def main():
    try:
        plan = build(os.environ, prompts.load_bible())
    except PlanError as e:
        print("::error::art-gen plan: %s" % e, file=sys.stderr)
        return 2
    sys.stdout.write("matrix=%s\n" % json.dumps(plan["matrix"], separators=(",", ":")))
    sys.stdout.write("run_dir=%s\n" % plan["run_dir"])
    sys.stdout.write("jobs=%d\n" % plan["jobs"])
    sys.stdout.write("preset=%s\n" % plan["preset"])
    summ = os.environ.get("GITHUB_STEP_SUMMARY")
    if summ:
        with open(summ, "a") as f:
            f.write("### Art farm plan: `%s`\n\n%d job(s), preset `%s`\n\n| job | hero | seeds |\n|---|---|---|\n"
                    % (plan["run_dir"], plan["jobs"], plan["preset"]))
            for e in plan["matrix"]["include"]:
                f.write("| %s | %s | %s |\n" % (e["key"], e["hero"], e["seeds"]))
    print("plan: %s, %d job(s)" % (plan["run_dir"], plan["jobs"]), file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
