"""Shared plumbing for run_hero.py, finalize.py, variants.py and fix.py: paths, CLI options,
settings resolution (bible + server discovery + flags), crop-and-inpaint, dry-run placeholders."""
import hashlib
import json
import os
import shutil
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import numpy as np  # noqa: E402
from PIL import Image, ImageDraw, ImageFilter  # noqa: E402

import comfy  # noqa: E402
import prompts  # noqa: E402
import workflows  # noqa: E402

ROOT = comfy.ROOT
DRYRUN_CKPT = "DRYRUN_PLACEHOLDER_illustrious.safetensors"
SERVER_SUBFOLDER = "halo_horn"
MIN_CKPT_SCORE = 5        # below this, discovery's top checkpoint is not a known anime SDXL family


class PipelineError(RuntimeError):
    pass


# ------------------------------------------------------------------ paths
def hero_dir(hero_id, dry_run=False):
    """art_src/<id> (live) or art_src/_dryrun/<id> (dry run, so placeholders never mix with real art)."""
    return os.path.join(comfy.dryrun_dir() if dry_run else comfy.art_src(), hero_id)


def rel(p):
    return comfy.rel(p)


def write_json(path, obj):
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path, "w") as f:
        json.dump(obj, f, indent=1)
    return path


def read_json(path, default=None):
    if not os.path.exists(path):
        return default
    with open(path) as f:
        return json.load(f)


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def archive(hdir, names, log=print, reason=""):
    """Move hdir/<name> (files or folders) that exist into hdir/history/<timestamp>/ and return that
    folder (None if nothing existed). Nothing is ever deleted: restore by moving it back."""
    present = [n for n in names if os.path.exists(os.path.join(hdir, n))]
    if not present:
        return None
    dest = os.path.join(hdir, "history", time.strftime("%Y%m%d-%H%M%S"))
    k = 1
    while os.path.exists(dest):
        k += 1
        dest = os.path.join(hdir, "history", time.strftime("%Y%m%d-%H%M%S") + "_%d" % k)
    os.makedirs(dest)
    for n in present:
        shutil.move(os.path.join(hdir, n), os.path.join(dest, n))
    if reason:
        with open(os.path.join(dest, "REASON.txt"), "w") as f:
            f.write(reason + "\n")
    log("archived %s -> %s" % (", ".join(present), rel(dest)))
    return dest


# ------------------------------------------------------------------ CLI
def add_common_args(ap):
    g = ap.add_argument_group("server and model")
    g.add_argument("--dry-run", action="store_true",
                   help="send nothing: write the exact API JSON to art_src/_dryrun/ and use placeholder images")
    g.add_argument("--ckpt", help="checkpoint file name (default: COMFYUI_CKPT or best anime SDXL found)")
    g.add_argument("--family", help="prompt/settings family from data/art_prompts.json (default: from the name)")
    g.add_argument("--sampler")
    g.add_argument("--scheduler")
    g.add_argument("--steps", type=int)
    g.add_argument("--cfg", type=float)
    g.add_argument("--size", help="base resolution WxH (SDXL bucket, default 768x1344)")
    g.add_argument("--lora", action="append", default=[], help="NAME[:STRENGTH], repeatable")
    g.add_argument("--vae", help="separate VAE file (default: the checkpoint's own)")
    g.add_argument("--upscale-model", help="upscale model file (default: best anime upscaler found)")
    g.add_argument("--no-hires", action="store_true", help="skip the hires-fix second pass")
    g.add_argument("--hires-mode", choices=["auto", "latent", "model"], default="auto")
    g.add_argument("--hires-denoise", type=float)
    g.add_argument("--zsnr", dest="zsnr", action="store_true", default=None,
                   help="v-pred families: force zero-terminal-SNR on (default: the family setting)")
    g.add_argument("--no-zsnr", dest="zsnr", action="store_false",
                   help="v-pred families: zsnr off (try if images look washed out or burnt)")
    g.add_argument("--timeout", type=int, default=900, help="seconds per running job")
    g.add_argument("--quiet", action="store_true")
    return ap


def parse_lora(spec):
    name, _, st = spec.partition(":")
    return {"name": name, "strength": float(st) if st else 0.8}


def make_client(args):
    return comfy.Comfy(dry_run=args.dry_run, timeout=60, verbose=not getattr(args, "quiet", False))


def resolve_settings(bible, args, client, hero_id=None):
    """Settings dict for workflows.* from the bible family block, server discovery and CLI flags.
    Returns (settings, discovery or None, object_info or None)."""
    if client.dry_run:
        disc, oi = comfy.load_cached_discovery()
        if oi:
            client.object_info_cache = oi
            client.schema = comfy.core_nodes.schema_from_object_info(oi)
    else:
        disc = client.discover(families=bible["families"])
        oi = client.object_info_cache
    rec = (disc or {}).get("recommended") or {}
    pin = comfy.load_pin() or {}
    ckpt = args.ckpt or os.environ.get("COMFYUI_CKPT") or pin.get("checkpoint")
    if not ckpt and rec.get("checkpoint"):
        score = rec.get("checkpoint_score")
        if score is not None and score < MIN_CKPT_SCORE:
            ranked = rec.get("checkpoint_scores") or [[None, n] for n in rec.get("checkpoint_ranking", [])]
            raise PipelineError(
                "no checkpoint on the server is recognisably an anime SDXL model (Illustrious, NoobAI, Pony, "
                "Animagine...); the best guess %r scored %s. Pick one and pass --ckpt NAME (or export "
                "COMFYUI_CKPT=NAME) plus --family if needed. Ranked: %s" % (
                    rec["checkpoint"], score, ", ".join("%s (%s)" % (n, sc) for sc, n in ranked[:10])))
        ckpt = rec["checkpoint"]
    if not ckpt:
        if not client.dry_run:
            raise PipelineError("no checkpoint on the server (models/checkpoints is empty?)")
        ckpt = DRYRUN_CKPT
    if disc and disc.get("checkpoints") and ckpt not in disc["checkpoints"]:
        raise PipelineError("checkpoint %r is not on the server. Available: %s" % (ckpt, ", ".join(disc["checkpoints"])))
    family = args.family or os.environ.get("COMFYUI_FAMILY") or (
        pin.get("family") if pin.get("checkpoint") and ckpt == pin.get("checkpoint") else None)
    guessed = False
    if not family:
        family, guessed = comfy.detect_family(ckpt, bible["families"])
    fam = prompts.family_block(bible, family)
    st = fam["settings"]
    w, h = st["width"], st["height"]
    if hero_id and bible["heroes"][hero_id].get("size"):
        w, h = [int(v) for v in bible["heroes"][hero_id]["size"]]
    if args.size:
        w, h = [int(v) for v in args.size.lower().split("x")]
    if w % 8 or h % 8:
        raise PipelineError("--size must be multiples of 8")
    loras = [dict(lo) for lo in bible.get("style", {}).get("loras", [])]     # roster-wide style
    if hero_id:
        loras += [dict(lo) for lo in bible["heroes"][hero_id].get("loras", [])]
    loras += [parse_lora(x) for x in args.lora]
    if disc and disc.get("loras") is not None:
        for lo in loras:
            if lo["name"] not in disc["loras"]:
                raise PipelineError("LoRA %r is not on the server. Available: %s" % (lo["name"], ", ".join(disc["loras"][:30])))
    up = getattr(args, "upscale_model", None) or os.environ.get("COMFYUI_UPSCALER") or rec.get("upscale_model")
    if disc and up and disc.get("upscale_models") is not None and up not in disc["upscale_models"]:
        raise PipelineError("upscale model %r is not on the server" % up)
    hires = dict(st["hires"])
    hires["enabled"] = not args.no_hires
    mode = args.hires_mode
    if mode == "auto":
        mode = "model" if up else "latent"
    if mode == "model" and not up:
        raise PipelineError("--hires-mode model needs an upscale model (none found; pass --upscale-model)")
    hires["mode"] = mode
    hires["denoise"] = args.hires_denoise if args.hires_denoise is not None else (
        hires.get("denoise_model", 0.4) if mode == "model" else hires.get("denoise_latent", 0.5))
    ms = dict(st["model_sampling"]) if st.get("model_sampling") else None
    if ms and getattr(args, "zsnr", None) is not None:
        ms["zsnr"] = bool(args.zsnr)
    s = {
        "checkpoint": ckpt, "family": family, "family_guessed": guessed,
        "sampler": args.sampler or st["sampler"], "scheduler": args.scheduler or st["scheduler"],
        "steps": args.steps or st["steps"], "cfg": args.cfg if args.cfg is not None else st["cfg"],
        "width": w, "height": h, "clip_skip": st.get("clip_skip"), "model_sampling": ms,
        "rescale_cfg": st.get("rescale_cfg"), "vae": args.vae, "loras": loras, "hires": hires,
        "upscale_model": up, "upscale_model_scale": comfy.upscaler_scale(up) if up else None,
        "rembg": rec.get("rembg"), "ipadapter": bool(rec.get("ipadapter")),
        "server_checked": bool(disc),
    }
    if disc and disc.get("samplers") and s["sampler"] not in disc["samplers"]:
        alt = next((x for x in ("euler_ancestral", "euler") if x in disc["samplers"]), disc["samplers"][0])
        client.log("warning: sampler %s not on the server, using %s" % (s["sampler"], alt))
        s["sampler"] = alt
    if disc and disc.get("schedulers") and s["scheduler"] not in disc["schedulers"]:
        s["scheduler"] = "normal" if "normal" in disc["schedulers"] else disc["schedulers"][0]
    if guessed:
        client.log("note: model family guessed as %r from %r; pass --family if wrong" % (family, ckpt))
    return s, disc, oi


def inherit_model(args, meta, source, log=print):
    """Use the checkpoint/family/VAE that made `meta` (a candidate's or final's metadata) so every
    derived pass (polish, variants, fixes) renders with the master's model. A conflicting --ckpt /
    --family wins but is warned about."""
    ms = (meta or {}).get("settings") or {}
    if not ms.get("checkpoint"):
        return
    if meta.get("dry_run") and not args.dry_run:
        log("note: %s was a dry run; not inheriting its placeholder model" % source)
        return
    for key, attr in (("checkpoint", "ckpt"), ("family", "family"), ("vae", "vae")):
        have, want = getattr(args, attr, None), ms.get(key)
        if want is None:
            continue
        if have and have != want:
            log("WARNING: --%s %s differs from %s (%s); the result will not match the master's style"
                % (attr, have, source, want))
        elif not have:
            setattr(args, attr, want)


def settings_for_meta(s):
    return {k: v for k, v in s.items() if k not in ("rembg",)}


def output_size(s):
    hz = s.get("hires") or {}
    f = float(hz.get("scale", 1.5)) if hz.get("enabled", True) else 1.0
    return int(round(s["width"] * f)), int(round(s["height"] * f))


# ------------------------------------------------------------------ dry-run placeholders
def _hex(c):
    return tuple(int(c[i:i + 2], 16) for i in (1, 3, 5))


FACTION_COLORS = {"celestial": ("#fefdff", "#f4c95c", "#8fd2f2"), "infernal": ("#c0283a", "#1c1420", "#f5b83d"),
                  "fallen": ("#8e6ce0", "#22202c", "#cfd3e6")}


def placeholder_figure(bible, hero_id, seed, size, label="DRY RUN"):
    """A crude flat-background stand-in figure (proportions roughly 7 heads, wings if the hero has
    them) so the post-processing chain can run without a server. Clearly labelled."""
    h = bible["heroes"][hero_id]
    _, bg = prompts.background(bible, hero_id)
    W, H = size
    rng = np.random.default_rng(seed)
    im = Image.new("RGB", (W, H), tuple(bg["rgb"]))
    d = ImageDraw.Draw(im)
    c1, c2, c3 = [_hex(c) for c in FACTION_COLORS[h["faction"]]]
    ol = (42, 29, 61)
    skin = (253, 232, 220) if "red skin" not in h["body"] else (190, 60, 50)
    cx = W * (0.48 + rng.uniform(-0.04, 0.04))
    feet, crown = H * 0.95, H * 0.08
    hh = (feet - crown) / 7.2
    if "wings" in h["wings_tail"]:
        sp = rng.uniform(1.4, 1.75)
        d.polygon([(cx + 0.4 * hh, crown + 1.6 * hh), (cx + sp * hh, crown + 0.6 * hh), (cx + 1.3 * hh, crown + 3.6 * hh)],
                  fill=c3, outline=ol, width=4)
        d.polygon([(cx - 0.4 * hh, crown + 1.6 * hh), (cx - sp * hh, crown + 0.8 * hh), (cx - 1.2 * hh, crown + 3.5 * hh)],
                  fill=c3, outline=ol, width=4)
    d.ellipse([cx - 0.42 * hh, crown, cx + 0.42 * hh, crown + hh], fill=skin, outline=ol, width=4)
    d.rectangle([cx - 0.12 * hh, crown + 0.95 * hh, cx + 0.12 * hh, crown + 1.3 * hh], fill=skin, outline=ol, width=3)
    d.polygon([(cx - 0.75 * hh, crown + 1.3 * hh), (cx + 0.75 * hh, crown + 1.3 * hh), (cx + 0.95 * hh, crown + 4.0 * hh),
               (cx - 0.95 * hh, crown + 4.0 * hh)], fill=c1, outline=ol, width=4)
    for sx in (-1, 1):
        d.rectangle([cx + sx * 0.35 * hh - 0.14 * hh, crown + 4.0 * hh, cx + sx * 0.35 * hh + 0.14 * hh, feet],
                    fill=skin, outline=ol, width=4)
        d.line([(cx + sx * 0.75 * hh, crown + 1.4 * hh), (cx + sx * 1.05 * hh, crown + 3.4 * hh)], fill=c2, width=int(0.2 * hh))
    d.rectangle([cx - 0.9 * hh, crown + 2.6 * hh, cx + 0.9 * hh, crown + 2.75 * hh], fill=c2)
    try:
        from PIL import ImageFont
        f = ImageFont.load_default(size=max(16, W // 28))
    except Exception:  # noqa: BLE001
        f = None
    d.text((20, 20), "%s  %s  s%d" % (label, hero_id, seed), fill=(30, 30, 30), font=f)
    return im


# ------------------------------------------------------------------ crop-and-inpaint
def square_box(box, size, scale=1.0, min_side=64):
    """(x, y, w, h) -> a square (x0, y0, x1, y1) around its centre, `scale` times the longer side,
    clamped inside an image of `size`."""
    x, y, w, h = box
    side = int(round(max(w, h, min_side) * scale))
    side = min(side, size[0], size[1])
    cx, cy = x + w / 2, y + h / 2
    x0 = int(round(min(max(cx - side / 2, 0), size[0] - side)))
    y0 = int(round(min(max(cy - side / 2, 0), size[1] - side)))
    return x0, y0, x0 + side, y0 + side


def ellipse_mask(size, box, feather=6):
    """Full-size L mask, white ellipse inscribed in box (x, y, w, h), blurred by `feather` px."""
    m = Image.new("L", size, 0)
    x, y, w, h = box
    ImageDraw.Draw(m).ellipse([x, y, x + w, y + h], fill=255)
    return m.filter(ImageFilter.GaussianBlur(feather)) if feather else m


def crop_inpaint(client, s, image, crop, mask, positive, negative, seed, denoise, job, work_dir,
                 target=1024, grow=6, steps=None, feather=4, mode="noise_mask", timeout=900):
    """Inpaint `mask` (full-size L, white = repaint) of an RGB image by working on the square `crop`
    (x0, y0, x1, y1) upscaled to `target` px (SDXL-native detail), then pasting the result back
    through a feathered mask. Returns (new RGB image, info). In dry-run the crop passes through."""
    x0, y0, x1, y1 = crop
    side = x1 - x0
    src = image.crop(crop).resize((target, target), Image.LANCZOS)
    mcrop = mask.crop(crop).resize((target, target), Image.BILINEAR)
    os.makedirs(work_dir, exist_ok=True)
    stem = job.replace("/", "_")
    sp, mp = os.path.join(work_dir, stem + "_src.png"), os.path.join(work_dir, stem + "_mask.png")
    src.save(sp)
    Image.merge("RGB", [mcrop] * 3).save(mp)
    name_src = client.upload_image(sp, name=stem + "_src.png", subfolder=SERVER_SUBFOLDER)
    name_mask = client.upload_image(mp, name=stem + "_mask.png", subfolder=SERVER_SUBFOLDER)
    graph = workflows.inpaint(s, name_src, name_mask, positive, negative, seed, denoise,
                              "%s/%s" % (SERVER_SUBFOLDER, job), mode=mode, grow=grow, steps=steps)
    paths = client.run(graph, job, work_dir, timeout=timeout, names=[stem + "_out.png"])
    if paths:
        res = Image.open(paths[0]).convert("RGB")
    else:
        res = src
    back = res.resize((side, side), Image.LANCZOS)
    m_back = mask.crop(crop)
    if feather:
        m_back = m_back.filter(ImageFilter.GaussianBlur(feather))
    out = image.copy()
    out.paste(back, (x0, y0), m_back)
    return out, {"crop": [x0, y0, side, side], "job": job, "denoise": denoise, "seed": seed,
                 "server_output": paths[0] if paths else None, "graph": graph}


def skin_profile(bible, hero_id):
    return "red" if "red skin" in bible["heroes"][hero_id].get("body", "") else "light"


def flat_rgb(rgba, rgb):
    """Composite an RGBA image over a flat colour (SD needs RGB; the flat colour keeps cutouts clean)."""
    bg = Image.new("RGB", rgba.size, tuple(rgb))
    bg.paste(rgba, (0, 0), rgba)
    return bg


def stamp():
    return time.strftime("%Y-%m-%dT%H:%M:%S")
