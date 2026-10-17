# 022 — Separate Mac and iOS library roots: Action record

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-10-17 | Plan written after the `#if os(macOS)` audit; maintainer scoped the work to the library root and the interaction model. | [000-plan.md](000-plan.md) |
| 2026-10-17 | Root and interaction-model split implemented on top of `40ae37a`. | `129150c` |
| 2026-10-17 | Grid and list containers split per platform ([002](002-grid-and-list-containers.md)); committed together with the root split because both steps edit the same files. | `129150c` |

## Outcome and current state (as of 2026-10-17)

`MyAnimeListApp.libraryRoot` shows `MacLibraryView` on the Mac and `LibraryView` on
iOS and iPadOS. Each root holds only its own platform's state.

Shared between the roots:

- **Entry actions.** `LibraryEntryActionState` holds delete and paste confirmation and
  the Share and Switch Poster workflow. The same file has the context-menu builders,
  `libraryEntryActionOverlays`, and `LibraryEntryWorkflowSheet`. `editButton` now
  requires its edit closure.
- **Browse state.** `LibraryBrowseState` is a per-window `@Observable` holding the
  scroll position and requests, the jump highlight, the search sheet, and the deferred
  jump from search. `libraryBrowseSearch` wires the search sheet and the add haptic.
  Each root passes a `reveal` closure for its platform's jump behavior. iOS passes a
  no-op; the Mac clears Find and selects the entry.
- **Window behaviors.** `libraryWindowBehaviors` covers the scoring/group reset, the
  scope-change hooks, highlight expiry, airing-reminder routing and its warning alert,
  and the duplicate-repair sheet.
- **Pages.** `LibraryEntryPage` wraps each layout page. A `LibraryEntryPages` switch existed until amendment 002 removed it.
- **Types.** `LibraryViewStyle` is now top-level. `LibraryEntryDetailHost` and
  `LibraryEntryDetailActivation` moved to their own file because `EntryDetailView`,
  `AnimeEntryListRow`, and `AnimeEntryCard` use them on both platforms.

iOS only (each file has one whole-file `#if !os(macOS)`):

- `LibraryView`, `LibraryView+MultiSelection`, `LibraryToolbar` (now including
  `LibrarySearchButton` and the iOS batch-selection controls), and
  `LibraryEntryInteractionState`.
- `LibraryEntryInteractionState` owns `actions: LibraryEntryActionState`. Its init sets
  `actions.willPresentWorkflow` so a newer workflow still retires a pending detail edit
  request. `activeSheetRoute` and `LibraryEntrySheetRoute` read the composed workflow
  state.

Mac only:

- `MacLibraryView` (state and body), `MacLibraryView+Actions` (renamed from
  `LibraryView+Mac`, with the `mac` prefixes dropped from members), and
  `MacLibraryToolbar`.
- `LibraryViewStyle.macCases` replaces `platformCases`.

Removed:

- `LibraryView+Commands.swift`. Its iOS `toggleInspector` and `inspectorReopenTarget`
  had no caller.
- The Mac `openProfileSettings` (`openSettings()`). Only the iOS toolbar's profile
  button called it; the Mac opens Settings from the app menu.

Platform conditionals in the touched files: `LibraryView.swift` went from 22 to 1, and
`LibraryEntryInteractionState.swift` from 11 to 1. `LibraryListView.swift` went from 7
to 9 in this step. Amendment [002](002-grid-and-list-containers.md) then split the grid
and list containers, which brought both files down to 1.

Key files:

- `MyAnimeList/Sources/Views/Library/LibraryView.swift`
- `MyAnimeList/Sources/Views/Library/LibraryEntryInteractionState.swift`
- `MyAnimeList/Sources/Views/Library/LibraryEntryActionState.swift`
- `MyAnimeList/Sources/Views/Library/LibraryEntryDetailHost.swift`
- `MyAnimeList/Sources/Views/Library/LibraryBrowseState.swift`
- `MyAnimeList/Sources/Views/Library/LibraryWindowBehaviors.swift`
- `MyAnimeList/Sources/Views/Library/LibraryEntryPage.swift` (since 002)
- `MyAnimeList/Sources/Views/Library/LibraryViewStyle.swift`
- `MyAnimeList/Sources/Views/Library/LibrarySearchSheet.swift`
- `MyAnimeList/Sources/Views/Library/LibrarySelectionDeleteButton.swift`
- `MyAnimeList/Sources/Mac/MacLibraryView.swift`
- `MyAnimeList/Sources/Mac/MacLibraryView+Actions.swift`
- `MyAnimeList/Sources/Mac/MacLibraryToolbar.swift`

## Deviations from plan

- Shared detail types moved to `LibraryEntryDetailHost.swift` instead of staying in the
  interaction file. The plan missed that the Mac inspector and shared rows use them.
- The plan said the batch-selection controls in `LibraryToolbar.swift` stay shared.
  Only `LibrarySelectionDeleteButton` is used on the Mac, so it moved to its own file
  and the rest of `LibraryToolbar.swift` became iOS-only. That also removed the
  `Membership` blank-icon conditional.
- `LibraryView+Search.swift` was renamed `LibrarySearchSheet.swift`, because its
  `LibraryView` extension moved into `LibraryBrowseState`.
- `LibraryEntryPages` mapped `.gallery` to the Grid page as a fallback. It was removed
  in 002.
- On iOS, Gallery was briefly an `if` branch outside `LibraryEntryPages`. Amendment
  002 restored the single `switch`.

## Validation

- `make build-mac` and `make build` (iOS) succeeded, both before and after
  `swift format`. The final build ran after `LibraryEntryPages` moved to its own file.
- `swift format lint -p` on every touched Swift file: no findings, after one
  doc-comment fix in `LibraryWindowBehaviors.swift`.
- `make test-app-sim APP_TEST_ONLY='MyAnimeListTests/LibraryEntryInteractionStateTests MyAnimeListTests/EntryDetailSessionTests'`
  on the booted iPad Pro 13-inch (M5) simulator: passed.
- `make test-app-mac APP_TEST_ONLY='MyAnimeListTests/LibraryEntryInteractionStateTests MyAnimeListTests/EntryDetailSessionTests MyAnimeListTests/MacLibrarySelectionTests'`:
  passed. A first attempt run alongside the simulator tests failed at build with a
  locked build database. That was a concurrent-build collision, not a test failure.
- Tests changed: the workflow and paste tests now target `LibraryEntryActionState`,
  and the multi-selection tests are iOS-only.
- `make run-mac`: the app launched and stayed running, with no new crash report. No UI
  interaction was exercised.
- Maintainer runtime pass, reported completed and passed on 2026-10-17, covering both
  this step and [002](002-grid-and-list-containers.md):
  - iOS: the Gallery ↔ List/Grid style transition, detail sheet and iPad inspector,
    Share and Switch Poster, delete and paste alerts, search add and jump with
    highlight, and multi-select batch actions.
  - Mac: selection, inspector, Find, menu commands, and the airing-reminder route.

## Open questions

None. Audit item #3 is done in [002](002-grid-and-list-containers.md).
