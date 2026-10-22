# Feature ideas

Brainstorm with the owner, 2026-10-19. **Built since (2026-10-20): the Rival (1 and 2: she learns
your team and tags your Lobby poster; she collects prints, 11 in part) and Misprints (numbered
prints, flaws, holo foil and grading: 7 and 8 in part)**; rules in `src/core/rival_rules.gd` and
`print_rules.gd` (port spec `docs/dev/unity-port.md` 8.5 and 9c), screens `rival` and `prints`.
Everything else here is not built. The owner asked for ideas that are
new to the genre ("no i need something novel"), not the usual idle gacha features, and picked two:
**the Rival** and **Misprints** ("i like the rival and the misprints ... keep these too"). The rest
are open. Rules for any of these follow `CLAUDE.md`: simulations (the Rival, the market) are plain
classes in `src/core/` on our own RNG with integer math, and real time comes in from the UI.

**Nothing that makes the game harder (owner, 2026-10-19).** Of the "More ideas" batch below the owner
said "no. these all make the game more difficult". New features add delight, rewards, spectacle or
less grind; they never punish, take things away or add skill checks. So the Rival never takes
anything (no Sanctum raid) and prints never fade (no ageing) unless the owner asks for them.

## Picked by the owner

### The Rival

Another summoner plays the same game alongside you: a Fallen hero, simulated on the phone on her own
idle curve (no server). She pulls from the same banners, sometimes gets the featured hero first and
gloats, climbs the Spire ahead of you, and challenges you; beating her wins part of her haul.

1. **She learns your team.** She reads which heroes you lean on and builds counters ("predictable").
   Change your team and she has to adapt.
2. **She vandalises your posters.** When she wins, she tags the Lobby poster (stickers, a drawn-on
   moustache, "LOSER" over the halftone band) until you beat her; then you tag hers.
3. **Lieutenants who remember you.** Five named Fallen captains: beaten ones come back scarred and
   holding a grudge, winners get promoted. Caution: Warner Bros holds a patent on its "Nemesis"
   system; keep this lighter and different, and check the patent before it ships.
4. **She raids the Sanctum** (dropped: it punishes). Idle rewards left full too long get skimmed, with a cut-out-letter
   ransom note saying how much; you can win it back.
5. **She can turn.** Rival, then frenemy, then reluctant ally; at the end of her arc she joins you, a
   16th hero that is earned, never pulled.

### Misprints

Every pulled hero is a numbered print ("No. 0412 of 5,000"). A few come out misprinted: shifted
plates, swapped inks, a missing plate. Rare misprints are cosmetic collectibles shown on the profile,
like stamp errors. They never change stats. The print shaders already draw every flaw.

6. **Print your own pulls.** The summon is a screen print: drag the squeegee across the screen, and
   how evenly you pull sets the grade (a sloppy pull misprints more often).
7. **Grading.** An appraiser grades each print 1-10 (centering, ink, edges), like trading-card
   grading; a "Gem Mint 10" first-edition misprint is the top trophy.
8. **Editions run out.** Each banner is a limited print run; serials 0001-0100 carry prestige, and a
   sold-out edition is gone for good.
9. **Prints age** (dropped: it punishes). Prints left out in the real sun fade a little; rare foxing and patina are prized;
   laminating stops the ageing.
10. **Double exposure.** Two heroes through the press at once: a rare cosmetic overprint with both on
    one sheet.

### Where the two meet

11. **The Rival collects too.** She hunts the same misprints, bids against you, offers lowball trades
    and gloats over a No. 0001.
12. **A collectors' market.** NPC collectors with their own tastes (one wants only misprinted angels,
    one pays anything for red); prices move as they buy, you sell misprints for currency, and the
    Rival can corner a market. Offline.
13. **Poster wars.** Paste prints across the 3D Campaign map to claim districts (rarer prints hold
    better); the Rival pastes over yours overnight, and each morning the map shows who owns what.

Claude's suggested first loop: 1, 2, 6 and 13 (print, she competes, the map keeps score).

## Art first, light commitment (2026-10-22)

The owner's steer after the core-loop pitches below: "i want the artwork to be front and center.
obviously people are buying the skins for the sexual value, so i want to continue giving them that
value, while not making the game too much of a committment". That rules out the city builder (the
art would shrink to buildings and it asks for planning). Claude's pitch for the main loop:

- **The cover shoot.** You run the afterlife's hottest pin-up magazine; the v4 poster UI already
  reads as one. A session is about two minutes:
  1. The idle haul is already counted.
  2. This week's readers want something ("Bunny Lounge, a demon, night"). Pick a hero and a skin;
     she fills the screen, rigged and moving. Frame the shot (pinch to zoom, angle, lighting) and
     shoot.
  3. It prints as a cover, becomes the Lobby poster and goes on your wall; sales come in while you
     are away, more when the cover matches what readers want. A weekly special issue (the swimsuit
     issue is Aqua Resort week) pays a bonus.

  Skins become the best tool in the game, not only a costume: every skin is a new cover and a trend
  match pays more, though no skin is ever required. One shoot a day is the whole commitment;
  missed days bank up, nothing expires and nothing fails. Battles keep running on auto for currency
  and heroes (manual play stays possible, never needed). It reuses what exists: 40 heroes x (base +
  4 skins) of installed art and rigs, the Rival as a rival magazine chasing the same trends, covers
  as numbered prints with Misprints. Adult gachas already reward play with art; a game where
  styling and shooting the art is the game itself was not found.

## Core loops (pitched 2026-10-22, set aside for "Art first" above)

After the batch below the owner said: "no i dont like these ideas. i want it more to do with what
keeps players coming back, the core gameplay loop, etc. like no one has made a proper city building
gacha. stuff like that". So: a different genre as the main loop, done properly, with gacha heroes
at its centre. Still nothing that makes the game harder.

- **Build Heaven and Hell (Claude's pick).** A real city builder, close to LucasArts' *Afterlife*
  (1996, a PC sim about building Heaven and Hell) with gacha heroes running it. Souls arrive every
  hour; you zone them into Celestial districts (virtues) and Infernal ones (sins), with the Fallen
  in the neutral strip between; placement and adjacency set the output (an Islanders-style score,
  no failure). Every hero is a landmark with her own ability (one opens a night club, one a
  cathedral spa), so a pull adds a new thing to build, not just bigger numbers; a dupe levels her
  landmark and a skin restyles it. Heroes live in the city and visit each other's places. The city
  is the idle Sanctum: it earns while you are away and you come back to a bigger city. Battles stay
  (mostly idle, manual ultimates) and win new land at the edges. No disasters, no raids. Closest
  existing games: Cookie Run: Kingdom (a Hay Day-style production town) and the 4X games (Whiteout
  Survival, Rise of Kingdoms: timer queues and PvP war); in neither do the heroes make up the city.
  Buildings would be Blender Cycles renders like the UI objects.
- **The heist crew.** Each day brings new targets (a Heaven vault, a Hell casino). Pick a crew of
  five; each hero has heist roles (the face, the hacker, the safecracker, the getaway driver) and
  combos. Plan on a dossier board in the poster style, then the heist plays out on its own as a
  comic while you are away. A heist never fails; a better plan means a bigger haul. No known gacha
  has heists as its core.
- **The club.** Run Purgatory's hottest club with heroes as the staff; matching hero to guest sets
  the night's takings, and the four skin packs (Aqua Resort, Bunny Lounge, Club Chrome, After Dark)
  become rooms and uniforms with bonuses. Not new: Cabaking (iOS) and KLab's Koi Shite Kyaba Jo do
  host-club management, and Yakuza's Cabaret Club Czar is a loved minigame version.

## Your game is yours (rejected, 2026-10-22: "no i dont like these ideas")

The owner asked for "something no one else has ever done" to stand out from thousands of gachas.
The theme of this batch: no other player's game looks like yours. A web search found no shipped
gacha RPG doing the first two.

- **One-of-one heroes (Claude's pick).** Every copy of a hero you pull is its own original painting:
  the same woman, a different pose, outfit cut, lighting and backdrop, numbered like a print. A
  duplicate is no longer a let-down: it is a new painting of her (and still counts as a dupe for
  stars). Players can show off a version nobody else owns. A studio that pays artists can't paint
  dozens of versions of every hero; our MOSS pipeline can, so rivals can't copy it cheaply. Costs:
  about 4 GPU minutes per finished painting (25 per hero for all 40 is roughly 65 hours, over many
  nights), the owner reviews every one, and the paintings are too many for the IPA, so the app
  downloads each one when it is pulled. Battles keep the rigged base art; a painting can get a
  quick rig (`tools/art_quick_rig.py`) to blink and breathe on the Lobby poster.
- **Your pulls write the story.** The story's cast is whoever you pulled, in the order you pulled
  them: the first hero is your lead, each new one enters at the current chapter, a dupe deepens her
  arc, and the Rival goes after the one you use most. Printed as a pulp serial in the poster style
  from the existing art. Every pull, a dupe included, moves the story on. No GPU needed.
- **She lives on the phone, not in the app.** The lead hero on the Lock Screen and in StandBy (the
  bedside clock while charging on its side), showing the idle haul and a line of hers. Needs a
  WidgetKit extension added to the Xcode project on the macOS runner; widgets in sideloaded apps
  can be unreliable depending on how the IPA is signed, so this is the riskiest of the three.

## Pure upside (open)

Pitched after the owner's "these all make the game more difficult". None of these adds difficulty.

- **Care packages.** Heroes leave you presents while you're away (gems, a print, a scribbled note
  with a lipstick mark), waiting on the Lobby poster.
- **Goodnight.** Tell the game you're going to bed; a hero says goodnight, and in the morning there
  is a bonus on the idle haul and the Daily Halo on the doorstep.
- **The Concierge.** A hero you pick runs your chores in one tap (dailies, the Sanctum claim, level
  ups, best gear on everyone), with commentary on how you'd be lost without her.
- **Divine intervention.** Once a day, when a fight is lost, a hero you don't have swoops in for one
  giant cut-in ultimate and turns it, then winks and leaves (and a taste of her makes you want her).
- **Stomp.** Stages far below your power clear in one second with a full-screen riso finisher
  instead of a whole fight.
- **Plate by plate.** Pity as a print: every pull on a banner prints one more ink plate of the
  featured hero's poster; when the last plate lands she's yours. You always see how close you are.
- **Benched heroes train.** Heroes outside the team slowly train themselves, so nobody falls behind
  and every pull stays useful.
- **The gallery wall.** Hang your prints on a wall; NPC collectors visit, admire the rare ones and
  leave tips. Misprints that only pay out.
- **Poster press.** Make your own poster from any hero you own (type, colours, layout, misprint
  effects), set it as the Lobby, or save it sized as a phone wallpaper.
- **Shake the Sanctum.** Shake the phone to collect the idle haul; coins rain down the poster.
- **Birthdays.** Your birthday (the game asks once) turns every screen into a party with a free
  pick; each hero has a birthday too, with a gift from her.

## More ideas (rejected: "these all make the game more difficult")

- **The Daily Halo.** A newspaper printed overnight from your own save, shown at the first login of
  the day: headlines ("KESSA CARRIES 4-7"), Rival sightings, gossip, classified ads (the day's
  offers), the real sky's weather and a horoscope.
- **The fine print.** Infernal heroes offer contracts: a big boost now, with a clause in tiny type
  you can zoom in to read ("for 3 days, every 10th pull is hers"). Reading the fine print is the game.
- **The Gate.** A daily desk game: souls arrive at the gate with papers, you spot the forgeries and
  send each one up or down; mistakes have consequences.
- **Sigils.** Cast an ultimate by drawing her sigil with a finger; the cleaner the stroke, the
  stronger the hit.
- **Moods.** Heroes benched too long sulk and refuse to fight until you make it up to them; heroes
  run ragged get tired. The roster feels alive.
- **Couples.** Two heroes fielded together often become a pair, with banter and a duo ultimate. It
  comes from how you play, not from a fixed list.
- **Mercenary prints.** A crusade mode with permadeath, played with one-run copies of your heroes, so
  nobody loses a hero they paid for.
- **Comic replays.** Your best fight is printed as a four-panel riso comic strip to save and share.
- **Secrets.** Heroes tell you secrets. Keep them for trust, or trade one to the Rival for an edge,
  and risk the hero finding out.
- **Holo foil.** Rare prints with a holographic foil that shifts as you tilt the phone (the tilt
  global is already there).
- **Hidden cipher.** Serials and misprints carry pieces of a code; solving it unlocks a secret hero.
- **Yesterday's you.** A daily duel against your own team as it was yesterday.
- **They choose you.** A recruitment path outside the gacha: post a notice, and heroes join or turn
  you down based on your reputation.
- **Sin seasons.** Each season is one of the seven sins or virtues and changes the rules (Greed: gold
  doubles and prices rise).
- **Photobomb.** Pose a hero over the phone camera's live view and take a photo (Godot's camera
  support on iOS needs testing first).

## Earlier ideas (open)

- **Fall and Rise.** Corrupt an angel or redeem a demon: her faction, skills and look change (a
  cracked halo, horns). The Fallen are the halfway point. Looks from Blender chrome halos and horns
  on the rig's head bone plus a colour shift, or repainted versions (GPU, ask first).
- **Vigil.** Leave the game open with the phone face-down and the heroes keep watch; rewards grow the
  longer it stays down and reset if you pick it up. The screen dims.
- **The pager.** A Blender-rendered chrome flip phone where heroes text you about what really happened
  while you were away, flirt, get jealous of your team picks, and send real phone notifications.
- **Real sky.** Local time and the real moon phase: angels stronger by day, demons at night, the
  Fallen at dusk and dawn; full moons and eclipses start events.
- **Soul Ledger.** How you play (spending, skipping, re-rolling, daily devotion) tilts your soul
  toward Halo or Horn, which changes who trusts you, which banner leans your way and how the Lobby
  looks.

## Genre staples (still needed some day)

Offered first and set aside as not novel: login calendar, mail, achievements, local notifications,
expeditions, a weekly boss, events, bonds and story scenes, a gallery, a season pass, arena, friends
and guilds.
