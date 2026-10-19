# Changelog

Downloads: [GitHub releases](https://github.com/MrEveryDay98/VoxHack/releases) · [itch.io](https://mreveryday.itch.io/voxhack)

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
