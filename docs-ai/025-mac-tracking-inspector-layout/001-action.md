# 025 — Mac tracking inspector layout: Action record

## Timeline
| Date | Change | Ref |
| --- | --- | --- |
| 2026-10-17 | First version (label grid, date timeline row) built and reviewed in the running app; judged messy. Its uncommitted files were later removed from the working tree outside this session. | — |
| 2026-10-17 | Rebuilt from HEAD as stat-card-style rows. | `ab61824` |
| 2026-10-17 | Review fixes: Track Dates row removed (context menu + hidden-state row), rewatch badge inline, notes editor 120 → 200 pt, calendar focus ring disabled. | `ab61824` |
| 2026-10-17 | Primary-color row labels; rewatch badge/popover replaced by a Times Rewatched row and a Rewatching context-menu toggle. | `ab61824` |
| 2026-10-17 | Rewatching checkmark item in the menu bar's Anime menu. | `c4d2e28` |
| 2026-10-17 | Fix: the Mac list row's status badge kept the old rewatch count. `LibraryWatchStatusBadge.title` is now a resolved string (`Text(verbatim:)`) instead of an interpolated `LocalizedStringResource`; the unused `%@ ×%lld` catalog key (identical in every language) is removed. Regression test `rewatchCountEditRefreshesTheCachedSnapshot` confirms the store cache already refreshed. | `86f035b` |

## Outcome and current state (as of 2026-10-17)
See the plan's Design section; it describes the code as built.

Key files:
- `MyAnimeList/Sources/Views/Library/EntryDetail/EntryDetailMacTrackingRows.swift`
- `MyAnimeList/Sources/Views/Library/EntryDetail/EntryDetailTrackingComponents.swift`
- `MyAnimeList/Sources/Views/Library/AnimeEntryTrackingControls.swift` (Mac stepper body removed; picker no longer centered)
- `MyAnimeList/Sources/Views/Library/EntryDetail/EntryDetailSupport.swift` (`today`, `dates`)
- `MyAnimeList/Sources/Mac/MacLibraryCommands.swift` (Rewatching menu item)
- `MyAnimeList/Sources/Views/Library/LibraryEntryVisuals.swift` (status badge title)
- `MyAnimeList/Tests/MyAnimeListTests/LibraryEntryInteractionStateTests.swift`
- `MyAnimeList/Resources/Localizable.xcstrings` (`Today`, `Dates`: ja, zh-Hans)

## Deviations from plan
None known.

## Validation
- `make build-mac`: Build completed.
- `make build` (iOS): Build completed.
- `make test-app-mac APP_TEST_ONLY='MyAnimeListTests/LibraryEntryInteractionStateTests'`: passed, including the new rewatch-count test.
- `make run-mac`: launched; maintainer visual pass on the first row version led to the review fixes. After the fixes: `make build` and `make run-mac` succeeded; not yet re-reviewed.

## Open questions
- 2026-10-18 follow-up: the Mac watch-status picker now uses an explicitly sized native control; see [002-status-picker-layout.md](002-status-picker-layout.md) for failed alternatives and current runtime/test evidence.
- Badge root cause is inferred: the snapshot updated (test passes) and only argument-only changes of the interpolated resource failed to redraw on macOS. Not confirmed against SwiftUI internals.
- Unverified visually after the review fixes: the hidden-dates row and the focus-ring fix.
