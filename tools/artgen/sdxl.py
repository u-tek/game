"""SDXL on CPU (fp32) with diffusers, for the art farm.

- Model files: only the diffusers folders of cagliostrolab/animagine-xl-4.0 are downloaded (never the
  single-file checkpoint), one weight variant per component.
- Text: ComfyUI-compatible prompt encoding (same weight syntax and chunking as tools/comfy/prompts.py
  and comfy/sd1_clip.py): words packed into 75-token chunks, "(tag:1.2)" weights applied as
  z = (z - z_empty) * w + z_empty, pooled output from the first chunk, positive and negative
  aligned by repeating to the least common multiple of their chunk counts (exactly what ComfyUI
  does; cross-attention output is unchanged by repetition). All prompts are encoded first, then
  the text encoders are freed before the UNet loads (16 GB runners).
- Sampling: txt2img / img2img / inpaint (4-channel UNet, latent blending like SetLatentNoiseMask),
  channels-last UNet in fp32 (or bf16 on CPUs with native bf16), fp32 VAE decode (tiled above
  ~1.1 MP), per-step timing.
"""
import gc
import math
import os
import resource
import time

import torch

import config as C
from sdxl_chunks import pack_chunks, word_tokens  # noqa: F401  (torch-free, tested offline)

_DTYPE = torch.float32
COMPONENTS = ("unet", "vae", "text_encoder", "text_encoder_2")


def rss_gb():
    """Peak resident memory of this process so far (GB)."""
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


def fetch_lora(name, cache_dir=None, log=print):
    from huggingface_hub import hf_hub_download
    spec = C.LORAS[name]
    t0 = time.time()
    p = hf_hub_download(spec["repo"], spec["file"], cache_dir=cache_dir)
    log("LoRA %s (%s/%s) ready in %.0f s" % (name, spec["repo"], spec["file"], time.time() - t0))
    return p


# ------------------------------------------------------------------ prompt encoding (ComfyUI-compatible)
class TextEncoders:
    def __init__(self, model_dir, variants, log=print):
        from transformers import CLIPTextModel, CLIPTextModelWithProjection, CLIPTokenizer
        t0 = time.time()
        self.log = log
        self.tok_l = CLIPTokenizer.from_pretrained(model_dir, subfolder="tokenizer")
        self.tok_g = CLIPTokenizer.from_pretrained(model_dir, subfolder="tokenizer_2")
        self.te_l = CLIPTextModel.from_pretrained(model_dir, subfolder="text_encoder", torch_dtype=_DTYPE,
                                                  variant=variants.get("text_encoder"), use_safetensors=True).eval()
        self.te_g = CLIPTextModelWithProjection.from_pretrained(
            model_dir, subfolder="text_encoder_2", torch_dtype=_DTYPE, variant=variants.get("text_encoder_2"),
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
        w = torch.tensor(weights[:-1], dtype=_DTYPE)[..., None]
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
    from diffusers import (DPMSolverMultistepScheduler, EulerAncestralDiscreteScheduler, EulerDiscreteScheduler,
                           LCMScheduler)
    cfg = dict(base_config)
    if sampler == "euler_ancestral":
        return EulerAncestralDiscreteScheduler.from_config(cfg, timestep_spacing="trailing")
    if sampler == "euler_trailing":
        return EulerDiscreteScheduler.from_config(cfg, timestep_spacing="trailing")
    if sampler == "dpmpp_2m_karras":
        return DPMSolverMultistepScheduler.from_config(cfg, use_karras_sigmas=True, algorithm_type="dpmsolver++",
                                                       solver_order=2)
    if sampler == "lcm":
        return LCMScheduler.from_config(cfg, timestep_spacing="trailing")
    raise ValueError("unknown sampler %r" % sampler)


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
    if name in (None, "", "auto"):
        return torch.bfloat16 if native_bf16() else torch.float32
    return {"fp32": torch.float32, "bf16": torch.bfloat16}[name]


def pin_fp32(module):
    """Make module.to() ignore dtype changes. The SDXL img2img/inpaint pipelines cast the VAE to the
    UNet dtype after encoding (force_upcast); with a bf16 UNet that would round the VAE weights to
    bf16 for good. Device moves still work."""
    orig = module.to

    def to(*args, **kwargs):
        device, _dtype, non_blocking, _fmt = torch._C._nn._parse_to(*args, **kwargs)
        return orig(device, non_blocking=non_blocking) if device is not None else module

    module.to = to
    return module


class Engine:
    """UNet + VAE (no text encoders) and the three pipelines sharing them. The UNet runs in `dtype`
    (fp32, or bf16 on CPUs with native bf16); the VAE always decodes in fp32 (own decode path)."""

    def __init__(self, model_dir, variants, log=print, threads=None, dtype="auto", tiling="auto"):
        from diffusers import (AutoencoderKL, StableDiffusionXLImg2ImgPipeline, StableDiffusionXLInpaintPipeline,
                               StableDiffusionXLPipeline, UNet2DConditionModel)
        self.log = log
        n = threads or os.cpu_count() or 4
        torch.set_num_threads(n)
        self.threads = n
        self.dtype = pick_dtype(dtype)
        t0 = time.time()
        unet = UNet2DConditionModel.from_pretrained(model_dir, subfolder="unet", torch_dtype=self.dtype,
                                                    variant=variants.get("unet"), use_safetensors=True).eval()
        unet.to(memory_format=torch.channels_last)
        vae = AutoencoderKL.from_pretrained(model_dir, subfolder="vae", torch_dtype=torch.float32,
                                            variant=variants.get("vae"), use_safetensors=True).eval()
        self.tiling = tiling
        self.vae = pin_fp32(vae)
        from diffusers import EulerAncestralDiscreteScheduler
        self.sched_config = EulerAncestralDiscreteScheduler.load_config(model_dir, subfolder="scheduler")
        sched = make_scheduler(self.sched_config, "euler_ancestral")
        self.t2i = StableDiffusionXLPipeline(vae=vae, text_encoder=None, text_encoder_2=None, tokenizer=None,
                                             tokenizer_2=None, unet=unet, scheduler=sched, add_watermarker=False)
        self.i2i = StableDiffusionXLImg2ImgPipeline.from_pipe(self.t2i, add_watermarker=False, torch_dtype=None)  # None: no re-cast of shared modules
        self.inp = StableDiffusionXLInpaintPipeline.from_pipe(self.t2i, add_watermarker=False, torch_dtype=None)  # None: no re-cast of shared modules
        for p in (self.t2i, self.i2i, self.inp):
            p.set_progress_bar_config(disable=True)
        self.lora = None
        self.load_s = time.time() - t0
        log("UNet (%s) + VAE (fp32) loaded in %.0f s on %d threads (rss peak %.1f GB)" % (
            str(self.dtype).replace("torch.", ""), self.load_s, n, rss_gb()))

    def set_threads(self, n):
        torch.set_num_threads(int(n))
        self.threads = int(n)

    # LoRA -----------------------------------------------------------
    def set_lora(self, name, scale=1.0, cache_dir=None):
        if name == (self.lora or {}).get("name") and scale == (self.lora or {}).get("scale"):
            return
        if self.lora:
            t0 = time.time()
            self.t2i.unfuse_lora(components=["unet"])
            self.t2i.unload_lora_weights()
            self.log("LoRA %s removed in %.0f s" % (self.lora["name"], time.time() - t0))
            self.lora = None
            gc.collect()
        if name:
            t0 = time.time()
            path = fetch_lora(name, cache_dir, self.log)
            self.t2i.load_lora_weights(os.path.dirname(path), weight_name=os.path.basename(path), adapter_name="fast")
            self.t2i.fuse_lora(components=["unet"], lora_scale=scale)
            self.lora = {"name": name, "scale": scale, "repo": C.LORAS[name]["repo"], "file": C.LORAS[name]["file"],
                         "license": C.LORAS[name]["license"]}
            self.log("LoRA %s fused at %.2f in %.0f s" % (name, scale, time.time() - t0))

    # sampling -------------------------------------------------------
    def _emb(self, t):
        return None if t is None else t.to(self.dtype)

    def _common(self, pipe, emb, seed, steps, cfg, sampler):
        pipe.scheduler = make_scheduler(self.sched_config, sampler)
        times = []
        last = [time.time()]

        def cb(_pipe, i, t, kw):
            now = time.time()
            times.append(now - last[0])
            last[0] = now
            return kw

        kw = {"prompt_embeds": self._emb(emb["prompt_embeds"]), "pooled_prompt_embeds": self._emb(emb["pooled_prompt_embeds"]),
              "num_inference_steps": int(steps), "guidance_scale": float(cfg), "output_type": "latent",
              "generator": torch.Generator("cpu").manual_seed(int(seed)), "callback_on_step_end": cb}
        if cfg > 1.0:
            kw["negative_prompt_embeds"] = self._emb(emb["negative_prompt_embeds"])
            kw["negative_pooled_prompt_embeds"] = self._emb(emb["negative_pooled_prompt_embeds"])
        return kw, times

    @torch.inference_mode()
    def decode(self, latents):
        """fp32 VAE decode (tiled above ~1.1 MP unless tiling is forced on/off)."""
        lat = latents.to(torch.float32) / self.vae.config.scaling_factor
        h, w = lat.shape[-2] * 8, lat.shape[-1] * 8
        tile = self.tiling == "on" or (self.tiling == "auto" and h * w > 1.15e6)
        if tile:
            self.vae.enable_tiling()
        else:
            self.vae.disable_tiling()
        img = self.vae.decode(lat, return_dict=False)[0]
        return self.t2i.image_processor.postprocess(img, output_type="pil")[0]

    def _run(self, pipe, kw, times, what):
        t0 = time.time()
        if pipe is not self.t2i:      # img2img/inpaint encode the init image with the VAE: tile big ones
            self.vae.enable_tiling()
        with torch.inference_mode():
            lat = pipe(**kw).images
        t1 = time.time()
        img = self.decode(lat)
        total = time.time() - t0
        info = {"what": what, "seconds": round(total, 1), "steps_run": len(times),
                "s_per_step": round(sum(times) / max(1, len(times)), 2), "step_s": [round(x, 2) for x in times],
                "decode_s": round(time.time() - t1, 1),
                "overhead_s": round(max(0.0, t1 - t0 - sum(times)), 1), "rss_peak_gb": round(rss_gb(), 2),
                "dtype": str(self.dtype).replace("torch.", ""), "threads": self.threads}
        self.log("  %s: %.0f s (%d steps, %.1f s/step, decode %.0f s, other %.0f s, %s, %d threads, rss peak %.1f GB)" % (
            what, total, len(times), info["s_per_step"], info["decode_s"], info["overhead_s"], info["dtype"],
            self.threads, info["rss_peak_gb"]))
        return img, info

    def txt2img(self, emb, seed, steps, cfg, sampler, width, height):
        kw, times = self._common(self.t2i, emb, seed, steps, cfg, sampler)
        # initial noise drawn in fp32 (same values as diffusers' own fp32 draw), so fp32 and bf16 runs of
        # a seed start from the same noise
        kw["latents"] = torch.randn((1, 4, int(height) // 8, int(width) // 8), generator=kw["generator"],
                                    dtype=torch.float32).to(self.dtype)
        kw.update(width=int(width), height=int(height), original_size=(int(height), int(width)),
                  target_size=(int(height), int(width)))
        return self._run(self.t2i, kw, times, "txt2img %dx%d" % (width, height))

    def img2img(self, emb, image, strength, seed, steps, cfg, sampler):
        kw, times = self._common(self.i2i, emb, seed, steps, cfg, sampler)
        kw.update(image=image, strength=float(strength), original_size=(image.height, image.width),
                  target_size=(image.height, image.width), aesthetic_score=6.0, negative_aesthetic_score=2.5)
        return self._run(self.i2i, kw, times, "img2img %dx%d @%.2f" % (image.width, image.height, strength))

    def inpaint(self, emb, image, mask, strength, seed, steps, cfg, sampler):
        kw, times = self._common(self.inp, emb, seed, steps, cfg, sampler)
        kw.update(image=image, mask_image=mask, strength=float(strength), width=image.width, height=image.height,
                  original_size=(image.height, image.width), target_size=(image.height, image.width))
        return self._run(self.inp, kw, times, "inpaint %dx%d @%.2f" % (image.width, image.height, strength))
