# 041 — Mac inspector selection latency: Action record

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-11-10 | Sampled the open-inspector lag; three throwaway builds judged by the maintainer (see the plan's Background). | [Plan](000-plan.md) |
| 2026-11-10 | Implemented all three changes, uncommitted, pending the maintainer's runtime pass. | Source paths below |
| 2026-11-10 | Maintainer pass: everything good except a remaining switch animation. A screen recording showed the notes section sliding its scope chip and delaying its text; gave the Mac notes section an entry-scoped `.id`. | `EntryDetailMacTrackingRows.swift` |
| 2026-11-10 | Maintainer approved; committed as three commits (deferral, sidebar counts, stable inspector with these docs). | Git history |

## Outcome and current state (as of 2026-11-10)

1. **Deferred inspector.** `MacLibraryInspector` shows `shownIDs`, which follows
   `selection.ids` after a 20 ms wait in `.task(id: selection.ids)`; a newer
   selection cancels it. The first selection after none, and clearing the
   selection, apply synchronously in the existing `onChange(of: selection.ids,
   initial: true)`. Content, `selectedEntry` (and so session synchronization), and
   the batch panel's entries read `shownIDs`; `lastSingleID` and the poster flight
   still follow the live selection.
2. **Sidebar counts.** `LibraryDisplayCounts` (in `LibraryDisplayOrder.swift`) is
   built from the display records' `LibraryDisplayOrderInputs`.
   `LibraryBrowseScope.displayCounts` reads the display first, then reuses a
   count cached per `displayGeneration`. A read during an invalidation counts
   from `store.library` directly, as the uncached display path does.
   `MacLibrarySidebar` reads it; `MacLibrarySidebarCounts` is gone.
3. **Stable Mac inspector tree.** On macOS `EntryDetailView` no longer applies
   `.id(session.instanceID)` to its scroll content; a
   `.transaction(value: session.instanceID)` clears the animation and sets
   `disablesAnimations` for the switch. A Mac session's `scrollPosition` starts at
   `ScrollPosition(edge: .top)`. The Mac header poster and the hero's logo and
   artwork `KFImageView`s carry `.id` of their `TMDbImage`.
   `EntryNotesSection` in the Mac tracking card carries `.id(entry.libraryIdentity)`. iOS keeps the `.id`
   reset and its cross-fade.

Key files:

- `MyAnimeList/Sources/Mac/MacLibraryInspector.swift`
- `MyAnimeList/Sources/Mac/MacLibrarySidebar.swift`
- `MyAnimeList/Sources/ViewModels/Library/LibraryBrowseScope.swift`
- `MyAnimeList/Sources/ViewModels/Library/LibraryDisplayOrder.swift`
- `MyAnimeList/Sources/Views/Library/EntryDetail/EntryDetailView.swift`
- `MyAnimeList/Sources/Models/Library/EntryDetailSession.swift`
- `MyAnimeList/Sources/Mac/MacEntryDetailHeader.swift`
- `MyAnimeList/Sources/Views/Library/EntryDetail/EntryDetailMacTrackingRows.swift`
- `MyAnimeList/Sources/Views/Library/EntryDetail/EntryDetailHeaderComponents.swift`
- `MyAnimeList/Tests/MyAnimeListTests/LibrarySortingAndDeletionTests.swift`

## Deviations from plan

- The episodes block got no `.id`: its rows are keyed by TMDb season and episode
  IDs, which already differ between entries. Corrected in the plan.
- The plan assumed `EntryNotesSection`'s own identity-change reset was enough. It
  resets a frame late and animated; the section got an `.id` instead.

## Validation

- `make build-mac` passed after each change.
- `make test-app-mac APP_TEST_ONLY='MyAnimeListTests/EntryDetailSessionTests MyAnimeListTests/LibrarySortingAndDeletionTests MyAnimeListTests/MacLibrarySelectionTests'`
  passed. `testLibraryOnDisplayRespectsFiltersAndHiddenDroppedState` now also
  checks favorite counts across unsaved toggles and that a hidden dropped entry
  counts only under Dropped.
- `make test-app-sim APP_TEST_ONLY='MyAnimeListTests/EntryDetailSessionTests MyAnimeListTests/LibrarySortingAndDeletionTests'`
  passed on the iPad Pro 13-inch (M5) simulator, booted with the maintainer's permission.
- `make run-mac` with the 800-entry fixture: the maintainer confirmed responsiveness,
  poster, scroll, notes, episodes, progress, and sidebar counts. The one remaining
  switch animation was traced from their screen recording (frame strip at 20 fps)
  to the notes section and fixed; the maintainer approved the rebuilt app.

## Open questions

- The transaction covers implicit animations in the switch update only. State that a
  subview resets in its own `onChange` after the switch animates on its own, as the
  notes section did; others of that shape were not found by inspection.
- The 20 ms deferral is empirical; whether a run-loop hop would also let the
  highlight commit first was not tested.
- Key repeat may still lag if one inspector update exceeds the repeat interval.
- No profile was taken of the final build.
