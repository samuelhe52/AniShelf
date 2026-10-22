# 031 — iPhone Duo adaptation: Action record

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-10-22 | Codex implemented the whole plan in one pass. The maintainer discarded it with a hard reset: it restyled the toolbar on every device, used custom bars while the inspector was open, and hid gallery dates on every device. | Reflog `9c69f26`..`163dc19` |
| 2026-10-22 | Released the empty inspector column. Staged sheet↔inspector migration on the outgoing host's disappearance (Codex slice 1, reviewed by Claude Code). | `76f6012`, [002](002-empty-inspector-column.md), [003](003-native-host-migration.md) |
| 2026-10-22 | Hybrid toolbar for vertical bars, chosen after an all-vertical first version was rejected. | `64dffeb`, [004](004-vertical-library-toolbar.md) |
| 2026-10-22 | Fixes from the maintainer's visual pass: the profile count on one line and the detail hero under the vertical bar. | `5ff92f7`, `ddfe075` |
| 2026-10-23 | The native inspector carries detail across Duo folds, replacing the close-then-reopen migration there. | `b5cad7f`, [005](005-native-inspector-adaptation.md) |
| 2026-10-23 | Gallery shelf dates fall back to a numeric format when the long format would wrap. | `3b15562` |

From slice 2 onward, Claude Code implemented the slices directly. Codex contributed slice 1 and the
investigation behind 005.

## Outcome and current state (as of 2026-10-23)

On iPhone Duo:

- **Detail.** The detail inspector is a native inspector in every pose. SwiftUI shows it as a
  sheet on the cover and a column on the inner display, keeping its content across folds and
  Split View changes. iPad and other iPhones keep the 005 sheet↔inspector migration, now staged on
  disappearance.
- **Toolbar.** Where the system places a vertical bar, the library header (count/category,
  Select, profile) stays horizontal. The bottom controls move into the vertical bar as symbols, and
  selection actions use the system overflow menu. The leftover horizontal header minimizes on
  scroll down, which is the system's automatic behavior and was kept deliberately.
- **Layout.** The detail hero artwork extends under the vertical bar. The profile count shrinks
  rather than wrapping beside the cover's bar. Gallery shelf dates switch to a numeric format
  only when the long format would wrap.

Other devices look as they did before this entry. The horizontal toolbar code is
source-identical, and every Duo-specific change is gated on a vertical bar or on a layout that
does not fit.

Key source files:

- `MyAnimeList/Sources/Views/Library/LibraryView.swift`
- `MyAnimeList/Sources/Views/Library/LibraryDetailHostCoordination.swift`
- `MyAnimeList/Sources/Views/Library/LibraryEntryInteractionState.swift`
- `MyAnimeList/Sources/Views/Library/LibraryToolbar.swift`
- `MyAnimeList/Sources/Views/Library/LibraryBrowseSummaryMenu.swift`
- `MyAnimeList/Sources/Views/Library/EntryDetail/EntryDetailHeaderComponents.swift`
- `MyAnimeList/Sources/Views/Library/LibraryProfileSettings/LibraryProfileSettingsSections.swift`
- `MyAnimeList/Sources/Views/Gadgets/AnimeEntryDates.swift`

## Deviations from plan

- **Empty inspector (P1).** None of the three candidate causes was the trigger. SwiftUI's own
  writes to the inspector binding during size-class changes caused it (002). On the Duo, the host
  migration was later replaced by native adaptation (005). This corrects the plan's non-goal of
  leaving the 005 host policy unchanged.
- **Toolbar (P1).** No single item kept the bar horizontal. The final design keeps the text header
  horizontal on purpose, following Apple's guidance that meaningful text stays horizontal (004).
- **Search beside the detail pane (P2).** Accepted by the maintainer as "a bit strange but
  acceptable". Apple's rule that only containers along the display edge get vertical bars means
  the library's bars stay horizontal while the inspector is open.
- **Grid columns crossing the fold (P2).** Dismissed by the maintainer as not a problem. No
  fold-aware grid was implemented.
- **Cover gallery date pill under the camera column (P2).** The maintainer judged it acceptable
  as it is, despite Apple's guidance. Not changed.
- **Gallery density (P3).** With the bottom bar moved into the vertical bar, inner landscape
  already reaches the multi-card shelf, so the shelf policy is unchanged. The narrow shelf exposed
  date wrapping, which `3b15562` fixes.
- **Sheet Done (P3).** Dropped. Apple's guidance accepts text-only Done staying horizontal.
- **Unplanned fixes from the visual pass:** the detail hero extension and the profile count.

## Validation

Recorded per slice in 002–005. Summary:

- **Duo simulator.** Runs used the iPhone Duo simulator (iOS 27.1, `sim-use`), plus Device Hub
  window captures where sim-use returned black cover screenshots. Fold paths were checked in
  gallery, grid, and list: open, closed, Done on the cover, opening on the cover, and swipe-down to
  close. Toolbars were checked on the cover, in inner landscape, and in inner portrait, in browse
  and selection modes.
- **Hero, count, dates.** The hero extension and the profile count were checked on the cover and
  inner display. The date fallback was checked in the inner-landscape shelf (numeric), and on the
  cover and in inner portrait (long format unchanged).
- **Native adaptation.** The launch-restore crash went from 4 failures in 5 runs to 9 passes in
  9. The inspector never remounted across fold cycles.
- **Split View (maintainer, by hand, 2026-10-23).** Opening detail in Split View, entering Split
  View with detail open, leaving it, closing detail before leaving, and folding in Split View all
  worked.
- **iPad.** iPad Pro simulator (iPadOS 27.0): the inspector opens with a single tap and closes
  with Done. The maintainer tested narrowing the window with detail open on 2026-10-23, and the
  app's own migration worked.
- **Tests.** Focused `LibraryEntryInteractionStateTests` and `EntryDetailSessionTests` passed
  after each host change, including the new policy test. Targeted `swift format lint` was clean.

## Open questions

- Physical iPhone Duo hardware was not tested. All Duo evidence comes from the iOS 27.1
  simulator.
- iPhone Pro Max rotation was not tested (no simulator). Its policy path is unchanged.
- The 400 ms settle delay for native inspector dismissals (005) and the latching of native
  adaptation once a scene has a vertical bar both depend on observed iOS 27.1 timing and behavior,
  not on documented guarantees.
