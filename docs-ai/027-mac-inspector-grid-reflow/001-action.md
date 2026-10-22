# 027 — Mac inspector grid reflow: Action record

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-10-17 | Inspected the maintainer's recording and compared Mac/iPad source. Opening showed 5 → 4 → 3 columns; closing showed 3 → 4 → 5. | Source baseline `0d4d785` |
| 2026-10-17 | Instrumented both actual app grids and ran a 100-entry generated library on Mac and an explicitly authorized iPad simulator. | Temporary, uncommitted probes |
| 2026-10-17 | Repeated opening without the diagnostic layout wrapper on both platforms; disabled Mac keyboard column-state writes for another opening/closing pair. | Controls below |
| 2026-10-17 | Removed all diagnostic source changes, verified the working tree was clean, and stopped the diagnostic apps. | No production fix or commit |
| 2026-10-17 | Created this new record at the maintainer's request and corrected entry 021's overly broad attribution of jitter to shared behavior. | Retrospective diagnosis; prospective fix plan |
| 2026-10-17 | Rejected and removed width retargeting; implemented measured endpoint layout with a separate native scroll viewport. Maintainer accepted motion and both resize paths. | [003](003-reject-width-retargeting.md), [004](004-endpoint-transition.md) |

## Outcome and current state (as of 2026-10-17)

**Implemented and manually accepted:** [004](004-endpoint-transition.md) supplies
one destination grid layout per inspector toggle while preserving native viewport
motion and live resizing. The candidate in [002](002-width-driven-animation.md)
was rejected and removed in [003](003-reject-width-retargeting.md). The baseline runtime evidence supports a
platform host/layout-delivery difference. It does not identify a specific private
framework implementation or establish that every Mac/iPad configuration behaves
the same way.

At the diagnosis baseline, the grids were separate implementations with similar
animation code. Amendment 002 tested width-driven animation on Mac; amendment 003 removed it:

| Source | Layout |
| --- | --- |
| `MyAnimeList/Sources/Mac/MacLibraryGrid.swift` | Adaptive widths 132–168 pt, column spacing 18 pt; geometry-observed column count is used for keyboard navigation. |
| `MyAnimeList/Sources/Views/Library/LibraryGridView.swift` | Adaptive widths 104–132 pt, column spacing 10 pt. |
| Both | Row spacing 16 pt, per-card `.geometryGroup()`, and `.transaction(value: isInspectorPresented)` assigning `.smooth(duration: 0.3)`. |
| `MyAnimeList/Sources/Views/Library/LibraryGridItem.swift` | Shared card rendering, including a 2:3 poster aspect ratio. |

### Method and environment

- Baseline: `0d4d785` (`fix: Modernize Mac category and reminder sheets`, dated
  2026-10-17). Debug builds, 100 generated entries on each platform.
- Native Mac: macOS 27.0.1, build 26A434.
- Simulator: iPad Pro 13-inch (M5), iPadOS 27.0. No physical-device run.
- Grid size observations recorded width and height without writing geometry back
  into layout state. Column counts were derived from width and grid parameters.
- A forwarding `Layout` around the first card recorded `sizeThatFits` proposals
  and `placeSubviews` placements. A transaction probe inside the grid's scoped
  animation recorded the card transaction; an outer probe recorded incoming grid
  transactions. The distinction matters: an outer nil transaction alone does
  not establish what animation reaches the card.
- Startup sizing was excluded. Consecutive equal widths were collapsed, including
  observations where only the lazy grid's estimated height changed.
- Local raw logs, instrumentation, builds, and the recording are not retained as
  repository evidence. The measured results are preserved below; do not depend on
  ignored build artifacts surviving cleanup.

### Measured results

| Run | Direction | Grid width endpoints | Width changes | Column sequence | Card transaction during resized placements |
| --- | --- | --- | --- | --- | --- |
| Mac, full probes | Open | 852 → 452 pt | 14 | 5 → 4 → 3 | `animation=nil`, `disablesAnimations=false` |
| Mac, full probes | Close | 452 → 852 pt | 15 | 3 → 4 → 5 | `animation=nil`, `disablesAnimations=false` |
| iPad, full probes | Open | 1004 → 524 pt | 1 | 8 → 4 | Smooth spring, response 0.3, damping fraction 1.0 |
| iPad, full probes | Close | 524 → 1004 pt | 1 | 4 → 8 | Same smooth spring |
| Mac, no diagnostic layout wrapper | Open | 852 → 452 pt | 14 | 5 → 4 → 3 | Card transaction probe absent |
| iPad, no diagnostic layout wrapper | Open | 1004 → 524 pt | 1 | 8 → 4 | Card transaction probe absent |
| Mac, no wrapper and no keyboard column-state writes | Close | 452 → 852 pt | 13 | 3 → 4 → 5 | Card transaction probe absent |
| Mac, no wrapper and no keyboard column-state writes | Open | 852 → 452 pt | 18 | 5 → 4 → 3 | Card transaction probe absent |

These counts describe individual runs, not a timing guarantee or performance
comparison. Different endpoint counts reflect platform sizing and window widths.

The full-probe Mac opening width sequence was:

```text
852 → 850 → 837 → 775 → 746 → 687 → 608 → 568
    → 523 → 501 → 488 → 478 → 469 → 455 → 452 pt
```

The first card was actually measured and placed at intermediate widths. For
example, its proposed width changed from 134.8 to 158.25 pt when the grid went
from five to four columns, then from 138.5 to 168 pt when it went from four to
three. This explains the shrink/enlarge pattern and associated row-height changes.
The iPad card changed directly from a 116.75 pt proposal to 123.5 pt when opening,
and directly back when closing, with the smooth animation on each destination
placement update.

**Interpretation:** Mac's native inspector transition produces repeated layout
updates that do not retain the grid's visibility-scoped animation. On iPad, the
destination layout receives that animation. The adaptive grid therefore exposes
successive discontinuous arrangements on Mac. This is stronger evidence than
screen-coordinate motion alone, but is not an identical-view-hierarchy minimal
framework reproduction. The extra Mac keyboard-state write is not necessary for
the observed repeated layouts; disabling it did not remove them.

## Deviations from plan

The investigation preceded this record. The plan is explicitly retrospective
about diagnosis and prospective about a fix. No destination-width coordinator,
column locking, hysteresis, spring change, or production workaround was included in the diagnosis. The subsequent
width-driven animation candidate is recorded in amendment 002.

## Validation

Final probe-free validation: `make run-mac` with a 100-entry grid fixture and
English locale completed successfully on 2026-10-17 after diagnostic removal.
`git diff --check` passed, and a source search found no remaining temporary grid
or native endpoint probes. No unit-test suite was run for this Mac-only view
change. The final build preserves the motion the maintainer accepted.

The following list records the original diagnosis. Final implementation evidence
and maintainer acceptance are in [004](004-endpoint-transition.md).

- `make run-mac` with `MAC_LAUNCH_ARGS` enabling `-library-fixture 100`, grid style,
  English locale, and temporary `-trace-grid-layout`: build and launch succeeded;
  inspector toolbar opening and closing were exercised.
- `make run-sim BOOTED_SIMULATOR_ID=0CADC51E-0627-4D94-9679-1146FA05FFAA`
  with equivalent `DEVICE_PROCESS_LAUNCH_ARGS`: build and launch succeeded;
  opening a card and dismissing with Done were exercised.
- Existing binaries were relaunched with temporary
  `-trace-grid-no-layout-probe` for the wrapper controls. A further
  `make run-mac` build/launch with `-trace-grid-no-column-state` succeeded for
  the keyboard-state control. These diagnostic switches were removed with the
  temporary source and are not supported by the current app.
- Builds emitted the App Intents metadata warning that extraction was skipped
  because no AppIntents framework dependency was found; none failed.
- The fixture inspector's remote metadata request showed an invalid placeholder
  API-key error. This run validated layout delivery, not successful remote detail
  loading. The fixture library and generated posters remained available.
- Simulator UI lookup under the old Simulator bundle identifier failed; the
  working interface was Device Hub. A post-quit accessibility read also failed
  because the Mac app had exited. Neither was a product failure.
- No unit tests, benchmark suite, or physical-device validation were run.
- Source restoration matched the pre-instrumentation copies, `git diff
  --exit-code` passed, and `git status --short` was empty at investigation cleanup.
  Diagnostic binaries were built, but the restored source was not rebuilt during
  cleanup. Both diagnostic app processes were stopped; the iPad simulator was
  left booted.

## Open questions

- Which native host/framework behavior supplies the intermediate Mac widths?
  A controlled reproduction with identical view hierarchy is still needed to
  attribute the difference to a particular framework implementation.
- The final implementation obtains the endpoint from inspector content width.
  Dedicated rapid-reversal coverage remains open; see amendment 004.
- How much do scroll-offset adjustment and lazy-grid height estimation contribute
  to the vertical component of the original recording's jitter?
- Physical iPad behavior and other OS versions remain unverified. Follow-up Mac
  coverage limits are recorded in 004; amendment 002 describes a rejected candidate.
