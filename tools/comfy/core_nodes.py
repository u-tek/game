"""Schemas of the ComfyUI *core* nodes our workflows use, plus a graph validator.

The schemas mirror ComfyUI's INPUT_TYPES / RETURN_TYPES (comfy nodes.py, comfy_extras) so graphs can
be checked offline (tests, --dry-run). When a live server is connected, comfy.py validates against
the server's own /object_info instead (schema_from_object_info), which is the real source of truth.

Input spec values:
    "MODEL", "CLIP", "IMAGE", ...   a link of that type: ["node_id", output_index]
    "INT" / "FLOAT" / "STRING" / "BOOLEAN"   a widget value
    [option, ...]                   a combo with fixed options
    "COMBO"                         a combo whose options come from the server (model files, uploads)
"""

WIDGET_TYPES = ("INT", "FLOAT", "STRING", "BOOLEAN", "COMBO")

SAMPLERS = [
    "euler", "euler_cfg_pp", "euler_ancestral", "euler_ancestral_cfg_pp", "heun", "heunpp2", "dpm_2",
    "dpm_2_ancestral", "lms", "dpm_fast", "dpm_adaptive", "dpmpp_2s_ancestral", "dpmpp_2s_ancestral_cfg_pp",
    "dpmpp_sde", "dpmpp_sde_gpu", "dpmpp_2m", "dpmpp_2m_cfg_pp", "dpmpp_2m_sde", "dpmpp_2m_sde_gpu",
    "dpmpp_3m_sde", "dpmpp_3m_sde_gpu", "ddpm", "lcm", "ipndm", "ipndm_v", "deis", "res_multistep",
    "ddim", "uni_pc", "uni_pc_bh2",
]
SCHEDULERS = ["normal", "karras", "exponential", "sgm_uniform", "simple", "ddim_uniform", "beta",
              "linear_quadratic", "kl_optimal"]
LATENT_UPSCALE_METHODS = ["nearest-exact", "bilinear", "area", "bicubic", "bislerp"]
IMAGE_UPSCALE_METHODS = ["nearest-exact", "bilinear", "area", "bicubic", "lanczos"]


def _n(required, output, optional=None):
    return {"required": required, "optional": optional or {}, "output": output}


CORE = {
    "CheckpointLoaderSimple": _n({"ckpt_name": "COMBO"}, ["MODEL", "CLIP", "VAE"]),
    "VAELoader": _n({"vae_name": "COMBO"}, ["VAE"]),
    "LoraLoader": _n({"model": "MODEL", "clip": "CLIP", "lora_name": "COMBO",
                      "strength_model": "FLOAT", "strength_clip": "FLOAT"}, ["MODEL", "CLIP"]),
    "LoraLoaderModelOnly": _n({"model": "MODEL", "lora_name": "COMBO", "strength_model": "FLOAT"}, ["MODEL"]),
    "CLIPSetLastLayer": _n({"clip": "CLIP", "stop_at_clip_layer": "INT"}, ["CLIP"]),
    "CLIPTextEncode": _n({"text": "STRING", "clip": "CLIP"}, ["CONDITIONING"]),
    "ConditioningConcat": _n({"conditioning_to": "CONDITIONING", "conditioning_from": "CONDITIONING"},
                             ["CONDITIONING"]),
    "ModelSamplingDiscrete": _n({"model": "MODEL",
                                 "sampling": ["eps", "v_prediction", "lcm", "x0", "img_to_img"],
                                 "zsnr": "BOOLEAN"}, ["MODEL"]),
    "RescaleCFG": _n({"model": "MODEL", "multiplier": "FLOAT"}, ["MODEL"]),
    "EmptyLatentImage": _n({"width": "INT", "height": "INT", "batch_size": "INT"}, ["LATENT"]),
    "KSampler": _n({"model": "MODEL", "seed": "INT", "steps": "INT", "cfg": "FLOAT",
                    "sampler_name": SAMPLERS, "scheduler": SCHEDULERS,
                    "positive": "CONDITIONING", "negative": "CONDITIONING",
                    "latent_image": "LATENT", "denoise": "FLOAT"}, ["LATENT"]),
    "VAEDecode": _n({"samples": "LATENT", "vae": "VAE"}, ["IMAGE"]),
    "VAEEncode": _n({"pixels": "IMAGE", "vae": "VAE"}, ["LATENT"]),
    "VAEEncodeForInpaint": _n({"pixels": "IMAGE", "vae": "VAE", "mask": "MASK", "grow_mask_by": "INT"}, ["LATENT"]),
    "SetLatentNoiseMask": _n({"samples": "LATENT", "mask": "MASK"}, ["LATENT"]),
    "LatentUpscaleBy": _n({"samples": "LATENT", "upscale_method": LATENT_UPSCALE_METHODS, "scale_by": "FLOAT"},
                          ["LATENT"]),
    "ImageScaleBy": _n({"image": "IMAGE", "upscale_method": IMAGE_UPSCALE_METHODS, "scale_by": "FLOAT"}, ["IMAGE"]),
    "ImageScale": _n({"image": "IMAGE", "upscale_method": IMAGE_UPSCALE_METHODS, "width": "INT", "height": "INT",
                      "crop": ["disabled", "center"]}, ["IMAGE"]),
    "UpscaleModelLoader": _n({"model_name": "COMBO"}, ["UPSCALE_MODEL"]),
    "ImageUpscaleWithModel": _n({"upscale_model": "UPSCALE_MODEL", "image": "IMAGE"}, ["IMAGE"]),
    "LoadImage": _n({"image": "COMBO"}, ["IMAGE", "MASK"]),
    "LoadImageMask": _n({"image": "COMBO", "channel": ["alpha", "red", "green", "blue"]}, ["MASK"]),
    "SaveImage": _n({"images": "IMAGE", "filename_prefix": "STRING"}, []),
    "PreviewImage": _n({"images": "IMAGE"}, []),
    "MaskToImage": _n({"mask": "MASK"}, ["IMAGE"]),
    "ImageToMask": _n({"image": "IMAGE", "channel": ["red", "green", "blue", "alpha"]}, ["MASK"]),
    "GrowMask": _n({"mask": "MASK", "expand": "INT", "tapered_corners": "BOOLEAN"}, ["MASK"]),
    "ImageCompositeMasked": _n({"destination": "IMAGE", "source": "IMAGE", "x": "INT", "y": "INT",
                                "resize_source": "BOOLEAN"}, ["IMAGE"], {"mask": "MASK"}),
    "ControlNetLoader": _n({"control_net_name": "COMBO"}, ["CONTROL_NET"]),
    "ControlNetApplyAdvanced": _n({"positive": "CONDITIONING", "negative": "CONDITIONING",
                                   "control_net": "CONTROL_NET", "image": "IMAGE", "strength": "FLOAT",
                                   "start_percent": "FLOAT", "end_percent": "FLOAT"},
                                  ["CONDITIONING", "CONDITIONING"], {"vae": "VAE"}),
}

OUTPUT_NODES = {"SaveImage", "PreviewImage"}
# Combo inputs whose valid values are uploads, not server lists we can check in advance.
UPLOAD_INPUTS = {("LoadImage", "image"), ("LoadImageMask", "image")}


def _combo_options(spec):
    """object_info input spec -> list of combo options, or None if it is not a combo."""
    if not isinstance(spec, (list, tuple)) or not spec:
        return None
    t = spec[0]
    if isinstance(t, list):
        return list(t)
    if t == "COMBO" and len(spec) > 1 and isinstance(spec[1], dict):
        return list(spec[1].get("options", []))
    return None


def _spec_type(spec):
    """object_info input spec -> our schema value (type string or option list)."""
    opts = _combo_options(spec)
    if opts is not None:
        return opts
    if isinstance(spec, (list, tuple)) and spec and isinstance(spec[0], str):
        return spec[0]
    return "*"


def schema_from_object_info(object_info):
    """Convert a server /object_info payload to the schema format above."""
    out = {}
    for cls, info in object_info.items():
        inp = info.get("input", {}) or {}
        req = {k: _spec_type(v) for k, v in (inp.get("required", {}) or {}).items()}
        opt = {k: _spec_type(v) for k, v in (inp.get("optional", {}) or {}).items()}
        out[cls] = {"required": req, "optional": opt, "output": list(info.get("output", []) or []),
                    "output_node": bool(info.get("output_node"))}
    return out


def is_link(v):
    return isinstance(v, list) and len(v) == 2 and isinstance(v[0], str) and isinstance(v[1], int)


def _type_ok(expected, value):
    if expected == "INT":
        return isinstance(value, int) and not isinstance(value, bool)
    if expected == "FLOAT":
        return isinstance(value, (int, float)) and not isinstance(value, bool)
    if expected == "STRING":
        return isinstance(value, str)
    if expected == "BOOLEAN":
        return isinstance(value, bool)
    if expected == "COMBO":
        return isinstance(value, str) and value != ""
    return True


def validate_graph(graph, schema=None, check_combos=True):
    """Validate an API-format graph {node_id: {"class_type", "inputs"}}. Returns a list of error strings
    (empty = valid). Checks: known node types, every required input present, no unknown inputs, links
    point to existing nodes and valid output indexes with matching types, widget value types, combo
    options, at least one output node, no cycles."""
    schema = schema or CORE
    errors = []
    if not isinstance(graph, dict) or not graph:
        return ["graph is empty or not a dict"]
    for nid, node in graph.items():
        where = "node %s" % nid
        if not isinstance(nid, str):
            errors.append("%s: node ids must be strings" % where)
        if not isinstance(node, dict) or "class_type" not in node or "inputs" not in node:
            errors.append("%s: needs class_type and inputs" % where)
            continue
        cls = node["class_type"]
        where = "node %s (%s)" % (nid, cls)
        sch = schema.get(cls)
        if sch is None:
            errors.append("%s: unknown node type" % where)
            continue
        inputs = node["inputs"]
        for name in sch["required"]:
            if name not in inputs:
                errors.append("%s: missing required input '%s'" % (where, name))
        for name, value in inputs.items():
            expected = sch["required"].get(name, sch["optional"].get(name))
            if expected is None:
                errors.append("%s: unknown input '%s'" % (where, name))
                continue
            if is_link(value):
                src = graph.get(value[0])
                if src is None:
                    errors.append("%s: input '%s' links to missing node %s" % (where, name, value[0]))
                    continue
                src_sch = schema.get(src.get("class_type"))
                if src_sch is None:
                    continue
                outs = src_sch["output"]
                if not 0 <= value[1] < len(outs):
                    errors.append("%s: input '%s' uses output %d of node %s (%s), which has %d outputs"
                                  % (where, name, value[1], value[0], src["class_type"], len(outs)))
                    continue
                got = outs[value[1]]
                if isinstance(expected, str) and expected not in WIDGET_TYPES and expected != "*" \
                        and got != "*" and got != expected:
                    errors.append("%s: input '%s' expects %s but node %s output %d is %s"
                                  % (where, name, expected, value[0], value[1], got))
                if isinstance(expected, list) or expected in WIDGET_TYPES:
                    # widgets may be converted to inputs; allow it only from primitive-like outputs
                    if got not in ("INT", "FLOAT", "STRING", "BOOLEAN", "*", "COMBO"):
                        errors.append("%s: widget '%s' is linked to a %s output" % (where, name, got))
                continue
            if isinstance(value, list):
                errors.append("%s: input '%s' looks like a malformed link %r (use [\"id\", index])"
                              % (where, name, value))
                continue
            if isinstance(expected, list):
                if check_combos and (cls, name) not in UPLOAD_INPUTS and value not in expected:
                    errors.append("%s: '%s' = %r is not one of %s" % (where, name, value, expected[:12]))
            elif expected in WIDGET_TYPES:
                if not _type_ok(expected, value):
                    errors.append("%s: '%s' = %r is not a valid %s" % (where, name, value, expected))
            elif expected != "*":
                errors.append("%s: input '%s' needs a %s link, got %r" % (where, name, expected, value))
    def _is_output(n):
        c = n.get("class_type")
        return c in OUTPUT_NODES or bool((schema.get(c) or {}).get("output_node"))
    if not any(_is_output(n) for n in graph.values() if isinstance(n, dict)):
        errors.append("graph has no output node (SaveImage)")
    # cycles
    state = {}

    def visit(n, depth=0):
        if state.get(n) == 1:
            return True
        if state.get(n) == 2 or n not in graph or depth > 10000:
            return False
        state[n] = 1
        for v in (graph[n].get("inputs") or {}).values():
            if is_link(v) and visit(v[0], depth + 1):
                return True
        state[n] = 2
        return False
    for n in graph:
        if visit(n):
            errors.append("graph has a cycle through node %s" % n)
            break
    return errors
