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
| Screen kits | `src/ui/v4/` | Built in parallel by three agents, to be folded into SignalKit: `poster_kit.gd` (Summon, Shop, Gear), `hero_poster_kit.gd` + `poster_card.gd` (Hero page, Roster, Team), `survey/` (Campaign 3D survey map: `iso_view`, `terrain_gen`, `survey_map`, print shaders; Spire `plate_stack`; `poster.gd`) |
| Battle and print kits | `src/ui/v4/battle/`, `src/ui/components/print_bits.gd` | Battle print pieces and the riso shader; drawn print bits (tick rule, dial, torn edge, dotted leader, crop marks, progress rule) and the Kit builders `print_label`, `tick_rule`, `halftone_ramp`, `fill_dial`, `sheet_pass`, `reward_receipt`, `loading_veil` |
| Rendered objects | `assets/art/ui/objects/`, `tools/blender/ui_objects.py` | Collage objects rendered in Cycles on the owner's GPU (4-10 s each): `coil_ink` (the poster's coil as black gloss), `coil_chrome`, `disc` (the machined coin under the Sanctum stamp). Gear: `tools/blender/gear_objects.py` models the 13 gear kinds and renders them in the 5 tier materials (Worn iron, Tempered steel, Gilded gold, Hallowed pearl, Eclipse black chrome with signal light) into `assets/art/ui/gear/`. `finish_objects.py` crops them and bakes a soft paper shadow; each file's object size and padding are constants in `home_screen.gd` |
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
| Campaign | exploded map layers (1), terrain (17), mission map (12) | A real 3D layered map per chapter: terrain slab, rivers, routes and the stage layer floating above it with leader lines to labels; the chapter as a data block (name, coordinates, stages cleared) |
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
