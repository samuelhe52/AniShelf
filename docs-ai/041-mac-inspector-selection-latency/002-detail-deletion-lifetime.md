# 041.002 — Keep deleted models out of detail layout

## Context

A TestFlight report for 1.107.0 (18) on macOS 27.3 beta 2 shows a SwiftData assertion inside SwiftUI scroll layout while a delete confirmation was dismissing. The summary has no symbolicated AniShelf frame, and the local dSYMs are from different builds.

The delayed selection (`shownIDs`) could still name the removed row, the old session stayed available until the next `onChange`, and a scroll content builder could outlive its parent's update. The local reproduction below confirmed a stale read during sheet dismissal.

## Change

- The inspector shows a session only when its entry is the selected display item's exact model, not just the same identity. Session synchronization no longer falls back to `existingEntry(identity:)`, so an entry missing from the displayed rows gets no session.
- `EntryDetailSession.canRenderEntry` checks both `isDeleted` and context attachment. A disk-backed SwiftData probe (not retained) showed `isDeleted` true after `delete`, then false once `save` detached the object. Sessions created for detached entries, such as previews, still render.
- The shared detail page and the episode-note chip scroller repeat the check inside their scroll content, because a check in the parent cannot protect a retained builder. The notes section also requires its entry to be the session's entry.

Delete timing, fault prefetching, and the per-entry display cache were left alone: the report does not implicate any of them. Keyboard selection deferral is unchanged.

The action record's `selectedEntry` description was corrected in place.

## Verification

On macOS 27.2.1, a temporary harness mounted AniShelf's inspector, confirmed each deletion through the native sheet, and checked that the sheet closed, the selection cleared, and the entry was gone. Each launch used a disposable disk-backed library with 12 generated entries.

| Build | Fresh launches | Deletion result |
| --- | ---: | --- |
| Before the fix (`1016211d`) | 5 | The first deletion crashed on every launch. |
| With the fix (pre-commit working copy) | 5 | All 60 deletions completed without a crash. |

All five local crash reports show the inspector's Open In controls reading `AnimeEntry.nameTranslations` after SwiftData detached the entry. The stack passes through the detail scroll builder and `-[NSSheetMoveHelper closeSheet]`. The implementation session `01a20bb1-e106-7198-9b00-01ba2ae4ffa6` records the run and a representative stack.

The original focused macOS test run passed 29 tests. It included the since-removed deletion test, whose post-delete sizing check created a fresh hosting controller. The outer detail guard returned an empty view before the retained scroll content could run, so the check could pass with the nested guards removed. The original generic iOS build also passed.

## Open questions

- The original TestFlight report remains unsymbolicated. The before-and-after run used macOS 27.2.1, and the reporter's macOS 27.3 beta 2 build was not rerun. The shared guards were built for iOS, and iOS deletion behavior remains unverified.

## Refs

- `MyAnimeList/Sources/Mac/MacLibraryInspector.swift`
- `MyAnimeList/Sources/Models/Library/EntryDetailSession.swift`
- `MyAnimeList/Sources/Views/Library/EntryDetail/EntryDetailView.swift`
- `MyAnimeList/Sources/Views/Library/EntryDetail/EntryNotesSection.swift`
