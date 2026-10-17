# Status and handoff

**Status as of 2026-10-17, 07:50 UTC.** This is the living status file: update it at the end of
every work block. Rules and conventions are in `CLAUDE.md`; this file is about where things stand.

## In one paragraph

v1 of the game builds as a sideloadable IPA (latest: run 38946000040, with the 15 farm-painted
heroes); the owner has not said whether they installed it. On 2026-10-17 the art moved to ComfyUI
on the owner's PC with their NoobAI-XL V-Pred checkpoint, and the roster became female only. Test
renders exist for most heroes, but nothing new is in `assets/` yet: the owner's review said the
renders have "a lot of AI artifacting and aren't smooth or high resolution", so a quality A/B is
under way first. **The work now continues in a regular Claude Code chat on the owner's PC**, not a
project thread, because the owner wants to review images directly in the chat.

## Start here (a local chat on the owner's PC)

1. Work in `D:\AI\claude game` (a clone of this repo). `git pull` first.
2. Read `art_src/_review/HANDOFF.md` on the PC. It is local only (in `.git/info/exclude`) and has
   the exact state: how ComfyUI is started, every hero's candidates, picks and finals, the A/B
   outputs, the queue and the uncommitted files. This file is the summary.
3. Show the owner images directly in the chat as they are rendered (contact sheets per hero, and
   1:1 crops for the A/B). That was their main request. The review set is in
   `art_src/_review/` (`pass_list.json`, `sheets/`, `ab/`).
4. Stay in the default (Ask) permission mode: the owner approves prompts in front of them. Auto
   mode blocked sending images anywhere as "data exfiltration" (see `CLAUDE.md`, Blocked before).
5. Tools on Windows: no bash `tools/*`; use `python` (not `python3`), the filter venv
   `.venv-artgen`, and the Windows commands in `CLAUDE.md` Setup. Godot is not on PATH.

## Current work (2026-10-17)

- **Owner asks:** "use comfyui on my machine to make the art professional. i have a noobai xl
  checkpoint set up and ready to go. also want it to be female only". Then: "anything that's not
  explicit nudity is fine", "raise it" (the filter), "send all generated images in here", and
  "the images have a lot of AI artifacting and aren't smooth or high resolution ... can you
  research the best settings for this model rather than guessing".
- **Female only:** done in the designs (briefs v3.3, `data/art_prompts.json`, `data/heroes.json`).
  Nuriel, Brakka, Orrin and Lucen keep their ids, names, roles and stats. Their shipped art is still
  the old male art until new finals are installed.
- **PC setup:** DESKTOP-VIS0U33, RTX 3070 8 GB, ComfyUI Desktop on 127.0.0.1:8188 (models and
  custom nodes under `D:\comfyui`), checkpoint `NoobAI-XL-Vpred-v1.0.safetensors` pinned as
  `noobai_vpred`. Installed on the owner's word (07:25 UTC): `4x-AnimeSharp.safetensors` and
  `4x-UltraSharp.safetensors` in `models/upscale_models`, and `ComfyUI_UltimateSDUpscale` (ssitu,
  commit a5547db) in `custom_nodes`. ComfyUI needs a restart to load the node, then
  `comfy.py discover`.
- **Filter at 0.5** (c3d35b5). Pilot pass rates at 0.5: Uriela 3/6 (v3.2 restored, pick s104002),
  Mordessa 6/6 (now with `(leotard under clothes:1.3)` so the hip slits show the leotard,
  f710bfe), Noctaire 6/6, Cassiel 6/6, Kessa 5/6, Lucen 5/6, Seraphiel about 1/6 (moderate
  cut-back pending). Held for hard lines and never sent or committed: Seraphiel s101002 (sheer
  groin drape), Mordessa s201000 and s201004 (bare hip in slits). Kessa s205023 and s205024 DROP
  at 0.5 (hip windows) but were shown to the owner in a contact sheet in the PC session.
- **Cutouts:** core RemoveBackground (BiRefNet) first; enclosed background holes are now cleared
  (459f0fe). Dark designs render on grey.
- **Quality research** (`/mnt/project-files/art/noobai-vpred-settings.md` in the project, with
  sources): the base settings match the NoobAI V-Pred card (Euler, CFG 4-5, 28-35 steps, about
  1 MP, v_prediction + zero-SNR). The gaps were after it: (1) latent hires (nearest-exact) at
  denoise 0.5, (2) finals only stretched 2x with lanczos, (3) no hand pass and no face pass on
  candidates, (4) Animagine quality tags instead of NoobAI's own (prefix
  `masterpiece, best quality, newest, absurdres, highres`, aesthetic `very awa`, negatives
  `worst quality, old, early, low quality, lowres, signature, username, logo, bad hands,
  mutated hands, worst aesthetic`).
- **A/B on Mordessa** (seeds 201010, 201011, 201015; outputs `art_src/_ab/<variant>/`, 1:1
  side-by-sides `art_src/_review/ab/mordessa_s*.jpg`): A current (latent hires 0.5); B NoobAI's
  own tags (prefix above + `very awa`, the card's negatives + `worst aesthetic, displeasing,
  furry, anthro, mammal, feral, sketch`; rating and safety negatives unchanged); C B + latent hires
  0.6. The PC session's read: **B clearly beats A** (cleaner lines, smoother gloss, tidier hair and
  face), C slightly crisper than B; B and C drift Mordessa toward a black leotard with less red
  dress. Not run yet: D (B + 4x-AnimeSharp model hires at 0.4) and E (D + Ultimate SD Upscale 2x
  at 0.35 + face and hand touch-up). E needs a new UltimateSDUpscale builder in
  `tools/comfy/workflows.py` and a finalize option (not written). The bible defaults are unchanged.
- **Gotcha:** with an upscaler installed, `--hires-mode auto` now picks model hires (denoise 0.4)
  and finalize's 2x uses the model; pass `--hires-mode latent` to reproduce A to C.
- **Per hero** (filter passes per 6 seeds at 0.5; no hero is installed, finals wait for the winner):
  | Hero | State |
  |---|---|
  | uriela | v3.2 3/6. Re-finalize from s104002 (the current s104025 final is an off-brief test design); fix the stray eyeliner (fix.py, wider box, denoise ~0.6); use `--face-box`. |
  | kessa | 5/6. Final s205022 PASS; mouth_open and smile s205501 PASS; eyes_closed still a wink at 0.75 (wider eyes region, denoise ~0.8). |
  | lucen | 5/6 (weighted asymmetric wings also 5/6, not in the bible). Final s304004 with refine 0.3 PASS; variants not reviewed. |
  | mordessa | 6/6 with the weighted leotard. Final s201012, not reviewed or checked. |
  | noctaire | 6/6 on grey. Final s301001 re-cut; painted white blobs in the scythe need fix.py or another seed. |
  | liora | 6/6. Final s103004, not reviewed. |
  | cassiel | 6/6 on grey. Final s102003, not reviewed. |
  | brakka | 6/6 on grey, not picked. |
  | seraphiel | Most drop even at 0.5 (breast 0.43-0.74); s101002 held; needs a cut-back. |
  | vesper, imra, orrin, sable, nuriel, ashra | Not started. |
- **ComfyUI on the PC:** a detached headless process on 8188 (exact start line in `HANDOFF.md`;
  logs `D:\comfyui\user\halo_comfy_stdout.log`); the Desktop app itself uses port 8000. Filter:
  `.\.venv-artgen\Scripts\python.exe tools/artgen/safety.py check <files>` (system Python 3.10
  can't take the pinned numpy). The review set had 117 of about 200 images checked at the
  handoff; `python art_src/_review/tools/collect_review.py` finishes it (cached; its helper paths
  still point at the old session's scratchpad).
- **Next lever if still rough:** a NoobAI-based fine-tune or a style LoRA (the owner's call).

## Next steps (art)

1. Finish the A/B, show the owner the side-by-sides, commit the winning settings.
2. Re-render with them; per hero pick, finalize, variants (eyes_closed at 0.75 for Kessa and
   Lucen, 0.62 gave winks), `safety.py check` at 0.5, 1:1 review, `install.py`, commit.
3. Rig each installed hero (`python tools/art_warp_build.py <id> --regen-masks`, then Godot
   import) or leave rigs to a cloud session (`tools/art_warp <id> --regen-masks`, `tools/check`).
4. When all 15 are in: an iOS build (`ios.yml`) and the run link to the owner.

## Done

| What | Where | Proof |
|---|---|---|
| v1 game: 15 heroes in 3 factions (Celestial > Infernal > Fallen > Celestial), 30-stage campaign, auto battle with manual ultimates and 1x/2x/4x speed, idle rewards with quick claims, summon with pity, odds screen and a free daily pull, levels, stars, gear, daily quests, a shop of free test purchases, first-session guide | `src/`, `data/` | IPA run 38830308549 |
| UI v2 in the reference game's style, with our own names, icons and fonts; flirty Lobby lines per hero | `docs/dev/ui-style-v2.md`, `src/ui/battle/lobby_lines.json` | IPA run 38852015265; critic scored 8/10 fidelity, 7/10 polish |
| Art farm: Animagine XL 4.0 on GitHub Actions CPU runners, fail-closed exposure filter with cover repair, output on branch `art-gen-output` | `docs/dev/art-farm.md`, `tools/artgen/`, `.github/workflows/art-gen.yml` | 14 runs on `art-gen-output` |
| Character briefs v3.1 (maximum allure, hard lines) and the prompt bible | `docs/dev/character-briefs.md`, `data/art_prompts.json` | |
| 15 painted heroes imported with warp rigs; Seraphiel's vector stand-in removed | `assets/art/heroes/<id>/` | commit 811d909 |
| Latest IPA with all 15 painted heroes | run 38946000040 (commit 811d909) | all steps green, 3m13s, about 50 MB |
| Handoff: `CLAUDE.md`, this file, the cloud SessionStart hook, `.gitattributes` (LF for bash scripts) | repo root, `.claude/` | |

**Getting the IPA:** the owner opens https://github.com/u-tek/game/actions/runs/38946000040 while
logged in to GitHub, downloads `HaloAndHorn-ipa` (a zip with `HaloAndHorn.ipa`) and sideloads it
with Sideloadly or AltStore (`docs/dev/ios-build.md`). The artifact expires on 2026-10-30. After
that, or after any change, run the **iOS build** workflow again on `claude/game-planning` and send
the new run link. Cloud sessions can't download artifacts themselves.

Earlier IPA runs: 38804639017 (trial), 38830308549 (v1), 38852015265 (UI v2).

## Verified health (2026-10-17, 00:15 UTC, HEAD 811d909)

| Check | Result |
|---|---|
| `tools/check e2e` | 93 tests, 0 failures; boot and 3 e2e scripts ok (2m07s) |
| `tools/check` on a fresh clone, no `.godot` cache | ok in 21 s |
| `python3 tools/artgen/test_artgen.py` | 81 OK |
| `python3 tools/artgen/test_sdxl_tiny.py` | 6 skipped without torch; 6 OK with torch 2.8.0 CPU on PYTHONPATH |
| `python3 tools/comfy/test_pipeline.py` | 51 tests, **2 known failures** (see Known issues) |
| `tools/art_warp --check` | 15 heroes, 0 errors |
| `tools/art_selftest.gd` | 1590 checks, 0 failures |
| `python3 -B tests/port_check/check_port.py` | 48 checks, 0 differ |

## Art per hero

All finals: Animagine XL 4.0, Euler a, CFG 5, 28 steps, 832x1216 candidates from run 38859902166
(`style=bible`, fp32), then a 1.5x hires pass, face polish, cutout, the 1024x2048 canvas and
inpainted eye and mouth variants. "Fit" is the figure height as a share of the 1900 px spec
(measured on the imported canvas). "Repaired" means the filter's cover repair repainted part of the
candidate the final was built from, or part of the final itself (finals start from the published,
already-repaired candidate). 14 heroes are byte-identical to their farm finals; Seraphiel was
edited at import.

| Hero | Final run | Seed | Fit | Repaired | Known flaws and off-brief details |
|---|---|---|---|---|---|
| Seraphiel | 38881543229 | s101000 | 77% | canvas, twice | Neckline closed with a dark-and-gold collar by the repair (design change). Grey pockets in the halo cleared at import, on the base and every variant. The top halo spike touched the top edge of the source candidate, so its tip may be cut. |
| Cassiel | 38881543229 | s102000 | 79% | hires image | `eyes_closed` came out as a wink, so she does not blink. |
| Liora | 38881543229 | s103000, flipped | 76% | candidate (chest, hem) and canvas | The repair turned the white lace bottom under her hem into skin shading: nothing explicit, but it can read as no underwear. Bead speck on the stocking top. |
| Uriela | 38881543229 | s104001, flipped | 78% | no | Smile variant is a wink (kept). Spear not over her shoulder. |
| Nuriel | 38881543229 | s105001 | 80% | no | Masked, so eyes slot only. Notch of about 2,300 px in the screen-right wing. Mask black, not white; daggers not in reverse grip. |
| Mordessa | 38881543229 | s201001 | 70% | no | Smallest figure. White rims around holes in the dark hair. Loose sword hilt. |
| Brakka | 38881543229 | s202001 | 82% | canvas, twice | Repair changed his chest from red to orange, added star studs and repainted a boot. `eyes_closed` is a wink (no blink); `mouth_open` barely differs. |
| Vesper | 38913405511 | s203000 | 80% | candidate (hip) and canvas (orb interior) | Orb kept with the detached-props fix. `eyes_closed` is a wink (no blink). Left margin 3 px (wing tip). |
| Imra | 38881543229 | s204000 | 89% | no | Best fit. White sliver at the hem by the right foot. Top is navy, not crimson; wings don't show. |
| Kessa | 38881543229 | s205000 | 75% | no | White rims in the dark hair. |
| Noctaire | 38881543229 | s301000 | 77% | no | Faint floor shadow under the feet. |
| Orrin | 38902617668 | s302000 | 78% | candidate (chest) | **Alternate seed**: the pick s302002's canvas was dropped in its only final run (38881543229, anime `pussy` 0.319 on the sternum, a false positive). Renders are deterministic, so a re-run would drop it again. No chest chain. |
| Sable | 38902617668 | s303001 | 75% | candidate (hips and upper thighs) | **Alternate seed**: s303000 dropped twice at 0.2515. Holds chains instead of her censer. Semi-transparent patch of about 3,000 px on the inner thigh, visible on dark backgrounds. |
| Lucen | 38881543229 | s304000 | 73% | no | Clean; the best final. Holds the rapier by its guard. |
| Ashra | 38881543229 | s305001 | 82% | canvas, twice | Chest re-shaded, with sweat-drop highlights. Shorts are white, not black. |

Most picks face near-frontal instead of the 3/4 view the rig was designed for. Each hero's run and
seed is also recorded in `assets/art/heroes/<id>/<id>.warp_src.json` (`_doc`, `meta.art`) and in
`docs/dev/art-farm.md` section 7.

## Owner decisions pending

Items 2-4, 7 and part of 5 were reported to the owner at 18:20 UTC on 2026-10-16; item 8 at
04:33; item 9 at 07:58 and 09:05. Items 1, 6, 10 and 11 (and the "discard, never patch" question
in 5) have never been put to them. They have answered none of them; their only messages since
09:05 asked for this handoff.

1. **Approve the 15 looks as a set.** The promised contact sheet of the picks was never sent; the
   owner has only seen the in-game lineup.
2. **Figure size.** Every figure fills only 70-89% of the spec height, because 832x1216
   compositions are limited by the canvas width. The Lobby and hero detail scale each hero to its
   own height, so this only shows in battle, where heroes look 11-30% smaller than designed (all at
   the same scale). Options: accept it; add a per-hero battle scale; re-render at 768x1344 (also a
   model-card size); composition prompts; relax the spec. The fixed battle scale is `BASE_SCALE`
   (0.145) in `src/art/hero_sprite.gd`; a per-hero scale would go there.
3. **Orrin:** keep s302000 (no chest chain), switch to s302001 (chest chain, but the tower shield is
   cut flat and there is a purple floor splash; it is on `art-gen-output`), or re-render.
   **Sable:** keep s303001 (chains instead of the censer, thigh haze) or re-render.
4. **Liora's lace:** accept the repaired canvas or re-render to get the lace back.
5. **Cover-repaired art at all.** `character-briefs.md` says an image that crosses a hard line is
   discarded, never patched into compliance, yet the shipped art of Seraphiel, Cassiel, Liora,
   Brakka, Vesper, Ashra, Orrin and Sable was repaired (Orrin and Sable at the candidate stage
   only), and some repairs changed designs (Seraphiel's collar, Brakka's skin colour, Ashra's
   chest). Accept, or re-render those heroes.
6. **Off-brief details** listed in the table: fix or accept.
7. **The open offer:** "Want me to start on them?" (Liora's lace, the missing blinks for Cassiel,
   Brakka and Vesper, Orrin's and Sable's original designs), ideally on the owner's GPU.
8. **Keeping filter-flagged images:** blocked for Claude. The owner would have to add a permission
   rule themselves, or generate on their own PC where images stay local.
9. **The PC:** did they clone or teleport the session onto their PC? Do they want ComfyUI there
   (local only, on 127.0.0.1) or exposed to the cloud through an authenticated tunnel? If they want
   a cloud session to message their PC session, they have to ask for the trust card again.
10. **Business questions never answered** (`docs/open-questions.md`): team and roles, budget,
    publisher, working title (Halo & Horn is Claude's name), target markets, the player
    character, VIP, rewarded ads, the hook, pity and free-currency generosity, backend.
11. Later, only if needed: Google Play (needs tamer "standard" outfits for every hero) and App Store
    signing (the export preset has a placeholder team id; a real Apple developer account is needed
    for anything beyond sideloading).

## Known issues

- **The import scripts are one-off tools.** `tools/art_import/` (see its README) holds the scripts
  that copied the finals from `art-gen-output` into `assets/` (`import_art.py`), generated the 15
  `warp_src.json` files (`rigs.py`, which regenerates all 15 byte for byte) and cleared
  Seraphiel's halo pockets (`fix_halo.py`), plus the picks they read (`finals_picks.json`). The
  rig regions are hand-drawn polygons in `rigs.py`; a new seed for a hero means new polygons. To
  re-import a hero by hand instead:
  from `art-gen-output`, copy `runs/<run dir>/<hero>/final_s<seed>/<hero>.png` and its
  `variants/<name>.png` for the hero's variant set (the names already in
  `assets/art/heroes/<id>/variants/`: `eyes_closed` or `eyes_open` for Seraphiel, `mouth_open`
  except Nuriel, `smile`; never the `*_patch.png` files) into `assets/art/heroes/<id>/`
  (`variants/` keeps its `.gdignore`), edit `<id>.warp_src.json`, run
  `tools/art_warp <id> --regen-masks`. Re-importing Seraphiel brings the grey halo pockets back
  unless they are cleared again (one alpha edit applied to the base and every variant).
- **Art farm:** the workflow input `style` defaults to `farm`, but production used `bible`;
  always pass `style=bible`. Final jobs take 83-143 min per seed on CPU. The filter drops some
  review images and `*_patch.png` files as false positives, so the published patch sets are
  incomplete (every `variants/<name>.png` was published). Side margins are 20-24 px against a 24 px
  spec (Vesper 3 px): `post.place_on_canvas` measures at alpha > 0.5 while the spec report uses alpha > 8 (fix in
  `tools/comfy/post.py`). Commit 105e7a4 (re-cut inside repaired regions) was tested locally
  before production. The Hugging Face model cache on Actions is evicted after 7 days unused; a job
  then downloads the model again (under a minute).
- **A farm re-run repeats its output.** Candidates, finals and face variants are deterministic per
  seed (variants use `seed_base + 500` and keep the first try; `--variant-tries` is not a
  workflow input). Re-running a final does not fix a wink or Liora's lace, and costs about 2 h per
  hero. On the farm, change the bible prompt (the hero's `variants` or outfit) or the code first,
  or use other seeds. On ComfyUI: `variants.py <id> --count 3`, then `--pick eyes_closed=<seed>`.
  Presets are fixed at 832x1216 (`tools/artgen/config.py` `PRESETS`, no size input) and finals
  reuse the candidate composition, so 768x1344 needs a new preset plus tests, committed before
  dispatch, then a new candidate round and new finals (owner plan approval, roughly 3-4 h of
  runner time).
- **HaloRig:** rig regions are approximate polygons drawn by eye (hand-painted masks would move
  better). The dissolve effect looks speckled. One flat painting can't swing limbs, so big attacks
  rely on body motion plus effects.
- **Tools are Linux-only** bash scripts (flock, xvfb-run). Untested on Windows.
- **No background art:** `assets/art/backgrounds` is empty; `src/ui/battle/scene_backdrop.gd` draws
  the backdrops in code.
- **Stale docs:** `docs/game-design.md` (draft v0.1), `docs/tech-plan.md` and `docs/roadmap.md`
  (Unity era) are background reading only. `docs/dev/art-style.md` section 2 (figure about
  1900 px, 24 px margins) is met by no final, pending decision 2. `docs/dev/art-generation.md` and
  `comfyui-setup.md` describe a path that has never run.

## Older next steps (2026-10-16, before ComfyUI; steps 2 and 4 are superseded above)

1. **Sync and report** (see "First things"). Send the owner a contact sheet of the 15 finals
   (rebuild it from `art-gen-output`, or `tools/shoot` / `tools/art_gif.py` in-game shots) and ask
   decisions 1-5 in one short message. Don't wait for the answers. In the same turn, start on
   steps 3 and 4 (and game work from step 5), which don't depend on them. Tell the owner what
   you're doing and when you'll report back (UTC). The owner often answers late or not at all; the
   18:20 questions are still open.
2. **ComfyUI on the owner's PC**, their preferred art path. Seconds per image on a GPU instead of
   30-40 minutes per candidate on the farm. It would fix: Liora's lace, the missing blinks
   (re-render `eyes_closed`), Orrin's and Sable's original designs, the figure size (re-render at
   768x1344 or with composition prompts), the off-brief details, the cutout flaws, and the 3/4
   view. Images stay on the owner's machine, which is the only way to meet their request to keep
   filter-flagged images. Game assets still go through the same content rules and filter before
   they are committed: `python tools/artgen/safety.py check` on the PC (`CLAUDE.md`, content hard
   lines). Two routes:
   - **A session on the PC (simplest):** the owner clones `https://github.com/u-tek/game` into a
     folder (for example `C:\halo-game`) and starts Claude Code there (or teleports a cloud session
     into it). That session installs or finds ComfyUI, adds Animagine XL 4.0 (about 7 GB), keeps
     ComfyUI on `http://127.0.0.1:8188` with no tunnel, and runs `docs/dev/art-generation.md`
     section 2. On the PC:
     - Pin the shipped model: put `animagine-xl-4.0.safetensors` from
       https://huggingface.co/cagliostrolab/animagine-xl-4.0 in `ComfyUI/models/checkpoints` and
       pass `--ckpt animagine-xl-4.0.safetensors --family animagine` on every command (or set
       `COMFYUI_CKPT`). Don't let `discover` pick another checkpoint the owner already has.
     - Set only `COMFYUI_URL` (PowerShell: `$env:COMFYUI_URL = "http://127.0.0.1:8188"`).
       `COMFYUI_AUTH` is for the tunnel route only, and `comfy.py` only warns about plain http for
       non-local hosts. Use `python`, not `python3`.
     - Rig on Windows (`tools/art_warp` is bash): `python tools/art_warp_build.py <id> --regen-masks`,
       then `godot --headless --path . --import`.
     - `finalize.py` uses its own cutout and a 2x upscale, not the farm's 1.5x hires and the
       `tools/artgen/cutout.py` fixes (grey pockets, floor shadows, detached props, re-cut), so
       fixed flaws can come back. Before `install.py`, composite the canvas on #120e24 and on white
       and compare it with the shipped hero.
   - **A tunnel into a cloud session:** `docs/dev/comfyui-setup.md` (ngrok with basic auth,
     `COMFYUI_URL` and `COMFYUI_AUTH` as environment secrets, never in chat or the repo).
   Keep the same model and settings for consistency with the 15 shipped heroes.
3. **Generalize the import tool:** `tools/art_import/` works for the 15 shipped picks only (fixed
   picks file, per-hero polygons, a Seraphiel-only halo fix). Make it take a hero, run and seed,
   or a ComfyUI final, so re-imports are one command.
4. **Small fixes:** the 2 `test_pipeline` failures, the margin rounding in `tools/comfy/post.py`,
   the remaining stale docs listed above.
5. **Game work** once the art is settled: background art (painted backdrops), more content and
   balance, polish from the UI critic's remaining notes, and a new IPA after each block.

## Outside the repo

- **The owner's four reference-game screenshots** (lobby, roster grid, lobby variant, detail
  screen). They were only in the old container and are gone in a new one. Ask the owner to send
  them again if a UI fidelity review needs them. Keep them outside the repo, along with any crops or
  side-by-side composites.
- The import, rig-generation and halo-fix scripts, the review images and contact sheets, and the
  local torch install for `test_sdxl_tiny.py`: all in the old container only. Everything except
  the scripts can be rebuilt from `art-gen-output` and the tools.
- The old session's conversation and plan files. Their content is captured here and in `CLAUDE.md`.

## Promises still open

- Send the owner the best pick for each hero (promised 08:52 UTC 2026-10-16): never sent; the finals
  were imported without their approval.
- Send the owner every generated image (asked 2026-10-17). Contact sheets for 7 heroes were shown
  in the PC session; a local chat on the PC can show the rest directly.
- "Want me to start on them?" (18:20): the fixes in decision 7.
- "Say 'ask again' and I'll send a fresh one": the trust card for messaging the PC session.
- At 09:05 the owner was asked to say "stop" once a PC copy was running, so that two copies don't
  both push. They never replied; check the branch before pushing.
- The handoff itself: the owner was told they would hear when it is safe to start a new session.
