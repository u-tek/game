# Open Questions, Risks and Decisions

Status: **Draft v0.1**. Tags say *when* each question must be answered:
**[Now]** before real work starts · **[Pre-prod]** during pre-production · **[Later]** before launch.

## Decisions made

| Date | Decision | Notes |
|---|---|---|
| 2026-10-15 | Genre: idle/AFK gacha RPG in the style of Idle Angels | |
| 2026-10-15 | Engine: Unity | Superseded the same day by Godot (below) |
| 2026-10-15 | Theme: celestial angels vs. demons, with original characters, story and art | |
| 2026-10-15 | Team: small team, commercial goal, new to game dev | Drives the phased roadmap |
| 2026-10-15 | Engine changed to **Godot 4.5** (GDScript), kept portable to Unity | Claude builds and tests it end to end; see `docs/dev/unity-port.md` |
| 2026-10-15 | iOS builds on GitHub Actions macOS runners (repo made public) | Unsigned IPA for sideloading; `docs/dev/ios-build.md` |
| 2026-10-15 | Art made in-house: full-scale vector anime characters, animated with our own HaloRig system (no Spine) | Vector art superseded on 2026-10-16 (below); HaloRig stays |
| 2026-10-15 | **Content rating: App Store 18+, suggestive fan-service art.** Adults only; implied, never explicit | `docs/dev/character-briefs.md`. Google Play is stricter; plan alternate outfits for Android |
| 2026-10-16 | Hero art is AI-painted (Animagine XL 4.0 on the GitHub Actions art farm), one painted PNG per hero on a HaloRig warp rig; all 15 imported | `docs/dev/art-farm.md`, `docs/dev/status.md`. ComfyUI on the owner's PC is the preferred upgrade |
| 2026-10-16 | Designs pushed to the maximum allure App Store 18+ allows (briefs v3.1), hard lines unchanged | `docs/dev/character-briefs.md` |
| 2026-10-16 | UI v2 follows the owner's reference game closely, with our own names, icons and fonts | `docs/dev/ui-style-v2.md` |

## Open questions

### Team and business
- **[Now]** Who is on the team, and which roles from `roadmap.md` does each person cover? Which
  roles are missing?
- ~~Who makes the character art?~~ **Decided:** AI-painted on the art farm (decisions table,
  2026-10-16).
- **[Now]** Budget and runway: how many months can the team work on this before it needs revenue?
- **[Pre-prod]** Self-publish, or look for a publisher after the vertical slice?
- **[Later]** Company entity, developer accounts (Apple and Google), and who owns the IP
  (contracts with every contributor, especially contract artists).

### Game and audience
- **[Pre-prod]** Working title.
- **[Pre-prod]** Target players and markets: Western, Southeast Asian, East Asian, global?
  This changes art style, monetization and localization.
- ~~Content rating~~ **Decided:** App Store 18+ (decisions table, 2026-10-15).
- ~~Portrait or landscape?~~ **Decided:** portrait (720x1280 base, `project.godot`).
- ~~Team size in battle: 5 or 6?~~ **Decided:** 5 in v1, with the 3-faction wheel (Celestial,
  Infernal, Fallen).
- **[Pre-prod]** Who is the player character: a mortal envoy or an angel?
- **[Pre-prod]** VIP system: yes or no? If yes, convenience-only perks?
- **[Pre-prod]** Rewarded ads: yes or no? (Affects ad SDKs and content rating.)
- **[Pre-prod]** What is our **hook**: the one thing we do better or differently than Idle Angels?
  (Candidates are in `vision.md`.)
- **[Pre-prod]** How generous should we be? Pity thresholds, free premium currency per month,
  whether duplicates or fodder gate star-ups.

### Tech
- **[Pre-prod]** Backend: still open. The original "Unity Gaming Services vs PlayFab" framing is
  from the Unity era (`tech-plan.md` is historical); the game is Godot now.
- ~~Spine vs Unity 2D Animation~~ **Superseded:** HaloRig, our own warp rig (decisions table,
  `docs/dev/halorig.md`).
- **[Later]** Anti-cheat level for PvP: re-simulate arena battles server-side?

## Risks

| Risk | Impact | Mitigation |
|---|---|---|
| Team is new to game dev | Slow progress, rework | Phase 0 learning, small vertical slice first, experienced backend/economy help |
| Art cost per hero too high to sustain the content cadence | Can't keep up after launch | Measure cost on hero #1 in pre-production; reuse rigs/templates; plan roster size from that |
| Economy exploits (client-side cheating, clock manipulation) | Lost revenue, broken PvP | Server-authoritative state, server time only (see `tech-plan.md`) |
| Too similar to Idle Angels | Legal risk; no reason for players to switch | Original characters/names/art/UI; a clear hook (see `vision.md`) |
| Loot-box regulation | Can't launch in some countries; store rejection | Legal check per target market (below) |
| Genre is crowded and user acquisition is expensive | Can't grow profitably | Soft launch to validate metrics before spending on marketing |

## Gacha / loot box legal notes (not legal advice; get real legal review before launch)

- **Apple App Store and Google Play** both require showing the odds of randomized paid items
  *before* purchase.
- **South Korea** has legally required detailed probability disclosure since March 2024.
- **Belgium** treats paid loot boxes as gambling; many games disable paid gacha there.
- **Japan** bans "kompu gacha" (paying to complete a set of random items for a prize).
- **China** requires a government license to publish games, usually through a local partner, plus
  odds disclosure and other rules. Treat China as out of scope unless a publisher handles it.
- Other countries (Netherlands, Australia, the EU generally) are actively reviewing rules; check
  status near launch.
- **Privacy:** GDPR (EU), COPPA (if under-13s might play), and app-store privacy labels.
