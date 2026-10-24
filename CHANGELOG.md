# Changelog

Downloads: [GitHub releases](https://github.com/MrEveryDay98/VoxHack/releases) · [itch.io](https://mreveryday.itch.io/voxhack)

## v0.7.9 (alpha) - 2026-10-24

- **Real shadows.** Monsters, objects and you (in third person) cast a shadow on the floor: the sprite itself, blacked out and projected away from the light, from its bottom corners, turning and slanting as it turns. Options: Shadows (on/off) and Shadow opacity.
- **Sprites without their drawn shadows.** Options > Shadows drawn on sprites > Removed (after a restart) uses a copy of the tile set with the black shadows painted on the monsters and objects taken off.
- **Polearms stab.** Hitting from a distance with a polearm, lance or Snickersnee thrusts the weapon forward. Their reach is your arm's reach times a multiple that grows with your skill, measured in the 3D world, at any angle.
- **Snickersnee's free hit** (once a turn, taking no time) sounds different: slowed, ringing on. Once it's used, a click spends the turn with a swing instead of "The blade doesn't reach there!" over and over.
- **Q invokes** what you wield when it can be invoked (an artifact's power, a crystal ball): "Q  Invoke" shows on the left.
- **Invisibility.** Invisible, you aren't drawn in third person; if you can see invisible, you and the invisible monsters you see are a see-through, crawling fuzz (as Doom's spectres).
- **Poison gas clouds** are a lasting cloud of particles while they last.
- **Chests and boxes always show** in a pile of things, however deep in it.
- **Drop** (Alt wheel) lets you tick several things at once.
- Fixed: the "?" for a monster you can't see (blind, hitting it) went missing or on the wrong square.
- Fort Ludios is hand-built, under its own night sky; new cave dweller pictures.
- **For modders:** the VoxHack Editor's Effects tab has Loops triggers (effects that play without a break over every square of a gas cloud).

## v0.7.8 (alpha) - 2026-10-23

- **Break boulders with a pick-axe:** attack a boulder next to you with a pick-axe or mattock in hand ("The boulder falls apart").
- **Altars show their alignment** even with things lying on them, and change picture when you convert them.
- **The Mines' walls** are cave walls even when you arrive blind.
- **The Big Room under the open sky** (a hand-built area): no ceilings hanging in the air over random ice patches, stairs, melted ice or anything else that changes; the solid rock round an open-sky area stops at wall height instead of standing as a dark cliff.
- New pictures for the altars (each alignment its own), wolves and werewolves, the mumak, the tinning kit and the can of grease.
- Fixed: "You are hurt by fell into a pit!".

## v0.7.7 (alpha) - 2026-10-22

- **Cursed items show red, blessed ones light blue** once you know (the inventory, containers, item menus and the "which item?" lists).
- **The dungeon level is under the mini-map** ("Dlvl:4 (The Gnomish Mines)", with the branch outside the main dungeon), instead of in the line top left.

## v0.7.6 (alpha) - 2026-10-22

- **The Oracle speaks.** Her consultations are read aloud with SAM from where she sits: a minor one's rumor, and a major one's whole oracle.
- **Priests greet you aloud** ("Pilgrim, you enter a sacred place!"). Lines the game puts together as it goes are now spoken in their speaker's voice too.
- **Exploding lights flash the screen.** A yellow light's blast of light (or a black light's kaleidoscopic one) turns the screen white at once, fading away slowly.
- The mail daemon speaks live too; "Delphi" is pronounced properly; new coin sounds.

## v0.7.5 (alpha) - 2026-10-22

- **Minetown has its own music** (and the Big Room). Special levels with a track of their own now play it, instead of their branch's music.
- **Hallways sound like hallways.** Corridors get a tight stone echo of their own, exactly on NetHack's corridor squares; rooms, doorways and the edges of rooms keep the room's sound.
- **A monster's arrow is no longer your doing.** A monster's missile that killed a watchman counted as you murdering him ("You murderer!", luck and alignment lost, the watch's anger), and a monster's potion breaking in a shop was billed to you. Now it's the monster's, as in NetHack.

## v0.7.4 (alpha) - 2026-10-22

- **Hallucinated boulders stay solid.** Hallucinating, a boulder drawn as some random object lost its hitbox and you could walk through it. It now keeps a boulder's full box (push it, squeeze past it, bump into it as ever), whatever it looks like; something merely pictured as a boulder isn't solid.

## v0.7.3 (alpha) - 2026-10-21

- **Jumping.** Hold Space (a tap still waits a turn): the squares you can jump to light up green on the floor - a Knight's L-shaped knight's moves, or any nearby square with jumping boots - and the one you look at glows brighter. Let go to jump there; you hop across. NetHack's own rules decide everything, and when you can't jump right now (burdened, levitating, held...) it says why.
- **Invisible monsters no longer hold you in place.** Stepping where an unseen monster stood was refused and your body put back, again and again: with invisible monsters around you couldn't get away. You now walk in among them, and NetHack tells you something's there.
- **Pushed boulders stay in step.** A boulder could be seen (and bump into) where NetHack no longer had it, a square behind where it really was, blocking your way.

## v0.7.2 (alpha) - 2026-10-21

- **Chatting is reliable.** Right-clicking a peaceful monster always chats with it, and holding right click always offers Chat. Before, a monster right in front of you could be two squares away on NetHack's map, or on your own square, and the right click acted on your own square instead; or it had just stepped aside, and you talked to empty air.
- **The pause menu's tips** sit just left of the menu at any screen size; they could overlap it.

## v0.7.1 (alpha) - 2026-10-21

- **F3: NetHack's commands.** A scrollable list of every command, with its #name, its key and what it does (NetHack's own descriptions). Type any of them in the command line (T). F3 again or Esc closes it. (F3 no longer toggles the fog.)
- **The pause menu's tips** (F2: NetHackWiki, F3: NetHack's commands) sit to the left of the menu.

## v0.7.0 (alpha) - 2026-10-20

- **Level changes fade.** Going up or down stairs, falling or teleporting to another level fades to black, holds still while the new level is built, and fades back in.
- **Falling through a hole or trap door takes half a second:** you drop into it before you land on the level below.
- **Searching for a number of turns (Ctrl+X) plays out like being helpless:** time runs fast forward, you're seen from behind and stand still, a turn at a time, and it stops whenever NetHack would stop it (a monster comes near, you get hurt...), or when you press X.
- **Objects lying on stairs and ladders never hide them:** stairs first seen with something on them were built as plain floor.
- **Wizard mode** (a world with a file named `nhv_debug` in it): K flies and H noclips. Flying, your body is a free camera and the hero stays where it stands; land to go back to it. Noclipping, the hero is invulnerable. `/brightness 0-100` lights the level.
- **For prefab builders:**
  - Area ids are shown without a "#1" on every one.
  - `/area revert` starts the area you're standing in over, undoing every change made to it (in this session and earlier ones).
  - The Wizard's Tower is built from its own areas (part 3); the astral plane has its own sky.

## v0.6.0 (alpha) - 2026-10-20

- **Spoken lines, live.** Shopkeepers, priests, your god, the Wizard of Yendor and some of the game's own texts are read aloud with SAM, the 1982 speech synthesizer, built into the game: it reads the real line as it happens, names and all ("Hello, Ron! Welcome to Asidonhopo's general store!"), from where the speaker stands. Each monster of a kind sounds a little different, female ones higher, big ones deeper. (NetHack options > Spoken lines turns them off.)
- **Sounds come from where they happen.** Monsters' noises, attacks, spells and deaths, doors, drawbridges, boulders, explosions, splashes and breaking potions come from their place, panning and fading with distance. Behind a wall or a closed door they're muffled. (Your own actions stay with you.)
- **Acoustics.** Every place has its own echo: the Mines ring like caves, temples like chapels, corridors are close and dry, big halls ring long, Gehennom sounds hellish, and underwater is muffled. Music stays clear.
- **Monsters killing monsters** (your pet's kills too) make the monster-killed sound.
- **Locked chests offer your lock pick** (or key, or credit card): "Unlock it with your lock pick?", as NetHack options > Locked doors / boxes says.
- **Hallucination's screen waves and colours can be turned off** (NetHack options > Hallucination screen waves and colours; monsters still look wavy). The NetHack options page scrolls.
- Fixes:
  - A click attacks once: a slightly long click could attack (and swing and sound) twice.
  - No "Other things that are here:" window after autopickup; the list down the left shows them.
  - Open holes and pits catch you anywhere in their square, not only at its middle.
- **For modders, in the sound editor:** voices are SAM's (Voice casting: per-speaker SAM voice, variation, effects like echo, reverb, chorus, robot...; a pronunciation dictionary; previews as the game says them), and a new Acoustics tab tunes each kind of place's reverb.

## v0.5.0 (alpha) - 2026-10-19

- **Kicks hit the monster before the items.** A monster in your kick's arc is kicked before any objects, including one sharing your own square.
- **Wavy sprites** (invisible, detected and hallucinated monsters, and those sensed by telepathy) no longer show stray pixels at their edges.
- **The Oracle's centre** is built as designed: doors in hand-built areas keep the blocks built above them, and when the door is on another side the wall built beside it fills its old spot.
- **Map blocks no longer go missing** in the prefab editor (each block is meshed on its own).
- **For prefab builders:**
  - **The level atlas:** `Launchers\VoxHack Level Atlas.bat` asks for a seed and builds every level of that game side by side (terrain only), to see how the prefabs fit together. Fly about with K and H; `/atlas` lists the levels, `/atlas <number>` goes to one, `/atlas ceilings` takes the ceilings off.
  - **`/copy` and `/paste`** in the prefab editor, with `rotate 90|180|270`, `flip x|z` and `noair`.
  - **A Sky block:** invisible, and nothing behind it is drawn; the sky shows there instead.
  - Area plates in the editor use the level's own walls (the Mines' in Minetown, Gehennom's in Orcus Town...), as the game builds them.

## v0.4.0 (alpha) - 2026-10-18

- **The tutorial is back, rewritten for VoxHack.** New characters are asked "Do you want a tutorial?" (Options > NetHack options > Offer the tutorial turns the question off). Its engravings now teach the 3D game's controls: WASD and the mouse, left click to fight, the right click and its wheels, F to pick up, X to search, the 1-5 keys, the inventory, Z for the map, F2 for the wiki.
- **Inscriptions show low in the middle of the screen**, in gold: what's engraved, written or burned where you stand stays there until you step off. ("Something is engraved here" still goes with the messages, and everything is in the log, T.)
- **Iron bars face the right way**, running along the wall or line of bars they're part of, and their see-through sides now turn with them (they were drawn edge-on across north-south passages).
- **Shop signs.** A wooden sign over each shop's door shows the shop's name ("Abitibi's / General Store") once you've seen the door; Minetown's shops have them too. Options > NetHack options > Signs over shop doors turns them off.
- **Levitation floats you.** You hover a little above the ground (over pits, water and the way down too, as NetHack says you can't reach the floor), rise with the steps of a staircase up, and make no footsteps or weapon sway while floating.
- **Picking a place on the map** (teleport control, a detection scroll...) uses the fullscreen map itself, exactly as Z shows it: click a square (it lights up under the pointer), Esc cancels.
- **The fullscreen map draws monsters, objects and features over their floor**, not on black squares: you, your pet, a dropped dagger, stairs, fountains and altars sit on the room or corridor floor under them.
- **Fighting blind works.** Left click hits a monster you can't see (blind, invisible, in the dark) when it's where you swing, as in NetHack ("You hit it.").
- **Telepathy while blind** (from eating a floating eye) shows the monsters it senses through the blindness, across the whole level.
- **Loading a game while blind** shows the blind view, not a black screen.
- **For prefab builders:** a world-building sprite sheet of block textures in the vanilla tile style (bricks, cobbles, planks, grass, roofs, carpet, a bookshelf...) and a World-building tab in the block editor to use them.

## v0.3.0 (alpha) - 2026-10-18

- **Pick up is now F** (it was R). When you're standing on items with nothing else there to use (no stairs, fountain, altar, box...), a right click tap picks them up too.
- **Help in the pause menu.** Esc > Help explains every default key: moving, fighting, the right click and all its wheels (Shift, Alt, Ctrl, E), the other keys, and the function keys.
- **A tip in the pause menu:** F2 opens NetHackWiki on whatever you're pointing at.

## v0.2.1 (alpha) - 2026-10-18

- **Sleeping gas traps put you to sleep again.** NetHack said "A cloud of gas puts you to sleep!" but woke you at once; now you sleep it off (third-person view, Z's and fast-forward while you're out). The same fix covers other things that leave you helpless as you walk, like a sleep ray or a floating eye.
- **Known traps stay visible under items and corpses.** A trap you've found keeps its picture on the floor when something is dropped on it.

## v0.2.0 (alpha) - 2026-10-18

- **NetHackWiki in the game (F2).** Press F2 while looking at a monster, an object or a feature to open its NetHackWiki page, right in the game: headings, colours, lists, links, pictures, infoboxes and tables, with Back/Forward, search and a Home page. F2 again closes it. Every item's menu has a **Wiki** button too, and `/wiki <page>` works from the command line. Pages are fetched live and kept for offline use. Lookups only ever use what you know: an unidentified potion opens the general *Potion* page.
- **Update check.** The title screen tells you when a newer VoxHack is out, with a link to download it (setting `nhv_update_check` turns it off).
- **HUD tidy-up.** Level, gold, AC and experience sit under the HP and Pw bars; the bottom status is one line (attributes, alignment, turns, conditions).
- **Pick-up prompt.** When something lies under you, the list of what's here shows **R  Pick up**, lower on the left, out of the way of messages.
- **Your money flashes gold** whenever gold is picked up or lost.
- **Controls:** F2 is the wiki (it no longer toggles the chat display).

## v0.1.0 (alpha) - 2026-10-18

The first public build: NetHack 3.7 in first person, in a voxel world.
