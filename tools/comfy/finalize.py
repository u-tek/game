#!/usr/bin/env python3
"""Turn a chosen candidate into the delivery image (docs/dev/art-style.md section 2).

    python3 tools/comfy/finalize.py <hero_id> <seed | candidate.png> [--skin SKIN] [--dry-run] [options]

Steps (server steps are skipped/passed through in --dry-run, which still writes their API JSON):
  1. optional full-image img2img polish (--refine-denoise 0.25-0.35)
  2. face polish: crop the face, inpaint it at 1024 px with low denoise (0.35), paste back
     (face box: --face-box x,y,w,h in candidate pixels, else auto-estimated)
  3. optional 2x upscale with the server's upscale model (default on when one exists)
  4. background removal: the server's background-removal node if discovered (--cutout server|auto),
     else local flood fill with edge unmixing (post.py)
  5. trim and place on the 1024x2048 canvas (crown y=108, soles y=1990, axis x=512), --flip to
     face right; portrait crop; review previews; meta JSON with face box and warp_src hints

Outputs in art_src/<id>/final/: <id>.png, <id>_portrait.png, <id>_check.png (cutout over checker /
magenta / dark), <id>_boxes.png (face + portrait boxes), <id>.json (with sha256 of the image and of
its source), <id>_source.png/.json (a copy of the chosen candidate: the master is never lost), plus
work files in work/.
--skin <skin id> (bible "skins", e.g. imra_lucky_ember or lucky_ember) finalizes a skin candidate from
art_src/<id>/skins/<art>/candidates/ into art_src/<id>/skins/<art>/final/<art>.* instead (the repaint
passes use the skin's prompt; the face keeps the hero's identity).

An existing final is never overwritten silently: without --force the run stops. With --force the
old final/, variants/ and masks/ move to art_src/<id>/history/<timestamp>/ (variants made from the
old final would no longer line up with the new one, so they go too).
Next: python3 tools/comfy/variants.py <id>
"""
import argparse
import os
import shutil
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


def find_candidate(target, spec):
    if os.path.exists(spec):
        return os.path.abspath(spec)
    if str(spec).lstrip("s").isdigit():
        p = os.path.join(target["dir"], "candidates", "%s_s%s.png" % (target["hero"], str(spec).lstrip("s")))
        if os.path.exists(p):
            return p
        raise P.PipelineError("no candidate %s (run run_hero.py %s%s first)" % (
            P.rel(p), target["hero"], " --skin " + target["skin"] if target["skin"] else ""))
    raise P.PipelineError("candidate %r not found" % spec)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("hero")
    ap.add_argument("candidate", help="seed number (from the contact sheet) or an image path")
    ap.add_argument("--face-box", help="x,y,w,h of the face (brow/hairline to chin) in candidate pixels")
    ap.add_argument("--no-face-refine", action="store_true")
    ap.add_argument("--face-denoise", type=float)
    ap.add_argument("--refine-denoise", type=float, default=0.0, help="full-image img2img polish (0 = off)")
    ap.add_argument("--upscale", choices=["auto", "on", "off", "tiled"], default="auto",
                    help="2x upscale: tiled = upscale model then a tiled low-denoise re-draw with the checkpoint "
                         "(needs the UltimateSDUpscale node); on = upscale model (or lanczos) only; auto = tiled "
                         "when the server has the node and an upscale model, else on when it has an upscale model")
    ap.add_argument("--tiled-denoise", type=float, help="--upscale tiled: denoise per tile (default %.2f)"
                    % workflows.TILED_DEFAULTS["denoise"])
    ap.add_argument("--cutout", choices=["auto", "local", "server"], default="auto")
    ap.add_argument("--tol", type=float, default=26.0, help="local cutout colour tolerance")
    ap.add_argument("--no-holes", action="store_true", help="local cutout: don't clear enclosed background")
    ap.add_argument("--feet-y", type=int, help="soles y in candidate pixels (if a cape/tail hangs lower)")
    ap.add_argument("--flip", action="store_true", help="mirror so the figure faces screen right")
    ap.add_argument("--seed", type=int, help="seed for the polish passes (default: candidate seed + 7)")
    ap.add_argument("--force", action="store_true",
                    help="replace an existing final: archive final/, variants/, masks/ to history/<timestamp>/")
    ap.add_argument("--skin", help="skin id (bible 'skins'): finalize that skin's candidate into "
                                   "art_src/<id>/skins/<art>/final/")
    P.add_common_args(ap)
    a = ap.parse_args(argv)
    log = (lambda *x: None) if a.quiet else print
    try:
        bible = prompts.load_bible()
        t = P.art_target(bible, a.hero, a.skin, a.dry_run, adult=a.adult)
        name, job = t["name"], t["job"]
        src_path = find_candidate(t, a.candidate)
        cmeta = P.read_json(src_path[:-4] + ".json", {}) or {}
        if "skin" in cmeta and (cmeta["skin"] or None) != t["skin"]:     # run_hero records it
            raise P.PipelineError("%s was rendered for %s, not %s: pass %s" % (
                P.rel(src_path), "skin " + cmeta["skin"] if cmeta.get("skin") else "the base look",
                "skin " + t["skin"] if t["skin"] else "the base look",
                "--skin " + cmeta["skin"] if cmeta.get("skin") else "no --skin"))
        if bool(cmeta.get("adult")) != bool(a.adult):
            raise P.PipelineError("%s was rendered for the %s look: finalize it %s, or re-run run_hero.py %s"
                                  % (P.rel(src_path), "adult (nude)" if cmeta.get("adult") else "tame",
                                     "with --adult" if a.adult else "without --adult",
                                     "without --adult" if a.adult else "with --adult"))
        hdir = t["dir"]
        final_png = os.path.join(hdir, "final", name + ".png")
        if os.path.abspath(src_path).startswith(os.path.abspath(os.path.join(hdir, "final")) + os.sep):
            raise P.PipelineError("%s is a finalize output; finalize a candidate (or a fix.py _fixed.png)"
                                  % P.rel(src_path))
        if os.path.exists(final_png) and not a.force:
            old = P.read_json(final_png[:-4] + ".json", {}) or {}
            raise P.PipelineError(
                "%s already exists (from %s, %s). Its variants and the rig are built on it. To replace it, re-run "
                "with --force: final/, variants/ and masks/ are archived to %s/history/<timestamp>/ first."
                % (P.rel(final_png), old.get("source_candidate", "?"), old.get("created", "?"), P.rel(hdir)))
        src_sha = P.sha256_file(src_path)
        client = P.make_client(a)
        P.inherit_model(a, cmeta, "the candidate", log)      # polish with the model that made it
        s, disc, oi = P.resolve_settings(bible, a, client, a.hero)
        bg_key, bg = prompts.background(bible, a.hero, (cmeta.get("background") or {}).get("key"))
        work = os.path.join(hdir, "work")
        seed = a.seed if a.seed is not None else int(cmeta.get("seed", t["seed_base"])) + 7
        img = Image.open(src_path)
        img = P.flat_rgb(img, bg["rgb"]) if img.mode == "RGBA" else img.convert("RGB")
        steps_done = []
        log("finalize %s from %s (%dx%d), checkpoint %s" % (t["label"], P.rel(src_path), img.width, img.height, s["checkpoint"]))

        # 1. optional full-image polish
        if a.refine_denoise and a.refine_denoise > 0:
            pr = prompts.full_body(bible, a.hero, s["family"], background_key=bg_key, skin=t["skin"], adult=a.adult)
            p = os.path.join(work, "%s_refine_src.png" % name)
            os.makedirs(work, exist_ok=True)
            img.save(p)
            sname = client.upload_image(p, subfolder=P.SERVER_SUBFOLDER)
            g = workflows.img2img(s, sname, pr["positive"], pr["negative"], seed, a.refine_denoise,
                                  "%s/%s/refine_s%d" % (P.SERVER_SUBFOLDER, job, seed))
            out = client.run(g, "%s/refine_s%d" % (job, seed), work, timeout=a.timeout,
                             names=["%s_refine_out.png" % name])
            if out:
                img = Image.open(out[0]).convert("RGB")
            steps_done.append({"step": "img2img", "denoise": a.refine_denoise, "seed": seed})

        # 1b. hires 1.5x for a base-size candidate (the MOSS family renders candidates without it)
        hz = s.get("hires") or {}
        src_scale = 1.0
        if s.get("final_hires") and not a.no_hires and img.width <= s["width"] + 8 and img.height <= s["height"] + 8:
            pr = prompts.full_body(bible, a.hero, s["family"], background_key=bg_key, skin=t["skin"], adult=a.adult)
            p = os.path.join(work, "%s_hires_src.png" % name)
            os.makedirs(work, exist_ok=True)
            img.save(p)
            sname = client.upload_image(p, subfolder=P.SERVER_SUBFOLDER)
            den = float(hz.get("denoise", 0.4))
            g = workflows.img2img(s, sname, pr["positive"], pr["negative"], seed, den,
                                  "%s/%s/hires_s%d" % (P.SERVER_SUBFOLDER, job, seed),
                                  scale_by=float(hz.get("scale", 1.5)), steps=hz.get("steps"))
            out = client.run(g, "%s/hires_s%d" % (job, seed), work, timeout=a.timeout, names=["%s_hires_out.png" % name])
            if out:
                hi = Image.open(out[0]).convert("RGB")
            else:       # dry run: stand in with a plain resize
                f = float(hz.get("scale", 1.5))
                hi = img.resize((int(round(img.width * f)), int(round(img.height * f))), Image.LANCZOS)
            src_scale = hi.width / float(img.width)
            img = hi
            if a.feet_y:
                a.feet_y = int(round(a.feet_y * src_scale))
            steps_done.append({"step": "hires", "scale": round(src_scale, 4), "denoise": den, "steps": hz.get("steps"),
                               "seed": seed})

        # 2. face polish
        user_box = post.parse_box(a.face_box)
        if user_box and src_scale != 1.0:      # --face-box is in candidate pixels
            user_box = [int(round(v * src_scale)) for v in user_box]
        if user_box:
            face_box, conf = user_box, "user"
        else:
            quick, _ = post.remove_background(img, holes=False, feather=0)
            face_box, conf = post.estimate_face_box(quick, P.skin_profile(bible, a.hero))
        log("face box %s (%s)%s" % (",".join(map(str, face_box)), conf,
                                    "" if conf == "user" else "  -> check final/%s_boxes.png; override with --face-box" % name))
        if not a.no_face_refine:
            pr = prompts.face(bible, a.hero, s["family"], background_key=bg_key, skin=t["skin"], adult=a.adult)
            fr = bible["regions"]["face"]
            mbox = post.region_box(face_box, fr)
            mask = P.ellipse_mask(img.size, mbox, feather=max(3, face_box[3] // 30))
            crop = P.square_box(face_box, img.size, scale=1.8)
            den = a.face_denoise if a.face_denoise is not None else bible["face_refine"]["denoise"]
            img, info = P.crop_inpaint(client, s, img, crop, mask, pr["positive"], pr["negative"], seed, den,
                                       "%s/face_refine_s%d" % (job, seed), work, timeout=a.timeout)
            steps_done.append({"step": "face_refine", "denoise": den, "seed": seed, "crop": info["crop"]})

        # 3. upscale
        use_up = a.upscale in ("on", "tiled") or (a.upscale == "auto" and s.get("upscale_model"))
        tiled = None
        if a.upscale == "auto" and s.get("final_upscale"):
            a.upscale = s["final_upscale"]      # the family's own choice (MOSS: "on", the plain model 2x)
            use_up = a.upscale in ("on", "tiled")
        if a.upscale == "auto" and s.get("upscale_model") and oi and "UltimateSDUpscale" in oi:
            a.upscale = "tiled"     # the A/B winner (docs/dev/status.md, 2026-10-17)
        if a.upscale == "tiled":
            if not s.get("upscale_model"):
                raise P.PipelineError("--upscale tiled needs an upscale model on the server")
            if oi and "UltimateSDUpscale" not in oi:
                raise P.PipelineError("--upscale tiled needs the UltimateSDUpscale node (ComfyUI_UltimateSDUpscale)")
            tiled = {"denoise": a.tiled_denoise if a.tiled_denoise is not None
                     else workflows.TILED_DEFAULTS["denoise"], "seed": seed}
        if use_up:
            p = os.path.join(work, "%s_up_src.png" % name)
            os.makedirs(work, exist_ok=True)
            img.save(p)
            sname = client.upload_image(p, subfolder=P.SERVER_SUBFOLDER)
            if tiled:
                pr = prompts.full_body(bible, a.hero, s["family"], background_key=bg_key, skin=t["skin"], adult=a.adult)
                g = workflows.tiled_upscale(s, sname, pr["positive"], pr["negative"], seed,
                                            "%s/%s/upscale" % (P.SERVER_SUBFOLDER, job), oi, scale=2.0,
                                            denoise=tiled["denoise"])
            else:
                g = workflows.upscale(s, sname, "%s/%s/upscale" % (P.SERVER_SUBFOLDER, job), scale=2.0)
            out = client.run(g, "%s/upscale" % job, work, timeout=a.timeout, names=["%s_up.png" % name])
            factor = 2.0
            if out:
                up = Image.open(out[0]).convert("RGB")
                factor = up.width / img.width
                img = up
            else:
                img = img.resize((img.width * 2, img.height * 2), Image.LANCZOS)
            face_box = [int(round(v * factor)) for v in face_box]
            if a.feet_y:
                a.feet_y = int(round(a.feet_y * factor))
            steps_done.append({"step": "upscale", "model": s.get("upscale_model") or "lanczos", "factor": factor,
                               **({"tiled": tiled} if tiled else {})})

        # 4. background removal
        mask_img = None
        rec = s.get("rembg")
        if a.cutout == "server" and not rec:
            raise P.PipelineError("--cutout server: no background-removal node on the server")
        if a.cutout in ("auto", "server") and rec and oi:
            p = os.path.join(work, "%s_cut_src.png" % name)
            os.makedirs(work, exist_ok=True)
            img.save(p)
            sname = client.upload_image(p, subfolder=P.SERVER_SUBFOLDER)
            g = workflows.remove_background(rec, sname, "%s/%s/mask" % (P.SERVER_SUBFOLDER, job), oi)
            out = client.run(g, "%s/rembg" % job, work, timeout=a.timeout, names=["%s_mask.png" % name])
            if out:
                mask_img = Image.open(out[0])
            steps_done.append({"step": "cutout", "method": rec["class"]})
        else:
            steps_done.append({"step": "cutout", "method": "local flood fill"})

        # 5. place, portrait, previews, meta (server work is done: only now touch the old final)
        final_dir = os.path.join(hdir, "final")
        if os.path.exists(final_dir):
            P.archive(hdir, ["final", "variants", "masks"], log=log,
                      reason="finalize.py --force %s %s at %s" % (t["label"], a.candidate, P.stamp()))
        meta = post.finalize_local(
            name, img, final_dir, face_box=face_box, face_source=conf, skin_profile=P.skin_profile(bible, a.hero),
            bg=None, mask=mask_img, feet_y_src=a.feet_y,
            tol=a.tol, holes=not a.no_holes, flip=a.flip,
            extra_meta={"hero": a.hero, "skin": t["skin"], "art": t["art"] or None, "adult": bool(a.adult),
                        "source_candidate": P.rel(src_path), "candidate_seed": cmeta.get("seed"),
                        "source_sha256": src_sha, "source_copy": name + "_source.png",
                        "polish_seed": seed, "steps": steps_done, "settings": P.settings_for_meta(s),
                        "created": P.stamp(), "dry_run": a.dry_run})
        # keep the master: candidates/*.png are git-ignored and can be re-rendered over
        shutil.copyfile(src_path, os.path.join(final_dir, name + "_source.png"))
        for ext in (".json", ".api.json"):
            if os.path.exists(src_path[:-4] + ext):
                shutil.copyfile(src_path[:-4] + ext, os.path.join(final_dir, name + "_source" + ext))
        meta["sha256"] = P.sha256_file(os.path.join(final_dir, name + ".png"))
        P.write_json(os.path.join(final_dir, name + ".json"), meta)
        for n in meta["transform"]["notes"]:
            log("note: %s" % n)
        log("final: %s  (figure %.0f px tall, head ~%d px, face box %s)" % (
            P.rel(os.path.join(final_dir, name + ".png")), meta["transform"]["figure_h"], meta["head_px_estimate"],
            ",".join(map(str, meta["face_box"]))))
        log("review: %s and %s" % (P.rel(os.path.join(final_dir, name + "_check.png")),
                                   P.rel(os.path.join(final_dir, name + "_boxes.png"))))
        log("next: python3 tools/comfy/variants.py %s%s%s%s" % (a.hero, " --skin " + t["skin"] if t["skin"] else "",
                                                                 " --adult" if a.adult else "",
                                                                 " --dry-run" if a.dry_run else ""))
    except (P.PipelineError, comfy.ComfyError, prompts.ContentRuleError, workflows.WorkflowError, ValueError) as e:
        print("ERROR: %s" % e, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
