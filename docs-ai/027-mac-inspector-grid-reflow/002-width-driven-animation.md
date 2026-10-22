# 027.002 — Animate native width-driven grid updates

## Context

The maintainer authorized trying a Mac fix after the recorded diagnosis. This
amendment was started before implementation. The first experiment targets the
missing animation on native width updates; the earlier single-destination-layout
proposal remains a fallback if continuous retargeting does not remove the visible
discontinuities.

## Change

Experiment (subsequently removed in 003): read the viewport width with a local `GeometryReader` in
`MyAnimeList/Sources/Mac/MacLibraryGrid.swift`, and key the grid's smooth animation
to that width. Keep the adaptive grid, card geometry groups, native inspector,
selection model, and iPad implementation intact. The measurement flows downward
as a value; it does not update ancestor state or impose a measured fixed width.

This still allows intermediate column arrangements internally. Acceptance depends
on whether the card geometry animates continuously through retargeting, rather
than snapping at each boundary. Do not claim the earlier single-reflow criterion
is met by this experiment.

Rejected as the first step: guessed inspector widths, timing-based width locks,
private split-controller access, and unconditional animation of every card update.
They introduce more behavior than directly assigning an animation when viewport
width changes.

## Validation plan

- Build and run the Mac fixture with the existing Makefile.
- Restore temporary diagnostics to verify animations reach resized card placements.
- Compare recorded opening/closing motion, including multiple column thresholds.
- Exercise resizing, rapid reversal, scrolled content, and keyboard navigation.
- Remove diagnostic code and reconcile this amendment with the actual result.

## Results and validation

- `make build-mac` and `make run-mac` succeeded with the 100-entry fixture.
- Temporary card probes recorded seven closing updates and eight opening updates
  in one focused pair, all with a smooth spring (response 0.3, damping fraction 1).
  None had the previous `animation=nil`. Counts vary with native resize delivery.
- Recorded uninstrumented opening/closing across 5/4/3-column layouts. Frame
  inspection showed cards interpolating through the changes rather than abruptly
  swapping row arrangements. This is continuous retargeting, not iPad's single
  destination layout; it does not prove all vertical jitter is eliminated.
- Exercised selected and unselected states, a scrolled viewport, narrower window
  sizes, and a live inspector-divider drag. The grid settled without a layout loop
  or crash. Selection survived toggles; keyboard Down moved three entries with
  three columns and five entries with five columns.
- A burst of four shortcut toggles settled without corrupted cards, but ended
  closed after starting open. Native shortcut/transition interruption behavior
  was not isolated; exact rapid-toggle parity is not claimed as passing.
- Removed the temporary probes and rebuilt/relaunched the production candidate.
  No test-only helpers or diagnostic switches are part of the change. Final
  opening/closing retained the selected entry and reached both inspector states.
- `git diff --check` and documentation link checks passed. Swift format lint
  reported one existing documentation-comment summary warning at line 14, outside
  the edited body. The final build reported the existing multiple-Mac-destinations
  warning and completed successfully.
- No new unit tests: this is local view animation wiring, whose key acceptance
  boundary is runtime motion. No shared/iPad source changed.

## Current state

**Rejected and removed after maintainer review.** The animation still hesitated
at intermediate layouts and broke live window resizing, with reflow deferred
until mouse release. These findings supersede the limited settled-state checks
above. See [003](003-reject-width-retargeting.md). The direct endpoint requirement
must not be weakened to continuous retargeting.

## Refs

- `MyAnimeList/Sources/Mac/MacLibraryGrid.swift`
- [Baseline runtime diagnosis](001-action.md)

Recordings and raw traces are local inspection artifacts, not durable repository
inputs. The observations above are the retained evidence.
