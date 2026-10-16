#!/usr/bin/env python3
"""Plan an art farm run: validate the workflow_dispatch inputs and build the job matrix.

Inputs arrive ONLY as environment variables (never interpolated into shell by the workflow):
    ART_HEROES   "seraphiel,cassiel" or "all"           (candidates; final: optional filter on the ART_SEEDS keys;
                                                         bench: the hero whose prompt is timed, default seraphiel)
    ART_MODE     candidates | final | bench
    ART_COUNT    candidates per hero, 1..12 (bench: jobs, 1..3)
    ART_SEEDS    JSON. candidates: optional {"hero": first_seed}.
                 final: {"hero": {"seeds": [...], "run": "<candidate run dir>", "flip": true}} (run required)
    ART_LABEL    free text, reduced to [a-z0-9-], max 40 chars
    ART_PRESET   a config.PRESETS name (CFG must pass config.preset_problems: > 1 and within 4-7)
    ART_STYLE    a config.STYLES name (farm | bible)
    ART_DTYPE    fp32 | bf16 (bf16: candidates and bench only)
    ART_PER_JOB  candidates per job (0 = one job per hero); splits a hero over parallel jobs
    GITHUB_RUN_ID
Writes `matrix=<json>`, `run_dir=<name>`, `jobs=<n>`, `preset=`, `style=`, `dtype=` lines for
$GITHUB_OUTPUT on stdout and a Markdown summary to $GITHUB_STEP_SUMMARY when set. Exit 2 on invalid input.
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
    if mode not in ("candidates", "final", "bench"):
        raise PlanError("mode must be candidates, final or bench")
    preset = (env.get("ART_PRESET") or C.DEFAULT_PRESET).strip()
    if preset not in C.PRESETS:
        raise PlanError("preset must be one of %s" % ", ".join(sorted(C.PRESETS)))
    probs = C.preset_problems(C.PRESETS[preset])
    if probs:
        raise PlanError("preset %s refused: %s" % (preset, "; ".join(probs)))
    sty = (env.get("ART_STYLE") or C.DEFAULT_STYLE).strip()
    if sty not in C.STYLES:
        raise PlanError("style must be one of %s" % ", ".join(sorted(C.STYLES)))
    dtype = (env.get("ART_DTYPE") or C.DEFAULT_DTYPE).strip()
    if dtype not in C.DTYPES:
        raise PlanError("dtype must be one of %s" % ", ".join(C.DTYPES))
    if mode == "final" and dtype != "fp32":
        raise PlanError("final mode runs in fp32 only (bf16 is for candidates and bench)")
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
    limit = C.LIMITS["jobs_max"]
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
    elif mode == "bench":
        limit = C.LIMITS["bench_jobs_max"]
        raw = (env.get("ART_HEROES") or "").strip().lower()
        hid = hero_ok(re.split(r"[\s,]+", raw)[0]) if raw and raw not in ("all", "*") else "seraphiel"
        if count > limit:
            raise PlanError("bench runs at most %d jobs" % limit)
        for i in range(count):
            include.append({"key": "bench-%d" % i, "hero": hid, "seeds": "1", "flip": "0", "source_run": ""})
    else:
        limit = C.LIMITS["final_jobs_max"]
        if not seeds:
            raise PlanError('final mode needs seeds, e.g. {"seraphiel": {"seeds": [101000], "run": "<run dir>"}}')
        only = (env.get("ART_HEROES") or "").strip().lower()
        narrow = None if only in ("", "all", "*") else {hero_ok(x) for x in re.split(r"[\s,]+", only) if x}
        for hid, spec in seeds.items():
            if narrow is not None and hid not in narrow:
                continue
            if not isinstance(spec, dict):
                raise PlanError('final seeds for %s must name the candidate run: {"seeds": [...], "run": "<run dir>"}' % hid)
            flip = spec.get("flip", False)
            run = spec.get("run", "")
            spec = spec.get("seeds")
            if isinstance(spec, int) and not isinstance(spec, bool):
                spec = [spec]
            if not isinstance(spec, list) or not spec:
                raise PlanError("final seeds for %s must be a non-empty list" % hid)
            if len(spec) > C.LIMITS["final_seeds_max"]:
                raise PlanError("at most %d final seeds per hero" % C.LIMITS["final_seeds_max"])
            if not isinstance(flip, bool):
                raise PlanError("flip must be true/false")
            if not isinstance(run, str) or not RUN_RE.match(run) or not re.match(r"^[0-9]+-candidates", run):
                raise PlanError("final seeds for %s need \"run\": the candidate run dir (<run id>-candidates[-label])" % hid)
            for s in spec:
                include.append({"key": "%s-f%d" % (hid, _seed(s)), "hero": hid, "seeds": str(_seed(s)),
                                "flip": "1" if flip else "0", "source_run": run})
        if not include:
            raise PlanError("no final jobs after filtering by heroes")
    keys = [e["key"] for e in include]
    if len(set(keys)) != len(keys):
        raise PlanError("duplicate jobs (same hero and seed twice)")
    if len(include) > limit:
        raise PlanError("%d jobs is more than the %s limit %d" % (len(include), mode, limit))
    run_dir = "%s-%s%s" % (run_id, mode, "-" + label if label else "")
    return {"matrix": {"include": include}, "run_dir": run_dir, "jobs": len(include), "mode": mode,
            "preset": preset, "style": sty, "dtype": dtype, "label": label, "count": count}


def main():
    try:
        plan = build(os.environ, prompts.load_bible())
    except PlanError as e:
        print("::error::art-gen plan: %s" % e, file=sys.stderr)
        return 2
    sys.stdout.write("matrix=%s\n" % json.dumps(plan["matrix"], separators=(",", ":")))
    sys.stdout.write("run_dir=%s\n" % plan["run_dir"])
    sys.stdout.write("jobs=%d\n" % plan["jobs"])
    for k in ("preset", "style", "dtype", "mode"):
        sys.stdout.write("%s=%s\n" % (k, plan[k]))
    summ = os.environ.get("GITHUB_STEP_SUMMARY")
    if summ:
        p = C.PRESETS[plan["preset"]]
        with open(summ, "a") as f:
            f.write("### Art farm plan: `%s`\n\n%d job(s), preset `%s` (%s, %d steps, CFG %g, %dx%d), style `%s`, "
                    "dtype `%s`\n\n| job | hero | seeds | source run |\n|---|---|---|---|\n"
                    % (plan["run_dir"], plan["jobs"], plan["preset"], p["sampler"], p["steps"], p["cfg"], p["width"],
                       p["height"], plan["style"], plan["dtype"]))
            for e in plan["matrix"]["include"]:
                f.write("| %s | %s | %s | %s |\n" % (e["key"], e["hero"], e["seeds"], e["source_run"] or "-"))
    print("plan: %s, %d job(s)" % (plan["run_dir"], plan["jobs"]), file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
