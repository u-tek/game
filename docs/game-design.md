# Game Design (GDD)

Status: **Draft v0.1**. All numbers are **placeholders** until the economy spreadsheet exists.
Each system has a scope tag:

- **Slice**: in the offline vertical slice (Phase 2)
- **Launch**: needed for soft launch (Phase 3)
- **Later**: after launch, based on player data

For how Idle Angels handles each system, see `reference-idle-angels.md`.

---

## 1. Core loop

```
        +-------------------------------+
        |  Idle rewards accrue (gold,   |
        |  hero EXP, gear) while away   |
        +---------------+---------------+
                        | claim
                        v
+--------------+   +----------------------+   +-------------------+
|  Summon new  |-->|  Upgrade & arrange   |-->|  Push campaign /  |
|  heroes      |   |  team (level, stars, |   |  tower / modes    |
+------^-------+   |  gear, formation)    |   +---------+---------+
       |           +----------------------+             |
       |                                                | beat a stage
       |   premium currency, scrolls, shards            v
       +------------------------------------- higher idle rate + rewards
```

**Session shape:** 3–5 short check-ins per day (claim idle rewards, do dailies, try a stage),
plus an optional longer session (tower, event, story). A full day of dailies should take
**10–15 minutes**.

---

## 2. Battle *(Slice)*

| Topic | Proposal | Notes |
|---|---|---|
| Team size | **5 heroes**: 2 front, 3 back | Idle Angels uses 6 (3+3) plus substitutes. 5 keeps each pick meaningful and reads better on a portrait screen. **Decide in pre-production.** |
| Targeting | Enemies hit the front row first; some skills target the back row | Positions become a real choice |
| Control | Auto by default. Ultimates fire automatically, or the player can tap a portrait to time them manually | Optional depth for players who want it (Pillar 3) |
| Speed | 1x / 2x; skip a battle once that stage is cleared | |
| Determinism | Seeded, logic-only battle sim (see `tech-plan.md`) | Enables skip, replays, server checks and balance sims |
| Length | 20–40 s per battle at 1x | |

### Factions: the counter wheel

Theme-driven, 3 factions (simple to learn, like Idle Angels' 3-class triangle):

```
Celestial --beats--> Infernal --beats--> Fallen --beats--> Celestial
```

- *Celestial smites the Infernal; the Infernal lords command the Fallen; the Fallen know every
  weakness of the heaven they left.*
- Advantage: **+20% damage** dealt (placeholder; Idle Angels uses +20%, AFK Arena +25%).
- **Faction bonus:** fielding 3+ heroes of one faction gives a team-wide stat bonus. This
  creates a real tension between "stack one faction" and "counter-pick this stage".
- **Later:** one or two rare "Ascendant" heroes outside the wheel, for premium events.

### Roles

Separate from faction. Every faction has every role.

| Role | Job | Usually placed |
|---|---|---|
| Guardian | Absorb damage, taunt, shield | Front |
| Striker | Single-target damage | Front/back |
| Caster | Area damage, debuffs | Back |
| Support | Heal, buff, energy | Back |
| Assassin | Dive to the back row | Back (jumps) |

### Skills

Each hero has: a basic attack, **1 ultimate** (fires when energy is full; energy is gained by
attacking and taking damage), and **2 passives** that unlock as the hero gains stars.

---

## 3. Heroes

| Topic | Proposal |
|---|---|
| Rarity at summon | **3 tiers**: Rare, Epic, Legendary. Not 10 like Idle Angels |
| Roster | Slice: 8–10 · Launch: 20–30 (sized by art cost from pre-production) · Then +1–2 per content update |
| Identity | Every hero: faction, role, name, short bio, voice lines (Launch), bond story (Launch) |
| Inspirations | Original characters. Mythology (seraphim, archangels, demon courts, Lilith-like figures) is public domain and fair to draw on; other games' characters are not |

---

## 4. Summoning (gacha)

| Feature | Scope | Proposal |
|---|---|---|
| Standard banner | Slice | Permanent pool, premium currency or scrolls |
| One free pull per day | Slice | Daily reason to log in |
| Odds screen | Slice | Required by Apple and Google; show it before every paid summon |
| Pity | Slice | Guaranteed Legendary by pull **N** (placeholder: 60). Counter carries over and is visible to the player |
| Duplicates → shards | Slice | Duplicates become that hero's shards for star-ups. Excess shards convert to a universal currency |
| Wishlist | Launch | Player picks a few Legendaries; Legendary results come from that list (like Idle Angels' Wish Pool / AFK Arena's wishlist) |
| Limited rate-up banners | Launch | Featured new hero for 2–3 weeks; separate pity counter |
| Faction banners | Later | Summon from one faction only |

Placeholder rates for the economy model: Legendary 2%, Epic 18%, Rare 80%.

---

## 5. Progression

| System | Scope | Proposal |
|---|---|---|
| Hero level | Slice | Hero EXP + gold. Level cap raised by stars |
| Stars (ascension) | Slice | Spend that hero's shards to add stars: more stats and passives unlocked |
| Gear | Slice | 4 slots (weapon, armor, helm, accessory). Gear drops from idle rewards and stages; upgrade with gold |
| **Level sharing** | Launch | Your top 5 heroes set the level for all others (like AFK Arena's Resonating Crystal; Idle Angels' Inheritance is similar). New heroes are usable immediately, so experimenting is encouraged |
| Account-wide bonus | Launch | Each star earned on any hero adds a small account-wide stat bonus (inspired by Idle Angels' Angels Temple). Keeps every summon worthwhile |
| Bonds | Launch | Gifts and daily interactions unlock bond story scenes and small stats. Stories are the main payoff |
| Relics / artifacts | Later | One relic slot per hero with passive effects |
| Skins | Launch | **Cosmetic only. Never stats.** |

---

## 6. Idle rewards *(Slice)*

- Gold, hero EXP and gear accrue per minute based on the furthest campaign stage cleared.
- **Cap: 12 hours** (placeholder). A visible "storage" bar fills; the player is nudged to return.
- **Quick claim:** instantly collect 2 hours of rewards; 1 free per day, more with gems
  (Launch).
- Computed from **server time** at claim (see `tech-plan.md`). The offline slice uses device
  time as a temporary stand-in.

---

## 7. Game modes

| Mode | Scope | Description |
|---|---|---|
| Campaign | Slice | Chapters of ~10–15 stages; each boss raises the idle rate. Story beats between chapters |
| Daily/weekly quests | Launch | Activity points → reward chests |
| Tower | Launch | Endless floors of fixed teams; tests team building. Leaderboard |
| Arena | Launch | Async PvP vs other players' saved defense teams; weekly ranking rewards |
| World boss | Launch | Daily attempts at a giant boss; damage leaderboard |
| Events framework | Launch | Limited-time login events, banner events, event shops (remote config) |
| Guild (lite) | Launch | Join, check-in rewards, guild boss. No chat at first |
| Roguelite dungeon | Later | Multi-floor run with no healing between fights and buffs to choose from (Idle Angels' Secret Abyss is similar). Rewards smart team building |
| Faction trials | Later | Stages that only allow one faction |
| Cross-server arena, guild wars | Later | |

**Unlock pacing:** introduce one system at a time over the first 7 days, roughly
Campaign → Summon → Gear → Quests → Arena → Tower → Guild.

---

## 8. Economy (first pass)

| Currency | Earned from | Spent on |
|---|---|---|
| Gold | Idle, stages, quests | Levels, gear upgrades |
| Hero EXP | Idle, stages | Levels |
| Gems (premium) | Purchases, quests, events, achievements | Summons, quick claims, shop refresh |
| Summon scrolls | Quests, events, stage milestones | Summons |
| Hero shards | Duplicates, events, shops | Stars |
| Universal shards | Excess duplicates | Any hero's stars (at a worse rate) |
| Arena / guild / event tokens | Their modes | Their shops |

**Rules of thumb for the economy model:**
- Every currency needs a **source** and a **sink**; track both in analytics.
- Decide the **free-player monthly gem income** first, then how many summons it buys per month,
  then how long a free player takes to max one Legendary (Idle Angels' players report far too
  long; that's the gap to beat).

---

## 9. Monetization *(Launch)*

| Product | Notes |
|---|---|
| Monthly card | Small daily gem payout for 30 days; the best-value offer |
| Battle pass (seasonal) | Free + paid tracks, completable by a regular player |
| Starter pack | One-time, high value, within the first days |
| Gem packs | Standard tiers; first-purchase bonus |
| Skins | Cosmetic only |
| Limited offers | Time-limited bundles. Avoid aggressive pop-ups |
| Rewarded ads (optional) | Opt-in only, e.g. an extra quick claim. **Decide in pre-production**: affects ad SDKs and content rating |
| VIP | **Open question.** If used, limit perks to convenience (extra quick claims, auto-dailies), not power |

**Principles:** published odds and pity; no stat-granting cosmetics; event rewards a free player
can complete; no "kompu gacha" (paying to complete a random set) anywhere.

---

## 10. Story and setting (to be written in pre-production)

- **Premise draft:** the war between Heaven and Hell has ended in a stalemate that broke both. The
  player is a *mortal envoy* (or a nameless angel; to decide) who can command all three factions.
- **Structure:** each campaign chapter is one region/act with a short story; bond stories go deep
  on individual characters.
- **Deliverable for pre-production:** a one-page bible per faction (look, values, conflicts,
  3 sample heroes).

---

## 11. Screens list (for UI planning)

Home/hub · Campaign map · Battle · Battle results · Hero list · Hero detail (level, stars, gear,
skills, bond) · Formation · Summon · Summon results · Odds/pity info · Inventory · Shop · Quests ·
Mail · Settings/account · Events · Tower · Arena · Guild.

Even the Slice needs about half of these, which is why UI/UX deserves an owner early.
