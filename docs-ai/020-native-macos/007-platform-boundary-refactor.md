# 020.007 — Platform boundary refactor

## Context

After the four slices landed, the maintainer asked how the macOS and iOS UI
coexist and whether the boundary could be cleaner. Claude proposed five
refactorings. A Codex session (gpt-6.1-sol, high effort) audited them read-only
against the source, and the two agreed on a revised plan on 2026-10-16 before
any code changed. The audit also found two defects that ranked above the
cleanups.

## Change

**Defects fixed**

- **Search had no presentation host during batch selection.** The search sheet
  was attached to `LibrarySearchButton`, which the Mac multi-select toolbar does
  not show, while ⌘N and ⌘F stay enabled during a batch. From source reading,
  those commands set `isSearching` with nothing to present it. Before this fix the
  defect had not been reproduced at runtime. The sheet now lives in a
  `librarySearchSheet(...)` modifier on `LibraryView`'s browser stack, which
  persists across toolbar changes on both platforms. The button only sets the
  flag. The modifier clears its "Entry Hidden" state when the sheet dismisses, so
  a stale alert cannot reappear on the next opening. The commands stay enabled
  during a batch. A jump from search already ends the batch through
  `applyMacSelection`.
- **Save Poster used the global key window.** With several windows open, its save
  panel could attach to the wrong one. `SavePosterButton` reads
  `\.windowSceneIdentifier`, and `ShareSheetPresenter.saveDownload(of:sceneIdentifier:)`
  resolves the window before the download starts. When the identifier names no
  window, nothing is presented. `AnimeSharingSheet` keeps `keyWindow` on purpose:
  that sheet is its own key window, and a panel on the parent would queue behind it.

**Boundary cleanups**

| Choice | Reason and rejected alternative |
| --- | --- |
| Split `LibraryView+Desktop.swift` into `Views/Library/LibraryView+Commands.swift` (compiles for both platforms) and `Mac/LibraryView+Mac.swift` (Mac only) | The old file mixed shared functions that contain platform forks with a Mac-only block. Folders are a convention only: the app is one synchronized multiplatform target, so Mac-only files still need `#if os(macOS)`. |
| `macLibrarySplitView(detail:)` in `LibraryView+Mac.swift` holds the split view, sidebar, column width rule, `focusedSceneValue`, window registration, inspector-width handling, and both Mac alerts. (Its selection and inspector parts were rebuilt in [021](../021-mac-selection-model/000-plan.md).) | Rejected: a `MacLibraryShell` type and an `@Observable MacLibraryState`. A few `@State` fields don't justify a second owner of state. `LibraryView` passes its own `libraryBrowserStack.modifier(entryInspector)` as `detail`, so the inspector stays inside the detail column (see [004](004-slice-2-mac-shell.md)). The Mac-only stored properties stay in `LibraryView`, because extensions cannot hold stored properties. |
| `WindowScenes.canReceiveRoute(_:)` and `View.onOtherWindowSceneClosed(than:perform:)` in `Views/Gadgets/WindowSceneIdentifierReader.swift` | They replace two platform forks in `LibraryView`. The predicate deliberately keeps different meanings per platform: on the Mac, a visible window; on iOS, a connected scene. It is the route-claiming check passed to `AiringReminderManager.claimPendingRoute`. A neutral name such as `isVisible` was rejected because it misdescribes the iOS check. The close callback runs in a new main-actor task. That gives teardown a chance to progress, but nothing guarantees teardown has finished. |
| `UserEntryInfo.hasPasteboardContent` in `Extensions/UserEntryInfo+Pasteboard.swift` | The availability check now sits beside copy and decode. It checks the pasteboard type without decoding the contents. |
| `MacSelectionClick` moved unchanged to `Mac/MacSelectionClick.swift` | It is an AppKit input adapter. Grid clicks must keep reading `.current` synchronously inside the click callback. Together with the Save Poster change, `LibraryEntryInteractionState.swift` no longer imports AppKit or UIKit. |

Kept as they were after the audit: the `LibraryToolbar` Mac/iOS fork, the
per-platform grid and inspector constants, `MacGalleryPager` scoped to its file,
and the iOS-only list selection dimming.

## Refs

- Files: `MyAnimeList/Sources/Views/Library/LibraryView.swift`,
  `MyAnimeList/Sources/Views/Library/LibraryView+Search.swift`,
  `MyAnimeList/Sources/Views/Library/LibraryView+Commands.swift`,
  `MyAnimeList/Sources/Views/Library/LibraryToolbar.swift`,
  `MyAnimeList/Sources/Views/Library/LibraryEntryInteractionState.swift`,
  `MyAnimeList/Sources/Mac/LibraryView+Mac.swift`,
  `MyAnimeList/Sources/Mac/MacSelectionClick.swift`,
  `MyAnimeList/Sources/Views/Gadgets/WindowSceneIdentifierReader.swift`,
  `MyAnimeList/Sources/Utils/ShareSheetPresenter.swift`,
  `MyAnimeList/Sources/Extensions/UserEntryInfo+Pasteboard.swift`.
- Validation on 2026-10-16: `make build` and `make build-mac` pass, and
  `make test-app-mac APP_TEST_ONLY='MyAnimeListTests/LibraryEntryInteractionStateTests MyAnimeListTests/AiringReminderManagerTests'`
  passes. No existing test covers the search host, the close adapter, or
  save-panel targeting.
- Not yet run: the runtime pass on Mac and iPad. The checks are batch selection
  with ⌘F and ⌘N, jumping from search, the Entry Hidden alert, Save Poster across
  two windows, list and grid focus, and the [014](../014-multiselect-invariants/000-plan.md)
  multi-selection invariants on iPad. The Codex session could not get
  computer-use access to the app or to Simulator.
- Commit: `0d46027` (this refactor, including the Mac source formatting pass).
