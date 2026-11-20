# 042.010 — Saver build ID and reinstall notice

## Context

On 2026-11-20 Samuel reported the slide typography bug from `3ac684f1` still showing
on the newest build. Cause: the installed saver (`~/Library/Screen Savers`, installed
21:02) predated the fix; building AniShelf updates only the copy embedded in the app.
The installed saver showed its update notice only when `rendererVersion` was bumped
by hand, and the typography change did not touch the snapshot format, so the old
saver kept drawing with old code and said nothing. Shipped updates would hit the same
gap. Samuel: "we definitely need a build number and an reinstall notice."

## Change

- **Build ID.** A `Stamp Screen Saver Build` run-script phase in the
  `AniShelfScreenSaver` target hashes every file under `ScreenSaver/`,
  `ScreenSaverKit/Sources/`, and `ScreenSaverKit/Package.swift` (sorted paths and
  contents, SHA-256, first 16 hex digits) and writes it to the saver's Info.plist as
  `AniShelfScreenSaverBuild` before signing. Any change to the saver's code gives a new
  ID; no manual bump. The phase declares the processed Info.plist as input, runs on
  every build, and the target sets `ENABLE_USER_SCRIPT_SANDBOXING = NO` so the script
  can read the sources.
- **Snapshot.** `ScreenSaverPublisher.embeddedSaverBuild` reads the ID from the saver
  embedded in the app; each manifest carries it as `saverBuild`. The writer treats a
  different `saverBuild` as a change, so the first publication after an AniShelf update
  restamps an otherwise unchanged snapshot.
- **Check.** The saver passes its own ID to `ScreenSaverRenderer.start(in:build:)`;
  `ScreenSaverSnapshotReader` returns `.requiresUpdate` when the snapshot's ID differs.
  Snapshots without an ID (older AniShelf) and readers without one (the in-app preview)
  skip the check. The notice now reads "AniShelf has a newer screen saver. Install it
  from AniShelf Settings › Screen Saver."
- `rendererVersion` stays for snapshot-format changes; manual saver build-number bumps
  are no longer needed for code changes.

Limits: the sandboxed app cannot read the installed saver, so the notice appears only
where the saver runs (System Settings preview and activation), not in the AniShelf
pane. Any source change, including comments, asks for a reinstall.

## Refs

- `MyAnimeList.xcodeproj/project.pbxproj` (`Stamp Screen Saver Build` phase)
- `ScreenSaverKit/Sources/ScreenSaverKit/ScreenSaverManifest.swift` (`buildInfoKey`, `saverBuild`), `ScreenSaverSnapshotReader.swift`, `ScreenSaverSceneLoader.swift`, `ScreenSaverRenderer.swift`
- `ScreenSaver/AniShelfScreenSaverView.swift`; `MyAnimeList/Sources/Mac/ScreenSaver/ScreenSaverPublisher.swift`, `ScreenSaverSnapshotWriter.swift`
- Tests: `ScreenSaverKitTests.aSaverBuiltFromOtherCodeAsksToBeReinstalled`, `ScreenSaverPublisherTests.anotherSaverBuildRestampsAnUnchangedSnapshot`
- Validation: `swift test --package-path ScreenSaverKit` (11 passed); `make test-app-mac APP_TEST_ONLY='MyAnimeListTests/ScreenSaverPublisherTests'` (succeeded); `make build-mac` (built saver's Info.plist has `AniShelfScreenSaverBuild = c6eb92c029295d47`, equal to the hash recomputed by hand; `codesign -v` passes); `make build` (passed). Not run: the notice in a real activation.
