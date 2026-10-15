# Open Questions, Risks and Decisions

Status: **Draft v0.1**. Tags say *when* each question must be answered:
**[Now]** before real work starts · **[Pre-prod]** during pre-production · **[Later]** before launch.

## Decisions made

| Date | Decision | Notes |
|---|---|---|
| 2026-10-15 | Genre: idle/AFK gacha RPG in the style of Idle Angels | |
| 2026-10-15 | Engine: Unity | See `tech-plan.md` |
| 2026-10-15 | Theme: celestial angels vs. demons, with original characters, story and art | |
| 2026-10-15 | Team: small team, commercial goal, new to game dev | Drives the phased roadmap |

## Open questions

### Team and business
- **[Now]** Who is on the team, and which roles from `roadmap.md` does each person cover? Which
  roles are missing?
- **[Now]** Who makes the character art? In-house, contractors, or an outsourcing studio? This
  is the biggest cost driver.
- **[Now]** Budget and runway: how many months can the team work on this before it needs revenue?
- **[Pre-prod]** Self-publish, or look for a publisher after the vertical slice?
- **[Later]** Company entity, developer accounts (Apple and Google), and who owns the IP
  (contracts with every contributor, especially contract artists).

### Game and audience
- **[Pre-prod]** Working title.
- **[Pre-prod]** Target players and markets: Western, Southeast Asian, East Asian, global?
  This changes art style, monetization and localization.
- **[Pre-prod]** **Content rating.** Many angel-themed gacha games use suggestive character art.
  Decide the target age rating early: it affects store featuring, ad networks you can buy
  traffic from, and some markets.
- **[Pre-prod]** Portrait or landscape?
- **[Pre-prod]** Team size in battle: 5 (proposed) or 6 like Idle Angels? Is the 3-faction
  wheel (Celestial, Infernal, Fallen) enough? See `game-design.md`.
- **[Pre-prod]** Who is the player character: a mortal envoy or an angel?
- **[Pre-prod]** VIP system: yes or no? If yes, convenience-only perks?
- **[Pre-prod]** Rewarded ads: yes or no? (Affects ad SDKs and content rating.)
- **[Pre-prod]** What is our **hook**: the one thing we do better or differently than Idle Angels?
  (Candidates are in `vision.md`.)
- **[Pre-prod]** How generous should we be? Pity thresholds, free premium currency per month,
  whether duplicates or fodder gate star-ups.

### Tech
- **[Pre-prod]** Backend: Unity Gaming Services vs PlayFab (spike planned).
- **[Pre-prod]** Spine vs Unity 2D Animation.
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
