#!/usr/bin/env python3
"""Tests for the ComfyUI art pipeline (stdlib unittest; needs PIL + numpy, no server, no network).

    python3 tools/comfy/test_pipeline.py            (or: python3 -m unittest discover -s tools/comfy -p 'test_*.py')

Covers: every workflow graph (links point to existing nodes and valid outputs of the right type,
required inputs present, widget types and combo values valid), schema-driven custom nodes against a
fake /object_info, discovery parsing, the HTTP client in dry-run and with a fake server, the prompt
bible (15 heroes, content-rule terms in every negative, adult cue in every positive), post.py on
synthetic images, and a full --dry-run (candidates -> finalize -> variants) in a temp folder.
"""
import email.parser
import email.policy
import hashlib
import http.server
import io
import json
import os
import shutil
import sys
import tempfile
import threading
import types
import unittest
from contextlib import redirect_stdout, redirect_stderr

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import numpy as np  # noqa: E402
from PIL import Image, ImageDraw  # noqa: E402

import comfy  # noqa: E402
import core_nodes  # noqa: E402
import pipeline as P  # noqa: E402
import post  # noqa: E402
import prompts  # noqa: E402
import workflows  # noqa: E402

ROOT = comfy.ROOT
BIBLE = prompts.load_bible()
TMP = None


def setUpModule():
    global TMP
    TMP = tempfile.mkdtemp(prefix="halo_comfy_test_")
    os.environ["HALO_ART_SRC"] = TMP      # keep tests out of the real art_src/


def tearDownModule():
    shutil.rmtree(TMP, ignore_errors=True)
    os.environ.pop("HALO_ART_SRC", None)


def args(**kw):
    base = dict(dry_run=True, ckpt=None, family=None, sampler=None, scheduler=None, steps=None, cfg=None, size=None,
                lora=[], vae=None, upscale_model=None, no_hires=False, hires_mode="auto", hires_denoise=None,
                timeout=900, quiet=True, zsnr=None)
    base.update(kw)
    return types.SimpleNamespace(**base)


def settings(family="illustrious", hero="kessa", **kw):
    client = comfy.Comfy(dry_run=True, verbose=False)
    s, _, _ = P.resolve_settings(BIBLE, args(family=family, **kw), client, hero)
    return s


def md5(path):
    return hashlib.md5(open(path, "rb").read()).hexdigest()


def fake_object_info(new_combo_format=False):
    """A /object_info payload built from the core schema, plus some custom nodes."""
    combos = {("CheckpointLoaderSimple", "ckpt_name"): ["noobaiXL_vpred10.safetensors", "illustriousXL_v01.safetensors",
                                                         "sd_xl_refiner_1.0.safetensors"],
              ("LoraLoader", "lora_name"): ["detail_tweaker_xl.safetensors"],
              ("LoraLoaderModelOnly", "lora_name"): ["detail_tweaker_xl.safetensors"],
              ("VAELoader", "vae_name"): ["sdxl_vae.safetensors"],
              ("UpscaleModelLoader", "model_name"): ["RealESRGAN_x2.pth", "4x-AnimeSharp.pth"],
              ("ControlNetLoader", "control_net_name"): ["openpose_sdxl.safetensors"],
              ("LoadImage", "image"): ["example.png"], ("LoadImageMask", "image"): ["example.png"]}
    oi = {}
    for cls, sch in core_nodes.CORE.items():
        req = {}
        for name, t in sch["required"].items():
            if isinstance(t, list):
                opts = t
            elif t == "COMBO":
                opts = combos.get((cls, name), ["x.safetensors"])
            else:
                opts = None
            if opts is not None:
                req[name] = ["COMBO", {"options": opts}] if new_combo_format else [opts]
            elif t in ("INT", "FLOAT"):
                req[name] = [t, {"default": 0}]
            elif t in ("STRING", "BOOLEAN"):
                req[name] = [t, {}]
            else:
                req[name] = [t]
        opt = {k: [v] for k, v in sch["optional"].items()}
        oi[cls] = {"input": {"required": req, "optional": opt}, "output": sch["output"],
                   "output_node": cls in core_nodes.OUTPUT_NODES, "name": cls}
    oi["IPAdapterUnifiedLoader"] = {"input": {"required": {
        "model": ["MODEL"], "preset": [["LIGHT - SD1.5 only (low strength)", "STANDARD (medium strength)",
                                        "PLUS (high strength)"]]}, "optional": {"ipadapter": ["IPADAPTER"]}},
        "output": ["MODEL", "IPADAPTER"]}
    oi["IPAdapterAdvanced"] = {"input": {"required": {
        "model": ["MODEL"], "ipadapter": ["IPADAPTER"], "image": ["IMAGE"],
        "weight": ["FLOAT", {"default": 1.0}], "weight_type": [["linear", "ease in"]],
        "combine_embeds": [["concat", "add"]], "start_at": ["FLOAT", {"default": 0.0}],
        "end_at": ["FLOAT", {"default": 1.0}], "embeds_scaling": [["V only", "K+V"]]},
        "optional": {"image_negative": ["IMAGE"], "attn_mask": ["MASK"], "clip_vision": ["CLIP_VISION"]}},
        "output": ["MODEL"]}
    oi["BRIA_RMBG_ModelLoader_Zho"] = {"input": {"required": {}}, "output": ["RMBGMODEL"]}
    oi["BRIA_RMBG_Zho"] = {"input": {"required": {"rmbgmodel": ["RMBGMODEL"], "image": ["IMAGE"]}},
                           "output": ["IMAGE", "MASK"]}
    oi["FaceDetailer"] = {"input": {"required": {"image": ["IMAGE"]}}, "output": ["IMAGE"]}
    oi["KSampler"]["input"]["required"]["sampler_name"] = [["euler", "euler_ancestral", "dpmpp_2m"]]
    return oi


def links_ok(graph):
    for nid, node in graph.items():
        for v in node["inputs"].values():
            if isinstance(v, list):
                assert len(v) == 2 and isinstance(v[0], str) and isinstance(v[1], int), (nid, v)
                assert v[0] in graph, (nid, v)
    return True


# ------------------------------------------------------------------ workflows
class TestWorkflows(unittest.TestCase):
    def check(self, graph, schema=None):
        errs = core_nodes.validate_graph(graph, schema)
        self.assertEqual(errs, [], "\n".join(errs))
        self.assertTrue(links_ok(graph))
        json.dumps(graph)  # serializable
        return graph

    def test_txt2img_every_family_and_mode(self):
        for fam in BIBLE["families"]:
            for kw in ({}, {"no_hires": True}, {"upscale_model": "4x-AnimeSharp.pth"},
                       {"upscale_model": "4x-AnimeSharp.pth", "hires_mode": "latent"},
                       {"lora": ["detail_tweaker_xl.safetensors:0.6"], "vae": "sdxl_vae.safetensors"}):
                s = settings(fam, **kw)
                g = self.check(workflows.txt2img(s, "pos", "neg", 123, "halo_horn/x"))
                classes = [n["class_type"] for n in g.values()]
                self.assertIn("SaveImage", classes)
                ks = [n for n in g.values() if n["class_type"] == "KSampler"]
                self.assertEqual(len(ks), 1 if kw.get("no_hires") else 2)
                if not kw.get("no_hires"):
                    self.assertAlmostEqual(ks[1]["inputs"]["denoise"], s["hires"]["denoise"])
                    self.assertTrue(0.35 <= ks[1]["inputs"]["denoise"] <= 0.55)
                if s["hires"]["mode"] == "model" and not kw.get("no_hires"):
                    self.assertIn("ImageUpscaleWithModel", classes)
                elif not kw.get("no_hires"):
                    self.assertIn("LatentUpscaleBy", classes)
                if fam == "pony":
                    self.assertIn("CLIPSetLastLayer", classes)
                if fam == "noobai_vpred":
                    self.assertIn("ModelSamplingDiscrete", classes)
                    self.assertIn("RescaleCFG", classes)
                if kw.get("lora"):
                    self.assertIn("LoraLoader", classes)
                    self.assertIn("VAELoader", classes)

    def test_sdxl_bucket_and_hires_sizes(self):
        s = settings("illustrious")
        self.assertIn((s["width"], s["height"]), [(768, 1344), (832, 1216), (704, 1408)])
        w, h = P.output_size(s)
        self.assertEqual((w % 8, h % 8), (0, 0))

    def test_img2img_inpaint_upscale(self):
        for up in (None, "4x-AnimeSharp.pth"):
            s = settings("illustrious", upscale_model=up)
            self.check(workflows.img2img(s, "halo_horn/a.png", "p", "n", 1, 0.3, "x"))
            self.check(workflows.img2img(s, "halo_horn/a.png", "p", "n", 1, 0.3, "x", scale_by=2.0))
            self.check(workflows.upscale(s, "halo_horn/a.png", "x", 2.0))
            for mode in ("noise_mask", "vae_inpaint"):
                for comp in (True, False):
                    g = self.check(workflows.inpaint(s, "a.png", "m.png", "p", "n", 1, 0.6, "x", mode=mode, composite=comp))
                    lm = [n for n in g.values() if n["class_type"] == "LoadImageMask"][0]
                    self.assertEqual(lm["inputs"]["channel"], "red")

    def test_against_fake_server_schema_both_combo_formats(self):
        for fmt in (False, True):
            oi = fake_object_info(new_combo_format=fmt)
            schema = core_nodes.schema_from_object_info(oi)
            s = settings("illustrious", ckpt="illustriousXL_v01.safetensors", upscale_model="4x-AnimeSharp.pth")
            s["sampler"] = "euler_ancestral"
            ip = {"image": "halo_horn/ref.png", "weight": 0.7, "preset": "PLUS (high strength)"}
            cn = {"model": "openpose_sdxl.safetensors", "image": "halo_horn/pose.png"}
            g = self.check(workflows.txt2img(s, "p", "n", 5, "x", ipadapter=ip, controlnet=cn, object_info=oi), schema)
            self.assertIn("IPAdapterAdvanced", [n["class_type"] for n in g.values()])
            ad = [n for n in g.values() if n["class_type"] == "IPAdapterAdvanced"][0]["inputs"]
            self.assertEqual(ad["weight_type"], "linear")      # filled from the schema
            self.assertEqual(ad["weight"], 0.7)
            self.check(workflows.inpaint(s, "a.png", "m.png", "p", "n", 1, 0.6, "x"), schema)
            rec = comfy.rembg_recipe(oi)
            self.assertEqual(rec["class"], "BRIA_RMBG_Zho")
            self.assertEqual(rec["providers"], {"rmbgmodel": ["BRIA_RMBG_ModelLoader_Zho", 0]})
            self.check(workflows.remove_background(rec, "a.png", "x", oi), schema)
            # ComfyUI's core BiRefNet node wins over the custom ones when the server has it
            names = ["birefnet.safetensors"]
            oi2 = dict(oi)
            oi2["LoadBackgroundRemovalModel"] = {"input": {"required": {"bg_removal_name": (
                ["COMBO", {"options": names}] if fmt else [names])}}, "output": ["BACKGROUND_REMOVAL"]}
            oi2["RemoveBackground"] = {"input": {"required": {"bg_removal_model": ["BACKGROUND_REMOVAL"],
                                                               "image": ["IMAGE"]}}, "output": ["MASK"]}
            rec2 = comfy.rembg_recipe(oi2)
            self.assertEqual(rec2["class"], "RemoveBackground")
            self.assertEqual(rec2["providers"], {"bg_removal_model": ["LoadBackgroundRemovalModel", 0]})
            self.assertEqual(rec2["mask_output"], 0)
            g = self.check(workflows.remove_background(rec2, "a.png", "x", oi2),
                           core_nodes.schema_from_object_info(oi2))
            loader = [n for n in g.values() if n["class_type"] == "LoadBackgroundRemovalModel"][0]
            self.assertEqual(loader["inputs"]["bg_removal_name"], "birefnet.safetensors")
            # a sampler the server doesn't have is caught
            s2 = dict(s, sampler="dpmpp_3m_sde")
            errs = core_nodes.validate_graph(workflows.txt2img(s2, "p", "n", 5, "x"), schema)
            self.assertTrue(any("sampler_name" in e for e in errs))

    def test_tiled_upscale_against_server_schema(self):
        combo = lambda xs, fmt: ["COMBO", {"options": xs}] if fmt else [xs]
        for fmt in (False, True):
            oi = fake_object_info(new_combo_format=fmt)
            req = {"image": ["IMAGE"], "model": ["MODEL"], "positive": ["CONDITIONING"],
                   "negative": ["CONDITIONING"], "vae": ["VAE"], "upscale_model": ["UPSCALE_MODEL"],
                   "upscale_by": ["FLOAT", {"default": 2}], "seed": ["INT", {"default": 0}],
                   "steps": ["INT", {"default": 20}], "cfg": ["FLOAT", {"default": 8.0}],
                   "sampler_name": combo(["euler", "euler_ancestral"], fmt),
                   "scheduler": combo(["simple", "karras", "normal"], fmt),
                   "denoise": ["FLOAT", {"default": 0.2}], "mode_type": combo(["Linear", "Chess", "None"], fmt),
                   "tile_width": ["INT", {"default": 512}], "tile_height": ["INT", {"default": 512}],
                   "mask_blur": ["INT", {"default": 8}], "tile_padding": ["INT", {"default": 32}],
                   "seam_fix_mode": combo(["None", "Band Pass", "Half Tile"], fmt),
                   "seam_fix_denoise": ["FLOAT", {"default": 1.0}], "seam_fix_width": ["INT", {"default": 64}],
                   "seam_fix_mask_blur": ["INT", {"default": 8}], "seam_fix_padding": ["INT", {"default": 16}],
                   "force_uniform_tiles": ["BOOLEAN", {"default": True}],
                   "tiled_decode": ["BOOLEAN", {"default": False}], "batch_size": ["INT", {"default": 1}]}
            oi["UltimateSDUpscale"] = {"input": {"required": req}, "output": ["IMAGE"]}
            schema = core_nodes.schema_from_object_info(oi)
            s = settings("noobai_vpred", ckpt="illustriousXL_v01.safetensors", upscale_model="4x-AnimeSharp.pth")
            g = self.check(workflows.tiled_upscale(s, "a.png", "p", "n", 9, "x", oi), schema)
            us = [n for n in g.values() if n["class_type"] == "UltimateSDUpscale"][0]["inputs"]
            self.assertEqual((us["denoise"], us["tile_width"], us["tile_height"], us["mode_type"]),
                             (0.35, 1024, 1024, "Chess"))
            self.assertEqual((us["cfg"], us["sampler_name"], us["steps"]), (s["cfg"], s["sampler"], s["steps"]))
            # the tiles are re-drawn with the family's own model stack (v-pred sampling + RescaleCFG)
            self.assertEqual(g[us["model"][0]]["class_type"], "RescaleCFG")
            us2 = [n for n in workflows.tiled_upscale(s, "a.png", "p", "n", 9, "x", oi, denoise=0.25, tile=768).values()
                   if n["class_type"] == "UltimateSDUpscale"][0]["inputs"]
            self.assertEqual((us2["denoise"], us2["tile_width"]), (0.25, 768))
            with self.assertRaises(workflows.WorkflowError):
                workflows.tiled_upscale(dict(s, upscale_model=None), "a.png", "p", "n", 9, "x", oi)
            with self.assertRaises(workflows.WorkflowError):      # node not installed
                workflows.tiled_upscale(s, "a.png", "p", "n", 9, "x", fake_object_info(new_combo_format=fmt))

    def test_validator_catches_errors(self):
        good = workflows.txt2img(settings(), "p", "n", 1, "x")
        self.assertEqual(core_nodes.validate_graph(good), [])

        def broken(fn):
            g = json.loads(json.dumps(good))
            fn(g)
            return core_nodes.validate_graph(g)
        ks = next(k for k, n in good.items() if n["class_type"] == "KSampler")
        dec = next(k for k, n in good.items() if n["class_type"] == "VAEDecode")
        save = next(k for k, n in good.items() if n["class_type"] == "SaveImage")
        self.assertTrue(broken(lambda g: g[ks]["inputs"].pop("cfg")))
        self.assertTrue(broken(lambda g: g[ks]["inputs"].__setitem__("model", ["1", 7])))
        self.assertTrue(broken(lambda g: g[ks]["inputs"].__setitem__("model", ["1", 1])))       # CLIP into MODEL
        self.assertTrue(broken(lambda g: g[ks]["inputs"].__setitem__("model", ["999", 0])))
        self.assertTrue(broken(lambda g: g[ks]["inputs"].__setitem__("model", [1, 0])))         # int id
        self.assertTrue(broken(lambda g: g[ks]["inputs"].__setitem__("steps", "28")))
        self.assertTrue(broken(lambda g: g[ks]["inputs"].__setitem__("sampler_name", "nope")))
        self.assertTrue(broken(lambda g: g[ks]["inputs"].__setitem__("bogus", 1)))
        self.assertTrue(broken(lambda g: g[dec].__setitem__("class_type", "VAEDecodeTiledX")))
        self.assertTrue(broken(lambda g: g.pop(save)))
        self.assertTrue(broken(lambda g: g[ks]["inputs"].__setitem__("latent_image", [ks, 0])))  # cycle

    def test_fill_from_schema_requires_links(self):
        oi = fake_object_info()
        with self.assertRaises(workflows.WorkflowError):
            workflows.fill_from_schema("IPAdapterAdvanced", oi, links={"model": ["1", 0]})
        with self.assertRaises(workflows.WorkflowError):
            workflows.fill_from_schema("NotANode", oi)


class TestSettings(unittest.TestCase):
    def test_hero_size_style_loras_and_zsnr(self):
        self.assertEqual((settings(hero="seraphiel")["width"], settings(hero="seraphiel")["height"]), (832, 1216))
        self.assertEqual((settings(hero="kessa")["width"], settings(hero="kessa")["height"]), (768, 1344))
        self.assertEqual(settings(hero="seraphiel", size="704x1408")["width"], 704)
        bible = json.loads(json.dumps(BIBLE))
        bible["style"]["loras"] = [{"name": "house_style.safetensors", "strength": 0.5}]
        bible["style"]["extra_tags"] = "painterly"
        s, _, _ = P.resolve_settings(bible, args(lora=["x.safetensors:0.3"]), comfy.Comfy(dry_run=True, verbose=False),
                                     "kessa")
        self.assertEqual([lo["name"] for lo in s["loras"]], ["house_style.safetensors", "x.safetensors"])
        self.assertIn("painterly", prompts.full_body(bible, "kessa", "illustrious")["positive"])
        self.assertTrue(settings("noobai_vpred")["model_sampling"]["zsnr"])
        self.assertFalse(settings("noobai_vpred", zsnr=False)["model_sampling"]["zsnr"])
        self.assertTrue(BIBLE["families"]["noobai_vpred"]["settings"]["model_sampling"]["zsnr"], "bible not mutated")

    def test_inherit_model_and_timeout(self):
        a = args()
        out = []
        P.inherit_model(a, {"settings": {"checkpoint": "master.safetensors", "family": "pony"}, "dry_run": True},
                        "final", out.append)
        self.assertEqual((a.ckpt, a.family), ("master.safetensors", "pony"))
        a = args(ckpt="other.safetensors")
        P.inherit_model(a, {"settings": {"checkpoint": "master.safetensors", "family": "pony"}, "dry_run": True},
                        "final", out.append)
        self.assertEqual(a.ckpt, "other.safetensors")
        self.assertTrue(any("WARNING" in m for m in out))

        class Stub:
            dry_run = True
            seen = {}

            def upload_image(self, path, name=None, subfolder=None):
                return name

            def run(self, graph, label, dest, timeout=None, names=None):
                Stub.seen["timeout"] = timeout
                return []
        img = Image.new("RGB", (256, 256), (128, 128, 128))
        P.crop_inpaint(Stub(), settings(), img, (0, 0, 128, 128), Image.new("L", (256, 256), 255), "p", "n", 1, 0.5,
                       "unit/t", os.path.join(TMP, "w"), timeout=1234)
        self.assertEqual(Stub.seen["timeout"], 1234)


# ------------------------------------------------------------------ discovery + client
class TestDiscovery(unittest.TestCase):
    def test_parse_object_info(self):
        for fmt in (False, True):
            d = comfy.parse_object_info(fake_object_info(fmt), BIBLE["families"])
            self.assertEqual(len(d["checkpoints"]), 3)
            self.assertEqual(d["recommended"]["checkpoint"], "illustriousXL_v01.safetensors")
            self.assertEqual(d["recommended"]["family"], "illustrious")
            self.assertEqual(d["recommended"]["upscale_model"], "4x-AnimeSharp.pth")
            self.assertEqual(d["recommended"]["upscale_model_scale"], 4)
            self.assertTrue(d["recommended"]["ipadapter"])
            self.assertIn("BRIA_RMBG_Zho", d["custom"]["background_removal"])
            self.assertIn("FaceDetailer", d["custom"]["face_detailer"])
            self.assertEqual(d["missing_core"], [])

    def test_family_detection(self):
        f = BIBLE["families"]
        cases = {"noobaiXLNAIXL_vPred10Version.safetensors": "noobai_vpred",
                 "noobaiXLNAIXL_epsilonPred11Version.safetensors": "illustrious",
                 "illustriousXL_v01.safetensors": "illustrious", "waiNSFWIllustrious_v140.safetensors": "illustrious",
                 "ponyDiffusionV6XL.safetensors": "pony", "autismmixSDXL_autismmixPony.safetensors": "pony",
                 "animagine-xl-4.0.safetensors": "animagine"}
        for name, fam in cases.items():
            self.assertEqual(comfy.detect_family(name, f)[0], fam, name)
        self.assertEqual(comfy.detect_family("mystery_v3.safetensors", f), ("illustrious", True))

    def test_checkpoint_metadata_and_unknown_models(self):
        self.assertEqual(comfy.checkpoint_arch({"modelspec.architecture": "stable-diffusion-xl-v1-base"}), "sdxl")
        self.assertEqual(comfy.checkpoint_arch({"ss_base_model_version": "sd_v1"}), "sd1")
        self.assertIsNone(comfy.checkpoint_arch({}))
        names = ["anything-v5.safetensors", "counterfeitV30.safetensors", "mysteryMix_v2.safetensors"]
        self.assertEqual(comfy.rank_checkpoints(names)[0][0], 0)
        r = comfy.rank_checkpoints(names, {"mysteryMix_v2.safetensors": "sdxl", "anything-v5.safetensors": "sd1"})
        self.assertEqual(r[0], (5, "mysteryMix_v2.safetensors"))
        self.assertLess(dict((n, sc) for sc, n in r)["anything-v5.safetensors"], 0)
        # a low score stops the pipeline unless the model is named explicitly
        oi = fake_object_info()
        oi["CheckpointLoaderSimple"]["input"]["required"]["ckpt_name"] = [names]
        disc = comfy.parse_object_info(oi, BIBLE["families"])
        self.assertLess(disc["recommended"]["checkpoint_score"], P.MIN_CKPT_SCORE)
        client = comfy.Comfy(dry_run=True, verbose=False)
        orig = comfy.load_cached_discovery
        comfy.load_cached_discovery = lambda: (disc, oi)
        try:
            with self.assertRaisesRegex(P.PipelineError, "--ckpt"):
                P.resolve_settings(BIBLE, args(), client, "kessa")
            s, _, _ = P.resolve_settings(BIBLE, args(ckpt="counterfeitV30.safetensors", family="illustrious"),
                                         comfy.Comfy(dry_run=True, verbose=False), "kessa")
            self.assertEqual(s["checkpoint"], "counterfeitV30.safetensors")
        finally:
            comfy.load_cached_discovery = orig

    def test_pin(self):
        out = io.StringIO()
        with redirect_stdout(out):
            self.assertEqual(comfy.main(["pin", "myModel_v3.safetensors", "--family", "pony"]), 0)
        try:
            s = settings(family=None, hero="kessa")         # an explicit --family would override the pin
            self.assertEqual((s["checkpoint"], s["family"]), ("myModel_v3.safetensors", "pony"))
            self.assertEqual(settings(family=None, hero="kessa", ckpt="other_illustrious.safetensors")["family"],
                             "illustrious")
        finally:
            with redirect_stdout(out):
                comfy.main(["pin", "none"])
        self.assertIsNone(comfy.load_pin())

    def test_checkpoint_ranking_skips_refiners_and_sd15(self):
        r = comfy.rank_checkpoints(["sd_xl_refiner_1.0.safetensors", "v1-5-pruned.safetensors",
                                    "juggernautXL.safetensors", "hassakuXLIllustrious_v2.safetensors"])
        self.assertEqual(r[0][1], "hassakuXLIllustrious_v2.safetensors")
        self.assertEqual(comfy.upscaler_scale("RealESRGAN_x2plus.pth"), 2)
        self.assertEqual(comfy.upscaler_scale("4x-UltraSharp.pth"), 4)


class FakeServerClient(comfy.Comfy):
    """Comfy with request() answered from a script, to test the polling and error paths."""

    def __init__(self, script):
        super().__init__(url="https://example.invalid", auth="user:pw", verbose=False)
        self.script = script
        self.calls = []

    def request(self, method, path, body=None, headers=None, raw=False, retries=3, timeout=None):
        self.calls.append((method, path))
        for prefix, responses in self.script.items():
            if path.startswith(prefix):
                r = responses.pop(0) if len(responses) > 1 else responses[0]
                if isinstance(r, Exception):
                    raise r
                return r
        raise comfy.ComfyError("unexpected %s %s" % (method, path))


class TestClient(unittest.TestCase):
    def test_dry_run_queue_writes_exact_body(self):
        c = comfy.Comfy(dry_run=True, verbose=False)
        pr = prompts.full_body(BIBLE, "kessa", "illustrious")
        g = workflows.txt2img(settings(), pr["positive"], pr["negative"], 7, "x")
        pid = c.queue(g, "unit/txt2img_s7")
        self.assertTrue(pid.startswith("dryrun:"))
        body = json.load(open(os.path.join(comfy.dryrun_dir(), "unit", "txt2img_s7.json")))
        self.assertEqual(body["prompt"], g)
        self.assertTrue(body["client_id"])
        self.assertEqual(c.wait(pid)["outputs"], {})
        with self.assertRaises(comfy.ComfyError):
            c.request("GET", "/object_info")      # dry run never touches the network

    def test_invalid_graph_is_refused_before_sending(self):
        c = comfy.Comfy(dry_run=True, verbose=False)
        pr = prompts.full_body(BIBLE, "kessa", "illustrious")
        g = workflows.txt2img(settings(), pr["positive"], pr["negative"], 7, "x")
        next(n for n in g.values() if n["class_type"] == "KSampler")["inputs"].pop("seed")
        with self.assertRaises(comfy.ComfyError):
            c.queue(g, "unit/bad")

    def test_queue_enforces_content_rules_and_refuses_placeholders(self):
        pr = prompts.full_body(BIBLE, "kessa", "illustrious")
        c = comfy.Comfy(dry_run=True, verbose=False)
        for bad_pos, bad_neg in ((pr["positive"] + ", teenage", pr["negative"]),
                                 (pr["positive"], pr["negative"].replace("loli, ", "")),
                                 ("1girl, solo, standing", pr["negative"])):
            g = workflows.txt2img(settings(), bad_pos, bad_neg, 7, "x")
            with self.assertRaisesRegex(comfy.ComfyError, "content rules"):
                c.queue(g, "unit/rules")
        self.assertFalse(os.path.exists(os.path.join(comfy.dryrun_dir(), "unit", "rules.json")))
        # the queue CLI re-checks an edited saved graph
        g = workflows.txt2img(settings(), pr["positive"].replace("1girl", "1girl, nude"), pr["negative"], 7, "x")
        path = os.path.join(TMP, "edited.api.json")
        json.dump({"prompt": g}, open(path, "w"))
        err = io.StringIO()
        with redirect_stderr(err), redirect_stdout(io.StringIO()):
            self.assertEqual(comfy.main(["queue", path, "--dry-run"]), 1)
        self.assertIn("nude", err.getvalue())
        # a live client refuses dry-run graphs (placeholder checkpoint) before any request
        live = FakeServerClient({})
        g = workflows.txt2img(settings(), pr["positive"], pr["negative"], 7, "x")
        self.assertEqual(g["1"]["inputs"]["ckpt_name"], P.DRYRUN_CKPT)
        with self.assertRaisesRegex(comfy.ComfyError, "dry-run graph"):
            live.queue(g, "unit/placeholder")
        self.assertEqual(live.calls, [])

    def test_empty_prompt_response_is_an_error(self):
        g = workflows.upscale(settings(), "halo_horn/a.png", "x", 2.0)
        for body in (None, {"error": "nope"}):
            c = FakeServerClient({"/prompt": [body]})
            with self.assertRaises(comfy.ComfyError):
                c.queue(g, "unit/empty")

    def test_url_warnings(self):
        self.assertEqual(comfy.url_warnings("https://x.ngrok-free.app"), [])
        self.assertTrue(comfy.url_warnings("http://x.ngrok-free.app"))
        self.assertTrue(comfy.url_warnings("https://x.ngrok-free.app:8188"))
        self.assertEqual(comfy.url_warnings("http://127.0.0.1:8188"), [])

    def test_env_and_auth(self):
        old = os.environ.pop("COMFYUI_URL", None)
        try:
            with self.assertRaises(comfy.ComfyError):
                comfy.Comfy()
        finally:
            if old is not None:
                os.environ["COMFYUI_URL"] = old
        self.assertTrue(comfy._auth_header("user:pw").startswith("Basic "))
        self.assertEqual(comfy._auth_header("Bearer abc"), "Bearer abc")
        self.assertEqual(comfy._auth_header("tok"), "Bearer tok")
        c = comfy.Comfy(url="https://x.example", auth="Basic Zm9vOmJhcg==", verbose=False)
        self.assertEqual(c._headers()["Authorization"], "Basic Zm9vOmJhcg==")

    def test_multipart(self):
        body, ct = comfy.encode_multipart({"type": "input"}, {"image": ("a.png", b"\x89PNGdata", "image/png")})
        self.assertIn("multipart/form-data; boundary=", ct)
        self.assertIn(b'name="image"; filename="a.png"', body)
        self.assertIn(b"\x89PNGdata", body)

    def test_wait_success_and_error(self):
        ok_entry = {"status": {"status_str": "success", "completed": True},
                    "outputs": {"9": {"images": [{"filename": "a.png", "subfolder": "halo_horn", "type": "output"}]}}}
        c = FakeServerClient({"/history/": [{}, {}, {"p1": ok_entry}],
                              "/queue": [{"queue_running": [[0, "p1", {}, {}, []]], "queue_pending": []}]})
        e = c.wait("p1", poll=0)
        self.assertEqual(comfy.history_images(e)[0]["filename"], "a.png")
        err_entry = {"status": {"status_str": "error", "completed": False, "messages": [
            ["execution_error", {"node_id": "5", "node_type": "KSampler", "exception_type": "RuntimeError",
                                 "exception_message": "CUDA out of memory"}]]}, "outputs": {}}
        c = FakeServerClient({"/history/": [{"p2": err_entry}], "/queue": [{}]})
        with self.assertRaisesRegex(comfy.ComfyError, "out of memory"):
            c.wait("p2", poll=0)

    def test_run_downloads_and_rejects_empty_jobs(self):
        ok_entry = {"status": {"status_str": "success", "completed": True},
                    "outputs": {"9": {"images": [{"filename": "a.png", "subfolder": "halo_horn", "type": "output"}]}}}
        c = FakeServerClient({"/prompt": [{"prompt_id": "p3", "number": 1, "node_errors": {}}],
                              "/history/": [{"p3": ok_entry}], "/queue": [{}], "/view": [b"PNGBYTES"]})
        g = workflows.upscale(settings(), "halo_horn/a.png", "x", 2.0)
        paths = c.run(g, "unit/up", os.path.join(TMP, "dl"), names=["out.png"])
        self.assertEqual(open(paths[0], "rb").read(), b"PNGBYTES")
        self.assertIn(("POST", "/prompt"), c.calls)
        c = FakeServerClient({"/prompt": [{"prompt_id": "p4", "node_errors": {}}],
                              "/history/": [{"p4": {"status": {"status_str": "success", "completed": True},
                                                    "outputs": {}}}], "/queue": [{}]})
        with self.assertRaises(comfy.ComfyError):
            c.run(g, "unit/up2", os.path.join(TMP, "dl"))

    def test_prompt_error_formatting(self):
        txt = comfy.format_prompt_error({"error": {"type": "prompt_outputs_failed_validation", "message": "bad"},
                                         "node_errors": {"1": {"class_type": "CheckpointLoaderSimple", "errors": [
                                             {"message": "Value not in list", "details": "ckpt_name: x"}]}}})
        self.assertIn("node 1 (CheckpointLoaderSimple)", txt)
        self.assertIn("Value not in list", txt)


# ------------------------------------------------------------------ prompt bible
YOUTH_AND_EXPLICIT = ["teen", "teenage", "teenager", "young", "young girl", "young boy", "little girl", "little boy",
                      "schoolgirl", "schoolboy", "student", "sailor collar", "gym uniform", "buruma",
                      "elementary school", "middle school", "high school", "school uniform", "loli", "child",
                      "areola slip", "nipple outline", "no panties", "pussy peek", "anus", "nude", "see-through",
                      "rating_questionable", "flat chest", "shortstack", "young-looking"]


def all_prompts(fam="illustrious"):
    for hid, h in BIBLE["heroes"].items():
        yield hid, "full_body", prompts.full_body(BIBLE, hid, fam)
        yield hid, "face", prompts.face(BIBLE, hid, fam)
        for v in sorted(set(h["variant_set"]) | {"eyes_closed", "mouth_open", "hurt"}):
            yield hid, v, prompts.face(BIBLE, hid, fam, v)
        yield hid, "custom", prompts.custom(BIBLE, hid, fam, "detailed hands")


class TestBible(unittest.TestCase):
    def test_all_15_heroes_match_the_game_data(self):
        game = json.load(open(os.path.join(ROOT, "data", "heroes.json")))["heroes"]
        self.assertEqual(len(BIBLE["heroes"]), 15)
        self.assertEqual(list(BIBLE["heroes"]), [h["id"] for h in game])
        for h in game:
            b = BIBLE["heroes"][h["id"]]
            for k in ("name", "faction", "role", "rarity"):
                self.assertEqual(b[k], h[k], (h["id"], k))

    def test_hero_fields(self):
        seeds = set()
        for hid, h in BIBLE["heroes"].items():
            for k in ("subject", "hair", "eyes", "expression", "outfit", "footwear", "weapon", "natural", "face",
                      "gender", "apparent_age"):
                self.assertTrue(h.get(k), (hid, k))
            self.assertIn(h["gender"], BIBLE["gender"])
            self.assertIn(h["background"], BIBLE["backgrounds"])
            self.assertNotIn(h["seed_base"], seeds)
            seeds.add(h["seed_base"])
            for v in ("eyes_closed", "mouth_open"):
                self.assertTrue(h["variants"].get(v), (hid, v))
            for v in h["variant_set"]:
                prompts.variant_spec(BIBLE, hid, v)
            self.assertIn("adult", h["natural"].lower(), hid)
            tw = prompts.tag_weights(h["subject"])
            self.assertIn("adult", tw, hid)
            cue = BIBLE["content_rules"]["adult_cue_by_gender"][h["gender"]]
            self.assertGreaterEqual(tw.get(cue, 0), 0.8 if hid in ("liora", "uriela", "imra") else 0.6, hid)
            if h.get("size"):
                self.assertEqual([v % 8 for v in h["size"]], [0, 0], hid)

    def test_young_end_heroes_get_adult_styling(self):
        for hid in ("liora", "uriela", "imra"):
            h = BIBLE["heroes"][hid]
            for t in ("lipstick", "eyeliner", "makeup", "long eyelashes"):
                self.assertIn(t, prompts.tag_weights(h["adult_face"]), (hid, t))
            self.assertNotIn("petite", prompts.tag_weights(prompts.full_body(BIBLE, hid, "illustrious")["positive"]))
        for hid in ("liora", "uriela"):
            neg = prompts.tag_weights(prompts.full_body(BIBLE, hid, "illustrious")["negative"])
            self.assertIn("petite", neg)
            self.assertGreater(neg["loli"], 1.0, "the weighted hero extra must win the de-duplication")
            self.assertGreater(neg["teenage"], 1.0)
        liora = prompts.tag_weights(prompts.full_body(BIBLE, "liora", "illustrious")["positive"])
        for t in ("light blush", "head tilt", "frilled skirt"):
            self.assertNotIn(t, liora)

    def test_global_negatives_carry_the_content_rules(self):
        neg = {prompts.norm_tag(t) for k in ("explicit", "childlike") for t in prompts.split_tags(BIBLE["negative"][k])}
        for group, terms in BIBLE["content_rules"]["required_negative"].items():
            for t in terms:
                self.assertIn(t, neg, (group, t))
        for g, groups in BIBLE["content_rules"]["required_negative_by_gender"].items():
            gneg = prompts.tag_weights(BIBLE["gender"][g]["negative"])
            for terms in groups.values():
                for t in terms:
                    self.assertIn(t, gneg, (g, t))
        for t in ("teenage", "young", "areola slip", "pussy peek", "no panties", "anus"):
            self.assertIn(t, prompts.tag_weights(BIBLE["negative"]["explicit"] + "," + BIBLE["negative"]["childlike"]
                                                 + "," + BIBLE["gender"]["female"]["negative"]))
        for t in ("feet out of frame", "head out of frame", "wings out of frame"):
            self.assertIn(t, BIBLE["negative"]["framing"])
        for t in ("light particles", "sparkle", "embers", "aura", "light rays", "smoke", "speed lines"):
            self.assertIn(t, BIBLE["negative"]["effects"])

    def test_every_composed_prompt_passes_the_rules_and_fits(self):
        for fam in BIBLE["families"]:
            for hid, kind, pr in all_prompts(fam):
                self.assertEqual(prompts.check(BIBLE, hid, pr["positive"], pr["negative"]), [], (fam, hid, kind))
                self.assertEqual(prompts.syntax_problems(pr["positive"]) + prompts.syntax_problems(pr["negative"]), [])
                self.assertLessEqual(pr["stats"]["positive"]["chunks"], 2, (fam, hid, kind, pr["stats"]))
                self.assertLessEqual(pr["stats"]["negative"]["chunks"], 3, (fam, hid, kind, pr["stats"]))
                self.assertNotIn(". ", pr["positive"], "no prose unless the family opts in")
                if kind == "full_body":
                    fb = pr["positive"]
                    q = BIBLE["families"][fam]["quality"].split(",")[0].strip()
                    if BIBLE["families"][fam].get("quality_position", "start") == "start":
                        self.assertTrue(fb.startswith(q), (fam, fb[:40]))
                    self.assertIn("full body", fb)
                    self.assertTrue(prompts.tag_weights(BIBLE["heroes"][hid]["footwear"]).keys()
                                    <= prompts.tag_weights(fb).keys(), hid)

    def test_effects_and_backgrounds(self):
        fx = set(prompts.tag_weights(BIBLE["negative"]["effects"])) | {"fire", "lava", "magic", "glowing", "sunburst"}
        for hid, h in BIBLE["heroes"].items():
            pos = prompts.tag_weights(prompts.full_body(BIBLE, hid, "illustrious")["positive"])
            self.assertFalse(fx & set(pos), (hid, fx & set(pos)))
            key = prompts.background(BIBLE, hid)[0]
            self.assertEqual("rim lighting" in pos, key == "grey", hid)
            self.assertIn("official art", pos)
        for hid in ("orrin", "ashra"):
            self.assertEqual(BIBLE["heroes"][hid]["background"], "green", hid)
        # NoobAI pilot (2026-10-17): on white or green the dark designs render as flat ink sketches
        for hid in ("kessa", "mordessa", "noctaire", "cassiel"):
            self.assertEqual(BIBLE["heroes"][hid]["background"], "grey", hid)
        self.assertNotEqual(BIBLE["heroes"]["sable"]["background"], "green")
        self.assertIn("black and purple theme", prompts.full_body(BIBLE, "vesper", "illustrious")["positive"])
        self.assertNotIn("red and black theme", prompts.full_body(BIBLE, "vesper", "illustrious")["positive"])

    def test_families(self):
        for fam in ("illustrious", "noobai_vpred"):
            qn = prompts.tag_weights(BIBLE["families"][fam]["quality_negative"])
            self.assertNotIn("oldest", qn)
            self.assertIn("old", qn)
            for t in ("furry", "anthro", "mammal", "feral"):
                self.assertIn(t, qn)
        for fam, f in BIBLE["families"].items():
            self.assertFalse(f.get("use_natural"), fam)

    def test_variants_do_not_contradict_themselves(self):
        opposite = {"eyes_open": ["closed eyes", "eyes closed"], "eyes_closed": ["open eyes", "eyes open"],
                    "mouth_open": ["closed mouth", "mouth closed"], "smile": ["frown", "sad"], "hurt": ["smile"]}
        for fam in ("illustrious", "pony"):
            for hid, kind, pr in all_prompts(fam):
                if kind not in opposite:
                    continue
                tags = prompts.tag_weights(pr["positive"])
                for t in opposite[kind]:
                    self.assertNotIn(t, tags, (hid, kind, t))
                for t in ("plunging neckline", "side slit", "full body"):
                    self.assertNotIn(t, tags, "face crops carry no costume/pose: %s %s" % (hid, t))
                if "closed eyes" in tags:
                    self.assertFalse([t for t in tags if t.endswith(" eyes") and t.split()[0] in
                                      ("blue", "red", "purple", "yellow", "green", "aqua", "grey", "orange")],
                                     (hid, kind))
        # the composer refuses a contradiction
        bad = json.loads(json.dumps(BIBLE))
        bad["heroes"]["seraphiel"]["variants"]["eyes_open"] = "yellow eyes, open eyes, closed eyes"
        with self.assertRaises(prompts.PromptError):
            prompts.face(bad, "seraphiel", "illustrious", "eyes_open")

    def test_doc_has_the_runbook(self):
        doc = open(os.path.join(ROOT, "docs", "dev", "art-generation.md")).read()
        for needle in ("Tonight's runbook", "--dry-run", "adult", "COMFYUI_URL", "roster.py", "install.py"):
            self.assertIn(needle, doc)
        heads = [ln for ln in doc.splitlines() if ln.startswith("## ")]
        self.assertTrue(any("Tonight's runbook" in h for h in heads))


class TestContentRules(unittest.TestCase):
    def test_youth_and_explicit_terms_are_refused(self):
        for hid in ("kessa", "lucen"):
            for term in YOUTH_AND_EXPLICIT:
                with self.assertRaises(prompts.ContentRuleError, msg=(hid, term)):
                    prompts.full_body(BIBLE, hid, "illustrious", extra_tags=term)
        with self.assertRaises(prompts.ContentRuleError):
            prompts.custom(BIBLE, "kessa", "pony", "topless")
        with self.assertRaises(prompts.ContentRuleError):        # the roster is all women now
            prompts.full_body(BIBLE, "brakka", "illustrious", extra_tags="topless")
        self.assertEqual(prompts.check_text(BIBLE, "1boy, adult, mature male, topless male",
                                            prompts.full_body(BIBLE, "kessa", "illustrious")["negative"]
                                            + ", bulge", gender="male"), [])      # men's rules still work

    def test_rule_checker_rejects_violations(self):
        pr = prompts.full_body(BIBLE, "imra", "illustrious")
        bad_pos = pr["positive"].replace("1girl", "1girl, loli")
        self.assertTrue(prompts.check(BIBLE, "imra", bad_pos, pr["negative"]))
        bad_neg = pr["negative"].replace("nipples, ", "")
        self.assertTrue(prompts.check(BIBLE, "imra", pr["positive"], bad_neg))
        self.assertTrue(prompts.check(BIBLE, "imra", pr["positive"], pr["negative"].replace("pantyshot, ", "")))
        no_adult = pr["positive"].replace("adult, ", "")
        self.assertTrue(prompts.check(BIBLE, "imra", no_adult, pr["negative"]))
        no_mature = pr["positive"].replace("(mature female:0.8), ", "")
        self.assertTrue(prompts.check(BIBLE, "imra", no_mature, pr["negative"]))
        weak = pr["positive"].replace("(mature female:0.8)", "(mature female:0.1)")
        self.assertTrue(any("weighted" in p for p in prompts.check(BIBLE, "imra", weak, pr["negative"])))
        weak_neg = pr["negative"].replace("nude,", "(nude:0.2),")
        self.assertTrue(any("nude" in p for p in prompts.check(BIBLE, "imra", pr["positive"], weak_neg)))
        with self.assertRaises(prompts.ContentRuleError):
            prompts.full_body(BIBLE, "imra", "illustrious", extra_tags="completely nude")
        # whole-word matching: 'sex' must not fire on 'sexy'; escapes and weights are seen through
        self.assertFalse(prompts._has_term("sexy pose", "sex"))
        self.assertTrue(prompts._has_term("1girl, (loli:1.2)", "loli"))
        self.assertTrue(prompts._has_term("1girl, \\(teen\\)", "teen"))
        self.assertFalse(prompts._has_term("canteen, fourteenth", "teen"))

    def test_comfy_weight_parsing(self):
        segs = prompts.weighted_segments("a, (b:0.8), (c), ((d)), star \\(symbol\\), (e, f:1.3)")
        w = {t.strip(", "): round(x, 3) for t, x in segs if t.strip(", ")}
        self.assertEqual(w["a"], 1.0)
        self.assertEqual(w["b"], 0.8)
        self.assertEqual(w["c"], 1.1)
        self.assertEqual(w["d"], 1.21)
        self.assertEqual(w["e, f"], 1.3)
        self.assertIn("star (symbol)", " ".join(t for t, _ in segs))
        self.assertEqual(prompts.syntax_problems("star \\(symbol\\), (x:1.2)"), [])
        self.assertTrue(prompts.syntax_problems("star (symbol)"))
        self.assertTrue(prompts.syntax_problems("(x:1.2"))
        self.assertIn("star \\(symbol\\)", prompts.full_body(BIBLE, "ashra", "illustrious")["positive"])
        self.assertNotIn("(", BIBLE["heroes"]["seraphiel"]["natural"])

    def test_token_estimate_and_chunks(self):
        self.assertEqual(prompts.clip_stats("one, two, three")["tokens"], 5)
        self.assertEqual(prompts.clip_stats("score_8_up")["tokens"], 5)
        long_text = ", ".join(["red hair"] * 30)                     # 30 x 2 words + 29 commas
        st = prompts.clip_stats(long_text)
        self.assertEqual((st["tokens"], st["chunks"]), (89, 2))
        self.assertEqual(prompts.clip_stats(", ".join(["red hair"] * 60))["chunks"], 3)
        self.assertEqual(prompts.clip_stats("(mature female:0.8)")["tokens"], 2, "weights are not tokens")

    def test_graph_check(self):
        s = settings()
        pr = prompts.full_body(BIBLE, "kessa", "illustrious")
        good = workflows.txt2img(s, pr["positive"], pr["negative"], 1, "x")
        self.assertEqual(prompts.check_graph(BIBLE, good), [])
        pos, neg = prompts.graph_prompts(good)
        self.assertEqual((pos, neg), ([pr["positive"]], [pr["negative"]]))
        bad = workflows.txt2img(s, pr["positive"] + ", schoolgirl", pr["negative"], 1, "x")
        self.assertTrue(prompts.check_graph(BIBLE, bad))
        weak = workflows.txt2img(s, pr["positive"], pr["negative"].replace("loli, ", ""), 1, "x")
        self.assertTrue(prompts.check_graph(BIBLE, weak))
        # swapped titles do not fool it: roles come from the sampler's inputs
        swapped = json.loads(json.dumps(bad))
        for n in swapped.values():
            if n["class_type"] == "CLIPTextEncode":
                n["_meta"]["title"] = "Negative prompt"
        self.assertTrue(prompts.check_graph(BIBLE, swapped))
        # through ControlNet: output 0 = positive, 1 = negative
        cn = {"model": "openpose_sdxl.safetensors", "image": "halo_horn/pose.png"}
        g = workflows.txt2img(s, pr["positive"], pr["negative"], 1, "x", controlnet=cn)
        self.assertEqual(prompts.graph_prompts(g), ([pr["positive"]], [pr["negative"]]))
        self.assertEqual(prompts.check_graph(BIBLE, workflows.upscale(s, "a.png", "x")), [])

    def test_long_prompts_are_encoded_in_whole_tag_chunks(self):
        pr = prompts.full_body(BIBLE, "seraphiel", "noobai_vpred")
        for text in (pr["positive"], pr["negative"]):
            parts = prompts.split_chunks(text)
            self.assertGreater(len(parts), 1)
            self.assertEqual(", ".join(parts), text)
            for p in parts:
                self.assertLessEqual(prompts.clip_stats(p)["tokens"], prompts.CHUNK_PACK)
        self.assertEqual(prompts.split_chunks("(a, b:1.2), c"), ["(a, b:1.2), c"])
        g = workflows.txt2img(settings(), pr["positive"], pr["negative"], 1, "x")
        enc = [n for n in g.values() if n["class_type"] == "CLIPTextEncode"]
        self.assertEqual(len(enc), len(prompts.split_chunks(pr["positive"])) + len(prompts.split_chunks(pr["negative"])))
        self.assertTrue(any(n["class_type"] == "ConditioningConcat" for n in g.values()))
        # the chunks are read back as one prompt each, so a chunk without the adult cue is no violation
        self.assertEqual(prompts.graph_prompts(g), ([pr["positive"]], [pr["negative"]]))
        self.assertEqual(prompts.check_graph(BIBLE, g), [])


# ------------------------------------------------------------------ post-processing
def synthetic(size=(576, 1008), bg=(128, 128, 128), gradient=True, seed=0):
    W, H = size
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    base = np.array(bg, np.float32)
    if gradient:
        g = 14 * (yy / H) - 7 + 5 * np.cos(xx / W * 3)
        arr = base[None, None, :] + g[..., None]
    else:
        arr = np.broadcast_to(base, (H, W, 3)).copy()
    arr += np.random.default_rng(seed).normal(0, 1.2, arr.shape)
    im = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))
    big = im.resize((W * 2, H * 2), Image.NEAREST)
    d = ImageDraw.Draw(big)
    s = 2
    ol = (42, 29, 61)
    cx = W
    d.ellipse([cx - 80 * s / 2, 60 * s, cx + 80 * s / 2, 150 * s], fill=(253, 228, 214), outline=ol, width=6)  # head
    d.polygon([(cx - 70 * s / 2 * 1.6, 160 * s), (cx + 56 * s, 160 * s), (cx + 70 * s, 560 * s),
               (cx - 70 * s, 560 * s)], fill=(250, 250, 253), outline=ol, width=6)                             # dress
    for dx in (-30, 30):
        d.rectangle([cx + dx * s - 14 * s, 560 * s, cx + dx * s + 14 * s, 960 * s], fill=(253, 228, 214),
                    outline=ol, width=6)                                                                       # legs
    d.line([(cx - 60 * s, 180 * s), (cx - 140 * s, 330 * s), (cx - 66 * s, 450 * s)], fill=ol, width=30)       # arm loop
    d.line([(cx - 60 * s, 180 * s), (cx - 140 * s, 330 * s), (cx - 66 * s, 450 * s)], fill=(253, 228, 214), width=20)
    d.polygon([(cx + 60 * s, 200 * s), (cx + 250 * s, 120 * s), (cx + 220 * s, 420 * s)], fill=(143, 210, 242),
              outline=ol, width=6)                                                                             # wing
    return big.resize((W, H), Image.LANCZOS)   # anti-aliased edges


class TestPost(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.img = synthetic()
        cls.rgba, cls.info = post.remove_background(cls.img)
        cls.a = np.asarray(cls.rgba)[..., 3]

    def test_cutout_background_and_figure(self):
        a = self.a
        for y, x in ((3, 3), (3, 570), (1000, 3), (500, 20)):
            self.assertEqual(a[y, x], 0, (y, x))
        for y, x in ((100, 288), (300, 300), (700, 258), (250, 470)):
            self.assertEqual(a[y, x], 255, (y, x))
        self.assertEqual(a[330, 200], 0, "enclosed hole between arm and body must be cleared")
        self.assertEqual(a[800, 288], 0, "gap between the legs must be cleared")
        partial = ((a > 0) & (a < 255)).sum()
        self.assertGreater(partial, 200, "edges should be anti-aliased")
        self.assertGreater(self.info["hole_px"], 100)

    def test_lineart_stays_opaque_and_despilled(self):
        rgba = np.asarray(self.rgba).astype(np.int32)
        row = rgba[700]
        xs = np.nonzero(row[:, 3] == 255)[0]
        self.assertTrue(len(xs))
        edge = xs[0]
        self.assertLess(row[edge, :3].mean(), 110, "the outermost opaque pixel should be dark lineart")
        semi = (rgba[..., 3] > 30) & (rgba[..., 3] < 200)
        # despilled edge colours move away from the grey background toward the line colour
        self.assertLess(np.median(rgba[semi][:, :3].mean(1)), 115)

    def test_white_background_and_server_mask(self):
        img = synthetic(bg=(255, 255, 255), gradient=False)
        rgba, _ = post.remove_background(img)
        a = np.asarray(rgba)[..., 3]
        self.assertEqual(a[3, 3], 0)
        self.assertEqual(a[300, 300], 255, "a big white dress on white must not be taken for a hole")
        self.assertEqual(a[330, 200], 0, "the small enclosed gap is still cleared")
        mask = Image.fromarray(255 - a)    # inverted polarity on purpose
        r2, info = post.alpha_from_mask(img, mask)
        a2 = np.asarray(r2)[..., 3]
        self.assertEqual(a2[3, 3], 0)
        self.assertEqual(a2[300, 300], 255)
        self.assertEqual(info["method"], "server_mask")

    def test_server_mask_that_fills_holes(self):
        # BiRefNet keeps the background seen between arm and body as figure: clear it like the local cutout
        filled = (self.a > 0).astype(np.uint8) * 255
        filled[300:360, 170:230] = 255
        r, info = post.alpha_from_mask(self.img, Image.fromarray(filled))
        a = np.asarray(r)[..., 3]
        self.assertEqual(a[330, 200], 0, "enclosed background in a server mask must be cleared")
        self.assertEqual(a[300, 300], 255)
        self.assertGreater(info["hole_px"], 100)
        r, info = post.alpha_from_mask(self.img, Image.fromarray(filled), holes=False)
        self.assertEqual(np.asarray(r)[330, 200, 3], 255)
        self.assertEqual(info["hole_px"], 0)

    def test_place_on_canvas_and_face_box(self):
        fb, conf = post.estimate_face_box(self.rgba)
        self.assertEqual(conf, "skin")
        self.assertTrue(250 <= fb[0] + fb[2] / 2 <= 330, fb)
        self.assertTrue(40 <= fb[1] <= 120, fb)
        canvas, tr = post.place_on_canvas(self.rgba, crown_src=post.crown_from_face_box(fb))
        self.assertEqual(canvas.size, (1024, 2048))
        self.assertEqual(canvas.mode, "RGBA")
        a = np.asarray(canvas)[..., 3]
        rows = np.nonzero((a > 127).sum(1) >= 3)[0]
        self.assertLessEqual(abs(int(rows.max()) + 1 - 1990), 2)
        cols = np.nonzero(a.max(0) > 8)[0]
        self.assertGreaterEqual(cols.min(), post.MARGIN - 1)
        self.assertLessEqual(cols.max(), 1024 - post.MARGIN)
        self.assertGreaterEqual(rows.min(), post.MARGIN - 1)
        m = post.figure_metrics(canvas)
        self.assertLess(abs(m["axis_x"] - 512), 3 if not tr["notes"] else 400)
        cfb = post.map_box(fb, tr)
        self.assertLess(abs(post.crown_from_face_box(cfb) - post.CROWN_Y), 6)
        por, rect = post.portrait(canvas, cfb)
        self.assertEqual(por.size, (512, 512))
        self.assertEqual(rect[2], rect[3])

    def test_face_box_ignores_halo_and_blonde_hair(self):
        img = synthetic()
        d = ImageDraw.Draw(img)
        d.ellipse([228, 20, 348, 44], outline=(244, 201, 92), width=5)          # gold halo ring
        d.pieslice([238, 52, 338, 120], 180, 360, fill=(250, 239, 203))         # platinum-blonde hair cap
        rgba, _ = post.remove_background(img)
        fb, conf = post.estimate_face_box(rgba)
        self.assertEqual(conf, "skin")
        self.assertGreaterEqual(fb[1], 70, fb)
        red = synthetic()
        ImageDraw.Draw(red).ellipse([248, 60, 328, 150], fill=(190, 52, 46), outline=(42, 29, 61), width=3)
        rr, _ = post.remove_background(red)
        fb2, conf2 = post.estimate_face_box(rr, "red")
        self.assertEqual(conf2, "skin")
        self.assertTrue(40 <= fb2[1] <= 110, fb2)

    def test_flood_and_morphology(self):
        cand = np.ones((50, 50), bool)
        cand[:, 25] = False
        seed = np.zeros_like(cand)
        seed[0, 0] = True
        f = post.flood(seed, cand)
        self.assertTrue(f[:, :25].all())
        self.assertFalse(f[:, 26:].any())
        m = np.zeros((20, 20), bool)
        m[5:15, 5:15] = True
        self.assertEqual(post.erode(m, 2).sum(), 36)
        self.assertEqual(post.dilate(m, 1).sum(), 144)

    def test_candidate_report_and_variant_alignment(self):
        _, rep = post.candidate_report(self.img, (128, 128, 128))
        self.assertEqual(rep["flags"], [])
        _, rep = post.candidate_report(self.img.crop((0, 100, 576, 1008)), (128, 128, 128))
        self.assertIn("CROP:top", rep["flags"])
        light = Image.new("RGB", (300, 600), (255, 255, 255))
        ImageDraw.Draw(light).ellipse([60, 60, 240, 540], fill=(236, 236, 240))
        self.assertTrue(any(f.startswith("EDGE") for f in post.candidate_report(light, (255, 255, 255))[1]["flags"]))
        self.assertTrue(post.candidate_report(self.img, (0, 177, 64))[1]["flags"] == ["BG?"])
        base = self.rgba
        var = base.copy()
        var.putpixel((290, 100), (0, 0, 0, var.getpixel((290, 100))[3]))
        self.assertEqual(post.variant_alignment(base, var, [270, 80, 40, 40]), [])
        self.assertTrue(post.variant_alignment(base, var, [10, 900, 20, 20]))
        other = base.copy()
        other.putalpha(255)
        self.assertTrue(post.variant_alignment(base, other, None))

    def test_contact_sheet_and_previews(self):
        out = os.path.join(TMP, "sheet.png")
        post.contact_sheet([(self.img, "s1"), (self.rgba, "s2"), (self.img, "s3")], out, cols=2, cell_w=200,
                           title="test")
        with Image.open(out) as im:
            im.load()
        self.assertEqual(im.width, 2 * 200 + 3 * 8)
        self.assertGreater(im.height, 2 * 350)
        prev = post.cutout_preview(self.rgba, 300)
        self.assertEqual(prev.height, 300)


# ------------------------------------------------------------------ the real HTTP layer (local fake ComfyUI)
class FakeComfyHandler(http.server.BaseHTTPRequestHandler):
    requests = []
    upload_fields = {}
    prompt_body = None

    def log_message(self, *a):
        pass

    def _send(self, code, body, ctype="application/json"):
        data = body if isinstance(body, bytes) else json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        FakeComfyHandler.requests.append(("GET", self.path, dict(self.headers)))
        if self.path.startswith("/history/pid1"):
            self._send(200, {"pid1": {"status": {"status_str": "success", "completed": True}, "outputs": {
                "9": {"images": [{"filename": "o.png", "subfolder": "halo_horn", "type": "output"}]}}}})
        elif self.path.startswith("/queue"):
            self._send(200, {"queue_running": [], "queue_pending": []})
        elif self.path.startswith("/view?"):
            self._send(200, b"\x89PNG-fake-output", "image/png")
        else:
            self._send(404, {"error": "not found"})

    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        FakeComfyHandler.requests.append(("POST", self.path, dict(self.headers)))
        if self.path == "/upload/image":
            raw = b"Content-Type: " + self.headers["Content-Type"].encode() + b"\r\n\r\n" + body
            msg = email.parser.BytesParser(policy=email.policy.HTTP).parsebytes(raw)
            fields = {}
            for part in msg.iter_parts():
                fields[part.get_param("name", header="content-disposition")] = (part.get_filename(),
                                                                                part.get_payload(decode=True))
            FakeComfyHandler.upload_fields = fields
            self._send(200, {"name": fields["image"][0], "subfolder": fields["subfolder"][1].decode(), "type": "input"})
        elif self.path == "/prompt":
            FakeComfyHandler.prompt_body = json.loads(body)
            self._send(200, {"prompt_id": "pid1", "number": 1, "node_errors": {}})
        else:
            self._send(404, {"error": "not found"})


class TestHTTPLayer(unittest.TestCase):
    """urllib on the wire against a local server: auth header, multipart as a MIME parser reads it, JSON body."""

    @classmethod
    def setUpClass(cls):
        cls.old_no_proxy = os.environ.get("no_proxy")
        os.environ["no_proxy"] = "127.0.0.1,localhost" + ("," + cls.old_no_proxy if cls.old_no_proxy else "")
        cls.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), FakeComfyHandler)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        cls.url = "http://127.0.0.1:%d" % cls.server.server_address[1]

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        if cls.old_no_proxy is None:
            os.environ.pop("no_proxy", None)
        else:
            os.environ["no_proxy"] = cls.old_no_proxy

    def test_upload_queue_wait_download(self):
        c = comfy.Comfy(url=self.url, auth="halo:secret", verbose=False)
        png = os.path.join(TMP, "up.png")
        Image.new("RGB", (8, 8), (1, 2, 3)).save(png)
        ref = c.upload_image(png, name="t.png", subfolder="halo_horn")
        self.assertEqual(ref, "halo_horn/t.png")
        f = FakeComfyHandler.upload_fields
        self.assertEqual(f["image"], ("t.png", open(png, "rb").read()))
        self.assertEqual({k: f[k][1] for k in ("type", "subfolder", "overwrite")},
                         {"type": b"input", "subfolder": b"halo_horn", "overwrite": b"true"})
        method, path, headers = FakeComfyHandler.requests[-1]
        self.assertEqual(headers["Authorization"], "Basic aGFsbzpzZWNyZXQ=")
        pr = prompts.full_body(BIBLE, "kessa", "illustrious")
        g = workflows.txt2img(settings(ckpt="illustriousXL_v01.safetensors"), pr["positive"], pr["negative"], 3, "x")
        paths = c.run(g, "unit/live", os.path.join(TMP, "dl_live"), names=["o.png"])
        self.assertEqual(FakeComfyHandler.prompt_body, {"prompt": g, "client_id": c.client_id})
        posts = [r for r in FakeComfyHandler.requests if r[:2] == ("POST", "/prompt")]
        self.assertEqual(posts[-1][2]["Content-Type"], "application/json")
        self.assertTrue(all(r[2].get("Authorization") == "Basic aGFsbzpzZWNyZXQ=" for r in FakeComfyHandler.requests))
        self.assertEqual(open(paths[0], "rb").read(), b"\x89PNG-fake-output")
        self.assertIn("filename=o.png", [r[1] for r in FakeComfyHandler.requests if r[1].startswith("/view")][-1])


# ------------------------------------------------------------------ dry run end to end + re-run guards
class TestDryRunEndToEnd(unittest.TestCase):
    """run_hero -> finalize -> variants -> install in a temp art_src, and every guard against
    overwriting chosen art. Methods run in name order and share state."""
    hero = "imra"

    @classmethod
    def setUpClass(cls):
        cls.seed = BIBLE["heroes"][cls.hero]["seed_base"]
        cls.hdir = os.path.join(comfy.dryrun_dir(), cls.hero)
        cls.final = os.path.join(cls.hdir, "final", cls.hero + ".png")
        cls.vdir = os.path.join(cls.hdir, "variants")

    def run_main(self, mod, argv, rc=0):
        out, err = io.StringIO(), io.StringIO()
        with redirect_stdout(out), redirect_stderr(err):
            got = mod.main(argv)
        self.assertEqual(got, rc, err.getvalue() + out.getvalue())
        return out.getvalue() + err.getvalue()

    def variants_json(self):
        return json.load(open(os.path.join(self.vdir, "variants.json")))

    def test_1_candidates(self):
        import run_hero
        self.run_main(run_hero, [self.hero, "--count", "2", "--dry-run", "--size", "512x896"])
        cdir = os.path.join(self.hdir, "candidates")
        for i in range(2):
            stem = os.path.join(cdir, "%s_s%d" % (self.hero, self.seed + i))
            self.assertTrue(os.path.exists(stem + ".png"))
            self.assertTrue(os.path.exists(stem + "_cut.png"))
            meta = json.load(open(stem + ".json"))
            for k in ("prompt", "negative", "seed", "settings", "check", "prompt_stats", "brief"):
                self.assertIn(k, meta)
            self.assertEqual(meta["seed"], self.seed + i)
            self.assertIsInstance(meta["check"]["flags"], list)
            body = json.load(open(os.path.join(self.hdir, "txt2img_s%d.json" % (self.seed + i))))
            self.assertEqual(core_nodes.validate_graph(body["prompt"]), [])
            self.assertEqual(prompts.check_graph(BIBLE, body["prompt"]), [])
            ks = [n for n in body["prompt"].values() if n["class_type"] == "KSampler"]
            self.assertEqual(ks[0]["inputs"]["seed"], self.seed + i)
            self.assertEqual(body["prompt"], json.load(open(stem + ".api.json"))["prompt"])
        self.assertTrue(os.path.exists(os.path.join(cdir, "contact_sheet.png")))
        self.assertEqual(run_hero.candidate_paths(cdir, self.hero)[0][0], self.seed, "_cut.png files are not candidates")

    def test_2_finalize_and_its_guards(self):
        import finalize
        import fix
        import run_hero
        self.run_main(finalize, [self.hero, str(self.seed), "--dry-run"])
        fdir = os.path.join(self.hdir, "final")
        im = Image.open(self.final)
        self.assertEqual((im.size, im.mode), ((1024, 2048), "RGBA"))
        fmeta = json.load(open(os.path.join(fdir, self.hero + ".json")))
        self.assertEqual(fmeta["origin"], [512, 1990])
        self.assertEqual(fmeta["sha256"], P.sha256_file(self.final))
        cand = os.path.join(self.hdir, "candidates", "%s_s%d.png" % (self.hero, self.seed))
        self.assertEqual(md5(os.path.join(fdir, self.hero + "_source.png")), md5(cand))
        self.assertEqual(fmeta["source_sha256"], P.sha256_file(cand))
        for f in (self.hero + "_portrait.png", self.hero + "_check.png", self.hero + "_boxes.png", self.hero + "_source.json"):
            self.assertTrue(os.path.exists(os.path.join(fdir, f)), f)
        self.assertTrue(os.path.exists(os.path.join(self.hdir, "face_refine_s%d.json" % (self.seed + 7))))
        before = md5(self.final)
        out = self.run_main(finalize, [self.hero, str(self.seed + 1), "--dry-run"], rc=1)
        self.assertIn("--force", out)
        self.assertEqual(md5(self.final), before, "a second finalize must not overwrite the final")
        self.run_main(fix, [self.hero, self.final, "--box", "400,400,50,50", "--dry-run"], rc=1)
        cmd5 = md5(cand)
        self.run_main(run_hero, [self.hero, "--count", "1", "--seed", str(self.seed), "--force", "--dry-run",
                                 "--size", "512x896"], rc=1)
        self.assertEqual(md5(cand), cmd5, "the master's candidate must not be re-rendered")

    def test_3_variants_keep_picks_and_tries(self):
        import variants
        self.run_main(variants, [self.hero, "--dry-run", "--count", "1"])
        base_sha = P.sha256_file(self.final)
        rec = self.variants_json()
        self.assertEqual(rec["base_sha"], base_sha)
        first = self.seed + 500
        base_a = np.asarray(Image.open(self.final))[..., 3]
        for v in BIBLE["heroes"][self.hero]["variant_set"]:
            self.assertEqual(rec["variants"][v]["picked_seed"], first)
            vim = Image.open(os.path.join(self.vdir, v + ".png"))
            self.assertTrue(np.array_equal(np.asarray(vim)[..., 3], base_a), v)
            self.assertTrue(os.path.exists(os.path.join(self.vdir, v + "_patch.png")))
            tj = json.load(open(os.path.join(self.vdir, "candidates", "%s_s%d.json" % (v, first))))
            self.assertEqual(tj["base_sha"], base_sha)
        self.assertIn("warp_overlay_hints", rec)
        try0 = os.path.join(self.vdir, "candidates", "smile_s%d.png" % first)
        m0 = md5(try0)
        self.run_main(variants, [self.hero, "--dry-run", "--count", "1", "--variants", "smile"])
        self.assertTrue(os.path.exists(os.path.join(self.vdir, "candidates", "smile_s%d.png" % (first + 1))))
        self.assertEqual(md5(try0), m0, "existing tries are never re-rendered without --force")
        self.run_main(variants, [self.hero, "--dry-run", "--pick", "smile=%d" % (first + 1)])
        self.assertEqual(self.variants_json()["variants"]["smile"]["picked_seed"], first + 1)
        smile = md5(os.path.join(self.vdir, "smile.png"))
        # the final's checkpoint is inherited by later variant passes
        fj = os.path.join(self.hdir, "final", self.hero + ".json")
        fm = json.load(open(fj))
        fm["settings"]["checkpoint"] = "master_ckpt.safetensors"
        json.dump(fm, open(fj, "w"))
        self.run_main(variants, [self.hero, "--dry-run", "--count", "1", "--variants", "smile"])
        rec = self.variants_json()
        self.assertEqual(rec["variants"]["smile"]["picked_seed"], first + 1, "a re-run must keep the pick")
        self.assertEqual(md5(os.path.join(self.vdir, "smile.png")), smile)
        self.assertEqual(rec["variants"]["smile"]["seeds"], [first, first + 1, first + 2])
        tj = json.load(open(os.path.join(self.vdir, "candidates", "smile_s%d.json" % (first + 2))))
        self.assertEqual(tj["settings"]["checkpoint"], "master_ckpt.safetensors")

    def test_4_finalize_force_archives_and_variants_detect_a_new_base(self):
        import finalize
        import variants
        old = md5(self.final)
        self.run_main(finalize, [self.hero, str(self.seed + 1), "--dry-run", "--force"])
        hist = sorted(os.listdir(os.path.join(self.hdir, "history")))
        self.assertEqual(len(hist), 1)
        arch = os.path.join(self.hdir, "history", hist[0])
        self.assertEqual(md5(os.path.join(arch, "final", self.hero + ".png")), old)
        self.assertTrue(os.path.exists(os.path.join(arch, "variants", "variants.json")))
        self.assertFalse(os.path.exists(self.vdir), "old variants must not sit next to a new final")
        self.assertEqual(json.load(open(self.final[:-4] + ".json"))["candidate_seed"], self.seed + 1)
        self.run_main(variants, [self.hero, "--dry-run", "--count", "1"])
        # the base image changes behind variants.py's back -> refuse, then --force archives
        im = Image.open(self.final).convert("RGBA")
        im.putpixel((5, 5), (1, 2, 3, 255))
        im.save(self.final)
        out = self.run_main(variants, [self.hero, "--dry-run", "--count", "1"], rc=1)
        self.assertIn("different base image", out)
        self.run_main(variants, [self.hero, "--dry-run", "--count", "1", "--force"])
        self.assertEqual(len(os.listdir(os.path.join(self.hdir, "history"))), 2)
        self.assertEqual(self.variants_json()["base_sha"], P.sha256_file(self.final))

    def test_5_install_checks_and_handoff(self):
        import install
        import roster
        self.run_main(install, [self.hero, "--dry-run"], rc=1)          # no live art yet
        live = os.path.join(comfy.art_src(), self.hero)
        shutil.copytree(self.hdir, live)
        fj = os.path.join(live, "final", self.hero + ".json")
        fm = json.load(open(fj))
        self.run_main(install, [self.hero], rc=1)                           # dry-run final
        fm["dry_run"] = False
        json.dump(fm, open(fj, "w"))
        out = self.run_main(install, [self.hero], rc=1)                     # final edited after finalize (test 4)
        self.assertIn("changed after finalize", out)
        fm["sha256"] = P.sha256_file(os.path.join(live, "final", self.hero + ".png"))
        json.dump(fm, open(fj, "w"))
        assets = os.path.join(TMP, "assets_heroes")
        os.environ["HALO_ASSETS_HEROES"] = assets
        try:
            self.run_main(install, [self.hero, "--dry-run"])
            self.assertFalse(os.path.exists(assets))
            self.run_main(install, [self.hero])
            dst = os.path.join(assets, self.hero)
            self.assertEqual(md5(os.path.join(dst, self.hero + ".png")), md5(os.path.join(live, "final", self.hero + ".png")))
            for v in BIBLE["heroes"][self.hero]["variant_set"]:
                self.assertTrue(os.path.exists(os.path.join(dst, "variants", v + ".png")), v)
            ho = json.load(open(install.handoff_path(self.hero)))
            slots = {o["slot"]: o for o in ho["warp_src"]["overlays"]}
            self.assertEqual(slots["eyes"]["variants"], {"closed": "variants/eyes_closed.png", "smile": "variants/smile.png"})
            self.assertEqual(slots["mouth"]["variants"], {"open": "variants/mouth_open.png", "smile": "variants/smile.png"})
            self.assertEqual(ho["warp_src"]["origin"], [512, 1990])
            self.assertEqual(ho["warp_src"]["meta"]["fx_color"], "#ff8a3d")
            self.run_main(install, [self.hero])                             # identical: fine without --force
            # a variant that changed outside its face region is refused
            sp = os.path.join(live, "variants", "smile.png")
            keep = open(sp, "rb").read()
            im = Image.open(sp).convert("RGBA")
            a = np.asarray(im)[..., 3]
            ys, xs = np.nonzero(a > 200)
            k = int(np.argmax(ys))
            im.putpixel((int(xs[k]), int(ys[k]) - 5), (0, 255, 0, int(a[ys[k] - 5, xs[k]])))
            im.save(sp)
            out = self.run_main(install, [self.hero], rc=1)
            self.assertIn("outside the expression region", out)
            open(sp, "wb").write(keep)
            # different art already installed -> --force, with a backup
            Image.new("RGBA", (1024, 2048), (9, 9, 9, 255)).save(os.path.join(dst, self.hero + ".png"))
            out = self.run_main(install, [self.hero], rc=1)
            self.assertIn("--force", out)
            self.run_main(install, [self.hero, "--force"])
            backups = [d for d in os.listdir(os.path.join(live, "history")) if d.startswith("installed_")]
            self.assertEqual(len(backups), 1)
            self.assertTrue(os.path.exists(os.path.join(live, "history", backups[0], self.hero + ".png")))
            out = self.run_main(roster, ["status"])
            self.assertIn("imra", out)
            self.assertIn("1/15 heroes handed", out)
        finally:
            os.environ.pop("HALO_ASSETS_HEROES", None)


if __name__ == "__main__":
    unittest.main(verbosity=2)
