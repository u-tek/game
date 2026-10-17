# Halo & Horn: notes for every Claude session

**Start here.** Read `docs/dev/status.md` first: where things stand, the owner's open decisions,
known issues and the next steps. Then check the remote before changing anything:

```bash
git fetch origin && git status && git log --oneline -5 origin/claude/game-planning
```

A copy of this project may also be running on the owner's Windows PC and pushing to the same
branch. Pull before you work, and never force-push.

Since 2026-10-17 the art work runs in a regular Claude Code chat on the owner's PC
(`D:\AI\claude game`), where images show directly in the chat. Its local notes are in
`art_src/_review/HANDOFF.md` there; the summary is in `docs/dev/status.md`.

## The project

A mobile idle/AFK gacha RPG close to *Idle Angels*: angels (Celestial), demons (Infernal) and the
Fallen, 15 heroes, 5-hero auto battles with manual ultimates, idle rewards, summons with pity.
Godot 4.5.1 (GDScript, GL Compatibility, portrait 720x1280 base). It ships as an unsigned iOS IPA
that the owner sideloads. The repo `u-tek/game` is public. The only code branch is
`claude/game-planning`, which is also the default branch; there is no `main`.

## The owner, and how to work with them

- The owner is not a programmer and is new to game development; the goal is commercial. They
  want Claude to be the whole team (design, code, art, builds) and want building, not planning
  documents. "Don't tell me it's not possible. Figure it out."
- Work on your own for long stretches. If a real limit exists, say it once, plainly, with the
  best alternative.
- They steer from an iPhone and a Windows PC. Messages are short, lowercase, often typo'd or
  voice-dictated: read for intent. When they answer a multiple-choice question with free text,
  follow the free text.
- Show the work. Send images, GIFs, screenshots, contact sheets and docs as files as soon as they
  exist. Give builds as the GitHub run link. They often ask "can i see...".
- Give concrete ETAs in UTC (their time zone is unknown). Say what is running in the background,
  what is slow and why. A turn that ends while background work runs looks like stopping to them.
- Say plainly which decisions you made without them, and tell them when an action needs their
  approval (plan mode, a permission card) and what to tap.
- Big multi-agent runs use their plan quota (the usage limit was hit once). Keep fan-out modest.
- **Their GPU, their call (2026-10-17).** Ask before any render job longer than about 10 minutes
  and before making new art settings the default. Send every render as its own full-size image as
  it lands, not only sheets. A test shows whether art is better; only the owner says whether it is
  good enough. (A 90-minute roster run started without asking was stopped: "I know I'm not going
  to be happy with" them.)
- What upset them before: planning instead of building, a web build, chibi or vector art,
  washed-out art, looking idle, deleting filtered images.
- In repo docs, call them "the owner" (they/them). Write plain, direct English.

## Standing directions (current versions)

- **Product:** idle gacha RPG very close to Idle Angels; cornering a niche is the point and a small
  player base is fine. Halo & Horn, the factions and the 15 heroes are Claude's designs; the owner
  has not objected.
- **Platform:** a native iOS app delivered as an IPA for sideloading. Never build a web or browser
  version, and avoid anything that would need a remake later.
- **Engine:** Godot 4.5.1, kept portable to Unity later (data contract below,
  `docs/dev/unity-port.md`). Game logic stays in GDScript; Godot's C# iOS export is experimental.
- **iOS builds:** `.github/workflows/ios.yml` on a free GitHub macOS runner (the repo is public for
  this), artifact `HaloAndHorn-ipa` on the run page. No GitHub releases.
- **Public repo:** the owner accepted that art, builds and the IPA are publicly visible.
- **Art:** professionally rendered, full-body anime gacha splash art, one painted PNG per hero.
  Not chibi, not vector, no code-drawn characters. Source from 2026-10-17: ComfyUI on the owner's
  GPU PC with **their NoobAI XL checkpoint** ("use comfyui on my machine to make the art
  professional"), driven by a Claude session on that PC (`tools/comfy/`,
  `docs/dev/art-generation.md`). The 15 shipped heroes came from the art farm (Animagine XL 4.0 on
  GitHub Actions CPU runners, `docs/dev/art-farm.md`), which stays as a fallback.
- **Animation:** HaloRig, our own replacement for Spine: a warp rig on the painted PNG with eye
  and mouth variants (`docs/dev/halorig.md`).
- **Render settings ("make sure you're using the correct cfg"):** always the model card of the
  checkpoint in use. NoobAI XL: family `illustrious` for epsilon checkpoints (Euler a, CFG 5.5,
  28 steps) or `noobai_vpred` for v-prediction ones (Euler, CFG 4.5, 32 steps, v_prediction with
  zsnr, RescaleCFG 0.7), quality tags first, 768x1344 (`families` in `data/art_prompts.json`).
  The art farm used the Animagine card: Euler Ancestral, CFG 5 (the code refuses values outside
  4-7), 28 steps, quality tags at the end. No speed LoRAs, Lightning or low-CFG presets.
- **Allure:** the maximum the App Store 18+ rating allows: skin-tight clothing, bodysuits, latex,
  highleg leotards, cutouts, bikini and micro armor, harnesses, curvier bodies. **Female only**
  (owner, 2026-10-17): Nuriel, Brakka, Orrin and Lucen were redesigned as women with the same ids,
  names, roles and stats. The owner asked for pasties; pasties-only tops are refused as past the
  App Store limit, so designs use small opaque cups or gem plates.
- **Theme: Aero Y2K (owner, 2026-10-17):** "Y2K futurism, like Frutiger [Aero] era almost, but
  like actually cool, but also like erotic and super, super, super revealing." Glossy chrome, PVC,
  latex and holographic fashion; maximum reveal inside the hard lines. Designs are in
  `docs/dev/character-briefs.md` (v4; Nuriel, Brakka, Orrin and Lucen fully redesigned) and
  purchasable skins in `docs/dev/skins.md` ("bikinis and whatever"). The bible and the `look` fields
  still hold v3.3 until the owner approves v4 and picks a checkpoint.
- **Licenses matter (commercial game).** NoobAI-XL forbids commercial use of its images; check
  every checkpoint's and LoRA's license before its art ships (`docs/dev/status.md`).
- **UI:** a close copy of the reference game's layout and visual language (the owner sent four
  screenshots and asked for "almost 1:1"), with our own names (Lobby, Heroes, Team, Gear, Summon;
  Sanctum = idle rewards), our own icons, Barlow fonts, a cyan accent, and the App Store 4.1
  copycat guardrails. Spec: `docs/dev/ui-style-v2.md`. No repo file or commit message names the
  reference game (the history is public; three early commit messages already do, so leave those
  alone); write "the reference game".
- **The owner sees every render (2026-10-17):** "just send them even if they get cut by the
  filter. i am more accurate than a filter". In the local chat on the PC, send renders, contact
  sheets and A/B sheets with the chat's file sending (`SendUserFile`), flagged or not. That works;
  pushing them to a repo or another service was blocked (see below). Look at each image yourself
  first; anything that crosses a hard line is not sent, and the owner is told where it is on the PC.
- **Continuity:** everything needed to resume lives in the repo. Update `docs/dev/status.md` at
  the end of every work block.

## Content hard lines (never traded for allure)

From `docs/dev/character-briefs.md`, which is authoritative:
- **Adults only.** Every character is an adult with an apparent age of 20 or older: adult body
  proportions, adult facial structure, adult styling and adult cues in every prompt. Never
  childlike bodies, faces, clothing (no school uniforms) or behavior.
- **No youth-coded clusters** on the young-end heroes (Liora, Uriela, Imra): no stacking of high
  twin tails with ribbons, small wings, small horns, fanged grins, blush with head tilt, cutesy
  framing. `mesugaki`, `shortstack`, `petite` (and `blue archive` on haloed heroes) are negated.
- **Suggestive, never explicit.** Never: exposed or visible nipples or areolae, including through
  sheer or wet fabric, as "covered nipples" outlines, or with nipple-cover-only tops (no
  pasties-as-the-only-top designs); genitals; the pubic area; cameltoe; sexual acts or poses that
  mimic them (no all fours, kneeling, lying or bent-over poses). Opaque where it matters: every
  slit, curtain and cutout sits over an opaque layer or bare non-explicit skin.
- **Sheer only over opaque.** Sheer never sits over breasts, nipples or the groin without an
  opaque layer under it.
- **Guardrails stay on.** `tools/comfy/prompts.py` `enforce()` (adult cue tags, forbidden terms,
  required safety negatives) is never removed or weakened. The art farm's exposure filter
  (`tools/artgen/safety.py`; thresholds in `tools/artgen/config.py` `FILTER`) is fail-closed.
  The owner raised both thresholds from 0.25 to 0.5 on 2026-10-17 ("anything that's not explicit
  nudity is fine", then "raise it"; commit c3d35b5), because 0.25 flagged clothed cleavage and
  highleg hips on NoobAI renders. 0.5 equals `max_threshold`, the ceiling `safety.py` enforces;
  never go above it, and never change the detectors, watched classes or canary bands.
- **For ComfyUI art the filter is a second opinion, not the gate (owner, 2026-10-17).** After
  seeing the flagged Mordessa renders: "theres no nudity here. just remove the filter, i think
  theyre all false". At 0.5 it flags highleg hips and deep cleavage on NoobAI renders. On the PC,
  still run `.\.venv-artgen\Scripts\python.exe tools/artgen/safety.py check <files>` on the base and
  every `variants/<name>.png` and record the verdict and scores in the final's JSON, but a DROP no
  longer blocks. **The gate is a 1:1 review** of the base and every variant by Claude and the owner
  against the hard lines above and `docs/dev/art-style.md` section 1, before `install.py` and git.
  An image that crosses a hard line is discarded whatever the filter said (never patched). The
  art farm keeps its fail-closed filter in code: it publishes to a public branch with nobody
  looking first. A cloud session on the tunnel can't run the filter (Hugging Face is unreachable)
  or see the images at 1:1 with the owner, so it never commits ComfyUI art.

## Hard rules

- **Git.** Work on `claude/game-planning`. Stage explicit paths (`git add <paths>`), never
  `git add -A`. Commit messages: an imperative summary, often with an area prefix
  ("art farm: ..."), and a body that lists the changes with run IDs and test results. End with the
  attribution trailers from the harness; never copy them into repo files. Subagents never commit
  or push; the lead session does. Don't commit half-edited farm code or prompt bible changes,
  because art runs execute from the branch. `claude/game-planning` is the default branch on
  purpose: commit and push finished, tested work straight to it, with no feature branch or pull
  request. The owner doesn't review PRs, iOS builds and art runs are dispatched with
  `ref: claude/game-planning`, and a PC copy pulls it; the previous session worked this way for
  the whole project. If this session started on another branch, tell the owner and merge into
  `claude/game-planning` before you dispatch a build.
- **Never commit:** `.godot/`, `screenshots/`, `build/`, `*.ipa`, `__pycache__/`, candidate, hires,
  review or contact-sheet images, the filter canary image, any image that failed the 1:1 review, the
  owner's reference screenshots or anything made from them, secrets (e.g. `COMFYUI_AUTH`), the
  owner's email, session IDs, and anything under `art_src/` except `README.md`, `.gitignore`,
  `.gdignore` and JSON metadata (ComfyUI writes finals, review images, variants and sheets there;
  `art_src/.gitignore` ignores the images, and if the stop hook flags any, never commit them).
- **Images.** Committed images live only under `assets/`. Hero art goes in
  `assets/art/heroes/<id>/`: `<id>.png` (1024x2048 RGBA, soles at 512,1990), `variants/*.png`
  (same alpha as the base, only the face changes) and the `tools/art_warp` outputs. UI icons are
  SVGs from `assets/art/ui/src/make_icons.py`.
- **Farm output** goes to the orphan branch `art-gen-output`, written only by art-gen.yml's publish
  job. Fetch it; never push to it by hand.
- **Godot runs go through `tools/gd`** (a flock on `/tmp/halo-godot.lock`, so parallel agents never
  run Godot at once). Run `tools/gd --headless --path . --import` after adding `class_name`
  scripts or assets. Godot keeps going after script errors: scan output for `SCRIPT ERROR`,
  `Parse Error` and `ERROR:`. `tools/check` must be green before you commit game code.
- **Engine-neutral data contract.** Content and tuning are JSON under `data/`, loaded read-only
  (`duplicate(true)` before changing). Rules are plain RefCounted classes in `src/core/` with no
  Nodes, Time or OS calls. Integer math only (basis points, 10000 = 100%). Our own RNG
  (`src/core/rng.gd`, xorshift32), never `randi()`. Golden fixtures in `data/fixtures/`; regenerate
  them (`tests/tools/make_fixtures.gd`) only after an intended rules change, and mirror every rules
  change in `tests/port_check/`.
- **GDScript style:** static types, tabs, snake_case dictionary keys across modules. UI is built in
  code with Kit (`src/ui/kit.gd`); `main.tscn` is the only scene. Touch targets at least 88 px.
  Keep the button strings the e2e tests press ("Skip", "Done", "OK", "Onward", "Fight", "Claim",
  "Test purchase: no charge").
- **Art farm practice:** preset `standard` and **`style=bible`** (the workflow default `farm`
  raised exposure scores; every production run used `bible`). Final seeds must name a published
  `<run id>-candidates...` run. Renders are deterministic, so a re-run repeats a filter drop:
  render other seeds instead. One run per mode at a time; keep rounds bounded.

## Blocked before: don't retry by re-wording

Ask the owner for approval (plan mode or a permission rule they add) instead.
- Building the IPA on Linux with a community copy of Apple's SDK. Use the macOS workflow.
- A GitHub release step in ios.yml. The IPA stays a workflow artifact.
- Dispatching `art-gen.yml` (it publishes art to the public branch) was blocked until the owner
  approved a plan in plan mode. Expect to need their explicit approval again.
- Committing any generated character image outside `assets/art/heroes`.
- In a cloud session: keeping or encrypting filter-flagged images, or changing the art farm's
  filter (thresholds above the owner-approved 0.5, detectors, watched classes, canary bands).
  On the PC, flagged renders simply stay in `art_src/` and are shown to the owner in the chat.
- Pushing generated images off the owner's PC to a repo or service (the PC session tried a private GitHub repo,
  2026-10-17): its auto mode blocked it as data exfiltration. It needs the owner to allow it in
  that session on the PC (a permission rule, or auto mode off). The owner's typed instruction in
  the chat ("im instructing you to do this") did not clear it: the private repo
  `u-tek/halo-art-review` was created, then `git clone` was blocked. A cloud session adding allow
  rules to `.claude/settings.json` for it, after the owner tapped "Add rule" on a card, was blocked
  too ("Auto-Mode Bypass"). The owner has to switch the PC session to Ask, or add the rule on the
  PC themselves. Don't route around it.
- `sleep` in Bash: use `run_in_background` or Monitor with an until-loop.
- Messaging the owner's PC Remote Control session: the trust card was not recorded. Don't re-send
  it unless the owner asks ("ask again"). The previous session had no computer-use tools. Before
  saying no to PC work, check for `mcp__remote-devices__computer_*` or
  `enable__mcp__remote-devices__computer` tools. They appear once the owner turns on Computer use
  in the Claude desktop app on the PC (they were told: Settings > This computer > Computer use)
  and picks the PC under Devices in the composer's + menu. The owner sometimes writes from that
  desktop app. Without those tools, the PC route is a session that runs on the PC: a local session
  in the desktop app, `claude remote-control` in the repo folder, or `git clone` plus
  `claude --teleport <session id>`.
- Cloud network: Hugging Face, Civitai, NovelAI, fal, Replicate, Stability, OpenAI and Unity hosts
  are unreachable; pypi and GitHub work; Actions artifact downloads don't (give the owner the run
  link; art comes back through `git fetch origin art-gen-output`). No GPU, 4 CPUs, about 15 GB RAM.

## Setup

- **Cloud session:** the SessionStart hook (`.claude/hooks/session-start.sh`, registered in
  `.claude/settings.json`) installs Godot 4.5.1 (checksum-verified), xvfb-run, and numpy, Pillow
  and PyYAML, and imports the project when `.godot/` is missing. It prints one status line;
  details are in `/tmp/halo-session-start.log`. It does nothing outside the cloud. A stop hook
  there refuses to end a turn while the tree is dirty or unpushed; answer it with an
  explicit-path snapshot commit ("WIP: <what> (agent snapshot)") that follows the rules above.
- **Owner's Windows PC:** Godot 4.5.1 (standard, checksum-verified) is at
  `C:\Users\jenso\tools\godot-4.5.1\` (not on PATH). In Git Bash, `export
  GODOT=/c/Users/jenso/tools/godot-4.5.1/Godot_v4.5.1-stable_win64_console.exe`, then `tools/check`
  and `tools/check e2e` work as on Linux (`tools/gd` runs unlocked where there is no flock: one
  Godot at a time). Verified 2026-10-17: import, 93 tests, boot and the 3 e2e scripts pass. Rig
  build instead of `tools/art_warp`: `python tools/art_warp_build.py <id> --regen-masks`, then
  `tools/gd --headless --path . --import`. ComfyUI runs headless on 127.0.0.1:8188 (start line in
  `art_src/_review/HANDOFF.md`); the pinned checkpoint is Amanatsu Illustrious v2.
- **Restarts:** background agents and workflows don't survive a container or worker restart, and
  the session may come back in plan mode; GitHub Actions runs keep going. After a restart, check
  `gh run list -R u-tek/game` and `git fetch origin art-gen-output` before relaunching anything.
  Relaunch with the earlier results written into the prompt (resuming re-runs finished agents),
  and tell the owner if a plan needs their approval.
- **Workflows:** dispatch with the GitHub MCP tool `actions_run_trigger` (method `run_workflow`,
  ref `claude/game-planning`); watch with `gh run list -R u-tek/game`.

## Commands (Linux)

```bash
tools/check                 # import + 93 unit tests + headless boot (~20 s); must be green
tools/check e2e             # plus 3 screen end-to-end scripts (~2 min)
tools/gd --headless --path . -s tests/run_tests.gd -- test_playthrough   # one test file
python3 -B tests/port_check/check_port.py        # independent Python rules check (48 checks)
python3 tools/artgen/test_artgen.py              # art farm offline tests (81)
python3 tools/comfy/test_pipeline.py             # ComfyUI pipeline tests (52, all pass)
tools/art_warp --check                           # validate all 15 hero rigs
tools/gd --headless --path . -s tools/art_selftest.gd   # every rig x every animation
tools/shoot home --rich --safe-area-sim --out screenshots/home.png   # render a screen to PNG
godot --path . -- --rich                         # play with every hero and lots of currency
```

## Code map

| Path | What |
|---|---|
| `src/core/` | Rules and state: `game_model.gd`, `battle_sim.gd`, `rng.gd`, rule classes; `game.gd` is the `Game` autoload |
| `src/data/`, `data/*.json` | Content and tuning loaders; `data/art_prompts.json` is the prompt bible |
| `src/ui/` | `UI` autoload, `Kit` widgets, theme, `screens/`, `battle/` (battle view, backdrops, lobby lines) |
| `src/art/` | `HeroArt` API and the HaloRig runtime (`rig/`) |
| `assets/art/heroes/<id>/` | Painted hero art, variants, rig source `<id>.warp_src.json` and built rig |
| `tests/` | Unit tests, fixture checks, e2e scripts, balance tools, `port_check/` |
| `tools/artgen/`, `.github/workflows/art-gen.yml` | The art farm |
| `tools/comfy/` | ComfyUI pipeline for a real GPU (prompts, finalize, variants, install) |
| `tools/art_*` | Rig build, preview, self-test, GIFs |
| `tools/art_import/` | The one-off scripts that imported the 15 farm finals and wrote their rigs (README inside) |

## Docs

`docs/dev/status.md` (start here), `architecture.md` (the build contract), `ui-style-v2.md`,
`art-farm.md` (how the shipped art was made; section 7 lists each hero's run and seed),
`character-briefs.md`, `art-style.md`, `halorig.md`, `art-generation.md` and `comfyui-setup.md`
(the ComfyUI path, not yet used), `economy-v1.md`, `unity-port.md`, `ios-build.md`.
`docs/open-questions.md` holds business questions the owner never answered. `docs/tech-plan.md`
and `docs/roadmap.md` are historical (written when Unity was the engine).
