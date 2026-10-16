# 020.005 — Slice 3: feature parity

## Context

Third slice of [002-implementation-decisions.md](002-implementation-decisions.md):
make every existing feature work on the Mac and validate it. The lifecycle work
that landed early in [004](004-slice-2-mac-shell.md) is validated here. Roles
are the same as in slice 2.

Computer-use rounds `s3a`–`s3c` changed the library only through one
throwaway TMDb entry, which was added, edited, and deleted each round; the
library ended at 137 entries every time. The maintainer had allowed iCloud
Sync to run against the CloudKit development environment. The Debug build's
signed entitlements were checked first (`aps-environment = development`, no
production container environment). Sync was then turned on, exercised, and
turned off again.

## Change

| Area | Mac behavior and reason |
| --- | --- |
| Files out of the app | A single file passed to `ShareSheetPresenter` (a backup, library export, or recovery export) opens an `NSSavePanel` sheet instead of the sharing picker. The Mac share menu has no "save to file" action, and Mac users expect Save for these. Other content still uses `NSSharingServicePicker`. |
| Sharing card | The sheet bar shows Close, Share… (`ShareLink`), and Save… (save panel on the sheet's key window). macOS sheet bars only render the cancellation, confirmation, and destructive slots, and one item per slot; a `ToolbarItemGroup` dropped the second button. Share therefore uses the destructive slot for its leading position. The iOS tap gesture layered on `ShareLink` was not carried over. |
| Save Poster | Downloads the poster and offers a save panel (`ShareSheetPresenter.saveDownload`). A `ShareLink` to a remote image URL could not save on the Mac. |
| Sheet buttons | New `ToolbarItemPlacement.sheetLeading`/`.sheetTrailing` map to the cancel and confirm slots on the Mac and to the top-bar placements on iOS. Batch Add (Back/Edit), About and Support (Done), and the search page's Batch Add use them; their buttons were invisible on the Mac before. |
| Add and Find | After a jump from Add or Find, the Mac selects the entry and inspects it (`performJump` → `applyMacSelection`). Before, it was only scrolled to and pulsed. |
| SVG rasters | SwiftDraw's macOS `rasterize` returns a lazily drawn `NSImage` whose point size equals the pixel size. On the Mac, `SVGImageProcessor` now draws into an `NSBitmapImageRep` with the requested point size and pixels per point. This bug was found by running the existing tests natively. |
| Help menu | Replaced the unavailable Help Book item with links to the website and the privacy policy. |
| Tests on macOS | `MyAnimeListTests` now also builds for macOS 26. The sharing tests build their source image from a bitmap context on both platforms. The SVG tests compare pixels per point on the Mac. The iOS bridge tests are iOS-only, because the Mac delegate is a different type. |

## Validation

- `make test-app-mac`: the whole `MyAnimeListTests` suite (except the
  live-fetch suite skipped by the Makefile) passed natively on macOS after the
  SVG fix. Before the fix, two SVG tests failed on the Mac.
- `make test-app-sim APP_TEST_ONLY='MyAnimeListTests/TMDbImageAndTranslationTests MyAnimeListTests/AnimeSharingTests MyAnimeListTests/UserEntryInfoAndLibraryStatsTests MyAnimeListTests/LibrarySyncNotificationBridgeTests'`
  passed on the booted iPhone 18 Pro simulator.
- `make build` and `make build-mac` pass.
- Rounds `s3a`–`s3c` (screenshots and reports were local and not retained)
  confirmed these flows:
  - Add (single, and Batch Add navigation).
  - Inspector editing: status, score, favorite, dates, episode stepper, notes
    with Save/Discard, and section expansion.
  - Poster replacement, Copy and Paste Info, the share menu, and saving a card
    PNG.
  - Backup and CSV export to save panels, and both simulated startup screens
    (`-simulate-startup-recovery`, `-simulate-newer-library-store`) with their
    export save panels.
  - Support product prices loading (no purchase), About, and the Help menu.
- iCloud Sync on the native build reached Synced with no conflict prompt. A
  score edit synced automatically in about 4 s, and the log showed "Registered
  for remote notifications with APNs." Turning sync on pulled one remote change
  from the development environment (an existing entry moved from Watched to
  Watching), which is expected sync behavior. Sync was turned off afterwards.
- Not exercised: an airing-reminder notification firing and being clicked (no
  airing entry was suitable), the 6-hour background refresh, the quit-time
  flush timeout, and sleep/wake. The code for these was reviewed in slice 2.

## Open issues

- Once, a quick Done → reopen of the inspector left the inspector's Done button
  in the toolbar with no inspector visible. Toggling the inspector recovered it;
  it was not reproduced.
- The English sharing card can repeat a title when the original and localized
  titles match. This is shared with iOS and was left unchanged.

## Refs

- `MyAnimeList/Sources/Utils/ShareSheetPresenter.swift`
- `MyAnimeList/Sources/Views/Sharing/AnimeSharingSheet.swift`
- `MyAnimeList/Sources/Views/Library/LibraryEntryInteractionState.swift`
- `MyAnimeList/Sources/Utils/PlatformViewModifiers.swift`
- `MyAnimeList/Sources/Views/Library/LibraryView+Search.swift`
- `MyAnimeList/Sources/Extensions/SVGImageProcessor.swift`
- `MyAnimeList/Sources/Mac/MacLibraryCommands.swift`
- `MyAnimeList.xcodeproj/project.pbxproj` (test target platforms)
- `MyAnimeList/Tests/MyAnimeListTests/AnimeSharingTests.swift`
- `TMDbImageAndTranslationTests+SVG.swift`
- `LibrarySyncNotificationBridgeTests.swift`
