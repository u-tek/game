"""ComfyUI API-format graph builders for the Halo & Horn art pipeline.

Every builder returns a plain dict {node_id: {"class_type", "inputs", "_meta"}} ready for POST /prompt.
Links are ["node_id", output_index]. By default only core ComfyUI nodes are used (see core_nodes.py);
optional custom nodes (IPAdapter, background removal) are added only when the caller passes the
server's /object_info, and their inputs are filled from that schema so version differences don't break.

Settings dict `s` (built by pipeline.resolve_settings from data/art_prompts.json + discovery + CLI):
    checkpoint, family, loras [{name, strength, clip_strength}], vae (or None), clip_skip (or None),
    model_sampling ({sampling, zsnr} or None), rescale_cfg (float or None),
    sampler, scheduler, steps, cfg, width, height,
    hires {enabled, mode ("latent"|"model"), scale, denoise, steps, latent_method},
    upscale_model (or None), upscale_model_scale (int)
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import core_nodes  # noqa: E402
import prompts  # noqa: E402


class WorkflowError(ValueError):
    pass


class Graph:
    def __init__(self):
        self.nodes = {}
        self._n = 0

    def add(self, class_type, title=None, **inputs):
        self._n += 1
        nid = str(self._n)
        self.nodes[nid] = {"class_type": class_type, "inputs": inputs, "_meta": {"title": title or class_type}}
        return nid

    def save(self, image, prefix, title="Save"):
        return self.add("SaveImage", title, images=image, filename_prefix=prefix)


def L(nid, idx=0):
    """A link to output `idx` of node `nid`."""
    return [str(nid), int(idx)]


# ------------------------------------------------------------------ schema-driven custom nodes
def fill_from_schema(class_type, object_info, links=None, values=None):
    """Inputs for a (custom) node from the server's schema: links/values given by the caller win,
    other required widgets get their schema default (or first combo option). Raises WorkflowError if
    a required link input is not provided."""
    info = (object_info or {}).get(class_type)
    if not info:
        raise WorkflowError("node %s is not on this server" % class_type)
    links, values = links or {}, values or {}
    inp = info.get("input", {}) or {}
    out = {}
    for name, spec in (inp.get("required", {}) or {}).items():
        if name in links:
            out[name] = links[name]
            continue
        opts = core_nodes._combo_options(spec)
        cfg = spec[1] if isinstance(spec, (list, tuple)) and len(spec) > 1 and isinstance(spec[1], dict) else {}
        if name in values:
            v = values[name]
            if opts is not None and v not in opts:
                v = cfg.get("default", opts[0] if opts else v)
            out[name] = v
            continue
        if opts is not None:
            out[name] = cfg.get("default", opts[0] if opts else "")
            continue
        t = spec[0] if spec else None
        if t in ("INT", "FLOAT", "STRING", "BOOLEAN"):
            out[name] = cfg.get("default", {"INT": 0, "FLOAT": 0.0, "STRING": "", "BOOLEAN": False}[t])
            continue
        raise WorkflowError("%s: required input '%s' (%s) has no link" % (class_type, name, t))
    for name in (inp.get("optional", {}) or {}):
        if name in links:
            out[name] = links[name]
        elif name in values:
            out[name] = values[name]
    return out


def output_index(object_info, class_type, type_name):
    outs = list(((object_info or {}).get(class_type) or {}).get("output", []) or [])
    if type_name not in outs:
        raise WorkflowError("%s has no %s output" % (class_type, type_name))
    return outs.index(type_name)


# ------------------------------------------------------------------ shared pieces
def model_stack(g, s):
    """Checkpoint -> LoRAs -> clip skip -> v-pred sampling -> RescaleCFG. Returns (model, clip, vae)."""
    ck = g.add("CheckpointLoaderSimple", "Checkpoint", ckpt_name=s["checkpoint"])
    model, clip, vae = L(ck, 0), L(ck, 1), L(ck, 2)
    for lo in s.get("loras") or []:
        st = float(lo.get("strength", 1.0))
        n = g.add("LoraLoader", "LoRA " + lo["name"], model=model, clip=clip, lora_name=lo["name"],
                  strength_model=st, strength_clip=float(lo.get("clip_strength", st)))
        model, clip = L(n, 0), L(n, 1)
    if s.get("clip_skip"):
        n = g.add("CLIPSetLastLayer", "Clip skip", clip=clip, stop_at_clip_layer=-abs(int(s["clip_skip"])))
        clip = L(n)
    ms = s.get("model_sampling")
    if ms:
        n = g.add("ModelSamplingDiscrete", "Model sampling", model=model, sampling=ms.get("sampling", "eps"),
                  zsnr=bool(ms.get("zsnr", False)))
        model = L(n)
    if s.get("rescale_cfg"):
        n = g.add("RescaleCFG", "Rescale CFG", model=model, multiplier=float(s["rescale_cfg"]))
        model = L(n)
    if s.get("vae"):
        n = g.add("VAELoader", "VAE", vae_name=s["vae"])
        vae = L(n)
    return model, clip, vae


def text_cond(g, clip, text, title):
    """One CLIPTextEncode per chunk of whole tags (prompts.split_chunks), joined by ConditioningConcat,
    so no tag is cut at a 75-token chunk break. The first chunk's pooled output is kept, as in
    ComfyUI's own chunking."""
    parts = prompts.split_chunks(text)
    cond = None
    for i, part in enumerate(parts):
        t = title if len(parts) == 1 else "%s %d/%d" % (title, i + 1, len(parts))
        n = L(g.add("CLIPTextEncode", t, text=part, clip=clip))
        cond = n if cond is None else L(g.add("ConditioningConcat", title + " join", conditioning_to=cond,
                                              conditioning_from=n))
    return cond


def encode(g, clip, positive, negative):
    return text_cond(g, clip, positive, "Positive prompt"), text_cond(g, clip, negative, "Negative prompt")


def ksampler(g, s, model, pos, neg, latent, seed, steps=None, denoise=1.0, title="KSampler"):
    return L(g.add("KSampler", title, model=model, seed=int(seed), steps=int(steps or s["steps"]),
                   cfg=float(s["cfg"]), sampler_name=s["sampler"], scheduler=s["scheduler"],
                   positive=pos, negative=neg, latent_image=latent, denoise=float(denoise)))


def upscale_with_model(g, s, image, scale):
    """Upscale `image` by `scale` using the upscale model if set (model x, then resize down to `scale`),
    else plain lanczos."""
    if s.get("upscale_model"):
        um = g.add("UpscaleModelLoader", "Upscale model", model_name=s["upscale_model"])
        up = g.add("ImageUpscaleWithModel", "Upscale (model)", upscale_model=L(um), image=image)
        factor = float(scale) / float(s.get("upscale_model_scale") or 4)
        if abs(factor - 1.0) < 1e-6:
            return L(up)
        return L(g.add("ImageScaleBy", "Resize", image=L(up), upscale_method="lanczos", scale_by=round(factor, 4)))
    return L(g.add("ImageScaleBy", "Resize", image=image, upscale_method="lanczos", scale_by=float(scale)))


def apply_ipadapter(g, model, ip, object_info):
    """Optional IPAdapter (ComfyUI_IPAdapter_plus) for identity/style consistency from a reference
    image. ip = {"image": uploaded name, "weight", "start_at", "end_at", "preset"}."""
    li = g.add("LoadImage", "IPAdapter reference", image=ip["image"])
    loader = "IPAdapterUnifiedLoader"
    ul = g.add(loader, "IPAdapter loader", **fill_from_schema(
        loader, object_info, links={"model": model}, values={"preset": ip.get("preset", "PLUS (high strength)")}))
    m_idx = output_index(object_info, loader, "MODEL")
    i_idx = output_index(object_info, loader, "IPADAPTER")
    adv = "IPAdapterAdvanced"
    ad = g.add(adv, "IPAdapter", **fill_from_schema(
        adv, object_info, links={"model": L(ul, m_idx), "ipadapter": L(ul, i_idx), "image": L(li)},
        values={"weight": float(ip.get("weight", 0.7)), "start_at": float(ip.get("start_at", 0.0)),
                "end_at": float(ip.get("end_at", 0.85))}))
    return L(ad, output_index(object_info, adv, "MODEL"))


def apply_controlnet(g, pos, neg, vae, cn, object_info=None):
    """Optional core ControlNet (e.g. an SDXL openpose/lineart model) from a prepared control image.
    cn = {"model", "image" (uploaded name), "strength", "start", "end"}."""
    cl = g.add("ControlNetLoader", "ControlNet", control_net_name=cn["model"])
    li = g.add("LoadImage", "Control image", image=cn["image"])
    kw = dict(positive=pos, negative=neg, control_net=L(cl), image=L(li), strength=float(cn.get("strength", 0.6)),
              start_percent=float(cn.get("start", 0.0)), end_percent=float(cn.get("end", 0.8)))
    opt = (((object_info or {}).get("ControlNetApplyAdvanced") or {}).get("input") or {}).get("optional") or {}
    if "vae" in opt:
        kw["vae"] = vae
    ap = g.add("ControlNetApplyAdvanced", "Apply ControlNet", **kw)
    return L(ap, 0), L(ap, 1)


# ------------------------------------------------------------------ (a) txt2img + hires fix
def txt2img(s, positive, negative, seed, prefix, ipadapter=None, controlnet=None, object_info=None,
            save_base=False):
    """Full-body portrait at an SDXL bucket (s.width x s.height), then a hires-fix second pass:
    latent upscale (LatentUpscaleBy) or, when an upscale model is set and hires.mode == "model",
    pixel upscale with the model, re-encode and re-sample at low denoise."""
    g = Graph()
    model, clip, vae = model_stack(g, s)
    if ipadapter:
        model = apply_ipadapter(g, model, ipadapter, object_info)
    pos, neg = encode(g, clip, positive, negative)
    if controlnet:
        pos, neg = apply_controlnet(g, pos, neg, vae, controlnet, object_info)
    lat = g.add("EmptyLatentImage", "Canvas", width=int(s["width"]), height=int(s["height"]), batch_size=1)
    base = ksampler(g, s, model, pos, neg, L(lat), seed, title="Base pass")
    hires = s.get("hires") or {}
    if not hires.get("enabled", True):
        img = L(g.add("VAEDecode", "Decode", samples=base, vae=vae))
        g.save(img, prefix)
        return g.nodes
    if save_base:
        g.save(L(g.add("VAEDecode", "Decode base", samples=base, vae=vae)), prefix + "_base", "Save base")
    scale = float(hires.get("scale", 1.5))
    if hires.get("mode") == "model" and s.get("upscale_model"):
        dec = L(g.add("VAEDecode", "Decode base", samples=base, vae=vae))
        up = upscale_with_model(g, s, dec, scale)
        lat2 = L(g.add("VAEEncode", "Encode hires", pixels=up, vae=vae))
    else:
        lat2 = L(g.add("LatentUpscaleBy", "Latent upscale", samples=base,
                       upscale_method=hires.get("latent_method", "nearest-exact"), scale_by=scale))
    fine = ksampler(g, s, model, pos, neg, lat2, seed, steps=hires.get("steps", 20),
                    denoise=hires.get("denoise", 0.45), title="Hires pass")
    img = L(g.add("VAEDecode", "Decode", samples=fine, vae=vae))
    g.save(img, prefix)
    return g.nodes


# ------------------------------------------------------------------ (b) img2img refine
def img2img(s, image_name, positive, negative, seed, denoise, prefix, scale_by=1.0, ipadapter=None,
            object_info=None, steps=None):
    """Refine an uploaded image: optional resize (upscale model if set), encode, re-sample at `denoise`."""
    g = Graph()
    model, clip, vae = model_stack(g, s)
    if ipadapter:
        model = apply_ipadapter(g, model, ipadapter, object_info)
    pos, neg = encode(g, clip, positive, negative)
    img = L(g.add("LoadImage", "Source", image=image_name))
    if abs(float(scale_by) - 1.0) > 1e-6:
        img = upscale_with_model(g, s, img, scale_by)
    lat = L(g.add("VAEEncode", "Encode", pixels=img, vae=vae))
    out = ksampler(g, s, model, pos, neg, lat, seed, steps=steps, denoise=denoise, title="Refine")
    g.save(L(g.add("VAEDecode", "Decode", samples=out, vae=vae)), prefix)
    return g.nodes


# ------------------------------------------------------------------ (c) inpaint
def inpaint(s, image_name, mask_name, positive, negative, seed, denoise, prefix, mode="noise_mask",
            grow=8, composite=True, steps=None):
    """Repaint the white area of an uploaded mask (red channel, white = repaint).
    mode "noise_mask": VAEEncode + SetLatentNoiseMask, keeps the original colors under the mask, any
      denoise (0.35 face polish, ~0.6 eyes closed / mouth open).
    mode "vae_inpaint": VAEEncodeForInpaint (masked area blanked, use denoise 1.0) for replacing things.
    composite: paste the result back over the original through the mask (ImageCompositeMasked) so
      pixels outside the mask are bit-identical."""
    g = Graph()
    model, clip, vae = model_stack(g, s)
    pos, neg = encode(g, clip, positive, negative)
    src = g.add("LoadImage", "Source", image=image_name)
    mask = L(g.add("LoadImageMask", "Mask", image=mask_name, channel="red"))
    if mode == "vae_inpaint":
        lat = L(g.add("VAEEncodeForInpaint", "Encode (inpaint)", pixels=L(src), vae=vae, mask=mask,
                      grow_mask_by=int(grow)))
    else:
        if grow:
            mask = L(g.add("GrowMask", "Grow mask", mask=mask, expand=int(grow), tapered_corners=True))
        enc = L(g.add("VAEEncode", "Encode", pixels=L(src), vae=vae))
        lat = L(g.add("SetLatentNoiseMask", "Noise mask", samples=enc, mask=mask))
    out = ksampler(g, s, model, pos, neg, lat, seed, steps=steps, denoise=denoise, title="Inpaint")
    img = L(g.add("VAEDecode", "Decode", samples=out, vae=vae))
    if composite:
        img = L(g.add("ImageCompositeMasked", "Keep unmasked pixels", destination=L(src), source=img, x=0, y=0,
                      resize_source=False, mask=mask))
    g.save(img, prefix)
    return g.nodes


# ------------------------------------------------------------------ (d) upscale
def upscale(s, image_name, prefix, scale=2.0):
    """Upscale an uploaded image by `scale` (upscale model when available, else lanczos)."""
    g = Graph()
    img = L(g.add("LoadImage", "Source", image=image_name))
    g.save(upscale_with_model(g, s, img, scale), prefix)
    return g.nodes


# ------------------------------------------------------------------ (e) tiled diffusion upscale
TILED_DEFAULTS = {"denoise": 0.35, "tile": 1024, "padding": 64, "mask_blur": 16, "mode": "Chess",
                  "seam_fix": "None", "steps": 20}     # 20 steps per tile: the owner-approved finishing test


def tiled_upscale(s, image_name, positive, negative, seed, prefix, object_info, scale=2.0, denoise=None,
                  tile=None, steps=None):
    """Upscale an uploaded image with the upscale model, then re-draw it tile by tile at low denoise
    (UltimateSDUpscale, custom node ComfyUI_UltimateSDUpscale) with the checkpoint, so the extra
    resolution gets real painted detail instead of a stretched image. Tiles are SDXL-native 1024 px;
    the model stack (v-pred sampling, RescaleCFG) and sampler settings are the family's own."""
    if not s.get("upscale_model"):
        raise WorkflowError("tiled upscale needs an upscale model (none found; pass --upscale-model)")
    d = dict(TILED_DEFAULTS)
    if denoise is not None:
        d["denoise"] = float(denoise)
    if tile:
        d["tile"] = int(tile)
    g = Graph()
    model, clip, vae = model_stack(g, s)
    pos, neg = encode(g, clip, positive, negative)
    img = L(g.add("LoadImage", "Source", image=image_name))
    um = L(g.add("UpscaleModelLoader", "Upscale model", model_name=s["upscale_model"]))
    node = "UltimateSDUpscale"
    us = g.add(node, "Tiled upscale", **fill_from_schema(
        node, object_info,
        links={"image": img, "model": model, "positive": pos, "negative": neg, "vae": vae, "upscale_model": um},
        values={"upscale_by": float(scale), "seed": int(seed), "steps": int(steps or d["steps"]),
                "cfg": float(s["cfg"]), "sampler_name": s["sampler"], "scheduler": s["scheduler"],
                "denoise": d["denoise"], "mode_type": d["mode"], "tile_width": d["tile"],
                "tile_height": d["tile"], "mask_blur": d["mask_blur"], "tile_padding": d["padding"],
                "seam_fix_mode": d["seam_fix"], "force_uniform_tiles": True, "tiled_decode": False,
                "batch_size": 1}))
    g.save(L(us, output_index(object_info, node, "IMAGE")), prefix)
    return g.nodes


# ------------------------------------------------------------------ optional: server-side background removal
def remove_background(recipe, image_name, prefix, object_info):
    """Run a discovered background-removal node (see comfy.rembg_recipe) and save its mask as an image
    (white = figure) or, if it has no MASK output, its image (RGBA). post.py turns that into alpha."""
    g = Graph()
    src = g.add("LoadImage", "Source", image=image_name)
    links = {recipe["image_input"]: L(src)}
    for inp, (pcls, pidx) in (recipe.get("providers") or {}).items():
        pn = g.add(pcls, "Provider " + pcls, **fill_from_schema(pcls, object_info))
        links[inp] = L(pn, pidx)
    rb = g.add(recipe["class"], "Remove background", **fill_from_schema(recipe["class"], object_info, links=links))
    if recipe.get("mask_output") is not None:
        img = L(g.add("MaskToImage", "Mask to image", mask=L(rb, recipe["mask_output"])))
    else:
        img = L(rb, recipe["image_output"])
    g.save(img, prefix)
    return g.nodes


def validate(graph, object_info=None):
    """Validation errors against the server schema (if given) or the embedded core schema."""
    if object_info:
        return core_nodes.validate_graph(graph, core_nodes.schema_from_object_info(object_info))
    return core_nodes.validate_graph(graph)
