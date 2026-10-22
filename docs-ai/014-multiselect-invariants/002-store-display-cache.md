# 014.002 — Selection snapshot replaced by the store display cache

## Context

The view-held selection snapshot (mechanism 1 of the plan) only covered iOS
multi-selection, kept a hand-maintained list of store inputs in a view modifier,
and was removed by refactors twice.

## Change

[023-library-display-cache](../023-library-display-cache/000-plan.md) moves the
memoization into `LibraryStore`, invalidated by observation tracking, and deletes
`selectionDisplayItems`, `selectionLayoutIDs`, and `selectionEntriesByID`. The
invariant becomes: views read `store.libraryDisplayItems` and must not
reintroduce a computed, uncached display list. The `GestureMask` invariant
(mechanism 2) is unchanged.

## Refs

See [023 action record](../023-library-display-cache/001-action.md).
