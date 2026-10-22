#!/usr/bin/env python3
"""Checked roster run (owner, 2026-10-22: "before the highres fix are you able to check that everything is correct").
Every hero and skin gets 2 MOSS base candidates (seed_base + 1780 and + 1781; 2 more per regenerate). A pick,
from Claude's review or from the owner in picker.py, is finished (face pass + 2x, install --partial --force, quick
rig, warp build), which puts it in the game's assets on this PC.

State in <run>/qa/: picks.json {key: seed}, rerolls.json {key: n}, owner_picks.json {key: seed}, done/<key>.ok
(the seed now in the game), review/NNN_<key>.jpg (the 2x master), log.txt, worker.pid. Keys: "<hero>" or
"<hero>@<art>". Stop: create <run>/pause.
    python tools/comfy/roster_qa.py [--run DIR]      (exits when nothing is left to render or finish)"""
import argparse
import glob
import json
import os
import subprocess
import sys
import time

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
DEFAULT_RUN = os.path.join(ROOT, "art_src", "_review", "vB_run")
OFFSET = 1780
PY = sys.executable


def qa_dir(run):
    return os.path.join(run, "qa")


def items(adult=False):
    """[(hero, skin id or None, art or None, first seed)]: the 40 heroes, then the skins in bible order. adult: the
    nude set (only looks with an "adult" prompt block; seeds +5000 like pipeline.art_target)."""
    b = json.load(open(os.path.join(ROOT, "data", "art_prompts.json"), encoding="utf-8"))
    off = OFFSET + (5000 if adult else 0)
    out = [(h, None, None, v.get("seed_base", 100) + off) for h, v in b["heroes"].items()
           if not adult or isinstance(v.get("adult"), dict)]
    out += [(s["hero"], sid, s["art"], s.get("seed_base", 100) + off) for sid, s in b["skins"].items()
            if not adult or isinstance(s.get("adult"), dict)]
    return out


def key_of(hero, art):
    return "%s@%s" % (hero, art) if art else hero


def cdir(hero, art, adult=False):
    d = os.path.join(ROOT, "art_src", hero, "skins", art) if art else os.path.join(ROOT, "art_src", hero)
    return os.path.join(d, "adult") if adult else d


def candidate(hero, art, seed, adult=False):
    for p in glob.glob(os.path.join(cdir(hero, art, adult), "candidates", "*_s%d.png" % seed)):
        if not p.endswith("_cut.png"):
            return p
    return None


def wanted(s0, rerolls):
    return [s0 + k for k in range(2 + 2 * int(rerolls))]


LOW_POSES = ("sitting", "kneeling", "on her knees", "lying", "all fours")


def nude_size(hero, sid):
    """Sitting, kneeling and lying nude poses render square so knees, wings and feet fit (owner, 2026-10-22: "i dont
    want the sitting down ones to be cropped"); None keeps the family size."""
    import prompts as P
    b = P.load_bible()
    h = P.skin_view(b, hero, sid, adult=True) if sid else P.hero_view(b, hero, adult=True)
    pose = P._nude_pose(b["families"]["moss"], h)
    return "1024x1024" if any(w in pose for w in LOW_POSES) else None


def is_adult(run):
    """<run>/qa/config.json {"adult": true, "after": "<other run dir>"} makes a run the nude set."""
    return bool(load(run, "config.json").get("adult"))


def load(run, name):
    try:
        return json.load(open(os.path.join(qa_dir(run), name), encoding="utf-8"))
    except (OSError, ValueError):
        return {}


def save(run, name, data):
    p = os.path.join(qa_dir(run), name)
    tmp = p + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=1)
    os.replace(tmp, p)


def done_info(run, key):
    """The done marker: {"seed": n, ...}, {"failed": "..."} or None."""
    try:
        return json.load(open(os.path.join(qa_dir(run), "done", key + ".ok"), encoding="utf-8"))
    except (OSError, ValueError):
        return None


def pid_alive(pid):
    if os.name == "nt":     # os.kill(pid, 0) would terminate the process on Windows
        r = subprocess.run(["tasklist", "/FI", "PID eq %d" % pid, "/NH", "/FO", "CSV"], capture_output=True, text=True,
                           creationflags=0x08000000)
        return '"%d"' % pid in r.stdout
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def worker_pid(run):
    try:
        pid = int(open(os.path.join(qa_dir(run), "worker.pid")).read().strip())
    except (OSError, ValueError):
        return None
    return pid if pid_alive(pid) else None


def pending(run):
    """(picks to finish, candidates to render) as lists of (index, hero, skin, art, seed). Renders for items the
    owner asked to regenerate come last (owner: "i want it saved and regenerated later")."""
    picks, rerolls = load(run, "picks.json"), load(run, "rerolls.json")
    adult = is_adult(run)
    fin, ren = [], []
    for i, (hero, sid, art, s0) in enumerate(items(adult)):
        key = key_of(hero, art)
        if key in picks:
            if done_info(run, key) is None:
                fin.append((i, hero, sid, art, int(picks[key])))
            continue
        for s in wanted(s0, rerolls.get(key, 0)):
            if not candidate(hero, art, s, adult):
                ren.append((i, hero, sid, art, s))
    ren.sort(key=lambda r: int(rerolls.get(key_of(r[1], r[3]), 0)) > 0)     # stable: first-run renders first
    return fin, ren


class Worker:
    def __init__(self, run):
        self.run = run
        self.qa = qa_dir(run)
        for d in ("done", "review"):
            os.makedirs(os.path.join(self.qa, d), exist_ok=True)
        self.logf = open(os.path.join(self.qa, "log.txt"), "a", encoding="utf-8")
        self.adult = is_adult(run)
        after = load(run, "config.json").get("after")
        self.after = os.path.join(ROOT, after) if after else None
        os.environ.setdefault("COMFYUI_URL", "http://127.0.0.1:8188")

    def log(self, msg):
        line = "%s %s" % (time.strftime("%H:%M:%S", time.gmtime()), msg)
        print(line, flush=True)
        self.logf.write(line + "\n")
        self.logf.flush()

    def step(self, args, what):
        r = subprocess.run([PY] + args, cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace")
        if r.returncode:
            raise RuntimeError("%s failed: %s" % (what, (r.stdout + r.stderr).strip().splitlines()[-3:]))

    def finish(self, i, n, hero, sid, art, seed):
        from PIL import Image
        key = key_of(hero, art)
        t0 = time.time()
        sk = (["--skin", sid] if sid else []) + (["--adult"] if self.adult else [])
        tdir = cdir(hero, art, self.adult)
        rig = key + (("@adult" if art else "@@adult") if self.adult else "")
        self.step(["tools/comfy/finalize.py", hero, str(seed), "--force"] + sk, "finalize")
        meta = json.load(open(os.path.join(tdir, "final", (art or hero) + ".json"), encoding="utf-8"))
        self.step(["tools/comfy/install.py", hero, "--partial", "--force"] + sk, "install")
        self.step(["tools/art_quick_rig.py", rig, "--face", ",".join(map(str, meta["face_box"])), "--seed", str(seed)],
                  "quick rig")
        self.step(["tools/art_warp_build.py", rig, "--regen-masks"], "warp build")
        ups = sorted(glob.glob(os.path.join(tdir, "work", "*_up.png")), key=os.path.getmtime)
        src = ups[-1] if ups else os.path.join(tdir, "final", (art or hero) + ".png")
        Image.open(src).convert("RGB").save(
            os.path.join(self.qa, "review", "%03d_%s.jpg" % (i + 1, key.replace("@", "_"))), quality=90)
        with open(os.path.join(self.qa, "done", key + ".ok"), "w") as f:
            json.dump({"seed": seed, "face": meta["face_box"]}, f)
        self.log("FINISHED %03d/%d %s s%d %.0fs" % (i + 1, n, key, seed, time.time() - t0))

    def loop(self):
        n = len(items(self.adult))
        waited = False
        while True:
            if os.path.exists(os.path.join(self.run, "pause")):
                self.log("paused")
                return
            if self.after and worker_pid(self.after):       # the other run (the normal art) goes first
                if not waited:
                    self.log("waiting for the %s worker to finish" % os.path.basename(self.after))
                    waited = True
                time.sleep(30)
                continue
            fin, ren = pending(self.run)
            if fin:
                i, hero, sid, art, seed = fin[0]
                try:
                    self.finish(i, n, hero, sid, art, seed)
                except Exception as e:  # noqa: BLE001 -- logged; the picker shows it as failed
                    self.log("FAIL finish %s s%d: %s" % (key_of(hero, art), seed, e))
                    with open(os.path.join(self.qa, "done", key_of(hero, art) + ".ok"), "w") as f:
                        json.dump({"failed": str(e)}, f)
                continue
            if ren:
                i, hero, sid, art, seed = ren[0]
                t0 = time.time()
                try:
                    self.step(["tools/comfy/run_hero.py", hero, "--count", "1", "--seed", str(seed), "--no-sheet"]
                              + (["--skin", sid] if sid else []) + (["--adult"] if self.adult else [])
                              + (["--size", size] if self.adult and (size := nude_size(hero, sid)) else []), "render")
                    self.log("CAND %03d/%d %s s%d %.0fs" % (i + 1, n, key_of(hero, art), seed, time.time() - t0))
                except Exception as e:  # noqa: BLE001
                    self.log("FAIL render %s s%d: %s" % (key_of(hero, art), seed, e))
                    time.sleep(30)
                continue
            self.log("IDLE: nothing to render or finish")
            return


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--run", default=DEFAULT_RUN)
    a = ap.parse_args(argv)
    run = os.path.abspath(a.run)
    other = worker_pid(run)
    if other and other != os.getpid():
        print("another worker is running (pid %d)" % other)
        return 0
    w = Worker(run)
    pidf = os.path.join(w.qa, "worker.pid")
    with open(pidf, "w") as f:
        f.write(str(os.getpid()))
    try:
        w.loop()
    finally:
        try:
            if open(pidf).read().strip() == str(os.getpid()):
                os.remove(pidf)
        except OSError:
            pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
