# 042.014 — One snapshot version and a narrower build ID

## Context

A code audit on 2026-11-21 found three version checks on the snapshot: `schemaVersion`
(2), a hand-bumped `rendererVersion` (5), and the automatic build ID from
[010](010-saver-build-id.md). Since 010, every change to the saver's code gives a new
build ID, so `rendererVersion` no longer added anything to the reinstall notice. The
compatibility paths for schema 1 readers and a missing `rendererVersion` only served
local development installs: the screen saver has not shipped. Samuel approved removing
them.

The audit also found that the build ID hashed all of `ScreenSaverKit/Sources/`. The
Screen Saver Demo (`ScreenSaverDemo`, from `fe1e33bf`) lives there too, so editing the
demo asked for a saver reinstall.

## Change

| Choice | Decision and rejected alternative |
| --- | --- |
| Versions | `rendererVersion` is gone. The manifest carries `schemaVersion` and `saverBuild`. Readers and the writer accept only the current schema version; a newer one gives `.requiresUpdate`, an older one reads as no snapshot until AniShelf writes it again. Rejected: keeping a range of accepted versions, which only matters once two shipped formats coexist. |
| Bump | `schemaVersion` is 3. Every saver installed before this change checks `schemaVersion > current`, so it shows the reinstall notice instead of drawing a snapshot without `rendererVersion`. |
| When to bump | Only for an incompatible change to the snapshot format. Changes to how the saver draws need no bump: the build ID catches them. |
| Build ID scope | The `Stamp Screen Saver Build` phase hashes `ScreenSaver/`, `ScreenSaverKit/Sources/ScreenSaverKit/` and `ScreenSaverKit/Package.swift`. The demo target is left out. Draft layouts under `Sources/ScreenSaverKit/Drafts/` still count, because they compile into the saver. |

010's statement that `rendererVersion` stays for format changes is superseded by this
record.

## Refs

- `ScreenSaverKit/Sources/ScreenSaverKit/ScreenSaverManifest.swift`, `ScreenSaverSnapshotReader.swift`
- `MyAnimeList/Sources/Mac/ScreenSaver/ScreenSaverSnapshotWriter.swift`
- `MyAnimeList.xcodeproj/project.pbxproj` (`Stamp Screen Saver Build` phase)
- Tests: `ScreenSaverKitTests.manifestRoundTrip`, `ScreenSaverKitTests.readerFallbacks`
