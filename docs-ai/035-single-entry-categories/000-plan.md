# 035 — Single-entry category assignment: Plan

| Field | Value |
| --- | --- |
| Status | Implemented — maintainer accepted |
| Anchor date | 2026-10-30 |
| Origin | Maintainer: adding one entry to a category requires entering multi-select, which is a hassle and unintuitive |
| Related | [034-ai-integration](../034-ai-integration/000-plan.md) (category drafting), [028-window-state-ownership](../028-window-state-ownership/000-plan.md) |

## Background

Category membership lives on each `AnimeEntry` as `categoryIDs`. Before this
work the only membership editors were batch surfaces: the iOS multi-select
toolbar's `LibrarySelectionCategoryMenu` (`MyAnimeList/Sources/Views/Library/LibraryToolbar.swift`)
and the Mac `MacBatchSelectionPanel`. Filing one anime meant entering
multi-select, selecting it, and using the batch menu. Entry detail showed no
categories at all, so an entry's memberships were only discoverable by
filtering each category.

## Goals

- Toggle one entry's categories, or create a category containing it, from the
  entry context menu on iOS (grid, list, gallery) and Mac (grid, list).
- Show an entry's categories in entry detail and edit them there.
- Mac: drag entries from the grid or list onto a sidebar category to add them;
  dragging a selected entry carries the whole selection.

### Non-goals

- Multi-selection context menus. The Mac context menu keeps acting on the
  clicked entry, like every other item in that menu.
- Dropping onto categories on iOS (the category strip), or removing membership
  by drag.

## Design / approach

**One write path.** Every new surface writes through
`LibraryBatchAction.category(id, isMember:, knownCategoryIDs:)` applied to the
entry, the same action the batch menus use, so stale-ID cleanup and
`categoriesUpdatedAt` stamping stay in one place.

**Shared menu content.** A proposed `EntryCategoryMenuContent` view
(proposed file `MyAnimeList/Sources/Views/Library/Categories/EntryCategoryMenu.swift`)
lists a checkmark toggle per category, then **New Category…**. In entry detail,
toggles keep the iOS menu open (`keepsMenuPresentedAfterAction()`), as the batch
menu does; in the context menu they dismiss it (see Amendments). It
reads `LibraryStore` from the environment and is hidden while categories are
turned off.

**Context menu.** `LibraryEntryActionState` gains a Categories submenu and a
pending new-category request. A context menu's views vanish when it closes, so
the name prompt is hosted by `libraryEntryActionOverlays`, which already
presents the per-window delete and paste alerts; on submit it creates the
category and adds the entry.

**Entry detail.** iOS: a compact category line under the quick actions row (the
Tracking disclosure is collapsed by default, so placing it there would hide it).
Mac: a Categories row in `MacEntryTrackingEditor`, matching its label/value
rows. Both are menus over the shared content, shown when categories are enabled
and at least one exists, and host their own name prompt. *Corrected after review:
iOS uses a Categories submenu in the quick actions' More menu instead of the line;
see [002-maintainer-review.md](002-maintainer-review.md).*

**Mac drag.** A proposed `LibraryEntryDragPayload` (`Codable`, `Transferable`)
carries entry raw IDs under a new exported type
`com.samuelhe.myanimelist.library-entries` declared in
`MyAnimeList/Resources/Info.plist`. Grid cards and list rows are `draggable`;
the payload is built lazily at drag start and holds the selection when the
dragged entry is selected, otherwise only that entry. Sidebar category rows
accept the payload with `dropDestination` and add the resolved entries.

## Alternatives & decisions

| Choice | Reason and alternative |
| --- | --- |
| Reuse `LibraryBatchAction.category` | Keeps one membership write path; a direct `updateCategoryMembership` call per surface would duplicate the known-ID cleanup. |
| Submenu of toggles over a picker sheet | Two taps from a long-press, matches the batch menu; a sheet is heavier and adds nothing. |
| Prompt hosted by action overlays | Context-menu content is torn down on dismissal, so it cannot own alert state. |
| iOS detail line under quick actions | Always visible; inside Tracking it would be collapsed by default. |
| Custom exported UTType for drag | Avoids treating arbitrary dropped text as entry IDs; a plain-string payload was rejected for that reason. |
| Per-entry context menu on Mac even within a selection | Consistent with the rest of the menu; Finder-style selection menus are out of scope. |

## Validation and acceptance criteria

- `make build` (iOS) and `make build-mac` succeed.
- Focused existing category tests still pass if a simulator is booted.
- Runtime UI checks (menu stays open, prompt appears, drop highlight) need the
  maintainer's visual pass unless a booted simulator is available.

## Amendments
- Updated 2026-10-30: context-menu toggles dismiss the menu, because iOS does not redraw an open context menu — see [001-action.md](001-action.md)
- Updated 2026-10-30: iOS menu checkmarks drawn in the icon column, Mac row width capped, iOS detail control moved into the More menu — see [002-maintainer-review.md](002-maintainer-review.md)
