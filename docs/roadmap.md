# Roadmap

Status: **Draft v0.1, historical** (written for a Unity team before the Godot v1 and HaloRig
existed; current state: `docs/dev/status.md`). Durations are rough ranges for a small team that is new to game
development. Treat them as planning placeholders and re-estimate at the end of every phase.

## Reality check first

Idle gacha RPGs are one of the most expensive mobile genres to make *and to run*:

- **Character art is the product.** Players spend money on characters they love the look of.
  The genre usually launches with dozens of heroes, each needing illustration, animation, skills
  and balance. After launch, new heroes are expected every few weeks.
- **It's a live service.** Revenue comes from events, banners and updates *after* launch. The
  team must keep producing content and running events indefinitely.
- **Economy and security are hard.** Mistakes in the economy or server code can be exploited
  within hours.

None of this means "don't do it". It means:

1. **Make the first goal a small, fun, playable slice, not "launch the game".**
2. **Get experienced help where mistakes are expensive**: at least a part-time or contract
   engineer with live-service/backend experience, and someone who has balanced a gacha economy.
3. **Gate each phase on exit criteria**, not on dates.

---

## Phase 0: Foundations (about 1 to 2 months)

Goal: the team can build and run a simple Unity project together.

- [ ] Everyone who will touch Unity completes **Unity Learn → "Unity Essentials"**; programmers
      continue with the **"Junior Programmer"** pathway (C# basics).
- [ ] Set up the GitHub repo with Git LFS and the Unity `.gitignore`; practice branching and
      merging on a toy project.
- [ ] **Learning project:** build a tiny idle clicker in 1 to 2 weeks (tap for gold, buy upgrades,
      earn gold while away, save/load). It's throwaway, but it teaches 80% of the core loop.
- [ ] Paper/spreadsheet prototype: a 3v3 battle resolved by hand or in a spreadsheet, with
      factions and a counter wheel. Is choosing a team interesting?
- [ ] Agree on working rhythm: weekly planning, a playable build every 2 weeks.

**Exit criteria:** the clicker runs on a real phone; everyone can pull, change and push the
project without breaking it.

---

## Phase 1: Pre-production (about 2 to 3 months)

Goal: answer the risky questions cheaply, before building content.

- [ ] **Battle prototype** with grey boxes: the `Core` battle simulation plus a basic playback
      scene. 5 placeholder heroes per side, positions, basic attacks, one active skill each,
      faction advantage.
- [ ] **Economy model** in a spreadsheet: currencies, sources/sinks, how fast a free player
      progresses on days 1, 7 and 30, and what a paying player gets per dollar.
- [ ] **Art direction target:** 3 character concept sketches, then **1 hero taken to final
      quality** (illustration + in-battle animation). This sets the art budget for every hero
      after it.
- [ ] **Spine vs Unity 2D Animation**: animate that one hero both ways and pick one.
- [ ] **Backend spike** (see `tech-plan.md`): pick UGS or PlayFab.
- [ ] Write the setting and faction bible (one page per faction).
- [ ] Decide the open questions marked **[Pre-prod]** in `open-questions.md`.

**Exit criteria:** people outside the team watch/play the grey-box battle and understand what's
happening; the economy model shows sensible day 1/7/30 pacing; art cost per hero is known.

---

## Phase 2: Vertical slice (about 3 to 4 months)

Goal: one short, polished, **offline** version of the game that feels like the real thing.

Scope (see the "Slice" column in `game-design.md`):

- 8 to 10 heroes across all factions, at least 3 at final art quality
- 2 campaign chapters, with idle/AFK rewards
- Summon screen with one banner, pity, and an odds disclosure screen
- Hero level-up and star-up (merging duplicates)
- One gear system
- Tutorial / first 15 minutes polished
- Analytics events wired in (even if only logged locally)

**Exit criteria:** 10 to 20 outside playtesters play it unprompted for several days; most finish
the slice and ask for more. If they don't, iterate here. Fixing fun is cheap now and very
expensive later.

---

## Phase 3: Production / Alpha (about 6 to 12 months)

Goal: everything needed to put the game in front of real players.

- Backend: accounts, cloud save, server-side summon/idle/upgrade/shop, receipt validation
- Monetization: IAP store, monthly card, battle pass (see `game-design.md`)
- Modes: tower, async arena, daily/weekly quests; guilds (lite) if capacity allows
- Event framework driven by remote config (limited-time banners, login events)
- Launch roster (target 20 to 30 heroes; decide in pre-production)
- Localization pipeline (even if launching English-only)
- Settings, account linking, customer support contact, terms of service and privacy policy
- Odds disclosure and legal review for target countries (see `open-questions.md`)

**Exit criteria:** stable builds, no known economy exploits, a content plan for the first 3 months
after launch.

---

## Phase 4: Soft launch (about 2 to 4 months)

Release in a few smaller countries (commonly English-speaking test markets) to measure real
behavior before spending on marketing.

Watch: retention (D1/D7/D30), tutorial completion, conversion to payer, average revenue per
daily user, crash rate. Commonly cited rough targets for mid-core games are D1 ≥ 40%,
D7 ≥ 15%, D30 ≥ 5%. Use them as a sanity check, not as a law.

**Exit criteria:** metrics are stable or improving across 2 to 3 updates, and cost to acquire a player
is plausibly lower than what a player is worth over their lifetime.

---

## Phase 5: Global launch and live ops

- Content cadence: new hero(es) and events every 2 to 4 weeks
- Seasonal events, balance patches, community management
- Expand modes (guild boss, guild wars, etc.) based on what players actually engage with

---

## Team roles to cover

One person may wear several hats. The point is that *someone* owns each one.

| Role | Owns | Notes |
|---|---|---|
| Producer / lead | Scope, schedule, decisions | Keeps phases gated on exit criteria. |
| Game designer | Systems, battle, progression | Also owns the spreadsheets. |
| Economy designer | Currencies, gacha rates, pricing | Contract an experienced one if nobody has done this. |
| Client programmer(s) | Unity gameplay and UI | |
| Backend programmer | Server logic, security, purchases | Strongly recommend experience here (hire/contract/advisor). |
| Character artist(s) | Illustrations | The single biggest cost and the biggest sales driver. |
| Animator | Spine/2D animation, VFX | |
| UI/UX artist | Screens, icons, flow | Gacha games are UI-heavy (dozens of screens). |
| Audio | Music, SFX | Usually outsourced. |
| QA / community | Testing, Discord, player support | Matters most from soft launch onward. |
