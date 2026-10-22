# 031.005 — Native inspector adaptation on iPhone Duo

## Context

After slice 1, the maintainer reported that with detail open, the inspector closed and then
reopened on every fold or unfold. A Codex investigation (session
`01a16447-1833-74a1-b859-a55e05a6bbe6`, transcript kept outside the repository) found the cause
and tested SwiftUI's native behavior:

- AniShelf's host migration from 005 caused the close-then-reopen. On a size-class change it
  retired the outgoing sheet or inspector, waited for it to disappear (slice 1), then presented
  a new host.
- A standalone app with one native `.inspector` and no migration adapted on its own on the Duo
  simulator (iOS 27.1 SDK). It became a sheet on the cover and a column on the inner display,
  without unmounting its content. This held for three fold cycles in a row, opened on the inner
  display.
- On iPad (iPadOS 27.0), narrowing the window did **not** reliably bring the native inspector
  back as a sheet, as the maintainer confirmed by hand. So iPad keeps the app's own migration.

## Change

- `LibraryEntryDetailHostPolicy` gains `adaptsInspectorNatively`. When it is true, the host stays
  `.inspector` even at compact width, so folding never triggers a host migration and SwiftUI
  presents the same inspector as a sheet on the cover. Detail activation still follows width:
  compact uses the tap preference, regular uses a single tap. `LibraryView` keeps compact
  activation for a natively adapted inspector.
- `LibraryDetailHostCoordination` turns on native adaptation the first time the scene reports a
  vertical bar (`toolbarVerticalEdge != nil`), and **keeps it on** for the scene. Unfolding briefly
  reports no vertical bar while the width is still compact. Following that would choose the sheet
  host, start a migration, and dismiss the inspector while UIKit is moving its sheet controller
  back into the column. Runtime evidence: an uncaught `UIViewControllerHierarchyInconsistency`,
  "trying to add child view controller that is already presented:
  `PresentationHostingController`". Without the latch, a launch-restored inspector crashed 4 of 5
  times on fold then unfold. With it, it passed 9 of 9. iPad and other iPhones never report a
  vertical bar, so their policy is unchanged.
- During the transition to a sheet, a natively adapting inspector reports a binding `false`
  followed by `true`. `syncInspectorColumn` now acts on a system `false` only after it has
  lasted 400 ms (the delay is chosen, not documented). It then closes the detail if the
  presentation is still current. The 002 handling that releases a restored column with no
  detail is kept, and covers Codex's observed stale restore after Done on the cover.

The slice 1 staging and the sheet gate stay in place for iPad and iPhone Pro Max rotation, where
the policy still migrates hosts.

Rejected or not pursued:

- Native adaptation on every platform. iPad window resizing doesn't re-present the inspector
  reliably.
- Deciding by device idiom. Plain iPhones would have changed from the app's sheet to an inspector
  sheet.
- Following `toolbarVerticalEdge` live. That caused the crash above.

Bisection before the cause was found: removing the sibling `.sheet`, the inspector's
`.presentationBackground`, or the action overlays one at a time did not stop the crash. The probe
attaches its inspector the same way AniShelf does.

## Refs

- `MyAnimeList/Sources/Views/Library/LibraryEntryInteractionState.swift`
- `MyAnimeList/Sources/Views/Library/LibraryDetailHostCoordination.swift`
- `MyAnimeList/Sources/Views/Library/LibraryView.swift`
- `MyAnimeList/Tests/MyAnimeListTests/LibraryEntryInteractionStateTests.swift`
- Related: [005-adaptive-library](../005-adaptive-library/000-plan.md)

## Validation (2026-10-23)

- iPhone Duo simulator, iOS 27.1, with the final build (temporary logging removed):
  - Detail restored into the column at launch, then fold and unfold: 3 of 3 passed. The
    instrumented build before cleanup passed 6 of 6.
  - Fold cycles in one session: 5 passed. Logging showed one content appearance and no
    disappearance or presentation change across three cycles, so the close-then-reopen is gone.
  - Done on the cover, then unfold: no stale column.
  - Detail opened on the cover, then unfold, then another fold cycle: the inspector kept its
    content.
  - Swiping the cover sheet down closed the detail, and unfolding showed no column.
- iPad Pro 13-inch simulator, iPadOS 27.0 (already booted by Codex): the inspector column opened
  on a single tap and closed with Done, as before. Narrowing the window was not tested.
- `make test-app-sim APP_TEST_ONLY='MyAnimeListTests/LibraryEntryInteractionStateTests MyAnimeListTests/EntryDetailSessionTests'`
  on the Duo passed, including the new policy test. Targeted `swift format lint` is clean.

Unverified: Split View multitasking on the Duo's inner display, which narrows the window like iPad
and might share iPad's unreliable re-presentation; iPhone Pro Max rotation (no simulator); and
physical hardware.
