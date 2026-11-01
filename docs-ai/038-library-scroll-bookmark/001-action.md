# 038 — Library scroll bookmark: Action record

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-10-31 | Diagnosed the `scrolledID` mechanism (taps as position, one global key, inconsistent restore, deletion jumps); Codex reviewed the diagnosis and design; maintainer set the policies; plan written. | [000-plan.md](000-plan.md) |
| 2026-10-31 | Codex measured observation-only prototypes on the iOS simulator (see the plan's Amendments). The run also found that restored scene state overrode the benchmarks' `-LibraryViewStyle`, so a Grid benchmark could measure List. | Prototype branch, deleted |
| 2026-10-31 | Fixture launches ignore restored window state. | `a6a1f178` |
| 2026-10-31 | Bookmark, trackers, and shared page modifier implemented for iOS and Mac; `ScrollState`, the persisted key, the debounced writer, interaction writes, and deletion scroll targets removed. | This entry's commit |
| 2026-10-31 | Maintainer saw extra separators in the iOS List: the per-row visibility modifier wrapped the row's list-row modifiers and hid them. Moved inside `rowContent`, on iOS and Mac. | This entry's commit |
| 2026-10-31 | Maintainer reported List → Grid failing on Mac. A Codex logging check found the Mac List delivers no user scroll phases and never reports scrolled-out rows as hidden. Mac List now reads its AppKit table. Maintainer confirmed by hand. | This entry's commit |
| 2026-10-31 | Codex review: Gallery advancing past a deleted card used `record`, which a held bookmark rejects, so a second deletion before any swipe restored the wrong side. It now settles the bookmark on the replacement card. | This entry's commit |

## Outcome and current state (as of 2026-10-31)

Each window's `LibraryBrowseState` owns a `LibraryScrollBookmark` in memory: the entry
on top of what the user scrolled to, never written by taps, selection, or context menus,
and not persisted. Each List or Grid page owns a `LibraryVisibleEntryTracker` that feeds
the bookmark the visible entry with the lowest display index. The shared
`libraryScrollBookmark` modifier restores the bookmark top-aligned on appear, and takes
one `LibraryScrollInputs` value: a changed `LibraryScrollRequest` scrolls to its entry
(unless already visible), otherwise a changed `DisplayDefinition` (filters, category,
sort, direction, group, and Mac Find) scrolls to the top. A restore, a request, a style
switch, or an inspector reflow holds the bookmark (`isSettling`) until the user scrolls,
which prevents round-trip drift.

Signal sources: iOS List uses per-row `onScrollVisibilityChange`; iOS and Mac Grid use
`onScrollTargetVisibilityChange` with `.scrollTargetLayout()` and `onScrollPhaseChange`;
Gallery follows its own `.scrollPosition(id:)` and aligns the nearest surviving card when
its card disappears; Mac List uses `MacLibraryListScrollObserver`. Deletion issues no
scroll on List and Grid.

- `MyAnimeList/Sources/Views/Library/LibraryScrollBookmark.swift`
- `MyAnimeList/Sources/Mac/MacLibraryListScrollObserver.swift`
- `MyAnimeList/Sources/Views/Library/LibraryBrowseState.swift`
- `MyAnimeList/Sources/ViewModels/Library/LibraryBrowseScope.swift` (`DisplayDefinition`)
- `MyAnimeList/Sources/Views/Library/LibraryListView.swift`, `LibraryGridView.swift`, `LibraryGalleryView.swift`, `LibraryView.swift`, `LibraryView+MultiSelection.swift`
- `MyAnimeList/Sources/Mac/MacLibraryList.swift`, `MacLibraryGrid.swift`, `MacLibraryView.swift`, `MacLibraryView+Actions.swift`

## Deviations from plan

- A scroll request settles the bookmark on its target instead of taking whatever is on
  top when the jump finishes, and does nothing when the page already shows the target.
- Scroll-to-top is handled in each page with the request, in one `onChange`, not issued
  from the window root, so a jump that also leaves a category lands on its entry.
- Mac List uses the AppKit table instead of per-row visibility, which the plan had as the
  fallback. The plan's Observation table and Amendments record why.
- Rows partly under the translucent bars count as visible, so a restored entry appears
  just below the category strip, slightly lower than where the user left it. Accepted
  as is; not raised by the maintainer.

## Validation

- `make build` and `make build-mac`: passed after the final change.
- `make test-app-sim APP_TEST_ONLY='MyAnimeListTests/LibrarySortingAndDeletionTests MyAnimeListTests/LibraryCloudSyncPreferencesTests'`
  on the final code: both suites passed, including the new
  `testScrollBookmarkHoldsWhileSettlingAndFallsBackToNeighbors`.
- iPhone 18 Pro simulator (iOS 27.2), 800-entry fixture, driven with sim-use: deep List
  → Grid landed on the List's top entry's row; Grid → List without scrolling returned the
  same entry; List → Gallery → List kept the position; switching category and back to All
  went to the top. After the separator fix: screenshots confirmed the custom separator tint
  and 10 pt insets returned, and List → Grid still landed correctly.
- Native Mac: Codex check with logging and synthetic wheel input diagnosed the original
  failure (no fix verified by it). The maintainer verified the AppKit-based Mac List by hand.
- `make bench-quick BENCH_ONLY='testScrollList testScrollGrid'` passed before and after the
  refactor, with hitch numbers within noise. The after-run predates the separator fix, so
  its List layout differed; the maintainer chose not to rerun.

## Open questions

- Grid → List on Mac: Codex saw the restored entry not always top-aligned; not
  investigated, and the maintainer's check did not flag it.
- Mac Page Down or Space scrolling without a selection does not release the hold;
  arrow keys do, through the selection change.
- Not exercised: search jump, deleting Gallery's current card, iPad inspector reflow,
  two windows, physical devices, and hardware-keyboard scrolling on iPad.
- Per-row List observation cost on a physical iPhone is unmeasured; simulator runs showed
  about 2% of one core near the top with no hitch regression.
