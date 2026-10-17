# 021 — Mac selection and inspector model: Action record

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-10-16 | The uncommitted handoff and grid-width attempts discarded | — |
| 2026-10-16 | Plan written and the redesign implemented | `5eef8c9` |
| 2026-10-16 | Follow-up: native controls, sizing, and iOS-only presentation code | `5eef8c9` |
| 2026-10-17 | Follow-up: multi-item batch inspector, and the animation baseline | `5eef8c9` |

The work was developed in several uncommitted rounds and committed as one change
when the branch history was rewritten on 2026-10-17. The Mac app-info windows
made in the same rounds are recorded in [020.008](../020-native-macos/008-mac-native-ui.md).

## Outcome and current state (as of 2026-10-17)

### Selection and inspector

Each Mac library window owns a `MacLibrarySelection`. Grid clicks, arrow keys,
native `List` selection, Select All, and Escape change it, and nothing else
follows from a selection change. The inspector is shown or hidden by a
per-window `@SceneStorage` setting (`libraryInspectorShown`, shown by default).
Its content (`MacLibraryInspector`) depends on the selection: No Selection, one
entry's `EntryDetailView`, or `MacBatchSelectionPanel`.

The window has one Show/Hide Inspector toggle, in the inspector's own toolbar.
SwiftUI keeps that item at the window toolbar's trailing edge while the
inspector is collapsed. An early build also kept a Show Inspector button in the
main toolbar, which showed two toggles. The old model had hidden the duplicate
only because a closed inspector had no content.

Open actions select the entry, show the inspector, and scroll to it: double-click
in the grid, double-click or Return in the list
(`contextMenu(forSelectionType:primaryAction:)`), Show Details, an
airing-reminder route, and a search jump. If the entry is out of scope, Find,
the category, or the filters give way first. Edit does the same and adds a
one-shot `MacEntryEditRequest`. The list's context menu uses the same
selection-based API. A library, scope, or Find change, a batch action, or a
delete prunes the selection to the visible entries.

The window subtitle and the menu-bar actions read the selection inside small
modifiers (`MacLibrarySubtitle`, `MacLibrarySelectionObservers`), so a click
does not re-run `LibraryView`'s body.

### Batch inspector

`MacBatchSelectionPanel` works like Finder's Get Info for several items:

- Status and Score are pop-up pickers that show "Mixed" while entries differ.
- Favorite, Track Dates, and each category are `Toggle(sources:isOn:)`
  checkboxes with a native mixed state. New Category… creates a category and adds
  the selection to it.
- Delete is at the bottom, with its existing confirmation.

Every change goes through `LibraryBatchAction`. A first version, a grouped form
of the shared command menus, looked unbalanced in the maintainer's review: it
had detached chevrons and no visible state.

### Native controls and sizing

- The hand-drawn batch rows (`LibrarySelectionActionRow`) are gone. The shared
  selection controls take the selected entries instead of
  `LibraryEntryInteractionState`.
- `libraryProfileCommandButtonStyle(tint:)` applies `.bordered` on the Mac.
  `LibraryProfileSelectionCapsule`, an imitation pop-up, is iOS-only.
- `macSheetFrame` states only an ideal size. The Settings window has a fixed
  900pt width and a resizable height.

### Platform boundary

These are compiled for iOS only:

- `LibraryEntryInteractionState`'s detail presentation, host migration, resize
  deferral, and edit-request state.
- The `.detail` sheet route.
- `LibraryDetailHostCoordination` and `LibraryInspectorDetailWorkspaceState`.
- `LibraryView`'s host helpers.
- `LibraryGalleryView`.

Tests of that behavior are gated the same way. Focus, workflows, delete, paste,
and multi-selection stay shared.

### Animation baseline

The Mac-only animation additions around the inspector were removed, keeping
what iPad already has:

- `EntryDetailView`'s Mac `.geometryGroup()` and its unanimated entry switches.
  The opacity transition is back on the Mac.
- The batch panel's stored copy of the shown posters.

The grid kept the iPad's scoped reflow animation (`f2ef101`), then fed by
`LibraryView.isInspectorShown`. This established a shared animation technique,
not equivalent runtime behavior across platforms. The 2026-10-17
[runtime diagnosis](../027-mac-inspector-grid-reflow/001-action.md) found repeated
unanimated Mac layout updates during inspector resizing, versus one animated
destination-width update on iPad. A subsequent Mac width-driven animation candidate was
[rejected and removed](../027-mac-inspector-grid-reflow/003-reject-width-retargeting.md)
after maintainer review. The subsequent [direct endpoint fix](../027-mac-inspector-grid-reflow/004-endpoint-transition.md)
was accepted for opening/closing and live window/divider resizing.

### Key source files

- `MyAnimeList/Sources/Mac/MacLibrarySelection.swift`
- `MyAnimeList/Sources/Mac/MacLibraryInspector.swift`
- `MyAnimeList/Sources/Mac/MacBatchSelectionPanel.swift`
- `MyAnimeList/Sources/Mac/LibraryView+Mac.swift`
- `MyAnimeList/Sources/Mac/MacLibraryCommands.swift` (`hasSelection`, `hasBatchSelection`)
- `MyAnimeList/Sources/Views/Library/LibraryEntryInteractionState.swift`
- `MyAnimeList/Sources/Views/Library/LibraryGridView.swift`, `LibraryListView.swift`, `LibraryToolbar.swift`
- `MyAnimeList/Tests/MyAnimeListTests/MacLibrarySelectionTests.swift`

## Deviations from plan

- Native controls, sheet and Settings sizing, and the iOS-only gating were
  non-goals in the plan. The maintainer asked for them after reviewing the
  remaining workarounds.
- The batch panel's visuals were redesigned: a multi-item inspector replaced the
  command list.
- The list's context menu moved to the selection-based API too, not only its
  open action.
- While a newly selected entry's detail session is being created, the inspector
  shows nothing for that pass rather than No Selection.
- The menu bar resolves its target entry with `existingEntry(identity:)`, so it
  does not recompute display items.

## Validation

- `make build-mac` and `make build` passed for `5eef8c9` on its own.
- `make test-app-mac` with `MacLibrarySelectionTests` (4 new tests),
  `LibraryEntryInteractionStateTests`, and `EntryDetailSessionTests` passed.
- `make test-app-sim` with `LibraryEntryInteractionStateTests`,
  `EntryDetailSessionTests`, and `LibraryProfileSettingsLayoutPolicyTests` passed
  on the booted iPad Pro simulator.
- Runtime and visual acceptance is pending with the maintainer: clicks and
  ⌘/⇧-clicks in the grid and list; the inspector with no, one, and several
  selected; scope, Find, and status changes that hide selected entries; Show
  Details, Edit, Delete, and Escape; relaunch; the batch inspector's mixed states;
  and sheet sizes.

## Open questions

- New windows restore the same last-inspected entry, from the shared AppStorage
  key the maintainer chose for iPad multi-window. Per-window `@SceneStorage`
  restoration would be more Mac-like.
- A batch checkbox writes each entry separately, so the three-or-more-entries
  review signal (`appReview.record(.multiSelectAction)`) is recorded only by the
  Status and Score pickers.
- Entry 027 records the accepted endpoint reflow fix and its remaining OS-version
  and interaction coverage limits.
