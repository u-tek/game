# art_src: generated art sources (not shipped)

Outputs of the ComfyUI pipeline in `tools/comfy/` (guide: `docs/dev/art-generation.md`).
Godot ignores this folder (`.gdignore`); approved art is copied to `assets/art/heroes/<id>/`
by `tools/comfy/install.py`.

```
art_src/
  _server/discovery.json, object_info.json   last `comfy.py discover` (git-ignored)
  _dryrun/<id>/...                            --dry-run output: API JSON + labelled placeholders (git-ignored)
  _downloads/                                 `comfy.py queue` downloads (git-ignored)
  <id>/
    candidates/<id>_s<seed>.png               txt2img candidates (PNG git-ignored, metadata kept)
    candidates/<id>_s<seed>.json, .api.json   prompt, negative, seed, model, settings; the exact graph
    candidates/contact_sheet.png              review sheet (seeds + face crops)
    final/<id>.png                            1024x2048 RGBA, crown ~y108, soles y1990, axis x512
    final/<id>_portrait.png, _check.png, _boxes.png, <id>.json   portrait, cutout check, boxes, meta
    variants/<name>.png                       eyes_closed|eyes_open, mouth_open, smile, hurt (full canvas)
    variants/<name>_patch.png/.json, sheet_<name>.png, candidates/, variants.json
    masks/eyes.png, mouth.png, eyes_mouth.png expression regions (canvas size, white = region)
    work/                                     crops, masks and server outputs of each pass (git-ignored)
```

Content rules (adults only, suggestive but never explicit) apply to everything here, including
discarded candidates: `docs/dev/character-briefs.md`, `docs/dev/art-style.md` section 1.
