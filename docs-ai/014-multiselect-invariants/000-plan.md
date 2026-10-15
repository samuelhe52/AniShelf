# 014 — Library multi-selection rendering invariants: Plan

| Field | Value |
| --- | --- |
| Status | Implemented |
| Anchor date | 2026-06-20 |
| Origin | Retrospective reconstruction on 2026-10-07; not a plan written before implementation |
| Related | [Adaptive library](../005-adaptive-library/000-plan.md) |

## Background

Library multi-selection (added in `789ae36`) became laggy as libraries grew:
toggling one selection, or dismissing selection mode, hitched the main thread. In
list edit mode, rows also stopped responding to whole-row taps, so only the
selection handles worked. Both fixes depend on structure that looks redundant at
the call site. Simplification refactors have removed one of them twice.

## Goals

- Toggling a selection must not recompute the library's filter/sort/snapshot pipeline.
- Native `List(selection:)` edit mode must receive whole-row taps.
- Row-level tap behavior outside selection (inspector focus, double-tap detail) must keep working.

## Design / approach

1. **Selection snapshot.** `LibraryStore.libraryDisplayItems` is computed: every
   access re-runs filtering, sorting, and `LibraryEntrySnapshot` construction for
   the whole library. When multi-selection begins, `LibraryView` captures
   `selectionDisplayItems` and `selectionEntriesByID`. It refreshes them only on
   library revision and display-criteria changes. Selection rendering and actions
   read the snapshot, never the live store.
2. **Gesture masking.** List rows keep their tap gestures but pass a
   `GestureMask` (`tapGestureMask`): `.all` normally, `.subviews` during
   multi-selection. This lets UIKit's cell-selection touches through without
   removing or swapping gesture wrappers.

## Alternatives & decisions

| Choice | Reason and alternative |
| --- | --- |
| Snapshot instead of reading the store per render | A live read is simpler and is what refactors keep restoring, but each selection tap then recomputes the whole library several times. |
| Keep native list selection | `2893549` briefly replaced the `List` selection binding with manual row-tap toggling; `94edc90` restored native selection the same day. |
| Mask gestures rather than remove them | Removing or swapping gesture wrappers changes the recognizer tree and resets row/card-local image state. That reset is why `75e8354` moved to simultaneous gestures. Immediately-recognizing simultaneous taps, however, cancel the cell-selection touches. Masking satisfies both. |

## Evidence and recovered rationale

Rationale comes from prior-discussion memory and the commit messages of `f2a3c36`
and `72fef47`, which state both mechanisms explicitly. Current source still
contains both. Memory associates the first fix with v1.95, but Git tags place
`2893549` and `94edc90` first in `v1.94`; this record follows the tags.

## Validation and acceptance criteria

When a refactor touches `LibraryView`, `LibraryView+MultiSelection.swift`,
`LibraryListView`, or `AnimeEntryListRow`, check that the snapshot and the
gesture mask survive. Symptoms if lost: laggy selection toggles, a glitchy
dismiss animation, and list rows not tappable in edit mode. No automated test
covers either invariant. Verify both at runtime, on a large library, in list
and grid modes.

## Amendments

None yet.
