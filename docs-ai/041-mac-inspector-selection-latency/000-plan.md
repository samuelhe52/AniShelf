# 041 — Mac inspector selection latency: Plan

| Field | Value |
| --- | --- |
| Status | Implemented |
| Anchor date | 2026-11-10 |
| Origin | Maintainer report: with the Mac inspector open, moving the List selection lags noticeably; with it closed, selection is fine. Written after a profile and three throwaway builds, before implementation. |
| Related | [021-mac-selection-model](../021-mac-selection-model/000-plan.md) ([021.002](../021-mac-selection-model/002-hidden-inspector-work.md)), [024-inspector-entry-switch](../024-inspector-entry-switch/000-plan.md), [039-library-save-invalidation](../039-library-save-invalidation/000-plan.md), [040-per-entry-display-updates](../040-per-entry-display-updates/000-plan.md) |

## Background

021.002 removed hidden-inspector work, and 039/040 removed the save-triggered
library refetch and the 800-row display rebuild. The open-inspector lag remained.
039 had already shown that the app's own selection work is small: session
construction 0.3–0.7 ms, `EntryDetailView.body` under 1 ms per evaluation. So
loading the detail data is not the cost.

A 30-second `sample` of the Debug app with the 800-entry fixture, taken while the
maintainer arrowed through the List with the inspector open, showed the main
thread busy for about 8,400 of 11,200 samples. Sampling slowed the app
noticeably, so these are proportions, not timings:

| Work | Samples |
| --- | ---: |
| SwiftUI measuring the inspector's scroll content | ~2,000 |
| ↳ of which, `NSHostingView` minimum-size passes | ~400 |
| `MacLibrarySidebarCounts.init`, recounting all entries in the sidebar's `body` | ~436 |
| Detail session, `prepare`, `apply`, and the unchanged-response comparator | ~165 |

Inside the inspector's layout, the heavy frames are layout-node creation
(`StackLayout.makeChildren`, `makeLayoutView`, `DynamicLayoutComputer`), text
measurement, and the cast carousel. That matches the whole tree being rebuilt:
`EntryDetailView` puts `.id(session.instanceID)` on its scroll content, and every
selection creates a new session. The inspector rebuild also runs in the same
update as the List's selection, so the highlight waits for it.

The sidebar recounts because its `body` reads `watchStatus`, `favorite`, `type`,
and `categoryIDs` of every entry, so any of those writes during a detail load
invalidates it (inference from the read set; the triggering write was not
isolated).

Throwaway builds, judged by the maintainer:

| Build | Result |
| --- | --- |
| Mac `.id` removed | Better, not at parity with the inspector closed |
| Inspector deferred ~20 ms behind the List, `.id` kept | Better than the previous build, not at parity |
| Deferral + `.id` removed + sidebar counts skipped | Substantially more responsive; inspector animations stutter on switch |

The stutter in the last build is expected: implicit animations keyed on entry
values (for example `.animation(.default, value: entry.watchStatus)` in
`MacEntryTrackingEditor`) fired on each switch once the views persisted.

## Goals

- Selecting in the Mac List with the inspector open feels close to the inspector
  closed, for single presses and for key repeat.
- The inspector shows the new entry complete and without animation on a switch,
  as 024 established; network-filled content still fades in.
- No per-entry state leaks from the previous entry.

### Non-goals

- iOS and iPad keep the `.id` reset and their 0.18 s cross-fade.
- Deferring the inspector until key repeat ends (Finder-style) is not part of
  this plan; it is the next lever if key repeat still lags.
- Moving persistence or card preparation off the main actor (039 measured ~2 ms
  card preparation and ~10 ms persistence; neither is the bottleneck).

## Design / approach

Three independent changes, each its own commit, in this order.

### 1. Defer the inspector one beat behind the List

`MacLibraryInspector` keeps `shownIDs`, the selection it shows, and updates it
from `selection.ids` in a `.task(id: selection.ids)`. When the inspector already
shows something and the new selection is non-empty, the task sleeps ~20 ms first;
a newer selection cancels it. An empty selection, or the first selection after an
empty one, applies at once. Content, the selected entry, the batch panel's
entries, and detail-session synchronization read `shownIDs`; `lastSingleID`, the
poster flight, and the anchor keep following the live selection.

File: `MyAnimeList/Sources/Mac/MacLibraryInspector.swift`.

### 2. Sidebar counts from the display cache

`LibraryBrowseScope` already keeps a `LibraryDisplayOrderInputs` per library entry
(040). Its `passingFilterIDs`, `isDropped`, and `categoryIDs` are what the counts
need. The scope computes a `LibraryDisplayCounts` from those cached inputs when it
assembles the display, stores it in `LibraryDisplayCache`, and exposes it as
`displayCounts`. `MacLibrarySidebar` reads that instead of iterating models. The
sidebar's body still re-evaluates when the display does, but no longer reads 800
models; counts update through the same per-entry registrations as the rows.

Files: `MyAnimeList/Sources/ViewModels/Library/LibraryBrowseScope.swift`,
`MyAnimeList/Sources/Views/Library/LibraryEntrySnapshot.swift`,
`MyAnimeList/Sources/Mac/MacLibrarySidebar.swift`.

### 3. Keep the Mac inspector's views across entries

On macOS, `EntryDetailView` drops the page-wide `.id(session.instanceID)`, so
SwiftUI updates the existing tree instead of rebuilding it. In its place:

- **No animation on a switch.** A `.transaction(value: session.instanceID)` sets
  `disablesAnimations` and clears the animation, so implicit `.animation(_:value:)`
  modifiers inside do not fire when the entry changes. Edits within one entry
  keep animating.
- **Scroll to top on a switch.** On macOS a new session's `ScrollPosition` starts
  at `.top`, since it no longer arrives with a fresh scroll view.
- **Per-entry state boundaries where state is per entry, not per interaction:**
  - The episodes block needs no new boundary: its `ForEach` rows are keyed by
    TMDb season and episode IDs, which differ between entries, so each entry's
    season loaders, preview models, and expansion state are new views.
    (Corrected 2026-11-10; the first draft gave the block an `.id`.)
  - `EntryEpisodeProgressControl` already has `.id(entry.libraryIdentity.rawID)`.
  - `EntryNotesSection` in the Mac tracking card gets `.id(entry.libraryIdentity)`.
    Its own `onChange(of: entry.libraryIdentity)` reset runs a frame after the
    switch, outside the switch transaction, so `.animation(.snappy, value:
    selectedScope)` slid the chip highlight and delayed the note text.
    (Corrected 2026-11-10 after the maintainer's recording.)
- **Images change identity with their request.** `KFImageView` keeps `loadState`
  across URL changes, so a reused poster would show the previous entry's image
  for a frame. The Mac header poster and the cinematic hero images get
  `.id(...)` keyed on their image, so the initializer's memory-cache path
  shows the new image in the switch frame.

Interaction-only state stays as is, for example star hover, date popover
`isEditing`, and the production-companies popover. A popover is transient
and closes when the pointer selects another row. Sheets are window-modal on the Mac.

The existing `.onChange(of: session.instanceID)` already cancels a conversion
task. `.onChange(of: session.entry.supportsEpisodeNotes)` can now fire across
entries; it then assigns the new session's own unedited baseline, which is a
no-op.

Files: `MyAnimeList/Sources/Views/Library/EntryDetail/EntryDetailView.swift`,
`MyAnimeList/Sources/Models/Library/EntryDetailSession.swift`,
`MyAnimeList/Sources/Mac/MacEntryDetailHeader.swift`,
`MyAnimeList/Sources/Views/Library/EntryDetail/EntryDetailHeaderComponents.swift`.

## Alternatives & decisions

| Choice | Reason and alternative |
| --- | --- |
| Defer by a short sleep, not a debounce | 021.002 rejected a keyboard debounce because it delays feedback. Here the List highlight stays immediate and only the inspector trails. A run-loop hop (`DispatchQueue.main.async`) may run before the display flush, because a pending main-queue message can skip the before-waiting observers; the sleep was measured to work in the throwaway build. The ~20 ms value is empirical. |
| Data loading off-main | Rejected: the app's data work is ~2% of busy samples, and the models are main-context SwiftData objects. |
| Counts from cached inputs over a separate count cache | The inputs and their per-entry registrations already exist (040); another set of model registrations would duplicate them. |
| Drop `.id` on the Mac only | iOS keeps the cross-fade from `4a42031` and its host-migration behavior; the Mac swaps instantly (024). |
| Section-level `.id` boundaries over auditing every `@State` | Gives the per-entry sections a clean state reset while the heavy, stateless parts (header, stat grid, overview, cast and staff) stay alive. Putting `.id` on the tracking card would rebuild its native controls each switch. |
| Suppress animations by transaction | Removing each `.animation(_:value:)` would lose in-entry animations; the transaction targets only the switch update. |

## Validation and acceptance criteria

- `make build-mac` after each change.
- `make test-app-mac` for the suites that cover display and sessions:
  `LibrarySortingAndDeletionTests` (extended with a counts check) and
  `EntryDetailSessionTests`.
- `make test-app-sim` on a booted simulator if one is booted, for the shared
  `LibraryBrowseScope` change.
- Maintainer, with `make run-mac`: List selection with the inspector open,
  single presses and key repeat, compared with the inspector closed; no
  animation, old poster, or carried scroll position on a switch; notes,
  episodes, and episode progress show the new entry's state; sidebar counts
  correct after status, favorite, and category changes.

## Amendments

- Updated 2026-11-10: the episodes block keeps no extra `.id`, and the scroll reset lives in the session's initial `ScrollPosition`; corrected in place under Design §3.
- Updated 2026-11-10: the Mac notes section gets an entry-scoped `.id`, after a recording showed its scope reset animating on a switch; corrected in place under Design §3.
