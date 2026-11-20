# AniShelfCovers

A macOS screensaver that turns an AniShelf library into a moving poster wall, built as a standalone
`.saver` bundle. It reads the AniShelf Core Data store **read-only** and never writes back.

This folder is self-contained: it is plain Objective-C plus two small Python/shell tools, has no
Xcode project and no build integration with the app target, so it can be adopted (or ignored)
without touching the Swift codebase.

## What it looks like

Five layouts, all driven by the same library:

| Mode | Description |
| --- | --- |
| **Cover wall** | A full-bleed grid of posters that drifts slowly. Rows always fill the screen height exactly, so no card is ever half-cut. |
| **Deck** | Posters shuffle in a fanned stack, one at a time, with the title underneath. |
| **Hero still** | A full-screen TMDb backdrop with the work's logo, tagline, country, year and TMDb score. Alignment can be left, centred, or randomised per item. |
| **Poster showcase** | Two variants: *fusion* puts the poster at full screen height on one side with its inner edge feathered into a blurred copy of itself; *classic* shows a poster card on one side with the blurred colour wash behind and the text column on the other. |

Shared options: metadata language (follow AniShelf / 中文 / English / 日本語), transition interval,
transition style (cross-fade or slide) and library scope (all / favourites / watched).

## How it works

1. `tools/export_library.py` reads `mal.store` from the AniShelf container with SQLite (read-only),
   then downloads posters, backdrops and logos from TMDb at the sizes the screensaver needs.
2. Everything is written into `AniShelfCovers.saver/Contents/Resources`, i.e. one copy inside the
   screensaver bundle. Nothing is duplicated elsewhere.
3. At runtime the saver reads only that folder — no network access on wake, no sandbox escapes.

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

Whenever the library changes, re-run:

```bash
./refresh.sh    # re-exports into the installed bundle and re-signs it
```

It is incremental, so only new entries are downloaded.

## Options panel

The options sheet covers language, transition interval and style, hero-still alignment, drift
style, columns per screen and library scope. If System Settings ever fails to show the sheet, the
same settings can be written directly:

```bash
./set-pref.sh mode 4        # 0 wall, 1 deck, 2 hero still, 3 poster focus, 4 cover fusion
./set-pref.sh interval 12   # seconds
./set-pref.sh effect 1      # 0 cross-fade, 1 slide
./set-pref.sh align 1       # hero still: 0 left, 1 centred, 2 random
./set-pref.sh cols 8        # 0 = automatic
./set-pref.sh lang 2        # 0 follow AniShelf, 1 Chinese, 2 English, 3 Japanese
```

## Metadata and languages

AniShelf stores localised names and synopses (`ZNAMETRANSLATIONS` / `ZOVERVIEWTRANSLATIONS`,
26 languages). The export packs Chinese, English and Japanese into `library.json`, and the
screensaver picks one at render time. Country names are localised too.

Taglines (`ZSUBTITLE`) exist in a single language only — the one the app fetched — so the tagline
is hidden when the selected language differs, rather than showing a mismatched line.

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
