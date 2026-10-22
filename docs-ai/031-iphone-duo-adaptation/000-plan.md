# 031 — iPhone Duo adaptation: Plan

| Field | Value |
| --- | --- |
| Status | In progress |
| Anchor date | 2026-10-22 |
| Origin | Maintainer request on 2026-10-22: check how the app looks on the iPhone Duo simulator against Apple's [Designing for iPhone Duo](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo) HIG page and decide what to optimize. Claude Code and an independent Codex session (thread `01a1634b-e3f0-7e42-a4a7-5059a2aedfb5`) each inspected the running build, then agreed on the problem list below. No code had changed when this plan was written. |
| Related | [005-adaptive-library](../005-adaptive-library/000-plan.md) (sheet/inspector host policy), [028-window-state-ownership](../028-window-state-ownership/000-plan.md) |

## Background

iPhone Duo has a compact cover display and a larger inner display behind a hinge.
On iOS 27.1 the system moves toolbars, tab bars, and the status bar to a vertical
column on the cover display and on the inner display in landscape. Partial folding
adds a reserved folding region across the middle of the inner display.

### Observed state

Observed on 2026-10-22 against `28ae91a` (1.103.0), built with the iOS 27.1
simulator SDK and run on the `iPhone Duo` simulator. These are runtime observations
from `sim-use` outlines, hit tests, and screenshots. Screenshots were kept outside
the repository.

| Pose | Observation |
| --- | --- |
| Cover (466×678 pt) | The library keeps horizontal top and bottom bars. The vertical status/camera column overlaps the neighboring gallery card's date pill. |
| Inner, portrait (669×951 pt) | Horizontal bars, which the HIG expects for this pose. No problem found. |
| Inner, landscape (951×669 pt) | Library bars stay horizontal. After some cover→inner transitions, an empty 364 pt app column appears on the trailing side (`ui --point` hit-tests a childless `Group` at x=587). The library is squeezed into ~587 pt. Tapping a card fills the column with detail, and it widens to ~500 pt. One Codex capture of the same transition did not show the column, so it is intermittent or depends on the path taken. |
| Inner, partially folded (130°) | Codex observed seven grid columns, so the fourth column crosses the fold. |
| Inner, library + detail | Library Search sits at the far trailing edge, next to the detail pane instead of the library pane. |
| Cover, detail sheet | Content stays clear of the camera column. "Done" is text-only and cannot participate in vertical presentation; whether it keeps the entire bar horizontal has not been isolated. |

Already working: folding closed with an inspector open moves the same entry into a
sheet (Codex observation).

## Goals

Agreed problem list, in priority order:

| Priority | Problem | Proposed fix |
| --- | --- | --- |
| P1 | Empty inspector column after unfolding | Present the inspector only when there is a valid host presentation with a resolved detail session; release the column otherwise. Keep the selection across legitimate sheet↔inspector migrations. |
| P1 | Library bars never adapt to the vertical layout | Rework `LibraryToolbar` items so they can go vertical: titled symbols (`Label`), semantic groups instead of the `Color.clear` balancing spacer and manual padding, visibility priorities, and the system overflow menu for the "Actions" ellipsis menu. |
| P2 | Grid columns straddle the fold | Use the reserved-region geometry, leave a gutter at the fold, and prefer an even column count when the grid spans it. Size cards from container space instead of the `isPad` branch in `LibraryGridView`. |
| P2 | Cover: gallery date pill under the status/camera column | Keep readable metadata in usable space; artwork may still run under the edge. Recheck after the toolbar work, since vertical bars may resolve it through safe areas. |
| P2 | Library Search sits beside the detail pane | Keep Search, filter, and view-style controls with the library pane. |
| P3 | Gallery density and sheet Done | After the P1 fix, reassess whether a wide, short container should show a shelf (`minimumShelfHeight` = 480 forces single-page at 669 pt). Give the detail sheet's Done a titled symbol while keeping its save/discard behavior. |

### Non-goals

- Inspector toolbars stay horizontal. Codex reports that Apple keeps inspector
  toolbars horizontal on purpose.
- No custom layout per device pose. The HIG asks for size-class-driven layouts that
  expand, not per-pose redesigns.
- No change to the 005 host policy (sheet in compact width, inspector in regular
  width).

## Design / approach

1. **Empty inspector (P1).** Add logging before changing anything. The presented
   flag comes from `interaction.inspectorPresentation` in `LibraryView`. The column
   content renders only when a detail session also exists. Candidate causes, none
   established yet:
   - the dormant-until-inspector path in `LibraryEntryInteractionState`;
   - session synchronization in `LibraryDetailHostCoordination` running after the
     host flips on a size-class change;
   - SwiftUI keeping a dismissed inspector column.

   Pick the patch after the log identifies which one it is.
2. **Toolbar (P1).** First isolate which items keep the bar horizontal by removing
   candidates one at a time on the cover display. The candidates are the principal
   `LibraryToolbarTitle` capsule, the `.status` `LibraryBrowseSummaryMenu` capsule,
   the "Select" text button, and the clear spacer. Codex cites
   [Preparing your app for iPhone Duo](https://developer.apple.com/documentation/technologyoverviews/preparing-your-app-for-iphone-duo):
   custom toolbar views and text-only items don't take part in the vertical layout.
   Then redesign the items that block it. The library count and category/filter
   state must stay reachable, for example through an icon menu with a badge for an
   active filter.
3. **Grid (P2).** Read the folding reserved region (`ReservedRegion`) in
   `LibraryGridView` and choose the column count from container width and the fold.
4. **Reserved region on the cover (P2).** Re-measure after step 2. Only if overlap
   remains, inset the gallery's metadata pills (`LibraryGalleryView`) using the
   trailing safe area or the reserved region.
5. **Pane ownership (P2).** Move library-scoped toolbar items so they stay with the
   library pane when the inspector is open, within the existing inspector host if
   possible.
6. **P3 items** only after the above, with fresh screenshots.

Key files: `MyAnimeList/Sources/Views/Library/LibraryView.swift`,
`MyAnimeList/Sources/Views/Library/LibraryDetailHostCoordination.swift`,
`MyAnimeList/Sources/Views/Library/LibraryEntryInteractionState.swift`,
`MyAnimeList/Sources/Views/Library/LibraryToolbar.swift`,
`MyAnimeList/Sources/Views/Library/LibraryGridView.swift`,
`MyAnimeList/Sources/Views/Library/LibraryGalleryView.swift`,
`MyAnimeList/Sources/Models/Library/LibraryGalleryLayoutPolicy.swift`.

## Alternatives & decisions

| Choice | Reason and alternative |
| --- | --- |
| Treat the wide-gallery "one small poster" as a P1 host bug first | Codex first read it as a gallery density problem. Claude's hit test showed an empty inspector column squeezing the library, and Codex's later capture agreed. Density is kept as a separate P3, to be judged only on correct geometry. |
| Isolate toolbar blockers before redesigning | The listed items are suspects, not proven causes. A text-only item can't go vertical, but that alone doesn't prove it keeps the whole bar horizontal. |
| Don't commit to `NavigationSplitView` | Codex initially suggested prototyping it for library→detail. 005 rejected a permanent split view because it constrains every browsing mode and changes compact navigation. That still holds unless the existing inspector host can't keep library controls with their pane. |
| Even grid columns across the fold | HIG guidance for grid layouts during folding. |
| Leave the cover gallery's full-bleed carousel | Peeking neighbor cards are intentional. Only readable metadata needs to avoid the camera column. |

## Validation and acceptance criteria

- Run on the iPhone Duo simulator with `make run-sim`, then check each pose with
  `sim-use ios fold closed|open|half` and `sim-use ios rotate`. `fold half` needs a
  sim-use build that supports it; Codex's did, Claude's did not on 2026-10-22.
- Empty inspector: repeat cover→inner transitions from the gallery, grid, and list
  styles, with and without a previously inspected entry. No childless trailing
  column may appear. Add a focused test in `MyAnimeList/Tests/` for the host-state
  rule if the fix lands in `LibraryEntryInteractionState`.
- Toolbar: library controls appear in the vertical column on the cover and inner
  landscape, and stay horizontal in inner portrait. All actions remain reachable,
  including through overflow.
- Grid: at 130° no card crosses the fold, and the column count is even.
- Cover: no readable text under the status/camera column.
- Regression: iPad sheet/inspector behavior from 005 is unchanged, and `make test-sim`
  is relevant for the host-policy change.

## Amendments

- Implementation and incremental local commits authorized by the maintainer on 2026-10-22. Pushes remain outside scope. The existing plan and index were present before implementation began.
- Updated 2026-10-22: P1 empty inspector column fixed. The cause was SwiftUI writing to the inspector binding during size-class changes, not any of the three listed candidates — see [002-empty-inspector-column.md](002-empty-inspector-column.md)
- Updated 2026-10-22: The remaining work is split into slices. Codex implements each slice and does the first sim-use validation; Claude Code reviews it and re-verifies on the simulator. Maintainer constraint for every slice: **other devices' appearance must not change.** Duo-specific presentation applies only where the system requests vertical bars (`toolbarVerticalEdge != nil`) or where Duo geometry exists (reserved regions). Everywhere else, rendering stays identical to `28ae91a`, including iPhone, iPad, and Duo inner portrait. An earlier Codex attempt (`9c69f26`..`163dc19`, discarded with a hard reset) restyled the toolbar globally, replaced the native toolbar with custom bars while the inspector was open, and hid gallery date pills on every device. Slice order:
  1. Stage sheet↔inspector host migration on the outgoing host's disappearance, on top of 002. Keep 002's deferred dismissal handling. A lost disappearance callback must not block opening detail.
  2. Toolbar items that can join the vertical bar (P1).
  3. Library controls stay with the library pane while the inspector is open (P2), using native toolbar items rather than custom bars.
  4. Grid fold gutter, and cover date pills kept out from under the camera column (P2).
  5. P3, reassessed with fresh screenshots.
- Updated 2026-10-22: Slice 1 stages native host migration on disappearance, preserves 002's deferred inspector handling, and adds bounded recovery for a lost callback — see [003-native-host-migration.md](003-native-host-migration.md). Duo first-pass validation is complete; Claude Code review remains. Slice 2 has not started.
