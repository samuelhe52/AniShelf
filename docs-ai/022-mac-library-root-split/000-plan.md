# 022 — Separate Mac and iOS library roots: Plan

| Field | Value |
| --- | --- |
| Status | Implemented on `feat/native-macos` (`129150c`); maintainer runtime checks passed on 2026-10-17; see [001-action.md](001-action.md) |
| Anchor date | 2026-10-17 |
| Origin | Maintainer request on 2026-10-17. Claude audited where `#if os(macOS)` should become separate types; the maintainer chose to start with the library root (audit item #1) and the interaction model (#2). |
| Related | [021 Mac selection model](../021-mac-selection-model/000-plan.md) (reverses its rejected "fully separate Mac library view" alternative; see decisions), [020 native macOS](../020-native-macos/000-plan.md), [014 multi-selection invariants](../014-multiselect-invariants/000-plan.md), [005 adaptive library](../005-adaptive-library/000-plan.md) |

## Background

021 gave the Mac its own selection and inspector, but kept one `LibraryView` struct
and one `LibraryEntryInteractionState` class for both platforms. Later Mac work then
compiled the iOS-only parts out with `#if !os(macOS)` instead of moving them. As of
`40ae37a`:

- `LibraryView.swift` has 22 platform conditionals. It has a Mac-only state block,
  an iOS-only state block, and `openDetails`, `editDetails`, `openProfileSettings`,
  `showsCategoryStrip`, and `libraryNavigationStack` each fork their whole body. The
  Gallery case has a "never reached" `EmptyView()` on the Mac.
- iOS-only state is still compiled and unused on the Mac. This includes the
  multi-selection snapshot (`selectionDisplayItems` and related),
  `showProfileSettings`, and `isReorderingCategories`. `LibraryToolbar` on the Mac
  receives the iOS multi-selection closures and ignores them.
- `LibraryView+Commands.swift` is mostly per-platform shims. Its iOS
  `toggleInspector()` branch has no caller (only `MacLibraryCommands` calls it).
- `LibraryEntryInteractionState.swift` has 11 conditionals. They remove the detail-host
  state machine on the Mac, but multi-selection (`isMultiSelecting`,
  `selectedEntryIDs`) and `focusedEntryID` remain there, always unused.

## Goals

- Two library roots, `LibraryView` (iOS and iPadOS) and `MacLibraryView`, each
  holding only its own platform's state. `MyAnimeListApp` picks one.
- Pieces both platforms use are shared types, not copies:
  - per-window scroll, highlight, and search-jump state;
  - window-level behaviors (airing-reminder routing and warnings, duplicate repair,
    the scoring/group reset);
  - entry actions (delete and paste confirmation, the Share and Switch Poster
    sheets, context-menu builders);
  - the List and Grid pages. (Corrected by 002: only the `LibraryEntryPage` wrapper
    stayed shared once the containers split.)
- `LibraryEntryInteractionState` becomes iOS-only. It owns the detail host,
  multi-selection, and focus, and composes the shared action state.
- No behavior change on either platform.

### Non-goals

- Splitting `LibraryGridView` and `LibraryListView` into per-platform containers
  (audit item #3). They stay shared for now and keep their selection `#if` blocks.
  Their remaining reads of iOS-only state move behind `#if` until #3 lands. (Taken on
  in 002.)
- `EntryDetailView`, `TMDbBatchAddView`, and settings conditionals.

## Design / approach

### Shared (proposed new files under `MyAnimeList/Sources/Views/Library/`)

- `LibraryEntryActionState.swift`: an `@Observable @MainActor` class holding
  `deletingEntryID`, `pendingPasteRequest`, and `workflowPresentation`, with their
  methods. The file also takes the menu builders (`contextMenu`, `shareButton`, and
  siblings), `libraryEntryInteractionOverlays` (renamed
  `libraryEntryActionOverlays`), `SavePosterButton`, and a
  `LibraryEntryWorkflowSheet` view for the Share and Switch Poster content then
  inside `LibraryView.workflowContent`. `editButton` always takes its edit closure;
  every caller already passes one.
- `LibraryBrowseState.swift`: an `@Observable @MainActor` per-window class holding
  `scrollState`, `scrollRequest`, `highlightRequest`, `isSearching`,
  `isSearchSheetOnScreen`, `pendingJumpEntryID`, and `newEntriesAddedToggle`.
  It provides `requestScroll(to:)`, the deferred jump from search, and
  TMDb result processing. The jump takes a per-platform `reveal` closure: the Mac
  clears Find and selects the entry; iOS does nothing extra.
- `LibraryWindowBehaviors.swift`: a view modifier for what both roots apply to the
  window. It covers the scoring/group reset, the scope-change hooks
  (`scopeDidChange`), highlight expiry, airing-reminder routing (with an
  `openRoutedEntry` closure) and its warning alert, and the duplicate-repair sheet.
- `LibraryViewStyle.swift`: `LibraryView.LibraryViewStyle` becomes the top-level
  `LibraryViewStyle`. `platformCases` goes away; the Mac lists `[.list, .grid]`
  itself.
- `LibraryEntryPages`: the List and Grid page switch with its transition and
  layout animation (`libraryViewPage`). iOS handles the Gallery case before
  delegating to it. (Removed in 002; each root now switches over the shared
  `LibraryEntryPage` wrapper.)

### iOS only

- `LibraryView.swift` keeps its name and becomes iOS-only. It keeps the detail host
  (sheet and iPad inspector), the profile-settings overlay, the category strip, the
  multi-selection snapshot, and `LibraryToolbar`.
- `LibraryView+MultiSelection.swift` becomes iOS-only and loses its Mac branch.
- `LibraryEntryInteractionState` keeps its name and becomes iOS-only. It owns
  `let actions: LibraryEntryActionState` and observes workflow presentation so a
  newer workflow still cancels a pending detail edit request.
  `activeSheetRoute` and `sheetRouteDidDismiss` read the composed workflow state.
- `LibraryToolbar` and `LibraryToolbarTitle` become iOS-only. The batch-selection
  controls in the same file stay shared, because `MacBatchSelectionPanel` uses them.
  (Corrected during implementation: the panel uses only the delete button, which
  moved to `LibrarySelectionDeleteButton.swift`; the rest of the file is iOS-only. See
  [001-action.md](001-action.md).)

### Mac only (`MyAnimeList/Sources/Mac/`)

- Proposed `MacLibraryView.swift`: the Mac root's state and body (split view,
  inspector, Find, selection, commands). `LibraryView+Mac.swift` is renamed to
  proposed `MacLibraryView+Actions.swift`, and its extension retargets to
  `MacLibraryView`. It absorbs the Mac halves of `LibraryView+Commands` and
  `LibraryView+Search`.
- Proposed `MacLibraryToolbar.swift`: today's `LibraryToolbar.macContent`.

### Removed

- `LibraryView+Commands.swift` and its dead iOS `toggleInspector` and
  `inspectorReopenTarget`.
- The `LibraryEntrySheetRoute.detail` conditionals. The Mac binds its sheet to the
  workflow presentation directly, so the route enum becomes iOS-only.

## Alternatives & decisions

| Choice | Reason and alternative |
| --- | --- |
| Separate Mac and iOS library roots | 021 rejected a fully separate Mac library view because it would duplicate browsing, toolbar, and workflow code. Since then the toolbar, detail hosting, Gallery, and selection have all diverged. The shared remainder is now small enough to extract, so separate roots hold less duplicated logic than the fork does. Keeping one struct with `#if` was rejected because each Mac change kept adding branches to it. |
| Extract shared pieces as types, not a `LibraryWindowRoot` protocol with default methods | The protocol would need about ten `nonmutating set` requirements mirroring `@State`, which is the same state with less clarity. An observable per-window object can be tested and keeps per-property observation. |
| iOS model composes the action state instead of subclassing or duplicating it | iOS needs the workflow state for its one `.sheet(item:)` and to cancel edit requests; the Mac needs only the action state. Composition keeps one source of truth for workflows. |
| Keep the names `LibraryView` and `LibraryEntryInteractionState` for iOS | Smallest churn across iOS-only files, tests, and earlier docs-ai records that cite them. |
| Leave grid and list shared for now | The maintainer scoped this change to #1 and #2. Their selection forks are item #3 and need a separate pass to protect the 014 invariants. (Superseded the same day by 002.) |

## Validation and acceptance criteria

- `make build-mac` and `make build` pass. `make lint` and `make format` leave no
  new findings.
- Focused tests pass on macOS and the booted iPad simulator:
  `LibraryEntryInteractionStateTests` (shared action-state tests retargeted, iOS
  tests unchanged in intent) and `EntryDetailSessionTests`.
- `make run-sim` and `make run-mac` smoke checks: open detail (sheet and iPad
  inspector), Share and Switch Poster, delete and paste alerts, search add and jump
  with highlight, multi-select batch actions on iOS, and Mac selection, inspector,
  Find, and menu commands. The maintainer does the visual pass.

## Amendments

- Updated 2026-10-17: Grid and list containers split per platform (audit item #3); the Non-goal above was taken on as a follow-up, and `AnimeEntryListRow` stays shared — see [002-grid-and-list-containers.md](002-grid-and-list-containers.md). Plan text it invalidated is corrected in place and marked.
