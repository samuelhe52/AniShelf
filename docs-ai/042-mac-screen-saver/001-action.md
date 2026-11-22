# 042 — Mac screen saver: Action record

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-11-20 | Plan written after the PR #28 review; decisions answered on the HTML plan | `bffa7e60` |
| 2026-11-20 | Slice 1: `AniShelf.saver`, `ScreenSaverKit` renderer, host-access gate passed ([002](002-slice-1-saver-and-host-gate.md)) | `bc6c8b14` |
| 2026-11-20 | Slice 2: snapshot builder, image export, publisher ([003](003-slice-2-snapshot-publisher.md)) | `4f0ae653` |
| 2026-11-20 | Slice 3: Settings pane, live preview, install ([004](004-slice-3-settings-pane.md)) | `f7591318` |
| 2026-11-20 | Export speed, in-memory preview, setup steps instead of a toggle, plain status wording ([005](005-export-speed-and-pane-revision.md)) | `f49405c1`, `5f0de053`, `c6e134f6` |
| 2026-11-20 | True-scale preview, Cover Wall rows, per-layout details, slide redesign, Hero Still renamed Backdrop ([006](006-preview-rows-and-details.md)) | `4a6c5f24` |
| 2026-11-20 | Uninstall, System Settings thumbnail, title always on, overview / TMDb score / watch status ([007](007-uninstall-thumbnail-and-more-details.md)) | `686a35d9` |
| 2026-11-20 | Slide typography; text drawn with CoreText ([008](008-slide-typography.md)) | `f4d45b4a`, `16ffbe07` |
| 2026-11-20 | Library category as a scope ([009](009-category-scope.md)) | `b16e5046` |
| 2026-11-20 | Saver build ID and reinstall notice ([010](010-saver-build-id.md)) | `94fdf612` |
| 2026-11-20 | Uninstall points to System Settings' Delete command ([007](007-uninstall-thumbnail-and-more-details.md), corrected) | `756ecb11` |
| 2026-11-20 | Scope declared complete by Samuel | — |

Implementation: Codex (6.2 sol high) built slices 1–3, the speed revision, and the
true-scale preview and rows; Claude Code wrote the docs and commits throughout and
built everything from the details model onward after Samuel asked it to take over.

## Outcome and current state (as of 2026-11-20)

- **Saver.** `AniShelf.saver` (bundle ID `com.samuelhe.MyAnimeList.ScreenSaver`,
  arm64 + x86_64, macOS 26) is embedded in the Mac app at
  `Contents/Library/Screen Savers`. It reads `~/Pictures/AniShelf Screen Saver` offline,
  plays Cover Wall (rows 2–8, [distance-weighted poster draws](011-cover-wall-shuffle-bag.md)),
  Poster Focus, or Backdrop, ends sessions on
  `stopAnimation`, `willstop`, and window detachment, and ships a thumbnail for the
  System Settings grid. A build-phase hash of its sources (`AniShelfScreenSaverBuild`)
  is compared with the snapshot's `saverBuild`; a mismatch shows "AniShelf has a newer
  screen saver. Install it from AniShelf Settings › Screen Saver."
- **Snapshot.** Built from `LibraryStore.library` for Favorites, Watched, All Library
  Entries, or one library category; never widened. Each entry carries title, season,
  year, up to three genres (TMDb Animation dropped), airing status, TMDb score, watch
  status, and overview, with posters at w780 and, for Backdrop, backdrop and logo.
  Content-addressed images; atomic manifest replacement; pruning. Exports run six at a
  time and commit partial manifests; look-only option changes apply without
  re-export.
- **Pane** (Settings › Screen Saver, Mac only). The live preview stays fixed with
  Show, Entry Type, Layout, and Mode. Below it, the form scrolls through Customize,
  layout-specific Details, Setup (install, open Wallpaper Settings, artwork status),
  and Uninstall (delete exported artwork and explain the System Settings removal step).
- **Typography.** Text is laid out, truncated, and drawn by CoreText. Poster Focus
  title 6.0%–3.0% of the shorter edge (fits one line first), season 2.4%, info line 2%,
  overview 2.2% capped at four lines; Backdrop info line 1.9% at 55% white.

Key files:

- `ScreenSaverKit/Sources/ScreenSaverKit/ScreenSaverManifest.swift`, `ScreenSaverSnapshotReader.swift`, `ScreenSaverRenderer.swift`, `ScreenSaverSceneLoader.swift`, `ScreenSaverLayouts.swift`, `CoverWall.swift`
- `ScreenSaver/AniShelfScreenSaverView.swift`, `ScreenSaver/thumbnail@2x.png`
- `MyAnimeList/Sources/Mac/ScreenSaver/ScreenSaverSettings.swift`, `ScreenSaverSnapshotBuilder.swift`, `ScreenSaverImageExporter.swift`, `ScreenSaverPublisher.swift`, `ScreenSaverSnapshotWriter.swift`, `MacScreenSaverSettingsPage.swift`, `ScreenSaverPreviewView.swift`
- Tests: `ScreenSaverKit/Tests/ScreenSaverKitTests/ScreenSaverKitTests.swift`, `MyAnimeList/Tests/MyAnimeListTests/ScreenSaverPublisherTests.swift`

## Deviations from plan

- Publication wording, the enable toggle, Refresh Now, and Show in Finder were
  replaced by setup steps, a plain status line, and Uninstall ([005](005-export-speed-and-pane-revision.md)).
- The live preview renders in memory from the app's image cache rather than from the
  disk snapshot, at the screen's real scale.
- Cover Wall rows are a user setting (2–8, default 4) instead of derived from screen
  height.
- Show Titles became per-layout detail toggles with the title always on; overview,
  TMDb score, and watch status were added (the plan had excluded the last two).
- Hero Still is named Backdrop in the UI and in code.
- Category scope, the build ID, uninstall, and the thumbnail were added beyond the
  plan.
- The saver checks the build ID as well as the schema version. (It also read a
  `rendererVersion` until [014](014-single-snapshot-version.md) removed it.)

## Validation

- `swift test --package-path ScreenSaverKit`: 11 tests passed (last run after `16ffbe07`).
- `make test-app-mac APP_TEST_ONLY='MyAnimeListTests/ScreenSaverPublisherTests MyAnimeListTests/LibraryProfileSettingsLayoutPolicyTests'`: succeeded (last run after `b16e5046`; `ScreenSaverPublisherTests` alone after `94fdf612`).
- `make build-mac` and `make build`: passed at each commit from `f49405c1` on.
- Host-access gate (slice 1): the installed saver read `~/Pictures/AniShelf Screen
  Saver` with no privacy prompt in the System Settings preview, direct activation, and
  idle activation.
- In-process renders of Poster Focus and Backdrop (16:10, ultrawide, portrait;
  Japanese and English) reviewed by Claude; Samuel reviewed renders and the running
  saver on his Mac.

## Open questions

- Lock-screen activation and behavior after a restart were never reported back.
- App Review guideline 2.4.5 for an embedded `.saver` is untested; the fallback is a
  separate notarized download ([backlog.md](backlog.md)).
- Export timings with real TMDb downloads were not measured.
- Not seen on screen: the reinstall notice in a real activation, the Uninstall dialog,
  the "Deleted Category" picker row, and the Japanese and Chinese wording of System
  Settings' Delete menu item that the dialog quotes.
- The marketing site (`../anishelf-site`) does not yet describe the Mac Screen Saver.
