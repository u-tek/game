#!/usr/bin/env python3
"""Plumbing test of the real sdxl.Engine with a tiny random SDXL-shaped UNet and VAE (no download).

Skipped when torch/diffusers are not installed (the offline suite is test_artgen.py). With them:

    pip install --target <dir> torch==2.8.0 diffusers==0.35.2 transformers==4.56.2 accelerate==1.10.1 safetensors==0.6.2
    PYTHONPATH=<dir> python3 tools/artgen/test_sdxl_tiny.py

Checks: txt2img, the lazy UNet, hires (VAE encode with the UNet released -> latent img2img ->
release -> untiled decode), inpaint, the effective-steps count, the CFG guard, the negative-embeds
guard, fp32 everywhere, bf16 refused for img2img/inpaint, the bench path, and the cover repair
(gen.publish_screened) through a real crop inpaint.
"""
import os
import shutil
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

try:
    import torch
    import diffusers  # noqa: F401
    HAVE = True
except Exception:       # noqa: BLE001
    HAVE = False

import config as C  # noqa: E402


def build_model(d):
    from diffusers import AutoencoderKL, EulerAncestralDiscreteScheduler, UNet2DConditionModel
    torch.manual_seed(0)
    unet = UNet2DConditionModel(
        block_out_channels=(32, 64), layers_per_block=1, sample_size=32, in_channels=4, out_channels=4,
        down_block_types=("DownBlock2D", "CrossAttnDownBlock2D"), up_block_types=("CrossAttnUpBlock2D", "UpBlock2D"),
        attention_head_dim=(2, 4), use_linear_projection=True, addition_embed_type="text_time",
        addition_time_embed_dim=8, transformer_layers_per_block=(1, 1), projection_class_embeddings_input_dim=80,
        cross_attention_dim=64, norm_num_groups=1)
    vae = AutoencoderKL(block_out_channels=[8, 16, 16, 16], in_channels=3, out_channels=3, layers_per_block=1,
                        down_block_types=["DownEncoderBlock2D"] * 4, up_block_types=["UpDecoderBlock2D"] * 4,
                        latent_channels=4, norm_num_groups=8, sample_size=1024)
    sched = EulerAncestralDiscreteScheduler(beta_start=0.00085, beta_end=0.012, beta_schedule="scaled_linear",
                                            steps_offset=1, timestep_spacing="leading")
    unet.save_pretrained(os.path.join(d, "unet"))
    vae.save_pretrained(os.path.join(d, "vae"))
    sched.save_pretrained(os.path.join(d, "scheduler"))
    return {"unet": None, "vae": None}


def emb(neg=True):
    g = torch.Generator().manual_seed(1)
    e = {"prompt_embeds": torch.randn(1, 77, 64, generator=g), "pooled_prompt_embeds": torch.randn(1, 32, generator=g),
         "negative_prompt_embeds": torch.randn(1, 77, 64, generator=g),
         "negative_pooled_prompt_embeds": torch.randn(1, 32, generator=g), "chunks": [1, 1]}
    if not neg:
        e["negative_prompt_embeds"] = None
    return e


@unittest.skipUnless(HAVE, "torch/diffusers not installed")
class TestTinyEngine(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        import sdxl
        cls.sdxl = sdxl
        cls.d = tempfile.mkdtemp()
        cls.variants = build_model(cls.d)
        cls.eng = sdxl.Engine(cls.d, cls.variants, log=lambda *a: None, threads=2, dtype="fp32", lazy_unet=True)

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.d, ignore_errors=True)

    def test_1_txt2img_and_lazy_unet(self):
        self.assertIsNone(self.eng.unet)
        img, info = self.eng.txt2img(emb(), 5, 4, 5.0, "euler_ancestral", 128, 192)
        self.assertEqual(img.size, (128, 192))
        self.assertEqual((info["steps_run"], info["num_inference_steps"], info["decode"]), (4, 4, "untiled"))
        self.assertIsNotNone(self.eng.unet)
        self.assertEqual(self.eng.unet.dtype, torch.float32)
        self.assertEqual(next(self.eng.vae.parameters()).dtype, torch.float32)
        self.assertIn("vmhwm_gb", info)
        img2, _ = self.eng.txt2img(emb(), 5, 4, 5.0, "dpmpp_2m_karras", 128, 192)
        self.assertEqual(img2.size, (128, 192))

    def test_2_hires_effective_steps(self):
        base, _ = self.eng.txt2img(emb(), 7, 3, 5.0, "euler_ancestral", 128, 192)
        loads = self.eng.unet_loads
        img, info = self.eng.hires(emb(), base, (192, 288), 0.4, 8, 5, 5.0, "euler_ancestral")
        self.assertEqual(img.size, (192, 288))
        self.assertEqual(info["steps_run"], 5)                     # effective
        self.assertEqual(info["num_inference_steps"], 13)          # int(13 * 0.4) = 5
        self.assertEqual((info["encode"], info["decode"]), ("untiled", "untiled"))
        self.assertIsNone(self.eng.unet)                           # released after the hires pass
        self.assertEqual(self.eng.unet_loads, loads + 1)

    def test_3_inpaint_reloads(self):
        from PIL import Image
        im = Image.new("RGB", (128, 128), (120, 120, 130))
        mask = Image.new("L", (128, 128), 0)
        mask.paste(255, (32, 32, 96, 96))
        out, info = self.eng.inpaint(emb(), im, mask, 0.6, 9, 4, 5.0, "euler_ancestral")
        self.assertEqual(out.size, (128, 128))
        self.assertEqual(info["steps_run"], 4)
        self.assertEqual(info["num_inference_steps"], 7)           # int(7 * 0.6) = 4
        self.assertIsNotNone(self.eng.unet)

    def test_4_guards(self):
        for cfg in (1.0, 1.8, 3.0, 7.5):
            with self.assertRaises(ValueError):
                self.eng.txt2img(emb(), 1, 2, cfg, "euler_ancestral", 64, 64)
        with self.assertRaises(ValueError):
            self.eng.txt2img(emb(neg=False), 1, 2, 5.0, "euler_ancestral", 64, 64)
        with self.assertRaises(ValueError):
            self.eng.txt2img(emb(), 1, 2, 5.0, "euler_trailing", 64, 64)
        with self.assertRaises(ValueError):
            self.sdxl.pick_dtype("auto")

    def test_5_bench_and_bf16(self):
        _none, info = self.eng.bench(emb(), 3, 5.0, "euler_ancestral", 64, 64)
        self.assertEqual(info["steps_run"], 3)
        self.assertIn("s_per_step_steady", info)
        e16 = self.sdxl.Engine(self.d, self.variants, log=lambda *a: None, threads=2, dtype="bf16", lazy_unet=False)
        self.assertEqual(e16.unet.dtype, torch.bfloat16)
        self.assertEqual(next(e16.vae.parameters()).dtype, torch.float32)
        img, _ = e16.txt2img(emb(), 3, 2, 5.0, "euler_ancestral", 64, 64)
        self.assertEqual(img.size, (64, 64))
        from PIL import Image
        with self.assertRaises(ValueError):
            e16.hires(emb(), img, (96, 96), 0.4, 1, 2, 5.0, "euler_ancestral")
        with self.assertRaises(ValueError):
            e16.inpaint(emb(), img, Image.new("L", (64, 64), 255), 0.5, 1, 2, 5.0, "euler_ancestral")
        e16.close()

    def test_6_cover_repair_through_the_engine(self):
        """gen.publish_screened with the real engine: the flagged square is repainted through a crop
        inpaint, the repaired file passes the (fake, box-capable) filter and is the one published."""
        import types

        import numpy as np
        from PIL import Image, ImageDraw

        import gen
        import safety

        class RedBox:
            name, classes, threshold = "redbox", ["EXPOSED"], 0.25

            @staticmethod
            def _red(img):
                a = np.asarray(img.convert("RGB")).astype(np.int16)
                return (a[..., 0] > 240) & (a[..., 1] < 15) & (a[..., 2] < 15)

            def class_max(self, img):
                return {"EXPOSED": float(min(1.0, self._red(img).mean() * 100))}

            def class_boxes(self, img, classes, conf):
                ys, xs = np.nonzero(self._red(img))
                if not len(ys):
                    return []
                return [(float(xs.min()), float(ys.min()), float(xs.max() + 1), float(ys.max() + 1), "EXPOSED", 0.9)]

        d = tempfile.mkdtemp()
        saved = dict(C.REPAIR)
        try:
            C.REPAIR.update(px=128, steps=2, crop_min=96)
            pub = safety.Publisher(safety.ExposureFilter([RedBox()], log=lambda *a: None), os.path.join(d, "out"),
                                   log=lambda *a: None)
            img = Image.new("RGB", (256, 384), (120, 120, 130))
            ImageDraw.Draw(img).rectangle([100, 150, 140, 190], fill=(255, 0, 0))
            tmp = gen.save_tmp(os.path.join(d, "work"), img, "x.webp", **gen.WEBP_KW)
            a = types.SimpleNamespace(no_repair=False, deadline=gen.Deadline(600))
            job = {"images": []}
            dest, out, rec, rep = gen.publish_screened(a, pub, self.eng, emb(), img, tmp, "h/x.webp", 11, gen._Est(), job)
            self.assertIsNotNone(dest, rec)
            self.assertTrue(rec["result"].startswith("published after"))
            self.assertEqual(job["images"][0]["steps_run"], 2)            # effective steps
            pub_img = Image.open(dest).convert("RGB")
            self.assertEqual(RedBox._red(pub_img).sum(), 0)
            a0 = np.asarray(img).astype(np.int16)
            a1 = np.asarray(pub_img).astype(np.int16)
            far = np.ones(a0.shape[:2], bool)
            far[100:260, 80:170] = False                                 # crop of the padded box + feather
            self.assertLess(np.abs(a1 - a0)[far].max(), 12)               # untouched outside (WebP noise only)
            self.assertEqual(safety.verify(os.path.join(d, "out"), log=lambda *a: None)["deleted"], 0)
        finally:
            C.REPAIR.clear()
            C.REPAIR.update(saved)
            shutil.rmtree(d, ignore_errors=True)


if __name__ == "__main__":
    unittest.main(verbosity=2)
