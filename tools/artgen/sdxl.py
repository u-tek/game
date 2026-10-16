"""SDXL on CPU with diffusers, for the art farm.

- Model files: only the diffusers folders of cagliostrolab/animagine-xl-4.0 are downloaded (never the
  single-file checkpoint), one weight variant per component (fp16 files, upcast on load).
- Text: ComfyUI-compatible prompt encoding (same weight syntax and chunking as tools/comfy/prompts.py
  and comfy/sd1_clip.py): words packed into 75-token chunks, "(tag:1.2)" weights applied as
  z = (z - z_empty) * w + z_empty, pooled output from the first chunk, positive and negative
  aligned by repeating to the least common multiple of their chunk counts (exactly what ComfyUI
  does; cross-attention output is unchanged by repetition). All prompts are encoded first, then
  the text encoders are freed before the UNet loads (16 GB runners).
- dtype is an explicit run-level setting: fp32 (default) or bf16 (UNet only; candidates and bench
  only: img2img/inpaint refuse it). The VAE always runs in fp32 through our own encode/decode.
- CFG is always > 1 (config.CFG_MIN..CFG_MAX, checked here too) and the negative embeddings are
  always passed, so the explicit/childlike negatives that prompts.enforce() requires are active.
- img2img/inpaint take EFFECTIVE steps (schedule.total_steps_for): the bible's "20 steps at denoise
  0.4" runs 20 steps, as on ComfyUI.
- Memory: the UNet (10.3 GB in fp32) is loaded lazily and released around the big hires VAE passes,
  so the 1248x1824 init image is encoded and the result decoded UNTILED (no tile seams) with only the
  VAE resident; tiled only when MemAvailable is low. Every sampled stage records its own VmHWM peak
  (memstat.reset() before it).
"""
import gc
import math
import os
import resource
import time

import torch

import config as C
import memstat
import schedule
from sdxl_chunks import pack_chunks, word_tokens  # noqa: F401  (torch-free, tested offline)

COMPONENTS = ("unet", "vae", "text_encoder", "text_encoder_2")


def rss_gb():
    """Peak resident memory of this process so far (GB; never decreases)."""
    return resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / 1024.0 / 1024.0


# ------------------------------------------------------------------ downloads
def choose_files(files):
    """allow_patterns + per-component weight variant from a repo file list (no single-file ckpt)."""
    patterns = ["model_index.json", "scheduler/*", "tokenizer/*", "tokenizer_2/*"]
    variants = {}
    for comp in COMPONENTS:
        cf = [f for f in files if f.startswith(comp + "/")]
        weights = [f for f in cf if f.endswith(".safetensors")]
        if not weights:
            raise RuntimeError("%s: no safetensors weights in %s/" % (C.MODEL["repo"], comp))
        # "diffusion_pytorch_model.safetensors" / "-00001-of-00002.safetensors" vs "*.fp16*.safetensors".
        # fp16 is preferred: half the download, upcast to fp32 on load.
        plain = [f for f in weights if os.path.basename(f).count(".") == 1]
        fp16 = [f for f in weights if ".fp16" in os.path.basename(f)]
        if fp16:
            variants[comp] = "fp16"
            patterns += fp16
        elif plain:
            variants[comp] = None
            patterns += plain
        else:
            raise RuntimeError("%s/%s: unknown weight naming %s" % (C.MODEL["repo"], comp, weights))
        patterns += [f for f in cf if f.endswith(".json")]
    return sorted(set(patterns)), variants


def fetch_model(cache_dir, log=print):
    """Download (or reuse from cache) the base model. Returns (local dir, variants, info)."""
    from huggingface_hub import HfApi, snapshot_download
    t0 = time.time()
    files = HfApi().list_repo_files(C.MODEL["repo"])
    patterns, variants = choose_files(files)
    log("model repo %s: %d files; downloading %s" % (C.MODEL["repo"], len(files), ", ".join(patterns)))
    path = snapshot_download(C.MODEL["repo"], allow_patterns=patterns, cache_dir=cache_dir)
    size = 0
    for dp, _dn, fn in os.walk(path):
        for f in fn:
            try:
                size += os.path.getsize(os.path.join(dp, f))
            except OSError:
                pass
    info = {"repo": C.MODEL["repo"], "license": C.MODEL["license"], "variants": variants,
            "download_s": round(time.time() - t0, 1), "size_gb": round(size / 1e9, 2), "repo_files": files}
    log("model ready in %.0f s (%.2f GB on disk), variants %s" % (info["download_s"], info["size_gb"], variants))
    return path, variants, info


# ------------------------------------------------------------------ prompt encoding (ComfyUI-compatible)
class TextEncoders:
    def __init__(self, model_dir, variants, log=print):
        from transformers import CLIPTextModel, CLIPTextModelWithProjection, CLIPTokenizer
        t0 = time.time()
        self.log = log
        self.tok_l = CLIPTokenizer.from_pretrained(model_dir, subfolder="tokenizer")
        self.tok_g = CLIPTokenizer.from_pretrained(model_dir, subfolder="tokenizer_2")
        self.te_l = CLIPTextModel.from_pretrained(model_dir, subfolder="text_encoder", torch_dtype=torch.float32,
                                                  variant=variants.get("text_encoder"), use_safetensors=True).eval()
        self.te_g = CLIPTextModelWithProjection.from_pretrained(
            model_dir, subfolder="text_encoder_2", torch_dtype=torch.float32, variant=variants.get("text_encoder_2"),
            use_safetensors=True).eval()
        # ComfyUI SDXL: clip_l pads with the end token, clip_g with token 0 ("!")
        self.spec = [(self.tok_l, self.te_l, self.tok_l.eos_token_id), (self.tok_g, self.te_g, 0)]
        self.load_s = time.time() - t0
        log("text encoders loaded in %.0f s (rss peak %.1f GB)" % (self.load_s, rss_gb()))

    @torch.inference_mode()
    def _encode_one(self, tok, te, pad, chunks, want_pooled):
        bos, eos = tok.bos_token_id, tok.eos_token_id
        rows, weights = [], []
        for ch in chunks + [[]]:                         # last row = the empty chunk (z_empty)
            ids = [bos] + [t for t, _ in ch] + [eos]
            ws = [1.0] + [w for _, w in ch] + [1.0]
            ids += [pad] * (77 - len(ids))
            ws += [1.0] * (77 - len(ws))
            rows.append(ids)
            weights.append(ws)
        ids = torch.tensor(rows, dtype=torch.long)
        out = te(ids, output_hidden_states=True)
        hid = out.hidden_states[-2]                      # penultimate layer, no final norm (SDXL)
        z_empty = hid[-1:]
        z = hid[:-1]
        w = torch.tensor(weights[:-1], dtype=torch.float32)[..., None]
        if (w != 1.0).any():
            z = (z - z_empty) * w + z_empty
        pooled = out.text_embeds[0:1] if want_pooled else None
        return z.reshape(1, -1, z.shape[-1]), pooled

    def encode(self, text):
        """(hidden [1, chunks*77, 2048], pooled [1, 1280], n_chunks)"""
        parts, pooled, n = [], None, None
        for i, (tok, te, pad) in enumerate(self.spec):
            chunks = pack_chunks(word_tokens(tok, text))
            n = len(chunks) if n is None else max(n, len(chunks))
            parts.append((tok, te, pad, chunks, i == 1))
        hs = []
        for tok, te, pad, chunks, want in parts:
            while len(chunks) < n:                       # both encoders must give the same length
                chunks.append([])
            h, p = self._encode_one(tok, te, pad, chunks, want)
            hs.append(h)
            if want:
                pooled = p
        return torch.cat(hs, dim=-1), pooled, n

    def encode_pair(self, positive, negative):
        ph, pp, pn = self.encode(positive)
        nh, npool, nn = self.encode(negative)
        lcm = pn * nn // math.gcd(pn, nn)
        ph = ph.repeat(1, lcm // pn, 1)
        nh = nh.repeat(1, lcm // nn, 1)
        return {"prompt_embeds": ph, "pooled_prompt_embeds": pp, "negative_prompt_embeds": nh,
                "negative_pooled_prompt_embeds": npool, "chunks": [pn, nn]}

    def close(self):
        del self.te_l, self.te_g, self.spec
        gc.collect()


# ------------------------------------------------------------------ samplers
def make_scheduler(base_config, sampler):
    from diffusers import DPMSolverMultistepScheduler, EulerAncestralDiscreteScheduler
    cfg = dict(base_config)
    if sampler == "euler_ancestral":
        return EulerAncestralDiscreteScheduler.from_config(cfg, timestep_spacing="trailing")
    if sampler == "dpmpp_2m_karras":
        return DPMSolverMultistepScheduler.from_config(cfg, use_karras_sigmas=True, algorithm_type="dpmsolver++",
                                                       solver_order=2)
    raise ValueError("unknown sampler %r (allowed: %s)" % (sampler, ", ".join(C.SAMPLERS)))


def cpu_flags():
    try:
        with open("/proc/cpuinfo") as f:
            for line in f:
                if line.startswith("flags"):
                    return set(line.split(":", 1)[1].split())
    except OSError:
        pass
    return set()


def native_bf16():
    """True when the CPU has bf16 matrix instructions (AVX512_BF16 or AMX); bf16 is emulated (slow) otherwise."""
    return bool({"avx512_bf16", "amx_bf16"} & cpu_flags())


def pick_dtype(name):
    """Only the explicit run-level choices: fp32 or bf16 (no 'auto': every job of a run uses the same)."""
    if name not in C.DTYPES:
        raise ValueError("dtype must be one of %s, got %r" % (", ".join(C.DTYPES), name))
    return {"fp32": torch.float32, "bf16": torch.bfloat16}[name]


def pin_fp32(module):
    """Make module.to() ignore dtype changes (bf16 runs only). The SDXL pipelines may cast the VAE to the
    UNet dtype (force_upcast round trip); with a bf16 UNet that would round the VAE weights for good.
    Device moves still work."""
    orig = module.to

    def to(*args, **kwargs):
        device, _dtype, non_blocking, _fmt = torch._C._nn._parse_to(*args, **kwargs)
        return orig(device, non_blocking=non_blocking) if device is not None else module

    module.to = to
    return module


def check_cfg(cfg):
    prob = C.cfg_problem(cfg)
    if prob:
        raise ValueError("refusing to sample: %s" % prob)
    return float(cfg)


class Engine:
    """UNet + VAE (no text encoders) and the SDXL pipelines sharing them.

    txt2img(...)                        candidates / --no-source base
    hires(emb, image, size, ...)        upscale + img2img at `size` (encode untiled with only the VAE
                                        resident, sample, release the UNet, decode untiled)
    inpaint(...)                        face polish / expression variants (crop sized)
    bench(...)                          s/step only, no decode, no image
    Every sampling call returns (PIL image or None, info) with timings, steps and the stage's VmHWM."""

    def __init__(self, model_dir, variants, log=print, threads=None, dtype=C.DEFAULT_DTYPE, lazy_unet=False):
        from diffusers import AutoencoderKL, EulerAncestralDiscreteScheduler
        self.log = log
        self.model_dir, self.variants = model_dir, variants
        self.set_threads(threads or os.cpu_count() or 4)
        self.dtype_name = dtype
        self.dtype = pick_dtype(dtype)
        t0 = time.time()
        vae = AutoencoderKL.from_pretrained(model_dir, subfolder="vae", torch_dtype=torch.float32,
                                            variant=variants.get("vae"), use_safetensors=True).eval()
        self.vae = pin_fp32(vae) if self.dtype != torch.float32 else vae
        self.vae.disable_tiling()
        self.sched_config = EulerAncestralDiscreteScheduler.load_config(model_dir, subfolder="scheduler")
        self.unet = None
        self._pipes = {}
        self.unet_loads = 0
        self.load_s = time.time() - t0
        self.info = {"dtype": dtype, "threads": self.threads, "vae_dtype": "fp32",
                     "vae_force_upcast": bool(getattr(self.vae.config, "force_upcast", False)),
                     "vae_scaling_factor": float(self.vae.config.scaling_factor),
                     "bf16_native": native_bf16()}
        log("VAE (fp32) loaded in %.0f s; vae force_upcast=%s scaling_factor=%s" % (
            self.load_s, self.info["vae_force_upcast"], self.info["vae_scaling_factor"]))
        if not lazy_unet:
            self.load_unet()

    # UNet lifecycle --------------------------------------------------
    def load_unet(self):
        if self.unet is not None:
            return
        from diffusers import UNet2DConditionModel
        t0 = time.time()
        unet = UNet2DConditionModel.from_pretrained(self.model_dir, subfolder="unet", torch_dtype=self.dtype,
                                                    variant=self.variants.get("unet"), use_safetensors=True).eval()
        unet.to(memory_format=torch.channels_last)
        self.unet = unet
        self.unet_loads += 1
        dt = time.time() - t0
        self.load_s += dt
        self.log("UNet (%s) loaded in %.0f s on %d threads (load #%d, rss peak %.1f GB, now %s)" % (
            self.dtype_name, dt, self.threads, self.unet_loads, rss_gb(), memstat.snapshot()))

    def release_unet(self):
        if self.unet is None:
            return
        self._pipes = {}
        self.unet = None
        gc.collect()
        self.log("UNet released (%s)" % memstat.snapshot())

    def close(self):
        self.release_unet()
        self.vae = None
        gc.collect()

    def _pipe(self, kind):
        from diffusers import StableDiffusionXLImg2ImgPipeline, StableDiffusionXLInpaintPipeline, StableDiffusionXLPipeline
        self.load_unet()
        if "t2i" not in self._pipes:
            t2i = StableDiffusionXLPipeline(vae=self.vae, text_encoder=None, text_encoder_2=None, tokenizer=None,
                                            tokenizer_2=None, unet=self.unet,
                                            scheduler=make_scheduler(self.sched_config, "euler_ancestral"),
                                            add_watermarker=False)
            t2i.set_progress_bar_config(disable=True)
            self._pipes["t2i"] = t2i
        if kind not in self._pipes:
            cls = {"i2i": StableDiffusionXLImg2ImgPipeline, "inp": StableDiffusionXLInpaintPipeline}[kind]
            p = cls.from_pipe(self._pipes["t2i"], add_watermarker=False, torch_dtype=None)  # None: no re-cast
            p.set_progress_bar_config(disable=True)
            self._pipes[kind] = p
        return self._pipes[kind]

    def set_threads(self, n):
        torch.set_num_threads(int(n))
        self.threads = int(n)

    # sampling -------------------------------------------------------
    def _emb(self, t):
        return None if t is None else t.to(self.dtype)

    def _common(self, pipe, emb, seed, total_steps, cfg, sampler):
        cfg = check_cfg(cfg)
        if emb.get("negative_prompt_embeds") is None or emb.get("negative_pooled_prompt_embeds") is None:
            raise ValueError("refusing to sample without the negative prompt")
        pipe.scheduler = make_scheduler(self.sched_config, sampler)
        times = []
        last = [time.time()]

        def cb(_pipe, i, t, kw):
            now = time.time()
            times.append(now - last[0])
            last[0] = now
            return kw

        kw = {"prompt_embeds": self._emb(emb["prompt_embeds"]), "pooled_prompt_embeds": self._emb(emb["pooled_prompt_embeds"]),
              "negative_prompt_embeds": self._emb(emb["negative_prompt_embeds"]),
              "negative_pooled_prompt_embeds": self._emb(emb["negative_pooled_prompt_embeds"]),
              "num_inference_steps": int(total_steps), "guidance_scale": cfg, "output_type": "latent",
              "generator": torch.Generator("cpu").manual_seed(int(seed)), "callback_on_step_end": cb}
        return kw, times

    def _tile_for(self, pixels):
        """Untiled when memory allows (no seams); tiled VAE only as the fallback."""
        avail = memstat.mem_available_gb()
        need = C.FINAL["untiled_min_avail_gb"] * max(1.0, pixels / 2.3e6) if self.unet is None else 99.0
        small = pixels <= 1.15e6
        tiled = not small and (avail is None or avail < need)
        return tiled, avail

    @torch.inference_mode()
    def decode(self, latents):
        """fp32 VAE decode; untiled unless the image is big and memory is short."""
        lat = latents.to(torch.float32) / self.vae.config.scaling_factor
        h, w = lat.shape[-2] * 8, lat.shape[-1] * 8
        tiled, avail = self._tile_for(h * w)
        self.vae.enable_tiling() if tiled else self.vae.disable_tiling()
        img = self.vae.decode(lat, return_dict=False)[0]
        self.vae.disable_tiling()
        from diffusers.image_processor import VaeImageProcessor
        pil = VaeImageProcessor(vae_scale_factor=8).postprocess(img, output_type="pil")[0]
        return pil, {"decode": "tiled" if tiled else "untiled", "memavail_before_decode_gb": avail}

    @torch.inference_mode()
    def encode_image(self, image):
        """PIL RGB -> scaled fp32 latents (latent mean; untiled unless big and memory is short)."""
        from diffusers.image_processor import VaeImageProcessor
        x = VaeImageProcessor(vae_scale_factor=8).preprocess(image.convert("RGB")).to(torch.float32)
        tiled, avail = self._tile_for(image.width * image.height)
        self.vae.enable_tiling() if tiled else self.vae.disable_tiling()
        lat = self.vae.encode(x).latent_dist.mode() * self.vae.config.scaling_factor
        self.vae.disable_tiling()
        return lat, {"encode": "tiled" if tiled else "untiled", "memavail_before_encode_gb": avail}

    def _sample(self, pipe, kw, times, what):
        memstat.reset()
        t0 = time.time()
        with torch.inference_mode():
            lat = pipe(**kw).images
        info = {"what": what, "sample_s": round(time.time() - t0, 1), "steps_run": len(times),
                "num_inference_steps": kw["num_inference_steps"], "cfg": kw["guidance_scale"],
                "sampler": type(pipe.scheduler).__name__,
                "s_per_step": round(sum(times) / max(1, len(times)), 2), "step_s": [round(x, 2) for x in times],
                "overhead_s": round(max(0.0, time.time() - t0 - sum(times)), 1),
                "dtype": self.dtype_name, "threads": self.threads, "mem_sample": memstat.snapshot()}
        return lat, info

    def _finish(self, lat, info, t0, release_first=False):
        if release_first:
            self.release_unet()
        t1 = time.time()
        img, dinfo = self.decode(lat)
        info.update(dinfo)
        info["decode_s"] = round(time.time() - t1, 1)
        info["seconds"] = round(time.time() - t0, 1)
        info["mem_stage"] = memstat.snapshot()
        info["vmhwm_gb"] = info["mem_stage"]["vmhwm_gb"]
        info["rss_peak_gb"] = round(rss_gb(), 2)
        self.log("  %s: %.0f s (%d steps of %d, %.1f s/step, decode %.0f s %s, %s, %d threads, VmHWM %s GB)" % (
            info["what"], info["seconds"], info["steps_run"], info["num_inference_steps"], info["s_per_step"],
            info["decode_s"], info["decode"], self.dtype_name, self.threads, info["vmhwm_gb"]))
        return img, info

    def txt2img(self, emb, seed, steps, cfg, sampler, width, height):
        t0 = time.time()
        pipe = self._pipe("t2i")
        kw, times = self._common(pipe, emb, seed, steps, cfg, sampler)
        # initial noise drawn in fp32 (same values as diffusers' own fp32 draw), so fp32 and bf16 runs of
        # a seed start from the same noise
        kw["latents"] = torch.randn((1, 4, int(height) // 8, int(width) // 8), generator=kw["generator"],
                                    dtype=torch.float32).to(self.dtype)
        kw.update(width=int(width), height=int(height), original_size=(int(height), int(width)),
                  target_size=(int(height), int(width)))
        lat, info = self._sample(pipe, kw, times, "txt2img %dx%d" % (width, height))
        info["steps_effective"] = int(steps)
        return self._finish(lat, info, t0)

    def _no_bf16(self, what):
        if self.dtype != torch.float32:
            raise ValueError("%s runs in fp32 only (dtype %s): the SDXL img2img/inpaint encode path is not "
                             "verified for a bf16 UNet" % (what, self.dtype_name))

    def hires(self, emb, image, size, strength, seed, steps, cfg, sampler):
        """Upscale `image` to `size` (w, h) with Lanczos, then img2img at `strength` for `steps`
        EFFECTIVE steps. Memory choreography: UNet out -> VAE encode -> UNet in -> sample -> UNet out ->
        VAE decode. The UNet stays released afterwards (the next inpaint reloads it)."""
        from PIL import Image
        self._no_bf16("hires img2img")
        t0 = time.time()
        W, H = int(size[0]), int(size[1])
        self.release_unet()
        memstat.reset()
        up = image.convert("RGB").resize((W, H), Image.LANCZOS)
        lat0, einfo = self.encode_image(up)
        einfo["mem_encode"] = memstat.snapshot()
        total = schedule.total_steps_for(steps, strength)
        pipe = self._pipe("i2i")
        kw, times = self._common(pipe, emb, seed, total, cfg, sampler)
        kw.update(image=lat0, strength=float(strength), original_size=(H, W), target_size=(H, W),
                  aesthetic_score=6.0, negative_aesthetic_score=2.5)
        lat, info = self._sample(pipe, kw, times, "hires img2img %dx%d @%.2f" % (W, H, strength))
        info.update(einfo)
        info.update({"steps_effective": int(steps), "strength": float(strength), "size": [W, H]})
        return self._finish(lat, info, t0, release_first=True)

    def inpaint(self, emb, image, mask, strength, seed, steps, cfg, sampler):
        """Crop-sized inpaint (4-channel UNet: latent blending like ComfyUI's SetLatentNoiseMask) for
        `steps` EFFECTIVE steps."""
        self._no_bf16("inpaint")
        t0 = time.time()
        total = schedule.total_steps_for(steps, strength)
        pipe = self._pipe("inp")
        kw, times = self._common(pipe, emb, seed, total, cfg, sampler)
        self.vae.disable_tiling()
        kw.update(image=image, mask_image=mask, strength=float(strength), width=image.width, height=image.height,
                  original_size=(image.height, image.width), target_size=(image.height, image.width))
        lat, info = self._sample(pipe, kw, times, "inpaint %dx%d @%.2f" % (image.width, image.height, strength))
        info.update({"steps_effective": int(steps), "strength": float(strength)})
        return self._finish(lat, info, t0)

    def bench(self, emb, steps, cfg, sampler, width, height, seed=1):
        """Time `steps` txt2img steps without decoding (no image is produced)."""
        pipe = self._pipe("t2i")
        kw, times = self._common(pipe, emb, seed, steps, cfg, sampler)
        kw["latents"] = torch.randn((1, 4, int(height) // 8, int(width) // 8), generator=kw["generator"],
                                    dtype=torch.float32).to(self.dtype)
        kw.update(width=int(width), height=int(height), original_size=(int(height), int(width)),
                  target_size=(int(height), int(width)))
        _lat, info = self._sample(pipe, kw, times, "bench txt2img %dx%d" % (width, height))
        steady = info["step_s"][1:] or info["step_s"]
        info["s_per_step_steady"] = round(sum(steady) / max(1, len(steady)), 2)
        self.log("  bench %s %d threads: steps %s (steady %.1f s/step, VmHWM %s GB)" % (
            self.dtype_name, self.threads, info["step_s"], info["s_per_step_steady"], info["mem_sample"]["vmhwm_gb"]))
        return None, info
