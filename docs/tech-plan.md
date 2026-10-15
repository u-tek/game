# Tech Plan

Status: **Draft v0.1**. Engine is decided (Unity). Backend is not decided yet; see "Backend" below.

This doc is written for a team that is new to programming and game development. Each choice
says *why*, so you can push back on it.

---

## 1. Guiding rules (the five things that matter most)

1. **The server is the source of truth for anything players can pay for.** Summons (gacha
   rolls), currencies, purchases, and idle rewards are calculated on the server. The client only
   displays results. A client-side gacha in a commercial game *will* be hacked.
2. **Never trust the device clock.** Idle/AFK rewards are computed from *server* timestamps.
   Players change their phone's clock to cheat idle games.
3. **Battle logic is separate from battle visuals.** Battle *logic* is plain C# that runs with no
   graphics: it takes two teams and a random seed and outputs a list of events ("A hits B for
   120"). The Unity scene only *plays back* that list. This one decision gives you:
   - skip/fast-forward/2x speed for free,
   - the ability to simulate 10,000 battles in seconds for balancing,
   - the option to re-run a battle on the server to catch cheaters.
4. **Game data lives in spreadsheets, not in code.** Hero stats, skills, stage enemies, drop
   tables and summon rates are rows in a spreadsheet that designers edit. A tool exports them
   to JSON that both the client and the server load. Programmers should almost never need to
   change code to rebalance the game.
5. **Ship new content without an app-store update.** New heroes and events arrive via
   downloadable content (Unity Addressables) and remote config. Gacha games live on a
   2 to 4 week content cadence, and app-store review can't be on that critical path.

---

## 2. Client (Unity)

| Area | Choice | Why |
|---|---|---|
| Engine | Latest **Unity 6 LTS** | LTS = long-term support, fewer surprises. Stay on one version per milestone. |
| Rendering | 2D, URP (Universal Render Pipeline) | Standard for mobile 2D; good performance on low-end phones. |
| Character animation | **Spine** (paid) *or* Unity 2D Animation (free) | Spine is the genre standard for animated anime-style characters. Decide in pre-production by animating one hero both ways. Check Spine's current license terms; they change at higher revenue tiers. |
| UI | uGUI (Unity UI) | Most tutorials, assets and hires know it. UI Toolkit is newer and still has gaps for game UI. |
| Content delivery | **Addressables** | Download new heroes and events after install. |
| Purchases | **Unity IAP** + server-side receipt validation | Handles both Apple and Google; the server must verify every receipt before granting items. |
| Testing | Unity Test Framework (NUnit) | Mainly to unit-test the battle and economy logic. |
| Target devices | iOS + Android, portrait orientation (TBD) | Test on a cheap Android phone early. Most of your players won't have flagships. |

### Project structure

Use **assembly definitions** to keep the battle and economy logic independent of Unity:

```
Assets/
  _Game/
    Core/        # Pure C#. NO "using UnityEngine". Battle sim, formulas, gacha rules, data models.
    Client/      # Unity code: scenes, UI, battle playback, audio, input.
    Data/        # Generated from spreadsheets (do not hand-edit).
    Art/ Audio/ Prefabs/ Scenes/
  Tests/
    Core.Tests/  # Fast unit tests for Core.
```

Because `Core` has no Unity dependency, the same code can run inside the backend if the backend
runs C# (see below). Writing the damage formula once and running it on both client and server
removes a whole class of bugs.

### Determinism tips for the battle sim

- Use a **seeded random number generator** that you own (not `UnityEngine.Random`), so the same
  seed always produces the same battle.
- Use **integers** for stats and damage (store percentages as basis points, e.g. 12.5% = 1250).
  Floating-point math can differ slightly between devices and server, and that breaks replays.
- Process units in a fixed, explicit order (e.g. by speed, then by slot index).

---

## 3. Backend

### What the backend must do

- Player accounts (guest login, then Apple/Google sign-in to link the account).
- Cloud save: the authoritative player state.
- Server-side actions: summon, claim idle rewards, level up, star up, buy from shop, and so on.
- Receipt validation for purchases.
- Remote config: event schedules, banner rotations, tuning values.
- Leaderboards and async PvP (arena) matchmaking.
- Guilds (later).
- Analytics events.

### Recommendation: use a managed backend ("BaaS") and don't build servers yourselves

For a team new to programming, running your own servers is a big extra job with a lot of
security risk. Shortlist two managed options that let you write server code in **C#**, so the
`Core` assembly can be shared:

| Option | Server code | Notes |
|---|---|---|
| **Unity Gaming Services (UGS)**: Authentication, Cloud Save, Cloud Code, Economy, Remote Config, Leaderboards | Cloud Code C# modules | Tightest Unity integration; one vendor. |
| **Microsoft PlayFab** | Azure Functions (C#) or CloudScript | Mature, widely used for live-service mobile games; strong economy and live-ops tooling. |

Other options to know about: **Nakama** (open source, can self-host, server code in
Go/TypeScript/Lua) and **Firebase** (general purpose, not game-specific).

**Decision process:** in pre-production, spend 1 to 2 weeks building the same tiny feature on the two
shortlisted options (guest login, then a server-side "summon" that deducts currency and grants a
hero). Compare ease of use, pricing at 10k/100k daily active users, and the live-ops dashboard.

> Until that spike happens, the vertical slice can run **offline**. Write all state changes
> through one interface (e.g. `IPlayerService.Summon(bannerId)`) with a local implementation
> now and a server implementation later, so swapping is cheap.

---

## 4. Content pipeline

```
Google Sheets (designers edit)
   -> export script (CSV/JSON)
      -> Unity importer creates ScriptableObjects / JSON in Assets/_Game/Data
      -> same JSON uploaded to backend config
```

- Every hero, skill, stage, item and banner has a **stable string ID** (e.g. `hero_seraph_01`).
  Never rename IDs after release; player saves reference them.
- Validate on import: missing IDs, negative stats, summon rates that don't add up to 100%.

---

## 5. Tooling and workflow

- **Version control:** Git + **Git LFS** (for images, audio and Spine files) on GitHub, using
  Unity's standard `.gitignore`. Non-programmers can use GitHub Desktop.
  Alternative: Unity Version Control (formerly Plastic SCM), which some art-heavy teams prefer.
- **Task tracking:** GitHub Projects or Trello. Keep it simple.
- **Builds:** Unity Build Automation or GitHub Actions, once there is something to test on phones.
- **Analytics from day one of playtesting:** tutorial funnel, session length, retention
  (D1/D7/D30), and where each currency comes from and goes to ("sources and sinks").
- **Balance simulator:** an editor tool that runs thousands of `Core` battles and reports win
  rates per hero and stage. This is cheap to build once the logic/visuals split exists.

---

## 6. Things NOT to build yourselves

- Login/accounts, payments, cloud save, push notifications, crash reporting: use services.
- Chat/moderation: use a service or postpone chat until after launch.
- A custom engine or custom networking: never.
