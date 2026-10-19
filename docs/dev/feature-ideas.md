# Feature ideas

Brainstorm with the owner, 2026-10-19. Nothing here is built yet. The owner asked for ideas that are
new to the genre ("no i need something novel"), not the usual idle gacha features, and picked two:
**the Rival** and **Misprints** ("i like the rival and the misprints ... keep these too"). The rest
are open. Rules for any of these follow `CLAUDE.md`: simulations (the Rival, the market) are plain
classes in `src/core/` on our own RNG with integer math, and real time comes in from the UI.

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
4. **She raids the Sanctum.** Idle rewards left full too long get skimmed, with a cut-out-letter
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
9. **Prints age.** Prints left out in the real sun fade a little; rare foxing and patina are prized;
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

## More ideas (open)

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
