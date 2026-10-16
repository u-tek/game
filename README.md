# art-gen-output

Generated hero art from the art farm (`.github/workflows/art-gen.yml`, docs in
`docs/dev/art-farm.md` on the main branch). Nothing here is used by the game directly: approved
finals are copied into `assets/art/heroes/<id>/`.

- `runs/<run id>-<mode>[-label]/<hero>/`: candidates (`<hero>_s<seed>.webp` + `.json` metadata) or
  finals (`final_s<seed>/`: `_hires.webp`, `_source.webp`, the 1024x2048 canvas `<hero>.png`, portrait,
  `_check.webp`, `_boxes.webp`, variants, masks, `variants_sheet.webp`, metadata), `contact_sheet.webp`.
- `runs/<run>/index.json`: jobs, timings, memory, filter statistics. `index.json`: all runs.
- Every image passed an automatic exposure filter (NudeNet + anime censor-point detector) on the
  runner before upload; images that failed were deleted and never uploaded (see each run's index).
- Model: cagliostrolab/animagine-xl-4.0 (CreativeML Open RAIL++-M), no LoRA. Settings per image are
  in its metadata.
