# 035 — Single-entry category assignment: Action record

## Timeline
| Date | Change | Ref |
| --- | --- | --- |
| 2026-10-30 | Shared category menu content, context-menu submenu with prompt hosted by the action overlays, entry detail control on iOS and Mac, Mac drag onto sidebar categories | Commit that adds this record |
| 2026-10-30 | Context-menu toggles changed to dismiss after the iPad simulator showed stale checkmarks | Commit that adds this record |
| 2026-10-30 | Maintainer review fixes: aligned iOS checkmarks, capped Mac row, iOS detail control moved into the More menu | [002](002-maintainer-review.md) |

## Outcome and current state (as of 2026-10-30)

- Entry context menus (iOS grid, list, gallery; Mac grid, list) carry a
  Categories submenu: one toggle per category, then New Category…, which
  creates the category and adds the entry. Hidden while categories are off.
- Entry detail edits the entry's categories: on iOS through a Categories
  submenu of the quick actions' More menu, on Mac through a Categories row in
  the tracking card ("None" when empty; the full list, or "<first> and N more"
  when that does not fit in 220 pt, with the full list as a tooltip; shown while categories are on and at least one
  exists). Both menus stay open between toggles and update in place.
- iOS menu rows draw the checkmark in the icon column
  (`LibraryCategoryMembership`, shared with the batch menu) so names align with
  New Category…; Mac menus use native toggles.
- Mac grid cards and list rows are draggable as `LibraryEntryDragPayload`
  (exported type `com.samuelhe.myanimelist.library-entries`); dragging a
  selected entry carries the whole selection. Sidebar category rows accept the
  drop and add the entries.
- Every write goes through `LibraryBatchAction.category`.

Key files:
- `MyAnimeList/Sources/Views/Library/Categories/EntryCategoryMenu.swift`
- `MyAnimeList/Sources/Views/Library/LibraryEntryActionState.swift`
- `MyAnimeList/Sources/Views/Library/EntryDetail/EntryDetailHeaderComponents.swift`
- `MyAnimeList/Sources/Views/Library/EntryDetail/EntryDetailMacTrackingRows.swift`
- `MyAnimeList/Sources/Mac/MacLibraryEntryDrag.swift`
- `MyAnimeList/Sources/Mac/MacLibrarySidebar.swift`
- `MyAnimeList/Resources/Info.plist`

## Deviations from plan

- Context-menu toggles no longer keep the menu open. On the iPad simulator a
  toggle inside the open context menu saved the change (entry detail reflected
  it) but the checkmark did not update until the menu was reopened. The same
  content in entry detail's regular `Menu` updated in place, so only the
  context menu dismisses (`keepsPresented: false`).

## Validation

- `make build` and `make build-mac`: succeeded, no new warnings.
- `make run-sim` on the booted iPad Pro 13-inch (M5) simulator, Japanese UI:
  context menu shows カテゴリ; New Category… from it presented the name prompt
  and the created category was checked for the entry; toggling from the context
  menu dismisses it and the change shows in detail; the detail line appears
  under the quick actions and its menu updates checkmarks in place. The
  temporary test category was deleted afterwards.
- Maintainer, on Mac: context menu and drag onto sidebar categories work.
- After the review fixes, on the iPad simulator: context-menu names align with
  and without a checkmark; the More menu's Categories submenu stays open and
  toggles its checkmark in place. Test toggles were reverted.
- Maintainer, after the review fixes: accepted on Mac and iOS, including the
  Mac row's full-list / "and N more" label.
- Not run: iPhone layout and automated
  tests (none added; the write path is the existing batch action).

## Open questions

- Whether sidebar rows show a drop highlight is unverified.
