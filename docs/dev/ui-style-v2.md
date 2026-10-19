# Halo & Horn UI Style v2: "Tactical Gacha"

Style v2 replaces v1's "twilight cathedral" look (dark indigo and gold filigree). The owner asked for a UI that closely follows the **layout and
visual language** of the owner-supplied reference game (its screenshots are kept privately,
outside the repo; this repo never names it). This document is the contract for that look:
tokens, components (all built by `Kit`, `src/ui/kit.gd`), the app shell (`src/ui/main.gd`)
and a layout spec for every screen on the 720 x 1560 canvas.

The live reference is the hidden `kit_demo` screen. It holds a gallery of every widget and
three mocks built only from Kit: the lobby, the roster grid and hero detail.

```bash
tools/shoot kit_demo --rich --safe-area-sim                                   # gallery
tools/shoot kit_demo --rich --safe-area-sim --shoot-params='{"scroll": 2600}'
tools/shoot kit_demo --rich --safe-area-sim --shoot-params='{"mock": "lobby"}'   # lobby | roster | detail
tools/shoot kit_demo --rich --safe-area-sim --shoot-params='{"show": "dialog"}'  # reward | confirm | dialog | popup | toast | notices | menu
```

## 1. The line we stay behind (App Store guideline 4.1)

We follow the reference's layout and general visual language (where things go and how they
feel) and none of its protected expression.

- **No names or terms from the reference.** Not the game name, its characters, its places or its
  systems (its idle base, its city, its in-game encyclopedia, its skill-chain mechanic, its
  guilds, its advice feature...); the owner's brief lists the exact words. "Lobby" is a
  generic word and is fine. Our terms are in section 2.
- **No logos, icons or graphics traced or cut from screenshots.** Every icon is an original SVG
  drawn from code (`assets/art/ui/src/make_icons.py`). Every decoration (hatching, barcodes,
  brackets, hexes, chevrons) is generic geometry drawn by `KitBox` / `Deco`. The rarity mark
  is our own chevron stack, not an "SSR" logotype. The lobby centre tab is a hexagon, not a
  sphere in a triangle.
- **Reference screenshots stay private.** They live outside the repo, in a private folder on
  the working machine; a new session does not have them and asks the owner to send them again.
  Never copy them, crops of them or composites into the repo or any committed file. Side-by-side
  reviews go to a private scratch folder outside the repo.
- **Our own palette and type.** Barlow and Barlow Condensed (OFL) for type. Accent colors are
  common UI blues and oranges. Rarity names are Rare, Epic and Legendary.
- **Our own content.** Angels, demons and the fallen, painted in our own art style
  (art-style.md). Character art carries the identity, not the chrome.
- **Our own signature details.** Each element on its own is generic, but copying many small
  details at once reproduces a look, so the lobby deliberately differs in these:
  - Objective strip: our flag glyph in a cyan **hexagon** (not a "!" in a circle), a plain
    white **chevron** at the end (not an arrow in a square), and our wording ("Next: Stage
    2-3", or the first-session step such as "Quick Claim 2h of rewards").
  - White plate (Team): the glyph sits in a thin **hexagon frame** over a faint hatched hex,
    not in corner brackets.
  - Sanctum meter: a plain percentage ("41%", no zero padding) under a "FILL" caption, and
    the Sanctum level as a small tag **next to the plate title** ("Sanctum LV 12").
  - Heroes nav glyph: a single haloed figure with one swept wing (our angel motif), one
    tone, never a group of busts.
  - Side buttons: one frame each (rounded tile), no stacked diamond-and-tile frames.
- **Code and commits.** Code comments and commit messages say "reference style", never the
  reference's name.

## 2. Feature mapping

| Reference concept | Halo & Horn | Where |
|---|---|---|
| Lobby (home, character on screen) | **Lobby** (`home`) | Nav centre hexagon |
| Character roster | **Heroes** (`heroes`) | Nav tab 1 |
| Squad | **Team** (`formation`) | Nav tab 2 |
| Inventory | **Gear** (`gear`) | Nav tab 4 |
| Recruit | **Summon** (`summon`) | Nav tab 5 |
| Idle base with a defence % | **Sanctum** (idle rewards; shows its **fill %** = elapsed / 12 h cap) | Lobby shortcut, dark plate with `Kit.percent_meter` |
| Campaign | **Campaign** (`campaign`) | Lobby shortcut, orange plate with stage tag and boss art |
| Second big lobby destination (white plate) | **Quests** (`quests`) | Lobby shortcut, white plate |
| Shop | **Shop** (`shop`) | Lobby shortcut, blue plate |
| Mission strip | Objective strip (`Kit.notice_bar`): flag hex, "Next: Stage x-y" or the guide step | Lobby, top right |
| Event banners | Banner card (`Kit.banner_card`): current summon banner | Lobby, top left |
| Side buttons (messages, events, friends) | Offers (shop), Daily (quests), Team, View (hide UI) | Lobby edges |
| Player avatar and level | Leader avatar (first team hero) with the **team power** chip (we have no account level) | Top bar, left |
| Mail / notice / menu | **Quests** (clipboard, red dot = claimable), **Notices** (bell: what's actionable), **Menu** (grid: every destination incl. Settings) | Top bar, right |
| Burst type numeral on cards | **Rarity tier** numeral I / II / III with a faction-colored roof | Card, second hex |
| Manufacturer / class icon | **Role** glyph in a white hex | Card, first hex |
| Character dialogue line | Speech bubble with the lobby hero's line | Lobby, mid-left |

## 3. Tokens

All tokens are `Kit` constants; never hard-code a color in a screen.

### 3.1 Color

Dark chrome (bars, glass over art). Text on it: `INK` / `INK_DIM`.

| Token | Value | Use |
|---|---|---|
| `BG` | `#15171b` | app background (dark) |
| `CHROME` | `#0c0d10` | bars, art shades |
| `PANEL` | `#1a1c21` @ 92% | glass panels (legacy default) |
| `PANEL_HI` | `#2b2e34` | raised plates |
| `LINE` | white @ 14% | hairlines on dark |
| `INK` | `#f4f6f8` | main text on dark |
| `INK_DIM` | `#9ba2ac` | secondary text on dark |
| `OUTLINE` | `#0c0d10` | text outlines on art |

Light pages (roster, info column, dialogs). Text on it: `TEXT` / `TEXT_DIM`.

| Token | Value | Use |
|---|---|---|
| `PAPER` | `#eceff2` | page tone (`Kit.page_bg("light")` is a `#f4f6f8` to `#e2e6ea` gradient) |
| `WHITE` | `#ffffff` | white panels, active tabs |
| `TEXT` | `#16181c` | near-black text |
| `TEXT_DIM` | `#6c737d` | secondary text |
| `LINE_LIGHT` | `#d5dbe1` | hairlines on light |

Accents.

| Token | Value | Use |
|---|---|---|
| `ACCENT` | `#12a8f4` | THE accent: primary buttons, selected chips, active tab bar, links, meters, focus |
| `ACCENT_HI` | `#6fd8ff` | accent text on dark, glows, percentages |
| `ACCENT_DEEP` | `#0b6fd8` | dialog headers, accent text on light |
| `ORANGE` | `#ff8a1e` | the one "go now" action (campaign plate, orange button), guide marks |
| `ORANGE_HI` | `#ffc23a` | stage tags, level numbers on plates |
| `NEW_RED` | `#f2481f` | "N" new badges |
| `RED_DOT` | `#ff4536` | notification dots |

Semantic (kept from v1 so older screens compile).

| Token | Value | Use |
|---|---|---|
| `GOLD` / `GOLD_LIGHT` / `GOLD_DEEP` | `#ffb627` / `#ffd98a` / `#b86e0a` | Celestial, currency gold; avoid for UI chrome in v2 |
| `EMBER` | `#e8432a` | Infernal, danger, defeat |
| `VIOLET` | `#8f6cf0` | Fallen |
| `SKY` | `#4fc3f7` | info |
| `GOOD` | `#37cf8a` | success, HP, "+N" deltas |
| `RARE` / `EPIC` / `LEGENDARY` | `#3b9cf2` / `#a95cf2` / `#ff9b1e` | rarity strips, chevrons, card footers |
| tier 1-5 | grey `#9aa1aa`, `GOOD`, `RARE`, `EPIC`, `LEGENDARY` | gear tier strips (`Kit.tier_color`) |
| factions | celestial `GOLD`, infernal `EMBER`, fallen `VIOLET` | numeral-hex roof, faction badges, hero detail stripes |

Rules: one accent per view (cyan); orange only for the single most important action or a
highlight; red only for N badges, dots, danger. Never put `INK` text on a light panel or
`TEXT` on dark chrome.

### 3.2 Type

| Face (OFL, `assets/fonts`) | `Kit.font()` weight names | Use |
|---|---|---|
| Barlow Medium | `regular`, `medium` | long body text |
| Barlow SemiBold | `bold` (default), `semibold` | body, captions, speech |
| Barlow Bold | `extrabold` | buttons, row titles, plate titles ("Shop") |
| Barlow Condensed Medium | `cond_light` | big level numerals ("01") |
| Barlow Condensed SemiBold | `cond` | small uppercase labels |
| Barlow Condensed Bold | `black`, `cond_bold` | numbers, uppercase labels, tags, tabs |
| Barlow Condensed ExtraBold | `title`, `cond_black` | headers, hero names, banners |

Scale on the 720 px canvas: 18-20 micro (tags, card captions), 22 `SIZE_SMALL`, 26
`SIZE_BODY`, 30 `SIZE_BUTTON`, 40 `SIZE_HEADER`, 56 `SIZE_HERO`; big numerals 44-52 (card
level, power). Case: buttons and body in sentence/title case ("Level Up"); section headers,
tabs, tags, stat names, nav labels and banners in UPPERCASE condensed. Numbers are always
condensed (`Kit.number`, `black`).

### 3.3 Geometry

| Item | Value |
|---|---|
| Canvas | 720 x 1560 (also 720 x 1280); safe-area sim 108 top / 62 bottom |
| Touch target | >= 88 px (`Kit.BUTTON_H`); small visuals keep 88 px hit areas (`draw_inset`) |
| Gutter / padding | 16 side gutter for full-width rows, 24 `PAD` inside panels, 16 `GAP` |
| Corner radius | 2-4 plates, tiles, cards, bars; 6 dialogs and notice strips; 8 buttons, chips, glass panels; 10-12 icon tiles and the avatar; 999 only for price pills |
| Skew | `Kit.SKEW` = tan(10 deg) = 0.176 of the height (rarity plates x1.4, ribbon 0.32) |
| Shortcut taper | far edge 12% shorter (plates turn toward the screen centre) |
| Lines | 1 px hairlines, 1.5 px borders, 2 px frames, 3 px emphasis (orange rim, brackets) |
| Shadows | soft, offset (0, 3-4), 6-10 px, black 28-45%; glows: zero offset, accent at 35-60% |
| Hatching | 45 degree lines rising right, spacing 7-14 px, width 2, white 3-16% on dark or black 3-5% on light; usually on the right 30-45% of a plate (`hatch_from` 0.55-0.72) |

### 3.4 Decoration vocabulary (`Kit.deco`, `KitBox`)

- **Hatching**: plate ends, page backgrounds, hero detail stripe band (faction color, 46 px
  spacing, 18 px lines).
- **Technical lines**: hairline with a thick start segment and end ticks (`techline`,
  `section_header`, `divider`), corner brackets (`brackets`, `corner_marks_*` on KitBox,
  around the white plate glyph), double tick marks near plate corners.
- **Barcode**: decorative bars top-right of portrait cards (seeded per hero, not a real code).
- **Hexagons**: role and tier badges, skill slots, the Lobby tab, guide-free accents.
- **Chevrons**: rarity marks (1 / 2 / 3 stacked chevrons for rare / epic / legendary).
- **Pips**: diamond star pips on cards, carousel dots on banners.

### 3.5 Motion

Press: scale to 95% in 0.06 s, spring back 0.18 s (`add_press_fx`). Screens fade in 0.15 s
with a 12 px rise. Modals: dim fades 0.18 s, panel pops from 86% with back easing. Badges and
dots pop in; dots breathe every 1.2 s. The orange campaign rim pulses slowly. Toasts slide
in 8 px, hold 2.2 s, fade 0.35 s.

### 3.6 Icons

`assets/art/ui/*.svg`, generated by `assets/art/ui/src/make_icons.py` (64-unit grid, 128 px).
UI glyphs are **solid white flat shapes** (4-unit strokes, rounded joins, cut-outs, no
outlines, no gradients) so code can tint them: `INK` on dark, `TEXT` / `#2a2d33` on light,
`INK_DIM` inactive. Only meaning-carrying icons are colored (currencies, stars, power,
crown, faction marks, toggles) with flat 2-3 tone fills. Nav icons are `nav_heroes`,
`nav_team`, `nav_lobby`, `nav_gear`, `nav_summon`. Other purpose glyphs: `codex` (open
book: the Codex tab and links, never the scrolls ticket), `flag` (objectives). Add icons in
the generator, never by hand-editing an SVG, and never by tracing a screenshot.

## 4. Components

Every builder is static on `Kit` and returns a ready Control. Old names keep working
(restyled); new ones are marked **new**.

### Text
- `label(text, size, color, weight, outline)`; `title()` (condensed ExtraBold, white, soft
  shadow); `header()` (condensed ExtraBold 40); `body()` (wrapping SemiBold); `number()`
  (condensed Bold, thin outline on light colors); `caption()` (22, dim); **new**
  `fit_label(label, width, max, min)`.

### Buttons
| Builder | Look |
|---|---|
| `primary_button` | cyan `#27b8fb` to `#0c97ea`, 1.5 px `#7fd8ff` rim, white Barlow Bold 30, hatched right end |
| `secondary_button` | graphite `#3a3d43` to `#2b2e33`, white text: secondary actions on dark |
| **new** `light_button` | white with `#c9d0d8` rim, `TEXT`: secondary actions on light pages and dialogs |
| **new** `orange_button` | orange `#ffa53a` to `#ff7a12` with an orange glow: the one urgent action |
| `danger_button` | red `#f25a43` to `#d63a24` |
| disabled | flat `#3a3c40` (light: `#e3e6ea`), dimmed text |
| `cost_button`, `costs_button` | label over a price pill (white pill with dark amounts on primary / orange / light; dark pill on secondary); short amounts red; amount 0 shows a green "FREE". `look`: primary, secondary, light, orange, danger |
| **new** `fit_button(b, width, max, min, pad)` | fits a text button into a tight row: narrower side padding, font shrunk until the text fits, so a row never grows wider than planned |
| `icon_button(icon, cb, size, look)` | 88 px; `round` dark glass tile, `accent` (or `gold`) cyan tile, `light` white tile with dark glyph, `bare` |
| **new** `back_bar()` | bottom-left cyan "Back" (exit glyph) + cyan square Home, for screens without the nav |
| `segmented` | graphite segments, selected = cyan |
| **new** `filter_chips(options, selected, cb, size)` | square graphite chips (76 px in an 88 px hit area), selected cyan; text ("ALL", "I") or glyphs |
| **new** `tab_strip(options, selected, cb, min_width)` | page / dialog tabs: active = white plate with a 5 px cyan top bar and `TEXT`; inactive = dark glass with light text; uppercase condensed 28 |
| `toggle` | cyan pill switch |
| `empty_slot` | dark glass square, corner brackets, faint plus, uppercase caption |

### Lobby widgets (new)
- `shortcut(text, icon, look, cb, opts)`: the big translucent plates. Tapered quad, glyph,
  Barlow Bold title. Looks: `blue` (glass cyan-blue), `white` (pale glass about 70% opaque,
  dark glyph in a thin hexagon frame, tick marks), `orange` (dark glass, glowing pulsing
  orange rim, hatching), `dark` (deep blue glass about 55-60% opaque, cyan rim, hatching,
  cyan text). opts: `size` (268 x 116 top row, 304 x 150 bottom row in the lobby), `side`
  (left / right), `badge` (N / ! / dot), `sub` (a meter: the glyph turns into a faint
  watermark), `art` + `art_caption` (framed art strip with a tag).
- `side_button(icon, text, cb, look, badge)`: 74 px icon tile + shadowed white caption 6 px
  under it, on a 104 x 120 hit area. Looks: `dark`, `accent`, `orange`, `white`, `diamond`
  (one dark glass diamond, white glyph). One frame per button.
- `speech_bubble(name, text, width)`: light glass `#0d0e11` @ 45% with soft text shadows,
  bold name, SemiBold line; 400 px in the lobby, left of the hero's centre line.
- `banner_card(title, subtitle, cb, opts)`: 330 x 132 dark plate, hatching in `color`, hero
  art crop on the left fading out, condensed uppercase title (auto-fit, 2 lines), colored
  sub-tag, optional carousel pips (`pages`, `page`), `badge`.
- `notice_bar(text, cb, width, icon)`: objective strip; a cyan hexagon with a glyph (default
  `flag`), bold text, a white chevron at the end. 88 px tall hit area.
- `percent_meter(caption, pct, icon, level_text)`: navy plate with cyan rim, glyph, uppercase
  caption, thin bar, big cyan `"41%"` (no zero padding); update with `set_percent_meter`.
- `ShortcutButton.set_title_tag(text)`: a small tag right after a plate's title ("LV 12").
- `resource_pill(entries, entry_width)`: one dark glass bar with `[icon] amount +` cells and
  1 px separators; each cell with `on_plus` is tappable; update with
  `set_chip_amount(pill.get_meta("entries")[id], n)`.
- `avatar(hero_id, size, caption, cb)`: rounded square head crop with a white 2.5 px rim.

### Panels and pages
- `panel(kind)`: dark kinds `glass` (default, corner marks), `card`, `inset`, `plain`;
  light kinds `white` (white card, 1 px `#dfe3e8` rim, soft shadow), `paper`, `light_inset`
  (grey well), `row` (flat white row); also `speech`, `bar`.
- **new** `info_panel()`: white panel (hero info column, light cards).
- **new** `header_bar(text, right, icon)`: graphite plate, 5 px cyan left edge, uppercase
  condensed white 24, hatched right end ("STATUS", "EQUIP").
- **new** `page_bg("light" | "dark")`: hatched page background with technical lines.
- **new** `dialog(title, content, width, light, icon)`: blue gradient header (white title,
  optional glyph, white X), white body (`light = true`) or graphite body for content built
  with light text. `UI.popup(..., light)` and `UI.confirm` use it.
- `section_header(text, size, color, light)`: 6 px cyan block, uppercase condensed title,
  technical hairline to the right edge with ticks. `divider(width, light)`.
- `screen_header(title, on_back, right)`: dark square back button, uppercase title.

### Hero cards and badges
- **new** `portrait_card(id, opts)` (roster, 4 per row at 158-160 wide, height x1.62): pale
  studio backdrop with faint faction-tinted bands, waist-up art crop (`art_crop`, zoom 1.3),
  white **role hex** + dark **tier numeral hex** (I/II/III by rarity, faction-colored roof)
  top-left, barcode + faction emblem top-right, dark footer gradient with a rarity glow,
  "LV." over a big condensed two-digit level on the left, name right, rarity chevrons and
  gold star pips above the name, rarity strip on the bottom edge. Options as hero_card plus
  `new`; unowned = greyscale and a pale veil; `selected` = cyan glow ring and check hex.
- `hero_card(id, opts)`: the square version (rewards, team slots, pickers).
- **new** `name_plate(level, max, name)`: "LV.46/120" on graphite + name on a black plate.
- **new** `rarity_mark(rarity, size)`: chevrons + uppercase rarity word in the rarity color.
- `rarity_badge` (skewed rarity plate), `tag` (flat 3 px radius tag, condensed), `role_badge`,
  `faction_badge(faction, size, show_name, light)`.
- **new** `hex_badge(icon, size, fill, fg, text)`: hexagon with a glyph or numeral; white
  fill gets a dark rim, dark fill a light rim.
- **new** `new_badge(size, text)` / `set_new(target, show)`: red-orange rounded "N"; a blue
  round "!" via `badge: "!"`. `dot` / `set_dot`: red dot with a white rim.
- **new** `equip_slot(slot, item, size, cb)`: pale tile, dark slot glyph, tier numeral hex,
  tier-colored base strip; empty = faint glyph + plus.
- `stat_row(stat, value, delta, label, light)`: glyph, uppercase short name (HP, ATK, DEF,
  SPD, CRIT), condensed value, green "+N". On white panels alternate `row` / `light_inset`.
- `reward_tile` / `reward_list(..., light)`: pale item tiles with a colored base strip and
  white outlined amounts bottom-right.
- `progress_bar(value, max, color, height, text, light)`: flat, 3 px radius, bright top
  edge, hatched fill when 16 px or taller.
- **new** `deco(kind, size, color)`, **new** `art_crop(id, aspect, zoom)`,
  **new** `vgradient(c0, c1, horizontal)`, `glow`, `rays`, `ribbon` (skewed band with
  hatching, side ticks, uppercase title), `art_background`.

## 5. Shell (`main.gd`, `ui.gd`)

- **Top bar** (104 px below the safe inset): leader avatar (70 px, tap = Team) with the
  team power chip; the resource pill (2 currencies, per screen via `UI.TOP_CURRENCIES`:
  default gems + gold; summon gems + scrolls; heroes / hero detail gold + hero EXP; gear
  gold + dust; `+` opens the shop or summon); the right cluster in one dark glass box:
  **Quests**, **Notices** (bell, opens a list of actionable items), **Menu** (grid of every
  destination, Settings included, Kit Preview in debug builds). Red dots on each.
- **Bottom nav** (120 px above the safe inset): Heroes, Team, **Lobby** (flat hexagon raised
  22 px above the bar, cyan rim and glow when active; keep the 100 px above the nav centre
  free of small text), Gear, Summon. White flat glyphs (60 px) over uppercase
  condensed labels; inactive `#aeb3ba`, active white with a short white bar above.
- **Chrome modes**: normal screens get solid bars (top: `#0b0c0e` to `#17191d` with faint
  hatching; nav: `#1a1c20` to `#0a0b0c` with a top hairline) and live between them.
  `UI.set_full_bleed(true)` (the lobby) lets a screen fill the window: the bars turn into
  gradients (black 70% fading down; transparent fading to black 90%) over the art; keep
  controls between `UI.content_top()` and the window bottom minus `UI.content_bottom()`.
  `UI.set_chrome(top, nav)` still hides bars (battle, summon reveal). Both reset on `go()`.
- **Routing**: `UI.NAV_TABS` = heroes, formation, home, gear, summon. `UI.NAV_ROOTS` also
  includes quests and shop (history resets; Back returns to the Lobby). Quests, shop,
  settings and campaign highlight the Lobby tab.
- **Toasts**: dark glass bar 540 px wide (every toast the same width, so a stack lines up),
  1 px light hairline, soft shadow, 6 px left edge in cyan (info), green (good) or red (bad),
  a glyph in a round bubble of that colour + white SemiBold text, centred under the top bar
  (motion: section 8).
- **Modals**: dim black 72%. `UI.popup(title, content, on_closed, width, light)` (Kit.dialog),
  `UI.confirm` (white dialog, light Cancel + cyan Confirm or red for danger),
  `UI.show_reward` (cyan rays and skewed cyan banner, white panel with a cyan top edge,
  "REWARD" technical caption, pale item tiles, cyan OK, "Tap anywhere to close").
- **Guide marks**: pulsing orange ring (`Guide.mark`). The shell marks nav tabs and the
  top-bar Quests button. A target with meta `guide_hex` (the raised Lobby tab) gets a
  hexagon ring around the hex instead of a box.
- **Pinned bottom bars**: the Lobby hexagon rises 26 px above the nav. Bars pinned to the
  bottom of a screen (campaign stage panel, quests Claim All, team Auto-fill / Battle) keep
  `UI.pinned_bottom_inset()` clear; scrolling lists may pass under it.
- **Scrollbars** are invisible and zero-width (theme). Show "more" with cut-off rows or a
  bottom fade (hero detail column) instead.
- **Top bar cluster** buttons (Quests, Notices, Menu) are 88 x 88.

## 6. Screen layouts (720 x 1560, safe-area sim)

Window y ranges with the notch sim: top bar 108-212, content 212-1378, nav 1378-1498, home
indicator 1498-1560. Without insets (720 x 1280): top bar 0-104, content 104-1160.
"Dark" means the default backdrop, "light" means `Kit.page_bg("light")` under the area.

### Lobby (`home`, full bleed) - mock: `kit_demo {"mock":"lobby"}`
- Full-window art: `HeroArt.background("home")` covered, the lobby hero **full body**
  (`HeroArt.texture`, 1024 x 2048) centred, height = window - content_top + 40, feet behind
  the nav; a black gradient over the bottom 45%. Painted art will carry the screen; keep
  the centre 360 px column free of widgets between y 380 and 1000.
- Top-left (content_top + 10): `banner_card` 330 x 132 (current summon banner, hero crop,
  "SUMMON NOW", 3 carousel pips). Top-right: `notice_bar` 340 ("Next: Stage x-y" to the
  campaign, or the first-session step).
- Left edge (x 6, from content_top + 176, 128 px pitch): `side_button` Daily (dark, dot),
  Offers (orange, N). Right edge: Hero (dark), View (dark, hides all UI and the chrome until
  the next tap).
- Mid-left (y ~ window/2 - 40, x 84): `speech_bubble` 400 wide; small white chevrons at both
  edges switch the lobby hero.
- Shortcut grid, bottom row ends 28 px above the nav (clear of the Lobby hex), plates 8 px
  from the screen edges with a 90-160 px gap in the middle so the hero shows between the
  columns: left column Shop (`blue`, 268 x 116), Sanctum (`dark`, 304 x 150,
  `percent_meter` "FILL 41%", "LV n" tag after the title, N when full); right column Team
  (`white`, 268 x 116, dot when the team can improve), Campaign (`orange`, 304 x 150, "!"
  badge inside the corner, art strip with the next boss and a STAGE tag). 8 px between
  rows.
- Quick claim and claim live in the Sanctum plate's sheet (tap the plate) or as a
  `side_button`; the first-session guide must still be able to mark the claim control.

### Roster (`heroes`) - mock: `kit_demo {"mock":"roster"}`
- Dark header strip (content top + 10, 88 tall): `tab_strip` [HEROES] at left; dark
  `secondary_button`s Team and Codex (or sort) at right.
- Light page from y +98: `filter_chips` (ALL + role glyphs, or factions), a sort button
  ("RARITY" + sort glyph) right-aligned, a `TEXT_DIM` hint line (20).
- `portrait_card` grid: 4 columns x 160, 12 px gaps, 18 px side margins; owned first, then
  unowned greyscale. Dots for upgrade-ready heroes, N for new ones. Scrolls vertically.

### Hero detail (`hero_detail`, nav hidden) - mock: `kit_demo {"mock":"detail"}`
- Light page; faction-colored hatch stripes across the bottom 520 px.
- Art: full body, height = content height, left edge at x -60 (the figure stands
  centre-left and is overlapped by the info column).
- Top-left technical caption: role hex 64, "HERO INFORMATION", techline.
- Info column (324 wide, 12 px from the right edge; it scrolls when the window is short,
  with a bottom fade and a down chevron while more is below): `rarity_mark` + star pips,
  `name_plate`, tier hex + "POWER" + condensed 50 px power, white `info_panel` with
  `header_bar("Status")` and alternating `stat_row(..., light = true)` rows, Level Up
  (`light_button`) + Star Up (`primary_button` or `costs_button`), a row of four skill
  `hex_badge`s (ultimate in the faction color), white panel with `header_bar("Equip")` and a
  2 x 2 grid of `equip_slot`s (150).
- Side tabs (Equip / Skills / Story) as `side_button`s pinned left of the column: level
  with the lower panel while it is on screen, never under Back / Home (tapping one also
  scrolls the column to the panel). `back_bar` bottom-left above the safe inset.
- Browse arrows flank the art at chest height (left screen edge, and just left of the
  column), 88 x 112 touch areas with a small dark tile; they never sit on the column.
- The top-left caption sits on a soft paper scrim above the art.

### Team (`formation`)
- Dark header: `tab_strip` [TEAM], team power (power glyph + condensed 44) right.
- Formation stage: two rows on a dark glass floor (front 2, back 3) of `hero_card`s (150)
  or `empty_slot`s ("FRONT" / "BACK"), faction-bonus chips (`tag`) under them.
- Light page below: `filter_chips` (factions), bench grid of `hero_card`s (5 columns x 120),
  selected = cyan ring. Bottom bar: `light_button` Auto-fill + `primary_button` Save/Battle.

### Summon (`summon`)
- Full-bleed banner art (featured legendaries full body), banner title as condensed white 56
  with a skewed rarity plate "FEATURED".
- `percent_meter`-style pity plate (Legendary within N pulls) and a `notice_bar` for the
  free daily pull. Rates as a `light_button` with the info glyph opening a light dialog.
- Banner title in two balanced lines (never an orphan word), on a soft dark scrim; the
  subtitle on a dark glass tag; featured names on small dark glass tags.
- Bottom: two `cost_button`s, x1 `secondary` and x10 `orange`, 330 x 112 each. While the
  free daily pull is waiting, x1 is `primary` with a green "FREE" price and spends nothing.
- Results: the ribbon, the cards and the shard / pity summary form one block centred above
  Summon Again / Done.
- Reveal: chrome hidden; cards flip as `hero_card`s with rarity rays (`Kit.rays` in the
  rarity color), results grid of `hero_card`s with N badges; Done = primary.

### Gear (`gear`)
- Dark header: `tab_strip` [GEAR], item count right. Light page: `filter_chips` (ALL + slot
  glyphs), hint, grid 4 x `equip_slot` (about 159, spanning the 16 px gutters) with name
  (condensed 18) and wearer (cyan
  condensed) or SPARE. Tap = light dialog: slot tile, name, tier, score, `header_bar` stats,
  Salvage (`danger_button`) or Open hero. Minimal version shipped in `gear_screen.gd`.

### Quests (`quests`)
- Dark header: `tab_strip` [DAILY] [WEEKLY later], reset timer right (timer glyph).
- Light page: one DAILY BONUS panel (the "complete N quests" milestone: progress, reward
  tiles, its Claim when reached; it is not repeated as a row); quest rows as white `row`
  panels: `hex_badge` glyph (cyan when done), title (Barlow Bold 26),
  `progress_bar` (cyan, 18), reward chips, Claim (`primary_button`, dot) / Go
  (`light_button`) / Done (disabled). Claim all = `primary_button` at the bottom.

### Shop (`shop`)
- Dark header: `tab_strip` [OFFERS] [GEMS] [DAILY]. Light page: offer cards as `info_panel`s
  with an art band (`banner_card` look) and a big condensed price; gem packs as a 2-column
  grid of pale tiles (gem art, amount condensed 36, price `primary_button`). Every price
  button says "Test purchase: no charge" (keep the e2e string).

### Settings (`settings`)
- Dark header: `screen_header("Settings")` or a tab. Light page: `info_panel` groups with
  `header_bar`s (SOUND, BATTLE, ACCOUNT, DEV TOOLS); rows = label + `toggle` / `segmented`;
  Reset Save = `danger_button`; credits in `TEXT_DIM` 20 (fonts: Barlow, Barlow Condensed).

### Campaign (`campaign`)
- Full-bleed chapter art with the stage path; dark header strip: chapter `tab_strip`
  (CHAPTER 1 / 2 / 3), progress "3 / 10" condensed.
- Stage nodes as hexagons (`hex_badge`, cleared = cyan, current = orange glow, boss = red
  roof + boss crop). Bottom: stage `info_panel` (stage id condensed 44, name, recommended
  power vs team power, enemy `hero_card` row, first-clear `reward_list(light)`), Fight =
  `orange_button` full width.

### Battle HUD (`battle`, chrome hidden)
- Top (safe top + 12): stage id tag, timer (condensed 30 on dark glass), speed `segmented`
  1x/2x/4x and auto `icon_button`s on the right, `icon_button` exit (retreat confirm).
- Units: HP bars `progress_bar` 10 px (allies `GOOD`, enemies `EMBER`), energy 6 px `ACCENT`.
- Bottom: five ally portraits as `hero_card`s (110) on a dark glass rail; a full energy bar
  gives the card a cyan glow ring and a pulsing "ULT" tag; Skip = `secondary_button`.
- Result: `ribbon("VICTORY", ACCENT)` or `ribbon("DEFEAT", EMBER)`, stars, reward panel
  like the reward popup, Next Stage = `orange_button`, Retry / Lobby = `light_button`s.

### Dialogs and reward popup
- Any dialog: `Kit.dialog` 560-640 wide; body 26 px padding; question text `TEXT` 28
  centred; secondary = `light_button`, primary = `primary_button`; cost strips in a
  `light_inset` with an uppercase `ACCENT_DEEP` label; materials as `reward_list(light)`.
- Reward popup: `UI.show_reward` (see section 5). Queued popups show one after another.

## 7. Character art in the UI

Painted heroes arrive as 1024 x 2048 PNGs through `HeroArt` (feet near y 1990). The UI
never assumes the placeholder silhouettes:
- **Cards** use `Kit.art_crop(id, aspect, zoom)`: framed from just above the head, using
  `HeroArt.portrait_region` (head and shoulders). Portrait cards: zoom 1.3, waist-up. Avatar:
  aspect 1, zoom 1.6-1.7. Banner art: aspect ~1.15, zoom 1.15. Plate art strips: 2.2 / 1.4.
- **Lobby and hero detail** show the full body (`HeroArt.texture`) at about 1.0-1.1 x the
  content height; leave the face area clear of widgets.
- Battle sprites are unchanged (`HeroArt.make_sprite`).

## 8. Motion and feel (2026-10-19)

The owner asked for "the 1% parts that make a game feel really nice to use". What every
screen gets for free, and how to stay inside it:
- **Presses** (`Kit.add_press_fx`, on every Kit button, tile, card and `make_tappable`): on
  touch-down the target squashes at once (3.5-8 %, more for small buttons) and brightens
  14 %; on release it springs ~4 % past full size and settles (back ease). A press that
  turns into a scroll restores quietly. Tapping a disabled button shakes it with the `deny`
  sound (`Kit.deny`). Taps play `tap` plus a light haptic (`Kit.haptic(10, 0.35)`); tabs and
  chips play `tab`; switches `toggle`. Disabled buttons are frosted slate (`*_disabled`).
- **Glints**: primary and orange buttons, banners and the orange / blue lobby plates catch a
  soft light sweep every 4-9 s (`Kit.add_shine`, drawn only while it moves). Orange buttons
  breathe a glow behind them (`Kit.add_glow_pulse`). Keep one orange call to action per
  screen.
- **Navigation** (`UI.go`): deeper screens slide in from the right (the old one drifts left,
  darkens and fades), Back mirrors it, bottom-nav tabs cross-fade, hero browse slides the
  way the arrow points, a battle zooms in behind a "Preparing battle" veil (`UI.busy` /
  `UI.idle`, `Kit.spinner`). New content rises in with a short stagger (`Kit.stagger_in`);
  a screen with an `intro()` method runs its own instead (the lobby: plates rise, side
  buttons slide in from their edges). The bottom nav's white bar and the tab strips' cyan
  bar slide between tabs; the new tab's glyph hops.
- **Popups**: the backdrop dims in, the panel springs up from 80 % (`pop` sound); closing
  shrinks and fades it and releases input at once. Toasts drop in with a spring, carry an
  icon bubble, stack, glide up as one leaves and dismiss themselves ("bad" ones play `deny`).
- **Numbers**: wallet amounts count with a colour flash and a floating "+N" (`Kit.float_text`);
  after a reward popup the currencies fly from their tiles into the wallet, which counts up
  as they land (`main.fly_currency`). Reward tiles pop in one by one with glints and rising
  notes; progress bars fill in when they appear; badges and red dots breathe.
- **Launch**: `BootScreen` (halo wordmark, Aero bubbles, shimmering bar, tips) covers the first
  frames while the lobby builds.
- **Reduce motion** (Settings > Display, `Kit.motion_ok()`): slides, staggers, glints, glow
  pulses and fill-ins stop; presses and fades stay. Check it for anything new that moves.
- **Cost rules**: animate with tweens on transform / modulate, not `_process` redraws; draw
  shapes once and move or fade the node. Nothing here runs on the battle HUD during a fight.
- **Containers reset scale and position when they re-sort.** For position offsets use
  `Kit.offset_in` / `Kit.shake` (they survive re-sorts); scale tweens re-apply each frame.

## 9. Notes for screen owners

- Start from the mocks in `kit_demo.gd`; they use only public Kit API.
- On light pages use `TEXT` / `TEXT_DIM`, `light_button`, `stat_row(..., light)`,
  `reward_list(..., light)`, `section_header(..., light)`, `empty_state(..., light)`.
- Replace v1 accents: `GOLD_LIGHT` titles become `INK` (dark) or `TEXT` (light); gold
  numbers become `ACCENT_HI` (dark) or `ACCENT_DEEP` (light); gold buttons become
  `primary_button` (cyan) or `orange_button` for the single urgent action.
- `UI.popup(..., light = true)` for new dialogs; build their content with `TEXT` colors.
- Keep every control at least 88 px tall, keep text out of the safe-area insets, and keep
  the e2e strings ("Skip", "Done", "OK", "Onward", "Fight", "Claim", "Test purchase: no
  charge", ...) on the buttons the tests press.
- Review: `tools/shoot <screen> --rich --safe-area-sim`, then put the shot next to the
  matching reference (privately, in a scratch folder outside the repo) and check it reads as
  the same family at a glance.
