#!/usr/bin/env python3
"""Splash cards: loading screens, promo and event art with one to three heroes on a faction scene.

    python tools/comfy/splash.py plates [--faction all|celestial|infernal|fallen] [--orient both|land|port] [--count 2]
        scenery plates (no humans) per faction, 16:9 (1344x768) and 9:16 (768x1344) + model hires,
        written to art_src/_splash/plates/<faction>_<orient>_s<seed>.png
    python tools/comfy/splash.py card <name> --plate <png> --heroes id:candidate.png[,id:candidate.png...]
                               [--orient land|port] [--denoise 0.28] [--no-finish]
        art_src/_splash/cards/<name>/:
          plate.png            the background at card size (1920x1080 or 1080x1920)
          hero_<n>_<id>.png    each hero cut out (RGBA, card size, already placed): the animation layers
          layout.json          card size, plate, each hero's file, box, scale and z order
          flat.png             plate + heroes, color-matched, with contact shadows
          card.png             flat.png after a light tiled repaint (one lighting pass over the whole card)

Consistency: one checkpoint and style for everything (the pinned model and data/art_prompts.json style),
one plate prompt per faction (PLATES), fixed layouts for 1, 2 and 3 heroes (LAYOUTS) and fixed seeds.
The layers are kept so the game can animate a card (parallax, breathing, light sweeps).
Every prompt passes prompts.enforce/check_text (plates are scenery: "no humans").
"""
import argparse
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

from PIL import Image, ImageFilter, ImageStat  # noqa: E402

import comfy  # noqa: E402
import pipeline as P  # noqa: E402
import prompts  # noqa: E402
import workflows  # noqa: E402

OUT = os.path.join(comfy.ROOT, "art_src", "_splash")
SIZES = {"land": (1344, 768), "port": (768, 1344)}
CARD = {"land": (1920, 1080), "port": (1080, 1920)}
PLATES = {
    "celestial": "scenery, sky, cumulus clouds, floating island, white marble and glass architecture, chrome spires, "
                 "waterfall, aqua water, sunlight, lens flare, bubble, frutiger aero, utopia, bright, wide shot",
    "infernal": "scenery, night, city, neon lights, red neon, hot pink neon, chrome, skyscraper, lava river, "
                "obsidian tower, red sky, reflections, wet street, cyberpunk, wide shot",
    "fallen": "scenery, dusk, purple sky, ruins, cathedral, broken halo monument, holographic, iridescent, cables, "
              "crt monitor, violet light, fog, glitch, wide shot",
}
PLATE_SEED = {"celestial": 900100, "infernal": 900200, "fallen": 900300}
# Hero boxes as fractions of the card: (center x, feet y, height). Later heroes are drawn in front.
LAYOUTS = {
    "land": {1: [(0.66, 1.08, 1.12)],
             2: [(0.36, 1.08, 1.10), (0.68, 1.10, 1.14)],
             3: [(0.22, 1.08, 1.02), (0.78, 1.08, 1.02), (0.50, 1.12, 1.16)]},
    "port": {1: [(0.50, 1.04, 0.92)],
             2: [(0.34, 1.04, 0.86), (0.66, 1.06, 0.92)],
             3: [(0.24, 1.00, 0.76), (0.76, 1.00, 0.76), (0.50, 1.06, 0.90)]},
}


def _settings(bible, client, size):
    a = P.add_common_args(argparse.ArgumentParser()).parse_args(
        ["--size", "%dx%d" % size, "--hires-mode", "model"])
    return P.resolve_settings(bible, a, client)


def _negative(bible, fam, characters):
    n = bible["negative"]
    g = bible["gender"]["female"]["negative"]
    if characters:              # several women on one card: drop only "multiple girls"
        g = prompts.join_tags(*[t for t in prompts.split_tags(g) if prompts.norm_tag(t) != "multiple girls"])
    parts = [fam.get("quality_negative", ""), fam.get("rating_negative", ""), n["quality"], n["anatomy"],
             n["explicit"], n["childlike"], n["text"], n["style"], g]
    if not characters:
        parts.append("1girl, 1boy, people, person, character")
    return prompts.join_tags(*parts)


def cmd_plates(a):
    bible = prompts.load_bible()
    client = comfy.Comfy(timeout=60, verbose=False)
    out = os.path.join(OUT, "plates")
    os.makedirs(out, exist_ok=True)
    factions = list(PLATES) if a.faction == "all" else [a.faction]
    orients = ["land", "port"] if a.orient == "both" else [a.orient]
    for f in factions:
        for o in orients:
            s, disc, oi = _settings(bible, client, SIZES[o])
            fam = prompts.family_block(bible, s["family"])
            pos = prompts.join_tags(fam.get("quality", ""), "no humans", PLATES[f], bible["style"]["tags"])
            neg = _negative(bible, fam, characters=False)
            probs = prompts.check_text(bible, pos, neg)
            if probs:
                raise P.PipelineError("plate prompt for %s: %s" % (f, probs))
            for i in range(a.count):
                seed = PLATE_SEED[f] + (0 if o == "land" else 50) + i
                name = "%s_%s_s%d" % (f, o, seed)
                if os.path.exists(os.path.join(out, name + ".png")):
                    continue
                g = workflows.txt2img(s, pos, neg, seed, "%s/splash/%s" % (P.SERVER_SUBFOLDER, name))
                got = client.run(g, "splash/" + name, out, timeout=900, names=[name + ".png"])
                P.write_json(os.path.join(out, name + ".json"), {"faction": f, "orient": o, "seed": seed,
                                                                 "prompt": pos, "negative": neg,
                                                                 "settings": P.settings_for_meta(s)})
                print("plate", P.rel(got[0]), flush=True)


def _cutout(client, rec, oi, src, work):
    stem = os.path.splitext(os.path.basename(src))[0]
    name = client.upload_image(src, subfolder=P.SERVER_SUBFOLDER)
    g = workflows.remove_background(rec, name, "%s/splash/mask_%s" % (P.SERVER_SUBFOLDER, stem), oi)
    got = client.run(g, "splash/mask_" + stem, work, timeout=300, names=["mask_%s.png" % stem])
    img = Image.open(src).convert("RGB")
    mask = Image.open(got[0]).convert("L").resize(img.size)
    rgba = img.copy()
    rgba.putalpha(mask)
    box = mask.point(lambda v: 255 if v > 24 else 0).getbbox()
    return rgba.crop(box) if box else rgba


def _match(fig, plate_region, k=0.25):
    """Pull the figure's mean colour a little toward the plate behind it (simple relight)."""
    rgb = fig.convert("RGB")
    a = fig.getchannel("A")
    fm = ImageStat.Stat(rgb, a).mean
    pm = ImageStat.Stat(plate_region.convert("RGB")).mean
    bands = []
    for i, b in enumerate(rgb.split()):
        shift = (pm[i] - fm[i]) * k
        bands.append(b.point(lambda v, s=shift: max(0, min(255, int(v + s)))))
    out = Image.merge("RGB", bands)
    out.putalpha(a)
    return out


def cmd_card(a):
    bible = prompts.load_bible()
    client = comfy.Comfy(timeout=60, verbose=False)
    disc = client.discover()
    oi = client.object_info_cache
    rec = (disc.get("recommended") or {}).get("rembg")
    if not rec:
        raise P.PipelineError("no background-removal node on the server")
    cdir = os.path.join(OUT, "cards", a.name)
    work = os.path.join(cdir, "work")
    os.makedirs(work, exist_ok=True)
    W, H = CARD[a.orient]
    plate = Image.open(a.plate).convert("RGB")
    k = max(W / plate.width, H / plate.height)
    plate = plate.resize((int(plate.width * k + 0.5), int(plate.height * k + 0.5)), Image.LANCZOS)
    left, top = (plate.width - W) // 2, (plate.height - H) // 2
    plate = plate.crop((left, top, left + W, top + H))
    plate.save(os.path.join(cdir, "plate.png"))
    heroes = [x.split(":", 1) for x in a.heroes.split(",")]
    slots = LAYOUTS[a.orient][len(heroes)]
    flat = plate.copy().convert("RGBA")
    layout = {"size": [W, H], "orient": a.orient, "plate": "plate.png", "heroes": []}
    # draw the back heroes first (the layout lists the front one last)
    for z, ((hid, src), (cx, fy, hh)) in enumerate(zip(heroes, slots)):
        fig = _cutout(client, rec, oi, src, work)
        scale = hh * H / fig.height
        fig = fig.resize((max(1, int(fig.width * scale)), max(1, int(fig.height * scale))), Image.LANCZOS)
        x, y = int(cx * W - fig.width / 2), int(fy * H - fig.height)
        region = plate.crop((max(0, x), max(0, y), min(W, x + fig.width), min(H, y + fig.height)))
        fig = _match(fig, region if region.width and region.height else plate)
        shadow = Image.new("RGBA", fig.size, (0, 0, 0, 0))
        sa = fig.getchannel("A").point(lambda v: int(v * 0.45))
        shadow.putalpha(sa.filter(ImageFilter.GaussianBlur(18)))
        flat.alpha_composite(shadow, (x + 14, y + 10)) if x + 14 >= 0 and y + 10 >= 0 else None
        layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        layer.paste(fig, (x, y), fig)
        fn = "hero_%d_%s.png" % (z, hid)
        layer.save(os.path.join(cdir, fn))
        flat.alpha_composite(layer)
        layout["heroes"].append({"id": hid, "file": fn, "source": P.rel(src), "z": z,
                                 "box": [x, y, fig.width, fig.height], "scale": round(scale, 4)})
        print("layer", fn, flush=True)
    flat = flat.convert("RGB")
    flat.save(os.path.join(cdir, "flat.png"))
    P.write_json(os.path.join(cdir, "layout.json"), layout)
    if a.no_finish:
        return
    s, _, _ = _settings(bible, client, SIZES[a.orient])
    s = dict(s, upscale_model=s.get("upscale_model") or "4x-AnimeSharp.safetensors")
    fam = prompts.family_block(bible, s["family"])
    n = len(heroes)
    who = {1: "1girl, solo", 2: "2girls", 3: "3girls, multiple girls"}[n]
    names = ", ".join(sorted({bible["heroes"][h]["faction"] for h, _ in heroes}))
    pos = prompts.join_tags(fam.get("quality", ""), fam.get("rating", ""), who, "adult",
                            "cowboy shot", PLATES[bible["heroes"][heroes[0][0]]["faction"]].replace("no humans, ", ""),
                            bible["style"]["tags"], "key visual, promotional art")
    neg = _negative(bible, fam, characters=True)
    probs = prompts.check_text(bible, pos, neg, gender="female")
    if probs:
        raise P.PipelineError("card prompt: %s (factions %s)" % (probs, names))
    name = client.upload_image(os.path.join(cdir, "flat.png"), subfolder=P.SERVER_SUBFOLDER)
    g = workflows.tiled_upscale(s, name, pos, neg, 777, "%s/splash/%s_card" % (P.SERVER_SUBFOLDER, a.name), oi,
                                scale=1.0, denoise=a.denoise)
    client.run(g, "splash/%s_card" % a.name, cdir, timeout=1800, names=["card.png"])
    layout["finish"] = {"denoise": a.denoise, "prompt": pos, "negative": neg}
    P.write_json(os.path.join(cdir, "layout.json"), layout)
    print("card", P.rel(os.path.join(cdir, "card.png")), flush=True)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("plates")
    p.add_argument("--faction", default="all", choices=["all"] + list(PLATES))
    p.add_argument("--orient", default="both", choices=["both", "land", "port"])
    p.add_argument("--count", type=int, default=2)
    c = sub.add_parser("card")
    c.add_argument("name")
    c.add_argument("--plate", required=True)
    c.add_argument("--heroes", required=True, help="id:candidate.png[,id:candidate.png...] (1 to 3)")
    c.add_argument("--orient", default="land", choices=["land", "port"])
    c.add_argument("--denoise", type=float, default=0.28)
    c.add_argument("--no-finish", action="store_true")
    a = ap.parse_args(argv)
    try:
        if a.cmd == "plates":
            cmd_plates(a)
        else:
            if not 1 <= len(a.heroes.split(",")) <= 3:
                raise P.PipelineError("a card has 1 to 3 heroes")
            cmd_card(a)
    except (P.PipelineError, comfy.ComfyError, prompts.ContentRuleError, workflows.WorkflowError) as e:
        print("ERROR: %s" % e, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
