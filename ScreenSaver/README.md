# AniShelfCovers

A macOS screensaver that turns an AniShelf library into a moving poster wall, built as a standalone
`.saver` bundle. It reads the AniShelf Core Data store **read-only** and never writes back.

This folder is self-contained: it is plain Objective-C plus a few small Python/shell tools, has no
Xcode project and no build integration with the app target, so it can be adopted (or ignored)
without touching the Swift codebase.

## What it looks like

Four modes, all driven by the same library:

| Mode | Description |
| --- | --- |
| **Cover wall** | A full-bleed grid of posters that drifts slowly. Rows always fill the screen height exactly, so no card is ever half-cut. |
| **Deck** | Posters shuffle in a fanned stack, one at a time, with the title underneath. |
| **Hero still** | A full-screen TMDb backdrop with the work's logo (or its title when no logo exists), a tagline, a metadata line and a genre line. Text can be left-aligned, centred, or randomised per item. |
| **Poster showcase** | Two variants. *Fusion*: the poster runs the full screen height on one side, and its inner edge resolves through a medium blur into a heavily blurred copy of itself. *Classic*: a poster card on the side, a blurred colour wash behind, and the text column opposite. |

### What the hero still shows

```
ダンジョン飯                        ← TMDb logo, or the title when there is none
「食うか、食われるか」              ← tagline (hidden if the language does not match)
Japan · 2024 · Airing · Watching · TMDB 8.4
Comedy / Action & Adventure         ← genres on their own line, "Animation" excluded
A dungeon, a party of adventurers…  ← synopsis, auto-fitted to the available height
```

Series status (airing / completed / in production), watch status (watching / watched / planned /
dropped, opt-in) and genres all come from the same export. Genres and metadata can be turned off
independently in the options sheet.

### Transitions (hero still and poster showcase)

Six styles, applied to the whole scene so the logo, tagline and text move with the artwork at the
same speed: **none**, **cross-fade**, **horizontal cut-in**, **horizontal push**, **vertical cut-in**
and **vertical push**. Cut-in slides the incoming still over the outgoing one; push moves both. The
vertical variants travel upwards, the horizontal ones right-to-left. During the dwell the still
zooms very slowly (1.0 → 1.045), and the zoom is scheduled to start once the transition finishes.

## How it works

1. `tools/export_library.py` reads `mal.store` from the AniShelf container with SQLite (read-only),
   then downloads posters, backdrops and logos from TMDb at the sizes the screensaver needs.
2. Everything is written into `AniShelfCovers.saver/Contents/Resources`, i.e. one copy inside the
   screensaver bundle. Nothing is duplicated elsewhere.
3. At runtime the saver reads only that folder — no network access on wake, no sandbox escapes,
   no dependency on AniShelf being open.

Because AniShelf does not keep an on-disk image cache of its own, the images have to be fetched
once; the export is incremental and skips files that already exist.

## Requirements

- macOS 12 or later
- Xcode Command Line Tools (`xcode-select --install`)
- AniShelf installed with a non-empty library
- A network connection the first time you export

## Build and install

```bash
cd ScreenSaver
./build.sh      # compiles Sources/AniShelfCoversView.m into dist/AniShelfCovers.saver
./install.sh    # copies it to ~/Library/Screen Savers and exports the library if needed
```

Then open **System Settings → Wallpaper → Screen Saver → Other → AniShelf Covers**.
The bundle is ad-hoc signed, which is enough for a locally built screensaver.

`BUNDLE_ID` and `DISPLAY_NAME` are overridable if this ever ships as a first-party feature:

```bash
BUNDLE_ID=com.example.AniShelfCovers ./build.sh
```

## Keeping it in sync

The screensaver holds a snapshot, so it has to be refreshed when the library changes.

```bash
./refresh.sh    # re-exports into the installed bundle and re-signs it
```

It is incremental, so only new entries are downloaded.

There is also an optional watcher:

```bash
./install.sh --auto-sync    # LaunchAgent watching mal.store, debounced by 4s
./install.sh                # removes it again
```

One caveat, and the reason this is off by default: macOS protects
`~/Library/Containers/<other app>` behind TCC, so a background agent cannot read the store unless
`/bin/bash` is granted **Full Disk Access**. Without that grant the agent logs the failure to
`.sync-status` inside the bundle instead of retrying silently. The clean alternative is for the app
itself to write the export when its library changes — it is the only process that can read its own
store without a permission prompt.

## Options panel

The sheet only shows the rows that belong to the selected mode:

| Mode | Rows |
| --- | --- |
| Cover wall | drift style, columns per screen |
| Deck | show title and score |
| Hero still | dwell time, transition style, text alignment |
| Poster showcase | cover variant, dwell time, transition style |

"Show more settings" reveals the rest: language, library scope (all / favourites / watched), media
kind (TV / movies / all), what to display (logo or title, tagline, metadata + genres + synopsis,
watch status).

If System Settings ever fails to show the sheet, the same settings can be written directly:

```bash
./set-pref.sh mode 2        # 0 wall, 1 deck, 2 hero still, 3 poster showcase
./set-pref.sh cover 0       # 0 fusion, 1 classic
./set-pref.sh interval 12   # seconds
./set-pref.sh effect 3      # 0 none, 1 fade, 2 h cut-in, 3 h push, 4 v cut-in, 5 v push
./set-pref.sh align 1       # hero still: 0 left, 1 centred, 2 random
./set-pref.sh cols 8        # 0 = automatic
./set-pref.sh lang 2        # 0 follow AniShelf, 1 Chinese, 2 English, 3 Japanese
```

## Metadata and languages

AniShelf stores localised names and synopses (`ZNAMETRANSLATIONS` / `ZOVERVIEWTRANSLATIONS`,
26 languages). The export packs Chinese, English and Japanese into `library.json`, and the
screensaver picks one at render time. Country names, genres and statuses are localised too.

Taglines (`ZSUBTITLE`) exist in a single language only — the one the app fetched — so the tagline
is hidden when the selected language differs, rather than showing a mismatched line.

Season entries inherit the genres of their parent series when they carry none of their own.

## Notes

- The saver only ever opens the store read-only; no schema is modified and no files in the app
  container are written.
- Disk usage is roughly the size of the downloaded artwork, typically 30–60 MB for a few hundred
  entries (backdrops dominate). Delete the bundle to reclaim all of it.
- TMDb's Japanese title coverage is patchy (43 of 158 entries in our sample); missing translations
  fall back to Chinese.
- Poster, backdrop and logo artwork belongs to TMDb and the respective rights holders; it is
  downloaded locally and never redistributed.

## License

Apache License 2.0, matching the rest of the project.
