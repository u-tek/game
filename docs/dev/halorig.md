# HaloRig: animation system for Halo & Horn heroes

HaloRig is our Spine/Live2D replacement: engine-neutral JSON + PNG data, a Godot runtime
(`src/art/rig/`), Python/GDScript build tools (`tools/art_*`), and shared animations. A Unity
port reads the same files (section 10).

There are two rig kinds. Both share bones, animations, mixing, springs, events and the tint
shader; they differ only in how pixels follow the bones.

| Kind | Source art | Used for |
|---|---|---|
| **warp** (default) | ONE painted full-body PNG + grayscale region masks + face variants | every hero (painted illustrations from the AI image service) |
| **cutout** | an SVG with one group per body part | the fallback silhouette (`_silhouette`); any future layered art |

`RigData.load_rig(id)` loads `<id>.warp.json` if present, else `<id>.rig.json`.

---------------------------------------------------------------------------------------------

## 1. Quick start: a new painted hero

```bash
# 1. Deliver the art (docs/dev/art-style.md section 2):
#    assets/art/heroes/<id>/<id>.png              1024x2048, transparent, feet at (512,1990)
#    assets/art/heroes/<id>/variants/eyes_open.png  (+ eyes_closed / mouth_open / smile / hurt)
# 2. Write assets/art/heroes/<id>/<id>.warp_src.json (copy seraphiel's; move pivots, edit the
#    region rules, list the variants). Coordinates are image pixels.
# 3. Build (masks from rules -> warp.json, overlays, portrait -> Godot import):
tools/art_warp <id> --regen-masks          # first time / after editing rules
tools/art_warp <id>                        # later: keeps hand-edited masks/*.png
# 4. Look at it:
python3 tools/art_review.py <id> r1        # detail / face / battle + portrait sizes
tools/art_preview my_jobs.json             # pose tests + animation frames (see tools/art_preview.gd)
python3 tools/art_gif.py <frames_dir> screenshots/rig/<id>_idle.gif --sheet screenshots/rig/idle_sheet.png
tools/gd --headless --path . -s tools/art_selftest.gd   # every rig x every animation
```

Nothing else is needed for the game to use the hero: `HeroArt.make_sprite(id)`,
`HeroArt.texture(id)` and `HeroArt.make_portrait(id, size)` pick the rig up automatically.
Heroes without art use the faction-tinted `_silhouette` rig.

---------------------------------------------------------------------------------------------

## 2. Coordinates, units, conventions

- **Canvas**: 1024 x 2048 source pixels, figure about 1900 px tall, **feet at (512, 1990)**.
- **Rig space**: origin at the feet (the canvas point `origin`), **+x right, +y down**,
  1 unit = 1 source pixel. All pivots, offsets and translations are rig units.
- **Rotation**: degrees, **positive = clockwise on screen** (y-down). A hanging arm raised
  toward the enemy is negative (-90 = level). Unity (y-up, CCW-positive): negate angles and y.
- **Bone transform**: `world = parent_world * T(local_offset + translate) * R(rotate) * S(scale)`;
  setup bones have no rotation (pivots only), so animation values are offsets from the setup.
- **Facing**: art faces RIGHT (3/4 view). `HeroSprite.set_facing(-1)` mirrors the whole node.
- **Sides are anatomical**: `_r` = her right = NEAR side (viewer's left, drawn in front, the
  weapon hand for right-handed heroes); `_l` = her left = FAR side.
- **Display size**: `HeroSprite` at scale 1 is battle size: `BASE_SCALE = 0.145`, so the
  2048-unit canvas is ~297 px and a 1900-unit figure ~275 px tall. Hero detail ~1100 px tall
  = node scale ~4.0 (scale 0.58 of the source).

## 3. Standard skeleton

Animations target these names, so shared animations work on every hero. Rigs may omit bones
(keys on missing bones are ignored) and may add extra bones (any name, with a parent).

| Bone | Parent | Typical pivot (female standard) | Role (warp region / cutout part) |
|---|---|---|---|
| root | - | feet (512,1990) | whole-body squash, tilt, hop, recoil |
| hips | root | pelvis (520,1066) | **body**: unassigned warp pixels follow it; skirt/legs parent |
| torso | hips | waist (530,960) | lower spine |
| chest | torso | (536,770) | breathing scale; wings, sleeves, arms parent |
| chest_upper | chest | (536,640) | cutout only: shoulders / collar |
| clavicle_r / clavicle_l | chest_upper | (500,470) / (566,466) | cutout: shoulder shrug |
| neck | chest (warp) / chest_upper (cutout) | (522,450) | |
| head | neck | top of neck (505..512, 340..390) | head tilt / nod; halo and horns ride on it |
| face | head | between the eyes (560,285) | warp: eyes/nose/mouth area, moves with `look` |
| hair_front | head | hairline | bangs (spring "bangs") |
| hair_side, hair_side_l | head | temple | side locks (spring "hair") |
| hair_back | head | nape/shoulder | long hair upper (spring "hair_long") |
| hair_long | hair_back | lower hair | long hair lower (spring "hair_long") |
| wing_upper_r/l, wing_lower_r/l (or wing_r/l) | chest | wing roots | flaps (spring "wing") |
| sleeve_r/l, cape, skirt, tail, ribbon_* | chest / hips | attachment point | springs "sleeve", "cape", "cloth", "tail", "ribbon" |
| arm_upper_r/l, arm_lower_r/l, hand_r/l | clavicle / chest | shoulder, elbow, wrist | cutout limbs; warp `arm_r/arm_l` (small gestures) |
| thigh_r/l, shin_r/l, foot_r/l | hips | hip, knee, ankle | cutout legs |
| weapon | hand (cutout) / hips (warp) | grip | `tip` = blade tip / orb, used for glows, trails, VFX |
| halo, horn_r/l | head | | accessories |

Spring presets are picked by name prefix unless the bone sets one (section 6.2):
`hair_front*`→bangs, `hair_back*`/`hair_long`/`ponytail*`→hair_long, `hair*`/`ahoge`→hair,
`skirt*`/`coat*`→cloth, `cape*`→cape, `ribbon*`→ribbon, `sleeve*`→sleeve, `wing*`→wing,
`tail*`→tail. Head-turn (`look`) factors by prefix: `face`/`eye` 1.0, `mouth` 0.95,
`hair_front` 0.7, `hair_side` 0.25, `hair_back` -0.35, `halo` -0.1, `horn` -0.15,
`wing_head` -0.3 (only the top bone of a chain shifts; children follow).

---------------------------------------------------------------------------------------------

## 4. Cutout rigs (`<id>.rig.json`)

Built by `tools/art_build <id>` from `assets/art/heroes/<id>/<id>.svg` (viewBox 0 0 1024 2048).
Each top-level `<g>` is one part with metadata attributes: `id` (= slot), `data-bone`
(default = slot), `data-parent`, `data-pivot="x,y"` (canvas px), `data-z` (draw order,
unique), `data-slot`/`data-variant`/`data-default="1"` for alternates (eyes open/closed...),
`data-spring="preset;key=value"`, `data-bend`, `data-axis`, `data-length`, `data-look`,
`data-tip`. An empty group with a pivot is a bone without art. Root attributes: `data-origin`,
`data-texel-scale`, `data-portrait="cx,cy,size"`, `data-tint-variants`, plus free `data-*`
meta (`weapon`, `attack`, `fx_color`). ThorVG-safe SVG only (no filters, CSS, text, images,
masks, blend modes). The tool rasterizes each part with Godot's renderer, trims it, writes
`parts/*.png` (mipmapped), the still, the portrait and the JSON, and validates (unknown parents,
missing pivots, duplicate z, art outside the canvas, forbidden SVG features).

```jsonc
{"format": "halorig", "version": 1, "id": "_silhouette", "canvas": [1024, 2048],
 "origin": [512, 1990], "texel_scale": 0.5,          // texture px per rig unit
 "look_px": [14, 8], "still": "..png", "portrait": "..png", "portrait_rect": [x, y, w, h],
 "meta": {...}, "bounds": [x, y, w, h],               // rig space
 "bones": [{"name": "hips", "parent": "root", "x": 8, "y": -924,  // pivot, rig space
            "lx": 8, "ly": -924,                      // offset from the parent pivot
            "axis": [0, 1], "length": 420,            // rest direction + reach (springs, bend)
            "spring": {...}, "bend": 0, "look": [x, y], "tip": [x, y]}],   // parents first
 "slots": [{"name": "eye_r", "bone": "eye_r", "z": 520, "default": "open",
            "attachments": {"open": {"texture": "parts/eye_r_open.png", "x": -15, "y": -8, "w": 30, "h": 16}}}]}
```
Attachment `x, y` = texture top-left relative to the bone pivot (rig units, unrotated);
draw the texture scaled by `1/texel_scale`. Slots are listed back to front.

---------------------------------------------------------------------------------------------

## 5. Animations (`*.anim.json`)

Search order: `assets/art/heroes/<id>/anim/<name>` (hero override), then for warp rigs
`assets/art/anim/warp/<name>`, then `assets/art/anim/<name>`. The shared sets are authored in
`tools/art_anims.py` (run it to rewrite the JSON); hero overrides can be written by hand.

```jsonc
{"name": "attack_melee", "duration": 0.8, "loop": false,
 "loop_start": 0.0,        // a looping anim repeats [loop_start, duration] after its first pass
 "hold": false,            // non-looping: keep the last frame (death) instead of fading out
 "mix": 0.06,              // crossfade-in seconds;  "mix_out": 0.2  fade-out when an overlay ends
 "bones": {"root": {"rotate":    [{"t": 0, "v": 0, "e": "cubic_out"}, {"t": 0.15, "v": -5}],
                    "translate": [{"t": 0, "x": 0, "y": 0, "e": "sine_in_out"}],
                    "scale":     [{"t": 0, "x": 1, "y": 1}],
                    "bend":      [{"t": 0, "v": 0.2}]}},          // radians, adds to spring bend
 "slots": {"eyes": {"attachment": [{"t": 0, "v": "open"}, {"t": 0.62, "v": "default"}],
                    "color": [{"t": 0, "c": "ffffffff"}]}},
 "look": [{"t": 0, "x": 0, "y": 0}],      // head turn -1..1 (x: +toward facing, y: +down)
 "fx": {"glow": [...], "hand_glow": [...], "aura": [...], "flash": [...], "trail": [...], "fade": [...]},
 "lunge": [{"t": 0.3, "v": 1.0}],         // share of the attack lunge HeroSprite applies
 "events": [{"t": 0.32, "name": "hit"}]}
```

- Keys are sorted by `t`. The ease on key *i* shapes the segment *i -> i+1*; default `linear`.
  `rotate` is additive degrees, `translate` additive units in the parent's space, `scale`
  multiplies. Values hold before the first key and after the last.
- Attachment value `"default"` means the slot's resting variant (the hero's default, or one set
  with `set_expression`). Missing variants fall back to the default, so shared anims can ask for
  `"hurt"` or `"smile"` safely.
- **Easing** (x in 0..1): `linear` x; `step` 0 until 1; `sine_in` 1-cos(πx/2); `sine_out`
  sin(πx/2); `sine_in_out` -(cos(πx)-1)/2; `quad_in` x²; `quad_out` 1-(1-x)²; `quad_in_out`
  x<.5 ? 2x² : 1-(-2x+2)²/2; `cubic_in` x³; `cubic_out` 1-(1-x)³; `cubic_in_out` x<.5 ? 4x³ :
  1-(-2x+2)³/2; `quint_out` 1-(1-x)⁵; `expo_out` 1-2^(-10x); `back_in` 2.70158x³-1.70158x²;
  `back_out` 1+2.70158(x-1)³+1.70158(x-1)²; `back_in_out` (Penner, c2=2.594909);
  `elastic_out` 2^(-10x)·sin((10x-0.75)·2π/3)+1.
- **fx channels** (0..1, can exceed 1): `glow` light at the weapon tip, `hand_glow` between the
  hands, `aura` ground ring, `flash` whole-rig whiten, `trail` weapon swoosh (cutout swings),
  `fade` dissolve into light (death).
- **Events**: `hit` (apply damage / spawn the hit spark: sync numbers to this), `release` (spell
  leaves the hand: spawn projectiles), `swing`, `windup`, `charge`, `impact`, `step`, `jump`,
  `land`, `cheer`, `ult_start`, `ult_pose`, `gone` (death finished), and `vfx_<kind>` (8.6).

### 5.1 Tracks, mixing, crossfades

`RigPlayer` has 3 tracks evaluated low to high; track 0 is the base (idle, run, victory,
death), track 1 holds actions (attack, cast, hit), track 2 is free. Each track has a current
entry and, while crossfading, the previous one. For every channel *c* in bone order:

```
acc = setup value (0 offsets, scale 1)
for each track (low -> high), with m = clamp(mix_t / mix, 0, 1) and w = track fade weight:
    if cur keys c:   v = lerp(prev keys c ? prev(c) : acc, cur(c), m);   acc = lerp(acc, v, w)
    elif prev keys c and m < 1:                                          acc = lerp(acc, prev(c), (1 - m) * w)
```
An overlay started on an empty track fades in over `mix` from the track below; when a
non-looping, non-`hold` overlay reaches its end it emits `anim_finished` and fades out over
`mix_out`, returning to the base track. Attachments are discrete: the top track whose weight
`w·m ≥ 0.5` decides. Events fire from current entries only (not while fading out), for keys with
`t_prev < t ≤ t_now`, handling loop wrap. Time advances by `delta · speed_scale`.

---------------------------------------------------------------------------------------------

## 6. Runtime features (`src/art/rig/rig_player.gd`)

### 6.1 Pose evaluation per frame
1. Advance tracks, collect events. 2. Sample + mix channels (5.1). 3. Head turn: for each bone
with a look factor `f` (only chain tops): `translate += (look.x·f.x·look_px.x, look.y·f.y·look_px.y)`
in the parent's space; `head.scale.x *= 1 - 0.05·|look.x|`. `look = anim look + look_extra`.
4. Solve world transforms parents-first with springs (6.2). 5. Draw (cutout: one node per slot
at `world[bone] * attachment offset`; warp: upload bone uniforms, 8.4). 6. Emit events.

### 6.2 Spring physics (secondary motion; Spine-4.2-physics equivalent)
Per spring bone (fixed step h = 1/60 s, at most 4 sub-steps per frame, frame targets
interpolated across sub-steps), in GLOBAL (screen) space so lunges and flips drive it:

```
o      = bone origin;  tip_rigid = world * (axis * length)        (animated pose, global)
hang   = o + G.basis * (axis * length * |bone scale|)             (rest direction in rig space)
target = lerp(tip_rigid, hang, g)  +  wind
wind   = (n1, 0.35·n2) · w·0.22·L·wind_mult,  n1 = .55 sin(1.3t+φ) + .3 sin(2.7t+1.7φ) + .15 sin(5.3t+.6φ),
         n2 = .5 sin(1.9t+1.3φ), φ = 1.7·bone_index, L = |tip_rigid - o|
p     += (target_step - target_prev_step) · (1 - i)               (inertia: part of the motion is carried)
a      = k·(target_step - p) - c·v;   v += a·h;   p += v·h
off    = clamp(signed_angle(tip_rigid - o, p - o), ±limit)        (negated if the transform is mirrored)
local rotation += off·(1 - b);   bend += off·b·1.6
```
Reset (p = target, v = 0) on the first frame and when the target jumps more than 2.5·L + 40.
Presets (`tools/art_spring_presets.json`, written into the rig JSON in full):

| preset | k | c | g | w | limit° | i | b |
|---|---|---|---|---|---|---|---|
| hair | 70 | 8 | 0.5 | 0.25 | 26 | 0.55 | 0.5 |
| bangs | 120 | 11 | 0.3 | 0.12 | 12 | 0.6 | 0.45 |
| hair_mass | 95 | 11 | 0.4 | 0.08 | 6 | 0.65 | 0.6 |
| hair_long | 42 | 6 | 0.6 | 0.35 | 32 | 0.45 | 0.6 |
| cloth | 65 | 8.5 | 0.6 | 0.25 | 14 | 0.6 | 0.5 |
| cape | 40 | 6 | 0.7 | 0.45 | 28 | 0.45 | 0.6 |
| ribbon | 30 | 4.5 | 0.5 | 0.6 | 40 | 0.35 | 0.7 |
| sleeve | 70 | 8 | 0.7 | 0.2 | 22 | 0.5 | 0.4 |
| wing | 110 | 11 | 0 | 0.12 | 10 | 0.7 | 0.55 |
| tail | 38 | 5 | 0.2 | 0.4 | 35 | 0.4 | 0.6 |
| accessory | 90 | 7 | 0.3 | 0.1 | 10 | 0.6 | 0 |
| weapon | 80 | 9 | 0 | 0.05 | 6 | 0.75 | 0 |

Override per bone: `"spring": "hair_long;limit=20;g=0.85"`. Long hair hanging from the head
needs high `g` (0.85-0.95) so it keeps hanging when the head turns.

### 6.3 Bend
Vertices at position `p` relative to the bone pivot are rotated by `bend · t²` about the pivot,
`t = clamp(dot(p, axis) / length, 0, 1.25)`: soft parts curve instead of turning rigidly.
Cutout: `rig.gdshader` on a 6x10 grid mesh per bendable part. Warp: per bone in `warp.gdshader`.

### 6.4 Blink, expressions
Every 2.5-5 s (20 % double blinks, 0.28 s apart) a slot showing variant `open` that also has a
`closed` variant shows `closed` for 0.11 s. `blink()` forces one. `set_expression(slot, variant)`
changes the resting variant (e.g. open Seraphiel's eyes on the detail screen).

### 6.5 Tint shader (`rig_tint.gdshaderinc`)
`flash` (mix to `flash_color`), `desat` + `shade`/`shade_color` (enemy echo: desaturate,
darks pulled to violet), `map_on` + `map_dark/mid/light` (luminance gradient map, used by the
fallback silhouette: dark #0d0a1c, mid = faction colour darkened 40 %, light = lightened 35 %),
`dissolve` (death fade: noise threshold `0.6·N(p/40) + 0.4·N(p/9) < 1.12·d - 0.06` discards,
a glow band in `dissolve_color` just above the threshold). N = value noise of `fract(sin(dot(p,
(127.1, 311.7)))·43758.5453)`, smoothstep-interpolated; p = mesh-local position.

---------------------------------------------------------------------------------------------

## 7. HeroSprite (what screens use) - `src/art/hero_sprite.gd`

`HeroArt.make_sprite(id) -> HeroSprite` (Node2D, feet at origin, battle size at scale 1).

| Method | Notes |
|---|---|
| `play_idle()` | base idle, stops actions |
| `play_attack(target_global_pos) -> String` | role/meta attack: caster+support → `attack_ranged`, spear → `attack_thrust`, others `attack_melee` (rig meta `attack` overrides). Melee lunges to 120 px short of the target and back |
| `play_cast() -> String` | `cast` (support role: `support_cast`) |
| `play_ultimate(target := INF) -> String` | `ultimate`, lunges for striker/assassin/guardian |
| `play_hit()`, `play_death()`, `play_victory()`, `play(anim)` | `play` puts looping anims (stun, run) on the base track, others as actions |
| `set_facing(dir)`, `set_echo(bool)`, `set_boss(bool)` | mirror; desat + violet shade; x1.3 + pulsing aura |
| `set_speed(mult)` | battle speed 1/2/4 (animations, events, physics) |
| `set_expression(slot, variant)`, `is_busy()` | overlay slots `eyes`, `mouth` |
| `get_point("chest"/"head"/"weapon") -> Vector2`, `vfx_point(kind)`, `get_height()` | global positions for VFX and damage numbers |

Signals: `anim_event(name)`, `anim_finished(name)`, `vfx_requested(kind, global_pos, facing)`.

**Event timings (seconds, warp set; cutout set in brackets):**

| anim | duration | windup / release | **hit** | VFX events |
|---|---|---|---|---|
| attack_melee | 0.80 | windup 0.15 | **0.32** [0.33] | vfx_slash 0.26 (lunge peaks 0.30) |
| attack_thrust | 0.80 | windup 0.18 | **0.32** [0.32] | vfx_thrust 0.27 |
| attack_ranged | 0.90 | release 0.40 | **0.48** [0.46] | vfx_bolt 0.40 |
| cast | 1.00 | release 0.55 | **0.60** | vfx_burst 0.55 |
| support_cast | 1.00 | release 0.50 | **0.56** | vfx_sparkle 0.50 |
| ultimate | 1.70 | ult_pose 0.65, release 0.92 | **0.98** | vfx_charge 0.10, vfx_burst 0.92 |
| hit | 0.45 | impact 0.00 | - | |
| death | 1.60 (hold) | impact 0.00, gone 1.50 | - | vfx_dissolve 0.85 |
| victory | 2.80, loops from 1.20 | land 0.46 | - | vfx_sparkle 0.50 |

Divide by `set_speed` multiplier for real time. VFX kinds and where `vfx_point` puts them:
`slash`/`thrust` (in front of the chest, facing side), `bolt`/`charge`/`burst` (weapon tip),
`sparkle` (head), `dissolve` (chest). The rig itself draws weapon glow, hand glow, ground aura,
whole-rig flash, the cutout weapon trail and the dissolve; projectiles, slash arcs and particles
belong to the battle screen.

**Performance** (this dev box, x86, Godot 4.5.1): rig update (animation + mixing + springs +
uniform upload) **0.17 ms CPU per rig per frame; 10 rigs = 1.7 ms**. Warp skinning runs on the
GPU (~1.6k triangles per hero, 3 influences + body per vertex). Draw calls per warp hero: 1
image mesh + 1 per visible face overlay + FX sprites. Texture memory per painted hero: 1024x2048
RGBA with mipmaps ≈ 11 MB (`texel_scale: 0.75` in the warp source ≈ 6 MB).

---------------------------------------------------------------------------------------------

## 8. Warp rigs (painted heroes)

### 8.1 Files (`assets/art/heroes/<id>/`)
| File | Who | Notes |
|---|---|---|
| `<id>.png` | art delivery | the painted image, also the UI still (`HeroArt.texture`) |
| `variants/<name>.png` | art delivery | same image with only the face changed (build input, not shipped) |
| `<id>.warp_src.json` | rigger | bones, regions + mask rules, overlays, grid |
| `masks/<region>.png` | generated or painted | grayscale weight masks (build input, not shipped) |
| `<id>.warp.json`, `overlays/*.png`, `<id>_portrait.png` | `tools/art_warp` | runtime data |

### 8.2 `<id>.warp_src.json`
```jsonc
{"image": "<id>.png", "origin": [512, 1990], "grid": [24, 48], "texel_scale": 1.0,
 "portrait": [cx, cy, size],               // head-and-shoulders square, image px
 "look_px": [14, 8], "meta": {"weapon": "sceptre", "attack": "attack_ranged", "fx_color": "#ffe9a8"},
 "body_bone": "hips",                       // gets every weight the regions don't take
 "bones": [{"name": "head", "parent": "neck", "pivot": [512, 390],
            "spring": "preset;key=value", "axis": [x, y], "length": L, "look": [x, y], "tip": [x, y]}],
 "regions": [{"name": "face", "bone": "face", "mask": "masks/face.png", "rule": {...}}],   // priority order
 "overlays": [{"slot": "eyes", "bone": "face", "base": "closed", "default": "closed", "z": 10,
               "rect": [x, y, w, h],        // optional: only look for differences here
               "threshold": 24, "margin": 10,
               "variants": {"open": "variants/eyes_open.png", "smile": "variants/smile.png"}}]}
```
`base` names what the painted image already shows; it becomes an attachment without a texture.

### 8.3 Masks: conventions
- One 8-bit grayscale PNG per region, **same size as the image**; white = moves 100 % with the
  region's bone, black = not at all, grays blend. The build blurs masks by a quarter grid cell
  before sampling, so hard edges are fine; feathering 10-30 px gives softer, nicer warps.
- **Regions are listed in priority order**: where masks overlap, the first region takes its
  weight and later ones only get the remainder. List details before what contains them:
  `face, hair_front, weapon, arm_*, hair_long, hair_side*, hair_back, head, wings, sleeves,
  chest, cape, skirt`. Whatever no region takes follows `body_bone` (hips).
- Include a margin of transparent background around moving parts (hair, cloth, wings) so the
  whole part moves, and keep region borders away from detailed paint where possible: the
  stretch between two regions happens at their border.
- Standard regions: `head` (head + halo + hair top + horns), `face`, `hair_front`, `hair_side*`,
  `hair_back`, `hair_long`, `chest` (shoulders to waist, wide feather: breathing), `skirt`,
  `cape`, `wing_upper_r/l`, `wing_lower_r/l` (or `wing_r/l`), `tail`, `weapon`, `sleeve_r/l`,
  `arm_r/l`.
- **Rules** generate masks without a painting program (written to `masks/` when the file is
  missing or with `--regen-masks`; afterwards you may paint over them):
  `polygon {points}`, `ellipse {center, radius}`, `color {within, hsv_min, hsv_max}` (0-255
  HSV, hue may wrap), `alpha {within}` (opaque pixels), `union {rules}`, `subtract {rules}`
  (first minus the rest); common `grow` (px dilation) and `feather` (px blur). Example: hair
  = `color` hue 22-44, sat 18-140, val ≥ 120 within a polygon around the hair.

### 8.4 Mesh and skinning
A `cols x rows` grid over the image's alpha bounds (+24 px), cells with no opaque pixel culled.
Per vertex at image point `x`: `remaining = 1; for region in order: w_r = mask_r(x)·remaining;
remaining -= w_r`; keep the 3 largest (renormalize if > 1); the rest goes to `body_bone`.
Bone axis/length for springs and bend come from the region mask (weighted centroid direction
from the pivot, maximum reach), unless given.

Deformation of a vertex `p` (rig space, rest):
```
deform_b(p) = W_b · bend_b(p - rest_pivot_b)          W_b = bone world transform this frame
bend_b(l)   = R(bend_b · t²) · l,  t = clamp(dot(l, axis_b) / length_b, 0, 1.25)
p'          = w0·deform_b0(p) + w1·deform_b1(p) + w2·deform_b2(p) + (1 - w0 - w1 - w2)·deform_body(p)
```
Godot: `warp.gdshader` (uniform arrays `bone_a` = basis (x.x, x.y, y.x, y.y), `bone_b` =
(origin, rest pivot), `bone_c` = (axis, length, bend); `CUSTOM0` = (b0, w0, b1, w1),
`CUSTOM1` = (b2, w2); max 32 bones). Overlay patches get a 4x4 grid whose weights are
interpolated from the image grid, so they deform exactly like the pixels under them.

### 8.5 `<id>.warp.json`
```jsonc
{"format": "halowarp", "version": 1, "id": "seraphiel", "image": "seraphiel.png",
 "image_size": [1024, 2048], "canvas": [1024, 2048], "origin": [512, 1990], "texel_scale": 1.0,
 "look_px": [14, 8], "still": "seraphiel.png", "portrait": "seraphiel_portrait.png",
 "portrait_rect": [x, y, w, h], "bounds": [x, y, w, h],      // grid rect, rig space
 "meta": {...}, "body_bone": "hips", "max_influences": 3,
 "bones": [ ...same fields as 4... ],
 "slots": [{"name": "eyes", "bone": "face", "z": 10, "default": "closed",
            "attachments": {"closed": {}, "open": {"texture": "overlays/eyes_open.png", "x": -84, "y": -1784, "w": 190, "h": 66}}}],
 "mesh": {"grid": [24, 48], "vertices": [x0, y0, ...],          // rig units
          "uvs": [u0, v0, ...], "triangles": [i0, i1, i2, ...], "skin": [b0, w0, b1, w1, b2, w2, ...]}}
```

### 8.6 What a single painting can and cannot do
Good: breathing, sway, head tilt (≤ ~7°), head turn (`look`), blinks and mouth/eye swaps, hair
and cloth sway with physics, wing flaps (≤ ~7°), floating weapon bob/thrust (≤ ~30 px,
≤ 10°), whole-body squash & stretch, lean (≤ ~10°), lunge, recoil, hop, dissolve.
Not possible without extra art: limbs swinging through large arcs, turning around, anything
revealing unpainted areas. The warp animation set (`assets/art/anim/warp/`) stays inside these
limits; big actions are sold with whole-body motion + VFX (`vfx_<kind>` events).

---------------------------------------------------------------------------------------------

## 9. Tools

| Tool | Purpose |
|---|---|
| `tools/art_warp [id] [--regen-masks] [--check]` | warp build (`tools/art_warp_build.py`, Python 3 + Pillow + numpy) + Godot import |
| `tools/art_build [id] [--check]` | cutout build (`tools/art_build.gd`) + import |
| `python3 tools/art_anims.py` | rewrite the shared animation JSON (cutout + warp sets) |
| `tools/art_preview jobs.json` | render pose tests, timelines (frames), and the 10-rig benchmark |
| `python3 tools/art_gif.py frames out.gif --sheet sheet.png` | GIF (on #120e24) + contact sheet |
| `python3 tools/art_review.py id label` | detail / 1:1 face / hair crop / battle + portrait sizes |
| `tools/gd --headless --path . -s tools/art_selftest.gd` | every rig x every animation sanity test |
| `tools/art_svg2png.gd` | rasterize SVGs with Godot's ThorVG (cutout art) |
| `tools/art_hero__silhouette.py` | generator: the fallback silhouette (cutout SVG) |

## 10. Unity port notes
- Load JSON as-is. Convert rig space to Unity: `x_u = x / ppu`, `y_u = -y / ppu`, angles `-deg`.
  Keep composition order `parent * T * R * S`.
- Warp: build a `Mesh` from `vertices` (flip y), `uvs` (flip v: `1 - v`), `triangles` (reverse
  winding after the y flip), put `skin` into UV2/UV3 (`(b0, w0, b1, w1)`, `(b2, w2)`), and port
  `warp.gdshader` to a URP 2D shader with `float4 _BoneA[32], _BoneB[32], _BoneC[32]`
  (`material.SetVectorArray`). Or skin on the CPU in a job (about 650-1050 vertices per painted hero).
- Cutout: one `SpriteRenderer` per slot sorted by `z`, sprite pivot from the attachment offset.
- Port `rig_anim.gd` (sampling, easing table, events), the mixing in 5.1, springs in 6.2
  (fixed 1/60 sub-steps), and the tint shader in 6.5. Golden check: play `attack_melee` on the
  silhouette rig at 30 fps and compare bone world positions with Godot's.
