# 042.007 — Uninstall, System Settings thumbnail, and more slide details

## Context

Samuel's review on 2026-11-20, after [006](006-preview-rows-and-details.md):

- "Turn Off Screen Saver" and its text ("AniShelf stops updating the screen saver and
  deletes its saved posters…") were unclear. Samuel gave the copy: "After
  installation, AniShelf updates the screen saver automatically when you change the
  options below. Uninstalling makes the AniShelf option disappear in the screen saver
  settings." and the button **Uninstall Screen Saver**.
- AniShelf appeared in System Settings with the generic swirl thumbnail, and its live
  preview did not render ("stopped working entirely").
- Slides need Overview (Poster Focus only), TMDb score and watch status (both slide
  layouts), and users must not be able to turn the title off.

## Diagnosis: the saver that "stopped working"

Not a code fault. Claude had deleted the per-user copy in `~/Library/Screen Savers`
during cleanup; Samuel then reinstalled for all users, which puts the bundle in
`/Library/Screen Savers`. System Settings still had AniShelf selected at the old
per-user path (`WallpaperAgent: looking for "/Users/.../AniShelf.saver"`), and the
running `legacyScreenSaver` host had the deleted bundle's class loaded, so the new copy
never loaded. Fix on the machine: quit System Settings, reopen, and choose AniShelf
again. (Tip for log reading: in zsh, `log` is a builtin; use `/usr/bin/log`.)

## Change

| Choice | Decision and rejected alternative |
| --- | --- |
| Setup copy | The Setup section footer reads "After installation, AniShelf updates the screen saver automatically when you change the options below." The turn-off row is gone from Setup. |
| Uninstall | A last section: "Uninstalling makes the AniShelf option disappear in the screen saver settings." with **Uninstall Screen Saver…**. It stops updates and deletes the artwork folder, then shows the steps to remove the saver in System Settings (Screen Saver…, Control-click AniShelf, Delete "AniShelf") with an **Open Wallpaper Settings** button. The sandboxed app cannot delete the installed bundle in either location, and macOS offers its own Delete command for third-party savers. *Corrected 2026-11-20:* the first version revealed `AniShelf.saver` in Finder with `activateFileViewerSelecting`, which does nothing from the sandbox for paths the app cannot access; Samuel found it never opened Finder and pointed to the system Delete command. An Open-panel route (user picks the bundle, the app trashes it) was started and dropped as unnecessary. |
| Thumbnail | `ScreenSaver/thumbnail.png` (215×140) and `thumbnail@2x.png` (430×280): an abstract Cover Wall of gradient poster tiles, drawn by a one-off CoreGraphics script. Apple's savers ship 90×58 / 180×116 at the same aspect; the larger size stays sharp in the System Settings grid. A static image cannot show the user's posters: the bundle is signed. |
| Title always on | `Detail.title` removed. Poster Focus always draws the title; Backdrop always draws the logo, or the title when there is none. |
| New details | `score` ("TMDb 8.4", from `AnimeEntryDetail.voteAverage`, hidden when 0), `watchStatus` (the app's localized watch status), `overview` (`detail.overview`, else `displayOverview`). Overview is offered for Poster Focus only (`Detail.available(for:)`); it draws at a fixed size, capped at 5 lines. Score and watch status join a line under genres in Poster Focus and the single meta line in Backdrop. Series status is now labelled **Airing Status** to tell it apart from Watch Status. All three default off. |
| Defaults | Poster Focus: season, year, genres. Backdrop: year. |
| Versions | `rendererVersion` 4; saver build number 4. |

Watch status was earlier kept off the saver for privacy ([backlog.md](backlog.md));
Samuel asked for it, so it is an opt-in toggle, off by default.

## Refs

- `MyAnimeList/Sources/Mac/ScreenSaver/MacScreenSaverSettingsPage.swift` (Setup footer, `ScreenSaverUninstallSection`, Details toggles)
- `ScreenSaverKit/Sources/ScreenSaverKit/ScreenSaverManifest.swift` (`Detail`, `Entry.score`, `watchStatus`, `overview`), `ScreenSaverLayouts.swift`, `ScreenSaverSceneLoader.swift`
- `MyAnimeList/Sources/Mac/ScreenSaver/ScreenSaverSnapshotBuilder.swift`
- `ScreenSaver/thumbnail.png`, `ScreenSaver/thumbnail@2x.png`
- Validation: `swift test --package-path ScreenSaverKit` (10 passed); `make test-app-mac APP_TEST_ONLY='MyAnimeListTests/ScreenSaverPublisherTests MyAnimeListTests/LibraryProfileSettingsLayoutPolicyTests'` (succeeded); `make build-mac` (thumbnails present in the built saver's Resources) and `make build` (passed). Not run: the Uninstall flow from the sandboxed app (Finder reveal) and the thumbnail in System Settings; Samuel checks both.
