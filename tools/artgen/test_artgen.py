#!/usr/bin/env python3
"""Offline tests for the art farm (no torch, no network): input validation and the content-rule
guards (CFG range, presets, dtype), step semantics, the style overlay, the cutout, the exposure
filter's fail-closed behaviour and canary, the upload gate, the sheets bundle and the stdlib publish
merge, the workflow's hardening, and every render mode end to end with a fake model, fake detectors
and placeholder figures.

    python3 tools/artgen/test_artgen.py
"""
import ast
import hashlib
import io
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import config as C  # noqa: E402
import numpy as np  # noqa: E402
from PIL import Image, ImageDraw  # noqa: E402

import collect  # noqa: E402
import cutout  # noqa: E402
import gen  # noqa: E402
import pipeline as P  # noqa: E402
import plan  # noqa: E402
import post  # noqa: E402
import prompts  # noqa: E402
import publish  # noqa: E402
import repair  # noqa: E402
import safety  # noqa: E402
import schedule  # noqa: E402
import sdxl_chunks  # noqa: E402
import sheet  # noqa: E402
import style  # noqa: E402

BIBLE = prompts.load_bible()
WORKFLOW = os.path.join(C.ROOT, ".github", "workflows", "art-gen.yml")
QUIET = lambda *a: None  # noqa: E731


# ------------------------------------------------------------------ fakes
class FakeScorer:
    def __init__(self, name="fake", classes=("EXPOSED",), threshold=0.25, fn=None):
        self.name, self.classes, self.threshold = name, list(classes), threshold
        self.fn = fn or (lambda img: {c: 0.01 for c in self.classes})

    def class_max(self, img):
        return self.fn(img)


def red_square_scorer(threshold=0.25):
    """'Detects' a pure red square (stand-in for an exposure) in any view."""
    def fn(img):
        a = np.asarray(img.convert("RGB")).astype(np.int16)
        red = ((a[..., 0] > 240) & (a[..., 1] < 15) & (a[..., 2] < 15)).mean()
        return {"EXPOSED": float(min(1.0, red * 100))}
    return FakeScorer("redsq", ["EXPOSED"], threshold, fn)


def fake_filter(log=QUIET):
    return safety.ExposureFilter([red_square_scorer(), FakeScorer("second")], log=log)


def red_bbox(img):
    a = np.asarray(safety.flatten(img)).astype(np.int16)
    ys, xs = np.nonzero((a[..., 0] > 240) & (a[..., 1] < 15) & (a[..., 2] < 15))
    return None if not len(ys) else (int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1)


def red_box_scorer(threshold=0.25, stuck=None):
    """red_square_scorer that can also localise (class_boxes), like the real detectors. stuck=(w, h):
    always flags, with one fixed box seen only in the full view of a w x h image (a repair never helps)."""
    base = red_square_scorer(threshold)
    if stuck:          # flags anything with content (the self-test's flat grey image still passes)
        base.fn = lambda img: {"EXPOSED": 0.9 if np.asarray(img.convert("L")).std() > 1 else 0.0}

    def class_boxes(img, classes, conf):
        if stuck:
            return [(300.0, 500.0, 420.0, 620.0, "EXPOSED", 0.9)] if img.size == tuple(stuck) else []
        bb = red_bbox(img)
        sc = base.fn(img)["EXPOSED"]
        return [] if bb is None or sc < conf else [bb + ("EXPOSED", sc)]
    base.name = "redbox"
    base.class_boxes = class_boxes
    return base


def box_filter(stuck=None):
    return lambda: safety.ExposureFilter([red_box_scorer(stuck=stuck), FakeScorer("second")], log=QUIET)


class FakeEncoders:
    def encode_pair(self, pos, neg):
        return {"prompt_embeds": None, "pooled_prompt_embeds": None, "negative_prompt_embeds": None,
                "negative_pooled_prompt_embeds": None, "chunks": [2, 3], "pos": pos, "neg": neg}

    def close(self):
        pass


class FakeEngine:
    load_s = 0.0

    def __init__(self, hero, poison_seed=None, fail_text=None, poison_hires=False):
        self.hero, self.calls, self.poison_seed, self.fail_text = hero, [], poison_seed, fail_text
        self.poison_hires = poison_hires
        self.info = {"dtype": "fp32", "bf16_native": False}
        self.threads = 4
        self.kw = []

    def _check(self, cfg, emb):
        prob = C.cfg_problem(cfg)
        if prob:
            raise ValueError(prob)
        assert "neg" in emb and emb["neg"], "negative prompt missing"

    def _info(self, what, steps):
        return {"what": what, "seconds": 0.1, "steps_run": steps, "s_per_step": 0.01, "decode_s": 0.0,
                "decode": "untiled", "vmhwm_gb": 0.1, "mem_stage": {"vmhwm_gb": 0.1}}

    def txt2img(self, emb, seed, steps, cfg, sampler, width, height):
        self._check(cfg, emb)
        self.calls.append(("txt2img", seed, steps, cfg, sampler, (width, height)))
        im = P.placeholder_figure(BIBLE, self.hero, seed, (width, height), label="TEST")
        if seed == self.poison_seed:
            ImageDraw.Draw(im).rectangle([300, 500, 420, 620], fill=(255, 0, 0))
        return im, self._info("txt2img %dx%d" % (width, height), steps)

    def hires(self, emb, image, size, strength, seed, steps, cfg, sampler):
        self._check(cfg, emb)
        self.calls.append(("hires", seed, steps, cfg, sampler, tuple(size), strength))
        out = image.convert("RGB").resize(tuple(size), Image.LANCZOS)
        if self.poison_hires:
            ImageDraw.Draw(out).rectangle([560, 700, 640, 780], fill=(255, 0, 0))
        return out, self._info("hires", steps)

    def inpaint(self, emb, image, mask, strength, seed, steps, cfg, sampler):
        self._check(cfg, emb)
        self.calls.append(("inpaint", seed, steps, cfg, sampler, image.size, strength))
        self.inpaint_texts = getattr(self, "inpaint_texts", []) + [emb.get("pos")]
        if self.fail_text and self.fail_text in emb["pos"]:
            raise RuntimeError("forced inpaint failure")
        out = image.copy()
        out.paste(Image.new("RGB", image.size, (60, 200, 255)), (0, 0), mask)
        return out, self._info("inpaint", steps)

    def bench(self, emb, steps, cfg, sampler, width, height, seed=1):
        self._check(cfg, emb)
        self.calls.append(("bench", self.threads))
        return None, dict(self._info("bench", steps), s_per_step_steady=0.01 * self.threads)

    def set_threads(self, n):
        self.threads = n

    def close(self):
        pass


def fake_source(hero="seraphiel", run="38832421932-candidates-bench-draft", bg=(70, 72, 80)):
    """A fetch component returning a placeholder 'published candidate' (and recording its calls)."""
    calls = []

    def fetch(repo, r, h, seed):
        calls.append((repo, r, h, seed))
        if r != run or h != hero:
            raise gen.SourceError("not found: runs/%s/%s" % (r, h))
        sty = style.full_body(BIBLE, hero, "farm")
        img = P.placeholder_figure(BIBLE, hero, seed, (832, 1216), label="TEST")
        meta = {"hero": hero, "mode": "candidates", "seed": seed, "width": 832, "height": 1216, "preset": "standard",
                "preset_settings": C.PRESETS["standard"], "style": sty["style"], "prompt": sty["positive"],
                "negative": sty["negative"]}
        src = {"repo": repo, "run": r, "path": "runs/%s/%s/%s_s%d.webp" % (r, hero, hero, seed), "sha256": "ab" * 32,
               "preset": "standard", "preset_settings": C.PRESETS["standard"], "style": "farm"}
        return meta, img, src
    fetch.calls = calls
    return fetch


class FakeFaces:
    """Face box of a placeholder figure (pipeline.placeholder_figure geometry), like the detector would."""

    def find(self, img):
        a = np.asarray(img.convert("RGB")).astype(np.int16)
        skin = (np.abs(a - np.array([253, 232, 220])).max(axis=2) < 6)
        ys, xs = np.nonzero(skin[: img.height // 3])
        if not len(ys):
            return None
        y0, y1, x0, x1 = ys.min(), ys.max(), xs.min(), xs.max()
        return [int(x0), int(y0), int(x1 - x0), int(min(y1 - y0, 1.1 * (x1 - x0)))], "fake detector"


def components(hero, poison_seed=None, fail_text=None, fetch=None, faces=True, poison_hires=False):
    eng = FakeEngine(hero, poison_seed, fail_text, poison_hires)

    def engine(**kw):
        eng.kw.append(kw)
        return eng
    return eng, {"filter": fake_filter, "encoders": FakeEncoders, "engine": engine, "cutter": lambda: None,
                 "faces": FakeFaces if faces else (lambda: None), "fetch": fetch or fake_source(hero)}


def images_in(d):
    return sorted(os.path.relpath(os.path.join(dp, f), d) for dp, _, fs in os.walk(d) for f in fs
                  if f.endswith((".png", ".webp")))


# ------------------------------------------------------------------ config, presets, CFG
class TestPresets(unittest.TestCase):
    def test_default_is_the_model_card(self):
        self.assertEqual(C.DEFAULT_PRESET, "standard")
        self.assertEqual(C.FINAL_PRESET, "standard")
        p = C.PRESETS["standard"]
        self.assertEqual((p["sampler"], p["steps"], p["cfg"], p["width"], p["height"]),
                         ("euler_ancestral", 28, 5.0, 832, 1216))
        self.assertEqual(prompts.family_block(BIBLE, C.FAMILY).get("quality_position"), "end")

    def test_every_preset_keeps_negatives_active(self):
        self.assertEqual(sorted(C.PRESETS), ["draft", "standard"])
        for name, p in C.PRESETS.items():
            self.assertEqual(C.preset_problems(p), [], name)
            self.assertTrue(p["cfg"] > 1.0 and C.CFG_MIN <= p["cfg"] <= C.CFG_MAX, name)
            self.assertFalse(p.get("lora"), name)
        self.assertFalse(hasattr(C, "LORAS"))
        self.assertNotIn("lightning", json.dumps(C.PRESETS).lower())

    def test_cfg_range(self):
        for bad in (1.0, 0.5, 1.8, 3.9, 7.5, 12, "x", None):
            self.assertIsNotNone(C.cfg_problem(bad), bad)
        for ok in (4, 5.0, 7):
            self.assertIsNone(C.cfg_problem(ok), ok)
        self.assertTrue(C.preset_problems({"lora": "lightning8", "sampler": "euler_trailing", "steps": 8, "cfg": 1.0,
                                           "width": 832, "height": 1216}))

    def test_engine_guard_in_source(self):
        """sdxl.py needs torch, so check its guard statically: _common always checks CFG and always
        passes the negative embeddings (no 'if cfg > 1' branch)."""
        src = open(os.path.join(HERE, "sdxl.py")).read()
        tree = ast.parse(src)
        fn = next(n for n in ast.walk(tree) if isinstance(n, ast.FunctionDef) and n.name == "_common")
        body = ast.get_source_segment(src, fn)
        self.assertIn("check_cfg(cfg)", body)
        self.assertIn('"negative_prompt_embeds"', body)
        self.assertNotRegex(body, r"if\s+cfg\s*>")
        pick = next(n for n in ast.walk(tree) if isinstance(n, ast.FunctionDef) and n.name == "pick_dtype")
        self.assertNotIn("auto", ast.get_source_segment(src, pick).split('"""')[-1])


class TestSchedule(unittest.TestCase):
    def test_effective_steps(self):
        self.assertEqual(schedule.total_steps_for(20, 0.4), 50)
        self.assertEqual(schedule.total_steps_for(16, 0.35), 46)
        self.assertEqual(schedule.total_steps_for(14, 0.6), 24)
        self.assertEqual(schedule.total_steps_for(28, 1.0), 28)
        for eff, st in ((20, 0.4), (16, 0.35), (14, 0.62), (14, 0.58), (13, 0.29), (7, 0.7)):
            n = schedule.total_steps_for(eff, st)
            self.assertEqual(schedule.steps_run(n, st), eff, (eff, st))
            self.assertLess(schedule.steps_run(n - 1, st), eff, (eff, st))
        for bad in ((0, 0.5), (10, 0.0), (10, 1.5)):
            with self.assertRaises(ValueError):
                schedule.total_steps_for(*bad)

    def test_estimates(self):
        s = schedule.estimate_s(90, 1000, 1000, 10, overhead_s=0)
        self.assertAlmostEqual(s, 900.0)
        self.assertAlmostEqual(schedule.ref_from_measure(90, 1000, 1000), 90.0)


# ------------------------------------------------------------------ plan.py
class TestPlan(unittest.TestCase):
    def env(self, **kw):
        e = {"ART_MODE": "candidates", "ART_HEROES": "seraphiel", "ART_COUNT": "2", "ART_SEEDS": "{}",
             "ART_PRESET": "", "ART_STYLE": "", "ART_DTYPE": "", "ART_PER_JOB": "0", "ART_LABEL": "smoke",
             "GITHUB_RUN_ID": "123"}
        e.update(kw)
        return e

    def test_smoke_plan_defaults(self):
        p = plan.build(self.env(), BIBLE)
        self.assertEqual(p["run_dir"], "123-candidates-smoke")
        self.assertEqual((p["preset"], p["style"], p["dtype"]), ("standard", "farm", "fp32"))
        self.assertEqual(p["matrix"]["include"], [{"key": "seraphiel-c0", "hero": "seraphiel", "seeds": "101000,101001",
                                                   "flip": "0", "source_run": ""}])

    def test_all_heroes_and_split(self):
        p = plan.build(self.env(ART_HEROES="all", ART_COUNT="4", ART_PER_JOB="2"), BIBLE)
        self.assertEqual(p["jobs"], 30)
        self.assertEqual(len({e["key"] for e in p["matrix"]["include"]}), 30)

    def test_rejects_bad_input(self):
        for kw in ({"ART_HEROES": "seraphiel; rm -rf /"}, {"ART_HEROES": "nobody"}, {"ART_COUNT": "99"},
                   {"ART_COUNT": "2; echo"}, {"ART_PRESET": "dmd2"}, {"ART_PRESET": "lightning8"},
                   {"ART_PRESET": "lightning8_cfg"}, {"ART_PRESET": "lcm8"}, {"ART_MODE": "shell"},
                   {"ART_STYLE": "anime"}, {"ART_DTYPE": "fp16"}, {"ART_DTYPE": "auto"},
                   {"ART_SEEDS": "not json"}, {"ART_SEEDS": '{"seraphiel": "1; ls"}'},
                   {"ART_MODE": "final", "ART_SEEDS": "{}"},
                   {"ART_MODE": "final", "ART_SEEDS": '{"seraphiel": {"seeds": [true], "run": "1-candidates"}}'},
                   {"ART_MODE": "final", "ART_SEEDS": '{"seraphiel": {"seeds": [1], "run": "../x"}}'},
                   {"GITHUB_RUN_ID": "1$(id)"}):
            with self.assertRaises(plan.PlanError, msg=str(kw)):
                plan.build(self.env(**kw), BIBLE)

    def test_injected_low_cfg_preset_is_refused(self):
        for cfg in (1.0, 1.8, 8.0):
            C.PRESETS["nocfg"] = dict(C.PRESETS["standard"], cfg=cfg)
            try:
                with self.assertRaises(plan.PlanError):
                    plan.build(self.env(ART_PRESET="nocfg"), BIBLE)
                rc = gen.main(["candidates", "--hero", "seraphiel", "--seeds", "1", "--preset", "nocfg",
                               "--out", tempfile.mkdtemp(), "--work", tempfile.mkdtemp()],
                              components=components("seraphiel")[1])
                self.assertEqual(rc, 2)
            finally:
                del C.PRESETS["nocfg"]

    def test_label_is_cleaned(self):
        p = plan.build(self.env(ART_LABEL="$(curl evil) `x` ../../ OK"), BIBLE)
        self.assertRegex(p["run_dir"], r"^123-candidates-[a-z0-9-]+$")

    def test_final_plan_needs_the_candidate_run(self):
        p = plan.build(self.env(ART_MODE="final", ART_SEEDS='{"seraphiel": {"seeds": [101000], "flip": true, '
                                                            '"run": "38832421932-candidates-bench-draft"}}'), BIBLE)
        self.assertEqual(p["matrix"]["include"], [{"key": "seraphiel-f101000", "hero": "seraphiel", "seeds": "101000",
                                                   "flip": "1", "source_run": "38832421932-candidates-bench-draft"}])
        for seeds in ('{"seraphiel": [101000]}', '{"seraphiel": {"seeds": [101000]}}',
                      '{"seraphiel": {"seeds": [101000], "run": "1-final-x"}}'):
            with self.assertRaises(plan.PlanError, msg=seeds):
                plan.build(self.env(ART_MODE="final", ART_SEEDS=seeds), BIBLE)
        with self.assertRaises(plan.PlanError):
            plan.build(self.env(ART_MODE="final", ART_DTYPE="bf16",
                                ART_SEEDS='{"seraphiel": {"seeds": [1], "run": "1-candidates"}}'), BIBLE)

    def test_final_jobs_limit(self):
        seeds = {h: {"seeds": [1, 2, 3, 4], "run": "1-candidates"} for h in list(BIBLE["heroes"])[:5]}
        with self.assertRaises(plan.PlanError):
            plan.build(self.env(ART_MODE="final", ART_HEROES="", ART_SEEDS=json.dumps(seeds)), BIBLE)

    def test_bench_plan(self):
        p = plan.build(self.env(ART_MODE="bench", ART_COUNT="2", ART_HEROES=""), BIBLE)
        self.assertEqual([e["key"] for e in p["matrix"]["include"]], ["bench-0", "bench-1"])
        self.assertEqual(p["matrix"]["include"][0]["hero"], "seraphiel")
        with self.assertRaises(plan.PlanError):
            plan.build(self.env(ART_MODE="bench", ART_COUNT="5"), BIBLE)


# ------------------------------------------------------------------ prompts and style
class TestPrompts(unittest.TestCase):
    def test_pack_like_comfy(self):
        words = [([1, 2], 1.0)] * 37 + [([3, 4, 5], 1.2)]    # 74 tokens, then a 3-token word
        ch = sdxl_chunks.pack_chunks(words)
        self.assertEqual([len(c) for c in ch], [74, 3])      # the word moves to the next chunk whole
        self.assertEqual(ch[1][0], (3, 1.2))
        long_word = [(list(range(10)), 1.0)]
        ch = sdxl_chunks.pack_chunks([([0] * 70, 1.0)] + long_word)
        self.assertEqual([len(c) for c in ch], [75, 5])      # >= 8 tokens: split across chunks
        self.assertEqual(sdxl_chunks.pack_chunks([]), [[]])

    def test_bible_prompts_pass_enforce(self):
        for hid in BIBLE["heroes"]:
            pr = prompts.full_body(BIBLE, hid, C.FAMILY)
            gen.checked(BIBLE, hid, pr["positive"], pr["negative"])     # enforce() passes for all 15

    def test_farm_style_all_heroes(self):
        fam = prompts.family_block(BIBLE, C.FAMILY)
        tail = prompts.join_tags(fam["quality"], fam["rating"])
        slate = set()
        for hid, h in BIBLE["heroes"].items():
            r = style.full_body(BIBLE, hid, "farm")
            gen.checked(BIBLE, hid, r["positive"], r["negative"])
            self.assertLessEqual(prompts.clip_stats(r["positive"])["chunks"], 3, hid)
            self.assertTrue(r["positive"].endswith(tail), hid)                     # quality tags at the END
            self.assertNotIn("cel shading", prompts.tag_weights(r["positive"]), hid)
            self.assertIn("from side", prompts.tag_weights(r["positive"]), hid)
            self.assertIn("shadow", prompts.tag_weights(r["negative"]), hid)
            self.assertEqual(r["style"]["name"], "farm")
            if r["background_key"] == "slate":
                slate.add(hid)
                self.assertEqual(r["bg_rgb"], C.STYLES["farm"]["background"]["rgb"])
                self.assertIn("dark grey background", r["positive"])
            else:
                self.assertEqual(r["background_key"], prompts.background(BIBLE, hid)[0])
            f = style.face(BIBLE, hid, "farm")
            gen.checked(BIBLE, hid, f["positive"], f["negative"])
            self.assertEqual(f["background_key"], r["background_key"])
            for v in h["variant_set"]:
                vp = style.face(BIBLE, hid, "farm", variant=v)
                gen.checked(BIBLE, hid, vp["positive"], vp["negative"])
                self.assertEqual(prompts.variant_conflicts(BIBLE, hid, v, vp["positive"]), [], (hid, v))
        expect = {hid for hid in BIBLE["heroes"] if prompts.background(BIBLE, hid)[0] == "grey"
                  and "white" in prompts.palette(BIBLE, hid)}
        self.assertEqual(slate, expect)
        self.assertNotIn("lucen", slate)

    def test_farm_exposure_hardening(self):
        st = C.STYLES["farm"]
        for hid, h in BIBLE["heroes"].items():
            hard = prompts.split_tags(st["harden_negative"][h["gender"]])
            for r in [style.full_body(BIBLE, hid, "farm"), style.face(BIBLE, hid, "farm")] + [
                    style.face(BIBLE, hid, "farm", variant=v) for v in h["variant_set"]]:
                gen.checked(BIBLE, hid, r["positive"], r["negative"])
                self.assertEqual(prompts.split_tags(r["negative"])[:len(hard)], hard, hid)   # at the FRONT
                nw = prompts.tag_weights(r["negative"])
                for t in hard:
                    self.assertEqual(nw[prompts.norm_tag(t)], prompts.tag_weights(t)[prompts.norm_tag(t)], (hid, t))
                self.assertIn("sensitive", prompts.tag_weights(r["positive"]), hid)
            pos = prompts.tag_weights(style.full_body(BIBLE, hid, "farm")["positive"])
            self.assertNotIn("huge breasts", pos, hid)
            for t in ("center opening", "opening to the navel", "open to the navel", "navel opening"):
                self.assertNotIn(t, pos, hid)
            if "huge breasts" in prompts.tag_weights(h["body"]):
                self.assertIn("large breasts", pos, hid)
            if h["gender"] == "male":
                self.assertNotIn("topless", prompts.tag_weights(style.full_body(BIBLE, hid, "farm")["negative"]), hid)
        # the swap on a hero that has the wording (the outfit lane owns the bible; test on a copy)
        b = json.loads(json.dumps(BIBLE))
        b["heroes"]["seraphiel"]["outfit"] = "white leotard, center opening, detached sleeves"
        b["heroes"]["seraphiel"]["body"] = "curvy, (huge breasts:1.1), wide hips"
        r = style.full_body(b, "seraphiel", "farm")
        tw = prompts.tag_weights(r["positive"])
        self.assertIn("plunging neckline", tw)
        self.assertIn("gold filigree panels", tw)
        self.assertIn("large breasts", tw)
        self.assertNotIn("center opening", tw)
        self.assertNotIn("huge breasts", tw)
        self.assertEqual(b["heroes"]["seraphiel"]["outfit"], "white leotard, center opening, detached sleeves")
        # final mode re-hardens a recorded (older) candidate prompt the same way
        old = "1girl, solo, adult, mature female, huge breasts, center opening, masterpiece"
        new = prompts.tag_weights(style.harden_positive(BIBLE, "seraphiel", "farm", old))
        self.assertIn("large breasts", new)
        self.assertIn("sensitive", new)
        self.assertNotIn("center opening", new)
        self.assertEqual(style.harden_positive(BIBLE, "seraphiel", "bible", old), old)

    def test_cover_prompts(self):
        drop = C.REPAIR["drop_outfit_terms"]
        for hid, h in BIBLE["heroes"].items():
            for sty in ("farm", "bible"):
                c = style.cover(BIBLE, hid, sty)
                gen.checked(BIBLE, hid, c["positive"], c["negative"])
                tw = prompts.tag_weights(c["positive"])
                self.assertIn("glossy fabric", c["material"])
                for t in prompts.split_tags(c["material"]):
                    self.assertIn(prompts.norm_tag(t), tw, (hid, t))
                for t in tw:
                    self.assertFalse(any(d in t for d in drop), (hid, sty, t))       # no exposure-prone outfit tags
                hard = prompts.split_tags(C.STYLES["farm"]["harden_negative"][h["gender"]])
                self.assertEqual(prompts.split_tags(c["negative"])[:len(hard)], hard, (hid, sty))
                self.assertLessEqual(prompts.clip_stats(c["negative"])["chunks"], 3, hid)
        self.assertEqual(style.cover(BIBLE, "seraphiel", "farm")["material"],
                         "white glossy fabric, gold filigree panels, clothed")

    def test_floating_weapon(self):
        for hid, h in BIBLE["heroes"].items():
            floats = [t for t in prompts.split_tags(h["weapon"] + ", " + h["accessories"])
                      if prompts.norm_tag(t).startswith("floating ")]
            r = style.full_body(BIBLE, hid, "farm")
            tw = prompts.tag_weights(r["positive"])
            for t in floats:
                self.assertAlmostEqual(tw[prompts.norm_tag(t)], 1.2, msg=hid)
            held = any("holding" in prompts.norm_tag(t) for f in ("weapon", "accessories", "pose")
                       for t in prompts.split_tags(h.get(f, "")))
            self.assertEqual("holding weapon" in prompts.tag_weights(r["negative"]), bool(floats) and not held, hid)

    def test_bible_style_is_the_bible(self):
        for hid in ("seraphiel", "brakka"):
            r = style.full_body(BIBLE, hid, "bible")
            pr = prompts.full_body(BIBLE, hid, C.FAMILY)
            self.assertEqual((r["positive"], r["negative"]), (pr["positive"], pr["negative"]))
        before = json.dumps(BIBLE, sort_keys=True)
        style.full_body(BIBLE, "seraphiel", "farm")
        self.assertEqual(json.dumps(BIBLE, sort_keys=True), before)       # the bible itself is never touched


# ------------------------------------------------------------------ cutout
class TestCutout(unittest.TestCase):
    BG = (70, 72, 80)

    def figure(self):
        """A figure with a ring (halo) enclosing background, two legs and a soft grey ground shadow."""
        im = Image.new("RGB", (400, 700), self.BG)
        d = ImageDraw.Draw(im)
        d.ellipse([130, 30, 270, 170], outline=(240, 200, 90), width=14)            # halo ring
        d.ellipse([170, 70, 230, 140], fill=(250, 225, 210), outline=(30, 20, 40), width=3)   # head
        d.rectangle([150, 140, 250, 450], fill=(240, 240, 250), outline=(30, 20, 40), width=3)  # gown
        for x in (165, 205):
            d.rectangle([x, 450, x + 30, 640], fill=(250, 225, 210), outline=(30, 20, 40), width=3)  # legs
        arr = np.asarray(im).astype(np.float32)
        yy, xx = np.mgrid[0:700, 0:400]
        sh = (((xx - 200) / 120.0) ** 2 + ((yy - 645) / 18.0) ** 2) < 1.0
        legs = np.zeros_like(sh)
        legs[450:642, 163:198] = True
        legs[450:642, 203:238] = True
        sh &= ~legs
        arr[sh] = arr[sh] * 0.6                                                      # darker, same chroma
        return Image.fromarray(arr.astype(np.uint8))

    def isnet(self, img):
        """Fake isnet: everything not background-coloured, PLUS the ring interior and the shadow (its failure modes)."""
        a = np.asarray(img).astype(np.float32)
        m = np.linalg.norm(a - np.array(self.BG, np.float32), axis=2) > 10
        yy, xx = np.mgrid[0:700, 0:400]
        m |= ((xx - 200) ** 2 + (yy - 100) ** 2) < 70 ** 2                          # ring interior "figure"
        return Image.fromarray((m * 255).astype(np.uint8), "L")

    def test_holes_and_shadow(self):
        img = self.figure()
        rgba, info = cutout.artgen_cutout(img, self.isnet(img))
        a = np.asarray(rgba)[..., 3]
        self.assertEqual(rgba.mode, "RGBA")
        self.assertLess(a[100, 160], 10, "ring interior beside the head must be transparent")   # inside the ring
        self.assertLess(a[648, 120], 10, "ground shadow left of the legs must be transparent")
        self.assertLess(a[648, 280], 10, "ground shadow right of the legs must be transparent")
        self.assertGreater(a[630, 180], 245, "the legs stay")
        self.assertGreater(a[300, 200], 245, "the gown stays")
        self.assertGreater(a[100, 135], 200, "the ring itself stays")
        self.assertGreater(info["hole_px"], 0)
        self.assertGreater(info["shadow_px"], 0)

    def test_without_isnet(self):
        img = self.figure()
        rgba, info = cutout.artgen_cutout(img, None)
        a = np.asarray(rgba)[..., 3]
        self.assertLess(a[648, 120], 10)
        self.assertGreater(a[630, 180], 245)
        self.assertEqual(info["method"], "colour flood + shadow")

    def test_white_gown_is_not_shadow(self):
        im = Image.new("RGB", (300, 500), (128, 128, 128))
        d = ImageDraw.Draw(im)
        d.rectangle([100, 50, 200, 480], fill=(150, 150, 150), outline=(20, 20, 20), width=3)   # lighter grey hem
        rgba, info = cutout.artgen_cutout(im, None)
        self.assertGreater(np.asarray(rgba)[470, 150, 3], 245)
        self.assertEqual(info["shadow_px"], 0)


# ------------------------------------------------------------------ filter
class TestFilter(unittest.TestCase):
    def setUp(self):
        self.d = tempfile.mkdtemp()

    def tearDown(self):
        shutil.rmtree(self.d, ignore_errors=True)

    def img(self, name, red=False, size=(512, 896)):
        im = Image.new("RGB", size, (128, 128, 128))
        if red:
            ImageDraw.Draw(im).rectangle([200, 600, 260, 660], fill=(255, 0, 0))
        p = os.path.join(self.d, name)
        im.save(p)
        return p

    def test_clean_passes_flagged_drops(self):
        f = fake_filter()
        self.assertTrue(f.check_file(self.img("a.png"))[0])
        ok, rep = f.check_file(self.img("b.png", red=True))
        self.assertFalse(ok)
        self.assertEqual(rep["flagged"][0]["class"], "EXPOSED")

    def test_tiles_catch_small_details(self):
        im = Image.new("RGB", (1024, 2048), (128, 128, 128))
        ImageDraw.Draw(im).rectangle([600, 900, 640, 940], fill=(255, 0, 0))
        ok, rep = fake_filter().check_image(im)
        self.assertFalse(ok)
        self.assertTrue(rep["flagged"][0]["view"].startswith("t"))

    def test_flag_boxes_in_image_pixels(self):
        im = Image.new("RGB", (832, 1216), (128, 128, 128))
        ImageDraw.Draw(im).rectangle([600, 900, 639, 939], fill=(255, 0, 0))
        f = safety.ExposureFilter([red_box_scorer(), FakeScorer("second")], log=QUIET)
        ok, rep = f.check_image(im)
        self.assertFalse(ok)
        classes = f.cover_classes(rep, C.REPAIR["near_frac"])
        self.assertEqual(classes, {"redbox": ["EXPOSED"]})
        boxes = f.flag_boxes(im, classes, C.REPAIR["box_conf_frac"])
        self.assertTrue(boxes)
        for b in boxes:                                    # every view maps back onto the square (tiles may cut it)
            x0, y0, x1, y1 = b["box"]
            self.assertTrue(600 <= x0 < x1 <= 640 and 900 <= y0 < y1 <= 940, b)
        self.assertIn([600, 900, 640, 940], [b["box"] for b in boxes if b["view"] == "full"])
        self.assertTrue(any(b["view"].startswith("t") and b["box"] == [600, 900, 640, 940] for b in boxes))
        with self.assertRaises(RuntimeError):              # a detector that cannot localise: no repair
            fake_filter().flag_boxes(im, {"redsq": ["EXPOSED"]}, 0.5)

    def test_near_classes_are_covered_too(self):
        f = safety.ExposureFilter([FakeScorer("a", ["X", "Y", "Z"])], log=QUIET)
        rep = {"flagged": [{"detector": "a", "class": "X", "score": 0.3}],
               "scores": {"a": {"X": 0.3, "Y": 0.21, "Z": 0.05}}}
        self.assertEqual(f.cover_classes(rep, 0.8), {"a": ["X", "Y"]})

    def test_detector_error_drops(self):
        def boom(img):
            raise RuntimeError("model crashed")
        ok, rep = safety.ExposureFilter([FakeScorer(fn=boom)]).check_file(self.img("a.png"))
        self.assertFalse(ok)
        self.assertIn("model crashed", rep["error"])

    def test_nan_score_drops(self):
        f = safety.ExposureFilter([FakeScorer(fn=lambda img: {"EXPOSED": float("nan")})])
        self.assertFalse(f.check_file(self.img("a.png"))[0])

    def test_unreadable_drops(self):
        p = os.path.join(self.d, "x.png")
        with open(p, "wb") as fh:
            fh.write(b"not a png")
        self.assertFalse(fake_filter().check_file(p)[0])

    def test_missing_detector_is_unavailable(self):
        def broken_loader(*a, **k):
            raise ImportError("No module named nudenet")
        orig = safety.NudeNetScorer
        safety.NudeNetScorer = broken_loader
        try:
            with self.assertRaises(safety.FilterUnavailable):
                safety.ExposureFilter()
        finally:
            safety.NudeNetScorer = orig
        with self.assertRaises(safety.FilterUnavailable):
            safety.ExposureFilter([])
        with self.assertRaises(safety.FilterUnavailable):
            safety.ExposureFilter([FakeScorer(threshold=0.9)])     # too loose

    def test_selftest(self):
        fake_filter().selftest()
        with self.assertRaises(safety.FilterUnavailable):     # a filter that drops everything fails the self-test
            safety.ExposureFilter([FakeScorer(fn=lambda img: {"EXPOSED": 0.99})]).selftest()

    def canary_scorers(self, breast, censor):
        return [FakeScorer("nudenet", C.FILTER["nudenet_classes"], 0.25,
                           lambda img: dict({c: 0.001 for c in C.FILTER["nudenet_classes"]},
                                            FEMALE_BREAST_EXPOSED=breast if img.size[0] > 600 else 0.01)),
                FakeScorer("anime_censor", C.FILTER["anime_classes"], 0.25,
                           lambda img: dict({c: 0.001 for c in C.FILTER["anime_classes"]},
                                            penis=censor if img.size[0] > 600 else 0.01))]

    def synthetic_canary(self):
        p = self.img("canary.png", size=(832, 1216))
        return p, dict(C.FILTER["canary"], sha256=safety.sha256_file(p))

    def test_canary_bands(self):
        path, spec = self.synthetic_canary()
        rep = safety.ExposureFilter(self.canary_scorers(0.2259, 0.1053)).canary(spec, path)    # the measured values
        self.assertEqual(rep["scores"]["nudenet"]["FEMALE_BREAST_EXPOSED"], 0.2259)
        for breast, censor in ((0.0, 0.0), (0.02, 0.1), (0.2, 0.001), (0.3, 0.1)):
            with self.assertRaises(safety.FilterUnavailable, msg=(breast, censor)):
                safety.ExposureFilter(self.canary_scorers(breast, censor)).canary(spec, path)
        self.assertFalse(fake_filter().default)          # test detectors: the canary is not part of selftest()

    def test_canary_unavailable_is_skipped_loudly(self):
        path, spec = self.synthetic_canary()
        lines = []
        f = safety.ExposureFilter(self.canary_scorers(0.0, 0.0), log=lines.append)
        self.assertIsNone(f.canary(dict(spec, sha256="0" * 64), path))          # wrong bytes: not scored
        orig = safety.fetch_canary
        safety.fetch_canary = lambda spec=None, log=None, **k: (None, "offline")
        try:
            self.assertIsNone(f.canary(spec))
            rep = safety.ExposureFilter(self.canary_scorers(0.0, 0.0), log=lines.append).selftest(canary=True)
        finally:
            safety.fetch_canary = orig
        self.assertEqual(rep["canary"], "skipped")
        self.assertTrue(any("canary SKIPPED" in str(x) for x in lines), lines)

    def test_canary_from_the_output_branch(self):
        """The real canary is never committed here: it is read from origin/art-gen-output when that ref
        has been fetched (skipped otherwise; on the runner it comes from the raw URL)."""
        spec = C.FILTER["canary"]
        r = subprocess.run(["git", "cat-file", "-e", "%s:%s" % (spec["ref"], spec["path"])], cwd=C.ROOT,
                           capture_output=True)
        if r.returncode != 0:
            self.skipTest("origin/art-gen-output not fetched")
        env = os.environ.pop("ARTGEN_CANARY_FILE", None)
        orig = safety.fetch_canary.__defaults__
        try:
            path, why = safety.fetch_canary(spec, log=QUIET)
        finally:
            if env:
                os.environ["ARTGEN_CANARY_FILE"] = env
        self.assertIsNone(why)
        self.assertEqual(safety.sha256_file(path), spec["sha256"])
        self.assertEqual(orig, safety.fetch_canary.__defaults__)
        self.assertFalse(os.path.exists(os.path.join(HERE, "testdata")))

    def test_rgba_is_flattened(self):
        im = Image.new("RGBA", (256, 256), (255, 0, 0, 0))      # transparent red = invisible
        self.assertTrue(fake_filter().check_image(im)[0])

    def test_publisher_and_verify(self):
        out = os.path.join(self.d, "out")
        pub = safety.Publisher(fake_filter(), out)
        good = pub.publish(self.img("g.png"), "h/g.png")
        bad = pub.publish(self.img("b.png", red=True), "h/b.png")
        self.assertTrue(good and os.path.exists(good))
        self.assertIsNone(bad)
        self.assertFalse(os.path.exists(os.path.join(self.d, "b.png")))    # dropped = deleted, not kept
        self.assertFalse(os.path.exists(os.path.join(out, "h", "b.png")))
        pub.write_json("h/g.json", {"a": 1})
        Image.new("RGB", (8, 8)).save(os.path.join(out, "h", "sneak.png"))
        Image.new("RGB", (8, 8)).save(os.path.join(out, "h", "sneak.jpg"))
        with open(os.path.join(out, "h", "note.txt"), "w") as fh:
            fh.write("x")
        with open(os.path.join(out, "h", "bad.json"), "w") as fh:
            fh.write("{")
        res = safety.verify(out, log=QUIET)
        self.assertEqual(sorted(os.listdir(os.path.join(out, "h"))), ["g.json", "g.png"])
        self.assertEqual(res["deleted"], 4)
        with open(good, "ab") as fh:                 # changed after the filter
            fh.write(b"\0")
        safety.verify(out, log=QUIET)
        self.assertFalse(os.path.exists(good))

    def test_verify_without_manifest_deletes_images(self):
        out = os.path.join(self.d, "o")
        os.makedirs(out)
        Image.new("RGB", (8, 8)).save(os.path.join(out, "a.png"))
        safety.verify(out, log=QUIET)
        self.assertEqual(os.listdir(out), [])

    def test_publish_rejects_other_types(self):
        pub = safety.Publisher(fake_filter(), os.path.join(self.d, "out"))
        with self.assertRaises(ValueError):
            pub.publish(self.img("g.jpg"), "h/g.jpg")
        with self.assertRaises(ValueError):
            pub.write_json("../escape.json", {})


# ------------------------------------------------------------------ render modes
class TestRepairPlan(unittest.TestCase):
    def test_pad_merge_and_crop(self):
        pl = repair.plan([{"box": [300, 500, 400, 600]}, {"box": [390, 505, 480, 600]}], (832, 1216))
        self.assertTrue(pl["ok"], pl["why"])
        self.assertEqual(len(pl["regions"]), 1)                       # two breasts -> one padded region
        x0, y0, x1, y1 = pl["regions"][0]
        self.assertLessEqual((x0, y0), (300 - 25, 500 - 25))         # 25% of the box on every side
        self.assertGreaterEqual((x1, y1), (480 + 22, 600 + 25))
        self.assertEqual(len(pl["clusters"]), 1)
        cx0, cy0, cx1, cy1 = pl["clusters"][0]["crop"]
        self.assertEqual(cx1 - cx0, cy1 - cy0)                         # square
        self.assertTrue(cx0 <= x0 and cy0 <= y0 and cx1 >= x1 and cy1 >= y1)
        self.assertGreaterEqual(cx1 - cx0, C.REPAIR["crop_min"])
        m = repair.mask((832, 1216), pl["regions"])
        self.assertEqual(m.getbbox(), tuple(pl["regions"][0]))

    def test_tiny_box_grows_and_far_regions_split(self):
        pl = repair.plan([[100, 100, 104, 104], [700, 1100, 704, 1104]], (832, 1216))
        self.assertTrue(pl["ok"])
        for r in pl["regions"]:
            self.assertGreaterEqual(min(r[2] - r[0], r[3] - r[1]), C.REPAIR["min_side"] - 1)
        self.assertEqual(len(pl["clusters"]), 2)                       # too far apart for one crop

    def test_refuses_what_is_not_a_local_slip(self):
        self.assertFalse(repair.plan([], (832, 1216))["ok"])
        many = [[i * 150, 10, i * 150 + 20, 30] for i in range(5)]
        self.assertIn("separate regions", repair.plan(many, (832, 1216))["why"])
        big = [[0, 0, 600, 600]]
        self.assertIn("of the image", repair.plan(big, (832, 1216))["why"])


class TestModes(unittest.TestCase):
    def setUp(self):
        self.d = tempfile.mkdtemp()

    def tearDown(self):
        shutil.rmtree(self.d, ignore_errors=True)

    def run_gen(self, args, comps, out_name="out"):
        out, work = os.path.join(self.d, out_name), os.path.join(self.d, "work_" + out_name)
        rc = gen.main(args + ["--out", out, "--work", work, "--key", "k", "--run", "1-test"], components=comps)
        return rc, out

    def test_candidates(self):
        eng, comps = components("seraphiel", poison_seed=101001)
        rc, out = self.run_gen(["candidates", "--hero", "seraphiel", "--seeds", "101000,101001"], comps)
        self.assertEqual(rc, 0)
        files = sorted(os.listdir(os.path.join(out, "seraphiel")))
        self.assertIn("seraphiel_s101000.webp", files)
        self.assertNotIn("seraphiel_s101001.webp", files)            # the poisoned one was dropped
        self.assertTrue(json.load(open(os.path.join(out, "seraphiel", "seraphiel_s101001.json")))["dropped"])
        meta = json.load(open(os.path.join(out, "seraphiel", "seraphiel_s101000.json")))
        self.assertIsNone(meta["lora"])
        self.assertEqual((meta["preset"], meta["style"]["name"], meta["dtype"]), ("standard", "farm", "fp32"))
        self.assertEqual((meta["width"], meta["height"]), (832, 1216))
        self.assertEqual(meta["background"]["key"], "slate")
        self.assertIn("adult", meta["prompt"])
        self.assertEqual([c[:6] for c in eng.calls],
                         [("txt2img", s, 28, 5.0, "euler_ancestral", (832, 1216)) for s in (101000, 101001)])
        self.assertEqual(eng.kw, [{"dtype": "fp32", "lazy_unet": False}])
        self.assertEqual(len(json.load(open(os.path.join(out, safety.MANIFEST)))["dropped"]), 1)
        self.assertEqual(safety.verify(out, log=QUIET)["deleted"], 0)
        job = json.load(open(os.path.join(out, "seraphiel", "job_k.json")))
        self.assertEqual(job["exit_code"], 0)
        self.assertNotIn("loras", job["licenses"])

    def test_candidate_cover_repair(self):
        eng, comps = components("seraphiel", poison_seed=101001)
        comps["filter"] = box_filter()
        rc, out = self.run_gen(["candidates", "--hero", "seraphiel", "--seeds", "101000,101001"], comps)
        self.assertEqual(rc, 0)
        R = C.REPAIR
        inp = [c for c in eng.calls if c[0] == "inpaint"]
        self.assertEqual(len(inp), 1)                                   # one crop, one pass
        self.assertEqual(inp[0][1:7], (101001 + R["seed_offset"], R["steps"], 5.0, "euler_ancestral", (R["px"], R["px"]),
                                       R["denoise"]))
        self.assertIn("glossy fabric", eng.inpaint_texts[0])
        d = os.path.join(out, "seraphiel")
        im = Image.open(os.path.join(d, "seraphiel_s101001.webp")).convert("RGB")
        self.assertIsNone(red_bbox(im))                                  # the published file is the repaired one
        a = np.asarray(im).astype(np.int16)
        self.assertLess(np.abs(a[540:580, 340:380] - [60, 200, 255]).max(), 40)    # fake cover paint inside the box
        meta = json.load(open(os.path.join(d, "seraphiel_s101001.json")))
        self.assertFalse(meta["dropped"])
        self.assertTrue(meta["repair"]["result"].startswith("published after 1"))
        att = meta["repair"]["attempts"][0]
        self.assertEqual(att["boxes"][0]["box"], [300, 500, 421, 621])
        self.assertTrue(meta["repair"]["original"]["flagged"])
        self.assertIn("glossy fabric", meta["cover_prompt"]["positive"])
        man = json.load(open(os.path.join(out, safety.MANIFEST)))
        self.assertEqual(man["dropped"], [])
        self.assertEqual(man["files"]["seraphiel/seraphiel_s101001.webp"]["repair"]["passes"], 1)
        self.assertEqual(man["stats"]["repaired"], 1)
        self.assertNotIn("repair", man["files"]["seraphiel/seraphiel_s101000.webp"])
        self.assertIsNone(json.load(open(os.path.join(d, "seraphiel_s101000.json")))["repair"])
        self.assertEqual(safety.verify(out, log=QUIET)["deleted"], 0)
        for p in images_in(out):                                         # the unrepaired original is nowhere
            self.assertIsNone(red_bbox(Image.open(os.path.join(out, p))), p)

    def test_candidate_repair_that_does_not_help_drops(self):
        eng, comps = components("seraphiel")
        comps["filter"] = box_filter(stuck=(832, 1216))
        rc, out = self.run_gen(["candidates", "--hero", "seraphiel", "--seeds", "101000"], comps)
        self.assertEqual(rc, 0)
        self.assertEqual(len([c for c in eng.calls if c[0] == "inpaint"]), C.REPAIR["attempts"])
        self.assertEqual(images_in(out), [])
        meta = json.load(open(os.path.join(out, "seraphiel", "seraphiel_s101000.json")))
        self.assertTrue(meta["dropped"])
        self.assertEqual(len(meta["repair"]["attempts"]), C.REPAIR["attempts"])
        self.assertTrue(meta["repair"]["result"].startswith("dropped: still flagged"))
        self.assertEqual([c["seeds"][0] for c in meta["repair"]["attempts"]],
                         [101000 + C.REPAIR["seed_offset"] + 10 * k for k in range(C.REPAIR["attempts"])])
        man = json.load(open(os.path.join(out, safety.MANIFEST)))
        self.assertEqual(len(man["dropped"]), 1)
        self.assertEqual(man["dropped"][0]["report"]["repair"]["result"], meta["repair"]["result"])
        self.assertEqual(man["files"], {})

    def test_no_repair_and_bf16_drop_at_once(self):
        for extra in (["--no-repair"], ["--dtype", "bf16"]):
            eng, comps = components("seraphiel", poison_seed=101000)
            comps["filter"] = box_filter()
            rc, out = self.run_gen(["candidates", "--hero", "seraphiel", "--seeds", "101000"] + extra, comps,
                                   out_name="o" + extra[-1])
            self.assertEqual(rc, 0)
            self.assertEqual([c[0] for c in eng.calls], ["txt2img"], extra)
            meta = json.load(open(os.path.join(out, "seraphiel", "seraphiel_s101000.json")))
            self.assertTrue(meta["dropped"])
            self.assertIn("repair off", meta["repair"]["result"])
            self.assertEqual(images_in(out), [])

    def test_final_hires_cover_repair(self):
        eng, comps = components("seraphiel", poison_hires=True)
        comps["filter"] = box_filter()
        rc, out = self.run_gen(self.final_args("--no-variants"), comps)
        self.assertEqual(rc, 0)
        kinds = [c[0] for c in eng.calls]
        self.assertEqual(kinds, ["hires", "inpaint", "inpaint"])        # hires, cover repair, face polish
        self.assertEqual(eng.calls[1][1], 101000 + C.REPAIR["seed_offset"])
        fd = os.path.join(out, "seraphiel", "final_s101000")
        for p in ("seraphiel_hires.webp", "seraphiel_source.webp", "seraphiel.png"):
            self.assertIsNone(red_bbox(Image.open(os.path.join(fd, p))), p)
        meta = json.load(open(os.path.join(fd, "seraphiel.json")))
        self.assertIn("seraphiel_hires.webp", meta["repairs"])
        self.assertEqual(meta["status"], "done")

    def test_final_hires_dropped_stops_the_seed(self):
        eng, comps = components("seraphiel", poison_hires=True)
        comps["filter"] = box_filter(stuck=(1248, 1824))
        rc, out = self.run_gen(self.final_args(), comps)
        self.assertEqual(rc, 5)
        self.assertEqual([c[0] for c in eng.calls], ["hires"] + ["inpaint"] * C.REPAIR["attempts"])
        fd = os.path.join(out, "seraphiel", "final_s101000")
        self.assertEqual(images_in(fd), [])
        meta = json.load(open(os.path.join(fd, "seraphiel.json")))
        self.assertEqual(meta["status"], "hires dropped")

    def test_draft_opt_in_and_bible_style(self):
        eng, comps = components("seraphiel")
        rc, out = self.run_gen(["candidates", "--hero", "seraphiel", "--seeds", "101000", "--preset", "draft",
                                "--style", "bible"], comps)
        self.assertEqual(rc, 0)
        self.assertEqual(eng.calls[0][2:5], (14, 5.0, "dpmpp_2m_karras"))
        meta = json.load(open(os.path.join(out, "seraphiel", "seraphiel_s101000.json")))
        self.assertEqual((meta["background"]["key"], meta["style"]["name"]), ("grey", "bible"))

    def test_filter_unavailable_refuses_to_render(self):
        eng, comps = components("seraphiel")

        def unavailable():
            raise safety.FilterUnavailable("no nudenet")
        comps["filter"] = unavailable
        rc, out = self.run_gen(["candidates", "--hero", "seraphiel", "--seeds", "101000"], comps)
        self.assertEqual(rc, 3)
        self.assertEqual(eng.calls, [])
        self.assertFalse(os.path.exists(out) and images_in(out))

    def final_args(self, *extra):
        return ["final", "--hero", "seraphiel", "--seeds", "101000", "--source-run",
                "38832421932-candidates-bench-draft", "--face-px", "512", "--variant-px", "512", *extra]

    def test_final_from_published_candidate(self):
        eng, comps = components("seraphiel")
        rc, out = self.run_gen(self.final_args(), comps)
        self.assertEqual(rc, 0)
        self.assertEqual([c[1:] for c in comps["fetch"].calls], [("38832421932-candidates-bench-draft", "seraphiel", 101000)])
        kinds = [c[0] for c in eng.calls]
        names = BIBLE["heroes"]["seraphiel"]["variant_set"]
        self.assertNotIn("txt2img", kinds)                               # the preview is the base
        self.assertEqual(kinds, ["hires"] + ["inpaint"] * (1 + len(names)))
        hires = eng.calls[0]
        hs = prompts.family_block(BIBLE, C.FAMILY)["settings"]["hires"]
        self.assertEqual(hires[2:7], (hs["steps"], 5.0, "euler_ancestral", (1248, 1824), hs["denoise_model"]))
        self.assertEqual(eng.calls[1][2], C.FINAL["face_steps"])          # effective steps
        self.assertEqual(eng.calls[2][2], C.FINAL["variant_steps"])
        self.assertEqual(eng.kw, [{"dtype": "fp32", "lazy_unet": True}])
        fd = os.path.join(out, "seraphiel", "final_s101000")
        canvas = Image.open(os.path.join(fd, "seraphiel.png"))
        self.assertEqual((canvas.size, canvas.mode), ((1024, 2048), "RGBA"))
        for n in names:
            v = Image.open(os.path.join(fd, "variants", n + ".png"))
            self.assertEqual(v.size, canvas.size)
            self.assertTrue(np.array_equal(np.asarray(v)[..., 3], np.asarray(canvas)[..., 3]))   # same alpha
        vj = json.load(open(os.path.join(fd, "variants", "variants.json")))
        self.assertEqual(sorted(vj["variants"]), sorted(names))
        for n in names:
            self.assertEqual(vj["variants"][n]["tries"][0]["alignment_problems"], [])
        meta = json.load(open(os.path.join(fd, "seraphiel.json")))
        self.assertEqual(meta["origin"], [512, 1990])
        self.assertEqual(meta["status"], "done")
        self.assertEqual(meta["source_candidate"]["run"], "38832421932-candidates-bench-draft")
        self.assertIn("spec", meta)
        self.assertEqual(meta["spec"]["feet_row"], 1990)
        self.assertEqual(meta["style"]["name"], "farm")
        self.assertEqual(safety.verify(out, log=QUIET)["deleted"], 0)
        for p in ("seraphiel_hires.webp", "seraphiel_source.webp", "seraphiel_portrait.png", "seraphiel_check.webp",
                  "seraphiel_boxes.webp", "variants_sheet.webp", "masks/eyes.png", "variants/eyes_open_patch.png"):
            self.assertTrue(os.path.exists(os.path.join(fd, p)), p)
        self.assertFalse(os.path.exists(os.path.join(fd, "seraphiel_base.webp")))    # already on the branch
        self.assertFalse(os.path.exists(os.path.join(fd, "variants", "candidates")))  # only with --variant-tries > 1
        self.assertFalse([p for p in images_in(fd) if p.endswith(("_check.png", "_boxes.png", "sheet.png"))])
        job = json.load(open(os.path.join(out, "seraphiel", "job_k.json")))
        self.assertTrue(job["stage_mem"])
        self.assertEqual(job["dtype"], "fp32")

    def test_final_variant_error_is_isolated(self):
        eng, comps = components("seraphiel", fail_text="singing")       # only mouth_open's prompt has it
        rc, out = self.run_gen(self.final_args(), comps)
        self.assertEqual(rc, 5)
        fd = os.path.join(out, "seraphiel", "final_s101000")
        self.assertTrue(os.path.exists(os.path.join(fd, "seraphiel.png")))
        vj = json.load(open(os.path.join(fd, "variants", "variants.json")))
        self.assertIn("error", vj["variants"]["mouth_open"])
        for n in ("eyes_open", "smile"):
            self.assertTrue(os.path.exists(os.path.join(fd, "variants", n + ".png")), n)
        meta = json.load(open(os.path.join(fd, "seraphiel.json")))
        self.assertEqual(meta["status"], "done with errors")

    def test_final_without_a_face_box_paints_no_face(self):
        eng, comps = components("seraphiel", faces=False)
        rc, out = self.run_gen(self.final_args(), comps)
        self.assertEqual(rc, 5)
        self.assertEqual([c[0] for c in eng.calls], ["hires"])          # no face polish, no variants
        fd = os.path.join(out, "seraphiel", "final_s101000")
        self.assertTrue(os.path.exists(os.path.join(fd, "seraphiel.png")))
        meta = json.load(open(os.path.join(fd, "seraphiel.json")))
        self.assertEqual(meta["face_box_source"], "proportions-only (low)")
        self.assertIn("variants: no face box", meta["skipped"])
        self.assertFalse(os.path.exists(os.path.join(fd, "variants", "eyes_open.png")))

    def test_face_box_plausibility(self):
        fm = {"top": 40, "feet": 1790, "bbox": [20, 40, 1200, 1790], "axis_x": 600}
        self.assertIsNone(gen.face_problem([560, 150, 100, 110], fm))
        self.assertIsNotNone(gen.face_problem([560, 700, 100, 110], fm))       # chest
        self.assertIsNotNone(gen.face_problem([560, 150, 600, 600], fm))       # far too big
        self.assertIsNotNone(gen.face_problem([1500, 150, 100, 110], fm))      # beside the figure

    def test_final_missing_source_renders_nothing(self):
        eng, comps = components("seraphiel")
        rc, out = self.run_gen(["final", "--hero", "seraphiel", "--seeds", "101000", "--source-run",
                                "999-candidates-nothing"], comps)
        self.assertEqual(rc, 6)
        self.assertEqual(eng.calls, [])
        self.assertEqual(eng.kw, [])
        self.assertEqual(images_in(out), [])
        self.assertEqual(gen.main(["final", "--hero", "seraphiel", "--seeds", "1", "--out", out, "--work", out]), 2)

    def test_final_tiny_budget_skips_hires(self):
        eng, comps = components("seraphiel")
        rc, out = self.run_gen(self.final_args("--max-minutes", "0.01"), comps)
        self.assertEqual(rc, 5)
        self.assertEqual(eng.calls, [])
        self.assertFalse(os.path.exists(os.path.join(out, "seraphiel", "final_s101000", "seraphiel.png")))
        meta = json.load(open(os.path.join(out, "seraphiel", "final_s101000", "seraphiel.json")))
        self.assertIn("hires: time budget", meta["skipped"])

    def test_final_no_source_renders_a_base(self):
        eng, comps = components("seraphiel")
        rc, out = self.run_gen(["final", "--hero", "seraphiel", "--seeds", "101000", "--no-source", "--face-px", "512",
                                "--variant-px", "512", "--no-variants"], comps)
        self.assertEqual(rc, 0)
        self.assertEqual([c[0] for c in eng.calls], ["txt2img", "hires", "inpaint"])
        self.assertTrue(os.path.exists(os.path.join(out, "seraphiel", "final_s101000", "seraphiel_base.webp")))

    def test_final_refuses_bf16(self):
        _eng, comps = components("seraphiel")
        rc, _out = self.run_gen(self.final_args("--dtype", "bf16"), comps)
        self.assertEqual(rc, 2)

    def test_bench_writes_no_images(self):
        eng, comps = components("seraphiel")
        rc, out = self.run_gen(["bench", "--hero", "seraphiel"], comps)
        self.assertEqual(rc, 0)
        self.assertEqual(images_in(out), [])
        job = json.load(open(os.path.join(out, "seraphiel", "job_k.json")))
        self.assertEqual([r["threads"] for r in job["bench"]["results"]], [4, 2])
        self.assertEqual(eng.calls, [("bench", 4), ("bench", 2)])


class TestFetchCandidate(unittest.TestCase):
    def store(self, **over):
        img = P.placeholder_figure(BIBLE, "seraphiel", 101000, (832, 1216), label="TEST")
        buf = io.BytesIO()
        img.save(buf, format="WEBP", quality=90)
        blob = buf.getvalue()
        meta = {"hero": "seraphiel", "mode": "candidates", "seed": 101000, "image": "seraphiel_s101000.webp",
                "dropped": False, "width": 832, "height": 1216, "preset": "draft", "preset_settings": C.PRESETS["draft"],
                "prompt": "p", "negative": "n"}
        meta.update(over.pop("meta", {}))
        man = {"files": {"seraphiel/seraphiel_s101000.webp": {"sha256": hashlib.sha256(blob).hexdigest(), "passed": True}}}
        man.update(over.pop("man", {}))
        files = {"seraphiel/seraphiel_s101000.json": json.dumps(meta).encode(), safety.MANIFEST: json.dumps(man).encode(),
                 "seraphiel/seraphiel_s101000.webp": over.pop("blob", blob)}

        def get(url, limit):
            rel = url.split("/runs/1-candidates-x/", 1)[1]
            if rel not in files:
                raise gen.SourceError("not found: " + url)
            return files[rel]
        return get

    def test_ok(self):
        meta, img, src = gen.fetch_candidate("u-tek/game", "1-candidates-x", "seraphiel", 101000, get=self.store())
        self.assertEqual(img.size, (832, 1216))
        self.assertEqual(src["style"], "bible")                  # no style recorded = the bible's prompts
        self.assertEqual(src["path"], "runs/1-candidates-x/seraphiel/seraphiel_s101000.webp")

    def test_rejects(self):
        cases = [dict(meta={"dropped": True}), dict(meta={"mode": "final"}), dict(meta={"seed": 1}),
                 dict(meta={"width": 768}), dict(man={"files": {}}), dict(blob=b"RIFF0000WEBPjunk")]
        for c in cases:
            with self.assertRaises(gen.SourceError, msg=str(c)[:60]):
                gen.fetch_candidate("u-tek/game", "1-candidates-x", "seraphiel", 101000, get=self.store(**c))
        for repo, run in (("u-tek/game;x", "1-candidates-x"), ("u-tek/game", "../x")):
            with self.assertRaises(gen.SourceError):
                gen.fetch_candidate(repo, run, "seraphiel", 101000, get=self.store())


# ------------------------------------------------------------------ sheets job and publish job
class TestSheetsAndPublish(unittest.TestCase):
    def setUp(self):
        self.d = tempfile.mkdtemp()

    def tearDown(self):
        shutil.rmtree(self.d, ignore_errors=True)

    def candidates_out(self, name, seeds="101000"):
        _eng, comps = components("seraphiel")
        out = os.path.join(self.d, name)
        gen.main(["candidates", "--hero", "seraphiel", "--seeds", seeds, "--out", out, "--work",
                  os.path.join(self.d, "w_" + name), "--key", name, "--run", "1-test"], components=comps)
        return out

    def bundle(self, name, seeds="101000", plan_keys=("k",)):
        incoming = os.path.join(self.d, "in_" + name)
        os.makedirs(incoming)
        shutil.copytree(self.candidates_out(name, seeds), os.path.join(incoming, "art-" + name))
        bdir = os.path.join(self.d, "bundle_" + name)
        orig = safety.ExposureFilter
        safety.ExposureFilter = lambda scorers=None, log=QUIET, **kw: orig(
            scorers if scorers is not None else [red_square_scorer(), FakeScorer("second")], log=log)
        try:
            collect.main(["--incoming", incoming, "--run-dir", "1-test", "--out", bdir,
                          "--plan-json", json.dumps({"include": [{"key": k} for k in plan_keys]})])
        finally:
            safety.ExposureFilter = orig
        return bdir

    def test_collect_merges_and_gates(self):
        out = self.candidates_out("k")
        incoming = os.path.join(self.d, "incoming")
        shutil.copytree(out, os.path.join(incoming, "art-seraphiel-c0"))
        Image.new("RGB", (8, 8)).save(os.path.join(incoming, "art-seraphiel-c0", "seraphiel", "rogue.png"))
        stage = os.path.join(self.d, "stage")
        os.makedirs(stage)
        merged, jobs = collect.merge_artifacts(incoming, stage)
        self.assertNotIn("seraphiel/rogue.png", merged["files"])
        self.assertFalse(os.path.exists(os.path.join(stage, "seraphiel", "rogue.png")))
        titles = []
        orig = post.contact_sheet
        post.contact_sheet = lambda entries, out_path, **kw: (titles.append(kw.get("title")), orig(entries, out_path, **kw))[1]
        try:
            sheets = collect.make_sheets(stage, merged, fake_filter(), run_name="1-test")
        finally:
            post.contact_sheet = orig
        self.assertEqual(sorted(sheets), ["overview.webp", "seraphiel/contact_sheet.webp"])
        self.assertTrue(all("1-test" in t and "artgen_" not in t for t in titles), titles)
        collect.write_manifest(stage, merged)
        self.assertEqual(safety.verify(stage, log=QUIET)["deleted"], 0)
        idx = collect.run_index("1-test", stage, merged, jobs, {"include": [{"key": "k"}, {"key": "x"}]}, sheets, "")
        self.assertEqual(idx["jobs_missing"], ["x"])
        self.assertEqual(idx["filter_totals"]["published_images"], 3)

    def test_verify_bundle_rejects(self):
        b = self.bundle("k")
        hdir = os.path.join(b, "seraphiel")
        good = os.path.join(hdir, "seraphiel_s101000.webp")
        man = publish.read_json(os.path.join(b, publish.MANIFEST))
        # a recorded name whose bytes are not a WebP, an unrecorded image, a symlink, a bad type, broken JSON
        fake = os.path.join(hdir, "fake.webp")
        with open(fake, "wb") as fh:
            fh.write(b"GIF89a not webp")
        man["files"]["seraphiel/fake.webp"] = {"sha256": publish.sha256_file(fake), "passed": True}
        publish.write_json(os.path.join(b, publish.MANIFEST), man)
        Image.new("RGB", (8, 8)).save(os.path.join(hdir, "unrecorded.png"))
        os.symlink(good, os.path.join(hdir, "link.webp"))
        with open(os.path.join(hdir, "x.sh"), "w") as fh:
            fh.write("echo")
        with open(os.path.join(hdir, "bad.json"), "w") as fh:
            fh.write("{")
        res, _ = publish.verify_bundle(b)
        self.assertEqual(res["deleted"], 5)
        self.assertEqual(sorted(f for f in os.listdir(hdir) if not f.endswith(".json")),
                         ["contact_sheet.webp", "seraphiel_s101000.webp"])
        with open(good, "ab") as fh:                       # changed after the filter
            fh.write(b"\0")
        publish.verify_bundle(b)
        self.assertFalse(os.path.exists(good))

    def git_remote(self):
        remote = os.path.join(self.d, "remote.git")
        subprocess.run(["git", "init", "-q", "--bare", remote], check=True)
        return "file://" + remote

    def ls(self, remote):
        return subprocess.run(["git", "--git-dir", remote[7:], "ls-tree", "-r", "--name-only", publish.BRANCH],
                              capture_output=True, text=True, check=True).stdout.split()

    def show(self, remote, path):
        return subprocess.run(["git", "--git-dir", remote[7:], "show", "%s:%s" % (publish.BRANCH, path)],
                              capture_output=True, check=True).stdout

    def test_publish_merges_never_deletes(self):
        remote = self.git_remote()
        b1 = self.bundle("a", seeds="101000,101001", plan_keys=("a", "b"))
        publish.verify_bundle(b1)
        self.assertTrue(publish.publish(b1, "1-test", remote, os.path.join(self.d, "w1")))
        first = self.ls(remote)
        self.assertIn("runs/1-test/seraphiel/seraphiel_s101000.webp", first)
        self.assertIn("runs/1-test/seraphiel/seraphiel_s101001.webp", first)
        # a re-run that only has job b's (different) output and fewer files: nothing published is deleted
        b2 = self.bundle("b", seeds="101002", plan_keys=("a", "b"))
        publish.verify_bundle(b2)
        self.assertTrue(publish.publish(b2, "1-test", remote, os.path.join(self.d, "w2")))
        second = self.ls(remote)
        self.assertTrue(set(first) <= set(second), set(first) - set(second))
        self.assertIn("runs/1-test/seraphiel/seraphiel_s101002.webp", second)
        man = json.loads(self.show(remote, "runs/1-test/filter_manifest.json"))
        for s in (101000, 101001, 101002):
            self.assertIn("seraphiel/seraphiel_s%d.webp" % s, man["files"])
        self.assertEqual(sorted(man["jobs"]), ["a", "b"])
        idx = json.loads(self.show(remote, "runs/1-test/index.json"))
        self.assertEqual(idx["jobs_missing"], [])
        self.assertEqual(sorted(j["key"] for j in idx["jobs"]), ["a", "b"])
        branch = json.loads(self.show(remote, "index.json"))
        self.assertEqual([r["run"] for r in branch["runs"]], ["1-test"])
        # a changed file with the same name replaces the old one
        b3 = self.bundle("c", seeds="101000", plan_keys=("c",))
        publish.verify_bundle(b3)
        new_sha = publish.sha256_file(os.path.join(b3, "seraphiel", "seraphiel_s101000.webp"))
        self.assertTrue(publish.publish(b3, "1-test", remote, os.path.join(self.d, "w3")))
        self.assertEqual(hashlib.sha256(self.show(remote, "runs/1-test/seraphiel/seraphiel_s101000.webp")).hexdigest(),
                         new_sha)
        # another run lands next to it
        self.assertTrue(publish.publish(b3, "2-test", remote, os.path.join(self.d, "w4")))
        self.assertIn("runs/1-test/seraphiel/seraphiel_s101001.webp", self.ls(remote))
        self.assertEqual([r["run"] for r in json.loads(self.show(remote, "index.json"))["runs"]], ["1-test", "2-test"])

    def test_final_gate_refuses_unrecorded(self):
        remote = self.git_remote()
        b = self.bundle("a")
        publish.verify_bundle(b)
        Image.new("RGB", (8, 8)).save(os.path.join(b, "seraphiel", "sneaked_in_after_verify.png"))
        self.assertFalse(publish.publish(b, "1-test", remote, os.path.join(self.d, "w")))
        self.assertEqual(self.ls_or_empty(remote), [])

    def ls_or_empty(self, remote):
        r = subprocess.run(["git", "--git-dir", remote[7:], "ls-tree", "-r", "--name-only", publish.BRANCH],
                           capture_output=True, text=True)
        return r.stdout.split() if r.returncode == 0 else []

    def test_publish_is_stdlib_only_and_in_sync(self):
        tree = ast.parse(open(os.path.join(HERE, "publish.py")).read())
        mods = set()
        for n in ast.walk(tree):
            if isinstance(n, ast.Import):
                mods |= {a.name.split(".")[0] for a in n.names}
            elif isinstance(n, ast.ImportFrom):
                mods.add((n.module or "").split(".")[0])
        stdlib = set(getattr(sys, "stdlib_module_names", ())) or {
            "argparse", "base64", "datetime", "hashlib", "json", "os", "re", "shutil", "subprocess", "sys", "tempfile",
            "time"}
        self.assertTrue(mods <= stdlib, mods - stdlib)
        self.assertEqual(publish.BRANCH, C.BRANCH)
        self.assertEqual(publish.UPLOAD_IMAGE_EXTS, C.UPLOAD_IMAGE_EXTS)
        self.assertEqual(publish.UPLOAD_TEXT_EXTS, C.UPLOAD_TEXT_EXTS)
        self.assertEqual(publish.MANIFEST, safety.MANIFEST)


# ------------------------------------------------------------------ workflow hardening
class TestWorkflow(unittest.TestCase):
    def setUp(self):
        try:
            import yaml
        except ImportError:
            self.skipTest("PyYAML not installed")
        with open(WORKFLOW) as f:
            self.wf = yaml.safe_load(f)
        self.jobs = self.wf["jobs"]

    def steps(self):
        for jname, job in self.jobs.items():
            for st in job.get("steps", []):
                yield jname, st

    def test_pinned_actions(self):
        for jname, st in self.steps():
            if "uses" in st:
                self.assertRegex(st["uses"], r"^actions/[a-z-]+@[0-9a-f]{40}$", jname)

    def test_permissions(self):
        self.assertEqual(self.wf["permissions"], {})
        writers = [j for j, job in self.jobs.items() if (job.get("permissions") or {}).get("contents") == "write"]
        self.assertEqual(writers, ["publish"])
        for j, job in self.jobs.items():
            self.assertIn("permissions", job, j)

    def test_publish_job_runs_no_third_party_code(self):
        pub = self.jobs["publish"]
        text = json.dumps(pub)
        for bad in ("setup-python", "pip install", "pip3", "python -m pip", "actions/cache", "requirements"):
            self.assertNotIn(bad, text)
        runs = [st["run"] for st in pub["steps"] if "run" in st]
        self.assertEqual(len(runs), 1)
        self.assertIn("tools/artgen/publish.py", runs[0])
        self.assertIn("GITHUB_TOKEN", json.dumps([st.get("env") for st in pub["steps"] if "run" in st]))
        others = json.dumps({j: v for j, v in self.jobs.items() if j != "publish"})
        self.assertNotIn("GITHUB_TOKEN", others)
        self.assertNotIn("github.token", others)

    def test_checkouts_uploads_and_limits(self):
        for jname, st in self.steps():
            if st.get("uses", "").startswith("actions/checkout@"):
                self.assertIs(st["with"].get("persist-credentials"), False, jname)
            if st.get("uses", "").startswith("actions/upload-artifact@"):
                self.assertIs(st["with"].get("overwrite"), True, jname)
        self.assertEqual(self.jobs["gen"]["strategy"]["max-parallel"], C.LIMITS["max_parallel"])
        self.assertIs(self.wf["concurrency"]["cancel-in-progress"], False)
        self.assertIn("inputs.mode", self.wf["concurrency"]["group"])

    def test_inputs_match_config(self):
        inputs = self.wf[True]["workflow_dispatch"]["inputs"] if True in self.wf else self.wf["on"]["workflow_dispatch"]["inputs"]
        self.assertEqual(sorted(inputs["preset"]["options"]), sorted(C.PRESETS))
        self.assertEqual(inputs["preset"]["default"], C.DEFAULT_PRESET)
        self.assertEqual(sorted(inputs["style"]["options"]), sorted(C.STYLES))
        self.assertEqual(inputs["style"]["default"], C.DEFAULT_STYLE)
        self.assertEqual(inputs["dtype"]["options"], list(C.DTYPES))
        self.assertEqual(inputs["dtype"]["default"], C.DEFAULT_DTYPE)

    def test_no_expressions_in_run(self):
        for jname, st in self.steps():
            if "run" in st:
                self.assertNotIn("${{", st["run"], jname)


if __name__ == "__main__":
    unittest.main(verbosity=1)
