# Layered rigs: from one painting to a NIKKE/BD2-style rig

The reference is Seraphiel's prototype, `rigproto2`, built 2026-10-20/21. The rig format is in
`docs/dev/halorig.md` sections 11.4-11.5. Everything runs on the owner's PC: ComfyUI on
127.0.0.1:8188, and See-through in `D:/AI/see-through`.

Work files stay local and are never committed:
- The work folder is `art_src/_review/rigproto/<hero>/` (the final, See-through's output, SAM masks
  and repaints).
- The rig folder is `assets/art/heroes/<hero>/skins/<art>/`. Keep it in `.git/info/exclude` until
  the owner approves the art.

## Steps

1. **Rig-pose art.** Run `HALO_ART_SRC=art_src/_review/rigproto python tools/comfy/run_hero.py <hero>
   --pose rig --count 4`.
   - The pose comes from the hero's `rig` block in `data/art_prompts.json`: front view, limbs clear
     of the body, props upright, eyes open.
   - The owner picks one; `finalize.py` follows.
2. **Expression frames.** With the same `HALO_ART_SRC`, run `tools/comfy/variants.py <hero>
   --variants eyes_closed,eyes_half,mouth_open,mouth_small,mouth_wide,smile --count 2`.
   - Look at every try and pick in the rig script (`PICKS`).
   - A hero whose base design has closed eyes needs her own variant lines, for example
     Seraphiel's `eyes_half`.
3. **Layers.** Run See-through (`inference_psd_blockswap.py --resolution 1280`) on a crop of the
   final, after `POST /free` to ComfyUI. It takes about 15 min and produces 23 tags with hidden parts
   painted in.
   - `st_to_canvas.py <st_dir> <final.json> <crop box> <out>` places them on the 1024x2048 canvas
     and reports the overlap with the final (aim for at least 0.97).
4. **Masks the splitter does not give.** `sam_cut.py` (run with the ComfyUI venv python) takes a
   spec of points and boxes, like `seraphiel_sam.json`, for each breast and hand. Check
   `_sam_sheet.png`.
5. **The rig source.** `<hero>_rig.py`, modelled on `seraphiel_rig.py`, writes the layers, masks
   and `warp_src.json`:
   - Breasts as their own layers, with grey-level weights pinned at the top.
   - Arms cut by the nearest bone segment into upper and forearm pieces, with an elbow cap disc.
   - Irises and lashes as their own layers, with the eye white painted in.
   - Hair in locks of four chained springs.
   - Legs on two-bone IK to planted ankles, with flat feet.
   - Held props with a `grip`.
   - `meta.idle` and `meta.idle_gestures`.

   Joint positions are read off zoomed coordinate grids of the layers.
6. **Hidden parts nobody painted:** the torso behind the breasts, a wing behind a prop.
   - The rig script writes a rough fill plus a hole mask.
   - `fill_hidden.py <layer> <hole> <crop x,y,side> <out> --seeds .. --denoise 0.72-0.9` repaints it
     with MOSS. Look at every try: some repaint breasts or hair over the hole.
   - Copy the pick to `work2/<layer>_fill.png` and re-run the rig script.
7. **Build:** `python tools/art_warp_build.py <hero>@<art> --regen-masks`, then
   `tools/gd --headless --path . --import`.
8. **Her animations.** `<hero>_anims.py`, modelled on `seraphiel_anims.py`, writes to the art's own
   `anim/` folder:
   - attack, cast, touch and victory;
   - idle gestures;
   - `carry` keys for a held prop;
   - `jiggle:x,y` events.
9. **Check and show.**
   - `run_preview.sh <jobs.json>` runs `tools/art_preview.gd` with its window parked off the main
     monitor.
   - Use single-pose jobs first (rotate bones in steps to find tears), then a timeline (`talk:<s>`,
     `expr:`, actions).
   - Encode with ffmpeg as in `art_src/_review/rigproto/encode_v4.sh`: full body and an upper-body
     close-up.

## Lessons

- Weight every layer by its own parts (`"weights": "own"`). Shared composition let See-through's
  amodal masks leak across layers: the belly followed the hair.
- A carried prop inherits the body's lean, and a 945 px stand swings its foot about 16 px per
  degree. Keep it planted (`carry` 0) through wind-ups and take it into the hand on the fast move.
- A model's repaint keeps its flat grey backdrop where it painted her narrower than the hole: clear
  those pixels (`seraphiel_rig.py` does).
- The preview must render as the iPhone does (HDR 2D off, `ui_linear` 0). Compare a rest frame with
  the painting pixel for pixel.
