#!/usr/bin/env python3
"""Generate full-body candidates for one hero and a contact sheet to choose from.

    python3 tools/comfy/run_hero.py <hero_id> [--count N] [--seed S] [--dry-run] [model/sampler flags]

Seeds are seed_base (data/art_prompts.json) + 0..N-1 unless --seed S is given (S, S+1, ...).
Writes to art_src/<id>/candidates/ (art_src/_dryrun/<id>/ with --dry-run):
    <id>_s<seed>.png         the candidate (flat background, ~1152x2016 after hires fix)
    <id>_s<seed>.json        metadata: prompt, negative, seed, checkpoint, family, every setting
    <id>_s<seed>.api.json    the exact API graph (live runs: re-send with comfy.py queue <file>)
    <id>_s<seed>_cut.png     automatic cutout check (over checker / magenta / dark)
    contact_sheet.png        all candidates of this hero, labelled with seeds and check flags, with face crops
Check flags on the sheet: CROP:top/bottom/left/right (figure touches the frame: head, feet or wings
cut), EDGE n% (outline melts into the background: change --background), BG? (background not the
flat colour asked for), FILL n% (a scene instead of a flat background). Unflagged is not approved:
the content rules and the art still need a person's eye (docs/dev/art-style.md sections 1 and 7).
Existing candidates with the same seed are kept unless --force; the seed finalize.py used as the
master is never overwritten (its copy also lives in final/<id>_source.png).

Next: pick one from the sheet, then  python3 tools/comfy/finalize.py <id> <seed>
"""
import argparse
import glob
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

from PIL import Image  # noqa: E402

import comfy  # noqa: E402
import pipeline as P  # noqa: E402
import post  # noqa: E402
import prompts  # noqa: E402
import workflows  # noqa: E402


def candidate_paths(cdir, hero_id):
    out = []
    for p in sorted(glob.glob(os.path.join(cdir, "%s_s*.png" % hero_id))):
        stem = os.path.basename(p)[len(hero_id) + 2:-4]
        if stem.isdigit():
            out.append((int(stem), p))
    return sorted(out)


def sheet_label(seed, png):
    flags = ((P.read_json(png[:-4] + ".json", {}) or {}).get("check") or {}).get("flags") or []
    return ("s%d  %s" % (seed, " ".join(flags))).strip()


def protected_seeds(hero_id, dry_run):
    """Seeds that finalize.py used as a master (never re-rendered over)."""
    fm = P.read_json(os.path.join(P.hero_dir(hero_id, dry_run), "final", hero_id + ".json"), {}) or {}
    return {int(fm["candidate_seed"])} if fm.get("candidate_seed") is not None else set()


def build_sheet(cdir, hero_id, per_sheet=12, log=print):
    cands = candidate_paths(cdir, hero_id)
    sheets = []
    for k in range(0, len(cands), per_sheet):
        chunk = cands[k:k + per_sheet]
        name = "contact_sheet.png" if k == 0 else "contact_sheet_%d.png" % (k // per_sheet + 1)
        path = os.path.join(cdir, name)
        post.contact_sheet([(p, sheet_label(seed, p)) for seed, p in chunk], path, cols=4,
                           title="%s candidates (%d-%d of %d): pick a seed" % (hero_id, k + 1, k + len(chunk), len(cands)))
        sheets.append(path)
        log("contact sheet: %s" % P.rel(path))
    return sheets


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("hero")
    ap.add_argument("--count", type=int, default=6)
    ap.add_argument("--seed", type=int, help="first seed (default: the hero's seed_base)")
    ap.add_argument("--force", action="store_true", help="re-render seeds that already exist")
    ap.add_argument("--background", choices=["grey", "white", "green"], help="override the hero's flat background")
    ap.add_argument("--extra-tags", default="", help="extra positive tags for this run (checked by the content rules)")
    ap.add_argument("--ref", help="reference image for IPAdapter (used only if the server has ComfyUI_IPAdapter_plus)")
    ap.add_argument("--ref-weight", type=float, default=0.7)
    ap.add_argument("--controlnet", help="ControlNet model name (core ControlNetLoader)")
    ap.add_argument("--control-image", help="prepared control image (pose/lineart) for --controlnet")
    ap.add_argument("--control-strength", type=float, default=0.6)
    ap.add_argument("--no-sheet", action="store_true")
    ap.add_argument("--no-cutout-check", action="store_true", help="skip the automatic cutout/framing check")
    P.add_common_args(ap)
    a = ap.parse_args(argv)
    log = (lambda *x: None) if a.quiet else print
    try:
        bible = prompts.load_bible()
        if a.hero not in bible["heroes"]:
            raise P.PipelineError("unknown hero %r. Heroes: %s" % (a.hero, ", ".join(bible["heroes"])))
        client = P.make_client(a)
        s, disc, oi = P.resolve_settings(bible, a, client, a.hero)
        pr = prompts.full_body(bible, a.hero, s["family"], background_key=a.background, extra_tags=a.extra_tags)
        bg_key, bg = prompts.background(bible, a.hero, a.background)
        h = bible["heroes"][a.hero]
        first = a.seed if a.seed is not None else int(h["seed_base"])
        seeds = [first + i for i in range(max(1, a.count))]
        if a.force:
            clash = sorted(protected_seeds(a.hero, a.dry_run) & set(seeds))
            if clash:
                raise P.PipelineError("seed %s is the master of final/%s.png; --force would overwrite it. Pick "
                                      "other seeds (--seed N) or archive the final first (finalize.py --force "
                                      "with another candidate)" % (", ".join(map(str, clash)), a.hero))
        for side in ("positive", "negative"):
            st = pr["stats"][side]
            if st["chunks"] > (2 if side == "positive" else 3):
                log("warning: %s prompt is ~%d tokens (%d CLIP chunks); tags after the first chunks get diluted. "
                    "Trim --extra-tags or the hero's tags." % (side, st["tokens"], st["chunks"]))
        hdir = P.hero_dir(a.hero, a.dry_run)
        cdir = os.path.join(hdir, "candidates")
        os.makedirs(cdir, exist_ok=True)
        log("%s: %d candidate(s), seeds %d..%d, checkpoint %s (%s), %dx%d -> %dx%d, %s/%s %d steps cfg %s" % (
            a.hero, len(seeds), seeds[0], seeds[-1], s["checkpoint"], s["family"], s["width"], s["height"],
            *P.output_size(s), s["sampler"], s["scheduler"], s["steps"], s["cfg"]))

        ipadapter = controlnet = None
        if a.ref:
            if oi and s["ipadapter"]:
                ipadapter = {"image": client.upload_image(a.ref, name="%s_ref.png" % a.hero, subfolder=P.SERVER_SUBFOLDER),
                             "weight": a.ref_weight, "start_at": 0.0, "end_at": 0.85, "preset": "PLUS (high strength)"}
            else:
                log("warning: --ref ignored (IPAdapter nodes not found on the server%s)" % (
                    "; dry run without cached discovery" if a.dry_run and not oi else ""))
        if a.controlnet:
            if not a.control_image:
                raise P.PipelineError("--controlnet needs --control-image")
            if disc and a.controlnet not in (disc.get("controlnets") or []):
                raise P.PipelineError("ControlNet %r is not on the server" % a.controlnet)
            controlnet = {"model": a.controlnet, "strength": a.control_strength, "start": 0.0, "end": 0.8,
                          "image": client.upload_image(a.control_image, name="%s_control.png" % a.hero,
                                                       subfolder=P.SERVER_SUBFOLDER)}

        jobs = []
        for seed in seeds:
            png = os.path.join(cdir, "%s_s%d.png" % (a.hero, seed))
            if os.path.exists(png) and not a.force:
                log("  s%d exists, skipping (--force to redo)" % seed)
                continue
            graph = workflows.txt2img(s, pr["positive"], pr["negative"], seed,
                                      "%s/%s/%s_s%d" % (P.SERVER_SUBFOLDER, a.hero, a.hero, seed),
                                      ipadapter=ipadapter, controlnet=controlnet, object_info=oi)
            job = "%s/txt2img_s%d" % (a.hero, seed)
            pid = client.queue(graph, job)
            P.write_json(os.path.join(cdir, "%s_s%d.api.json" % (a.hero, seed)), {"prompt": graph})
            jobs.append((seed, pid, png, graph))
        if jobs and not a.dry_run:
            log("queued %d job(s) on %s" % (len(jobs), client.url))
        for seed, pid, png, graph in jobs:
            if a.dry_run:
                P.placeholder_figure(bible, a.hero, seed, P.output_size(s)).save(png)
                server_file = None
            else:
                entry = client.wait(pid, timeout=a.timeout)
                imgs = comfy.history_images(entry)
                if not imgs:
                    raise P.PipelineError("job %s finished without an image" % pid)
                client.download(imgs[-1], png)
                server_file = imgs[-1]
                im = Image.open(png)
                log("  s%d -> %s (%dx%d)" % (seed, P.rel(png), im.width, im.height))
            check = None
            if not a.no_cutout_check:
                cut, check = post.candidate_report(Image.open(png), bg["rgb"])
                post.cutout_preview(cut, 600).save(png[:-4] + "_cut.png")
                if check["flags"]:
                    log("  s%d check: %s" % (seed, " ".join(check["flags"])))
            meta = {
                "hero": a.hero, "seed": seed, "image": os.path.basename(png), "created": P.stamp(),
                "dry_run": a.dry_run, "prompt": pr["positive"], "negative": pr["negative"],
                "prompt_stats": pr["stats"], "brief": h["natural"], "check": check,
                "background": {"key": bg_key, "rgb": bg["rgb"]},
                "settings": P.settings_for_meta(s), "ipadapter_ref": a.ref if ipadapter else None,
                "controlnet": controlnet, "prompt_id": pid, "server_file": server_file,
                "server": client.url or None, "bible_version": bible.get("version"),
                "api_graph": os.path.basename(png)[:-4] + ".api.json",
            }
            P.write_json(png[:-4] + ".json", meta)
        if a.dry_run and jobs:
            log("dry run: API JSON in %s" % P.rel(os.path.join(comfy.dryrun_dir(), a.hero)))
        if not a.no_sheet:
            build_sheet(cdir, a.hero, log=log)
        log("next: review the contact sheet, then  python3 tools/comfy/finalize.py %s <seed>%s" % (
            a.hero, " --dry-run" if a.dry_run else ""))
    except (P.PipelineError, comfy.ComfyError, prompts.ContentRuleError, prompts.PromptError, workflows.WorkflowError,
            KeyError) as e:
        print("ERROR: %s" % e, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
