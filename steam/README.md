# VoxHack on Steam (Early Access): the kit

What's ready, what only you can do, and in which order. The store page text
is in [STORE_PAGE.md](STORE_PAGE.md).

## 0. Decide first (blockers)

- **SAM, the voice.** Its code has no licence (CREDITS.md). On itch and
  GitHub that risk was accepted; on Steam, especially if the game is paid,
  a takedown hurts more. Either accept it knowingly again, or ask me for a
  build without SAM (Spoken lines off and the SAM code left out).
- **Free or paid.** NetHack's licence allows selling the game, as long as
  the full source stays available (it is: GitHub, linked from the README and
  the store page). Steam's fee is the same either way.
- **The name "NetHack".** The licence covers the code, not the name. The
  store page says "based on NetHack" and "not an official NetHack release".
  Consider telling the NetHack DevTeam before launch.
- **Keep proof of your music and sound licences** (the royalty-free and
  CC0 sources in CREDITS.md). Valve can ask for it.

## 1. Steamworks account (you; once)

1. Sign up at https://partner.steamgames.com/ (Steam Direct).
2. Fill in the company or personal info, the **tax interview** and **bank
   details**, and verify your identity.
3. Pay the **Steam Direct fee** (US$100 per game; paid back once the game
   makes US$1,000).
4. New developers wait **30 days** after paying before they can release.
   Use the time for the store page and builds.

The app gets an **App ID**; under App Admin > SteamPipe > Depots, add a
**depot** (Windows, 64-bit, all languages). Put both ids in
[steam.json](steam.json).

## 2. Settings in App Admin (you)

**Installation > General: launch option**

| Field | Value |
|---|---|
| Executable | `engine\bin\luanti.exe` |
| Arguments | `--go --world worlds\nethack --name player --password ""` |
| Working directory | `engine` |
| Operating system | Windows, 64-bit only |
| Launch type | Launch (default) |

**Steam Cloud (Auto-Cloud)**, so saves survive a reinstall or a new PC.
Without it, uninstalling deletes the save (it's inside the install folder):

| Root | Subdirectory | Pattern | Recursive |
|---|---|---|---|
| `GameInstall` | `engine/worlds/nethack` | `*` | yes |
| `GameInstall` | `engine` | `minetest.conf` | no |

Byte quota: 200 MB, number of files: 2000.

**Depot: no redistributables needed** (every DLL ships with the game).

## 3. The build (me, then you upload)

```bash
python -I tools/make_steam.py --desc "v0.7.0"
```

This makes `dist/steam/content` (the game as a Steam install holds it) and
`dist/steam/scripts` (the SteamPipe scripts, with the ids from steam.json).
It differs from the zip release:
- no shortcut maker and no Play launcher (Steam starts the game);
- the game's default settings are in `engine\nhv_defaults.conf`, not
  `minetest.conf`: that file is the player's own settings, and Steam would
  put a shipped one back on every "Verify integrity of game files". (This
  needs the engine built after 2026-10-21; the script checks.)

Upload it with SteamCMD (https://developer.valvesoftware.com/wiki/SteamCMD;
it asks for your Steam Guard code the first time):

```bash
steamcmd +login YOUR_STEAM_LOGIN +run_app_build "C:\Users\mreve\Documents\NetHackVoxel\dist\steam\scripts\app_build.vdf" +quit
```

Then in Steamworks > SteamPipe > Builds, set the new build live on the
`default` branch (or a `beta` branch first, to try it through Steam).

## 4. Store page (you paste; text in STORE_PAGE.md)

- Store page: descriptions, tags, system requirements, the **Early Access
  questions**, content survey, **AI disclosure** (answer it yourself: it asks
  whether players see content made with AI tools).
- Art (PNG/JPG, no review quotes or awards on capsules):

| Asset | Size |
|---|---|
| Header capsule | 920 x 430 |
| Small capsule | 462 x 174 |
| Main capsule | 1232 x 706 |
| Vertical capsule | 748 x 896 |
| Screenshots (at least 5) | 1920 x 1080 |
| Library capsule | 600 x 900 |
| Library hero | 3840 x 1240 |
| Library logo (transparent) | 1280 x 720 |
| Community icon | 184 x 184 |
| Trailer (strongly recommended) | 1080p mp4 |

- Submit the store page for review (a few business days), then mark it
  **Coming Soon**: it must be public for at least **2 weeks** before release.
- Submit the build for review too, then release.

## 5. Each update after that

1. `python -I tools/make_steam.py --desc "vX.Y.Z"`
2. the steamcmd line above;
3. set the build live in Steamworks;
4. post the CHANGELOG section as a Steam news/update post (the itch devlog
   text works too).
