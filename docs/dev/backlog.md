# Backlog

The ranked work list for the autonomous blocks (the owner's autopilot brief).
One line per item: priority, status, what, and "done when". P0 broken, P1 visibly wrong, P2 below the
bar, P3 code health, P4 new things. Status: `todo`, `doing`, `done <commit>`, `parked` (needs the
owner: see `status.md` "Waiting on the owner"). Keep each item under about an hour; split big ones.

Sources: the audit of 2026-10-27 (every screen fresh / rich / skins / short, `screenshots/audit/`,
reviewed by eye and by four review agents; a code read by four agents, each finding checked by a
skeptic). Short-phone shots before 2026-10-27 23:30 UTC used notch insets on a 16:9 window (too
pessimistic; `--safe-area-sim` now gives a 16:9 window a home-button iPhone's insets), so short-phone
items are re-checked against `screenshots/audit2/`.

Not on the list on purpose (owner decisions the reviewers flagged): the faction growths on the poster
corners, the rendered currency icons in the masthead, no birthday question on the intake form.

## P0

- P0 done **Gallery: BACK dead after hiding the UI** (e2e check in meta_screens_e2e).
- P0 done **Formation's BATTLE pass under the nav**; Formation and Gear have a Back (they left the nav
  on 2026-10-23 but were still history roots).
- P0 not real: **Front oath SWEAR passes on short phones** (the old notch simulation; audit2 shows them).

## P1

- P1 done **The Halloween stamp never animates** (the claim's `changed` rebuilt the stamps first).
- P1 done **The Lobby date goes stale after midnight**: a new day reprints the poster.
- P1 done **Leaving in the victory pose lost the win.**
- P1 done **Champion retreat** used a try, counted no damage and returned to Campaign (e2e check).
- P1 done **District: a swipe that started on a free lot bought a prop** (e2e check).
- P1 done **Gallery in 18+ mode sells skins** that can't show; **hidden BUY still live**; **a tap
  undoes the zoom**; the strip highlight lands on a card being freed.
- P2 todo **Hero page: the level-up pass and abilities capsule sit over her legs and wings** (the
  stuck-on collage of the approved layout; move only with a take that keeps her as big).
- P1 done **Summon: the RATES card sat on her head** (Standard banner; the stubs at her feet stay as
  stuck-on collage).
- P1 done **Quests: the last order row was cut; two title sizes** (the GO boxes already had 108x86
  hit areas).
- P1 done **Shop: a long skin description ran into the price; the micro type crossed the name.**
- P1 done **Heroes: PWR ran into the tier numeral; the stars overflowed** (the numeral is gone: the
  frame says the rarity; the tabs already had 88 px hit areas).
- P1 done **Prints: the grade word was cut by the label strip; the count ran into its caption.**
- P1 done **Rival: 'HER LV · POWER' cut by the plate; the reward line overflowed the plate.**
- P1 done **Battle: a flame covered the SOULS count; the fifth FOES square printed over TEAM;
  '+40 SOULS' showed on wins that pay none.**
- P1 done **Campaign and Spire: the pass plate's sub-line was cut by its bevel** (every pass; the
  world arrows already had 88 px hit areas).
- P1 done **Settings: the band's micro type ran through the giant title.**
- P1 done **Lobby: the rights line was cut by the bulletin tab.** Not real with true insets: VIEW
  clipped and the > arrow hidden on short phones (audit2 shows both).
- P1 done **Calling: SKIP and the signature copy nearly invisible** (SKIP FOR NOW now sits on the
  form above ANSWER, 12 px, an 88 px target).
- P1 done **Profile: PORTRAIT > CHANGE tag over the avatar art** (the side menu's hit areas were
  already 88 px).
- P1 done **Toasts drew under modals; the loading veil drew under the bars.**

## P2

- P2 doing **Halloween is a moment** (2026-10-31): done: cut-paper bats on a taped thread (Blender
  renders; they swing with the tilt, a thumb brushes them, strung up in front of the player the first
  time), the stamp in pumpkin ink, the boot print run in pumpkin with HALLOWEEN on the proof stamp,
  candlelight from 18:00 to 05:00, the gift's receipt in pumpkin with a paper bat taped to it. Left:
  the last build on the phone by 2026-10-30 UTC.
- P2 done **Every real day checked** (2026-10-28, `screenshots/days/`): each holiday and birthday
  shows its line, stamp and ink. Christmas has no ink or decorations yet (see the next item).
- P2 done **Decorations for the other days:** white card snowflakes (Christmas Eve, Christmas), folded
  gold card stars (New Year's Eve, New Year), pink card hearts in Valentine's ink. Left: bunting for
  birthdays (the pennants are still flat).
- P2 doing **The summon reveal, produced** (the money moment): a motion piece made with real tools,
  not code shapes. Done: the gold foil has a real surface (a tiling normal map of creased facets,
  `tools/textures/foil_normal.py`, global `foil_n`), so it catches the glint facet by facet instead
  of reading as a smooth gradient. The Epic tell's "electric blue" was the desktop render only (see
  the shots item below); on the iPhone's path it is the intended violet. Left: the Legendary poster's
  restraint (foil, halftone, thorns and the stamp compete).
- P1 done **Shots didn't show what the phone shows:** on this Windows/Vulkan build the HDR 2D canvas
  is really 8-bit sRGB, so every shader-drawn colour (halftones, foil, paper relief, candle) printed
  darker and more saturated than on the iPhone, where HDR 2D is off (the band's red #ff5c29 came out
  #f81000). `tools/shoot` now renders with `--ldr` (the iPhone's path) unless SHOOT_HDR=1. Shots
  before 2026-10-28 16:30 UTC are in the old, darker colours.
- P2 done **The first session's guide pointed away** from a step on the screen itself: it no longer
  rings the nav there (free pull or a full ten on Summon, the first fight from Campaign or Team);
  Summon rings the free pull while the Sanctum claim waits; Team rings its Battle pass for the first
  fight. Next: walk the whole first session by shots (the third moment).
- P2 parked **Lobby restraint pass:** a "quiet" take to show the owner (shot param `take: "quiet"`:
  no bulletin card and tab, no hero arrows and counter, no NEXT label). Waiting on the owner.
- P2 done **Settings was a stock list:** rows are channel lines on a device panel (01.1 SOUND
  EFFECTS, mono caps, no stock glyphs); the switch's state word prints in full ink. Could go further:
  rendered hardware switches (Blender), a glass disc.
- P2 done **Gear had no Back** (top left now). Left: the empty state leads nowhere; the chrome above
  the first item is tall.
- P2 doing **Gallery:** done: the look strip sits centred when it fits, captions 11 px. Left: the dark
  lightbox is outside the poster language (a take to show the owner); a locked look's BUY pass only
  shows once the look is chosen.
- P2 done **Daily resets reopened when the day went backwards** (a flight west, a zone change): days
  roll forward only (unit test; port spec 8.1, 9c, 9e).
- P2 done **Replay the opening, then SKIP, wiped the signature** (unit test).
- P2 done **On a birthday with 18+ on, the bulletin's sale opened a shop tab that doesn't exist.**
- P2 done **Notices waited for a Lobby rebuild**; **daylight saving read as travel** ("an hour" now).
- P2 done **The shop and quests didn't refresh at midnight.**
- P2 done **Holding LEVEL UP to the cap left the pass sunk.**
- P2 done **A hit-stop during an ultimate's hold cancelled its freeze.**
- P2 doing **Too many reds:** done: Quests (red only on what is ready to claim: the CLAIM stickers and
  the map's ready circles), Gear (ink tier stickers on the sheet), Rival (the counter-pick tag and her
  line's label in ink). Left: Prints.

## P3

- P3 doing **One poster kit:** done: the palette has one source (41 files' INK, PAPER, SIG/SIGNAL,
  MATTE and BAND constants now point at SignalKit / Kit.BAND). Left: 72 inline uses of the same hex
  colours in expressions; folding `poster_kit.gd`, `hero_poster_kit.gd`, survey `poster.gd` and
  SignalKit into one kit (three copies of the pass alone); one set of spacing constants.
- P3 done **War claim paid by the current side** (no switch while a claim waits); **the oath promised a
  side switch no screen offered** (CHANGE TO ... on the Front at a week's start).
- P3 done **Profile ENLISTED date in UTC** (local now).
- P3 done **The record forgot stamped days after 400 days** (kept 3700 days now).
- P1 doing **Flaky e2e: "Lambda capture at index 0 was freed"** (likely found: two Summon timers
  captured the scroll strip in a lambda, and Godot prints this whenever a captured node was freed
  first, as when the e2e changes banners at once; now weak references; two full runs clean) prints now and then during
  meta_screens_e2e (3 of about 15 full `tools/check e2e` runs on 2026-10-27/28; 0 of 7 standalone
  runs), and tools/check fails a script on any ERROR line. No GDScript frames in the backtrace (the
  lambda runs from engine code: a signal, a tween or a timer), so the capture that was freed is
  unknown. Commit fe36c64 says the e2e was green; its full run had this error (0 check failures);
  three reruns of the script were clean. The summon confirm's two-frame wait is fixed (c156b9b).

## P4

- P4 todo **Per-skin 18+ art:** `HeroArt._built_art` uses `skins/<art>/adult/` when it exists (base
  nude as fallback); `test_skins.gd test_nudity_mode_drops_skins` updated.
- P4 done **The War behind one interface:** `WarFront` (offline front = today's simulation); a fake
  server front in test_war drives the War and receives the souls.
