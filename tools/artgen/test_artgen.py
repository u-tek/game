#!/usr/bin/env python3
"""Offline tests for the art farm (no torch, no network): input validation, the exposure filter's
fail-closed behaviour, the upload gate, prompt chunking, and both render modes end to end with a
fake model, fake detectors and placeholder figures.

    python3 tools/artgen/test_artgen.py
"""
import json
import os
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
import gen  # noqa: E402
import pipeline as P  # noqa: E402
import plan  # noqa: E402
import prompts  # noqa: E402
import safety  # noqa: E402
import sdxl_chunks  # noqa: E402

BIBLE = prompts.load_bible()


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


def fake_filter(log=lambda *a: None):
    return safety.ExposureFilter([red_square_scorer(), FakeScorer("second")], log=log)


class FakeEncoders:
    def encode_pair(self, pos, neg):
        return {"prompt_embeds": None, "pooled_prompt_embeds": None, "negative_prompt_embeds": None,
                "negative_pooled_prompt_embeds": None, "chunks": [2, 3], "pos": pos, "neg": neg}

    def close(self):
        pass


class FakeEngine:
    load_s = 0.0

    def __init__(self, hero, poison_seed=None):
        self.hero, self.lora, self.calls, self.poison_seed = hero, None, [], poison_seed

    def set_lora(self, name, scale=1.0, cache_dir=None):
        self.lora = {"name": name, "scale": scale} if name else None

    def _info(self, what):
        return {"what": what, "seconds": 0.1, "steps_run": 1, "s_per_step": 0.1, "decode_s": 0.0, "rss_peak_gb": 0.1}

    def txt2img(self, emb, seed, steps, cfg, sampler, width, height):
        self.calls.append(("txt2img", seed, self.lora))
        im = P.placeholder_figure(BIBLE, self.hero, seed, (width, height), label="TEST")
        if seed == self.poison_seed:
            ImageDraw.Draw(im).rectangle([300, 500, 420, 620], fill=(255, 0, 0))
        return im, self._info("txt2img %dx%d" % (width, height))

    def img2img(self, emb, image, strength, seed, steps, cfg, sampler):
        self.calls.append(("img2img", seed, self.lora))
        return image.copy(), self._info("img2img")

    def inpaint(self, emb, image, mask, strength, seed, steps, cfg, sampler):
        self.calls.append(("inpaint", seed, self.lora))
        out = image.copy()
        tint = Image.new("RGB", image.size, (60, 200, 255))
        out.paste(tint, (0, 0), mask)
        return out, self._info("inpaint")


def components(hero, poison_seed=None):
    eng = FakeEngine(hero, poison_seed)
    return eng, {"filter": fake_filter, "encoders": FakeEncoders, "engine": lambda: eng,
                 "cutter": lambda: None, "faces": lambda: None}


# ------------------------------------------------------------------ tests
class TestPlan(unittest.TestCase):
    def env(self, **kw):
        e = {"ART_MODE": "candidates", "ART_HEROES": "seraphiel", "ART_COUNT": "2", "ART_SEEDS": "{}",
             "ART_PRESET": "lightning8", "ART_PER_JOB": "0", "ART_LABEL": "smoke", "GITHUB_RUN_ID": "123"}
        e.update(kw)
        return e

    def test_smoke_plan(self):
        p = plan.build(self.env(), BIBLE)
        self.assertEqual(p["run_dir"], "123-candidates-smoke")
        self.assertEqual(p["matrix"]["include"], [{"key": "seraphiel-c0", "hero": "seraphiel", "seeds": "101000,101001",
                                                   "flip": "0", "source_run": ""}])

    def test_all_heroes_and_split(self):
        p = plan.build(self.env(ART_HEROES="all", ART_COUNT="6", ART_PER_JOB="3"), BIBLE)
        self.assertEqual(p["jobs"], 30)
        self.assertEqual(len({e["key"] for e in p["matrix"]["include"]}), 30)

    def test_rejects_bad_input(self):
        for kw in ({"ART_HEROES": "seraphiel; rm -rf /"}, {"ART_HEROES": "nobody"}, {"ART_COUNT": "99"},
                   {"ART_COUNT": "2; echo"}, {"ART_PRESET": "dmd2"}, {"ART_MODE": "shell"},
                   {"ART_SEEDS": "not json"}, {"ART_SEEDS": '{"seraphiel": "1; ls"}'},
                   {"ART_MODE": "final", "ART_SEEDS": "{}"}, {"ART_MODE": "final", "ART_SEEDS": '{"seraphiel": [true]}'},
                   {"ART_MODE": "final", "ART_SEEDS": '{"seraphiel": {"seeds": [1], "run": "../x"}}'},
                   {"GITHUB_RUN_ID": "1$(id)"}):
            with self.assertRaises(plan.PlanError, msg=str(kw)):
                plan.build(self.env(**kw), BIBLE)

    def test_label_is_cleaned(self):
        p = plan.build(self.env(ART_LABEL="$(curl evil) `x` ../../ OK"), BIBLE)
        self.assertRegex(p["run_dir"], r"^123-candidates-[a-z0-9-]+$")

    def test_final_plan(self):
        p = plan.build(self.env(ART_MODE="final",
                                ART_SEEDS='{"seraphiel": {"seeds": [101001], "flip": true, "run": "1-candidates-x"}}'), BIBLE)
        self.assertEqual(p["matrix"]["include"], [{"key": "seraphiel-f101001", "hero": "seraphiel", "seeds": "101001",
                                                   "flip": "1", "source_run": "1-candidates-x"}])

    def test_no_dmd2(self):
        self.assertFalse(any("dmd" in json.dumps(v).lower() for v in C.LORAS.values()))


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
        # 40x40 red in a 1024x2048 image: ~0.08% of the full view, but a large share of a 512 tile
        im = Image.new("RGB", (1024, 2048), (128, 128, 128))
        ImageDraw.Draw(im).rectangle([600, 900, 640, 940], fill=(255, 0, 0))
        f = fake_filter()
        ok, rep = f.check_image(im)
        self.assertFalse(ok)
        self.assertTrue(rep["flagged"][0]["view"].startswith("t"))

    def test_detector_error_drops(self):
        def boom(img):
            raise RuntimeError("model crashed")
        f = safety.ExposureFilter([FakeScorer(fn=boom)])
        ok, rep = f.check_file(self.img("a.png"))
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
        # sneak files in: an unlisted image, a tampered image, a disallowed type, broken json
        Image.new("RGB", (8, 8)).save(os.path.join(out, "h", "sneak.png"))
        Image.new("RGB", (8, 8)).save(os.path.join(out, "h", "sneak.jpg"))
        with open(os.path.join(out, "h", "note.txt"), "w") as fh:
            fh.write("x")
        with open(os.path.join(out, "h", "bad.json"), "w") as fh:
            fh.write("{")
        res = safety.verify(out, log=lambda *a: None)
        left = sorted(os.listdir(os.path.join(out, "h")))
        self.assertEqual(left, ["g.json", "g.png"])
        self.assertEqual(res["deleted"], 4)
        with open(good, "ab") as fh:                 # changed after the filter
            fh.write(b"\0")
        safety.verify(out, log=lambda *a: None)
        self.assertFalse(os.path.exists(good))

    def test_verify_without_manifest_deletes_images(self):
        out = os.path.join(self.d, "o")
        os.makedirs(out)
        Image.new("RGB", (8, 8)).save(os.path.join(out, "a.png"))
        safety.verify(out, log=lambda *a: None)
        self.assertEqual(os.listdir(out), [])

    def test_publish_rejects_other_types(self):
        out = os.path.join(self.d, "out")
        pub = safety.Publisher(fake_filter(), out)
        with self.assertRaises(ValueError):
            pub.publish(self.img("g.jpg"), "h/g.jpg")
        with self.assertRaises(ValueError):
            pub.write_json("../escape.json", {})


class TestChunks(unittest.TestCase):
    def test_pack_like_comfy(self):
        words = [([1, 2], 1.0)] * 37 + [([3, 4, 5], 1.2)]    # 74 tokens, then a 3-token word
        ch = sdxl_chunks.pack_chunks(words)
        self.assertEqual([len(c) for c in ch], [74, 3])      # the word moves to the next chunk whole
        self.assertEqual(ch[1][0], (3, 1.2))
        long_word = [(list(range(10)), 1.0)]
        ch = sdxl_chunks.pack_chunks([([0] * 70, 1.0)] + long_word)
        self.assertEqual([len(c) for c in ch], [75, 5])      # >= 8 tokens: split across chunks
        self.assertEqual(sdxl_chunks.pack_chunks([]), [[]])

    def test_prompts_fit_two_chunks(self):
        for hid in BIBLE["heroes"]:
            pr = prompts.full_body(BIBLE, hid, C.FAMILY)
            self.assertLessEqual(pr["stats"]["positive"]["chunks"], 2, hid)
            gen.checked(BIBLE, hid, pr["positive"], pr["negative"])     # enforce() passes for all 15


class TestModes(unittest.TestCase):
    def setUp(self):
        self.d = tempfile.mkdtemp()

    def tearDown(self):
        shutil.rmtree(self.d, ignore_errors=True)

    def run_gen(self, args, comps):
        out, work = os.path.join(self.d, "out"), os.path.join(self.d, "work")
        rc = gen.main(args + ["--out", out, "--work", work, "--key", "k", "--run", "1-test"], components=comps)
        return rc, out

    def test_candidates(self):
        eng, comps = components("seraphiel", poison_seed=101001)
        rc, out = self.run_gen(["candidates", "--hero", "seraphiel", "--seeds", "101000,101001"], comps)
        self.assertEqual(rc, 0)
        files = sorted(os.listdir(os.path.join(out, "seraphiel")))
        self.assertIn("seraphiel_s101000.webp", files)
        self.assertNotIn("seraphiel_s101001.webp", files)            # the poisoned one was dropped
        meta = json.load(open(os.path.join(out, "seraphiel", "seraphiel_s101001.json")))
        self.assertTrue(meta["dropped"])
        meta = json.load(open(os.path.join(out, "seraphiel", "seraphiel_s101000.json")))
        self.assertEqual(meta["lora"]["name"], "lightning8")
        self.assertIn("adult", meta["prompt"])
        man = json.load(open(os.path.join(out, safety.MANIFEST)))
        self.assertEqual(len(man["dropped"]), 1)
        self.assertEqual(safety.verify(out, log=lambda *a: None)["deleted"], 0)
        self.assertEqual([c[0] for c in eng.calls], ["txt2img", "txt2img"])

    def test_filter_unavailable_refuses_to_render(self):
        eng, comps = components("seraphiel")

        def unavailable():
            raise safety.FilterUnavailable("no nudenet")
        comps["filter"] = unavailable
        rc, out = self.run_gen(["candidates", "--hero", "seraphiel", "--seeds", "101000"], comps)
        self.assertEqual(rc, 3)
        self.assertEqual(eng.calls, [])
        self.assertFalse(os.path.exists(out) and any(f.endswith((".png", ".webp")) for _, _, fs in os.walk(out) for f in fs))

    def test_final_end_to_end(self):
        eng, comps = components("seraphiel")
        rc, out = self.run_gen(["final", "--hero", "seraphiel", "--seeds", "101001", "--no-source",
                                "--inpaint-px", "256"], comps)
        self.assertEqual(rc, 0)
        fd = os.path.join(out, "seraphiel", "final_s101001")
        canvas = Image.open(os.path.join(fd, "seraphiel.png"))
        self.assertEqual((canvas.size, canvas.mode), ((1024, 2048), "RGBA"))
        names = BIBLE["heroes"]["seraphiel"]["variant_set"]
        for n in names:
            v = Image.open(os.path.join(fd, "variants", n + ".png"))
            self.assertEqual(v.size, canvas.size)
            self.assertTrue(np.array_equal(np.asarray(v)[..., 3], np.asarray(canvas)[..., 3]))   # same alpha
        with open(os.path.join(fd, "variants", "variants.json")) as fh:
            vj = json.load(fh)
        self.assertEqual(sorted(vj["variants"]), sorted(names))
        for n in names:
            self.assertEqual(vj["variants"][n]["tries"][0]["alignment_problems"], [])
        meta = json.load(open(os.path.join(fd, "seraphiel.json")))
        self.assertEqual(meta["origin"], [512, 1990])
        kinds = [c[0] for c in eng.calls]
        self.assertEqual(kinds[:2], ["txt2img", "img2img"])
        self.assertEqual(eng.calls[0][2]["name"], "lightning8")        # base with the candidate LoRA
        self.assertIsNone(eng.calls[1][2])                              # quality passes without it
        self.assertEqual(kinds.count("inpaint"), 1 + len(names))       # face polish + variants
        self.assertEqual(safety.verify(out, log=lambda *a: None)["deleted"], 0)
        for p in ("seraphiel_base.webp", "seraphiel_source.webp", "seraphiel_portrait.png", "variants_sheet.png",
                  "masks/eyes.png"):
            self.assertTrue(os.path.exists(os.path.join(fd, p)), p)

    def test_collect_merges_and_gates(self):
        _eng, comps = components("seraphiel")
        _rc, out = self.run_gen(["candidates", "--hero", "seraphiel", "--seeds", "101000"], comps)
        incoming = os.path.join(self.d, "incoming")
        shutil.copytree(out, os.path.join(incoming, "art-seraphiel-c0"))
        Image.new("RGB", (8, 8)).save(os.path.join(incoming, "art-seraphiel-c0", "seraphiel", "rogue.png"))
        stage = os.path.join(self.d, "stage")
        os.makedirs(stage)
        merged, jobs = collect.merge_artifacts(incoming, stage)
        self.assertNotIn("seraphiel/rogue.png", merged["files"])
        self.assertFalse(os.path.exists(os.path.join(stage, "seraphiel", "rogue.png")))
        sheets = collect.make_sheets(stage, merged, fake_filter())
        self.assertIn("seraphiel/contact_sheet.png", sheets)
        collect.write_manifest(stage, merged)
        self.assertEqual(safety.verify(stage, log=lambda *a: None)["deleted"], 0)
        idx = collect.run_index("1-test", stage, merged, jobs, {"include": [{"key": "k"}, {"key": "x"}]}, sheets, "")
        self.assertEqual(idx["jobs_missing"], ["x"])
        self.assertEqual(idx["filter_totals"]["published_images"], 3)

    def test_collect_push_to_local_remote(self):
        _eng, comps = components("seraphiel")
        _rc, out = self.run_gen(["candidates", "--hero", "seraphiel", "--seeds", "101000"], comps)
        stage = os.path.join(self.d, "stage")
        shutil.copytree(out, stage)
        remote = os.path.join(self.d, "remote.git")
        subprocess.run(["git", "init", "-q", "--bare", remote], check=True)
        bdir = os.path.join(self.d, "branch")
        os.makedirs(bdir)
        subprocess.run(["git", "init", "-q"], cwd=bdir, check=True)
        subprocess.run(["git", "remote", "add", "origin", remote], cwd=bdir, check=True)
        subprocess.run(["git", "config", "user.name", "t"], cwd=bdir, check=True)
        subprocess.run(["git", "config", "user.email", "t@t"], cwd=bdir, check=True)
        self.assertTrue(collect.push(stage, "1-test", bdir, "x/y", ""))
        self.assertTrue(collect.push(stage, "2-test", bdir, "x/y", ""))   # second run onto the existing branch
        ls = subprocess.run(["git", "ls-tree", "-r", "--name-only", "art-gen-output"], cwd=remote,
                            capture_output=True, text=True, check=True).stdout.split()
        self.assertIn("runs/1-test/seraphiel/seraphiel_s101000.webp", ls)
        self.assertIn("runs/2-test/seraphiel/seraphiel_s101000.webp", ls)
        self.assertIn("index.json", ls)


if __name__ == "__main__":
    unittest.main(verbosity=1)
