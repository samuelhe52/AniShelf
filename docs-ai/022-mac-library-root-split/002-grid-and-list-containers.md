# 022.002 — Separate Mac and iOS grid and list containers

## Context

After the root split ([001-action.md](001-action.md)), `LibraryGridView` and
`LibraryListView` were still shared. They had 8 and 9 platform conditionals, and almost
none of their behavior was common: selection model, gestures, keyboard handling, list
style, and context-menu API all differed. The maintainer approved this follow-up
(audit item #3) on 2026-10-17 with Claude's defaults:

- split the row too;
- keep the Mac list's swipe actions;
- accept a few duplicated lines of scroll and animation code rather than add a shared
  modifier.

## Change

- **Shared cell.** `LibraryGridItem`, the poster card, moved out of
  `LibraryGridView.swift` into its own file. It keeps both selection looks: iOS dimming
  (`isSelected`) and the Mac ring (`showsSelectionRing`).
- **iOS containers.** `LibraryGridView` and `LibraryListView` are now iOS-only, each
  with one whole-file `#if`. They keep:
  - the multi-selection dimming and edit mode, the tap and double-tap gesture modifier,
    per-row context menus with previews, swipe actions, and focus;
  - the [014](../014-multiselect-invariants/000-plan.md) invariants: the list's row
    tap mask during edit mode (`tapGesturesEnabled: !interaction.isMultiSelecting`) and
    rendering from `LibraryView`'s selection snapshot.
- **Mac containers.**
  - `MacLibraryGrid`: `MacLibrarySelection` clicks, arrow keys, Escape, the
    column-count measurement, and the selection ring.
  - `MacLibraryList`: native `List(selection:)`, the inset style,
    `contextMenu(forSelectionType:primaryAction:)`, and the swipe actions it already
    had.
  - Code was moved, not rewritten.
- **Page switching.** `LibraryEntryPages` was removed. Each root builds its own page
  switch with the shared `LibraryEntryPage` wrapper. On iOS, Gallery, List, and Grid
  are again cases of one `switch`, as before 022. That removes the transition
  uncertainty 001 recorded.
- **Edit-mode shim.** `selectionEditMode` was removed from `PlatformViewModifiers`. Its
  only caller is now the iOS list, which sets `\.editMode` directly.
- **Row split not done.** The agreed default was to make `AnimeEntryListRow` iOS-only
  and add a Mac row. While implementing, Claude found that the row is also used on the
  Mac by Library search results (`LibrarySearchContent`) and the duplicate-repair
  sheet. Search results depend on the row's tap surface there: tapping a result jumps
  to it. Claude's earlier claim that the Mac never uses the row's tap closures was true
  only of the library list. Splitting the row would have moved conditionals into those
  call sites, so it stays shared, with 2 conditionals. `MacLibraryList` no longer passes
  the tap closures it never used.

## Refs

- `MyAnimeList/Sources/Views/Library/LibraryGridItem.swift`
- `MyAnimeList/Sources/Views/Library/LibraryGridView.swift`
- `MyAnimeList/Sources/Views/Library/LibraryListView.swift`
- `MyAnimeList/Sources/Views/Library/LibraryEntryPage.swift`
- `MyAnimeList/Sources/Mac/MacLibraryGrid.swift`
- `MyAnimeList/Sources/Mac/MacLibraryList.swift`
- `MyAnimeList/Sources/Utils/PlatformViewModifiers.swift`

Committed with the root split in `129150c`.

## Validation

- `make build-mac` and `make build` succeeded.
- `swift format lint -p` on the touched files: no findings.
- Focused tests passed on the booted iPad Pro 13-inch (M5) simulator and on macOS:
  `LibraryEntryInteractionStateTests`, `EntryDetailSessionTests`, and (Mac)
  `MacLibrarySelectionTests`.
- `make run-mac`: the app launched and stayed running, with no new crash report. No UI
  interaction was exercised.
- Maintainer runtime pass, reported completed and passed on 2026-10-17:
  - iOS: multi-select in List and Grid (row tap-to-select in edit mode, dimming) and
    tap or double-tap to open.
  - Mac: grid click, ⌘-click, ⇧-click, arrow keys, and Escape; list selection,
    double-click, Return, and swipe actions; and the context menus.
