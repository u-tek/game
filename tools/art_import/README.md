# tools/art_import: the 2026-10-16 hero import

These are the one-off scripts that put the 15 painted farm heroes into the game (commit 811d909).
They are kept so the import can be repeated or extended. They are not a general tool yet.

| File | What it does |
|---|---|
| `finals_picks.json` | The chosen final for each hero: canvas path inside the `art-gen-output` branch, run, seed label (with figure fit), notes |
| `import_art.py [id ...]` | Copies each pick's canvas and delivery variants into `assets/art/heroes/<id>/`, writes `import_log.json` |
| `rigs.py [id ...]` | Writes `assets/art/heroes/<id>/<id>.warp_src.json`: hand-drawn region polygons and key points per hero, plus the face and overlay rects from the farm metadata and variant diffs |
| `fix_halo.py` | Clears the grey pockets inside Seraphiel's halo windows (same alpha edit on the base and every variant) |
| `import_log.json` | What `import_art.py` copied on 2026-10-16 |

## Running them

They read the farm output from a checkout of the `art-gen-output` branch:

```bash
git fetch origin art-gen-output
git worktree add artgen-out origin/art-gen-output   # or set ARTGEN_OUT=<dir of a checkout>
python3 tools/art_import/import_art.py vesper        # copy one hero (all if no ids)
python3 tools/art_import/rigs.py vesper              # write its warp_src.json
tools/art_warp vesper --regen-masks                  # masks, overlays, portrait, warp.json
```

`HALO_ASSETS_HEROES` overrides the destination (default `assets/art/heroes`). `artgen-out/` is
git-ignored. Re-running `rigs.py` on the shipped picks reproduces all 15 committed
`warp_src.json` files exactly. Re-importing Seraphiel needs `fix_halo.py` again afterwards.

A different seed for a hero needs new polygons in that hero's entry in `rigs.py`, because the
regions are drawn for one image.
