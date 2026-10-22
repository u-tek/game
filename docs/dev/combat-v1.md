# Combat v1: scope (draft for the owner, 2026-10-20)

## The war version (pitched 2026-10-22; building since the same day: "yeah see what you can come up with")

**Built so far (2026-10-22):**
- **Front view** (`battle_screen.gd`): the team stands big in the foreground (ALLY_H 60% of the
  field), facing the camera, along a line 2.5 screens wide (LINE_ORDER puts the front pair in the
  middle); the camera glides to whoever acts or is hit (CAM_HOLD between focus changes, forced on
  ultimates); a sideways swipe on the field looks along the line for SWIPE_HOLD. Foes stand smaller
  in the mid-ground with a little parallax. Lunges are a step toward the mark (16% of the way for the
  team, 30% for foes). The team's overhead tags and ground rings are off (their cards carry HP).
- **Souls** (`src/ui/battle/souls_crowd.gd`): 40 flame wisps in the sky over the foes with a SOULS
  count; the player's share follows how much more of the foes' HP is gone than the team's; the
  winner takes them all (+40 SOULS on a victory). Display only: nothing is saved yet (the front and
  the economy come later).
- **Charm**: see Faction signatures below.
- **Ultimate close-up** (`ult_cinematic.gd`, the player's heroines; foes keep the band): the screen
  cuts to ink with her red halftone print and speed lines, her live rig in her skin fills it framed
  on her face (portrait rect, in rig units) playing her ultimate while the camera pushes in, the
  skill name lands huge across the foot; at least 1.5 s at 1x before the hit.
- **Encore** (rules in `battle_sim.gd` + port check, `encore` in `data/battle.json`): an ally
  ultimate within 3 s of the previous one is the next step of a chain (max 4); fired by hand each
  step adds +15% ultimate damage; auto chains show the same close-up with no bonus (any auto bonus
  made a first session clear chapter 1: `test_first_session_progress`). The close-up of a chained
  ultimate brings the previous heroine in from the lower left with ENCORE xN stamped in signal; a
  sticker over the cards counts the window down. Debug shot: battle `{"encore_demo": true}`.
- **Spotlight and Mark** (rules + port check, `spotlight` in `data/battle.json`; inputs only, auto
  uses neither): tap a heroine on the field to light her (+30% energy gain, +10% ATK; 3 s between
  switches): a warm beam behind her, the camera holds on her; tap a foe to mark it (the team's basic
  attacks go to it; Taunt still wins): a signal crosshair. A one-time sticker teaches the taps
  (setting `seen_tap_hint`). The camera swipe and the taps share the field (a drag is not a tap).
  Debug shot: battle `{"tap_demo": true}`.
- **The front** (built 2026-10-22, offline: `src/core/war_rules.gd`, `data/war.json`, GameModel
  `war*`, screen `front` from the Lobby's FRONT label, port spec 9d): the Oath (pick Heaven or Hell;
  switch only at a week's start), then the war map: seven sectors between HEAVEN and HELL, the front
  line at each sector's control, the player's sector pinned (tap a column to move it), the standing,
  the souls table, last week's claim (both sides rewarded, winners and sectors held more), a FIGHT
  pass. Every campaign or Spire win sends 40 souls to the pinned sector (the battle says where). The
  other side's hosts are simulated (seeded per day and sector), so it works with no server.
- Next: the balance pass; the player's district; the weekly Champion boss; the server (real sides).


The owner liked the War for Souls (`docs/dev/feature-ideas.md`: "this is better yes") and asked
"whats the combat going to be?". The draft below stays (big front-view heroines, mostly auto, tap
for ultimates); the war gives it its enemies, its score and its weekly fight:
- **Souls on the field.** A crowd of souls stands between the lines and shifts colour (gold for
  Heaven, red for Hell) as the fight swings; at the end the ones on your side fly into your soul
  count and push the front. A scoring layer on `battle_sim`; the win condition stays.
- **Enemies are the other side's players.** Each player sets a defence team; on the front you fight
  real teams from the other side, in their skins, run by the auto-battler. That answers the enemy
  art question (heroines, no monster art). Matched to your power, so no 2-6 style wall. Defenders
  lose nothing and get a note and a small reward when their team holds. Before the server exists,
  simulated teams fill the front (the Rival's way).
- **Faction signatures.** Infernal heroines charm (a new status: the enemy fights for you for a few
  seconds), Celestials inspire (heal, shield, win souls faster), the Fallen mix both. **Built
  2026-10-22:** `charm` in `battle_sim.gd` and the port check; every Infernal ultimate except
  Brakka's (a taunt: charm would pull a foe off her) charms its target for 2.5 s.
- **Hands-on stays optional:** ultimates and Encore chains, Spotlight, Mark, as drafted below.
- **Play time.** Away: your team keeps fighting the front (the idle haul is souls). Daily: a few
  charges, 2-3 minutes, cleared fights skippable. Weekly: **the Champion**, the other side's
  most-fielded heroine and skin as a giant boss; the whole side's damage adds up and everyone who
  joined is rewarded.

## Decisions so far (owner, 2026-10-20)
- **Combat should feel special, but the game stays mostly idle:** a few minutes of hands-on play a day.
- **What draws the owner to NIKKE:** the back view, hands-on shooting and cinematic ultimates. But "i don't want it to feel like a nikke ripoff".
- **v1 is front view only.** One front rig per hero (the animation plan, `docs/dev/halorig.md` 11-12). Back views, Skyfall and a camera that pans along the squad from behind all wait until after v1: "a mammoth task" for every hero and skin.
- **The owner's standing rules:** new features never make the game harder, and novel ideas beat genre staples.

## What stays
- **The rules core.** `src/core/battle_sim.gd` stays: deterministic 5v5 in 100 ms ticks, role targeting, energy to ultimate, the faction wheel, statuses and the 90 s limit. It is tested, port-checked and has fixtures. v1 adds a few inputs to it and does not replace it.
- **Formation, kits, gear, idle rewards, the campaign and the Rival.**

## What changes

### 1. The stage: the heroines big on screen
Today every heroine is about a tenth of the screen tall. In v1:
- **Allies:** a front line, large, in the lower two thirds. Two or three are in view at once, and the camera glides along the line to whoever is acting.
- **Swipe:** sideways to look along the line. Auto mode follows the action.
- **Enemies:** smaller, in the mid-ground, facing the camera as now. Only front-view art is needed.
- **The new rigs carry the show:** breathing, hit reactions with real weight, expression changes (hurt, determined, smug after a kill), hair and clothes on physics, and the tilt lighting.
- **Ultimate cinematic:** a full-screen close-up of her front rig (2-3 s: wind-up, expression, her big move, VFX), then a cut back to the stage as the hit lands.
- **Combat skins:** a skin brings its look into battle and its own ultimate cinematic (pose, VFX colour, expression). Cosmetic only.

### 2. Optional hands-on: three inputs, all done automatically too
- **Spotlight:** tap a heroine, or swipe her to the centre, to put her in the spotlight. She gets a rim and key light, a camera push-in, faster energy gain and a small damage boost. One at a time, with a short switch cooldown. Auto rotates the spotlight to whoever benefits.
- **Mark:** tap an enemy to make it the focus target. Taunt still wins. Auto marks sensibly, for example healers first.
- **Ultimate and Encore:** a heroine's portrait glows when she is ready, and a tap fires the cinematic. An ultimate fired within about 3 s of the previous one starts an Encore chain: rising bonus damage and a shared cut-in for two or more heroines. Auto fires them too, at a smaller chain bonus.

Balance rule: auto clears campaign content at the intended pace. Hands-on play only adds a bonus (faster clears, better grades), so nothing gets harder (owner rule).

### 3. Rules additions (`battle_sim.gd`, `data/battle.json`, port check, fixtures)
- `set_spotlight(ally)`: an energy-gain and ATK buff, with a switch cooldown.
- `set_mark(enemy)`: a target-priority override below Taunt.
- **Encore:** a chain window and a multiplier per step.
- An auto policy for all three, so a skipped or idle fight resolves the same way every time.
- Everything stays integer, seeded and replayable.

### 4. Balance pass
The stage 2-6 wall is real: a typical team needs about level 64 there, and the economy affords about 32-38. v1 re-tunes the campaign curve so a mostly-idle player keeps moving, with a target the owner sets (for example, about a chapter a day early on).

## Not in v1
- Back views and Skyfall.
- New monster enemy art: enemies stay echo-tinted heroes.
- PvP beyond the existing Rival.
- Voice.

## Effort and dependencies
- **Rules additions and their tests:** about 3-5 days.
- **Balance pass:** about 2-4 days.
- **Stage, camera, inputs, cinematics and VFX:** about 2-3 weeks of build.

The stage can be built on today's rigs and gets better as each hero receives her new layered rig. The ultimate cinematics depend most on the animation pipeline.

## Open questions for the owner
- Do Spotlight, Mark and Encore feel right as the hands-on layer, or is a different feel wanted, such as tap to shoot?
- Enemies: echo-tinted heroes (no new art), or monsters and demons (new art, a big job)?
- How fast should an idle player progress?
