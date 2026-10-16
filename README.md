# art-gen-output

Generated hero art from the art farm (`.github/workflows/art-gen.yml`, docs in
`docs/dev/art-farm.md` on the main branch). Nothing here is used by the game directly: approved
finals are copied into `assets/art/heroes/<id>/`.

- `runs/<run id>-<mode>[-label]/<hero>/`: candidates (`<hero>_s<seed>.webp` + `.json` metadata) or
  finals (`final_s<seed>/`: 1024x2048 canvas, portrait, variants, masks, metadata), `contact_sheet.png`.
- `runs/<run>/index.json`: jobs, timings, filter statistics. `index.json`: all runs.
- Every image passed an automatic exposure filter (NudeNet + anime censor-point detector) on the
  runner before upload; images that failed were deleted and never uploaded (see each run's index).
- Model: cagliostrolab/animagine-xl-4.0 (CreativeML Open RAIL++-M); candidate rounds may use the
  SDXL-Lightning or LCM LoRA (OpenRAIL++). Licences per image are in its metadata.
