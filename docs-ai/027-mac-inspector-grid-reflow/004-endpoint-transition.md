# 027.004 — Single destination transition

## Context and plan

The maintainer authorized continuing after the width-retargeting candidate was
removed. Before changing production behavior, inspect public AppKit view/layer
geometry during the native inspector transition to determine whether its final
width is already available independently of intermediate SwiftUI proposals.
Temporary probes must only read geometry, not modify ancestor constraints.

Select the smallest mechanism that supplies one endpoint layout per toggle,
retains lazy rendering, and leaves live window/divider resizing immediate. Do not
substitute smoothing intermediate layouts, debounce timers, or a guessed inspector
width for that contract. Validate first open, close, reversal, restored/resized
inspector width, and motion during a held drag. Record rejected experiments and
remove all temporary probes before final delivery.

## Implementation and evidence

Read-only native probes found the library hosting view stays full width while
its trailing safe area changes through intermediate values. The inspector's own
content remained 400 points wide throughout opening and closing, even while its
native wrapper collapsed to zero. No useful layer endpoint animation was found
on the grid's ancestor chain. These are observations on macOS 27.0.1, not a claim
about private framework implementation across OS releases.

The implementation keeps the native inspector and `LazyVGrid`:

- `MyAnimeList/Sources/Mac/MacLibraryInspectorLayout.swift` stores the measured,
  positive inspector content width per library window. The inspector writes it;
  only the grid consumes it. Inspector and ancestor constraints never depend on
  this measurement, avoiding a sizing feedback loop.
- `MyAnimeList/Sources/Mac/MacLibraryView.swift` supplies that state to the grid
  and inspector through the environment.
- `MyAnimeList/Sources/Mac/MacLibraryInspector.swift` measures its content width,
  including changes from dragging the native divider.
- `MyAnimeList/Sources/Mac/MacLibraryGrid.swift` uses an outer geometry reader for
  the native visible viewport and an inner reader that ignores only the trailing
  container safe area. The inner full width minus the measured inspector width
  supplies the destination grid width immediately. The outer width controls the
  visible scroll viewport as the native inspector moves.

Only effective inspector presentation changes install the 0.3-second smooth card
transaction. The sizing proposals themselves do not animate. Width changes from
window/divider dragging therefore do not enqueue a reflow animation. Existing
sort/filter animations remain scoped separately. When the inspector measurement
first becomes available, the effective presentation Boolean changes; there is no
hard-coded width, debounce, timer, or explicit animation-completion state machine.

An early prototype animated the fixed scroll width itself; traces still showed
intermediate grid proposals, so that approach was discarded. Reading the trailing
safe-area inset from the reader that ignores it returned zero; the final design
uses the outer reader for the visible viewport instead. Separating the viewport
also avoids immediately cropping moving cards to the final narrow scroll frame.

## Validation and acceptance

- Instrumented Mac fixture runs built and launched with `make run-mac`.
- The final two-reader prototype recorded one grid width change on opening,
  852 → 452 points (5 → 3 columns), and one on closing, 452 → 852 (3 → 5).
  The card transaction carried the smooth animation. Consecutive equal widths
  and lazy-grid height changes were excluded from these counts.
- A local recording captured opening and closing. It was inspected but is not
  retained as repository evidence. Attempted automated window drags in that clip
  did not produce a resize, so it is not evidence for live resizing.
- The maintainer reported that the result looked good and explicitly confirmed
  both window-edge and inspector-divider resizing worked correctly. This is
  manual acceptance, separate from build and trace evidence.
- Temporary native, card, grid, and window-limit probes were removed. The final
  probe-free build/launch result is recorded in the action record.
- No shared/iPad source changed. No new unit tests were added for this view wiring;
  layout delivery and visual timing were checked at runtime.

## Remaining coverage limits

The current fix was exercised on macOS 27.0.1; the macOS 26 deployment baseline
was not run. Dedicated rapid-reversal, fresh initially-closed-window,
multi-window isolation, keyboard navigation, and scrolled-position matrices were
not completed for the final prototype. Earlier experiments are not evidence that
those combinations passed. The accepted opening/closing and resize paths meet
the reported defect's scope; these limits remain useful regression targets.
