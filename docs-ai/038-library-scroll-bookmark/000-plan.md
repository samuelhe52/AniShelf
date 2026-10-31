# 038 — Library scroll bookmark: Plan

| Field | Value |
| --- | --- |
| Status | Implemented — see [001-action.md](001-action.md) |
| Anchor date | 2026-10-31 |
| Origin | Maintainer request (2026-10-31) to review the `scrolledID` persistence mechanism, which had become hard to maintain and behaved unpredictably. Diagnosis by Claude Code, then discussed with an independent Codex thread (gpt-6.1-sol, high). The maintainer confirmed the symptoms and decided the policies below. |
| Related | [028-window-state-ownership](../028-window-state-ownership/000-plan.md), [026-library-performance-benchmarks](../026-library-performance-benchmarks/000-plan.md), [037-view-style-transition-under-bars](../037-view-style-transition-under-bars/000-plan.md), [014-multiselect-invariants](../014-multiselect-invariants/000-plan.md) |

## Background

Users can have very large libraries. Switching view styles (List, Grid, Gallery on
iOS; List, Grid on Mac) should not reset them to the top. The current mechanism
is one value, `ScrollState.scrolledID`
(`MyAnimeList/Sources/ViewModels/ScrollState.swift`). Each window has its own copy
in memory, but every window writes it to one app-global `UserDefaults` key
(`PersistedScrolledID`) through `DebouncedStringUserDefaultsWriter`, and new
windows seed from that key.

Writers give the value different meanings:

| Writer | Meaning |
| --- | --- |
| Gallery `.scrollPosition(id:)`, committed on settle (`LibraryGalleryView.swift`) | The page actually on screen |
| Gallery detail open and context menu `.onAppear` | The last touched card; `onDisappear` can then overwrite it with the local position |
| iOS List and Grid, Mac Grid: tap, double-tap, context menu `.onAppear`, Mac arrow keys | The last touched entry, not the visible one |
| Mac List | Never writes, so its value can be arbitrarily old |
| `LibraryBrowseState.requestScroll` (search jump, deletion, batch deletion) | The target of a command |

Restore runs once per style in `onAppear` through `proxy.scrollTo`, using
different anchors (List default, Grid `.center`) and without checking that the
entry is still displayed.

Observed symptoms, confirmed by the maintainer:

- After scrolling far without tapping, a style switch lands on an old tapped entry.
- Invisible interactions (detail open, context menu preview, search jump) move the
  restore target.
- A new window can restore to another window's position.

Deletion causes separate jumps. `LibraryBrowseScope.deleteEntry` scrolls to the
deleted entry's predecessor regardless of the viewport (on Mac, computed from
`scope.displayIDs`, which ignores Find). Batch deletion
(`LibraryView+MultiSelection.swift`, `MacLibraryView+Actions.swift`) scrolls to the
first surviving entry.

## Goals

- One meaning: the bookmark is the entry at the top of what the user is looking
  at, observed from scrolling. Taps, selection, and context menus never write it.
- A view-style switch restores the bookmark, including one made mid-scroll.
- Each window owns its bookmark in memory, consistent with 028.
- Deletion and other passive data changes keep the viewport.
- No measurable scroll regression in List and Grid at large library sizes.

### Non-goals

- Restoring the position after a cold launch or scene restoration. The maintainer
  decided this is not needed.
- Remembering a position per category, filter, or sort.

## Behavior contract

| Event | Result |
| --- | --- |
| View-style switch | Restore the bookmarked entry: top-aligned in List and Grid, the aligned card in Gallery |
| Category, filter, or Mac Find change | Scroll to the top; the bookmark becomes the new first entry |
| Sort strategy, sort direction, or group change | Scroll to the top. The bookmark was the incidental top row, not a user choice, so following it into a new order lands at an arbitrary point. |
| Passive data change (sync, an edit that reorders under the current sort) | Keep the bookmarked entry |
| Deletion that keeps the bookmarked entry, single or batch | No scroll |
| Deletion of the bookmarked entry | Move to the nearest surviving neighbor in the previous display order, searching outward; top if none survives |
| Search jump, add from search, Mac reveal | Scroll and highlight via `LibraryScrollRequest`; the bookmark settles on the target until the user scrolls. A target the page already shows does not scroll or move the bookmark, so a Mac double-click does not act like the old tap writes. |
| Multi-selection, inspector open or close, window resize | Keep the bookmarked entry; reflow does not change it |
| Repeated style switches without scrolling | The same entry every time; no drift |

## Design / approach

### Ownership

`LibraryBrowseState` holds the window's bookmark in memory, outside the serialized
`LibraryBrowseScope.State`. Remove `ScrollState`, the `PersistedScrolledID` key and
its entry in the preference key list (`String+Extensions.swift`), and
`MyAnimeList/Sources/Utils/DebouncedUserDefaultsWriter.swift` (its only user is
`ScrollState`). Stale values left in user defaults are ignored.

### Observation

Each page owns a small visibility tracker (`LibraryVisibleEntryTracker` in
`MyAnimeList/Sources/Views/Library/LibraryScrollBookmark.swift`, with the bookmark and the shared
page modifier).
It is a plain reference type, not `@Observable`, so a visibility callback updates
a set and never invalidates a view. It keeps the visible IDs and an ID → display
index map, rebuilt only when display order changes. The candidate is the visible
ID with the lowest index.

| Surface | Source |
| --- | --- |
| iOS and Mac Grid | `.scrollTargetLayout()` with one `onScrollTargetVisibilityChange` |
| Gallery | The existing local `.scrollPosition(id:)` |
| iOS List | Per-row `onScrollVisibilityChange`, inside the row's list-row modifiers (applied outside them, it hid them from the List) |
| Mac List | The backing `NSTableView`, found by searching the view hierarchy around a background probe for the table scroll view that overlaps it (public AppKit API only): visible rows on clip-view bounds changes, and a local `.scrollWheel` monitor for the user's scrolling (`MacLibraryListScrollObserver.swift`) |

"Visible" uses an explicit threshold chosen in the spike. The default 50% leaves
out a partly visible leading row, which may be what we want for a top-aligned
restore.

### Hand-off and suppression

- On a style switch, the outgoing page's current candidate becomes the bookmark
  before the new page is built. It must not depend on outgoing `onDisappear`
  ordering, and it must not require the scroll to be idle.
- A restore, a reflow, or a `LibraryScrollRequest` sets a "settling" flag. Candidates
  observed while it is set do not replace the bookmark. The flag clears when the
  user scrolls (`onScrollPhaseChange` to `.interacting`, `.tracking`, or
  `.decelerating`), and on the Mac also when the selection moves, since arrow keys
  scroll without a user phase. This prevents round-trip drift: restoring item 103
  into a grid whose row starts at 100 keeps 103.
- The style picker freezes the bookmark before the page swap, so the outgoing page's
  last callbacks cannot move it.
- Because the tracker belongs to the page, callbacks from an outgoing page cannot
  reach the incoming one. Add generation tagging only if the spike shows leakage.

### Commands

`LibraryScrollRequest` stays as the one-shot command channel. Pages take one
`LibraryScrollInputs` value (the scope's `DisplayDefinition`, the Mac Find query,
and the request) and handle it in a single `onChange`: a changed request wins,
otherwise a changed definition scrolls to the first entry. A jump that also leaves a
category or clears Find therefore lands on its entry, not on the top.

Deletion issues no scroll: List and Grid rows below move up into place. Gallery
aligns the nearest surviving neighbor when its aligned card disappears, which the
old predecessor policy (`c9b33bcc`) existed for. `LibraryBrowseScope.deleteEntry`
and its predecessor and first-survivor targets are removed; restore falls back to
the nearest neighbor in the order recorded with the bookmark.

### Removed code

Interaction writes in `LibraryListView`, `LibraryGridView`, `LibraryGalleryView`
(including the card wrapper's binding and `commitLocalScrollPosition`),
`MacLibraryList`, and `MacLibraryGrid`; the per-style `onAppear` restores, which
become one restore path; the batch-deletion scroll targets.

## Alternatives & decisions

| Choice | Reason and alternative |
| --- | --- |
| Observe visibility rather than infer from taps | Taps are the root cause of the symptoms. |
| Drop persistence | Cold-launch restore is not needed (maintainer). Removes the global key, the debounced writer, and the cross-window seeding. |
| Non-observable tracker | Keeps callback cost to a set update with no SwiftUI invalidation; addresses the maintainer's CPU concern by construction. |
| Query visible rows only at switch time | Rejected: SwiftUI has no synchronous "visible IDs now" query. |
| Grid offset → index math | Rejected for now: the grid is adaptive and reflows with the inspector, so this duplicates layout. Revisit only if measurement shows a problem. |
| UIKit/AppKit introspection of visible rows | Fallback for List only if the public API fails the spike; fragile mapping from native rows to IDs. |
| Commit only when scrolling stops | Rejected: a mid-scroll style switch would restore a stale position. |
| Top after category, filter, Find | Maintainer decision. |
| Top after sort and group | Recommended by Claude Code and adopted. The maintainer was unsure; one-line policy flip if they prefer keeping the entry. |
| Keep viewport on deletion | Maintainer decision; replaces the predecessor and first-survivor jumps. |
| Generation tagging of observations | Proposed by Codex; deferred because page-owned trackers already isolate pages. |

## Validation and acceptance criteria

1. **Spike (before the main change):** per-row `onScrollVisibilityChange` in List on
   iOS 26 and native Mac. Check the first appearance, row reuse, keyboard and
   trackpad scrolling, non-animated `scrollTo`, and whether
   `onScrollPhaseChange` fires for List. Record callback counts per screen of scroll.
2. **Performance:** compare baseline and change at the 800-entry fixture, plus a
   2,000-entry fixture if one can be generated, using `LibraryBenchmarkTests` on
   iPhone (per 026, not the iPad simulator). Add a deep-scroll then style-switch
   case. Accept no meaningful regression in hitch metrics for `testScrollList` and
   `testScrollGrid`. Mac performance is checked manually; the benchmarks do not
   cover native Mac.
3. **Correctness:** rapid switches during momentum; repeated switches without
   scrolling; first and last rows; inspector open and close; deletion of the
   bookmarked entry and of other entries, single and batch; Mac Find; two windows
   with different positions; late Mac scene restoration of view style.
4. **Tests:** update `LibrarySortingAndDeletionTests.testDeletionScrollTargetFallbacks`
   for the nearest-neighbor policy and `LibraryCloudSyncPreferencesTests` for the
   removed key. Add a unit test for the tracker's candidate selection only if its
   logic is more than a min-by-index.
5. Builds: `make build`, `make build-mac`, `make test-sim` with a booted simulator.

## Amendments

- 2026-10-31: Observation cost was measured by Codex on the iOS 27.2 simulator before
  implementation (prototype branch since deleted at the maintainer's request).
  Grid's single target-visibility callback showed no consistent CPU change. Per-row
  List observation added 9–21% app CPU per swipe window near the top (about 2% of one
  core), not reproduced in one deep-scroll pair, with no hitch regression beyond
  run-to-run noise; 8–12 visibility callbacks per swipe. A fixed-row-height offset
  variant disagreed with per-row visibility by one row and was rejected. Per-row List
  observation was adopted; a native `UICollectionView` probe was started and stopped
  before validation.
- 2026-10-31: On native Mac, the maintainer saw List → Grid fail. A Codex check with
  logging and synthetic wheel input found both SwiftUI signals unreliable for the Mac
  List: it reported no user scroll phases, so the restore lock never released, and rows
  scrolled out of view never reported themselves hidden, so the tracker stayed on row 0.
  Mac Grid delivered phases and target visibility correctly under the same input. The
  Mac List now reads its AppKit table instead; iOS is unchanged.
