# 031.002 — Empty inspector column (P1 slice)

## Context

First slice of the 031 plan: the empty trailing column on the inner display after a
cover→inner transition. Following the plan, temporary `os.Logger` output was added to
`LibraryView` (render state, inspector and sheet binding writes) before any fix, then
removed once the cause was identified.

## Change

### Root cause (runtime evidence, 2026-10-22)

Logged on the iPhone Duo simulator (iOS 27.1), with detail open and the fold toggled.
None of the three candidate causes in the plan was the trigger. The column comes from
SwiftUI writing to the inspector's `isPresented` binding by itself during a size-class
change:

- **Unfold with the detail sheet open.** The host moved sheet→inspector while the sheet
  was still animating away. SwiftUI then wrote the inspector binding `true`, `false`,
  `true` within ~110 ms. The `false` reached `detailHostDidDismiss`, which closed the
  detail, because host and desired host already matched. The later `true` was ignored
  by the old setter. The getter returned `false`, yet the column stayed, empty. The
  sheet's own dismissal callback arrived ~1 s later.
- **Fold closed with the inspector open** (seen in a separate run). SwiftUI wrote `false`
  before `horizontalSizeClass` reached `LibraryView`, so the detail closed instead of
  migrating to a sheet. On the next unfold, SwiftUI wrote `true` and restored the
  remembered column with no detail behind it.

In both runs the binding getter was `false` while the column stayed on screen. SwiftUI
does not re-apply a getter value that has not changed, so a derived getter could not
remove the column.

### Fix (`MyAnimeList/Sources/Views/Library/LibraryView.swift`)

- The inspector binding now reads local `@State isInspectorColumnPresented`. It is synced
  from the gated inspector presentation on change, and records system writes.
- The inspector stays dormant while a detail sheet is still on screen
  (`isDetailSheetOnScreen`, set by the sheet content's `onAppear`/`onDisappear`). The
  inspector is presented only after the outgoing sheet has gone.
- `syncInspectorColumn` handles a system write on the next main-actor turn. A dismissal
  that is still current after the size-class update closes the detail, as before.
  Otherwise the column is set to follow the detail host, which releases a restored empty
  column and re-presents a column that a new inspector presentation needs.

Rejected or not pursued:

- Patching `LibraryEntryInteractionState` (the dormant path) or
  `LibraryDetailHostCoordination` session sync. The logs showed both behaving correctly;
  the faulty part was the view-to-SwiftUI binding. The model is unchanged, so the plan's
  conditional unit test does not apply.
- Ignoring every inspector `false` in regular width. That would also have worked here,
  but it drops the 005 contract that a real inspector dismissal closes the detail.
  Deferring by one turn keeps that contract.

The one-turn deferral relies on the size-class `onChange` running before the next
main-actor turn. That ordering was observed but is not documented by Apple.

## Refs

- Source: `MyAnimeList/Sources/Views/Library/LibraryView.swift`.
- Runtime validation (2026-10-22, iPhone Duo simulator, inner landscape ↔ cover;
  screenshots and logs kept local, not retained). Each style was run through these paths:
  A (inspector open → fold → sheet on cover → unfold → inspector with content),
  B (inspector open → fold → Done on cover → unfold → no column),
  C (nothing open → fold cycle → no column), and
  D (detail opened on cover → unfold → inspector with content).
  - Gallery: A ×4, B, C and D passed on the build before the final `syncInspectorColumn`
    rework.
  - Grid: A ×2 and B passed.
  - List: A ×2 and B passed, then A ×3, B and C on the final build.
- Tests: `make test-app-sim APP_TEST_ONLY='MyAnimeListTests/LibraryEntryInteractionStateTests MyAnimeListTests/EntryDetailSessionTests'`
  passed.
- Not run: iPad sheet/inspector regression on an iPad simulator. Only the Duo simulator
  was booted, and project rules forbid booting another without permission.
