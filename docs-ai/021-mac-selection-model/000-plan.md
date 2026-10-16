# 021 — Mac selection and inspector model: Plan

| Field | Value |
| --- | --- |
| Status | Implemented on `feat/native-macos` (`5eef8c9`); maintainer runtime check pending; see [001-action.md](001-action.md) |
| Anchor date | 2026-10-16 |
| Origin | Maintainer review on 2026-10-16: the Mac fixes and workarounds had become hard to follow and maintain, and many patched the wrong model. Claude proposed this redesign and the maintainer approved it in the same session. |
| Related | [020 native macOS](../020-native-macos/000-plan.md) (supersedes the selection parts of [004](../020-native-macos/004-slice-2-mac-shell.md), [006](../020-native-macos/006-slice-4-polish.md), and [008](../020-native-macos/008-mac-native-ui.md)), [014 multi-selection invariants](../014-multiselect-invariants/000-plan.md) |

## Background

The native Mac app (020) reused the iOS interaction model for selection. On iOS,
entry detail is *presented* (a sheet or an iPad inspector) through
`LibraryEntryInteractionState`'s detail/host presentation state, and
multi-selection is a *mode* (`isMultiSelecting`) entered with Select and left with
the X button. On the Mac, a click opened detail and a ⌘-click entered the
multi-selection mode, so inspector visibility followed selection.

Every Mac follow-up then had to translate between the desktop selection and that
model:

- `LibraryEntryInspectorModifier` kept a stored copy of inspector visibility,
  reconciled from detail and batch state, and had to tell SwiftUI's own
  dismissal apart from a content swap.
- `isBatchInspectorHidden` had to be reset when a batch began. The detail-to-batch
  handoff depended on the order of state writes, and a later review round
  (discarded before commit) reordered them again.
- `dismissInspectorOutsideScope()` closed the inspector when a filter hid the
  entry. `refreshSelectionDisplayItemsIfNeeded()` turned a batch of one back into
  detail.
- The iOS sheet/inspector host migration (`LibraryDetailHostCoordination`,
  resize deferral, dormant detail) still ran on the Mac, where detail is only ever
  in the inspector.

## Goals

- A Mac selection model in the shape Finder, Mail, Xcode, and Notes use:
  - One selection per window: a set of entry identities.
  - Inspector visibility is a separate per-window setting. ⌥⌘I and the toolbar
    toggle it; selecting does not open or close it.
  - Inspector content follows the selection: nothing selected shows No
    Selection, one entry shows its detail, several show the batch panel. Swapping
    content never presents or dismisses anything.
  - A scope or Find change narrows the selection to the entries still visible.
- Delete the Mac branches that existed only to translate between the two models.
- Keep iOS behavior and its code paths unchanged.

### Non-goals

- Grid reflow jitter while the inspector animates. The measured-width attempt from
  last review round was discarded, and jitter stays an open issue.
- Redesigning the inspector's contents (`EntryDetailView`'s Mac layout,
  `MacBatchSelectionPanel`'s visuals).
- `macSheetFrame` and the Settings window size. (Later brought into scope; see [001-action.md](001-action.md).)

## Design / approach

### State

- Proposed `MyAnimeList/Sources/Mac/MacLibrarySelection.swift`: an
  `@Observable @MainActor` class owned by each library window (`@State` in
  `LibraryView`). It holds `ids: Set<LibraryEntryIdentity>` and the `anchor` of the
  last plain or ⌘-click. Its methods are pure state transitions, so they can be
  tested without views:
  - `click(_:_:layoutIDs:)` handles replace, toggle (⌘), and extend (⇧), using
    `MacSelectionClick`.
  - `select(_:)` handles native `List` selection.
  - `move(by:in:)` moves by one card for the grid's arrow keys.
  - `prune(keeping:)` intersects the selection with what is still visible.
  - `single` is the selected identity when exactly one entry is selected.
- Inspector visibility is a `@SceneStorage` Bool in `LibraryView`, true by default.
- A one-shot edit request (identity and request ID) replaces
  `LibraryEntryDetailEditRequest` on the Mac. It asks the inspector's detail to
  scroll to the editing section.

`LibraryView`'s body does not read `ids`. Selection-dependent views (grid rings,
the `List` binding, the inspector, the window subtitle, the menu-bar actions)
read it themselves. A click then does not recompute the library's display items
([014](../014-multiselect-invariants/000-plan.md) records why that matters).

### Views

- Proposed `MyAnimeList/Sources/Mac/MacLibraryInspector.swift`: the inspector's
  root view. It switches on the selection, keeps `EntryDetailSessionStore` in sync
  for a single selection, hosts `EntryDetailView` or `MacBatchSelectionPanel`, and
  owns the one Hide Inspector toolbar button.
- `macLibrarySplitView` attaches `.inspector(isPresented:)` directly to the
  library column, with the SceneStorage binding.
- `LibraryEntryInspectorModifier` becomes iOS-only and drops its batch
  parameters. `LibraryDetailHostCoordination` is applied on iOS only.
- `LibraryListView` (Mac) binds `List(selection:)` to the selection. Double-click
  and Return use `contextMenu(forSelectionType:menu:primaryAction:)`, the native
  List API.
- `LibraryGridView` (Mac) reads the selection from the environment. Clicks and
  arrow keys go through `MacLibrarySelection`, because `LazyVGrid` has no native
  selection. Double-click reveals the entry in the inspector.
- Batch-selection controls (`LibrarySelectionStatusMenu` and its siblings in
  `LibraryToolbar.swift`) take the selected entries instead of
  `LibraryEntryInteractionState`. iOS passes its snapshot entries, and the Mac
  passes the selected entries in layout order.

### Entry actions on the Mac

| Request | Behavior |
| --- | --- |
| Click, ⌘-click, ⇧-click, arrows, List selection | Change the selection only. |
| Double-click, Return, Show Details, airing-reminder route, search jump | Select the entry, show the inspector, scroll to it. |
| Edit (context menu, ⌘E) | As Show Details, plus an edit request. |
| Batch action | Apply to the selected entries. Visibility pruning then drops entries the action moved out of scope. |
| Delete (⌫) | One entry: the existing single-delete alert. Several: the batch-delete alert. |
| Escape | Clear the selection. |
| Last-inspected restore | Persist the single selection to the existing `libraryLastInspectorDetailEntryIdentity` key and restore it on first appear, as before. |

### Removed on the Mac

`applyMacSelection`, `handleMacClick`, `dismissInspectorOutsideScope`,
`endMacBatchForEntryRequest`, `isBatchInspectorHidden`, `macSelectionAnchor`,
`isMacBatchInspectorShown`, the Mac branch and stored binding in
`LibraryEntryInspectorModifier`, the Mac branches in `LibraryView+Commands`,
`LibraryView+MultiSelection`, and `LibraryView+Search`, and the `click`/`select`
fields on `LibraryEntryDetailActions`. The Mac no longer calls
`interaction.openDetails`, `enterMultiSelection`, or `exitMultiSelection`.
Workflows (Share, Switch Poster), the delete and paste alerts, and focus stay in
`LibraryEntryInteractionState` and remain shared.

## Alternatives & decisions

| Choice | Reason and alternative |
| --- | --- |
| Separate the Mac selection and presentation layer; share data, detail views, and batch actions | Patching the shared model kept producing ordering bugs (see [020.008](../020-native-macos/008-mac-native-ui.md)'s rejected attempts). A fully separate Mac library view was rejected: it would duplicate browsing, toolbar, and workflow code that already works. |
| Inspector visibility independent of selection | The desktop convention, and it removes the handoff entirely. Opening the inspector on every click was rejected because it couples the two again. Explicit open actions (double-click, Show Details) still show it. |
| A per-window observable selection object instead of `@State Set` in `LibraryView` | Keeps selection changes from re-running `LibraryView`'s body and recomputing display items. Inferred from the 014 performance invariant; not measured on the Mac. |
| `contextMenu(forSelectionType:primaryAction:)` for List double-click | The native List API for an open action on a selection. Row-level tap gestures were rejected; they fight native selection (see 014). |
| Restore last-inspected entry from the existing shared AppStorage key | Keeps the behavior the maintainer chose for multi-window ([multi-window decision](../008-multi-window-presentation/000-plan.md)). Per-window SceneStorage restoration would be more Mac-like and is left open. |
| Keep the grid's custom click and arrow handling | `LazyVGrid` has no selection API on macOS. This matches common practice for SwiftUI grids. |

## Validation and acceptance criteria

- `make build-mac` and `make build` (iOS) pass.
- New `MacLibrarySelectionTests` (Mac-only) cover click, toggle, extend, arrow
  moves at edges, List selection anchor, and pruning. Existing
  `LibraryEntryInteractionStateTests` pass on macOS and the booted iOS simulator.
- Maintainer runtime checks: click and ⌘/⇧-click in grid and list; hide and show
  the inspector with and without a selection; switch between one and several
  selected without the inspector closing; filter, Find, or a status change that
  hides selected entries; Show Details, Edit, Delete, and Escape; relaunch.

## Amendments

- Updated 2026-10-17: The follow-ups on this entry were folded into [001-action.md](001-action.md) when the records were consolidated: native controls and sizing cleanup, the multi-item batch inspector, iOS-only presentation code, and the animation baseline.
