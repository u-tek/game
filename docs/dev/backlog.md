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
  candlelight from 18:00 to 05:00. Left: the gift receipt, a check of every Halloween screen, the
  build on the phone by 2026-10-30 UTC.
- P2 todo **Every real day checked:** Christmas Eve, Christmas, New Year's Eve, New Year, Valentine's,
  three heroine birthdays (Lobby, hero page, roster, shop).
- P2 todo **Decorations for the other days:** snowflakes, gold stars, hearts and bunting to the bats'
  standard (take 1: ghostly snowflakes, a broken heart fill, flat pennants).
- P2 todo **The summon reveal, produced** (the money moment): a motion piece made with real tools,
  not code shapes. Pitch the take first in shots and a video.
- P2 todo **The first session:** the fresh-save guide loop circles 02 LOBBY on screens whose next step
  is right there (free pull on Summon, ENTER on Campaign, LEVEL UP on the hero page).
- P2 todo **Lobby restraint pass:** fewer stuck-on objects (bulletin, arrows and counter, NEXT label,
  team plate, stage plate, ENGAGE), one readable giant line.
- P2 todo **Settings is a stock list:** rebuild as the device panel of the brief (switches as
  hardware, a glass disc, serial codes), ON/OFF readable at a glance.
- P2 todo **Gear: no back; the empty state leads nowhere; 450 px of chrome above the first item.**
- P2 todo **Gallery: the strip is left-aligned and tiny; a locked look has no BUY step; dark lightbox.**
- P2 todo **Daily resets reopen when the day goes backwards** (time zone west): roll forward only
  (`game_model.gd` refresh_daily, free pull, Rue's haul, Champion). Rules change: port check + test.
- P2 done **Replay the opening, then SKIP, wiped the signature** (unit test).
- P2 done **On a birthday with 18+ on, the bulletin's sale opened a shop tab that doesn't exist.**
- P2 done **Notices waited for a Lobby rebuild**; **daylight saving read as travel** ("an hour" now).
- P2 done **The shop didn't refresh at midnight** (quests: todo).
- P2 done **Holding LEVEL UP to the cap left the pass sunk.**
- P2 done **A hit-stop during an ultimate's hold cancelled its freeze.**
- P2 todo **Too many reds:** Quests, Gear, Rival, Prints each print five or more red masses.

## P3

- P3 todo **One poster kit:** fold `poster_kit.gd`, `hero_poster_kit.gd`, survey `poster.gd` and
  `SignalKit` pieces into one kit; one `INK`/`PAPER` palette (about 35 copies) and one set of spacing
  constants. Done when: no file defines its own INK/PAPER and `tools/check e2e` is green.
- P3 todo **War claim pays by the current side; the oath promises a side switch no screen offers.**
- P3 todo **Profile ENLISTED date in UTC** (the rest is local).
- P3 todo **The record forgets stamped days after 400 days** (claims are pruned).
- P3 todo **Flaky e2e:** meta_screens_e2e "gem summon asks first" failed once and passed on a rerun
  (two frames may not be enough for the confirm); a "Lambda capture was freed" error in the same run.

## P4

- P4 todo **Per-skin 18+ art:** `HeroArt._built_art` uses `skins/<art>/adult/` when it exists (base
  nude as fallback); `test_skins.gd test_nudity_mode_drops_skins` updated.
- P4 todo **The War behind one interface:** every screen reaches the war through one class, with the
  offline simulation behind it, so a server drops in later.
