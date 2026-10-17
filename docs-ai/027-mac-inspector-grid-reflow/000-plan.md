# 027 — Mac inspector grid reflow: Plan

| Field | Value |
| --- | --- |
| Status | Implemented — direct endpoint reflow; maintainer accepted |
| Anchor date | 2026-10-17 |
| Origin | The maintainer requested a new record after the Mac/iPad runtime investigation. Reconstructed on 2026-10-17 from that investigation; this document did not precede the temporary diagnostic instrumentation. |
| Related | [021 — Mac selection and inspector model](../021-mac-selection-model/000-plan.md), [022 — Separate library roots](../022-mac-library-root-split/000-plan.md), [026 — Library fixtures](../026-library-performance-benchmarks/000-plan.md) |

## Background

Opening or closing the Mac inspector makes the poster grid shrink, jump between
row arrangements, and resize again. The maintainer suspected unstable column
counts near adaptive-layout boundaries, then noted that iPad animates directly
between its initial and final arrangements despite using similar grid code.

The [action record](001-action.md) establishes a difference at the platform
host/layout boundary: Mac delivers successive widths and unanimated card-layout
updates; iPad delivers the destination width with the existing smooth animation.
The observed column sequences are monotonic, not repeated oscillation around one
threshold. A specific internal AppKit or UIKit cause has not been isolated.

## Goals

- Preserve the native Mac inspector while making grid reflow continuous.
- Preserve the working iPad transition and each platform's existing card sizes.
- Preserve selection, keyboard row navigation, scrolling, and lazy rendering.
- Use the measured host behavior to guide the fix rather than tuning springs
  against an assumed single animated layout change.

### Non-goals

- Redesign selection, poster loading, or inspector content.
- Change iPad layout policy to accommodate Mac behavior.
- Treat the diagnostic run as a performance benchmark or a completed fix.

## Design / approach

**Required direction:** transition directly between initial and final grid
arrangements during an inspector toggle. Intermediate host widths must not
produce intermediate column-layout animation targets. Ordinary window/divider
resizing must track the pointer without queuing a reflow animation after release.

The width-driven animation experiment in [002](002-width-driven-animation.md)
was rejected by the maintainer and removed. It retained the 5 → 4 → 3 path and
regressed live resizing. [003](003-reject-width-retargeting.md) records the review,
related public reports. [004](004-endpoint-transition.md) records the implemented
endpoint discovery and the maintainer's visual and live-resize acceptance.

The implementation seam is `MyAnimeList/Sources/Mac/MacLibraryGrid.swift` and its
host in `MyAnimeList/Sources/Mac/MacLibraryView.swift`. Inspector presentation is
controlled through `MyAnimeList/Sources/Mac/MacLibraryInspector.swift` and
`MyAnimeList/Sources/Mac/MacLibraryView+Actions.swift`. The inspector's measured content width supplies the destination through per-window
`MacLibraryInspectorLayout` state. The grid ignores the intermediate trailing
safe area for layout, while a separate outer reader preserves the native visible
scroll viewport. Only effective presentation changes animate card placement.
Do not introduce synchronous geometry feedback into ancestor sizing to obtain
that destination; the earlier native-host sizing risks are recorded in
[020.008](../020-native-macos/008-mac-native-ui.md).

The iPad reference is `MyAnimeList/Sources/Views/Library/LibraryGridView.swift`,
hosted by `MyAnimeList/Sources/Views/Library/LibraryView.swift`. Both grids render
`MyAnimeList/Sources/Views/Library/LibraryGridItem.swift`, so card-level changes
require validation on both platforms.

## Alternatives & decisions

| Choice | Reason and alternative |
| --- | --- |
| Investigate the Mac inspector's intermediate widths | Runtime card proposals establish actual repeated layouts, not merely animated presentation geometry. |
| Preserve iPad's existing behavior | It already receives one destination-width change with a 0.3-second smooth card transaction in the measured runs. |
| Do not treat keyboard `columnCount` writes as the root cause | Disabling those writes on Mac preserved intermediate layouts in both directions. |
| Do not select hysteresis or spring tuning as the complete fix | The recorded sequence crosses distinct thresholds once each; later Mac card transactions have no animation. These alternatives were not implemented or exhaustively tested. |
| Reject width-driven retargeting | Maintainer review found intermediate-layout hesitation and broken live resizing. One initial-to-final reflow is required, not a fallback. |

## Evidence and recovered rationale

- **Current discussion:** the maintainer supplied the recording, described the
  smoother iPad behavior, authorized the comparison and iPad simulator boot,
  and then explicitly requested this new record.
- **Verified evidence:** temporary runtime probes at source commit `0d4d785`,
  measured widths and transactions, and controls documented in the action record.
- **Existing source records:** entries 020–022 describe the native inspector and
  prior stabilization baseline; they do not prove this diagnosis or a new fix.
- **Inference/proposal:** platform host resize delivery explains why the same
  animation technique behaves differently. A single destination reflow is the
  implemented response, not proof of a specific framework defect.

## Validation and acceptance criteria

- Start with `make build-mac`; use the project Makefile for subsequent runtime
  checks. Use an already-booted simulator, or obtain permission before booting one.
- Recheck layout proposals and placements: a five-to-three-column toggle must
  produce one destination layout, with no four-column animation target.
- Record motion during a held window/divider drag and after release: content must
  track resizing without delayed animated reflow. Settled screenshots are insufficient.
- Visually compare opening and closing at widths crossing one and several column
  thresholds, with no selection and with a selected entry.
- Exercise rapid reversals, inspector resizing, top/middle/bottom scroll positions,
  and a second window. Check for scroll jumps, layout loops, and misplaced cards.
- Verify keyboard row navigation against the final displayed column count.
- Recheck iPad's direct reflow if any shared code changes. Builds alone do not
  establish visual acceptance; maintainer acceptance remains required.
- Add only focused tests for any new transition-state behavior that cannot be
  adequately protected by existing tests. No speculative tests were added here.

## Amendments

- Updated 2026-10-17: Implementation authorized. First test width-driven animation transactions before introducing destination-width coordination — see [002-width-driven-animation.md](002-width-driven-animation.md).

- Updated 2026-10-17: Maintainer rejected intermediate retargeting and live-resize regression; removed the candidate and restored the direct endpoint requirement — see [003-reject-width-retargeting.md](003-reject-width-retargeting.md).

- Updated 2026-10-17: Implemented direct endpoint reflow after native geometry investigation; maintainer accepted opening/closing and both resize paths — see [004-endpoint-transition.md](004-endpoint-transition.md).
