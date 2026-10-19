# Halo & Horn UI Style v4: "Signal" (editorial compositions)

Style v4 replaces v3 "Aero Y2K" (glass bubbles, aqua) and the v2 layouts. The owner asked for a
full redesign on 2026-10-19 from 22 reference images and chose: signal red-orange as the one
accent, "clean, grit on big moments", "rethink every screen", the Godot Mobile renderer ("I need
this to look exceptional"), and, after four rejected rounds, "mix them per screen".

## 0. The house style: the poster (owner, 2026-10-19)

After seeing two more Lobby concepts (a dark lab with the hero sealed under shrink-wrap film, and
a pale instrument housing with a round window), the owner chose the poster: "the one i okay'd
before was so much better. i want that visual style to be maintained throughout the UI". So the
**look of every screen is the approved Lobby poster** (`lobby_v5_screen.gd`); "mix them per
screen" only means a screen's content may borrow its reference's idea (a dossier, a layered map, a
contact sheet), drawn in the poster style:

- A paper matte page (#f5f4f0) with printed poster panels (paper #e9e8e2, soft shadow), still
  film grain on top.
- Ink #101113 for type and hairline rules; signal red-orange for one keyword or accent per poster,
  the halftone print and status lights.
- Dark vertical bands (#141517) carrying a red halftone print of a hero, with paper-white mono
  micro type.
- Giant compressed display type, turned on its side and cut off by the poster edge, two-tone where
  it crosses a band; mono micro type for labels, serials, issue numbers and dates; the slanted
  serif for signatures.
- Menus as small vertical mono labels with tick marks on a hairline rule, and footer strips
  ("01 HEROES / 02 TEAM ...") with a signal underline.
- Collage objects stuck on, sparingly: the pass button (main actions), stamps on silver discs, the
  coil, barcodes, matrix codes, status lights.
- Hero art in full colour in front of the type, boxed by a hairline, with a blurred red echo.
- Not: dark full-screen HUDs, glass panels, instrument housings, specimen film, machined
  dashboards, grids of game buttons.

## 1. The brief (read this first)

**Each screen is composed like one of the references. The interface lives inside that
composition; it is not a game menu with a new skin.**

Four rounds failed the same way: the v2 skeleton (top bar, side buttons, hero in the middle, a
stack of buttons, a nav bar) dressed in better and better materials. The owner: "you keep making
the same thing", and the problems they picked were "still a normal game layout", "not editorial
enough" and "reference pieces missing" (not "too many buttons"). The fifth round, the Lobby as a
printed poster (`lobby_v5`), got "this is like a billion times better".

So, for every screen:

- Start from the reference it is built like (section 3), not from the old layout. Keep the
  screen's functions; move them into the composition (a menu becomes poster labels, a stat becomes
  stat dots or a data table, a button becomes a pass, a stamp or a printed line).
- Editorial type: one giant element per screen (a name, a line, a numeral), often rotated or cut
  off by the edge; compressed and wide grotesk, mono micro type, serials, issue numbers, dates,
  signatures, barcodes, rules and ticks. Scale contrast: huge against tiny.
- Physical objects sit on the composition like collage: the OG-pass card (main calls to action),
  stamps, tags, glass slabs, light tubes, machined knobs (`Plate`, `GlassBlock`, `LightStrip`).
- One accent: signal red-orange (`Kit.ACCENT`) for the main action, status lights and one keyword.
- Grit on big moments only: halftone, film grain, duotone, glitch (summons, loading, hero pages,
  battle results).
- The hero art stays in full colour and is never covered by a menu. Halftone or duotone copies of
  it are background elements only.
- Never copy a reference image or trace it: rebuild the idea as our own working asset (a poster
  cannot be a button; the map must show our stages). The references stay private (section 5).

## 2. The kit

| Piece | Where | Notes |
|---|---|---|
| Tokens | `Kit` constants | `ACCENT` #ff4b1f, `BONE`, `METAL_TOP/BOTTOM`, `LED`, graphite `BG`; token names are v2's so old screens compile |
| Type | `Kit.font()` | Archivo variable: `title`, `wide`, `wide_black`, `compressed`, `compressed_light`, normal and condensed weights; JetBrains Mono `mono`, `mono_bold`; Instrument Serif `serif`, `serif_italic` (signatures, captions). All OFL (`assets/fonts/LICENSE-fonts.md`) |
| Plate | `src/ui/components/plate.gd`, `src/ui/shaders/plate.gdshader` | A shape rendered as a machined part in a photo studio: presets `silver`, `graphite`, `slate`, `signal` (emissive), `dial`, `ink`; cut corners or any polygon (`cut_rect`, `tab_bottom`, `tab_top`), circles, screws, engraved contour grooves (`topo`), `recess` (cut in), contact + soft shadow, glow that spills onto neighbours (`Plate.relight_all`), reflections that follow the phone's tilt (`ui_tilt`), `set_pressed_look` (sinks 3 px) |
| GlassBlock | `plate.gd`, `refract_glass.gdshader` | Thick frosted glass: 32-tap blur, edge refraction, dispersion, fresnel rim, light sweep |
| LightStrip | `plate.gd`, `light_strip.gdshader` | Emissive tube; breathes, flickers, blooms, lights nearby plates |
| HUD pieces | `src/ui/components/hud.gd` | `Ring` (instrument dial), `Leader` (callout that draws on), `Ruler`, `Led`, `Dots` (stat dots), `Scan`, `Dust` (bokeh) |
| Halftone | `src/ui/shaders/halftone.gdshader` | Any texture as rotated ink dots (light or dark dots) |
| Grain | `src/ui/shaders/grain.gdshader` | Multiplied film grain |
| SignalKit | `src/ui/components/signal_kit.gd` | Shared v4 pieces: `plate()`, `pass_button()` (the OG-pass call to action), `etch` / `etch_icon` (text cut into metal), `pill`, `stamp`, `matrix`, `barcode`, `coil`, `halftone_material`, `grain`, `relight` |
| Screen kits | `src/ui/v4/` | Built in parallel by three agents, to be folded into SignalKit: `poster_kit.gd` (Summon, Shop, Gear), `hero_poster_kit.gd` + `poster_card.gd` (Hero page, Roster, Team), `survey/` (Campaign: worlds `world_dossier`, `world_view`, `planet.gdshader`; the terrain model `iso_view`, `terrain_gen`, `survey_map`, `survey_legend`, `model_terrain` / `molten_river` / `cloud_sprite` / `contact_shadow` shaders; Spire `plate_stack`; `poster.gd`, whose `vfont` / `tv` set Archivo's axes by OpenType tag) |
| Battle and print kits | `src/ui/v4/battle/`, `src/ui/components/print_bits.gd` | Battle print pieces and the riso shader; drawn print bits (tick rule, dial, torn edge, dotted leader, crop marks, progress rule) and the Kit builders `print_label`, `tick_rule`, `halftone_ramp`, `fill_dial`, `sheet_pass`, `reward_receipt`, `loading_veil` |
| Rendered objects | `assets/art/ui/objects/`, `tools/blender/ui_objects.py` | Collage objects rendered in Cycles on the owner's GPU (4-10 s each): `coil_ink` (the poster's coil as black gloss), `coil_chrome`, `disc` (the machined coin under the Sanctum stamp). Gear: `tools/blender/gear_objects.py` models the 13 gear kinds and renders them in the 5 tier materials (Worn iron, Tempered steel, Gilded gold, Hallowed pearl, Eclipse black chrome with signal light) into `assets/art/ui/gear/`. `finish_objects.py` crops them and bakes a soft paper shadow; each file's object size and padding are constants in `home_screen.gd`. **Worlds:** `tools/blender/planets.py` models the six chapter planets as node-graph terrain (terraced highland, canyon badlands, crater maria, an ice shell with lineae, lava fields, crystal fields) and bakes them onto a sphere in Godot's UV layout; `finish_worlds.py` turns the bakes into `assets/art/worlds/w<N>_albedo.jpg` (2048 x 1024, cavity baked in), `_normal.jpg` (1536 x 768, sphere-frame normals from the 2x height, fine relief boosted) and `_height.png` (1024 x 512: height + feature mask). `tools/blender/clouds.py` renders six volumetric cumulus (and their top-down silhouettes) that `finish_worlds.py clouds` packs into `clouds.png` / `clouds_shadow.png`. All of it runs on the CPU too (pass `cpu`) |
| Physical paper | `src/ui/components/physical_kit.gd` (`PhysicalKit`), `src/ui/shaders/paper.gdshader`, `paper_relief.gdshader`, `deboss.gdshader` | The owner's "make the game feel physical" (references 23, 24 of the v5 set). Every poster sheet (`PosterKit.poster`, `HeroPosterKit.poster`, survey `Poster.poster` all call `PhysicalKit.sheet`) is real paper: a seamless 512 px tile (grey felt for cool fills, warm parchment for warm ones: `paper_felt`, `paper_parch`, each a grey detail map and a normal map) lit by the key light, which leans with `ui_tilt`; a hair of sheet thickness (lit edge toward the light, shaded lip opposite), a contact shadow and a soft shadow on the matte. Sheets of 160k px² and up get the relief overlay (a BackBufferCopy, viewport mode, then `paper_relief`): the print already on the sheet is re-lit through the grain; children holding a hero figure (`HeroBox`, `HeroAnchor`, meta `above_paper`) stay above it. The giant titles (`PosterKit.giant`, `HeroPosterKit.giant`, `BP.giant`, the Lobby's line, dialog titles) sit in a `PhysicalKit.deboss` CanvasGroup: pressed into the paper (shadowed wall toward the light, a paper rim away from it). Light dialog sheets get `PhysicalKit.paper_fill` and an orange LED by the serial. A/B: `HH_PHYS_OFF=relief,deboss` (debug builds) leaves those out. Screen reads are in UI px via the `ui_px` global (main.gd) |
| Physical objects | `assets/art/ui/physical/` (+ `physical.json`), `tools/blender/physical_objects.py`, `tools/blender/finish_physical.py` | Cycles renders, top down, lit like the UI, each with its own contact shadow (shadow-catcher floor): **thorns** `thorn_<chrome\|black>_<tl\|tr\|br\|bl\|edge\|clump_a\|clump_b>` (liquid chrome: fused curve branches with twisted vines, knots and thorns, voxel remeshed; chrome carries blue crystal and pale fur, black carries red jelly and a red eye; grass tufts), **jelly** `jelly_<tl\|tr\|br\|bl\|edge\|clump>` (wet wine-red jelly under fuzzy moss, LED beads sunk in), **hardware** `dome_<up\|down>`, `bezel_<up\|down>` (red cap in a knurled silver bezel), `led_<green\|orange\|red\|cyan>_<on\|off>` (diffused LEDs, glow baked in: nothing relies on bloom), **acrylic** `acrylic_tab` (clear, frosted, steel eyelet) and `acrylic_card` (orange, halftone dot grid, round cutout) as `_t` (transmission + coverage) and `_l` (added light) from a render over black and over white. Use: `PhysicalKit.growth(faction, shape, parent, at, ppu)` (Celestial chrome thorns, Fallen black thorns, Infernal jelly; `at` = the poster corner), `PhysicalKit.Led`, `PhysicalKit.PushCap` (`set_pressed`), `PhysicalKit.Acrylic` (frosts what is behind it). Where: the Lobby (growth by her faction over the band's two left corners, under the stuck-on pieces; LED status lights; the acrylic tab is the bulletin's index, tap for the next bulletin), Summon (a growth per banner, the orange card carries the pity readout, the x10 ticket's dome press cap), Victory (chrome thorns), Defeat (a jelly frame), the Sanctum sheet (bezel button beside Claim, green when there is something to collect). **Re-render:** check `nvidia-smi --query-gpu=memory.used --format=csv,noheader` (over 2500 MiB: add `--cpu`), then `blender --background --factory-startup --python tools/blender/physical_objects.py -- <dir> "thorn_*,jelly_*,led_*,dome_*,bezel_*,acrylic_*" 256` (about 10 s a piece on the GPU, 2-3 min on the CPU), `python tools/blender/finish_physical.py <dir>` (crops, scales, bakes LED glow, splits the acrylic, writes the manifest; `python tools/blender/finish_physical.py paper` makes the paper tiles), then `tools/gd --headless --path . --import`. About 6 MB in all |
| Old Kit/theme | `theme.gd`, `KitBox.signal_look` | Restyled to graphite, bone and signal with cut corners, so screens not yet rebuilt stay coherent |

## 3. Screen by screen

The content ideas per screen, all drawn in the poster style of section 0 (the summon's specimen
packs, the gear's studio objects, the dark map terrain and the device panels below are replaced
by printed equivalents: a run of printed posters, a printed catalogue sheet, ink line work on
paper).

| Screen | Built like (reference no.) | Composition |
|---|---|---|
| Lobby (`home`) | mint poster (3) | **Approved mockup `lobby_v5`.** A poster on a paper matte: dark band with the hero's face as red halftone, her lobby line set huge in compressed type and turned on its side behind her (keyword in signal), the hero in full colour boxed by a hairline, small vertical labels down the right edge as the side menu (Daily, Offers, Spire, Shop) with ticks and a status light, a coil, the Campaign pass (OG-pass card) and the Sanctum stamp stuck on; under the poster the five sections as a footer strip, the date and her signature. Tap her for another line (the poster resets) |
| Hero page | Thatcher poster (4) | Giant name across, vertical repeated name, stat dots (HP, ATK, SPD ...), ID code, faction and role lines, bio paragraph, barcode, signature, framed pixel-mosaic squares, a rounded capsule with "/ ULTIMATE > ..." and "/ PASSIVE > ..." blocks; level up and gear as pass objects |
| Heroes roster | specimen packaging (7, 18) | Each hero a sealed specimen card with label, serial and rarity stamp; filters as printed tabs |
| Team | numbered units (19), device panel (22) | Five numbered bays "01-05" on a machined plate, big stencil numerals, power readout |
| Campaign | planet dossier (v5 ref 25), isometric terrain with clouds (v5 ref 26), mission map (12) | **Worlds (chapter select):** each chapter is a planet on a dossier poster (`world_dossier.gd`, `world_view.gd`): the Blender-baked planet turning in real time (`planet.gdshader`: a grey studio render of the relief on the day side, halftone ink dots and an ink terminator on the night side; lava glows, ice and crystal glint; drag to turn, tap to dive in), ring arcs, ticks, "Loading ..." typing in, the MASS tag, a barcode ring, a progress gauge, the next world peeking in at the right edge, the catalogue mark ("01 S1 \|"), the chapter name huge between ‹ › over a ghosted chapter number, a two-column mono data list (host, stages cleared, enemy levels and grades, recommended power, counter, boss, then the world's readouts from `data/worlds.json`), the ENTER pass (a locked world: LOCKED stamp and its access key). A new chapter's first visit opens on its world; ENTER dives into the planet (it grows past the poster, a paper flash) and the map prints with the story. **Map:** the chapter as a physical relief model lying on the poster (`survey_map.gd`, `model_terrain.gdshader`), shaped like its world, its stage route a molten river (`molten_river.gdshader`: hot and flowing to the current stage, cooled crust beyond, pouring off the slab's edge), valleys lit warm, Blender cumulus drifting over it with their shadows, stage marks on the river with id tags on thin leaders, name labels for the selected stage and the boss, the survey data slip, the scale bar with a north arrow, and under it the route profile (`survey_legend.gd`: a sine wave through a row of stage circles, tap one to pick that stage). WORLDS on the index zooms back out |
| Spire | exploded layers (1) | Floors as stacked plates pulled apart; the current floor lit; boss floors marked |
| Quests | mission map (12) | Tasks as a document over a map: circles, routes, task panels |
| Summon | vacuum-sealed specimen (7), planet dials (5, 6, 14) | The portal is an instrument dial; each pull arrives sealed in a labelled pack that tears open; rare pulls get the big reveal |
| Gear | product shots (11, 18, 19), data table (14) | Items as studio objects with stickers and labels, stats as a mono data table with brackets |
| Shop | OG pass (20, 21) | Packs, passes and offers as physical cards |
| Battle | instruments (5, 6) in battle; Tarmac print (8, 15) for results | HUD as instrument readouts; victory and defeat as two-tone risograph prints |
| Settings | ERUPT device (16) | One device panel: switches, a glass disc, serial codes |
| Loading screens | mint poster (3), Tarmac (8) | Halftone hero posters with a line of type |
| Sanctum (idle claim) | chamfered instrument (5) | Gauges and a fill dial |

## 4. Rendering notes (Mobile renderer, HDR 2D)

- `project.godot`: `rendering_method` and `rendering_method.mobile` are `mobile`;
  `viewport/hdr_2d=true`. iPhone uses Metal; desktop uses Vulkan (`tools/shoot` picks Vulkan on
  Windows; `SHOOT_DRIVER` overrides; Linux cloud boxes fall back to OpenGL without bloom).
- `main.gd` adds a WorldEnvironment with glow over the canvas (threshold 1.0) and drives the
  `ui_tilt` shader global (high-passed gravity on a phone, a slow drift elsewhere).
- The canvas is linear HDR. The new shaders do their maths in sRGB numbers (colour uniforms have no
  `source_color` hint) and convert at the end (`to_canvas`: pow 2.2, and alpha corrected so a
  translucent dark darkens as it would in sRGB). Only emissive edges and tube cores go above 1.0;
  the bloom does the halo. Translucent overlays from the old theme blend weaker in linear light:
  raise their alpha when a screen is rebuilt.
- Screenshots: the viewport texture is linear float data. `main.gd _capture()` converts it to sRGB
  before saving (without that, captures look dark and over-saturated; the display is fine).

## 5. The references

22 images the owner sent on 2026-10-19 (Creative Commons according to the owner, except the
game-character poster). They are not in the repo and must never be committed or uploaded. On the
owner's PC a copy is in `D:\AI\halo-private\ui-refs-v4\` (1.jpg to 22.webp); a session elsewhere
asks the owner to send them again.

1 exploded isometric map layers with labels (green areas, urban, network, hydrography, contours) ·
2 chrome thorn sculpture on a textured plate with type · 3 mint two-tone poster, giant rotated
type, halftone band, coil, vertical labels, date and signature · 4 red/cream character dossier
poster (giant name, stat dots, bio, barcode, signature, pixel squares, weapon capsule) · 5
chamfered white instrument around a planet · 6 round instrument around an orange planet · 7 body
in a vacuum-sealed pack with a product label · 8 red risograph collage with film stills · 9
biomech skull, black and white · 10 3D sculpture collage poster · 11 white techwear device with
stencil type and circuit lines · 12 dark map interface with circles and panels · 13 faceted glass
head · 14 planet with a mono data table and brackets · 15 red risograph poster with a text block ·
16 sage metal device with LEDs, frosted disc, lava photo, serial code, display serif · 17 isometric
terrain with clouds and climate tables · 18 white resin skull with stickers · 19 white robot
helmet numbered 09 · 20, 21 OG pass card: brushed silver plate with QR, knob and stamp over a
glowing green plate, barcode tag · 22 dark layered device panel: matte plates with stepped
outlines, engraved glyphs, light tube, frosted glass block, round knob, cut-out hole, braille dots.

A second set (2026-10-19, the owner: "make the game feel physical ... copy them and their elements",
Creative Commons according to the owner) is on the PC in `D:\AI\halo-private\ui-refs-v5\`: 23 grey felt
poster with debossed type, black liquid-chrome thorns with blue crystal and white fur, a red dome, a red
button in a knurled bezel, small LEDs, an orange acrylic card with a dot grid and a round cutout · 24
parchment poster framed by wet red jelly under moss with LEDs sunk in, a clear frosted acrylic tab · 25
a grey planet with HUD rings and a mono data list · 26 an isometric terrain with a molten river,
clouds and leader lines. The physical objects (section 2) re-create 23 and 24's elements from code;
no pixels of them are used.

## 6. Mockups

```bash
tools/shoot lobby_v5 --rich --safe-area-sim     # the approved Lobby poster (mockup)
tools/shoot home --rich --safe-area-sim         # the real Lobby (home_screen.gd), built from it
```

The real Lobby keeps every function of the old one: the bulletin in the band is the old banner
carousel (summon, offers, chapter), the paper label at the foot of the band is the objective strip,
the Sanctum stamp opens the claim sheet, the pass is the Campaign plate, `< >` switch the lobby
hero, and the vertical labels are the side buttons (Daily, Offers, Team, Spire, Shop, Hero, View).
The guide marks the stamp, the Team label and the pass.
